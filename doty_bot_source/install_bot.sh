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

# URL utilisée uniquement en interne
REPO_URL="https://github.com/ILYASSETOM55/TOM_TUNNEL.git"

BOT_SOURCE="${TEMP_DIR}/tom_tunnel_core_bot"
CONFIG_FILE="${BOT_DIR}/config.json"
VENV_DIR="${BOT_DIR}/venv"
SERVICE_FILE="/etc/systemd/system/tom_tunnel_bot.service"

# ==========================================================
# HEADER
# ==========================================================

echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${LN}┃${NC}${BG}          INSTALLATION DE TOM_TUNNEL BOT          ${NC}${LN}"
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

read -r -s -p " ➔ Entrez le TOKEN du Bot : " bot_token
echo

if [[ -z "$bot_token" ]]; then
    echo -e "${RD}[-] Erreur : le Token est obligatoire.${NC}"
    exit 1
fi

# ==========================================================
# ADMIN ID
# ==========================================================

read -r -p " ➔ Entrez votre ID Telegram : " admin_id

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
# PREPARATION SYSTEME
# ==========================================================

echo -e "${GR}[+] Préparation de l'environnement système...${NC}"

export DEBIAN_FRONTEND=noninteractive

if ! apt-get update -y >/dev/null 2>&1; then
    echo -e "${RD}[-] ERREUR : impossible de préparer le système.${NC}"
    exit 1
fi

if ! apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : impossible d'installer les composants nécessaires.${NC}"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RD}[-] ERREUR : Python3 n'est pas disponible.${NC}"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo -e "${RD}[-] ERREUR : le composant de téléchargement n'est pas disponible.${NC}"
    exit 1
fi

# ==========================================================
# NETTOYAGE
# ==========================================================

echo -e "${GR}[+] Nettoyage des anciens fichiers temporaires...${NC}"

rm -rf "$TEMP_DIR"

# ==========================================================
# DOSSIER BOT
# ==========================================================

echo -e "${GR}[+] Création du répertoire TOM_TUNNEL BOT...${NC}"

if ! mkdir -p "$BOT_DIR"; then
    echo -e "${RD}[-] ERREUR : impossible de créer le répertoire du bot.${NC}"
    exit 1
fi

# ==========================================================
# CONFIGURATION
# ==========================================================

echo -e "${GR}[+] Création sécurisée de la configuration...${NC}"

cat > "$CONFIG_FILE" <<EOF
{
  "bot_token": "$bot_token",
  "super_admin": $admin_id,
  "admins": []
}
EOF

if [[ $? -ne 0 ]]; then
    echo -e "${RD}[-] ERREUR : impossible de créer la configuration.${NC}"
    exit 1
fi

chmod 600 "$CONFIG_FILE"

# Nettoyage de la variable contenant le token
unset bot_token

# ==========================================================
# TELECHARGEMENT DU MOTEUR
# ==========================================================

echo -e "${GR}[+] Téléchargement du moteur TOM B2...${NC}"

if ! git clone \
    -q \
    --depth 1 \
    "$REPO_URL" \
    "$TEMP_DIR" \
    >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : impossible de télécharger le moteur.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Moteur TOM B2 téléchargé.${NC}"

# ==========================================================
# VERIFICATION DU MOTEUR
# ==========================================================

echo -e "${GR}[+] Vérification du moteur TOM_TUNNEL BOT...${NC}"

if [[ ! -d "$BOT_SOURCE" ]]; then

    echo -e "${RD}[-] ERREUR : le moteur du bot est introuvable.${NC}"
    echo -e "${YL}[!] Installation interrompue.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Moteur TOM_TUNNEL BOT trouvé.${NC}"

# ==========================================================
# COPIE DES FICHIERS
# ==========================================================

echo -e "${GR}[+] Installation des fichiers du bot...${NC}"

rm -rf "$BOT_DIR/modules"

if ! cp -a "$BOT_SOURCE/." "$BOT_DIR/" >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : impossible d'installer les fichiers du bot.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Fichiers du bot installés.${NC}"

# ==========================================================
# VERIFICATION FICHIER PRINCIPAL
# ==========================================================

BOT_FILE="$BOT_DIR/tom_tunnel_bot.py"

if [[ ! -f "$BOT_FILE" ]]; then

    FOUND_BOT=$(find "$BOT_DIR" -maxdepth 2 -type f \
        \( -name "tom_tunnel_bot.py" \
        -o -name "bot.py" \
        -o -name "main.py" \) \
        2>/dev/null | head -n 1)

    if [[ -n "$FOUND_BOT" ]]; then
        BOT_FILE="$FOUND_BOT"
    fi
fi

if [[ ! -f "$BOT_FILE" ]]; then

    echo -e "${RD}[-] ERREUR : le fichier principal du bot est introuvable.${NC}"
    echo -e "${YL}[!] Installation interrompue.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Fichier principal du bot validé.${NC}"

# ==========================================================
# ENVIRONNEMENT PYTHON
# ==========================================================

echo -e "${GR}[+] Préparation de l'environnement Python isolé...${NC}"

rm -rf "$VENV_DIR"

if ! python3 -m venv "$VENV_DIR" >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : impossible de créer l'environnement Python.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then

    echo -e "${RD}[-] ERREUR : environnement Python invalide.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Environnement Python créé.${NC}"

# ==========================================================
# MISE A JOUR PIP
# ==========================================================

echo -e "${GR}[+] Mise à jour de pip...${NC}"

if ! "$VENV_DIR/bin/python" -m pip install \
    --disable-pip-version-check \
    -q \
    --upgrade \
    pip \
    setuptools \
    wheel \
    >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : impossible de préparer pip.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Pip prêt.${NC}"

# ==========================================================
# DEPENDANCES PRINCIPALES
# ==========================================================

echo -e "${GR}[+] Installation des composants nécessaires...${NC}"

if ! "$VENV_DIR/bin/python" -m pip install \
    --disable-pip-version-check \
    -q \
    psutil \
    requests \
    pyTelegramBotAPI \
    >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : installation des composants échouée.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Composants installés.${NC}"

# ==========================================================
# REQUIREMENTS.TXT
# ==========================================================

if [[ -f "$BOT_DIR/requirements.txt" ]]; then

    echo -e "${GR}[+] Installation des dépendances supplémentaires...${NC}"

    if ! "$VENV_DIR/bin/python" -m pip install \
        --disable-pip-version-check \
        -q \
        -r "$BOT_DIR/requirements.txt" \
        >/dev/null 2>&1; then

        echo -e "${RD}[-] ERREUR : une dépendance supplémentaire ne peut pas être installée.${NC}"

        rm -rf "$TEMP_DIR"

        exit 1
    fi

    echo -e "${GR}[✓] Dépendances supplémentaires installées.${NC}"

else

    echo -e "${YL}[!] Aucune dépendance supplémentaire détectée.${NC}"

fi

# ==========================================================
# TEST PSUTIL
# ==========================================================

echo -e "${GR}[+] Vérification du moteur système...${NC}"

if ! "$VENV_DIR/bin/python" -c "import psutil" >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : le moteur système n'est pas fonctionnel.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Moteur système fonctionnel.${NC}"

# ==========================================================
# TEST REQUESTS
# ==========================================================

echo -e "${GR}[+] Vérification de la communication réseau...${NC}"

if ! "$VENV_DIR/bin/python" -c "import requests" >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : le module réseau n'est pas fonctionnel.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Communication réseau fonctionnelle.${NC}"

# ==========================================================
# TEST TELEGRAM
# ==========================================================

echo -e "${GR}[+] Vérification de l'interface Telegram...${NC}"

if ! "$VENV_DIR/bin/python" -c "import telebot" >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : l'interface Telegram n'est pas disponible.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Interface Telegram fonctionnelle.${NC}"

# ==========================================================
# TEST MODULES BOT
# ==========================================================

echo -e "${GR}[+] Vérification des modules du bot...${NC}"

cd "$BOT_DIR" || {
    echo -e "${RD}[-] ERREUR : impossible d'accéder au répertoire du bot.${NC}"
    exit 1
}

if ! "$VENV_DIR/bin/python" -c "
import sys
sys.path.insert(0, '$BOT_DIR')

import psutil
import requests
import telebot

from modules import system_core
" >/dev/null 2>&1; then

    echo -e "${RD}[-] ERREUR : un module du bot ne peut pas être chargé.${NC}"
    echo -e "${YL}[!] Installation interrompue.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Modules du bot chargés correctement.${NC}"

# ==========================================================
# PERMISSIONS
# ==========================================================

echo -e "${GR}[+] Configuration sécurisée des permissions...${NC}"

chmod -R 755 "$BOT_DIR"

chmod 600 "$CONFIG_FILE"

mkdir -p /var/log/tom_tunnel_bot

touch /var/log/tom_tunnel_bot/bot.log

chmod 755 /var/log/tom_tunnel_bot

chmod 644 /var/log/tom_tunnel_bot/bot.log

# ==========================================================
# SERVICE SYSTEMD
# ==========================================================

echo -e "${GR}[+] Configuration du service TOM_TUNNEL BOT...${NC}"

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

if [[ $? -ne 0 ]]; then

    echo -e "${RD}[-] ERREUR : impossible de configurer le service.${NC}"

    rm -rf "$TEMP_DIR"

    exit 1
fi

echo -e "${GR}[✓] Service configuré.${NC}"

# ==========================================================
# NETTOYAGE FINAL
# ==========================================================

echo -e "${GR}[+] Nettoyage de l'installation...${NC}"

rm -rf "$TEMP_DIR"

# ==========================================================
# SYSTEMD
# ==========================================================

echo -e "${GR}[+] Activation du service TOM_TUNNEL BOT...${NC}"

if ! systemctl daemon-reload >/dev/null 2>&1; then
    echo -e "${RD}[-] ERREUR : impossible de recharger systemd.${NC}"
    exit 1
fi

if ! systemctl enable tom_tunnel_bot.service >/dev/null 2>&1; then
    echo -e "${RD}[-] ERREUR : impossible d'activer le service.${NC}"
    exit 1
fi

if ! systemctl restart tom_tunnel_bot.service >/dev/null 2>&1; then
    echo -e "${RD}[-] ERREUR : impossible de démarrer le bot.${NC}"
    exit 1
fi

sleep 4

# ==========================================================
# VERIFICATION SERVICE
# ==========================================================

if systemctl is-active --quiet tom_tunnel_bot.service; then

    echo
    echo -e "${GR}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${GR}┃          ✓ TOM_TUNNEL BOT ACTIVÉ               ┃${NC}"
    echo -e "${GR}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo

    echo -e "${GR}[✓] Service : ACTIF${NC}"
    echo -e "${GR}[✓] Admin   : $admin_id${NC}"
    echo -e "${GR}[✓] Telegram: PRÊT${NC}"

    echo
    echo -e "${GR}➡ Allez sur Telegram et envoyez /start${NC}"

else

    echo
    echo -e "${RD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${RD}┃       ✗ ÉCHEC DU DÉMARRAGE DU BOT              ┃${NC}"
    echo -e "${RD}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo

    echo -e "${YL}[!] Le service n'a pas démarré correctement.${NC}"
    echo
    echo -e "${YL}Pour consulter les logs du service :${NC}"
    echo -e "journalctl -u tom_tunnel_bot -n 40 --no-pager"

    exit 1
fi

echo
echo -e "${GR}[✓] Installation terminée avec succès.${NC}"
echo