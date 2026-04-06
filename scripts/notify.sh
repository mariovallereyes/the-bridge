#!/bin/bash
# notify.sh -- Robust Bridge completion notification
#
# Tries multiple delivery methods to ensure the orchestrator agent
# receives the completion signal:
#   1. openclaw system event (primary, but flaky in current setup)
#   2. direct message into the known OpenClaw session (strong fallback)
#   3. write a signal file to a known location (durable fallback)
#   4. tmux display-message in a non-bridge session (visual fallback)
#
# Usage: notify.sh "<message>" [--task-id <id>] [--result-file <path>]
#
# Environment:
#   BRIDGE_DIR                - Bridge directory (default: ~/.the-bridge)
#   BRIDGE_NOTIFY_METHOD      - auto|event|direct|file|all (default: auto)
#   BRIDGE_NOTIFY_TIMEOUT     - Timeout for system event in ms (default: 10000)
#   BRIDGE_NOTIFY_SESSION_KEY - Direct-session fallback target

set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
METHOD="${BRIDGE_NOTIFY_METHOD:-auto}"
TIMEOUT="${BRIDGE_NOTIFY_TIMEOUT:-10000}"
SESSION_KEY="${BRIDGE_NOTIFY_SESSION_KEY:-agent:main:whatsapp:direct:+16502966520}"
MESSAGE="${1:?Usage: notify.sh '<message>' [--task-id <id>] [--result-file <path>] }"
TASK_ID=""
RESULT_FILE=""

shift || true
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

try_system_event() {
  command -v openclaw >/dev/null 2>&1 || return 1
  openclaw system event --text "$MESSAGE" --mode now --timeout "$TIMEOUT" >/dev/null 2>&1
}

try_direct_session() {
  command -v openclaw >/dev/null 2>&1 || return 1
  openclaw agent --session "$SESSION_KEY" --message "$MESSAGE" >/dev/null 2>&1
}

try_signal_file() {
  mkdir -p "$SIGNAL_DIR"
  _NF_MESSAGE="$MESSAGE" _NF_TASK_ID="$TASK_ID" _NF_RESULT_FILE="$RESULT_FILE" _NF_SIGNAL_FILE="$SIGNAL_FILE" python3 -c "
import json, os
from datetime import datetime
signal = {
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'message': os.environ.get('_NF_MESSAGE', ''),
    'task_id': os.environ.get('_NF_TASK_ID') or None,
    'result_file': os.environ.get('_NF_RESULT_FILE') or None,
}
with open(os.environ['_NF_SIGNAL_FILE'], 'w') as f:
    json.dump(signal, f, indent=2)
"
  return 0
}

try_tmux_display() {
  for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -v "^bridge" || true); do
    tmux display-message -t "$session" "Bridge: $MESSAGE" 2>/dev/null && return 0
  done
  return 1
}

case "$METHOD" in
  event)
    try_system_event && DELIVERED=true || true
    ;;
  direct)
    try_direct_session && DELIVERED=true || true
    ;;
  file)
    try_signal_file && DELIVERED=true || true
    ;;
  all)
    try_system_event && DELIVERED=true || true
    try_direct_session && DELIVERED=true || true
    try_signal_file || true
    try_tmux_display || true
    ;;
  auto|*)
    if try_system_event; then
      DELIVERED=true
    elif try_direct_session; then
      DELIVERED=true
    else
      try_signal_file || true
      try_tmux_display || true
    fi
    ;;
esac

# Always leave a durable artifact
try_signal_file >/dev/null 2>&1 || true

if [ "$DELIVERED" = "true" ]; then
  echo ":: Notification delivered" >&2
else
  echo ":: Primary delivery failed. Fallbacks recorded." >&2
fi
