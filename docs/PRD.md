# Product Requirements Document — The Bridge

**Version:** 0.1.0-draft
**Status:** Design Phase
**Last Updated:** 2025-07-03

---

## 1. Executive Summary

The Bridge is a file-based protocol that enables an AI orchestrator agent to delegate tasks to a subscription-covered AI tool (like Claude Code) running in a terminal session. It uses the filesystem as a message queue and a tmux session as the interaction layer, eliminating the need for API calls or third-party harness integrations.

### 1.1 The Motivation

The AI tool landscape has split into two pricing models:

1. **API/token-based** — Pay per use. Scales with volume. Used by orchestration platforms.
2. **Subscription-based** — Flat monthly fee. Unlimited (within fair use). Used by interactive tools.

These two worlds don't talk to each other. If you have a $20/month Claude Pro subscription that covers Claude Code, and you also run an AI orchestrator, the orchestrator can't leverage your subscription — it must pay API rates separately for the same model.

The Bridge connects these worlds through the simplest possible interface: files on disk.

### 1.2 Core Insight

Claude Code (and similar tools) are designed to read project instructions from a markdown file (`CLAUDE.md`) and respond to natural language input in a terminal. This is already a protocol — just an informal one.

The Bridge formalizes it:
- **Contract** = a `CLAUDE.md` that tells the worker exactly how to behave (static protocol)
- **Context** = a `CONTEXT.md` that gives the worker situational awareness (living state)
- **Input** = a JSON file in a known directory (per-task instructions)
- **Output** = a JSON file in a known directory (structured results)
- **Trigger** = a keystroke in a tmux session

No hacking. No reverse engineering. No API interception. Just using the tool as designed, with conventions that happen to be machine-readable.

### 1.3 The Three Layers

Every Bridge instance separates concerns into three files:

| Layer | File | Changes | Purpose |
|-------|------|---------|---------|
| **Protocol** | `CLAUDE.md` | Rarely | HOW to work — file format, lifecycle, rules |
| **Context** | `CONTEXT.md` | Between tasks | WHO, WHY — projects, preferences, history, standing instructions |
| **Task** | `inbox/*.json` | Every task | WHAT to do — specific instructions for this unit of work |

This separation means the worker always knows the protocol (CLAUDE.md), always has current context (CONTEXT.md), and gets specific instructions per task (JSON). No cold starts. No guessing.

---

## 2. Problem Statement

### 2.1 User Pain Points

| Pain Point | Detail |
|-----------|--------|
| **Double payment** | Users pay for a Claude subscription AND API tokens when their orchestrator needs Claude |
| **Model lock-in** | Switching the orchestrator's model is expensive because it's tied to API billing |
| **Wasted subscription** | Claude Code sits idle while the orchestrator pays full API rates for the same model |
| **Harness restrictions** | Providers are increasingly blocking third-party tools from using subscription quotas |

### 2.2 The April 2025 Trigger

Anthropic announced that starting April 4, 2025, third-party harnesses (including OpenClaw) can no longer use Claude subscription limits. Users must pay API rates ("extra usage") for any third-party tool access. This affects every user running Claude through non-Anthropic interfaces.

The Bridge is a direct response to this shift.

---

## 3. Target Users

### 3.1 Primary

- **AI orchestrator users** — People running OpenClaw, n8n, LangChain, AutoGPT, or custom agent setups who also have subscriptions to interactive AI tools
- **Cost-conscious power users** — Developers who want maximum capability per dollar

### 3.2 Secondary

- **AI hobbyists** — Tinkerers who want to experiment with multi-agent setups without API costs
- **Teams** — Small teams where one subscription covers Claude Code and an orchestrator needs to delegate to it

---

## 4. Requirements

### 4.1 Functional Requirements

#### FR-1: File-Based Task Protocol
- The system MUST use filesystem files (JSON) as the sole communication channel between orchestrator and worker
- Task files MUST be written to a designated `inbox/` directory
- Result files MUST be written to a designated `outbox/` directory
- The protocol MUST NOT require network calls, webhooks, or HTTP servers

#### FR-2: Terminal Interaction via tmux
- The worker agent MUST run inside a tmux session
- The orchestrator MUST be able to send keystrokes to the worker's tmux pane
- The orchestrator MUST be able to read the worker's tmux pane output
- The worker MUST NOT require any modification or patching

#### FR-3: Structured Contract (CLAUDE.md) and Living Context (CONTEXT.md)
- Each Bridge instance MUST include a `CLAUDE.md` (or equivalent) that defines the worker's behavior
- The contract MUST specify: where to find tasks, how to read them, what format to output, where to write results
- Each Bridge instance SHOULD include a `CONTEXT.md` that provides living context
- `CONTEXT.md` MUST be readable by the worker at the start of every task
- `CONTEXT.md` SHOULD be updated by the orchestrator between task cycles
- `CONTEXT.md` MUST include: dispatcher identity, active projects, preferences, recent task history
- Both files MUST be human-readable and agent-readable
- `CLAUDE.md` + `CONTEXT.md` MUST be the ONLY configuration needed on the worker side

#### FR-4: Task Lifecycle
- Tasks MUST have unique identifiers
- Tasks MUST transition through defined states: `pending` → `running` → `completed` | `failed` | `timeout`
- The orchestrator MUST be able to poll for task completion
- Completed tasks MUST include structured results (status, output, files changed, errors)

#### FR-5: Multi-Project Support
- The worker MUST be able to operate on files outside the bridge directory
- Task definitions MUST support specifying a target working directory
- The bridge directory itself is infrastructure, not the workspace

#### FR-6: Timeout and Error Handling
- Tasks MUST support configurable timeouts
- The orchestrator MUST detect stalled tasks (worker stopped responding)
- Failed tasks MUST include error information in the result file
- The system MUST NOT leave orphaned tasks without eventual resolution

### 4.2 Non-Functional Requirements

#### NFR-1: Zero Installation (Worker Side)
- The worker side requires ONLY a `CLAUDE.md` file — no scripts, no daemons, no dependencies
- Any terminal-based AI tool that reads project instructions can be a worker

#### NFR-2: Human Auditability
- Every task and result MUST be stored as a human-readable file
- A human MUST be able to inspect the full task history by reading the filesystem
- No binary formats, no databases

#### NFR-3: Security Boundary
- The bridge directory MUST NOT contain credentials, tokens, or secrets
- The worker agent MUST NOT be asked to handle authentication
- Task files MUST NOT include sensitive data beyond what's needed for the task
- The protocol MUST document security considerations explicitly

#### NFR-4: Portability
- The protocol MUST work on macOS, Linux, and WSL
- The only system dependency is tmux
- The protocol MUST NOT be tied to any specific orchestrator or worker

#### NFR-5: Graceful Degradation
- If the worker crashes, pending tasks remain in `inbox/` for retry
- If the orchestrator crashes, results remain in `outbox/` for later pickup
- No data loss from either side going down

---

## 5. Out of Scope (v1)

- **Real-time streaming** — v1 is request/response only (no live output streaming)
- **Multi-worker** — v1 supports one worker per bridge instance (scale horizontally with multiple bridges)
- **GUI** — No graphical interface; file and terminal only
- **Authentication between agents** — Trust is implicit (same machine, same user, same filesystem)
- **Auto-spawning workers** — The human starts Claude Code; the orchestrator doesn't launch it

---

## 6. Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                        Host Machine                          │
│                                                              │
│  ┌──────────────┐                      ┌──────────────────┐  │
│  │ Orchestrator  │                      │  tmux session     │  │
│  │ (any AI agent)│                      │  ┌──────────────┐ │  │
│  │               │   1. write task      │  │ Claude Code   │ │  │
│  │               │ ────────────────→    │  │               │ │  │
│  │               │   (inbox/task.json)  │  │ reads CLAUDE.md│ │  │
│  │               │                      │  │ reads inbox/  │ │  │
│  │               │   2. send keystroke  │  │ does work     │ │  │
│  │               │ ────────────────→    │  │ writes outbox/│ │  │
│  │               │   ("new task")       │  │               │ │  │
│  │               │                      │  └──────────────┘ │  │
│  │               │   4. read result     │                    │  │
│  │               │ ←────────────────    │                    │  │
│  │               │   (outbox/result)    │                    │  │
│  └──────────────┘                      └──────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │              the-bridge/ (filesystem)                  │    │
│  │  inbox/          outbox/         archive/   CLAUDE.md │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

→ Full details: [ARCHITECTURE.md](ARCHITECTURE.md)

---

## 7. Success Criteria

| Metric | Target |
|--------|--------|
| API cost for delegated tasks | $0 (subscription-covered) |
| Task round-trip time | < 60s for simple tasks |
| Setup time for new user | < 15 minutes |
| Worker-side dependencies | 0 (just CLAUDE.md) |
| Protocol reliability | No lost tasks across normal usage |

---

## 8. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Provider blocks terminal automation | Low | High | Protocol uses standard terminal input; indistinguishable from human. No API fingerprint. |
| Worker ignores CLAUDE.md instructions | Medium | Medium | Contract design section covers prompt engineering for reliability. Test and iterate. |
| tmux dependency limits portability | Low | Low | tmux is available on all target platforms. Alternative: screen, or direct PTY. |
| File protocol too slow for real-time | Medium | Low | Explicitly out of scope for v1. Adequate for task delegation (not chat). |
| Subscription ToS changes | Medium | Medium | Protocol is generic — works with any terminal AI tool, not just Claude Code. |

---

## 9. Milestones

| Phase | Deliverable | Description |
|-------|------------|-------------|
| **Phase 0** | Documentation | Complete docs (this PRD, architecture, protocol spec, guides) |
| **Phase 1** | Reference Implementation | Working bridge with Claude Code as worker |
| **Phase 2** | Orchestrator Skill | OpenClaw skill that uses the bridge natively |
| **Phase 3** | Multi-Worker | Support for multiple workers and routing |
| **Phase 4** | Community Release | Clean repo, examples, templates for other orchestrators |

---

## 10. Open Questions

1. **Should the orchestrator poll `outbox/` or watch for filesystem events?** Polling is simpler and more portable. `fswatch`/`inotify` is faster but adds a dependency.

2. **What happens when Claude Code enters a multi-turn conversation?** The CLAUDE.md contract needs to handle this — either force single-turn (do task, write result, stop) or define a continuation protocol.

3. **Should task files support binary attachments?** v1 says no — reference file paths instead. Reconsider if image/audio tasks become common.

4. **How to handle Claude Code's "permission" prompts?** Claude Code sometimes asks for confirmation before file operations. The CLAUDE.md should instruct it to use `--dangerously-skip-permissions` or the `bypassPermissions` flag, but this requires the human to start it that way.

5. **Rate limiting?** Should the protocol enforce a max tasks-per-minute to avoid looking automated? Probably wise but needs testing.

---

*This document will be updated as design decisions are finalized.*
