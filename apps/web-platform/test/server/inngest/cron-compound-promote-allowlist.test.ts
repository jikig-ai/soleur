// Guard 2 (#8274) — the proposal diff path allowlist.
//
// The shipped filter inspected lines starting with `+++ b/` and checked those
// against TARGET_ALLOW_RE. `git apply` with no `-p` strips ONE leading path
// component, whatever it is — so `+++ x/...` and `+++ w/...` write files the
// filter never saw, `badPath` is undefined, and the allowlist passes vacuously.
//
// Every fixture below is a real patch fed to the real `git apply`, so the
// assertions are about what git DOES, not about what a hand-written parser
// believes. Rows 3, 6, 7, 8 and 10 are measured bypasses of the shipped filter.
import { describe, expect, it, beforeAll, afterAll } from "vitest";
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { vi } from "vitest";
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { checkDiffPaths } from "@/server/inngest/functions/cron-compound-promote";
import { gitFixture } from "../../../../../plugins/soleur/test/lib/git-fixture-env";

let repoRoot: string;
let git: (args: string[]) => string;

const SKILL_A = "plugins/soleur/skills/alpha/SKILL.md";
const SKILL_B = "plugins/soleur/skills/beta/SKILL.md";

beforeAll(() => {
  repoRoot = mkdtempSync(join(tmpdir(), "compound-allowlist-"));
  git = gitFixture(repoRoot);
  git(["init", "-q", "."]);
  writeFileSync(join(repoRoot, "AGENTS.rules.md"), "rules\nsecond line\n");
  mkdirSync(join(repoRoot, "plugins/soleur/skills/alpha"), { recursive: true });
  writeFileSync(join(repoRoot, SKILL_A), "skill alpha\nbody\n");
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

  it("row 3: two-file diff, first allowed and second forbidden, is REFUSED", async () => {
    const diff = patchFor(() => {
      writeFileSync(join(repoRoot, "AGENTS.rules.md"), "rules\nsecond line\nok\n");
      mkdirSync(join(repoRoot, ".github/workflows"), { recursive: true });
      writeFileSync(join(repoRoot, ".github/workflows/evil.yml"), "on: push\n");
    });
    const verdict = await checkDiffPaths(diff, repoRoot);
    expect(verdict.ok).toBe(false);
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
});
