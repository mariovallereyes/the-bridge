# Implementation Checklist: ACP-Bridge Hybrid Layer

**Reference:** [Hybrid-Architecture-ACP-Bridge.md](Hybrid-Architecture-ACP-Bridge.md)
**Last Updated:** 2026-04-06

---

## Phase 1: Foundation (DONE)

- [x] Bridge protocol v0.1.0 (CLAUDE.md, CONTEXT.md, inbox/outbox lifecycle)
- [x] bridge.sh one-liner dispatch + poll
- [x] dispatch.sh, poll.sh, archive.sh, status.sh helper scripts
- [x] Bridge skill for OpenClaw (skills/the-bridge/SKILL.md)
- [x] AGENTS.md mandatory routing check on every message
- [x] SOUL.md cost discipline section
- [x] Public repo at github.com/mariovallereyes/the-bridge
- [x] Full documentation suite (PRD, Architecture, Protocol, Agent Contract, Orchestrator Guide, Setup, Security)

## Phase 2: ACP-Aware Dispatch (CURRENT)

- [x] bridge-acp.sh -- extended dispatch with metadata support (agent, session_key, task type, constraints, context files, background)
- [x] relay.sh -- result parser that formats human-readable output from result JSON
- [x] BRIDGE_OUTPUT_MODE=relay for inline result formatting
- [x] Hybrid architecture doc (Hybrid-Architecture-ACP-Bridge.md)
- [x] Implementation checklist (this file)
- [x] Update PROTOCOL.md with metadata extension spec (section 3.3)
- [x] Update README doc table with new docs
- [x] relay.sh tested with real result files (works)
- [x] bridge-acp.sh tested: task JSON generation verified (valid JSON with metadata). Full round-trip requires a separate worker session (cannot self-dispatch).
- [x] Update Orchestrator Guide with bridge-acp.sh usage examples (section 3.1 + 3.2, env var table, relay.sh examples)
- [x] Smoke tests passed: task JSON generation with metadata, relay.sh with 4 result types (completed/failed/partial/data), tmux session detection, all scripts executable with valid shebangs
- [ ] Full round-trip test with external dispatch (requires separate worker session -- cannot self-test)

## Phase 3: Structured Result Relay (CURRENT)

- [x] context-update.sh -- auto-appends completed tasks to CONTEXT.md task history (keeps last 10, updates date header, removes placeholder)
- [x] health.sh -- worker health check (tmux alive, orphans in active/, stale results, JSON and human output modes)
- [x] test-e2e.sh -- end-to-end test harness with mock worker (12 tests)
- [x] E2E tests: 12/12 passed
- [x] openclaw-dispatch.sh -- full integration script: preflight -> dispatch -> relay -> context-update -> task-registry. One exec call for OpenClaw agents.
- [x] Preflight health check integrated (health.sh called before dispatch, exits 2 if unhealthy)
- [x] Post-completion CONTEXT.md update integrated (context-update.sh called automatically)
- [x] Task registry update hooks integrated (auto-detects log-task.sh, logs done/failed)
- [ ] Agent appends significant tasks to daily memory file (agent-side, not script-side)

## Phase 4: OpenClaw Task Integration

- [ ] Bridge dispatches create OpenClaw background tasks (openclaw tasks)
- [ ] Bridge results trigger task completion notifications
- [ ] Task Flow support for multi-Bridge sequences (research -> code -> test)
- [ ] metadata.session_key enables result delivery to any session
- [ ] Verify background task lifecycle matches Bridge task lifecycle

## Phase 5: Context Automation

- [ ] CONTEXT.md auto-updated after each completed task
- [ ] Bridge worker health monitored via cron (tmux session check)
- [ ] Auto-archive completed results on schedule
- [ ] Stale task detection (orphans in active/) via cron alert
- [ ] qmd reindex Bridge docs/workspace on schedule

## Phase 6: Multi-Bridge Routing

- [ ] Orchestrator routes to Patti's bridge (coding/analysis) vs Marko's bridge (marketing)
- [ ] Bridge capability metadata per worker
- [ ] Load-aware routing (check if worker has active task before dispatching)
- [ ] OUT_OF_SCOPE error triggers automatic re-routing

---

## Script Reference

| Script | Purpose | Phase |
|--------|---------|-------|
| bridge.sh | Simple dispatch + poll (any orchestrator) | 1 |
| bridge-acp.sh | ACP-aware dispatch with metadata + relay mode | 2 |
| relay.sh | Parse result JSON into human-readable summary | 2 |
| dispatch.sh | Low-level dispatch only (no poll) | 1 |
| poll.sh | Low-level poll only (no dispatch) | 1 |
| archive.sh | Move completed results to archive/ | 1 |
| status.sh | Bridge dashboard (inbox/active/outbox counts) | 1 |
| openclaw-dispatch.sh | Full integration: preflight + dispatch + relay + context + registry | 3 |
| context-update.sh | Append completed task to CONTEXT.md history | 3 |
| health.sh | Worker health check (tmux, orphans, stale results) | 3 |
| test-e2e.sh | End-to-end test harness with mock worker (12 tests) | 3 |

## Environment Variables (bridge-acp.sh)

| Variable | Default | Purpose |
|----------|---------|---------|
| BRIDGE_DIR | ~/.the-bridge | Bridge directory |
| BRIDGE_TMUX_SESSION | bridge | tmux session name |
| BRIDGE_TRIGGER | check inbox | Trigger phrase |
| BRIDGE_AGENT | openclaw | Dispatching agent name |
| BRIDGE_SESSION_KEY | (empty) | OpenClaw session key for result relay |
| BRIDGE_TASK_TYPE | composite | Task type |
| BRIDGE_CONSTRAINTS | (empty) | JSON array of constraint strings |
| BRIDGE_CONTEXT_FILES | (empty) | JSON array of file paths |
| BRIDGE_BACKGROUND | (empty) | Background info string |
| BRIDGE_OUTPUT_MODE | json | "json" or "relay" (human-readable) |

---

*Track progress here. Check off items as they ship.*
