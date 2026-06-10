// HTTPS static server (SEA-embedded assets) + CORS-bypass reverse proxy.
// Runs both in dev (node server.cjs) and inside the SEA exe (AIExcelCustom.exe).
// Port comes from port.txt next to the executable; TLS from ./certs/localhost.pfx.
const https = require("node:https");
const { readFileSync, existsSync, writeFileSync } = require("node:fs");
const { extname, join, normalize, dirname } = require("node:path");
const { Readable } = require("node:stream");
const { execFileSync } = require("node:child_process");
const net = require("node:net");

// node:sea only exists inside the packaged exe.
let sea = null;
try { sea = require("node:sea"); } catch (_) { sea = null; }
const inSea = !!(sea && sea.isSea && sea.isSea());

// base dir = folder of the running exe (SEA) or this script (dev)
const BASE = inSea ? dirname(process.execPath) : __dirname;
const PUBLIC = join(BASE, "public");
const CERTS = join(BASE, "certs");
const PORT_FILE = join(BASE, "port.txt");
const MANIFEST = join(BASE, "manifest.xml");
const MANIFEST_TPL = join(BASE, "manifest.template.xml");
const PFX_PASS = "localdev";

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8", ".png": "image/png",
  ".svg": "image/svg+xml", ".woff": "font/woff", ".woff2": "font/woff2",
  ".ico": "image/x-icon",
};

function tlsOptions() {
  const pfx = join(CERTS, "localhost.pfx");
  if (existsSync(pfx)) return { pfx: readFileSync(pfx), passphrase: PFX_PASS };
  // dev fallback: office-addin-dev-certs PEM in homedir
  const os = require("node:os");
  const d = join(os.homedir(), ".office-addin-dev-certs");
  return { key: readFileSync(join(d, "localhost.key")), cert: readFileSync(join(d, "localhost.crt")) };
}

function readAsset(rel) {
  // rel uses forward slashes, no leading slash
  if (inSea) {
    try { return Buffer.from(sea.getAsset(rel)); } catch (_) { return null; }
  }
  const p = normalize(join(PUBLIC, rel));
  if (!p.startsWith(PUBLIC) || !existsSync(p)) return null;
  return readFileSync(p);
}

function setCors(res, req) {
  res.setHeader("Access-Control-Allow-Origin", req.headers.origin || "*");
  res.setHeader("Access-Control-Allow-Credentials", "true");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", req.headers["access-control-request-headers"] || "*");
  res.setHeader("Access-Control-Expose-Headers", "*");
  res.setHeader("Access-Control-Max-Age", "86400");
}

const STRIP_REQ = new Set(["host", "origin", "referer", "connection", "keep-alive", "content-length", "accept-encoding"]);
const STRIP_RES = new Set(["content-encoding", "content-length", "transfer-encoding", "connection",
  "access-control-allow-origin", "access-control-allow-credentials", "access-control-allow-methods", "access-control-allow-headers"]);

async function handleProxy(req, res, rest) {
  const qIndex = req.url.indexOf("?");
  const query = qIndex >= 0 ? req.url.slice(qIndex) : "";
  const target = "https://" + rest + query;
  if (req.method === "OPTIONS") { setCors(res, req); res.writeHead(204); res.end(); return; }
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;
  const fwd = {};
  for (const [k, v] of Object.entries(req.headers)) if (!STRIP_REQ.has(k.toLowerCase())) fwd[k] = v;
  let up;
  try {
    up = await fetch(target, {
      method: req.method, headers: fwd,
      body: req.method === "GET" || req.method === "HEAD" ? undefined : body, redirect: "manual",
    });
  } catch (e) {
    setCors(res, req); res.writeHead(502, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "proxy_upstream_error", target, detail: String(e) })); return;
  }
  setCors(res, req);
  up.headers.forEach((value, name) => { if (!STRIP_RES.has(name.toLowerCase())) res.setHeader(name, value); });
  res.writeHead(up.status);
  if (up.body) Readable.fromWeb(up.body).pipe(res); else res.end();
}

function handleStatic(req, res) {
  let urlPath = decodeURIComponent(new URL(req.url, "https://localhost").pathname);
  if (urlPath === "/") urlPath = "/taskpane.html";
  const rel = urlPath.replace(/^\/+/, "");
  const data = readAsset(rel);
  if (!data) { res.writeHead(404); res.end("Not found: " + urlPath); return; }
  const type = MIME[extname(rel).toLowerCase()] || "application/octet-stream";
  res.writeHead(200, { "Content-Type": type, "Cache-Control": "no-store" });
  res.end(data);
}

function isFree(port) {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.once("error", () => resolve(false));
    s.once("listening", () => s.close(() => resolve(true)));
    s.listen(port, "127.0.0.1");
  });
}

async function pickPort(start) {
  for (let p = start; p < start + 100; p++) if (await isFree(p)) return p;
  throw new Error("no free port in range");
}

function balloon(text) {
  // best-effort non-blocking tray balloon; ignore failures
  try {
    const ps = "Add-Type -AssemblyName System.Windows.Forms;" +
      "$n=New-Object System.Windows.Forms.NotifyIcon;" +
      "$n.Icon=[System.Drawing.SystemIcons]::Information;$n.Visible=$true;" +
      "$n.ShowBalloonTip(4000,'AI in Excel'," + JSON.stringify(text) + ",'Info');Start-Sleep -s 4;$n.Dispose()";
    execFileSync("powershell", ["-NoProfile", "-WindowStyle", "Hidden", "-Command", ps],
      { stdio: "ignore", windowsHide: true });
  } catch (_) { /* ignore */ }
}

function recoverPort(newPort) {
  // rewrite port.txt, render manifest from template, re-register HKCU sideload
  try {
    writeFileSync(PORT_FILE, String(newPort));
    if (existsSync(MANIFEST_TPL)) {
      const tpl = readFileSync(MANIFEST_TPL, "utf8").replace(/__PORT__/g, String(newPort));
      writeFileSync(MANIFEST, tpl);
      const key = "HKCU\\Software\\Microsoft\\Office\\16.0\\WEF\\Developer";
      execFileSync("reg", ["add", key, "/v", MANIFEST, "/t", "REG_SZ", "/d", MANIFEST, "/f"],
        { stdio: "ignore", windowsHide: true });
    }
  } catch (_) { /* ignore */ }
}

async function main() {
  let port = 3000;
  if (existsSync(PORT_FILE)) {
    const v = parseInt(readFileSync(PORT_FILE, "utf8").trim(), 10);
    if (v) port = v;
  }
  if (!(await isFree(port))) {
    const np = await pickPort(3000);
    recoverPort(np);
    port = np;
    balloon("端口已切换到 " + port + "，请重启 Excel 后再使用。");
  }
  const server = https.createServer(tlsOptions(), async (req, res) => {
    try {
      const p = new URL(req.url, "https://localhost").pathname;
      if (p.startsWith("/proxy/")) await handleProxy(req, res, p.slice("/proxy/".length));
      else handleStatic(req, res);
    } catch (e) { res.writeHead(500); res.end(String(e)); }
  });
  server.listen(port, "127.0.0.1", () => {
    console.log("AI in Excel server on https://localhost:" + port);
    if (inSea) balloon("AI in Excel 服务已就绪（端口 " + port + "），请打开 Excel。");
  });
}

main().catch((e) => { console.error(e); process.exit(1); });
