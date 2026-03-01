#!/bin/sh
# =============================================================================
# git-watcher.sh — Watches vault for changes and commits/pushes to git
#
# Uses inotifywait (event-driven, not polling) to detect filesystem changes.
# Debounces events to avoid committing during active Obsidian syncs.
#
# Runs as an s6 longrun service — s6 will restart it if it crashes.
# =============================================================================
set -eu

# ---------------------------------------------------------------------------
# Configuration (from environment, with defaults)
# ---------------------------------------------------------------------------
DEBOUNCE="${OBSIDIAN_GIT_DEBOUNCE_SECS:-30}"
VAULT="/vault"
BRANCH="${OBSIDIAN_GIT_BRANCH:-main}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
  echo "[git-watcher] $*"
}

log_error() {
  echo "[git-watcher] ERROR: $*" >&2
}

# ---------------------------------------------------------------------------
# Commit and push any staged changes
# ---------------------------------------------------------------------------
do_commit_and_push() {
  cd "${VAULT}"

  # Stage everything
  git add -A

  # Only commit if there are actual changes
  if git diff --cached --quiet; then
    log "No changes to commit"
    return 0
  fi

  TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  COMMIT_MSG="vault sync: ${TIMESTAMP}"

  if git commit -m "${COMMIT_MSG}"; then
    log "Committed: ${COMMIT_MSG}"
  else
    log_error "git commit failed"
    return 1
  fi

  if git push origin "${BRANCH}"; then
    log "Pushed to origin/${BRANCH}"
  else
    log_error "git push failed (will retry on next change)"
    # Don't return error — the commit is local, push will be retried
    # next time the watcher triggers.
  fi
}

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

# inotifywait monitors recursively, excluding .git directory.
# -m = monitor mode (don't exit after first event)
# -r = recursive
# --exclude = skip .git directory (its own writes would cause loops)
# -e = event types to watch
# --format = output format (we only care that *something* changed)
#
# The output is piped into a read loop that implements debouncing:
# after the first event, drain all events for DEBOUNCE seconds of quiet,
# then commit and push.

inotifywait -m -r \
  --exclude '/\.git(/|$)' \
  -e modify,create,delete,move \
  --format '%w%f' \
  "${VAULT}" 2>/dev/null |
while read -r changed_file; do
  log "Change detected: ${changed_file}"

  # Debounce: drain events until DEBOUNCE seconds of silence.
  # read -t returns non-zero when the timeout expires (no more events).
  while read -t "${DEBOUNCE}" -r _; do :; done

  log "Debounce complete. Committing changes..."

  do_commit_and_push || log_error "Commit/push cycle failed (will retry on next change)"
done

# If we get here, inotifywait exited unexpectedly
log_error "inotifywait exited unexpectedly. s6 will restart this service."
exit 1
