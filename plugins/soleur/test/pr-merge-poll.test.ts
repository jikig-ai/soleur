import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync } from "fs";
import { resolve } from "path";
import {
  isBehindPollState,
  isTerminalPollState,
  shouldResyncBeforePoll,
  behindSyncInstructions,
  PR_BEHIND_SYNC_SENTINEL,
  MERGE_STATE_BEHIND,
  MERGE_STATE_DIRTY,
  formatPrPollState,
} from "../lib/pr-merge-poll";
import { pollInstructions } from "../lib/harness";

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
      expect(text).toContain("--help 2>/dev/null | grep -q -- '--fence'");
      expect(text).not.toContain("--help 2>/dev/null | grep -q -- '--step'");
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