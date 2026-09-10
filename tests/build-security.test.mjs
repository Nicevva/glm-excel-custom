import test from "node:test";
import assert from "node:assert/strict";
import {
  appendFileSync, copyFileSync, existsSync, mkdirSync, mkdtempSync,
  readFileSync, readdirSync, rmSync, writeFileSync,
} from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repository = fileURLToPath(new URL("../", import.meta.url));
const payload = [
  "AIExcelCustom.exe", "install.ps1", "uninstall.ps1", "launch.vbs",
  "manifest.template.xml", "app.ico", "certificate.ps1",
];

function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), "glm-build-security-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
}

function put(root, path, value = "not real secret material") {
  const target = join(root, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, value);
  return target;
}

function sedValue(text, key) {
  const values = [...text.matchAll(new RegExp(`^${key}=(.*)$`, "gm"))]
    .map(match => match[1].trim()).filter(value => !value.startsWith("%"));
  assert.equal(values.length, 1, `one literal ${key} is required`);
  return values[0];
}

function sedFiles(text) {
  return [...text.matchAll(/^FILE\d+="([^"]+)"\r?$/gm)].map(match => match[1]);
}

// Break caught: arbitrary public files (including backup/private inputs) enter SEA.
test("SEA includes runtime static assets, not certificates, backups or developer inputs", t => {
  const root = scratch(t);
  mkdirSync(join(root, "installer"));
  copyFileSync(join(repository, "installer/gen-sea-config.mjs"), join(root, "installer/gen-sea-config.mjs"));
  const allowed = ["taskpane.html", "commands.html", "assets/app.js", "assets/app.css", "assets/icon.png", "assets/logo.svg", "assets/font.woff", "assets/font.woff2"];
  const privateFiles = [
    "assets/app.js.orig", "localhost.pfx", "localhost.crt", "cert.thumbprint", "private.key",
    "chain.pem", "key.p12", "bundle.p7b", ".env", "install.log", "port.txt", "state.json",
    "assets/helper.test.js", "assets/helper.spec.js", "assets/debug.dev.js", "assets/local.local.js",
    "assets/secret.js", "assets/localhost.key.js", "certs/preview.svg", "private/input.js",
    "tests/fixture.js", "fixtures/input.html", ".git/config", "assets/.cache/input.js",
    "node_modules/some-package/index.js", "coverage/index.html", "assets/debug.js", "assets/runtime-state.js",
  ];
  for (const path of [...allowed, ...privateFiles]) put(root, `public/${path}`);
  execFileSync(process.execPath, [join(root, "installer/gen-sea-config.mjs")], { cwd: tmpdir() });
  const config = JSON.parse(readFileSync(join(root, "installer/build/sea-config.json"), "utf8"));
  assert.deepEqual(Object.keys(config.assets).sort(), allowed.sort());
  for (const path of Object.values(config.assets)) assert.ok(isAbsolute(path));
});

// Break caught: IExpress's declared inputs include shared secrets or omit the helper.
test("checked-in SED declares exactly the seven public installer payloads", () => {
  const text = readFileSync(join(repository, "installer/app.sed"), "utf8");
  assert.deepEqual(sedFiles(text), payload);
  assert.deepEqual([...text.matchAll(/^%FILE(\d+)%=\r?$/gm)].map(match => Number(match[1])), [0, 1, 2, 3, 4, 5, 6]);
});

async function builder() {
  // Give an assertion failure, not an import/require error, before the new entry exists.
  assert.ok(existsSync(join(repository, "installer/build.mjs")), "a reusable safe build entry must exist");
  const module = await import(new URL("../installer/build.mjs", import.meta.url));
  assert.equal(typeof module.buildInstaller, "function");
  return module.buildInstaller;
}

function fixture(t) {
  const root = scratch(t);
  put(root, "server.cjs", "// fixture server; never executed\n");
  put(root, "public/taskpane.html", '<script src="assets/taskpane-DG2CZyG2.js"></script>');
  put(root, "public/commands.html", "<html></html>");
  put(root, "public/assets/taskpane-DG2CZyG2.js", "// committed patched bundle\n");
  put(root, "public/assets/api-url.js", "// helper\n");
  put(root, "manifest/manifest.xml", '<url>https://localhost:3000/taskpane.html</url>');
  for (const name of ["install.ps1", "uninstall.ps1", "launch.vbs", "app.ico", "certificate.ps1"]) {
    put(root, `installer/${name}`, `fixture ${name}; no certificate operations`);
  }
  copyFileSync(join(repository, "installer/app.sed"), join(root, "installer/app.sed"));
  const nodePath = put(root, "tools/node.exe", "fixture node executable");
  const iexpressPath = join(root, "tools/iexpress.exe");
  const postjectPath = put(root, "tools/postject/dist/cli.js", "// fixture external CLI\n");
  const calls = [];
  const logs = [];
  // Only external process boundaries are faked. Config generation, staging,
  // manifest rendering, SED generation and final output handling run for real.
  function run(command, args, options) {
    calls.push({ command, args, options });
    assert.equal(options.cwd, root);
    assert.notEqual(options.shell, true);
    if (command === "python") {
      assert.deepEqual(args, [join(root, "patch.py")]);
      writeFileSync(join(root, "public/assets/taskpane-DG2CZyG2.js"), "// explicitly patched\n");
    } else if (command === nodePath && args[0] === "--experimental-sea-config") {
      const config = JSON.parse(readFileSync(args[1], "utf8"));
      assert.ok(isAbsolute(config.output));
      writeFileSync(config.output, JSON.stringify(Object.keys(config.assets)));
    } else if (command === nodePath && args[0] === postjectPath) {
      assert.equal(args[2], "NODE_SEA_BLOB");
      assert.deepEqual(args.slice(4), ["--sentinel-fuse", "NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2"]);
      appendFileSync(args[1], readFileSync(args[3]));
    } else if (basename(command) === "iexpress.exe") {
      assert.deepEqual(args.slice(0, 2), ["/N", "/Q"]);
      const sed = readFileSync(args[2], "utf8");
      const source = sedValue(sed, "SourceFiles0");
      const target = sedValue(sed, "TargetName");
      assert.ok(isAbsolute(source));
      assert.ok(isAbsolute(target));
      const files = sedFiles(sed);
      assert.deepEqual(readdirSync(source).sort(), [...payload].sort());
      writeFileSync(target, JSON.stringify(Object.fromEntries(files.map(name => [name, readFileSync(join(source, name), "utf8")]))));
    } else {
      assert.fail(`unexpected external command: ${command} ${args.join(" ")}`);
    }
    return { status: 0, signal: null, error: undefined };
  }
  return { root, nodePath, postjectPath, iexpressPath, calls, logs, run, log: text => logs.push(text) };
}

// Break caught: the default build invokes Python/cert tools or packages stale dist.
test("default build uses the committed bundle and fresh seven-file staging despite polluted dist", async t => {
  const buildInstaller = await builder();
  const f = fixture(t);
  for (const name of ["localhost.pfx", "localhost.crt", "cert.thumbprint", "certs/private.key", "install.log", "port.txt", "manifest.xml", "AI-Excel-Setup.exe"]) {
    put(f.root, `installer/dist/${name}`, `untouched old ${name}`);
  }
  put(f.root, "installer/build/package/keep.txt", "unowned old staging directory");
  put(f.root, "public/assets/backup.js.orig");
  put(f.root, "public/localhost.pfx");
  const output = join(f.root, "results/safe dated installer.exe");
  const result = buildInstaller({ ...f, output });
  assert.equal(result.output, output);
  assert.deepEqual(readdirSync(result.stageDir).sort(), [...payload].sort());
  const archive = JSON.parse(readFileSync(output, "utf8"));
  assert.deepEqual(Object.keys(archive), payload);
  assert.equal(archive["manifest.template.xml"], '﻿<url>https://localhost:__PORT__/taskpane.html</url>');
  assert.ok(archive["AIExcelCustom.exe"].includes("assets/api-url.js"));
  assert.ok(!archive["AIExcelCustom.exe"].includes(".orig"));
  assert.ok(!archive["AIExcelCustom.exe"].includes(".pfx"));
  assert.equal(readFileSync(join(f.root, "installer/dist/manifest.xml"), "utf8"), "untouched old manifest.xml");
  assert.equal(readFileSync(join(f.root, "installer/dist/AI-Excel-Setup.exe"), "utf8"), "untouched old AI-Excel-Setup.exe");
  assert.equal(readFileSync(join(f.root, "installer/dist/certs/private.key"), "utf8"), "untouched old certs/private.key");
  assert.equal(readFileSync(join(f.root, "installer/build/package/keep.txt"), "utf8"), "unowned old staging directory");
  assert.ok(!existsSync(join(f.root, "public/assets/taskpane-DG2CZyG2.js.orig")));
  assert.equal(f.calls.length, 3);
  assert.ok(f.logs.some(line => line.includes(output)));
  const second = buildInstaller({ ...f, output: join(f.root, "results/second.exe") });
  assert.notEqual(result.stageDir, second.stageDir);
});

// Break caught: --patch fabricates a pristine input or starts build before checking it.
test("optional patch fails early with an actionable missing-pristine-backup error", async t => {
  const buildInstaller = await builder();
  const f = fixture(t);
  assert.throws(() => buildInstaller({ ...f, patch: true }), /\.orig[\s\S]*(?:pristine|original)[\s\S]*(?:without --patch|omit --patch)/i);
  assert.equal(f.calls.length, 0);
  assert.ok(!existsSync(join(f.root, "installer/build")));
  assert.ok(!existsSync(join(f.root, "public/assets/taskpane-DG2CZyG2.js.orig")));
});

test("explicit patch runs once before creating the SEA blob", async t => {
  const buildInstaller = await builder();
  const f = fixture(t);
  put(f.root, "patch.py", "# fixture, never executed\n");
  put(f.root, "public/assets/taskpane-DG2CZyG2.js.orig", "pristine fixture");
  const result = buildInstaller({ ...f, patch: true });
  assert.equal(f.calls[0].command, "python");
  assert.equal(f.calls.filter(call => call.command === "python").length, 1);
  assert.ok(existsSync(result.output));
});

test("missing certificate helper is reported before any build tool or filesystem staging", async t => {
  const buildInstaller = await builder();
  const f = fixture(t);
  rmSync(join(f.root, "installer/certificate.ps1"));
  assert.throws(() => buildInstaller(f), /certificate\.ps1/i);
  assert.equal(f.calls.length, 0);
  assert.ok(!existsSync(join(f.root, "installer/build")));
});

test("missing local postject never falls back to a network installer", async t => {
  const buildInstaller = await builder();
  const f = fixture(t);
  assert.throws(() => buildInstaller({ ...f, postjectPath: undefined }), /postject@1\.0\.0-alpha\.6[\s\S]*--postject-path/i);
  assert.equal(f.calls.length, 0);
});

for (const failAt of ["patch", "SEA", "postject", "IExpress"]) {
  test(`${failAt} nonzero exit aborts without replacing an existing installer`, async t => {
    const buildInstaller = await builder();
    const f = fixture(t);
    put(f.root, "patch.py", "# fixture\n");
    put(f.root, "public/assets/taskpane-DG2CZyG2.js.orig", "pristine fixture");
    const output = put(f.root, "installer/dist/AI-Excel-Setup.exe", "existing installer must survive");
    let count = 0;
    const expectedCount = { patch: 1, SEA: 2, postject: 3, IExpress: 4 }[failAt];
    const run = (...args) => ++count === expectedCount ? { status: 19, signal: null } : f.run(...args);
    assert.throws(() => buildInstaller({ ...f, output, patch: true, run }), /(?:failed|exit)[\s\S]*19/i);
    assert.equal(count, expectedCount);
    assert.equal(readFileSync(output, "utf8"), "existing installer must survive");
  });
}

test("IExpress success without an output file is not reported as a completed build", async t => {
  const buildInstaller = await builder();
  const f = fixture(t);
  const run = (command, ...args) => basename(command) === "iexpress.exe" ? { status: 0 } : f.run(command, ...args);
  assert.throws(() => buildInstaller({ ...f, run }), /(?:output|installer|package).*(?:missing|empty|not created)/i);
  assert.ok(!existsSync(join(f.root, "installer/dist/AI-Excel-Setup.exe")));
});

test("build CLI help and invalid arguments run from a foreign cwd without producing artifacts", t => {
  const root = scratch(t);
  const entry = join(root, "installer/build.mjs");
  mkdirSync(dirname(entry));
  for (const name of ["build.mjs", "gen-sea-config.mjs", "build.cmd"]) {
    copyFileSync(join(repository, "installer", name), join(root, "installer", name));
  }
  const help = spawnSync(process.execPath, [entry, "--help"], { cwd: tmpdir(), encoding: "utf8" });
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /--postject-path/);
  assert.match(help.stdout, /overwritten/i);
  const invalid = spawnSync(process.execPath, [entry, "--output"], { cwd: tmpdir(), encoding: "utf8" });
  assert.equal(invalid.status, 1);
  assert.match(invalid.stderr, /--output requires a path/);
  if (process.platform === "win32") {
    const batch = spawnSync(process.env.ComSpec || "cmd.exe", ["/d", "/s", "/c", `""${join(root, "installer/build.cmd")}" --help"`], { cwd: tmpdir(), encoding: "utf8", windowsVerbatimArguments: true });
    assert.equal(batch.status, 0, batch.stderr);
    assert.match(batch.stdout, /--postject-path/);
  }
  const bytes = readFileSync(join(root, "installer/build.cmd"));
  assert.ok([...bytes].every(byte => byte < 128), "batch launcher must be ASCII/UTF-8 without a BOM");
  assert.ok(!/(?<!\r)\n/.test(bytes.toString("utf8")), "batch launcher must use CRLF");
  assert.ok(!existsSync(join(root, "installer/build")));
});

test("tampered SED with a wildcard source is rejected before external tools", async t => {
  const buildInstaller = await builder();
  const f = fixture(t);
  appendFileSync(join(f.root, "installer/app.sed"), "\n*=\n");
  assert.throws(() => buildInstaller(f), /SED|app\.sed|payload/i);
  assert.equal(f.calls.length, 0);
});

test("rendered manifest has exactly one UTF-8 BOM and preserves Chinese text", async t => {
  const buildInstaller = await builder();
  for (const prefix of ["", "﻿"]) {
    const f = fixture(t);
    put(f.root, "manifest/manifest.xml", `${prefix}<url title="中文插件">https://localhost:3000/taskpane.html</url>`);
    const { stageDir } = buildInstaller(f);
    const manifest = readFileSync(join(stageDir, "manifest.template.xml"));
    assert.deepEqual([...manifest.subarray(0, 3)], [0xEF, 0xBB, 0xBF]);
    assert.equal(manifest.toString("utf8"), '﻿<url title="中文插件">https://localhost:__PORT__/taskpane.html</url>');
  }
});

test("tool launch errors and signal exits stop the build", async t => {
  const buildInstaller = await builder();
  for (const result of [{ error: new Error("fixture executable unavailable"), status: null }, { status: null, signal: "SIGTERM" }]) {
    const f = fixture(t);
    assert.throws(() => buildInstaller({ ...f, run: () => result }), /failed.*(?:unavailable|SIGTERM)/i);
    assert.ok(!existsSync(join(f.root, "installer/dist/AI-Excel-Setup.exe")));
  }
});

test("default destination replaces only the requested setup and warns before overwrite", async t => {
  const buildInstaller = await builder();
  const f = fixture(t);
  put(f.root, "installer/dist/AI-Excel-Setup.exe", "old setup");
  const result = buildInstaller(f);
  assert.equal(result.output, resolve(f.root, "installer/dist/AI-Excel-Setup.exe"));
  assert.ok(JSON.parse(readFileSync(result.output, "utf8"))["certificate.ps1"]);
  assert.ok(f.logs.some(line => /overwrit/i.test(line)));
});
