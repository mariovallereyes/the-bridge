#!/bin/bash
# openclaw-dispatch.sh -- Full OpenClaw-to-Bridge integration in one command
#
# Performs: preflight health check -> dispatch via bridge-acp.sh -> result relay
#           -> CONTEXT.md update -> optional task registry update
#
# Usage:
#   openclaw-dispatch.sh "<title>" "<description>" [working_dir] [timeout]
#
# Output (stdout):
#   Human-readable relay summary (for the agent to send to the user)
#
# Exit codes:
#   0 = task completed successfully
#   1 = task failed or timed out
#   2 = preflight failed (worker down, bridge dir missing)
#
# Environment variables (all optional, same as bridge-acp.sh plus):
#   BRIDGE_DIR              - Bridge directory (default: ~/.the-bridge)
#   BRIDGE_TMUX_SESSION     - tmux session name (default: bridge)
#   BRIDGE_AGENT            - Agent name (default: openclaw)
#   BRIDGE_SESSION_KEY      - Session key for tracking
#   BRIDGE_TASK_TYPE        - code|research|analysis|file|command|composite
#   BRIDGE_CONSTRAINTS      - JSON array of constraints
#   BRIDGE_CONTEXT_FILES    - JSON array of file paths
#   BRIDGE_BACKGROUND       - Background context string
#   BRIDGE_TASK_REGISTRY    - Path to task registry script (default: auto-detect)
#   BRIDGE_SKIP_PREFLIGHT   - Set to "1" to skip health check
#   BRIDGE_SKIP_CONTEXT     - Set to "1" to skip CONTEXT.md update
#   BRIDGE_SKIP_REGISTRY    - Set to "1" to skip task registry update

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
TMUX_SESSION="${BRIDGE_TMUX_SESSION:-bridge}"
SKIP_PREFLIGHT="${BRIDGE_SKIP_PREFLIGHT:-0}"
SKIP_CONTEXT="${BRIDGE_SKIP_CONTEXT:-0}"
SKIP_REGISTRY="${BRIDGE_SKIP_REGISTRY:-0}"

TITLE="${1:?Usage: openclaw-dispatch.sh '<title>' '<description>' [working_dir] [timeout]}"
DESCRIPTION="${2:?Missing description}"
WORKING_DIR="${3:-}"
TIMEOUT="${4:-300}"

# Auto-detect task registry
TASK_REGISTRY="${BRIDGE_TASK_REGISTRY:-}"
if [ -z "$TASK_REGISTRY" ]; then
  # Look in common locations
  for candidate in \
    "$HOME/.openclaw/workspace/tasks/log-task.sh" \
    "$(dirname "$SCRIPT_DIR")/../../tasks/log-task.sh"; do
    if [ -x "$candidate" ]; then
      TASK_REGISTRY="$candidate"
      break
    fi
  done
fi

# --- Phase 1: Preflight ---
if [ "$SKIP_PREFLIGHT" != "1" ]; then
  HEALTH=$("$SCRIPT_DIR/health.sh" --json 2>/dev/null || echo '{"healthy":false}')
  IS_HEALTHY=$(echo "$HEALTH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('healthy', False))" 2>/dev/null || echo "False")

  if [ "$IS_HEALTHY" = "False" ]; then
    PROBLEMS=$(echo "$HEALTH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('problems','Worker is down') or 'Worker is down')" 2>/dev/null || echo "Worker is down")
    echo "Bridge preflight failed: $PROBLEMS" >&2
    echo "Bridge is not available. $PROBLEMS"
    exit 2
  fi
  echo ":: Preflight passed" >&2
fi

# --- Phase 2: Dispatch ---
# Force relay output mode internally, capture both relay output and raw JSON
export BRIDGE_OUTPUT_MODE=json
RESULT_JSON=$("$SCRIPT_DIR/bridge-acp.sh" "$TITLE" "$DESCRIPTION" "$WORKING_DIR" "$TIMEOUT" 2>/dev/null)
DISPATCH_EXIT=$?

if [ $DISPATCH_EXIT -ne 0 ] || [ -z "$RESULT_JSON" ]; then
  echo ":: Dispatch failed or timed out (exit $DISPATCH_EXIT)" >&2
  echo "Bridge task timed out after ${TIMEOUT}s. The worker may still be processing."
  exit 1
fi

# Extract task ID and status from result
TASK_ID=$(echo "$RESULT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id','unknown'))" 2>/dev/null || echo "unknown")
STATUS=$(echo "$RESULT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")
echo ":: Task $TASK_ID completed with status: $STATUS" >&2

# --- Phase 3: Relay ---
RELAY_OUTPUT=$(echo "$RESULT_JSON" | "$SCRIPT_DIR/relay.sh" --stdin 2>/dev/null)

# --- Phase 4: Context Update ---
if [ "$SKIP_CONTEXT" != "1" ] && [ -f "$BRIDGE_DIR/CONTEXT.md" ]; then
  echo "$RESULT_JSON" | BRIDGE_DIR="$BRIDGE_DIR" "$SCRIPT_DIR/context-update.sh" --stdin 2>/dev/null || true
  echo ":: CONTEXT.md updated" >&2
fi

# --- Phase 5: Task Registry ---
if [ "$SKIP_REGISTRY" != "1" ] && [ -n "$TASK_REGISTRY" ] && [ -x "$TASK_REGISTRY" ]; then
  PROJECT="${WORKING_DIR:-$BRIDGE_DIR}"
  if [ "$STATUS" = "completed" ]; then
    SUMMARY=$(echo "$RESULT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result',{}).get('summary','Completed'))" 2>/dev/null || echo "Completed")
    "$TASK_REGISTRY" done "$TASK_ID" "{\"summary\": \"$SUMMARY\"}" 2>/dev/null || true
  elif [ "$STATUS" = "failed" ]; then
    ERROR_MSG=$(echo "$RESULT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error',{}).get('message','Failed'))" 2>/dev/null || echo "Failed")
    "$TASK_REGISTRY" failed "$TASK_ID" "{\"error\": \"$ERROR_MSG\"}" 2>/dev/null || true
  fi
  echo ":: Task registry updated" >&2
fi

# --- Output ---
echo "$RELAY_OUTPUT"

# Exit based on status
if [ "$STATUS" = "completed" ]; then
  exit 0
else
  exit 1
fi
