import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const source = readFileSync(new URL('../server.cjs', import.meta.url), 'utf8');
const tls = source.slice(source.indexOf('function tlsOptions()'), source.indexOf('\nfunction readAsset'));
function options(inSea, hasPfx) {
  const context = { inSea, CERTS: '/local/certs', PFX_PASS: 'localdev', join, existsSync: () => hasPfx,
    readFileSync: path => path, require: name => { assert.equal(name, 'node:os'); return { homedir: () => '/home/test' }; } };
  return vm.runInNewContext(`${tls};tlsOptions()`, context);
}
const balloon = source.slice(source.indexOf('function balloon('), source.indexOf('\nfunction recoverPort'));
test('login autostart never opens notification UI while manual launch still can', () => {
  for (const silent of [true, false]) {
    const calls = [];
    vm.runInNewContext(`${balloon};balloon('ready')`, { process: { argv: silent ? ['app.exe', '--autostart'] : ['app.exe'] }, execFileSync: (...args) => calls.push(args) });
    assert.equal(calls.length, silent ? 0 : 1);
  }
});
test('installed SEA refuses unrelated development certificates when its private key is absent', () => {
  assert.throws(() => options(true, false), /reinstall|重新安装/i);
});
test('local PFX is used by the packaged server', () => {
  const value = options(true, true);
  assert.equal(value.pfx, join('/local/certs', 'localhost.pfx'));
  assert.equal(value.passphrase, 'localdev');
});
test('development mode retains the explicit Office dev certificate fallback', () => {
  const value = options(false, false);
  assert.equal(value.cert, join('/home/test', '.office-addin-dev-certs', 'localhost.crt'));
});
