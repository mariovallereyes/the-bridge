#!/bin/bash
# status.sh — Bridge status dashboard
# Usage: ./status.sh

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"
TMUX_SESSION="${BRIDGE_TMUX_SESSION:-bridge}"

echo "═══════════════════════════════"
echo "   THE BRIDGE — Status"
echo "═══════════════════════════════"
echo ""

# tmux session
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "🟢 Worker session: RUNNING ($TMUX_SESSION)"
else
  echo "🔴 Worker session: DOWN ($TMUX_SESSION)"
fi
echo ""

# Inbox
INBOX_COUNT=$(find "$BRIDGE_DIR/inbox" -name "*.json" -not -name ".*" 2>/dev/null | wc -l | tr -d ' ')
echo "📥 Inbox (pending):  $INBOX_COUNT"
if [[ $INBOX_COUNT -gt 0 ]]; then
  for f in "$BRIDGE_DIR/inbox/"*.json; do
    [[ -f "$f" ]] || continue
    echo "   └─ $(basename "$f")"
  done
fi

# Active
ACTIVE_COUNT=$(find "$BRIDGE_DIR/active" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
echo "⚙️  Active (running): $ACTIVE_COUNT"
if [[ $ACTIVE_COUNT -gt 0 ]]; then
  for f in "$BRIDGE_DIR/active/"*.json; do
    [[ -f "$f" ]] || continue
    echo "   └─ $(basename "$f")"
  done
fi

# Outbox
OUTBOX_COUNT=$(find "$BRIDGE_DIR/outbox" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
echo "📤 Outbox (done):    $OUTBOX_COUNT"
if [[ $OUTBOX_COUNT -gt 0 ]]; then
  for f in "$BRIDGE_DIR/outbox/"*.json; do
    [[ -f "$f" ]] || continue
    echo "   └─ $(basename "$f")"
  done
fi

# Archive
ARCHIVE_COUNT=$(find "$BRIDGE_DIR/archive" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
echo "📦 Archive (total):  $ARCHIVE_COUNT"

echo ""
echo "═══════════════════════════════"
