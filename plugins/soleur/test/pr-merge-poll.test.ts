import { describe, test, expect } from "bun:test";
import { execFileSync } from "child_process";
import { readFileSync, readdirSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { dirname, join, resolve } from "path";
import {
  isBehindPollState,
  isTerminalPollState,
  shouldResyncBeforePoll,
  behindSyncInstructions,
  parsePrPollRead,
  GH_ERR_LINE_MAX,
  PR_BEHIND_SYNC_SENTINEL,
  MERGE_STATE_BEHIND,
  MERGE_STATE_DIRTY,
  formatPrPollState,
} from "../lib/pr-merge-poll";
import { pollInstructions, type Harness } from "../lib/harness";
import { gitCleanEnv } from "./lib/git-clean-env";
import { gitFixture } from "./lib/git-fixture-env";

const PLUGIN_ROOT = resolve(import.meta.dir, "..");

describe("pr-merge-poll BEHIND contract", () => {
  test("formatPrPollState matches ship Phase 7 jq output", () => {
    expect(formatPrPollState("OPEN", "BEHIND")).toBe("OPEN BEHIND");
    expect(isBehindPollState("OPEN BEHIND")).toBe(true);
    expect(isBehindPollState("OPEN CLEAN")).toBe(false);
  });

  test("shouldResyncBeforePoll fires on BEHIND or DIRTY", () => {
    expect(shouldResyncBeforePoll(MERGE_STATE_BEHIND)).toBe(true);
    expect(shouldResyncBeforePoll(MERGE_STATE_DIRTY)).toBe(true);
    expect(shouldResyncBeforePoll("CLEAN")).toBe(false);
    expect(shouldResyncBeforePoll("BLOCKED")).toBe(false);
  });

  test("terminal states stop poll loop", () => {
    expect(isTerminalPollState("MERGED CLEAN")).toBe(true);
    expect(isTerminalPollState("CLOSED DIRTY")).toBe(true);
    expect(isTerminalPollState("OPEN BEHIND")).toBe(false);
  });

  test("grok pollInstructions mention BEHIND and sync script", () => {
    const md = pollInstructions("grok");
    expect(md).toContain("mergeStateStatus");
    expect(md).toContain("BEHIND");
    expect(md).toContain("sync-pr-behind.sh");
    expect(md).toContain("AwaitShell");
  });

  test("behindSyncInstructions (claude) names the --step call the Monitor loop makes", () => {
    expect(behindSyncInstructions("claude")).toContain("sync-pr-behind.sh <PR-number> --step");
  });

  test("standalone invocations use the installed plugin root, never a repo-relative path (ADR-179)", () => {
    for (const h of ["grok", "claude", "devin"] as const) {
      const md = behindSyncInstructions(h);
      expect(md).toContain('bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh"');
      expect(md).not.toContain("bash plugins/soleur/scripts/sync-pr-behind.sh");
    }
    const ship = readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8");
    expect(ship).not.toContain("bash plugins/soleur/scripts/sync-pr-behind.sh");
  });

  test("Grok AwaitShell patterns wake on every tagged Phase 7 / sync line", () => {
    const sync = behindSyncInstructions("grok");
    const poll = pollInstructions("grok");
    for (const md of [sync, poll]) {
      expect(md).toContain("\\[pr-behind-sync\\] kind=");
      expect(md).toContain("\\[ship\\.phase7\\.");
    }
    expect(poll).toContain("Merge poll timed out");
    const ship = readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8");
    // The Phase 7 Grok line must name the fence's actual timeout text.
    expect(ship).toMatch(/AwaitShell\*\* with a `pattern` matching poll output \([^\n]*`Merge poll timed out`[^\n]*`\\\[ship\\\.phase7\\\.`/);
  });

  test("behindSyncInstructions agrees with the queued skip: queued is a no-op to keep polling, dequeued stops (#9454)", () => {
    for (const h of ["grok", "claude"] as const) {
      const md = behindSyncInstructions(h);
      expect(md).toContain("kind=queued");
      expect(md).toContain("kind=dequeued");
    }
    // The old unconditional ban would tell an agent to stop heartbeating on a queued PR.
    expect(behindSyncInstructions("claude")).toMatch(/unless the script reported `kind=queued`/);
    expect(behindSyncInstructions("grok")).toMatch(/never push, update-branch or --admin/);
    // Exit 11 for a queued PR is the --step arm only; the standalone script the Grok text runs exits 0 (kind=queued rc=0).
    expect(behindSyncInstructions("grok")).toMatch(/exits 0 here and 11 only with `--step`/);
    expect(behindSyncInstructions("claude")).toMatch(/exit 11 with `--step`/);
  });

  test("exit 14 is named where exit codes are listed: kind=queue_wait is exit 0 standalone and 14 under a flagless --step (#9869)", () => {
    // Exit 11 stays the fences' uncounted no-op arm; the refusal has its own code so an OLD pasted fence stops loudly instead of looping.
    expect(behindSyncInstructions("grok")).toMatch(/exit 14/i);
    expect(behindSyncInstructions("grok")).toMatch(/exits 0 here and 11 only with `--step`/);
    expect(behindSyncInstructions("claude")).toMatch(/exit 11 with `--step`/);
    expect(behindSyncInstructions("claude")).toMatch(/exit 14/);
    for (const h of ["grok", "claude"] as const) expect(behindSyncInstructions(h)).not.toContain("--fence");
  });

  test("the fences' only opt-in flag is taught nowhere an agent could copy it from (#9869)", () => {
    // `--fence` is accident prevention, not authentication: the two Phase 7 fences pass it, the script's own --help defines it, and
    // NOTHING else names it. A third surface that did would teach every hand-rolled loop to bypass the queue-armed refusal.
    const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");
    const ALLOWED_FENCE = new Set(["skills/ship/SKILL.md", "skills/merge-pr/SKILL.md", "scripts/sync-pr-behind.sh"]);
    const SKIP = new Set(["node_modules", "test", ".git"]);
    const walk = (dir: string, out: string[] = []): string[] => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        const full = resolve(dir, e.name);
        if (e.isDirectory()) {
          if (!SKIP.has(e.name)) walk(full, out);
        } else if (/\.(md|ts|js|mjs|sh|yml|yaml|json|njk)$/.test(e.name)) out.push(full);
      }
      return out;
    };
    const files = [...walk(PLUGIN_ROOT), ...walk(resolve(REPO_ROOT, ".github"))];
    expect(files.length).toBeGreaterThan(300); // non-vacuity: the walk found skills, scripts, lib, hooks and workflows
    const rel = (f: string) => (f.startsWith(PLUGIN_ROOT + "/") ? f.slice(PLUGIN_ROOT.length + 1) : f);
    const withFence = files.filter((f) => readFileSync(f, "utf-8").includes("--fence")).map(rel).sort();
    // the allow-list is exact: the script and both fences carry it (a fence that lost it would run the flagless call)
    expect(withFence).toEqual([...ALLOWED_FENCE].sort());
    // generated instruction text, for every harness: never names it either
    for (const h of ["grok", "claude", "codex", "devin", "opencode", "cursor", "unknown"] as const) {
      expect(behindSyncInstructions(h)).not.toContain("--fence");
      expect(pollInstructions(h)).not.toContain("--fence");
    }
    for (const f of ["skills/drain-prs/SKILL.md", "lib/harness.ts", "codex/INSTRUCTIONS.md", "devin/INSTRUCTIONS.md"]) {
      expect(readFileSync(resolve(PLUGIN_ROOT, f), "utf-8")).not.toContain("--fence");
    }
  });

  test("nothing but the two Phase 7 fences calls sync-pr-behind.sh with --step (#9869)", () => {
    // A hand-rolled `--step` loop is the second writer this change closes. The call shapes: the fence's `"$SYNC_SNAP" "$PR" --step`,
    // and any `sync-pr-behind.sh <pr> --step` an instruction or workflow would hand to an agent to run.
    const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");
    const CALL = /(\$SYNC_SNAP"?\s+"?\$PR"?\s+--step|sync-pr-behind\.sh"?\s+("?\$?[\w{}<>-]+"?)\s+--step)\b/;
    const SKIP = new Set(["node_modules", "test", ".git"]);
    const walk = (dir: string, out: string[] = []): string[] => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        const full = resolve(dir, e.name);
        if (e.isDirectory()) {
          if (!SKIP.has(e.name)) walk(full, out);
        } else if (/\.(md|ts|js|mjs|sh|yml|yaml)$/.test(e.name)) out.push(full);
      }
      return out;
    };
    // positive controls: the pattern must fire on the real spellings, or the empty result pins nothing
    expect('bash "$SYNC_SNAP" "$PR" --step --fence || sync_rc=$?').toMatch(CALL);
    expect('bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh" 4242 --step').toMatch(CALL);
    expect("`sync-pr-behind.sh <PR-number> --step`").toMatch(CALL);
    const files = [...walk(PLUGIN_ROOT), ...walk(resolve(REPO_ROOT, ".github"))];
    expect(files.length).toBeGreaterThan(300);
    const FENCES = new Set([resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), resolve(PLUGIN_ROOT, "skills/merge-pr/SKILL.md")]);
    // pr-merge-poll.ts names the call once, to say it is never the agent's ("never yours"); the script's header comments list its callers.
    const DOC = new Set([resolve(PLUGIN_ROOT, "lib/pr-merge-poll.ts"), resolve(PLUGIN_ROOT, "scripts/sync-pr-behind.sh")]);
    const hits = files.filter((f) => !FENCES.has(f) && !DOC.has(f) && CALL.test(readFileSync(f, "utf-8")));
    expect(hits).toEqual([]);
    // each fence has exactly one call, and it is the fenced one
    for (const f of FENCES) {
      const text = readFileSync(f, "utf-8");
      expect(text.match(/bash "\$SYNC_SNAP" "\$PR" --step/g)?.length).toBe(1);
      expect(text).toContain('bash "$SYNC_SNAP" "$PR" --step --fence || sync_rc=$?');
      // `[|]`, not a bare pipe: the probe is quoted text here, not a pipeline (scripts/lint-grep-q-pipe-guard scans for the shape)
      expect(text).toMatch(/--help 2>\/dev\/null [|] grep -q -- '--fence'/);
      expect(text).not.toMatch(/--help 2>\/dev\/null [|] grep -q -- '--step'/);
    }
  });

  test("behindSyncInstructions agrees with queue mode: a queue_wait heartbeat on BEHIND is not a reason to sync (#9710)", () => {
    // Every harness gets the exception: the default case is appended for codex, devin and unknown, and without it the
    // amended FORBIDDEN/resolve lines sit above an unconditional "BEHIND -> merge origin/main and push".
    for (const h of ["grok", "claude", "codex", "devin", "opencode", "cursor", "unknown"] as const) {
      const md = behindSyncInstructions(h);
      if (h === "cursor") continue; // cursor prescribes no wait primitive and no sync at all
      expect(md).toContain("[ship.phase7.queue_wait]");
      expect(md).toContain("[ship.phase7.queue_wait_expired]");
    }
    expect(behindSyncInstructions("grok")).toMatch(/Exception \(first\): when `main` has a merge queue and the PR is armed \(the Phase 7 poll prints `\[ship\.phase7\.queue_wait\]`\)[^\n]*never run the sync script/);
    expect(behindSyncInstructions("claude")).toMatch(/likewise when `main` has a merge queue and the PR is armed \(the Phase 7 poll prints `\[ship\.phase7\.queue_wait\]`\)/);
    expect(behindSyncInstructions("codex")).toMatch(/Exception \(first\): when `main` has a merge queue and the PR is armed \(the Phase 7 poll prints `\[ship\.phase7\.queue_wait\]`\)[^\n]*never merge origin\/main into it/);
  });

  // 2026-10-09 (PR 9839): an agent hand-wrote a poll loop and ran sync-pr-behind.sh on an armed PR in a merge-queue repo.
  // The exception was conditioned on a marker only the Phase 7 fence prints, and the text invited the ad-hoc call. The
  // script now refuses (kind=queue_wait); these assertions pin the TEXT so it does not drift back.
  test("no text invites a hand-rolled loop or an ad hoc sync, and the exception is stated on facts", () => {
    const claude = behindSyncInstructions("claude");
    const grok = behindSyncInstructions("grok");
    expect(claude).not.toContain("outside that loop");
    for (const md of [claude, grok]) {
      expect(md).toMatch(/never write your own/i);
      expect(md).toContain("kind=queue_wait");
    }
    // the --step mention carries its own warning, in the same sentence, so the pinned substring is not a teaching. The script now
    // REFUSES a flagless --step on an armed BEHIND PR of a merge-queue repo (kind=queue_wait, exit 14): the text says so, and the
    // old "unguarded by design" wording (false since #9869) is gone. The flag the fences pass is deliberately not named here.
    expect(claude).toMatch(/sync-pr-behind\.sh <PR-number> --step`[^.]*never yours; the script refuses a flagless `--step`[^.]*`kind=queue_wait`, exit 14/);
    expect(claude).not.toContain("unguarded by design");
    // grok: the queue exception comes BEFORE the sync bullet
    expect(grok.indexOf("Exception (first)")).toBeGreaterThan(-1);
    expect(grok.indexOf("Exception (first)")).toBeLessThan(grok.indexOf("Otherwise, from the PR worktree"));
  });

  test("the queue-armed exception is one state-based phrase on every text surface, never marker-conditioned alone", () => {
    const CANON = /when `main` has a merge queue and the PR is armed \(the Phase 7 (poll|loop) prints `\[ship\.phase7\.queue_wait\]`/;
    const surfaces: Record<string, string> = {
      "ship/SKILL.md": readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8"),
      "codex/INSTRUCTIONS.md": readFileSync(resolve(PLUGIN_ROOT, "codex/INSTRUCTIONS.md"), "utf-8"),
      "devin/INSTRUCTIONS.md": readFileSync(resolve(PLUGIN_ROOT, "devin/INSTRUCTIONS.md"), "utf-8"),
      "drain-prs/SKILL.md": readFileSync(resolve(PLUGIN_ROOT, "skills/drain-prs/SKILL.md"), "utf-8"),
    };
    for (const h of ["grok", "claude", "codex", "devin", "opencode", "unknown"] as const) {
      surfaces[`behindSyncInstructions(${h})`] = behindSyncInstructions(h);
      surfaces[`pollInstructions(${h})`] = pollInstructions(h);
    }
    for (const [name, text] of Object.entries(surfaces)) {
      // drain-prs states it in its own words (leave-it-alone first) but must still name the marker and the script refusal
      if (name === "drain-prs/SKILL.md") {
        expect(text).toMatch(/Armed on a merge-queue repo, not yet enqueued: leave it alone[^\n]*kind=queue_wait/);
        continue;
      }
      expect(text).toMatch(CANON);
      expect(text).not.toMatch(/once the poll has printed/);
    }
  });

  test("no instruction surface conditions the queue exception on a marker only the Phase 7 fence prints (class ban, whole plugin)", () => {
    // The incident: "once the poll has printed `[ship.phase7.queue_wait]`" is never satisfied by a hand-written loop, so the
    // exception was vacuous for exactly the reader who needed it. Ban the CLASS (once/after/until the poll|loop|fence
    // [has] <up to three words> printed|prints|emitted|logged), whitespace-normalised, over every markdown, TS, JS and
    // shell source in the plugin that an agent can read, plus the root AGENTS files.
    const BAN = /(once|after|only after|until) the (ship |Phase 7 )?(poll|loop|fence)( has| had)?(\s+\S+){0,3}?\s+(printed|prints|emitted|emits|logged)/i;
    // positive controls: the ban must fire on the incident sentence and its near spellings, or it pins nothing
    for (const bad of [
      "once the poll has printed `[ship.phase7.queue_wait]`",
      "Once the ship poll has printed the marker",
      "only after the loop prints it",
      "once the   poll\n has emitted x",
    ]) expect(bad.replace(/\s+/g, " ")).toMatch(BAN);
    expect("when `main` has a merge queue and the PR is armed (the Phase 7 poll prints `[ship.phase7.queue_wait]`)").not.toMatch(BAN);
    const SKIP = new Set(["node_modules", "test", ".git"]);
    const walk = (dir: string, out: string[] = []): string[] => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        const full = resolve(dir, e.name);
        if (e.isDirectory()) {
          if (!SKIP.has(e.name)) walk(full, out);
        } else if (/\.(md|ts|js|mjs|sh)$/.test(e.name)) out.push(full);
      }
      return out;
    };
    const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");
    const files = [...walk(PLUGIN_ROOT), resolve(REPO_ROOT, "AGENTS.md"), resolve(REPO_ROOT, "AGENTS.rules.md")];
    expect(files.length).toBeGreaterThan(300); // non-vacuity: the walk found agents, commands, skills, scripts and hooks
    for (const dir of ["agents", "commands", "skills", "scripts", "hooks", "lib"]) {
      expect(files.some((f) => f.includes(`/plugins/soleur/${dir}/`))).toBe(true);
    }
    const hits = files.filter((f) => BAN.test(readFileSync(f, "utf-8").replace(/\s+/g, " ")));
    expect(hits).toEqual([]);
  });

  test("ship item 6 puts the queue exception BEFORE the stop-and-sync rule and no longer invites an ad hoc poll", () => {
    const ship = readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8");
    const item = ship.split("\n").find((l) => l.startsWith("6. **BEHIND stop-and-sync:**")) ?? "";
    expect(item).not.toBe("");
    expect(item.indexOf("**Queue mode first:**")).toBeGreaterThan(-1);
    expect(item.indexOf("**Queue mode first:**")).toBeLessThan(item.indexOf("**Otherwise**"));
    expect(item).toContain("merge queue");
    expect(item).toContain("armed");
    expect(item).toContain("[ship.phase7.queue_wait_expired]");
    expect(item).toContain("`kind=queue_wait`");
    expect(item).toContain("use the Phase 7 loop, never write your own");
    expect(item).not.toContain("Grok/ad-hoc polls");
    expect(item).not.toContain("--step"); // item 6 no longer teaches the fence's call
  });

  test("the merge_queue rule selector is the same literal in the script and both fences (it is the predicate, in three places)", () => {
    const SEL = 'select(.type == "merge_queue")';
    for (const f of ["scripts/sync-pr-behind.sh", "skills/ship/SKILL.md", "skills/merge-pr/SKILL.md"]) {
      expect(readFileSync(resolve(PLUGIN_ROOT, f), "utf-8")).toContain(SEL);
    }
  });

  test("behindSyncInstructions forbids operator handoff on Grok", () => {
    const md = behindSyncInstructions("grok");
    expect(md).toContain("STOP");
    expect(md).toContain("sync-pr-behind.sh");
    expect(md).toContain("do NOT ask");
  });

  test("cursor behind-sync is one stop with no plugin root and no wait tool", () => {
    const stop = behindSyncInstructions("cursor");
    expect(pollInstructions("cursor")).toBe(stop);
    expect(stop).not.toContain("CLAUDE_PLUGIN_ROOT");
    expect(stop).not.toContain("AwaitShell");
    expect(stop).not.toContain("Monitor");
    expect(stop).not.toContain("run_subagent");
    expect(stop).toContain("or stop");
    expect(stop).toContain("harness that already has a wait");
    expect(stop).toContain("does not make the plugin supported");
  });
});

describe("pr-merge-poll sentinel markers", () => {
  test("sync-pr-behind.sh exists and is executable", () => {
    const script = resolve(PLUGIN_ROOT, "scripts/sync-pr-behind.sh");
    const stat = readFileSync(script, "utf-8");
    expect(stat).toContain("BEHIND detected");
    expect(stat).toContain("auto-sync");
    expect(stat).toContain("[pr-behind-sync]");
    // The Phase 7 fences run `--step --fence` and refuse a copy whose --help lacks --fence (#8383, #9869): the flag is how a fence
    // proves it is paired with a script that knows about the queue-armed refusal. --queue-wait is the hook's read-only verdict.
    expect(stat).toContain("--step");
    expect(stat).toContain("--fence");
    expect(stat).toContain("--queue-wait");
    expect(stat).toMatch(/^  14 +.*kind=queue_wait/m);
    expect(PR_BEHIND_SYNC_SENTINEL).toBe("pr-behind-sync-protocol");
  });

  test("ship SKILL.md documents BEHIND stop-and-sync for Grok", () => {
    const ship = readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8");
    expect(ship).toContain("sync-pr-behind.sh");
    expect(ship).toContain("pr-merge-poll.ts");
  });
});
// ── Defect 1 (#12697): stdout is the answer, stderr is the diagnostic ─────────────────────────────────
// gh 2.106.0 prints an 8-line `hint: … gh event listen …` block on STDERR for `gh pr view` of an open PR (also an in-progress PR
// run's `gh run view` and `gh api …/pulls/<N>`), rc 0, BEFORE stdout. Under
// `2>&1` the capture's first line is that hint, so every OPEN branch of the Phase 7 poll misread the state. The fixture is the
// real block with a synthesized PR number, shared with the fence, sync and operator-gate suites.
const HINT = readFileSync(resolve(PLUGIN_ROOT, "test/fixtures/gh-pr-view-hint.txt"), "utf-8").replace(/\n$/, "");

describe("parsePrPollRead: stdout is the answer, stderr only names a failure", () => {
  test("the shared hint fixture has the measured shape (one `hint:` line, then indented lines), so these rows are not vacuous", () => {
    const lines = HINT.split("\n");
    expect(lines.length).toBe(8);
    expect(lines[0].startsWith("hint:")).toBe(true);
    for (const l of lines.slice(1)) expect(l).toMatch(/^\s+\S/);
    expect(HINT).toContain("gh event listen");
  });

  test("rc 0: a hint and a warning on stderr leave the state unchanged (the falsifiable case: a merged-stream reader fails it)", () => {
    expect(parsePrPollRead({ rc: 0, stdout: "OPEN BEHIND\n", stderr: HINT + "\nwarning\n" })).toBe("OPEN BEHIND");
    expect(parsePrPollRead({ rc: 0, stdout: "MERGED CLEAN", stderr: HINT })).toBe("MERGED CLEAN");
    expect(parsePrPollRead({ rc: 0, stdout: "  CLOSED DIRTY  \n", stderr: "" })).toBe("CLOSED DIRTY");
  });

  test("rc 0: empty or malformed stdout is refused (null), never guessed", () => {
    expect(parsePrPollRead({ rc: 0, stdout: "", stderr: "" })).toBeNull();
    expect(parsePrPollRead({ rc: 0, stdout: "\n", stderr: HINT })).toBeNull();
    // a merged stream (what `2>&1` produces) is refused instead of misread
    expect(parsePrPollRead({ rc: 0, stdout: HINT + "\nOPEN BEHIND", stderr: "" })).toBeNull();
    expect(parsePrPollRead({ rc: 0, stdout: "OPEN BEHIND\nOPEN CLEAN", stderr: "" })).toBeNull();
    expect(parsePrPollRead({ rc: 0, stdout: "OPEN behind", stderr: "" })).toBeNull();
    expect(parsePrPollRead({ rc: 0, stdout: "DRAFT BEHIND", stderr: "" })).toBeNull();
    expect(parsePrPollRead({ rc: 0, stdout: "OPEN", stderr: "" })).toBeNull();
  });

  test("rc != 0: the first non-hint, non-indented stderr line is the error", () => {
    expect(parsePrPollRead({ rc: 1, stdout: "", stderr: HINT + "\ngh: HTTP 502" })).toBe("fetch-error: gh: HTTP 502");
    expect(parsePrPollRead({ rc: 1, stdout: "", stderr: "\n\n" + HINT + "\n\ngh: HTTP 502\nsecond line\n" })).toBe("fetch-error: gh: HTTP 502");
  });

  test("rc != 0 with only hint text (or nothing) on stderr names the rc", () => {
    expect(parsePrPollRead({ rc: 1, stdout: "", stderr: HINT })).toBe("fetch-error: rc=1");
    expect(parsePrPollRead({ rc: 4, stdout: "", stderr: "" })).toBe("fetch-error: rc=4");
    expect(parsePrPollRead({ rc: 1, stdout: "", stderr: "   indented only\n\t tabbed\n" })).toBe("fetch-error: rc=1");
  });

  test("rc != 0 is always a fetch-error, even when stdout looks like a valid state", () => {
    expect(parsePrPollRead({ rc: 1, stdout: "OPEN BEHIND\n", stderr: "gh: HTTP 502" })).toBe("fetch-error: gh: HTTP 502");
    expect(parsePrPollRead({ rc: 1, stdout: "MERGED CLEAN\n", stderr: HINT })).toBe("fetch-error: rc=1");
  });

  test("the error line drops non-printables and is cut to GH_ERR_LINE_MAX (the fence's `${e:0:200}`)", () => {
    expect(GH_ERR_LINE_MAX).toBe(200);
    expect(parsePrPollRead({ rc: 1, stdout: "", stderr: "gh: \x1b[31mboom\x07\r\n" })).toBe("fetch-error: gh: [31mboom");
    const long = parsePrPollRead({ rc: 1, stdout: "", stderr: "E".repeat(GH_ERR_LINE_MAX + 50) });
    expect(long).toBe("fetch-error: " + "E".repeat(GH_ERR_LINE_MAX));
    // a line that is non-printable only is not an error line
    expect(parsePrPollRead({ rc: 1, stdout: "", stderr: "\x1b\x07\nreal: error" })).toBe("fetch-error: real: error");
  });
});

// ── parsePrPollRead vs the fence's own `gh_err_line`: one table, two implementations ──────────────────────────────────────────
// The docstring claims the fence runs the SAME rule. This runs the `gh_err_line` line extracted verbatim from ship/SKILL.md and
// from the merge-pr mirror in bash, over a file holding each row's stderr, and asserts the two outputs are equal.
const PARITY_ROWS: [number, string][] = [
  [1, HINT + "\ngh: HTTP 502"],
  [1, "\n\n" + HINT + "\n\ngh: HTTP 502\nsecond line\n"],
  [1, HINT],
  [4, ""],
  [4, HINT + "\n"],
  [1, "   indented only\n\t tabbed\n"],
  [1, "gh: \x1b[31mboom\x07\r\n"],
  [1, "\x1b\x07\nreal: error"],
  [1, "\x1bhint: masked by an escape\nreal"],
  [1, "\tfoo\nbar"],
  [2, "\x00\x01\n\x7f\nx"],
  [1, "a\rb\vc\fd"],
  [1, "héllo wörld \u{1F600}!"],
  [1, "E".repeat(GH_ERR_LINE_MAX + 50)],
  [1, "E".repeat(GH_ERR_LINE_MAX - 1) + "éFG"],
  [1, "é".repeat(5) + "\n" + "x".repeat(10)],
  [1, "no trailing newline"],
  [1, "a\tb"],
];

function fenceGhErrLine(skillRel: string): string {
  const src = readFileSync(resolve(PLUGIN_ROOT, skillRel), "utf-8");
  const lines = src.split("\n").filter((l) => l.startsWith("gh_err_line() {"));
  if (lines.length !== 1) throw new Error(`${skillRel}: want exactly one \`gh_err_line() {\` line, got ${lines.length}`);
  return lines[0];
}

describe("parsePrPollRead and the fence's gh_err_line agree on every row", () => {
  for (const skillRel of ["skills/ship/SKILL.md", "skills/merge-pr/SKILL.md"]) {
    test(`${skillRel}: the extracted gh_err_line, run in bash, equals parsePrPollRead's error arm`, () => {
      const fn = fenceGhErrLine(skillRel);
      const dir = mkdtempSync(join(tmpdir(), "gh-err-line-"));
      try {
        const got: string[] = [];
        const want: string[] = [];
        PARITY_ROWS.forEach(([rc, stderr], n) => {
          const f = join(dir, `row${n}`);
          writeFileSync(f, stderr);
          const out = execFileSync("bash", ["-c", `${fn}\nGH_ERR="$1"; gh_err_line "$2"`, "bash", f, String(rc)], {
            encoding: "utf8",
            env: { PATH: process.env.PATH ?? "/usr/bin:/bin", LANG: "C.UTF-8", LC_ALL: "C.UTF-8" },
          }).replace(/\n$/, "");
          got.push(`${n}: fetch-error: ${out}`);
          want.push(`${n}: ${parsePrPollRead({ rc, stdout: "", stderr })}`);
        });
        expect(got).toEqual(want);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });
  }

  test("the table is not vacuous: it holds a control-character row, a cut row and an rc row", () => {
    expect(PARITY_ROWS.length).toBeGreaterThanOrEqual(18);
    const outs = PARITY_ROWS.map(([rc, stderr]) => parsePrPollRead({ rc, stdout: "", stderr }));
    expect(outs).toContain("fetch-error: gh: [31mboom");
    expect(outs).toContain("fetch-error: rc=4");
    expect(outs).toContain("fetch-error: real");
    expect(outs).toContain("fetch-error: " + "E".repeat(GH_ERR_LINE_MAX));
  });
});

// The stdout-only rule, as instruction text. Pinned as a literal here (not imported) so a mutant that empties the shared constant
// cannot pass a `toContain("")`.
const STDOUT_ONLY = /Read `gh` stdout only; send stderr to a file, never `2>&1`/;

/** Every value of the `Harness` union, read from its declaration so a newly added harness cannot skip these rows. */
function harnessUnion(): Harness[] {
  const src = readFileSync(resolve(PLUGIN_ROOT, "lib/harness.ts"), "utf-8");
  const decl = src.match(/^export type Harness\s*=([^;]+);/m);
  if (!decl) throw new Error("lib/harness.ts: `export type Harness = …;` not found — the union census has nothing to iterate");
  return [...decl[1].matchAll(/"([a-z]+)"/g)].map((m) => m[1] as Harness);
}

describe("the stdout-only read rule is stated on every instruction surface", () => {
  test("the union census reads the real declaration (non-vacuity)", () => {
    const hs = harnessUnion();
    expect(hs.length).toBeGreaterThanOrEqual(8);
    for (const h of ["claude", "grok", "cursor", "unknown"]) expect(hs).toContain(h as Harness);
  });

  test("behindSyncInstructions(h) carries the sentence for every harness", () => {
    for (const h of harnessUnion()) expect({ h, md: behindSyncInstructions(h) }).toEqual({ h, md: expect.stringMatching(STDOUT_ONLY) });
  });

  test("pollInstructions(h) carries its OWN sentence, outside the embedded behind-sync text (cursor returns the stop unchanged)", () => {
    for (const h of harnessUnion()) {
      const poll = pollInstructions(h);
      const behind = behindSyncInstructions(h);
      if (h === "cursor") {
        expect(poll).toBe(behind);
        continue;
      }
      expect(poll).toContain(behind); // the removal below must actually remove something
      const own = poll.replace(behind, "");
      expect({ h, own }).toEqual({ h, own: expect.stringMatching(STDOUT_ONLY) });
    }
  });
});

// ── Guard 2: no `gh` capture merges stderr into the value it returns ─────────────────────────────────
// Property: no tracked non-test file under plugins/ or .claude/hooks/ captures a `gh` command (or a `*_gh` wrapper) in a command
// substitution (or an assignment's backtick capture) with a top-level stderr merge (MERGE_AT: `2>&1`, `2>& 1`, `|&`, `&>`,
// `2>/dev/stdout`) before the substitution's MATCHING `)`, except the sites on EXCLUSIONS below. Nothing outside those two
// directories (scripts/, .github/, apps/) is scanned.
// Planted violations are built by concatenation so this file never carries the shape it bans (it is a *.test.ts and is not scanned).
const MERGE = "2>" + "&1";
const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");
const GUARD2_PATHSPECS = ["plugins", ".claude/hooks"];
const GUARD2_EXT = /\.(sh|bash|md|ts|js|mjs|cjs)$/;

/** Backslash-newline continuations are removed, as the shell does, so a two-line `gh … \` / `--jq … 2>&1)` read is one line. */
function joinContinuations(text: string): string {
  return text.replace(/\\\r?\n/g, "");
}

/**
 * Index just past the `)` that closes the substitution whose body starts at `start`, or -1. Tracks single quotes, double quotes
 * (with nested `$(` inside them) and bare parens, because every real site's jq template carries `)` inside quotes
 * (`'"\(.state) \(.mergeStateStatus)"'`). An unclosed top-level capture ends at its logical line.
 */
function matchingParen(s: string, start: number): number {
  const stack: ("sub" | "dq")[] = ["sub"];
  let i = start;
  while (i < s.length) {
    const c = s[i];
    if (stack[stack.length - 1] === "dq") {
      if (c === "\\") i += 2;
      else if (c === '"') { stack.pop(); i++; }
      else if (c === "$" && s[i + 1] === "(") { stack.push("sub"); i += 2; }
      else i++;
      continue;
    }
    if (c === "\\") { i += 2; continue; }
    if (c === "'") { const j = s.indexOf("'", i + 1); if (j < 0) return -1; i = j + 1; continue; }
    if (c === '"') { stack.push("dq"); i++; continue; }
    if (c === "(") { stack.push("sub"); i++; continue; }
    if (c === ")") { stack.pop(); i++; if (stack.length === 0) return i; continue; }
    if (c === "\n" && stack.length === 1) return -1;
    i++;
  }
  return -1;
}

/**
 * Every spelling that sends gh's stderr into the captured value: `2>&1` and its spaced / other-fd forms (`[0-9]*>&\s*1`),
 * `|&` (stderr piped with stdout), `&>` / `&>>` (both streams to one target), and `2>/dev/stdout` (or `/dev/fd/1`).
 * Built from pieces so this file never carries a bare banned shape on one line.
 */
const MERGE_AT = new RegExp(
  "^(?:[0-9]*>&\\s*1(?![0-9])" + "|\\|&" + "|&>" + "|2>>?\\s*/dev/(?:stdout|fd/1)(?![A-Za-z0-9_/])" + ")",
);

/** True when `body` holds a stderr merge outside quotes and outside any nested group (a nested `$(x 2>&1)` is not gh's stderr). */
function topLevelMerge(body: string): boolean {
  let depth = 0;
  let dq = false;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (dq) { if (c === "\\") i++; else if (c === '"') dq = false; continue; }
    if (c === "\\") { i++; continue; }
    if (c === "'") { const j = body.indexOf("'", i + 1); i = j < 0 ? body.length : j; continue; }
    if (c === '"') dq = true;
    else if (c === "(") depth++;
    else if (c === ")") depth--;
    else if (depth === 0 && MERGE_AT.test(body.slice(i, i + 24))) return true;
  }
  return false;
}

// Words that may stand before the command word: whitespace, `VAR=x` assignments, a quoted or braced expansion used as a wrapper
// (`"${to[@]}"`), `command`/`env`/`builtin`/`nohup`, and `timeout [flags] N`.
const GH_PREFIX = new RegExp(
  "^(?:\\s+" +
    "|[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|\"[^\"]*\"|[^\\s'\"]*)(?=\\s)" +
    "|\"\\$\\{[^\"}]*\\}\"(?=\\s)|\"\\$[A-Za-z_][A-Za-z0-9_]*\"(?=\\s)|\\$\\{[^}\\s]*\\}(?=\\s)" +
    "|(?:command|env|builtin|nohup)(?=\\s)" +
    "|timeout(?:\\s+-\\S+(?:\\s+[^\\s-]\\S*)?)*\\s+[0-9.]+[smhd]?(?=\\s))",
);
const GH_WORD = /^(?:gh|[A-Za-z0-9_]*_gh)(?=[\s)])/;

/** True when the command word at `p` (after any GH_PREFIX words) is `gh` or a `*_gh` wrapper. */
function ghAt(s: string, p: number): boolean {
  for (;;) {
    const m = s.slice(p).match(GH_PREFIX);
    if (!m || m[0].length === 0) break;
    p += m[0].length;
  }
  return GH_WORD.test(s.slice(p));
}

/**
 * Every `$( [prefix…] gh|*_gh … <merge> … )` capture in `text`, and every backtick capture of the same shape that is the value
 * of an assignment (`` x=`gh …` `` or `` x="`gh …`" ``), as the substitution's own text. Backticks elsewhere are not scanned:
 * in a SKILL.md they are inline code (`` `gh run view … 2>&1 | tail` `` in prose is not a capture).
 */
function findMergedGhCaptures(text: string): string[] {
  const s = joinContinuations(text);
  const out: string[] = [];
  for (let k = s.indexOf("$("); k >= 0; k = s.indexOf("$(", k + 2)) {
    if (!ghAt(s, k + 2)) continue;
    const end = matchingParen(s, k + 2);
    if (end > 0 && topLevelMerge(s.slice(k + 2, end - 1))) out.push(s.slice(k, end));
  }
  for (const m of s.matchAll(/="?`((?:\\.|[^`\\\n])*)`/g)) {
    if (ghAt(m[1], 0) && topLevelMerge(m[1])) out.push(m[0].slice(m[0].indexOf("`")));
  }
  return out;
}

/** The ONE file-list chokepoint: tracked files (dot-dirs included, unlike Bun `Glob`), minus tests and archives. */
function listGuard2Files(root: string, pathspecs: string[] = GUARD2_PATHSPECS, env: NodeJS.ProcessEnv = gitCleanEnv() as NodeJS.ProcessEnv): string[] {
  return execFileSync("git", ["ls-files", "-z", "--", ...pathspecs], { cwd: root, env, encoding: "utf8" })
    .split("\0")
    .filter((f) => f !== "" && GUARD2_EXT.test(f) && !/\.test\.(sh|ts)$/.test(f) && !f.includes("/archive/"));
}

type Finding = { path: string; text: string };
function scanGuard2(root: string, files: string[]): Finding[] {
  const out: Finding[] = [];
  for (const f of files) {
    let text: string;
    try {
      text = readFileSync(resolve(root, f), "utf-8");
    } catch {
      continue; // tracked but deleted in the working tree
    }
    for (const t of findMergedGhCaptures(text)) out.push({ path: f, text: t });
  }
  return out;
}

/**
 * Shrink-only exclusion list: `<path>` + a literal substring of the matched capture + the exact count of captures it covers.
 * Each is a site that prints no hint today and that this PR does not edit (CTO ruling F1). A stale entry fails, and so does
 * any count that moved, in either direction: a new capture in an excluded file is not hidden by the existing entry.
 * Measured 2026-11-28 by running this scan on the tree, and re-measured with every MERGE_AT spelling and the backtick scan: no
 * new site. The plan's `--log-failed` dumps are NOT here: they are pipes
 * (`gh run view … --log-failed 2>&1 | tail`), not captures, so the scan never matches them and an entry would be stale.
 */
type Exclusion = { path: string; substr: string; count: number };
const EXCLUSIONS: Exclusion[] = [
  // ship post-merge release poll: `gh run list` prints no hint
  { path: "plugins/soleur/skills/ship/SKILL.md", substr: "gh run list --workflow <workflow-filename>", count: 1 },
  // worktree-manager draft-PR bootstrap: the error text is echoed to the operator, never parsed as a value
  { path: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh", substr: 'gh pr list --head "$branch"', count: 1 },
  { path: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh", substr: "gh pr create --draft", count: 1 },
  // community digest's six `gh api` reads (the issues read appears twice)
  { path: "plugins/soleur/skills/community/scripts/github-community.sh", substr: 'gh api "repos/${repo}/issues?', count: 2 },
  { path: "plugins/soleur/skills/community/scripts/github-community.sh", substr: 'gh api --paginate "repos/${repo}/pulls?', count: 1 },
  { path: "plugins/soleur/skills/community/scripts/github-community.sh", substr: 'gh api "repos/${repo}/commits?', count: 1 },
  { path: "plugins/soleur/skills/community/scripts/github-community.sh", substr: "gh api graphql", count: 1 },
  { path: "plugins/soleur/skills/community/scripts/github-community.sh", substr: 'gh api "repos/${repo}" ', count: 1 },
  // the admin hatch greps `err` for 'Base branch was modified'; it never parses a state from it
  { path: "plugins/soleur/skills/ship/references/settle-then-admin-merge.md", substr: "gh pr merge <N> --squash --admin", count: 1 },
];

type Guard2Verdict = { unexcluded: Finding[]; stale: Exclusion[]; miscounted: { entry: Exclusion; got: number }[] };
function judgeGuard2(findings: Finding[], exclusions: Exclusion[]): Guard2Verdict {
  const got = new Map<Exclusion, number>(exclusions.map((e) => [e, 0]));
  const unexcluded: Finding[] = [];
  for (const f of findings) {
    const e = exclusions.find((x) => x.path === f.path && f.text.includes(x.substr));
    if (e) got.set(e, (got.get(e) ?? 0) + 1);
    else unexcluded.push(f);
  }
  return {
    unexcluded,
    stale: exclusions.filter((e) => got.get(e) === 0),
    miscounted: exclusions.filter((e) => (got.get(e) ?? 0) > 0 && got.get(e) !== e.count).map((e) => ({ entry: e, got: got.get(e)! })),
  };
}
const GREEN: Guard2Verdict = { unexcluded: [], stale: [], miscounted: [] };

/** Synthesized findings equal to today's excluded set, for the pure mutation rows. */
function excludedFindings(): Finding[] {
  return EXCLUSIONS.flatMap((e) => Array.from({ length: e.count }, () => ({ path: e.path, text: `$(${e.substr} … ${MERGE})` })));
}

describe("Guard 2: no gh capture merges stderr into its value", () => {
  test("the tree: zero unexcluded captures, zero stale exclusions, every count exact, and the file floor holds", () => {
    const files = listGuard2Files(REPO_ROOT);
    // floor (mutation 2): a typo'd pathspec must not pass over an empty list. 56 non-test files contain `gh pr view` (2026-11-28).
    const withPrView = files.filter((f) => readFileSync(resolve(REPO_ROOT, f), "utf-8").includes("gh pr view"));
    expect(withPrView.length).toBeGreaterThanOrEqual(10);
    expect(files.some((f) => f.startsWith(".claude/hooks/"))).toBe(true);
    const verdict = judgeGuard2(scanGuard2(REPO_ROOT, files), EXCLUSIONS);
    expect(verdict).toEqual(GREEN);
  });

  test("mutation 1: the fence's verbatim two-line read with `2>&1` on the --jq continuation is found (joiner + paren-depth)", () => {
    const fence = `     s=$(gh pr view "$PR" --json state,mergeStateStatus \\\n       --jq '"\\(.state) \\(.mergeStateStatus)"' ${MERGE}) || s="fetch-error: $s"\n`;
    expect(findMergedGhCaptures(fence)).toHaveLength(1);
    // the same text without the joiner is a capture whose top level ends at the backslash line: the joiner is load-bearing
    expect(findMergedGhCaptures(fence.replace("\\\n", "\n"))).toHaveLength(0);
  });

  test("mutation 2: a file list that resolves empty fails the floor", () => {
    const files = listGuard2Files(REPO_ROOT, ["plugins-typo"]);
    expect(files.filter((f) => readFileSync(resolve(REPO_ROOT, f), "utf-8").includes("gh pr view")).length).toBeLessThan(10);
  });

  test("mutation 4: fixing an excluded site without deleting its entry is a stale exclusion", () => {
    const fixed = excludedFindings().filter((f) => !f.text.includes('gh pr list --head "$branch"'));
    const v = judgeGuard2(fixed, EXCLUSIONS);
    expect(v.stale.map((e) => e.substr)).toEqual(['gh pr list --head "$branch"']);
    expect(judgeGuard2(excludedFindings(), EXCLUSIONS)).toEqual(GREEN); // control: the synthesized set is exactly covered
  });

  test("mutation 5: a new `$(gh run list … 2>&1)` in a skill file is not excluded", () => {
    const md = "```bash\nr=$(gh run list --workflow ci.yml --limit 1 --json status " + MERGE + ")\n```\n";
    const found = findMergedGhCaptures(md).map((text) => ({ path: "plugins/soleur/skills/new-skill/SKILL.md", text }));
    expect(found).toHaveLength(1);
    expect(judgeGuard2([...excludedFindings(), ...found], EXCLUSIONS).unexcluded).toEqual(found);
  });

  test("mutation 6: a prefix-wrapped command word is still the gh command", () => {
    for (const cmd of [
      `x=$("\${to[@]}" gh pr view "$PR" --json state ${MERGE})`,
      `x=$(timeout 30 gh pr view "$PR" --json state ${MERGE})`,
      `x=$(timeout -k 5 30s gh pr view "$PR" ${MERGE})`,
      `x=$(timeout -v -k5 30 gh pr view "$PR" ${MERGE})`,
      `x=$(timeout --foreground --kill-after=2 30 gh pr view "$PR" ${MERGE})`,
      `x=$(command gh pr view "$PR" ${MERGE})`,
      `x=$(GH_PAGER= GH_HOST="github.com" gh pr view "$PR" ${MERGE})`,
      `x=$(env GH_PAGER=cat gh pr view "$PR" ${MERGE})`,
      `cur=$(parked_gh pr view --json number --jq .number ${MERGE})`,
      `x="$(gh pr view "$PR" --jq '.a | "\\(.b))"' ${MERGE})"`,
    ]) expect({ cmd, n: findMergedGhCaptures(cmd).length }).toEqual({ cmd, n: 1 });
  });

  test("mutation 7: a second capture in an excluded file exceeds that entry's count", () => {
    const extra = { path: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh", text: `$(gh pr list --head "$branch" --json url ${MERGE})` };
    const v = judgeGuard2([...excludedFindings(), extra], EXCLUSIONS);
    expect(v.unexcluded).toEqual([]);
    expect(v.miscounted.map((m) => [m.entry.substr, m.got])).toEqual([['gh pr list --head "$branch"', 2]]);
  });

  test("mutation 8: every other stderr-merge spelling, and an assignment's backtick capture, is found", () => {
    const AMP = "&";
    for (const cmd of [
      `s=$(gh pr view "$PR" --json state 2>${AMP} 1)`,
      `s=$(gh pr view "$PR" --json state 2>${AMP}  1)`,
      `s=$(gh pr view "$PR" --json state |${AMP} cat)`,
      `s=$(gh pr view "$PR" --json state ${AMP}>/dev/stdout)`,
      `s=$(gh pr view "$PR" --json state ${AMP}>>"$f")`,
      `s=$(gh pr view "$PR" --json state 2>/dev/stdout)`,
      `s=$(gh pr view "$PR" --json state 2> /dev/fd/1)`,
      `s=$(gh pr view "$PR" --json state 2>>/dev/stdout)`,
      // the fence's own redirect kept, a merge added after it (the mutant the fixture's static row also refuses)
      `s=$(gh pr view "$PR" --json state 2>"\${GH_ERR:-/dev/null}" 2>${AMP} 1)`,
      "s=`gh pr view 1 --json state " + MERGE + "`",
      's="`gh pr view 1 --json state |' + AMP + ' head -1`"',
      "local s=`timeout 30 gh pr view 1 " + MERGE + "`",
    ]) expect({ cmd, n: findMergedGhCaptures(cmd).length }).toEqual({ cmd, n: 1 });
  });

  test("EXCLUSIONS is pinned: its length and every entry, literally, so the list cannot grow unnoticed", () => {
    expect(EXCLUSIONS.length).toBe(9);
    expect(EXCLUSIONS.map((e) => `${e.path} | ${e.substr} | ${e.count}`)).toEqual([
      "plugins/soleur/skills/ship/SKILL.md | gh run list --workflow <workflow-filename> | 1",
      'plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh | gh pr list --head "$branch" | 1',
      "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh | gh pr create --draft | 1",
      'plugins/soleur/skills/community/scripts/github-community.sh | gh api "repos/${repo}/issues? | 2',
      'plugins/soleur/skills/community/scripts/github-community.sh | gh api --paginate "repos/${repo}/pulls? | 1',
      'plugins/soleur/skills/community/scripts/github-community.sh | gh api "repos/${repo}/commits? | 1',
      "plugins/soleur/skills/community/scripts/github-community.sh | gh api graphql | 1",
      'plugins/soleur/skills/community/scripts/github-community.sh | gh api "repos/${repo}"  | 1',
      "plugins/soleur/skills/ship/references/settle-then-admin-merge.md | gh pr merge <N> --squash --admin | 1",
    ]);
    expect(EXCLUSIONS.reduce((a, e) => a + e.count, 0)).toBe(10);
  });

  test("the Guard 2 describe keeps its test count (a deleted mutation row is a red, not a silent pass)", () => {
    const self = readFileSync(resolve(import.meta.dir, "pr-merge-poll.test.ts"), "utf-8");
    const start = self.indexOf('describe("Guard 2: no gh capture merges stderr into its value"');
    expect(start).toBeGreaterThan(0);
    const body = self.slice(start);
    expect((body.match(/^ {2}test\(/gm) ?? []).length).toBeGreaterThanOrEqual(12);
  });

  test("not a violation: stderr to a file or /dev/null, a merge inside quotes or a nested group, and non-gh commands", () => {
    for (const ok of [
      `s=$(gh pr view "$PR" --json state --jq '"\\(.state) \\(.mergeStateStatus)"' 2>"$errf")`,
      `s=$(gh pr view "$PR" --json state 2>"\${GH_ERR:-/dev/null}") || s="fetch-error: $(gh_err_line $?)"`,
      `s=$(gh pr view "$PR" --json state 2>/dev/null)`,
      `s=$(gh pr view "$PR" --jq '"${MERGE})"')`,
      `s=$(gh pr view "$PR" --json body --jq "$(printf x ${MERGE})")`,
      `v=$(git log -1 ${MERGE})`,
      `v=$(ghost run ${MERGE})`,
      `v=$(gh_err_line ${MERGE})`,
      `gh run view 1 --log-failed ${MERGE} | tail -80`,
      `s=$(gh pr view "$PR" --json state 2>/dev/null >` + `&2)`,
      `s=$(gh pr view "$PR" --json state 2>/dev/stdout_log)`,
      "Prose: never `gh pr view 1 " + MERGE + "` in a capture.",
      "Prose: `gh run view 1 --log-failed " + MERGE + " | tail` is a pipe.",
      "s=`git log -1 " + MERGE + "`",
    ]) expect({ ok, n: findMergedGhCaptures(ok).length }).toEqual({ ok, n: 0 });
  });

  test("harness rows H-a / H-b and mutation 3: a real fixture tree through the real file-list chokepoint", () => {
    const root = mkdtempSync(join(tmpdir(), "guard2-"));
    try {
      const git = gitFixture(root);
      git(["init", "-q", "-b", "main"]);
      const put = (rel: string, body: string) => {
        mkdirSync(dirname(join(root, rel)), { recursive: true });
        writeFileSync(join(root, rel), body);
      };
      // compliant first sites (H-b: must-PASS non-canonical forms) …
      put("plugins/soleur/scripts/a.sh", `s=$(gh pr view "$PR" --json state 2>"$errf")\nt=$(gh pr view "$PR" 2>/dev/null)\n`);
      put("plugins/soleur/skills/x/SKILL.md", "```bash\ns=$(gh pr view 1 --json state 2>\"$errf\")\n```\n");
      // … a violation in a SECOND file under the dot-dir (mutation 3), and the same shape in files the scan must skip
      put(".claude/hooks/b.sh", `cur=$(parked_gh pr view --json number ${MERGE})\n`);
      put("plugins/soleur/test/b.test.sh", `cur=$(gh pr view ${MERGE})\n`);
      put("plugins/soleur/test/b.test.ts", `const s = "$(gh pr view ${MERGE})";\n`);
      put("plugins/soleur/skills/archive/old.md", `cur=$(gh pr view ${MERGE})\n`);
      put("elsewhere/c.sh", `cur=$(gh pr view ${MERGE})\n`);
      git(["add", "-A"]);
      const env = gitCleanEnv({ GIT_CEILING_DIRECTORIES: dirname(root) }) as NodeJS.ProcessEnv;
      const files = listGuard2Files(root, GUARD2_PATHSPECS, env);
      expect(files.sort()).toEqual([".claude/hooks/b.sh", "plugins/soleur/scripts/a.sh", "plugins/soleur/skills/x/SKILL.md"]);
      // H-a: exactly the planted file
      expect(scanGuard2(root, files).map((f) => f.path)).toEqual([".claude/hooks/b.sh"]);
      // H-b: the compliant files alone report none
      expect(scanGuard2(root, files.filter((f) => f !== ".claude/hooks/b.sh"))).toEqual([]);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
