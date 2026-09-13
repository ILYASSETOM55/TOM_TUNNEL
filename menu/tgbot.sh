#!/bin/bash

clear
LN='\e[36m'
NC='\e[0m'
BG='\e[44m'
RD='\e[31m'
GR='\e[32m'

echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${LN}┃${NC} ${BG}           INSTALLATION DE TOM_TUNNEL BOT            ${NC} ${LN}┃${NC}"
echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo -e ""
echo -e " Ce module va relier votre serveur à Telegram."
echo -e " Vous deviendrez le SUPER ADMIN du système."
echo -e ""

read -p " ➔ Entrez le TOKEN du Bot (ex: 1234:ABCDef...) : " bot_token
if [[ -z "$bot_token" ]]; then echo -e "${RD}Erreur: Le Token est obligatoire.${NC}"; sleep 2; exit; fi

read -p " ➔ Entrez votre ID Telegram (ex: 123456789) : " admin_id
if [[ -z "$admin_id" ]]; then echo -e "${RD}Erreur: L'ID Admin est obligatoire.${NC}"; sleep 2; exit; fi

echo -e "\n${GR}[+] Préparation de l'environnement Python...${NC}"
apt-get install -y python3 python3-pip git >/dev/null 2>&1
pip3 install pyTelegramBotAPI psutil requests >/dev/null 2>&1

echo -e "${GR}[+] Création sécurisée de la base de données...${NC}"
mkdir -p /etc/nexus_bot
cat <<JSON > /etc/tom_tunnel_bot/config.json
{
  "bot_token": "$bot_token",
  "super_admin": $admin_id,
  "admins": []
}
JSON

echo -e "${GR}[+] Téléchargement du moteur TOM B2 depuis le dépôt principal...${NC}"
cd /tmp
rm -rf tom_tunnel_bot_temp

# ✅ CORRECTION: Télécharger depuis le dépôt principal ILYASSETOM55
git clone https://github.com/ILYASSETOM55/TOM_TUNNEL.git >/dev/null 2>&1

# Vérifier si le téléchargement a réussi
if [ ! -d "tom_tunnel_bot_temp/tom_tunnel_core_bot" ]; then
    echo -e "${RD}[-] ERREUR: Impossible de télécharger depuis le dépôt principal.${NC}"
    echo -e "${RD}[-] Essai du dépôt secondaire...${NC}"
    rm -rf tom_tunnel_bot_temp
    git clone https://github.com/ILYASSETOM55/TOM_TUNNEL.git nexus_bot_temp >/dev/null 2>&1
fi

# Copier les fichiers du bot depuis le dépôt
if [ -d "tom_tunnel_bot_temp/tom_tunnel_core_bot" ]; then
    cp -r tom_tunnel_bot_temp/tom_tunnel_core_bot/* /etc/tom_tunnel_bot/
    echo -e "${GR}[+] Fichiers TOM_ TUNNEL B2 copiés avec succès.${NC}"
else
    echo -e "${RD}[-] ERREUR: tom_tunnel_core_bot non trouvé.${NC}"
    exit 1
fi

rm -rf nexus_bot_temp

echo -e "${GR}[+] Téléchargement des modules et dépendances...${NC}"

# Télécharger requirements.txt
if [ -f "/etc/tom_tunnel_bot/requirements.txt" ]; then
    pip3 install -r /etc/nexus_bot/requirements.txt >/dev/null 2>&1
fi

echo -e "${GR}[+] Configuration et alignement du Démon système...${NC}"

# Créer le service systemd
cat << 'SRV' > /etc/systemd/system/nexus_bot.service
[Unit]
Description=Tom Bot Telegram B2
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/tom_tunnel_bot
ExecStart=/usr/bin/python3 /etc/tom_tunnel_bot/tom_tunnel_bot.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SRV

# Créer les logs
mkdir -p /var/log/tom_tunnel_bot
touch /var/log/tom_tunnel_bot/bot.log

# Activer et démarrer le service
systemctl daemon-reload
systemctl enable tom_tunnel_bot
systemctl restart tom_tunnel_bot

# Attendre le démarrage
sleep 2

# Vérifier le statut
if systemctl is-active --quiet tom_tunnel_bot; then
    echo -e "\n${GR}[✓] Bot Telegram activé avec succès !${NC}"
    echo -e "${GR}[✓] Statut: $(systemctl is-active tom_tunnel_bot)${NC}"
else
    echo -e "\n${RD}[!] Erreur: Le bot n'a pas pu démarrer.${NC}"
    echo -e "${RD}[!] Vérifiez les logs: journalctl -u tom_tunnel_bot -n 20${NC}"
fi

echo -e "\n${GR}[+] Configuration du Bot Telegram complétée !${NC}"
echo -e " Allez sur Telegram et tapez /start avec le bot"
echo -e " Votre ID Admin: ${GR}$admin_id${NC}"
echo -e "\n Appuyez sur ENTRÉE pour retourner au menu."
read
menu
