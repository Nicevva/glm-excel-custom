import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('uninstall deletes only proven certificate trust and preserves recovery files on failure', { skip: process.platform !== 'win32' }, () => {
  const script = fileURLToPath(new URL('./uninstall-security.ps1', import.meta.url));
  const uninstall = fileURLToPath(new URL('../installer/uninstall.ps1', import.meta.url));
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', `& ([ScriptBlock]::Create([IO.File]::ReadAllText('${script.replaceAll("'", "''")}'))) -UninstallerPath '${uninstall.replaceAll("'", "''")}'`], { encoding: 'utf8', timeout: 120000 });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /UNINSTALL_SECURITY_TESTS_PASSED/);
});
