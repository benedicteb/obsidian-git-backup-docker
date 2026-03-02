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

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# ---------------------------------------------------------------------------
# Validate PUID/PGID are numeric
# ---------------------------------------------------------------------------
case "${PUID}" in
  ''|*[!0-9]*) echo "[init-usermap] ERROR: PUID must be numeric, got: '${PUID}'" >&2; exit 1 ;;
esac
case "${PGID}" in
  ''|*[!0-9]*) echo "[init-usermap] ERROR: PGID must be numeric, got: '${PGID}'" >&2; exit 1 ;;
esac

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
# Only chown if the current ownership doesn't match. This avoids slow
# recursive chown on large vaults when permissions are already correct.
# ---------------------------------------------------------------------------
fix_ownership() {
  dir="$1"
  if [ -d "${dir}" ]; then
    dir_uid="$(stat -c '%u' "${dir}" 2>/dev/null || stat -f '%u' "${dir}")"
    dir_gid="$(stat -c '%g' "${dir}" 2>/dev/null || stat -f '%g' "${dir}")"
    if [ "${dir_uid}" != "${PUID}" ] || [ "${dir_gid}" != "${PGID}" ]; then
      log "Fixing ownership of ${dir} (${dir_uid}:${dir_gid} → ${PUID}:${PGID})"
      chown "${PUID}:${PGID}" "${dir}"
    fi
  fi
}

# Fix top-level directories (non-recursive for speed)
fix_ownership /config
fix_ownership /vault

# Ensure .ssh directory and its contents are owned correctly
if [ -d /config/.ssh ]; then
  chown -R "${PUID}:${PGID}" /config/.ssh
fi

log "User: obsidian (UID=${PUID}, GID=${PGID})"
