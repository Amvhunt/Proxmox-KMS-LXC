#!/usr/bin/env bash
#==================================================================================
# ░█████╗░███╗░░░███╗██╗░░░██╗██╗░░██╗██╗░░░██╗███╗░░██╗████████╗
# ██╔══██╗████╗░████║██║░░░██║██║░░██║██║░░░██║████╗░██║╚══██╔══╝
# ███████║██╔████╔██║╚██╗░██╔╝███████║██║░░░██║██╔██╗██║░░░██║░░░
# ██╔══██║██║╚██╔╝██║░╚████╔╝░██╔══██║██║░░░██║██║╚████║░░░██║░░░
# ██║░░██║██║░╚═╝░██║░░╚██╔╝░░██║░░██║╚██████╔╝██║░╚███║░░░██║░░░
# ╚═╝░░╚═╝╚═╝░░░░░╚═╝░░░╚═╝░░░╚═╝░░╚═╝░╚═════╝░╚═╝░░╚══╝░░░╚═╝░░░
#             Amvhunt - Universal KMS LXC Installer (Premium)
#==================================================================================

set -e

#---- ASCII LOGO
cat <<"EOF"
░█████╗░███╗░░░███╗██╗░░░██╗██╗░░██╗██╗░░░██╗███╗░░██╗████████╗
██╔══██╗████╗░████║██║░░░██║██║░░██║██║░░░██║████╗░██║╚══██╔══╝
███████║██╔████╔██║╚██╗░██╔╝███████║██║░░░██║██╔██╗██║░░░██║░░░
██╔══██║██║╚██╔╝██║░╚████╔╝░██╔══██║██║░░░██║██║╚████║░░░██║░░░
██║░░██║██║░╚═╝░██║░░╚██╔╝░░██║░░██║╚██████╔╝██║░╚███║░░░██║░░░
╚═╝░░╚═╝╚═╝░░░░░╚═╝░░░╚═╝░░░╚═╝░░╚═╝░╚═════╝░╚═╝░░╚══╝░░░╚═╝░░░
         Amvhunt - Universal KMS LXC Installer
EOF

echo
echo "[INFO] This script deploys a premium KMS LXC with firewall & premium web UI."
echo

#---- CHOOSE STORAGE FOR TEMPLATE AND CT
read -rp "Available storage (for templates): " -e -i "local" TEMPLATE_STORAGE
read -rp "Available storage (for rootfs/containers): " -e -i "local-lvm" CT_STORAGE

#---- STATIC OR DHCP IP
read -rp "Use static IP? (y/n) [n]: " STATIC_ANSWER
if [[ "${STATIC_ANSWER,,}" =~ ^y ]]; then
  read -rp "Enter static IPv4 address (e.g., 192.168.1.99/24): " CT_IP
  read -rp "Enter gateway (e.g., 192.168.1.1): " CT_GATEWAY
  NET_CONF="ip=${CT_IP},gw=${CT_GATEWAY}"
else
  NET_CONF="ip=dhcp"
fi

#---- BRIDGE
read -rp "Network bridge [vmbr0]: " -e -i "vmbr0" BRIDGE

#---- FIREWALL SOURCE SUBNET (по умолчанию 192.168.1.0/24)
read -rp "Allow KMS/Web only for subnet (e.g., 192.168.1.0/24): " -e -i "192.168.1.0/24" ALLOWED_SUBNET

#---- ПАРАМЕТРЫ
CTID=120
HOSTNAME="amvhunt-kms"
MEM=256
DISK=2
PASSWORD="kms-server"
IMAGE_NAME="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
VLMCS_PORT=1688
WEB_PORT=8000

#---- CHECKS
if ! command -v pveversion >/dev/null; then
  echo "[ERROR] Run on Proxmox host!"
  exit 1
fi

#---- DOWNLOAD LXC TEMPLATE IF NEEDED
if ! pveam list $TEMPLATE_STORAGE | grep -q "$IMAGE_NAME"; then
  echo "[INFO] Downloading LXC template to $TEMPLATE_STORAGE: $IMAGE_NAME"
  pveam update
  pveam download "$TEMPLATE_STORAGE" "$IMAGE_NAME"
fi

#---- REMOVE OLD CONTAINER IF EXISTS
if pct status "$CTID" &>/dev/null; then
  echo "[WARN] CT $CTID exists — destroying"
  pct stop "$CTID" || true
  pct destroy "$CTID"
fi

#---- CREATE CONTAINER
echo "[INFO] Creating CT $CTID"
pct create "$CTID" "$TEMPLATE_STORAGE:vztmpl/$IMAGE_NAME" \
  -hostname "$HOSTNAME" \
  -net0 name=eth0,bridge="$BRIDGE",$NET_CONF \
  -memory "$MEM" -cores 1 -swap 0 \
  -rootfs "$CT_STORAGE:$DISK" \
  -unprivileged 1 \
  -features nesting=1 \
  -password "$PASSWORD" \
  -onboot 1 \
  -features fuse=1

#---- ENABLE FIREWALL & ALLOW ONLY SUBNET TO PORTS
pct set "$CTID" -features fuse=1 -features nesting=1 -features keyctl=1
pct set "$CTID" -features mount=1

pct set "$CTID" -features "fuse=1,nesting=1,keyctl=1,mount=1" # for Proxmox 8.x
pct set "$CTID" -features "fuse=1,nesting=1" # for Proxmox 7.x

pct set "$CTID" -features fuse=1
pct set "$CTID" -features nesting=1

pct set "$CTID" -features "fuse=1,nesting=1,keyctl=1"

pct set "$CTID" -features fuse=1

pct set "$CTID" -features nesting=1

pct set "$CTID" -features "fuse=1,nesting=1"

pct set "$CTID" --features fuse=1,nesting=1
pct set "$CTID" -features fuse=1
pct set "$CTID" -features nesting=1

pct set "$CTID" --onboot 1 --features fuse=1,nesting=1

pct set "$CTID" --unprivileged 1 --memory "$MEM" --swap 0 --cores 1

pct set "$CTID" --features fuse=1,nesting=1

pct set "$CTID" --net0 "name=eth0,bridge=$BRIDGE,$NET_CONF,firewall=1"

# Firewall rules
pct set "$CTID" -features fuse=1,nesting=1
pct set "$CTID" --net0 "name=eth0,bridge=$BRIDGE,$NET_CONF,firewall=1"

cat >/etc/pve/firewall/$CTID.fw <<EOF
[OPTIONS]
enable: 1

[RULES]
IN ACCEPT -source $ALLOWED_SUBNET -dest port $VLMCS_PORT -proto tcp
IN ACCEPT -source $ALLOWED_SUBNET -dest port $WEB_PORT -proto tcp
IN DROP
EOF

#---- START CT
pct start "$CTID"
sleep 7

echo "[INFO] Installing vlmcsd & web interface..."
pct exec "$CTID" -- bash -c "
apt update -qq
apt install -y git build-essential python3 python3-flask
git clone https://github.com/Wind4/vlmcsd.git /opt/vlmcsd
cd /opt/vlmcsd
make
ln -sf /opt/vlmcsd/bin/vlmcsd /usr/local/bin/vlmcsd
cat >/etc/systemd/system/vlmcsd.service <<EOL
[Unit]
Description=vlmcsd KMS Server
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/vlmcsd -L 0.0.0.0:$VLMCS_PORT
Restart=always
[Install]
WantedBy=multi-user.target
EOL
systemctl daemon-reload
systemctl enable --now vlmcsd

mkdir -p /opt/amvhunt
cat >/opt/amvhunt/app.py <<EOL
from flask import Flask, render_template_string
app = Flask(__name__)
T = '''
<html><head><title>KMS GVLK Keys</title></head><body><h2>Amvhunt Keys</h2><table border=1>
<tr><th>Product</th><th>Key</th></tr>
<tr><td>Win10 Pro</td><td>W269N-WFGWX-YVC9B-4J6C9-T83GX</td></tr>
<tr><td>Win10 Enterprise</td><td>NPPR9-FWDCX-D2C8J-H872K-2YT43</td></tr>
<tr><td>Win11 Pro</td><td>W269N-WFGWX-YVC9B-4J6C9-T83GX</td></tr>
</table>
</body></html>
'''
@app.route('/')
def i():
    return render_template_string(T)
if __name__=='__main__':
    app.run(host='0.0.0.0', port=$WEB_PORT)
EOL

cat >/etc/systemd/system/amvhunt-web.service <<EOL
[Unit]
Description=Amvhunt GVLK Web Server
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/amvhunt/app.py
Restart=always
[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable --now amvhunt-web
"

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo "========================================"
echo "[OK] Amvhunt KMS LXC ready!"
echo "KMS:         tcp://$IP:$VLMCS_PORT"
echo "Web keys:    http://$IP:$WEB_PORT"
echo "Use in Windows:"
echo " slmgr /ipk KEY"
echo " slmgr /skms $IP:$VLMCS_PORT"
echo " slmgr /ato"
echo "Check services:"
echo " pct exec $CTID -- systemctl status vlmcsd"
echo " pct exec $CTID -- systemctl status amvhunt-web"
echo
echo "Firewall restricts access to $ALLOWED_SUBNET only!"
echo "========================================"
