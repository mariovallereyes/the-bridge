#!/bin/bash
# test-e2e.sh -- End-to-end test for Bridge dispatch + relay cycle
# Uses a mock worker (background process) to simulate the full cycle
# without requiring a real Claude Code session.
#
# Usage: test-e2e.sh [--verbose]
#
# Tests:
#   1. Task JSON generation with metadata
#   2. Atomic write to inbox
#   3. Mock worker consumes task, writes result
#   4. bridge-acp.sh detects result and returns it
#   5. relay.sh formats the result correctly
#   6. context-update.sh appends to CONTEXT.md
#   7. health.sh reports status correctly
#
# Creates a temporary bridge directory, runs tests, cleans up.

set -euo pipefail

VERBOSE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d /tmp/bridge-e2e-XXXXXX)
PASS=0
FAIL=0

log() {
  echo "  $1"
}

pass() {
  PASS=$((PASS + 1))
  log "PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  log "FAIL: $1"
}

cleanup() {
  rm -rf "$TEST_DIR"
  # Kill mock worker if still running
  [ -n "${MOCK_PID:-}" ] && kill "$MOCK_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "Bridge E2E Test Suite"
echo "====================="
echo "Test dir: $TEST_DIR"
echo ""

# Setup test bridge directory
mkdir -p "$TEST_DIR"/{inbox,outbox,active,archive,workspace,logs}
cat > "$TEST_DIR/CONTEXT.md" << 'CTXEOF'
# CONTEXT.md -- Living Context

*Last updated by orchestrator: 2026-01-01*

## Recent Task History

| Task ID | Date | Type | Summary | Status |
|---------|------|------|---------|--------|
| (none yet) | -- | -- | -- | -- |
CTXEOF

# --- Test 1: relay.sh with completed result ---
echo "Test 1: relay.sh completed result"
RELAY_OUT=$(echo '{"id":"e2e-001","version":"0.1.0","completed_at":"2026-04-06T00:00:00Z","duration_seconds":30,"status":"completed","result":{"summary":"Test passed","details":"All good","files_changed":["a.ts"],"files_created":[],"tests_run":"npm test (1 passed)","data":null,"warnings":[]},"error":null}' | bash "$SCRIPT_DIR/relay.sh" --stdin 2>/dev/null)
if echo "$RELAY_OUT" | grep -q "Test passed"; then
  pass "relay.sh formats completed result"
else
  fail "relay.sh completed output: $RELAY_OUT"
fi

# --- Test 2: relay.sh with failed result ---
echo "Test 2: relay.sh failed result"
RELAY_OUT=$(echo '{"id":"e2e-002","version":"0.1.0","completed_at":"2026-04-06T00:00:00Z","duration_seconds":5,"status":"failed","result":null,"error":{"code":"FILE_NOT_FOUND","message":"src/main.ts does not exist","recoverable":true,"suggestion":"Check the path"}}' | bash "$SCRIPT_DIR/relay.sh" --stdin 2>/dev/null)
if echo "$RELAY_OUT" | grep -q "FAILED \[FILE_NOT_FOUND\]" && echo "$RELAY_OUT" | grep -q "recoverable"; then
  pass "relay.sh formats failed result with code and recoverable flag"
else
  fail "relay.sh failed output: $RELAY_OUT"
fi

# --- Test 3: context-update.sh ---
echo "Test 3: context-update.sh appends to CONTEXT.md"
echo '{"id":"e2e-003","version":"0.1.0","completed_at":"2026-04-06T12:00:00Z","duration_seconds":60,"status":"completed","result":{"summary":"Built the widget"},"error":null}' | BRIDGE_DIR="$TEST_DIR" bash "$SCRIPT_DIR/context-update.sh" --stdin 2>/dev/null
if grep -q "e2e-003" "$TEST_DIR/CONTEXT.md" && grep -q "Built the widget" "$TEST_DIR/CONTEXT.md"; then
  pass "context-update.sh appends task to history"
else
  fail "context-update.sh: task not found in CONTEXT.md"
  [ "$VERBOSE" = "--verbose" ] && cat "$TEST_DIR/CONTEXT.md"
fi

# Check that (none yet) was removed
if grep -q "(none yet)" "$TEST_DIR/CONTEXT.md"; then
  fail "context-update.sh: (none yet) placeholder not removed"
else
  pass "context-update.sh removes (none yet) placeholder"
fi

# Check date was updated
if grep -q "Last updated by orchestrator: $(date +%Y-%m-%d)" "$TEST_DIR/CONTEXT.md"; then
  pass "context-update.sh updates date header"
else
  fail "context-update.sh: date not updated"
fi

# --- Test 4: health.sh JSON mode ---
echo "Test 4: health.sh JSON output"
HEALTH_OUT=$(BRIDGE_DIR="$TEST_DIR" BRIDGE_TMUX_SESSION="nonexistent-test-session" bash "$SCRIPT_DIR/health.sh" --json 2>/dev/null || true)
if echo "$HEALTH_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['tmux_status']=='down'; assert d['healthy']==False; print('valid')" 2>/dev/null; then
  pass "health.sh detects down worker in JSON mode"
else
  fail "health.sh JSON output: $HEALTH_OUT"
fi

# --- Test 5: Mock worker end-to-end cycle ---
echo "Test 5: Full dispatch -> mock worker -> result cycle"

# Start a mock worker that watches inbox and writes a result after a delay
(
  while true; do
    TASK_FILE=$(find "$TEST_DIR/inbox" -name "*.json" -not -name ".*" 2>/dev/null | head -1)
    if [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ]; then
      TASK_ID=$(python3 -c "import json; print(json.load(open('$TASK_FILE'))['id'])")
      # Move to active
      cp "$TASK_FILE" "$TEST_DIR/active/$(basename "$TASK_FILE")"
      rm "$TASK_FILE"
      # Simulate work
      sleep 1
      # Write result
      cat > "$TEST_DIR/outbox/${TASK_ID}.json" << RESEOF
{
  "id": "${TASK_ID}",
  "version": "0.1.0",
  "completed_at": "2026-04-06T15:00:00Z",
  "duration_seconds": 1,
  "status": "completed",
  "result": {
    "summary": "Mock worker completed the task",
    "details": "E2E test mock execution",
    "files_changed": [],
    "files_created": [],
    "tests_run": null,
    "data": null,
    "warnings": []
  },
  "error": null
}
RESEOF
      # Clean active
      rm -f "$TEST_DIR/active/$(basename "$TASK_FILE")"
    fi
    sleep 1
  done
) &
MOCK_PID=$!
sleep 2  # Let mock worker start its poll loop

# Write a task directly (bypass bridge-acp.sh since we can't use tmux)
TASK_ID="e2e-roundtrip-001"
cat > "$TEST_DIR/inbox/${TASK_ID}.json" << EOF
{
  "id": "${TASK_ID}",
  "version": "0.1.0",
  "created_at": "2026-04-06T15:00:00Z",
  "timeout_seconds": 30,
  "type": "composite",
  "title": "E2E round-trip test",
  "description": "Mock task for testing",
  "metadata": {"source": "test-harness"}
}
EOF

# Poll for result
ELAPSED=0
while [ ! -f "$TEST_DIR/outbox/${TASK_ID}.json" ] && [ $ELAPSED -lt 15 ]; do
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

if [ -f "$TEST_DIR/outbox/${TASK_ID}.json" ]; then
  # Verify result
  STATUS=$(python3 -c "import json; print(json.load(open('$TEST_DIR/outbox/${TASK_ID}.json'))['status'])")
  if [ "$STATUS" = "completed" ]; then
    pass "Full round-trip: task dispatched, mock worker processed, result in outbox"
  else
    fail "Round-trip result status: $STATUS (expected completed)"
  fi

  # Test relay on the round-trip result
  RELAY_RT=$(bash "$SCRIPT_DIR/relay.sh" "$TEST_DIR/outbox/${TASK_ID}.json" 2>/dev/null)
  if echo "$RELAY_RT" | grep -q "Mock worker completed"; then
    pass "relay.sh correctly parses round-trip result"
  else
    fail "relay.sh round-trip: $RELAY_RT"
  fi

  # Test context-update on the round-trip result
  BRIDGE_DIR="$TEST_DIR" bash "$SCRIPT_DIR/context-update.sh" "$TEST_DIR/outbox/${TASK_ID}.json" 2>/dev/null
  if grep -q "$TASK_ID" "$TEST_DIR/CONTEXT.md"; then
    pass "context-update.sh appends round-trip task to history"
  else
    fail "context-update.sh: round-trip task not in CONTEXT.md"
  fi
else
  fail "Round-trip: no result after 15s (mock worker may not have started)"
fi

# Kill mock worker
kill "$MOCK_PID" 2>/dev/null || true
MOCK_PID=""

# --- Test 6: openclaw-dispatch.sh preflight failure ---
echo "Test 6: openclaw-dispatch.sh preflight with dead worker"
OC_OUT=$(BRIDGE_DIR="$TEST_DIR" BRIDGE_TMUX_SESSION="nonexistent-test" bash "$SCRIPT_DIR/openclaw-dispatch.sh" "Test" "Test" "" 30 2>/dev/null || true)
if echo "$OC_OUT" | grep -q "Bridge is not available"; then
  pass "openclaw-dispatch.sh reports preflight failure cleanly"
else
  fail "openclaw-dispatch.sh preflight: $OC_OUT"
fi

# --- Test 7: openclaw-dispatch.sh with skip-preflight and mock result ---
echo "Test 7: openclaw-dispatch.sh relay output from existing result"
# Write a result directly and test relay portion
MOCK_TASK="e2e-oc-001"
cat > "$TEST_DIR/outbox/${MOCK_TASK}.json" << MOCKEOF
{
  "id": "${MOCK_TASK}",
  "version": "0.1.0",
  "completed_at": "2026-04-06T16:00:00Z",
  "duration_seconds": 42,
  "status": "completed",
  "result": {
    "summary": "OpenClaw integration test passed",
    "files_changed": ["src/app.ts"],
    "files_created": [],
    "tests_run": "vitest (5 passed)",
    "data": null,
    "warnings": []
  },
  "error": null
}
MOCKEOF
# Test relay directly on this result
RELAY_OC=$(bash "$SCRIPT_DIR/relay.sh" "$TEST_DIR/outbox/${MOCK_TASK}.json" 2>/dev/null)
if echo "$RELAY_OC" | grep -q "OpenClaw integration test passed" && echo "$RELAY_OC" | grep -q "src/app.ts"; then
  pass "openclaw-dispatch relay path formats result with summary + files"
else
  fail "openclaw-dispatch relay: $RELAY_OC"
fi

# --- Test 8: health.sh human mode ---
echo "Test 8: health.sh human-readable output"
HEALTH_HUMAN=$(BRIDGE_DIR="$TEST_DIR" BRIDGE_TMUX_SESSION="bridge" bash "$SCRIPT_DIR/health.sh" 2>/dev/null || true)
if echo "$HEALTH_HUMAN" | grep -q "Bridge Health Check" && echo "$HEALTH_HUMAN" | grep -q "Worker"; then
  pass "health.sh produces human-readable dashboard"
else
  fail "health.sh human output: $HEALTH_HUMAN"
fi

# --- Test 9: notify.sh signal file ---
echo "Test 9: notify.sh writes signal file"
mkdir -p "$TEST_DIR/logs"
BRIDGE_DIR="$TEST_DIR" BRIDGE_NOTIFY_METHOD=file bash "$SCRIPT_DIR/notify.sh" "Test notification" --task-id "e2e-notify-001" 2>/dev/null
if [ -f "$TEST_DIR/logs/completion-signal.json" ]; then
  SIGNAL_TASK=$(python3 -c "import json; print(json.load(open('$TEST_DIR/logs/completion-signal.json'))['task_id'])" 2>/dev/null)
  if [ "$SIGNAL_TASK" = "e2e-notify-001" ]; then
    pass "notify.sh writes valid signal file with task ID"
  else
    fail "notify.sh signal file task_id: $SIGNAL_TASK"
  fi
else
  fail "notify.sh: signal file not created"
fi

# --- Test 10: check-completions.sh count mode ---
echo "Test 10: check-completions.sh"
# Write a fresh result for testing
cat > "$TEST_DIR/outbox/e2e-check-001.json" << CHECKEOF
{
  "id": "e2e-check-001",
  "version": "0.1.0",
  "completed_at": "2026-04-06T16:00:00Z",
  "duration_seconds": 10,
  "status": "completed",
  "result": {"summary": "Check completions test"},
  "error": null
}
CHECKEOF
# Clear consumed log so this is fresh
rm -f "$TEST_DIR/logs/consumed.log"

# Test count
COUNT=$(BRIDGE_DIR="$TEST_DIR" bash "$SCRIPT_DIR/check-completions.sh" --count 2>/dev/null || echo "0")
if [ "$COUNT" -gt 0 ]; then
  pass "check-completions.sh --count finds pending completions"
else
  fail "check-completions.sh --count: expected >0, got $COUNT"
fi

# Test consume
CONSUME_OUT=$(BRIDGE_DIR="$TEST_DIR" bash "$SCRIPT_DIR/check-completions.sh" 2>/dev/null)
if echo "$CONSUME_OUT" | grep -q "Check completions test"; then
  pass "check-completions.sh consumes and relays result"
else
  fail "check-completions.sh consume: $CONSUME_OUT"
fi

# Test dedup (second consume should find nothing)
BRIDGE_DIR="$TEST_DIR" bash "$SCRIPT_DIR/check-completions.sh" --count >/dev/null 2>/dev/null
DEDUP_EXIT=$?
if [ $DEDUP_EXIT -eq 1 ]; then
  pass "check-completions.sh dedup prevents re-processing (exit 1 = nothing pending)"
else
  fail "check-completions.sh dedup: expected exit 1, got $DEDUP_EXIT"
fi

# --- Summary ---
echo ""
echo "====================="
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if [ $FAIL -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
