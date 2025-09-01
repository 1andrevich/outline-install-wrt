#!/bin/sh
# Outline scripted, xjasonlyu/tun2socks based installer for OpenWRT (RAM).
# https://github.com/1andrevich/outline-install-wrt
echo 'Starting Outline OpenWRT install to RAM script'

# Step 1: Check for kmod-tun
opkg list-installed | grep kmod-tun > /dev/null
if [ $? -ne 0 ]; then
    echo "kmod-tun is not installed. Exiting."
    exit 1
    echo 'kmod-tun installed'
fi

# Step 2: Check for ip-full
opkg list-installed | grep ip-full > /dev/null
if [ $? -ne 0 ]; then
    echo "ip-full is not installed. Exiting."
    exit 1
    echo 'ip-full installed'
fi

# Step 3: Check for tun2socks then download tun2socks binary from GitHub (to RAM)
if [ ! -f "/tmp/tun2socks*" ]; then
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
wget https://github.com/1andrevich/outline-install-wrt/releases/latest/download/tun2socks-linux-$ARCH -O /tmp/tun2socks
 # Check wget's exit status
    if [ $? -ne 0 ]; then
        echo "Download failed. No file for your Router's architecture"
        exit 1
   fi
fi
# Step 4: Executing chmod +x command
chmod +x /tmp/tun2socks

# Step 5: Check for existing config in /etc/config/network then add entry
if ! grep -q "config interface 'tunnel'" /etc/config/network; then
echo "
config interface 'tunnel'
    option device 'tun1'
    option proto 'static'
    option ipaddr '172.16.10.1'
    option netmask '255.255.255.252'
" >> /etc/config/network
    echo 'added entry into /etc/config/network'
fi
echo 'found entry into /etc/config/network'

# Step 6:Check for existing config /etc/config/firewall then add entry
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
fi

echo 'found entry into /etc/config/firewall'
# Step 7: Restart network
/etc/init.d/network restart
echo 'Restarting Network....'

# Step 8: Read user variable for OUTLINE HOST IP
read -p "Enter Outline Server IP: " OUTLINEIP
# Read user variable for Outline config
read -p "Enter Outline (Shadowsocks) Config (format ss://base64coded@HOST:PORT/?outline=1): " OUTLINECONF

#Step 9. Check for default gateway and save it into DEFGW
DEFGW=$(ip route | grep default | awk '{print $3}')
echo 'checked default gateway'

#Step 10. Check for default interface and save it into DEFIF
DEFIF=$(ip route | grep default | awk '{print $5}')
echo 'checked default interface'

# Step 11: Create script /etc/init.d/tun2socks
if [ ! -f "/etc/init.d/tun2socks" ]; then
cat <<EOL > /etc/init.d/tun2socks
#!/bin/sh /etc/rc.common
USE_PROCD=1

# starts after network starts
START=99
# stops before networking stops
STOP=89

#PROG=/usr/bin/tun2socks
#IF="tun1"
#OUTLINE_CONFIG="$OUTLINECONF"
#LOGLEVEL="warning"
#BUFFER="64kb"

#Check for tun2socks then download tun2socks binary from GitHub to RAM
before_start() {
if [ ! -f "/tmp/tun2socks*" ]; then
  ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
  wget https://github.com/1andrevich/outline-install-wrt/releases/download/v2.5.1/tun2socks-linux-$ARCH -O /tmp/tun2socks
 # Check wget's exit status
    if [ $? -ne 0 ]; then
        echo "Download failed. No file for your Router's architecture"
        exit 1
   fi
fi
#Executing chmod +x command
chmod +x /tmp/tun2socks
}

start_service() {
    before_start
    procd_open_instance
    procd_set_param user root
    procd_set_param command /tmp/tun2socks -device tun1 -tcp-rcvbuf 64kb -tcp-sndbuf 64kb  -proxy "$OUTLINECONF" -loglevel "warning"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn "${respawn_threshold:-3600}" "${respawn_timeout:-5}" "${respawn_retry:-5}"
    procd_close_instance
    ip route add "$OUTLINEIP" via "$DEFGW" #Adds route to OUTLINE Server
	echo 'route to Outline Server added'
    ip route save default > /tmp/defroute.save  #Saves existing default route
    echo "tun2socks is working!"
}

boot() {
    # This gets run at boot-time.
    start
}

shutdown() {
    # This gets run at shutdown/reboot.
    stop
}

stop_service() {
    service_stop /tmp/tun2socks
    ip route restore default < /tmp/defroute.save #Restores saved default route
    ip route del "$OUTLINEIP" via "$DEFGW" #Removes route to OUTLINE Server
    echo "tun2socks has stopped!"
}

reload_service() {
    stop
    sleep 3s
    echo "tun2socks restarted!"
    start
}
EOL
DEFAULT_GATEWAY=""
#Ask user to use Outline as default gateway
while [ "$DEFAULT_GATEWAY" != "y" ] && [ "$DEFAULT_GATEWAY" != "n" ]; do
    echo "Use Outline as default gateway? [y/n]: "
    read DEFAULT_GATEWAY
done

if [ "$DEFAULT_GATEWAY" = "y" ]; then
		cat <<EOL >> /etc/init.d/tun2socks
#Replaces default route for Outline
service_started() {
    # This function checks if the default gateway is Outline, if no changes it
     echo 'Replacing default gateway for Outline...'
     sleep 2s
     if ip link show tun1 | grep -q "UP" ; then
         ip route del default #Deletes existing default route
         ip route add default via 172.16.10.2 dev tun1 #Creates default route through the proxy
     fi
}
start() {
    start_service
    service_started
}
EOL
#Checks rc.local and adds script to rc.local to check default route on startup
if ! grep -q "sleep 10" /etc/rc.local; then
sed '/exit 0/i\
sleep 10\
#Check if default route is through Outline and change if not\
if ! ip route | grep -q '\''^default via 172.16.10.2 dev tun1'\''; then\
    /etc/init.d/tun2socks start\
fi\
' /etc/rc.local > /tmp/rc.local.tmp && mv /tmp/rc.local.tmp /etc/rc.local
		echo "All traffic would be routed through Outline"
fi
	else
		cat <<EOL >> /etc/init.d/tun2socks
start() {
    before_start
    start_service
}
EOL
		echo "No changes to default gateway"
fi

echo 'script /etc/init.d/tun2socks created'

chmod +x /etc/init.d/tun2socks
fi

# Step 12: Create symbolic link, autostart
if [ ! -f "/etc/rc.d/S99tun2socks" ]; then
ln -s /etc/init.d/tun2socks /etc/rc.d/S99tun2socks
echo '/etc/init.d/tun2socks /etc/rc.d/S99tun2socks symlink created'
fi

# Step 13: Start service
/etc/init.d/tun2socks start

echo 'Script finished'
