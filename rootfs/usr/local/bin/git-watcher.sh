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
# Helpers
# ---------------------------------------------------------------------------
LOG_TAG="git-watcher"
. /usr/local/lib/log-functions.sh

# ---------------------------------------------------------------------------
# Configuration (from environment, with defaults)
# ---------------------------------------------------------------------------
DEBOUNCE="${OBSIDIAN_GIT_DEBOUNCE_SECS:-30}"
PULL_INTERVAL="${OBSIDIAN_GIT_PULL_INTERVAL:-300}"
VAULT="/vault"
BRANCH="${OBSIDIAN_GIT_BRANCH:-main}"

# ---------------------------------------------------------------------------
# Validate configuration
# ---------------------------------------------------------------------------
case "${DEBOUNCE}" in
  ''|*[!0-9]*)
    log_error "OBSIDIAN_GIT_DEBOUNCE_SECS must be a positive integer, got: '${DEBOUNCE}'"
    exit 1
    ;;
  0)
    log_error "OBSIDIAN_GIT_DEBOUNCE_SECS must be >= 1 (got 0). A zero debounce commits on every file event."
    exit 1
    ;;
esac

case "${PULL_INTERVAL}" in
  ''|*[!0-9]*)
    log_error "OBSIDIAN_GIT_PULL_INTERVAL must be a non-negative integer, got: '${PULL_INTERVAL}'"
    exit 1
    ;;
esac

# Minimum pull interval is 10 seconds (when enabled). Values 1-9 are too
# aggressive for a network operation and would cause issues with the
# EOF-vs-timeout detection in the main loop.
if [ "${PULL_INTERVAL}" -gt 0 ] && [ "${PULL_INTERVAL}" -lt 10 ]; then
  log_error "OBSIDIAN_GIT_PULL_INTERVAL must be 0 (disabled) or >= 10, got: '${PULL_INTERVAL}'"
  exit 1
fi

# Track consecutive push failures for escalating warnings
push_failures=0

# Track whether the remote branch exists. Starts false — set to true after
# the first successful push, or if ls-remote confirms the branch exists.
# Avoids a network round-trip (ls-remote) on every commit cycle.
remote_branch_verified=false

# ---------------------------------------------------------------------------
# Pull from remote — rebase first, merge fallback if rebase fails
#
# Strategy:
#   1. Try git pull --rebase (linear history, clean)
#   2. If rebase fails (conflicts), abort and fall back to merge with
#      -X ours (local/Obsidian content wins conflicts, remote history
#      is fully preserved in the merge commit)
#   3. --allow-unrelated-histories handles the case where local and
#      remote were initialized independently (e.g., container started
#      against an empty remote, then the remote was initialized
#      separately from another machine)
#
# Returns 0 on success or if remote is empty. Returns 1 on failure.
# On failure, local commits are preserved — the caller should still
# attempt to push (which will fail on divergence but succeed if the
# issue was transient).
# ---------------------------------------------------------------------------
do_pull() {
  # Check if the remote branch exists yet. On a brand-new bare repo the
  # remote has no branches at all — pulling would fail with
  # "couldn't find remote ref <branch>".
  #
  # We cache the result after the first successful push to avoid a network
  # round-trip (ls-remote) on every commit cycle.
  if ! "${remote_branch_verified}"; then
    if git -C "${VAULT}" ls-remote --exit-code --heads origin "${BRANCH}" >/dev/null 2>&1; then
      remote_branch_verified=true
    else
      log "Remote branch origin/${BRANCH} does not exist yet — skipping pull"
      return 0
    fi
  fi

  # Strategy 1: Rebase (preferred — keeps linear history)
  # --allow-unrelated-histories handles independently initialized repos
  pull_output="$(git -C "${VAULT}" pull --rebase --allow-unrelated-histories origin "${BRANCH}" 2>&1)" && {
    log "Pulled from origin/${BRANCH} (rebase)"
    return 0
  }

  log_error "git pull --rebase failed:"
  log_error "${pull_output}"

  # Abort the failed rebase to restore the working tree
  git -C "${VAULT}" rebase --abort 2>/dev/null || true

  # Strategy 2: Merge fallback with local wins (-X ours)
  # Creates a merge commit but preserves ALL history from both sides.
  # -X ours: for conflicting hunks, keep the local (Obsidian) version.
  # Non-conflicting remote changes are still merged in normally.
  log "Retrying with merge strategy (local content wins conflicts)..."
  merge_output="$(git -C "${VAULT}" pull --no-rebase --allow-unrelated-histories -X ours origin "${BRANCH}" 2>&1)" && {
    log "Pulled from origin/${BRANCH} (merge, local wins)"
    return 0
  }

  # Both strategies failed — this is unusual (e.g., network error, lock file)
  log_error "git pull merge fallback also failed:"
  log_error "${merge_output}"
  log_error "Local commits are safe. Pull will be retried on the next cycle."
  return 1
}

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

  # Pull before push to handle any divergence with the remote
  do_pull || true  # don't abort on pull failure — still attempt push

  # Use -u (--set-upstream) so the first push to an empty remote creates the
  # branch. On subsequent pushes this is a harmless no-op.
  push_output="$(git -C "${VAULT}" push -u origin "${BRANCH}" 2>&1)" && {
    log "Pushed to origin/${BRANCH}"
    push_failures=0
    remote_branch_verified=true
    return 0
  }

  # Push failed
  push_failures=$((push_failures + 1))
  log_error "git push failed (${push_failures} consecutive failure(s)):"
  log_error "${push_output}"
  log_error "Your commit is saved locally. Push will be retried on the next file change."

  if [ "${push_failures}" -ge 5 ]; then
    log_error "WARNING: ${push_failures} consecutive push failures. Backup is NOT reaching the remote."
    log_error "Check your SSH key, network, and git remote configuration."
  fi

  # Don't return error — commit is local, push will be retried
}

# ---------------------------------------------------------------------------
# FIFO for inotifywait output
#
# inotifywait writes to a named FIFO; the main loop reads from it.
# This keeps the read loop in the main shell process (not a pipe
# subshell), so signal traps work correctly — in particular, the
# shutdown trap that commits pending changes before the container stops.
#
# A pipe (inotifywait | while read ...) would put the while loop in a
# subshell where POSIX requires traps to be reset to default disposition.
# ---------------------------------------------------------------------------
EVENTS_FIFO="$(mktemp -u /tmp/git-watcher-events.XXXXXX)"
mkfifo "${EVENTS_FIFO}"

cleanup() {
  rm -f "${EVENTS_FIFO}"
  # Kill inotifywait if still running
  [ -n "${INOTIFY_PID:-}" ] && kill "${INOTIFY_PID}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Graceful shutdown: commit any pending changes before exit
# ---------------------------------------------------------------------------
shutdown() {
  log "Shutting down — committing any pending changes..."
  do_commit_and_push || log_error "Final commit/push failed"
  cleanup
  exit 0
}

trap shutdown TERM INT
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Main: watch for filesystem events and debounce
# ---------------------------------------------------------------------------
log "Starting filesystem watcher on ${VAULT}"
if [ "${PULL_INTERVAL}" -gt 0 ]; then
  log "Debounce: ${DEBOUNCE}s | Pull interval: ${PULL_INTERVAL}s | Branch: ${BRANCH}"
else
  log "Debounce: ${DEBOUNCE}s | Periodic pull: disabled (pull only before push) | Branch: ${BRANCH}"
fi

# Wait for the vault to be ready (git repo must exist)
while [ ! -d "${VAULT}/.git" ]; do
  log "Waiting for git repository at ${VAULT}..."
  sleep 5
done

log "Git repository found. Watching for changes..."

# inotifywait monitors recursively, excluding noisy paths.
# These exclusions should be a superset of the vault .gitignore:
# any gitignored file should also be excluded here to avoid
# unnecessary watcher trigger → debounce → "no changes" cycles.
#
#   .git/                — git internals (would cause feedback loops)
#   .trash/              — Obsidian trash
#   cache/               — Obsidian cache (rebuilt automatically)
#   workspace*.json      — Obsidian workspace state (high churn)
#   graph.json           — Obsidian graph view state
#
# Note: plugin data.json files are NOT excluded here because they
# contain user settings (Templater, Tasks, etc.) that should be backed
# up. The vault .gitignore also does not ignore them by default.
#
# -m = monitor mode (don't exit after first event)
# -r = recursive
# -e = event types to watch
# --format = output format (we only care that *something* changed)
#
# inotifywait writes to the FIFO in the background. The main loop
# reads from the FIFO, keeping traps active in the main process.

inotifywait -m -r \
  --exclude '/\.(git|trash)(/|$)|/\.obsidian/(workspace.*\.json|graph\.json|cache/)' \
  -e modify,create,delete,move \
  --format '%w%f' \
  "${VAULT}" > "${EVENTS_FIFO}" 2>&1 &
INOTIFY_PID=$!

# Main event loop — reads from the FIFO (not a pipe subshell).
# This runs in the main shell process where trap shutdown TERM INT
# is active, ensuring graceful shutdown commits work correctly.
while true; do
  # Wait for the next filesystem event OR a pull-interval timeout.
  # - If PULL_INTERVAL=0, block until a file event arrives (no periodic pull).
  # - If PULL_INTERVAL>0, timeout after PULL_INTERVAL seconds of silence to
  #   pull any remote changes even when no local files have changed.
  #
  # read -t returns non-zero on BOTH timeout and EOF (FIFO closed).
  # We distinguish them by measuring wall-clock time: a real timeout takes
  # ~PULL_INTERVAL seconds, while EOF returns almost instantly (< 2s).
  # The minimum PULL_INTERVAL of 10s provides a large safety margin.
  if [ "${PULL_INTERVAL}" -gt 0 ]; then
    read_start="$(date +%s)"
    if ! read -t "${PULL_INTERVAL}" -r changed_file; then
      read_elapsed=$(( $(date +%s) - read_start ))
      if [ "${read_elapsed}" -lt 2 ]; then
        # EOF — inotifywait exited (FIFO closed almost immediately)
        break
      fi
      # Timeout — no local changes, but the remote may have advanced.
      log "No local changes in ${PULL_INTERVAL}s. Checking remote..."
      do_pull || log_error "Periodic pull failed (will retry next interval)"
      continue
    fi
  else
    if ! read -r changed_file; then
      # EOF — inotifywait exited
      break
    fi
  fi

  log "Change detected: ${changed_file}. Waiting ${DEBOUNCE}s for more changes..."

  # Debounce: drain events until DEBOUNCE seconds of silence.
  # read -t returns non-zero when the timeout expires (no more events
  # within DEBOUNCE seconds). This is safe under set -eu because the
  # while loop tests read's exit code as its condition — a non-zero
  # return simply terminates the loop without triggering set -e.
  debounce_count=0
  while read -t "${DEBOUNCE}" -r _; do
    debounce_count=$((debounce_count + 1))
  done

  [ "${debounce_count}" -gt 0 ] && log "Debounced ${debounce_count} additional change(s)"
  log "Committing changes..."

  do_commit_and_push || log_error "Commit/push cycle failed (will retry on next change)"
done < "${EVENTS_FIFO}"

# If we get here, inotifywait exited unexpectedly
log_error "inotifywait exited unexpectedly. s6 will restart this service."
cleanup
exit 1
