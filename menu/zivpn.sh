#!/bin/bash

clear

# ============================================================
#                 ZIVPN ACCOUNT MANAGER
# ============================================================

export LN='\e[34m'
export BG='\e[44m'
export NC='\e[0m'
export GR='\e[32m'
export RD='\e[31m'
export GREEN='\e[32m'
export YL='\e[33m'

ZIVPN_DIR="/etc/zivpn"
USER_DB="$ZIVPN_DIR/user.db"
CONFIG="$ZIVPN_DIR/config.json"

DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "N/A")
MYIP=$(wget -qO- -T 5 ipv4.icanhazip.com 2>/dev/null || echo "N/A")

# ------------------------------------------------------------
# Initialisation
# ------------------------------------------------------------

init_zivpn_files() {
    mkdir -p "$ZIVPN_DIR"

    if [[ ! -f "$USER_DB" ]]; then
        touch "$USER_DB"
        chmod 600 "$USER_DB"
    fi

    if [[ ! -f "$CONFIG" ]]; then
        echo '{"config":[]}' > "$CONFIG"
    fi
}

# ------------------------------------------------------------
# Vérification JSON
# ------------------------------------------------------------

check_zivpn_config() {
    [[ -f "$CONFIG" ]] || return 1

    python3 - "$CONFIG" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, dict):
        sys.exit(1)

    if "config" not in data:
        sys.exit(1)

    if not isinstance(data["config"], list):
        sys.exit(1)

except Exception:
    sys.exit(1)
PY
}

# ------------------------------------------------------------
# Ajouter le mot de passe dans config.json
# ------------------------------------------------------------

zivpn_add_password() {
    local password="$1"

    python3 - "$CONFIG" "$password" <<'PY'
import json
import sys
import tempfile
import os

config_file = sys.argv[1]
password = sys.argv[2]

try:
    with open(config_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, dict):
        data = {}

    if not isinstance(data.get("config"), list):
        data["config"] = []

    if password not in data["config"]:
        data["config"].append(password)

    directory = os.path.dirname(config_file) or "."

    fd, tmp = tempfile.mkstemp(
        prefix=".zivpn_config.",
        dir=directory,
        text=True
    )

    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    os.replace(tmp, config_file)

except Exception as e:
    print("ERROR:", e)
    sys.exit(1)
PY
}

# ------------------------------------------------------------
# Supprimer le mot de passe de config.json
# ------------------------------------------------------------

zivpn_remove_password() {
    local password="$1"

    python3 - "$CONFIG" "$password" <<'PY'
import json
import sys
import tempfile
import os

config_file = sys.argv[1]
password = sys.argv[2]

try:
    with open(config_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, dict):
        sys.exit(1)

    if not isinstance(data.get("config"), list):
        sys.exit(1)

    data["config"] = [
        item for item in data["config"]
        if str(item) != password
    ]

    directory = os.path.dirname(config_file) or "."

    fd, tmp = tempfile.mkstemp(
        prefix=".zivpn_config.",
        dir=directory,
        text=True
    )

    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    os.replace(tmp, config_file)

except Exception as e:
    print("ERROR:", e)
    sys.exit(1)
PY
}

# ------------------------------------------------------------
# Redémarrage ZiVPN
# ------------------------------------------------------------

restart_zivpn() {
    if systemctl restart zivpn >/dev/null 2>&1; then
        return 0
    fi

    echo -e "  ${YL}[!] Impossible de redémarrer le service ZiVPN.${NC}"
    return 1
}

# ------------------------------------------------------------
# Affichage des utilisateurs
# ------------------------------------------------------------

show_zivpn_users() {
    init_zivpn_files

    if [[ ! -s "$USER_DB" ]]; then
        echo -e "${LN}┃${NC} ${YL}Aucun utilisateur ZiVPN.${NC}"
        return 1
    fi

    printf "${LN}┃ %-4s %-16s %-16s %-12s %-10s ${NC}\n" \
        "No." "Username" "Password" "Expiry" "Status"

    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"

    local i=1
    local username
    local password
    local expiry
    local status
    local today

    today=$(date +%s)

    while read -r username password expiry _; do

        [[ -z "$username" ]] && continue
        [[ "$username" == \#* ]] && continue

        if [[ -z "$password" || -z "$expiry" ]]; then
            continue
        fi

        if date -d "$expiry" >/dev/null 2>&1; then
            expiry_ts=$(date -d "$expiry" +%s)

            if (( expiry_ts < today )); then
                status="${RD}EXPIRED${NC}"
            else
                status="${GR}ACTIVE${NC}"
            fi
        else
            status="${RD}INVALID${NC}"
        fi

        printf "${LN}┃ %-4s %-16s %-16s %-12s %-10b ${NC}\n" \
            "$i" "$username" "$password" "$expiry" "$status"

        ((i++))

    done < "$USER_DB"

    return 0
}

# ------------------------------------------------------------
# CREATE ACCOUNT
# ------------------------------------------------------------

add_zivpn() {

    clear

    init_zivpn_files

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}               ADD ZIVPN ACCOUNT                ${NC}${LN}┃${NC}"
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

        read -rp "  Enter password: " pass

        if [[ -z "$pass" ]]; then
            echo -e "  ${RD}Password cannot be empty.${NC}"
            continue
        fi

        # Évite les problèmes avec user.db et JSON
        if [[ ! "$pass" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo -e "  ${RD}Invalid password.${NC}"
            echo -e "  ${YL}Use letters, numbers, _ or -.${NC}"
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

        if [[ -z "$days" || ! "$days" =~ ^[0-9]+$ || "$days" -le 0 ]]; then
            echo -e "  ${RD}Expiry days must be a positive number.${NC}"
            continue
        fi

        break
    done

    exp=$(date -d "+${days} days" +"%Y-%m-%d")

    # Ajouter dans config.json
    if ! zivpn_add_password "$pass"; then
        echo -e "  ${RD}Failed to update config.json.${NC}"
        read -n 1 -s -r -p "  Press any key..."
        menu_zivpn
        return
    fi

    # Ajouter dans user.db
    echo "$user $pass $exp" >> "$USER_DB"

    chmod 600 "$USER_DB"

    restart_zivpn

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                  ZIVPN ACCOUNT                 ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${GREEN}User $user added successfully!${NC}"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC}  IPV4      : $MYIP"
    echo -e "${LN}┃${NC}  Domain    : $DOMAIN"
    echo -e "${LN}┃${NC}  Username  : $user"
    echo -e "${LN}┃${NC}  Password  : $pass"
    echo -e "${LN}┃${NC}  Expiry    : $exp"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo ""

    read -n 1 -s -r -p " Press any key to return to menu..."

    menu_zivpn
}

# ------------------------------------------------------------
# DELETE ACCOUNT
# ------------------------------------------------------------

del_zivpn() {

    clear

    init_zivpn_files

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              DELETE ZIVPN ACCOUNT              ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo ""

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "${LN}┃${NC} ${RD}No users found.${NC}"
        echo ""

        read -n 1 -s -r -p "  Press any key to return..."

        menu_zivpn
        return
    fi

    show_zivpn_users

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
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

    password=$(echo "$line" | awk '{print $2}')

    echo ""
    echo -e "  ${YL}Account selected:${NC} $user"
    echo -e "  ${YL}Password:${NC} $password"

    read -rp "  Confirm deletion [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then

        echo -e "  ${YL}Deletion cancelled.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    # Supprimer du JSON
    if ! zivpn_remove_password "$password"; then
        echo -e "  ${RD}Failed to update config.json.${NC}"
        read -n 1 -s -r -p "  Press any key..."
        menu_zivpn
        return
    fi

    # Supprimer de user.db
    awk -v u="$user" '$1 != u' "$USER_DB" > "${USER_DB}.tmp" &&
        mv "${USER_DB}.tmp" "$USER_DB"

    chmod 600 "$USER_DB"

    restart_zivpn

    echo ""
    echo -e "  ${GREEN}✓ User '$user' deleted successfully.${NC}"
    echo -e "  ${GREEN}✓ Removed from user.db.${NC}"
    echo -e "  ${GREEN}✓ Password removed from config.json.${NC}"

    echo ""

    read -n 1 -s -r -p "  Press any key to return..."

    menu_zivpn
}

# ------------------------------------------------------------
# RENEW ACCOUNT
# ------------------------------------------------------------

renew_zivpn() {

    clear

    init_zivpn_files

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              RENEW ZIVPN ACCOUNT               ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo ""

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "  ${RD}No users found.${NC}"

        read -n 1 -s -r -p "  Press any key to return..."

        menu_zivpn
        return
    fi

    show_zivpn_users

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

    password=$(echo "$line" | awk '{print $2}')
    current_exp=$(echo "$line" | awk '{print $3}')

    echo ""
    echo -e "  ${YL}Current expiry:${NC} $current_exp"

    read -rp "  Enter additional days: " add_days

    if [[ -z "$add_days" || ! "$add_days" =~ ^[0-9]+$ || "$add_days" -le 0 ]]; then

        echo -e "  ${RD}Invalid number of days.${NC}"

        read -n 1 -s -r -p "  Press any key..."

        menu_zivpn
        return
    fi

    # Si le compte est déjà expiré,
    # on renouvelle à partir d'aujourd'hui.
    current_ts=$(date -d "$current_exp" +%s 2>/dev/null || echo 0)
    today_ts=$(date +%s)

    if (( current_ts < today_ts )); then
        new_exp=$(date -d "+${add_days} days" +"%Y-%m-%d")
    else
        new_exp=$(date -d "$current_exp +${add_days} days" +"%Y-%m-%d")
    fi

    awk -v u="$user" -v p="$password" -v e="$new_exp" '
        $1 == u {$0=u" "p" "e}
        {print}
    ' "$USER_DB" > "${USER_DB}.tmp" &&
        mv "${USER_DB}.tmp" "$USER_DB"

    chmod 600 "$USER_DB"

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}               ZIVPN ACCOUNT                   ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${GREEN}User renewed successfully!${NC}"
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

# ------------------------------------------------------------
# LIST ACCOUNTS
# ------------------------------------------------------------

list_zivpn() {

    clear

    init_zivpn_files

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}               ZIVPN ACCOUNT LIST               ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"

    if [[ ! -s "$USER_DB" ]]; then

        echo -e "${LN}┃${NC} ${YL}No users found.${NC}"

    else

        show_zivpn_users

    fi

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"

    echo ""

    read -n 1 -s -r -p " Press any key to return to menu..."

    menu_zivpn
}

# ------------------------------------------------------------
# MENU
# ------------------------------------------------------------

menu_zivpn() {

    clear

    init_zivpn_files

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                  ZIVPN MENU                    ${NC}${LN}┃${NC}"
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
            echo -e "${RD} [ERROR] Invalid selection!${NC}"
            sleep 1
            menu_zivpn
            ;;

    esac
}

# ------------------------------------------------------------
# START
# ------------------------------------------------------------

menu_zivpn