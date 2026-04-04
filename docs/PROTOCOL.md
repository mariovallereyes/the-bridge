# Protocol Specification — The Bridge

**Version:** 0.1.0-draft
**Status:** Design Phase

---

## 1. Overview

The Bridge Protocol defines how an orchestrator agent and a worker agent communicate through the filesystem. It specifies file formats, directory structure, naming conventions, task lifecycle, and behavioral contracts.

This document is the canonical reference for implementers on both sides.

---

## 2. Directory Structure

```
<bridge-root>/
├── CLAUDE.md              # Worker contract — static protocol (required)
├── CONTEXT.md             # Living context — updated between tasks (recommended)
├── inbox/                 # Orchestrator → Worker (pending tasks)
├── outbox/                # Worker → Orchestrator (completed results)
├── active/                # Currently executing (moved from inbox by worker)
├── archive/               # Completed tasks (moved from outbox by orchestrator or cron)
├── workspace/             # Scratch space for worker operations
└── logs/                  # Optional: worker logs, debug output
```

### 2.1 Directory Semantics

| Component | Written By | Read By | Purpose |
|-----------|-----------|---------|---------|
| `CLAUDE.md` | Human (setup) | Worker | Static protocol contract |
| `CONTEXT.md` | Orchestrator | Worker | Living context — projects, preferences, history |
| `inbox/` | Orchestrator | Worker | New tasks awaiting pickup |
| `active/` | Worker | Both | Task currently being executed |
| `outbox/` | Worker | Orchestrator | Completed results ready for pickup |
| `archive/` | Either | Either | Historical tasks and results (audit trail) |
| `workspace/` | Worker | Worker | Temporary files, scratch space |
| `logs/` | Worker | Either | Debug and execution logs |

---

## 3. Context File Format

### 3.1 Living Context (`CONTEXT.md`)

The `CONTEXT.md` file provides persistent, evolving context to the worker. It is written in Markdown (not JSON) because:
- Workers read Markdown natively and reliably
- Humans can read and audit it easily
- It supports flexible structure (tables, lists, prose)

#### Required Sections

| Section | Purpose |
|---------|---------|
| **Dispatcher** | Who is sending tasks and on whose behalf |
| **Active Projects** | Current projects with paths, stacks, and status |
| **Preferences** | Coding style, conventions, standing rules |
| **Recent Task History** | Last 5-10 tasks with one-line summaries |

#### Optional Sections

| Section | Purpose |
|---------|---------|
| **Standing Instructions** | Rules that apply to all tasks (e.g., "always use TypeScript strict mode") |
| **Knowledge Base** | Pointers to documentation, vault files, or reference material |
| **Notes** | Anything else the orchestrator wants the worker to know |

#### Update Cadence

The orchestrator SHOULD update `CONTEXT.md`:
- After each completed task (add to Recent Task History)
- When project status changes
- When preferences or standing instructions change
- Before dispatching a task that requires new context

The orchestrator SHOULD NOT update `CONTEXT.md`:
- During task execution (worker is already reading it)
- With sensitive data (credentials, tokens, secrets)

#### Priority

If `CONTEXT.md` and a task JSON conflict, **the task JSON takes priority**. Task-level instructions are more specific and more recent.

#### Example

```markdown
# CONTEXT.md — Living Context

*Last updated by orchestrator: 2025-07-03*

## Dispatcher
- **Agent:** My AI Assistant (via OpenClaw)
- **On behalf of:** Jane Developer
- **Timezone:** America/New_York

## Active Projects
| Project | Path | Stack | Status |
|---------|------|-------|--------|
| My SaaS App | ~/Projects/my-saas | Next.js, TypeScript, Prisma | Active |
| Marketing Site | ~/Projects/marketing | Astro, Tailwind | Maintenance |

## Coding Preferences
- TypeScript strict mode
- Prefer const over let, never var
- Commit format: type: short description
- Run tests after every change

## Standing Instructions
- Always check .env.example before assuming env vars
- Keep functions under 50 lines
- Don't install new packages without mentioning in result

## Recent Task History
| Task ID | Date | Summary | Status |
|---------|------|---------|--------|
| task-001 | 2025-07-03 | Added input validation to registration | ✅ |
| task-002 | 2025-07-03 | Fixed mobile nav overlap | ✅ |
```

---

## 4. Task File Format

### 3.1 Task Request (`inbox/<task-id>.json`)

```json
{
  "id": "task-20250703-001",
  "version": "0.1.0",
  "created_at": "2025-07-03T15:30:00Z",
  "timeout_seconds": 300,
  "priority": "normal",
  "type": "code",
  "title": "Add input validation to user registration",
  "description": "Add email format validation and password strength checking to the registration endpoint in src/api/auth.ts",
  "working_directory": "~/Projects/my-app",
  "context": {
    "files": ["src/api/auth.ts", "src/utils/validation.ts"],
    "background": "The app currently accepts any string as email/password. We need basic validation before the form refactor next week.",
    "constraints": ["Do not modify the database schema", "Use zod for validation"]
  },
  "expected_output": {
    "type": "code_change",
    "success_criteria": "Registration endpoint rejects invalid emails and passwords shorter than 8 characters"
  },
  "metadata": {
    "source": "orchestrator",
    "tags": ["backend", "validation"]
  }
}
```

### 3.2 Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | ✅ | Unique task identifier. Format: `task-YYYYMMDD-NNN` or UUID |
| `version` | string | ✅ | Protocol version |
| `created_at` | ISO 8601 | ✅ | Timestamp of task creation |
| `timeout_seconds` | integer | ❌ | Max execution time. Default: 300 (5 min) |
| `priority` | enum | ❌ | `low`, `normal`, `high`, `critical`. Default: `normal` |
| `type` | enum | ✅ | Task type (see §3.3) |
| `title` | string | ✅ | Short human-readable summary |
| `description` | string | ✅ | Detailed task description. Natural language. |
| `working_directory` | path | ❌ | Directory for the worker to operate in. If omitted, uses `workspace/` |
| `context` | object | ❌ | Additional context for the worker |
| `context.files` | string[] | ❌ | Relevant file paths (relative to working_directory) |
| `context.vault_files` | string[] | ❌ | Obsidian vault files to read for context before executing (relative to vault root) |
| `context.background` | string | ❌ | Why this task exists, broader context |
| `context.constraints` | string[] | ❌ | Rules the worker must follow |
| `expected_output` | object | ❌ | What the orchestrator expects back |
| `expected_output.type` | enum | ❌ | `code_change`, `analysis`, `file`, `answer`, `structured_data` |
| `expected_output.success_criteria` | string | ❌ | How to know the task is done correctly |
| `metadata` | object | ❌ | Arbitrary key-value pairs for tracking |

### 3.3 Task Types

| Type | Description | Typical Worker Action |
|------|-------------|----------------------|
| `code` | Write, modify, or refactor code | Edit files, run tests |
| `review` | Review code or a PR | Read files, write analysis |
| `research` | Investigate a question | Read docs, search, synthesize |
| `analysis` | Analyze data or a codebase | Read, compute, report |
| `file` | Create or transform a file | Write output file |
| `command` | Run a specific command and report output | Execute, capture, report |
| `composite` | Multiple sub-tasks (worker handles sequencing) | Varies |

---

## 5. Result File Format

### 4.1 Task Result (`outbox/<task-id>.json`)

```json
{
  "id": "task-20250703-001",
  "version": "0.1.0",
  "completed_at": "2025-07-03T15:32:45Z",
  "duration_seconds": 165,
  "status": "completed",
  "result": {
    "summary": "Added zod-based email and password validation to the registration endpoint",
    "details": "Created a registrationSchema in src/utils/validation.ts using zod. Email validated with z.string().email(), password requires min 8 chars, 1 uppercase, 1 number. Applied schema in auth.ts registration handler with proper error responses (400 + field-level errors).",
    "files_changed": [
      "src/api/auth.ts",
      "src/utils/validation.ts"
    ],
    "files_created": [],
    "tests_run": "npm test -- --grep registration (3 passed, 0 failed)",
    "warnings": []
  },
  "error": null
}
```

### 4.2 Failed Task Result

```json
{
  "id": "task-20250703-002",
  "version": "0.1.0",
  "completed_at": "2025-07-03T15:40:12Z",
  "duration_seconds": 45,
  "status": "failed",
  "result": null,
  "error": {
    "code": "DEPENDENCY_MISSING",
    "message": "zod is not installed in the project. Run: npm install zod",
    "recoverable": true,
    "suggestion": "Install zod and resubmit the task"
  }
}
```

### 4.3 Result Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | ✅ | Must match the task request `id` |
| `version` | string | ✅ | Protocol version |
| `completed_at` | ISO 8601 | ✅ | When the worker finished |
| `duration_seconds` | integer | ✅ | Wall-clock execution time |
| `status` | enum | ✅ | `completed`, `failed`, `partial`, `timeout` |
| `result` | object \| null | ✅ | Null if failed; populated if completed/partial |
| `result.summary` | string | ✅* | One-line summary of what was done |
| `result.details` | string | ❌ | Detailed explanation |
| `result.files_changed` | string[] | ❌ | Files modified (relative to working_directory) |
| `result.files_created` | string[] | ❌ | New files created |
| `result.tests_run` | string | ❌ | Test command and results if applicable |
| `result.data` | any | ❌ | Structured data output (for `analysis`/`structured_data` tasks) |
| `result.warnings` | string[] | ❌ | Non-blocking issues noticed |
| `error` | object \| null | ✅ | Null if completed; populated if failed |
| `error.code` | string | ✅* | Machine-readable error code |
| `error.message` | string | ✅* | Human-readable error description |
| `error.recoverable` | boolean | ❌ | Can this task be retried? |
| `error.suggestion` | string | ❌ | What to do to fix it |

---

## 6. Task Lifecycle

```
                ┌──────────┐
                │  created  │  (orchestrator writes to inbox/)
                └─────┬────┘
                      │
                      ▼
                ┌──────────┐
                │  pending  │  (file sits in inbox/ awaiting pickup)
                └─────┬────┘
                      │  worker moves file to active/
                      ▼
                ┌──────────┐
                │  running  │  (worker is executing)
                └─────┬────┘
                      │
              ┌───────┼───────┐
              ▼       ▼       ▼
        ┌──────┐ ┌────────┐ ┌─────────┐
        │ done │ │ failed │ │ timeout │
        └──┬───┘ └───┬────┘ └────┬────┘
           │         │           │
           └─────────┴───────────┘
                      │
                      ▼  worker writes result to outbox/
                ┌──────────┐
                │ picked up│  (orchestrator reads outbox/ file)
                └─────┬────┘
                      │  orchestrator moves to archive/
                      ▼
                ┌──────────┐
                │ archived │
                └──────────┘
```

### 5.1 State Transitions

| From | To | Triggered By | Action |
|------|----|-------------|--------|
| — | pending | Orchestrator | Write task JSON to `inbox/` |
| pending | running | Worker | Move task from `inbox/` to `active/` |
| running | completed | Worker | Write result to `outbox/`, delete from `active/` |
| running | failed | Worker | Write error result to `outbox/`, delete from `active/` |
| running | timeout | Orchestrator | Detected via `created_at` + `timeout_seconds` |
| completed/failed | archived | Orchestrator | Move task+result pair to `archive/` |

### 5.2 Timeout Detection

The orchestrator is responsible for timeout detection:

1. Read `active/<task-id>.json` timestamp
2. Compare `created_at + timeout_seconds` against current time
3. If exceeded: write a timeout result to `outbox/`, clean up `active/`
4. Optionally: send a cancel signal to the worker via tmux

---

## 7. Trigger Mechanism

### 6.1 Primary: tmux Keystroke

After writing a task to `inbox/`, the orchestrator sends a message to the worker's tmux pane:

```bash
tmux send-keys -t bridge "check inbox" Enter
```

The exact trigger phrase is configurable in `CLAUDE.md`. Recommended defaults:
- `check inbox` — check for new tasks
- `status` — report current state
- `cancel` — abort current task

### 6.2 Why Not File Watching?

File watching (`fswatch`, `inotify`) would be more elegant but:
- Adds a dependency
- Requires a daemon/watcher process
- The worker AI can't run background processes — it needs explicit prompting
- tmux keystroke is universally available and zero-config

### 6.3 Alternative: Polling

If tmux is unavailable, the CLAUDE.md can instruct the worker to poll `inbox/` at intervals. This is less efficient but works without any orchestrator interaction beyond file writes.

---

## 8. Concurrency Model

### 7.1 v1: Single Worker, Single Task

- One bridge instance = one worker = one task at a time
- New tasks queue in `inbox/` (FIFO by filename sort)
- Worker picks up the oldest file first

### 7.2 Multiple Bridge Instances

For parallelism, run multiple bridge instances:

```
~/.bridges/
├── bridge-alpha/    ← Claude Code instance 1
├── bridge-beta/     ← Claude Code instance 2
└── bridge-gamma/    ← Cursor instance
```

Each has its own tmux session, its own `CLAUDE.md`, its own inbox/outbox.

The orchestrator routes tasks to the appropriate bridge based on type, load, or capability.

---

## 9. File Naming Conventions

### 8.1 Task Files

```
inbox/task-20250703-001.json
inbox/task-20250703-002.json
active/task-20250703-001.json
outbox/task-20250703-001.json
```

Format: `task-YYYYMMDD-NNN.json` where NNN is a zero-padded sequence number per day.

Alternative: UUIDs (`task-a1b2c3d4-e5f6-7890-abcd-ef1234567890.json`) for globally unique IDs.

### 8.2 Archive Structure

```
archive/
├── 2025-07-03/
│   ├── task-20250703-001.request.json
│   ├── task-20250703-001.result.json
│   ├── task-20250703-002.request.json
│   └── task-20250703-002.result.json
```

Archived files are renamed with `.request.json` and `.result.json` suffixes for clarity.

---

## 10. Error Codes

| Code | Description |
|------|-------------|
| `TASK_COMPLETED` | Normal completion |
| `TASK_PARTIAL` | Partially completed (some objectives met) |
| `DEPENDENCY_MISSING` | Required tool/package not installed |
| `FILE_NOT_FOUND` | Referenced file doesn't exist |
| `PERMISSION_DENIED` | Worker lacks filesystem permissions |
| `INVALID_TASK` | Task JSON is malformed or missing required fields |
| `WORKING_DIR_NOT_FOUND` | Specified working_directory doesn't exist |
| `TIMEOUT` | Task exceeded timeout_seconds |
| `WORKER_ERROR` | Unspecified worker-side error |
| `CANCELLED` | Task was cancelled by orchestrator |

---

## 11. Versioning

The protocol uses semantic versioning. The `version` field in every task and result file ensures compatibility.

- **Major** version changes = breaking protocol changes
- **Minor** version changes = new optional fields, backward compatible
- **Patch** version changes = clarifications, no format changes

Workers SHOULD reject tasks with a major version they don't understand.
Workers SHOULD accept tasks with unknown minor/patch versions (ignore unknown fields).

---

*This specification is the source of truth for all implementations.*
