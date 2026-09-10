// Offline installer build. Shared private keys require an explicit build option.
import {
  copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync,
  readdirSync, statSync, writeFileSync,
} from "node:fs";
import { dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { X509Certificate } from "node:crypto";
import { createSecureContext } from "node:tls";
import { createSeaConfig } from "./gen-sea-config.mjs";

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const payloadFiles = [
  "AIExcelCustom.exe", "install.ps1", "uninstall.ps1", "launch.vbs",
  "manifest.template.xml", "app.ico", "certificate.ps1", "startup.ps1", "options.ps1",
];
const sharedPayloadFiles = ["shared-localhost.pfx", "shared-localhost.crt", "shared-cert.thumbprint"];
const sharedSourceFiles = ["localhost.pfx", "localhost.crt", "cert.thumbprint"];
const postjectVersion = "1.0.0-alpha.6";

function requireFile(path, description = "Build input") {
  if (!existsSync(path) || !lstatSync(path).isFile() || statSync(path).size === 0) {
    throw new Error(`${description} missing, empty or not a regular file: ${path}`);
  }
}

function readSharedCertificate(root, suppliedDir, log) {
  if (typeof suppliedDir !== "string" || !suppliedDir.trim()) throw new Error("--shared-cert-dir requires a directory path.");
  const directory = resolve(root, suppliedDir);
  log("WARNING: This package will contain a shared private key that anyone can extract; it is not a safe default key. Each installation requires explicit shared-certificate risk acceptance.");
  if (!existsSync(directory) || !lstatSync(directory).isDirectory()) {
    throw new Error(`Shared certificate directory missing or not a regular directory: ${directory}`);
  }
  for (const name of sharedSourceFiles) requireFile(join(directory, name), "Shared certificate input");
  // Read once and stage these same validated bytes, never scan dist or another directory.
  const [pfx, crt, thumb] = sharedSourceFiles.map(name => readFileSync(join(directory, name)));
  const thumbprint = thumb.toString("utf8").trim().toUpperCase();
  if (!/^[A-F0-9]{40}$/.test(thumbprint)) throw new Error("Shared cert.thumbprint must contain exactly 40 hexadecimal characters.");
  let certificate;
  try { certificate = new X509Certificate(crt); }
  catch { throw new Error("Shared localhost.crt must be a parseable X.509 certificate."); }
  if (certificate.fingerprint.replaceAll(":", "") !== thumbprint) throw new Error("Shared CRT thumbprint does not match cert.thumbprint.");
  // OpenSSL's CA classification is only a precheck, not an explicit BasicConstraints parser.
  if (certificate.ca !== false) throw new Error("Shared CRT must be classified as non-CA by Node.");
  if (certificate.checkHost("localhost", { subject: "never", wildcards: false }) === undefined) {
    throw new Error("Shared CRT must contain an explicit localhost DNS SAN.");
  }
  const now = Date.now();
  const validFrom = Date.parse(certificate.validFrom);
  const validTo = Date.parse(certificate.validTo);
  if (!Number.isFinite(validFrom) || !Number.isFinite(validTo) || now < validFrom || now >= validTo) {
    throw new Error("Shared CRT is outside its validity period.");
  }
  // Compatibility password, not a secret. This creates no listener or store entry.
  // Full PFX/CRT identity and extension validation remains mandatory at install time.
  try { createSecureContext({ pfx, passphrase: "localdev" }); }
  catch { throw new Error("Shared localhost.pfx must be parseable using the compatibility password localdev."); }
  log(`Shared certificate SHA-1: ${thumbprint}; valid ${certificate.validFrom} to ${certificate.validTo}; SAN: ${JSON.stringify(certificate.subjectAltName || "(none)")}`);
  return [pfx, crt, thumb];
}

function selectPostject(root, suppliedPath) {
  if (suppliedPath) {
    const path = resolve(root, suppliedPath);
    requireFile(path, "Postject CLI");
    if (![".js", ".cjs", ".mjs", ".exe"].includes(extname(path).toLowerCase())) {
      throw new Error("--postject-path must name the actual dist/cli.js (or executable), not an npm .cmd shim.");
    }
    return path;
  }
  const packageDir = join(root, "node_modules", "postject");
  const packageFile = join(packageDir, "package.json");
  const cli = join(packageDir, "dist", "cli.js");
  if (!existsSync(packageFile) || !existsSync(cli)) {
    throw new Error(`Preinstall postject@${postjectVersion}, or pass --postject-path to an existing cached dist/cli.js. The build does not download tools.`);
  }
  if (JSON.parse(readFileSync(packageFile, "utf8")).version !== postjectVersion) {
    throw new Error(`Local postject must be postject@${postjectVersion}; use --postject-path to explicitly select a trusted cached CLI.`);
  }
  requireFile(cli, "Postject CLI");
  return cli;
}

function renderSed(template, stageDir, target, shared = false) {
  // Percent expansion and newlines have meaning in SED/INI syntax.
  for (const path of [stageDir, target]) {
    if (/[\r\n%\"]/.test(path)) throw new Error(`Unsupported IExpress path: ${path}`);
  }
  template = template.replace(/\r\n/g, "\n");
  const declarations = payloadFiles.map((name, index) => `FILE${index}="${name}"`);
  const declared = template.match(/^[ \t]*FILE\d+[ \t]*=.*$/gim) || [];
  if (JSON.stringify(declared) !== JSON.stringify(declarations) || !template.includes(declarations.join("\n") + "\n[SourceFiles]\n")) {
    throw new Error("app.sed must declare exactly the nine base payload files with indices FILE0-8.");
  }
  const references = template.match(/^[ \t]*%FILE\d+%[ \t]*=.*$/gim) || [];
  const expectedReferences = payloadFiles.map((_, index) => `%FILE${index}%=`);
  if (JSON.stringify(references) !== JSON.stringify(expectedReferences)) {
    throw new Error("app.sed must reference exactly FILE0-8, once each.");
  }
  const sourceSection = template.split("[SourceFiles]\n");
  const expectedSource = ["SourceFiles0=__SOURCE_PATH__", "[SourceFiles0]", ...expectedReferences].join("\n");
  if (sourceSection.length !== 2 || sourceSection[1].trim() !== expectedSource) {
    throw new Error("app.sed source section must contain only the nine base payload references, without wildcards or extra sources.");
  }
  for (const placeholder of ["__SOURCE_PATH__", "__TARGET_PATH__"]) {
    if (template.split(placeholder).length !== 2) throw new Error(`app.sed requires one ${placeholder} placeholder.`);
  }
  if (shared) {
    const extraDeclarations = sharedPayloadFiles.map((name, index) => `FILE${payloadFiles.length + index}="${name}"`);
    const extraReferences = sharedPayloadFiles.map((_, index) => `%FILE${payloadFiles.length + index}%=`);
    template = template.replace("[SourceFiles]\n", extraDeclarations.join("\n") + "\n[SourceFiles]\n");
    template = template.trimEnd() + "\n" + extraReferences.join("\n") + "\n";
  }
  return template.replace("__SOURCE_PATH__", () => stageDir + sep)
    .replace("__TARGET_PATH__", () => target).replace(/\n/g, "\r\n");
}

export function buildInstaller({
  root = rootDir,
  output,
  patch = false,
  postjectPath,
  sharedCertDir,
  nodePath = process.execPath,
  iexpressPath = process.env.SystemRoot ? join(process.env.SystemRoot, "System32", "iexpress.exe") : "iexpress.exe",
  run = spawnSync,
  log = console.log,
} = {}) {
  root = resolve(root);
  output = resolve(root, output || "installer/dist/AI-Excel-Setup.exe");
  nodePath = resolve(nodePath);
  if (extname(output).toLowerCase() !== ".exe" || output.toLowerCase() === nodePath.toLowerCase()) {
    throw new Error("--output must name an installer .exe, not the Node executable.");
  }
  if (Number(process.versions.node.split(".")[0]) < 22) throw new Error("Building requires Node.js 22 or newer.");
  const shared = sharedCertDir === undefined ? null : readSharedCertificate(root, sharedCertDir, log);
  const packageFiles = shared ? [...payloadFiles, ...sharedPayloadFiles] : payloadFiles;
  // All input checks precede tools and staging. Never manufacture a .orig backup.
  if (patch) {
    const original = join(root, "public/assets/taskpane-DG2CZyG2.js.orig");
    if (!existsSync(original)) {
      throw new Error(`Missing ${original}. Supply the pristine original upstream bundle to use --patch, or omit --patch to build the committed public bundle. Do not copy the patched .js to .orig.`);
    }
    requireFile(original, "Pristine patch backup");
    requireFile(join(root, "patch.py"));
  }
  for (const path of [
    "server.cjs", "manifest/manifest.xml", "public/taskpane.html", "public/commands.html",
    "public/assets/taskpane-DG2CZyG2.js", "public/assets/api-url.js", "installer/app.sed",
    "installer/install.ps1", "installer/uninstall.ps1", "installer/launch.vbs",
    "installer/app.ico", "installer/certificate.ps1", "installer/startup.ps1", "installer/options.ps1",
  ]) requireFile(join(root, path));
  requireFile(nodePath, "Node executable");
  const postject = selectPostject(root, postjectPath);
  const template = readFileSync(join(root, "installer/app.sed"), "utf8");
  const manifest = readFileSync(join(root, "manifest/manifest.xml"), "utf8");
  if (!manifest.includes("localhost:3000")) throw new Error("manifest/manifest.xml must contain localhost:3000 for port templating.");

  function step(label, command, args) {
    log(label);
    const result = run(command, args, { cwd: root, stdio: "inherit", shell: false });
    if (result.error) throw new Error(`${label} failed: ${result.error.message}`, { cause: result.error });
    if (result.status !== 0) throw new Error(`${label} failed (exit ${result.status}, signal ${result.signal || "none"}).`);
  }
  if (existsSync(output)) log(`WARNING: successful build will overwrite ${output}. Use --output to keep the previous package.`);
  if (patch) step("Patch frontend", "python", [join(root, "patch.py")]);

  const buildDir = join(root, "installer/build");
  mkdirSync(buildDir, { recursive: true });
  // Never reuse/clean an existing dist or package directory. Each run owns only
  // this newly-created directory; leave it for inspection, including on failure.
  const workDir = mkdtempSync(join(buildDir, "package-"));
  const stageDir = join(workDir, "payload");
  mkdirSync(stageDir);
  const packagePath = join(workDir, "AI-Excel-Setup.exe");
  const sedPath = join(workDir, "app.sed");
  writeFileSync(sedPath, renderSed(template, stageDir, packagePath, Boolean(shared)));
  const { config, configPath } = createSeaConfig({ root, buildDir: workDir });
  step("Generate SEA blob", nodePath, ["--experimental-sea-config", configPath]);
  requireFile(config.output, "SEA output blob");
  const executable = join(stageDir, "AIExcelCustom.exe");
  copyFileSync(nodePath, executable);
  const injectArgs = [executable, "NODE_SEA_BLOB", config.output, "--sentinel-fuse", "NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2"];
  if (extname(postject).toLowerCase() === ".exe") step("Inject SEA blob", postject, injectArgs);
  else step("Inject SEA blob", nodePath, [postject, ...injectArgs]);
  requireFile(executable, "SEA executable");

  for (const name of payloadFiles.slice(1)) {
    const target = join(stageDir, name);
    // Windows PowerShell 5.1 needs a UTF-8 BOM when reading non-ASCII manifests.
    if (name === "manifest.template.xml") writeFileSync(target, "﻿" + manifest.replace(/^﻿/, "").replaceAll("localhost:3000", "localhost:__PORT__"));
    else copyFileSync(join(root, "installer", name), target);
  }
  if (shared) sharedPayloadFiles.forEach((name, index) => writeFileSync(join(stageDir, name), shared[index]));
  const staged = readdirSync(stageDir).sort();
  if (JSON.stringify(staged) !== JSON.stringify([...packageFiles].sort())) throw new Error("Unexpected file in package staging directory.");
  for (const name of packageFiles) requireFile(join(stageDir, name), "Package payload");
  step("Build IExpress installer", iexpressPath, ["/N", "/Q", sedPath]);
  requireFile(packagePath, "Installer output");
  mkdirSync(dirname(output), { recursive: true });
  copyFileSync(packagePath, output);
  log(`DONE -> ${output}`);
  log(`Payload staging (${packageFiles.length} files${shared ? "; contains an extractable shared private key" : "; no shared certificate"}) -> ${stageDir}`);
  return { output, stageDir, workDir, sedPath, configPath };
}

const usage = `Usage: installer\\build.cmd [--patch] [--postject-path PATH] [--shared-cert-dir PATH] [--output PATH]
  Default: nine files, no shared certificate; installation generates an independent key.
           Uses committed public assets; no Python, Pillow or certificate generation.
  --patch          Rebuild JS with python patch.py; requires the pristine .orig.
  --postject-path   Offline cached postject dist/cli.js (not the npm .cmd shim).
                   Otherwise requires local postject@${postjectVersion}.
  --shared-cert-dir  Explicit directory: localhost.pfx, localhost.crt, cert.thumbprint.
                    Adds exactly three shared-* payloads; PFX password is localdev.
                    WARNING: the shared private key can be extracted from the package.
                    Not a safe default key; shared mode requires risk acceptance per install.
                    Omit to disable the shared-certificate option in the installer.
  --output         Setup .exe path. All relative paths resolve from the project.
                   Default installer/dist/AI-Excel-Setup.exe WILL be overwritten.
  --help           Show this help without building.
Each build keeps its own installer/build/package-*/payload for inspection.
No existing dist or user certificates are selected automatically.`;

function main(args) {
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--help" || args[i] === "-h") { console.log(usage); return; }
    if (args[i] === "--patch") options.patch = true;
    else if (["--postject-path", "--output", "--shared-cert-dir"].includes(args[i])) {
      const name = args[i];
      const value = args[++i];
      if (!value || value.startsWith("--")) throw new Error(`${name} requires a path.`);
      options[{ "--output": "output", "--postject-path": "postjectPath", "--shared-cert-dir": "sharedCertDir" }[name]] = value;
    } else throw new Error(`Unknown option: ${args[i]}\n${usage}`);
  }
  if (process.platform !== "win32") throw new Error("IExpress installer builds require Windows.");
  buildInstaller(options);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(`BUILD FAILED: ${error.message}`); process.exitCode = 1; }
}
