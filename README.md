# Wildcard SSL Let's Encrypt для QNAP

Автоматическое обновление Wildcard-сертификата на NAS QNAP через [acme.sh](https://github.com/acmesh-official/acme.sh) и DNS-01.  
Проверено на **QTS 5.2.9.3499**.

Встроенный мастер QTS Wildcard не выпускает — нужен DNS API ([список провайдеров](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)).

---

## Быстрая установка

Замените `admin` на своего пользователя QNAP, `example.com` — на свой домен.

### 1. Установите acme.sh

SSH под **администратором** (не root). Меню Console Management — `Q`, затем `Y`.

```bash
mkdir -p /share/CACHEDEV1_DATA/homes/admin/acme
cd /share/CACHEDEV1_DATA/homes/admin/acme
curl -L https://github.com/acmesh-official/acme.sh/tarball/master | tar xz --strip-components=1
chmod +x acme.sh
```

### 2. Выпустите сертификат (один раз)

Токены API — **только здесь**, acme.sh сохранит их сам. В скрипт токены не пишутся.

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme

# переменные по документации вашего DNS-провайдера
export YOUR_PROVIDER_VAR="..."

DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_your_provider \
  --ecc \
  -d '*.example.com' \
  -d example.com \
  --server letsencrypt \
  --home /share/CACHEDEV1_DATA/homes/admin/acme \
  --config-home /share/CACHEDEV1_DATA/homes/admin/acme \
  --dnssleep 120
```

### 3. Скачайте и настройте скрипт

```bash
cd /share/CACHEDEV1_DATA/homes/admin/acme

curl -fsSL -o renew_ssl.sh \
  "https://raw.githubusercontent.com/SlayerSS/qnap-letsencrypt-wildcard-dns/refs/heads/main/renew_ssl.sh"

chmod +x renew_ssl.sh
vi renew_ssl.sh
```

Укажите в начале файла:

| Переменная | Пример |
|------------|--------|
| `DOMAIN` | `example.com` |
| `QNAP_ADMIN_USER` | `admin` |
| `QNAP_DATA_VOLUME` | `/share/CACHEDEV1_DATA` |
| `DNS_API` | `dns_webnames` |
| `DNS_SLEEP` | `120` (увеличьте до `180`, если LE не видит TXT) |

`DNS_API` — **код провайдера** (не токен). Заглушка `dns_your_provider` не сработает.

Проверка **от root**:

```bash
sudo -i
/share/CACHEDEV1_DATA/homes/admin/acme/renew_ssl.sh
tail -30 /var/log/renew_ssl.log
```

### 4. Автозапуск (Cron)

Не используйте `crontab -e` — после перезагрузки задача пропадёт.

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

---

## Частые ошибки

| Ошибка | Решение |
|--------|---------|
| `Укажите DNS_API` | Замените `dns_your_provider` на код провайдера |
| `Каталог сертификата не найден` | Сначала шаг 2 (`--issue`) |
| `is not an issued domain` | Вызывайте acme.sh с `--home` и `--config-home` на каталог установки, плюс `--ecc` |
| `No TXT record found at _acme-challenge` | Увеличьте `DNS_SLEEP` (120–180) |
| `acme.sh завершился с кодом 2` / `Skipping. Next renewal time` | Это не ошибка: обновлять ещё рано. В актуальном скрипте код 2 = тихий выход без перезапуска служб |
| `acme.sh завершился с кодом` (не 0 и не 2) | Обновление не удалось; stunnel не трогали — смотрите `/var/log/renew_ssl.log` |
| `It seems that you are using sudo` | Запускайте скрипт от root, не acme.sh напрямую |
| Cron пропал после reboot | Задача в `/etc/config/crontab` |

---

## Сноска: автор тестировал с Webnames.ru

Код API: `dns_webnames`. Ключ — в кабинете: **Управление зоной** → **Настройка Certbot**.  
Плагин Certbot: [certbot-dns-webnames](https://github.com/regtime-ltd/certbot-dns-webnames).

```bash
export WEBNAMES_Token="ВАШ_ТОКЕН"
export WEBNAMES_Username="ВАШ_ЛОГИН"

DNSAPI_PATH=./dnsapi ./acme.sh --issue \
  --dns dns_webnames \
  --ecc \
  -d '*.example.com' -d example.com \
  --server letsencrypt \
  --home /share/CACHEDEV1_DATA/homes/admin/acme \
  --config-home /share/CACHEDEV1_DATA/homes/admin/acme \
  --dnssleep 120
```

---

[Репозиторий](https://github.com/SlayerSS/qnap-letsencrypt-wildcard-dns) · [acme.sh DNS API](https://github.com/acmesh-official/acme.sh/wiki/dnsapi) · [MIT](LICENSE)
