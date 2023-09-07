# outline-install-wrt
OpenWRT script to install Outline (Shadowsocks) with xjasonlyu/tun2socks
How to use:

First, get the script and make it executable:

cd /tmp
wget https://raw.githubusercontent.com/1andrevich/outline-install-wrt/main/install_outline.sh -O install_outline.sh
chmod +x install_outline.sh
Check if you have kmod-tun and ip-full installed, if not run:
opkg update
opkg install kmod-tun ip-full

Then run the script:

./install_outline.sh

You'll be asked for your Outline Server IP, Outline (shadowsocks config in ss://base64coded@HOST:PORT format) and if you want to use Outline (shadowsocks) as your default gateway.


If you have any question, please read the FAQ first. Feel free to contact.
