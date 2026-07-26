FROM mcr.microsoft.com/devcontainers/javascript-node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      iptables ipset aggregate curl dnsutils iproute2 jq ripgrep \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code @openai/codex

COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh && \
    echo 'node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh' \
      > /etc/sudoers.d/firewall && chmod 0440 /etc/sudoers.d/firewall
