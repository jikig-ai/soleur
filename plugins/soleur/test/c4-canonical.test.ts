// Canonical on-disk format for the compiled LikeC4 model (#8542, ADR-235).
//
// model.likec4.json used to be one 1.1 MB JSON line, so ANY two PRs that
// regenerated it conflicted on GitHub. The canonical form is one JSON value per
// line with every view's `hash` blanked: a 152-pair replay of real concurrent
// .c4 PRs went from 0 clean merges to 107, with no merge that was clean but
// wrong. Three writers (scripts/regenerate-c4-model.sh, the web app's
// c4-render.ts, the plugin's generate-c4-from-components.ts) must emit exactly
// these bytes, or each rewrites the others' file on every save.
//
// Every `git` spawn below passes gitCleanEnv(): a hook-exported GIT_DIR beats
// cwd and `git -C` (plugin AGENTS.md §Test Fixture Conventions).
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { canonicalizeC4Model } from "../lib/c4-canonical.mjs";
import { gitCleanEnv } from "./lib/git-clean-env";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const CLI = join(REPO_ROOT, "plugins/soleur/lib/c4-canonical-cli.mjs");
const MIRROR_SRC = join(REPO_ROOT, "plugins/soleur/lib/c4-canonical.mjs");
const MIRROR_DST = join(REPO_ROOT, "apps/web-platform/lib/c4-canonical.mjs");
const ARTIFACT = "knowledge-base/engineering/architecture/diagrams/model.likec4.json";

// A raw likec4-shaped export: one line, non-alphabetical key order, two views
// with non-empty hashes, one view with no hash key at all, and a non-view
// `hash` that must survive. Values carry the shapes a real layouted export has:
// out-of-order arrays whose order is meaningful, floats, an exponent, non-ASCII
// text, an escaped newline, and a U+2028 followed by spaces (which a /^ +/gm
// strip would eat, because ^ matches after U+2028 under the m flag).
const RAW = JSON.stringify({
  projectId: "default",
  elements: {
    b: { id: "b", title: "B — backend", description: { txt: "line one\nline two" } },
    a: { id: "a", title: "A", description: { txt: "pasted\u2028   text" } },
  },
  relations: { r1: { source: "a", target: "b", title: "uses" } },
  views: {
    index: {
      id: "index",
      hash: "6v56Y9lvx4UMwclrRQ4gL_jWujZQPMIQbDx8qnXD68w",
      nodes: [
        { id: "b", x: 12.345, y: 1e21 },
        { id: "a", x: 1, y: -2.5 },
      ],
      edges: [{ id: "e1", points: [[3, 4], [1, 2]] }],
    },
    context: { id: "context", hash: "enjPCp_0DCUhTkngHCSw18BHR3S8EP80rilGMTPdK2Q", nodes: [] },
    bare: { id: "bare", nodes: [] },
  },
  manualLayouts: { index: { hash: "keep-me" } },
});

function withTmp<T>(fn: (d: string) => T): T {
  const d = mkdtempSync(join(tmpdir(), "c4-canonical-"));
  try {
    return fn(d);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
}

function mergeFile(ours: string, base: string, theirs: string): { out: string; conflicted: boolean } {
  return withTmp((d) => {
    const [o, b, t] = ["o", "b", "t"].map((n) => join(d, n));
    writeFileSync(o, ours);
    writeFileSync(b, base);
    writeFileSync(t, theirs);
    const r = spawnSync("git", ["merge-file", "-p", o, b, t], { encoding: "utf8", env: gitCleanEnv() });
    if (r.status === null || r.status < 0) throw new Error(`git merge-file failed to run: ${r.error}`);
    return { out: r.stdout, conflicted: r.status !== 0 };
  });
}

function node(args: string[]) {
  return spawnSync("node", args, { encoding: "utf8", env: gitCleanEnv() });
}

describe("canonicalizeC4Model", () => {
  const out = canonicalizeC4Model(RAW);
  const parsed = JSON.parse(out);

  test("blanks EVERY view hash that exists (fixture has two)", () => {
    expect(parsed.views.index.hash).toBe("");
    expect(parsed.views.context.hash).toBe("");
  });

  test("does not ADD a hash key to a view that had none", () => {
    expect("hash" in parsed.views.bare).toBe(false);
  });

  test("leaves non-view hash keys untouched", () => {
    expect(parsed.manualLayouts.index.hash).toBe("keep-me");
  });

  test("round-trips: same data except blanked view hashes, same key order", () => {
    const want = JSON.parse(RAW);
    for (const v of Object.values<Record<string, unknown>>(want.views)) if ("hash" in v) v.hash = "";
    expect(parsed).toEqual(want);
    // Key-order oracle is JSON.stringify(JSON.parse(x)), not the raw text:
    // JS hoists integer-like keys, and the canonical form inherits that.
    expect(JSON.stringify(parsed)).toBe(JSON.stringify(want));
  });

  test("one value per line: no line starts with whitespace, exactly one trailing newline", () => {
    expect(out.split("\n").length).toBeGreaterThan(20);
    expect(/\n[ \t]/.test(out)).toBe(false);
    expect(out.endsWith("\n")).toBe(true);
    expect(out.endsWith("\n\n")).toBe(false);
  });

  test("is idempotent", () => {
    expect(canonicalizeC4Model(out)).toBe(out);
  });

  test("preserves spaces after a U+2028 inside a string value", () => {
    expect(parsed.elements.a.description.txt).toBe("pasted\u2028   text");
  });

  test("rejects non-JSON and non-object input", () => {
    expect(() => canonicalizeC4Model("{not json")).toThrow();
    expect(() => canonicalizeC4Model("[1,2]")).toThrow();
    expect(() => canonicalizeC4Model("null")).toThrow();
  });
});

describe("CLI (run under node, as the repo writer runs it)", () => {
  test("writes to stdout the same bytes as the import", () =>
    withTmp((d) => {
      const f = join(d, "raw.json");
      writeFileSync(f, RAW);
      const r = node([CLI, f]);
      expect(r.status).toBe(0);
      expect(r.stdout).toBe(canonicalizeC4Model(RAW));
    }));

  test("--check prints canonical (exit 0) on canonical input, not-canonical (exit 1) on raw", () =>
    withTmp((d) => {
      const raw = join(d, "raw.json");
      const canon = join(d, "canon.json");
      writeFileSync(raw, RAW);
      writeFileSync(canon, canonicalizeC4Model(RAW));
      const ok = node([CLI, "--check", canon]);
      expect([ok.status, ok.stdout.trim()]).toEqual([0, "canonical"]);
      const bad = node([CLI, "--check", raw]);
      expect([bad.status, bad.stdout.trim()]).toEqual([1, "not-canonical"]);
    }));

  // Each negative differs from canonical on ONE axis, so a --check that ignores
  // whitespace, trims, or only looks at hashes cannot pass all of them.
  test.each([
    ["hashes blank but one line", (c: string) => JSON.stringify(JSON.parse(c))],
    ["missing the trailing newline", (c: string) => c.slice(0, -1)],
    ["indented with two spaces", (c: string) => JSON.stringify(JSON.parse(c), null, 2) + "\n"],
    ["an extra trailing newline", (c: string) => c + "\n"],
  ])("--check rejects input that is %s", (_label, perturb) =>
    withTmp((d) => {
      const canon = canonicalizeC4Model(RAW);
      const f = join(d, "near.json");
      writeFileSync(f, perturb(canon));
      expect(readFileSync(f, "utf8")).not.toBe(canon);
      const r = node([CLI, "--check", f]);
      expect([r.status, r.stdout.trim()]).toEqual([1, "not-canonical"]);
    }));

  test("an unreadable or invalid input exits 2 with nothing on stdout", () =>
    withTmp((d) => {
      const f = join(d, "bad.json");
      writeFileSync(f, "{not json");
      const r = node([CLI, f]);
      expect(r.status).toBe(2);
      expect(r.stdout).toBe("");
      const missing = node([CLI, join(d, "absent.json")]);
      expect(missing.status).toBe(2);
    }));
});

describe("mergeability (git merge-file over synthetic base/A/B)", () => {
  const base = JSON.parse(RAW);
  const sideA = structuredClone(base);
  sideA.elements.a.title = "A (renamed on side A)";
  sideA.views.index.hash = "hash-after-A";
  const sideB = structuredClone(base);
  sideB.relations.r1.title = "calls (edited on side B)";
  sideB.views.index.hash = "hash-after-B";

  test("disjoint edits: raw conflicts, canonical merges into the expected object", () => {
    const raw = mergeFile(JSON.stringify(sideA), JSON.stringify(base), JSON.stringify(sideB));
    expect(raw.conflicted).toBe(true);
    const c = (o: unknown) => canonicalizeC4Model(JSON.stringify(o));
    const canon = mergeFile(c(sideA), c(base), c(sideB));
    expect(canon.conflicted).toBe(false);
    const want = structuredClone(base);
    want.elements.a.title = sideA.elements.a.title;
    want.relations.r1.title = sideB.relations.r1.title;
    expect(JSON.parse(canon.out)).toEqual(JSON.parse(c(want)));
  });

  test("same-leaf edit still conflicts (positive control)", () => {
    const b2 = structuredClone(base);
    b2.elements.a.title = "A (renamed differently on side B)";
    const c = (o: unknown) => canonicalizeC4Model(JSON.stringify(o));
    expect(mergeFile(c(sideA), c(base), c(b2)).conflicted).toBe(true);
  });
});

describe("repo wiring", () => {
  // Census, not a hand-kept list: every tracked source file that runs
  // `likec4 export json` can produce model.likec4.json, so each one must route
  // its output through the canonical module. A new writer that does not fails
  // here instead of silently reformatting the file in customer repos.
  test("every file that runs `likec4 export json` routes through c4-canonical", () => {
    const r = spawnSync(
      "git",
      ["grep", "-l", "-E", "export[\"', ]+json", "--", "*.sh", "*.ts", "*.mjs", "*.js", ":!**/test/**", ":!**/*.test.*"],
      { cwd: REPO_ROOT, encoding: "utf8", env: gitCleanEnv() },
    );
    expect([0, 1]).toContain(r.status);
    // Comment-stripped, and anchored on an INVOCATION (an argv array or a shell
    // `export json -o`), so prose that merely names the command is not a writer.
    const code = (f: string) =>
      readFileSync(join(REPO_ROOT, f), "utf8")
        .split("\n")
        .filter((l) => !/^\s*(\/\/|#|\*)/.test(l))
        .join("\n");
    const INVOKES = /["']export["'],\s*["']json["']|\bexport json -o\b/;
    const writers = r.stdout.trim().split("\n").filter(Boolean).filter((f) => INVOKES.test(code(f)));
    // Floor: the three known writers. An empty census would pass vacuously.
    expect(writers.sort()).toEqual(
      expect.arrayContaining([
        "apps/web-platform/server/c4-render.ts",
        "plugins/soleur/scripts/generate-c4-from-components.ts",
        "scripts/regenerate-c4-model.sh",
      ]),
    );
    const unrouted = writers.filter((f) => !/c4-canonical/.test(code(f)));
    expect(unrouted).toEqual([]);
  });

  test("the apps copy is a byte-identical mirror of the plugin module", () => {
    expect(resolve(MIRROR_SRC)).not.toBe(resolve(MIRROR_DST));
    expect(readFileSync(MIRROR_DST, "utf8")).toBe(readFileSync(MIRROR_SRC, "utf8"));
  });

  test("the artifact carries linguist-generated and no merge/diff-changing attribute", () => {
    const r = spawnSync("git", ["check-attr", "-a", "--", ARTIFACT], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      env: gitCleanEnv(),
    });
    expect(r.status).toBe(0);
    const attrs = r.stdout
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((l) => l.split(": ").slice(1).join(": "));
    // `binary`, `-diff`, `-merge` or `merge=` would make git side-pick silently
    // (resolve-regenerable-conflicts.sh documents it) — the opposite of this fix.
    expect(attrs).toEqual(["linguist-generated: true"]);
  });
});
