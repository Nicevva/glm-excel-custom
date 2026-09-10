import test from "node:test";
import assert from "node:assert/strict";
import { cpSync, mkdtempSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";

// Break caught: the real SEA generator stops including the imported helper.
// Run it in a scratch layout, never write installer build output in the repo.
test("SEA public traversal embeds the URL helper beside the taskpane bundle", () => {
  const root = mkdtempSync(join(tmpdir(), "glm-excel-sea-assets-"));
  try {
    mkdirSync(join(root, "installer"));
    cpSync(new URL("../installer/gen-sea-config.mjs", import.meta.url), join(root, "installer/gen-sea-config.mjs"));
    cpSync(new URL("../public", import.meta.url), join(root, "public"), { recursive: true, filter: path => !path.endsWith(".orig") });
    execFileSync(process.execPath, [join(root, "installer/gen-sea-config.mjs")]);
    const config = JSON.parse(readFileSync(join(root, "installer/build/sea-config.json"), "utf8"));
    assert.equal(readFileSync(config.assets["assets/api-url.js"], "utf8"), readFileSync(new URL("../public/assets/api-url.js", import.meta.url), "utf8"));
    assert.ok(config.assets["assets/taskpane-DG2CZyG2.js"]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
