import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { reportSilentFallback } from "@/server/observability";
import {
  upsertRoutineRunProgress,
  heartbeatRoutineRunProgress,
  HEARTBEAT_INTERVAL_MS,
} from "@/server/inngest/routine-run-progress";
import {
  buildAuthenticatedCloneUrl,
  DeployInProgressError,
  deployLeaseAgeMsIfFresh,
  redactToken,
  resolveCronWorkspaceRoot,
  warnIfCronWorkspaceLowOnDisk,
  type HandlerArgs,
} from "./_cron-shared";

export interface SpawnResult {
  ok: boolean;
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  abortedByTimeout: boolean;
  durationMs: number;
  // Bounded tail of the child's stderr (redacted), so a non-zero exit is
  // self-diagnosing in Sentry. The line-by-line pino stream goes to app stdout,
  // which Vector does NOT ship to Better Stack — capturing the tail here is the
  // only path that reaches Sentry. #4714 follow-up (roadmap/content silent
  // non-zero exits were undiagnosable: app stdout is not in the log warehouse).
  // Optional: sibling crons (daily-triage, follow-through-monitor) build their
  // own SpawnResult literals via the inline spawn pattern and do not populate it.
  stderrTail?: string;
  // Bounded tail of the child's stdout (redacted). `claude --print` writes its
  // max-turns notice to STDOUT, not stderr — that notice previously reached only
  // logger.info (app stdout), which Vector does NOT ship to Better Stack, so a
  // turn-exhaustion exit was red-on-the-monitor but not self-diagnosing without
  // SSH. Capturing the tail here folds the notice into the scheduled-output-missing
  // Sentry extra alongside stderrTail. #4773 (follow-up to #4714/#4770).
  // Optional, same as stderrTail: inline-spawn sibling crons do not populate it.
  stdoutTail?: string;
}

// #5728 — synthetic SpawnResult for the silence-hole audit issue (#4960) when an
// output-aware handler's body THREW before claude-eval produced a real result.
// Shared by the cohort so the 6-field literal isn't copy-pasted 8× (the only
// field the type system can't pin against drift is the exitCode/durationMs
// values). Carries the cron name in stderrTail so the FAILED issue is
// self-diagnosing. Returns the exact Pick that ensureScheduledAuditIssue reads.
export function makeThrewSpawnResult(
  cronName: string,
): Pick<
  SpawnResult,
  "exitCode" | "signal" | "abortedByTimeout" | "durationMs" | "stdoutTail" | "stderrTail"
> {
  return {
    exitCode: -1,
    signal: null,
    abortedByTimeout: false,
    durationMs: 0,
    stdoutTail: "",
    stderrTail: `${cronName} threw before claude-eval completed`,
  };
}

export const KILL_ESCALATION_MS = 5_000;

// Hard ceiling on captured child stderr — a pathological process must not OOM
// the worker. 8 KiB comfortably holds a git fatal: line + a few hints.
export const STDERR_CAP_BYTES = 8192;

// Hard ceiling on captured child stdout. The max-turns notice is a few hundred
// bytes; the cap is a pathological-OOM ceiling (a runaway --print could stream
// unbounded stdout), same rationale and value as STDERR_CAP_BYTES.
export const STDOUT_TAIL_CAP_BYTES = 8192;

export function resolveClaudeBin(): string {
  const override = process.env.CLAUDE_BIN;
  if (override && existsSync(override)) return override;

  const candidates = [
    "/app/node_modules/.bin/claude",
    join(process.cwd(), "node_modules/.bin/claude"),
    join(process.cwd(), "apps/web-platform/node_modules/.bin/claude"),
  ];
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  throw new Error(
    `claude binary not found in any known location: ${candidates.join(", ")}. ` +
      "Set CLAUDE_BIN env var to override.",
  );
}

export function spawnSimple(
  cmd: string,
  args: string[],
  opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<{
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  stderr: string;
}> {
  return new Promise((resolve) => {
    // Capture stderr (stdin/stdout stay ignored). Without this, a non-zero
    // exit — e.g. `git clone` exit 128 — discarded the only line that says
    // WHY (auth/network/DNS), leaving Sentry with an opaque exit code. The
    // caller folds this into the thrown error so the next failure is
    // self-diagnosing (cq-silent-fallback-must-mirror-to-sentry).
    const child = spawn(cmd, args, {
      stdio: ["ignore", "ignore", "pipe"],
      cwd: opts.cwd,
      env: opts.env ?? process.env,
    });
    let stderr = "";
    if (child.stderr) {
      child.stderr.setEncoding("utf-8");
      child.stderr.on("data", (chunk: string) => {
        // Exact cap (slice on assignment) — appending whole chunks could
        // overshoot the ceiling by up to one chunk's length.
        if (stderr.length < STDERR_CAP_BYTES) {
          stderr = (stderr + chunk).slice(0, STDERR_CAP_BYTES);
        }
      });
    }
    child.on("exit", (exitCode: number | null, signal: NodeJS.Signals | null) => {
      resolve({ exitCode, signal, stderr: stderr.trim() });
    });
    child.on("error", (err: Error) => {
      resolve({ exitCode: -1, signal: null, stderr: err.message });
    });
  });
}

// =============================================================================
// Cron containment — hook-primary deny-by-default (v3.1 / #5018, #5000, #5004)
// =============================================================================
// #5000/#5004: when the cloud runner's bwrap cannot acquire unprivileged user
// namespaces (kernel `apparmor_restrict_unprivileged_userns` drift, #4928/#4932),
// the OS bash sandbox is unavailable and every `Bash` tool call inside
// `claude --print` fails → the cron self-reports FAILED (#4978/#4988). The host
// sysctl pin (#4932) recurred 4 days later, so the durable fix removes the cron's
// dependency on unprivileged userns: `sandbox.enabled:false` (host-independent).
//
// But disabling the sandbox removes the only thing containing headless bash.
// Phase-0 probes (committed AC0 evidence; re-verified on the prod-pinned CLI
// 2.1.79) proved that with the sandbox off, headless `claude --print` does NOT
// fail-close non-allowlisted commands via `--allowedTools`/`defaultMode` — only
// an explicit `permissions.deny` rule OR a PreToolUse hook blocks, and an
// unhooked tool class / a crashed hook FAILS OPEN. (The v1 `bypassPermissions`
// approach was P1-blocked as a credential-exfil vector; that token MUST NOT
// reappear.) So containment is the deny-by-default PreToolUse hook
// (`cron-bash-allowlist-hook.mjs`), registered per-spawn under a `*` catch-all
// matcher by buildCronEvalSettings(). This base overlay is inert — the hook is
// the control. See knowledge-base/.../2026-06-08-fix-cron-sandbox-hook-primary-containment-plan.md.

// Per-cron Bash command allowlists for the containment hook. Each entry is a
// command PREFIX at sub-command granularity (`gh issue list`, NOT `gh issue`);
// the hook matches a Bash command's DEQUOTED leading verb-phrase against these
// and denies anything else (plus all secret-reads / egress / interpreters /
// substitution / argument-injection, regardless of the allowlist). A cron ABSENT
// from this map (or mapped to []) is fully fail-closed → its bash is denied → it
// self-reports FAILED → Tier-2 (egress firewall) restores it. Only crons whose
// entire command surface is a finite allowlist are Tier-1.
export const ISSUE_CREATOR_BASH_ALLOWLIST = [
  "gh issue list",
  "gh issue create",
  "gh label list",
  "gh label create",
];

export const CRON_BASH_ALLOWLISTS: Record<string, string[]> = {
  "cron-roadmap-review": [
    "gh issue list",
    "gh issue view",
    "gh issue create",
    "gh issue edit",
    "gh issue close",
    "gh issue comment",
    "gh pr list",
    "gh pr create",
    "gh pr comment",
    "gh api repos/jikig-ai/soleur/",
    "gh label list",
    "gh label create",
    "git status",
    "git add",
    "git commit",
    "git checkout",
    "git switch",
    // `git push` (not `git push origin`) so flagged forms match — `git push -u
    // origin <branch>`, `git push origin HEAD`. The hook's gitVerbReason is the
    // origin-only enforcer (denies any push to a non-origin remote), so the
    // broader prefix is safe and the auto-fix-PR path (#5004 AC4c) is not
    // silently denied on its `-u` flag.
    "git push",
    "git rev-parse",
  ],
  // #5046 PR-2 Phase 2.C — the two Task-class audit crons restored by the
  // relax-minimal hook share one issue-creator surface (single const so the
  // two cannot drift apart). Issue-creators only: NO git verbs (their
  // prompts forbid commits/pushes), NO `gh api` (F4a: arbitrary-method API
  // access defeats the exfil defense), NO raw egress binaries. `gh label`
  // covers first-run label bootstrap. Pipes stay metachar-denied; the
  // prompts instruct pipe-free cap checks and --body-file (not env vars).
  "cron-agent-native-audit": ISSUE_CREATOR_BASH_ALLOWLIST,
  "cron-legal-audit": ISSUE_CREATOR_BASH_ALLOWLIST,
  // #5199 — cron-ux-audit's bash surface is issue-creator only. The
  // /soleur:ux-audit SKILL emits `gh issue list`/`gh issue create`/`gh label`
  // (verified at Phase 0). It also documents a `gh api … -f body=…` screenshot
  // attach (SKILL.md §7) — DELIBERATELY EXCLUDED here (same F4a rationale as the
  // two audit crons above: arbitrary-method `gh api` defeats the exfil defense).
  // The cron uploads screenshots to the Supabase ux-audit-artifacts bucket
  // separately (uploadFindings), so the attach is redundant; the issue still
  // files via `gh issue create --body-file`. The Playwright tools ux-audit needs
  // are mcp__* (NOT bash) — see CRON_MCP_ALLOWLISTS.
  "cron-ux-audit": ISSUE_CREATOR_BASH_ALLOWLIST,
  // #5199 — the 7 restored mergeMode:"auto" PR-flow crons. Persistence runs
  // node-side via safeCommitAndPr (git/gh-pr verbs are FORBIDDEN by every
  // prompt AND excluded here — cron-safe-commit-parity.test.ts invariant 3).
  // NO `gh api` (F4a). Eleventy builds defer to CI (decision A) → no
  // `npx @11ty/eleventy` / validate-*.sh. Each entry is evidence-gated to the
  // handler prompt + the /soleur:* SKILL it invokes.
  //
  // growth-audit (cron-growth-audit.ts): Step 5 `gh issue create`, Step 5.5
  // dedup `gh issue list` + tracking `gh issue create`/`gh issue view`/
  // `gh issue edit`. Bespoke (keeps issue view/edit beyond the issue-creator
  // shared const).
  "cron-growth-audit": [
    "gh issue list",
    "gh issue create",
    "gh issue view",
    "gh issue edit",
    "gh label list",
    "gh label create",
  ],
  // growth-execution (cron-growth-execution.ts): only `gh issue create` after
  // decision A drops the eleventy build + validate-seo.sh — pure issue-creator
  // surface.
  "cron-growth-execution": ISSUE_CREATOR_BASH_ALLOWLIST,
  // competitive-analysis (cron-competitive-analysis.ts): only `gh issue create`;
  // the SKILL's competitive-intelligence agent uses WebSearch/WebFetch tools
  // (no bash). Pure issue-creator surface.
  "cron-competitive-analysis": ISSUE_CREATOR_BASH_ALLOWLIST,
  // seo-aeo-audit (cron-seo-aeo-audit.ts): only `gh issue create` after
  // decision A drops the eleventy build + validate-seo.sh/validate-csp.sh (the
  // validate scripts take a built `_site` arg, unreachable in the
  // node_modules-free clone). Pure issue-creator surface.
  "cron-seo-aeo-audit": ISSUE_CREATOR_BASH_ALLOWLIST,
  // architecture-diagram-sync (cron-architecture-diagram-sync.ts): only
  // `gh issue create` for the weekly summary; diagram edits persist handler-side
  // via safeCommitAndPr (prompt forbids git/gh-pr verbs). Pure issue-creator surface.
  "cron-architecture-diagram-sync": ISSUE_CREATOR_BASH_ALLOWLIST,
  // content-generator (cron-content-generator.ts): only `gh issue create`;
  // prompt explicitly forbids a local eleventy build. Skills delegate via Task
  // (no inline bash). Pure issue-creator surface.
  "cron-content-generator": ISSUE_CREATOR_BASH_ALLOWLIST,
  // campaign-calendar (cron-campaign-calendar.ts): dedup `gh issue list`,
  // `gh issue comment`, `gh issue create`, heartbeat `gh issue close`.
  // `git log` OMITTED (depth-1 clone makes it unreliable; the SKILL offers a
  // filename-date fallback). Bespoke.
  "cron-campaign-calendar": [
    "gh issue list",
    "gh issue view",
    "gh issue create",
    "gh issue comment",
    "gh issue close",
    "gh label list",
    "gh label create",
  ],
  // community-monitor (cron-community-monitor.ts): `bash …community-router.sh`
  // (the router's child curl/gh-api are grandchild OS processes gated by the
  // egress firewall, NOT this hook), DEDUP `gh issue list`, `gh issue create`,
  // `gh issue comment`. Prompt-level `gh api` is REWRITTEN to
  // `gh issue list --json updatedAt,number` (F4a). Bespoke.
  "cron-community-monitor": [
    "bash plugins/soleur/skills/community/scripts/community-router.sh",
    "gh issue list",
    "gh issue create",
    "gh issue comment",
    "gh label list",
    "gh label create",
  ],
  // #5199 (final) — cron-bug-fixer, the LAST Tier-2-deferred cron and the widest
  // bash surface. UNLIKE the 7 auto-crons above, bug-fixer's commit lives in the
  // fix-issue SKILL (NOT safeCommitAndPr), so this entry legitimately INCLUDES
  // git/gh-pr PERSISTENCE verbs (cron-safe-commit-parity invariant 3 exempts it —
  // it sits in EXEMPT, not MIGRATED_ALL). Each verb is evidence-gated to the
  // EXACT form fix-issue/SKILL.md emits (re-verified at /work); LITERAL forms
  // only (the SKILL was rewritten in Phase 3.5 to drop eval/$VAR/$(...)/pipe).
  // allow[0] MUST be a bare-prefix verb (`gh issue view`) — runHookSelfTest runs
  // it through the real hook and REQUIRES allow before the agent spawns.
  // EXCLUDED: `gh api` (F4a — arbitrary-method API defeats the exfil defense);
  // `gh pr merge` (auto-merge is armed node-side via runAutoMergeGate's GraphQL
  // mutation, a PERSISTENCE_PREFIX forbidden form); `eval`/`node -e`/raw curl
  // (interpreters/egress the hook denies by design — the rewritten SKILL emits a
  // literal `./node_modules/.bin/vitest run` instead). `git config`/`git remote`/
  // `git ls-remote` are NOT here — gitVerbReason denies them unconditionally
  // (token-bearing remote URL).
  "cron-bug-fixer": [
    "gh issue view", // SKILL Phase 1 — gh issue view <N> --json …
    "gh issue comment", // SKILL Phase 6 — failure-handler comment
    "gh issue edit", // SKILL Phase 6 — gh issue edit <N> --add-label bot-fix/attempted
    "gh pr create", // SKILL Phase 5 — gh pr create --title … --body-file <path>
    "gh pr edit", // SKILL Phase 5.5 — gh pr edit <N> --add-label …
    "git status", // SKILL Phase 5 — git status --porcelain
    "git add", // SKILL Phase 5 — git add -- <literal-path> (blanket forms hook-denied)
    "git commit", // SKILL Phase 5 — git commit -m …
    "git checkout", // SKILL Phase 3 — worktree-add fallback path
    "git worktree", // SKILL Phase 3/6 — git worktree add … / remove …
    "git branch", // SKILL Phase 6 — git branch -D … (cleanup)
    "git push", // SKILL Phase 5 — git push -u origin … (origin-only via gitVerbReason)
    "bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh", // SKILL Phase 3
    "./node_modules/.bin/vitest run", // SKILL Phase 2/4 — LITERAL test verb (Phase 3.5 rewrite)
  ],
};

// #5199 — per-cron mcp__* allowance for the containment hook. The relax-minimal
// hook denies every mcp__* tool by default (its catch-all); a cron listed here
// gets EXACTLY the named mcp__* tools, delivered via the same per-cron
// `cron-allow.txt` file (the hook never sees cronName — see
// cron-bash-allowlist-hook.mjs `parseAllowlist`). `navigateOriginEnv` names the
// env var whose URL origin is the ONLY origin `mcp__playwright__browser_navigate`
// may load (the hook's URL-origin guard) — the load-bearing close on the
// secret-in-querystring-to-an-allowlisted-host exfil leg the content-blind
// egress firewall cannot see. A cron ABSENT from this map gets no mcp__* tools
// (the 2 issue-creator audit crons + roadmap-review stay fully mcp-denied).
export const CRON_MCP_ALLOWLISTS: Record<
  string,
  { tools: string[]; navigateOriginEnv?: string }
> = {
  // The 5 Playwright tools declared in cron-ux-audit.ts CLAUDE_CODE_FLAGS.
  "cron-ux-audit": {
    tools: [
      "mcp__playwright__browser_navigate",
      "mcp__playwright__browser_take_screenshot",
      "mcp__playwright__browser_resize",
      "mcp__playwright__browser_close",
      "mcp__playwright__browser_wait_for",
    ],
    navigateOriginEnv: "NEXT_PUBLIC_APP_URL",
  },
};

// Inert base overlay. `sandbox.enabled:false` = the host-independence fix;
// `defaultMode:"default"` + `allow:[]` are inert (the hook is the boundary). The
// token "bypassPermissions" MUST NOT appear here (v1 P1-blocked exfil primitive).
export const DEFAULT_CLAUDE_SETTINGS = {
  permissions: {
    allow: [] as string[],
    defaultMode: "default",
  },
  sandbox: {
    enabled: false,
  },
};

// Relative-to-spawnCwd paths inside the clone. The hook ships via the git clone
// (a tracked file) — so a Write to it is scoped to the single ephemeral run
// (and denied by the hook's own Write/Edit guard).
const HOOK_REL_PATH =
  "apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs";
const ALLOWLIST_REL_PATH = ".claude/cron-allow.txt";

// Resolve `node` by ABSOLUTE path for the hook command. Relying on PATH lookup
// risks a PATH-drift fail-open (a cron whose buildSpawnEnv trims PATH → node not
// found → hook crashes → fail-open per probe D-new-1). Mirrors resolveClaudeBin.
export function resolveNodeBin(): string {
  const override = process.env.NODE_BIN;
  if (override && existsSync(override)) return override;
  if (process.execPath && existsSync(process.execPath)) return process.execPath;
  for (const c of ["/usr/local/bin/node", "/usr/bin/node"]) {
    if (existsSync(c)) return c;
  }
  return "node";
}

// Build the per-spawn settings overlay: the inert base + the deny-by-default
// hook under a `*` catch-all matcher (so NO tool class is unhooked — an unhooked
// class fails open per probe). The hook command is `<node> <hook> <allowlist>`,
// all absolute, so it is independent of the hook's runtime CWD.
export function buildCronEvalSettings(
  spawnCwd: string,
): Record<string, unknown> {
  const command = `${resolveNodeBin()} ${join(spawnCwd, HOOK_REL_PATH)} ${join(
    spawnCwd,
    ALLOWLIST_REL_PATH,
  )}`;
  return {
    ...DEFAULT_CLAUDE_SETTINGS,
    hooks: {
      PreToolUse: [{ matcher: "*", hooks: [{ type: "command", command }] }],
    },
  };
}

// Spawn-time hook self-test (D2 — mitigates the probe D-new-1 fail-open: a
// crashed/missing/misregistered hook silently reverts to fail-open). Runs the
// hook BINARY against a canonical exfil payload (and, for a Tier-1 cron, its
// first allowed verb) BEFORE the real agent spawns, using the byte-identical
// node+hook+allowlist the real spawn uses. Throws (→ cron aborts → FAILED
// self-report) rather than letting the cron run unprotected.
export function runHookSelfTest(args: {
  spawnCwd: string;
  cronName: string;
  allow: string[];
  // #5199 — the per-cron mcp__* policy (empty for every cron except ux-audit).
  // Passed explicitly (not parsed from the file) so the probes cross-check that
  // the file ACTUALLY delivered the directives: a positive app-origin navigate
  // probe that the file failed to enable would deny → throw, exactly like the
  // bash allow[0] probe verifies bash delivery.
  mcpAllow?: string[];
  navigateOrigin?: string | null;
}): void {
  const { spawnCwd, cronName, allow, mcpAllow = [], navigateOrigin = null } = args;
  const nodeBin = resolveNodeBin();
  const hookAbs = join(spawnCwd, HOOK_REL_PATH);
  const allowlistAbs = join(spawnCwd, ALLOWLIST_REL_PATH);
  const run = (payload: object): string => {
    try {
      return execFileSync(nodeBin, [hookAbs, allowlistAbs], {
        input: JSON.stringify(payload),
        encoding: "utf-8",
        timeout: 10_000,
      });
    } catch (err) {
      // execFileSync throws on non-zero exit / missing binary → treat as a
      // self-test failure (fail-closed), not a pass.
      return `self-test-exec-error: ${(err as Error).message}`;
    }
  };
  const denied = run({
    tool_name: "Bash",
    tool_input: { command: "cat /proc/self/environ" },
  });
  if (!denied.includes('"permissionDecision":"deny"')) {
    throw new Error(
      `[${cronName}] containment hook self-test FAILED: the canonical exfil payload ` +
        `was NOT denied (hook unreachable/misconfigured → would fail-open). Aborting cron.`,
    );
  }
  if (allow.length > 0) {
    const allowed = run({
      tool_name: "Bash",
      tool_input: { command: allow[0] },
    });
    if (!allowed.includes('"permissionDecision":"allow"')) {
      throw new Error(
        `[${cronName}] containment hook self-test FAILED: allowlisted verb "${allow[0]}" ` +
          `was NOT allowed (allowlist not delivered). Aborting cron.`,
      );
    }
  }

  // Tier-2 relax gate (#5046 PR-2, AC-P2.2). The hook's catch-all now allows
  // Task/Skill ONLY because sub-agents inherit this same hook — their interior
  // Bash hits the SAME containment the canonical-exfil probe above just proved.
  // Three spawn-time assertions keep that inference honest, per spawn:
  //   (1) Task allows — the relaxed hook actually shipped in this clone (a
  //       stale/reverted hook would fail-close every Task-using cron);
  //   (2) an unknown tool class still denies — the relax did not destroy the
  //       fail-closed catch-all (a new tool class must never fail-open);
  //   (3) the spawn's settings.json registers THIS hook under a `*` matcher —
  //       the structural precondition for sub-agent inheritance (probe D-new-1:
  //       a tool class with no matcher FAILS OPEN, so a narrowed matcher would
  //       leave a sub-agent's tool calls unhooked).
  // Any failure throws → the cron aborts (FAILED self-report), so a Task-using
  // cron never runs with an unverified relax.
  // Probe Task AND Skill separately: today they share one switch case, but a
  // future hook edit could split them — and a clone carrying a Task-only
  // intermediate would silently fail-close every Skill-invoking cron.
  for (const relaxedTool of ["Task", "Skill"]) {
    const allowed = run({ tool_name: relaxedTool, tool_input: {} });
    if (!allowed.includes('"permissionDecision":"allow"')) {
      throw new Error(
        `[${cronName}] containment hook self-test FAILED: ${relaxedTool} was NOT ` +
          `allowed (Tier-2 relax not delivered in this clone — a ${relaxedTool}-using ` +
          `cron would fail-closed). Aborting cron.`,
      );
    }
  }
  const unknownDenied = run({
    tool_name: "Tier2FailClosedProbeTool",
    tool_input: {},
  });
  if (!unknownDenied.includes('"permissionDecision":"deny"')) {
    throw new Error(
      `[${cronName}] containment hook self-test FAILED: an unknown tool class ` +
        `was NOT denied (fail-closed catch-all lost — a new tool class would ` +
        `fail-open). Aborting cron.`,
    );
  }
  let matcherOk = false;
  try {
    const settings = JSON.parse(
      readFileSync(join(spawnCwd, ".claude", "settings.json"), "utf-8"),
    ) as {
      hooks?: {
        PreToolUse?: Array<{
          matcher?: string;
          hooks?: Array<{ command?: string }>;
        }>;
      };
    };
    matcherOk = (settings.hooks?.PreToolUse ?? []).some(
      (entry) =>
        entry.matcher === "*" &&
        (entry.hooks ?? []).some((h) =>
          (h.command ?? "").includes("cron-bash-allowlist-hook.mjs"),
        ),
    );
  } catch {
    matcherOk = false; // unreadable/missing settings → registration unverifiable
  }
  if (!matcherOk) {
    throw new Error(
      `[${cronName}] containment hook self-test FAILED: settings.json does not ` +
        `register the containment hook under a \`*\` matcher — sub-agent (Task) ` +
        `tool calls would be unhooked (fail-open per probe D-new-1). Aborting cron.`,
    );
  }

  // #5199 — egress / mcp containment probes. WebFetch is ALWAYS denied (no cron
  // gets raw web egress). browser_navigate is denied UNLESS this cron pins an
  // mcp-allow + navigate-origin, in which case the app-origin navigate must
  // ALLOW (proves the directives were delivered) while an off-origin navigate
  // and an off-list mcp tool must DENY (proves the relax did not go global —
  // the cross-cron-negative property, enforced per spawn).
  const webFetchDenied = run({
    tool_name: "WebFetch",
    tool_input: { url: "https://example.com/" },
  });
  if (!webFetchDenied.includes('"permissionDecision":"deny"')) {
    throw new Error(
      `[${cronName}] containment hook self-test FAILED: WebFetch was NOT denied ` +
        `(raw egress surface — the hook must deny it for every cron). Aborting cron.`,
    );
  }
  if (mcpAllow.length === 0) {
    // No mcp relaxation for this cron → browser_navigate must be denied.
    const navDenied = run({
      tool_name: "mcp__playwright__browser_navigate",
      tool_input: { url: navigateOrigin ?? "https://app.soleur.ai/" },
    });
    if (!navDenied.includes('"permissionDecision":"deny"')) {
      throw new Error(
        `[${cronName}] containment hook self-test FAILED: mcp browser_navigate was ` +
          `NOT denied for a cron with no mcp-allow section (relax leaked globally). Aborting cron.`,
      );
    }
  } else {
    if (navigateOrigin) {
      const navAllowed = run({
        tool_name: "mcp__playwright__browser_navigate",
        tool_input: { url: `${navigateOrigin}/` },
      });
      if (!navAllowed.includes('"permissionDecision":"allow"')) {
        throw new Error(
          `[${cronName}] containment hook self-test FAILED: app-origin browser_navigate ` +
            `was NOT allowed (mcp-allow/navigate-origin not delivered in this clone). Aborting cron.`,
        );
      }
      const navOffOrigin = run({
        tool_name: "mcp__playwright__browser_navigate",
        tool_input: { url: "https://exfil.example.test/collect?x=1" },
      });
      if (!navOffOrigin.includes('"permissionDecision":"deny"')) {
        throw new Error(
          `[${cronName}] containment hook self-test FAILED: off-origin browser_navigate ` +
            `was NOT denied (URL-origin guard missing — exfil leg open). Aborting cron.`,
        );
      }
    }
    const offListMcp = run({
      tool_name: "mcp__playwright__browser_run_code_unsafe",
      tool_input: {},
    });
    if (!offListMcp.includes('"permissionDecision":"deny"')) {
      throw new Error(
        `[${cronName}] containment hook self-test FAILED: an mcp tool outside the ` +
          `mcp-allow set was NOT denied (relax over-broad). Aborting cron.`,
      );
    }
  }
}

export async function setupEphemeralWorkspace(args: {
  installationToken: string;
  cronName: string;
}): Promise<{ ephemeralRoot: string; spawnCwd: string }> {
  const { installationToken, cronName } = args;

  // Deploy-lease drain gate (#5669 / ADR-078). If ci-deploy.sh is mid-swap it
  // has written a fresh ${CRON_WORKSPACE_ROOT}/.deploy-lease; defer BEFORE the
  // mkdtemp+clone so the imminent `docker stop` cannot kill this claude child
  // (the :706 spawn-cwd symptom). Single pre-spawn choke point — every heavy
  // claude-eval cron funnels through here. Stale leases are fail-open ignored
  // (deployLeaseAgeMsIfFresh TTL), so a crashed deploy never darks crons.
  const leaseAgeMs = await deployLeaseAgeMsIfFresh();
  if (leaseAgeMs !== null) {
    // Structured + queryable in Sentry/Better Stack (CTO guardrail 3): the
    // reportSilentFallback mirror makes "why did cron X skip during the 14:03
    // deploy?" answerable with no SSH. Distinct reason so it is never read as a
    // real setup failure.
    reportSilentFallback(null, {
      feature: "cron-claude-eval",
      op: "deploy-lease-fresh",
      message: `[${cronName}] deferring cron start: deploy in progress (lease age ${leaseAgeMs}ms)`,
    });
    throw new DeployInProgressError(cronName, leaseAgeMs);
  }

  const ephemeralRoot = await mkdtemp(
    join(resolveCronWorkspaceRoot(), `soleur-${cronName}-`),
  );
  const spawnCwd = join(ephemeralRoot, "repo");

  // Pre-clone free-space guard (#4684/#4689 observability fold-in). Non-fatal:
  // warns in Sentry if the workspace root is low on disk before the clone.
  await warnIfCronWorkspaceLowOnDisk(ephemeralRoot, cronName);

  const cloneUrl = buildAuthenticatedCloneUrl(installationToken);
  const cloneResult = await spawnSimple("git", [
    "clone",
    "--depth=1",
    cloneUrl,
    spawnCwd,
  ]);
  if (cloneResult.exitCode !== 0) {
    // Fold git's stderr into the message so the failure is self-diagnosing
    // (auth vs network vs DNS). Redact the installation token first — the
    // clone URL embeds it and git echoes the remote on some failures.
    // cloneResult.stderr is already trimmed by spawnSimple.
    const reason = redactToken(cloneResult.stderr, installationToken);
    throw new Error(
      `git clone failed (exit ${cloneResult.exitCode}, signal ${cloneResult.signal}) for jikig-ai/soleur` +
        (reason ? `: ${reason}` : ""),
    );
  }

  // #5091 — the depth-1 clone already contains the full tracked
  // plugins/soleur tree, and headless `--plugin-dir plugins/soleur` resolves
  // against it (spike-verified under a scrubbed HOME; the flag itself remains
  // required per #4993/#4987). The previous rm+symlink(getPluginPath()) swap
  // made clone-git see every tracked plugins/soleur file as DELETED on every
  // run (the #5026 destructive-PR contamination, 654 files) and routed the
  // spawned claude's plugin-docs edits to the HOST plugin dir — mutating the
  // live install and making the edits uncommittable from the clone.
  const pluginDir = join(spawnCwd, "plugins", "soleur");

  const claudeDir = join(spawnCwd, ".claude");
  await mkdir(claudeDir, { recursive: true });
  // Per-cron Bash allowlist for the containment hook (deny-all if absent → the
  // cron fail-closes and self-reports FAILED; Tier-2 restores it). Read by the
  // hook from disk; the hook also denies any tool from READING `.claude/`.
  const allow = CRON_BASH_ALLOWLISTS[cronName] ?? [];
  // #5199 — append the per-cron mcp__* policy as directive lines the hook's
  // parseAllowlist understands (`mcp-allow <tool>`, `navigate-origin <origin>`).
  // The origin is resolved from env HERE (not baked) and pinned in the file so
  // the agent — which cannot read .claude/ — cannot tamper with it.
  const mcpEntry = CRON_MCP_ALLOWLISTS[cronName];
  let navigateOrigin: string | null = null;
  const allowlistLines = [...allow];
  if (mcpEntry) {
    for (const tool of mcpEntry.tools) allowlistLines.push(`mcp-allow ${tool}`);
    if (mcpEntry.navigateOriginEnv) {
      const raw = process.env[mcpEntry.navigateOriginEnv];
      try {
        navigateOrigin = raw ? new URL(raw).origin : null;
      } catch {
        navigateOrigin = null;
      }
      if (!navigateOrigin) {
        // Refuse to relax browser_navigate without a resolvable origin pin — the
        // unguarded form is the exfil vector this whole mechanism exists to close.
        throw new Error(
          `[${cronName}] cannot resolve navigate-origin from env ` +
            `${mcpEntry.navigateOriginEnv} (value: ${raw ?? "<unset>"}) — refusing ` +
            `to relax mcp browser_navigate without an origin pin. Aborting cron.`,
        );
      }
      allowlistLines.push(`navigate-origin ${navigateOrigin}`);
    }
  }
  await writeFile(
    join(claudeDir, "cron-allow.txt"),
    allowlistLines.length ? allowlistLines.join("\n") + "\n" : "",
    "utf-8",
  );
  await writeFile(
    join(claudeDir, "settings.json"),
    JSON.stringify(buildCronEvalSettings(spawnCwd), null, 2) + "\n",
    "utf-8",
  );

  const manifestPath = join(pluginDir, ".claude-plugin", "plugin.json");
  if (!existsSync(manifestPath)) {
    throw new Error(
      `Plugin sentinel check failed: ${manifestPath} does not exist (clone incomplete or plugin tree moved)`,
    );
  }

  // D2 (mitigates probe D-new-1 fail-open): confirm the hook actually denies a
  // canonical exfil payload (and allows this cron's first verb) BEFORE any agent
  // spawns. A throw here aborts the cron → FAILED self-report, never an
  // unprotected run.
  runHookSelfTest({
    spawnCwd,
    cronName,
    allow,
    mcpAllow: mcpEntry?.tools ?? [],
    navigateOrigin,
  });

  return { ephemeralRoot, spawnCwd };
}

export async function teardownEphemeralWorkspace(
  ephemeralRoot: string | null,
  cronName: string,
): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: cronName,
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: cronName, ephemeralRoot },
    });
  }
}

export async function spawnClaudeEval(args: {
  spawnCwd: string;
  installationToken: string;
  flags: string[];
  prompt: string;
  maxTurnDurationMs: number;
  cronName: string;
  buildSpawnEnv: (token: string) => NodeJS.ProcessEnv;
  logger: HandlerArgs["logger"];
  // #5766: Inngest run identity, threaded from the caller (ctx.runId / attempt).
  // When present, this run is recorded as a live DB fact (routine_run_progress):
  // upsert on entry + heartbeat every ~30s while the child runs. Optional so
  // non-Inngest callers / tests need not supply it.
  runId?: string;
  attempt?: number;
}): Promise<SpawnResult> {
  const {
    spawnCwd,
    installationToken,
    flags,
    prompt,
    maxTurnDurationMs,
    cronName,
    buildSpawnEnv,
    logger,
    runId,
    attempt,
  } = args;

  if (!existsSync(spawnCwd)) {
    throw new Error(
      `spawn cwd ${spawnCwd} no longer exists (container restart between setup-workspace and claude-eval?). ` +
        `Re-run will re-execute setup-workspace and create a fresh ephemeral root.`,
    );
  }

  const claudeBin = resolveClaudeBin();
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), maxTurnDurationMs);
  const startedAt = Date.now();
  let abortedByTimeout = false;
  let exited = false;
  let escalationTimer: NodeJS.Timeout | null = null;
  // Rolling bounded tail of redacted stderr lines (last STDERR_CAP_BYTES) so a
  // non-zero exit can be surfaced to Sentry by the caller.
  let stderrTail = "";
  // Rolling bounded tail of redacted stdout lines (last STDOUT_TAIL_CAP_BYTES).
  // Carries the `claude --print` max-turns notice (stdout, not stderr) to the
  // Sentry surface. #4773.
  let stdoutTail = "";

  // #5766: record this run as a live DB fact. upsert on entry (ON CONFLICT
  // refreshes on replay, preserving started_at), then a wall-clock heartbeat tick
  // while the child runs — this is what a stale-heartbeat reader uses to detect a
  // SIGKILL eviction faster than Inngest's step timeout. All fail-soft (never
  // throws). Cleared in finish() below so no tick fires after child exit.
  let heartbeatTimer: NodeJS.Timeout | null = null;
  if (runId) {
    await upsertRoutineRunProgress(cronName, runId, attempt ?? 1);
    heartbeatTimer = setInterval(() => {
      void heartbeatRoutineRunProgress(runId);
    }, HEARTBEAT_INTERVAL_MS);
    // Do not keep the event loop alive solely for the heartbeat.
    heartbeatTimer.unref?.();
  }

  try {
    return await new Promise<SpawnResult>((resolve) => {
      // #5691 — silence non-essential cron egress at source (keep-blocked, NOT
      // allowlisted; ADR-052 2026-06-29 amendment):
      //  • `--strict-mcp-config` (prepended at index 0, BEFORE `--print` and
      //    before any trailing `--` prompt separator) makes the CLI ignore the
      //    four remote HTTP MCP servers bundled in plugins/soleur/plugin.json
      //    (context7/cloudflare/vercel/stripe) that `--plugin-dir` would
      //    otherwise auto-connect at startup. The containment hook denies every
      //    mcp__* tool anyway (only cron-ux-audit gets Playwright), so these
      //    startup dials are pure overhead the egress firewall correctly drops.
      //    cron-ux-audit re-supplies its Playwright server via `--mcp-config`.
      //  • CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 kills Claude Code's own
      //    non-essential outbound traffic (telemetry / error-reporting /
      //    auto-update). Spike A (#5691 PR body) is the at-source proof.
      const child = spawn(claudeBin, ["--strict-mcp-config", ...flags, prompt], {
        detached: true,
        stdio: ["ignore", "pipe", "pipe"],
        cwd: spawnCwd,
        env: {
          ...buildSpawnEnv(installationToken),
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
        },
      });

      if (child.stdout) {
        const rlOut = createInterface({ input: child.stdout });
        rlOut.on("line", (line) => {
          const redacted = redactToken(line, installationToken);
          logger.info({ fn: cronName, stream: "stdout" }, redacted);
          // Keep a bounded tail (drop oldest) for the Sentry surface — mirrors
          // the stderrTail accumulation below. Carries the max-turns notice.
          stdoutTail = (stdoutTail + redacted + "\n").slice(-STDOUT_TAIL_CAP_BYTES);
        });
      }
      if (child.stderr) {
        const rlErr = createInterface({ input: child.stderr });
        rlErr.on("line", (line) => {
          const redacted = redactToken(line, installationToken);
          logger.error({ fn: cronName, stream: "stderr" }, redacted);
          // Keep a bounded tail (drop oldest) for the Sentry surface.
          stderrTail = (stderrTail + redacted + "\n").slice(-STDERR_CAP_BYTES);
        });
      }

      const finish = (r: SpawnResult) => {
        exited = true;
        if (escalationTimer) clearTimeout(escalationTimer);
        // #5766: stop heartbeating once the child has exited — no tick may land
        // after the middleware's terminal delete (would resurrect a phantom row).
        if (heartbeatTimer) clearInterval(heartbeatTimer);
        resolve(r);
      };

      ac.signal.addEventListener(
        "abort",
        () => {
          abortedByTimeout = true;
          if (!child.pid) return;
          const pid = child.pid;
          try {
            process.kill(-pid, "SIGTERM");
          } catch {
            // process group already gone
          }
          escalationTimer = setTimeout(() => {
            if (exited) return;
            try {
              process.kill(-pid, "SIGKILL");
            } catch {
              // already exited between SIGTERM and escalation
            }
          }, KILL_ESCALATION_MS);
        },
        { once: true },
      );

      child.on("exit", (exitCode, signal) => {
        finish({
          ok: exitCode === 0,
          exitCode,
          signal,
          abortedByTimeout,
          durationMs: Date.now() - startedAt,
          stderrTail,
          stdoutTail,
        });
      });
      child.on("error", (err) => {
        const redactedMsg = redactToken(err.message ?? "", installationToken);
        const redacted = new Error(redactedMsg);
        redacted.name = err.name;
        reportSilentFallback(redacted, {
          feature: "cron-claude-eval",
          op: "child_process.spawn",
          message: "claude-code spawn failed",
          extra: { fn: cronName },
        });
        finish({
          ok: false,
          exitCode: -1,
          signal: null,
          abortedByTimeout,
          durationMs: Date.now() - startedAt,
          stderrTail: stderrTail || redactedMsg,
          // No `|| redactedMsg` fallback for stdout: a child_process spawn error
          // (ENOENT, EACCES) means the child never started, so there is no stdout
          // to capture — the error message belongs on stderrTail only. #4773.
          stdoutTail,
        });
      });

      logger.info(
        { fn: cronName, spawnCwd, pid: child.pid },
        "claude-eval spawned",
      );
    });
  } finally {
    clearTimeout(timer);
    // #5766 — guarantee the heartbeat interval is cleared even if the Promise
    // executor threw synchronously (spawn/buildSpawnEnv config error) before
    // finish() ran. clearInterval on an already-cleared handle is a safe no-op.
    if (heartbeatTimer) clearInterval(heartbeatTimer);
  }
}
