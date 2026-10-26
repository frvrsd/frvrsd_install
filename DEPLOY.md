# Инструкция по развёртыванию

**Docker Compose** — рекомендуемый путь для VPS (свой или чужой сервер).  
Legacy **systemd + venv** — только миграция: [docs/MIGRATION.md](docs/MIGRATION.md).

Образ: `frvrsd/frvrsd_vpn_bot` (публичный Docker Hub). `frvrsd update` и `frvrsd install` сами ставят последний тег `x.y.z` (`dev` и `latest` не берутся).

Vendor при сборке образа (`docker build`): multi-stage Dockerfile компилирует
критичные модули Nuitka (ADR 0007). Оператору ничего дополнительно настраивать
не нужно — тянет готовый образ как раньше.

---

## A. Docker Compose (рекомендуется)

### One-shot на чистом VPS

```bash
curl -fsSL -o install.sh \
  https://raw.githubusercontent.com/frvrsd/frvrsd_install/1.7.0/install.sh
chmod +x install.sh && ./install.sh
```

Либо клон публичного репозитория на нужном теге:

```bash
git clone --branch 1.7.0 --depth 1 https://github.com/frvrsd/frvrsd_install /opt/frvrsd_vpn
cd /opt/frvrsd_vpn
cp .env.example .env && nano .env   # или позже: frvrsd env

chmod +x install.sh
./install.sh setup                  # frvrsd в PATH, config → .frvrsd/

sudo ./install.sh bootstrap         # Docker + UFW (SSH-порт из sshd_config, 80, 443)
# re-login в группу docker, если bootstrap добавил пользователя

frvrsd install --https -y           # wizard .env (если пусто) → последний x.y.z → up → /health
frvrsd health
```

`bootstrap` — **один раз** с sudo. Дальше команды **без sudo** (пользователь в группе `docker`).

`frvrsd init` и `frvrsd self-update` скачивают `install.sh`, `docker-compose.yml`,
`.env.example` и `deploy/Caddyfile` с последнего semver-тега
`frvrsd/frvrsd_install`. Токен GitHub не нужен. Коммит без тега клиентам не отдаётся.

### Обязательные поля `.env`

| Поле | Описание |
|---|---|
| `BOT_TOKEN` | @BotFather |
| `REMNAWAVE_BASE_URL`, `REMNAWAVE_TOKEN` | Панель |
| `COOKIES` | JSON только если панель ставили скриптом egames; иначе `{}` |
| `MINI_APP_URL` | `https://your-domain.com` |
| `PAYMENT_CHAT_ID` | Telegram ID **owner** (несменяемый; ЛК + fallback алертов). Остальных админов — Mini App → Настройки → Админы |
| `FRVRSD_IMAGE` | Записывается CLI: последний тег `x.y.z` с Docker Hub |

`MINI_APP_DOMAIN` можно не задавать — `install.sh` возьмёт host из `MINI_APP_URL`.

### Post-install checklist

1. `frvrsd health` → Mini App отвечает на `http://127.0.0.1:8080/health`
2. BotFather → Menu Button → URL из `MINI_APP_URL`
3. Platega (если онлайн-оплата): callback  
   `{MINI_APP_URL}/api/payments/callback/platega`
4. Открыть Mini App под аккаунтом `PAYMENT_CHAT_ID` (owner) → Админка → Настройки:
   - **Админы** — роли admin / support / readonly (owner только из `.env`)
   - платежи, LTE, канал, брендинг; secrets/лицензия — только owner
5. DNS `MINI_APP_DOMAIN` → IP этого сервера (если HTTPS-профиль Caddy)
6. Алерты панели/нод (опционально): в `.env` панели Remnawave  
   `WEBHOOK_ENABLED=true`  
   `WEBHOOK_URL={MINI_APP_URL}/api/webhooks/remnawave`  
   `WEBHOOK_SECRET_HEADER=` секрет из Настройки → Алерты → Подключение панели  
   Тумблеры событий — там же. Исходящие webhooks оператора (оплата наружу) — другая задача.

### CLI

```bash
frvrsd              # меню RU/EN
frvrsd update       # последний тег x.y.z с Docker Hub
frvrsd status
frvrsd logs miniapp
frvrsd restart
```

Конфиг: `{deploy}/.frvrsd/config` · Docker auth: `{deploy}/.docker/`  
Данные: Postgres volume `pgdata` + `./data` для support-media.

### Бэкап / перенос Postgres

```bash
# Консистентный dump (CLI останавливает bot+miniapp на время снимка)
frvrsd backup --tar
# → data/backup-*/frvrsd.dump  и опц. frvrsd-backup-*.tar.gz

# Восстановление на том же или другом хосте (Postgres должен быть up)
frvrsd import data/backup-…/frvrsd.dump
# или: frvrsd import /tmp/frvrsd-backup-….tar.gz

curl -fsS http://127.0.0.1:8080/ready
```

Схема на deploy: `docker compose run --rm --profile migrate migrate`  
(`frvrsd install` / `update` / `start` делают это сами).

**Rollback:**
1. `docker compose stop bot miniapp`
2. Предыдущий image tag / git revision
3. `frvrsd import` из последнего `.dump` (или S3 `pg_restore`)
4. `docker compose up -d` → `curl /ready`

S3: объекты `*.dump` (`pg_dump -Fc`); restore в чистый Postgres.  
Межсерверный перенос: `frvrsd backup --tar` на старом и `frvrsd import` на новом.

> **Postgres 18:** volume в compose — `pgdata:/var/lib/postgresql`  
> (не `.../data`; иначе контейнер в restart loop).

### Первый cutover со старого `data/frvrsd.db` (один раз)

Пока на проде ещё файл БД, а не Postgres volume — offline импорт.
Импорт гонять **в сети compose** (hostname `postgres`), не с хоста через `.venv`
и `DATABASE_URL` с `@postgres`.

```bash
docker compose stop bot miniapp
cp -a data/frvrsd.db "data/frvrsd.db.bak-$(date +%F)"
docker compose up -d postgres
docker compose --profile migrate run --rm migrate
docker compose --profile migrate run --rm \
  -v "$(pwd)/data:/data" \
  migrate python -m scripts.migrate_sqlite_to_postgres \
  --sqlite /data/frvrsd.db --verify
docker compose up -d
curl -fsS http://127.0.0.1:8080/ready
# затем: frvrsd backup --tar  и только после этого удалять *.db*
```

Дальше бэкапы только через `frvrsd backup` / S3 `.dump`. Подробности — ADR 0008.

### Troubleshooting

| Симптом | Что сделать |
|---|---|
| `Pull failed` | Сеть до Docker Hub; `frvrsd logs` не про логин — образ публичный |
| Health timeout | `frvrsd logs miniapp`; проверить `.env` (`BOT_TOKEN`, Remnawave); `frvrsd status` |
| HTTPS не поднимается | DNS A/AAAA → VPS; порты 80/443 в UFW; `frvrsd logs caddy`; `MINI_APP_DOMAIN` |
| Caddy не в `ps` | `frvrsd` → Enable HTTPS, или `frvrsd install --https` / restart с HTTPS |
| Нет доступа в админку | `PAYMENT_CHAT_ID` = ваш числовой Telegram ID (owner) или запись в Настройки → Админы |
| Permission denied на Docker | пользователь в группе `docker`, затем re-login / `newgrp docker` |

### Обновление

```bash
# Берёт последний тег x.y.z с Docker Hub (не dev и не latest) и пересоздаёт сервисы.
frvrsd update
```

Образ собирает maintainer в закрытом репозитории приложения (`Dockerfile`,
`scripts/docker-build.sh`). Оператор тянет готовый `frvrsd/frvrsd_vpn_bot`.

---

## B. Systemd + venv (legacy)

Старый деплой из репозитория приложения. Новый сервер ставьте этим пакетом, не клоном приложения.

---

## Полезные команды

```bash
frvrsd logs miniapp
frvrsd restart
sudo frvrsd bootstrap   # только Docker/UFW
```
