#!/bin/bash
set -u
LIB="/usr/local/lib/tom_tunnel"
CLI="$LIB/v2ray-dns-cli"
clear
if [[ ! -x "$CLI" ]]; then
  echo "❌ V2RAY-DNS n'est pas installé. Installez d'abord le module depuis le menu principal."
  read -r -p "Entrée pour revenir..." _
  exit 0
fi
while true; do
  clear
  echo "╭▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╮"
  echo "┃      🌐 V2RAY-DNS PANEL     ┃"
  echo "╰▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╯"
  echo "[01] Installer / vérifier"
  echo "[02] Créer un compte"
  echo "[03] Liste des comptes"
  echo "[04] Voir un compte"
  echo "[05] Supprimer un compte"
  echo "[06] Renouveler un compte"
  echo "[07] Verrouiller un compte"
  echo "[08] Déverrouiller un compte"
  echo "[09] Modifier quota"
  echo "[10] Modifier limite IP"
  echo "[11] Synchroniser statistiques"
  echo "[12] Statut"
  echo "[13] Désinstaller"
  echo "[00] Retour"
  echo
  read -r -p "Sélection : " o
  case "$o" in
    1|01) "$CLI" install ;;
    2|02)
      read -r -p "Username : " u
      read -r -p "Durée (jours) : " d
      read -r -p "Quota (ex: 25GB, 500MB, 0=illimité) : " q
      read -r -p "Limite IP (1/2/3/5/10, 0=illimité) : " ip
      "$CLI" create "$u" "$d" "$q" "$ip" ;;
    3|03) "$CLI" list ;;
    4|04) read -r -p "Username : " u; "$CLI" show "$u" ;;
    5|05) read -r -p "Username : " u; "$CLI" delete "$u" ;;
    6|06) read -r -p "Username : " u; read -r -p "Jours à ajouter : " d; "$CLI" renew "$u" "$d" ;;
    7|07) read -r -p "Username : " u; "$CLI" lock "$u" ;;
    8|08) read -r -p "Username : " u; "$CLI" unlock "$u" ;;
    9|09) read -r -p "Username : " u; read -r -p "Nouveau quota : " q; "$CLI" set-quota "$u" "$q" ;;
    10) read -r -p "Username : " u; read -r -p "Nouvelle limite IP (0=illimité) : " ip; "$CLI" set-ip-limit "$u" "$ip" ;;
    11) "$CLI" sync ;;
    12) "$CLI" status ;;
    13) "$CLI" uninstall ;;
    0|00) exit 0 ;;
    *) echo "❌ Option invalide." ;;
  esac
  echo
  read -r -p "Entrée pour continuer..." _
done
