#!/usr/bin/env node
/**
 * bridge.js — The Bridge dispatcher (Windows, --print mode)
 *
 * Usage:
 *   node bridge.js <title> <description> [working_dir] [timeout_sec] [type]
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const BRIDGE_DIR = path.join(process.env.USERPROFILE, '.the-bridge');
const INBOX  = path.join(BRIDGE_DIR, 'inbox');
const OUTBOX = path.join(BRIDGE_DIR, 'outbox');
const ACTIVE = path.join(BRIDGE_DIR, 'active');

const TITLE       = process.argv[2] || 'Untitled task';
const DESCRIPTION = process.argv[3] || 'No description provided';
const WORKING_DIR = (process.argv[4] && process.argv[4] !== '.') ? process.argv[4] : path.join(BRIDGE_DIR, 'workspace');
const TIMEOUT_SEC = parseInt(process.argv[5]) || 120;
const TASK_TYPE   = process.argv[6] || 'code';

function generateTaskId() {
  const ymd = new Date().toISOString().split('T')[0].replace(/-/g, '');
  const num = String(Math.floor(Math.random() * 1000)).padStart(3, '0');
  return `task-${ymd}-${num}`;
}

function writeTask(taskId, data) {
  const tmp  = path.join(INBOX, `.${taskId}.tmp.json`);
  const dest = path.join(INBOX, `${taskId}.json`);
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2), 'utf8');
  fs.renameSync(tmp, dest);
  return dest;
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function pollOutbox(taskId, timeoutSec) {
  const resultPath = path.join(OUTBOX, `${taskId}.json`);
  const deadline = Date.now() + timeoutSec * 1000;

  while (Date.now() < deadline) {
    if (fs.existsSync(resultPath)) {
      return JSON.parse(fs.readFileSync(resultPath, 'utf8'));
    }
    sleep(2000);
  }
  return { id: taskId, status: 'timeout', message: `No result after ${timeoutSec}s` };
}

function main() {
  // Ensure dirs exist
  for (const d of [INBOX, OUTBOX, ACTIVE]) {
    if (!fs.existsSync(d)) fs.mkdirSync(d, { recursive: true });
  }

  const taskId = generateTaskId();
  const taskData = {
    id: taskId,
    version: '0.1.0',
    created_at: new Date().toISOString(),
    type: TASK_TYPE,
    title: TITLE,
    description: DESCRIPTION,
    working_directory: WORKING_DIR,
    timeout_seconds: TIMEOUT_SEC,
    context: { files: [], constraints: [] },
    expected_output: { type: 'code_change', success_criteria: 'Task completed successfully' }
  };

  writeTask(taskId, taskData);
  process.stderr.write(`[bridge] Task ${taskId} written to inbox\n`);
  process.stderr.write(`[bridge] Invoking Claude Code...\n`);

  // Run claude --print from the bridge directory
  // CLAUDE.md is auto-loaded because cwd = BRIDGE_DIR
  const result = spawnSync('claude', [
    '--print',
    '--dangerously-skip-permissions',
    'check inbox'
  ], {
    cwd: BRIDGE_DIR,
    stdio: ['ignore', 'pipe', 'pipe'],
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024
  });

  if (result.stderr) process.stderr.write(result.stderr);
  if (result.stdout) process.stderr.write(`[claude output]\n${result.stdout}\n`);

  // Poll outbox
  process.stderr.write(`[bridge] Polling outbox for result...\n`);
  const taskResult = pollOutbox(taskId, TIMEOUT_SEC);

  // Print result to stdout as JSON
  console.log(JSON.stringify(taskResult, null, 2));

  // Archive if completed
  if (taskResult.status && taskResult.status !== 'timeout') {
    const dateStr = new Date().toISOString().split('T')[0];
    const archiveDir = path.join(BRIDGE_DIR, 'archive', dateStr);
    if (!fs.existsSync(archiveDir)) fs.mkdirSync(archiveDir, { recursive: true });

    const resultFile = path.join(OUTBOX, `${taskId}.json`);
    if (fs.existsSync(resultFile)) {
      fs.renameSync(resultFile, path.join(archiveDir, `${taskId}.result.json`));
    }
  }
}

main();
