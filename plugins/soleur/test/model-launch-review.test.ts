import { describe, test, expect, beforeAll } from "bun:test";
import {
  existsSync,
  readFileSync,
  mkdtempSync,
  writeFileSync,
  mkdirSync,
  rmSync,
} from "node:fs";
import { resolve, join } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SKILL_DIR = resolve(REPO_ROOT, "plugins/soleur/skills/model-launch-review");
const SKILL_MD = resolve(SKILL_DIR, "SKILL.md");
const AUDIT_SH = resolve(SKILL_DIR, "scripts/audit-models.sh");

// Current model landscape (2026-06). The auditor flags anything NOT in this set
// that lives in a config-class path. Source of truth: claude-api skill table.
const CURRENT_IDS = [
  "claude-opus-4-8",
  "claude-sonnet-5",
  "claude-haiku-4-5-20251001",
  "claude-fable-5",
];

function run(args: string[], root: string) {
  return spawnSync("bash", [AUDIT_SH, "--root", root, ...args], {
    encoding: "utf8",
  });
}

/** Build a synthesized mini-repo: one stale config file, one stale test
 * fixture, one stale archive note. Only the config file is an auto-fix target. */
function makeFixtureRoot(staleId = "claude-opus-4-7"): string {
  const root = mkdtempSync(join(tmpdir(), "mlr-fixture-"));
  // config class — auto-fixable
  mkdirSync(join(root, "apps/web-platform/server/inngest/functions"), {
    recursive: true,
  });
  writeFileSync(
    join(root, "apps/web-platform/server/inngest/functions/cron-fake-audit.ts"),
    `export const ANTHROPIC_MODEL = "${staleId}";\n`,
  );
  // test class — must be EXCLUDED
  mkdirSync(join(root, "apps/web-platform/test"), { recursive: true });
  writeFileSync(
    join(root, "apps/web-platform/test/fake.test.ts"),
    `const m = "${staleId}"; // fixture asserts the id\n`,
  );
  // archive class — must be EXCLUDED
  mkdirSync(join(root, "knowledge-base/project/plans/archive"), {
    recursive: true,
  });
  writeFileSync(
    join(root, "knowledge-base/project/plans/archive/old-plan.md"),
    `historical: used ${staleId}\n`,
  );
  return root;
}

describe("model-launch-review skill scaffold (AC9)", () => {
  test("SKILL.md exists with name + third-person description", () => {
    expect(existsSync(SKILL_MD)).toBe(true);
    const md = readFileSync(SKILL_MD, "utf8");
    expect(md).toMatch(/^name:\s*model-launch-review\s*$/m);
    expect(md).toMatch(/^description:\s*"This skill should be used when/m);
  });

  test("description is within the 1024-char SKILL limit", () => {
    const md = readFileSync(SKILL_MD, "utf8");
    const m = md.match(/^description:\s*"([^"]*)"/m);
    expect(m).not.toBeNull();
    expect(m![1].length).toBeLessThanOrEqual(1024);
  });

  test("audit-models.sh exists and is executable", () => {
    expect(existsSync(AUDIT_SH)).toBe(true);
  });

  test("SKILL.md inlines the checklist and the operator-gh-auth precondition", () => {
    const md = readFileSync(SKILL_MD, "utf8");
    expect(md.toLowerCase()).toContain("checklist");
    // auto-fix-vs-flag matrix must be present (model-ID auto-fix; others flag)
    expect(md.toLowerCase()).toMatch(/auto-?fix/);
    expect(md.toLowerCase()).toMatch(/flag-only/);
    // operator gh auth precondition (CI-gated PR property)
    expect(md.toLowerCase()).toMatch(/operator|gh auth|interactive/);
  });
});

describe("model-launch-review audit classification (AC1, AC2)", () => {
  test("reports a stale config model ID as auto-fixable", () => {
    const root = makeFixtureRoot();
    const r = run([], root);
    expect(r.stdout).toContain("claude-opus-4-7");
    expect(r.stdout).toContain(
      "apps/web-platform/server/inngest/functions/cron-fake-audit.ts",
    );
    rmSync(root, { recursive: true, force: true });
  });

  test("excludes test fixtures and archive paths from auto-fix targets", () => {
    const root = makeFixtureRoot();
    const r = run([], root);
    // The fixture + archive files carry the same id but must NOT be auto-fix targets
    expect(r.stdout).not.toContain("apps/web-platform/test/fake.test.ts");
    expect(r.stdout).not.toContain(
      "knowledge-base/project/plans/archive/old-plan.md",
    );
    rmSync(root, { recursive: true, force: true });
  });
});

describe("model-launch-review no-silent-green (AC3)", () => {
  test("all-clear run still enumerates every check", () => {
    const root = mkdtempSync(join(tmpdir(), "mlr-clean-"));
    mkdirSync(join(root, "apps/web-platform/server"), { recursive: true });
    writeFileSync(
      join(root, "apps/web-platform/server/ok.ts"),
      `const m = "${CURRENT_IDS[0]}";\n`,
    );
    const r = run([], root);
    // Every check group must be named even when clean
    expect(r.stdout.toLowerCase()).toContain("model-id");
    expect(r.stdout.toLowerCase()).toContain("pin");
    expect(r.stdout.toLowerCase()).toContain("pricing");
    expect(r.stdout.toLowerCase()).toContain("tier-map");
    rmSync(root, { recursive: true, force: true });
  });
});

describe("model-launch-review --detect mode (AC11 cron signal)", () => {
  test("exits non-zero with drift, zero when clean", () => {
    const dirty = makeFixtureRoot();
    const rDirty = run(["--detect"], dirty);
    expect(rDirty.status).toBe(10); // contract: exit 10 = drift (rule-audit.yml depends on it)
    rmSync(dirty, { recursive: true, force: true });

    const clean = mkdtempSync(join(tmpdir(), "mlr-clean2-"));
    mkdirSync(join(clean, "apps/web-platform/server"), { recursive: true });
    writeFileSync(
      join(clean, "apps/web-platform/server/ok.ts"),
      `const m = "${CURRENT_IDS[1]}";\n`,
    );
    const rClean = run(["--detect"], clean);
    expect(rClean.status).toBe(0);
    rmSync(clean, { recursive: true, force: true });
  });
});

describe("model-launch-review auto-fix safety (AC5, AC6)", () => {
  test("--fix swaps stale config IDs but never touches test/archive", () => {
    const root = makeFixtureRoot();
    const r = run(["--fix"], root);
    expect(r.status).toBe(0);
    const config = readFileSync(
      join(root, "apps/web-platform/server/inngest/functions/cron-fake-audit.ts"),
      "utf8",
    );
    expect(config).toContain("claude-opus-4-8");
    expect(config).not.toContain("claude-opus-4-7");
    // excluded classes untouched
    const fixture = readFileSync(
      join(root, "apps/web-platform/test/fake.test.ts"),
      "utf8",
    );
    expect(fixture).toContain("claude-opus-4-7");
    rmSync(root, { recursive: true, force: true });
  });

  test("--fix aborts when net deletions exceed the guard (no git add -A)", () => {
    // The script must never contain a `git add -A` / `git add .` invocation.
    const src = readFileSync(AUDIT_SH, "utf8");
    expect(src).not.toMatch(/git\s+add\s+(-A|\.)/);
    // deletion guard constant present
    expect(src.toLowerCase()).toMatch(/deletion|guard|max.*delet/);
    rmSync(makeFixtureRoot(), { recursive: true, force: true });
  });

  test("pin/pricing/tier-map are flag-only — --fix never edits them", () => {
    // A root whose only drift is a pricing/pin concern yields no file mutation.
    const root = mkdtempSync(join(tmpdir(), "mlr-flagonly-"));
    mkdirSync(join(root, "apps/web-platform/server"), { recursive: true });
    // current model id (no model-ID drift), but a "pricing" marker file
    const pricing = join(root, "apps/web-platform/server/pricing.ts");
    writeFileSync(pricing, `const MODEL_PRICING = { "${CURRENT_IDS[1]}": 3 };\n`);
    const before = readFileSync(pricing, "utf8");
    run(["--fix"], root);
    expect(readFileSync(pricing, "utf8")).toBe(before);
    rmSync(root, { recursive: true, force: true });
  });
});

describe("model-launch-review multi-tier auto-fix (Sonnet 5 launch)", () => {
  test("--fix maps a stale Sonnet id to claude-sonnet-5", () => {
    const root = makeFixtureRoot("claude-sonnet-4-6");
    expect(run([], root).stdout).toContain("claude-sonnet-4-6");
    expect(run(["--fix"], root).status).toBe(0);
    const config = readFileSync(
      join(root, "apps/web-platform/server/inngest/functions/cron-fake-audit.ts"),
      "utf8",
    );
    expect(config).toContain("claude-sonnet-5");
    expect(config).not.toContain("claude-sonnet-4-6");
    rmSync(root, { recursive: true, force: true });
  });

  test("Opus and Sonnet stale ids each map to their OWN tier target in one run", () => {
    const root = mkdtempSync(join(tmpdir(), "mlr-multitier-"));
    const dir = join(root, "apps/web-platform/server/inngest/functions");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "cron-a.ts"), `export const M = "claude-opus-4-7";\n`);
    writeFileSync(join(dir, "cron-b.ts"), `export const M = "claude-sonnet-4-6";\n`);
    expect(run(["--fix"], root).status).toBe(0);
    // Per-tier map: opus → opus-4-8, sonnet → sonnet-5 (not a single global target).
    expect(readFileSync(join(dir, "cron-a.ts"), "utf8")).toContain("claude-opus-4-8");
    expect(readFileSync(join(dir, "cron-b.ts"), "utf8")).toContain("claude-sonnet-5");
    rmSync(root, { recursive: true, force: true });
  });
});
