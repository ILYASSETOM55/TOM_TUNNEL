#!/bin/bash
clear
LN='\e[34m'
NC='\e[0m'
GR='\e[32m'
RD='\e[31m'
SERVER_HOST="https://raw.githubusercontent.com/RootNexTPro/nexTPro-ScriptAll/main"

echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${LN}┃${NC} ${GR}       MISE À JOUR OTA (OVER-THE-AIR)             ${NC}${LN}┃${NC}"
echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo -e "\n [*] Connexion au dépôt GitHub central..."
echo -e " [*] Déploiement des modules..."

MODULES=(dns zivpn expiry domain iptools menu socks ssh status trojan vless vmess netguard port log tgbot uninstall update fastdns)

for script in "${MODULES[@]}"; do
    wget -q -O "/usr/local/sbin/$script" "${SERVER_HOST}/menu/${script}.sh"
    chmod +x "/usr/local/sbin/$script"
    echo -e "  -> Module $script [OK]"
done

echo -e "\n${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${LN}┃${NC} ${GR}         MISE À JOUR TOM_TUNNEL WEB            ${NC}${LN}┃${NC}"
echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

TOM_TUNNEL_WEB_DIR="/opt/tom_tunnel-tunnel-web"
TOM_TUNNEL_REPO_URL="https://github.com/RootNexTPro/nexTPro-ScriptAll.git"
NTW_TMP="$(mktemp -d)"

if [ -d "$TOM_TUNNEL_WEB_DIR" ] && [ -f "$TOM_TUNNEL_WEB_DIR/dist/server/index.js" ]; then
  echo -e "  -> Panel tom_tunnel Web détecté, mise à jour en cours..."
  if git clone --depth 1 "$TOM_TUNNEL_REPO_URL" "$NTW_TMP" >/dev/null 2>&1; then
    if [ -d "$NTW_TMP/tom_tunnel-web" ]; then
      cp -rf "$NTW_TMP/tom_tunnel-web"/. "$TOM_TUNNEL_WEB_DIR/"
      sed -i "s|const PUBLIC_DIR = .*|const PUBLIC_DIR = '/opt/tom_tunnel-tunnel-web/public';|g" \
          "$TOM_TUNNEL_WEB_DIR/server/index.ts" 2>/dev/null || true
      sed -i 's/callback(null, false);/callback(null, true);/g' \
          "$TOM_TUNNEL_WEB_DIR/server/index.ts" 2>/dev/null || true
      if [ -d "$TOM_TUNNEL_WEB_DIR/frontend" ]; then
        cd "$TOM_TUNNEL_WEB_DIR/frontend" && npm install --quiet >/dev/null 2>&1 && npm run build >/dev/null 2>&1
      fi
      cd "$TOM_TUNNEL_WEB_DIR" && npm install --production=false --quiet >/dev/null 2>&1 && npm run build >/dev/null 2>&1
      systemctl restart tom_tunnel-web 2>/dev/null || true
      echo -e "  -> TOM_TUNNEL Web [OK]"
    fi
    rm -rf "$NTW_TMP"
  else
    echo -e "  -> ${RD}[WARN] Impossible de mettre à jour tom_tunnel Web (pas de connexion GitHub)${NC}"
  fi
else
  echo -e "  -> TOM_TUNNEL Web non installé, ignoré."
fi

echo -e "\n ${GR}[+] Mise à jour OTA terminée avec succès !${NC}"
sleep 2
menu
