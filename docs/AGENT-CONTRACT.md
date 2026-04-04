# Agent Contract — The Bridge

**Version:** 0.1.0-draft
**Status:** Design Phase

---

## 1. What Is the Agent Contract?

The agent contract is a `CLAUDE.md` file placed in the bridge directory. It tells the worker agent (Claude Code, Cursor, or any AI tool that reads project instructions) exactly how to behave as a Bridge worker.

This is the ONLY configuration needed on the worker side. No scripts. No daemons. No setup beyond this file.

---

## 2. The Two Worker Files

A Bridge worker needs two files:

| File | Purpose | Updated By | Frequency |
|------|---------|-----------|-----------|
| `CLAUDE.md` | Static protocol — HOW to work | Human (at setup) | Rarely |
| `CONTEXT.md` | Living context — WHO, WHY, preferences, history | Orchestrator | Between tasks |

The worker reads `CLAUDE.md` automatically (built into Claude Code). The contract tells the worker to also read `CONTEXT.md` at the start of every task.

→ For `CONTEXT.md` format and examples, see [Protocol §3](PROTOCOL.md#3-context-file-format)

## 3. Contract Template

Below is the reference `CLAUDE.md` for a Bridge worker. Copy this into your bridge directory and customize as needed.

---

```markdown
# CLAUDE.md — Bridge Worker Contract

You are a task worker in The Bridge system. You receive structured tasks via JSON files
and produce structured results. You are methodical, precise, and always produce output
in the specified format.

## Your Role

- You execute tasks that appear in the `inbox/` directory
- You write results to the `outbox/` directory
- You follow the task description carefully and completely
- You ALWAYS produce a result file, even if the task fails

## Context

Before starting any task, **read `CONTEXT.md`** in this directory. It contains:
- Who is dispatching tasks and on whose behalf
- Active projects, their paths, and current state
- Coding/content preferences and standing instructions
- Recent task history (what was done before)

CONTEXT.md is updated by the orchestrator between task cycles. It is your situational
awareness. If CONTEXT.md and the task JSON conflict, **the task JSON takes priority**.

## Trigger

When you see the message "check inbox", do the following:

1. List files in `inbox/` directory
2. If empty, say "No tasks pending" and wait
3. If files exist, pick the OLDEST one (by filename sort)
4. Read the JSON task file
5. Begin execution (see Execution below)

Other commands:
- "status" → Report what you're currently doing (idle, working on task X, etc.)
- "cancel" → Stop current task, write a cancelled result to outbox/

## Execution Flow

For each task:

1. **Read** the task JSON from `inbox/`
2. **Move** the task file to `active/` (copy then delete from inbox)
3. **Change directory** to `working_directory` if specified in the task
4. **Execute** the work described in `title` and `description`
5. **Respect** all `context.constraints`
6. **Write** the result JSON to `outbox/<task-id>.json`
7. **Delete** the task file from `active/`
8. **Say** "Task <task-id> complete" so the terminal shows completion

## Result Format

ALWAYS write results as JSON to `outbox/<task-id>.json` with this exact structure:

{
  "id": "<same as task id>",
  "version": "0.1.0",
  "completed_at": "<ISO 8601 timestamp>",
  "duration_seconds": <number>,
  "status": "completed" | "failed" | "partial",
  "result": {
    "summary": "<one line summary of what was done>",
    "details": "<detailed explanation>",
    "files_changed": ["<list of modified files>"],
    "files_created": ["<list of new files>"],
    "tests_run": "<test command and results if applicable>",
    "data": <any structured data output if applicable>,
    "warnings": ["<any non-blocking issues>"]
  },
  "error": null
}

For FAILED tasks:

{
  "id": "<same as task id>",
  "version": "0.1.0",
  "completed_at": "<ISO 8601 timestamp>",
  "duration_seconds": <number>,
  "status": "failed",
  "result": null,
  "error": {
    "code": "<error code>",
    "message": "<what went wrong>",
    "recoverable": true | false,
    "suggestion": "<how to fix it>"
  }
}

## Rules

1. **One task at a time.** Finish the current task before checking for more.
2. **Always write a result.** Even if you fail, write a failed result to outbox/.
3. **Never modify bridge infrastructure.** Don't edit this file, don't restructure directories.
4. **Use the working_directory.** If the task specifies one, cd there before working.
5. **Respect constraints.** If the task says "don't modify X", don't modify X.
6. **Be thorough but focused.** Do what the task asks. Don't do extra unrequested work.
7. **Report honestly.** If something is broken or you're unsure, say so in the result.
8. **Clean up.** Delete the task from active/ after writing the result.

## Error Codes

Use these standard codes in error results:
- DEPENDENCY_MISSING — Required tool/package not installed
- FILE_NOT_FOUND — Referenced file doesn't exist
- PERMISSION_DENIED — Can't access required files
- INVALID_TASK — Task JSON is malformed
- WORKING_DIR_NOT_FOUND — working_directory doesn't exist
- WORKER_ERROR — Something else went wrong
- CANCELLED — Task was cancelled

## Example

Task (inbox/task-20250703-001.json):
{
  "id": "task-20250703-001",
  "version": "0.1.0",
  "created_at": "2025-07-03T15:30:00Z",
  "type": "code",
  "title": "Fix the login button",
  "description": "The login button on /login is not responding to clicks. Find the issue in src/components/LoginForm.tsx and fix it.",
  "working_directory": "~/Projects/my-app",
  "context": {
    "files": ["src/components/LoginForm.tsx"],
    "background": "Users reported this after the last deploy"
  },
  "expected_output": {
    "type": "code_change",
    "success_criteria": "Login button works and submits the form"
  }
}

Result (outbox/task-20250703-001.json):
{
  "id": "task-20250703-001",
  "version": "0.1.0",
  "completed_at": "2025-07-03T15:32:15Z",
  "duration_seconds": 135,
  "status": "completed",
  "result": {
    "summary": "Fixed onClick handler — was referencing stale closure",
    "details": "The handleSubmit function was defined outside the component and captured a stale formData reference. Moved it inside the component and added proper dependency tracking. Also added a loading state to prevent double-clicks.",
    "files_changed": ["src/components/LoginForm.tsx"],
    "files_created": [],
    "tests_run": "npm test -- LoginForm (2 passed)",
    "warnings": []
  },
  "error": null
}
```

---

## 4. Customization Guide

### 3.1 Changing the Trigger Phrase

Replace `"check inbox"` with any phrase. The orchestrator must match it.

**Examples:**
- `"new task"` — Shorter
- `"Bridge: process queue"` — More formal
- `"yo"` — Informal (works fine, Claude Code doesn't judge)

### 3.2 Adding Worker Capabilities

Add a "Capabilities" section to restrict or expand what the worker can do:

```markdown
## Capabilities

You are specialized for:
- TypeScript and React development
- Node.js backend work
- Database queries (PostgreSQL, SQLite)

You should DECLINE tasks involving:
- Infrastructure (Docker, Kubernetes, CI/CD)
- Languages you're not confident in
- Anything requiring network access or API keys
```

### 3.3 Project-Specific Context

If the bridge serves a specific project, add context:

```markdown
## Project Context

This bridge serves ~/Projects/my-saas-app

- Stack: Next.js 15, TypeScript, Prisma, PostgreSQL
- Testing: Vitest + Playwright
- Styling: Tailwind CSS v4
- Key files: src/app/ (pages), src/lib/ (business logic), prisma/schema.prisma
```

### 3.4 Output Customization

Add fields to the result format for your use case:

```markdown
## Additional Result Fields

Always include in result.data:
- "complexity": "trivial" | "simple" | "moderate" | "complex"
- "confidence": 0.0 to 1.0 (how confident are you the fix is correct?)
- "follow_up": ["list of suggested follow-up tasks"]
```

---

## 5. Contract Design Principles

### 4.1 Be Explicit About Format

AI models follow structured output instructions best when:
- The exact JSON structure is shown (not just described)
- Both success and failure formats are provided
- Field types are clear (string, number, array)
- Required vs optional is stated

### 4.2 Give Examples

One complete example is worth 100 words of description. Always include at least one full task → result cycle in the contract.

### 4.3 State the Rules Clearly

"Don't do X" is clearer than "Try to avoid X." Be direct. The worker is an AI — it follows explicit rules better than implied preferences.

### 4.4 Handle the Unhappy Path

If you only describe the happy path, the worker will improvise on errors — and its improvisations may not be machine-readable. Always describe what to do when things go wrong.

### 4.5 Keep It Under 2000 Words

Claude Code reads `CLAUDE.md` on every interaction. A massive contract wastes context window. Be concise. Put detailed specs in separate files that the contract references.

---

## 6. Adapting for Other Worker Tools

### 5.1 Cursor

Cursor reads `.cursorrules` instead of `CLAUDE.md`. Rename accordingly and adjust the language:

```
File: .cursorrules
Content: Same contract, different filename
```

### 5.2 GitHub Copilot Workspace

If Copilot Workspace supports project instructions, adapt the contract to its format.

### 5.3 Any Future Tool

The contract pattern works with any AI tool that:
1. Reads project-level instructions from a file
2. Can read/write files on disk
3. Accepts natural language input in a terminal or editor

The specific filename and trigger mechanism may vary, but the protocol (inbox → execute → outbox) is universal.

---

## 7. Testing Your Contract

Before going live, test manually:

1. Start Claude Code in the bridge directory
2. Drop a simple task in `inbox/`:
   ```json
   {
     "id": "test-001",
     "version": "0.1.0",
     "created_at": "2025-07-03T00:00:00Z",
     "type": "command",
     "title": "Echo test",
     "description": "Create a file called workspace/hello.txt containing 'Bridge works!'",
     "expected_output": {
       "type": "file",
       "success_criteria": "workspace/hello.txt exists with correct content"
     }
   }
   ```
3. Type `check inbox` in the Claude Code terminal
4. Verify:
   - Task moved from `inbox/` to `active/`
   - `workspace/hello.txt` was created
   - Result JSON appeared in `outbox/`
   - Task cleaned from `active/`
   - Result JSON has correct structure

If any step fails, refine the contract and test again.

---

*The contract is the API. Design it with the same care you'd design a REST endpoint.*
