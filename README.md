# Wildcard SSL Let's Encrypt для QNAP

Автоматическое обновление Wildcard-сертификата (`*.example.com`) на NAS QNAP через [acme.sh](https://github.com/acmesh-official/acme.sh) и DNS-01.

Встроенный мастер сертификатов QTS не выпускает Wildcard. Это решение подтверждает домен через DNS API — порты 80/443 открывать не нужно.

Проверено на **QTS 5.2.9.3499**.

---

## Что понадобится

- QNAP с QTS и доступом по SSH
- Домен с DNS API ([список провайдеров acme.sh](https://github.com/acmesh-official/acme.sh/wiki/dnsapi))
- Один раз выпустить сертификат вручную, дальше всё делает `renew_ssl.sh`

---

## 1. Установка acme.sh

Подключитесь по SSH **под администратором** (не root).  
Если открылось меню Console Management — `Q`, затем `Y`.

Узнайте путь к тому с данными:

```bash
ls -la /share/ | grep CACHEDEV
```

Установите acme.sh (замените `admin` на своего пользователя):

```bash
mkdir -p /share/CACHEDEV1_DATA/homes/admin/acme
cd /share/CACHEDEV1_DATA/homes/admin/acme
curl -L https://github.com/acmesh-official/acme.sh/tarball/master | tar xz --strip-components=1
chmod +x acme.sh
```

---

## 2. Первый выпуск сертификата

Важно различать два понятия:

| Что | Куда | Пример |
|-----|------|--------|
| **Код DNS API** | В `renew_ssl.sh` → `DNS_API` | `dns_webnames`, `dns_cloudflare` |
| **Секреты (токен, пароль)** | Только при первом `--issue` вручную | `export WEBNAMES_Token="..."` |

Секреты в скрипт **не прописываются** — acme.sh сохранит их сам после первого выпуска.  
Но **код провайдера** (`DNS_API`) в `renew_ssl.sh` **обязателен** — без него скрипт не запустится.

1. Найдите код вашего DNS API в [wiki acme.sh](https://github.com/acmesh-official/acme.sh/wiki/dnsapi).
2. Экспортируйте переменные с токенами согласно документации провайдера.
3. Выпустите сертификат:

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme

# секреты — только здесь, один раз (по документации провайдера)
export YOUR_PROVIDER_VAR="..."

DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_webnames \
  -d example.com \
  -d '*.example.com' \
  --server letsencrypt \
  --home .
```

Проверка:

```bash
ls -la /share/CACHEDEV1_DATA/homes/admin/acme/*.example.com_ecc/
```

---

## 3. Настройка renew_ssl.sh

Скопируйте скрипт из репозитория на NAS:

```bash
# от root
cp renew_ssl.sh /share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh
chmod +x /share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh
vi /share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh
```

Измените в начале файла (значение `dns_your_provider` — заглушка, замените на свой код):

| Переменная | Пример | Обязательно |
|------------|--------|-------------|
| `DOMAIN` | `example.com` | да |
| `QNAP_ADMIN_USER` | `admin` | да |
| `QNAP_DATA_VOLUME` | `/share/CACHEDEV1_DATA` | да |
| `DNS_API` | `dns_webnames` | да — код провайдера, не токен |

Токены и пароли API в скрипт **не вносятся** — acme.sh подтянет их из сохранённой конфигурации.

Проверка:

```bash
/share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh
tail -30 /var/log/renew_ssl.log
```

---

## 4. Автозапуск по расписанию

На QNAP не используйте `crontab -e` — после перезагрузки задача пропадёт.

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
```

Скрипт обновит сертификат автоматически, когда до истечения останется около 30 дней.

---

## Если что-то пошло не так

**«It seems that you are using sudo...»** — acme.sh нужно запускать от обычного пользователя. Скрипт делает это через `sudo -u admin`.

**«Каталог сертификата не найден»** — сначала выполните первый `--issue` (шаг 2).

**Cron не работает после перезагрузки** — задача должна быть в `/etc/config/crontab`, не в `crontab -e`.

**Старый сертификат в браузере** — проверьте лог и перезапустите службы:

```bash
cat /var/log/renew_ssl.log
/etc/init.d/Qthttpd.sh restart
/etc/init.d/thttpd.sh restart
/etc/init.d/stunnel.sh restart
```

---

## Ссылки

- [acme.sh](https://github.com/acmesh-official/acme.sh)
- [DNS API провайдеры](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)

Лицензия: [MIT](LICENSE)

---

## Сноска: тестирование с Webnames.ru

> Автор проверял решение с DNS-провайдером [Webnames.ru](https://www.webnames.ru).  
> Для других регистраторов шаги 1–4 выше остаются теми же — меняются только код DNS API и переменные окружения.

API-ключ Webnames: **Мои домены** → **Управление доменом** → **Управление зоной** → **Настройка Certbot**.  
Плагин для Certbot: [certbot-dns-webnames](https://github.com/regtime-ltd/certbot-dns-webnames).

Подготовка по инструкции Webnames:

```bash
sudo apt-get install certbot
mkdir letsencrypt_certbot
cd letsencrypt_certbot
git clone https://github.com/certbot/certbot
git clone https://github.com/regtime-ltd/certbot-dns-webnames

curl -k "https://www.webnames.ru/scripts/json_domain_zone_manager.pl?action=get_config_certbot&domain=example.com&apikey=ВАШ_API_KEY" \
  -o certbot-dns-webnames/config.sh
```

Выпуск через acme.sh (в `renew_ssl.sh` указать `DNS_API="dns_webnames"`):

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme
export WEBNAMES_Token="ВАШ_ТОКЕН"
export WEBNAMES_Username="ВАШ_ЛОГИН"

DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_webnames \
  -d example.com \
  -d '*.example.com' \
  --server letsencrypt \
  --home .
```
