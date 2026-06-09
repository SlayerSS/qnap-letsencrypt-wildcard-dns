# SSL Wildcard Let's Encrypt для QNAP (QTS)

Автоматизация выпуска и обновления **Wildcard SSL-сертификатов Let's Encrypt** (`*.example.com`) на NAS QNAP с ОС QTS.

Решение использует [acme.sh](https://github.com/acmesh-official/acme.sh) и **DNS-01 challenge** — подтверждение владения доменом через TXT-записи в DNS, без открытия портов 80/443 и без встроенного мастера сертификатов QNAP.

---

## Зачем это нужно

Встроенный клиент QTS (Control Panel → Security → Certificate) **не выпускает Wildcard-сертификаты** и часто требует HTTP-проверку с доступом NAS из интернета. Если вам нужен один сертификат на `*.domain.tld` и `domain.tld` — надёжный путь на QNAP:

1. Выпустить сертификат через **DNS API** вашего регистратора или DNS-хостинга.
2. Установить его в формат **stunnel** (`/etc/stunnel/stunnel.pem`, `/etc/stunnel/uca.pem`).
3. Автоматизировать обновление через **Cron** в `/etc/config/crontab`.

Скрипт `renew_ssl.sh` закрывает пункты 2 и 3. Первичный выпуск (пункт 1) выполняется один раз вручную — API-ключи сохраняются в acme.sh и больше не попадают в код.

---

## Содержание

- [Преимущества](#преимущества)
- [Состав репозитория](#состав-репозитория)
- [Архитектура и особенности QNAP](#архитектура-и-особенности-qnap)
- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Установка acme.sh](#установка-acmesh)
- [Первичный выпуск сертификата](#первичный-выпуск-сертификата)
- [Настройка renew_ssl.sh](#настройка-renew_sslsh)
- [Автоматизация через Cron](#автоматизация-через-cron)
- [Структура файлов сертификата](#структура-файлов-сертификата)
- [Устранение неполадок](#устранение-неполадок)
- [Безопасность](#безопасность)
- [Лицензия](#лицензия)

---

## Преимущества

| Возможность | Описание |
|-------------|----------|
| **Wildcard** | Один сертификат на `*.domain.tld` и `domain.tld` |
| **Без портов** | DNS-01 не требует доступности NAS из интернета |
| **Персистентность** | Cron через `/etc/config/crontab` переживает перезагрузку |
| **Безопасность** | API-ключи не хранятся в скрипте и репозитории |
| **Проверено на QTS** | Учтены пути `CACHEDEV`, суффикс `_ecc`, конфликт sudo |

---

## Состав репозитория

| Файл | Назначение |
|------|------------|
| `renew_ssl.sh` | Скрипт автоматического обновления и установки SSL в stunnel |
| `README.md` | Пошаговая инструкция |
| `LICENSE` | MIT |
| `.gitignore` | Исключает ключи и сертификаты из git |

---

## Архитектура и особенности QNAP

| # | Проблема | Решение |
|---|----------|---------|
| 1 | **acme.sh и sudo** — при запуске от root ошибка *«It seems that you are using sudo...»* | Cron от root, acme.sh через `sudo -u <администратор>` |
| 2 | **Хук `--deploy-hook qnap`** часто не работает | Ручная сборка `stunnel.pem` и `uca.pem` |
| 3 | **Формат QTS** — stunnel ожидает файлы в `/etc/stunnel/` | Ключ + сертификат → `stunnel.pem`, CA → `uca.pem` |
| 4 | **Cron QNAP** — `crontab -e` сбрасывается после reboot | Редактирование `/etc/config/crontab` |
| 5 | **DNS API** — ключи не должны быть в GitHub | Однократная настройка acme.sh |
| 6 | **Пути QNAP** — `/share/homes/` — симлинк на `CACHEDEV*_DATA` | Явное указание `QNAP_DATA_VOLUME` |
| 7 | **Rate limit** — `--force` в Cron вызывает бан LE | `--issue` без `--force` |
| 8 | **Wildcard в путях** — `*` в имени папки ломает `[[ -d ... ]]` | Glob-маска + `ACME_CERT_DIR` |

---

## Требования

| Компонент | Описание |
|-----------|----------|
| Устройство | NAS QNAP с QTS |
| Доступ | SSH (администратор + root) |
| Домен | С управлением DNS через API |
| DNS-провайдер | Поддерживаемый acme.sh ([список](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)) |
| Инструмент | acme.sh, установленный **под обычным пользователем** |

---

## Быстрый старт

```text
1. SSH под администратором → установить acme.sh в ~/acme
2. Один раз выпустить Wildcard-сертификат (--issue + DNS API)
3. Скопировать renew_ssl.sh, настроить CONFIGURATION
4. Запустить от root, проверить лог
5. Добавить задачу в /etc/config/crontab
```

---

## Установка acme.sh

> Все команды acme.sh выполняйте **от имени администратора** (не root).  
> Если открылось меню Console Management — нажмите `Q`, затем `Y` для выхода в Shell.

### 1. Определите физический путь тома

```bash
ls -la /share/ | grep CACHEDEV
readlink -f /share/homes/admin
```

### 2. Скачайте acme.sh

```bash
mkdir -p /share/CACHEDEV1_DATA/homes/admin/acme
cd /share/CACHEDEV1_DATA/homes/admin/acme
curl -L https://github.com/acmesh-official/acme.sh/tarball/master | tar xz --strip-components=1
chmod +x acme.sh
```

---

## Первичный выпуск сертификата

При первом `--issue` acme.sh **сохраняет** API-токены во внутренних конфигах. В `renew_ssl.sh` их прописывать не нужно.

### Пример: Webnames.ru (`dns_webnames`)

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme
export WEBNAMES_Token="ВАШ_ТОКЕН_API"
export WEBNAMES_Username="ВАШ_ЛОГИН"

DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_webnames \
  -d example.com \
  -d '*.example.com' \
  --server letsencrypt \
  --home .
```

### Пример: Cloudflare (`dns_cloudflare`)

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme
export CF_Token="ваш_api_токен"

DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_cloudflare \
  -d example.com \
  -d '*.example.com' \
  --server letsencrypt \
  --home .
```

### Проверка

```bash
ls -la /share/CACHEDEV1_DATA/homes/admin/acme/*.example.com_ecc/
```

| Файл | Назначение |
|------|------------|
| `*.example.com.key` | Приватный ключ |
| `*.example.com.cer` | Сертификат домена |
| `ca.cer` | Промежуточный CA |

---

## Настройка renew_ssl.sh

```bash
# от root
cp renew_ssl.sh /share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh
chmod +x /share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh
vi /share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh
```

| Переменная | Пример |
|------------|--------|
| `DOMAIN` | `example.com` |
| `QNAP_ADMIN_USER` | `admin` |
| `QNAP_DATA_VOLUME` | `/share/CACHEDEV1_DATA` |
| `DNS_API` | `dns_webnames` |

### Тестовый запуск

```bash
/share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh
tail -30 /var/log/renew_ssl.log
```

---

## Автоматизация через Cron

> **Не используйте** `crontab -e` — изменения пропадут после перезагрузки.

```bash
vi /etc/config/crontab
```

Добавьте строку:

```cron
15 3 * * * /share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh >> /var/log/renew_ssl.log 2>&1
```

Примените:

```bash
crontab /etc/config/crontab
/etc/init.d/crond.sh restart
crontab -l
```

---

## Структура файлов сертификата

```text
/etc/stunnel/
├── stunnel.pem    ← ключ + сертификат домена
├── uca.pem        ← цепочка CA
└── backup/        ← резервные копии
```

---

## Устранение неполадок

| Симптом | Решение |
|---------|---------|
| «It seems that you are using sudo...» | acme.sh только через `sudo -u admin` |
| Каталог сертификата не найден | Выполните первичный `--issue`, проверьте `*.domain_ecc` |
| `tmp_pem: unbound variable` | Не используйте `trap RETURN` с `set -u`; см. актуальный `renew_ssl.sh` |
| Rate limit LE | Уберите `--force` из Cron |
| Cron пропал после reboot | Задача в `/etc/config/crontab` |

---

## Безопасность

| Практика | Статус |
|----------|--------|
| API-ключи в скрипте / GitHub | **Запрещено** |
| Права `stunnel.pem` | `600` |
| Запуск Cron | root; acme.sh — `sudo -u admin` |

---

## Лицензия

[MIT](LICENSE)

---

## Полезные ссылки

- [acme.sh](https://github.com/acmesh-official/acme.sh)
- [acme.sh — DNS API](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)
- [Let's Encrypt — Rate Limits](https://letsencrypt.org/docs/rate-limits/)
