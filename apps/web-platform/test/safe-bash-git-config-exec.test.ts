// Falsifier for #9600: which auto-approved git reads EXECUTE a repo-config helper, measured with real git.
//
// Three tests over one ROWS table:
//   A. observed channels (real git, planted config) === the row's `executes`  — pins git's behaviour, so a
//      git upgrade that changes it turns this RED, and a vacuous fixture (config not planted) is detected.
//   B. isBashCommandSafe(cmd) === the row's `approved`                          — the policy under test.
//   C. every approved row that executes under the PLAIN env is in the exact CARRIER_DEPENDENT_APPROVED set,
//      and no approved row carries an exec-requesting flag. Under the PINNED env the bare-repository
//      carriers execute nothing (the env pin is the primary control).
//
// Honest reading (stated in the PR): bare `git diff` / `git status` still execute a config that is
// present. The hole is closed at the CARRIERS (env pin + `.git` file-tool guard), not at the verb.
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { isBashCommandSafe, SAFE_BASH_PATTERNS } from "@/server/safe-bash";
import {
  buildGitConfigExecFixture,
  type Base,
  type Channel,
  type EnvKind,
  type GitConfigExecFixture,
} from "./helpers/git-config-exec-fixture";

interface Row {
  cmd: string;
  base?: Base;
  env?: EnvKind;
  executes: Channel[];
  approved: boolean;
}

const row = (cmd: string, executes: Channel[], approved: boolean, base: Base = "repo", env: EnvKind = "plain"): Row => ({
  cmd,
  base,
  env,
  executes,
  approved,
});

const FM_F: Channel[] = ["filter", "fsmonitor"];
const ALL3: Channel[] = ["ext-diff", "filter", "fsmonitor"];

const ROWS: Row[] = [
  // ---- status / diff: ordinary reads that execute a planted config (approved, carrier-dependent)
  row("git status", FM_F, true),
  row("git diff", ALL3, true),
  row("git diff HEAD~1", ALL3, true),
  row("git diff HEAD~1 --stat", FM_F, true),
  row("git diff --stat", FM_F, true),
  row("git diff --name-only", FM_F, true),
  row("git diff --cached", ["fsmonitor"], true),
  row("git diff --no-ext-diff", ["filter", "fsmonitor", "textconv"], true),
  row("git diff --no-ext-diff --no-textconv", FM_F, true),
  row("git diff HEAD~1 HEAD --stat", [], true),
  // ---- diff: exec-requesting flags (denied; some execute even though the flag only RE-asks for it)
  row("git diff --ext-diff", ALL3, false),
  row("git diff --ext-diff=x", [], false), // git rejects a value on a boolean flag
  row("git diff --textconv", ALL3, false),
  row("git diff -p", ALL3, false),
  row("git diff -U3", ALL3, false),
  row("git diff --word-diff", ALL3, false),
  row("git diff HEAD~1 --textconv --stat", FM_F, false),
  row("git diff --ext HEAD~1", [], false), // unique-prefix abbreviation: rejected by git 2.56, denied regardless
  row("git diff --textc", [], false),
  row("git diff -O/etc/hostname", ALL3, false), // reads an order file only, but never admitted
  row("git diff -Oorder", FM_F, false), // missing order file: git dies before any diff driver runs
  row("git diff --output=out.txt", ALL3, false), // writes a file; already denylisted
  // ---- log
  row("git log", [], true),
  row("git log --oneline -5", [], true),
  row("git log -n 5", [], true),
  row("git log --stat", [], true),
  row("git log --name-only", [], true),
  row("git log --graph --all", [], true),
  row("git log --oneline -5 HEAD~1..HEAD", [], true),
  row("git log -p", ["textconv"], false),
  row("git log --patch", ["textconv"], false),
  row("git log -p --ext-diff", ["ext-diff"], false),
  row("git log -S one", ["textconv"], false),
  row("git log -G one", ["textconv"], false),
  row("git log --textconv", [], false),
  row("git log --show-signature -1 signed", ["gpg"], false),
  row("git log --oneline && git diff --ext-diff", ALL3, false), // one exec segment denies the chain
  row("git log --oneline -5 && git diff --textconv", ALL3, false),
  // ---- show
  row("git show HEAD", ["textconv"], true),
  row("git show", ["textconv"], true),
  row("git show --stat", [], true),
  row("git show --name-only", [], true),
  row("git show -s", [], true),
  row("git show HEAD:f.txt", [], true),
  row("git show --no-ext-diff --no-textconv", [], true),
  row("git show --ext-diff", ["ext-diff"], false),
  row("git show --ext-diff HEAD", ["ext-diff"], false),
  row("git show --show-signature signed", ["gpg"], false),
  // ---- inert neighbours that must stay approved
  row("git rev-parse HEAD", [], true),
  row("git branch", [], true),
  row("git config --get core.fsmonitor", [], true),
  // ---- forms that do not start with `git <verb>` never reach a read pattern (env / global options)
  row("GIT_CONFIG_COUNT=0 git status", FM_F, false),
  row("git -c core.fsmonitor=false status", ["filter"], false), // -c cannot pin filter.*.clean
  row("git --git-dir=evil log", [], false),
  row("git --bare log", [], false),
  // ---- carriers: bare repository discovery (no `.git` path component, no file-tool write needed)
  row("cd evil && git diff HEAD~1 HEAD", ["ext-diff"], true, "repo", "plain"), // text-built bare dir
  row("cd evil && git diff HEAD~1 HEAD", [], true, "repo", "pinned"),
  row("cd evil && git diff HEAD~1 HEAD", ["ext-diff"], true, "clone", "plain"), // COMMITTED, then cloned
  row("cd evil && git diff HEAD~1 HEAD", [], true, "clone", "pinned"), // pin wins over the repo's own safe.bareRepository=all
  row("cd evil && git status", [], true, "clone", "plain"),
  row("cd evil && git log --oneline -5", [], true, "repo", "plain"),
  // ---- a planted REAL repo config is untouched by the env pin (closed by the .git file-tool guard instead)
  row("git status", FM_F, true, "repo", "pinned"),
  row("git diff HEAD~1", ALL3, true, "repo", "pinned"),
  // ---- submodule: its gitdir is written locally under .git/modules, never delivered by clone
  row("git diff HEAD~1 HEAD", [], true, "sub", "plain"),
  row("git status", [], true, "sub", "plain"),
  row("git log -p", [], false, "sub", "plain"),
];

/** Approved AND executing under the plain env: the set the carrier controls exist to protect. Exact, by design. */
const CARRIER_DEPENDENT_APPROVED: ReadonlySet<string> = new Set([
  "repo|git status",
  "repo|git diff",
  "repo|git diff HEAD~1",
  "repo|git diff HEAD~1 --stat",
  "repo|git diff --stat",
  "repo|git diff --name-only",
  "repo|git diff --cached",
  "repo|git diff --no-ext-diff",
  "repo|git diff --no-ext-diff --no-textconv",
  "repo|git show HEAD",
  "repo|git show",
  "repo|cd evil && git diff HEAD~1 HEAD",
  "clone|cd evil && git diff HEAD~1 HEAD",
]);

const EXEC_FLAG = /(?:^|\s)(?:--ext-diff|--textconv|-p|--patch|-S\S*|-G\S*|--show-signature|-O\S*|--output\S*|-U\d*|--word-diff\S*)(?:\s|=|$)/;

let fx: GitConfigExecFixture;
beforeAll(() => {
  fx = buildGitConfigExecFixture();
}, 60_000);
afterAll(() => fx?.cleanup());

describe("safe-bash git config-exec falsifier (#9600)", () => {
  it("floors: the table is not vacuous", () => {
    expect(ROWS.length).toBeGreaterThanOrEqual(60);
    expect(ROWS.filter((r) => r.approved).length).toBeGreaterThanOrEqual(25);
    expect(ROWS.filter((r) => !r.approved).length).toBeGreaterThanOrEqual(20);
    const gitPatterns = SAFE_BASH_PATTERNS.filter((p) => p.source.startsWith("^git"));
    expect(gitPatterns.length).toBeGreaterThanOrEqual(5);
  });

  it("A: observed channels match the table under real git (title carries the git version)", () => {
    const mismatches: string[] = [];
    for (const r of ROWS) {
      const got = fx.run(r.cmd, r.base!, r.env!);
      if (JSON.stringify(got) !== JSON.stringify([...r.executes].sort())) {
        mismatches.push(`${r.base}/${r.env} \`${r.cmd}\`: observed ${JSON.stringify(got)}, table ${JSON.stringify(r.executes)}`);
      }
    }
    expect(mismatches, `git ${fx.gitVersion}`).toEqual([]);
  });

  it("A (vacuity): the fixture really plants every channel", () => {
    const seen = new Set<Channel>();
    for (const r of ROWS) for (const c of fx.run(r.cmd, r.base!, r.env!)) seen.add(c);
    expect([...seen].sort()).toEqual(["ext-diff", "filter", "fsmonitor", "gpg", "textconv"]);
  });

  it("B: isBashCommandSafe matches the table", () => {
    const wrong = ROWS.filter((r) => isBashCommandSafe(r.cmd) !== r.approved).map(
      (r) => `\`${r.cmd}\`: approved=${isBashCommandSafe(r.cmd)}, table ${r.approved}`,
    );
    expect(wrong).toEqual([]);
  });

  it("B: a denied single-segment git row matches NO safe pattern (a second compliant pattern cannot launder it)", () => {
    for (const r of ROWS.filter((x) => !x.approved && !x.cmd.includes("&&") && x.cmd.startsWith("git "))) {
      expect(SAFE_BASH_PATTERNS.some((p) => p.test(r.cmd)), r.cmd).toBe(false);
    }
  });

  it("C: the approved-and-executing set equals CARRIER_DEPENDENT_APPROVED exactly", () => {
    const observed = new Set(
      ROWS.filter((r) => r.env === "plain" && r.approved && fx.run(r.cmd, r.base!, r.env!).length > 0).map(
        (r) => `${r.base}|${r.cmd}`,
      ),
    );
    expect([...observed].sort()).toEqual([...CARRIER_DEPENDENT_APPROVED].sort());
  });

  it("C: no approved row carries an exec-requesting flag", () => {
    for (const r of ROWS.filter((x) => x.approved)) expect(EXEC_FLAG.test(r.cmd), r.cmd).toBe(false);
  });

  it("C: under the pinned env no bare-repository carrier executes (text-built, committed+cloned, repo-local safe.bareRepository=all)", () => {
    for (const base of ["repo", "clone"] as const) {
      expect(fx.run("cd evil && git diff HEAD~1 HEAD", base, "pinned")).toEqual([]);
    }
    // control: the same command under the plain env DOES execute, so the empty result above is the pin, not a broken fixture
    expect(fx.run("cd evil && git diff HEAD~1 HEAD", "clone", "plain")).toEqual(["ext-diff"]);
  });
});
