# =============================================================================
# obsidian-git-backup-docker
#
# Syncs an Obsidian vault via obsidian-headless and backs it up to git.
# Uses s6-overlay for process supervision (PID 1, service ordering, restarts).
#
# Two long-lived services:
#   1. obsidian-sync  — ob sync --continuous (Obsidian headless sync)
#   2. git-watcher    — inotifywait-based watcher that commits/pushes changes
#
# One init service (oneshot):
#   - init-config — validates env, sets up SSH, clones git repo, configures ob
# =============================================================================

FROM node:22-alpine

ARG S6_OVERLAY_VERSION=3.2.2.0

# ---------------------------------------------------------------------------
# Map Docker's TARGETARCH to s6-overlay's architecture naming.
#
# Docker uses:  amd64, arm64
# s6 uses:      x86_64, aarch64
# ---------------------------------------------------------------------------
ARG TARGETARCH
ARG S6_ARCH
RUN case "${TARGETARCH}" in \
      amd64)  S6_ARCH="x86_64"  ;; \
      arm64)  S6_ARCH="aarch64" ;; \
      *)      echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    echo "S6_ARCH=${S6_ARCH}" > /tmp/s6-arch.env

# ---------------------------------------------------------------------------
# Install system dependencies
# ---------------------------------------------------------------------------
RUN apk add --no-cache \
    git \
    openssh-client \
    inotify-tools \
    xz

# ---------------------------------------------------------------------------
# Install s6-overlay v3
#
# Two tarballs:
#   1. noarch  — scripts and service definitions (architecture-independent)
#   2. arch    — statically linked s6 binaries for this platform
# ---------------------------------------------------------------------------
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp/
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz

# Use the arch we determined above
RUN . /tmp/s6-arch.env && \
    wget -q "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
      -O /tmp/s6-overlay-arch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz

# Cleanup
RUN rm -f /tmp/s6-overlay-*.tar.xz /tmp/s6-arch.env

# ---------------------------------------------------------------------------
# Install obsidian-headless
# ---------------------------------------------------------------------------
RUN npm install -g obsidian-headless && \
    npm cache clean --force

# ---------------------------------------------------------------------------
# Create runtime directories
# ---------------------------------------------------------------------------
RUN mkdir -p /vault /config/.ssh

# ---------------------------------------------------------------------------
# Copy rootfs overlay (s6 service definitions + scripts)
# ---------------------------------------------------------------------------
COPY rootfs/ /

# Make scripts executable
RUN chmod +x /usr/local/bin/*.sh

# ---------------------------------------------------------------------------
# s6-overlay configuration
# ---------------------------------------------------------------------------
# If a oneshot init fails, stop the container (fail fast)
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

# ---------------------------------------------------------------------------
# Volumes
#
#   /config  — SSH keys and persistent state (REQUIRED mount)
#   /vault   — Obsidian vault data + git working tree (optional mount)
# ---------------------------------------------------------------------------
VOLUME ["/config", "/vault"]

# s6-overlay as PID 1
ENTRYPOINT ["/init"]
