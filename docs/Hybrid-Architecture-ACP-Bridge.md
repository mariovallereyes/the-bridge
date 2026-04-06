# Hybrid Architecture: OpenClaw ACP + The Bridge

**Version:** 0.1.0-draft
**Status:** Design Phase
**Last Updated:** 2026-04-06

---

## 1. Goals and Non-Goals

### Goals

1. **Seamless routing.** The orchestrator agent (Patti/Marko in OpenClaw) automatically decides whether to handle a task directly or delegate to The Bridge, with zero user intervention.
2. **Cost elimination.** All heavy compute (coding, analysis, research, multi-step shell work) runs through subscription-covered Claude Code in tmux, not through API tokens.
3. **Result continuity.** Bridge results flow back into the OpenClaw session so the user sees a coherent conversation, not disjointed file artifacts.
4. **Identity preservation.** The orchestrator agent keeps its personality, memory, and context. The Bridge worker is anonymous compute that produces structured output.
5. **Failure transparency.** When The Bridge fails, the orchestrator gracefully falls back or reports clearly. No silent black holes.

### Non-Goals

- **Real-time streaming from Bridge to OpenClaw.** v1 is request/response. The worker completes, then the orchestrator relays the result.
- **Bidirectional conversation.** The Bridge is one-shot: task in, result out. Multi-turn clarification flows are deferred to v2.
- **Shared session state.** The Bridge worker does not see OpenClaw session history. It gets CONTEXT.md + task JSON only.
- **Auto-spawning workers.** A human starts Claude Code in tmux. The orchestrator does not launch it.
- **Replacing ACP.** The Bridge supplements ACP for heavy work. Lightweight ACP tool calls, memory, and messaging stay native.

---

## 2. Component Model

```
┌──────────────────────────────────────────────────────────────────────┐
│                           Host Machine                               │
│                                                                      │
│  ┌─────────────────────────────────┐                                 │
│  │     OpenClaw Gateway             │                                 │
│  │                                  │                                 │
│  │  ┌───────────────────────────┐   │                                 │
│  │  │  Agent: Patti (main)      │   │                                 │
│  │  │                           │   │                                 │
│  │  │  Session Manager          │   │   ┌──────────────────────────┐ │
│  │  │  Context Engine           │   │   │    tmux: "bridge"         │ │
│  │  │  Memory (MEMORY.md)       │   │   │  ┌────────────────────┐  │ │
│  │  │  Tools (native)           │   │   │  │  Claude Code        │  │ │
│  │  │                           │   │   │  │                      │  │ │
│  │  │  ┌─────────────────────┐  │   │   │  │  Reads: CLAUDE.md   │  │ │
│  │  │  │  Bridge Router      │──────────│  │  Reads: CONTEXT.md  │  │ │
│  │  │  │  (skill + AGENTS.md)│  │ files │  │  Reads: inbox/      │  │ │
│  │  │  │                     │──────────│  │  Writes: outbox/     │  │ │
│  │  │  │  Decides: direct    │  │ tmux  │  │                      │  │ │
│  │  │  │  vs Bridge          │  │ keys  │  └────────────────────┘  │ │
│  │  │  └─────────────────────┘  │   │   └──────────────────────────┘ │
│  │  │                           │   │                                 │
│  │  │  Result Relay             │   │   ┌──────────────────────────┐ │
│  │  │  (parses outbox JSON,     │   │   │  ~/.the-bridge/          │ │
│  │  │   formats for user,       │   │   │  CLAUDE.md  CONTEXT.md   │ │
│  │  │   updates memory/tasks)   │   │   │  inbox/  outbox/         │ │
│  │  └───────────────────────────┘   │   │  active/  archive/       │ │
│  │                                  │   └──────────────────────────┘ │
│  │  Messaging Surfaces              │                                 │
│  │  (WhatsApp, CLI, WebChat)        │                                 │
│  └─────────────────────────────────┘                                 │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Components

| Component | Lives In | Role |
|-----------|----------|------|
| **Bridge Router** | OpenClaw agent (skill + AGENTS.md) | Decides direct vs Bridge for every message. Silent, automatic. |
| **Bridge Dispatcher** | OpenClaw agent (exec: bridge.sh) | Writes task JSON, triggers tmux, polls outbox. |
| **Bridge Worker** | Claude Code in tmux | Reads CLAUDE.md + CONTEXT.md + task JSON. Does the work. Writes result. |
| **Result Relay** | OpenClaw agent (post-exec) | Parses result JSON, formats for user, updates task registry and memory. |
| **Context Updater** | OpenClaw agent (between tasks) | Keeps CONTEXT.md current with project state, preferences, and task history. |

---

## 3. Sequence Flows

### 3.1 Happy Path: User Message -> Bridge -> Reply

```
User                    OpenClaw (Patti)              Filesystem               Bridge Worker
 │                           │                            │                        │
 │  "Fix the login bug"      │                            │                        │
 │──────────────────────────>│                            │                        │
 │                           │                            │                        │
 │                           │ 1. Bridge Router:          │                        │
 │                           │    coding task -> Bridge   │                        │
 │                           │                            │                        │
 │                           │ 2. Log to task registry    │                        │
 │                           │                            │                        │
 │                           │ 3. exec bridge.sh          │                        │
 │                           │────────────────────────────>│ inbox/task.json       │
 │                           │                            │                        │
 │                           │ 4. tmux send-keys          │                        │
 │                           │─────────────────────────────────────────────────────>│
 │                           │                            │                        │
 │                           │                            │ 5. Worker reads task   │
 │                           │                            │<───────────────────────│
 │                           │                            │                        │
 │                           │                            │ 6. Worker executes     │
 │                           │                            │        ... time ...    │
 │                           │                            │                        │
 │                           │                            │ 7. Worker writes result│
 │                           │                            │ outbox/task.json <─────│
 │                           │                            │                        │
 │                           │ 8. bridge.sh returns JSON  │                        │
 │                           │<────────────────────────────│                        │
 │                           │                            │                        │
 │                           │ 9. Result Relay:           │                        │
 │                           │    parse, format, reply    │                        │
 │                           │                            │                        │
 │  "Fixed the login bug..." │                            │                        │
 │<──────────────────────────│                            │                        │
 │                           │                            │                        │
 │                           │ 10. Update task registry   │                        │
 │                           │     Update daily memory    │                        │
```

### 3.2 Direct Handling (No Bridge)

```
User                    OpenClaw (Patti)
 │                           │
 │  "What's on my calendar?" │
 │──────────────────────────>│
 │                           │
 │                           │ 1. Bridge Router:
 │                           │    calendar query -> direct
 │                           │
 │                           │ 2. Native tool call (gog)
 │                           │
 │  "You have 3 meetings..." │
 │<──────────────────────────│
```

### 3.3 Bridge Failure -> Fallback

```
User                    OpenClaw (Patti)              Bridge
 │                           │                          │
 │  "Refactor the API"       │                          │
 │──────────────────────────>│                          │
 │                           │ Router: coding -> Bridge │
 │                           │ Check: tmux has-session  │
 │                           │ Result: session NOT found│
 │                           │                          │
 │                           │ Fallback: Codex          │
 │                           │ (or tell user to start   │
 │                           │  the Bridge worker)      │
 │                           │                          │
 │  "Bridge is down. I'll    │                          │
 │   use Codex instead..."   │                          │
 │<──────────────────────────│                          │
```

---

## 4. Message and Task Envelopes

### 4.1 Inbound: User Message (OpenClaw native)

OpenClaw receives messages as ACP session events. No change needed. The message enters the agent loop and hits the Bridge Router during tool/action planning.

### 4.2 Bridge Task Envelope (inbox JSON)

```json
{
  "id": "task-YYYYMMDD-NNN",
  "version": "0.1.0",
  "created_at": "ISO 8601",
  "timeout_seconds": 300,
  "type": "code|research|analysis|file|command|composite",
  "title": "Short summary for the worker",
  "description": "Detailed instructions. Include everything the worker needs.",
  "working_directory": "/absolute/path",
  "context": {
    "files": ["paths/to/read/first"],
    "background": "Why this task exists",
    "constraints": ["Hard rules"]
  },
  "expected_output": {
    "type": "code_change|analysis|structured_data|file|answer",
    "success_criteria": "How to know it's done correctly"
  },
  "metadata": {
    "source": "openclaw",
    "agent": "patti",
    "session_key": "agent:main:whatsapp:direct:+16502966520",
    "reply_to": "user"
  }
}
```

The `metadata` block is new -- it carries ACP session identity so the result relay knows where to deliver the response.

### 4.3 Bridge Result Envelope (outbox JSON)

Standard Bridge result format (unchanged from protocol spec). The orchestrator reads `status`, `result.summary`, `result.details`, `result.files_changed`, `error`, etc.

---

## 5. Session and Task Identity Mapping

### The Problem

OpenClaw has sessions (keyed by `agent:main:<source>`). The Bridge has tasks (keyed by `task-YYYYMMDD-NNN`). These are independent identity spaces.

### The Mapping

| OpenClaw Concept | Bridge Concept | Relationship |
|-----------------|----------------|-------------|
| Session | N/A | The Bridge worker has no session. It reads CONTEXT.md for persistent state. |
| Agent run (runId) | Task (task-id) | 1:1 for each Bridge dispatch. The orchestrator creates a Bridge task as part of an agent run. |
| Background task | Task result | The orchestrator can track the Bridge dispatch as an OpenClaw background task. |
| Session key | metadata.session_key | Carried in the task envelope so the result relay knows which session to respond to. |

### Identity Flow

1. User sends message in session `agent:main:whatsapp:direct:+16502966520`
2. Patti's agent run gets a `runId` from the gateway
3. Patti dispatches Bridge task `task-20260406-042` with `metadata.session_key` pointing back
4. Bridge worker processes, writes result to outbox
5. bridge.sh returns result JSON to Patti's exec context
6. Patti parses result and replies in the original session
7. Patti logs to task registry with both the `runId` and `task-id` for traceability

### OpenClaw Task Registry Integration

```bash
# On dispatch
tasks/log-task.sh add "task-20260406-042" '{
  "task": "Fix login bug",
  "project": "~/Projects/subs-audit",
  "agent": "claude-code",
  "sessionId": "task-20260406-042",
  "requestedBy": "mario"
}'

# On completion
tasks/log-task.sh done "task-20260406-042" '{
  "summary": "Fixed stale closure in onClick handler"
}'
```

---

## 6. Result Relay Design

### What the Result Relay Does

The Result Relay is not a separate component -- it's the orchestrator agent's behavior after bridge.sh returns. It:

1. **Parses** the result JSON from bridge.sh stdout
2. **Extracts** the key information: status, summary, files changed, warnings, errors
3. **Formats** a human-friendly response (not raw JSON)
4. **Replies** to the user in the originating session
5. **Updates** the task registry (done/failed)
6. **Updates** daily memory if significant
7. **Archives** the result (or lets the next context update cycle handle it)

### Formatting Rules

- **Completed tasks:** Lead with the summary. Mention files changed. Include warnings if any. Keep it concise.
- **Failed tasks (recoverable):** Report the error and suggestion. Offer to retry.
- **Failed tasks (not recoverable):** Report clearly. Don't retry.
- **Partial tasks:** Report what was done and what wasn't.
- **Never dump raw JSON** at the user. Parse and format.

### Example Relay

Bridge result:
```json
{
  "status": "completed",
  "result": {
    "summary": "Fixed stale closure in onClick handler",
    "files_changed": ["src/components/LoginForm.tsx"],
    "tests_run": "npm test -- LoginForm (2 passed, 0 failed)"
  }
}
```

Patti replies to Mario:
> Fixed the stale closure in LoginForm.tsx -- the handleSubmit was defined outside the component. Moved it inside. Tests pass (2/2).

---

## 7. Failure Modes and Recovery

| Failure | Detection | Recovery |
|---------|-----------|----------|
| **Worker not running** | `tmux has-session -t bridge` fails before dispatch | Tell user to start worker, OR fall back to Codex |
| **Task timeout** | bridge.sh exits 1 after timeout_seconds | Retry with longer timeout, or break into smaller tasks |
| **Worker crash mid-task** | Task stays in active/, no result in outbox | Orchestrator detects timeout. Move task back to inbox or report failure. |
| **Malformed result JSON** | bridge.sh returns non-JSON or partial JSON | Capture raw output, report error, log for debugging |
| **Worker rejects task (OUT_OF_SCOPE)** | Result has `error.code: "OUT_OF_SCOPE"` | Route to correct bridge (Patti vs Marko) |
| **Bridge dir missing** | inbox/ or outbox/ doesn't exist | Create directories or report setup error |
| **tmux pane unresponsive** | Worker doesn't pick up task within 30s | Send "status" to tmux, check pane output, consider restarting |
| **OpenClaw gateway restart** | Bridge task was in flight when gateway restarted | On startup, check outbox/ for unprocessed results. Resume relay. |
| **Concurrent dispatch** | Two tasks in inbox at once | Worker processes oldest first (FIFO). Second waits. No data loss. |

### Fallback Chain

```
Bridge (Claude Code, $0)
  |-- fail --> Codex (openai/gpt-5.4, API cost)
                |-- fail --> Direct (Patti/Opus, API cost)
                              |-- fail --> Report to user
```

---

## 8. Recommended Implementation Phases

### Phase 1: Current State (DONE)

- Bridge skill (`skills/the-bridge/SKILL.md`) with routing rules
- AGENTS.md mandatory routing check on every message
- bridge.sh one-liner for dispatch + poll
- Manual result relay (Patti reads result, formats reply)
- Task registry logging (manual via log-task.sh)

### Phase 2: Structured Result Relay

- Patti automatically parses bridge.sh stdout JSON
- Formats human-friendly response from result fields
- Updates task registry on completion/failure
- Appends to daily memory for significant tasks
- Updates CONTEXT.md task history after each completed task

### Phase 3: OpenClaw Task Integration

- Bridge dispatches create OpenClaw background tasks (via `openclaw tasks` or task registry)
- Bridge results trigger task completion notifications
- Task Flow can orchestrate multi-Bridge sequences (e.g., "research then code then test")
- `metadata.session_key` enables result delivery to any session, not just the dispatching one

### Phase 4: Context Automation

- CONTEXT.md auto-updated after each task (task history, project status)
- Bridge worker health monitored via cron (tmux session check + orphan detection)
- Auto-archive completed results on a schedule
- Stale task detection and alerting

### Phase 5: Multi-Bridge Routing (Future)

- Orchestrator routes to Patti's bridge (coding/analysis) vs Marko's bridge (marketing) based on task type
- Bridge capability metadata (what each worker is good at)
- Load-aware routing (don't dispatch if worker has active task)

---

## 9. What Stays ACP-Native vs Bridge-Native

### ACP-Native (OpenClaw handles directly)

| Category | Why |
|----------|-----|
| Conversation, chat, opinions | Personality and memory are the value. No compute needed. |
| Memory recall and updates | Files are in the workspace. Context is the value. |
| Calendar, email, reminders | Native tool calls, fast, low-latency. |
| WhatsApp/messaging | Session continuity matters. Bridge can't message. |
| Web search and fetch | Native tools, fast round-trip. |
| Routing decisions | The orchestrator decides. The worker executes. |
| Result relay and formatting | The orchestrator owns the user relationship. |
| Task registry and tracking | Orchestrator-side bookkeeping. |
| CONTEXT.md updates | The orchestrator maintains living context. |

### Bridge-Native (Claude Code worker handles)

| Category | Why |
|----------|-----|
| Coding, refactoring, debugging | Full IDE-grade reasoning + file system access. |
| Shell commands, build, test | Direct terminal execution. |
| Multi-file repo work | Context window + file access + reasoning. |
| Deep analysis and research | Claude Code quality reasoning at zero API cost. |
| Long document processing | Large context window, patient execution. |
| Strategic planning and architecture | Strong reasoning without token anxiety. |
| Data processing and migrations | Shell + code + reasoning combined. |
| Vault/filesystem search and synthesis | Can grep, read, and synthesize across many files. |

### Split Tasks (Orchestrator provides context, Bridge does work)

| Pattern | Orchestrator Role | Bridge Role |
|---------|-------------------|-------------|
| "Analyze LP pipeline" | Provides CRM data path, current context | Reads DB, analyzes, returns structured findings |
| "Write the quarterly update" | Provides fund status from memory, constraints | Drafts the document with full reasoning |
| "Research this company" | Provides what's already known from memory | Does the deep analysis, returns findings |

---

*The hybrid is the point. Neither system alone is optimal. Together they cover the full spectrum: fast + cheap + smart + persistent.*
