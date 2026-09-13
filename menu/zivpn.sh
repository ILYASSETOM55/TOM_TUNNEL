#!/bin/bash

# ============================================================
#  ZIVPN ACCOUNT MANAGER
# ============================================================

clear

export LN='\e[34m'
export BG='\e[44m'
export NC='\e[0m'
export GR='\e[32m'
export RD='\e[31m'
export YL='\e[33m'
export CY='\e[36m'
export DOMAIN="$(cat /etc/xray/domain 2>/dev/null || echo "N/A")"
export MYIP="$(wget -qO- -T 5 ipv4.icanhazip.com 2>/dev/null || echo "N/A")"

ZIVPN_DIR="/etc/zivpn"
ZIVPN_CONFIG="$ZIVPN_DIR/config.json"
ZIVPN_DB="$ZIVPN_DIR/user.db"

# ------------------------------------------------------------
# Vérification des fichiers
# ------------------------------------------------------------

init_zivpn_db() {
    mkdir -p "$ZIVPN_DIR"

    if [[ ! -f "$ZIVPN_DB" ]]; then
        touch "$ZIVPN_DB"
        chmod 600 "$ZIVPN_DB"
    fi

    if [[ ! -f "$ZIVPN_CONFIG" ]]; then
        echo -e "${RD}[ERROR] ZiVPN config.json introuvable.${NC}"
        return 1
    fi
}

# ------------------------------------------------------------
# Vérifier si le service existe
# ------------------------------------------------------------

zivpn_service_ok() {
    if ! systemctl list-unit-files 2>/dev/null | grep -q '^zivpn.service'; then
        echo -e "${RD}[ERROR] Service zivpn.service introuvable.${NC}"
        return 1
    fi

    return 0
}

# ------------------------------------------------------------
# Synchroniser les mots de passe user.db -> config.json
# ------------------------------------------------------------

sync_zivpn_config() {

    init_zivpn_db || return 1

    python3 - "$ZIVPN_CONFIG" "$ZIVPN_DB" <<'PY'
import json
import sys
import os

config_file = sys.argv[1]
db_file = sys.argv[2]

try:
    with open(config_file, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as e:
    print(f"[ERROR] Impossible de lire config.json: {e}")
    sys.exit(1)

passwords = []

if os.path.exists(db_file):
    with open(db_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()

            if not line:
                continue

            parts = line.split()

            if len(parts) >= 3:
                password = parts[1]
                expiry = parts[2]

                # Seulement les comptes encore valides
                from datetime import date

                try:
                    if date.fromisoformat(expiry) < date.today():
                        continue
                except Exception:
                    continue

                if password not in passwords:
                    passwords.append(password)

auth = data.setdefault("auth", {})
auth["mode"] = "passwords"
auth["config"] = passwords

tmp = config_file + ".tmp"

with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)

os.replace(tmp, config_file)

print(f"[OK] {len(passwords)} mot(s) de passe synchronisé(s).")
PY

    if [[ $? -ne 0 ]]; then
        echo -e "${RD}[ERROR] Échec de synchronisation.${NC}"
        return 1
    fi

    systemctl restart zivpn >/dev/null 2>&1

    return 0
}

# ------------------------------------------------------------
# Ajouter un compte
# ------------------------------------------------------------

add_zivpn() {

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              ADD ZIVPN ACCOUNT                 ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    init_zivpn_db || {
        read -n 1 -s -r -p " Press any key..."
        menu_zivpn
        return
    }

    while true; do

        read -rp "  Enter username: " user

        if [[ -z "$user" ]]; then
            echo -e "  ${RD}Username cannot be empty.${NC}"
            continue
        fi

        if [[ ! "$user" =~ ^[a-zA-Z0-9_]+$ ]]; then
            echo -e "  ${RD}Invalid username.${NC}"
            continue
        fi

        if awk -v u="$user" '$1 == u {found=1} END {exit !found}' "$ZIVPN_DB"; then
            echo -e "  ${RD}Username already exists.${NC}"
            continue
        fi

        break
    done

    while true; do

        read -rsp "  Enter password: " pass
        echo

        if [[ -z "$pass" ]]; then
            echo -e "  ${RD}Password cannot be empty.${NC}"
            continue
        fi

        if awk -v p="$pass" '$2 == p {found=1} END {exit !found}' "$ZIVPN_DB"; then
            echo -e "  ${RD}Password already in use.${NC}"
            continue
        fi

        break
    done

    while true; do

        read -rp "  Validity (days): " days

        if [[ ! "$days" =~ ^[0-9]+$ || "$days" -le 0 ]]; then
            echo -e "  ${RD}Invalid number of days.${NC}"
            continue
        fi

        break
    done

    exp=$(date -d "+$days days" +"%Y-%m-%d")

    echo "$user $pass $exp" >> "$ZIVPN_DB"

    if ! sync_zivpn_config; then
        sed -i "\|^${user} |d" "$ZIVPN_DB"
        echo -e "${RD}Account creation cancelled.${NC}"
        read -n 1 -s -r -p " Press any key..."
        menu_zivpn
        return
    fi

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              ZIVPN ACCOUNT CREATED              ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo -e "${LN}┃${NC} Username : ${GR}$user${NC}"
    echo -e "${LN}┃${NC} Password : ${GR}$pass${NC}"
    echo -e "${LN}┃${NC} Expiry   : ${GR}$exp${NC}"
    echo -e "${LN}┃${NC} Server   : ${GR}$MYIP${NC}"
    echo -e "${LN}┃${NC} Domain   : ${GR}$DOMAIN${NC}"

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    read -n 1 -s -r -p " Press any key to return..."
    menu_zivpn
}

# ------------------------------------------------------------
# Supprimer un compte
# ------------------------------------------------------------

del_zivpn() {

    clear

    init_zivpn_db || return

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              DELETE ZIVPN ACCOUNT               ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    if [[ ! -s "$ZIVPN_DB" ]]; then
        echo -e "${RD}No users found.${NC}"
        read -n 1 -s -r -p " Press any key..."
        menu_zivpn
        return
    fi

    list_zivpn false

    read -rp "  Enter username to delete: " user

    if [[ -z "$user" ]]; then
        echo -e "${RD}Username cannot be empty.${NC}"
        read -n 1 -s -r -p " Press any key..."
        menu_zivpn
        return
    fi

    line=$(awk -v u="$user" '$1 == u {print; exit}' "$ZIVPN_DB")

    if [[ -z "$line" ]]; then
        echo -e "${RD}Username '$user' not found.${NC}"
        read -n 1 -s -r -p " Press any key..."
        menu_zivpn
        return
    fi

    pass=$(awk '{print $2}' <<< "$line")

    read -rp "  Confirm deletion of '$user'? [y/N]: " confirm

    case "$confirm" in
        y|Y)
            ;;
        *)
            echo -e "${YL}Deletion cancelled.${NC}"
            read -n 1 -s -r -p " Press any key..."
            menu_zivpn
            return
            ;;
    esac

    sed -i "\|^${user}[[:space:]]|d" "$ZIVPN_DB"

    if ! sync_zivpn_config; then
        echo -e "${RD}Failed to update ZiVPN configuration.${NC}"
        read -n 1 -s -r -p " Press any key..."
        menu_zivpn
        return
    fi

    echo -e "${GR}User '$user' deleted successfully.${NC}"

    read -n 1 -s -r -p " Press any key..."
    menu_zivpn
}

# ------------------------------------------------------------
# Renouveler un compte
# ------------------------------------------------------------

renew_zivpn() {

    clear

    init_zivpn_db || return

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              RENEW ZIVPN ACCOUNT                ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    if [[ ! -s "$ZIVPN_DB" ]]; then
        echo -e "${RD}No users found.${NC}"
        read -n 1 -s -r -p " Press any key..."
        menu_zivpn
        return
    fi

    list_zivpn false

    read -rp "  Enter username to renew: " user

    line=$(awk -v u="$user" '$1 == u {print; exit}' "$ZIVPN_DB")

    if [[ -z "$line" ]]; then
        echo -e "${RD}Username '$user' not found.${NC}"
        read -n 1 -s -r -p " Press any key..."
        menu_zivpn
        return
    fi

    password=$(awk '{print $2}' <<< "$line")
    current_exp=$(awk '{print $3}' <<< "$line")

    read -rp "  Enter additional days: " add_days

    if [[ ! "$add_days" =~ ^[0-9]+$ || "$add_days" -le 0 ]]; then
        echo -e "${RD}Invalid number of days.${NC}"
        read -n 1 -s -r -p " Press any key..."
        menu_zivpn
        return
    fi

    today=$(date +%Y-%m-%d)

    if [[ "$current_exp" < "$today" ]]; then
        base_date="$today"
    else
        base_date="$current_exp"
    fi

    new_exp=$(date -d "$base_date + $add_days days" +"%Y-%m-%d")

    awk -v u="$user" -v p="$password" -v e="$new_exp" '
        $1 == u {$0=u" "p" "e}
        {print}
    ' "$ZIVPN_DB" > "$ZIVPN_DB.tmp"

    mv "$ZIVPN_DB.tmp" "$ZIVPN_DB"

    sync_zivpn_config

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}               ACCOUNT RENEWED                  ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo -e "${LN}┃${NC} Username   : ${GR}$user${NC}"
    echo -e "${LN}┃${NC} Old expiry : ${YL}$current_exp${NC}"
    echo -e "${LN}┃${NC} New expiry : ${GR}$new_exp${NC}"
    echo -e "${LN}┃${NC} Days added : ${GR}$add_days${NC}"

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    read -n 1 -s -r -p " Press any key to return..."
    menu_zivpn
}

# ------------------------------------------------------------
# Nettoyage des comptes expirés
# ------------------------------------------------------------

cleanup_expired_zivpn() {

    init_zivpn_db || return

    [[ ! -s "$ZIVPN_DB" ]] && return

    today=$(date +%Y-%m-%d)

    awk -v today="$today" '
        NF >= 3 && $3 >= today
    ' "$ZIVPN_DB" > "$ZIVPN_DB.tmp"

    if ! cmp -s "$ZIVPN_DB" "$ZIVPN_DB.tmp"; then
        mv "$ZIVPN_DB.tmp" "$ZIVPN_DB"
        sync_zivpn_config >/dev/null 2>&1
    else
        rm -f "$ZIVPN_DB.tmp"
    fi
}

# ------------------------------------------------------------
# Liste des comptes
# ------------------------------------------------------------

list_zivpn() {

    local return_menu="${1:-true}"

    clear

    cleanup_expired_zivpn

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                    ZIVPN ACCOUNT LIST                   ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    if [[ ! -s "$ZIVPN_DB" ]]; then
        echo -e "${LN}┃${NC} ${RD}No active users found.${NC}"
    else

        printf "${LN}┃ %-3s %-15s %-15s %-12s %-10s ${NC}\n" \
            "No." "Username" "Password" "Expiry" "Status"

        echo -e "${LN}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"

        i=1
        today=$(date +%Y-%m-%d)

        while read -r user pass exp; do

            [[ -z "$user" ]] && continue

            if [[ "$exp" < "$today" ]]; then
                status="${RD}EXPIRED${NC}"
            else
                status="${GR}ACTIVE${NC}"
            fi

            printf "${LN}┃ %-3s %-15s %-15s %-12s ${NC}%b\n" \
                "$i" "$user" "$pass" "$exp" "$status"

            ((i++))

        done < "$ZIVPN_DB"
    fi

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo ""
    echo -e "${CY}Note:${NC} ZiVPN standard utilise des mots de passe pour l'authentification."
    echo -e "${CY}Les usernames/date sont gérés par TOM TUNNEL.${NC}"

    if [[ "$return_menu" == "true" ]]; then
        echo ""
        read -n 1 -s -r -p " Press any key to return..."
        menu_zivpn
    fi
}

# ------------------------------------------------------------
# Statut ZiVPN
# ------------------------------------------------------------

zivpn_status() {

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                 ZIVPN STATUS                   ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    if systemctl is-active --quiet zivpn; then
        echo -e "${LN}┃${NC} Service : ${GR}ONLINE${NC}"
    else
        echo -e "${LN}┃${NC} Service : ${RD}OFFLINE${NC}"
    fi

    if [[ -f "$ZIVPN_CONFIG" ]]; then

        count=$(python3 - "$ZIVPN_CONFIG" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as f:
        d=json.load(f)

    print(len(d.get("auth", {}).get("config", [])))
except:
    print(0)
PY
)

        echo -e "${LN}┃${NC} Active passwords : ${GR}$count${NC}"
    else
        echo -e "${LN}┃${NC} Config : ${RD}MISSING${NC}"
    fi

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo ""
    read -n 1 -s -r -p " Press any key..."
    menu_zivpn
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------

menu_zivpn() {

    clear

    cleanup_expired_zivpn

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                  ZIVPN MENU                    ${NC}${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} [01] • Create Account      [04] • Account List"
    echo -e "${LN}┃${NC} [02] • Extend Account      [05] • ZiVPN Status"
    echo -e "${LN}┃${NC} [03] • Delete Account"
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
            zivpn_status
            ;;

        0|00)
            clear
            menu
            ;;

        *)
            echo -e "${RD}[ERROR] Invalid selection!${NC}"
            sleep 1
            menu_zivpn
            ;;

    esac
}

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

init_zivpn_db
menu_zivpn