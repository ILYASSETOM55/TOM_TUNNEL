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
GIT_LOG="/tmp/tom_tunnel_git.log"

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

read -p " ➔ Entrez le TOKEN du Bot : " bot_token

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

read -p " ➔ Entrez votre ID Telegram : " admin_id

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
    echo -e "${RD}[-] Impossible de créer le répertoire du bot.${NC}"
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
rm -f "$GIT_LOG"

# ==========================================================
# TELECHARGEMENT DU MODULE
# ==========================================================
# L'URL du dépôt est volontairement masquée à l'utilisateur.
# Les sorties Git sont également redirigées afin d'éviter
# qu'une URL ou un nom de dépôt apparaisse à l'écran.
# ==========================================================

echo -e "${GR}[+] Téléchargement du moteur TOM B2...${NC}"

if ! git clone --depth 1 "$REPO_URL" "$TEMP_DIR" >"$GIT_LOG" 2>&1; then

    echo -e "${RD}[-] ERREUR : impossible de télécharger le module.${NC}"
    echo
    echo -e "${YL}[!] Vérifiez votre connexion Internet et réessayez.${NC}"

    rm -rf "$TEMP_DIR"
    rm -f "$GIT_LOG"

    exit 1
fi

# ==========================================================
# VERIFICATION DU MODULE BOT
# ==========================================================

echo -e "${GR}[+] Vérification du moteur TOM_TUNNEL BOT...${NC}"

if [[ ! -d "$BOT_SOURCE" ]]; then

    echo -e "${RD}[-] ERREUR : le module du bot est introuvable.${NC}"
    echo

    echo -e "${YL}[!] Structure disponible :${NC}"

    find "$TEMP_DIR" -maxdepth 2 -type d 2>/dev/null \
        | sed "s|$TEMP_DIR|module|g" \
        | head -50

    echo

    rm -rf "$TEMP_DIR"
    rm -f "$GIT_LOG"

    exit 1
fi

echo -e "${GR}[✓] Module TOM_TUNNEL BOT trouvé.${NC}"

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
    rm -f "$GIT_LOG"

    exit 1
fi

echo -e "${GR}[+] Mise à jour de pip...${NC}"

"$VENV_DIR/bin/python" -m pip install --upgrade pip \
    >/dev/null 2>&1

# ==========================================================
# REQUIREMENTS
# ==========================================================

if [[ -f "$BOT_DIR/requirements.txt" ]]; then

    echo -e "${GR}[+] Installation des dépendances Python...${NC}"

    if ! "$VENV_DIR/bin/pip" install -r "$BOT_DIR/requirements.txt"; then

        echo -e "${RD}[-] ERREUR lors de l'installation des dépendances.${NC}"
        echo -e "${YL}[!] Vérifiez requirements.txt puis réessayez.${NC}"

        rm -rf "$TEMP_DIR"
        rm -f "$GIT_LOG"

        exit 1
    fi

else

    echo -e "${YL}[!] requirements.txt introuvable.${NC}"
    echo -e "${GR}[+] Installation des dépendances principales...${NC}"

    if ! "$VENV_DIR/bin/pip" install \
        pyTelegramBotAPI \
        psutil \
        requests; then

        echo -e "${RD}[-] ERREUR lors de l'installation des dépendances.${NC}"

        rm -rf "$TEMP_DIR"
        rm -f "$GIT_LOG"

        exit 1
    fi

fi

# ==========================================================
# VERIFICATION DU FICHIER PRINCIPAL
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

    else

        echo -e "${RD}[-] ERREUR : aucun fichier Python principal du bot trouvé.${NC}"
        echo
        echo -e "${YL}Fichiers Python présents :${NC}"

        find "$BOT_DIR" -type f -name "*.py" \
            | sed "s|$BOT_DIR|module|g"

        rm -rf "$TEMP_DIR"
        rm -f "$GIT_LOG"

        exit 1
    fi
fi

echo -e "${GR}[✓] Moteur Python trouvé.${NC}"

# ==========================================================
# PERMISSIONS
# ==========================================================

echo -e "${GR}[+] Configuration des permissions...${NC}"

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
rm -f "$GIT_LOG"

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

    echo -e "${YL}Le service a rencontré un problème au démarrage.${NC}"
    echo -e "${YL}Utilisez la commande suivante pour consulter les détails :${NC}"
    echo
    echo -e "${GR}journalctl -u tom_tunnel_bot -n 30 --no-pager${NC}"
    echo

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