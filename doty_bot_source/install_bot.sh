#!/bin/bash

clear

# ==========================================================
# TOM_TUNNEL BOT - INSTALLATEUR COMPLET
# ==========================================================

LN='\e[36m'
NC='\e[0m'
BG='\e[44m'
RD='\e[31m'
GR='\e[32m'
YL='\e[33m'

BOT_DIR="/etc/tom_tunnel_bot"
TEMP_DIR="/tmp/tom_tunnel_bot_temp"
REPO_URL="https://github.com/ILYASSETOM55/TOM_TUNNEL.git"
BOT_SOURCE="${TEMP_DIR}/tom_tunnel_core_bot"
CONFIG_FILE="${BOT_DIR}/config.json"
VENV_DIR="${BOT_DIR}/venv"
SERVICE_FILE="/etc/systemd/system/tom_tunnel_bot.service"

# ==========================================================
# HEADER
# ==========================================================

echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${LN}┃${NC}${BG}          INSTALLATION DE TOM_TUNNEL BOT          ${NC}${LN}┃${NC}"
echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo

echo -e "${GR}Ce module va relier votre serveur à Telegram.${NC}"
echo -e "${GR}Vous deviendrez le SUPER ADMIN du système.${NC}"
echo

# ==========================================================
# ROOT
# ==========================================================

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RD}[-] ERREUR : ce script doit être exécuté en root.${NC}"
    exit 1
fi

# ==========================================================
# TOKEN
# ==========================================================

read -p " ➔ Entrez le TOKEN du Bot : " bot_token

if [[ -z "$bot_token" ]]; then
    echo -e "${RD}[-] Erreur : le Token est obligatoire.${NC}"
    exit 1
fi

# ==========================================================
# ADMIN ID
# ==========================================================

read -p " ➔ Entrez votre ID Telegram : " admin_id

if [[ -z "$admin_id" ]]; then
    echo -e "${RD}[-] Erreur : l'ID Telegram est obligatoire.${NC}"
    exit 1
fi

if ! [[ "$admin_id" =~ ^[0-9]+$ ]]; then
    echo -e "${RD}[-] Erreur : l'ID Telegram doit être numérique.${NC}"
    exit 1
fi

# ==========================================================
# ARRET ANCIEN BOT
# ==========================================================

echo
echo -e "${GR}[+] Arrêt de l'ancienne installation...${NC}"

systemctl stop tom_tunnel_bot.service >/dev/null 2>&1
systemctl disable tom_tunnel_bot.service >/dev/null 2>&1

# ==========================================================
# INSTALLATION PAQUETS
# ==========================================================

echo -e "${GR}[+] Préparation de l'environnement système...${NC}"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl

if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RD}[-] Python3 n'est pas disponible.${NC}"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo -e "${RD}[-] Git n'est pas disponible.${NC}"
    exit 1
fi

# ==========================================================
# NETTOYAGE TEMPORAIRE
# ==========================================================

echo -e "${GR}[+] Nettoyage des anciens fichiers temporaires...${NC}"

rm -rf "$TEMP_DIR"

# ==========================================================
# DOSSIER BOT
# ==========================================================

echo -e "${GR}[+] Création du dossier TOM_TUNNEL BOT...${NC}"

mkdir -p "$BOT_DIR"

# ==========================================================
# CONFIGURATION
# ==========================================================

echo -e "${GR}[+] Création de la configuration Telegram...${NC}"

cat > "$CONFIG_FILE" <<EOF
{
  "bot_token": "$bot_token",
  "super_admin": $admin_id,
  "admins": []
}
EOF

chmod 600 "$CONFIG_FILE"

# ==========================================================
# TELECHARGEMENT DEPOT
# ==========================================================

echo -e "${GR}[+] Téléchargement du dépôt TOM_TUNNEL...${NC}"
echo -e "${LN}${REPO_URL}${NC}"

if ! git clone --depth 1 "$REPO_URL" "$TEMP_DIR"; then
    echo
    echo -e "${RD}[-] ERREUR : impossible de télécharger le dépôt.${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GR}[✓] Dépôt téléchargé avec succès.${NC}"

# ==========================================================
# VERIFICATION MODULE BOT
# ==========================================================

echo -e "${GR}[+] Recherche du moteur TOM_TUNNEL BOT...${NC}"

if [[ ! -d "$BOT_SOURCE" ]]; then

    echo -e "${RD}[-] ERREUR : le dossier tom_tunnel_core_bot est introuvable.${NC}"

    echo
    echo -e "${YL}Structure trouvée :${NC}"

    find "$TEMP_DIR" -maxdepth 2 -type d

    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GR}[✓] tom_tunnel_core_bot trouvé.${NC}"

# ==========================================================
# COPIE DES FICHIERS
# ==========================================================

echo -e "${GR}[+] Copie des fichiers du bot...${NC}"

rm -rf "$BOT_DIR/modules"

cp -a "$BOT_SOURCE/." "$BOT_DIR/"

# ==========================================================
# VERIFICATION FICHIER PRINCIPAL
# ==========================================================

BOT_FILE="$BOT_DIR/tom_tunnel_bot.py"

if [[ ! -f "$BOT_FILE" ]]; then

    FOUND_BOT=$(find "$BOT_DIR" -maxdepth 2 -type f \
        \( -name "tom_tunnel_bot.py" \
        -o -name "bot.py" \
        -o -name "main.py" \) \
        | head -n 1)

    if [[ -n "$FOUND_BOT" ]]; then
        BOT_FILE="$FOUND_BOT"
    fi
fi

if [[ ! -f "$BOT_FILE" ]]; then

    echo -e "${RD}[-] ERREUR : fichier principal du bot introuvable.${NC}"

    echo
    echo -e "${YL}Fichiers Python disponibles :${NC}"
    find "$BOT_DIR" -type f -name "*.py"

    exit 1
fi

echo -e "${GR}[✓] Fichier principal : $BOT_FILE${NC}"

# ==========================================================
# ENVIRONNEMENT VIRTUEL PYTHON
# ==========================================================

echo -e "${GR}[+] Création de l'environnement Python...${NC}"

rm -rf "$VENV_DIR"

python3 -m venv "$VENV_DIR"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo -e "${RD}[-] ERREUR : impossible de créer le venv.${NC}"
    exit 1
fi

# ==========================================================
# PIP
# ==========================================================

echo -e "${GR}[+] Préparation de pip...${NC}"

"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel

# ==========================================================
# DEPENDANCES OBLIGATOIRES
# ==========================================================

echo -e "${GR}[+] Installation des dépendances TOM_TUNNEL...${NC}"

"$VENV_DIR/bin/python" -m pip install \
    psutil \
    requests \
    pyTelegramBotAPI

if [[ $? -ne 0 ]]; then
    echo -e "${RD}[-] ERREUR : installation des dépendances principales échouée.${NC}"
    exit 1
fi

# ==========================================================
# REQUIREMENTS.TXT
# ==========================================================

if [[ -f "$BOT_DIR/requirements.txt" ]]; then

    echo -e "${GR}[+] Installation de requirements.txt...${NC}"

    if ! "$VENV_DIR/bin/python" -m pip install \
        -r "$BOT_DIR/requirements.txt"; then

        echo -e "${RD}[-] ERREUR : requirements.txt contient une dépendance impossible à installer.${NC}"
        exit 1
    fi

else

    echo -e "${YL}[!] requirements.txt absent.${NC}"
    echo -e "${GR}[+] Les dépendances principales ont quand même été installées.${NC}"

fi

# ==========================================================
# TEST PSUTIL
# ==========================================================

echo -e "${GR}[+] Vérification de psutil...${NC}"

if ! "$VENV_DIR/bin/python" -c "import psutil"; then

    echo -e "${RD}[-] ERREUR : psutil n'est pas installé dans le venv.${NC}"
    exit 1
fi

echo -e "${GR}[✓] psutil fonctionne correctement.${NC}"

# ==========================================================
# TEST REQUESTS
# ==========================================================

echo -e "${GR}[+] Vérification de requests...${NC}"

if ! "$VENV_DIR/bin/python" -c "import requests"; then

    echo -e "${RD}[-] ERREUR : requests n'est pas installé.${NC}"
    exit 1
fi

echo -e "${GR}[✓] requests fonctionne correctement.${NC}"

# ==========================================================
# TEST TELEBOT
# ==========================================================

echo -e "${GR}[+] Vérification de pyTelegramBotAPI...${NC}"

if ! "$VENV_DIR/bin/python" -c "import telebot"; then

    echo -e "${RD}[-] ERREUR : pyTelegramBotAPI n'est pas installé.${NC}"
    exit 1
fi

echo -e "${GR}[✓] Telegram API fonctionne correctement.${NC}"

# ==========================================================
# TEST IMPORTS TOM_TUNNEL
# ==========================================================

echo -e "${GR}[+] Vérification des modules TOM_TUNNEL...${NC}"

cd "$BOT_DIR"

if ! "$VENV_DIR/bin/python" -c "
import sys
sys.path.insert(0, '$BOT_DIR')

import psutil
import requests
import telebot

from modules import system_core
print('IMPORTS_OK')
"; then

    echo -e "${RD}[-] ERREUR : un module TOM_TUNNEL ne peut pas être chargé.${NC}"
    echo
    echo -e "${YL}Vérifiez les fichiers Python avec :${NC}"
    echo -e "find $BOT_DIR -type f -name '*.py'"
    exit 1
fi

echo -e "${GR}[✓] Modules TOM_TUNNEL chargés correctement.${NC}"

# ==========================================================
# PERMISSIONS
# ==========================================================

echo -e "${GR}[+] Configuration des permissions...${NC}"

chmod -R 755 "$BOT_DIR"
chmod 600 "$CONFIG_FILE"

mkdir -p /var/log/tom_tunnel_bot

touch /var/log/tom_tunnel_bot/bot.log

chmod 755 /var/log/tom_tunnel_bot
chmod 644 /var/log/tom_tunnel_bot/bot.log

# ==========================================================
# SERVICE SYSTEMD
# ==========================================================

echo -e "${GR}[+] Création du service systemd...${NC}"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=TOM_TUNNEL Telegram Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR

ExecStart=$VENV_DIR/bin/python $BOT_FILE

Restart=always
RestartSec=3

Environment=PYTHONUNBUFFERED=1

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ==========================================================
# NETTOYAGE
# ==========================================================

rm -rf "$TEMP_DIR"

# ==========================================================
# SYSTEMD
# ==========================================================

echo -e "${GR}[+] Activation du service TOM_TUNNEL BOT...${NC}"

systemctl daemon-reload

systemctl enable tom_tunnel_bot.service

systemctl restart tom_tunnel_bot.service

sleep 4

# ==========================================================
# VERIFICATION SERVICE
# ==========================================================

if systemctl is-active --quiet tom_tunnel_bot.service; then

    echo
    echo -e "${GR}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${GR}┃        ✓ TOM_TUNNEL BOT ACTIVÉ                  ┃${NC}"
    echo -e "${GR}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo
    echo -e "${GR}[✓] Service : ACTIF${NC}"
    echo -e "${GR}[✓] Admin   : $admin_id${NC}"
    echo -e "${GR}[✓] Dossier : $BOT_DIR${NC}"
    echo
    echo -e "${GR}➡ Allez sur Telegram et envoyez /start${NC}"

else

    echo
    echo -e "${RD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${RD}┃       ✗ ÉCHEC DU DÉMARRAGE DU BOT              ┃${NC}"
    echo -e "${RD}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo

    echo -e "${YL}Derniers logs :${NC}"

    journalctl -u tom_tunnel_bot.service -n 40 --no-pager

    echo
    echo -e "${YL}Commande pour suivre les logs :${NC}"
    echo -e "journalctl -u tom_tunnel_bot -f"

    exit 1
fi

echo
echo -e "${GR}[+] Installation terminée.${NC}"
echo