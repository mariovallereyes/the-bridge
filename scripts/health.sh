#!/bin/bash
# health.sh -- Bridge worker health check
# Usage: health.sh [--json]
#
# Checks: tmux session alive, orphans in active/, stale results in outbox/,
# worker responsiveness. Returns exit 0 if healthy, 1 if issues found.
# With --json, outputs machine-readable health status.

set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
TMUX_SESSION="${BRIDGE_TMUX_SESSION:-bridge}"
JSON_MODE="${1:-}"
ISSUES=0

check_tmux() {
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "up"
  else
    echo "down"
  fi
}

count_files() {
  local dir="$1"
  find "$dir" -name "*.json" -not -name ".*" 2>/dev/null | wc -l | tr -d ' '
}

count_orphans() {
  # Tasks in active/ older than 10 minutes
  find "$BRIDGE_DIR/active" -name "*.json" -not -name ".*" -mmin +10 2>/dev/null | wc -l | tr -d ' '
}

count_stale_outbox() {
  # Results in outbox/ older than 1 hour (should have been consumed)
  find "$BRIDGE_DIR/outbox" -name "*.json" -not -name ".*" -mmin +60 2>/dev/null | wc -l | tr -d ' '
}

TMUX_STATUS=$(check_tmux)
INBOX_COUNT=$(count_files "$BRIDGE_DIR/inbox")
ACTIVE_COUNT=$(count_files "$BRIDGE_DIR/active")
OUTBOX_COUNT=$(count_files "$BRIDGE_DIR/outbox")
ORPHAN_COUNT=$(count_orphans)
STALE_COUNT=$(count_stale_outbox)

# Determine overall health
HEALTHY=true
PROBLEMS=""

if [ "$TMUX_STATUS" = "down" ]; then
  HEALTHY=false
  PROBLEMS="${PROBLEMS}Worker session '$TMUX_SESSION' is down. "
  ISSUES=$((ISSUES + 1))
fi

if [ "$ORPHAN_COUNT" -gt 0 ]; then
  HEALTHY=false
  PROBLEMS="${PROBLEMS}${ORPHAN_COUNT} orphaned task(s) in active/ (>10 min). "
  ISSUES=$((ISSUES + 1))
fi

if [ "$STALE_COUNT" -gt 0 ]; then
  PROBLEMS="${PROBLEMS}${STALE_COUNT} stale result(s) in outbox/ (>1 hour). "
  ISSUES=$((ISSUES + 1))
fi

if [ "$JSON_MODE" = "--json" ]; then
  python3 << PYEOF
import json
healthy = True if "$HEALTHY" == "true" else False
problems = "$PROBLEMS".strip() or None
print(json.dumps({
    "healthy": healthy,
    "tmux_session": "$TMUX_SESSION",
    "tmux_status": "$TMUX_STATUS",
    "inbox": $INBOX_COUNT,
    "active": $ACTIVE_COUNT,
    "outbox": $OUTBOX_COUNT,
    "orphans": $ORPHAN_COUNT,
    "stale_results": $STALE_COUNT,
    "issues": $ISSUES,
    "problems": problems
}, indent=2))
PYEOF
else
  echo "Bridge Health Check"
  echo "==================="
  echo "Worker ($TMUX_SESSION): $TMUX_STATUS"
  echo "Inbox:   $INBOX_COUNT pending"
  echo "Active:  $ACTIVE_COUNT running"
  echo "Outbox:  $OUTBOX_COUNT ready"
  echo "Orphans: $ORPHAN_COUNT (tasks stuck >10min)"
  echo "Stale:   $STALE_COUNT (results uncollected >1hr)"
  echo ""
  if [ "$HEALTHY" = "true" ] && [ "$ISSUES" -eq 0 ]; then
    echo "Status: HEALTHY"
  elif [ "$HEALTHY" = "true" ]; then
    echo "Status: OK (${ISSUES} warning(s))"
    echo "$PROBLEMS"
  else
    echo "Status: UNHEALTHY (${ISSUES} issue(s))"
    echo "$PROBLEMS"
  fi
fi

if [ "$HEALTHY" = "false" ]; then
  exit 1
fi
exit 0
