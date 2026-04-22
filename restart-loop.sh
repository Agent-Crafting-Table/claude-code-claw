#!/bin/bash
# Supervises the interactive Claude Code session.
# Reads the active model from data/current-model.json on each restart.
# Resumes the most recent session transcript if available.
#
# Model switching: update data/current-model.json and send Ctrl+C to claude:0
# — the loop restarts Claude with the new model automatically.

export CLAUDE_FLEET_LONG_LIVED=1

WORKSPACE="${WORKSPACE_DIR:-/workspace}"
MODEL_STATE="$WORKSPACE/data/current-model.json"
SESSION_ID_FILE="$WORKSPACE/data/session-id"
TRANSCRIPT_DIR="/root/.claude/projects/-workspace"
MIN_TRANSCRIPT_SIZE="+10k"

get_model() {
  if [ -f "$MODEL_STATE" ]; then
    node -e "try{process.stdout.write(JSON.parse(require('fs').readFileSync('$MODEL_STATE','utf8')).model||'sonnet')}catch(e){process.stdout.write('sonnet')}"
  else
    echo "sonnet"
  fi
}

# Resolve alias to full model name
resolve_model() {
  case "$1" in
    opus)    echo "claude-opus-4-6" ;;
    haiku)   echo "claude-haiku-4-5" ;;
    *)       echo "claude-sonnet-4-6" ;;
  esac
}

capture_session_id() {
  local newest
  newest=$(find "$TRANSCRIPT_DIR" -maxdepth 1 -name '*.jsonl' -size "$MIN_TRANSCRIPT_SIZE" -printf '%T@ %f\n' 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}' | sed 's/\.jsonl$//')
  if [ -n "$newest" ]; then
    echo "$newest" > "$SESSION_ID_FILE"
    echo "[$(date)] Captured session ID: $newest"
  fi
}

mkdir -p "$(dirname "$SESSION_ID_FILE")"

while true; do
  ALIAS=$(get_model)
  MODEL=$(resolve_model "$ALIAS")
  SESSION_ID=""

  if [ -f "$SESSION_ID_FILE" ]; then
    SESSION_ID=$(tr -d '[:space:]' < "$SESSION_ID_FILE")
  fi

  if [ -n "$SESSION_ID" ] && [ -s "$TRANSCRIPT_DIR/${SESSION_ID}.jsonl" ]; then
    echo "[$(date)] Resuming session $SESSION_ID with model: $MODEL"
    claude --dangerously-skip-permissions --model "$MODEL" \
      --channels plugin:discord@claude-plugins-official \
      --resume "$SESSION_ID"
  else
    echo "[$(date)] Starting fresh session with model: $MODEL"
    claude --dangerously-skip-permissions --model "$MODEL" \
      --channels plugin:discord@claude-plugins-official
  fi

  capture_session_id
  echo "[$(date)] Claude exited. Restarting in 10s..."
  sleep 10
done
