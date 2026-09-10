import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const helper = fileURLToPath(new URL('../installer/certificate.ps1', import.meta.url));

test('certificate lifecycle isolates keys, rotates certificates and removes only owned trust', { skip: process.platform !== 'win32' }, () => {
  assert.ok(existsSync(helper), 'Per-install certificate lifecycle helper is missing');
  const script = fileURLToPath(new URL('./certificate-security.ps1', import.meta.url));
  const command = `& ([ScriptBlock]::Create([IO.File]::ReadAllText('${script.replaceAll("'", "''")}'))) -HelperPath '${helper.replaceAll("'", "''")}'`;
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], { encoding: 'utf8', timeout: 120000 });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /CERTIFICATE_SECURITY_TESTS_PASSED/);
});
