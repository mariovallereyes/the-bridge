# Windows / `--print` Mode

> An alternative Bridge implementation for Windows (or any OS without tmux).

---

## Why?

The original Bridge implementation uses **tmux** to manage a persistent terminal session. The orchestrator sends keystrokes (`tmux send-keys "check inbox" Enter`) to a running AI tool, which processes tasks in a long-lived interactive session.

**On Windows, tmux doesn't exist.** WSL is an option, but adds complexity and friction. Instead, this implementation uses Claude Code's `--print` mode — a single-turn, non-interactive execution model that achieves the same result through a different mechanism.

---

## How `--print` Mode Works

Instead of maintaining a persistent terminal session and injecting keystrokes:

1. **Dispatcher** (`bridge.js`) writes a task JSON to `inbox/`
2. **Dispatcher** spawns `claude --print "check inbox"` as a child process
3. **Claude Code** starts fresh, reads `CLAUDE.md` (worker contract) from the current directory, reads `CONTEXT.md`, picks up the task, does the work, writes result to `outbox/`
4. **Dispatcher** polls `outbox/` for the result and prints it to stdout

```
┌─────────────┐    spawn + --print     ┌─────────────────┐
│  bridge.js   │ ─────────────────────→ │  Claude Code     │
│ (dispatcher) │                        │  (single-turn)   │
│              │ ← polls outbox/result  │                  │
└─────────────┘                        └─────────────────┘
       │                                       │
       ├── inbox/task.json ──────────────────→ │ (reads)
       │                                       │
       │ ←──────────────── outbox/result.json ─┤ (writes)
```

### Key difference from tmux approach

| Aspect | tmux (Mac/Linux) | `--print` (Windows) |
|--------|-----------------|---------------------|
| **Session** | Persistent — worker stays alive between tasks | Stateless — fresh process per task |
| **Invocation** | Keystroke injection via `tmux send-keys` | Child process via `spawnSync` |
| **Context** | Worker accumulates conversation context | Worker reads `CONTEXT.md` fresh each time |
| **Dependencies** | tmux, bash | Node.js only |
| **OS** | Mac/Linux | Any (Windows, Mac, Linux) |
| **Concurrency** | One task at a time (shared session) | One task at a time (synchronous spawn) |

---

## Directory Structure

```
~/.the-bridge/              (C:\Users\<you>\.the-bridge\)
├── CLAUDE.md               # Worker contract (--print mode version)
├── CONTEXT.md              # Living context — updated between tasks
├── bridge.js               # Node.js dispatcher
├── inbox/                  # Pending tasks (JSON)
├── outbox/                 # Completed results (JSON)
├── active/                 # Task currently being processed
├── archive/                # Completed tasks, organized by date
│   └── 2026-04-05/
├── workspace/              # Default working directory for tasks
└── logs/                   # Optional log storage
```

---

## Setup

### Prerequisites

- **Node.js** (v18+)
- **Claude Code** CLI installed and authenticated (`claude` available in PATH)
- A Claude subscription (Max, Pro, etc.)

### Steps

```powershell
# 1. Clone the repo
git clone https://github.com/mariovallereyes/the-bridge.git
cd the-bridge

# 2. Create the bridge directory structure
$bridge = "$env:USERPROFILE\.the-bridge"
mkdir "$bridge\inbox", "$bridge\outbox", "$bridge\active", "$bridge\archive", "$bridge\workspace", "$bridge\logs" -Force

# 3. Copy templates
copy templates\CLAUDE-windows.md "$bridge\CLAUDE.md"
copy templates\CONTEXT-example.md "$bridge\CONTEXT.md"
copy scripts\bridge.js "$bridge\bridge.js"

# 4. Edit CONTEXT.md with your info
# Update WHO YOU ARE, WHO THE USER IS, ACTIVE PROJECTS, etc.

# 5. Test it
node "$bridge\bridge.js" "Ping test" "Create a file called hello.txt with 'Bridge is live'"
```

### What happens on first run

1. `bridge.js` creates a task JSON in `inbox/`
2. It spawns `claude --print "check inbox"` from `~/.the-bridge/`
3. Claude Code reads `CLAUDE.md`, processes the task, writes result to `outbox/`
4. `bridge.js` picks up the result and prints it

---

## Usage

```powershell
# Basic task
node bridge.js "Fix the login bug" "The form doesn't submit on click" "C:\Users\me\Projects\my-app"

# With custom timeout (seconds) and task type
node bridge.js "Write unit tests" "Add tests for auth module" "C:\Users\me\Projects\my-app" 300 "code"

# Arguments:
#   1: title (required)
#   2: description (required)
#   3: working_directory (optional, defaults to ~/.the-bridge/workspace)
#   4: timeout_seconds (optional, defaults to 120)
#   5: type (optional, defaults to "code")
```

---

## Trade-offs

### Advantages over tmux approach

- **No tmux dependency** — works on Windows natively, no WSL needed
- **Simpler mental model** — each task is a clean, isolated invocation
- **No session management** — no need to keep a tmux session alive
- **Portable** — works on any OS with Node.js and Claude Code

### Disadvantages

- **No conversation continuity** — each invocation starts fresh (mitigated by `CONTEXT.md`)
- **Startup overhead** — Claude Code initializes on each call (~2-5 seconds)
- **No streaming** — output is collected after completion, not streamed live
- **Stateless** — worker can't reference "what we discussed earlier" (use `CONTEXT.md` for this)

### Mitigations

The `CONTEXT.md` file is the key to making stateless invocations feel stateful. By updating it between tasks with project state, recent history, and preferences, the worker starts each invocation with full awareness — no cold starts in practice.

---

## Integration with Orchestrators

Any orchestrator (OpenClaw, custom scripts, other AI agents) can use `bridge.js` programmatically:

```javascript
const { spawnSync } = require('child_process');

const result = spawnSync('node', [
  'C:\\Users\\me\\.the-bridge\\bridge.js',
  'Task title',
  'Task description',
  'C:\\Users\\me\\Projects\\target-repo',
  '120',
  'code'
], { encoding: 'utf8' });

const taskResult = JSON.parse(result.stdout);
console.log(taskResult.status); // "completed" or "failed"
```

Or simply write JSON to `inbox/` and invoke `claude --print "check inbox"` directly — `bridge.js` is a convenience wrapper, not a requirement.
