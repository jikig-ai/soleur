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
  DEFAULT_CLAUDE_SETTINGS,
  runHookSelfTest,
  spawnClaudeEval,
  spawnSimple,
  STDOUT_TAIL_CAP_BYTES,
} from "@/server/inngest/functions/_cron-claude-eval-substrate";

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
