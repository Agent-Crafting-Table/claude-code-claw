#!/bin/bash
# Entrypoint for the claude-code-claw container.
# Launches a tmux session with 3 windows:
#   claude:0    — interactive Claude Code session (via restart-loop.sh)
#   claude:cron — cron job runner
#   claude:slash — Discord slash command handler

set -e

WORKSPACE="${WORKSPACE_DIR:-/workspace}"

# Create required directories
mkdir -p "$WORKSPACE/data" "$WORKSPACE/crons/logs" "$WORKSPACE/memory"

# Initialize model state if not present
if [ ! -f "$WORKSPACE/data/current-model.json" ]; then
  echo '{"model":"sonnet"}' > "$WORKSPACE/data/current-model.json"
fi

# Wipe stale lock files left by previous container instances. SIGKILL,
# OOM kills, and unclean restarts can orphan lock files; without this hook
# any agent that re-acquires the same lock would refuse to start.
if [ -x "$WORKSPACE/scripts/cleanup-stale-locks.sh" ]; then
  bash "$WORKSPACE/scripts/cleanup-stale-locks.sh" || true
fi

# Install npm dependencies if needed
if [ ! -d "$WORKSPACE/node_modules" ]; then
  echo "[start.sh] Installing npm dependencies..."
  cd "$WORKSPACE" && npm install
fi

# Kill any existing claude session
tmux kill-session -t claude 2>/dev/null || true

# Window 0: main Claude Code session
tmux new-session -d -s claude -n bash \
  "bash $WORKSPACE/restart-loop.sh 2>&1 | tee -a $WORKSPACE/crons/logs/restart-loop.log"

# Window 1: cron runner
tmux new-window -t claude -n cron \
  "node $WORKSPACE/scripts/cron-runner.js 2>&1 | tee -a $WORKSPACE/crons/logs/cron-runner.log"

# Window 2: slash command handler
tmux new-window -t claude -n slash \
  "node $WORKSPACE/scripts/discord-slash-handler.js 2>&1 | tee -a $WORKSPACE/crons/logs/slash-handler.log"

echo "[start.sh] All windows launched. Agent is running."

# Keep the container alive
tail -f /dev/null
