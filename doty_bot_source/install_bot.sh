#!/bin/bash
# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
# Script d'installation et de déploiement corrigé - TOM_TUNNEL / TOM BOT
# Dépôt GitHub : https://github.com/ILYASSETOM55/TOM_TUNNEL.git
#‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬

set -e

# Couleurs pour le terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_URL="https://github.com/ILYASSETOM55/TOM_TUNNEL.git"
INSTALL_DIR="/opt/tom_bot"
CONFIG_DIR="/etc/tom_bot"
SERVICE_NAME="TOM_bot"

echo -e "${BLUE}‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e "${BLUE}        INSTALLATION DE TOM BOT / TOM_TUNNEL      ${NC}"
echo -e "${BLUE}‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"

# 1. Vérification des droits ROOT
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Erreur: Ce script doit être exécuté en tant que root (sudo bash install_bot.sh)${NC}"
  exit 1
fi

# 2. Saisie interactive des identifiants (avec validation)
echo -e "${YELLOW}Ce module va relier votre serveur à Telegram.${NC}"
read -rp " ➔ Entrez le TOKEN du Bot (ex: 1234:ABCDef...) : " BOT_TOKEN
read -rp " ➔ Entrez votre ID Telegram (ex: 123456789) : " ADMIN_ID

if [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_ID" ]; then
    echo -e "${RED}[!] Erreur: Le TOKEN et l'ID Admin ne peuvent pas être vides.${NC}"
    exit 1
fi

# 3. Installation des paquets système requis
echo -e "${YELLOW}[+] Mise à jour du système et dépendances...${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install -y python3 python3-pip python3-venv git curl jq > /dev/null 2>&1

# 4. Préparation et nettoyage du répertoire cible
echo -e "${YELLOW}[+] Préparation de l'environnement d'installation...${NC}"
mkdir -p "$CONFIG_DIR"

if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${YELLOW}[+] Mise à jour du code depuis GitHub...${NC}"
    cd "$INSTALL_DIR"
    git reset --hard
    git pull origin main
else
    echo -e "${YELLOW}[+] Clonage du dépôt principal...${NC}"
    rm -rf "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 5. Garantie d'intégrité de l'architecture Python (Fichiers __init__.py)
mkdir -p "$INSTALL_DIR/bot/modules"
touch "$INSTALL_DIR/bot/__init__.py"
touch "$INSTALL_DIR/bot/modules/__init__.py"

# Si le fichier main.py se trouve sous un autre dossier (ex: nexus_core_bot), création d'un lien d'entrée
if [ ! -f "$INSTALL_DIR/bot/main.py" ]; then
    if [ -f "$INSTALL_DIR/nexus_core_bot/main.py" ]; then
        cp -r "$INSTALL_DIR/nexus_core_bot/"* "$INSTALL_DIR/bot/"
    elif [ -f "$INSTALL_DIR/doty_bot_source/main.py" ]; then
        cp -r "$INSTALL_DIR/doty_bot_source/"* "$INSTALL_DIR/bot/"
    fi
fi

# 6. Environnement virtuel isolatif (VENV)
echo -e "${YELLOW}[+] Configuration de l'environnement virtuel Python...${NC}"
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip > /dev/null 2>&1

if [ -f "$INSTALL_DIR/requirements.txt" ]; then
    "$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt" > /dev/null 2>&1
else
    "$INSTALL_DIR/venv/bin/pip" install "python-telegram-bot>=20.0,<21.0" requests psutil python-dotenv > /dev/null 2>&1
fi

# 7. Génération de la configuration JSON sécurisée
echo -e "${YELLOW}[+] Sauvegarde de la configuration dans $CONFIG_DIR...${NC}"
PUBLIC_IP=$(curl -s ifconfig.me || echo "127.0.0.1")

cat <<EOF > "$CONFIG_DIR/config.json"
{
  "bot_token": "$BOT_TOKEN",
  "admin_id": "$ADMIN_ID",
  "vps_ip": "$PUBLIC_IP"
}
EOF
chmod 600 "$CONFIG_DIR/config.json"

# 8. Alignement et configuration du Service Systemd (Corrigé)
echo -e "${YELLOW}[+] Configuration et alignement du Démon système ($SERVICE_NAME)...${NC}"

cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=TOM C2 Telegram Bot Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/bot/main.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONPATH=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

# 9. Démarrage et contrôle de santé du service
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service > /dev/null 2>&1
systemctl restart ${SERVICE_NAME}.service

echo -e "${YELLOW}[+] Vérification du statut du service...${NC}"
sleep 3

if systemctl is-active --quiet ${SERVICE_NAME}.service; then
    echo -e "${GREEN}‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
    echo -e "${GREEN}   Configuration du Bot Telegram complétée !         ${NC}"
    echo -e "${GREEN}‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
    echo -e " Allez sur Telegram et tapez /start avec le bot"
    echo -e " Votre ID Admin: ${GREEN}$ADMIN_ID${NC}"
else
    echo -e "${RED}[!] Erreur: Le bot n'a pas pu démarrer.${NC}"
    echo -e "${RED}[!] Log des erreurs récents :${NC}"
    journalctl -u ${SERVICE_NAME}.service -n 15 --no-pager
    exit 1
fi

