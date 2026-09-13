#!/bin/bash

# ============================================================
# ZIVPN ACCOUNT MANAGER
# Create / Renew / Delete / List
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
# INITIALIZE ZIVPN FILES
# ============================================================

init_zivpn_files() {

    # Create directory
    if [[ ! -d "$ZIVPN_DIR" ]]; then
        mkdir -p "$ZIVPN_DIR"
    fi

    # Create database if missing
    if [[ ! -f "$USER_DB" ]]; then
        touch "$USER_DB"
        chmod 600 "$USER_DB"
    fi

    # Remove Windows CR characters if present
    if [[ -f "$USER_DB" ]]; then
        sed -i 's/\r$//' "$USER_DB"
    fi
}

# ============================================================
# CHECK CONFIG
# ============================================================

check_zivpn_config() {

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "  ${RD}[ERROR] ZIVPN config not found:${NC}"
        echo -e "  ${YL}$CONFIG_FILE${NC}"
        echo ""
        read -n 1 -s -r -p "  Press any key to return..."
        return 1
    fi

    # Validate JSON if python is available
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
            echo -e "  ${RD}[ERROR] Invalid ZIVPN config.json${NC}"
            echo ""
            read -n 1 -s -r -p "  Press any key to return..."
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

    echo -e "  ${YL}[WARNING] zivpn.service was not found.${NC}"
    return 1
}

# ============================================================
# ADD PASSWORD TO CONFIG.JSON
# ============================================================

add_password_to_config() {

    local password="$1"

    python3 - "$CONFIG_FILE" "$password" <<'PY'
import json
import sys
import os

config_file = sys.argv[1]
password = sys.argv[2]

try:
    with open(config_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Locate the password list.
    # Expected structure:
    # {
    #     "config": [...]
    # }

    if "config" not in data:
        data["config"] = []

    if not isinstance(data["config"], list):
        raise ValueError("config must be a list")

    if password not in data["config"]:
        data["config"].append(password)

    tmp_file = config_file + ".tmp"

    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
        f.write("\n")

    os.replace(tmp_file, config_file)

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

    tmp_file = config_file + ".tmp"

    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
        f.write("\n")

    os.replace(tmp_file, config_file)

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PY
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

    printf "${LN}┃ %-5s %-18s %-18s %-12s${NC}\n" \
        "No." "Username" "Password" "Expiry"

    echo -e "${LN}┃${NC}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local i=1
    local username
    local password
    local expiry

    while IFS=' ' read -r username password expiry _; do

        # Skip empty/broken lines
        [[ -z "$username" ]] && continue

        printf "${LN}┃${NC} %-5s %-18s %-18s %-12s\n" \
            "$i" "$username" "$password" "$expiry"

        ((i++))

    done < "$USER_DB"

    return 0
}

# ============================================================
# ADD ZIVPN ACCOUNT
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
            echo -e "  ${YL}Use only letters, numbers and underscore.${NC}"
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

    # Add password to config first
    if ! add_password_to_config "$pass"; then
        echo -e "  ${RD}[ERROR] Unable to update config.json${NC}"
        echo ""
        read -n 1 -s -r -p "  Press any key..."
        return
    fi

    # Add account to database
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
    echo -e "${LN}┃${NC}  Username  : $user"
    echo -e "${LN}┃${NC}  IPV4      : $MYIP"
    echo -e "${LN}┃${NC}  Domain    : $DOMAIN"
    echo -e "${LN}┃${NC}  Password  : $pass"
    echo -e "${LN}┃${NC}  Expiry    : $exp"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    read -n 1 -s -r -p " Press any key to return to menu..."

    menu_zivpn
}

# ============================================================
# DELETE ZIVPN ACCOUNT
# ============================================================

del_zivpn() {

    init_zivpn_files

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              DELETE ZIVPN ACCOUNT              ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "${LN}┃${NC}  ${YL}No users found.${NC}"
        echo ""

        read -n 1 -s -r -p "  Press any key to return..."

        menu_zivpn
        return
    fi

    show_zivpn_users

    echo ""
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    read -rp "  Enter username to delete: " user

    if [[ -z "$user" ]]; then
        echo -e "  ${RD}Username cannot be empty.${NC}"
        read -n 1 -s -r -p "  Press any key..."
        menu_zivpn
        return
    fi

    # Find exact user line
    line=$(awk -v u="$user" '$1 == u {print; exit}' "$USER_DB")

    if [[ -z "$line" ]]; then

        echo -e "  ${RD}Username '$user' not found.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    pass=$(printf '%s\n' "$line" | awk '{print $2}')

    # Remove password from config
    if ! remove_password_from_config "$pass"; then
        echo -e "  ${RD}[ERROR] Could not update config.json${NC}"
        read -n 1 -s -r -p "  Press any key..."
        menu_zivpn
        return
    fi

    # Remove exact username line
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
# RENEW ZIVPN ACCOUNT
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
        echo ""

        read -n 1 -s -r -p "  Press any key to return..."

        menu_zivpn
        return
    fi

    show_zivpn_users

    echo ""
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
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

    current_exp=$(printf '%s\n' "$line" | awk '{print $3}')
    password=$(printf '%s\n' "$line" | awk '{print $2}')

    while true; do

        read -rp "  Enter additional days: " add_days

        if [[ ! "$add_days" =~ ^[0-9]+$ ]] || [[ "$add_days" -le 0 ]]; then
            echo -e "  ${RD}Invalid number of days.${NC}"
            continue
        fi

        break
    done

    # If current expiration is already past,
    # renew from today instead of the old expiration date.
    today=$(date +%Y-%m-%d)

    if [[ "$current_exp" < "$today" ]]; then
        new_exp=$(date -d "+${add_days} days" +"%Y-%m-%d")
    else
        new_exp=$(date -d "${current_exp} +${add_days} days" +"%Y-%m-%d")
    fi

    # Replace exact user line
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
    echo -e "${LN}┃${NC}  Username   : $user"
    echo -e "${LN}┃${NC}  Old expiry : $current_exp"
    echo -e "${LN}┃${NC}  New expiry : $new_exp"
    echo -e "${LN}┃${NC}  Days added : $add_days"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""

    read -n 1 -s -r -p "   Press any key to return to menu..."

    menu_zivpn
}

# ============================================================
# LIST ZIVPN ACCOUNTS
# ============================================================

list_zivpn() {

    init_zivpn_files

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                ZIVPN ACCOUNT LIST              ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "${LN}┃${NC}  ${YL}No ZIVPN users found.${NC}"
        echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
        echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"
        echo ""

        read -n 1 -s -r -p " Press any key to return..."

        menu_zivpn
        return
    fi

    show_zivpn_users

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"
    echo ""

    read -n 1 -s -r -p " Press any key to return..."

    menu_zivpn
}

# ============================================================
# ZIVPN MENU
# ============================================================

menu_zivpn() {

    clear

    # Reinitialize files every time menu opens
    init_zivpn_files

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                  ZIVPN MENU                    ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} [01] • Create Account      [03] • Delete Account"
    echo -e "${LN}┃${NC} [02] • Extend Account      [04] • Account List"
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

        0|00)
            clear
            menu
            ;;

        *)
            echo ""
            echo -e "  ${RD}[ERROR] Invalid selection!${NC}"
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