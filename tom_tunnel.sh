#!/bin/bash
clear
export LN='\033[34m'
export BG='\033[44m'
export NC='\033[0m'
export GR='\033[32m'
export RD='\033[31m'
export MYIP=$(wget -qO- ipv4.icanhazip.com)

# --- CONFIGURATION DU DÉPÔT CENTRAL (CORRIGÉ) ---
readonly SERVER_HOST="https://raw.githubusercontent.com/ILYASSETOM55/TOM_TUNNEL/main"
readonly TIMEZONE="Asia/Kuala_Lumpur"

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
            return 0  
        else
            echo "Unsupported OS: $ID. Exiting."
            exit 1
        fi
    else
        echo "Cannot detect OS. Exiting."
        exit 1
    fi
}

check_root_virt() {
    [ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }
    [ "$(systemd-detect-virt)" = "openvz" ] && { echo "OpenVZ is not supported"; exit 1; }
}

setup_host_time() {
    local localip hst host_entry
    localip=$(hostname -I | awk '{print $1}')
    hst=$(hostname)
    host_entry=$(awk '{print $2}' /etc/hosts | grep -w "$hst" || true)
    [ "$hst" != "$host_entry" ] && echo "$localip $hst" >> /etc/hosts
    ln -fs "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
}

prepare_env() {
    mkdir -p /etc/xray
    touch /etc/xray/domain
}

function show_tns() {
    clear
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}            TERMS & CONDITIONS PANEL            ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${GR}Welcome to TOM_TUNNEL Services!${NC}"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} [*] Please read the terms below carefully"
    echo -e "${LN}┃${NC} [*] TOM_TUNNEL is provided as-is, no warranties."
    echo -e "${LN}┃${NC} [*] Do not use this service for illegal activities."
    echo -e "${LN}┃${NC} [*] TOM_TUNNEL is not liable for data loss or leaks."
    echo -e "${LN}┃${NC} [*] You must follow all applicable laws."
    echo -e "${LN}┃${NC} [*] Terms may change anytime without notice."
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"
    echo -e "${LN}┃${NC} [01] • Accept Terms"
    echo -e "${LN}┃${NC} [02] • Decline & Exit"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"
    echo
    read -p "  Select an option : " opt
    echo ""
    case $opt in
    1 | 01)
        clear
        echo -e " ${GR}You have accepted the Terms & Conditions.${NC}"
        echo -e " ${GR}Loading...${NC}"
        sleep 5
        add_domain
        ;;
    2 | 02)
        clear
        echo -e " ${RD}You declined the Terms & Conditions.${NC}"
        echo -e " ${RD}Removing all /root/*.sh scripts and exiting...${NC}"
        rm -f /root/*.sh
        sleep 10
        exit 0
        ;;
    *)
        echo -e "${RD} [ERROR] Invalid selection!${NC}"
        rm -f /root/*.sh
        sleep 10
        exit 0
        ;;
    esac
}

function add_domain() {
    clear
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                 DOMAIN PANEL                   ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo
    while true; do
        read -rp " Hostname / Domain: " host
        if [[ -z "$host" ]]; then
            echo -e " ${RD}Domain cannot be empty. Please try again.${NC}"
            continue
        fi
        domain_ip=$(getent ahosts "$host" | awk '{print $1; exit}')
        if [[ "$domain_ip" == "$MYIP" ]]; then
            break
        else
            clear
            echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
            echo -e "${LN}┃${NC} ${BG}                 DOMAIN PANEL                   ${NC} ${LN}┃${NC}"
            echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
            echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
            echo -e "${LN}┃${NC} ${RD}✘ Domain does not point to this VPS!${NC}"
            echo -e "${LN}┃${NC} ${RD}Domain resolves to: $domain_ip ${NC}"
            echo -e "${LN}┃${NC} ${RD}VPS public IP is : $MYIP ${NC}"
            echo -e "${LN}┃${NC} ${RD}Please fix your DNS settings and try again.${NC}"
            echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
            echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"
            echo ""
            read -n 1 -s -r -p " Press any key to return to the menu..."
            add_domain
            return
        fi
    done
    echo "$host" > /root/domain
    echo "$host" > /etc/xray/domain
    if [[ -f /root/domain ]]; then
        domain=$(cat /root/domain)
    elif [[ -f /etc/xray/domain ]]; then
        domain=$(cat /etc/xray/domain)
    else
        echo -e "${RD} [*] Domain file not found!${NC}"
        rm -f /root/*.sh
        exit 1
    fi
    clear
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}                 DOMAIN PANEL                   ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} Domain has been set successfully!"
    echo -e "${LN}┃${NC} Current Domain: ${domain}"
    echo -e "${LN}┃${NC}                                                    "
    echo -e "${LN}┃${NC} AutoScript Xray by tom_tunnel Team"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"
    sleep 4
    echo " [*] Installation started...."
    sleep 3
}

update_system() {
    echo "[INFO] Updating system..."
    apt-get update -y
    apt-get upgrade -y
    apt-get dist-upgrade -y
    apt-get remove --purge -y ufw firewalld exim4 nginx* dropbear* apache2*
    apt autoremove -y
}

install_packages() {
    echo "[INFO] Installing packages..."
    apt-get install -y \
    screen curl jq bzip2 gzip vnstat coreutils rsyslog iftop zip unzip git \
    apt-transport-https build-essential wget figlet ruby-full python3 make cmake \
    net-tools nano sed gnupg gnupg1 bc shc libxml-parser-perl neofetch lsof \
    libsqlite3-dev libz-dev gcc g++ libreadline-dev zlib1g-dev libssl-dev \
    dropbear fail2ban nginx certbot iptables-persistent
    if command -v gem >/dev/null; then
        gem install lolcat >/dev/null
    fi
    if ! dpkg -s nginx >/dev/null 2>&1; then
        echo "[ERROR] nginx failed to install"
        exit 1
    fi
}

run_scripts() {
    scripts=("sshws.sh" "xray.sh" "vpn.sh" "websocket.sh" "setup_zivpn.sh" "setup_dns.sh" "setup_udp.sh" "validator.sh")
    for script in "${scripts[@]}"; do
        url="${SERVER_HOST}/core/${script}"
        echo "[INFO] Downloading $script..."
        if wget -q "$url" -O "$script"; then
            chmod +x "$script"
            echo "[INFO] Running $script..."
            ./"$script"
        else
            echo "[ERROR] Failed to download $script from $url"
        fi
    done
}

install_menu() {
    for script in dns zivpn expiry domain iptools menu socks ssh status trojan vless vmess netguard port log tgbot uninstall update web fastdns; do
        wget -q -O "/usr/local/sbin/$script" "${SERVER_HOST}/menu/${script}.sh"
        chmod +x "/usr/local/sbin/$script"
    done
}

setup_autoreboot() {
    grep -q "shutdown -r now" /etc/crontab || \
    echo "0 0 * * * root /sbin/shutdown -r now" >> /etc/crontab
}

setup_autolog() {
    grep -q "/usr/local/sbin/log" /etc/crontab || \
    echo "*/30 * * * * root /usr/local/sbin/log" >> /etc/crontab
}

setup_autoexp() {
    local cronjob="55 23 * * * root /usr/local/sbin/expiry"
    grep -q "/usr/local/sbin/expiry" /etc/crontab || echo "$cronjob" >> /etc/crontab
}

setup_profile() {
    cat > /root/.profile <<'EOF'
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
clear
menu
EOF
    echo "[*] Profile configured"
}

cleanner() {
    rm -f /root/*.sh 2>/dev/null
    rm -f /root/*.pem 2>/dev/null
}

restart_services() {
    echo "[*] Enabling and restarting all system services..."
    SERVICES=(
        ssh
        dropbear
        stunnel5
        cron
        nginx
        vnstat
        fail2ban
        ws-dropbear
        ws-stunnel
        xray
        runn
        squid
        openvpn
        ohp
        zivpn
        dnstt
        udp-custom
    )
    for svc in "${SERVICES[@]}"; do
        if systemctl list-unit-files | grep -q "^$svc.service"; then
            echo "[INFO] Restarting $svc..."
            systemctl enable "$svc" --now || echo "[WARN] Failed to enable $svc"
            systemctl restart "$svc" || echo "[WARN] Failed to restart $svc"
        fi
    done
    for port in 7100 7200 7300; do
        svc="badvpn@$port"
        if systemctl list-unit-files | grep -q "^$svc.service"; then
            echo "[INFO] Restarting $svc..."
            systemctl enable "$svc" --now || echo "[WARN] Failed to enable $svc"
            systemctl restart "$svc" || echo "[WARN] Failed to restart $svc"
        fi
    done
    echo "[INFO] All services have been enabled and restarted successfully."
}

doty_completed() {
    clear
    domain=$(cat /etc/xray/domain)
    MYIP=$(wget -qO- ipv4.icanhazip.com)
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${BG}              INSTALLATION COMPLETE               ${NC} ${LN}┃${NC}"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${LN}┃${NC} ${GR}Congratulations! TOM_TUNNEL is ready.${NC}"
    echo -e "${LN}┃${NC}"
    echo -e "${LN}┃${NC} Domain: ${domain}"
    echo -e "${LN}┃${NC} VPS IP: ${MYIP}"
    echo -e "${LN}┃${NC} Enjoy secure VPN services!${NC}"
    echo -e "${LN}┃${NC} AutoScript Xray by tom_tunnel Team"
    echo -e "${LN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e "${LN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${NC}"
    echo
}

set_version() {
    wget -q "$SERVER_HOST/version" -O /etc/version
    wget -q "$SERVER_HOST/port_info" -O /etc/xray/port_info
}

enable_bbr() {
    sudo sysctl -w net.core.default_qdisc=fq
    sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
    grep -q "net.core.default_qdisc" /etc/sysctl.conf || echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control = bbr" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
}

main() {
    check_root_virt
    check_os
    setup_host_time
    prepare_env
    update_system
    install_packages
    show_tns
    run_scripts
    install_menu
    setup_profile
    setup_autoreboot
    setup_autolog
    setup_autoexp
    enable_bbr
    restart_services
    set_version
    doty_completed
    cleanner
    echo "Installation finished. Server will reboot in 10 seconds."
    sleep 10
    reboot
}

main
