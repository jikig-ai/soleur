// Ship Phase 2 learning probe — pins that the probe the agent runs is BRANCH-scoped (#8470).
//
// The pre-fix probe was `git log --oneline --since="1 week ago" -- knowledge-base/project/learnings/`,
// a repo-wide calendar window that was non-empty in 12 of 12 sampled weeks, so a literal read always
// concluded "a learning exists" and compound never ran. This suite extracts the ONE fenced block in
// `## Phase 2: Capture Learnings` and EXECUTES it against fixture repositories with a real local bare
// `origin`, asserting the exact verdict line. It pins behaviour, not bytes: any block that answers
// the eleven rows correctly passes, and the pre-fix block fails every row (it prints hashes or
// nothing, never a `BRANCH_LEARNING=` token).
//
// Test harness: bun:test, per-gate file like ship-pr-title-guard.test.ts. Git runs through
// gitFixture / gitFixtureEnv (fixture-env-adoption.test.sh enforces that).

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { resolve, join } from "path";
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { spawnSync } from "child_process";

import { gitFixture, gitFixtureEnv } from "./lib/git-fixture-env";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");
const HEADING = "## Phase 2: Capture Learnings";
// Any fence opener or closer: backtick or tilde, three or more, optionally indented (a fence
// under a list item still executes as far as the agent is concerned).
const FENCE = /^\s*(`{3,}|~{3,})/;

const LEARNINGS = "knowledge-base/project/learnings";

/** The Phase 2 section: from the heading to the next `## ` heading that is not inside a fence. */
function phase2Section(skill: string): string[] | null {
  const lines = skill.split("\n");
  const start = lines.findIndex((l) => l.startsWith(HEADING));
  if (start === -1) return null;
  const out: string[] = [];
  let inFence = false;
  for (let i = start + 1; i < lines.length; i++) {
    const l = lines[i];
    if (FENCE.test(l)) inFence = !inFence;
    if (!inFence && l.startsWith("## ")) break;
    out.push(l);
  }
  return out;
}

function fenceLines(section: string[]): number[] {
  return section.flatMap((l, i) => (FENCE.test(l) ? [i] : []));
}

/** The body of the section's first fenced block, or "" if there is none. */
function probeBlock(section: string[]): string {
  const f = fenceLines(section);
  if (f.length < 2) return "";
  return section.slice(f[0] + 1, f[1]).join("\n");
}

let section: string[] | null;
let block: string;
const roots: string[] = [];

beforeAll(() => {
  section = phase2Section(readFileSync(SHIP_SKILL, "utf8"));
  block = section ? probeBlock(section) : "";
});

afterAll(() => {
  for (const r of roots) rmSync(r, { recursive: true, force: true });
});

describe("ship Phase 2 section shape", () => {
  test("the Phase 2 heading exists (a miss is a failure, not a skip)", () => {
    expect(section).not.toBeNull();
  });

  test("the section holds exactly one fenced block — the probe the agent runs", () => {
    const n = fenceLines(section ?? []).length;
    if (n !== 2) {
      throw new Error(
        `ship Phase 2 must contain exactly one fenced block — the learning probe the agent runs ` +
          `(found ${n} fence lines, want 2). A second block can re-introduce a repo-wide probe the ` +
          `behavioural rows never execute (#8470). Put other snippets in another phase.`,
      );
    }
    expect(block).toContain("BRANCH_LEARNING=");
  });

  test("no fenced line in the section ranges history by date (#8470 backstop)", () => {
    const s = section ?? [];
    let inFence = false;
    const bad: string[] = [];
    for (const l of s) {
      if (FENCE.test(l)) {
        inFence = !inFence;
        continue;
      }
      if (inFence && /--(since|after|until|before)\b/.test(l)) bad.push(l);
    }
    expect(bad).toEqual([]);
  });
});

/**
 * A fixture: `<root>/origin.git` (bare, branch main) and `<root>/work`, a clone-equivalent whose
 * main already carries one learning committed today — the state in which the pre-fix probe
 * answered "a learning exists" for every branch.
 */
function fixture(): { root: string; work: string; git: (a: string[]) => string } {
  const root = mkdtempSync(join(tmpdir(), "ship-learning-probe-"));
  roots.push(root);
  const work = join(root, "work");
  mkdirSync(work);
  gitFixture(root)(["init", "-q", "--bare", "-b", "main", "origin.git"]);
  const git = gitFixture(work);
  git(["init", "-q", "-b", "main"]);
  mkdirSync(join(work, LEARNINGS), { recursive: true });
  mkdirSync(join(work, "sub"), { recursive: true });
  writeFileSync(join(work, "sub/keep.txt"), "x\n");
  writeFileSync(join(work, LEARNINGS, "old.md"), "# old learning\n");
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "learning: old"]);
  git(["remote", "add", "origin", "../origin.git"]);
  git(["push", "-q", "origin", "HEAD:refs/heads/main"]);
  git(["fetch", "-q", "origin", "main"]);
  git(["checkout", "-q", "-b", "feat-x"]);
  writeFileSync(join(work, "code.txt"), "change\n");
  git(["add", "code.txt"]);
  git(["commit", "-q", "-m", "feat: unrelated change"]);
  return { root, work, git };
}

function runProbe(cwd: string, fixtureDir: string) {
  const env = { ...gitFixtureEnv(fixtureDir) };
  // gitFixtureEnv sweeps GIT_* only. BASH_ENV runs a file in every non-interactive bash, and an
  // exported SHELLOPTS=pipefail changes the pipeline's status — neither belongs in a verdict.
  for (const k of ["BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS"]) delete env[k];
  return spawnSync("bash", ["--noprofile", "--norc", "-c", block], { cwd, env, encoding: "utf8" });
}

function expectVerdict(cwd: string, fixtureDir: string, want: "present" | "absent") {
  const r = runProbe(cwd, fixtureDir);
  expect(r.stdout.trim()).toBe(`BRANCH_LEARNING=${want}`);
  expect(r.status).toBe(0);
}

describe("ship Phase 2 probe verdicts", () => {
  test("row 1 — main has a learning committed today, branch adds none → absent (the #8470 defect)", () => {
    const { work } = fixture();
    expectVerdict(work, work, "absent");
  });

  test("row 2 — untracked new learning → present", () => {
    const { work } = fixture();
    writeFileSync(join(work, LEARNINGS, "new.md"), "# new\n");
    expectVerdict(work, work, "present");
  });

  test("row 3 — committed new learning → present", () => {
    const { work, git } = fixture();
    writeFileSync(join(work, LEARNINGS, "new.md"), "# new\n");
    git(["add", "-A"]);
    git(["commit", "-q", "-m", "docs: add a note"]);
    expectVerdict(work, work, "present");
  });

  test("row 4 — committed modification of an existing learning (non-compound subject) → absent", () => {
    const { work, git } = fixture();
    writeFileSync(join(work, LEARNINGS, "old.md"), "# old learning, edited\n");
    git(["commit", "-q", "-am", "docs: tweak wording"]);
    expectVerdict(work, work, "absent");
  });

  test("row 5 — branch merged a newer main carrying a learning → absent", () => {
    const { work, git } = fixture();
    git(["checkout", "-q", "main"]);
    writeFileSync(join(work, LEARNINGS, "main-side.md"), "# from main\n");
    git(["add", "-A"]);
    git(["commit", "-q", "-m", "learning: main side"]);
    git(["push", "-q", "origin", "main"]);
    git(["checkout", "-q", "feat-x"]);
    git(["merge", "-q", "--no-edit", "main"]);
    expectVerdict(work, work, "absent");
  });

  test("row 6 — no origin remote → absent, no crash", () => {
    const { work, git } = fixture();
    git(["remote", "remove", "origin"]);
    expectVerdict(work, work, "absent");
  });

  test("row 7 — fetch fails and origin/main is stale; branch merged local main's learning → absent", () => {
    const { work, git } = fixture();
    const base = git(["rev-parse", "HEAD~1"]).trim();
    // Rewind the remote-tracking ref to before the branch point, then give local main a learning.
    git(["checkout", "-q", "main"]);
    writeFileSync(join(work, LEARNINGS, "local-main.md"), "# local main\n");
    git(["add", "-A"]);
    git(["commit", "-q", "-m", "docs: local main note"]);
    git(["checkout", "-q", "feat-x"]);
    git(["merge", "-q", "--no-edit", "main"]);
    git(["update-ref", "refs/remotes/origin/main", `${base}~0`]);
    git(["remote", "set-url", "origin", join(work, "..", "does-not-exist.git")]);
    expectVerdict(work, work, "absent");
  });

  test("row 8 — untracked new learning, probe run from a subdirectory → present", () => {
    const { work } = fixture();
    writeFileSync(join(work, LEARNINGS, "new.md"), "# new\n");
    expectVerdict(join(work, "sub"), work, "present");
  });

  test("row 9 — staged (A) new learning → present", () => {
    const { work, git } = fixture();
    writeFileSync(join(work, LEARNINGS, "new.md"), "# new\n");
    git(["add", join(LEARNINGS, "new.md")]);
    expectVerdict(work, work, "present");
  });

  test("row 10 — `learning: update` commit modifying an existing learning → present", () => {
    const { work, git } = fixture();
    writeFileSync(join(work, LEARNINGS, "old.md"), "# old learning, updated\n");
    git(["commit", "-q", "-am", "learning: update old"]);
    expectVerdict(work, work, "present");
  });

  test("row 11 — fetch fails, committed new learning → absent (accepted miss, safe direction)", () => {
    const { work, git } = fixture();
    writeFileSync(join(work, LEARNINGS, "new.md"), "# new\n");
    git(["add", "-A"]);
    git(["commit", "-q", "-m", "docs: add a note"]);
    git(["remote", "set-url", "origin", join(work, "..", "does-not-exist.git")]);
    expectVerdict(work, work, "absent");
  });
});
