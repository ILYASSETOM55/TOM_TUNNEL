MYIP=$(curl -sS ipv4.icanhazip.com)
readonly SERVER_HOST="https://raw.githubusercontent.com/ILYASSETOM55/TOM_TUNNEL/main"
clear

# ═══════════ COULEURS ═══════════
NC='\033[0m'        # Reset
BOLD='\033[1m'      # Gras
RED='\033[1;31m'    # Rouge
GREEN='\033[1;32m'  # Vert
YELLOW='\033[1;33m' # Jaune
BLUE='\033[1;34m'   # Bleu
MAGENTA='\033[1;35m'# Magenta
CYAN='\033[1;36m'   # Cyan
WHITE='\033[1;37m'  # Blanc
BG_BLUE='\033[44m'  # Fond bleu
BG_CYAN='\033[46m'  # Fond cyan
BG_RED='\033[41m'   # Fond rouge
BG_GREEN='\033[42m' # Fond vert

# Alias pour compatibilité
LN="$CYAN"
BG="$BG_BLUE"
GR="$GREEN"
RD="$RED"

domain=$(cat /etc/xray/domain)
uptime="$(uptime -p | cut -d " " -f 2-10)"
IPV4=$(curl -s -4 ifconfig.co)
IPV6=$(curl -s -6 ifconfig.co)
VERSION_FILE="/etc/version"
INSTALLED_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0")
LATEST_VERSION=$(curl -sS "$SERVER_HOST/version" || echo "$INSTALLED_VERSION")
UPDATE_AVAILABLE=0
version_greater() {
[ "$(printf '%s
%s
' "$1" "$2" | sort -V | tail -n1)" = "$1" ] && [ "$1" != "$2" ]
}
if version_greater "$LATEST_VERSION" "$INSTALLED_VERSION"; then
UPDATE_AVAILABLE=1
wget -q -O /usr/local/sbin/update "$SERVER_HOST/menu/update.sh" && chmod +x /usr/local/sbin/update
fi
if [ -f /etc/os-release ]; then
. /etc/os-release
OS="$NAME"
VER="$VERSION_ID"
else
OS=$(uname -s)
VER=$(uname -r)
fi

nginx=$( systemctl is-active nginx )
if [[ $nginx == "active" ]]; then
status_nginx="${BG_GREEN}${WHITE} ● ONLINE ${NC}"
else
status_nginx="${BG_RED}${WHITE} ● OFFLINE ${NC}"
fi

xray=$( systemctl is-active xray )
if [[ $xray == "active" ]]; then
status_xray="${BG_GREEN}${WHITE} ● ONLINE ${NC}"
else
status_xray="${BG_RED}${WHITE} ● OFFLINE ${NC}"
fi

ssh_ws=$( systemctl is-active ws-stunnel )
if [[ $ssh_ws == "active" ]]; then
status_ws="${BG_GREEN}${WHITE} ● ONLINE ${NC}"
else
status_ws="${BG_RED}${WHITE} ● OFFLINE ${NC}"
fi

clear

# ═══════════ BANNER ═══════════
echo -e "${MAGENTA}${BOLD}"
echo -e "     ██╗ ██████╗ ███████╗██╗         ████████╗ ██████╗ ███╗   ███╗"
echo -e "     ██║██╔═══██╗██╔════╝██║         ╚══██╔══╝██╔═══██╗████╗ ████║"
echo -e "     ██║██║   ██║█████╗  ██║            ██║   ██║   ██║██╔████╔██║"
echo -e "██   ██║██║   ██║██╔══╝  ██║            ██║   ██║   ██║██║╚██╔╝██║"
echo -e "╚█████╔╝╚██████╔╝███████╗███████╗       ██║   ╚██████╔╝██║ ╚═╝ ██║"
echo -e " ╚════╝  ╚═════╝ ╚══════╝╚══════╝       ╚═╝    ╚═════╝ ╚═╝     ╚═╝"
echo -e "${NC}"

# ═══════════ SYSTEM INFO ═══════════
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬MRTOM▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e "${BG_BLUE}${WHITE}${BOLD}              🖥   S Y S T E M   I N F O   🖥              ${NC}"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e "  ${GREEN}●${NC} ${YELLOW}OS${NC}       ${MAGENTA}»${NC} ${WHITE}$OS $VER${NC}"
echo -e "  ${GREEN}●${NC} ${YELLOW}UPTIME${NC}   ${MAGENTA}»${NC} ${WHITE}$uptime${NC}"
echo -e "  ${GREEN}●${NC} ${YELLOW}IPv4${NC}     ${MAGENTA}»${NC} ${WHITE}${IPV4:-N/A}${NC}"
if [ -n "$IPV6" ]; then
echo -e "  ${GREEN}●${NC} ${YELLOW}IPv6${NC}     ${MAGENTA}»${NC} ${WHITE}$IPV6${NC}"
fi
echo -e "  ${GREEN}●${NC} ${YELLOW}DOMAIN${NC}   ${MAGENTA}»${NC} ${WHITE}$domain${NC}"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"

# ═══════════ SERVICES STATUS ═══════════
echo -e "${BG_BLUE}${WHITE}${BOLD}            📡   S E R V I C E S   S T A T U S   📡          ${NC}"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e "  ${YELLOW}NGINX${NC}        ${MAGENTA}»${NC} [${status_nginx}${NC}]"
echo -e "  ${YELLOW}XRAY${NC}         ${MAGENTA}»${NC} [${status_xray}${NC}]"
echo -e "  ${YELLOW}WS-STUNNEL${NC}  ${MAGENTA}»${NC} [${status_ws}${NC}]"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"

# ═══════════ MENU ═══════════
echo -e "${BG_CYAN}\033[30m${BOLD}                 📶   M  E  N  U   📶                    ${NC}"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e "   ${GREEN}[01]${NC} ${WHITE}• SSH/WS MENU${NC}        ${GREEN}[04]${NC} ${WHITE}• TROJAN MENU${NC}"
echo -e "   ${GREEN}[02]${NC} ${WHITE}• VMESS MENU${NC}         ${GREEN}[05]${NC} ${WHITE}• SOCKS MENU${NC}"
echo -e "   ${GREEN}[03]${NC} ${WHITE}• VLESS MENU${NC}         ${GREEN}[06]${NC} ${WHITE}• ZIVPN MENU${NC}"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"

# ═══════════ TOOLS ═══════════
echo -e "${BG_CYAN}\033[30m${BOLD}                   🛠   T O O L S   🛠                      ${NC}"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e "   ${GREEN}[07]${NC} ${WHITE}• DNS PANEL${NC}          ${GREEN}[11]${NC} ${WHITE}• NETGUARD PANEL${NC}"
echo -e "   ${GREEN}[08]${NC} ${WHITE}• DOMAIN PANEL${NC}       ${GREEN}[12]${NC} ${WHITE}• VPN PORT INFO${NC}"
echo -e "   ${GREEN}[09]${NC} ${WHITE}• IPV6 PANEL${NC}         ${GREEN}[13]${NC} ${WHITE}• CLEAN VPS LOGS${NC}"
echo -e "   ${GREEN}[10]${NC} ${WHITE}• VPS STATUS${NC}         ${GREEN}[14]${NC} ${WHITE}• TOM_TUNNEL BOT${NC}"
echo -e "   ${GREEN}[15]${NC} ${WHITE}• UNINSTALL TOM_TUNNEL${NC}"
echo -e "   ${GREEN}[16]${NC} ${WHITE}• FAST DNS MENU${NC}"
echo -e "   ${GREEN}[00]${NC} ${WHITE}• EXIT${NC}               ${GREEN}[88]${NC} ${WHITE}• REBOOT VPS${NC}"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"

# ═══════════ WEB PANEL ═══════════
echo -e "${BG_CYAN}\033[30m${BOLD}              🌐   W E B   P A N E L   🌐                  ${NC}"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e "   ${GREEN}[18]${NC} ${WHITE}• TOM_TUNNEL WEB${NC}"
echo -e "${CYAN}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"

# ═══════════ UPDATE ═══════════
if [ "$UPDATE_AVAILABLE" -eq 1 ]; then
echo -e "${RED}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e "${BG_RED}${WHITE}${BOLD}      ⚠  [99] • UPDATE SCRIPT AVAILABLE (v$LATEST_VERSION)   ${NC}"
echo -e "${RED}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
fi

# ═══════════ FOOTER ═══════════
VERSION=$(cat /etc/version)
echo -e "${MAGENTA}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e "  ${GREEN}●${NC} ${YELLOW}VERSION${NC}      ${MAGENTA}»${NC} ${WHITE}${VERSION}${NC}"
echo -e "  ${GREEN}●${NC} ${YELLOW}SCRIPT BY${NC}    ${MAGENTA}»${NC} ${CYAN}${BOLD}JOELTOM TEAM${NC}"
echo -e "  ${GREEN}●${NC} ${YELLOW}CONTACT INFO${NC} ${MAGENTA}»${NC} ${WHITE}+237 654 14 55 40${NC}"
echo -e "${MAGENTA}▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬MRTOM▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬${NC}"
echo -e ""
read -p " Select menu :  " opt
echo -e ""

case $opt in
1 | 01) clear ; ssh ;;
2 | 02) clear ; vmess ;;
3 | 03) clear ; vless ;;
4 | 04) clear ; trojan ;;
5 | 05) clear ; socks ;;
6 | 06) clear ; zivpn ;;
7 | 07) clear ; dns ;;
8 | 08) clear ; domain ;;
9 | 09) clear ; iptools ;;
10) clear ; status ;;
11) clear ; netguard ;;
12) clear ; port ;;
13) clear ; log ;;
14) clear ; tgbot ;;
15) clear ; uninstall ;;
16) clear ; fastdns ;;
18) clear ; web ;;
88) reboot ;;
99) clear ; update ;;
0 | 00) exit ;;
*) clear ; menu ;;
esac