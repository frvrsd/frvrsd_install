#!/usr/bin/env bash
# FRVRSD VPN — installer & operator CLI (Docker Compose)
#
# Interactive:  ./install.sh   or   frvrsd
# Commands:      frvrsd install | update | start | stop | restart | status | health | logs | setup
#
# Public repo, no GitHub token. A CLI release is a semver git tag (same number
# as INSTALLER_VERSION). init / self-update download that tag, not a branch tip.
#   curl -fsSL -o install.sh \
#     "https://raw.githubusercontent.com/frvrsd/frvrsd_install/1.7.0/install.sh"
#   chmod +x install.sh && ./install.sh
#
# Pin a tag or branch: FRVRSD_GITHUB_BRANCH=1.7.0
# Creates /opt/frvrsd_vpn, downloads compose/Caddyfile/.env.example, then menu.

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/frvrsd"
CONFIG_FILE=""
CLI_NAME="frvrsd"
DEFAULT_IMAGE="frvrsd/frvrsd_vpn_bot"
XRAY_CHECKER_IMAGE="kutovoys/xray-checker:v1.3.1"
DEFAULT_INSTALL_DIR="${FRVRSD_INSTALL_DIR:-/opt/frvrsd_vpn}"
GITHUB_REPO="${FRVRSD_GITHUB_REPO:-frvrsd/frvrsd_install}"
GITHUB_BRANCH="${FRVRSD_GITHUB_BRANCH:-main}"
INSTALLER_VERSION="1.7.0"
DEPLOY_REMOTE_FILES=(docker-compose.yml .env.example deploy/Caddyfile)

# Loaded from ~/.config/frvrsd/config
INSTALL_DIR=""
FRVRSD_LANG="ru"
FRVRSD_HTTPS="0"
CLI_UPDATE_AVAILABLE=""
CLI_REMOTE_VERSION=""

# ---------------------------------------------------------------------------
# i18n
# ---------------------------------------------------------------------------
i18n() {
  local key="$1"
  if [[ "${FRVRSD_LANG}" == "en" ]]; then
    case "$key" in
      app_title)        echo "FRVRSD VPN" ;;
      menu_title)       echo "Operator menu" ;;
      menu_install)     echo "Install / first deploy" ;;
      menu_update)      echo "Update (pull image + restart)" ;;
      menu_start)       echo "Start services" ;;
      menu_stop)        echo "Stop services" ;;
      menu_restart)     echo "Restart services" ;;
      menu_status)      echo "Status (docker compose ps)" ;;
      menu_health)      echo "Ready check (/ready)" ;;
      menu_logs)        echo "View logs" ;;
      menu_edit_env)    echo "Edit .env" ;;
      menu_https_on)    echo "Enable HTTPS (Caddy profile)" ;;
      menu_https_off)   echo "Disable HTTPS (Caddy profile)" ;;
      menu_xray_on)     echo "Enable xray-checker (server status)" ;;
      menu_xray_off)    echo "Disable xray-checker" ;;
      menu_setup_cli)   echo "Install CLI command (frvrsd)" ;;
      menu_lang)        echo "Language / Язык" ;;
      menu_exit)        echo "Exit" ;;
      prompt_choice)    echo "Choice" ;;
      press_enter)      echo "Press Enter..." ;;
      invalid_choice)   echo "Invalid choice" ;;
      missing_docker)   echo "Docker not found — installing..." ;;
      missing_compose)  echo "Docker Compose plugin not found — installing Docker..." ;;
      installing_docker) echo "Installing Docker Engine + Compose..." ;;
      docker_ready)     echo "Docker is ready" ;;
      docker_install_failed) echo "Docker install failed. See https://docs.docker.com/engine/install/" ;;
      need_root)        echo "Root or sudo required to install Docker / configure UFW" ;;
      setting_ufw)      echo "Configuring UFW (22, 80, 443)..." ;;
      ufw_done)         echo "UFW enabled: allow 22, 80, 443" ;;
      ufw_skip)         echo "UFW not found — skipped (install ufw manually if needed)" ;;
      menu_bootstrap)   echo "Prepare server (Docker + UFW)" ;;
      cmd_bootstrap)    echo "  bootstrap               Install Docker + configure UFW" ;;
      menu_init)        echo "Re-download deploy files from GitHub" ;;
      cmd_init)         echo "  init [dir]              Create deploy dir + fetch from GitHub" ;;
      init_creating)    echo "Creating deploy directory:" ;;
      init_fetch)       echo "Fetching" ;;
      init_done)        echo "Deploy layout ready:" ;;
      init_failed)      echo "Failed to download" ;;
      need_github_token) echo "Set FRVRSD_GITHUB_TOKEN (repo scope) for private GitHub repo" ;;
      github_token_prompt) echo "GitHub token (repo scope, private repo):" ;;
      github_token_empty) echo "Token is required for a private repository" ;;
      github_token_invalid) echo "GitHub token rejected — check repo access and branch" ;;
      github_using_branch) echo "GitHub branch:" ;;
      missing_files)    echo "Missing deploy files in" ;;
      missing_install)  echo "Install dir not configured. Run install from deploy folder or: frvrsd install" ;;
      created_env)      echo "Created .env from .env.example" ;;
      edit_env_hint)    echo "Edit .env (BOT_TOKEN, REMNAWAVE_*, MINI_APP_URL, PAYMENT_CHAT_ID, …)." ;;
      edit_env_pause)   echo "Press Enter when ready, or Ctrl+C to abort." ;;
      env_wizard_title) echo "=== .env setup ===" ;;
      env_label_bot_token) echo "Telegram BOT_TOKEN" ;;
      env_label_remna_base) echo "Remnawave panel URL (https://...)" ;;
      env_label_remna_token) echo "Remnawave API token" ;;
      env_label_remna_proxy) echo "REMNAWAVE_PROXY_HEADERS (always|auto, Enter=always)" ;;
      env_label_mini_app_url) echo "Mini App public URL (https://domain)" ;;
      env_label_payment_chat) echo "PAYMENT_CHAT_ID (your Telegram ID — Mini App admin + alerts)" ;;
      env_label_cookies) echo "COOKIES JSON (only if panel was installed via egames script; else Enter={})" ;;
      env_label_platega_merchant) echo "Platega merchant ID (optional, Enter=skip)" ;;
      env_label_platega_secret) echo "Platega secret (optional)" ;;
      env_label_support_url) echo "Support URL (optional, e.g. https://t.me/...)" ;;
      env_label_support_contact) echo "Support contact (optional, e.g. @username)" ;;
      env_required)     echo "Required — enter a value" ;;
      env_missing)      echo "Missing required .env keys:" ;;
      env_open_editor)  echo "Open .env in editor for extra keys?" ;;
      menu_env_setup)   echo "Setup .env (wizard)" ;;
      menu_env_editor)  echo "Edit .env in editor" ;;
      menu_backup)      echo "Backup Postgres + .env" ;;
      menu_import)      echo "Import database (.dump / tar)" ;;
      cmd_env)          echo "  env|setup-env           Interactive .env wizard" ;;
      cmd_backup)       echo "  backup [--tar]          pg_dump + .env → data/backup-*" ;;
      cmd_import)       echo "  import [path]           Restore from .dump or tar" ;;
      backup_no_db)     echo "Postgres not reachable / DATABASE_URL missing — nothing to backup" ;;
      backup_stopping)  echo "Stopping bot + miniapp for a consistent backup..." ;;
      backup_done)      echo "Backup saved:" ;;
      backup_archive)   echo "Archive:" ;;
      backup_tar_prompt) echo "Create .tar.gz archive for migration?" ;;
      db_exists_offer_backup) echo "Postgres already has data — create a backup before install?" ;;
      db_import_hint)   echo "Import an existing Postgres dump before first start (optional)." ;;
      db_import_examples) echo "Examples: /tmp/frvrsd.dump  /tmp/frvrsd-backup.tar.gz  Enter=skip" ;;
      db_import_prompt) echo "Path to .dump or tar.gz" ;;
      import_not_found) echo "Import source not found:" ;;
      import_done)      echo "Database restored into Postgres" ;;
      import_overwrite_warn) echo "Target Postgres is not empty — wipe and restore? (backup first)" ;;
      env_label_pg_password) echo "POSTGRES_PASSWORD (DB password)" ;;
      env_label_database_url) echo "DATABASE_URL (Enter=auto from POSTGRES_*)" ;;
      migrate_schema)   echo "Applying DB schema (alembic)..." ;;
      waiting_ready)    echo "Waiting for /ready" ;;
      ready_ok)         echo "Mini App is ready" ;;
      ready_fail)       echo "Ready check timed out. Try: frvrsd logs miniapp" ;;
      prompt_yes_no)    echo "Yes?" ;;
      set_domain)       echo "Set MINI_APP_DOMAIN=" ;;
      warn_env)         echo "Warning: check .env — likely unset:" ;;
      need_domain)      echo "MINI_APP_DOMAIN or MINI_APP_URL required for HTTPS." ;;
      missing_caddy)    echo "Missing deploy/Caddyfile" ;;
      pulling)          echo "Pulling image" ;;
      pull_failed)      echo "Pull failed." ;;
      image_resolved)   echo "Release image" ;;
      image_tags_failed) echo "Could not read semver tags on Docker Hub for" ;;
      ufw_fail)         echo "UFW setup failed — check manually before enabling" ;;
      starting)         echo "Starting services" ;;
      waiting_health)   echo "Waiting for /ready" ;;
      health_ok)        echo "Mini App is healthy" ;;
      health_fail)      echo "Health check timed out. Try: frvrsd logs miniapp" ;;
      next_steps)       echo "Next steps" ;;
      step_botfather)   echo "BotFather → Menu Button →" ;;
      step_platega)     echo "Platega callback:" ;;
      step_admin)       echo "Mini App admin → Settings: payments, LTE, channel" ;;
      step_pin_image)   echo "frvrsd update pulls the newest x.y.z tag from Docker Hub" ;;
      https_hint)       echo "HTTPS: run menu → Enable HTTPS, or use external reverse proxy on 127.0.0.1:8080" ;;
      cli_installed)    echo "CLI installed:" ;;
      cli_path_hint)    echo "Add to PATH if needed:" ;;
      config_saved)     echo "Config saved:" ;;
      install_dir_prompt) echo "Deploy directory" ;;
      lang_set_ru)      echo "Language: Русский" ;;
      lang_set_en)      echo "Language: English" ;;
      logs_which)       echo "Logs: 1=miniapp 2=bot 3=caddy 4=xray-checker 5=all" ;;
      stopped)          echo "Services stopped" ;;
      updated)          echo "Update complete" ;;
      no_env)           echo ".env not found — run Install first" ;;
      no_editor)        echo "Set EDITOR or install nano/vi" ;;
      https_enabled)    echo "HTTPS profile enabled (saved)" ;;
      https_disabled)   echo "HTTPS profile disabled (saved)" ;;
      already_running)  echo "Already in deploy directory:" ;;
      copy_deploy)      echo "Copy docker-compose.yml, .env.example, deploy/ here first." ;;
      usage_header)     echo "Usage: frvrsd [command]" ;;
      cmd_install)      echo "  install [--https] [-y]  First deploy" ;;
      cmd_update)       echo "  update [--https]        Pull newest x.y.z image and recreate" ;;
      cmd_pull)          echo "  pull                    Pull image only" ;;
      cmd_start)        echo "  start|up [--https]" ;;
      cmd_stop)         echo "  stop|down" ;;
      cmd_restart)      echo "  restart [--https]" ;;
      cmd_status)       echo "  status|ps" ;;
      cmd_health)       echo "  health" ;;
      cmd_logs)         echo "  logs [miniapp|bot|caddy|xray-checker|all]" ;;
      cmd_setup)        echo "  setup                   Install frvrsd command" ;;
      cmd_xray_on)      echo "  xray-checker on         Enable server-status sidecar" ;;
      cmd_xray_off)     echo "  xray-checker off        Disable xray-checker" ;;
      xray_enabled)     echo "xray-checker profile enabled" ;;
      xray_disabled)    echo "xray-checker profile disabled" ;;
      xray_need_url)    echo "Set XRAY_CHECKER_SUBSCRIPTION_URL in .env first" ;;
      cmd_lang)         echo "  lang ru|en" ;;
      menu_action_failed) echo "Command failed" ;;
      cmd_menu)         echo "  menu                    Interactive menu (default)" ;;
      current_dir)      echo "Deploy dir:" ;;
      current_image)    echo "Image:" ;;
      current_https)    echo "HTTPS:" ;;
      current_xray)     echo "xray-checker:" ;;
      current_lang)     echo "Language:" ;;
      current_cli_version) echo "frvrsd CLI:" ;;
      version_uptodate) echo "frvrsd is up to date:" ;;
      version_available) echo "Update available:" ;;
      version_check_failed) echo "Could not check GitHub for a newer frvrsd (token / network)" ;;
      menu_self_update) echo "Update frvrsd CLI from GitHub" ;;
      menu_check_update) echo "Check frvrsd CLI updates" ;;
      cmd_version)      echo "  version [--check]       Show CLI version / check GitHub" ;;
      cmd_self_update)  echo "  self-update             Download CLI from the latest git tag" ;;
      self_update_fetch) echo "Downloading install.sh from the latest tag..." ;;
      self_update_done) echo "frvrsd CLI updated:" ;;
      self_update_reexec) echo "Restarting with new CLI..." ;;
      self_update_invalid) echo "Downloaded file is not a valid install.sh" ;;
      menu_section_ops) echo "— Services —" ;;
      menu_section_cfg) echo "— Config —" ;;
      menu_section_sys) echo "— System —" ;;
      menu_section_cli) echo "— CLI —" ;;
      yes)              echo "yes" ;;
      no)               echo "no" ;;
      *)                echo "$key" ;;
    esac
  else
    case "$key" in
      app_title)        echo "FRVRSD VPN" ;;
      menu_title)       echo "Меню оператора" ;;
      menu_install)     echo "Установка / первый деплой" ;;
      menu_update)      echo "Обновление (pull образа + перезапуск)" ;;
      menu_start)       echo "Запустить сервисы" ;;
      menu_stop)        echo "Остановить сервисы" ;;
      menu_restart)     echo "Перезапустить сервисы" ;;
      menu_status)      echo "Статус (docker compose ps)" ;;
      menu_health)      echo "Проверка /ready" ;;
      menu_logs)        echo "Логи" ;;
      menu_edit_env)    echo "Редактировать .env" ;;
      menu_https_on)    echo "Включить HTTPS (профиль Caddy)" ;;
      menu_https_off)   echo "Выключить HTTPS (профиль Caddy)" ;;
      menu_xray_on)     echo "Включить xray-checker (статус серверов)" ;;
      menu_xray_off)    echo "Выключить xray-checker" ;;
      menu_setup_cli)   echo "Установить команду frvrsd" ;;
      menu_lang)        echo "Language / Язык" ;;
      menu_exit)        echo "Выход" ;;
      prompt_choice)    echo "Выбор" ;;
      press_enter)      echo "Enter..." ;;
      invalid_choice)   echo "Неверный выбор" ;;
      missing_docker)   echo "Docker не найден — устанавливаю..." ;;
      missing_compose)  echo "Docker Compose не найден — устанавливаю Docker..." ;;
      installing_docker) echo "Установка Docker Engine + Compose..." ;;
      docker_ready)     echo "Docker готов" ;;
      docker_install_failed) echo "Не удалось установить Docker. См. https://docs.docker.com/engine/install/" ;;
      need_root)        echo "Нужен root или sudo для Docker и UFW" ;;
      setting_ufw)      echo "Настройка UFW (22, 80, 443)..." ;;
      ufw_done)         echo "UFW включён: allow 22, 80, 443" ;;
      ufw_skip)         echo "UFW не найден — пропуск (установите ufw вручную при необходимости)" ;;
      menu_bootstrap)   echo "Подготовка сервера (Docker + UFW)" ;;
      cmd_bootstrap)    echo "  bootstrap               Docker + UFW" ;;
      menu_init)        echo "Скачать deploy-файлы из GitHub заново" ;;
      cmd_init)         echo "  init [dir]              Каталог деплоя + fetch из GitHub" ;;
      init_creating)    echo "Создаю каталог деплоя:" ;;
      init_fetch)       echo "Скачиваю" ;;
      init_done)        echo "Deploy готов:" ;;
      init_failed)      echo "Не удалось скачать" ;;
      need_github_token) echo "Задайте FRVRSD_GITHUB_TOKEN (scope repo) для приватного GitHub" ;;
      github_token_prompt) echo "GitHub token (scope repo, приватный репозиторий):" ;;
      github_token_empty) echo "Для приватного репозитория нужен token" ;;
      github_token_invalid) echo "GitHub token не принят — проверьте доступ и ветку" ;;
      github_using_branch) echo "Ветка GitHub:" ;;
      missing_files)    echo "Нет файлов деплоя в" ;;
      missing_install)  echo "Каталог деплоя не настроен. Запустите из папки с compose или: frvrsd install" ;;
      created_env)      echo "Создан .env из .env.example" ;;
      edit_env_hint)    echo "Заполните .env (BOT_TOKEN, REMNAWAVE_*, MINI_APP_URL, PAYMENT_CHAT_ID, …)." ;;
      edit_env_pause)   echo "Enter — продолжить, Ctrl+C — отмена." ;;
      env_wizard_title) echo "=== Настройка .env ===" ;;
      env_label_bot_token) echo "Telegram BOT_TOKEN" ;;
      env_label_remna_base) echo "URL панели Remnawave (https://...)" ;;
      env_label_remna_token) echo "API-токен Remnawave" ;;
      env_label_remna_proxy) echo "REMNAWAVE_PROXY_HEADERS (always|auto, Enter=always)" ;;
      env_label_mini_app_url) echo "Публичный URL Mini App (https://домен)" ;;
      env_label_payment_chat) echo "PAYMENT_CHAT_ID (ваш Telegram ID — админ ЛК + алерты)" ;;
      env_label_cookies) echo "COOKIES JSON (только если панель ставили скриптом egames; иначе Enter={})" ;;
      env_label_platega_merchant) echo "Platega merchant ID (необяз., Enter=пропуск)" ;;
      env_label_platega_secret) echo "Platega secret (необяз.)" ;;
      env_label_support_url) echo "Support URL (необяз., напр. https://t.me/...)" ;;
      env_label_support_contact) echo "Support contact (необяз., напр. @username)" ;;
      env_required)     echo "Обязательное поле — введите значение" ;;
      env_missing)      echo "Не заполнены обязательные ключи .env:" ;;
      env_open_editor)  echo "Открыть .env в редакторе для остальных ключей?" ;;
      menu_env_setup)   echo "Настройка .env (мастер)" ;;
      menu_env_editor)  echo "Редактор .env (nano/vi)" ;;
      menu_backup)      echo "Бэкап Postgres + .env" ;;
      menu_import)      echo "Импорт базы (.dump / tar)" ;;
      cmd_env)          echo "  env|setup-env           Мастер настройки .env" ;;
      cmd_backup)       echo "  backup [--tar]          pg_dump + .env → data/backup-*" ;;
      cmd_import)       echo "  import [path]           Восстановление из .dump или tar" ;;
      backup_no_db)     echo "Postgres недоступен / нет DATABASE_URL — бэкапить нечего" ;;
      backup_stopping)  echo "Останавливаю bot + miniapp для консистентного бэкапа..." ;;
      backup_done)      echo "Бэкап сохранён:" ;;
      backup_archive)   echo "Архив:" ;;
      backup_tar_prompt) echo "Создать .tar.gz для переноса на другой сервер?" ;;
      db_exists_offer_backup) echo "В Postgres уже есть данные — сделать бэкап перед установкой?" ;;
      db_import_hint)   echo "Импорт существующего dump Postgres перед первым запуском (необяз.)." ;;
      db_import_examples) echo "Примеры: /tmp/frvrsd.dump  /tmp/frvrsd-backup.tar.gz  Enter=пропуск" ;;
      db_import_prompt) echo "Путь к .dump или tar.gz" ;;
      import_not_found) echo "Источник импорта не найден:" ;;
      import_done)      echo "База восстановлена в Postgres" ;;
      import_overwrite_warn) echo "Целевой Postgres не пуст — очистить и восстановить? (сначала бэкап)" ;;
      env_label_pg_password) echo "POSTGRES_PASSWORD (пароль БД)" ;;
      env_label_database_url) echo "DATABASE_URL (Enter=авто из POSTGRES_*)" ;;
      migrate_schema)   echo "Применяю схему БД (alembic)..." ;;
      waiting_ready)    echo "Ожидание /ready" ;;
      ready_ok)         echo "Mini App готов" ;;
      ready_fail)       echo "Таймаут /ready. Попробуйте: frvrsd logs miniapp" ;;
      prompt_yes_no)    echo "Да?" ;;
      set_domain)       echo "MINI_APP_DOMAIN=" ;;
      warn_env)         echo "Проверьте .env — возможно пусто:" ;;
      need_domain)      echo "Для HTTPS нужны MINI_APP_DOMAIN или MINI_APP_URL." ;;
      missing_caddy)    echo "Нет deploy/Caddyfile" ;;
      pulling)          echo "Загрузка образа" ;;
      pull_failed)      echo "Не удалось скачать образ." ;;
      image_resolved)   echo "Релизный образ" ;;
      image_tags_failed) echo "Не удалось прочитать semver-теги Docker Hub для" ;;
      ufw_fail)         echo "UFW не настроен — проверьте вручную перед enable" ;;
      starting)         echo "Запуск сервисов" ;;
      waiting_health)   echo "Ожидание /ready" ;;
      health_ok)        echo "Mini App отвечает" ;;
      health_fail)      echo "Таймаут health. Попробуйте: frvrsd logs miniapp" ;;
      next_steps)       echo "Дальше" ;;
      step_botfather)   echo "BotFather → Menu Button →" ;;
      step_platega)     echo "Platega callback:" ;;
      step_admin)       echo "Админка Mini App → Настройки: платежи, LTE, канал" ;;
      step_pin_image)   echo "frvrsd update сам берёт последний тег x.y.z с Docker Hub" ;;
      https_hint)       echo "HTTPS: меню → Включить HTTPS, или внешний reverse proxy на 127.0.0.1:8080" ;;
      cli_installed)    echo "Команда установлена:" ;;
      cli_path_hint)    echo "Добавьте в PATH при необходимости:" ;;
      config_saved)     echo "Конфиг сохранён:" ;;
      install_dir_prompt) echo "Каталог деплоя" ;;
      lang_set_ru)      echo "Язык: Русский" ;;
      lang_set_en)      echo "Language: English" ;;
      logs_which)       echo "Логи: 1=miniapp 2=bot 3=caddy 4=xray-checker 5=all" ;;
      stopped)          echo "Сервисы остановлены" ;;
      updated)          echo "Обновление завершено" ;;
      no_env)           echo "Нет .env — сначала Установка" ;;
      no_editor)        echo "Задайте EDITOR или установите nano/vi" ;;
      https_enabled)    echo "HTTPS включён (сохранено)" ;;
      https_disabled)   echo "HTTPS выключен (сохранено)" ;;
      already_running)  echo "Уже в каталоге деплоя:" ;;
      copy_deploy)      echo "Скопируйте сюда docker-compose.yml, .env.example, deploy/." ;;
      usage_header)     echo "Использование: frvrsd [команда]" ;;
      cmd_install)      echo "  install [--https] [-y]  Первый деплой" ;;
      cmd_update)       echo "  update [--https]        Скачать последний x.y.z и пересоздать" ;;
      cmd_pull)          echo "  pull                    Только pull образа" ;;
      cmd_start)        echo "  start|up [--https]" ;;
      cmd_stop)         echo "  stop|down" ;;
      cmd_restart)      echo "  restart [--https]" ;;
      cmd_status)       echo "  status|ps" ;;
      cmd_health)       echo "  health" ;;
      cmd_logs)         echo "  logs [miniapp|bot|caddy|xray-checker|all]" ;;
      cmd_setup)        echo "  setup                   Установить команду frvrsd" ;;
      cmd_xray_on)      echo "  xray-checker on         Включить sidecar статуса серверов" ;;
      cmd_xray_off)     echo "  xray-checker off        Выключить xray-checker" ;;
      xray_enabled)     echo "Профиль xray-checker включён" ;;
      xray_disabled)    echo "Профиль xray-checker выключен" ;;
      xray_need_url)    echo "Сначала задайте XRAY_CHECKER_SUBSCRIPTION_URL в .env" ;;
      cmd_lang)         echo "  lang ru|en" ;;
      menu_action_failed) echo "Команда завершилась с ошибкой" ;;
      cmd_menu)         echo "  menu                    Интерактивное меню (по умолчанию)" ;;
      current_dir)      echo "Каталог:" ;;
      current_image)    echo "Образ:" ;;
      current_https)    echo "HTTPS:" ;;
      current_xray)     echo "xray-checker:" ;;
      current_lang)     echo "Язык:" ;;
      current_cli_version) echo "frvrsd CLI:" ;;
      version_uptodate) echo "frvrsd актуален:" ;;
      version_available) echo "Доступно обновление:" ;;
      version_check_failed) echo "Не удалось проверить версию на GitHub (token / сеть)" ;;
      menu_self_update) echo "Обновить frvrsd CLI с GitHub" ;;
      menu_check_update) echo "Проверить обновления frvrsd CLI" ;;
      cmd_version)      echo "  version [--check]       Версия CLI / проверка GitHub" ;;
      cmd_self_update)  echo "  self-update             Скачать CLI с последнего git-тега" ;;
      self_update_fetch) echo "Скачиваю install.sh с последнего тега..." ;;
      self_update_done) echo "frvrsd CLI обновлён:" ;;
      self_update_reexec) echo "Перезапуск с новой версией CLI..." ;;
      self_update_invalid) echo "Скачанный файл не похож на install.sh" ;;
      menu_section_ops) echo "— Сервисы —" ;;
      menu_section_cfg) echo "— Конфиг —" ;;
      menu_section_sys) echo "— Система —" ;;
      menu_section_cli) echo "— CLI —" ;;
      yes)              echo "да" ;;
      no)               echo "нет" ;;
      *)                echo "$key" ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
use_color() {
  case "${FRVRSD_COLOR:-auto}" in
    always|1|yes|true) return 0 ;;
    never|0|no|false)  return 1 ;;
  esac
  [[ -z "${NO_COLOR:-}" ]] || return 1
  # Prefer colors on interactive terminals; allow override for pipes/CI
  [[ -t 1 || -t 0 ]]
}

init_colors() {
  if use_color; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[1;34m'
    C_MAGENTA=$'\033[1;35m'
    C_CYAN=$'\033[1;36m'
    C_WHITE=$'\033[1;37m'
  else
    C_RESET= C_BOLD= C_DIM= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_MAGENTA= C_CYAN= C_WHITE=
  fi
}
init_colors

cprintf() {
  # cprintf COLOR "fmt" args...  — COLOR is empty or ANSI, then printf
  local color="$1"
  shift
  if [[ -n "$color" ]]; then
    printf '%s' "$color"
    printf "$@"
    printf '%s' "$C_RESET"
  else
    printf "$@"
  fi
}

red()     { cprintf "$C_RED" '%s\n' "$*"; }
green()   { cprintf "$C_GREEN" '%s\n' "$*"; }
yellow()  { cprintf "$C_YELLOW" '%s\n' "$*"; }
cyan()    { cprintf "$C_CYAN" '%s\n' "$*"; }
blue()    { cprintf "$C_BLUE" '%s\n' "$*"; }
magenta() { cprintf "$C_MAGENTA" '%s\n' "$*"; }
bold()    { cprintf "$C_BOLD" '%s\n' "$*"; }
dim()     { cprintf "$C_DIM" '%s\n' "$*"; }

status_kv() {
  local label="$1" value="$2" color="${3:-$C_CYAN}"
  printf '  %s%s%s %s%s%s\n' "$C_DIM" "$label" "$C_RESET" "$color" "$value" "$C_RESET"
}

menu_section() {
  printf '\n  %s%s%s\n' "$C_MAGENTA" "$1" "$C_RESET"
}

menu_item() {
  local num="$1" text="$2" highlight="${3:-0}"
  if [[ "$highlight" -eq 1 ]]; then
    printf ' %s%2s)%s %s%s%s\n' "$C_YELLOW" "$num" "$C_RESET" "$C_BOLD$C_YELLOW" "$text" "$C_RESET"
  else
    printf ' %s%2s)%s %s%s%s\n' "$C_CYAN" "$num" "$C_RESET" "$C_WHITE" "$text" "$C_RESET"
  fi
}

refresh_cli_update_hint() {
  CLI_UPDATE_AVAILABLE=""
  CLI_REMOTE_VERSION=""
  resolve_install_dir 2>/dev/null || return 0
  fetch_remote_installer_version "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}" || true
  CLI_REMOTE_VERSION="${REMOTE_INSTALLER_VERSION:-}"
  if [[ -n "$CLI_REMOTE_VERSION" ]] \
    && version_is_newer "$CLI_REMOTE_VERSION" "$INSTALLER_VERSION"; then
    CLI_UPDATE_AVAILABLE=1
  fi
}

pause() {
  local msg="${1:-$(i18n press_enter)}"
  yellow "$msg"
  read -r _
}

sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    local expr="${1}"
    local file="${2}"
    sed -i '' "${expr}" "${file}"
  fi
}

same_path() {
  local a b
  [[ -e "$1" && -e "$2" ]] || return 1
  a="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  b="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
  [[ "$a" == "$b" ]]
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
read_config_var() {
  local key="$1" file="$2"
  grep -E "^${key}=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2- \
    | sed 's/^["'\''"]//; s/["'\''"]$//' || true
}

install_config_path() {
  echo "${1}/.frvrsd/config"
}

github_probe() {
  local url="$1"
  local code
  # curl -f can fail and still print code; avoid concatenating fallback "000"
  if [[ -n "${FRVRSD_GITHUB_TOKEN:-}" ]]; then
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
      -H "Authorization: token ${FRVRSD_GITHUB_TOKEN}" \
      -H "Cache-Control: no-cache" \
      "$url" 2>/dev/null || true)"
  else
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
      -H "Cache-Control: no-cache" \
      "$url" 2>/dev/null || true)"
  fi
  [[ "${code:-000}" == "200" ]]
}

# Latest release is the highest semver git tag (optional leading v).
# A commit on a branch is not a CLI release until that tag exists.
fetch_latest_release_tag() {
  local raw ver
  RELEASE_TAG=""
  raw="$(curl -fsSL --max-time 20 \
    -H "Accept: application/vnd.github+json" \
    -H "Cache-Control: no-cache" \
    "https://api.github.com/repos/${GITHUB_REPO}/tags?per_page=100" 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 0
  ver="$(printf '%s\n' "$raw" \
    | grep -o '"name": "[^"]*"' \
    | sed 's/"name": "//; s/"$//' \
    | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed 's/^v//' \
    | sort -V \
    | tail -n1 || true)"
  RELEASE_TAG="${ver:-}"
}

resolve_github_ref() {
  if [[ -n "${FRVRSD_GITHUB_BRANCH:-}" ]]; then
    GITHUB_BRANCH="$FRVRSD_GITHUB_BRANCH"
    return 0
  fi
  fetch_latest_release_tag
  if [[ -n "${RELEASE_TAG:-}" ]]; then
    GITHUB_BRANCH="$RELEASE_TAG"
    return 0
  fi
  GITHUB_BRANCH="main"
}

ensure_github_auth() {
  local probe_url
  # Public repo: do not send a saved token. A revoked token from the old
  # private repo makes GitHub answer 401 even for a public file.
  resolve_github_ref
  probe_url="$(github_raw_url "docker-compose.yml")"
  if github_probe "$probe_url"; then
    return 0
  fi
  red "$(i18n init_failed) docker-compose.yml (${GITHUB_REPO}@${GITHUB_BRANCH})"
  exit 1
}

docker_data_dir() {
  echo "${INSTALL_DIR}/.docker"
}

deploy_root_from_script() {
  if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
    echo "${SCRIPT_DIR}"
    return 0
  fi
  if [[ -f "${SCRIPT_DIR}/../docker-compose.yml" ]]; then
    cd "${SCRIPT_DIR}/.." && pwd
    return 0
  fi
  return 1
}

load_config() {
  local f dir root
  root="$(deploy_root_from_script 2>/dev/null || true)"
  for dir in "${INSTALL_DIR}" "${root}" "${SCRIPT_DIR}" "${DEFAULT_INSTALL_DIR}"; do
    [[ -n "$dir" ]] || continue
    f="$(install_config_path "$dir")"
    if [[ -f "$f" ]]; then
      CONFIG_FILE="$f"
      INSTALL_DIR="$(read_config_var INSTALL_DIR "$f")"
      FRVRSD_LANG="$(read_config_var FRVRSD_LANG "$f")"
      FRVRSD_HTTPS="$(read_config_var FRVRSD_HTTPS "$f")"
      break
    fi
  done
  if [[ -z "${CONFIG_FILE}" && -f "${CONFIG_DIR}/config" ]]; then
    CONFIG_FILE="${CONFIG_DIR}/config"
    INSTALL_DIR="${INSTALL_DIR:-$(read_config_var INSTALL_DIR "$CONFIG_FILE")}"
    FRVRSD_LANG="$(read_config_var FRVRSD_LANG "$CONFIG_FILE")"
    FRVRSD_HTTPS="$(read_config_var FRVRSD_HTTPS "$CONFIG_FILE")"
  fi
  FRVRSD_LANG="${FRVRSD_LANG:-ru}"
  FRVRSD_HTTPS="${FRVRSD_HTTPS:-0}"
}

write_config_file() {
  if [[ -n "${INSTALL_DIR}" ]]; then
    CONFIG_FILE="$(install_config_path "${INSTALL_DIR}")"
    mkdir -p "${INSTALL_DIR}/.frvrsd"
  else
    mkdir -p "$CONFIG_DIR"
    CONFIG_FILE="${CONFIG_DIR}/config"
  fi
  cat >"$CONFIG_FILE" <<EOF
INSTALL_DIR=${INSTALL_DIR}
FRVRSD_LANG=${FRVRSD_LANG}
FRVRSD_HTTPS=${FRVRSD_HTTPS}
EOF
  chmod 600 "$CONFIG_FILE"
}

save_config() {
  write_config_file
  green "$(i18n config_saved) $CONFIG_FILE"
}

# Heal FRVRSD_HTTPS when config drifted from .env COMPOSE_PROFILES / running Caddy.
# Must run before sync_https_compose_profile (which would strip COMPOSE_PROFILES).
detect_https_active() {
  local profiles=""
  if [[ -f .env ]]; then
    profiles="$(read_env_var COMPOSE_PROFILES 2>/dev/null || true)"
    # Exact comma-separated profile token (not substring)
    case ",${profiles// /}," in
      *,https,*) return 0 ;;
    esac
  fi
  if docker_ready 2>/dev/null; then
    mkdir -p "$(docker_data_dir)" 2>/dev/null || true
    export DOCKER_CONFIG="$(docker_data_dir)"
    if COMPOSE_PROFILES=https docker compose --profile https ps --status running -q caddy 2>/dev/null \
      | grep -q .; then
      return 0
    fi
  fi
  return 1
}

reconcile_https_flag() {
  # Explicit disable (https-off / --no-https) must win over .env/caddy heal
  [[ "${FRVRSD_HTTPS_SKIP_RECONCILE:-}" == "1" ]] && return 0
  [[ "${FRVRSD_HTTPS}" == "1" ]] && return 0
  detect_https_active || return 0
  FRVRSD_HTTPS=1
  write_config_file
}

resolve_install_dir() {
  local root
  load_config

  if [[ -n "${INSTALL_DIR}" && -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
    cd "${INSTALL_DIR}"
    reconcile_https_flag
    return 0
  fi

  if root="$(deploy_root_from_script 2>/dev/null)"; then
    INSTALL_DIR="$root"
    cd "${INSTALL_DIR}"
    reconcile_https_flag
    return 0
  fi

  if [[ -f "${DEFAULT_INSTALL_DIR}/docker-compose.yml" ]]; then
    INSTALL_DIR="${DEFAULT_INSTALL_DIR}"
    cd "${INSTALL_DIR}"
    reconcile_https_flag
    return 0
  fi

  return 1
}

require_install_dir() {
  ensure_deploy_layout
}

# ---------------------------------------------------------------------------
# GitHub deploy bundle fetch
# ---------------------------------------------------------------------------
github_raw_url() {
  # cache-bust query helps after private-repo pushes (CDN may lag)
  echo "https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${1}?$(date +%s)"
}

github_api_url() {
  echo "https://api.github.com/repos/${GITHUB_REPO}/contents/${1}?ref=${GITHUB_BRANCH}"
}

github_curl() {
  # github_curl <url> [extra curl args...]
  local url="$1"
  shift
  if [[ -n "${FRVRSD_GITHUB_TOKEN:-}" ]]; then
    curl -fsSL \
      -H "Authorization: token ${FRVRSD_GITHUB_TOKEN}" \
      -H "Cache-Control: no-cache" \
      -H "Pragma: no-cache" \
      "$@" "$url"
  else
    curl -fsSL \
      -H "Cache-Control: no-cache" \
      -H "Pragma: no-cache" \
      "$@" "$url"
  fi
}

fetch_repo_file() {
  local remote_path="$1" local_path="$2"
  mkdir -p "$(dirname "$local_path")"
  local raw api
  raw="$(github_raw_url "$remote_path")"
  api="$(github_api_url "$remote_path")"

  # Prefer GitHub API for private repos (fresher than raw CDN)
  if [[ -n "${FRVRSD_GITHUB_TOKEN:-}" ]]; then
    if github_curl "$api" -H "Accept: application/vnd.github.raw+json" -o "$local_path"; then
      return 0
    fi
  fi
  if github_curl "$raw" -o "$local_path"; then
    return 0
  fi
  return 1
}

strip_version_value() {
  printf '%s' "$1" | cut -d= -f2- | command tr -d '\r\n' | sed 's/^["'\''"]//; s/["'\''"]$//'
}

installer_version_from_file() {
  local file="$1" line
  [[ -f "$file" ]] || return 1
  line="$(grep -m1 '^INSTALLER_VERSION=' "$file" 2>/dev/null || true)"
  strip_version_value "$line"
}

fetch_remote_installer_version() {
  local line raw

  REMOTE_INSTALLER_VERSION=""
  resolve_github_ref
  # The release tag name is the CLI version. Fall back to the file only when
  # no semver tag exists yet (first publish).
  if [[ "$GITHUB_BRANCH" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    REMOTE_INSTALLER_VERSION="$GITHUB_BRANCH"
    return 0
  fi
  raw="$(github_raw_url "install.sh")"
  line="$(github_curl "$raw" 2>/dev/null | grep -m1 '^INSTALLER_VERSION=' || true)"
  REMOTE_INSTALLER_VERSION="$(strip_version_value "$line")"
}

version_is_newer() {
  local remote="$1" local_ver="$2"

  [[ -n "$remote" && -n "$local_ver" && "$remote" != "$local_ver" ]] || return 1
  if [[ "$remote" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.+~-]*)?$ \
     && "$local_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.+~-]*)?$ ]]; then
    [[ "$(printf '%s\n' "$remote" "$local_ver" | sort -V | tail -n1)" == "$remote" ]]
    return
  fi
  return 0
}

check_installer_update() {
  local quiet="${1:-0}"
  local target="${INSTALL_DIR:-${FRVRSD_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}}"

  fetch_remote_installer_version "$target"
  if [[ -z "${REMOTE_INSTALLER_VERSION:-}" ]]; then
    [[ "$quiet" -eq 1 ]] || yellow "$(i18n version_check_failed)"
    return 1
  fi
  if version_is_newer "$REMOTE_INSTALLER_VERSION" "$INSTALLER_VERSION"; then
    [[ "$quiet" -eq 1 ]] || yellow "$(i18n version_available) ${INSTALLER_VERSION} → ${REMOTE_INSTALLER_VERSION}"
    return 0
  fi
  [[ "$quiet" -eq 1 ]] || green "$(i18n version_uptodate) ${INSTALLER_VERSION}"
  return 1
}

install_script_paths() {
  local target="${1:-${INSTALL_DIR:-${FRVRSD_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}}}"
  INSTALL_SH_PATH="${target}/install.sh"
  CLI_BIN_PATH="${target}/bin/${CLI_NAME}"
}

cmd_version() {
  local do_check=0 arg
  for arg in "$@"; do
    case "$arg" in
      --check|-c) do_check=1 ;;
    esac
  done
  status_kv "$(i18n current_cli_version)" "$INSTALLER_VERSION" "$C_GREEN"
  if [[ "$do_check" -eq 1 ]]; then
    resolve_install_dir 2>/dev/null || true
    check_installer_update 0 || true
    status_kv "GitHub" "${GITHUB_REPO}@${GITHUB_BRANCH}" "$C_BLUE"
  else
    status_kv "GitHub" "${GITHUB_REPO}" "$C_BLUE"
  fi
}

cmd_self_update() {
  local target tmp new_ver old_ver
  local -a deploy_only=(docker-compose.yml .env.example deploy/Caddyfile)
  local with_deploy=0 remote
  local -a reexec_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deploy) with_deploy=1; shift ;;
      --no-reexec) FRVRSD_SELF_UPDATE_NO_REEXEC=1; shift ;;
      *) shift ;;
    esac
  done

  resolve_install_dir 2>/dev/null || require_install_dir
  target="${INSTALL_DIR}"
  tmp="$(mktemp)"
  old_ver="$INSTALLER_VERSION"

  ensure_github_auth "$target"
  cyan "$(i18n self_update_fetch)"

  if ! fetch_repo_file "install.sh" "$tmp"; then
    rm -f "$tmp"
    red "$(i18n init_failed) install.sh"
    exit 1
  fi

  new_ver="$(installer_version_from_file "$tmp")"
  if [[ -z "$new_ver" ]] || ! grep -q '^INSTALLER_VERSION=' "$tmp"; then
    rm -f "$tmp"
    red "$(i18n self_update_invalid)"
    exit 1
  fi
  if [[ "$GITHUB_BRANCH" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$new_ver" != "$GITHUB_BRANCH" ]]; then
    rm -f "$tmp"
    red "$(i18n self_update_invalid)"
    exit 1
  fi

  if [[ "$with_deploy" -eq 1 ]]; then
    for remote in "${deploy_only[@]}"; do
      cyan "$(i18n init_fetch) ${remote}"
      fetch_repo_file "$remote" "${target}/${remote}" || {
        red "$(i18n init_failed) ${remote}"
        rm -f "$tmp"
        exit 1
      }
    done
  fi

  install_script_paths "$target"
  cp -f "$tmp" "$INSTALL_SH_PATH"
  chmod +x "$INSTALL_SH_PATH"
  rm -f "$tmp"

  INSTALL_DIR="$target"
  cd "$INSTALL_DIR"
  install_cli_command "$INSTALL_SH_PATH" "$INSTALL_DIR"

  if [[ "$new_ver" == "$old_ver" ]]; then
    green "$(i18n version_uptodate) ${old_ver}"
  else
    green "$(i18n self_update_done) ${old_ver} → ${new_ver}"
  fi

  if [[ "${FRVRSD_SELF_UPDATE_NO_REEXEC:-}" == "1" ]]; then
    return 0
  fi

  if [[ "${FRVRSD_MENU:-}" == "1" || "${FRVRSD_SELF_UPDATE_REEXEC_MENU:-}" == "1" ]]; then
    reexec_args=(menu)
  else
    reexec_args=(version)
  fi
  reexec_updated_cli "${reexec_args[@]}"
}

reexec_updated_cli() {
  local bin
  install_script_paths "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
  bin="${CLI_BIN_PATH:-}"
  if [[ ! -x "$bin" ]]; then
    bin="${INSTALL_SH_PATH:-}"
  fi
  if [[ ! -x "$bin" ]]; then
    yellow "$(i18n self_update_reexec)"
    return 0
  fi
  cyan "$(i18n self_update_reexec)"
  exec "$bin" "$@"
}

mkdir_deploy_dir() {
  local target="$1"
  if [[ -d "$target" ]]; then
    return 0
  fi
  if [[ "${EUID}" -eq 0 ]]; then
    mkdir -p "$target"
  elif [[ -w "$(dirname "$target")" ]]; then
    mkdir -p "$target"
  else
    run_root mkdir -p "$target"
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      run_root chown "${SUDO_USER}:${SUDO_USER}" "$target"
    fi
  fi
}

cmd_init() {
  local target="${1:-${FRVRSD_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}}"
  local remote

  cyan "$(i18n init_creating) ${target}"
  mkdir_deploy_dir "$target"
  mkdir -p "${target}/.frvrsd" "${target}/data" "${target}/deploy"

  ensure_github_auth "$target"

  for remote in "${DEPLOY_REMOTE_FILES[@]}"; do
    cyan "$(i18n init_fetch) ${remote}"
    if ! fetch_repo_file "$remote" "${target}/${remote}"; then
      red "$(i18n init_failed) ${remote}"
      exit 1
    fi
  done

  cyan "$(i18n init_fetch) install.sh"
  if ! fetch_repo_file "install.sh" "${target}/install.sh"; then
    cp -f "$SCRIPT_PATH" "${target}/install.sh"
  fi
  chmod +x "${target}/install.sh"

  INSTALL_DIR="$target"
  cd "${INSTALL_DIR}"

  if [[ ! -f .env ]]; then
    cp .env.example .env
    yellow "$(i18n created_env)"
  fi
  secure_env_file
  save_config
  install_cli_command "${INSTALL_DIR}/install.sh" "${INSTALL_DIR}"
  green "$(i18n init_done) ${INSTALL_DIR}"
  yellow "Release: ${GITHUB_BRANCH} · Repo: ${GITHUB_REPO}"
}

ensure_deploy_layout() {
  if resolve_install_dir 2>/dev/null; then
    ensure_cli_installed
    return 0
  fi
  cmd_init "${FRVRSD_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
}

# ---------------------------------------------------------------------------
# Env / domain helpers
# ---------------------------------------------------------------------------
read_env_var() {
  local key="$1"
  [[ -f .env ]] || return 1
  grep -E "^${key}=" .env 2>/dev/null | tail -n1 | cut -d= -f2- \
    | sed 's/^["'\''"]//; s/["'\''"]$//' || true
}

ensure_env_key() {
  local key="$1"
  local value="$2"
  grep -qE "^${key}=" .env 2>/dev/null || printf '\n%s=%s\n' "$key" "$value" >>.env
}

set_env_key() {
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=" .env 2>/dev/null; then
    sed_inplace "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '\n%s=%s\n' "$key" "$value" >>.env
  fi
}

secure_env_file() {
  [[ -f .env ]] && chmod 600 .env
}

env_value_empty() {
  local v="$1"
  [[ -z "$v" || "$v" == *"..."* ]]
}

prompt_env_var() {
  local key="$1" label_key="$2" secret="${3:-0}" required="${4:-1}"
  local current="" display="" input=""

  current="$(read_env_var "$key")"
  if [[ "$secret" -eq 1 && -n "$current" ]] && ! env_value_empty "$current"; then
    display="****"
  elif ! env_value_empty "$current"; then
    display="$current"
  fi

  if [[ -n "$display" ]]; then
    printf '%s [%s]: ' "$(i18n "$label_key")" "$display"
  else
    printf '%s: ' "$(i18n "$label_key")"
  fi

  if [[ "$secret" -eq 1 ]]; then
    read -rs input
    echo ""
  else
    read -r input
  fi

  if [[ -z "$input" ]]; then
    if env_value_empty "$current"; then
      if [[ "$required" -eq 1 ]]; then
        yellow "$(i18n env_required)"
        prompt_env_var "$key" "$label_key" "$secret" "$required"
      elif [[ "$key" == "REMNAWAVE_PROXY_HEADERS" ]]; then
        set_env_key "$key" "always"
      fi
    fi
    return 0
  fi

  set_env_key "$key" "$input"
}

gen_db_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  elif command -v head >/dev/null 2>&1; then
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  else
    date +%s%N | sha256sum | head -c 32
  fi
}

ensure_db_credentials() {
  local user db pass url
  [[ -f .env ]] || cp .env.example .env

  user="$(read_env_var POSTGRES_USER)"
  db="$(read_env_var POSTGRES_DB)"
  pass="$(read_env_var POSTGRES_PASSWORD)"
  url="$(read_env_var DATABASE_URL)"

  [[ -n "$user" ]] || user="frvrsd"
  [[ -n "$db" ]] || db="frvrsd"
  set_env_key "POSTGRES_USER" "$user"
  set_env_key "POSTGRES_DB" "$db"

  if env_value_empty "$pass" || [[ "$pass" == "change-me" ]]; then
    pass="$(gen_db_secret)"
    set_env_key "POSTGRES_PASSWORD" "$pass"
    yellow "POSTGRES_PASSWORD → (generated)"
  fi

  if env_value_empty "$url"; then
    url="postgresql://${user}:${pass}@postgres:5432/${db}"
    set_env_key "DATABASE_URL" "$url"
  fi
}

validate_env_required() {
  local missing=() var val
  ensure_db_credentials
  for var in BOT_TOKEN REMNAWAVE_BASE_URL REMNAWAVE_TOKEN MINI_APP_URL PAYMENT_CHAT_ID \
             POSTGRES_PASSWORD DATABASE_URL; do
    val="$(read_env_var "$var")"
    if env_value_empty "$val"; then
      missing+=("$var")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    red "$(i18n env_missing) ${missing[*]}"
    exit 1
  fi
}

interactive_env_setup() {
  [[ -f .env ]] || { cp .env.example .env; yellow "$(i18n created_env)"; }

  bold "$(i18n env_wizard_title)"
  echo ""
  prompt_env_var BOT_TOKEN env_label_bot_token 1 1
  prompt_env_var REMNAWAVE_BASE_URL env_label_remna_base 0 1
  prompt_env_var REMNAWAVE_TOKEN env_label_remna_token 1 1
  prompt_env_var REMNAWAVE_PROXY_HEADERS env_label_remna_proxy 0 0
  prompt_env_var COOKIES env_label_cookies 0 0
  # Empty → {}; needed only when Remnawave was installed via egames script
  if env_value_empty "$(read_env_var COOKIES)"; then
    set_env_key "COOKIES" "{}"
  fi
  prompt_env_var MINI_APP_URL env_label_mini_app_url 0 1
  prompt_env_var PAYMENT_CHAT_ID env_label_payment_chat 0 1
  prompt_env_var PLATEGA_MERCHANT_ID env_label_platega_merchant 0 0
  prompt_env_var PLATEGA_SECRET env_label_platega_secret 1 0
  prompt_env_var SUPPORT_URL env_label_support_url 0 0
  prompt_env_var SUPPORT_CONTACT env_label_support_contact 0 0
  prompt_env_var POSTGRES_PASSWORD env_label_pg_password 1 0
  prompt_env_var DATABASE_URL env_label_database_url 0 0

  sync_mini_app_domain
  ensure_db_credentials
  secure_env_file
  validate_env_required

  if [[ -t 0 ]]; then
    local open_ed=""
    printf "%s [y/N]: " "$(i18n env_open_editor)"
    read -r open_ed
    if [[ "$open_ed" =~ ^[yY] ]]; then
      cmd_edit_env
    fi
  fi
}

pg_user() { local u; u="$(read_env_var POSTGRES_USER)"; echo "${u:-frvrsd}"; }
pg_db() { local d; d="$(read_env_var POSTGRES_DB)"; echo "${d:-frvrsd}"; }

services_running() {
  docker_ready || return 1
  compose ps --status running -q bot miniapp 2>/dev/null | grep -q .
}

postgres_running() {
  docker_ready || return 1
  compose ps --status running -q postgres 2>/dev/null | grep -q .
}

restart_app_services() {
  docker_ready || return 0
  compose up -d bot miniapp 2>/dev/null || compose start bot miniapp 2>/dev/null || true
}

wait_postgres() {
  local i user db
  user="$(pg_user)"
  db="$(pg_db)"
  for i in $(seq 1 40); do
    if compose exec -T postgres pg_isready -U "$user" -d "$db" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

ensure_postgres_up() {
  need_docker
  require_install_dir
  ensure_db_credentials
  secure_env_file
  compose up -d postgres
  wait_postgres || {
    red "$(i18n backup_no_db)"
    return 1
  }
}

compose_migrate() {
  cyan "$(i18n migrate_schema)"
  require_install_dir
  mkdir -p "$(docker_data_dir)"
  export DOCKER_CONFIG="$(docker_data_dir)"
  sync_https_compose_profile
  local profile_args=(--profile migrate)
  local profiles tok
  profiles="$(compose_profiles_get)"
  if [[ -n "$profiles" ]]; then
    export COMPOSE_PROFILES="$profiles"
    IFS=',' read -ra _profile_toks <<< "$profiles"
    for tok in "${_profile_toks[@]}"; do
      tok="$(echo "$tok" | tr -d '[:space:]')"
      [[ -n "$tok" && "$tok" != "migrate" ]] && profile_args+=(--profile "$tok")
    done
  fi
  docker compose "${profile_args[@]}" run --rm migrate
}

pg_public_table_count() {
  local user db
  user="$(pg_user)"
  db="$(pg_db)"
  compose exec -T postgres psql -U "$user" -d "$db" -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'" \
    2>/dev/null | tr -d '[:space:]'
}

pg_has_data() {
  local n
  n="$(pg_public_table_count)"
  [[ -n "$n" && "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]]
}

find_dump_file() {
  local root="$1" f
  if [[ -f "$root/frvrsd.dump" ]]; then
    echo "$root/frvrsd.dump"
    return 0
  fi
  if [[ -f "$root/data/frvrsd.dump" ]]; then
    echo "$root/data/frvrsd.dump"
    return 0
  fi
  f="$(find "$root" -maxdepth 3 -type f -name '*.dump' 2>/dev/null | head -n 1 || true)"
  [[ -n "$f" ]] || return 1
  echo "$f"
}

pg_dump_to_file() {
  local out="$1"
  local user db
  user="$(pg_user)"
  db="$(pg_db)"
  compose exec -T postgres pg_dump -Fc -U "$user" "$db" >"$out"
}

pg_restore_from_file() {
  local dump="$1"
  local user db
  user="$(pg_user)"
  db="$(pg_db)"
  # Custom-format dump via stdin; --clean drops objects before recreate
  compose exec -T postgres pg_restore -U "$user" -d "$db" \
    --clean --if-exists --no-owner --no-acl <"$dump"
}

backup_data() {
  local with_tar="${1:-0}" stop_first="${2:-1}"
  local ts bkp archive was_running=0

  mkdir -p data
  ensure_postgres_up || {
    yellow "$(i18n backup_no_db)"
    return 1
  }

  if [[ "$stop_first" -eq 1 ]] && services_running; then
    was_running=1
    cyan "$(i18n backup_stopping)"
    compose stop bot miniapp 2>/dev/null || true
  fi

  ts="$(date +%F-%H%M%S)"
  bkp="data/backup-${ts}"
  mkdir -p "$bkp"
  if ! pg_dump_to_file "$bkp/frvrsd.dump"; then
    red "$(i18n backup_no_db)"
    [[ "$was_running" -eq 1 ]] && restart_app_services
    return 1
  fi
  [[ -f .env ]] && cp -a .env "$bkp/.env"
  green "$(i18n backup_done) ${bkp}/frvrsd.dump"

  if [[ "$with_tar" -eq 1 ]]; then
    archive="frvrsd-backup-${ts}.tar.gz"
    tar czf "$archive" -C "$bkp" frvrsd.dump .env 2>/dev/null \
      || tar czf "$archive" -C "$bkp" frvrsd.dump
    green "$(i18n backup_archive) ${archive}"
  fi

  if [[ "$was_running" -eq 1 ]]; then
    restart_app_services
  fi
}

import_data_from_path() {
  local src="$1"
  local stop_first="${2:-1}"
  local was_running=0 tmp_dir member dump="" ans

  [[ -n "$src" && -e "$src" ]] || {
    red "$(i18n import_not_found) ${src:-<empty>}"
    return 1
  }

  ensure_postgres_up || return 1

  if pg_has_data; then
    yellow "$(i18n import_overwrite_warn)"
    printf "%s [y/N]: " "$(i18n prompt_yes_no)"
    read -r ans
    if [[ ! "$ans" =~ ^[yY] ]]; then
      return 0
    fi
    backup_data 0 1 || true
  fi

  if [[ "$stop_first" -eq 1 ]] && services_running; then
    was_running=1
    compose stop bot miniapp 2>/dev/null || true
  fi

  mkdir -p data

  if [[ -f "$src" && ( "$src" == *.tar.gz || "$src" == *.tgz ) ]]; then
    while IFS= read -r member; do
      case "$member" in
        /*|*../*|*/../*|*/..|..)
          red "Unsafe path in archive: $member"
          [[ "$was_running" -eq 1 ]] && restart_app_services
          return 1
          ;;
      esac
    done < <(tar tzf "$src" 2>/dev/null || true)

    tmp_dir="$(mktemp -d)"
    if ! tar xzf "$src" -C "$tmp_dir"; then
      rm -rf "$tmp_dir"
      [[ "$was_running" -eq 1 ]] && restart_app_services
      return 1
    fi
    dump="$(find_dump_file "$tmp_dir" || true)"
    if [[ -z "$dump" ]]; then
      rm -rf "$tmp_dir"
      red "$(i18n import_not_found) *.dump in archive"
      [[ "$was_running" -eq 1 ]] && restart_app_services
      return 1
    fi
    if [[ -f "$tmp_dir/.env" && ! -f .env ]]; then
      cp -a "$tmp_dir/.env" .env
      secure_env_file
      ensure_db_credentials
    fi
    if ! pg_restore_from_file "$dump"; then
      rm -rf "$tmp_dir"
      red "$(i18n import_not_found) pg_restore failed"
      [[ "$was_running" -eq 1 ]] && restart_app_services
      return 1
    fi
    rm -rf "$tmp_dir"
  elif [[ -f "$src" && ( "$src" == *.dump || "$(basename "$src")" == "frvrsd.dump" ) ]]; then
    if ! pg_restore_from_file "$src"; then
      red "$(i18n import_not_found) pg_restore failed"
      [[ "$was_running" -eq 1 ]] && restart_app_services
      return 1
    fi
  elif [[ -d "$src" ]]; then
    dump="$(find_dump_file "$src" || true)"
    if [[ -z "$dump" ]]; then
      red "$(i18n import_not_found) $src/*.dump"
      [[ "$was_running" -eq 1 ]] && restart_app_services
      return 1
    fi
    if [[ -f "$src/.env" && ! -f .env ]]; then
      cp -a "$src/.env" .env
      secure_env_file
      ensure_db_credentials
    elif [[ -f "$src/../.env" && ! -f .env ]]; then
      cp -a "$src/../.env" .env
      secure_env_file
      ensure_db_credentials
    fi
    if ! pg_restore_from_file "$dump"; then
      red "$(i18n import_not_found) pg_restore failed"
      [[ "$was_running" -eq 1 ]] && restart_app_services
      return 1
    fi
  else
    red "$(i18n import_not_found) $src"
    [[ "$was_running" -eq 1 ]] && restart_app_services
    return 1
  fi

  green "$(i18n import_done)"
  if [[ "$was_running" -eq 1 ]]; then
    restart_app_services
  fi
  return 0
}

prepare_data() {
  local skip_interactive="${1:-0}"
  local src ans

  mkdir -p data

  if postgres_running && pg_has_data; then
    if [[ "$skip_interactive" -eq 0 && -t 0 ]]; then
      yellow "$(i18n db_exists_offer_backup)"
      printf "%s [y/N]: " "$(i18n prompt_yes_no)"
      read -r ans
      if [[ "$ans" =~ ^[yY] ]]; then
        backup_data 0 1
      fi
    fi
    return 0
  fi

  if [[ "$skip_interactive" -eq 1 || ! -t 0 ]]; then
    return 0
  fi

  cyan "$(i18n db_import_hint)"
  yellow "$(i18n db_import_examples)"
  printf "%s: " "$(i18n db_import_prompt)"
  read -r src
  if [[ -n "$src" ]]; then
    import_data_from_path "$src" 0
  fi
}

domain_from_url() {
  local url="${1%/}"
  url="${url#https://}"
  url="${url#http://}"
  url="${url%%/*}"
  echo "$url"
}

sync_mini_app_domain() {
  local url domain had_domain=""
  url="$(read_env_var MINI_APP_URL)"
  domain="$(read_env_var MINI_APP_DOMAIN)"
  [[ -n "$domain" ]] && had_domain=1
  if [[ -z "$domain" && -n "$url" ]]; then
    domain="$(domain_from_url "$url")"
  fi
  if [[ -n "$domain" ]]; then
    set_env_key "MINI_APP_DOMAIN" "$domain"
    export MINI_APP_DOMAIN="$domain"
    if [[ -z "$had_domain" ]]; then
      yellow "$(i18n set_domain)${domain}"
    fi
  fi
}

image_repository() {
  local ref="${1:-}"
  [[ -n "$ref" ]] || ref="$(current_image)"
  ref="${ref%%@*}"
  local name="${ref##*/}"
  if [[ "$name" == *:* ]]; then
    ref="${ref%:*}"
  fi
  printf '%s\n' "$ref"
}

is_semver_tag() {
  [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Newest x.y.z (or vx.y.z) tag on Docker Hub. Ignores dev/latest and pre-releases.
latest_semver_tag() {
  local repo="$1"
  local url="https://hub.docker.com/v2/repositories/${repo}/tags?page_size=100"
  local best="" name key best_key top next page=0 tmp
  tmp="$(mktemp)"
  while [[ -n "$url" && "$url" != "null" && "$page" -lt 20 ]]; do
    if ! curl -fsSL --max-time 20 "$url" -o "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      is_semver_tag "$name" || continue
      key="${name#v}"
      if [[ -z "$best" ]]; then
        best="$name"
        continue
      fi
      best_key="${best#v}"
      top="$(printf '%s\n%s\n' "$key" "$best_key" | sort -V | tail -n1)"
      if [[ "$top" == "$key" && "$key" != "$best_key" ]]; then
        best="$name"
      elif [[ "$key" == "$best_key" && "$name" != v* ]]; then
        best="$name"
      fi
    done < <(grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' "$tmp" \
      | sed -E 's/.*"([^"]+)"$/\1/' || true)
    next="$(grep -oE '"next"[[:space:]]*:[[:space:]]*("https:[^"]+"|null)' "$tmp" \
      | head -1 | sed -E 's/.*"next"[[:space:]]*:[[:space:]]*//; s/^"//; s/"$//' || true)"
    if [[ -z "$next" || "$next" == "null" ]]; then
      break
    fi
    url="$next"
    page=$((page + 1))
  done
  rm -f "$tmp"
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}

resolve_release_image() {
  local repo tag
  repo="$(image_repository)"
  if ! tag="$(latest_semver_tag "$repo")"; then
    red "$(i18n image_tags_failed) ${repo}" >&2
    return 1
  fi
  cyan "$(i18n image_resolved): ${repo}:${tag}" >&2
  printf '%s:%s\n' "$repo" "$tag"
}

current_image() {
  if [[ -n "${FRVRSD_IMAGE:-}" ]]; then
    echo "${FRVRSD_IMAGE}"
    return 0
  fi
  local img
  img="$(read_env_var FRVRSD_IMAGE)"
  echo "${img:-$DEFAULT_IMAGE}"
}

# ---------------------------------------------------------------------------
# Docker + host (UFW)
# ---------------------------------------------------------------------------
run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    red "$(i18n need_root)"
    exit 1
  fi
}

docker_ready() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

install_docker_engine() {
  cyan "$(i18n installing_docker)"
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL https://get.docker.com -o "$tmp"; then
    red "$(i18n docker_install_failed)"
    exit 1
  fi
  run_root sh "$tmp"
  rm -f "$tmp"
  if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    run_root usermod -aG docker "${SUDO_USER}" 2>/dev/null || true
    yellow "Added ${SUDO_USER} to group docker (re-login to skip sudo for compose)"
  fi
  if docker_ready; then
    green "$(i18n docker_ready)"
    return 0
  fi
  red "$(i18n docker_install_failed)"
  exit 1
}

detect_ssh_port() {
  local port=22
  if [[ -f /etc/ssh/sshd_config ]]; then
    port="$(awk '/^[[:space:]]*Port[[:space:]]+/ {print $2; exit}' /etc/ssh/sshd_config)"
    [[ -z "$port" ]] && port=22
  fi
  echo "$port"
}

setup_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      run_root apt-get update -qq
      run_root apt-get install -y ufw
    else
      yellow "$(i18n ufw_skip)"
      return 0
    fi
  fi
  cyan "$(i18n setting_ufw)"
  local ssh_port ok=0
  ssh_port="$(detect_ssh_port)"
  run_root ufw allow "${ssh_port}/tcp" comment 'SSH' && ok=1
  run_root ufw allow 80/tcp comment 'HTTP'
  run_root ufw allow 443/tcp comment 'HTTPS'
  if [[ "$ok" -eq 0 ]]; then
    red "$(i18n ufw_fail)"
    return 1
  fi
  if run_root ufw --force enable; then
    green "$(i18n ufw_done) (SSH ${ssh_port})"
  else
    red "$(i18n ufw_fail)"
    return 1
  fi
}

ensure_docker() {
  if ! docker_ready; then
    yellow "$(i18n missing_docker)"
    install_docker_engine
  fi
}

ensure_host_ready() {
  ensure_docker
  setup_ufw
}

need_docker() {
  ensure_docker
}

docker_cmd() {
  require_install_dir
  mkdir -p "$(docker_data_dir)"
  DOCKER_CONFIG="$(docker_data_dir)" docker "$@"
}

compose() {
  local domain
  require_install_dir
  mkdir -p "$(docker_data_dir)"
  export DOCKER_CONFIG="$(docker_data_dir)"
  # Compose substitutes ${MINI_APP_DOMAIN} from shell/.env — keep both in sync
  domain="$(read_env_var MINI_APP_DOMAIN)"
  if [[ -z "$domain" ]]; then
    domain="$(domain_from_url "$(read_env_var MINI_APP_URL)")"
  fi
  if [[ -n "$domain" ]]; then
    export MINI_APP_DOMAIN="$domain"
  fi
  # Heal HTTPS flag before sync (sync would strip COMPOSE_PROFILES if flag is 0)
  reconcile_https_flag
  # COMPOSE_PROFILES in .env + export so optional services appear for bare docker compose
  sync_https_compose_profile
  local profiles profile_args=()
  profiles="$(compose_profiles_get)"
  if [[ -n "$profiles" ]]; then
    export COMPOSE_PROFILES="$profiles"
    local tok
    IFS=',' read -ra _profile_toks <<< "$profiles"
    for tok in "${_profile_toks[@]}"; do
      tok="$(echo "$tok" | tr -d '[:space:]')"
      [[ -n "$tok" ]] && profile_args+=(--profile "$tok")
    done
    docker compose "${profile_args[@]}" "$@"
  else
    unset COMPOSE_PROFILES || true
    docker compose "$@"
  fi
}

# Comma-separated COMPOSE_PROFILES helpers (https + xray-checker, …).
compose_profiles_get() {
  local raw
  raw="$(read_env_var COMPOSE_PROFILES 2>/dev/null || true)"
  echo "$raw" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk 'NF' | paste -sd, -
}

compose_profiles_write() {
  local joined="$1"
  if [[ -n "$joined" ]]; then
    set_env_key "COMPOSE_PROFILES" "$joined"
    export COMPOSE_PROFILES="$joined"
  else
    if grep -qE '^COMPOSE_PROFILES=' .env 2>/dev/null; then
      sed_inplace '/^COMPOSE_PROFILES=/d' .env
    fi
    unset COMPOSE_PROFILES || true
  fi
}

compose_profiles_has() {
  local needle="$1" tok
  IFS=',' read -ra _toks <<< "$(compose_profiles_get)"
  for tok in "${_toks[@]}"; do
    tok="$(echo "$tok" | tr -d '[:space:]')"
    [[ "$tok" == "$needle" ]] && return 0
  done
  return 1
}

compose_profiles_add() {
  local token="$1" out=() tok
  IFS=',' read -ra _toks <<< "$(compose_profiles_get)"
  for tok in "${_toks[@]}"; do
    tok="$(echo "$tok" | tr -d '[:space:]')"
    [[ -n "$tok" && "$tok" != "$token" ]] && out+=("$tok")
  done
  out+=("$token")
  local IFS=,
  compose_profiles_write "${out[*]}"
}

compose_profiles_remove() {
  local token="$1" out=() tok
  IFS=',' read -ra _toks <<< "$(compose_profiles_get)"
  for tok in "${_toks[@]}"; do
    tok="$(echo "$tok" | tr -d '[:space:]')"
    [[ -n "$tok" && "$tok" != "$token" ]] && out+=("$tok")
  done
  local IFS=,
  compose_profiles_write "${out[*]-}"
}

sync_https_compose_profile() {
  if [[ "${FRVRSD_HTTPS}" == "1" ]]; then
    compose_profiles_add https
  else
    compose_profiles_remove https
  fi
}

prepare_deploy_files() {
  for f in docker-compose.yml .env.example; do
    if [[ ! -f "$f" ]]; then
      red "$(i18n missing_files) $(pwd)"
      exit 1
    fi
  done
  mkdir -p data deploy
}

prepare_env() {
  local image="${1:-$(current_image)}"
  local skip_interactive="${2:-0}"

  [[ -f .env ]] || cp .env.example .env
  set_env_key "FRVRSD_IMAGE" "$image"
  ensure_db_credentials

  if [[ "$skip_interactive" -eq 0 ]]; then
    interactive_env_setup
  else
    secure_env_file
    sync_mini_app_domain
    validate_env_required
  fi
}

validate_https() {
  if [[ "${FRVRSD_HTTPS}" != "1" ]]; then
    return 0
  fi
  local domain
  sync_mini_app_domain
  domain="$(read_env_var MINI_APP_DOMAIN)"
  [[ -n "$domain" ]] || domain="$(domain_from_url "$(read_env_var MINI_APP_URL)")"
  if [[ -z "$domain" ]]; then
    red "$(i18n need_domain)"
    exit 1
  fi
  set_env_key "MINI_APP_DOMAIN" "$domain"
  export MINI_APP_DOMAIN="$domain"
  secure_env_file
  [[ -f deploy/Caddyfile ]] || { red "$(i18n missing_caddy)"; exit 1; }
}

pull_image() {
  local image="${1:-$(current_image)}"
  cyan "$(i18n pulling): ${image}"
  export FRVRSD_IMAGE="$image"
  set_env_key "FRVRSD_IMAGE" "$image"
  secure_env_file
  if ! docker_cmd pull "$image"; then
    red "$(i18n pull_failed)"
    exit 1
  fi
}

wait_health() {
  cyan "$(i18n waiting_ready)..."
  local ok=0 i
  for i in $(seq 1 45); do
    if curl -sf "http://127.0.0.1:8080/ready" >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 2
  done
  if [[ "$ok" -eq 1 ]]; then
    green "$(i18n ready_ok) (http://127.0.0.1:8080/ready)"
    return 0
  fi
  yellow "$(i18n ready_fail)"
  return 1
}

print_next_steps() {
  local base image
  base="$(read_env_var MINI_APP_URL)"
  [[ -n "$base" ]] || base="https://YOUR_DOMAIN"
  image="$(current_image)"
  echo ""
  bold "$(i18n next_steps)"
  blue "  1. $(i18n step_botfather) ${base}"
  blue "  2. $(i18n step_platega) ${base}/api/payments/callback/platega"
  blue "  3. $(i18n step_admin)"
  if [[ "$image" == *:latest || "$image" == *"/latest" || "$image" != *:* ]]; then
    yellow "  4. $(i18n step_pin_image)"
  fi
  if [[ "${FRVRSD_HTTPS}" != "1" ]]; then
    yellow "$(i18n https_hint)"
  fi
}

print_status_line() {
  local https_val xray_val lang_val cli_color="$C_GREEN"

  reconcile_https_flag 2>/dev/null || true

  if [[ -n "$CLI_UPDATE_AVAILABLE" ]]; then
    cli_color="$C_YELLOW"
  fi

  echo ""
  status_kv "$(i18n current_dir)" "${INSTALL_DIR:-—}" "$C_BLUE"
  status_kv "$(i18n current_image)" "$(current_image)" "$C_CYAN"
  if [[ "${FRVRSD_HTTPS}" == "1" ]]; then
    https_val="$(i18n yes)"
    status_kv "$(i18n current_https)" "$https_val" "$C_GREEN"
  else
    https_val="$(i18n no)"
    status_kv "$(i18n current_https)" "$https_val" "$C_DIM"
  fi
  if resolve_install_dir 2>/dev/null && [[ -f .env ]] && compose_profiles_has xray-checker 2>/dev/null; then
    xray_val="$(i18n yes)"
    status_kv "$(i18n current_xray)" "$xray_val" "$C_GREEN"
  else
    xray_val="$(i18n no)"
    status_kv "$(i18n current_xray)" "$xray_val" "$C_DIM"
  fi
  if [[ "${FRVRSD_LANG}" == "en" ]]; then
    lang_val="English"
  else
    lang_val="Русский"
  fi
  status_kv "$(i18n current_lang)" "$lang_val" "$C_MAGENTA"
  if [[ -n "$CLI_REMOTE_VERSION" && -n "$CLI_UPDATE_AVAILABLE" ]]; then
    status_kv "$(i18n current_cli_version)" "${INSTALLER_VERSION} → ${CLI_REMOTE_VERSION}" "$cli_color"
  else
    status_kv "$(i18n current_cli_version)" "${INSTALLER_VERSION}" "$cli_color"
  fi
  if [[ -n "$CLI_UPDATE_AVAILABLE" ]]; then
    yellow "  ↑ $(i18n version_available) → $(i18n menu_self_update) (20)"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_bootstrap() {
  ensure_host_ready
  green "$(i18n docker_ready)"
}

cmd_install() {
  local skip_pause=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --https) FRVRSD_HTTPS=1; shift ;;
      -y|--yes) skip_pause=1; shift ;;
      *) shift ;;
    esac
  done

  ensure_host_ready
  require_install_dir
  prepare_deploy_files
  local image
  image="$(resolve_release_image)" || exit 1
  prepare_env "$image" "$skip_pause"
  validate_https
  sync_https_compose_profile
  pull_image "$image"
  save_config

  cyan "$(i18n starting)..."
  ensure_postgres_up || exit 1
  prepare_data "$skip_pause"
  compose_migrate || exit 1
  compose up -d --remove-orphans
  wait_health || exit 1
  compose ps
  print_next_steps
}

cmd_update() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --https) FRVRSD_HTTPS=1; shift ;;
      --no-https)
        FRVRSD_HTTPS=0
        FRVRSD_HTTPS_SKIP_RECONCILE=1
        shift
        ;;
      *) shift ;;
    esac
  done

  need_docker
  require_install_dir
  prepare_deploy_files
  [[ -f .env ]] || { red "$(i18n no_env)"; exit 1; }
  ensure_db_credentials
  validate_https
  sync_https_compose_profile
  local image
  image="$(resolve_release_image)" || exit 1
  pull_image "$image"
  save_config
  ensure_postgres_up || exit 1
  compose_migrate || exit 1
  compose up -d --remove-orphans
  wait_health || exit 1
  compose ps
  green "$(i18n updated)"
}

cmd_pull() {
  need_docker
  require_install_dir
  [[ -f .env ]] || cp .env.example .env
  local image
  image="$(resolve_release_image)" || exit 1
  pull_image "$image"
}

cmd_start() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --https) FRVRSD_HTTPS=1; shift ;;
      *) shift ;;
    esac
  done
  need_docker
  require_install_dir
  ensure_db_credentials
  validate_https
  sync_https_compose_profile
  save_config
  ensure_postgres_up || exit 1
  compose_migrate || exit 1
  compose up -d --remove-orphans
  compose ps
}

cmd_stop() {
  need_docker
  require_install_dir
  compose down
  green "$(i18n stopped)"
}

cmd_restart() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --https) FRVRSD_HTTPS=1; shift ;;
      *) shift ;;
    esac
  done
  need_docker
  require_install_dir
  validate_https
  sync_https_compose_profile
  save_config
  # up -d creates newly enabled caddy; restart alone would not
  compose up -d --remove-orphans
  compose restart
  wait_health || true
  compose ps
}

cmd_status() {
  need_docker
  require_install_dir
  print_status_line
  compose ps
}

cmd_health() {
  require_install_dir
  if curl -sf "http://127.0.0.1:8080/ready"; then
    echo ""
    green "$(i18n ready_ok)"
  else
    red "$(i18n ready_fail)"
    exit 1
  fi
}

cmd_logs() {
  local target="${1:-}"
  need_docker
  require_install_dir

  case "$target" in
    bot)     compose logs -f --tail=100 bot ;;
    miniapp|"") compose logs -f --tail=100 miniapp ;;
    caddy)   compose logs -f --tail=100 caddy ;;
    xray-checker|xray|checker) compose logs -f --tail=100 xray-checker ;;
    all)     compose logs -f --tail=80 ;;
    *)
      yellow "$(i18n logs_which)"
      read -r target
      cmd_logs "$target"
      ;;
  esac
}

cmd_env_setup() {
  require_install_dir
  interactive_env_setup
}

cmd_backup() {
  require_install_dir
  local make_tar=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tar) make_tar=1; shift ;;
      *) shift ;;
    esac
  done
  if [[ "$make_tar" -eq 0 && -t 0 && -z "${FRVRSD_MENU:-}" ]]; then
    printf "%s [y/N]: " "$(i18n backup_tar_prompt)"
    read -r ans
    [[ "$ans" =~ ^[yY] ]] && make_tar=1
  fi
  backup_data "$make_tar" 1
}

cmd_import() {
  require_install_dir
  local src="${1:-}"
  if [[ -z "$src" && -t 0 ]]; then
    cyan "$(i18n db_import_hint)"
    yellow "$(i18n db_import_examples)"
    printf "%s: " "$(i18n db_import_prompt)"
    read -r src
  fi
  [[ -n "$src" ]] || return 0
  import_data_from_path "$src" 1
}

cmd_edit_env() {
  require_install_dir
  [[ -f .env ]] || cp .env.example .env
  local ed="${EDITOR:-}"
  if [[ -z "$ed" ]]; then
    if command -v nano >/dev/null 2>&1; then ed=nano
    elif command -v vi >/dev/null 2>&1; then ed=vi
    else red "$(i18n no_editor)"; exit 1
    fi
  fi
  "$ed" .env
}

cmd_set_lang() {
  local lang="${1:-}"
  case "$lang" in
    ru) FRVRSD_LANG=ru; green "$(i18n lang_set_ru)" ;;
    en) FRVRSD_LANG=en; green "$(i18n lang_set_en)" ;;
    *)
      echo "1) Русский  2) English"
      read -r lang
      case "$lang" in
        1|ru) FRVRSD_LANG=ru; green "$(i18n lang_set_ru)" ;;
        2|en) FRVRSD_LANG=en; green "$(i18n lang_set_en)" ;;
        *) red "$(i18n invalid_choice)"; return 1 ;;
      esac
      ;;
  esac
  if [[ -n "${INSTALL_DIR}" ]]; then
    save_config
  else
    mkdir -p "$CONFIG_DIR"
    save_config
  fi
}

cmd_https_on() {
  FRVRSD_HTTPS=1
  require_install_dir
  need_docker
  prepare_deploy_files
  [[ -f deploy/Caddyfile ]] || { red "$(i18n missing_caddy)"; exit 1; }
  sync_mini_app_domain
  validate_https
  sync_https_compose_profile
  save_config
  cyan "$(i18n pulling): caddy:2.9-alpine"
  docker_cmd pull caddy:2.9-alpine || true
  cyan "$(i18n starting)... (profile https → caddy)"
  compose up -d --remove-orphans
  # Explicitly ensure caddy is in the project (profile must be active)
  compose up -d caddy
  wait_health || true
  if ! compose ps --status running -q caddy 2>/dev/null | grep -q .; then
    red "Caddy не запущен. Логи:"
    compose logs --tail=80 caddy || true
    yellow "Проверьте: MINI_APP_DOMAIN, порты 80/443, DNS → этот сервер"
    yellow "Ручной запуск: cd ${INSTALL_DIR} && docker compose --profile https up -d caddy"
    exit 1
  fi
  compose ps
  green "$(i18n https_enabled)"
  green "Caddy → https://${MINI_APP_DOMAIN}"
}

cmd_https_off() {
  FRVRSD_HTTPS=0
  FRVRSD_HTTPS_SKIP_RECONCILE=1
  if resolve_install_dir 2>/dev/null; then
    sync_https_compose_profile
    save_config
    if docker_ready; then
      mkdir -p "$(docker_data_dir)"
      export DOCKER_CONFIG="$(docker_data_dir)"
      docker compose --profile https stop caddy 2>/dev/null || true
      docker compose --profile https rm -f caddy 2>/dev/null || true
    fi
  fi
  green "$(i18n https_disabled)"
}

ensure_xray_checker_auth() {
  local user pass
  user="$(read_env_var XRAY_CHECKER_USERNAME 2>/dev/null || true)"
  pass="$(read_env_var XRAY_CHECKER_PASSWORD 2>/dev/null || true)"
  if [[ -z "$user" ]]; then
    set_env_key "XRAY_CHECKER_USERNAME" "checker"
  fi
  if [[ -z "$pass" ]]; then
    set_env_key "XRAY_CHECKER_PASSWORD" "$(gen_db_secret)"
  fi
  set_env_key "XRAY_CHECKER_METRICS_PROTECTED" "true"
}

cmd_xray_checker_on() {
  require_install_dir
  need_docker
  prepare_deploy_files
  local sub
  sub="$(read_env_var XRAY_CHECKER_SUBSCRIPTION_URL 2>/dev/null || true)"
  if [[ -z "$sub" ]]; then
    red "$(i18n xray_need_url)"
    exit 1
  fi
  ensure_xray_checker_auth
  compose_profiles_add xray-checker
  cyan "$(i18n pulling): ${XRAY_CHECKER_IMAGE}"
  docker_cmd pull "$XRAY_CHECKER_IMAGE" || true
  compose up -d --remove-orphans
  compose up -d xray-checker
  green "$(i18n xray_enabled)"
}

cmd_xray_checker_off() {
  require_install_dir
  compose_profiles_remove xray-checker
  if docker_ready; then
    mkdir -p "$(docker_data_dir)"
    export DOCKER_CONFIG="$(docker_data_dir)"
    docker compose --profile xray-checker stop xray-checker 2>/dev/null || true
    docker compose --profile xray-checker rm -f xray-checker 2>/dev/null || true
  fi
  green "$(i18n xray_disabled)"
}

install_cli_command() {
  local source_script="$1"
  local install_dir="$2"
  local quiet="${3:-0}"
  local bindir="" target="" dest=""

  [[ -f "$source_script" ]] || source_script="${install_dir}/install.sh"
  dest="${install_dir}/bin/${CLI_NAME}"

  if [[ "${EUID}" -eq 0 ]] || [[ -w /usr/local/bin ]]; then
    bindir="/usr/local/bin"
  elif command -v sudo >/dev/null 2>&1 && sudo -n test -w /usr/local/bin 2>/dev/null; then
    bindir="/usr/local/bin"
  else
    bindir="${HOME}/.local/bin"
    mkdir -p "$bindir"
  fi
  target="${bindir}/${CLI_NAME}"

  mkdir -p "${install_dir}/bin"
  if same_path "$source_script" "$dest"; then
    chmod +x "$dest"
  else
    cp -f "$source_script" "$dest"
    chmod +x "$dest"
  fi

  if [[ -w "$bindir" ]]; then
    ln -sf "${install_dir}/bin/${CLI_NAME}" "$target"
  else
    run_root ln -sf "${install_dir}/bin/${CLI_NAME}" "$target"
  fi

  INSTALL_DIR="$install_dir"
  SCRIPT_PATH="${install_dir}/bin/${CLI_NAME}"
  if [[ "$quiet" -eq 0 ]]; then
    save_config
    green "$(i18n cli_installed) ${target}"
    green "  ${CLI_NAME} menu"
    green "  ${CLI_NAME} update"
    if [[ "$bindir" == "${HOME}/.local/bin" ]]; then
      yellow "$(i18n cli_path_hint) export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
  else
    write_config_file
  fi
}

ensure_cli_installed() {
  # Do not reinstall/copy on every frvrsd invocation — only fix missing binary/symlink
  [[ -n "${INSTALL_DIR}" ]] || return 0
  local dest="${INSTALL_DIR}/bin/${CLI_NAME}"
  local src="${INSTALL_DIR}/install.sh"
  local link="/usr/local/bin/${CLI_NAME}"
  local need=0

  [[ -f "$src" ]] || return 0

  if [[ ! -x "$dest" ]]; then
    need=1
  fi
  if [[ ! -e "$link" && ! -e "${HOME}/.local/bin/${CLI_NAME}" ]]; then
    need=1
  fi
  [[ "$need" -eq 1 ]] || return 0

  if [[ -x "$dest" ]]; then
    src="$dest"
  fi
  install_cli_command "$src" "${INSTALL_DIR}" 1
}

cmd_setup_cli() {
  if ! resolve_install_dir 2>/dev/null; then
    red "$(i18n missing_install)"
    exit 1
  fi
  install_cli_command "${INSTALL_DIR}/install.sh" "${INSTALL_DIR}"
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
show_menu() {
  init_colors
  clear 2>/dev/null || true
  printf '%s=== %s — %s ===%s\n' "$C_BOLD$C_CYAN" "$(i18n app_title)" "$(i18n menu_title)" "$C_RESET"
  print_status_line
  menu_section "$(i18n menu_section_ops)"
  menu_item 1 "$(i18n menu_install)"
  menu_item 2 "$(i18n menu_update)"
  menu_item 3 "$(i18n menu_start)"
  menu_item 4 "$(i18n menu_stop)"
  menu_item 5 "$(i18n menu_restart)"
  menu_item 6 "$(i18n menu_status)"
  menu_item 7 "$(i18n menu_health)"
  menu_item 8 "$(i18n menu_logs)"
  menu_section "$(i18n menu_section_cfg)"
  menu_item 9 "$(i18n menu_env_setup)"
  menu_item 10 "$(i18n menu_env_editor)"
  if [[ "${FRVRSD_HTTPS}" == "1" ]]; then
    menu_item 11 "$(i18n menu_https_off)"
  else
    menu_item 11 "$(i18n menu_https_on)"
  fi
  if compose_profiles_has xray-checker 2>/dev/null; then
    menu_item 12 "$(i18n menu_xray_off)"
  else
    menu_item 12 "$(i18n menu_xray_on)"
  fi
  menu_section "$(i18n menu_section_sys)"
  menu_item 13 "$(i18n menu_setup_cli)"
  menu_item 14 "$(i18n menu_lang)"
  menu_item 15 "$(i18n menu_bootstrap)"
  menu_item 16 "$(i18n menu_init)"
  menu_item 17 "$(i18n menu_backup)"
  menu_item 18 "$(i18n menu_import)"
  menu_section "$(i18n menu_section_cli)"
  menu_item 19 "$(i18n menu_check_update)"
  menu_item 20 "$(i18n menu_self_update)" "${CLI_UPDATE_AVAILABLE:-0}"
  menu_item 0 "$(i18n menu_exit)"
  echo ""
  printf '%s%s:%s ' "$C_CYAN" "$(i18n prompt_choice)" "$C_RESET"
}

run_menu_action() {
  local rc=0
  (
    FRVRSD_MENU=1
    "$@"
  ) || rc=$?
  if [[ $rc -ne 0 ]]; then
    red "$(i18n menu_action_failed) ($rc)"
  fi
  # Reload persisted state (HTTPS/lang/dir) written inside the subshell
  load_config
  resolve_install_dir 2>/dev/null || true
  pause
}

run_menu() {
  load_config
  resolve_install_dir 2>/dev/null || true
  refresh_cli_update_hint

  while true; do
    show_menu
    read -r choice
    case "$choice" in
      1) run_menu_action cmd_install ;;
      2) run_menu_action cmd_update ;;
      3) run_menu_action cmd_start ;;
      4) run_menu_action cmd_stop ;;
      5) run_menu_action cmd_restart ;;
      6) run_menu_action cmd_status ;;
      7) run_menu_action cmd_health ;;
      8) run_menu_action cmd_logs ;;
      9) run_menu_action cmd_env_setup ;;
      10) run_menu_action cmd_edit_env ;;
      11)
        if [[ "${FRVRSD_HTTPS}" == "1" ]]; then
          run_menu_action cmd_https_off
        else
          run_menu_action cmd_https_on
        fi
        ;;
      12)
        if compose_profiles_has xray-checker 2>/dev/null; then
          run_menu_action cmd_xray_checker_off
        else
          run_menu_action cmd_xray_checker_on
        fi
        ;;
      13) run_menu_action cmd_setup_cli ;;
      14) run_menu_action cmd_set_lang ;;
      15) run_menu_action cmd_bootstrap ;;
      16) run_menu_action cmd_init ;;
      17) run_menu_action cmd_backup ;;
      18) run_menu_action cmd_import ;;
      19) run_menu_action cmd_version --check; refresh_cli_update_hint ;;
      20)
        # Must not run in a subshell: self-update exec's the new binary
        FRVRSD_SELF_UPDATE_REEXEC_MENU=1
        if ! cmd_self_update; then
          red "$(i18n menu_action_failed)"
          pause
        fi
        # If exec did not replace us (NO_REEXEC / failure path):
        load_config
        resolve_install_dir 2>/dev/null || true
        refresh_cli_update_hint
        pause
        ;;
      0|q|Q) exit 0 ;;
      *) red "$(i18n invalid_choice)"; sleep 1 ;;
    esac
  done
}

usage() {
  echo "$(i18n usage_header)"
  echo "$(i18n cmd_install)"
  echo "$(i18n cmd_update)"
  echo "$(i18n cmd_pull)"
  echo "$(i18n cmd_start)"
  echo "$(i18n cmd_stop)"
  echo "$(i18n cmd_restart)"
  echo "$(i18n cmd_status)"
  echo "$(i18n cmd_health)"
  echo "$(i18n cmd_logs)"
  echo "$(i18n cmd_xray_on)"
  echo "$(i18n cmd_xray_off)"
  echo "$(i18n cmd_setup)"
  echo "$(i18n cmd_lang)"
  echo "$(i18n cmd_env)"
  echo "$(i18n cmd_backup)"
  echo "$(i18n cmd_import)"
  echo "$(i18n cmd_bootstrap)"
  echo "$(i18n cmd_init)"
  echo "$(i18n cmd_version)"
  echo "$(i18n cmd_self_update)"
  echo "$(i18n cmd_menu)"
}

# ---------------------------------------------------------------------------
# Main — legacy flags + subcommands
# ---------------------------------------------------------------------------
is_subcommand() {
  case "$1" in
    install|update|upgrade|pull|start|up|stop|down|restart|status|ps|health|logs|edit-env|env|setup-env|backup|import|setup|setup-cli|lang|language|menu|bootstrap|init|version|self-update|update-cli|xray-checker|help)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

main() {
  load_config

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  # help/init-only: init skips full layout when explicitly requested
  if [[ "${1:-}" == "init" ]]; then
    shift
    cmd_init "${1:-${FRVRSD_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}}"
    exit 0
  fi

  if [[ "${1:-}" != "help" ]]; then
    ensure_deploy_layout
  fi

  if [[ $# -eq 0 ]]; then
    run_menu
    exit 0
  fi

  # Legacy: ./install.sh [--with-https] [--pull-only] [-y]
  if ! is_subcommand "$1"; then
    local legacy_https=0 legacy_pull=0 legacy_yes=0
    local arg
    for arg in "$@"; do
      case "$arg" in
        --with-https) legacy_https=1 ;;
        --pull-only)  legacy_pull=1 ;;
        -y|--yes)     legacy_yes=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)
          red "Unknown option: $arg"
          usage
          exit 1
          ;;
      esac
    done
    FRVRSD_HTTPS=$legacy_https
    if [[ $legacy_pull -eq 1 ]]; then
      cmd_pull
      exit 0
    fi
    if [[ $legacy_yes -eq 1 ]]; then
      cmd_install -y $([[ $legacy_https -eq 1 ]] && echo --https)
    else
      cmd_install $([[ $legacy_https -eq 1 ]] && echo --https)
    fi
    exit 0
  fi

  local cmd="$1"
  shift
  case "$cmd" in
    install)         cmd_install "$@" ;;
    update|upgrade)  cmd_update "$@" ;;
    pull)            cmd_pull ;;
    start|up)        cmd_start "$@" ;;
    stop|down)       cmd_stop ;;
    restart)         cmd_restart "$@" ;;
    status|ps)       cmd_status ;;
    health)          cmd_health ;;
    logs)            cmd_logs "${1:-miniapp}" ;;
    xray-checker)
      case "${1:-}" in
        on|enable|1)  cmd_xray_checker_on ;;
        off|disable|0) cmd_xray_checker_off ;;
        *)
          red "Usage: frvrsd xray-checker on|off"
          exit 1
          ;;
      esac
      ;;
    edit-env)        cmd_edit_env ;;
    env|setup-env)   cmd_env_setup ;;
    backup)          cmd_backup "$@" ;;
    import)          cmd_import "$@" ;;
    setup|setup-cli) cmd_setup_cli ;;
    lang|language)   cmd_set_lang "${1:-}" ;;
    bootstrap)       cmd_bootstrap ;;
    init)            cmd_init "${1:-}" ;;
    version)         cmd_version "$@" ;;
    self-update|update-cli) cmd_self_update "$@" ;;
    menu)            run_menu ;;
    help)            usage ;;
    *)
      red "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
