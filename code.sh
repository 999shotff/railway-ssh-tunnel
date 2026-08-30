#!/bin/bash
set -e

USERNAME="${SSH_USER:-tunnel}"
PASSWORD="${SSH_PASSWORD:-}"

# ---- create the tunnel user ----
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USERNAME"
    usermod -aG sudo "$USERNAME"
fi

# ---- password: from env, or generate & print ----
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 14)
    echo "=================================================="
    echo " GENERATED SSH/RDP PASSWORD : $PASSWORD"
    echo " (also set SSH_PASSWORD variable to fix your own)"
    echo "=================================================="
fi
echo "$USERNAME:$PASSWORD" | chpasswd

# ---- desktop session for RDP ----
echo "startxfce4" > "/home/$USERNAME/.xsession"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.xsession"

# ---- sshd config ----
cat > /etc/ssh/sshd_config <<'EOF'
Port 22
Protocol 2
PermitRootLogin no
PasswordAuthentication yes
AllowTcpForwarding yes
PermitTunnel yes
GatewayPorts no
X11Forwarding no
ClientAliveInterval 60
ClientAliveCountMax 3
TCPKeepAlive yes
UseDNS no
PrintMotd no
EOF

mkdir -p /run/sshd
/usr/sbin/sshd

# ---- xrdp ----
rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/sesman.pid 2>/dev/null || true
xrdp-sesman
xrdp

# ---- print Dark Tunnel cheat-sheet into the Railway logs ----
HOST_HINT="your-app.up.railway.app"
cat <<EOF

############ DARK TUNNEL CONFIG (copy to phone) ############
USER: $USERNAME
PASS: $PASSWORD

[A] SSH via WebSocket (direct to Railway, port 443)
  Host     : $HOST_HINT
  Port     : 443
  Payload  :
GET / HTTP/1.1[crlf]Host: $HOST_HINT[crlf]Upgrade: WebSocket[crlf]Connection: Upgrade[crlf][crlf]

[B] Through CloudFront (if you add your own distribution)
  Host     : dXXXXXXXXX.cloudfront.net
  Port     : 443
  SNI      : dXXXXXXXXX.cloudfront.net  (or your carrier bug host)
  Payload  :
GET wss://dXXXXXXXXX.cloudfront.net/ HTTP/1.1[crlf]Host: dXXXXXXXXX.cloudfront.net[crlf]Upgrade: WebSocket[crlf]Connection: Upgrade[crlf][crlf]

[C] RDP (add a TCP Proxy on port 3389 in Railway settings)
  Address  : <tcp-proxy-host>.rlwy.net:<assigned-port>

[D] SNI/bug host: generate per carrier at https://snihost.com
###########################################################

EOF

echo "[start] ws_bridge on :${PORT} -> sshd:22 | xrdp on :3389"
exec python3 /opt/ws_bridge.py
