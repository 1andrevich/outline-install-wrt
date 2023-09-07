# outline-install-wrt
OpenWRT /bin/sh script to install Outline (Shadowsocks) with [xjasonlyu/tun2socks](https://github.com/xjasonlyu/tun2socks)

## How to use:

First, get the script and make it executable:

    cd /tmp
    wget https://raw.githubusercontent.com/1andrevich/outline-install-wrt/main/install_outline.sh -O install_outline.sh
    chmod +x install_outline.sh

Check if you have kmod-tun and ip-full installed, if not run:

    opkg update
    opkg install kmod-tun ip-full

Then run the script:

You'll need at least **9 MiB of free space** on /

    ./install_outline.sh

You'll be asked for:

 - your Outline Server IP
 - Outline (Shadowsocks) config in "ss://base64coded@HOST:PORT" format
 - If you want to use Outline (shadowsocks) as your default gateway (y/n)





If you have any question, please read the FAQ first. Feel free to contact.
