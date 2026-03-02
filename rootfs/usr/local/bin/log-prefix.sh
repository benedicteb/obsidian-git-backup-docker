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
# Requires: mkfifo (coreutils)
# =============================================================================
set -eu

PREFIX="$1"
shift

# Create a temporary FIFO for capturing output
FIFO="$(mktemp -u /tmp/log-prefix.XXXXXX)"
mkfifo "${FIFO}"

# Start the prefixer in the background — reads from FIFO, writes to stdout.
# Uses a while-read loop instead of sed because BusyBox sed does not support
# -u (unbuffered). Shell's built-in read/echo is naturally line-buffered.
while IFS= read -r line; do
    printf '%s %s\n' "${PREFIX}" "${line}"
done < "${FIFO}" &
READER_PID=$!

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
# Disable set -e for the wait block: we need to capture the child's exit
# code without the shell aborting on non-zero. If a trapped signal (TERM/INT)
# interrupts wait, it returns 128+signum; we then re-wait for the real code.
set +e
wait "${CMD_PID}" 2>/dev/null
EXIT_CODE=$?
if [ "${EXIT_CODE}" -gt 128 ] 2>/dev/null; then
    # wait was interrupted by a signal. Re-wait for the child's real exit code.
    wait "${CMD_PID}" 2>/dev/null
    EXIT_CODE=$?
fi
set -e

# Command is done — its side of the FIFO is closed, the reader gets EOF.
wait "${READER_PID}" 2>/dev/null || true

exit "${EXIT_CODE}"
