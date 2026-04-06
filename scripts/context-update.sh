#!/bin/bash
# context-update.sh -- Append a completed task to CONTEXT.md task history
# Usage: context-update.sh <result-file.json>
#    or: cat result.json | context-update.sh --stdin
#
# Appends a row to the "Recent Task History" table in CONTEXT.md.
# Keeps the last 10 entries (trims oldest if over limit).

set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
CONTEXT_FILE="${BRIDGE_DIR}/CONTEXT.md"
MAX_HISTORY=10

if [ ! -f "$CONTEXT_FILE" ]; then
  echo "ERROR: $CONTEXT_FILE not found" >&2
  exit 1
fi

# Read result JSON
if [ "${1:-}" = "--stdin" ]; then
  RESULT_JSON=$(cat)
elif [ -n "${1:-}" ] && [ -f "$1" ]; then
  RESULT_JSON=$(cat "$1")
else
  echo "Usage: context-update.sh <result-file.json> | --stdin" >&2
  exit 1
fi

# Extract fields
ROW=$(python3 -c "
import json, sys
from datetime import datetime

r = json.loads(sys.argv[1])
task_id = r.get('id', 'unknown')
status = r.get('status', 'unknown')
date = r.get('completed_at', '')[:10] or datetime.now().strftime('%Y-%m-%d')

if status == 'completed':
    summary = r.get('result', {}).get('summary', 'Completed')
    icon = '✅'
elif status == 'failed':
    summary = r.get('error', {}).get('message', 'Failed')
    icon = '❌'
elif status == 'partial':
    summary = r.get('result', {}).get('summary', 'Partial')
    icon = '⚠️'
else:
    summary = status
    icon = '?'

task_type = 'composite'
# Try to get type from metadata or infer
summary_short = summary[:80] + '...' if len(summary) > 80 else summary

print(f'| {task_id} | {date} | {task_type} | {summary_short} | {icon} {status} |')
" "$RESULT_JSON")

# Update the date header
python3 -c "
import sys, re
from datetime import datetime

with open('$CONTEXT_FILE', 'r') as f:
    content = f.read()

# Update the 'Last updated' line
today = datetime.now().strftime('%Y-%m-%d')
content = re.sub(
    r'\*Last updated by orchestrator:.*\*',
    f'*Last updated by orchestrator: {today}*',
    content
)

# Find the task history table and append the new row
# Look for the table header pattern
lines = content.split('\n')
new_lines = []
table_found = False
history_rows = []

i = 0
while i < len(lines):
    line = lines[i]
    # Detect the task history table header
    if '| Task ID' in line and '| Date' in line:
        table_found = True
        new_lines.append(line)
        i += 1
        # Skip separator row
        if i < len(lines) and lines[i].startswith('|---'):
            new_lines.append(lines[i])
            i += 1
        # Collect existing rows
        while i < len(lines) and lines[i].startswith('|') and '(none yet)' not in lines[i]:
            history_rows.append(lines[i])
            i += 1
        # Skip the '(none yet)' placeholder if present
        if i < len(lines) and '(none yet)' in lines[i]:
            i += 1
        # Add new row
        history_rows.append(sys.argv[1])
        # Trim to last N entries
        history_rows = history_rows[-$MAX_HISTORY:]
        new_lines.extend(history_rows)
        continue
    new_lines.append(line)
    i += 1

if not table_found:
    # No table found, just append
    new_lines.append('')
    new_lines.append(sys.argv[1])

with open('$CONTEXT_FILE', 'w') as f:
    f.write('\n'.join(new_lines))

print(f'Updated: {sys.argv[1].strip()}', file=sys.stderr)
" "$ROW"

echo "CONTEXT.md updated" >&2
