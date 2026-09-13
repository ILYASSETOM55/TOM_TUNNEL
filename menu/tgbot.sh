#!/bin/bash

clear

LN='\e[36m'
NC='\e[0m'
BG='\e[44m'
RD='\e[31m'
GR='\e[32m'
YL='\e[33m'

# ==========================================================
# TOM_TUNNEL BOT - INSTALLATEUR
# ==========================================================

BOT_DIR="/etc/tom_tunnel_bot"
TEMP_DIR="/tmp/tom_tunnel_bot_temp"
REPO_URL="https://github.com/ILYASSETOM55/TOM_TUNNEL.git"
BOT_SOURCE="${TEMP_DIR}/tom_tunnel_core_bot"
CONFIG_FILE="${BOT_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/tom_tunnel_bot.service"

echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${LN}┃${NC}${BG}          INSTALLATION DE TOM_TUNNEL BOT          ${NC}${LN}┃${NC}"
echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo

echo -e "${GR}Ce module va relier votre serveur à Telegram.${NC}"
echo -e "${GR}Vous deviendrez le SUPER ADMIN du système.${NC}"
echo

# ==========================================================
# VERIFICATION ROOT
# ==========================================================

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RD}[-] ERREUR : lancez ce script en root.${NC}"
    exit 1
fi

# ==========================================================
# TOKEN TELEGRAM
# ==========================================================

read -p " ➔ Entrez le TOKEN du Bot (ex: 1234:ABCDef...) : " bot_token

if [[ -z "$bot_token" ]]; then
    echo -e "${RD}[-] Erreur : le Token est obligatoire.${NC}"
    exit 1
fi

# Vérification basique du token Telegram
if ! [[ "$bot_token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    echo -e "${YL}[!] Attention : le format du token semble inhabituel.${NC}"
    echo -e "${YL}[!] Vérifiez le token avant de continuer.${NC}"
fi

# ==========================================================
# ID TELEGRAM ADMIN
# ==========================================================

read -p " ➔ Entrez votre ID Telegram (ex: 123456789) : " admin_id

if [[ -z "$admin_id" ]]; then
    echo -e "${RD}[-] Erreur : l'ID Admin est obligatoire.${NC}"
    exit 1
fi

if ! [[ "$admin_id" =~ ^[0-9]+$ ]]; then
    echo -e "${RD}[-] Erreur : l'ID Telegram doit être numérique.${NC}"
    exit 1
fi

# ==========================================================
# PREPARATION
# ==========================================================

echo
echo -e "${GR}[+] Préparation de l'environnement Python...${NC}"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y >/dev/null 2>&1

apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    >/dev/null 2>&1

if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RD}[-] Python3 n'est pas disponible.${NC}"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo -e "${RD}[-] Git n'est pas disponible.${NC}"
    exit 1
fi

# ==========================================================
# CREATION DU DOSSIER BOT
# ==========================================================

echo -e "${GR}[+] Création du répertoire TOM_TUNNEL BOT...${NC}"

mkdir -p "$BOT_DIR"

if [[ ! -d "$BOT_DIR" ]]; then
    echo -e "${RD}[-] Impossible de créer $BOT_DIR${NC}"
    exit 1
fi

# ==========================================================
# CREATION CONFIGURATION
# ==========================================================

echo -e "${GR}[+] Création sécurisée de la configuration...${NC}"

cat > "$CONFIG_FILE" <<EOF
{
  "bot_token": "$bot_token",
  "super_admin": $admin_id,
  "admins": []
}
EOF

chmod 600 "$CONFIG_FILE"

# ==========================================================
# NETTOYAGE ANCIEN TELECHARGEMENT
# ==========================================================

echo -e "${GR}[+] Nettoyage des anciens fichiers temporaires...${NC}"

rm -rf "$TEMP_DIR"

# ==========================================================
# TELECHARGEMENT DU DEPOT
# ==========================================================

echo -e "${GR}[+] Téléchargement du moteur TOM B2 depuis le dépôt principal...${NC}"
echo -e "${LN}    Dépôt : ${REPO_URL}${NC}"

if ! git clone --depth 1 "$REPO_URL" "$TEMP_DIR" >/tmp/tom_tunnel_git.log 2>&1; then

    echo -e "${RD}[-] ERREUR : impossible de télécharger le dépôt principal.${NC}"
    echo

    if [[ -f /tmp/tom_tunnel_git.log ]]; then
        echo -e "${RD}Détail :${NC}"
        cat /tmp/tom_tunnel_git.log
    fi

    rm -rf "$TEMP_DIR"
    exit 1
fi

# ==========================================================
# VERIFICATION DU MODULE BOT
# ==========================================================

echo -e "${GR}[+] Vérification du moteur TOM_TUNNEL BOT...${NC}"

if [[ ! -d "$BOT_SOURCE" ]]; then
    echo -e "${RD}[-] ERREUR : tom_tunnel_core_bot est introuvable.${NC}"
    echo
    echo -e "${YL}[!] Structure trouvée dans le dépôt :${NC}"
    find "$TEMP_DIR" -maxdepth 2 -type d | head -50
    echo
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GR}[✓] tom_tunnel_core_bot trouvé.${NC}"

# ==========================================================
# COPIE DES FICHIERS
# ==========================================================

echo -e "${GR}[+] Installation des fichiers du bot...${NC}"

cp -a "$BOT_SOURCE/." "$BOT_DIR/"

if [[ ! -f "$BOT_DIR/tom_tunnel_bot.py" ]]; then
    echo -e "${YL}[!] tom_tunnel_bot.py n'est pas présent à la racine du module.${NC}"
fi

# ==========================================================
# DEPENDANCES PYTHON
# ==========================================================

echo -e "${GR}[+] Préparation de l'environnement Python isolé...${NC}"

VENV_DIR="$BOT_DIR/venv"

if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo -e "${RD}[-] ERREUR : environnement Python virtuel non créé.${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GR}[+] Mise à jour de pip...${NC}"

"$VENV_DIR/bin/python" -m pip install --upgrade pip \
    >/dev/null 2>&1

# ==========================================================
# REQUIREMENTS
# ==========================================================

if [[ -f "$BOT_DIR/requirements.txt" ]]; then

    echo -e "${GR}[+] Installation des dépendances de requirements.txt...${NC}"

    if ! "$VENV_DIR/bin/pip" install -r "$BOT_DIR/requirements.txt"; then
        echo -e "${RD}[-] ERREUR lors de l'installation des dépendances.${NC}"
        exit 1
    fi

else

    echo -e "${YL}[!] requirements.txt introuvable.${NC}"
    echo -e "${GR}[+] Installation des dépendances principales...${NC}"

    "$VENV_DIR/bin/pip" install \
        pyTelegramBotAPI \
        psutil \
        requests

fi

# ==========================================================
# VERIFICATION DU FICHIER PRINCIPAL
# ==========================================================

BOT_FILE="$BOT_DIR/tom_tunnel_bot.py"

if [[ ! -f "$BOT_FILE" ]]; then

    # Recherche automatique du fichier Python principal
    FOUND_BOT=$(find "$BOT_DIR" -maxdepth 2 -type f \
        \( -name "tom_tunnel_bot.py" \
        -o -name "bot.py" \
        -o -name "main.py" \) \
        | head -n 1)

    if [[ -n "$FOUND_BOT" ]]; then
        BOT_FILE="$FOUND_BOT"
    else
        echo -e "${RD}[-] ERREUR : aucun fichier Python principal du bot trouvé.${NC}"
        echo
        echo -e "${YL}Fichiers Python présents :${NC}"
        find "$BOT_DIR" -type f -name "*.py"
        exit 1
    fi
fi

echo -e "${GR}[✓] Moteur Python trouvé : $BOT_FILE${NC}"

# ==========================================================
# PERMISSIONS
# ==========================================================

chmod -R 755 "$BOT_DIR"

chmod 600 "$CONFIG_FILE"

# ==========================================================
# SERVICE SYSTEMD
# ==========================================================

echo -e "${GR}[+] Configuration du service systemd...${NC}"

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
# LOGS
# ==========================================================

mkdir -p /var/log/tom_tunnel_bot

touch /var/log/tom_tunnel_bot/bot.log

chmod 755 /var/log/tom_tunnel_bot
chmod 644 /var/log/tom_tunnel_bot/bot.log

# ==========================================================
# NETTOYAGE
# ==========================================================

rm -rf "$TEMP_DIR"
rm -f /tmp/tom_tunnel_git.log

# ==========================================================
# SYSTEMD
# ==========================================================

echo -e "${GR}[+] Activation du service TOM_TUNNEL BOT...${NC}"

systemctl daemon-reload

systemctl enable tom_tunnel_bot.service >/dev/null 2>&1

systemctl restart tom_tunnel_bot.service

sleep 3

# ==========================================================
# VERIFICATION
# ==========================================================

if systemctl is-active --quiet tom_tunnel_bot.service; then

    echo
    echo -e "${GR}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GR}[✓] BOT TELEGRAM ACTIVÉ AVEC SUCCÈS !${NC}"
    echo -e "${GR}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${GR}[✓] Service : $(systemctl is-active tom_tunnel_bot.service)${NC}"
    echo -e "${GR}[✓] Bot     : TOM_TUNNEL${NC}"
    echo -e "${GR}[✓] Admin   : $admin_id${NC}"
    echo -e "${GR}[✓] Dossier : $BOT_DIR${NC}"
    echo
    echo -e "${GR}Allez sur Telegram et envoyez /start à votre bot.${NC}"

else

    echo
    echo -e "${RD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RD}[!] ERREUR : LE BOT N'A PAS DÉMARRÉ.${NC}"
    echo -e "${RD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${YL}Derniers logs :${NC}"
    journalctl -u tom_tunnel_bot.service -n 30 --no-pager
    echo
    echo -e "${YL}Pour revoir les logs :${NC}"
    echo -e "journalctl -u tom_tunnel_bot -f"

fi

# ==========================================================
# FIN
# ==========================================================

echo
echo -e "${GR}[+] Configuration du Bot Telegram terminée.${NC}"
echo

if declare -F menu >/dev/null 2>&1; then
    read -p "Appuyez sur ENTRÉE pour retourner au menu."
    menu
else
    echo -e "${YL}Le menu TOM_TUNNEL n'est pas chargé dans ce shell.${NC}"
    echo -e "${GR}Installation terminée.${NC}"
fi