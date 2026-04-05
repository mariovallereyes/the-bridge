# Setup Guide — The Bridge

**Version:** 0.1.0-draft
**Status:** Design Phase

---

## 1. Requirements

| Requirement | Details |
|------------|---------|
| **Operating System** | macOS, Linux, or WSL on Windows |
| **tmux** | Any recent version (3.0+) |
| **Worker AI Tool** | Claude Code, Cursor, or any terminal-based AI that reads project instructions |
| **Orchestrator** | Any AI agent platform, script, or manual operation |
| **Subscription** | Active subscription to the worker AI tool |

That's it. No servers. No databases. No packages to install.

---

## 2. Installation

### 2.1 Install tmux (if needed)

```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt install tmux

# Arch
sudo pacman -S tmux
```

### 2.2 Create the Bridge Directory

```bash
# Choose a location (examples)
BRIDGE_DIR="$HOME/.the-bridge"          # Global
# BRIDGE_DIR="$HOME/bridges/claude"     # Named per worker
# BRIDGE_DIR="$HOME/Projects/app/.bridge" # Project-specific

# Create structure
mkdir -p "$BRIDGE_DIR"/{inbox,outbox,active,archive,workspace,logs}
```

### 2.3 Install the Worker Contract

Copy the reference `CLAUDE.md` into the bridge directory:

```bash
# If you have the-bridge repo cloned:
cp the-bridge/templates/CLAUDE.md "$BRIDGE_DIR/CLAUDE.md"

# Or create it manually — see docs/AGENT-CONTRACT.md for the full template
```

**Important:** Read [Agent Contract](AGENT-CONTRACT.md) and customize the contract for your use case before proceeding.

### 2.4 Create the Context File

Create `CONTEXT.md` to give the worker persistent awareness:

```bash
cat > "$BRIDGE_DIR/CONTEXT.md" << 'EOF'
# CONTEXT.md — Living Context

*Last updated by orchestrator: YYYY-MM-DD*

## Dispatcher
- **Agent:** Your AI assistant name
- **On behalf of:** Your name
- **Timezone:** Your/Timezone

## Active Projects
| Project | Path | Stack | Status |
|---------|------|-------|--------|
| My App  | ~/Projects/my-app | Next.js, TypeScript | Active |

## Coding Preferences
- Your coding style rules here
- Commit message format
- Testing expectations

## Standing Instructions
- Any rules that apply to ALL tasks

## Recent Task History
| Task ID | Date | Summary | Status |
|---------|------|---------|--------|
EOF
```

The orchestrator updates this file between task cycles. See [Protocol §3](PROTOCOL.md) for the full spec.

### 2.5 Verify the Structure

```bash
ls -la "$BRIDGE_DIR"
# Should show:
# CLAUDE.md
# CONTEXT.md
# inbox/
# outbox/
# active/
# archive/
# workspace/
# logs/
```

---

## 3. Starting the Worker

### 3.1 Create a tmux Session

```bash
# Start a new detached tmux session named "bridge"
tmux new-session -d -s bridge -c "$BRIDGE_DIR"
```

### 3.2 Launch Claude Code in the Session

```bash
# Attach to the session
tmux attach -t bridge

# Inside the session, start Claude Code with permissions bypass
claude --dangerously-skip-permissions

# Claude Code will read CLAUDE.md automatically
```

**Why `--dangerously-skip-permissions`?**

Without this flag, Claude Code asks for confirmation before file operations. Since the Bridge protocol requires the worker to move files between directories and write results, permission prompts would block automation. This flag is safe in this context because:
- You control the task input (you write the inbox files)
- The worker operates on your local machine with your user permissions
- The CLAUDE.md contract constrains what the worker does

### 3.3 Verify Worker Is Ready

Inside the Claude Code session, you should see it acknowledge the `CLAUDE.md`. Test it:

```
You: check inbox
Claude Code: No tasks pending.
```

If it doesn't recognize the command, refine your `CLAUDE.md` wording and try again.

### 3.4 Detach from tmux

```bash
# Press Ctrl+B, then D to detach
# The session continues running in the background
```

---

## 4. Testing

### 4.1 Quick Test with bridge.sh

The fastest way to test your setup:

```bash
./scripts/bridge.sh "Ping test" "Create a file workspace/hello.txt containing 'Bridge works!'" "$BRIDGE_DIR" 60
```

This dispatches a task, triggers the worker, waits for the result, and prints it. If you see a JSON result with `"status": "completed"`, your bridge is working.

### 4.2 Manual Test

Open a new terminal (NOT the tmux session):

```bash
# Write a test task
cat > "$BRIDGE_DIR/inbox/test-001.json" << 'EOF'
{
  "id": "test-001",
  "version": "0.1.0",
  "created_at": "2025-07-03T00:00:00Z",
  "type": "command",
  "title": "Echo test",
  "description": "Create a file called workspace/hello.txt containing exactly: Bridge works!",
  "expected_output": {
    "type": "file",
    "success_criteria": "workspace/hello.txt exists with content 'Bridge works!'"
  }
}
EOF

# Trigger the worker
tmux send-keys -t bridge "check inbox" Enter

# Wait and check
sleep 15
cat "$BRIDGE_DIR/outbox/test-001.json"
```

### 4.3 Expected Result

```json
{
  "id": "test-001",
  "version": "0.1.0",
  "completed_at": "2025-07-03T00:00:15Z",
  "duration_seconds": 12,
  "status": "completed",
  "result": {
    "summary": "Created workspace/hello.txt with content 'Bridge works!'",
    "files_created": ["workspace/hello.txt"]
  },
  "error": null
}
```

### 4.4 Verification Checklist

- [ ] Task file gone from `inbox/`
- [ ] Task file NOT in `active/` (was cleaned up)
- [ ] Result file in `outbox/`
- [ ] Result JSON is valid and machine-readable
- [ ] `workspace/hello.txt` exists with correct content
- [ ] Worker terminal shows task completion

If any check fails, review your `CLAUDE.md` — the issue is almost always in the contract wording.

---

## 5. Connecting an Orchestrator

### 5.1 OpenClaw

If you use OpenClaw, install The Bridge skill:

```bash
# (Phase 2 — skill not yet published)
clawhub install the-bridge
```

Or point your existing agent to use the bridge directory and tmux session.

### 5.2 Shell Script Orchestrator

Minimal orchestrator in bash:

```bash
#!/bin/bash
# dispatch.sh — Send a task to The Bridge
BRIDGE_DIR="$HOME/.the-bridge"
TASK_ID="task-$(date +%Y%m%d)-$(printf '%03d' $((RANDOM % 1000)))"

# Create task file (atomic write)
cat > "$BRIDGE_DIR/inbox/.${TASK_ID}.json.tmp" << EOF
{
  "id": "${TASK_ID}",
  "version": "0.1.0",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "type": "${1:-code}",
  "title": "${2:-Untitled task}",
  "description": "${3:-No description provided}",
  "working_directory": "${4:-}",
  "timeout_seconds": ${5:-300}
}
EOF
mv "$BRIDGE_DIR/inbox/.${TASK_ID}.json.tmp" "$BRIDGE_DIR/inbox/${TASK_ID}.json"

# Trigger worker
tmux send-keys -t bridge "check inbox" Enter

# Wait for result
echo "Task ${TASK_ID} dispatched. Waiting..."
TIMEOUT=${5:-300}
ELAPSED=0
while [ ! -f "$BRIDGE_DIR/outbox/${TASK_ID}.json" ] && [ $ELAPSED -lt $TIMEOUT ]; do
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

if [ -f "$BRIDGE_DIR/outbox/${TASK_ID}.json" ]; then
  echo "=== RESULT ==="
  cat "$BRIDGE_DIR/outbox/${TASK_ID}.json"
else
  echo "TIMEOUT: No result after ${TIMEOUT}s"
fi
```

Usage:
```bash
./dispatch.sh code "Fix the login bug" "The login form doesn't submit..." ~/Projects/my-app 120
```

### 5.3 Python Orchestrator

See [Orchestrator Guide](ORCHESTRATOR-GUIDE.md) for Python examples with polling, retry logic, and error handling.

### 5.4 AI Agent Integration

For any AI agent platform, you need three capabilities:
1. **Write files** — to create task JSON in `inbox/`
2. **Run shell commands** — to send tmux keystrokes and poll `outbox/`
3. **Read files** — to process results from `outbox/`

Most AI agent platforms (OpenClaw, LangChain, AutoGPT, CrewAI) have all three.

---

## 6. Configuration

### 6.1 Environment Variables (Optional)

Add to your shell profile (`~/.bashrc`, `~/.zshrc`):

```bash
export BRIDGE_DIR="$HOME/.the-bridge"
export BRIDGE_TMUX_SESSION="bridge"
export BRIDGE_DEFAULT_TIMEOUT=300
```

### 6.2 Multiple Bridges

For multiple workers, use named bridges:

```bash
# Create bridges
mkdir -p ~/bridges/claude/{inbox,outbox,active,archive,workspace,logs}
mkdir -p ~/bridges/cursor/{inbox,outbox,active,archive,workspace,logs}

# Start workers in named sessions
tmux new-session -d -s bridge-claude -c ~/bridges/claude
tmux new-session -d -s bridge-cursor -c ~/bridges/cursor

# Dispatch to specific bridge
tmux send-keys -t bridge-claude "check inbox" Enter
tmux send-keys -t bridge-cursor "check inbox" Enter
```

### 6.3 Auto-Start on Login (macOS)

Create a Launch Agent to start the tmux session automatically:

```xml
<!-- ~/Library/LaunchAgents/com.the-bridge.tmux.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.the-bridge.tmux</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/tmux</string>
        <string>new-session</string>
        <string>-d</string>
        <string>-s</string>
        <string>bridge</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.the-bridge.tmux.plist
```

**Note:** This only creates the tmux session. You still need to manually start Claude Code inside it (once). Claude Code stays alive as long as the tmux session persists.

### 6.4 Auto-Start on Boot (Linux)

```bash
# Add to crontab
crontab -e

# Add this line:
@reboot /usr/bin/tmux new-session -d -s bridge -c $HOME/.the-bridge
```

---

## 7. Troubleshooting

### Worker doesn't recognize "check inbox"

**Cause:** `CLAUDE.md` wording isn't being followed.
**Fix:** Refine the trigger section. Try being more explicit. Add "IMPORTANT:" prefix. Include an example interaction.

### Result JSON is malformed

**Cause:** Worker generated non-standard JSON.
**Fix:** Add more explicit JSON examples in `CLAUDE.md`. Show exact field names. Add "CRITICAL: The result MUST be valid JSON."

### Task stays in inbox forever

**Cause:** Worker isn't processing the trigger.
**Fix:**
1. Attach to tmux: `tmux attach -t bridge`
2. Check if Claude Code is still running
3. Type "check inbox" manually — does it work?
4. If not, restart Claude Code and test again

### Worker modifies bridge infrastructure

**Cause:** `CLAUDE.md` rules aren't clear enough.
**Fix:** Add explicit rules: "NEVER modify CLAUDE.md. NEVER create or delete directories. ONLY touch files inside inbox/, active/, outbox/, and workspace/."

### tmux session not found

**Cause:** Session was never created or machine restarted.
**Fix:** `tmux new-session -d -s bridge -c ~/.the-bridge`

### Worker asks for permission (stuck on Y/N)

**Cause:** Claude Code wasn't started with `--dangerously-skip-permissions`.
**Fix:** Restart Claude Code with the flag. Or if using `claude` CLI, add to CLAUDE.md: "Always proceed without asking for confirmation."

---

## 8. Maintenance

### 8.1 Cleaning Old Archives

```bash
# Delete archives older than 30 days
find "$BRIDGE_DIR/archive" -type f -mtime +30 -delete
find "$BRIDGE_DIR/archive" -type d -empty -delete
```

### 8.2 Monitoring Disk Usage

```bash
du -sh "$BRIDGE_DIR"/{inbox,outbox,active,archive,workspace,logs}
```

### 8.3 Log Rotation

If the worker writes to `logs/`, rotate periodically:

```bash
# Keep last 7 days of logs
find "$BRIDGE_DIR/logs" -type f -mtime +7 -delete
```

### 8.4 Worker Session Health

Add to cron for regular health checks:

```bash
# Every 5 minutes, check if bridge session exists
*/5 * * * * tmux has-session -t bridge 2>/dev/null || echo "Bridge session down" | mail -s "Bridge Alert" you@email.com
```

---

*Setup takes 10 minutes. The hardest part is writing a good CLAUDE.md — and we gave you a template for that.*
