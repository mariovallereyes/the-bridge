#!/bin/bash
# poll.sh — Wait for a Bridge task result
# Usage: ./poll.sh <task-id> [timeout_seconds]

set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
TASK_ID="${1:?Usage: $0 <task-id> [timeout_seconds]}"
TIMEOUT="${2:-300}"

RESULT_FILE="$BRIDGE_DIR/outbox/$TASK_ID.json"
ELAPSED=0
INTERVAL=3

echo "⏳ Waiting for result: $TASK_ID (timeout: ${TIMEOUT}s)"

while [[ ! -f "$RESULT_FILE" ]] && [[ $ELAPSED -lt $TIMEOUT ]]; do
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
  
  # Slow down after 60 seconds
  if [[ $ELAPSED -gt 60 && $INTERVAL -lt 10 ]]; then
    INTERVAL=10
  fi
  
  # Show progress every 30 seconds
  if [[ $((ELAPSED % 30)) -eq 0 ]]; then
    echo "  ... ${ELAPSED}s elapsed"
  fi
done

if [[ -f "$RESULT_FILE" ]]; then
  echo "✅ Result ready (${ELAPSED}s)"
  echo "---"
  cat "$RESULT_FILE"
else
  echo "❌ TIMEOUT after ${TIMEOUT}s — no result for $TASK_ID"
  echo "Check: ls $BRIDGE_DIR/active/"
  exit 1
fi
