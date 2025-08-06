# Platinum KMS LXC for Proxmox: Full Guide

## Overview

This guide covers **ultra-fast deployment** of a KMS server in a secure LXC container on Proxmox, and **step-by-step activation** of any Windows 10/11 VM via your own KMS.  
Best for research, farms, business, or test infrastructure.

---

## Step 1: Deploy the KMS LXC Container

1. **Run this one-liner as root on your Proxmox host:**
   ```bash
   bash -c "$(curl -fsSL https://raw.githubusercontent.com/yourgithub/platinum-kms-lxc/main/proxmox-create-kms-lxc.sh)"
   ```
   - You can edit the script before running if you need to change container ID, RAM, disk size, or hostname.

2. **Wait 1-2 minutes for deployment to complete.**

3. **The script will show the container’s IP address** at the end.  
   Save or copy it — you’ll need this IP for Windows activation.

---

## Step 2: (Optional) Security Hardening

- **Restrict access to port 1688 (KMS) to only your VMs**:  
  - Use Proxmox firewall rules  
  - Or set firewall inside the LXC (e.g. with `ufw` or `nftables`)
- **Do not expose KMS to the internet.**  
  This server should be private to your LAN or Proxmox VM subnet.

---

## Step 3: Activate Windows 10/11 via Your KMS

On **each Windows VM** you want to activate:

1. **Open PowerShell or CMD as Administrator.**

2. **Set your KMS server address:**
   ```powershell
   slmgr /skms <KMS_CONTAINER_IP>:1688
   ```
   - Replace `<KMS_CONTAINER_IP>` with the IP shown at the end of the LXC script, e.g. `10.10.10.22`.

3. **(If needed) Install a Generic KMS Client Key**  
   *(Only required if Windows isn’t already using a KMS-compatible edition or asks for a key.)*

   - For Windows 10 Pro:
     ```powershell
     slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX
     ```
   - For other Windows editions, see the [official Microsoft KMS client keys list](https://learn.microsoft.com/en-us/windows-server/get-started/kmsclientkeys).

4. **Activate Windows:**
   ```powershell
   slmgr /ato
   ```

5. **Check activation status:**
   ```powershell
   slmgr /dli
   ```
   or
   ```powershell
   slmgr /xpr
   ```
   - You should see “Windows is activated” (or similar).

---

## Step 4: Automation (Optional)

To automatically activate Windows in clones/VMs, you can include the activation commands in a startup script, Group Policy, or unattend.xml if mass-deploying.

---

## Service Management

- **To check KMS status inside the LXC container:**
  ```bash
  pct exec 120 -- systemctl status vlmcsd
  ```
- **To restart KMS:**
  ```bash
  pct exec 120 -- systemctl restart vlmcsd
  ```
- **To update vlmcsd:**
  ```bash
  pct exec 120 -- bash -c "cd /opt/vlmcsd && git pull && make && systemctl restart vlmcsd"
  ```
- **To destroy the container:**
  ```bash
  pct stop 120
  pct destroy 120
  ```

---

## FAQ / Troubleshooting

- **Q:** *Windows won’t activate!*
  - Double-check the KMS server IP and port (1688).
  - Check that the container is running:  
    `pct exec 120 -- systemctl status vlmcsd`
  - Make sure firewall rules allow Windows VMs to access the KMS container.
  - If using NAT, verify port forwarding.

- **Q:** *Do I need to re-activate after cloning VMs?*
  - Yes, run the activation commands (`slmgr /skms ...` and `slmgr /ato`) on each VM.

- **Q:** *Can I use this for other Windows editions?*
  - Yes! Just use the correct [KMS client key](https://learn.microsoft.com/en-us/windows-server/get-started/kmsclientkeys).

- **Q:** *Can I restrict KMS to only certain VMs?*
  - Yes. Use Proxmox or LXC firewall to limit access by IP/subnet.

---

## Disclaimer

This setup is for legal activation in accordance with Microsoft’s licensing terms and your local laws.  
**Abuse is not permitted.**
