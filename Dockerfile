FROM node:24

# Install supervisor for process management and openssh-server for optional SSH access
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    supervisor \
    openssh-server \
    chromium-headless-shell \
    fonts-liberation fonts-noto-color-emoji \
    libatk-bridge2.0-0 \
    ffmpeg imagemagick \
    && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd

# Install OpenClaw globally from npm
RUN npm install -g openclaw@latest

# Add supervisord config and entrypoint script
COPY docker/supervisord.conf /etc/supervisor/conf.d/openclaw.conf
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/patch-config.js /patch-config.js
RUN chmod +x /entrypoint.sh

# Environment setup
ENV NODE_ENV=production
ENV HOME=/home/node
ENV TERM=xterm-256color

# Create data directory for OpenClaw config and generated certs
RUN mkdir -p /home/node/.openclaw && \
    chown -R node:node /home/node

# SSH configuration script
COPY docker/setup-ssh.sh /setup-ssh.sh
RUN chmod +x /setup-ssh.sh

EXPOSE 18789 18790 22

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisor/conf.d/openclaw.conf"]
