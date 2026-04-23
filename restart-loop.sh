#!/bin/bash
# Supervises the interactive Claude Code session.
#
# Two goals beyond the original loop:
#   1. Persist the session UUID across model switches so /model in Discord
#      kills claude → bash relaunches with --resume → context preserved.
#   2. Self-heal if the persisted UUID points at a missing/empty transcript.
#
# State files:
#   /workspace/data/current-model.json       — { "model": "sonnet" | "opus" | ... }
#   /workspace/data/interactive-session-id   — last good UUID (single line)
#
# After every claude exit we re-scan ~/.claude/projects/-workspace/*.jsonl
# and pin the most-recently-modified large transcript as the resume target.
# This means a fresh session that claude itself spawns gets captured for
# the next loop iteration.

export CLAUDE_FLEET_LONG_LIVED=1
MODEL_STATE="/workspace/data/current-model.json"
SESSION_ID_FILE="/workspace/data/interactive-session-id"
TRANSCRIPT_DIR="/home/node/.claude/projects/-workspace"
MIN_TRANSCRIPT_SIZE="+10k"   # ignore stub/test transcripts
MODE_FILE="/workspace/data/herc-mode"

get_model() {
  if [ -f "$MODEL_STATE" ]; then
    node -e "try{process.stdout.write(JSON.parse(require('fs').readFileSync('$MODEL_STATE','utf8')).model||'sonnet')}catch(e){process.stdout.write('sonnet')}"
  else
    echo "sonnet"
  fi
}

capture_session_id() {
  # Pin the newest non-trivial transcript as the resume target for next loop.
  local newest
  newest=$(find "$TRANSCRIPT_DIR" -maxdepth 1 -name '*.jsonl' -size "$MIN_TRANSCRIPT_SIZE" -printf '%T@ %f\n' 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}' | sed 's/\.jsonl$//')
  if [ -n "$newest" ]; then
    echo "$newest" > "$SESSION_ID_FILE"
    echo "[$(date)] Captured session ID for next loop: $newest"
  fi
}

mkdir -p "$(dirname "$SESSION_ID_FILE")"

read_mode() {
  if [ -f "$MODE_FILE" ]; then tr -d '[:space:]' < "$MODE_FILE"; else echo "claude"; fi
}

while true; do
  if [ "$(read_mode)" = "cursor" ]; then
    echo "[$(date)] [herc-a] Mode=cursor — idling..."
    sleep 10
    continue
  fi

  MODEL=$(get_model)
  SESSION_ID=""
  if [ -f "$SESSION_ID_FILE" ]; then
    SESSION_ID=$(tr -d '[:space:]' < "$SESSION_ID_FILE")
  fi

  if [ -n "$SESSION_ID" ] && [ -s "$TRANSCRIPT_DIR/${SESSION_ID}.jsonl" ]; then
    echo "[$(date)] Resuming Claude session $SESSION_ID with model: $MODEL"
    claude --dangerously-skip-permissions --model "$MODEL" \
      --channels plugin:discord@claude-plugins-official \
      --resume "$SESSION_ID"
  else
    echo "[$(date)] Starting fresh Claude session with model: $MODEL"
    claude --dangerously-skip-permissions --model "$MODEL" \
      --channels plugin:discord@claude-plugins-official
  fi

  capture_session_id
  echo "[$(date)] Claude exited. Restarting in 10s..."
  sleep 10
done
