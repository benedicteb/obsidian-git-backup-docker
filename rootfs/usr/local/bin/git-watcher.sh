#!/bin/sh
# =============================================================================
# git-watcher.sh — Watches vault for changes and commits/pushes to git
#
# Uses inotifywait (event-driven, not polling) to detect filesystem changes.
# Debounces events to avoid committing during active Obsidian syncs.
#
# Runs as an s6 longrun service — s6 will restart it if it crashes.
#
# NOTE: This script uses BusyBox ash extensions (read -t) which are available
# on Alpine but are not POSIX-standard. The shebang is /bin/sh which is
# BusyBox ash on Alpine.
# =============================================================================
set -eu

# ---------------------------------------------------------------------------
# Configuration (from environment, with defaults)
# ---------------------------------------------------------------------------
DEBOUNCE="${OBSIDIAN_GIT_DEBOUNCE_SECS:-30}"
VAULT="/vault"
BRANCH="${OBSIDIAN_GIT_BRANCH:-main}"

# ---------------------------------------------------------------------------
# Validate configuration
# ---------------------------------------------------------------------------
case "${DEBOUNCE}" in
  ''|*[!0-9]*)
    echo "[git-watcher] ERROR: OBSIDIAN_GIT_DEBOUNCE_SECS must be a positive integer, got: '${DEBOUNCE}'" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
  echo "[git-watcher] $*"
}

log_error() {
  echo "[git-watcher] ERROR: $*" >&2
}

# Track consecutive push failures for escalating warnings
push_failures=0

# ---------------------------------------------------------------------------
# Commit and push any staged changes
# ---------------------------------------------------------------------------
do_commit_and_push() {
  # Stage everything (use -C to avoid cd side effects)
  git -C "${VAULT}" add -A

  # Only commit if there are actual changes
  if git -C "${VAULT}" diff --cached --quiet; then
    log "No changes to commit"
    return 0
  fi

  TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  COMMIT_MSG="vault sync: ${TIMESTAMP}"

  if git -C "${VAULT}" commit -m "${COMMIT_MSG}"; then
    log "Committed: ${COMMIT_MSG}"
  else
    log_error "git commit failed"
    return 1
  fi

  # Pull before push to handle any divergence (rebase keeps linear history)
  if ! git -C "${VAULT}" pull --rebase origin "${BRANCH}" 2>&1; then
    log_error "git pull --rebase failed. Aborting rebase and continuing."
    git -C "${VAULT}" rebase --abort 2>/dev/null || true
    # Don't return error — local commit is preserved, will retry next cycle
  fi

  push_output="$(git -C "${VAULT}" push origin "${BRANCH}" 2>&1)" && {
    log "Pushed to origin/${BRANCH}"
    push_failures=0
    return 0
  }

  # Push failed
  push_failures=$((push_failures + 1))
  log_error "git push failed (attempt #${push_failures}):"
  log_error "${push_output}"
  log_error "Local commit was saved. Push will be retried on next change."

  if [ "${push_failures}" -ge 5 ]; then
    log_error "WARNING: ${push_failures} consecutive push failures. Backup is NOT reaching the remote."
    log_error "Check your SSH key, network, and git remote configuration."
  fi

  # Don't return error — commit is local, push will be retried
}

# ---------------------------------------------------------------------------
# Graceful shutdown: commit any pending changes before exit
# ---------------------------------------------------------------------------
shutdown() {
  log "Shutting down — committing any pending changes..."
  do_commit_and_push || log_error "Final commit/push failed"
  exit 0
}

trap shutdown TERM INT

# ---------------------------------------------------------------------------
# Main: watch for filesystem events and debounce
# ---------------------------------------------------------------------------
log "Starting filesystem watcher on ${VAULT}"
log "Debounce: ${DEBOUNCE}s | Branch: ${BRANCH}"

# Wait for the vault to be ready (git repo must exist)
while [ ! -d "${VAULT}/.git" ]; do
  log "Waiting for git repository at ${VAULT}..."
  sleep 5
done

log "Git repository found. Watching for changes..."

# inotifywait monitors recursively, excluding noisy paths:
#   .git/       — git's own internal writes would cause feedback loops
#   .trash/     — Obsidian trash, gitignored
#   cache/      — Obsidian cache, gitignored, rebuilt automatically
#   workspace*  — Obsidian workspace state, gitignored, high churn
#   graph.json  — Obsidian graph view state, gitignored
#
# -m = monitor mode (don't exit after first event)
# -r = recursive
# -e = event types to watch
# --format = output format (we only care that *something* changed)
#
# The output is piped into a read loop that implements debouncing:
# after the first event, drain all events for DEBOUNCE seconds of quiet,
# then commit and push.

inotifywait -m -r \
  --exclude '/\.(git|trash)(/|$)|/\.obsidian/(workspace.*\.json|graph\.json|cache/)' \
  -e modify,create,delete,move \
  --format '%w%f' \
  "${VAULT}" |
while read -r changed_file; do
  log "Change detected: ${changed_file}. Waiting ${DEBOUNCE}s for more changes..."

  # Debounce: drain events until DEBOUNCE seconds of silence.
  # read -t returns non-zero when the timeout expires (no more events).
  # NOTE: read -t is a BusyBox ash extension (not POSIX).
  debounce_count=0
  while read -t "${DEBOUNCE}" -r _; do
    debounce_count=$((debounce_count + 1))
  done

  [ "${debounce_count}" -gt 0 ] && log "Debounced ${debounce_count} additional change(s)"
  log "Committing changes..."

  do_commit_and_push || log_error "Commit/push cycle failed (will retry on next change)"
done

# If we get here, inotifywait exited unexpectedly
log_error "inotifywait exited unexpectedly. s6 will restart this service."
exit 1
