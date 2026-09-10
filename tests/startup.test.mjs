import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readFileSync, existsSync } from 'node:fs';

const startup = fileURLToPath(new URL('../installer/startup.ps1', import.meta.url));

test('startup functions ship with PS5.1-compatible UTF-8 BOM', () => {
  assert.ok(existsSync(startup), 'startup.ps1 must provide the auto-start API');
  assert.deepEqual([...readFileSync(startup).subarray(0, 3)], [0xef, 0xbb, 0xbf]);
});

test('auto-start state, ownership and rollback use only the mocked Registry provider', { skip: process.platform !== 'win32' }, () => {
  const script = fileURLToPath(new URL('./startup.ps1', import.meta.url));
  const quote = value => `'${value.replaceAll("'", "''")}'`;
  const command = `& ([ScriptBlock]::Create([IO.File]::ReadAllText(${quote(script)}))) -StartupPath ${quote(startup)}`;
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], { encoding: 'utf8', timeout: 30000 });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /STARTUP_TESTS_PASSED: \d+/);
});
