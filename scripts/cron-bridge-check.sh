#!/bin/bash
# cron-bridge-check.sh -- Lightweight cron-compatible Bridge completion check
#
# Checks for unconsumed Bridge completions. If any found, fires a system
# event to wake the orchestrator agent. Zero cost when nothing is pending.
#
# Designed for OpenClaw cron: runs every 2-5 minutes, silent when idle.
#
# Usage: cron-bridge-check.sh
#
# Environment:
#   BRIDGE_DIR - Bridge directory (default: ~/.the-bridge)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.the-bridge}"

# Quick count check (no model tokens, just filesystem)
COUNT=$("$SCRIPT_DIR/check-completions.sh" --count 2>/dev/null | tr -d '[:space:]')
COUNT="${COUNT:-0}"

if [ "$COUNT" -gt 0 ] 2>/dev/null; then
  # Consume and format the completions
  RELAY_OUTPUT=$("$SCRIPT_DIR/check-completions.sh" 2>/dev/null || echo "")

  if [ -n "$RELAY_OUTPUT" ]; then
    # Fire system event with the relay output
    openclaw system event \
      --text "Bridge completion: $RELAY_OUTPUT" \
      --mode now \
      --timeout 10000 2>/dev/null || true
  fi
fi

# Exit silently when nothing pending (zero cost)
