#!/bin/bash
# dispatch.sh — Send a task to The Bridge
# Usage: ./dispatch.sh <task-json-file>
#    or: ./dispatch.sh --inline '<json string>'
#    or: echo '{"id":...}' | ./dispatch.sh --stdin

set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
TMUX_SESSION="${BRIDGE_TMUX_SESSION:-bridge}"
TRIGGER_PHRASE="${BRIDGE_TRIGGER:-check inbox}"

# --- Parse input ---
TASK_JSON=""

if [[ "${1:-}" == "--inline" ]]; then
  TASK_JSON="$2"
elif [[ "${1:-}" == "--stdin" ]]; then
  TASK_JSON="$(cat)"
elif [[ -n "${1:-}" && -f "$1" ]]; then
  TASK_JSON="$(cat "$1")"
else
  echo "Usage: $0 <task-file.json> | --inline '<json>' | --stdin"
  exit 1
fi

# --- Validate JSON ---
TASK_ID=$(echo "$TASK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
if [[ -z "$TASK_ID" ]]; then
  echo "ERROR: Invalid JSON or missing 'id' field"
  exit 1
fi

# --- Check prerequisites ---
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: tmux session '$TMUX_SESSION' not found"
  echo "Start it with: tmux new-session -d -s $TMUX_SESSION -c $BRIDGE_DIR"
  exit 1
fi

if [[ -f "$BRIDGE_DIR/inbox/$TASK_ID.json" ]]; then
  echo "ERROR: Task $TASK_ID already exists in inbox"
  exit 1
fi

# --- Atomic write to inbox ---
echo "$TASK_JSON" > "$BRIDGE_DIR/inbox/.$TASK_ID.json.tmp"
mv "$BRIDGE_DIR/inbox/.$TASK_ID.json.tmp" "$BRIDGE_DIR/inbox/$TASK_ID.json"
echo "✅ Task $TASK_ID written to inbox"

# --- Trigger worker ---
tmux send-keys -t "$TMUX_SESSION" "$TRIGGER_PHRASE" Enter
echo "⚡ Worker triggered"

echo "📋 Task ID: $TASK_ID"
echo "📁 Result will appear at: $BRIDGE_DIR/outbox/$TASK_ID.json"
