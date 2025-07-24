#!/bin/sh
# Modified Outline scripted installer for OpenWRT
# Fixes SSH disconnection on subsequent runs

echo 'Starting Outline OpenWRT install script'

# Step 1: Check for kmod-tun
opkg list-installed | grep kmod-tun > /dev/null
if [ $? -ne 0 ]; then
    echo "kmod-tun is not installed. Exiting."
    exit 1
fi
echo 'kmod-tun installed'

# Step 2: Check for ip-full
opkg list-installed | grep ip-full > /dev/null
if [ $? -ne 0 ]; then
    echo "ip-full is not installed. Exiting."
    exit 1
fi
echo 'ip-full installed'

# Step 3: Check for tun2socks then download if needed
NEED_RESTART=0
if [ ! -f "/usr/bin/tun2socks" ]; then
    if [ ! -f "/tmp/tun2socks" ]; then
        ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
        echo "Downloading tun2socks for architecture: $ARCH"
        wget https://github.com/1andrevich/outline-install-wrt/releases/download/v2.5.1/tun2socks-linux-$ARCH -O /tmp/tun2socks
        if [ $? -ne 0 ]; then
            echo "Download failed. No file for your Router's architecture"
            exit 1
        fi
    fi
    
    # Step 4: Move to /usr/bin and set permissions
    mv /tmp/tun2socks /usr/bin/
    echo 'moving tun2socks to /usr/bin'
    chmod +x /usr/bin/tun2socks
    NEED_RESTART=1
else
    echo 'tun2socks already installed'
fi

# Step 5: Check for existing config in /etc/config/network
if ! grep -q "config interface 'tunnel'" /etc/config/network; then
    echo "
config interface 'tunnel'
    option device 'tun1'
    option proto 'static'
    option ipaddr '172.16.10.1'
    option netmask '255.255.255.252'
" >> /etc/config/network
    echo 'added entry into /etc/config/network'
    NEED_RESTART=1
fi
echo 'found entry into /etc/config/network'

# Step 6: Check for existing config /etc/config/firewall
if ! grep -q "option name 'proxy'" /etc/config/firewall; then
    echo "
config zone
    option name 'proxy'
    list network 'tunnel'
    option forward 'REJECT'
    option output 'ACCEPT'
    option input 'REJECT'
    option masq '1'
    option mtu_fix '1'
    option device 'tun1'
    option family 'ipv4'

config forwarding
    option name 'lan-proxy'
    option dest 'proxy'
    option src 'lan'
    option family 'ipv4'
" >> /etc/config/firewall
    echo 'added entry into /etc/config/firewall'
    NEED_RESTART=1
fi
echo 'found entry into /etc/config/firewall'

# Step 7: Only restart network if changes were made
if [ $NEED_RESTART -eq 1 ]; then
    echo 'Changes detected, restarting network...'
    /etc/init.d/network restart
    echo 'Network restarted, waiting for stabilization...'
    sleep 5
else
    echo 'No network changes needed, skipping restart'
fi

# Step 8: Read user variables
read -p "Enter Outline Server IP: " OUTLINEIP
read -p "Enter Outline (Shadowsocks) Config (format ss://base64coded@HOST:PORT/?outline=1): " OUTLINECONF

# Step 9: Check for default gateway
DEFGW=$(ip route | grep default | awk '{print $3}')
echo "Default gateway: $DEFGW"

# Step 10: Check for default interface
DEFIF=$(ip route | grep default | awk '{print $5}')
echo "Default interface: $DEFIF"

# Step 11: Create init script if it doesn't exist
if [ ! -f "/etc/init.d/tun2socks" ]; then
cat <<EOL > /etc/init.d/tun2socks
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99
STOP=89

start_service() {
    procd_open_instance
    procd_set_param user root
    procd_set_param command /usr/bin/tun2socks -device tun1 -tcp-rcvbuf 64kb -tcp-sndbuf 64kb -proxy "$OUTLINECONF" -loglevel "warning"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_close_instance
    
    # Add route to Outline server
    ip route add "$OUTLINEIP" via "$DEFGW" 2>/dev/null
    echo 'route to Outline Server added'
    
    # Save default route
    ip route save default > /tmp/defroute.save
    echo "tun2socks service started"
}

stop_service() {
    # Restore default route if backup exists
    if [ -f "/tmp/defroute.save" ]; then
        ip route restore default < /tmp/defroute.save
    fi
    
    # Remove route to Outline server
    ip route del "$OUTLINEIP" via "$DEFGW" 2>/dev/null
    echo "tun2socks service stopped"
}

service_started() {
    echo 'Checking if default gateway should be changed...'
    sleep 3
    
    # Check if user wants Outline as default gateway
    read -p "Do you want to use Outline (shadowsocks) as your default gateway? (y/n): " DEFAULT_GW
    
    if [ "$DEFAULT_GW" = "y" ] || [ "$DEFAULT_GW" = "Y" ]; then
        if ip link show tun1 | grep -q "UP"; then
            ip route del default
            ip route add default via 172.16.10.2 dev tun1
            echo 'Default gateway changed to Outline tunnel'
        fi
    fi
}

boot() {
    start
}
EOL

    chmod +x /etc/init.d/tun2socks
    echo 'created /etc/init.d/tun2socks'
else
    echo '/etc/init.d/tun2socks already exists'
fi

# Step 12: Enable autostart
if [ ! -f "/etc/rc.d/S99tun2socks" ]; then
    /etc/init.d/tun2socks enable
    echo 'enabled tun2socks autostart'
fi

# Step 13: Start the service
echo 'Starting tun2socks service...'
/etc/init.d/tun2socks start

echo 'Script finished successfully!'
