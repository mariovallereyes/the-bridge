# The Bridge

> **An open-source protocol for humans to organize task delegation to their own AI subscriptions. Through the filesystem, not through APIs.**
>
> Zero API cost. Zero dependencies. Just files on disk.

---

## Why?

AI providers are increasingly restricting third-party access to subscription-covered tools. If you pay for an interactive AI assistant (flat monthly fee, unlimited use), you can use it in its terminal, but your orchestrator agent can't. Your orchestrator has to pay API rates separately, for the same model you already have access to.

**The Bridge** fixes this. It lets any orchestrator agent delegate tasks to any subscription-covered terminal AI using nothing but the filesystem. No API calls, no tokens burned.

The key insight: terminal-based AI tools already read project instruction files and respond to natural language. That's already a protocol, just an informal one. The Bridge formalizes it with structured JSON input/output and a defined lifecycle.

*This project respects provider policies. The Bridge does not bypass APIs, intercept tokens, or harness third-party integrations. It organizes how humans use their own subscription tools through the terminal, as intended.*

---

## The Three Layers

Every Bridge instance separates concerns into three files:

| Layer | File | Updated | Purpose |
|-------|------|---------|---------|
| **Protocol** | `CLAUDE.md` | Rarely (at setup) | **HOW** to work — file formats, lifecycle, rules |
| **Context** | `CONTEXT.md` | Between tasks | **WHO + WHY** — projects, preferences, history |
| **Task** | `inbox/*.json` | Every task | **WHAT** to do — specific instructions |

The worker always knows the protocol, always has current context, and gets specific instructions per task. No cold starts. No guessing.

---

## How It Works

```
┌─────────────┐       filesystem        ┌─────────────────┐
│ Orchestrator │ ──── inbox/task.json ──→ │  Worker Agent    │
│   (any AI)   │ ←── outbox/result.json ─ │ (terminal-based) │
└─────────────┘                          └─────────────────┘
```

### Flow

1. Orchestrator updates `CONTEXT.md` with current state
2. Orchestrator writes a task JSON to `inbox/`
3. Orchestrator sends a keystroke to the worker's terminal (`"check inbox"`)
4. Worker reads `CONTEXT.md` + the task, does the work, writes result to `outbox/`
5. Orchestrator reads the result and continues

The worker runs inside a normal tmux session. From its perspective, it's just a human asking it to do things.

---

## Quick Example

**Send a task** — write to `inbox/task-001.json`:

```json
{
  "id": "task-001",
  "version": "0.1.0",
  "created_at": "2025-07-03T15:30:00Z",
  "type": "code",
  "title": "Fix email validation regex",
  "description": "The /api/users endpoint returns 500 when email contains '+'. Fix the regex in src/utils/validate.ts.",
  "working_directory": "~/Projects/my-app",
  "context": {
    "files": ["src/utils/validate.ts"],
    "constraints": ["Don't change the API response format"]
  },
  "expected_output": {
    "type": "code_change",
    "success_criteria": "POST /api/users with 'user+tag@example.com' returns 201"
  }
}
```

**Get the result** — read from `outbox/task-001.json`:

```json
{
  "id": "task-001",
  "version": "0.1.0",
  "completed_at": "2025-07-03T15:32:15Z",
  "duration_seconds": 135,
  "status": "completed",
  "result": {
    "summary": "Fixed email regex to allow '+' in local part",
    "files_changed": ["src/utils/validate.ts"],
    "tests_run": "npm test -- validate (3 passed, 0 failed)"
  },
  "error": null
}
```

That's it. JSON in, JSON out. Every task and result is a file you can read, audit, and archive.

---

## Key Properties

- **Zero API cost** — uses subscription-covered tools only
- **Model agnostic** — orchestrator can be any AI (or a shell script, or a human)
- **Worker agnostic** — works with any terminal-based AI that reads project instructions
- **File-based protocol** — no network calls, no webhooks, no servers
- **Structured I/O** — JSON in, JSON out, machine-readable by design
- **Human-auditable** — every task and result is a file on disk
- **Living context** — `CONTEXT.md` gives the worker persistent awareness across tasks
- **Resilient** — if either side crashes, files persist on disk for recovery

---

## Quick Start

> See **[docs/SETUP.md](docs/SETUP.md)** for step-by-step installation and configuration.

**TL;DR:**

```bash
# 1. Create the bridge directory
mkdir -p ~/.the-bridge/{inbox,outbox,active,archive,workspace,logs}

# 2. Copy the worker contract template
cp templates/CLAUDE.md ~/.the-bridge/CLAUDE.md
cp templates/CONTEXT.md ~/.the-bridge/CONTEXT.md

# 3. Start a tmux session and launch your AI tool
tmux new-session -d -s bridge -c ~/.the-bridge

# 4. Dispatch a task (one command)
./scripts/bridge.sh "Fix the login bug" "The login form doesn't submit on click" ~/Projects/my-app
```

`bridge.sh` writes the task JSON, triggers the worker, polls for the result, and prints it to stdout. One command, full round-trip.

---

## Windows / `--print` Mode

The default Bridge uses tmux for persistent terminal sessions — great on Mac/Linux, unavailable on Windows. The **`--print` mode** implementation replaces tmux with Claude Code's single-turn `--print` flag, using a Node.js dispatcher (`scripts/bridge.js`) that spawns a fresh `claude --print` process per task. Same protocol, same JSON format, no tmux dependency.

Works on any OS with Node.js and Claude Code installed. See **[docs/WINDOWS.md](docs/WINDOWS.md)** for setup, usage, architecture details, and trade-offs.

---

## Documentation

| Document | Audience | Description |
|----------|----------|-------------|
| [PRD](docs/PRD.md) | Everyone | Product requirements and design rationale |
| [Architecture](docs/ARCHITECTURE.md) | Engineers, Agents | System design and data flow |
| [Protocol](docs/PROTOCOL.md) | Engineers, Agents | The file protocol specification |
| [Agent Contract](docs/AGENT-CONTRACT.md) | Worker Agents | Template contract and contract design |
| [Orchestrator Guide](docs/ORCHESTRATOR-GUIDE.md) | Orchestrator Agents | How to dispatch and manage tasks |
| [Setup](docs/SETUP.md) | Humans | Step-by-step installation and configuration |
| [Windows](docs/WINDOWS.md) | Humans, Agents | Windows/`--print` mode setup and architecture |
| [Security](docs/SECURITY.md) | Everyone | Threat model and safety considerations |

---

## Who Is This For?

- **AI power users** who run orchestration platforms and want to stop paying twice for the same model
- **Developers** building agentic systems that need to delegate to subscription-covered tools
- **Tinkerers** who want to experiment with multi-agent setups without API costs
- **Anyone** who has a subscription AI tool sitting idle while their orchestrator burns tokens

---

## Contributing

Contributions are welcome. For small fixes, open a PR directly. For larger changes, please open an issue first to discuss the approach.

This is a protocol, not a framework — keep it simple.

---

## License

MIT

---

*Built by humans and AIs who think paying twice for the same model is silly.*
