// Builds sea-config.json: main = server.cjs, assets = every file under public/.
// Asset keys are POSIX-relative paths (match server.cjs readAsset()).
import { readdirSync, statSync, writeFileSync, mkdirSync } from "node:fs";
import { join, relative, dirname, sep } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");          // project root
const pub = join(root, "public");
const buildDir = join(here, "build");
mkdirSync(buildDir, { recursive: true });

function walk(dir, acc) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) walk(full, acc);
    else acc.push(full);
  }
  return acc;
}

const assets = {};
for (const f of walk(pub, [])) {
  const key = relative(pub, f).split(sep).join("/"); // posix key
  assets[key] = f.split(sep).join("/");
}

const cfg = {
  main: join(root, "server.cjs").split(sep).join("/"),
  output: join(buildDir, "sea-prep.blob").split(sep).join("/"),
  disableExperimentalSEAWarning: true,
  useSnapshot: false,
  useCodeCache: false,
  assets,
};
writeFileSync(join(buildDir, "sea-config.json"), JSON.stringify(cfg, null, 2));
console.log("sea-config.json:", Object.keys(assets).length, "assets");
