#!/bin/bash
# check-completions.sh -- Check for and consume Bridge completion signals
#
# Reads the durable signal file and any uncollected results in outbox/.
# Returns formatted relay output for each completion found.
# Clears consumed signals to avoid duplicate processing.
#
# Usage:
#   check-completions.sh              # Check and consume (default)
#   check-completions.sh --peek       # Check without consuming
#   check-completions.sh --json       # Output as JSON array
#   check-completions.sh --count      # Just print count of pending completions
#
# Exit codes:
#   0 = completions found and processed
#   1 = no completions pending
#
# Designed for Patti to call from heartbeat, cron, or proactive check.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
SIGNAL_FILE="$BRIDGE_DIR/logs/completion-signal.json"
CONSUMED_LOG="$BRIDGE_DIR/logs/consumed.log"
MODE="${1:-consume}"
FOUND=0

# Ensure logs dir exists
mkdir -p "$BRIDGE_DIR/logs"

# Collect all pending completions from outbox
collect_outbox() {
  find "$BRIDGE_DIR/outbox" -name "*.json" -not -name ".*" 2>/dev/null | sort
}

# Check if a task ID was already consumed (dedup)
is_consumed() {
  local task_id="$1"
  [ -f "$CONSUMED_LOG" ] && grep -qF "$task_id" "$CONSUMED_LOG" 2>/dev/null
}

# Mark a task ID as consumed
mark_consumed() {
  local task_id="$1"
  echo "$task_id $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CONSUMED_LOG"
}

# Trim consumed log to last 100 entries
trim_consumed_log() {
  if [ -f "$CONSUMED_LOG" ] && [ "$(wc -l < "$CONSUMED_LOG" | tr -d ' ')" -gt 100 ]; then
    tail -100 "$CONSUMED_LOG" > "$CONSUMED_LOG.tmp"
    mv "$CONSUMED_LOG.tmp" "$CONSUMED_LOG"
  fi
}

# --- Count mode ---
if [ "$MODE" = "--count" ]; then
  COUNT=0
  for result_file in $(collect_outbox); do
    TASK_ID=$(python3 -c "import json; print(json.load(open('$result_file'))['id'])" 2>/dev/null || echo "")
    if [ -n "$TASK_ID" ] && ! is_consumed "$TASK_ID"; then
      COUNT=$((COUNT + 1))
    fi
  done
  echo "$COUNT"
  [ "$COUNT" -gt 0 ] && exit 0 || exit 1
fi

# --- JSON mode ---
if [ "$MODE" = "--json" ]; then
  RESULTS="["
  FIRST=true
  for result_file in $(collect_outbox); do
    TASK_ID=$(python3 -c "import json; print(json.load(open('$result_file'))['id'])" 2>/dev/null || echo "")
    if [ -n "$TASK_ID" ] && ! is_consumed "$TASK_ID"; then
      [ "$FIRST" = "true" ] && FIRST=false || RESULTS="$RESULTS,"
      RESULTS="$RESULTS$(cat "$result_file")"
      FOUND=$((FOUND + 1))
      if [ "$MODE" != "--peek" ]; then
        mark_consumed "$TASK_ID"
      fi
    fi
  done
  RESULTS="$RESULTS]"
  echo "$RESULTS" | python3 -m json.tool 2>/dev/null || echo "$RESULTS"
  # Clear signal file if we consumed everything
  if [ $FOUND -gt 0 ] && [ "$MODE" != "--peek" ]; then
    rm -f "$SIGNAL_FILE"
    trim_consumed_log
  fi
  [ $FOUND -gt 0 ] && exit 0 || exit 1
fi

# --- Consume or Peek mode ---
for result_file in $(collect_outbox); do
  TASK_ID=$(python3 -c "import json; print(json.load(open('$result_file'))['id'])" 2>/dev/null || echo "")

  if [ -z "$TASK_ID" ]; then
    continue
  fi

  # Skip already consumed
  if is_consumed "$TASK_ID"; then
    continue
  fi

  FOUND=$((FOUND + 1))

  # Format relay output
  if [ -x "$SCRIPT_DIR/relay.sh" ]; then
    echo "--- Bridge completion: $TASK_ID ---"
    bash "$SCRIPT_DIR/relay.sh" "$result_file" 2>/dev/null
    echo ""
  else
    echo "--- Bridge completion: $TASK_ID ---"
    python3 -c "
import json
r = json.load(open('$result_file'))
status = r.get('status','unknown')
if status == 'completed':
    print(r.get('result',{}).get('summary','Completed'))
elif status == 'failed':
    print(f\"FAILED: {r.get('error',{}).get('message','Unknown error')}\")
else:
    print(f'Status: {status}')
" 2>/dev/null
    echo ""
  fi

  # Mark as consumed (unless peeking)
  if [ "$MODE" != "--peek" ]; then
    mark_consumed "$TASK_ID"
  fi
done

# Clear signal file after consuming
if [ $FOUND -gt 0 ] && [ "$MODE" != "--peek" ]; then
  rm -f "$SIGNAL_FILE"
  trim_consumed_log
  echo ":: $FOUND completion(s) consumed" >&2
fi

if [ $FOUND -eq 0 ]; then
  # Also check signal file for completions not yet in outbox
  if [ -f "$SIGNAL_FILE" ]; then
    SIG_TASK=$(python3 -c "import json; s=json.load(open('$SIGNAL_FILE')); print(s.get('task_id','') or '')" 2>/dev/null || echo "")
    SIG_MSG=$(python3 -c "import json; s=json.load(open('$SIGNAL_FILE')); print(s.get('message',''))" 2>/dev/null || echo "")
    if [ -n "$SIG_TASK" ] && ! is_consumed "$SIG_TASK"; then
      echo "--- Bridge signal (result may still be processing): $SIG_TASK ---"
      echo "$SIG_MSG"
      echo ""
      FOUND=1
      if [ "$MODE" != "--peek" ]; then
        mark_consumed "$SIG_TASK"
        rm -f "$SIGNAL_FILE"
      fi
    fi
  fi
fi

[ $FOUND -gt 0 ] && exit 0 || exit 1
