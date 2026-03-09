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
#
# The mapping is computed inline within the RUN that needs it (below).
# No temp file or separate ARG required.
# ---------------------------------------------------------------------------
ARG TARGETARCH

# ---------------------------------------------------------------------------
# Install system dependencies
#
# git-lfs   — Git Large File Storage for binary assets (images, PDFs, etc.)
# su-exec   — lightweight privilege de-escalation (Alpine alternative to gosu)
# shadow    — usermod/groupmod for runtime UID/GID remapping
# xz        — only needed for extracting s6-overlay tarballs (removed after)
# ---------------------------------------------------------------------------
RUN apk add --no-cache \
    git \
    git-lfs \
    openssh-client \
    inotify-tools \
    findutils \
    su-exec \
    shadow \
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

# Map TARGETARCH to s6 naming and install the platform-specific binary
RUN case "${TARGETARCH}" in \
      amd64)  S6_ARCH="x86_64"  ;; \
      arm64)  S6_ARCH="aarch64" ;; \
      *)      echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    wget -q "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
      -O /tmp/s6-overlay-arch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz

# Cleanup: remove tarballs and build-only dependency
RUN rm -f /tmp/s6-overlay-*.tar.xz && \
    apk del xz

# ---------------------------------------------------------------------------
# Install obsidian-headless
#
# Pinned to a specific version for build reproducibility. The package is
# pre-stable (0.x), so unpinned installs risk breaking changes.
#
# better-sqlite3 (a dependency) requires native compilation.
# Build deps are installed, used, then removed in one layer to keep
# the final image small.
# ---------------------------------------------------------------------------
RUN apk add --no-cache --virtual .build-deps \
      python3 \
      make \
      g++ && \
    npm install -g obsidian-headless@0.0.4 && \
    npm cache clean --force && \
    apk del .build-deps

# ---------------------------------------------------------------------------
# Create app user and runtime directories
#
# Default UID/GID is 1000. Users override at runtime via PUID/PGID env vars.
# The init-usermap oneshot remaps the UID/GID before services start.
# ---------------------------------------------------------------------------
# The node:22-alpine base image includes a 'node' user (UID/GID 1000).
# Rename it to 'obsidian' for clarity. The UID/GID will be remapped at
# runtime by init-usermap to match PUID/PGID.
RUN (deluser node 2>/dev/null || true) && \
    addgroup -g 1000 obsidian && \
    adduser -u 1000 -G obsidian -s /bin/sh -D obsidian && \
    mkdir -p /vault /config && \
    chown -R obsidian:obsidian /vault /config

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
# PUID/PGID — Runtime user identity (linuxserver.io convention)
#
# Set these to your host user's UID/GID to avoid permission issues with
# bind mounts (especially on macOS).
#
#   docker run -e PUID=501 -e PGID=20 ...       # typical macOS
#   docker run -e PUID=1000 -e PGID=1000 ...    # typical Linux
#
# Defaults to 1000:1000 (the 'obsidian' user created above).
# ---------------------------------------------------------------------------
ENV PUID=1000
ENV PGID=1000

# ---------------------------------------------------------------------------
# Git LFS — Large File Storage for binary assets
#
# When enabled, binary files (images, PDFs, videos, audio) are stored via
# Git LFS instead of directly in the git repository. This keeps the repo
# small and fast even with large attachments.
#
# OBSIDIAN_GIT_LFS_EXTENSIONS overrides the default list of file extensions
# tracked by LFS. Set to a comma-separated list (e.g., "png,jpg,pdf").
# ---------------------------------------------------------------------------
ENV OBSIDIAN_GIT_LFS_ENABLED=true
ENV OBSIDIAN_GIT_LFS_EXTENSIONS="png,jpg,jpeg,gif,bmp,webp,tif,tiff,mp4,mov,avi,mkv,webm,mp3,wav,ogg,flac,m4a,aac,pdf,doc,docx,xls,xlsx,ppt,pptx,zip,tar,gz,7z,rar,woff,woff2,ttf,otf"

# ---------------------------------------------------------------------------
# Volumes
#
#   /config  — Persistent configuration and SSH keys (REQUIRED mount)
#   /vault   — Obsidian vault data + git working tree (optional mount)
# ---------------------------------------------------------------------------
VOLUME ["/config", "/vault"]

# No ports exposed — this container has no web interface or API

# s6-overlay as PID 1
ENTRYPOINT ["/init"]
