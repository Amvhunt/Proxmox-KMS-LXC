#!/usr/bin/env bash
#==================================================================================
# ░█████╗░███╗░░░███╗██╗░░░██╗██╗░░██╗██╗░░░██╗███╗░░██╗████████╗
# ██╔══██╗████╗░████║██║░░░██║██║░░██║██║░░░██║████╗░██║╚══██╔══╝
# ███████║██╔████╔██║╚██╗░██╔╝███████║██║░░░██║██╔██╗██║░░░██║░░░
# ██╔══██║██║╚██╔╝██║░╚████╔╝░██╔══██║██║░░░██║██║╚████║░░░██║░░░
# ██║░░██║██║░╚═╝░██║░░╚██╔╝░░██║░░██║╚██████╔╝██║░╚███║░░░██║░░░
# ╚═╝░░╚═╝╚═╝░░░░░╚═╝░░░╚═╝░░░╚═╝░░╚═╝░╚═════╝░╚═╝░░╚══╝░░░╚═╝░░░
#         Amvhunt - Universal KMS LXC Installer (Premium)
#==================================================================================

set -e

# ===== ПАРАМЕТРЫ ПО УМОЛЧАНИЮ =====
DEFAULT_OS_TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
DEFAULT_TEMPLATE_STORAGE="local"
DEFAULT_CT_STORAGE="local-lvm"
HOSTNAME="amvhunt-kms"
MEM=256
DISK=2
BRIDGE="vmbr0"
NET_CONF="ip=dhcp"
PASSWORD="kms-server"
VLMCS_PORT=1688
WEB_PORT=8000

# --- AUTO-SELECT CTID ---
for ((i=100; i<10000; i++)); do
    if ! qm status "$i" &>/dev/null && ! pct status "$i" &>/dev/null; then
        CTID=$i
        echo "[INFO] Auto-selected first available CTID: $CTID"
        break
    fi
done

# --- LOGO ---
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
echo "Default OS Template: $DEFAULT_OS_TEMPLATE"
echo

# --- OS TEMPLATE CHOICE ---
read -rp "Press Enter to use default ($DEFAULT_OS_TEMPLATE) or enter another: " OS_TEMPLATE
OS_TEMPLATE=${OS_TEMPLATE:-$DEFAULT_OS_TEMPLATE}

# --- TEMPLATE STORAGE CHOICE ---
read -rp "Press Enter to use default storage for template ($DEFAULT_TEMPLATE_STORAGE) or enter another: " TEMPLATE_STORAGE
TEMPLATE_STORAGE=${TEMPLATE_STORAGE:-$DEFAULT_TEMPLATE_STORAGE}

# --- CONTAINER STORAGE CHOICE ---
read -rp "Press Enter to use default container storage ($DEFAULT_CT_STORAGE) or enter another: " CT_STORAGE
CT_STORAGE=${CT_STORAGE:-$DEFAULT_CT_STORAGE}

# --- BRIDGE (NETWORK) CHOICE ---
read -rp "Press Enter to use default bridge ($BRIDGE) or enter another: " INPUT_BRIDGE
BRIDGE=${INPUT_BRIDGE:-$BRIDGE}

# --- CHECK PROXMOX ---
if ! command -v pveversion >/dev/null; then
  echo "[ERROR] Run on Proxmox host!"
  exit 1
fi

# --- DOWNLOAD TEMPLATE IF NEEDED ---
if ! pveam list $TEMPLATE_STORAGE | grep -q "$OS_TEMPLATE"; then
  echo "[INFO] Downloading LXC template to $TEMPLATE_STORAGE: $OS_TEMPLATE"
  pveam update
  pveam download "$TEMPLATE_STORAGE" "$OS_TEMPLATE"
fi

# --- REMOVE OLD CONTAINER (if exists) ---
if pct status "$CTID" &>/dev/null; then
  echo "[WARN] CT $CTID exists — destroying"
  pct stop "$CTID" || true
  pct destroy "$CTID"
fi

# --- CREATE CONTAINER ---
echo "[INFO] Creating CT $CTID"
pct create "$CTID" "$TEMPLATE_STORAGE:vztmpl/$OS_TEMPLATE" \
  -hostname "$HOSTNAME" \
  -net0 name=eth0,bridge="$BRIDGE",$NET_CONF,firewall=1 \
  -memory "$MEM" -cores 1 -swap 512 \
  -rootfs "$CT_STORAGE:$DISK" \
  -unprivileged 1 \
  -features nesting=1 \
  -password "$PASSWORD" \
  -onboot 1

# --- AUTO-DETECT ALLOWED_SUBNET ---
BRIDGE_IP=$(ip -4 -o addr show dev "$BRIDGE" | awk '{print $4}')
IFS="/." read -r i1 i2 i3 i4 mask <<<"$BRIDGE_IP"
ALLOWED_SUBNET="$i1.$i2.$i3.0/24"
echo "[INFO] Detected ALLOWED_SUBNET as $ALLOWED_SUBNET"

# --- FIREWALL RULES ---
cat >/etc/pve/firewall/$CTID.fw <<EOF
[OPTIONS]
enable: 1

[RULES]
IN ACCEPT -source $ALLOWED_SUBNET -dest port $VLMCS_PORT -proto tcp
IN ACCEPT -source $ALLOWED_SUBNET -dest port $WEB_PORT -proto tcp
IN DROP
EOF

# --- START CT ---
pct start "$CTID"
sleep 7

echo "[INFO] Installing vlmcsd & web interface in container..."
pct exec "$CTID" -- bash -c "
apt update -qq
apt install -y git build-essential python3 python3-flask
git clone https://github.com/Wind4/vlmcsd.git /opt/vlmcsd
cd /opt/vlmcsd
make
install -m 755 bin/vlmcsd /usr/local/bin/vlmcsd
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
