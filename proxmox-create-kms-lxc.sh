#!/usr/bin/env bash
#==================================================================================
#
#          Amvhunt - Proxmox KMS LXC Auto-Installer
#
#   Description: Deploy a minimal Ubuntu LXC container running vlmcsd (KMS server)
#   Author: Chuvak & ChatGPT
#   License: MIT
#==================================================================================

set -e

#----------------------------------------------------------------------------------
# VARIABLES -- Customize if needed
#----------------------------------------------------------------------------------

CTID=120                       # Container ID (must be unique)
HOSTNAME="amvhunt-kms"         # Container hostname
MEM=256                        # Memory in MB
DISK=2                         # Disk size in GB
BRIDGE="vmbr0"                 # Network bridge
NET_TYPE="dhcp"                # "dhcp" or static (e.g. 10.10.10.22/24)
PASSWORD="kms-server"          # Root password (change if needed)
IMAGE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
STORAGE="local-lvm"            # Storage pool for rootfs
VLMCS_PORT=1688                # KMS server port

#----------------------------------------------------------------------------------
# LOGO & INTRO
#----------------------------------------------------------------------------------

cat <<"EOF"
==================================================================================
 ░█████╗░███╗░░░███╗██╗░░░██╗██╗░░██╗██╗░░░██╗███╗░░██╗████████╗
 ██╔══██╗████╗░████║██║░░░██║██║░░██║██║░░░██║████╗░██║╚══██╔══╝
 ███████║██╔████╔██║╚██╗░██╔╝███████║██║░░░██║██╔██╗██║░░░██║░░░
 ██╔══██║██║╚██╔╝██║░╚████╔╝░██╔══██║██║░░░██║██║╚████║░░░██║░░░
 ██║░░██║██║░╚═╝░██║░░╚██╔╝░░██║░░██║╚██████╔╝██║░╚███║░░░██║░░░
 ╚═╝░░╚═╝╚═╝░░░░░╚═╝░░░╚═╝░░░╚═╝░░╚═╝░╚═════╝░╚═╝░░╚══╝░░░╚═╝░░░
            Amvhunt - KMS LXC Auto-Installer
==================================================================================

         Amvhunt - KMS LXC Auto-Installer
           by Amvhunt
================================================
EOF

#----------------------------------------------------------------------------------
# CHECKS & PREPARATION
#----------------------------------------------------------------------------------

echo "[Info] Checking if running on Proxmox VE host..."
if ! command -v pveversion >/dev/null 2>&1; then
    echo "[ERROR] This script must be run on a Proxmox VE host."
    exit 1
fi

echo "[Info] Checking for LXC template image..."
if ! pveam available | grep -q "$IMAGE"; then
    echo "[Info] Downloading LXC image: $IMAGE ..."
    pveam update
    pveam download local $IMAGE
fi

if pct status $CTID &>/dev/null; then
    echo "[Warning] Container $CTID already exists. Removing..."
    pct stop $CTID || true
    pct destroy $CTID
fi

#----------------------------------------------------------------------------------
# CREATE LXC CONTAINER
#----------------------------------------------------------------------------------

echo "[Info] Creating LXC container ($CTID)..."
pct create $CTID local:$IMAGE \
    -hostname $HOSTNAME \
    -net0 name=eth0,bridge=$BRIDGE,ip=$NET_TYPE \
    -cores 1 -memory $MEM -swap 0 \
    -rootfs $STORAGE:$DISK \
    -features nesting=1 \
    -unprivileged 1 \
    -password $PASSWORD

#----------------------------------------------------------------------------------
# START CONTAINER & INSTALL VLMCD
#----------------------------------------------------------------------------------

echo "[Info] Starting container..."
pct start $CTID
sleep 5

echo "[Info] Installing vlmcsd KMS server in container..."

pct exec $CTID -- bash -c "
    apt update &&
    apt install -y git build-essential &&
    git clone https://github.com/Wind4/vlmcsd.git /opt/vlmcsd &&
    cd /opt/vlmcsd &&
    make &&
    ln -sf /opt/vlmcsd/bin/vlmcsd /usr/local/bin/vlmcsd &&
    # Create systemd service for autostart
    cat >/etc/systemd/system/vlmcsd.service <<SERVICE
[Unit]
Description=vlmcsd KMS Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vlmcsd -L 0.0.0.0:$VLMCS_PORT
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE
    systemctl daemon-reload &&
    systemctl enable --now vlmcsd
"

#----------------------------------------------------------------------------------
# DISPLAY RESULT & USAGE
#----------------------------------------------------------------------------------

echo "================================================"
echo "[Success] KMS server is running in LXC container $CTID."
echo "------------------------------------------------"
echo "Container IP addresses:"
pct exec $CTID -- ip -4 addr show eth0 | grep inet
echo "------------------------------------------------"
echo "To activate Windows, use these commands in CMD or PowerShell (as Admin):"
echo
echo "   slmgr /skms <CONTAINER_IP>:$VLMCS_PORT"
echo "   slmgr /ato"
echo
echo "To check activation status:"
echo "   slmgr /xpr"
echo
echo "Autostart: vlmcsd runs automatically on container boot."
echo "Service management inside LXC:"
echo "   systemctl status vlmcsd"
echo "   systemctl restart vlmcsd"
echo
echo "[Note] For security, restrict port $VLMCS_PORT to your VMs/subnet!"
echo "================================================"

# End of script
