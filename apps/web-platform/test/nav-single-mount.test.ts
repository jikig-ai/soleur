import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// AC4b (THE structural rule): OrgSwitcherContainer + LiveRepoBadge must render
// in EXACTLY one module — the context band. A second mount (the bug this PR
// fixes) puts a stale duplicate of workspace identity on screen. This is a
// negative-space source guard: it asserts no other module imports them. A
// behavioral test cannot catch "rendered in two layouts at once" cheaply;
// reachability via import is the proxy.

const ROOT = dirname(dirname(fileURLToPath(import.meta.url))); // apps/web-platform
const SCAN_DIRS = ["app", "components", "hooks"];

function walk(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) walk(p, acc);
    else if (/\.(tsx|ts)$/.test(p) && !/\.test\.tsx?$/.test(p)) acc.push(p);
  }
  return acc;
}

const FILES = SCAN_DIRS.flatMap((d) => walk(join(ROOT, d)));

const CASES = [
  {
    name: "OrgSwitcherContainer",
    re: /from\s+["']@\/components\/dashboard\/org-switcher-container["']/,
  },
  {
    name: "LiveRepoBadge",
    re: /from\s+["']@\/components\/dashboard\/live-repo-badge["']/,
  },
] as const;

describe("single-mount: workspace identity renders in exactly one module (AC4b)", () => {
  for (const { name, re } of CASES) {
    it(`${name} is imported only by workspace-context-band.tsx`, () => {
      const importers = FILES.filter((f) => re.test(readFileSync(f, "utf8")))
        .map((f) => f.slice(ROOT.length + 1))
        .sort();
      expect(importers).toEqual([
        "components/dashboard/workspace-context-band.tsx",
      ]);
    });
  }
});
