#!/bin/bash
# ============================================================
#  TOM TUNNEL WEB — INSTALLER (Cyberpunk Theme Edition)
#  Installs Node.js, dependencies, builds TypeScript,
#  creates systemd service and config.
# ============================================================

set -uo pipefail

TOM_WEB_DIR="/opt/tom-tunnel-web"
CONFIG_DIR="/etc/tom-tunnel-web"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/tom-web.service"
NODE_MIN_VERSION=18

# ==============================================================================
# PALETTE NEON CYBERPUNK (ANSI 256)
# ==============================================================================
export C_RESET='\033[0m'
export C_BOLD='\033[1m'
export C_CYAN='\033[38;5;45m'
export C_MAGENTA='\033[38;5;201m'
export C_GREEN='\033[38;5;46m'
export C_GOLD='\033[38;5;220m'
export C_RED='\033[38;5;196m'
export C_GRAY='\033[38;5;242m'
export C_WHITE='\033[38;5;255m'

log_info()  { echo -e "  ${C_CYAN}► [INFO]${C_RESET}  $*"; }
log_ok()    { echo -e "  ${C_GREEN}⚡ [OK]${C_RESET}    $*"; }
log_warn()  { echo -e "  ${C_GOLD}⚠ [WARN]${C_RESET}  $*"; }
log_error() { echo -e "  ${C_RED}✖ [ERROR]${C_RESET} $*"; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log_error "Ce script doit être exécuté en privilèges root."
    exit 1
  fi
}

# ─── Find available port ─────────────────────────────────────────────────────
find_available_port() {
  local candidates=(2087 2096 8787 3001 9090 8088 9180)
  for port in "${candidates[@]}"; do
    if ! ss -tlnp 2>/dev/null | grep -q ":$port " && \
       ! netstat -tlnp 2>/dev/null | grep -q ":$port "; then
      echo "$port"
      return 0
    fi
  done
  echo "2087"  # Fallback port
}

# ─── Install Node.js ─────────────────────────────────────────────────────────
install_nodejs() {
  if command -v node &>/dev/null; then
    local ver
    ver=$(node -e "process.stdout.write(process.version.replace('v','').split('.')[0])" 2>/dev/null || echo "0")
    if [ "$ver" -ge "$NODE_MIN_VERSION" ]; then
      log_ok "Node.js $(node --version) est déjà installé."
      return 0
    fi
    log_warn "Node.js v$ver détecté, mais v$NODE_MIN_VERSION minimum requise. Mise à niveau..."
  fi

  log_info "Installation de Node.js v${NODE_MIN_VERSION}.x..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MIN_VERSION}.x" | bash - >/dev/null 2>&1
  apt-get install -y nodejs >/dev/null 2>&1
  log_ok "Node.js $(node --version) installé avec succès."
}

# ─── Main install ─────────────────────────────────────────────────────────────
main() {
  require_root
  clear

  echo -e "${C_MAGENTA}╔═════════════════════════════════════════════════════════════════╗${C_RESET}"
  echo -e "${C_MAGENTA}║${C_RESET} ${C_BOLD}${C_CYAN}❖ TOM TUNNEL WEB — INSTALLATEUR DU PANNEAU${C_RESET}                     ${C_MAGENTA}║${C_RESET}"
  echo -e "${C_MAGENTA}╚═════════════════════════════════════════════════════════════════╝${C_RESET}"
  echo ""

  # ── Identifiants administrateur ──
  local admin_user admin_pass admin_pass2

  while true; do
    read -rp "  ► Nom d'utilisateur Admin : " admin_user
    [[ -n "$admin_user" ]] && break
    log_error "Le nom d'utilisateur ne peut pas être vide."
  done

  while true; do
    read -srp "  ► Mot de passe Admin      : " admin_pass; echo ""
    [[ ${#admin_pass} -ge 6 ]] && break
    log_error "Le mot de passe doit contenir au moins 6 caractères."
  done

  read -srp "  ► Confirmer mot de passe  : " admin_pass2; echo ""
  if [[ "$admin_pass" != "$admin_pass2" ]]; then
    log_error "Les mots de passe ne correspondent pas. Abandon."
    exit 1
  fi

  echo ""

  # ── Détection du port ──
  local port
  port=$(find_available_port)
  log_info "Port attribué : ${C_GOLD}$port${C_RESET}"

  # ── Clé secrète JWT ──
  local jwt_secret
  jwt_secret=$(openssl rand -hex 48 2>/dev/null || head -c 48 /dev/urandom | base64 | tr -d '=\n+/')

  # ── Dépendances système ──
  log_info "Installation des dépendances système de base..."
  apt-get update -y -q >/dev/null 2>&1
  apt-get install -y -q curl git build-essential python3 make chrony >/dev/null 2>&1

  systemctl enable chrony --now 2>/dev/null || systemctl enable chronyd --now 2>/dev/null || true
  log_ok "Dépendances système et NTP (chrony) opérationnels."

  install_nodejs

  # ── Déploiement du projet ──
  log_info "Déploiement des fichiers vers ${C_CYAN}$TOM_WEB_DIR${C_RESET}..."
  mkdir -p "$TOM_WEB_DIR"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ "$SCRIPT_DIR" != "$TOM_WEB_DIR" ]; then
    cp -r "$SCRIPT_DIR"/* "$TOM_WEB_DIR/"
  fi
  cd "$TOM_WEB_DIR"

  # ── Build Frontend React ──
  if [ -d "$TOM_WEB_DIR/frontend" ]; then
    log_info "Compilation de l'interface Frontend React..."
    cd "$TOM_WEB_DIR/frontend"
    npm install --quiet 2>&1 | tail -5

    if ! npm run build 2>&1; then
      log_warn "Avertissements lors du build Frontend, poursuite de l'installation..."
    else
      log_ok "Interface React compilée avec succès."
    fi

    cd "$TOM_WEB_DIR"
  fi

  # ── Build Backend Node.js / TypeScript ──
  log_info "Installation des dépendances Node.js du serveur..."
  npm install --production=false --quiet 2>&1 | tail -5

  log_info "Compilation du serveur TypeScript..."

  if ! npm run build 2>&1; then
    log_warn "Avertissements pendant la compilation TypeScript, contrôle de dist..."

    if [ ! -f "$TOM_WEB_DIR/dist/server/index.js" ]; then
      log_error "Échec de la compilation TypeScript."
      exit 1
    fi
  fi

  log_ok "Serveur TypeScript compilé."

  # ── Fichier de configuration ──
  log_info "Génération de la configuration..."
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"

  cat > "$CONFIG_FILE" <<JSON
{
  "port": $port,
  "admin_user": "$admin_user",
  "admin_password": "$admin_pass",
  "jwt_secret": "$jwt_secret",
  "scripts_dir": "/usr/local/sbin",
  "db_dir": "$CONFIG_DIR"
}
JSON

  chmod 600 "$CONFIG_FILE"
  log_ok "Configuration sauvegardée : $CONFIG_FILE"

  # ── Service Systemd ──
  log_info "Création du service Systemd..."

  cat > "$SERVICE_FILE" <<SVC
[Unit]
Description=Tom Tunnel Web Panel
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$TOM_WEB_DIR
ExecStart=/usr/bin/node $TOM_WEB_DIR/dist/server/index.js
Restart=always
RestartSec=5
StartLimitBurst=10
StartLimitIntervalSec=60
Environment=NODE_ENV=production
Environment=TOM_CONFIG=$CONFIG_FILE
Environment=TOM_DB_DIR=$CONFIG_DIR
Environment=TOM_JWT_SECRET=$jwt_secret
Environment=TOM_ADMIN_USER=$admin_user
Environment=TOM_ADMIN_PASS=$admin_pass
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

  chmod 600 "$SERVICE_FILE"

  # ── Watchdog de santé (Cron) ──
  cat > /usr/local/bin/tom-web-watchdog.sh <<'WATCHDOG'
#!/bin/bash

CONFIG_FILE="/etc/tom-tunnel-web/config.json"

PORT=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG_FILE" 2>/dev/null | awk -F: '{gsub(/[^0-9]/,"",$2); print $2}')

[ -z "$PORT" ] && PORT=2087

FAIL_COUNT_FILE="/tmp/.tom-web-watchdog-fails"

if curl -sf --max-time 8 "http://localhost:${PORT}/api/health" > /dev/null 2>&1; then
  rm -f "$FAIL_COUNT_FILE"
else
  count=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
  count=$((count + 1))
  echo "$count" > "$FAIL_COUNT_FILE"

  if [ "$count" -ge 3 ]; then
    echo "[$(date -u)] Health check failed ${count} times — restarting tom-web" >> /var/log/tom-web-watchdog.log
    systemctl restart tom-web
    rm -f "$FAIL_COUNT_FILE"
  fi
fi
WATCHDOG

  chmod 755 /usr/local/bin/tom-web-watchdog.sh

  echo "* * * * * root /usr/local/bin/tom-web-watchdog.sh" > /etc/cron.d/tom-web-watchdog
  chmod 644 /etc/cron.d/tom-web-watchdog

  log_ok "Watchdog de santé actif (/etc/cron.d/tom-web-watchdog)"

  # ── Démarrage du service ──
  systemctl daemon-reload
  systemctl enable tom-web
  systemctl restart tom-web

  sleep 2

  if systemctl is-active --quiet tom-web; then
    log_ok "Le service Tom Tunnel Web fonctionne correctement !"
  else
    log_warn "Le service n'a pas pu démarrer instantanément. Vérifiez : journalctl -u tom-web -n 30"
  fi

  # ── Alias Raccourci Menu ──
  ln -sf /usr/local/sbin/web /usr/local/sbin/web 2>/dev/null || true

  # ── Récapitulatif ──
  local server_ip
  server_ip=$(curl -s4 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')

  echo ""
  echo -e "${C_MAGENTA}╔═════════════════════════════════════════════════════════════════╗${C_RESET}"
  echo -e "${C_MAGENTA}║${C_RESET} ${C_BOLD}${C_GOLD}⚡ TOM TUNNEL WEB — INSTALLATION TERMINÉE${C_RESET}                    ${C_MAGENTA}║${C_RESET}"
  echo -e "${C_MAGENTA}╠═════════════════════════════════════════════════════════════════╣${C_RESET}"

  printf "${C_MAGENTA}║${C_RESET}  ${C_WHITE}URL Accès Web${C_RESET}  : ${C_GREEN}http://%s:%s${C_RESET}%*s ${C_MAGENTA}║${C_RESET}\n" \
    "$server_ip" "$port" $(( 32 - ${#server_ip} - ${#port} )) ""

  printf "${C_MAGENTA}║${C_RESET}  ${C_WHITE}Utilisateur${C_RESET}    : ${C_CYAN}%-43s${C_RESET} ${C_MAGENTA}║${C_RESET}\n" \
    "$admin_user"

  printf "${C_MAGENTA}║${C_RESET}  ${C_WHITE}Configuration${C_RESET}  : %-43s ${C_MAGENTA}║${C_RESET}\n" \
    "$CONFIG_FILE"

  printf "${C_MAGENTA}║${C_RESET}  ${C_WHITE}Statut Service${C_RESET} : %-43s ${C_MAGENTA}║${C_RESET}\n" \
    "systemctl status tom-web"

  echo -e "${C_MAGENTA}╚═════════════════════════════════════════════════════════════════╝${C_RESET}"
  echo ""
}

main "$@"