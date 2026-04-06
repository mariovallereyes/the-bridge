#!/bin/bash
# notify.sh -- Robust Bridge completion notification
#
# Tries multiple delivery methods to ensure the orchestrator agent
# receives the completion signal:
#   1. openclaw system event (primary -- wakes the agent session)
#   2. Write a signal file to a known location (fallback)
#   3. tmux display-message in the orchestrator's pane (visual fallback)
#
# Usage: notify.sh "<message>" [--task-id <id>] [--result-file <path>]
#
# Environment:
#   BRIDGE_DIR              - Bridge directory (default: ~/.the-bridge)
#   BRIDGE_NOTIFY_METHOD    - "auto" (default), "event", "file", "all"
#   BRIDGE_NOTIFY_TIMEOUT   - Timeout for system event in ms (default: 10000)

set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
METHOD="${BRIDGE_NOTIFY_METHOD:-auto}"
TIMEOUT="${BRIDGE_NOTIFY_TIMEOUT:-10000}"
MESSAGE="${1:?Usage: notify.sh '<message>' [--task-id <id>] [--result-file <path>]}"
TASK_ID=""
RESULT_FILE=""

# Parse optional args
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --task-id) TASK_ID="$2"; shift 2 ;;
    --result-file) RESULT_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

SIGNAL_DIR="$BRIDGE_DIR/logs"
SIGNAL_FILE="$SIGNAL_DIR/completion-signal.json"
DELIVERED=false
METHODS_TRIED=""

# Method 1: openclaw system event
try_system_event() {
  if command -v openclaw >/dev/null 2>&1; then
    if openclaw system event --text "$MESSAGE" --mode now --timeout "$TIMEOUT" 2>/dev/null; then
      echo ":: Notification delivered via system event" >&2
      DELIVERED=true
      return 0
    else
      echo ":: System event failed (gateway may be down)" >&2
      return 1
    fi
  else
    echo ":: openclaw not found" >&2
    return 1
  fi
}

# Method 2: Write signal file (orchestrator can poll this)
try_signal_file() {
  mkdir -p "$SIGNAL_DIR"
  python3 -c "
import json
from datetime import datetime
signal = {
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'message': '$MESSAGE',
    'task_id': '$TASK_ID' or None,
    'result_file': '$RESULT_FILE' or None
}
with open('$SIGNAL_FILE', 'w') as f:
    json.dump(signal, f, indent=2)
"
  echo ":: Signal file written to $SIGNAL_FILE" >&2
  return 0
}

# Method 3: tmux display-message (visual notification)
try_tmux_display() {
  # Try to find any non-bridge tmux session to display in
  for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -v "^bridge"); do
    tmux display-message -t "$session" "Bridge: $MESSAGE" 2>/dev/null && {
      echo ":: tmux display-message sent to session $session" >&2
      return 0
    }
  done
  echo ":: No suitable tmux session for display-message" >&2
  return 1
}

# Execute based on method
case "$METHOD" in
  event)
    try_system_event || true
    ;;
  file)
    try_signal_file
    ;;
  all)
    try_system_event || true
    try_signal_file
    try_tmux_display || true
    ;;
  auto|*)
    METHODS_TRIED="event"
    if try_system_event; then
      DELIVERED=true
    else
      METHODS_TRIED="$METHODS_TRIED,file"
      try_signal_file
      METHODS_TRIED="$METHODS_TRIED,tmux"
      try_tmux_display || true
    fi
    ;;
esac

# Always write signal file as a durable record
if [ "$METHOD" != "file" ]; then
  try_signal_file 2>/dev/null || true
fi

if [ "$DELIVERED" = "true" ]; then
  echo ":: Notification delivered" >&2
else
  echo ":: Primary notification failed. Signal file written as fallback." >&2
fi
