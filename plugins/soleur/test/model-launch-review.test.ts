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

// Current model landscape (2026-09). The auditor flags anything NOT in this set
// that lives in a config-class path. Source of truth: claude-api skill table +
// https://platform.claude.com/docs/en/about-claude/models/overview.md.
// `claude-fable-5` moved OUT of this set at the Fable 5.1 launch — it is now a
// source id (still served, but superseded in-tier by `claude-fable-5-1`).
const CURRENT_IDS = [
  "claude-opus-5",
  "claude-sonnet-5",
  "claude-haiku-4-5-20251001",
  "claude-fable-5-1",
];

/** Parse AUTOFIX_PAIRS out of the script so tests are driven BY the table
 * rather than restating a hand-picked member of it. */
function parseAutofixPairs(): Array<[string, string]> {
  const src = readFileSync(AUDIT_SH, "utf8");
  const block = src.match(/AUTOFIX_PAIRS=\(([\s\S]*?)\)/);
  if (!block) throw new Error("AUTOFIX_PAIRS block not found in audit-models.sh");
  return [...block[1].matchAll(/"([^"=]+)=([^"]+)"/g)].map(
    (m) => [m[1], m[2]] as [string, string],
  );
}

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
    // ...and it must actually REPORT clean. The four headings above print
    // unconditionally, so asserting only their presence passes identically on
    // a DIRTY root — this test's name was a claim its assertions did not back.
    // This line is what makes CURRENT_IDS[0] load-bearing.
    expect(r.stdout).toContain("none — config model IDs are current.");
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
    expect(config).toContain("claude-opus-5");
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

  test("EVERY declared pair maps its stale id to its own target", () => {
    // Population-of-one guard. The per-tier test below exercises ONE opus and
    // ONE sonnet id, so a pair can be deleted from AUTOFIX_PAIRS with the whole
    // suite green (proven: dropping the opus-4-8 pair — the one #6934 added —
    // changed nothing). Drive the table itself so adding a pair without
    // coverage is impossible.
    const pairs = parseAutofixPairs();
    expect(pairs.length).toBeGreaterThanOrEqual(5); // non-vacuity floor, not a pin

    const root = mkdtempSync(join(tmpdir(), "mlr-allpairs-"));
    const dir = join(root, "apps/web-platform/server/inngest/functions");
    mkdirSync(dir, { recursive: true });
    for (const [from] of pairs) {
      writeFileSync(join(dir, `cron-${from}.ts`), `export const M = "${from}";\n`);
    }
    expect(run(["--fix"], root).status).toBe(0);
    for (const [from, to] of pairs) {
      const got = readFileSync(join(dir, `cron-${from}.ts`), "utf8");
      expect(got).toContain(to);
      expect(got).not.toContain(`"${from}"`);
    }
    rmSync(root, { recursive: true, force: true });
  });

  test("AUTOFIX_PAIRS is single-hop and every target is a current id", () => {
    const pairs = parseAutofixPairs();
    const sources = new Set(pairs.map(([from]) => from));
    for (const [from, to] of pairs) {
      // Chaining (4-7=4-8 alongside 4-8=5) makes --fix order-dependent: files
      // land on an intermediate id and --detect re-flags them forever.
      expect(
        sources.has(to),
        `pair ${from}=${to} chains: '${to}' is itself a source id`,
      ).toBe(false);
      // A target that is not a current id means someone added a pair without
      // retargeting the tier at launch time.
      expect(CURRENT_IDS, `target '${to}' is not a current id`).toContain(to);
    }
  });

  test("the script itself refuses to run on a non-convergent pair table", () => {
    // Pin the guard's behavior, not just its presence: mutate a SANDBOX copy
    // into a chained table and assert it exits 78 rather than silently
    // producing a one-hop rewrite.
    const sandbox = mkdtempSync(join(tmpdir(), "mlr-chain-"));
    const copy = join(sandbox, "audit-models.sh");
    const src = readFileSync(AUDIT_SH, "utf8").replace(
      '"claude-opus-4-7=claude-opus-5"',
      '"claude-opus-4-7=claude-opus-4-8"',
    );
    writeFileSync(copy, src);
    const r = spawnSync("bash", [copy, "--root", sandbox, "--detect"], {
      encoding: "utf8",
    });
    expect(r.status).toBe(78);
    expect(r.stderr).toContain("NON-CONVERGENT");
    rmSync(sandbox, { recursive: true, force: true });
  });

  test("a stale id that is a PREFIX of its successor does not self-flag forever", () => {
    // Fable 5.1 is the first launch where the stale id (`claude-fable-5`) is a
    // strict prefix of its target (`claude-fable-5-1`). The --fix sed was
    // always boundary-anchored, but SELECTION was a bare alternation, so a file
    // already on the CURRENT id matched, --fix reported "fixed" while changing
    // nothing, and --detect re-flagged it on every run: a permanently-red drift
    // cron auto-filing issues it cannot fix. assert_single_hop does not catch
    // this ('claude-fable-5-1' is not itself a source id), so pin it here.
    //
    // Derived from the pair table, not hardcoded — this must keep holding at
    // the next launch that introduces a prefix-shadowed pair.
    const prefixPairs = parseAutofixPairs().filter(([from, to]) =>
      to.startsWith(from),
    );
    expect(
      prefixPairs.length,
      "expected at least one prefix-shadowed pair (claude-fable-5=claude-fable-5-1)",
    ).toBeGreaterThan(0);

    for (const [, to] of prefixPairs) {
      const root = mkdtempSync(join(tmpdir(), "mlr-prefix-"));
      const dir = join(root, "apps/web-platform/server/inngest/functions");
      mkdirSync(dir, { recursive: true });
      const file = join(dir, "cron-current.ts");
      // Already on the CURRENT id — nothing to do.
      writeFileSync(file, `export const M = "${to}";\n`);

      // POSITIVE CONTROL. Every other assertion here is an ABSENCE (status 0,
      // bytes unchanged) and is satisfied identically by the auditor never
      // running at all — a wrong AUDIT_SH path, a renamed script, a changed
      // --root arg. Require a side effect only the script can produce, or this
      // test cannot tell "the boundary works" from "nothing executed".
      const detected = run(["--detect"], root);
      expect(detected.stdout, "the auditor must actually have run").toContain(
        "model-drift: none",
      );
      expect(detected.status, `${to} must read as clean`).toBe(0);

      // And the rewriter must agree with the selector: no corruption into
      // `${to}-1`, and the file converges rather than oscillating.
      expect(run(["--fix"], root).status).toBe(0);
      expect(readFileSync(file, "utf8")).toBe(`export const M = "${to}";\n`);
      expect(run(["--detect"], root).status).toBe(0);

      rmSync(root, { recursive: true, force: true });
    }
  });

  test("the prefix invariant holds for a SYNTHESIZED pair, independent of today's table", () => {
    // The test above quantifies over the LIVE table, so it stops exercising the
    // prefix case the moment fable leaves the prefix family (`fable-5=fable-6`
    // and `fable-5-1=fable-6` share no prefix) — i.e. coverage would vanish at a
    // future launch, silently, while the `toBeGreaterThan(0)` floor turned that
    // correct table RED. Synthesize the case instead, the way the chained-table
    // test synthesizes its own, so the invariant is pinned unconditionally.
    const sandbox = mkdtempSync(join(tmpdir(), "mlr-synth-prefix-"));
    const script = join(sandbox, "audit-models.sh");
    const src = readFileSync(AUDIT_SH, "utf8").replace(
      '  "claude-fable-5=claude-fable-5-1"\n',
      '  "claude-fable-5=claude-fable-5-1"\n  "claude-zeta-1=claude-zeta-1-1"\n',
    );
    expect(src, "synthetic pair must have been injected").toContain(
      "claude-zeta-1=claude-zeta-1-1",
    );
    writeFileSync(script, src);

    const root = mkdtempSync(join(tmpdir(), "mlr-synth-root-"));
    const dir = join(root, "apps/web-platform/server/inngest/functions");
    mkdirSync(dir, { recursive: true });
    const onCurrent = join(dir, "cron-current.ts");
    const onStale = join(dir, "cron-stale.ts");
    writeFileSync(onCurrent, `export const M = "claude-zeta-1-1";\n`);
    writeFileSync(onStale, `export const M = "claude-zeta-1";\n`);

    const sh = (args: string[]) =>
      spawnSync("bash", [script, "--root", root, ...args], {
        encoding: "utf8",
      });

    // The stale one is drift; the current one must not be.
    expect(sh(["--detect"]).status).toBe(10);
    expect(sh(["--fix"]).status).toBe(0);
    expect(readFileSync(onStale, "utf8")).toBe(
      `export const M = "claude-zeta-1-1";\n`,
    );
    // Not corrupted into `claude-zeta-1-1-1`.
    expect(readFileSync(onCurrent, "utf8")).toBe(
      `export const M = "claude-zeta-1-1";\n`,
    );
    // Converges: a second pass finds nothing.
    expect(sh(["--detect"]).status).toBe(0);

    rmSync(sandbox, { recursive: true, force: true });
    rmSync(root, { recursive: true, force: true });
  });

  test("an id at end-of-line with no trailing newline is still detected", () => {
    // ID_BOUNDARY's `|$` alternative had ZERO coverage: every fixture in this
    // file writes `... = "<id>";\n`, so the id is always followed by `"` and the
    // `|$` limb is never exercised. Measured: dropping it from ID_BOUNDARY left
    // the whole suite green while `--detect` reported `model-drift: none`,
    // exit 0, on real drift — a false-clean detector, the #5100 class.
    const root = mkdtempSync(join(tmpdir(), "mlr-eol-"));
    const dir = join(root, "apps/web-platform/server/inngest/functions");
    mkdirSync(dir, { recursive: true });
    // No trailing newline, id is the last byte of the file.
    writeFileSync(join(dir, "cron.env"), `MODEL=claude-opus-4-7`);

    expect(run(["--detect"], root).status, "EOL id must be seen").toBe(10);
    expect(run(["--fix"], root).status).toBe(0);
    expect(readFileSync(join(dir, "cron.env"), "utf8")).toBe(
      `MODEL=claude-opus-5`,
    );
    expect(run(["--detect"], root).status).toBe(0);

    rmSync(root, { recursive: true, force: true });
  });

  test("--fix rewrites the stale id ONLY, leaving longer variants byte-identical", () => {
    // The `--fix` sed's anchoring was entirely untested: every fixture reaching
    // it held its stale id alone and quoted, so nothing after it needed
    // protecting. Three independent mutations of the sed — dropping the
    // boundary, dropping the backreference, and skewing the boundary charset
    // away from selection's — each left the suite 17/17 green while corrupting
    // real source (`claude-opus-4-7-20260101` -> `claude-opus-5-20260101`,
    // `claude-fable-5-1` -> `claude-fable-5-1-1`, and an eaten closing quote
    // that makes the file stop parsing). One fixture reds all three.
    const root = mkdtempSync(join(tmpdir(), "mlr-sed-anchor-"));
    const dir = join(root, "apps/web-platform/server/inngest/functions");
    mkdirSync(dir, { recursive: true });
    const file = join(dir, "cron-mixed.ts");
    const before =
      `export const STALE = "claude-opus-4-7";\n` +
      `export const DATED = "claude-opus-4-7-20260101";\n` +
      `export const CURRENT = "claude-fable-5-1";\n`;
    writeFileSync(file, before);

    expect(run(["--fix"], root).status).toBe(0);

    // Byte-exact: only the bare stale id moves. The dated variant is a DIFFERENT
    // model and must not be silently re-pointed; the current fable id must not
    // grow a second `-1`; the quoting must survive intact.
    expect(readFileSync(file, "utf8")).toBe(
      `export const STALE = "claude-opus-5";\n` +
        `export const DATED = "claude-opus-4-7-20260101";\n` +
        `export const CURRENT = "claude-fable-5-1";\n`,
    );

    rmSync(root, { recursive: true, force: true });
  });

  test("the [1] report names EVERY hit and renders ids without the boundary char", () => {
    // Two gaps in one fixture. (a) Every audit-mode fixture had exactly ONE
    // in-scope file, so truncating the report loop to `${hits[0]}` left the
    // suite green while the operator-facing inventory silently dropped every
    // hit but the first. (b) The display trim was unasserted: removing it
    // printed `[claude-opus-4-7" ]` and the only assertion was a substring
    // `toContain`, which the mangled form satisfies.
    const root = mkdtempSync(join(tmpdir(), "mlr-report-"));
    const dir = join(root, "apps/web-platform/server/inngest/functions");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "a.ts"), `export const M = "claude-opus-4-7";\n`);
    writeFileSync(join(dir, "b.ts"), `export const M = "claude-sonnet-4-6";\n`);

    const out = run([], root).stdout;
    // Both files named — not just the first.
    expect(out).toMatch(/a\.ts\s+\[claude-opus-4-7 \]/);
    expect(out).toMatch(/b\.ts\s+\[claude-sonnet-4-6 \]/);
    // And the boundary char the pattern had to capture is stripped.
    expect(out).not.toContain(`claude-opus-4-7"`);

    rmSync(root, { recursive: true, force: true });
  });

  test("[2b] distinguishes pin-matches-install, skew, and no-install", () => {
    // The whole [2b] version-comparison block had ZERO coverage: inverting its
    // `!=` to `==`, breaking the pin extraction, and deleting the block outright
    // all left the suite green. The inverted form is the dangerous one — it
    // prints "matches the package.json pin" on a genuine skew, the false-PASS
    // direction the block's own comment calls out as worse.
    const mk = (pinned: string, installed: string | null) => {
      const root = mkdtempSync(join(tmpdir(), "mlr-2b-"));
      const wp = join(root, "apps/web-platform");
      mkdirSync(join(wp, "server/inngest/leader-prompts"), { recursive: true });
      writeFileSync(
        join(wp, "package.json"),
        JSON.stringify({
          dependencies: { "@anthropic-ai/claude-code": pinned },
        }),
      );
      // The scanned registries the tier loop harvests ids from.
      writeFileSync(
        join(wp, "server/inngest/model-tiers.ts"),
        `export const AUDIT_MODEL = "claude-opus-5" as const;\n`,
      );
      writeFileSync(
        join(wp, "server/inngest/leader-prompts/constants.ts"),
        `export const SONNET_MODEL = "claude-sonnet-5" as const;\n`,
      );
      if (installed !== null) {
        const pkg = join(
          wp,
          "node_modules/@anthropic-ai/claude-code-linux-x64",
        );
        mkdirSync(pkg, { recursive: true });
        writeFileSync(
          join(pkg, "package.json"),
          JSON.stringify({ version: installed }),
        );
        // The bundle: carries opus-5 but NOT sonnet-5, so the tier loop must
        // report one ok and one DRIFT — proving the loop ran at all.
        writeFileSync(join(pkg, "cli.blob"), `\0claude-opus-5\0filler\n`);
      }
      return root;
    };

    // (a) pin === installed -> the reassuring line is legitimate.
    const same = mk("2.1.219", "2.1.219");
    const sameOut = run([], same).stdout;
    expect(sameOut).toContain("(matches the package.json pin)");
    expect(sameOut).toContain("ok      claude-opus-5");
    // Anchored presence probe: sonnet-5 is genuinely absent from this bundle.
    expect(sameOut).toContain("DRIFT   claude-sonnet-5");
    rmSync(same, { recursive: true, force: true });

    // (b) skew -> must NOT claim a match, and must say which is which.
    const skew = mk("2.1.219", "2.1.142");
    const skewOut = run([], skew).stdout;
    expect(skewOut).toContain("NOTE: measuring INSTALLED 2.1.142");
    expect(skewOut).toContain("but package.json pins 2.1.219");
    expect(skewOut).not.toContain("(matches the package.json pin)");
    rmSync(skew, { recursive: true, force: true });

    // (c) no install at all -> UNKNOWN, never a match. Guarding the reassuring
    // branch on the pin alone printed "matches the package.json pin" here,
    // directly above the UNKNOWN line contradicting it.
    const none = mk("2.1.219", null);
    const noneOut = run([], none).stdout;
    expect(noneOut).not.toContain("(matches the package.json pin)");
    expect(noneOut).toContain("installed: (none)");
    expect(noneOut).toContain("NOT a pass");
    rmSync(none, { recursive: true, force: true });
  });

  test("[2b] presence probe is anchored — a longer id does not vouch for its prefix", () => {
    // The probe was `grep -raqF`, unanchored on both sides, so a bundle holding
    // only `claude-opus-5-20260101` answered "ok present" for `claude-opus-5`
    // and even for the bare tier `claude-opus`. That is this file's own
    // prefix-shadowing class in the PRESENCE direction: the one tier whose id
    // the pin genuinely lacks reports green.
    const root = mkdtempSync(join(tmpdir(), "mlr-2b-anchor-"));
    const wp = join(root, "apps/web-platform");
    mkdirSync(join(wp, "server/inngest/leader-prompts"), { recursive: true });
    writeFileSync(
      join(wp, "package.json"),
      JSON.stringify({ dependencies: { "@anthropic-ai/claude-code": "9.9.9" } }),
    );
    writeFileSync(
      join(wp, "server/inngest/model-tiers.ts"),
      `export const AUDIT_MODEL = "claude-opus-5" as const;\n`,
    );
    writeFileSync(
      join(wp, "server/inngest/leader-prompts/constants.ts"),
      `export const X = "claude-haiku-4-5-20251001" as const;\n`,
    );
    const pkg = join(wp, "node_modules/@anthropic-ai/claude-code-linux-x64");
    mkdirSync(pkg, { recursive: true });
    writeFileSync(join(pkg, "package.json"), JSON.stringify({ version: "9.9.9" }));
    // Only the DATED opus id and the dated haiku id are in the bundle.
    writeFileSync(
      join(pkg, "cli.blob"),
      `\0claude-opus-5-20260101\0claude-haiku-4-5-20251001\0\n`,
    );

    // A SIBLING package under the same @anthropic-ai scope that DOES carry the
    // id. The probe used to grep the whole scope, so this package alone made
    // the answer "ok present in the pinned CLI bundle" while claude-code lacked
    // the id entirely — measured in this repo, where claude-agent-sdk and
    // claude-agent-sdk-linux-x64 both contain `claude-sonnet-5`. A false PASS on
    // the exact #6934 degradation [2b] exists to catch.
    const sibling = join(wp, "node_modules/@anthropic-ai/claude-agent-sdk");
    mkdirSync(sibling, { recursive: true });
    writeFileSync(join(sibling, "index.js"), `const m = "claude-opus-5";\n`);

    const out = run([], root).stdout;
    // The bare id is NOT vouched for by the longer one, NOR by the sibling package.
    expect(out).toContain("DRIFT   claude-opus-5");
    // Non-vacuity: an exact match in the same bundle still reports ok, so this
    // is anchoring rather than a probe that has stopped matching anything.
    expect(out).toContain("ok      claude-haiku-4-5-20251001");

    rmSync(root, { recursive: true, force: true });
  });

  test("a BINARY file carrying a stale id is never selected or rewritten", () => {
    // Selection used `grep -rEl` with no -I, so a compiled artifact under $ROOT
    // was a legitimate hit: measured, a blob holding `claude-opus-4-7` between
    // NULs was reported as a stale config file, the [1] re-scan could not read
    // it back (`grep -o` on binary yields no stdout and exits 0), and `--fix`
    // would `sed -i` the binary in place and print `fixed:`. This skill's own
    // SKILL.md makes that reachable by telling the operator to unpack
    // `claude-code-linux-x64` and grep it.
    const root = mkdtempSync(join(tmpdir(), "mlr-binary-"));
    const dir = join(root, "apps/web-platform/server/inngest/functions");
    mkdirSync(dir, { recursive: true });
    const blob = join(dir, "cli.blob");
    const bytes = Buffer.from(`junk\0claude-opus-4-7\0more\n`, "binary");
    writeFileSync(blob, bytes);
    // A real text hit alongside it, so this fixture cannot pass vacuously by
    // the auditor simply finding nothing anywhere.
    writeFileSync(join(dir, "real.ts"), `export const M = "claude-opus-4-7";\n`);

    const audit = run([], root);
    expect(audit.status, "the binary must not abort the audit").toBe(0);
    expect(audit.stdout).toContain("real.ts");
    expect(audit.stdout, "binaries are not config class").not.toContain(
      "cli.blob",
    );

    expect(run(["--fix"], root).status).toBe(0);
    expect(
      readFileSync(blob),
      "the binary must be byte-identical after --fix",
    ).toEqual(bytes);

    rmSync(root, { recursive: true, force: true });
  });

  test("Opus and Sonnet stale ids each map to their OWN tier target in one run", () => {
    const root = mkdtempSync(join(tmpdir(), "mlr-multitier-"));
    const dir = join(root, "apps/web-platform/server/inngest/functions");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "cron-a.ts"), `export const M = "claude-opus-4-7";\n`);
    writeFileSync(join(dir, "cron-b.ts"), `export const M = "claude-sonnet-4-6";\n`);
    expect(run(["--fix"], root).status).toBe(0);
    // Per-tier map: opus → opus-5, sonnet → sonnet-5 (not a single global target).
    expect(readFileSync(join(dir, "cron-a.ts"), "utf8")).toContain("claude-opus-5");
    expect(readFileSync(join(dir, "cron-b.ts"), "utf8")).toContain("claude-sonnet-5");
    rmSync(root, { recursive: true, force: true });
  });
});
