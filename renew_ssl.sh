#!/bin/bash
#
# renew_ssl.sh — автоматическое обновление Wildcard SSL-сертификата Let's Encrypt
# на NAS QNAP (QTS) с ручной сборкой формата stunnel.
#
# Запуск: от root (например, через планировщик Cron в /etc/config/crontab).
# acme.sh вызывается от имени обычного администратора через sudo -u.
#
# Перед первым использованием отредактируйте переменные ниже.

set -euo pipefail

# =============================================================================
# Настройки
# =============================================================================

DOMAIN="example.com"
QNAP_ADMIN_USER="admin"

# Путь к тому: ls -la /share/ | grep CACHEDEV
QNAP_DATA_VOLUME="/share/CACHEDEV1_DATA"

# Каталог установки acme.sh (можно отличаться от ~/.acme.sh)
ACME_BASE_DIR="${QNAP_DATA_VOLUME}/homes/${QNAP_ADMIN_USER}/acme"
ACME_SH="${ACME_BASE_DIR}/acme.sh"

# DNS API: https://github.com/acmesh-official/acme.sh/wiki/dnsapi
DNS_API="dns_your_provider"

# Пауза после TXT, пока запись не разойдётся по NS провайдера (Webnames: 120–180)
DNS_SLEEP=120

# Папка сертификата acme.sh (суффикс _ecc)
ACME_CERT_GLOB="${ACME_BASE_DIR}/*.${DOMAIN}_ecc"

# Целевые файлы QNAP stunnel
STUNNEL_DIR="/etc/stunnel"
STUNNEL_PEM="${STUNNEL_DIR}/stunnel.pem"
STUNNEL_UCA="${STUNNEL_DIR}/uca.pem"

BACKUP_DIR="/etc/stunnel/backup"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/renew_ssl.log"

QNAP_SERVICES=(
    "/etc/init.d/Qthttpd.sh"
    "/etc/init.d/thttpd.sh"
    "/etc/init.d/stunnel.sh"
)

# Разрешается при старте скрипта
ACME_CERT_DIR=""

# =============================================================================
# FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "${LOG_FILE}"
}

die() {
    log "ERROR" "$@"
    exit 1
}

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "Скрипт должен запускаться от root (через Cron QNAP)."
    fi
}

resolve_cert_dir() {
    local dir_check
    dir_check=$(ls -d ${ACME_CERT_GLOB} 2>/dev/null || true)
    [[ -n "${dir_check}" ]] || return 1
    # Берём первый каталог, если совпадений несколько
    ACME_CERT_DIR=$(echo "${dir_check}" | head -n 1)
}

check_prerequisites() {
    require_root

    [[ -x "${ACME_SH}" ]] || die "acme.sh не найден: ${ACME_SH}"
    id "${QNAP_ADMIN_USER}" &>/dev/null || die "Пользователь не существует: ${QNAP_ADMIN_USER}"

    [[ "${DNS_API}" != "dns_your_provider" ]] || die \
        "Укажите DNS_API в настройках скрипта (например, dns_webnames)"

    resolve_cert_dir || die \
        "Каталог сертификата не найден (${ACME_CERT_GLOB}). " \
        "Сначала выпустите сертификат вручную (см. README.md)."

    for svc in "${QNAP_SERVICES[@]}"; do
        [[ -x "${svc}" ]] || die "Служба не найдена: ${svc}"
    done
}

run_acme_renew() {
    local acme_rc=0

    log "INFO" "Запуск проверки/обновления сертификата для *.${DOMAIN} (DNS API: ${DNS_API})..."

    # --renew без --force. Коды acme.sh: 0 — обновлено, 2 — ещё рано (skip).
    # Абсолютный --home/--config-home: sudo -u подменяет HOME, относительный "." легко теряется.
    cd "${ACME_BASE_DIR}"
    sudo -u "${QNAP_ADMIN_USER}" DNSAPI_PATH="./dnsapi" "${ACME_SH}" --renew \
        --ecc \
        --dns "${DNS_API}" \
        -d "*.${DOMAIN}" \
        --server letsencrypt \
        --home "${ACME_BASE_DIR}" \
        --config-home "${ACME_BASE_DIR}" \
        --dnssleep "${DNS_SLEEP}" \
        >> "${LOG_FILE}" 2>&1 || acme_rc=$?

    case "${acme_rc}" in
        0)
            log "INFO" "Проверка acme.sh завершена."
            ;;
        2)
            log "INFO" "Сертификат ещё не требует обновления. Службы не перезапускались."
            exit 0
            ;;
        *)
            die "acme.sh завершился с кодом ${acme_rc}. Сертификат не установлен, службы не перезапускались."
            ;;
    esac
}

backup_stunnel_files() {
    mkdir -p "${BACKUP_DIR}"
    for f in "${STUNNEL_PEM}" "${STUNNEL_UCA}"; do
        if [[ -f "${f}" ]]; then
            cp -a "${f}" "${BACKUP_DIR}/$(basename "${f}").${TIMESTAMP}.bak"
            log "INFO" "Резервная копия: ${f}"
        fi
    done
}

find_cert_key() {
    local f
    for f in *."${DOMAIN}.key" *.key; do
        [[ -f "${f}" ]] || continue
        echo "${f}"
        return 0
    done
    return 1
}

find_cert_cer() {
    local f
    for f in *."${DOMAIN}.cer" *.cer; do
        [[ -f "${f}" ]] || continue
        case "${f}" in
            ca.cer|fullchain.cer) continue ;;
        esac
        echo "${f}"
        return 0
    done
    return 1
}

deploy_to_qnap() {
    local key_file
    local cert_file
    local ca_file
    local tmp_pem
    local tmp_uca

    log "INFO" "Установка сертификата в stunnel из ${ACME_CERT_DIR}..."

    cd "${ACME_CERT_DIR}"

    key_file=$(find_cert_key) || die "Приватный ключ не найден в ${ACME_CERT_DIR}"
    cert_file=$(find_cert_cer) || die "Сертификат не найден в ${ACME_CERT_DIR}"
    ca_file="ca.cer"

    tmp_pem="$(mktemp)"
    tmp_uca="$(mktemp)"

    # stunnel.pem = ключ + сертификат; uca.pem = цепочка CA
    cat "${key_file}" "${cert_file}" > "${tmp_pem}"

    # uca.pem
    [[ -f "${ca_file}" ]] || die "Не найден ca.cer в ${ACME_CERT_DIR}"
    cp "${ca_file}" "${tmp_uca}"

    chmod 600 "${tmp_pem}"
    chmod 644 "${tmp_uca}"

    backup_stunnel_files

    cp "${tmp_pem}" "${STUNNEL_PEM}"
    cp "${tmp_uca}" "${STUNNEL_UCA}"
    chmod 600 "${STUNNEL_PEM}"
    chmod 644 "${STUNNEL_UCA}"

    rm -f "${tmp_pem}" "${tmp_uca}"

    log "INFO" "Сертификаты установлены: ${STUNNEL_PEM}, ${STUNNEL_UCA}"
}

restart_qnap_services() {
    local svc
    for svc in "${QNAP_SERVICES[@]}"; do
        log "INFO" "Перезапуск: ${svc}"
        "${svc}" restart >> "${LOG_FILE}" 2>&1 || die "Не удалось перезапустить: ${svc}"
    done
    log "INFO" "Все веб-службы QNAP перезапущены."
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log "INFO" "========== Начало процесса SSL =========="
    check_prerequisites
    run_acme_renew
    deploy_to_qnap
    restart_qnap_services
    log "INFO" "========== Процесс SSL успешно завершён =========="
}

main "$@"
