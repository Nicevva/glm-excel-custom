import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('installer options require explicit shared-key consent and preserve only startup preference', { skip: process.platform !== 'win32' }, () => {
  const helper = fileURLToPath(new URL('../installer/options.ps1', import.meta.url));
  assert.ok(existsSync(helper), 'Installer option policy and dialog are missing');
  const script = fileURLToPath(new URL('./install-options.ps1', import.meta.url));
  const command = `& ([ScriptBlock]::Create([IO.File]::ReadAllText('${script.replaceAll("'", "''")}'))) -HelperPath '${helper.replaceAll("'", "''")}'`;
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-STA', '-Command', command], { encoding: 'utf8', timeout: 120000 });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /INSTALL_OPTIONS_TESTS_PASSED/);
});
