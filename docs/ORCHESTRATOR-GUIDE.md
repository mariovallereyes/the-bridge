# Orchestrator Guide — The Bridge

**Version:** 0.1.0-draft
**Status:** Design Phase

---

## 1. Overview

This guide is for the **orchestrator** — the AI agent that dispatches tasks to a Bridge worker and processes results. The orchestrator can be any system: OpenClaw, LangChain, a custom Python script, a shell script, or even a human.

---

## 2. Prerequisites

Before dispatching tasks, ensure:

1. ✅ Bridge directory exists with correct structure (`inbox/`, `outbox/`, `active/`, `archive/`)
2. ✅ `CLAUDE.md` is in the bridge directory
3. ✅ tmux session is running with the worker agent active
4. ✅ Worker has been tested with a manual task (see [Agent Contract](AGENT-CONTRACT.md) §6)

---

## 3. Quick Dispatch (One Command)

The `scripts/bridge.sh` script handles the full dispatch-and-poll cycle in a single command:

```bash
./scripts/bridge.sh "Task title" "Detailed description of what to do" ~/Projects/target 300
```

Arguments:
1. **Title** (required) - short summary
2. **Description** (required) - detailed instructions
3. **Working directory** (optional) - where the worker should operate
4. **Timeout** (optional, default 300s) - max seconds to wait

It generates a task ID, writes the JSON atomically to `inbox/`, sends the tmux trigger, polls `outbox/` with backoff, and prints the result JSON to stdout. Exit code 0 on success, 1 on timeout.

This is the recommended starting point for simple orchestrators. For more control, see `bridge-acp.sh` and the detailed dispatch flow below.

### 3.1 ACP-Aware Dispatch (bridge-acp.sh)

For orchestrators that need session tracking, metadata, and formatted result relay, use `bridge-acp.sh`:

```bash
# Basic usage (same as bridge.sh)
./scripts/bridge-acp.sh "Fix the login bug" "The form doesn't submit on click" ~/Projects/my-app 300

# With metadata via environment variables
BRIDGE_AGENT=patti \
BRIDGE_SESSION_KEY="agent:main:whatsapp:direct:+1234567890" \
BRIDGE_TASK_TYPE=code \
BRIDGE_BACKGROUND="Users reported this after the last deploy" \
BRIDGE_CONSTRAINTS='["Do not change the API response format", "Run tests after fixing"]' \
BRIDGE_CONTEXT_FILES='["src/components/LoginForm.tsx"]' \
  ./scripts/bridge-acp.sh "Fix login form" "The onClick handler seems stale" ~/Projects/my-app 300

# Get human-readable output instead of raw JSON
BRIDGE_OUTPUT_MODE=relay \
  ./scripts/bridge-acp.sh "Analyze the codebase" "Find unused exports" ~/Projects/my-app 300
```

**Environment variables:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `BRIDGE_DIR` | `~/.the-bridge` | Bridge directory |
| `BRIDGE_TMUX_SESSION` | `bridge` | tmux session name |
| `BRIDGE_AGENT` | `openclaw` | Dispatching agent name |
| `BRIDGE_SESSION_KEY` | (empty) | Session identifier for result relay routing |
| `BRIDGE_TASK_TYPE` | `composite` | Task type: `code`, `research`, `analysis`, `file`, `command`, `composite` |
| `BRIDGE_CONSTRAINTS` | (empty) | JSON array of constraint strings |
| `BRIDGE_CONTEXT_FILES` | (empty) | JSON array of file paths for the worker to read first |
| `BRIDGE_BACKGROUND` | (empty) | Background context string |
| `BRIDGE_OUTPUT_MODE` | `json` | `json` (raw result) or `relay` (human-readable summary) |

The `metadata` block in the task JSON carries session identity so the orchestrator can route the result back to the correct conversation. See [Protocol 3.3](PROTOCOL.md) for the metadata spec.

### 3.2 Parsing Results with relay.sh

`relay.sh` formats Bridge result JSON into a human-readable summary:

```bash
# From a file
./scripts/relay.sh outbox/task-001.json

# From stdin (e.g., piped from bridge-acp.sh)
./scripts/bridge-acp.sh "Task" "Description" | ./scripts/relay.sh --stdin

# Example output for a completed task:
#   Fixed email regex to allow '+' in local part
#   Files: src/utils/validate.ts
#   Tests: npm test -- validate (3 passed, 0 failed)

# Example output for a failed task:
#   FAILED [DEPENDENCY_MISSING]: zod is not installed
#   Suggestion: Install zod and resubmit the task
#   (recoverable)
```

Task ID and duration are printed on stderr for logging:
```
[task-20260406-042 | 135s | completed]
```

---

## 4. Maintaining Context

### 3.1 Update CONTEXT.md Between Tasks

The orchestrator is responsible for keeping `CONTEXT.md` current. This gives the worker persistent awareness without memory.

**When to update:**
- After each completed task → add to Recent Task History
- When project status changes → update Active Projects
- When standing instructions change → update that section
- Before a task that requires new context the worker hasn't seen

**How to update:**
```bash
# Read the current CONTEXT.md, modify the relevant section, write it back
# Or use a script to append to the Recent Task History table

# Example: append a task to history
cat >> "${BRIDGE_DIR}/CONTEXT.md" << EOF
| ${TASK_ID} | $(date +%Y-%m-%d) | ${SUMMARY} | ✅ |
EOF
```

**What NOT to put in CONTEXT.md:**
- Credentials, tokens, API keys
- Data that changes mid-task (use task JSON for that)
- Protocol rules (that's CLAUDE.md's job)

→ Full CONTEXT.md spec: [Protocol §3](PROTOCOL.md#3-context-file-format)

---

## 5. Dispatching a Task (Detailed)

### 4.1 Step-by-Step

```bash
# 1. Generate a unique task ID
TASK_ID="task-$(date +%Y%m%d)-$(printf '%03d' $RANDOM)"

# 2. Write the task JSON to inbox/
cat > "${BRIDGE_DIR}/inbox/${TASK_ID}.json" << 'EOF'
{
  "id": "TASK_ID_HERE",
  "version": "0.1.0",
  "created_at": "2025-07-03T15:30:00Z",
  "type": "code",
  "title": "Your task title",
  "description": "Detailed description of what to do",
  "working_directory": "~/Projects/target-project"
}
EOF

# 3. Trigger the worker
tmux send-keys -t bridge "check inbox" Enter

# 4. Poll for result
while [ ! -f "${BRIDGE_DIR}/outbox/${TASK_ID}.json" ]; do
  sleep 3
done

# 5. Read result
cat "${BRIDGE_DIR}/outbox/${TASK_ID}.json"
```

### 3.2 Atomic File Writes

**Critical:** Write task files atomically to prevent the worker from reading partial JSON.

```bash
# WRONG — worker might read partial file
echo '{"id": "task-001"...' > inbox/task-001.json

# RIGHT — write to temp, then atomic move
echo '{"id": "task-001"...' > inbox/.task-001.json.tmp
mv inbox/.task-001.json.tmp inbox/task-001.json
```

Convention: Files starting with `.` are ignored by the worker. Use `.filename.tmp` for writes-in-progress.

---

## 6. Reading Results

### 4.1 Polling Strategy

```python
import time
import json
import os

def wait_for_result(bridge_dir, task_id, timeout=300):
    """Poll outbox for task result with exponential backoff."""
    result_path = f"{bridge_dir}/outbox/{task_id}.json"
    start = time.time()
    interval = 3  # Start at 3 seconds
    
    while time.time() - start < timeout:
        if os.path.exists(result_path):
            with open(result_path) as f:
                return json.load(f)
        time.sleep(interval)
        if interval < 10:
            interval += 1  # Gradually slow down
    
    return {"status": "timeout", "id": task_id}
```

### 4.2 Processing Results

```python
result = wait_for_result(bridge_dir, task_id)

if result["status"] == "completed":
    # Task succeeded
    summary = result["result"]["summary"]
    files = result["result"].get("files_changed", [])
    # Act on the result...

elif result["status"] == "failed":
    error = result["error"]
    if error.get("recoverable"):
        # Modify task and retry
        retry_task(task, error["suggestion"])
    else:
        # Report failure
        report_error(error["message"])

elif result["status"] == "partial":
    # Some work done, some not
    # Check result.warnings for what didn't work

elif result["status"] == "timeout":
    # Worker didn't finish in time
    # Check active/ for orphaned task
    handle_timeout(task_id)
```

### 4.3 Archiving

After processing a result, move both the request and result to `archive/`:

```bash
DATE=$(date +%Y-%m-%d)
mkdir -p "${BRIDGE_DIR}/archive/${DATE}"

# The original task (if you kept a copy)
cp "${BRIDGE_DIR}/outbox/${TASK_ID}.json" "${BRIDGE_DIR}/archive/${DATE}/${TASK_ID}.result.json"

# Clean outbox
rm "${BRIDGE_DIR}/outbox/${TASK_ID}.json"
```

---

## 7. tmux Interaction

### 5.1 Session Management

```bash
# Check if bridge session exists
tmux has-session -t bridge 2>/dev/null && echo "Running" || echo "Not running"

# Create session (if not exists)
tmux new-session -d -s bridge -c "${BRIDGE_DIR}"

# Attach to session (for debugging)
tmux attach -t bridge

# Kill session (emergency)
tmux kill-session -t bridge
```

### 5.2 Sending Commands

```bash
# Trigger task processing
tmux send-keys -t bridge "check inbox" Enter

# Check worker status
tmux send-keys -t bridge "status" Enter

# Cancel current task
tmux send-keys -t bridge "cancel" Enter
```

### 5.3 Reading Worker Output

```bash
# Capture last 50 lines of the pane
tmux capture-pane -t bridge -p -S -50

# Capture and save to file
tmux capture-pane -t bridge -p -S -100 > /tmp/bridge-output.txt

# Check if worker said "Task X complete"
tmux capture-pane -t bridge -p -S -10 | grep "complete"
```

### 5.4 Multi-Pane Setup

For monitoring, split the tmux session:

```bash
# Worker in pane 0 (main)
# Monitoring in pane 1
tmux split-window -t bridge -h
tmux send-keys -t bridge:0.1 "watch -n 2 'ls -la inbox/ active/ outbox/'" Enter
```

---

## 8. Task Design Best Practices

### 6.1 Write Clear Descriptions

The worker is an AI. It follows instructions literally. Be specific:

```json
// BAD — vague
{
  "description": "Fix the bug"
}

// GOOD — specific
{
  "description": "The /api/users endpoint returns 500 when the email field contains a '+' character (e.g., user+tag@example.com). Fix the email validation regex in src/utils/validate.ts to allow '+' in the local part."
}
```

### 6.2 Provide Context

```json
{
  "context": {
    "files": ["src/utils/validate.ts", "src/api/users.ts"],
    "background": "This broke after commit abc123 which added email validation",
    "constraints": [
      "Don't change the API response format",
      "Keep backward compatibility with existing stored emails",
      "Run the existing test suite after fixing"
    ]
  }
}
```

### 6.3 Define Success

```json
{
  "expected_output": {
    "type": "code_change",
    "success_criteria": "POST /api/users with email 'test+1@example.com' returns 201, not 500. Existing tests still pass."
  }
}
```

### 6.4 Set Appropriate Timeouts

| Task Type | Suggested Timeout |
|-----------|------------------|
| Simple code fix | 120s (2 min) |
| Feature implementation | 600s (10 min) |
| Code review | 300s (5 min) |
| Research question | 300s (5 min) |
| Complex refactor | 1200s (20 min) |
| File creation | 60s (1 min) |

### 6.5 Use Task Types Correctly

| Type | When to Use |
|------|------------|
| `code` | Any task that modifies source code |
| `review` | Read-only analysis, code review, PR review |
| `research` | Investigating a question, reading docs, finding solutions |
| `analysis` | Data analysis, codebase analysis, dependency audit |
| `file` | Creating documents, configs, non-code files |
| `command` | Run a command and report the output |
| `composite` | Multiple related sub-tasks in sequence |

---

## 9. Error Recovery

### 7.1 Retry Logic

```python
MAX_RETRIES = 2

def dispatch_with_retry(task, bridge_dir, tmux_session):
    for attempt in range(MAX_RETRIES + 1):
        result = dispatch_and_wait(task, bridge_dir, tmux_session)
        
        if result["status"] == "completed":
            return result
        
        if result["status"] == "failed":
            if not result["error"].get("recoverable", False):
                return result  # Can't retry
            
            # Apply suggestion and retry
            task["description"] += f"\n\nPrevious attempt failed: {result['error']['message']}"
            task["description"] += f"\nSuggestion: {result['error']['suggestion']}"
            task["id"] = f"{task['id']}-retry{attempt + 1}"
            continue
        
        if result["status"] == "timeout":
            # Increase timeout and retry
            task["timeout_seconds"] = task.get("timeout_seconds", 300) * 2
            task["id"] = f"{task['id']}-retry{attempt + 1}"
            continue
    
    return {"status": "failed", "error": {"message": f"Failed after {MAX_RETRIES} retries"}}
```

### 7.2 Orphan Detection

Check for tasks stuck in `active/` (worker crashed mid-task):

```bash
# Find tasks in active/ older than 10 minutes
find "${BRIDGE_DIR}/active" -name "*.json" -mmin +10

# Recovery: move back to inbox for retry
for f in $(find "${BRIDGE_DIR}/active" -name "*.json" -mmin +10); do
  mv "$f" "${BRIDGE_DIR}/inbox/"
done
```

### 7.3 Worker Health Check

```bash
# Send status command and check response
tmux send-keys -t bridge "status" Enter
sleep 3
STATUS=$(tmux capture-pane -t bridge -p -S -5)

if echo "$STATUS" | grep -q "idle\|working\|No tasks"; then
  echo "Worker healthy"
else
  echo "Worker may be stuck or crashed"
fi
```

---

## 10. OpenClaw Integration

For OpenClaw users, The Bridge can be wrapped as a skill:

```markdown
# SKILL.md — the-bridge

## Trigger
Use when delegating coding, research, or analysis tasks to a local Claude Code worker.

## Usage
1. Write task JSON to bridge inbox
2. Send tmux trigger
3. Poll for result
4. Return result to user

## Configuration
- BRIDGE_DIR: ~/.the-bridge
- TMUX_SESSION: bridge
- DEFAULT_TIMEOUT: 300
```

A full OpenClaw skill implementation is planned for Phase 2.

---

## 11. Monitoring Dashboard (Optional)

A simple watch command provides a live dashboard:

```bash
watch -n 2 '
echo "=== THE BRIDGE ==="
echo ""
echo "INBOX (pending):"
ls -1 inbox/ 2>/dev/null || echo "  (empty)"
echo ""
echo "ACTIVE (running):"
ls -1 active/ 2>/dev/null || echo "  (none)"
echo ""
echo "OUTBOX (completed):"
ls -1 outbox/ 2>/dev/null || echo "  (empty)"
echo ""
echo "ARCHIVE (total):"
find archive/ -name "*.json" 2>/dev/null | wc -l | xargs echo "  files"
'
```

---

*The orchestrator is the brain. The worker is the hands. The filesystem is the nervous system.*
