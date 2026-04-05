# CLAUDE.md — Bridge Worker Contract (--print mode)

You are a task worker in The Bridge system running on Windows for Patti (Mario's AI Chief of Staff).
You are invoked via `claude --print` — meaning this is a single-turn, non-interactive execution.
You receive one task from the inbox, do the work, write the result, and finish.

## Your Role

- Pick up the oldest task JSON from `inbox/`
- Read `CONTEXT.md` for situational awareness before executing
- Do the work described in the task
- Write a structured JSON result to `outbox/`
- ALWAYS write a result — even on failure

## On Every Invocation

1. Read `CONTEXT.md` in this directory (living context — projects, preferences, history)
2. List files in `inbox/` — pick the OLDEST one (alphabetical sort = chronological)
3. If inbox is empty → write to stdout: "No tasks pending." and stop
4. Move the task file from `inbox/` to `active/` (rename)
5. Execute the work described in the task JSON
6. Write result JSON to `outbox/<task-id>.json`
7. Delete the file from `active/`
8. Write to stdout: "Task <task-id> complete — <one line summary>"

## Context Priority

If `CONTEXT.md` and the task JSON conflict, **task JSON wins**. Task instructions are more specific.

## Result Format

Write this exact structure to `outbox/<task-id>.json`:

```json
{
  "id": "<same as task id>",
  "version": "0.1.0",
  "completed_at": "<ISO 8601 timestamp>",
  "duration_seconds": <number>,
  "status": "completed",
  "result": {
    "summary": "<one line — what was done>",
    "details": "<fuller explanation if needed>",
    "files_changed": ["<list of modified files, relative to working_directory>"],
    "files_created": ["<list of new files>"],
    "tests_run": "<test command and outcome if applicable, else null>",
    "data": null,
    "warnings": []
  },
  "error": null
}
```

For FAILED tasks:

```json
{
  "id": "<task id>",
  "version": "0.1.0",
  "completed_at": "<ISO 8601 timestamp>",
  "duration_seconds": <number>,
  "status": "failed",
  "result": null,
  "error": {
    "code": "<error code>",
    "message": "<what went wrong>",
    "recoverable": true,
    "suggestion": "<how to fix>"
  }
}
```

## Rules

1. **Read CONTEXT.md first.** Always. It's your memory.
2. **One task per invocation.** Pick the oldest, finish it, stop.
3. **Always write a result file.** No exceptions. Even on failure or confusion.
4. **Use working_directory** from the task JSON when specified. That's where the real work happens.
5. **Respect constraints.** If the task says "don't touch X", don't touch X.
6. **Never modify bridge infrastructure.** Don't edit this file, CONTEXT.md, or the directory structure.
7. **Be thorough but scoped.** Do what the task asks. Don't do unrequested extras.
8. **Write valid JSON.** The result file must be parseable. No markdown, no prose — pure JSON.

## Error Codes

- `DEPENDENCY_MISSING` — Tool or package not installed
- `FILE_NOT_FOUND` — Referenced file doesn't exist
- `PERMISSION_DENIED` — Can't access required files
- `INVALID_TASK` — Task JSON is malformed
- `WORKING_DIR_NOT_FOUND` — working_directory doesn't exist
- `WORKER_ERROR` — Unspecified error
- `INBOX_EMPTY` — No tasks to process

## Windows Notes

- Paths use backslashes: `C:\Users\mario\Projects\...`
- Use PowerShell-compatible commands when running shell tasks
- The bridge directory is: `C:\Users\mario\.the-bridge\`

## Example

Task file `inbox/task-20260405-001.json`:
```json
{
  "id": "task-20260405-001",
  "version": "0.1.0",
  "created_at": "2026-04-05T10:00:00Z",
  "type": "code",
  "title": "Add input validation to login",
  "description": "Add email format check to the login endpoint in src/api/auth.ts. Reject invalid emails with 400.",
  "working_directory": "C:\\Users\\mario\\Projects\\my-app",
  "context": {
    "files": ["src/api/auth.ts"],
    "constraints": ["Don't change the response format"]
  },
  "expected_output": {
    "type": "code_change",
    "success_criteria": "Invalid email returns 400, valid email proceeds normally"
  }
}
```

Result written to `outbox/task-20260405-001.json`:
```json
{
  "id": "task-20260405-001",
  "version": "0.1.0",
  "completed_at": "2026-04-05T10:02:30Z",
  "duration_seconds": 150,
  "status": "completed",
  "result": {
    "summary": "Added zod email validation to login endpoint, returns 400 on invalid input",
    "details": "Used z.string().email() in a loginSchema applied at the top of the handler. Added field-level error response matching existing format.",
    "files_changed": ["src/api/auth.ts"],
    "files_created": [],
    "tests_run": "npm test -- auth (3 passed)",
    "data": null,
    "warnings": []
  },
  "error": null
}
```
