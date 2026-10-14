clear
LN=$'\033[34m'
BG=$'\033[44m'
NC=$'\033[0m'
GR=$'\033[32m'
RD=$'\033[31m'

DB=/etc/zivpn/user.db
CFG=/etc/zivpn/config.json

if [[ $EUID -ne 0 ]]; then
  echo -e "${RD}Run as root.${NC}"
  exit 1
fi

DOMAIN=$(cat /etc/xray/domain 2>/dev/null)
MYIP=$(wget -T 5 -t 1 -qO- ipv4.icanhazip.com)
touch "$DB"

TOP="${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
BOT="${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
END="${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"

header() {
  clear
  echo -e "$TOP"
  printf "%s┃%s %s%-48s%s %s┃%s\n" "$LN" "$NC" "$BG" "$1" "$NC" "$LN" "$NC"
  echo -e "$BOT"
}

pause() {
  echo ""
  read -n 1 -s -r -p "  Press any key to return to menu..."
}

# Retire la virgule en trop avant "]" pour garder un JSON valide
fix_json() {
  sed -i ':a;N;$!ba;s/,\n[ \t]*\]/\n    ]/' "$CFG"
}

user_exists() { awk -v u="$1" '$1==u{f=1} END{exit !f}' "$DB"; }
pass_exists() {
  awk -v p="$1" '$2==p{f=1} END{exit !f}' "$DB" && return 0
  grep -qF "\"$1\"" "$CFG"
}

print_table() {
  echo -e "$TOP"
  printf "${LN}┃${NC} %-5s %-15s %-15s %-10s\n" "No." "Username" "Password" "Expiry"
  echo -e "$END"
  local i=1 u p e
  while read -r u p e; do
    [[ -z "$u" ]] && continue
    e=${e//$'\r'/}
    printf "${LN}┃${NC} %-5s %-15s %-15s %-10s\n" "$i" "$u" "$p" "$e"
    ((i++))
  done < "$DB"
  echo -e "$BOT"
}

add_zivpn() {
  header "ADD ZIVPN ACCOUNT"
  local user pass days exp tmp
  while true; do
    read -rp "  Enter username: " user
    if [[ -z "$user" ]]; then
      echo -e "  ${RD}Username cannot be empty.${NC}"; continue
    fi
    if [[ ! "$user" =~ ^[a-zA-Z0-9_]+$ ]]; then
      echo -e "  ${RD}Invalid username (letters, numbers, underscore only).${NC}"; continue
    fi
    if user_exists "$user"; then
      echo -e "  ${RD}Username already exists.${NC}"; continue
    fi
    break
  done
  while true; do
    read -rp "  Enter password: " pass
    if [[ -z "$pass" ]]; then
      echo -e "  ${RD}Password cannot be empty.${NC}"; continue
    fi
    if [[ ! "$pass" =~ ^[a-zA-Z0-9_.@-]+$ ]]; then
      echo -e "  ${RD}Invalid password (letters, numbers, _ . @ - only).${NC}"; continue
    fi
    if pass_exists "$pass"; then
      echo -e "  ${RD}Password already in use.${NC}"; continue
    fi
    break
  done
  while true; do
    read -rp "  Validity (days): " days
    if [[ ! "$days" =~ ^[0-9]+$ || "$days" -le 0 ]]; then
      echo -e "  ${RD}Expiry days must be a positive number.${NC}"; continue
    fi
    break
  done

  exp=$(date -d "+$days days" +"%Y-%m-%d")

  sed -i '/"config": \[/a\      "'"$pass"'",' "$CFG"
  fix_json

  tmp=$(mktemp)
  { echo "$user $pass $exp"; cat "$DB"; } > "$tmp" && cat "$tmp" > "$DB"
  rm -f "$tmp"

  systemctl restart zivpn

  header "ZIVPN ACCOUNT"
  echo -e "$TOP"
  echo -e "${LN}┃${NC}  ${GR}User $user added successfully!${NC}"
  echo -e "${LN}┃${NC}"
  echo -e "${LN}┃${NC}  IPV4      : $MYIP"
  echo -e "${LN}┃${NC}  Domain    : $DOMAIN"
  echo -e "${LN}┃${NC}  Password  : $pass"
  echo -e "${LN}┃${NC}  Expiry    : $exp"
  echo -e "$BOT"
  echo -e "$END"
  pause
}

del_zivpn() {
  header "DELETE ZIVPN ACCOUNT"
  if [[ ! -s "$DB" ]]; then
    echo -e "${LN}┃${NC} [**] ${RD}No users found.${NC}"
    pause; return
  fi
  print_table
  echo ""
  local user line pass tmp
  read -rp "  Enter username to delete: " user
  if [[ -z "$user" ]]; then
    echo -e "  [**] ${RD}Username cannot be empty.${NC}"; pause; return
  fi
  line=$(awk -v u="$user" '$1==u {print; exit}' "$DB")
  if [[ -z "$line" ]]; then
    echo -e "  [**] ${RD}Username '$user' not found.${NC}"; pause; return
  fi
  pass=$(echo "$line" | awk '{print $2}')

  sed -i "/^[[:space:]]*\"$pass\",\?[[:space:]]*$/d" "$CFG"
  fix_json

  tmp=$(mktemp)
  awk -v u="$user" '$1!=u' "$DB" > "$tmp" && cat "$tmp" > "$DB"
  rm -f "$tmp"

  systemctl restart zivpn
  echo -e "  [**] ${GR}User $user deleted successfully.${NC}"
  echo -e "$END"
  pause
}

renew_zivpn() {
  header "RENEW ZIVPN ACCOUNT"
  if [[ ! -s "$DB" ]]; then
    echo -e "${LN}┃${NC} [**] ${RD}No users found.${NC}"
    pause; return
  fi
  print_table
  echo ""
  local user line current_exp add_days new_exp tmp
  read -rp "  Enter username to renew: " user
  if [[ -z "$user" ]]; then
    echo -e "  ${RD}Username cannot be empty.${NC}"; pause; return
  fi
  line=$(awk -v u="$user" '$1==u {print; exit}' "$DB")
  if [[ -z "$line" ]]; then
    echo -e "  ${RD}Username '$user' not found.${NC}"; pause; return
  fi
  current_exp=$(echo "$line" | awk '{print $3}' | tr -d '\r')
  read -rp "  Enter additional days: " add_days
  if [[ ! "$add_days" =~ ^[0-9]+$ || "$add_days" -le 0 ]]; then
    echo -e "  ${RD}Invalid number of days.${NC}"; pause; return
  fi
  new_exp=$(date -d "$current_exp +$add_days days" +"%Y-%m-%d")

  tmp=$(mktemp)
  awk -v u="$user" -v n="$new_exp" '$1==u{$3=n} 1' "$DB" > "$tmp" && cat "$tmp" > "$DB"
  rm -f "$tmp"

  header "RENEW ZIVPN ACCOUNT"
  echo -e "$TOP"
  echo -e "${LN}┃${NC} ${GR}User $user renewed successfully!${NC}"
  echo -e "${LN}┃${NC}"
  echo -e "${LN}┃${NC} Username   : $user"
  echo -e "${LN}┃${NC} Old expiry : $current_exp"
  echo -e "${LN}┃${NC} New expiry : $new_exp"
  echo -e "${LN}┃${NC} Day Added  : $add_days"
  echo -e "$BOT"
  echo -e "$END"
  pause
}

list_zivpn() {
  header "ZIVPN ACCOUNT LIST"
  if [[ ! -s "$DB" ]]; then
    echo -e "${LN}┃${NC} [**] No users found."
  else
    print_table
  fi
  echo -e "$END"
  pause
}

menu_zivpn() {
  local opt
  while true; do
    header "ZIVPN MENU"
    echo -e "$TOP"
    echo -e "${LN}┃${NC} [01] • Create Account      [03] • Delete Account"
    echo -e "${LN}┃${NC} [02] • Extend Account      [04] • Account List"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} [00] • Back to Main Menu"
    echo -e "$BOT"
    echo -e "$END"
    echo ""
    read -rp "  Select menu : " opt
    case $opt in
      1 | 01) add_zivpn ;;
      2 | 02) renew_zivpn ;;
      3 | 03) del_zivpn ;;
      4 | 04) list_zivpn ;;
      0 | 00) clear; menu; return ;;
      *) echo -e "${RD} [ERROR] Invalid selection!${NC}"; sleep 1 ;;
    esac
  done
}

menu_zivpn
