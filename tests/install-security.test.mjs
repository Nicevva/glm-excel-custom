import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('installation rotates locally generated trust and rolls back failed upgrades', { skip: process.platform !== 'win32' }, () => {
  const script = fileURLToPath(new URL('./install-security.ps1', import.meta.url));
  const installer = fileURLToPath(new URL('../installer/install.ps1', import.meta.url));
  const command = `& ([ScriptBlock]::Create([IO.File]::ReadAllText('${script.replaceAll("'", "''")}'))) -InstallerPath '${installer.replaceAll("'", "''")}'`;
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], { encoding: 'utf8', timeout: 120000 });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /INSTALL_SECURITY_TESTS_PASSED/);
});
