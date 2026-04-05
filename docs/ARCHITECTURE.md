# Architecture — The Bridge

**Version:** 0.1.0-draft
**Status:** Design Phase

---

## 1. System Overview

The Bridge is a local, file-based task delegation system. There are no servers, no databases, no network calls. The entire system runs on a single machine using two components:

1. **Orchestrator** — An AI agent (running in any platform) that creates tasks and reads results
2. **Worker** — A subscription-covered AI tool (e.g., Claude Code) running in a tmux terminal session

They communicate exclusively through files on the local filesystem.

```
┌─────────────────────────────────────────────────────────────────┐
│                          Host Machine                           │
│                                                                 │
│  ┌─────────────────┐         ┌────────────────────────────────┐ │
│  │   Orchestrator   │         │        tmux: "bridge"          │ │
│  │                  │         │  ┌──────────────────────────┐  │ │
│  │  ┌────────────┐  │  files  │  │      Claude Code          │  │ │
│  │  │  Bridge     │──────────│  │                            │  │ │
│  │  │  Skill /    │  │       │  │  Reads: CLAUDE.md          │  │ │
│  │  │  Driver     │  │ tmux  │  │  Watches: inbox/           │  │ │
│  │  │            │──────────│  │  Writes: outbox/            │  │ │
│  │  └────────────┘  │ keys  │  │  Works in: working_directory│  │ │
│  │                  │       │  └──────────────────────────────┘  │ │
│  │  (OpenClaw,      │       └────────────────────────────────┘  │ │
│  │   n8n, custom,   │                                           │
│  │   any agent)     │         ┌────────────────────────────────┐ │
│  └─────────────────┘         │     the-bridge/ (filesystem)    │ │
│                              │                                  │ │
│                              │  CLAUDE.md                       │ │
│                              │  inbox/   → pending tasks        │ │
│                              │  active/  → currently executing  │ │
│                              │  outbox/  → completed results    │ │
│                              │  archive/ → historical records   │ │
│                              │  workspace/ → scratch space      │ │
│                              └────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Component Details

### 2.1 The Bridge Directory

This is the heart of the system. It's just a directory on disk with a defined structure.

**Location:** Anywhere the user chooses. Examples:
- `~/.the-bridge/` (single global bridge)
- `~/bridges/claude-code/` (named per worker)
- Inside a project: `~/Projects/my-app/.bridge/`

**Key property:** The bridge directory is infrastructure, not a workspace. The worker can operate on any directory on the machine — the bridge just holds the queue and contract.

### 2.2 The Three-Layer Information Model

The Bridge separates information into three layers:

| Layer | File | Updated | Read By Worker |
|-------|------|---------|----------------|
| **Protocol** | `CLAUDE.md` | Rarely (by human) | Every interaction (automatic) |
| **Context** | `CONTEXT.md` | Between tasks (by orchestrator) | Start of every task |
| **Task** | `inbox/*.json` | Per task (by orchestrator) | When triggered |

- **CLAUDE.md** — Static. Defines HOW the worker operates: file formats, lifecycle, rules, error codes. Rarely changes.
- **CONTEXT.md** — Living. Defines WHO is dispatching, active projects, coding preferences, standing instructions, recent task history. Updated by the orchestrator between task cycles to keep the worker situationally aware.
- **Task JSON** — Ephemeral. Defines WHAT to do right now. One file per task, consumed and archived.

This separation eliminates cold starts. The worker always knows the protocol, always has current context, and gets specific instructions per task.

### 2.3 The Orchestrator

The orchestrator is whatever AI agent needs to delegate work. It has four responsibilities:

1. **Update context** — Keep `CONTEXT.md` current (projects, preferences, history)
2. **Write tasks** — Create JSON files in `inbox/`
3. **Trigger the worker** — Send a keystroke to the tmux session
4. **Read results** — Poll or watch `outbox/` for completed tasks

The orchestrator does NOT need to understand the worker's internals. It only needs to:
- Know the bridge directory path
- Know the tmux session name
- Follow the protocol spec for file formats

**Example orchestrator implementations:**
- `scripts/bridge.sh` - reference implementation, single-command dispatch + poll
- An OpenClaw skill (reads/writes files, sends tmux keys)
- A Python script
- A shell script
- A LangChain tool
- A human using a terminal (yes, you can manually drop JSON files in inbox/)

### 2.4 The Worker

The worker is a subscription-covered AI tool running in a tmux session. It has five responsibilities:

1. **Read the contract** — Follow instructions in `CLAUDE.md`
2. **Read context** — Check `CONTEXT.md` for current state before every task
3. **Pick up tasks** — Read the oldest file from `inbox/`, move to `active/`
4. **Execute** — Do the work described in the task, informed by context
5. **Write results** — Create a result JSON in `outbox/`, clean up `active/`

The worker does NOT know it's part of a bridge. From its perspective:
- It's a normal Claude Code session in a project directory
- Its `CLAUDE.md` tells it to check `inbox/` when prompted
- `CONTEXT.md` gives it background on the projects and preferences
- It reads a JSON file, does work, writes a JSON file
- Standard Claude Code behavior — nothing exotic

### 2.4 tmux Session

tmux is the glue. It provides:

- **Persistence** — The worker stays alive across orchestrator restarts
- **Addressability** — The orchestrator can target a specific pane
- **Input injection** — The orchestrator can type into the worker's terminal
- **Output reading** — The orchestrator can capture the worker's screen

**Session setup:**
```bash
# Create the session
tmux new-session -d -s bridge -c ~/.the-bridge

# Inside the session, start Claude Code
claude --dangerously-skip-permissions
```

**Orchestrator interaction:**
```bash
# Send a trigger
tmux send-keys -t bridge "check inbox" Enter

# Read the screen (last 100 lines)
tmux capture-pane -t bridge -p -S -100
```

---

## 3. Data Flow

### 3.1 Happy Path

```
Time →

Orchestrator                    Filesystem                    Worker
    │                               │                            │
    │  1. Write task                │                            │
    │──────────────────────→ inbox/task-001.json                 │
    │                               │                            │
    │  2. Send tmux keystroke       │                            │
    │────────────────────────────────────────────────────→ "check inbox"
    │                               │                            │
    │                               │  3. Worker reads task      │
    │                        inbox/task-001.json ───────────────→│
    │                               │                            │
    │                               │  4. Worker moves to active │
    │                        active/task-001.json                │
    │                               │                            │
    │                               │  5. Worker does the work   │
    │                               │           ... time ...     │
    │                               │                            │
    │                               │  6. Worker writes result   │
    │                        outbox/task-001.json ←──────────────│
    │                               │                            │
    │                               │  7. Worker cleans active   │
    │                        (active/task-001.json deleted)      │
    │                               │                            │
    │  8. Orchestrator polls        │                            │
    │  outbox/task-001.json ←───────│                            │
    │                               │                            │
    │  9. Process result            │                            │
    │  10. Archive                  │                            │
    │──────────────────→ archive/2025-07-03/task-001.*.json      │
    │                               │                            │
```

### 3.2 Error Path

```
Orchestrator                    Filesystem                    Worker
    │                               │                            │
    │  Write task → inbox/          │                            │
    │  Send keystroke               │                            │
    │                               │  Worker reads, moves to active
    │                               │  Worker encounters error   │
    │                               │                            │
    │                        outbox/task-001.json ←──── (status: "failed")
    │                               │                            │
    │  Read result                  │                            │
    │  Check error.recoverable      │                            │
    │  If true: modify task, resubmit to inbox/                 │
    │  If false: report failure upstream                         │
```

### 3.3 Timeout Path

```
Orchestrator                    Filesystem                    Worker
    │                               │                            │
    │  Write task (timeout: 300s)   │                            │
    │  Record start time            │                            │
    │                               │  Worker picks up task      │
    │                               │  Worker is slow/stuck...   │
    │                               │                            │
    │  Poll: 300s elapsed           │                            │
    │  No result in outbox/         │                            │
    │  Task still in active/        │                            │
    │                               │                            │
    │  Write timeout result         │                            │
    │──────────────────→ outbox/task-001.json (status: "timeout")│
    │  Clean active/                │                            │
    │  Optionally: tmux "cancel"    │                            │
```

---

## 4. Worker Contract Design

The `CLAUDE.md` file is the most critical component. It must be written carefully because it's the only thing that tells the worker how to behave.

### 4.1 Contract Principles

1. **Clear and unambiguous** — The worker is an AI; vague instructions cause unpredictable behavior
2. **Self-contained** — The worker shouldn't need external docs to understand its role
3. **Structured output emphasis** — The contract must stress JSON output format repeatedly
4. **Error handling** — The contract must tell the worker what to do when things go wrong
5. **Scope limitation** — The contract must tell the worker what NOT to do

### 4.2 Contract Sections

A well-designed `CLAUDE.md` includes:

1. **Role** — "You are a task worker. You receive structured tasks and produce structured results."
2. **Trigger** — "When you see 'check inbox', read the oldest .json file in inbox/"
3. **Execution** — "Move the task to active/, do the work, write the result to outbox/"
4. **Format** — Full JSON schema for result files
5. **Rules** — "One task at a time. Never modify the bridge infrastructure. Always write a result, even on failure."
6. **Examples** — At least one complete task → result example

→ Full template: [AGENT-CONTRACT.md](AGENT-CONTRACT.md)

---

## 5. Orchestrator Design

### 5.1 Core Loop

```
loop:
  1. Check if there's work to delegate
  2. Create task JSON
  3. Write to inbox/
  4. Send tmux trigger
  5. Poll outbox/ for result (with timeout)
  6. Read result
  7. Archive task+result
  8. Act on result (report to user, trigger next step, etc.)
```

### 5.2 Polling Strategy

Recommended polling for `outbox/`:
- Start polling 5 seconds after trigger
- Poll every 3 seconds for the first 60 seconds
- Poll every 10 seconds after that
- Give up after `timeout_seconds`

```bash
# Simple poll
while [ ! -f "outbox/task-001.json" ]; do
  sleep 3
done
```

### 5.3 Multiple Bridges

An orchestrator managing multiple bridges needs a routing layer:

```
Orchestrator
    │
    ├── bridge-alpha (Claude Code — coding tasks)
    ├── bridge-beta  (Claude Code — research tasks)  
    └── bridge-gamma (Cursor — UI tasks)
```

Routing can be based on:
- Task type (`code` → alpha, `research` → beta)
- Worker capabilities (defined in each bridge's metadata)
- Load balancing (round-robin across idle workers)
- Priority (critical tasks go to dedicated workers)

---

## 6. Resilience

### 6.1 Orchestrator Crash

- Pending tasks remain in `inbox/` — not lost
- Active tasks remain in `active/` — worker may finish and write to `outbox/`
- Results remain in `outbox/` — orchestrator picks them up on restart
- **Recovery:** On startup, check `outbox/` for unprocessed results, check `active/` for orphans

### 6.2 Worker Crash

- Active task remains in `active/` — no result written
- **Recovery:** Orchestrator detects timeout, writes timeout result, moves task back to `inbox/` for retry or reports failure
- Human restarts Claude Code in the tmux session; `CLAUDE.md` is still there

### 6.3 Machine Restart

- tmux session dies — human must restart it and Claude Code
- All files persist on disk — no data loss
- Orchestrator and worker resume from filesystem state

---

## 7. Extension Points

### 7.1 Callbacks (Future)

Instead of polling, the worker could write a signal file:
```bash
# Worker writes after completing
touch outbox/.ready
```
Orchestrator watches for `.ready` with `fswatch` — instant notification.

### 7.2 Streaming (Future)

For long-running tasks, the worker could write progress updates:
```
active/task-001.progress.json
{
  "percent": 60,
  "message": "Running tests...",
  "updated_at": "2025-07-03T15:31:30Z"
}
```

### 7.3 Multi-Turn (Future)

Some tasks need back-and-forth:
```
inbox/task-001.json          → initial request
outbox/task-001.clarify.json → worker needs info
inbox/task-001.reply.json    → orchestrator provides info
outbox/task-001.json         → final result
```

This keeps the file-based protocol but adds conversation.

---

## 8. Comparison with Alternatives

| Approach | Latency | Cost | Complexity | Reliability |
|----------|---------|------|------------|-------------|
| **The Bridge** | ~10-60s | $0 (subscription) | Low | High (files persist) |
| API calls | ~1-5s | $$$ (per token) | Low | High |
| ACP/Harness | ~1-5s | $$$ (blocked) | Low | Varies |
| MCP server | ~1-5s | $$$ (API backend) | Medium | Medium |
| Clipboard bridge | ~5-30s | $0 | High | Low (fragile) |
| Screenshot + OCR | ~10-30s | $0 | Very High | Very Low |

The Bridge trades latency for cost. For tasks that take minutes (coding, research, analysis), the overhead is negligible.

---

*This architecture is intentionally simple. Complexity is a bug.*
