#!/bin/sh
# =============================================================================
# log-prefix.sh — Run a command with a log prefix on every output line
#
# Usage: log-prefix.sh PREFIX COMMAND [ARGS...]
#
# Runs COMMAND as a direct child process, forwarding SIGTERM/SIGINT.
# Reads COMMAND's stdout+stderr line by line and prepends PREFIX.
#
# This avoids the pipeline problems of `cmd | sed 's/^/prefix/'`:
#   - Signal delivery: SIGTERM is forwarded to the child explicitly
#   - Exit code: the real exit code is preserved and returned to s6
#   - No SIGPIPE risk: the child writes to a FIFO, not a pipe
#
# Requires: mkfifo (coreutils), BusyBox sed -u (unbuffered)
# =============================================================================
set -eu

PREFIX="$1"
shift

# Create a temporary FIFO for capturing output
FIFO="$(mktemp -u /tmp/log-prefix.XXXXXX)"
mkfifo "${FIFO}"

# Start the prefixer in the background — reads from FIFO, writes to stdout
# Use | as sed delimiter to avoid issues if PREFIX contains /
sed -u "s|^|${PREFIX} |" < "${FIFO}" &
SED_PID=$!

# Run the actual command, sending stdout+stderr to the FIFO.
# This is a direct child of this script, so we can signal it explicitly.
"$@" > "${FIFO}" 2>&1 &
CMD_PID=$!

# On SIGTERM/SIGINT: forward to the command, then clean up.
# The EXIT trap handles FIFO removal regardless of how we exit.
trap 'kill -TERM "${CMD_PID}" 2>/dev/null || true' TERM INT
trap 'rm -f "${FIFO}"' EXIT

# Wait for the command to finish and capture its exit code.
#
# If a trapped signal (TERM/INT) interrupts wait, the trap handler runs
# (forwarding SIGTERM to the child) and wait returns 128+signum. We then
# re-wait to collect the child's actual exit code after it handles the signal.
if ! wait "${CMD_PID}" 2>/dev/null; then
    # Either the child exited non-zero, or wait was interrupted by a signal.
    # Re-wait: if the child is still running (processing our forwarded signal),
    # this blocks until it exits. If already reaped, returns immediately.
    wait "${CMD_PID}" 2>/dev/null || true
fi
EXIT_CODE=$?

# Command is done — its side of the FIFO is closed, sed gets EOF and exits.
wait "${SED_PID}" 2>/dev/null || true

exit "${EXIT_CODE}"
