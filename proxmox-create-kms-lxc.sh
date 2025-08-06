#!/usr/bin/env bash
#==================================================================================
# ░█████╗░███╗░░░███╗██╗░░░██╗██╗░░██╗██╗░░░██╗███╗░░██╗████████╗
# ██╔══██╗████╗░████║██║░░░██║██║░░██║██║░░░██║████╗░██║╚══██╔══╝
# ███████║██╔████╔██║╚██╗░██╔╝███████║██║░░░██║██╔██╗██║░░░██║░░░
# ██╔══██║██║╚██╔╝██║░╚████╔╝░██╔══██║██║░░░██║██║╚████║░░░██║░░░
# ██║░░██║██║░╚═╝░██║░░╚██╔╝░░██║░░██║╚██████╔╝██║░╚███║░░░██║░░░
# ╚═╝░░╚═╝╚═╝░░░░░╚═╝░░░╚═╝░░░╚═╝░░╚═╝░╚═════╝░╚═╝░░╚══╝░░░╚═╝░░░
#         Amvhunt - Universal KMS LXC Installer
#==================================================================================

set -e

# ===== ПАРАМЕТРЫ ПО УМОЛЧАНИЮ =====
OS_TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
TEMPLATE_STORAGE="local"
CT_STORAGE="local-lvm"
CTID=120
HOSTNAME="amvhunt-kms"
MEM=256
DISK=2
BRIDGE="vmbr0"
NET_CONF="ip=dhcp"
PASSWORD="kms-server"
VLMCS_PORT=1688
WEB_PORT=8000
ALLOWED_SUBNET="192.168.1.0/24"

# -------- ЛОГО ----------
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
echo "OS Template: $OS_TEMPLATE (optimal for KMS LXC on Proxmox)"
echo

# ==== (СКИП ВЫБОР, ЕСЛИ ХОЧЕШЬ — ОСТАВЬ ПОЛЬЗОВАТЕЛЮ ВОЗМОЖНОСТЬ ЗАМЕНИТЬ) ====
read -rp "Press Enter to use default ($OS_TEMPLATE) or enter another: " INPUT_OS
if [[ -n "$INPUT_OS" ]]; then
    OS_TEMPLATE="$INPUT_OS"
fi

# ---- ПРОВЕРКА PROXMOX ----
if ! command -v pveversion >/dev/null; then
  echo "[ERROR] Run on Proxmox host!"
  exit 1
fi

# ---- СКАЧАТЬ ОБРАЗ, ЕСЛИ НУЖНО ----
if ! pveam list $TEMPLATE_STORAGE | grep -q "$OS_TEMPLATE"; then
  echo "[INFO] Downloading LXC template to $TEMPLATE_STORAGE: $OS_TEMPLATE"
  pveam update
  pveam download "$TEMPLATE_STORAGE" "$OS_TEMPLATE"
fi

# ---- УДАЛЕНИЕ СТАРОГО КОНТЕЙНЕРА ----
if pct status "$CTID" &>/dev/null; then
  echo "[WARN] CT $CTID exists — destroying"
  pct stop "$CTID" || true
  pct destroy "$CTID"
fi

# ---- СОЗДАНИЕ КОНТЕЙНЕРА ----
echo "[INFO] Creating CT $CTID"
pct create "$CTID" "$TEMPLATE_STORAGE:vztmpl/$OS_TEMPLATE" \
  -hostname "$HOSTNAME" \
  -net0 name=eth0,bridge="$BRIDGE",$NET_CONF,firewall=1 \
  -memory "$MEM" -cores 1 -swap 0 \
  -rootfs "$CT_STORAGE:$DISK" \
  -unprivileged 1 \
  -features nesting=1 \
  -password "$PASSWORD" \
  -onboot 1

# ---- FIREWALL ----
cat >/etc/pve/firewall/$CTID.fw <<EOF
[OPTIONS]
enable: 1

[RULES]
IN ACCEPT -source $ALLOWED_SUBNET -dest port $VLMCS_PORT -proto tcp
IN ACCEPT -source $ALLOWED_SUBNET -dest port $WEB_PORT -proto tcp
IN DROP
EOF

# ---- START CT ----
pct start "$CTID"
sleep 7

echo "[INFO] Installing vlmcsd & web interface in container..."
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
