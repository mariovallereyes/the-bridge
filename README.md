# The Bridge

**A file-based protocol for AI-to-AI task delegation using subscription-covered tools.**

---

## The Problem

AI orchestration platforms (like OpenClaw, n8n, custom agents) can coordinate powerful AI models — but API access costs money. Meanwhile, tools like Claude Code, GitHub Copilot, and Cursor are covered by existing subscriptions, but they're designed for human interaction, not programmatic access.

**The Bridge** closes this gap. It lets an orchestrator agent delegate tasks to a subscription-covered AI tool using nothing but the filesystem — no API calls, no tokens burned, no third-party harness detection.

## How It Works

```
┌─────────────┐       filesystem        ┌──────────────┐
│ Orchestrator │ ──── inbox/task.json ──→ │  Worker Agent │
│   (any AI)   │ ←── outbox/result.json ─ │ (Claude Code) │
└─────────────┘                          └──────────────┘
```

The bridge directory contains three key files the worker reads:

- **`CLAUDE.md`** — The static protocol contract (HOW to work)
- **`CONTEXT.md`** — Living context updated between tasks (WHO, WHY, preferences, history)
- **`inbox/*.json`** — Individual task instructions (WHAT to do)

### Flow

1. The orchestrator updates `CONTEXT.md` with current state (if needed)
2. The orchestrator writes a task file to `inbox/`
3. The orchestrator sends a keystroke to the worker's terminal ("check inbox")
4. The worker reads `CONTEXT.md` + the task, does the work, writes the result to `outbox/`
5. The orchestrator reads the result and continues

The worker agent operates inside a normal terminal session (tmux). Its project `CLAUDE.md` defines the protocol contract — what to watch for, how to respond, what format to use. From the worker's perspective, it's just a human asking it to do things.

## Key Properties

- **Zero API cost** — Uses subscription-covered tools only
- **Model agnostic** — Orchestrator can be any AI (Gemini, GPT, open-source, etc.)
- **File-based protocol** — No network calls, no webhooks, no servers
- **Structured I/O** — JSON in, JSON out. Machine-readable by design
- **Human-auditable** — Every task and result is a file you can read
- **Worker-agnostic** — Claude Code today, any terminal-based AI tomorrow
- **Living context** — `CONTEXT.md` gives the worker persistent awareness across tasks without memory

## Quick Start

→ See [docs/SETUP.md](docs/SETUP.md)

## Documentation

| Document | Audience | Description |
|----------|----------|-------------|
| [PRD](docs/PRD.md) | Everyone | Product requirements and design rationale |
| [Architecture](docs/ARCHITECTURE.md) | Engineers, Agents | System design and data flow |
| [Protocol](docs/PROTOCOL.md) | Engineers, Agents | The file protocol specification |
| [Agent Contract](docs/AGENT-CONTRACT.md) | Worker Agents | Template CLAUDE.md and contract design |
| [Orchestrator Guide](docs/ORCHESTRATOR-GUIDE.md) | Orchestrator Agents | How to dispatch and manage tasks |
| [Setup](docs/SETUP.md) | Humans | Step-by-step installation and configuration |
| [Security](docs/SECURITY.md) | Everyone | Threat model and safety considerations |

## Who Is This For?

- **AI power users** who run orchestration platforms and want to reduce API costs
- **Developers** building agentic systems that need to delegate to subscription tools
- **Anyone** who pays for Claude Code (or similar) and wants more value from that subscription

## License

MIT

---

*Built by humans and AIs who think paying twice for the same model is silly.*
