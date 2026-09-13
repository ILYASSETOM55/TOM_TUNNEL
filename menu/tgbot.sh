#!/bin/bash

clear

# ============================================================
#                 TOM_TUNNEL TELEGRAM BOT
# ============================================================

LN='\e[36m'
NC='\e[0m'
BG='\e[44m'
RD='\e[31m'
GR='\e[32m'
YL='\e[33m'

BOT_DIR="/etc/tom_tunnel_bot"
SERVICE_NAME="tom_tunnel_bot.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

REPO_URL="https://github.com/ILYASSETOM55/TOM_TUNNEL.git"
CORE_DIR="tom_tunnel_core_bot"

echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${LN}┃${NC} ${BG}        INSTALLATION DE TOM_TUNNEL BOT        ${NC}${LN}┃${NC}"
echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo

echo -e "${LN}Ce module va relier votre serveur à Telegram.${NC}"
echo -e "${LN}Vous deviendrez le SUPER ADMIN du système.${NC}"
echo

# ============================================================
#                    INFORMATIONS BOT
# ============================================================

read -p " ➔ Entrez le TOKEN du Bot : " bot_token

if [[ -z "$bot_token" ]]; then
    echo -e "${RD}[ERREUR] Le Token est obligatoire.${NC}"
    sleep 2
    exit 1
fi

read -p " ➔ Entrez votre ID Telegram : " admin_id

if [[ -z "$admin_id" ]]; then
    echo -e "${RD}[ERREUR] L'ID Telegram est obligatoire.${NC}"
    sleep 2
    exit 1
fi

# Vérification simple de l'ID
if ! [[ "$admin_id" =~ ^-?[0-9]+$ ]]; then
    echo -e "${RD}[ERREUR] L'ID Telegram doit être numérique.${NC}"
    exit 1
fi

# ============================================================
#                    DEPENDANCES
# ============================================================

echo
echo -e "${GR}[+] Installation des dépendances...${NC}"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y >/dev/null 2>&1

if ! apt-get install -y python3 python3-pip git >/dev/null 2>&1; then
    echo -e "${RD}[ERREUR] Impossible d'installer Python/Git.${NC}"
    exit 1
fi

if ! pip3 install pyTelegramBotAPI psutil >/dev/null 2>&1; then
    echo -e "${RD}[ERREUR] Installation des modules Python échouée.${NC}"
    exit 1
fi

# ============================================================
#                    DOSSIER DU BOT
# ============================================================

echo -e "${GR}[+] Création du dossier TOM_TUNNEL BOT...${NC}"

mkdir -p "$BOT_DIR"

if [[ ! -d "$BOT_DIR" ]]; then
    echo -e "${RD}[ERREUR] Impossible de créer $BOT_DIR${NC}"
    exit 1
fi

# ============================================================
#                    CONFIGURATION
# ============================================================

echo -e "${GR}[+] Création de la configuration Telegram...${NC}"

cat > "$BOT_DIR/config.json" <<JSON
{
  "bot_token": "$bot_token",
  "super_admin": $admin_id,
  "admins": []
}
JSON

if [[ ! -f "$BOT_DIR/config.json" ]]; then
    echo -e "${RD}[ERREUR] config.json n'a pas été créé.${NC}"
    exit 1
fi

chmod 600 "$BOT_DIR/config.json"

# ============================================================
#                    TELECHARGEMENT
# ============================================================

echo -e "${GR}[+] Téléchargement du moteur TOM_TUNNEL C2...${NC}"

cd /tmp || exit 1

rm -rf tom_tunnel_repo

if ! git clone --depth 1 "$REPO_URL" tom_tunnel_repo >/dev/null 2>&1; then
    echo -e "${RD}[ERREUR] Impossible de cloner le dépôt TOM_TUNNEL.${NC}"
    exit 1
fi

if [[ ! -d "/tmp/tom_tunnel_repo/$CORE_DIR" ]]; then
    echo -e "${RD}[ERREUR] Le dossier $CORE_DIR est absent du dépôt.${NC}"
    rm -rf /tmp/tom_tunnel_repo
    exit 1
fi

# ============================================================
#                    COPIE DU BOT
# ============================================================

echo -e "${GR}[+] Installation des fichiers du Bot...${NC}"

cp -a "/tmp/tom_tunnel_repo/$CORE_DIR/." "$BOT_DIR/"

if [[ $? -ne 0 ]]; then
    echo -e "${RD}[ERREUR] Copie des fichiers du Bot échouée.${NC}"
    rm -rf /tmp/tom_tunnel_repo
    exit 1
fi

rm -rf /tmp/tom_tunnel_repo

# ============================================================
#                    RECHERCHE DU PROGRAMME
# ============================================================

echo -e "${GR}[+] Recherche du programme principal...${NC}"

BOT_MAIN=""

# Priorité au nom attendu
if [[ -f "$BOT_DIR/tom_tunnel_bot.py" ]]; then
    BOT_MAIN="$BOT_DIR/tom_tunnel_bot.py"
elif [[ -f "$BOT_DIR/nexus_bot.py" ]]; then
    BOT_MAIN="$BOT_DIR/nexus_bot.py"
else
    # Recherche automatique d'un fichier Python contenant le bot
    BOT_MAIN=$(find "$BOT_DIR" -maxdepth 2 -type f -name "*.py" | head -n 1)
fi

if [[ -z "$BOT_MAIN" || ! -f "$BOT_MAIN" ]]; then
    echo -e "${RD}[ERREUR] Aucun programme Python du Bot trouvé.${NC}"
    echo
    echo -e "${YL}Fichiers Python trouvés :${NC}"
    find "$BOT_DIR" -type f -name "*.py" 2>/dev/null
    exit 1
fi

echo -e "${GR}[OK] Programme trouvé : $BOT_MAIN${NC}"

# ============================================================
#                    SERVICE SYSTEMD
# ============================================================

echo -e "${GR}[+] Création du service systemd...${NC}"

cat > "$SERVICE_FILE" <<SRV
[Unit]
Description=TOM_TUNNEL Telegram Bot C2
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
ExecStart=/usr/bin/python3 $BOT_MAIN
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SRV

if [[ ! -f "$SERVICE_FILE" ]]; then
    echo -e "${RD}[ERREUR] Le service systemd n'a pas été créé.${NC}"
    exit 1
fi

# ============================================================
#                    ACTIVATION
# ============================================================

echo -e "${GR}[+] Activation du service TOM_TUNNEL BOT...${NC}"

systemctl daemon-reload

if ! systemctl enable "$SERVICE_NAME" >/dev/null 2>&1; then
    echo -e "${RD}[ERREUR] Impossible d'activer le service.${NC}"
    exit 1
fi

if ! systemctl restart "$SERVICE_NAME"; then
    echo -e "${RD}[ERREUR] Impossible de démarrer TOM_TUNNEL BOT.${NC}"
    echo
    echo -e "${YL}Derniers logs :${NC}"
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager
    exit 1
fi

sleep 3

# ============================================================
#                    VERIFICATION
# ============================================================

if systemctl is-active --quiet "$SERVICE_NAME"; then

    echo
    echo -e "${GR}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${GR}┃              TOM_TUNNEL BOT OK                  ┃${NC}"
    echo -e "${GR}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo
    echo -e "${GR}[+] Base de données configurée.${NC}"
    echo -e "${GR}[+] Service systemd actif.${NC}"
    echo -e "${GR}[+] Bot Telegram démarré.${NC}"
    echo
    echo -e " ➜ Allez sur Telegram et envoyez ${YL}/start${NC}"
    echo

else

    echo
    echo -e "${RD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${RD}┃            ECHEC DU DEMARRAGE BOT               ┃${NC}"
    echo -e "${RD}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo
    echo -e "${RD}[ERREUR] Le service n'est pas actif.${NC}"
    echo
    echo -e "${YL}Derniers logs systemd :${NC}"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager

    exit 1
fi

echo
read -p "Appuyez sur ENTRÉE pour retourner au menu."
menu