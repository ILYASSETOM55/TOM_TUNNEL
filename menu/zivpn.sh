#!/bin/bash
clear
export LN='\033[34m'
export BG='\033[44m'
export NC='\033[0m'
export GR='\033[32m'
export RD='\033[31m'
export YE='\033[33m'

# Alias pour compatibilité
GREEN="${GR}"

DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "N/A")
MYIP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -4 -s ifconfig.me)

# Créer les fichiers s'ils n'existent pas
mkdir -p /etc/zivpn
[[ ! -f /etc/zivpn/user.db ]] && touch /etc/zivpn/user.db
[[ ! -f /etc/zivpn/config.json ]] && echo '{"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn","auth":{"mode":"passwords","config":[]}}' > /etc/zivpn/config.json

# Fonction robuste pour nettoyer les virgules en trop dans le JSON
clean_json() {
    # Supprime les virgules avant ] ou }
    sed -i -E 's/,[[:space:]]*([}\]])/\1/g' /etc/zivpn/config.json
    # Supprime les lignes vides
    sed -i '/^[[:space:]]*$/d' /etc/zivpn/config.json
}

add_zivpn() {
    clear
    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC} ${BG}               ADD ZIVPN ACCOUNT                ${NC} \( {LN}┃ \){NC}"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"

    while true; do
        read -rp "  Enter username: " user
        [[ -z "$user" ]] && { echo -e "  \( {RD}Username cannot be empty. \){NC}"; continue; }
        [[ ! "\( user" =\~ ^[a-zA-Z0-9_]+ \) ]] && { echo -e "  \( {RD}Invalid username (letters, numbers, underscore only). \){NC}"; continue; }
        if grep -qw "^$user " /etc/zivpn/user.db 2>/dev/null; then
            echo -e "  \( {RD}Username already exists. \){NC}"
            continue
        fi
        break
    done

    while true; do
        read -rp "  Enter password: " pass
        [[ -z "$pass" ]] && { echo -e "  \( {RD}Password cannot be empty. \){NC}"; continue; }
        if grep -qw "$pass" /etc/zivpn/user.db 2>/dev/null || grep -q "\"$pass\"" /etc/zivpn/config.json 2>/dev/null; then
            echo -e "  \( {RD}Password already in use. \){NC}"
            continue
        fi
        break
    done

    while true; do
        read -rp "  Validity (days): " days
        [[ -z "$days" || ! "\( days" =\~ ^[0-9]+ \) || "$days" -le 0 ]] && { echo -e "  \( {RD}Expiry days must be a positive number. \){NC}"; continue; }
        break
    done

    exp=$(date -d "+$days days" +"%Y-%m-%d")

    # Ajout propre dans config.json
    if grep -q '"config": \[\]' /etc/zivpn/config.json; then
        sed -i "s|\"config\": \[\]|\"config\": [ \"$pass\" ]|" /etc/zivpn/config.json
    else
        sed -i "/\"config\": \[/a\      \"$pass\"," /etc/zivpn/config.json
        clean_json
    fi

    # Ajout dans user.db (en bas pour ordre chronologique)
    echo "$user $pass $exp" >> /etc/zivpn/user.db

    systemctl restart zivpn 2>/dev/null

    clear
    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC} ${BG}                  ZIVPN ACCOUNT                 ${NC} \( {LN}┃ \){NC}"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC}  ${GR}User \( user added successfully! \){NC}"
    echo -e "\( {LN}┃ \){NC}"
    echo -e "\( {LN}┃ \){NC}  IPV4      : $MYIP"
    echo -e "\( {LN}┃ \){NC}  Domain    : $DOMAIN"
    echo -e "\( {LN}┃ \){NC}  Username  : $user"
    echo -e "\( {LN}┃ \){NC}  Password  : $pass"
    echo -e "\( {LN}┃ \){NC}  Expiry    : $exp"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    echo -e "\( {LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━● \){NC}"
    echo ""
    read -n 1 -s -r -p " Press any key to return to menu..."
    menu_zivpn
}

del_zivpn() {
    clear
    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC} ${BG}              DELETE ZIVPN ACCOUNT              ${NC} \( {LN}┃ \){NC}"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"

    if [[ ! -s /etc/zivpn/user.db ]]; then
        echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
        echo -e "\( {LN}┃ \){NC}  \( {RD}No users found. \){NC}"
        echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
        echo ""
        read -n 1 -s -r -p "  Press any key to return..."
        menu_zivpn
        return
    fi

    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    printf "${LN}┃ %-4s %-15s %-18s %-12s ${NC}\n" "No." "Username" "Password" "Expiry"
    echo -e "\( {LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━● \){NC}"

    i=1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        username=$(echo "$line" | awk '{print $1}')
        password=$(echo "$line" | awk '{print $2}')
        expiry=$(echo "$line" | awk '{print $3}')
        printf "${LN}┃ %-4s %-15s %-18s %-12s ${NC}\n" "$i" "$username" "$password" "$expiry"
        ((i++))
    done < /etc/zivpn/user.db

    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    echo ""
    read -rp "  Enter username to delete: " user
    [[ -z "$user" ]] && { echo -e "  \( {RD}Username cannot be empty. \){NC}"; sleep 1; menu_zivpn; return; }

    line=$(awk -v u="$user" '$1 == u {print; exit}' /etc/zivpn/user.db)
    if [[ -z "$line" ]]; then
        echo -e "  ${RD}Username '\( user' not found. \){NC}"
        read -n 1 -s -r -p "  Press any key..."
        menu_zivpn
        return
    fi

    pass=$(echo "$line" | awk '{print $2}')

    # Suppression propre dans config.json
    sed -i "/\"$pass\"/d" /etc/zivpn/config.json
    clean_json

    # Suppression dans user.db
    sed -i "/^$user /d" /etc/zivpn/user.db

    systemctl restart zivpn 2>/dev/null

    echo -e "  ${GR}User \( user deleted successfully. \){NC}"
    echo ""
    read -n 1 -s -r -p "  Press any key to return to menu..."
    menu_zivpn
}

renew_zivpn() {
    clear
    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC} ${BG}              RENEW ZIVPN ACCOUNT               ${NC} \( {LN}┃ \){NC}"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"

    if [[ ! -s /etc/zivpn/user.db ]]; then
        echo -e "  \( {RD}No users found. \){NC}"
        read -n 1 -s -r -p "  Press any key..."
        menu_zivpn
        return
    fi

    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    printf "${LN}┃ %-4s %-15s %-18s %-12s ${NC}\n" "No." "Username" "Password" "Expiry"
    echo -e "\( {LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━● \){NC}"

    i=1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        username=$(echo "$line" | awk '{print $1}')
        password=$(echo "$line" | awk '{print $2}')
        expiry=$(echo "$line" | awk '{print $3}')
        printf "${LN}┃ %-4s %-15s %-18s %-12s ${NC}\n" "$i" "$username" "$password" "$expiry"
        ((i++))
    done < /etc/zivpn/user.db

    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    echo ""
    read -rp "  Enter username to renew: " user
    [[ -z "$user" ]] && { echo -e "  \( {RD}Username cannot be empty. \){NC}"; menu_zivpn; return; }

    line=$(awk -v u="$user" '$1 == u {print; exit}' /etc/zivpn/user.db)
    if [[ -z "$line" ]]; then
        echo -e "  ${RD}Username '\( user' not found. \){NC}"
        read -n 1 -s -r -p "  Press any key..."
        menu_zivpn
        return
    fi

    current_exp=$(echo "$line" | awk '{print $3}')
    password=$(echo "$line" | awk '{print $2}')

    read -rp "  Enter additional days: " add_days
    if [[ -z "$add_days" || ! "\( add_days" =\~ ^[0-9]+ \) || "$add_days" -le 0 ]]; then
        echo -e "  \( {RD}Invalid number of days. \){NC}"
        menu_zivpn
        return
    fi

    new_exp=$(date -d "$current_exp + $add_days days" +"%Y-%m-%d" 2>/dev/null)
    if [[ -z "$new_exp" ]]; then
        # Fallback si date -d échoue
        new_exp=$(date -d "+$add_days days" +"%Y-%m-%d")
    fi

    sed -i "/^$user /c$user $password $new_exp" /etc/zivpn/user.db

    clear
    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC} ${BG}                  ZIVPN RENEWED                 ${NC} \( {LN}┃ \){NC}"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC} ${GR}User \( user renewed successfully! \){NC}"
    echo -e "\( {LN}┃ \){NC}"
    echo -e "\( {LN}┃ \){NC} Username   : $user"
    echo -e "\( {LN}┃ \){NC} Old expiry : $current_exp"
    echo -e "\( {LN}┃ \){NC} New expiry : $new_exp"
    echo -e "\( {LN}┃ \){NC} Days added : $add_days"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    echo ""
    read -n 1 -s -r -p "   Press any key to return to menu..."
    menu_zivpn
}

list_zivpn() {
    clear
    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC} ${BG}               ZIVPN ACCOUNT LIST               ${NC} \( {LN}┃ \){NC}"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"

    total=\( (grep -cve '^\s* \)' /etc/zivpn/user.db 2>/dev/null || echo 0)

    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC}  Total accounts : ${GR}\( total \){NC}"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"

    if [[ "$total" -eq 0 ]]; then
        echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
        echo -e "\( {LN}┃ \){NC}  \( {RD}No users found. \){NC}"
        echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    else
        echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
        printf "${LN}┃ %-4s %-15s %-18s %-12s ${NC}\n" "No." "Username" "Password" "Expiry"
        echo -e "\( {LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━● \){NC}"

        i=1
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue
            user=$(echo "$line" | awk '{print $1}')
            pass=$(echo "$line" | awk '{print $2}')
            exp=$(echo "$line" | awk '{print $3}')
            # Color expired accounts in red
            if [[ $(date -d "$exp" +%s 2>/dev/null) -lt $(date +%s) ]]; then
                printf "${LN}┃ %-4s %-15s %-18s \( {RD}%-12s \){NC}\n" "$i" "$user" "$pass" "$exp (EXPIRED)"
            else
                printf "${LN}┃ %-4s %-15s %-18s %-12s ${NC}\n" "$i" "$user" "$pass" "$exp"
            fi
            ((i++))
        done < /etc/zivpn/user.db

        echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    fi

    echo -e "\( {LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━● \){NC}"
    echo ""
    read -n 1 -s -r -p "Press any key to return to menu..."
    menu_zivpn
}

menu_zivpn() {
    clear
    total=\( (grep -cve '^\s* \)' /etc/zivpn/user.db 2>/dev/null || echo 0)

    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC} ${BG}                  ZIVPN MENU                    ${NC} \( {LN}┃ \){NC}"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    echo -e "\( {LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \){NC}"
    echo -e "\( {LN}┃ \){NC}  Total users registered : ${GR}\( total \){NC}"
    echo -e "\( {LN}┃ \){NC}"
    echo -e "\( {LN}┃ \){NC} [01] • Create Account      [03] • Delete Account"
    echo -e "\( {LN}┃ \){NC} [02] • Extend Account      [04] • Account List"
    echo -e "\( {LN}┃ \){NC}"
    echo -e "\( {LN}┃ \){NC} [00] • Back to Main Menu"
    echo -e "\( {LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ \){NC}"
    echo -e "\( {LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━● \){NC}"
    echo ""
    read -p "  Select menu : " opt
    echo ""
    case $opt in
        1|01) clear ; add_zivpn ;;
        2|02) clear ; renew_zivpn ;;
        3|03) clear ; del_zivpn ;;
        4|04) clear ; list_zivpn ;;
        0|00) clear ; menu 2>/dev/null || exit 0 ;;
        *)
            echo -e "\( {RD} [ERROR] Invalid selection! \){NC}"
            sleep 1
            menu_zivpn
            ;;
    esac
}

menu_zivpn