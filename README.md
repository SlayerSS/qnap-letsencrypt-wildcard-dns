# SSL Wildcard Let's Encrypt для QNAP (QTS)

Автоматизация выпуска и обновления **Wildcard SSL-сертификатов Let's Encrypt** на NAS QNAP с ОС QTS через [acme.sh](https://github.com/acmesh-official/acme.sh) и DNS-01 challenge.

Скрипт `renew_ssl.sh` рассчитан на запуск от **root** через планировщик Cron, но сам **acme.sh** выполняется от имени обычного администратора — это критично для корректной работы на QNAP.

---

## Содержание

- [Архитектура и особенности QNAP](#архитектура-и-особенности-qnap)
- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Первичный выпуск сертификата](#первичный-выпуск-сертификата)
- [Настройка скрипта](#настройка-скрипта)
- [Автоматизация через Cron](#автоматизация-через-cron)
- [Структура файлов сертификата](#структура-файлов-сертификата)
- [Устранение неполадок](#устранение-неполадок)
- [Безопасность](#безопасность)

---

## Архитектура и особенности QNAP

При проектировании решения учтены нюансы QTS, которые неочевидны из документации acme.sh:

| # | Проблема | Решение в этом репозитории |
|---|----------|----------------------------|
| 1 | **acme.sh и sudo** — при запуске от root acme.sh выдаёт ошибку *«It seems that you are using sudo...»*, т.к. конфиг и API-токены лежат в домашней папке обычного пользователя | Cron запускает скрипт от root, но внутри используется `sudo -u <администратор>` |
| 2 | **Хук `--deploy-hook qnap`** часто не работает: нет файлов хука в локальной установке, curl на QNAP может блокировать загрузку | Ручная сборка `stunnel.pem` и `uca.pem` без deploy-hook |
| 3 | **Формат QTS** — веб-стек thttpd / Qthttpd / stunnel ожидает файлы в `/etc/stunnel/` | Ключ + сертификат → `stunnel.pem`, цепочка CA → `uca.pem`, затем перезапуск трёх служб |
| 4 | **Cron QNAP** — `crontab -e` сбрасывается после перезагрузки | Редактирование `/etc/config/crontab` + `crontab /etc/config/crontab` |
| 5 | **DNS API** — ключи не должны храниться в публичном репозитории | Однократная ручная настройка acme.sh; скрипт использует сохранённые credentials |
| 6 | **Пути QNAP** — `/share/homes/` часто является симлинком на `CACHEDEV*_DATA` | Явное указание `QNAP_DATA_VOLUME` и каталога `acme` |
| 7 | **Rate limit Let's Encrypt** — флаг `--force` при частом Cron вызывает бан | Используется `--issue` без `--force`; acme.sh обновляет только при необходимости |

---

## Требования

| Компонент | Описание |
|-----------|----------|
| Устройство | NAS QNAP с QTS |
| Доступ | SSH с правами администратора и root |
| DNS | Домен с возможностью управления DNS-записями через API |
| DNS-провайдер | Поддерживаемый acme.sh (см. [список DNS API](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)) |
| Инструмент | [acme.sh](https://github.com/acmesh-official/acme.sh), установленный **под обычным пользователем** (не root) |

---

## Быстрый старт

```text
1. Определить физический путь тома (CACHEDEV1_DATA и т.п.)
2. Установить acme.sh в каталог пользователя (например, ~/acme)
3. Один раз выпустить Wildcard ECC-сертификат вручную (сохранить DNS API-ключи)
4. Скопировать renew_ssl.sh на NAS, настроить переменные
5. Проверить ручной запуск от root
6. Добавить задачу в /etc/config/crontab
```

---

## Первичный выпуск сертификата

> **Важно:** все команды acme.sh ниже выполняйте **от имени обычного администратора** (например, `admin`), **не от root**.

### 1. Определение физического пути тома

На QNAP путь `/share/homes/` часто указывает на симлинк вроде `/share/CACHEDEV1_DATA`. Узнайте актуальный том:

```bash
ls -la /share/ | grep CACHEDEV
# или
readlink -f /share/homes/admin
```

Значение понадобится для переменной `QNAP_DATA_VOLUME` в скрипте.

### 2. Установка acme.sh

Подключитесь по SSH под пользователем-администратором (например, `admin`):

```bash
# Каталог установки — может отличаться от стандартного ~/.acme.sh
mkdir -p ~/acme
cd ~/acme
curl https://get.acme.sh | sh -s email=your@email.example --install-dir . --home .
```

### 3. Сохранение учётных данных DNS-провайдера

Замените `dns_your_provider` на код вашего провайдера из [wiki acme.sh](https://github.com/acmesh-official/acme.sh/wiki/dnsapi).

**Пример для Cloudflare** (`dns_cloudflare`):

```bash
cd ~/acme
export CF_Token="ваш_api_токен"
export CF_Account_ID="ваш_account_id"   # если требуется провайдером

# Сохранить credentials в acme.sh (один раз):
DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_cloudflare \
  -d example.com \
  -d '*.example.com' \
  --server letsencrypt \
  --home .
```

**Пример для абстрактного провайдера** — подставьте переменные окружения согласно документации acme.sh для `dns_your_provider`:

```bash
cd ~/acme
export YOUR_PROVIDER_API_KEY="..."
export YOUR_PROVIDER_API_SECRET="..."   # если нужно

DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_your_provider \
  -d example.com \
  -d '*.example.com' \
  --server letsencrypt \
  --home .
```

После успешного выпуска acme.sh **сохранит API-ключи** в `account.conf` и профиле DNS API. Повторно указывать их в скрипте или в Cron **не нужно**.

### 4. Проверка выпущенных файлов

```bash
ls -la /share/CACHEDEV1_DATA/homes/admin/acme/*.example.com_ecc/
```

> acme.sh создаёт каталог с суффиксом `_ecc` для ECC-сертификатов. Имя начинается с `*.` (буквальная звёздочка).

Ожидаемые файлы:

| Файл | Назначение |
|------|------------|
| `*.example.com.key` | Приватный ключ |
| `*.example.com.cer` | Сертификат домена |
| `ca.cer` | Промежуточный CA |
| `fullchain.cer` | Полная цепочка |

---

## Настройка скрипта

Скопируйте `renew_ssl.sh` на NAS, например:

```bash
# от root
mkdir -p /share/Public/scripts
# загрузите renew_ssl.sh в /share/Public/scripts/
chmod +x /share/Public/scripts/renew_ssl.sh
```

Отредактируйте секцию **CONFIGURATION** в начале файла:

| Переменная | Описание | Пример |
|------------|----------|--------|
| `DOMAIN` | Базовый домен | `example.com` |
| `QNAP_ADMIN_USER` | Пользователь-владелец acme.sh | `admin` |
| `QNAP_DATA_VOLUME` | Физический путь тома с данными | `/share/CACHEDEV1_DATA` |
| `ACME_BASE_DIR` | Каталог установки acme.sh | `.../homes/admin/acme` |
| `DNS_API` | Код DNS API acme.sh | `dns_cloudflare` |
| `LOG_FILE` | Путь к логу | `/var/log/renew_ssl.log` |

### Логика обновления

Скрипт вызывает `acme.sh --issue` (не `--renew --force`):

- acme.sh **сам определяет**, нужно ли обновление (~за 30 дней до истечения);
- при ежедневном Cron **не срабатывает rate limit** Let's Encrypt;
- если обновление не требуется, acme.sh завершится с ненулевым кодом — скрипт продолжит работу (`|| true`) и всё равно применит актуальные файлы к stunnel.

### Тестовый запуск

```bash
# от root
/share/Public/scripts/renew_ssl.sh
```

Проверьте лог:

```bash
tail -f /var/log/renew_ssl.log
```

---

## Автоматизация через Cron

> **Не используйте** `crontab -e` на QNAP — изменения **пропадут после перезагрузки**.

### Правильный способ

1. Отредактируйте системный файл:

```bash
vi /etc/config/crontab
```

2. Добавьте строку (пример: проверка каждый день в 03:15):

```cron
15 3 * * * /share/Public/scripts/renew_ssl.sh >> /var/log/renew_ssl.log 2>&1
```

3. Примените и перезапустите планировщик:

```bash
crontab /etc/config/crontab
/etc/init.d/crond.sh restart
```

4. Убедитесь, что задача загружена:

```bash
crontab -l
```

### Рекомендуемое расписание

| Расписание | Cron-выражение | Комментарий |
|------------|----------------|-------------|
| Ежедневно в 03:15 | `15 3 * * *` | acme.sh обновит сертификат только при необходимости (~за 30 дней до истечения) |
| Дважды в неделю | `15 3 * * 1,4` | Альтернатива при ограничениях DNS API |

---

## Структура файлов сертификата

QNAP QTS (stunnel) ожидает два файла в `/etc/stunnel/`:

```text
/etc/stunnel/
├── stunnel.pem    ← приватный ключ + сертификат домена
├── uca.pem        ← промежуточная цепочка CA
└── backup/        ← резервные копии (создаёт скрипт)
```

### Что делает скрипт при деплое

```bash
# stunnel.pem
cat domain.key domain.cer > /etc/stunnel/stunnel.pem

# uca.pem
cp ca.cer /etc/stunnel/uca.pem
```

### Перезапуск служб (строго в этом порядке)

```bash
/etc/init.d/Qthttpd.sh restart
/etc/init.d/thttpd.sh restart
/etc/init.d/stunnel.sh restart
```

Скрипт выполняет это автоматически после успешного обновления.

---

## Устранение неполадок

### «It seems that you are using sudo...»

**Причина:** acme.sh запущен от root или через `sudo` без `-u`.

**Решение:** убедитесь, что в скрипте используется:

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme
sudo -u admin DNSAPI_PATH=./dnsapi ./acme.sh --issue --dns dns_your_provider ...
```

### «Каталог сертификата acme.sh не найден»

**Причина:** сертификат ещё не выпускался вручную, неверный `QNAP_DATA_VOLUME` или путь к `acme`.

**Решение:** выполните первичный `--issue` (см. раздел выше) и проверьте путь:

```bash
ls -d /share/CACHEDEV1_DATA/homes/admin/acme/*.example.com_ecc
```

### Rate limit / слишком частые запросы Let's Encrypt

**Причина:** в Cron или вручную используется `--force` при каждом запуске.

**Решение:** используйте `--issue` без `--force`, как в `renew_ssl.sh`. Принудительное обновление (`--force`) — только при отладке.

### Cron не срабатывает после перезагрузки

**Причина:** задача добавлена через `crontab -e`, а не в `/etc/config/crontab`.

**Решение:** перенесите задачу в `/etc/config/crontab` и выполните:

```bash
crontab /etc/config/crontab && /etc/init.d/crond.sh restart
```

### Веб-интерфейс показывает старый сертификат

1. Проверьте даты файлов: `ls -la /etc/stunnel/`
2. Просмотрите лог: `cat /var/log/renew_ssl.log`
3. Перезапустите службы вручную (см. выше)
4. Очистите кэш браузера или проверьте через `openssl s_client`

### Ошибки DNS API при renew

**Причина:** истёк или отозван API-токен, изменились права у DNS-провайдера.

**Решение:** повторите однократную настройку credentials от пользователя `admin`:

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme
sudo -u admin DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_your_provider \
  -d example.com -d '*.example.com' \
  --server letsencrypt --home . --force
```

---

## Безопасность

| Практика | Статус |
|----------|--------|
| API-ключи в скрипте / GitHub | **Запрещено** — используйте однократную настройку acme.sh |
| Права `stunnel.pem` | `600` (только root) |
| Права `uca.pem` | `644` |
| Резервные копии | `/etc/stunnel/backup/` с меткой времени |
| Запуск Cron | от root; acme.sh — только через `sudo -u admin` |
| Логи | `/var/log/renew_ssl.log` — не содержат секретов |

---

## Лицензия

MIT — используйте и адаптируйте свободно. При публикации форков сохраняйте указание на источник.

---

## Полезные ссылки

- [acme.sh — официальный репозиторий](https://github.com/acmesh-official/acme.sh)
- [acme.sh — DNS API провайдеры](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)
- [Let's Encrypt — документация](https://letsencrypt.org/docs/)
