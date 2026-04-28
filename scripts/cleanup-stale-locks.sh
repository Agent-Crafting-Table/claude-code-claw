#!/usr/bin/env bash
# cleanup-stale-locks.sh — wipe stale lock files left behind by killed processes.
#
# Runs on container boot and (optionally) on agent-toggle events. Lock
# files are normally cleaned up by their owner via process.on('exit'), but
# SIGKILL, container restarts, or OOM kills leave them orphaned. After
# that any agent that uses the same lock will refuse to start, thinking
# its predecessor is still running.
#
# This script removes:
#   - $WORKSPACE/crons/*.pid       — cron-runner lock and similar daemon PIDs
#                                     (only if the named PID is dead)
#   - $WORKSPACE/data/*_LOCK       — domain-specific lock files older than
#                                     LOCK_MAX_AGE_MINUTES (default 60)
#
# Add additional lock-file patterns by appending to LOCK_PATTERNS below.
#
# Usage:
#   bash cleanup-stale-locks.sh           # default: 60min threshold
#   LOCK_MAX_AGE_MINUTES=30 bash cleanup-stale-locks.sh
#
# Exit code is always 0 — failures are logged but never fatal. This is a
# best-effort hygiene step; don't let it block the boot.

set -u

WORKSPACE="${WORKSPACE_DIR:-/workspace}"
LOCK_MAX_AGE_MINUTES="${LOCK_MAX_AGE_MINUTES:-60}"

# Patterns of lock files to clean by age. Add domain-specific globs here.
LOCK_PATTERNS=(
  "$WORKSPACE/data/*_LOCK"
  "$WORKSPACE/data/*.lock"
)

# ── PID files: only remove when the named PID is dead ─────────────────────
for pidfile in "$WORKSPACE"/crons/*.pid; do
  [ -f "$pidfile" ] || continue
  pid="$(tr -d '[:space:]' < "$pidfile" 2>/dev/null || true)"
  if [ -z "$pid" ]; then
    rm -f "$pidfile"
    echo "[cleanup-stale-locks] removed empty PID file: $pidfile"
    continue
  fi
  if kill -0 "$pid" 2>/dev/null; then
    # Live process — leave the lock alone
    continue
  fi
  rm -f "$pidfile"
  echo "[cleanup-stale-locks] removed stale PID file: $pidfile (pid $pid not running)"
done

# ── Domain-specific lock files: remove if older than threshold ────────────
for pattern in "${LOCK_PATTERNS[@]}"; do
  # shellcheck disable=SC2086
  for lock in $pattern; do
    [ -f "$lock" ] || continue
    if find "$lock" -mmin "+$LOCK_MAX_AGE_MINUTES" -print -quit 2>/dev/null | grep -q .; then
      rm -f "$lock"
      echo "[cleanup-stale-locks] removed stale lock: $lock (>${LOCK_MAX_AGE_MINUTES}min old)"
    fi
  done
done

exit 0
