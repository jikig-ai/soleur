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

// window-assembly: phase2Section — complete against PHASE 2's OWN decision surface, and
// nothing wider. Three assertions carry that claim: the whole-FILE heading count (exactly one
// `## Phase 2: Capture Learnings`, so a second section cannot hold a probe this window never
// sees), the exactly-one-fence rule inside the slice (so the executed block is unambiguous),
// and the prose+indented scan over the slice (so an unfenced or four-space-indented command
// cannot re-enter a repo-wide probe beside the fenced one). The one consumer that lives
// OUTSIDE the slice — the `## Headless Mode Detection` bullet — is pinned separately by a
// whole-file regex in the dispatch test.
// NOT complete against: any other phase. A repo-wide learnings probe added to Phase 1.5, or a
// checklist line elsewhere in ship/SKILL.md, is outside this window by construction and is not
// asserted here.
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

/**
 * Lines that an agent could execute but that the fenced-block extractor never sees: a four-space
 * indented code block, and an inline-code span holding a git command. The `--since` backstop below
 * scans these too, because re-adding one line of prose — the `learnings/**` Glob this PR deleted, or
 * an indented `git log --since=…` — reinstates #8470 with the executed block untouched.
 */
function agentRunnableProseLines(section: string[]): string[] {
  const out: string[] = [];
  let inFence = false;
  for (const l of section) {
    if (FENCE.test(l)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    if (/^ {4,}\S/.test(l)) out.push(l);
    // Only spans that could BE a command: a bare flag or path name (`--since`, `archive/`) carries
    // no verb, and the opening sentence names the retired flag deliberately. A command has a space.
    for (const m of l.matchAll(/`([^`]+)`/g)) if (/\S\s+\S/.test(m[1])) out.push(m[1]);
  }
  return out;
}

/** The body of the section's first fenced block, or "" if there is none. */
function probeBlock(section: string[]): string {
  const f = fenceLines(section);
  if (f.length < 2) return "";
  return section.slice(f[0] + 1, f[1]).join("\n");
}

let skill: string;
let section: string[] | null;
let block: string;
const roots: string[] = [];

beforeAll(() => {
  skill = readFileSync(SHIP_SKILL, "utf8");
  section = phase2Section(skill);
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

  test("the heading occurs exactly once (a second section would be invisible to the extractor)", () => {
    const n = skill.split("\n").filter((l) => l.startsWith(HEADING)).length;
    expect(n).toBe(1);
  });

  test("nothing in the section ranges history by date — fenced, indented or inline (#8470 backstop)", () => {
    const s = section ?? [];
    const DATE_RANGE = /--(since|after|until|before)\b/;
    const bad: string[] = [];
    let inFence = false;
    for (const l of s) {
      if (FENCE.test(l)) {
        inFence = !inFence;
        continue;
      }
      // The one sanctioned mention: the opening sentence NAMES the retired probe to say why it
      // was retired. Anchored on that sentence's own words so it cannot license a command.
      if (!inFence && l.includes("a repo-wide `--since` window is non-empty")) continue;
      if (inFence && DATE_RANGE.test(l)) bad.push(l);
    }
    for (const l of agentRunnableProseLines(s)) if (DATE_RANGE.test(l)) bad.push(l);
    expect(bad).toEqual([]);
  });

  test("no prose line re-introduces a repo-wide learnings glob or log", () => {
    const bad = agentRunnableProseLines(section ?? []).filter((l) =>
      /(knowledge-base\/project\/learnings\/\*|learnings\/\*\*)/.test(l),
    );
    expect(bad).toEqual([]);
  });

  test("the dispatch the verdict feeds is pinned: present → Phase 3, absent → compound", () => {
    const s = (section ?? []).join("\n");
    const present = s.match(/\*\*`BRANCH_LEARNING=present`:\*\*[^\n]*/)?.[0] ?? "";
    const absent = s.match(/\*\*`BRANCH_LEARNING=absent`:\*\*[^\n]*/)?.[0] ?? "";
    expect(present).toContain("Phase 3");
    expect(present).not.toContain("skill: soleur:compound");
    expect(absent).toContain("compound runs");
    expect(absent).not.toContain("Phase 3");
    // Headless mode reads the same token; an unconditional auto-invoke contradicts `present`.
    expect(skill).toMatch(
      /- Phase 2: auto-invoke `skill: soleur:compound --headless`[^\n]*BRANCH_LEARNING=absent/,
    );
  });

  test("the unarchived-artifact check runs on BOTH verdicts, not only on absent", () => {
    const s = (section ?? []).join("\n");
    // The artifact globs must not sit under the `absent` branch alone: a hand-committed learning
    // reads `present`, and shipping then leaves the plan/spec unarchived (compound is the last
    // point at which archival can happen — see this skill's archival note).
    expect(s).toMatch(/Run the artifact check below/);
    expect(s).toMatch(/If no unarchived artifacts exist AND the probe printed `BRANCH_LEARNING=present`/);
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

/**
 * @param shellOpts prologue `set` options. The default is the bare shell the fixtures use; the
 *   `pipefail` row drives the shell an agent may actually be handed. A profile-set `pipefail` is
 *   what turns `producer | grep -q .` into a FAILURE report on a SUCCESSFUL match, so the verdict
 *   must not depend on any pipeline's status (`.claude/hooks/grep-q-pipe-guard.test.sh`).
 */
function runProbe(cwd: string, fixtureDir: string, shellOpts = "") {
  const env = { ...gitFixtureEnv(fixtureDir) };
  // gitFixtureEnv sweeps GIT_* only. BASH_ENV runs a file in every non-interactive bash, and an
  // exported SHELLOPTS=pipefail changes the pipeline's status — neither belongs in a verdict.
  for (const k of ["BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS"]) delete env[k];
  for (const k of Object.keys(env)) if (k.startsWith("BASH_FUNC_")) delete env[k];
  const script = shellOpts ? `set ${shellOpts}\n${block}` : block;
  return spawnSync("bash", ["--noprofile", "--norc", "-c", script], {
    cwd,
    env,
    encoding: "utf8",
    timeout: 60_000,
  });
}

function expectVerdict(
  cwd: string,
  fixtureDir: string,
  want: "present" | "absent",
  shellOpts = "",
) {
  const r = runProbe(cwd, fixtureDir, shellOpts);
  expect(`${r.stdout.trim()}${r.stderr.trim() ? ` | stderr: ${r.stderr.trim()}` : ""}`).toBe(
    `BRANCH_LEARNING=${want}`,
  );
  expect(r.status).toBe(0);
}

/** Advance `main` with a learning AFTER the branch point, and push it. Returns that commit's sha. */
function advanceMain(work: string, git: (a: string[]) => string, name = "main-side.md"): string {
  const head = git(["rev-parse", "HEAD"]).trim();
  git(["checkout", "-q", "main"]);
  writeFileSync(join(work, LEARNINGS, name), "# from main\n");
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "learning: main side"]);
  const sha = git(["rev-parse", "HEAD"]).trim();
  git(["push", "-q", "origin", "main"]);
  git(["checkout", "-q", "feat-x"]);
  expect(git(["rev-parse", "HEAD"]).trim()).toBe(head);
  return sha;
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

  // Rows 12-14 are the axis the first battery never edited: in rows 1-11 `origin/main` IS the
  // branch point, so the range's left edge and the fetch's REFRESH role are unobservable — and
  // `..`→`...`, `origin/main`→`main`, and fetch→reachability-probe all pass without them.
  test("row 12 — main gained a learning after the branch point, branch did not merge it → absent", () => {
    const { work, git } = fixture();
    advanceMain(work, git);
    expectVerdict(work, work, "absent");
  });

  test("row 13 — branch merged that commit while the LOCAL main ref is stale → absent", () => {
    const { work, git } = fixture();
    const base = git(["rev-parse", "HEAD~1"]).trim();
    advanceMain(work, git);
    git(["merge", "-q", "--no-edit", "origin/main"]);
    // Local `main` now points before the learning: a probe reading `main..HEAD` says present.
    git(["branch", "-f", "main", base]);
    expectVerdict(work, work, "absent");
  });

  test("row 14 — tracking ref stale but remote reachable: the probe must FETCH, not just ping → absent", () => {
    const { work, git } = fixture();
    const base = git(["rev-parse", "HEAD~1"]).trim();
    advanceMain(work, git);
    git(["merge", "-q", "--no-edit", "origin/main"]);
    // Rewind only the remote-tracking ref; `origin` still answers. A reachability check leaves it
    // stale and the merged learning falls back inside the range.
    git(["update-ref", "refs/remotes/origin/main", base]);
    expectVerdict(work, work, "absent");
  });

  test("row 15 — uncommitted MODIFICATION of an existing learning → absent", () => {
    const { work } = fixture();
    writeFileSync(join(work, LEARNINGS, "old.md"), "# old learning, edited in the worktree\n");
    expectVerdict(work, work, "absent");
  });

  test("row 16 — a branch commit that merely mentions 'learning' mid-subject → absent", () => {
    const { work, git } = fixture();
    writeFileSync(join(work, "code.txt"), "more\n");
    git(["commit", "-q", "-am", "fix(ship): Phase 2 learning probe is branch-scoped"]);
    expectVerdict(work, work, "absent");
  });

  test("row 17 — untracked NON-learning file under learnings/ (editor swap) → absent", () => {
    const { work } = fixture();
    writeFileSync(join(work, LEARNINGS, ".old.md.swp"), "junk\n");
    writeFileSync(join(work, LEARNINGS, "notes.txt"), "junk\n");
    expectVerdict(work, work, "absent");
  });

  test("row 18 — untracked learning in a NEW category subdirectory → present", () => {
    const { work } = fixture();
    mkdirSync(join(work, LEARNINGS, "workflow-issues"), { recursive: true });
    writeFileSync(join(work, LEARNINGS, "workflow-issues/new.md"), "# new\n");
    expectVerdict(work, work, "present");
  });

  test("row 19 — a present verdict survives `set -euo pipefail` in the agent's shell", () => {
    const { work } = fixture();
    writeFileSync(join(work, LEARNINGS, "new.md"), "# new\n");
    expectVerdict(work, work, "present", "-euo pipefail");
  });

  test("row 20 — an absent verdict survives `set -euo pipefail` too", () => {
    const { work } = fixture();
    expectVerdict(work, work, "absent", "-euo pipefail");
  });

  test("row 21 — a TAG named origin/main does not outrank the remote-tracking ref → absent", () => {
    const { work, git } = fixture();
    const base = git(["rev-parse", "HEAD~1"]).trim();
    advanceMain(work, git);
    git(["merge", "-q", "--no-edit", "origin/main"]);
    // `origin/main` as a REV resolves refs/tags/ before refs/remotes/, so a pushed tag of that name
    // would otherwise rewind the range and re-admit main's learning. The block names
    // refs/remotes/origin/main outright, so the tag is inert.
    git(["tag", "origin/main", base]);
    expectVerdict(work, work, "absent");
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
