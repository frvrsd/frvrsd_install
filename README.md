# frvrsd_install

Публичный пакет установки FRVRSD VPN: CLI `frvrsd`, Docker Compose, Caddyfile и `.env.example`.
Исходники бота сюда не входят. Образ `frvrsd/frvrsd_vpn_bot` тянется с Docker Hub.

Репозиторий открыт, чтобы установку можно было скачать без токена.
Копировать и распространять файлы нельзя: [LICENSE](LICENSE).

```bash
curl -fsSL -o install.sh \
  https://raw.githubusercontent.com/frvrsd/frvrsd_install/1.7.1/install.sh
chmod +x install.sh && ./install.sh
```

Дальше: `sudo ./install.sh bootstrap`, затем `frvrsd install --https -y`.
Подробности — [DEPLOY.md](DEPLOY.md).

`init` и `self-update` сами скачивают compose, Caddyfile и `.env.example` с последнего semver-тега. GitHub-токен не нужен.

## Релиз CLI

Новая версия CLI — это git-тег `X.Y.Z` без префикса `v`. Номер тега совпадает с `INSTALLER_VERSION` в `install.sh`.

Коммит без такого тега покупателям не отдаётся.

```bash
# в install.sh: INSTALLER_VERSION="1.7.0"
git tag 1.7.0
git push origin 1.7.0
```
