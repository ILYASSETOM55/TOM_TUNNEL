#!/bin/bash
set -euo pipefail

BOT_DIR="/etc/tom_tunnel_bot"
SERVICE_NAME="tom_tunnel_bot.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
REPO_URL="https://github.com/ILYASSETOM55/TOM_TUNNEL.git"
CORE_DIR="tom_tunnel_core_bot"

if [[ $EUID -ne 0 ]]; then echo "[ERREUR] Lancez ce script en root."; exit 1; fi

read -r -p "Token Telegram : " BOT_TOKEN
read -r -p "ID Telegram Super Admin : " ADMIN_ID
[[ -n "$BOT_TOKEN" && "$ADMIN_ID" =~ ^-?[0-9]+$ ]] || { echo "[ERREUR] Token ou ID invalide."; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-pip git
python3 -m pip install --break-system-packages -r <(printf 'pyTelegramBotAPI>=4.29,<5\npsutil>=5.9,<7\n')

mkdir -p "$BOT_DIR"
chmod 700 "$BOT_DIR"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
git clone --depth 1 "$REPO_URL" "$TMP_DIR/repo"
[[ -d "$TMP_DIR/repo/$CORE_DIR" ]] || { echo "[ERREUR] $CORE_DIR absent."; exit 1; }

cat > "$BOT_DIR/config.json" <<JSON
{
  "bot_token": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$BOT_TOKEN"),
  "super_admin": $ADMIN_ID,
  "admins": [],
  "super_admins": []
}
JSON
chmod 600 "$BOT_DIR/config.json"

rm -rf "$BOT_DIR/modules"
cp -a "$TMP_DIR/repo/$CORE_DIR/." "$BOT_DIR/"

python3 -m py_compile "$BOT_DIR/tom_tunnel_bot.py" "$BOT_DIR/modules/"*.py

cat > "$SERVICE_FILE" <<UNIT
[Unit]
Description=TOM_TUNNEL Telegram Bot C2
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
ExecStart=/usr/bin/python3 $BOT_DIR/tom_tunnel_bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
sleep 2
systemctl --no-pager --full status "$SERVICE_NAME" || true

echo
echo "[OK] TOM_TUNNEL BOT installé et démarré."
echo "[INFO] Testez avec /start sur Telegram."
