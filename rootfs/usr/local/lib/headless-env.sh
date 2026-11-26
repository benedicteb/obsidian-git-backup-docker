# =============================================================================
# headless-env.sh — Where obsidian-headless keeps its state
#
# obsidian-headless stores its config, sync state (state.db) and log under
# $XDG_CONFIG_HOME/obsidian-headless. By default that is in the obsidian
# user's home directory inside the container, which is lost whenever the
# container is recreated (every Unraid edit, every image update). Losing it
# means a full re-check of every file on the next start.
#
# This points XDG_CONFIG_HOME at the persistent /config volume instead.
#
# The directory is per vault: several containers may share one /config, and
# obsidian-headless finds a vault's config by its local path, which is /vault
# in every container. Separate directories keep containers from picking up
# each other's vault configs.
#
# Sourced by init-config.sh and the obsidian-sync service:
#
#   . /usr/local/lib/headless-env.sh
#
# Requires OBSIDIAN_GIT_VAULT_NAME. Sets and exports XDG_CONFIG_HOME, and
# sets HEADLESS_SYNC_DIR (where obsidian-headless keeps per-vault sync data).
# =============================================================================

: "${OBSIDIAN_GIT_VAULT_NAME:?headless-env.sh: OBSIDIAN_GIT_VAULT_NAME must be set}"

# Make the vault name a safe single path component: replace anything outside
# [A-Za-z0-9._-] with '_'. BusyBox tr works per byte, so different non-ASCII
# names can map to the same string (e.g. two CJK names of equal length).
# Append a checksum of the raw name to keep them apart. The suffix also
# rules out '.' and '..'.
_headless_vault_sum="$(printf '%s' "${OBSIDIAN_GIT_VAULT_NAME}" | cksum | cut -d' ' -f1)"
_headless_vault_dir="$(printf '%s' "${OBSIDIAN_GIT_VAULT_NAME}" | tr -c 'A-Za-z0-9._-' '_')-${_headless_vault_sum}"

XDG_CONFIG_HOME="/config/headless/${_headless_vault_dir}"
export XDG_CONFIG_HOME

# obsidian-headless appends "obsidian-headless/sync/<vault-id>/" itself.
HEADLESS_SYNC_DIR="${XDG_CONFIG_HOME}/obsidian-headless/sync"

unset _headless_vault_dir _headless_vault_sum
