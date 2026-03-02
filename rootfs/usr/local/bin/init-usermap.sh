#!/bin/sh
# =============================================================================
# init-usermap.sh — Remap UID/GID of the 'obsidian' user at container start
#
# Follows the linuxserver.io PUID/PGID convention:
#   - PUID and PGID env vars specify the desired UID/GID
#   - The 'obsidian' user/group created at build time is remapped to match
#   - Ownership of /config and /vault is fixed up
#
# This runs as a s6 oneshot BEFORE init-config, so all subsequent services
# (including init-config itself) can use su-exec to run as the correct user.
# =============================================================================
set -eu

log() {
  echo "[init-usermap] $*"
}

log_error() {
  echo "[init-usermap] ERROR: $*" >&2
}

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# ---------------------------------------------------------------------------
# Validate PUID/PGID
# ---------------------------------------------------------------------------
case "${PUID}" in
  ''|*[!0-9]*)
    log_error "PUID must be a numeric UID, got: '${PUID}'"
    log_error "Run 'id -u' on your host to find the correct value."
    log_error "Set PUID in your .env file or docker-compose.yml."
    exit 1
    ;;
esac
case "${PGID}" in
  ''|*[!0-9]*)
    log_error "PGID must be a numeric GID, got: '${PGID}'"
    log_error "Run 'id -g' on your host to find the correct value."
    log_error "Set PGID in your .env file or docker-compose.yml."
    exit 1
    ;;
esac

# Block UID/GID 0 — running services as root defeats privilege separation
if [ "${PUID}" = "0" ]; then
  log_error "PUID=0 (root) is not allowed."
  log_error "Run 'id -u' on your host to find the correct value."
  exit 1
fi
if [ "${PGID}" = "0" ]; then
  log_error "PGID=0 (root) is not allowed."
  log_error "Run 'id -g' on your host to find the correct value."
  exit 1
fi

# ---------------------------------------------------------------------------
# Remap group GID if needed
# ---------------------------------------------------------------------------
CURRENT_GID="$(id -g obsidian)"
if [ "${PGID}" != "${CURRENT_GID}" ]; then
  log "Remapping group 'obsidian' GID: ${CURRENT_GID} → ${PGID}"
  groupmod -o -g "${PGID}" obsidian
fi

# ---------------------------------------------------------------------------
# Remap user UID if needed
# ---------------------------------------------------------------------------
CURRENT_UID="$(id -u obsidian)"
if [ "${PUID}" != "${CURRENT_UID}" ]; then
  log "Remapping user 'obsidian' UID: ${CURRENT_UID} → ${PUID}"
  usermod -o -u "${PUID}" obsidian
fi

# ---------------------------------------------------------------------------
# Fix ownership of runtime directories
#
# Recursive chown only runs when the top-level ownership doesn't match.
# This means it's a no-op on normal restarts (fast) but correctly fixes
# all files when PUID/PGID changes (slower, but necessary).
# ---------------------------------------------------------------------------
fix_ownership() {
  dir="$1"
  if [ -d "${dir}" ]; then
    # BusyBox stat on Alpine — always uses -c format
    dir_uid="$(stat -c '%u' "${dir}")"
    dir_gid="$(stat -c '%g' "${dir}")"
    if [ "${dir_uid}" != "${PUID}" ] || [ "${dir_gid}" != "${PGID}" ]; then
      log "Fixing ownership of ${dir} recursively (${dir_uid}:${dir_gid} → ${PUID}:${PGID})"
      log "  This may take a moment for large vaults..."
      chown -R "${PUID}:${PGID}" "${dir}"
    fi
  fi
}

fix_ownership /config
fix_ownership /vault

log "User: obsidian (UID=${PUID}, GID=${PGID})"
