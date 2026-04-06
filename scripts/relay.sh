#!/bin/bash
# relay.sh -- Parse a Bridge result JSON and output human-readable summary
# Usage: relay.sh <result-file.json>
#    or: cat result.json | relay.sh --stdin
#
# Designed for OpenClaw agents to format Bridge results for users.

set -euo pipefail

if [ "${1:-}" = "--stdin" ]; then
  RESULT_JSON=$(cat)
elif [ -n "${1:-}" ] && [ -f "$1" ]; then
  RESULT_JSON=$(cat "$1")
else
  echo "Usage: relay.sh <result-file.json> | relay.sh --stdin" >&2
  exit 1
fi

python3 -c "
import json, sys

r = json.loads(sys.argv[1])

task_id = r.get('id', 'unknown')
status = r.get('status', 'unknown')
duration = r.get('duration_seconds', 0)

if status == 'completed':
    result = r.get('result', {})
    summary = result.get('summary', 'Task completed.')
    details = result.get('details', '')
    files_changed = result.get('files_changed', [])
    files_created = result.get('files_created', [])
    tests = result.get('tests_run')
    warnings = result.get('warnings', [])
    data = result.get('data')

    print(summary)

    if details and len(details) > len(summary) + 20:
        print()
        print(details)

    all_files = files_changed + files_created
    if all_files:
        print()
        label = 'Files'
        if files_changed and files_created:
            label = f'Changed: {\", \".join(files_changed)} | Created: {\", \".join(files_created)}'
        else:
            label = f'Files: {\", \".join(all_files)}'
        print(label)

    if tests:
        print(f'Tests: {tests}')

    for w in warnings:
        print(f'Warning: {w}')

    if data and isinstance(data, dict):
        # Print structured data keys as a hint
        print(f'Data keys: {\", \".join(data.keys())}')

elif status == 'failed':
    error = r.get('error', {})
    code = error.get('code', 'UNKNOWN')
    message = error.get('message', 'No details')
    suggestion = error.get('suggestion', '')
    recoverable = error.get('recoverable', False)

    print(f'FAILED [{code}]: {message}')
    if suggestion:
        print(f'Suggestion: {suggestion}')
    if recoverable:
        print('(recoverable)')

elif status == 'partial':
    result = r.get('result', {})
    print(f'PARTIAL: {result.get(\"summary\", \"Partially completed\")}')
    warnings = result.get('warnings', [])
    for w in warnings:
        print(f'Warning: {w}')

else:
    print(f'Status: {status}')

# Always print task ID and duration on stderr for logging
print(f'[{task_id} | {duration}s | {status}]', file=sys.stderr)
" "$RESULT_JSON"
