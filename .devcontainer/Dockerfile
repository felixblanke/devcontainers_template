ARG NODE_VARIANT=22-bookworm
FROM mcr.microsoft.com/devcontainers/javascript-node:${NODE_VARIANT}

# Dependencies of OpenAI's firewall script.
RUN apt-get update && apt-get install -y --no-install-recommends \
      iptables ipset jq dnsutils iproute2 \
    && rm -rf /var/lib/apt/lists/*

# pixi: conda-forge packages with lockfiles built in.
# Recipe from https://pixi.prefix.dev/latest/integration/editor/vscode/
ARG PIXI_VERSION=v0.75.0
RUN curl -fsSL --compressed -o /usr/local/bin/pixi \
      "https://github.com/prefix-dev/pixi/releases/download/${PIXI_VERSION}/pixi-$(uname -m)-unknown-linux-musl" \
    && chmod 0755 /usr/local/bin/pixi && pixi info

# Both CLIs via npm. The official claude-code Dev Container Feature is NOT used:
# an older published artifact of it ships Anthropic's own init-firewall.sh to
# /usr/local/bin, and because Features layer AFTER this Dockerfile it silently
# overwrites the checksum-verified script fetched below. Pin versions here if you
# want reproducible builds.
ARG CODEX_VERSION=latest
ARG CLAUDE_VERSION=latest
RUN npm install -g @openai/codex@${CODEX_VERSION} @anthropic-ai/claude-code@${CLAUDE_VERSION} \
    && npm cache clean --force

# Egress firewall from openai/codex, pinned and checksum-verified rather than
# vendored. To update: bump CODEX_REF, rebuild, and the sha256sum failure prints
# the new hashes. Do not fetch this unpinned -- it runs as root with NET_ADMIN.
ARG CODEX_REF=578c1b2230288104041e880a86d0f7f3a5ca6e47
ARG FIREWALL_SHA256=1932ddde26dc46248488f9d0ac6b894698f360087a20daf78a38e05331bd699d
ARG POSTSTART_SHA256=912d52d541f1194ac52d8d7c4cbb361107e28415de7cb490daa6a993f4e91b0e
ARG RAW=https://raw.githubusercontent.com/openai/codex/${CODEX_REF}/.devcontainer
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/init-firewall.sh "${RAW}/init-firewall.sh"; \
    curl -fsSL -o /usr/local/bin/post-start.sh    "${RAW}/post-start.sh"; \
    echo "${FIREWALL_SHA256}  /usr/local/bin/init-firewall.sh" | sha256sum -c -; \
    echo "${POSTSTART_SHA256}  /usr/local/bin/post-start.sh"   | sha256sum -c -; \
    chmod 0500 /usr/local/bin/init-firewall.sh; \
    chmod 0555 /usr/local/bin/post-start.sh

# Upstream bug: `dig +short A` prints the CNAME chain as well as the A records,
# and the script feeds every line to an IPv4 regex, exiting on the first
# mismatch -- so it aborts on any CNAME-fronted host (auth.openai.com,
# files.pythonhosted.org, and most CDN-backed hosts). Filter to A records only.
# Single-quoted throughout so the build shell expands nothing; sed's c\ replaces
# the whole line. Applied AFTER the checksum check, so if upstream edits this
# line sha256sum fails first and you revisit the patch. The grep -q fails the
# build if the substitution ever stops matching.
RUN sed -i '/ips="$(dig/c\  ips="$(dig +short A "$domain" | grep -E "^[0-9]+([.][0-9]+){3}$")"' \
      /usr/local/bin/init-firewall.sh \
 && grep -q 'grep -E' /usr/local/bin/init-firewall.sh

# Create the volume mount points, owned by node, BEFORE any volume is attached.
# A named volume mounted over a path that does not exist in the image is created
# root-owned, and Claude Code / Codex then silently fail to write their state.
# When the path does exist, Docker copies its contents AND ownership into the
# fresh volume, which is what makes the state survive a reset.
RUN install -d -o root -g root \
      /root/.claude /root/.codex /root/.cache /commandhistory \
    && install -o root -g root /dev/null /commandhistory/.bash_history

USER root
