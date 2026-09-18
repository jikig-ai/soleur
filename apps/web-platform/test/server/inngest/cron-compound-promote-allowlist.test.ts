// Guard 2 (#8274) — the proposal diff path allowlist.
//
// The shipped filter inspected lines starting with `+++ b/` and checked those
// against TARGET_ALLOW_RE. `git apply` with no `-p` strips ONE leading path
// component, whatever it is — so `+++ x/...` and `+++ w/...` write files the
// filter never saw, `badPath` is undefined, and the allowlist passes vacuously.
//
// Most fixtures below are real patches fed to the real `git apply`, so the
// assertions are about what git DOES, not about what a hand-written parser
// believes. Rows 10 and 11 are hand-written on purpose: a git-GENERATED patch
// cannot express them, and that is exactly why they went unnoticed.
//
// Which rows are measured bypasses of the SHIPPED filter: every refusal row
// EXCEPT 3b. An earlier revision of this header said "rows 3, 6, 7, 8 and 10",
// which was wrong three ways — row 3's canonical two-file diff emits
// `+++ b/.github/...` and the old filter CAUGHT it (a control, not a bypass);
// there was no row 10 at the time; and rows 1, 2, 4, 5 and 9 are bypasses that
// went unlisted. Re-derived by replaying the old filter over each fixture.
import { beforeEach, describe, expect, it, beforeAll, afterAll } from "vitest";
import {
  mkdtempSync,
  rmSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  readFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { vi } from "vitest";
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  checkDiffPaths,
  TARGET_ALLOW_RE,
  MIN_TARGET_RETENTION,
  promotionShrankTarget,
} from "@/server/inngest/functions/cron-compound-promote";
import { gitFixture } from "../../../../../plugins/soleur/test/lib/git-fixture-env";

let repoRoot: string;
let git: (args: string[]) => string;

const SKILL_A = "plugins/soleur/skills/alpha/SKILL.md";
const SKILL_B = "plugins/soleur/skills/beta/SKILL.md";
// A HYPHENATED skill dir. 77 of the repo's 99 real skill directories contain a
// character outside [a-z]; every earlier fixture used `alpha`, so narrowing
// TARGET_ALLOW_RE to `[a-z]+` silently refused 78% of the guard's real targets
// with the whole suite green.
const SKILL_HYPHEN = "plugins/soleur/skills/agent-browser/SKILL.md";
// A pre-existing NON-allowlisted file. Row 3 used to create `.github/workflows/
// evil.yml`, which git reports as a CREATION — so it was refused at the
// structural gate and never reached the allowlist loop at all. That left the
// loop only ever driven with a one-element array, and `paths.find(...)` →
// `[paths[0]].find(...)` survived the whole suite.
const OUTSIDE = "README.md";

beforeAll(() => {
  repoRoot = mkdtempSync(join(tmpdir(), "compound-allowlist-"));
  git = gitFixture(repoRoot);
  git(["init", "-q", "."]);
  writeFileSync(join(repoRoot, "AGENTS.rules.md"), "rules\nsecond line\n");
  writeFileSync(join(repoRoot, OUTSIDE), "readme\nbody\n");
  mkdirSync(join(repoRoot, "plugins/soleur/skills/alpha"), { recursive: true });
  writeFileSync(join(repoRoot, SKILL_A), "skill alpha\nbody\n");
  mkdirSync(join(repoRoot, "plugins/soleur/skills/agent-browser"), { recursive: true });
  writeFileSync(join(repoRoot, SKILL_HYPHEN), "skill hyphen\nbody\n");
  git(["add", "-A"]);
  git(["commit", "-qm", "init"]);
});

afterAll(() => {
  rmSync(repoRoot, { recursive: true, force: true });
});

/** Capture a patch for the current worktree state, then restore it. */
function patchFor(mutate: () => void): string {
  mutate();
  git(["add", "-A"]);
  const diff = git(["diff", "--cached"]);
  git(["reset", "-q", "--hard", "HEAD"]);
  return diff;
}

// Assertion floor. Stripping every `expect` from this file left it reporting
// "N passed", exit 0 -- indistinguishable from a suite that pins something.
// `requireAssertions` at the runner would be stronger, but it fails 174
// pre-existing tests across 28 unrelated files (measured), so it is scoped
// here: every test in this file must assert at least once.
beforeEach(() => {
  expect.hasAssertions();
});

describe("Guard 2 — diff path derivation (#8274)", () => {
  // -- must-PASS controls: the guard must not refuse everything -------------

  it("row 0a (must-PASS): a plain content edit of AGENTS.rules.md is allowed", async () => {
    const diff = patchFor(() =>
      writeFileSync(join(repoRoot, "AGENTS.rules.md"), "rules\nsecond line\nadded\n"),
    );
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(true);
    if (verdict.ok) expect(verdict.paths).toEqual(["AGENTS.rules.md"]);
  });

  it("row 0b (must-PASS, non-canonical): a legitimate TWO-file edit still applies", async () => {
    const diff = patchFor(() => {
      writeFileSync(join(repoRoot, "AGENTS.rules.md"), "rules\nsecond line\nx\n");
      writeFileSync(join(repoRoot, SKILL_A), "skill alpha\nbody\ny\n");
    });
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(true);
    if (verdict.ok) expect(verdict.paths.sort()).toEqual(["AGENTS.rules.md", SKILL_A].sort());
  });

  // -- mutation matrix ------------------------------------------------------

  it("row 1: a `+++ x/` prefix variant is REFUSED (measured: it applies today)", async () => {
    // Written from scratch, not derived from a git-produced canonical — the
    // harness row that proves the RED fixtures are not all one mutation of one
    // captured patch.
    const diff = [
      "diff --git x/.github/workflows/foo.yml x/.github/workflows/foo.yml",
      "--- /dev/null",
      "+++ x/.github/workflows/foo.yml",
      "@@ -0,0 +1 @@",
      "+evil: true",
      "",
    ].join("\n");
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
  });

  it("row 2: a diff with no `+++` header at all is REFUSED (empty derived set)", async () => {
    const verdict = await checkDiffPaths("not a diff at all\n", repoRoot);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("underivable");
  });

  it("row 3: two EDITS, first allowed and second forbidden, is REFUSED at the ALLOWLIST", async () => {
    // Both files pre-exist, so both records are `M` and the verdict must come
    // from TARGET_ALLOW_RE rather than from the structural gate. This is the
    // only row that drives the allowlist loop with more than one element —
    // without it, checking just `paths[0]` passes the whole suite.
    const diff = patchFor(() => {
      writeFileSync(join(repoRoot, "AGENTS.rules.md"), "rules\nsecond line\nok\n");
      writeFileSync(join(repoRoot, OUTSIDE), "readme\nbody\nedited\n");
    });
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
    // Assert the REASON and the offending path, not just `ok === false`: a
    // failure that does not say which gate moved is a failure you cannot act on.
    if (!verdict.ok) {
      expect(verdict.reason).toBe("path-refused");
      expect(verdict.detail).toBe(OUTSIDE);
    }
  });

  it("row 3b: a CREATED forbidden file alongside an allowed edit is REFUSED", async () => {
    // The shape row 3 used to have. Kept, because it is a real bypass of the
    // SHIPPED filter — it just refuses structurally, not at the allowlist.
    const diff = patchFor(() => {
      writeFileSync(join(repoRoot, "AGENTS.rules.md"), "rules\nsecond line\nok2\n");
      mkdirSync(join(repoRoot, ".github/workflows"), { recursive: true });
      writeFileSync(join(repoRoot, ".github/workflows/evil.yml"), "on: push\n");
    });
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("structural-op");
  });

  it("row 4: renaming AGENTS.rules.md into an allowlisted SKILL.md path is REFUSED", async () => {
    // The bypass Kieran's plan-review caught. BOTH paths are allowlisted, and
    // `--numstat` reports only the destination, so a numstat-only derivation
    // sees a fully-allowlisted set while the apply DELETES the rule corpus.
    const diff = patchFor(() => {
      mkdirSync(join(repoRoot, "plugins/soleur/skills/beta"), { recursive: true });
      git(["mv", "AGENTS.rules.md", SKILL_B]);
    });
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("structural-op");
    // The property, not the proxy: the corpus survives.
    expect(existsSync(join(repoRoot, "AGENTS.rules.md"))).toBe(true);
  });

  it("row 5: a copy of AGENTS.rules.md into an allowlisted path is REFUSED", async () => {
    const diff = [
      "diff --git a/AGENTS.rules.md b/plugins/soleur/skills/gamma/SKILL.md",
      "similarity index 100%",
      "copy from AGENTS.rules.md",
      "copy to plugins/soleur/skills/gamma/SKILL.md",
      "",
    ].join("\n");
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
  });

  it("row 6: DELETING an allowlisted file is REFUSED", async () => {
    const diff = patchFor(() => {
      git(["rm", "-q", SKILL_A]);
    });
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("structural-op");
  });

  it("row 7: CREATING a new file is REFUSED (creation is Phase 2, #8293)", async () => {
    const diff = patchFor(() => {
      mkdirSync(join(repoRoot, "plugins/soleur/skills/delta"), { recursive: true });
      writeFileSync(join(repoRoot, "plugins/soleur/skills/delta/SKILL.md"), "new\n");
    });
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("structural-op");
  });

  it("row 8: a MODE CHANGE on an allowlisted path is REFUSED", async () => {
    // Nobody enumerated this shape; the empty-summary invariant catches it for
    // free. A proposal that makes a markdown file executable is not an edit.
    const diff = [
      "diff --git a/AGENTS.rules.md b/AGENTS.rules.md",
      "old mode 100644",
      "new mode 100755",
      "",
    ].join("\n");
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("structural-op");
  });

  it("row 9 (dispatch): a diff git cannot parse is REFUSED, never silently allowed", async () => {
    // The vacuity row. If the derivation yields nothing, the verdict must be a
    // refusal — an empty derived set must never read as "no forbidden paths".
    const verdict = await checkDiffPaths("", repoRoot);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("underivable");
  });

  it("row 10: an IMPLICIT rename (no rename headers) is REFUSED and the source survives", async () => {
    // The bypass that falsified the previous design. `git apply --summary` is
    // EMPTY for this shape and `--numstat` reports ONLY the destination, so a
    // summary+numstat derivation returned {ok:true, paths:["AGENTS.rules.md"]}
    // while the apply DELETED the source. Hand-written on purpose: row 4 uses
    // `git mv`, which emits `rename from`/`rename to`, and those headers are
    // the only reason row 4 ever caught anything. A model authoring a diff is
    // under no obligation to emit them.
    const diff = [
      `diff --git a/${SKILL_A} b/AGENTS.rules.md`,
      `--- a/${SKILL_A}`,
      "+++ b/AGENTS.rules.md",
      "@@ -1,2 +1,3 @@",
      " skill alpha",
      " body",
      "+- [id: hr-attacker-controlled-rule]",
      "",
    ].join("\n");
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("structural-op");
    // The property, not the proxy: the source file is still on disk.
    expect(existsSync(join(repoRoot, SKILL_A))).toBe(true);
  });

  it("row 11: a GIT binary patch on an allowlisted path is REFUSED", async () => {
    // Measured: a binary hunk yields an EMPTY --summary, derives as a plain
    // `M` on an allowlisted path, and carries no `-` lines at all — so it also
    // makes diffRemovesHardRule vacuous. The post-apply byte budget only
    // catches GROWTH, so a wholesale shrink of the corpus passed every gate.
    const diff = [
      "diff --git a/AGENTS.rules.md b/AGENTS.rules.md",
      "index 8baef1b..b3f1c2d 100644",
      "GIT binary patch",
      "literal 5",
      "McmWFt_ha}E00i0r^#A|>",
      "",
      "literal 0",
      "HcmV?d00001",
      "",
    ].join("\n");
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("structural-op");
  });

  // -- allowlist SHAPE: pins TARGET_ALLOW_RE itself ---------------------------
  // Nothing pinned the regex before. Six independent mutations of it — dropping
  // `0-9_-`, dropping either anchor, widening to `.+`, adding /i, dropping the
  // dot escapes — each survived all eleven rows, because every fixture used the
  // single skill dir `alpha` and no row ever exercised a near-miss path.

  it("row 12 (must-PASS): a hyphenated skill directory is allowed", async () => {
    const diff = patchFor(() =>
      writeFileSync(join(repoRoot, SKILL_HYPHEN), "skill hyphen\nbody\nmore\n"),
    );
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(true);
    if (verdict.ok) expect(verdict.paths).toEqual([SKILL_HYPHEN]);
  });

  it("row 13: near-miss paths are all REFUSED by the allowlist regex", () => {
    // Driven against the regex directly: these are paths the fixture repo does
    // not contain, and the point is the predicate, not git's behaviour.
    for (const good of [
      "AGENTS.rules.md",
      "plugins/soleur/skills/alpha/SKILL.md",
      "plugins/soleur/skills/agent-browser/SKILL.md",
      "plugins/soleur/skills/cf_token_scope/SKILL.md",
      "plugins/soleur/skills/seo-aeo-2/SKILL.md",
    ]) {
      expect(TARGET_ALLOW_RE.test(good)).toBe(true);
    }
    for (const bad of [
      "AGENTS.rules.md.bak",
      "AGENTS.rules.mdx",
      "x/AGENTS.rules.md",
      "AGENTSxrulesxmd",
      "agents.rules.md",
      "plugins/soleur/skills/a/b/SKILL.md",
      "plugins/soleur/skills/alpha/SKILL.md.bak",
      "plugins/soleur/skills/alpha/NOTICE",
      "plugins/soleur/skills//SKILL.md",
      ".github/workflows/deploy.yml",
    ]) {
      expect(TARGET_ALLOW_RE.test(bad)).toBe(false);
    }
  });

  // -- over-aggression controls: the guard must not refuse LEGITIMATE edits ---
  // Row 0b was the only detector of an over-aggressive guard, and it only fires
  // on mutations that correlate with size. Every over-aggression orthogonal to
  // size — refusing a no-newline-at-EOF marker, refusing CRLF, refusing a
  // second hunk within one file — stayed green.

  it("row 14 (must-PASS): an edit with no trailing newline is allowed", async () => {
    const diff = patchFor(() =>
      writeFileSync(join(repoRoot, "AGENTS.rules.md"), "rules\nsecond line\nno-eol"),
    );
    expect(diff).toContain("\\ No newline at end of file");
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(true);
  });

  it("row 15 (must-PASS): a two-hunk edit of a SINGLE file is allowed", async () => {
    const many = Array.from({ length: 40 }, (_, i) => `line ${i}`).join("\n");
    git(["rm", "-q", "--cached", "AGENTS.rules.md"]);
    writeFileSync(join(repoRoot, "AGENTS.rules.md"), `${many}\n`);
    git(["add", "-A"]);
    git(["commit", "-qm", "widen"]);
    const lines = many.split("\n");
    lines[1] = "line 1 EDITED";
    lines[38] = "line 38 EDITED";
    const diff = patchFor(() =>
      writeFileSync(join(repoRoot, "AGENTS.rules.md"), `${lines.join("\n")}\n`),
    );
    expect((diff.match(/^@@ /gm) ?? []).length).toBe(2);
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(true);
  });
});

/**
 * Guard 2b — the CHOKEPOINT census the plan specified and the suite never had.
 *
 * Every row above drives `checkDiffPaths` in isolation. That pins the
 * FUNCTION and says nothing about whether anything CALLS it: deleting the
 * `if (!pathVerdict.ok)` block from the handler left all of Guard 2 green.
 * Two covered endpoints, one uncovered wire.
 */
const SRC = join(
  __dirname, "..", "..", "..", "server", "inngest", "functions", "cron-compound-promote.ts",
);

describe("Guard 2b — every apply site is behind the derivation", () => {
  /** Comment-strip: this file documents the constructs it forbids. */
  function code(): string {
    return readFileSync(SRC, "utf-8")
      .split("\n")
      .map((l: string) => l.replace(/^\s*\/\/.*$/, "").replace(/^\s*\*.*$/, ""))
      .join("\n");
  }

  it("census: every git `apply` argv sits inside the derivation or the applier", () => {
    const lines = code().split("\n");
    const applySites = lines
      .map((l, i) => ({ l, i }))
      .filter(({ l }) => /spawnGit(Capture)?\(\[\s*"apply"/.test(l));
    // Anti-vacuity: a census that finds nothing must FAIL, not read clean.
    expect(applySites.length).toBeGreaterThanOrEqual(3);

    const src = code();
    const derivStart = src.indexOf("export async function checkDiffPaths");
    const applierStart = src.indexOf("async function applyDiffToWorkspace");
    expect(derivStart).toBeGreaterThan(-1);
    expect(applierStart).toBeGreaterThan(-1);
    const lineOf = (idx: number) => src.slice(0, idx).split("\n").length - 1;
    const derivL = lineOf(derivStart);
    const applierL = lineOf(applierStart);
    // Each function's body ends at the next top-level `}` — sufficient here
    // because both are top-level declarations with no sibling between them.
    const endOf = (from: number) => {
      for (let i = from + 1; i < lines.length; i++) if (lines[i] === "}") return i;
      return lines.length;
    };
    const inDeriv = (n: number) => n > derivL && n < endOf(derivL);
    const inApplier = (n: number) => n > applierL && n < endOf(applierL);

    const unclassified = applySites
      .filter(({ i }) => !inDeriv(i) && !inApplier(i))
      .map(({ l, i }) => `L${i + 1}: ${l.trim()}`);
    // An UNCLASSIFIED bucket, not a count: a new apply site added anywhere
    // else is the thing this census exists to catch.
    expect(unclassified).toEqual([]);
  });

  it("the handler calls checkDiffPaths BEFORE applyDiffToWorkspace, and refuses on !ok", () => {
    const src = code();
    const check = src.indexOf("await checkDiffPaths(cluster.proposed_diff_unified");
    const apply = src.indexOf("await applyDiffToWorkspace(cluster.proposed_diff_unified");
    expect(check).toBeGreaterThan(-1);
    expect(apply).toBeGreaterThan(-1);
    expect(check).toBeLessThan(apply);
    // Ordering alone is spelling: the refusal must also be WIRED. Anchor on
    // the early-return a comment cannot produce.
    const between = src.slice(check, apply);
    expect(between).toMatch(/if \(!pathVerdict\.ok\)/);
    // The reason is bound to a local (`const reason = \`diff-${…}\``), so anchor
    // on the refusal RETURN inside the !ok block rather than on an inline
    // template literal the code does not have. Verified against the source.
    const block = between.slice(between.indexOf("if (!pathVerdict.ok)"));
    expect(block).toMatch(/return \{ kind: "refused", reason/);
    expect(block.indexOf("return { kind:")).toBeGreaterThan(-1);
  });
});

describe("Guard 4 — the post-apply shrink floor", () => {
  // The byte budget was a CEILING only. A diff that emptied AGENTS.rules.md,
  // or replaced 40 kB with 40 bytes via a binary hunk or an implicit rename,
  // passed every gate. This floor asserts the PROPERTY on the tree.
  it("a rule-count drop of ONE refuses regardless of bytes", () => {
    expect(promotionShrankTarget({ rulesBefore: 98, rulesAfter: 97, bytesBefore: 1000, bytesAfter: 5000 })).toBe(true);
  });
  it("exactly at the retention floor passes; one byte under refuses", () => {
    const before = 1000;
    const floor = Math.floor(before * MIN_TARGET_RETENTION);
    expect(promotionShrankTarget({ rulesBefore: 5, rulesAfter: 5, bytesBefore: before, bytesAfter: floor })).toBe(false);
    expect(promotionShrankTarget({ rulesBefore: 5, rulesAfter: 5, bytesBefore: before, bytesAfter: floor - 1 })).toBe(true);
  });
  it("growth and a same-size rewording both pass (over-aggression control)", () => {
    expect(promotionShrankTarget({ rulesBefore: 5, rulesAfter: 6, bytesBefore: 1000, bytesAfter: 1200 })).toBe(false);
    expect(promotionShrankTarget({ rulesBefore: 5, rulesAfter: 5, bytesBefore: 1000, bytesAfter: 1000 })).toBe(false);
  });
  it("the WIRE: the handler consults the floor between the apply and the commit", () => {
    const src = readFileSync(SRC, "utf-8")
      .split("\n").map((l: string) => l.replace(/^\s*\/\/.*$/, "")).join("\n");
    const apply = src.indexOf("await applyDiffToWorkspace(cluster.proposed_diff_unified");
    const floor = src.indexOf("promotionShrankTarget({");
    const commit = src.indexOf("await safeCommitAndPr({");
    expect(apply).toBeGreaterThan(-1);
    expect(floor).toBeGreaterThan(apply);
    expect(commit).toBeGreaterThan(floor);
    const between = src.slice(floor, commit);
    expect(between).toMatch(/return \{ kind: "refused", reason: "corpus-shrink-refused" \}/);
  });
});
