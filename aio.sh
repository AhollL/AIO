#!/bin/bash

NC='\e[0m'       # No Color
DEFBOLD='\e[39;1m' # Default Bold
RB='\e[31;1m'    # Red Bold
GB='\e[32;1m'    # Green Bold
YB='\e[33;1m'    # Yellow Bold

print_msg() {
    COLOR=$1
    MSG=$2
    echo -e "${COLOR}${MSG}${NC}"
}

check_success() {
    if [ $? -eq 0 ]; then
        print_msg $GB "Success"
    else
        print_msg $RB "Failed: $1"
        exit 1
    fi
}

# Check OS compatibility
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "debian" && ("$VERSION_ID" == "11" || "$VERSION_ID" == "12") ]] || [[ "$ID" == "ubuntu" && ("$VERSION_ID" == "20.04" || "$VERSION_ID" == "22.04") ]]; then
            print_msg $GB "Supported OS detected: $PRETTY_NAME"
        else
            print_msg $RB "Unsupported OS: $PRETTY_NAME. This script supports Debian 11/12 and Ubuntu 20.04/22.04 only."
            exit 1
        fi
    else
        print_msg $RB "Cannot detect OS. This script requires /etc/os-release."
        exit 1
    fi
}

if [ "$EUID" -ne 0 ]; then
    print_msg $RB "Run as root."
    exit 1
fi

check_os

# Function for Xray Installation
install_xray() {
    print_msg $YB "Installing Xray..."
    # Download and run the original installer from dugong-lewat
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/dugong-lewat/1clickxray/main/install2.sh)"
    check_success "Xray installation failed"

    # Additional improvements: Ensure UFW and persistence
    ufw allow 443/tcp
    ufw allow 80/tcp
    ufw reload
    netfilter-persistent save

    print_msg $GB "Xray installed! Type 'menu' for Xray menu, or use AIO panel."
}

# Function for ZIVPN Installation
install_zivpn() {
    print_msg $YB "Installing ZIVPN UDP..."
    apt-get update && apt-get upgrade -y
    apt install -y ufw iptables iptables-persistent jq openssl wget lsb-release

    systemctl stop zivpn.service >/dev/null 2>&1

    wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn >/dev/null 2>&1
    chmod +x /usr/local/bin/zivpn

    mkdir -p /etc/zivpn
    wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O /etc/zivpn/config.json >/dev/null 2>&1

    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"

    sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1

    cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    echo "Enter ZIVPN passwords (comma-separated, e.g., pass1,pass2; default 'zi'):"
    read input_config
    if [ -z "$input_config" ]; then
        input_config="zi"
    fi

    jq --argjson configs "[$(echo "$input_config" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]" '.config = $configs' /etc/zivpn/config.json > temp.json && mv temp.json /etc/zivpn/config.json

    echo "Enter custom port for ZIVPN (default 5667):"
    read custom_port
    if [ -z "$custom_port" ]; then
        custom_port=5667
    fi

    jq ".port = $custom_port" /etc/zivpn/config.json > temp.json && mv temp.json /etc/zivpn/config.json

    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service

    IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    iptables -t nat -A PREROUTING -i $IFACE -p udp --dport 6000:19999 -j DNAT --to-destination :$custom_port
    netfilter-persistent save

    ufw allow 6000:19999/udp
    ufw allow $custom_port/udp
    ufw enable
    ufw reload

    print_msg $GB "ZIVPN installed! Use panel option 2 for menu."
}

# Function for Uninstall Xray
uninstall_xray() {
    print_msg $YB "Uninstalling Xray..."
    systemctl stop xray >/dev/null 2>&1
    systemctl disable xray >/dev/null 2>&1
    rm -f /etc/systemd/system/xray.service
    rm -rf /usr/local/bin/xray /usr/local/etc/xray /var/log/xray
    ufw delete allow 443/tcp
    ufw delete allow 80/tcp
    ufw reload
    systemctl daemon-reload
    print_msg $GB "Xray uninstalled."
}

# Function for Uninstall ZIVPN
uninstall_zivpn() {
    print_msg $YB "Uninstalling ZIVPN..."
    systemctl stop zivpn.service >/dev/null 2>&1
    systemctl disable zivpn.service >/dev/null 2>&1
    rm -f /etc/systemd/system/zivpn.service /usr/local/bin/zivpn
    rm -rf /etc/zivpn
    iptables -t nat -D PREROUTING -i $(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1) -p udp --dport 6000:19999 -j DNAT --to-destination :5667  # Assume default port; adjust if custom
    netfilter-persistent save
    ufw delete allow 6000:19999/udp
    ufw delete allow 5667/udp  # Assume default
    ufw reload
    systemctl daemon-reload
    print_msg $GB "ZIVPN uninstalled."
}

# Function for ZIVPN Manager Menu
zivpn_manager() {
    CONFIG_FILE="/etc/zivpn/config.json"

    if ! command -v jq &> /dev/null; then
        apt update && apt install -y jq
    fi

    check_expired() {
        TODAY=$(date +%Y-%m-%d)
        jq --arg today "$TODAY" 'del(.config[] | select(.expired < $today))' $CONFIG_FILE > temp.json && mv temp.json $CONFIG_FILE
        systemctl restart zivpn.service >/dev/null 2>&1
        print_msg $GB "Expired users deleted."
    }

    add_user() {
        echo "Enter new password:"
        read password
        echo "Enter expiration days (e.g., 30):"
        read days
        EXPIRED=$(date -d "+$days days" +%Y-%m-%d)
        jq --arg pass "$password" --arg exp "$EXPIRED" '.config += [{"password": $pass, "expired": $exp}]' $CONFIG_FILE > temp.json && mv temp.json $CONFIG_FILE
        systemctl restart zivpn.service >/dev/null 2>&1
        print_msg $GB "User $password added with expiration $EXPIRED."
    }

    list_users() {
        jq '.config[] | "Password: \(.password), Expired: \(.expired)"' $CONFIG_FILE
    }

    delete_user() {
        list_users
        echo "Enter password to delete:"
        read password
        jq --arg pass "$password" 'del(.config[] | select(.password == $pass))' $CONFIG_FILE > temp.json && mv temp.json $CONFIG_FILE
        systemctl restart zivpn.service >/dev/null 2>&1
        print_msg $GB "User $password deleted."
    }

    check_expired  # Auto-check
    while true; do
        echo "ZIVPN Manager Menu:"
        echo "1. Add User with Expiration"
        echo "2. List Users"
        echo "3. Delete Specific User"
        echo "4. Check and Delete Expired"
        echo "5. Back to AIO Menu"
        read choice
        case $choice in
            1) add_user ;;
            2) list_users ;;
            3) delete_user ;;
            4) check_expired ;;
            5) return ;;
            *) echo "Invalid choice" ;;
        esac
    done
}

# Main AIO VPN Menu
aio_menu() {
    while true; do
        echo "AIO VPN Menu:"
        echo "1. xray (membuka menu xray yg sudah ada pada repo dugong)"
        echo "2. zivpn (membuka menu zivpn)"
        echo "3. install xray"
        echo "4. install zivpn"
        echo "5. uninstall xray"
        echo "6. uninstall zivpn"
        echo "7. exit"
        read choice
        case $choice in
            1) 
                if command -v menu &> /dev/null; then
                    menu  # Call existing Xray menu from dugong repo
                else
                    print_msg $RB "Xray menu not found. Install Xray first."
                fi
                ;;
            2) zivpn_manager ;;
            3) install_xray ;;
            4) install_zivpn ;;
            5) uninstall_xray ;;
            6) uninstall_zivpn ;;
            7) exit 0 ;;
            *) echo "Invalid choice" ;;
        esac
    done
}

# Install the 'panel' command if not already (copy this script to /usr/local/bin/panel)
if [ "$(basename "$0")" == "aio.sh" ]; then
    cp "$0" /usr/local/bin/panel
    chmod +x /usr/local/bin/panel
    print_msg $GB "Installed 'panel' command. Run 'panel' to open AIO VPN Menu."
    aio_menu  # Run menu on first execution
else
    aio_menu  # If called as 'panel', directly open menu
fi
