#!/bin/bash

# ============================================================
# DNS PANEL
# Google / Cloudflare / OpenDNS / Quad9 / AdGuard / Custom
# ============================================================

export LN='\e[34m'
export BG='\e[44m'
export NC='\e[0m'
export GR='\e[32m'
export RD='\e[31m'
export YL='\e[33m'

# ============================================================
# SHOW CURRENT DNS
# ============================================================

show_current_dns() {

    local current_dns

    if [[ -r /etc/resolv.conf ]]; then
        current_dns=$(awk '
            $1 == "nameserver" {
                if (dns != "") dns = dns " "
                dns = dns $2
            }
            END {
                print dns
            }
        ' /etc/resolv.conf)
    fi

    if [[ -z "$current_dns" ]]; then
        current_dns="No DNS configured"
    fi

    echo -e "${LN}┃${NC} Current Active DNS : ${GR}${current_dns}${NC}"
    echo -e "${LN}┃${NC}"
}

# ============================================================
# VALIDATE DNS
# ============================================================

valid_dns() {

    local dns="$1"

    [[ "$dns" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    IFS='.' read -r a b c d <<< "$dns"

    (( a <= 255 && b <= 255 && c <= 255 && d <= 255 ))
}

# ============================================================
# APPLY DNS
# ============================================================

apply_dns() {

    # Script normally runs as root.
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RD}[ERROR] This operation requires root privileges.${NC}"
        return 1
    fi

    # Validate both DNS addresses
    if ! valid_dns "$dns1"; then
        echo -e "${RD}[ERROR] Invalid primary DNS: $dns1${NC}"
        return 1
    fi

    if ! valid_dns "$dns2"; then
        echo -e "${RD}[ERROR] Invalid secondary DNS: $dns2${NC}"
        return 1
    fi

    # --------------------------------------------------------
    # systemd-resolved active
    # --------------------------------------------------------

    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then

        # Disable the current symlink so that resolv.conf
        # can be managed directly by this script.
        if [[ -L /etc/resolv.conf ]]; then
            rm -f /etc/resolv.conf
        fi

        cat > /etc/resolv.conf <<EOF
nameserver $dns1
nameserver $dns2
EOF

        chmod 644 /etc/resolv.conf

        systemctl restart systemd-resolved >/dev/null 2>&1

    else

        # ----------------------------------------------------
        # systemd-resolved inactive
        # ----------------------------------------------------

        if [[ -L /etc/resolv.conf ]]; then
            rm -f /etc/resolv.conf
        fi

        cat > /etc/resolv.conf <<EOF
nameserver $dns1
nameserver $dns2
EOF

        chmod 644 /etc/resolv.conf
    fi

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    if grep -qE "^nameserver[[:space:]]+$dns1$" /etc/resolv.conf &&
       grep -qE "^nameserver[[:space:]]+$dns2$" /etc/resolv.conf; then
        return 0
    fi

    return 1
}

# ============================================================
# DNS MENU
# ============================================================

dns_menu() {

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                   DNS PANEL                    ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"

    show_current_dns

    echo -e "${LN}┃${NC} [01] • Google DNS           [04] • Quad9 DNS"
    echo -e "${LN}┃${NC} [02] • Cloudflare DNS       [05] • AdGuard Default"
    echo -e "${LN}┃${NC} [03] • OpenDNS              [06] • AdGuard Family"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} [99] • Custom DNS"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} [00] • Back to Main Menu"

    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"

    echo ""

    read -rp " Select DNS Provider : " opt

    case "$opt" in

        1|01)
            dns1="8.8.8.8"
            dns2="8.8.4.4"
            provider="Google DNS"
            ;;

        2|02)
            dns1="1.1.1.1"
            dns2="1.0.0.1"
            provider="Cloudflare DNS"
            ;;

        3|03)
            dns1="208.67.222.222"
            dns2="208.67.220.220"
            provider="OpenDNS"
            ;;

        4|04)
            dns1="9.9.9.9"
            dns2="149.112.112.112"
            provider="Quad9"
            ;;

        5|05)
            dns1="94.140.14.14"
            dns2="94.140.15.15"
            provider="AdGuard Default"
            ;;

        6|06)
            dns1="94.140.14.15"
            dns2="94.140.15.16"
            provider="AdGuard Family"
            ;;

        99)

            while true; do

                read -rp " Enter Primary DNS  : " dns1

                if ! valid_dns "$dns1"; then
                    echo -e " ${RD}[ERROR] Invalid DNS address.${NC}"
                    continue
                fi

                break
            done

            while true; do

                read -rp " Enter Secondary DNS: " dns2

                if ! valid_dns "$dns2"; then
                    echo -e " ${RD}[ERROR] Invalid DNS address.${NC}"
                    continue
                fi

                break
            done

            provider="Custom DNS"
            ;;

        0|00)

            clear
            menu
            return
            ;;

        *)

            echo ""
            echo -e " ${RD}[ERROR] Invalid option!${NC}"
            sleep 2
            dns_menu
            return
            ;;

    esac

    # ========================================================
    # APPLY
    # ========================================================

    if ! apply_dns; then

        echo ""
        echo -e " ${RD}[ERROR] Failed to apply DNS configuration.${NC}"
        echo ""

        read -n 1 -s -r -p " Press any key to return..."

        dns_menu
        return
    fi

    # ========================================================
    # SUCCESS
    # ========================================================

    clear

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                   DNS PANEL                    ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${GR}DNS has been set successfully!${NC}"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} DNS Provider : ${provider}"
    echo -e "${LN}┃${NC} Primary DNS  : ${dns1}"
    echo -e "${LN}┃${NC} Secondary DNS: ${dns2}"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} Current DNS  : ${GR}$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | xargs)${NC}"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} TOM_TUNNEL DNS PANEL"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"

    echo ""

    read -n 1 -s -r -p " Press any key to return to the menu..."

    dns_menu
}

# ============================================================
# START
# ============================================================

dns_menu