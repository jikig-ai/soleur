// #8623: the app's staging refusal and the ADR-235 local resolver
// (plugins/soleur/scripts/resolve-regenerable-conflicts.sh) must refuse the
// same likec4 config files. The resolver uses a shell glob; every exact name
// the app refuses must match it, as bash itself evaluates the pattern.
import { describe, it, expect } from "vitest";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { LIKEC4_CONFIG_NAMES } from "@/server/c4-stage-sources";

const APP = join(fileURLToPath(new URL(".", import.meta.url)), "..");
const RESOLVER = join(APP, "..", "..", "plugins", "soleur", "scripts", "resolve-regenerable-conflicts.sh");

describe("likec4 config names: app refusal ⊆ resolver refusal", () => {
  it("every LIKEC4_CONFIG_NAMES entry matches the resolver's likec4-config case pattern", () => {
    const src = readFileSync(RESOLVER, "utf8");
    const lines = src.split("\n");
    const i = lines.findIndex((l) => /na likec4-config /.test(l));
    expect(i).toBeGreaterThan(0);
    const pattern = lines[i - 1].trim().replace(/\)$/, "");
    expect(pattern).toMatch(/likec4\.config/);
    for (const name of LIKEC4_CONFIG_NAMES) {
      const r = spawnSync("bash", ["-c", `case "$1" in ${pattern}) exit 0 ;; *) exit 1 ;; esac`, "_", name]);
      expect(r.status, `${name} vs ${pattern}`).toBe(0);
    }
    // Positive control: a source file does not match.
    const ctl = spawnSync("bash", ["-c", `case "$1" in ${pattern}) exit 0 ;; *) exit 1 ;; esac`, "_", "model.c4"]);
    expect(ctl.status).toBe(1);
  });
});
