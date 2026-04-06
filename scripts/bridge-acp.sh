#!/bin/bash
# bridge-acp.sh -- OpenClaw ACP-aware Bridge dispatch + poll + relay
# Extended version of bridge.sh with metadata for session tracking and result formatting.
#
# Usage: bridge-acp.sh "<title>" "<description>" [working_dir] [timeout]
#
# Environment variables (all optional):
#   BRIDGE_DIR            - Bridge directory (default: ~/.the-bridge)
#   BRIDGE_TMUX_SESSION   - tmux session name (default: bridge)
#   BRIDGE_TRIGGER        - trigger phrase (default: check inbox)
#   BRIDGE_AGENT          - dispatching agent name (default: openclaw)
#   BRIDGE_SESSION_KEY    - OpenClaw session key for result relay
#   BRIDGE_TASK_TYPE      - task type: code|research|analysis|file|command|composite (default: composite)
#   BRIDGE_CONSTRAINTS    - JSON array of constraint strings
#   BRIDGE_CONTEXT_FILES  - JSON array of file paths for context
#   BRIDGE_BACKGROUND     - background info string
#   BRIDGE_OUTPUT_MODE    - "json" (default) or "relay" (human-readable summary)
#
# Returns: result JSON on stdout (json mode) or formatted summary (relay mode)
# Exit: 0 on success, 1 on failure/timeout

set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
TMUX_SESSION="${BRIDGE_TMUX_SESSION:-bridge}"
TRIGGER_PHRASE="${BRIDGE_TRIGGER:-check inbox}"

TITLE="${1:?Usage: bridge-acp.sh '<title>' '<description>' [working_dir] [timeout]}"
DESCRIPTION="${2:?Missing description}"
WORKING_DIR="${3:-}"
TIMEOUT="${4:-300}"

# ACP metadata (from env)
AGENT="${BRIDGE_AGENT:-openclaw}"
SESSION_KEY="${BRIDGE_SESSION_KEY:-}"
TASK_TYPE="${BRIDGE_TASK_TYPE:-composite}"
CONSTRAINTS="${BRIDGE_CONSTRAINTS:-}"
CONTEXT_FILES="${BRIDGE_CONTEXT_FILES:-}"
BACKGROUND="${BRIDGE_BACKGROUND:-}"
OUTPUT_MODE="${BRIDGE_OUTPUT_MODE:-json}"

# Generate task ID
TASK_ID="task-$(date +%Y%m%d)-$(printf '%03d' $((RANDOM % 1000)))"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Check prerequisites
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: tmux session '$TMUX_SESSION' not found. Start Bridge worker first." >&2
  exit 1
fi

# Build task JSON with full ACP metadata
TASK_JSON=$(python3 -c "
import json, sys, os

task = {
    'id': '$TASK_ID',
    'version': '0.1.0',
    'created_at': '$TIMESTAMP',
    'timeout_seconds': $TIMEOUT,
    'type': '$TASK_TYPE',
    'title': sys.argv[1],
    'description': sys.argv[2],
}

if sys.argv[3]:
    task['working_directory'] = sys.argv[3]

# Build context block
context = {}
bg = os.environ.get('BRIDGE_BACKGROUND', '')
if bg:
    context['background'] = bg
cf = os.environ.get('BRIDGE_CONTEXT_FILES', '')
if cf:
    try:
        context['files'] = json.loads(cf)
    except:
        pass
cs = os.environ.get('BRIDGE_CONSTRAINTS', '')
if cs:
    try:
        context['constraints'] = json.loads(cs)
    except:
        pass
if context:
    task['context'] = context

# Build metadata block (ACP session tracking)
metadata = {
    'source': '$AGENT',
    'dispatched_at': '$TIMESTAMP',
}
sk = os.environ.get('BRIDGE_SESSION_KEY', '')
if sk:
    metadata['session_key'] = sk
task['metadata'] = metadata

print(json.dumps(task, indent=2))
" "$TITLE" "$DESCRIPTION" "$WORKING_DIR")

# Atomic write to inbox
echo "$TASK_JSON" > "$BRIDGE_DIR/inbox/.$TASK_ID.json.tmp"
mv "$BRIDGE_DIR/inbox/.$TASK_ID.json.tmp" "$BRIDGE_DIR/inbox/$TASK_ID.json"

# Trigger worker
tmux send-keys -t "$TMUX_SESSION" "$TRIGGER_PHRASE" Enter

echo ":: Dispatched $TASK_ID (agent=$AGENT, timeout=${TIMEOUT}s)" >&2

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
  echo ":: Complete (${ELAPSED}s)" >&2

  if [ "$OUTPUT_MODE" = "relay" ]; then
    # Human-readable relay format
    python3 -c "
import json, sys

with open('$BRIDGE_DIR/outbox/$TASK_ID.json') as f:
    r = json.load(f)

status = r.get('status', 'unknown')
if status == 'completed':
    result = r.get('result', {})
    print(result.get('summary', 'Task completed.'))
    files = result.get('files_changed', []) + result.get('files_created', [])
    if files:
        print(f\"Files: {', '.join(files)}\")
    tests = result.get('tests_run')
    if tests:
        print(f\"Tests: {tests}\")
    warnings = result.get('warnings', [])
    for w in warnings:
        print(f\"Warning: {w}\")
elif status == 'failed':
    error = r.get('error', {})
    print(f\"FAILED [{error.get('code', 'UNKNOWN')}]: {error.get('message', 'No details')}\")
    if error.get('suggestion'):
        print(f\"Suggestion: {error['suggestion']}\")
    if error.get('recoverable'):
        print('(recoverable -- can retry)')
else:
    print(f\"Status: {status}\")
    if r.get('result', {}).get('summary'):
        print(r['result']['summary'])
"
  else
    # Raw JSON mode
    cat "$BRIDGE_DIR/outbox/$TASK_ID.json"
  fi
  exit 0
else
  echo ":: Timeout after ${TIMEOUT}s" >&2
  exit 1
fi
