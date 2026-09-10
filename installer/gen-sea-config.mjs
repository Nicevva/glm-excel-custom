// Include runtime static assets only; never embed local backups or certificates.
// Asset keys are POSIX-relative paths (match server.cjs readAsset()).
import { readdirSync, writeFileSync, mkdirSync } from "node:fs";
import { join, relative, dirname, sep, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const staticTypes = new Set([".html", ".js", ".css", ".svg", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".woff", ".woff2", ".ttf", ".eot"]);
const privatePart = /(?:^|[._-])(?:orig|bak|backup|test|tests|spec|fixtures?|dev|debug|coverage|node_modules|runtime|local|private|secrets?|certs?|certificates?|keys?|pem|pfx|p12|p7b|p7c|crt|cer|der|csr|thumbprint)(?:$|[._-])/i;
const posix = path => path.split(sep).join("/");

export function createSeaConfig({ root = join(here, ".."), buildDir = join(here, "build") } = {}) {
  root = resolve(root);
  buildDir = resolve(buildDir);
  const pub = join(root, "public");
  const assets = {};
  function walk(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      // Do not follow symlinks/junctions out of the public tree.
      if (entry.name.startsWith(".") || privatePart.test(entry.name) || entry.isSymbolicLink()) continue;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && staticTypes.has(extname(entry.name).toLowerCase())) {
        assets[posix(relative(pub, full))] = posix(full);
      }
    }
  }
  walk(pub);
  const config = {
    main: posix(join(root, "server.cjs")),
    output: posix(join(buildDir, "sea-prep.blob")),
    disableExperimentalSEAWarning: true,
    useSnapshot: false,
    useCodeCache: false,
    assets,
  };
  mkdirSync(buildDir, { recursive: true });
  const configPath = join(buildDir, "sea-config.json");
  writeFileSync(configPath, JSON.stringify(config, null, 2));
  return { config, configPath };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { config } = createSeaConfig();
  console.log("sea-config.json:", Object.keys(config.assets).length, "assets");
}
