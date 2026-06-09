# Wildcard SSL Let's Encrypt для QNAP

Автоматическое обновление Wildcard-сертификата (`*.example.com`) на NAS QNAP через [acme.sh](https://github.com/acmesh-official/acme.sh) и DNS-01.

Встроенный мастер сертификатов QTS не выпускает Wildcard. Это решение подтверждает домен через DNS API — порты 80/443 открывать не нужно.

Проверено на **QTS 5.2.9.3499** с DNS-провайдером [Webnames.ru](https://www.webnames.ru).

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

API-ключи указываются **один раз**. acme.sh сохранит их сам — в скрипт их прописывать не нужно.

**Webnames.ru**

Домен должен быть делегирован на DNS Webnames (`ns1.nameself.com`, `ns2.nameself.com`).

API-ключ берётся в личном кабинете: **Мои домены** → **Управление доменом** → **Управление зоной** → **Настройка Certbot** (внизу страницы). Тот же ключ используется в [официальной инструкции Webnames для Certbot](https://www.webnames.ru/scripts/domain_nss.pl?id=4330) и плагине [certbot-dns-webnames](https://github.com/regtime-ltd/certbot-dns-webnames).

На QNAP вместо Certbot используется **acme.sh** с модулем `dns_webnames` — API-ключ и логин те же:

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme
export WEBNAMES_Token="ваш_apikey_из_кабинета"
export WEBNAMES_Username="ваш_логин_webnames"

DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_webnames \
  -d example.com \
  -d '*.example.com' \
  --server letsencrypt \
  --home .
```

В `renew_ssl.sh` укажите `DNS_API="dns_webnames"`.

**Cloudflare:**

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme
export CF_Token="ваш_токен"

DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_cloudflare \
  -d example.com \
  -d '*.example.com' \
  --server letsencrypt \
  --home .
```

Другой провайдер — замените `dns_webnames` на код из [wiki acme.sh](https://github.com/acmesh-official/acme.sh/wiki/dnsapi).

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

Измените в начале файла:

| Переменная | Пример |
|------------|--------|
| `DOMAIN` | `example.com` |
| `QNAP_ADMIN_USER` | `admin` |
| `QNAP_DATA_VOLUME` | `/share/CACHEDEV1_DATA` |
| `DNS_API` | `dns_webnames` |

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
- [DNS API провайдеры acme.sh](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)
- [Webnames — настройка Certbot (получение API-ключа)](https://www.webnames.ru/scripts/domain_nss.pl?id=4330)
- [certbot-dns-webnames](https://github.com/regtime-ltd/certbot-dns-webnames) — альтернатива через Certbot (не для QNAP)

Лицензия: [MIT](LICENSE)
