FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PORT=8080

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    python3 \
    xrdp \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    x11-xserver-utils \
    sudo \
    curl \
    ca-certificates \
    tzdata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd /var/run/xrdp /opt

COPY ws_bridge.py /opt/ws_bridge.py
COPY start.sh /start.sh
RUN chmod +x /start.sh /opt/ws_bridge.py

EXPOSE 8080 3389 22

CMD ["/start.sh"]
