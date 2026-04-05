#!/bin/bash
# bridge.sh — One-command Bridge dispatch + poll
# Usage: bridge.sh "<title>" "<description>" [working_dir] [timeout]
# Returns: result JSON on stdout, exit 0 on success, 1 on failure/timeout

set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
TMUX_SESSION="${BRIDGE_TMUX_SESSION:-bridge}"
TRIGGER_PHRASE="${BRIDGE_TRIGGER:-check inbox}"

TITLE="${1:?Usage: bridge.sh '<title>' '<description>' [working_dir] [timeout]}"
DESCRIPTION="${2:?Missing description}"
WORKING_DIR="${3:-}"
TIMEOUT="${4:-300}"

# Generate task ID
TASK_ID="task-$(date +%Y%m%d)-$(printf '%03d' $((RANDOM % 1000)))"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Check prerequisites
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: tmux session '$TMUX_SESSION' not found. Start Bridge worker first." >&2
  exit 1
fi

# Build task JSON
TASK_JSON=$(python3 -c "
import json, sys
task = {
    'id': '$TASK_ID',
    'version': '0.1.0',
    'created_at': '$TIMESTAMP',
    'timeout_seconds': $TIMEOUT,
    'type': 'composite',
    'title': sys.argv[1],
    'description': sys.argv[2]
}
if sys.argv[3]:
    task['working_directory'] = sys.argv[3]
print(json.dumps(task))
" "$TITLE" "$DESCRIPTION" "$WORKING_DIR")

# Atomic write to inbox
echo "$TASK_JSON" > "$BRIDGE_DIR/inbox/.$TASK_ID.json.tmp"
mv "$BRIDGE_DIR/inbox/.$TASK_ID.json.tmp" "$BRIDGE_DIR/inbox/$TASK_ID.json"

# Trigger worker
tmux send-keys -t "$TMUX_SESSION" "$TRIGGER_PHRASE" Enter

echo "⚡ Dispatched $TASK_ID (timeout: ${TIMEOUT}s)" >&2

# Poll for result
ELAPSED=0
INTERVAL=3
while [ ! -f "$BRIDGE_DIR/outbox/$TASK_ID.json" ] && [ $ELAPSED -lt $TIMEOUT ]; do
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
  if [ $ELAPSED -gt 60 ] && [ $INTERVAL -lt 10 ]; then
    INTERVAL=10
  fi
done

if [ -f "$BRIDGE_DIR/outbox/$TASK_ID.json" ]; then
  echo "✅ Complete (${ELAPSED}s)" >&2
  cat "$BRIDGE_DIR/outbox/$TASK_ID.json"
  exit 0
else
  echo "❌ Timeout after ${TIMEOUT}s" >&2
  exit 1
fi
