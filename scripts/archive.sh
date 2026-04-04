#!/bin/bash
# archive.sh — Move completed tasks to archive
# Usage: ./archive.sh [task-id]  (specific task)
#    or: ./archive.sh --all      (all outbox tasks)

set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
DATE=$(date +%Y-%m-%d)

archive_task() {
  local task_id="$1"
  local result_file="$BRIDGE_DIR/outbox/$task_id.json"
  
  if [[ ! -f "$result_file" ]]; then
    echo "⚠️  No result found for $task_id"
    return 1
  fi
  
  mkdir -p "$BRIDGE_DIR/archive/$DATE"
  mv "$result_file" "$BRIDGE_DIR/archive/$DATE/$task_id.result.json"
  echo "📦 Archived: $task_id → archive/$DATE/"
}

if [[ "${1:-}" == "--all" ]]; then
  for f in "$BRIDGE_DIR/outbox/"*.json; do
    [[ -f "$f" ]] || continue
    TASK_ID=$(basename "$f" .json)
    archive_task "$TASK_ID"
  done
  echo "✅ All tasks archived"
elif [[ -n "${1:-}" ]]; then
  archive_task "$1"
else
  echo "Usage: $0 <task-id> | --all"
  exit 1
fi
