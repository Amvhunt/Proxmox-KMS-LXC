#!/usr/bin/env bash
#==================================================================================
# ░█████╗░███╗░░░███╗██╗░░░██╗██╗░░██╗██╗░░░██╗███╗░░██╗████████╗
# ██╔══██╗████╗░████║██║░░░██║██║░░██║██║░░░██║████╗░██║╚══██╔══╝
# ███████║██╔████╔██║╚██╗░██╔╝███████║██║░░░██║██╔██╗██║░░░██║░░░
# ██╔══██║██║╚██╔╝██║░╚████╔╝░██╔══██║██║░░░██║██║╚████║░░░██║░░░
# ██║░░██║██║░╚═╝░██║░░╚██╔╝░░██║░░██║╚██████╔╝██║░╚███║░░░██║░░░
# ╚═╝░░╚═╝╚═╝░░░░░╚═╝░░░╚═╝░░░╚═╝░░╚═╝░╚═════╝░╚═╝░░╚══╝░░░╚═╝░░░
#           Amvhunt - Platinum KMS LXC Installer
#==================================================================================

set -e

# CONFIGURABLE PARAMETERS
CTID=120
HOSTNAME="amvhunt-kms"
MEM=256
DISK=2
BRIDGE="vmbr0"
NET_TYPE="dhcp"
PASSWORD="kms-server"
IMAGE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
STORAGE="local-lvm"
VLMCS_PORT=1688
WEB_PORT=8000

# Show LOGO and info
cat <<"EOF"
░█████╗░███╗░░░███╗██╗░░░██╗██╗░░██╗██╗░░░██╗███╗░░██╗████████╗
██╔══██╗████╗░████║██║░░░██║██║░░██║██║░░░██║████╗░██║╚══██╔══╝
███████║██╔████╔██║╚██╗░██╔╝███████║██║░░░██║██╔██╗██║░░░██║░░░
██╔══██║██║╚██╔╝██║░╚████╔╝░██╔══██║██║░░░██║██║╚████║░░░██║░░░
██║░░██║██║░╚═╝░██║░░╚██╔╝░░██║░░██║╚██████╔╝██║░╚███║░░░██║░░░
╚═╝░░╚═╝╚═╝░░░░░╚═╝░░░╚═╝░░░╚═╝░░╚═╝░╚═════╝░╚═╝░░╚══╝░░░╚═╝░░░
      Amvhunt - Platinum KMS LXC Installer
EOF

echo
echo "[INFO] This script will deploy a premium KMS server in a Proxmox LXC with:"
echo " - Auto-start KMS (vlmcsd)"
echo " - Premium web interface with all GVLK keys at port $WEB_PORT"
echo

# CHECKS & PREPARATION
if ! command -v pveversion >/dev/null 2>&1; then
    echo "[ERROR] This script must be run on a Proxmox VE host."
    exit 1
fi

# --- Download template if needed ---
if ! pveam available | grep -q "$IMAGE"; then
    echo "[INFO] Downloading LXC image: $IMAGE ..."
    pveam update
    pveam download local $IMAGE
fi

# --- Remove previous container if exists ---
if pct status $CTID &>/dev/null; then
    echo "[Warning] Container $CTID already exists. Removing..."
    pct stop $CTID || true
    pct destroy $CTID
fi

# CREATE LXC CONTAINER
echo "[INFO] Creating LXC container ($CTID)..."
pct create $CTID local:$IMAGE \
    -hostname $HOSTNAME \
    -net0 name=eth0,bridge=$BRIDGE,ip=$NET_TYPE \
    -cores 1 -memory $MEM -swap 0 \
    -rootfs $STORAGE:$DISK \
    -features nesting=1 \
    -unprivileged 1 \
    -password $PASSWORD

echo "[INFO] Starting container..."
pct start $CTID
sleep 7

# INSTALL VLMCD & PREMIUM WEB INTERFACE
echo "[INFO] Installing KMS server and web interface..."

pct exec $CTID -- bash -c "
apt update -qq
apt install -y git build-essential python3 python3-flask
# VLMCD KMS
git clone https://github.com/Wind4/vlmcsd.git /opt/vlmcsd
cd /opt/vlmcsd
make
ln -sf /opt/vlmcsd/bin/vlmcsd /usr/local/bin/vlmcsd
# Systemd service for KMS
cat > /etc/systemd/system/vlmcsd.service <<EOF2
[Unit]
Description=vlmcsd KMS Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vlmcsd -L 0.0.0.0:$VLMCS_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF2
systemctl daemon-reload
systemctl enable --now vlmcsd

# Flask Premium Web Interface
mkdir -p /opt/amvhunt
cat > /opt/amvhunt/app.py <<EOF3
from flask import Flask, render_template_string

app = Flask(__name__)

TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
  <title>Amvhunt Platinum KMS - GVLK Keys</title>
  <style>
    body { font-family: Segoe UI,Arial,sans-serif; background:#181C23; color:#eee; }
    h2 { color:#93E9BE; }
    .container { max-width: 800px; margin:30px auto; background: #22232c; border-radius:10px; padding: 30px; box-shadow:0 0 24px #000; }
    table { border-collapse: collapse; width:100%; margin-bottom: 1em; }
    th,td { border:1px solid #444; padding:10px 8px; }
    th { background:#222; color:#93E9BE; }
    code { background: #252b38; color:#1df7a8; padding:2px 4px; border-radius:3px; }
    .instructions { background: #252b38; padding:18px; margin-bottom:18px; border-radius: 7px;}
    .footer { margin-top:35px; font-size:0.95em; color:#999;}
  </style>
</head>
<body>
  <div class="container">
    <h2>🪪 Amvhunt KMS Client Setup Keys</h2>
    <div class="instructions">
      <b>Activate Windows manually:</b><br>
      <code>slmgr /ipk [KEY]</code><br>
      <code>slmgr /skms [KMS_SERVER_IP]:1688</code><br>
      <code>slmgr /ato</code>
    </div>
    <table>
      <tr><th>Product</th><th>GVLK Key</th></tr>
      <tr><td>Windows 11 Pro</td><td><code>W269N-WFGWX-YVC9B-4J6C9-T83GX</code></td></tr>
      <tr><td>Windows 11 Enterprise</td><td><code>NPPR9-FWDCX-D2C8J-H872K-2YT43</code></td></tr>
      <tr><td>Windows 11 Education</td><td><code>NW6C2-QMPVW-D7KKK-3GKT6-VCFB2</code></td></tr>
      <tr><td>Windows 10 Pro</td><td><code>W269N-WFGWX-YVC9B-4J6C9-T83GX</code></td></tr>
      <tr><td>Windows 10 Enterprise</td><td><code>NPPR9-FWDCX-D2C8J-H872K-2YT43</code></td></tr>
      <tr><td>Windows 10 Education</td><td><code>NW6C2-QMPVW-D7KKK-3GKT6-VCFB2</code></td></tr>
      <tr><td>Office 2019 Pro Plus</td><td><code>6MWKP-HH8Q2-93T6X-KBKQT-CDQRD</code></td></tr>
      <tr><td>Office 2021 Pro Plus</td><td><code>FXYTK-NJJ8C-GB6DW-3DYQT-6F7TH</code></td></tr>
      <tr><td>Office 2016 Pro Plus</td><td><code>XQNVK-8JYDB-WJ9W3-YJ8YR-WFG99</code></td></tr>
    </table>
    <div class="footer">
      Full list: <a href='https://learn.microsoft.com/en-us/windows-server/get-started/kmsclientkeys' style='color:#93E9BE'>Microsoft Docs</a><br>
      <b>Amvhunt Platinum KMS</b> — Open <b>/</b> for keys anytime.<br>
      Web UI runs on port $WEB_PORT (Flask, Python3).
    </div>
  </div>
</body>
</html>
'''

@app.route('/')
def index():
    return render_template_string(TEMPLATE)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=$WEB_PORT)
EOF3

cat > /etc/systemd/system/amvhunt-web.service <<EOF4
[Unit]
Description=Amvhunt GVLK Web Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/amvhunt/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF4

systemctl daemon-reload
systemctl enable --now amvhunt-web
"

# DISPLAY RESULT & INSTRUCTIONS
IPADDR=$(pct exec $CTID -- hostname -I | awk '{print $1}')

echo "======================================================"
echo "[SUCCESS] Amvhunt Platinum KMS LXC deployed!"
echo
echo "KMS server:            tcp://${IPADDR}:$VLMCS_PORT"
echo "Premium web interface: http://${IPADDR}:$WEB_PORT"
echo
echo "🪪 Example Windows activation (in CMD as Admin):"
echo "  slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX"
echo "  slmgr /skms ${IPADDR}:$VLMCS_PORT"
echo "  slmgr /ato"
echo
echo "Web GVLK page:  http://${IPADDR}:$WEB_PORT"
echo
echo "To check KMS:   pct exec $CTID -- systemctl status vlmcsd"
echo "To check web:   pct exec $CTID -- systemctl status amvhunt-web"
echo
echo "For more keys visit:"
echo "  https://learn.microsoft.com/en-us/windows-server/get-started/kmsclientkeys"
echo "======================================================"
