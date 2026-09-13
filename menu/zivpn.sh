#!/bin/bash

# ============================================================
# ZIVPN ACCOUNT MANAGER
# Create / Renew / Delete / List
# Connections / Quota / Usage
# ============================================================

clear

# ============================================================
# COLORS
# ============================================================

export LN='\e[34m'
export BG='\e[44m'
export NC='\e[0m'
export GR='\e[32m'
export RD='\e[31m'
export YL='\e[33m'
export CY='\e[36m'
export WH='\e[37m'

# ============================================================
# PATHS
# ============================================================

ZIVPN_DIR="/etc/zivpn"
USER_DB="${ZIVPN_DIR}/user.db"
CONFIG_FILE="${ZIVPN_DIR}/config.json"

DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "N/A")
MYIP=$(wget -qO- -T 5 ipv4.icanhazip.com 2>/dev/null || echo "N/A")

# ============================================================
# DEFAULT QUOTA
# ============================================================

# Quota par défaut en GB.
# Modifier cette valeur si nécessaire.
DEFAULT_QUOTA_GB=10

# ============================================================
# INITIALIZE ZIVPN FILES
# ============================================================

init_zivpn_files() {

    mkdir -p "$ZIVPN_DIR"

    if [[ ! -f "$USER_DB" ]]; then
        touch "$USER_DB"
    fi

    chmod 600 "$USER_DB"

    # Remove Windows CRLF
    sed -i 's/\r$//' "$USER_DB" 2>/dev/null
}

# ============================================================
# CHECK CONFIG
# ============================================================

check_zivpn_config() {

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "  ${RD}[ERROR] ZIVPN config not found:${NC}"
        echo -e "  ${YL}$CONFIG_FILE${NC}"
        return 1
    fi

    if command -v python3 >/dev/null 2>&1; then

        if ! python3 - "$CONFIG_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        json.load(f)
except Exception:
    sys.exit(1)
PY
        then
            echo -e "  ${RD}[ERROR] Invalid config.json${NC}"
            return 1
        fi
    fi

    return 0
}

# ============================================================
# RESTART ZIVPN
# ============================================================

restart_zivpn() {

    if systemctl list-unit-files 2>/dev/null | grep -q '^zivpn.service'; then

        systemctl restart zivpn >/dev/null 2>&1

        if systemctl is-active --quiet zivpn; then
            return 0
        fi

        echo -e "  ${YL}[WARNING] ZIVPN service is not running.${NC}"
        return 1
    fi

    echo -e "  ${YL}[WARNING] zivpn.service not found.${NC}"
    return 1
}

# ============================================================
# PASSWORD -> CONFIG.JSON
# ============================================================

add_password_to_config() {

    local password="$1"

    [[ ! -f "$CONFIG_FILE" ]] && return 1

    python3 - "$CONFIG_FILE" "$password" <<'PY'
import json
import sys
import os

config_file = sys.argv[1]
password = sys.argv[2]

try:

    with open(config_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    if "config" not in data:
        data["config"] = []

    if not isinstance(data["config"], list):
        raise ValueError("config must be a list")

    if password not in data["config"]:
        data["config"].append(password)

    tmp = config_file + ".tmp"

    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
        f.write("\n")

    os.replace(tmp, config_file)

except Exception as e:

    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PY
}

# ============================================================
# REMOVE PASSWORD FROM CONFIG.JSON
# ============================================================

remove_password_from_config() {

    local password="$1"

    [[ ! -f "$CONFIG_FILE" ]] && return 1

    python3 - "$CONFIG_FILE" "$password" <<'PY'
import json
import sys
import os

config_file = sys.argv[1]
password = sys.argv[2]

try:

    with open(config_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    if "config" in data and isinstance(data["config"], list):

        data["config"] = [
            item for item in data["config"]
            if str(item) != password
        ]

    tmp = config_file + ".tmp"

    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
        f.write("\n")

    os.replace(tmp, config_file)

except Exception as e:

    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PY
}

# ============================================================
# CONNECTION COUNTER
# ============================================================

get_connected_users() {

    local user="$1"
    local count=0

    # --------------------------------------------------------
    # IMPORTANT:
    # This searches current ZIVPN processes/connections.
    # If your ZIVPN exposes another session database/API,
    # replace this section with the official ZIVPN command.
    # --------------------------------------------------------

    if command -v ss >/dev/null 2>&1; then

        count=$(ss -u -n -p 2>/dev/null |
            grep -i "zivpn" |
            grep -F "$user" |
            wc -l)

    fi

    echo "$count"
}

# ============================================================
# TRAFFIC USAGE
# ============================================================

get_user_usage() {

    local user="$1"

    # --------------------------------------------------------
    # Placeholder until the installed ZIVPN exposes
    # per-user traffic statistics.
    #
    # We return 0 GB instead of inventing traffic numbers.
    # --------------------------------------------------------

    echo "0.00"
}

# ============================================================
# USER QUOTA
# ============================================================

get_user_quota() {

    local user="$1"

    # Current default quota.
    # Can later be replaced by a per-user quota database.
    echo "$DEFAULT_QUOTA_GB"
}

# ============================================================
# REMAINING QUOTA
# ============================================================

get_user_remaining() {

    local user="$1"

    local quota
    local used

    quota=$(get_user_quota "$user")
    used=$(get_user_usage "$user")

    awk -v q="$quota" -v u="$used" '
    BEGIN {
        r=q-u
        if (r < 0)
            r=0
        printf "%.2f", r
    }'
}

# ============================================================
# SHOW USERS
# ============================================================

show_zivpn_users() {

    init_zivpn_files

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "${LN}┃${NC}  ${YL}No ZIVPN users found.${NC}"
        return 1
    fi

    printf "${LN}┃ %-4s %-15s %-15s %-12s %-7s %-9s %-9s${NC}\n" \
        "No." \
        "Username" \
        "Password" \
        "Expiry" \
        "Conn." \
        "Used" \
        "Quota"

    echo -e "${LN}┃${NC}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local i=1
    local username
    local password
    local expiry

    while IFS=' ' read -r username password expiry _; do

        [[ -z "$username" ]] && continue

        local connected
        local used
        local quota

        connected=$(get_connected_users "$username")
        used=$(get_user_usage "$username")
        quota=$(get_user_quota "$username")

        printf "${LN}┃${NC} %-4s %-15s %-15s %-12s %-7s %-9s %-9s\n" \
            "$i" \
            "$username" \
            "$password" \
            "$expiry" \
            "$connected" \
            "${used}GB" \
            "${quota}GB"

        ((i++))

    done < "$USER_DB"

    echo -e "${LN}┃${NC}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    return 0
}

# ============================================================
# ACCOUNT DETAILS
# ============================================================

show_account_details() {

    local user="$1"

    local line
    local password
    local expiry
    local connected
    local used
    local quota
    local remaining

    line=$(awk -v u="$user" '$1 == u {print; exit}' "$USER_DB")

    if [[ -z "$line" ]]; then
        return 1
    fi

    password=$(echo "$line" | awk '{print $2}')
    expiry=$(echo "$line" | awk '{print $3}')

    connected=$(get_connected_users "$user")
    used=$(get_user_usage "$user")
    quota=$(get_user_quota "$user")
    remaining=$(get_user_remaining "$user")

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                 ACCOUNT STATUS                 ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo -e "${LN}┃${NC} Username     : $user"
    echo -e "${LN}┃${NC} Password     : $password"
    echo -e "${LN}┃${NC} Expiry       : $expiry"
    echo -e "${LN}┃${NC} Connected    : $connected"
    echo -e "${LN}┃${NC} Used         : ${used} GB"
    echo -e "${LN}┃${NC} Quota        : ${quota} GB"
    echo -e "${LN}┃${NC} Remaining    : ${remaining} GB"

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

# ============================================================
# ADD ACCOUNT
# ============================================================

add_zivpn() {

    init_zivpn_files

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}               ADD ZIVPN ACCOUNT                ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    while true; do

        read -rp "  Enter username: " user

        if [[ -z "$user" ]]; then
            echo -e "  ${RD}Username cannot be empty.${NC}"
            continue
        fi

        if [[ ! "$user" =~ ^[a-zA-Z0-9_]+$ ]]; then
            echo -e "  ${RD}Invalid username.${NC}"
            echo -e "  ${YL}Use letters, numbers and underscore only.${NC}"
            continue
        fi

        if awk -v u="$user" '$1 == u {found=1} END {exit !found}' "$USER_DB"; then
            echo -e "  ${RD}Username already exists.${NC}"
            continue
        fi

        break
    done

    while true; do

        read -rsp "  Enter password: " pass
        echo ""

        if [[ -z "$pass" ]]; then
            echo -e "  ${RD}Password cannot be empty.${NC}"
            continue
        fi

        if [[ "$pass" =~ [[:space:]] ]]; then
            echo -e "  ${RD}Password cannot contain spaces.${NC}"
            continue
        fi

        if awk -v p="$pass" '$2 == p {found=1} END {exit !found}' "$USER_DB"; then
            echo -e "  ${RD}Password already in use.${NC}"
            continue
        fi

        break
    done

    while true; do

        read -rp "  Validity (days): " days

        if [[ ! "$days" =~ ^[0-9]+$ ]] || [[ "$days" -le 0 ]]; then
            echo -e "  ${RD}Expiry days must be a positive number.${NC}"
            continue
        fi

        break
    done

    exp=$(date -d "+${days} days" +"%Y-%m-%d")

    if ! check_zivpn_config; then

        read -n 1 -s -r -p "  Press any key..."
        menu_zivpn
        return
    fi

    if ! add_password_to_config "$pass"; then

        echo -e "  ${RD}[ERROR] Unable to update config.json${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    printf '%s %s %s\n' "$user" "$pass" "$exp" >> "$USER_DB"

    chmod 600 "$USER_DB"

    restart_zivpn >/dev/null 2>&1

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                  ZIVPN ACCOUNT                 ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC}  ${GR}User added successfully!${NC}"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} Username  : $user"
    echo -e "${LN}┃${NC} IPV4      : $MYIP"
    echo -e "${LN}┃${NC} Domain    : $DOMAIN"
    echo -e "${LN}┃${NC} Password  : $pass"
    echo -e "${LN}┃${NC} Expiry    : $exp"
    echo -e "${LN}┃${NC} Quota     : ${DEFAULT_QUOTA_GB} GB"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    read -n 1 -s -r -p " Press any key to return to menu..."

    menu_zivpn
}

# ============================================================
# DELETE ACCOUNT
# ============================================================

del_zivpn() {

    init_zivpn_files

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              DELETE ZIVPN ACCOUNT              ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "  ${YL}No users found.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    show_zivpn_users

    echo ""
    read -rp "  Enter username to delete: " user

    if [[ -z "$user" ]]; then

        echo -e "  ${RD}Username cannot be empty.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    line=$(awk -v u="$user" '$1 == u {print; exit}' "$USER_DB")

    if [[ -z "$line" ]]; then

        echo -e "  ${RD}Username '$user' not found.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    pass=$(echo "$line" | awk '{print $2}')

    if ! remove_password_from_config "$pass"; then

        echo -e "  ${RD}[ERROR] Could not update config.json${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    awk -v u="$user" '$1 != u' "$USER_DB" > "${USER_DB}.tmp"

    mv "${USER_DB}.tmp" "$USER_DB"

    chmod 600 "$USER_DB"

    restart_zivpn >/dev/null 2>&1

    echo ""
    echo -e "  ${GR}[OK] User '$user' deleted successfully.${NC}"
    echo ""

    read -n 1 -s -r -p "  Press any key to return to menu..."

    menu_zivpn
}

# ============================================================
# RENEW ACCOUNT
# ============================================================

renew_zivpn() {

    init_zivpn_files

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              RENEW ZIVPN ACCOUNT               ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "  ${YL}No users found.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    show_zivpn_users

    echo ""
    read -rp "  Enter username to renew: " user

    if [[ -z "$user" ]]; then

        echo -e "  ${RD}Username cannot be empty.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    line=$(awk -v u="$user" '$1 == u {print; exit}' "$USER_DB")

    if [[ -z "$line" ]]; then

        echo -e "  ${RD}Username '$user' not found.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    current_exp=$(echo "$line" | awk '{print $3}')
    password=$(echo "$line" | awk '{print $2}')

    while true; do

        read -rp "  Enter additional days: " add_days

        if [[ ! "$add_days" =~ ^[0-9]+$ ]] || [[ "$add_days" -le 0 ]]; then
            echo -e "  ${RD}Invalid number of days.${NC}"
            continue
        fi

        break
    done

    today=$(date +%Y-%m-%d)

    if [[ "$current_exp" < "$today" ]]; then
        new_exp=$(date -d "+${add_days} days" +"%Y-%m-%d")
    else
        new_exp=$(date -d "${current_exp} +${add_days} days" +"%Y-%m-%d")
    fi

    awk -v u="$user" \
        -v p="$password" \
        -v e="$new_exp" \
        '$1 == u {$0=u" "p" "e} {print}' \
        "$USER_DB" > "${USER_DB}.tmp"

    mv "${USER_DB}.tmp" "$USER_DB"

    chmod 600 "$USER_DB"

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              ZIVPN ACCOUNT RENEW              ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC}  ${GR}User renewed successfully!${NC}"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} Username   : $user"
    echo -e "${LN}┃${NC} Old expiry : $current_exp"
    echo -e "${LN}┃${NC} New expiry : $new_exp"
    echo -e "${LN}┃${NC} Days added : $add_days"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    read -n 1 -s -r -p " Press any key to return to menu..."

    menu_zivpn
}

# ============================================================
# LIST ACCOUNTS
# ============================================================

list_zivpn() {

    init_zivpn_files

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                 ZIVPN ACCOUNT LIST                         ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "${LN}┃${NC}  ${YL}No ZIVPN users found.${NC}"

        echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

        read -n 1 -s -r -p " Press any key to return..."

        menu_zivpn
        return
    fi

    show_zivpn_users

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"
    echo ""

    read -n 1 -s -r -p " Press any key to return..."

    menu_zivpn
}

# ============================================================
# ACCOUNT INFORMATION
# ============================================================

account_info_zivpn() {

    init_zivpn_files

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              ZIVPN ACCOUNT INFO                ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "  ${YL}No users found.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    show_zivpn_users

    echo ""
    read -rp "  Enter username: " user

    if [[ -z "$user" ]]; then
        menu_zivpn
        return
    fi

    clear

    show_account_details "$user"

    echo ""

    read -n 1 -s -r -p " Press any key to return..."

    menu_zivpn
}

# ============================================================
# ZIVPN MENU
# ============================================================

menu_zivpn() {

    clear

    init_zivpn_files

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                  ZIVPN MENU                    ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} [01] • Create Account      [03] • Delete Account"
    echo -e "${LN}┃${NC} [02] • Extend Account      [04] • Account List"
    echo -e "${LN}┃${NC} [05] • Account Information"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} [00] • Back to Main Menu"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"
    echo ""

    read -rp "  Select menu : " opt

    case "$opt" in

        1|01)
            add_zivpn
            ;;

        2|02)
            renew_zivpn
            ;;

        3|03)
            del_zivpn
            ;;

        4|04)
            list_zivpn
            ;;

        5|05)
            account_info_zivpn
            ;;

        0|00)
            clear
            menu
            ;;

        *)
            echo ""
            echo -e "${RD} [ERROR] Invalid selection!${NC}"
            sleep 1
            menu_zivpn
            ;;

    esac
}

# ============================================================
# START
# ============================================================

init_zivpn_files
menu_zivpn