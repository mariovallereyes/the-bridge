# Security Considerations — The Bridge

**Version:** 0.1.0-draft
**Status:** Design Phase

---

## 1. Threat Model

The Bridge operates under these assumptions:

| Assumption | Detail |
|-----------|--------|
| **Single user** | Both orchestrator and worker run as the same OS user |
| **Local machine** | All communication is via local filesystem — no network |
| **Trusted orchestrator** | The orchestrator is controlled by the user (not a random third party) |
| **Semi-trusted worker** | The worker follows instructions but may hallucinate or misinterpret |
| **No shared access** | The bridge directory is not exposed to other users or network services |

---

## 2. Risk Analysis

### 2.1 Low Risk

| Risk | Assessment | Mitigation |
|------|-----------|------------|
| Worker reads files it shouldn't | Worker has same filesystem access as user; no escalation | Use `context.constraints` to limit scope; don't point `working_directory` at sensitive dirs |
| Task files contain sensitive data | Files are local, same permission as user's other files | Don't put credentials in task descriptions; reference file paths instead |
| Worker writes to wrong directory | Worker follows CLAUDE.md; may misinterpret paths | Always use absolute paths in `working_directory`; add explicit constraints |

### 2.2 Medium Risk

| Risk | Assessment | Mitigation |
|------|-----------|------------|
| Worker runs destructive commands | Claude Code can execute shell commands | Use `context.constraints`: "Do not delete files", "Do not run rm/drop commands"; review CLAUDE.md rules carefully |
| Malicious task injection | If another process can write to `inbox/`, it can dispatch arbitrary tasks | Restrict `inbox/` permissions: `chmod 700 inbox/`; only orchestrator should write there |
| Sensitive data in archive | Archives accumulate task/result history including code and analysis | Rotate archives; `find archive/ -mtime +30 -delete`; don't archive tasks with credentials |
| Worker ignores constraints | AI hallucination; worker may not follow all rules perfectly | Test critical constraints before trusting them; add verification steps to orchestrator |

### 2.3 High Risk

| Risk | Assessment | Mitigation |
|------|-----------|------------|
| `--dangerously-skip-permissions` | Removes all Claude Code safety prompts | This flag is REQUIRED for automation. Mitigate by: constraining task scope, reviewing results, not pointing at production systems |
| Exfiltration via worker | Worker could theoretically curl/upload data | Claude Code's default permissions model prevents network calls; with skip-permissions, add explicit CLAUDE.md rule: "NEVER make network requests, curl, wget, or any outbound connections" |
| Bridge directory on shared filesystem | NFS/SMB/cloud sync could expose tasks to other machines | Use local filesystem only; exclude bridge directory from cloud sync (Dropbox, iCloud, etc.) |

---

## 3. Security Rules for CLAUDE.md

Add these rules to every worker contract:

```markdown
## Security Rules

1. NEVER make network requests (no curl, wget, fetch, or any HTTP calls)
2. NEVER access or modify files outside the working_directory and bridge directories
3. NEVER read, display, or log credentials, tokens, API keys, or secrets
4. NEVER install packages or dependencies without explicit instruction in the task
5. NEVER modify system files or configurations
6. NEVER execute commands that delete data (rm, drop, truncate) unless the task explicitly requires it AND specifies the exact target
7. If a task asks you to do something that seems dangerous or destructive, write a FAILED result explaining why instead of executing
```

---

## 4. Filesystem Permissions

### 4.1 Recommended Permissions

```bash
# Bridge root: only owner can access
chmod 700 "$BRIDGE_DIR"

# All subdirectories: only owner
chmod 700 "$BRIDGE_DIR"/{inbox,outbox,active,archive,workspace,logs}

# CLAUDE.md: readable by owner (worker needs to read it)
chmod 600 "$BRIDGE_DIR/CLAUDE.md"
```

### 4.2 Exclude from Cloud Sync

If you use iCloud, Dropbox, Google Drive, or similar:

```bash
# macOS — exclude from iCloud
xattr -w com.apple.fileprovider.ignore 1 "$BRIDGE_DIR"

# .gitignore (if bridge is inside a git repo)
echo ".bridge/" >> .gitignore

# Dropbox — use selective sync to exclude the directory
```

---

## 5. Credential Handling

### 5.1 Never in Task Files

```json
// ❌ NEVER DO THIS
{
  "description": "Deploy to production using API key sk-abc123..."
}

// ✅ DO THIS INSTEAD
{
  "description": "Deploy to production using the API key stored in ~/.config/deploy/key",
  "context": {
    "constraints": ["Read the API key from ~/.config/deploy/key at runtime"]
  }
}
```

### 5.2 Never in Results

The CLAUDE.md should instruct: "Never include credentials, tokens, or secrets in result files. If a task produces sensitive output, write it to a separate file in workspace/ and reference the path in the result."

### 5.3 Environment Variables

If the worker needs env vars, set them in the tmux session, not in task files:

```bash
# Set before starting Claude Code
tmux send-keys -t bridge "export DATABASE_URL=postgres://..." Enter
tmux send-keys -t bridge "claude --dangerously-skip-permissions" Enter
```

---

## 6. Provider Considerations

### 6.1 Terms of Service

The Bridge uses subscription-covered tools exactly as designed:
- Claude Code reads a project instruction file → standard behavior
- A human (or AI acting on behalf of a human) types in a terminal → standard behavior  
- Claude Code reads/writes files → standard behavior

There is no API interception, token theft, or protocol violation. However:

**Be aware:** Providers may update their ToS to restrict automated use of interactive tools. Monitor ToS changes for your specific tools.

### 6.2 Rate Limiting

Even though you're not hitting an API, the worker tool may have fair-use limits:
- Claude Code may have session length limits
- Continuous rapid task processing could trigger abuse detection
- Add reasonable delays between tasks (the polling interval naturally provides this)

**Recommendation:** Don't process more than 20-30 tasks per hour. A human wouldn't type faster than that.

### 6.3 What The Bridge Is NOT

- ❌ NOT an API bypass — no API is involved
- ❌ NOT credential sharing — your subscription, your machine, your terminal
- ❌ NOT reverse engineering — using published CLI tools as documented
- ❌ NOT a proxy — the worker runs locally, not as a service for others

---

## 7. Audit Trail

The archive directory provides a complete audit trail:

```
archive/
├── 2025-07-03/
│   ├── task-001.request.json   ← What was asked
│   ├── task-001.result.json    ← What was done
│   ├── task-002.request.json
│   └── task-002.result.json
```

Review periodically:
- Are tasks within expected scope?
- Are results accurate and safe?
- Any unexpected files_changed or commands run?

```bash
# Quick audit: what files were changed in the last 7 days?
find "$BRIDGE_DIR/archive" -name "*.result.json" -mtime -7 -exec grep -l "files_changed" {} \; | xargs jq '.result.files_changed'
```

---

## 8. Emergency Procedures

### 8.1 Kill the Worker Immediately

```bash
# Kill the tmux session (terminates Claude Code)
tmux kill-session -t bridge
```

### 8.2 Freeze the Queue

```bash
# Rename inbox so worker can't pick up new tasks
mv "$BRIDGE_DIR/inbox" "$BRIDGE_DIR/inbox.frozen"
```

### 8.3 Review What Happened

```bash
# Check what the worker was doing
cat "$BRIDGE_DIR/active/"*.json 2>/dev/null

# Check recent results
ls -lt "$BRIDGE_DIR/outbox/" | head -5

# Check tmux scrollback (if session is still alive)
tmux capture-pane -t bridge -p -S -500 > /tmp/bridge-forensics.txt
```

### 8.4 Clean State Reset

```bash
# Archive everything and start fresh
DATE=$(date +%Y-%m-%d)
mkdir -p "$BRIDGE_DIR/archive/$DATE"
mv "$BRIDGE_DIR/inbox/"*.json "$BRIDGE_DIR/archive/$DATE/" 2>/dev/null
mv "$BRIDGE_DIR/active/"*.json "$BRIDGE_DIR/archive/$DATE/" 2>/dev/null
mv "$BRIDGE_DIR/outbox/"*.json "$BRIDGE_DIR/archive/$DATE/" 2>/dev/null
rm -rf "$BRIDGE_DIR/workspace/"*
```

---

*Security through simplicity. No network = no remote exploits. No database = no injection. No server = no unauthorized access.*
