// TR9 PR-11/2 (closes #4464) — Migrated from the GHA scheduled-ux-audit
// workflow (deleted in the same PR per TR9 I-13 hygiene). Substrate
// extension: Playwright Chromium + bot-fixture lifecycle + Supabase
// findings-upload. Reference handler: cron-legal-audit.ts (closest
// side-effect class: claude-eval + issue-creator).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (50 min). Manual
//        SIGTERM→SIGKILL escalation via process-group kill (detached:true).
//   I4 — claude binary resolved at spawn time via filesystem checks.
//        Chromium pinned transitively via @playwright/test devDep at
//        docker build time (image-baked, not runtime-installed).
//   I5 — Deterministic step.run return shape: {ok, exitCode, signal,
//        abortedByTimeout, durationMs}. stdout is NOT captured.
//   I6 — Event payloads emitted by cron-*.ts MUST carry actor: "platform".
//        (This handler emits none.)
//   I7 — Chromium zombie process reaping: production docker run SHOULD use
//        --init (tini) to reap zombie chrome zygote children. Without it,
//        zombie <defunct> processes accumulate (one set per monthly fire).
//        Verified in PR-1 I3 gate.
//
// SHAPE DIFF vs cron-legal-audit.ts:
//   - --allowedTools adds Playwright MCP tools for authenticated screenshots.
//   - Bot-fixture lifecycle: seed → signin → writeStorageState → eval → reset.
//   - Per-fire .mcp.json overlay with --user-data-dir (NOT --isolated).
//   - Upload findings to Supabase ux-audit-artifacts bucket.
//   - Monthly cron 0 9 1 * * (vs quarterly).

import { existsSync } from "node:fs";
import { chmod, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  redactToken,
  mintInstallationToken,
  deferIfTier2Cron,
  postSentryHeartbeat,
  ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS,
  REPO_NAME,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
  spawnClaudeEval,
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { inngest } from "@/server/inngest/client";
import { getPluginPath } from "@/server/plugin-path";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import { AUDIT_MODEL } from "@/server/inngest/model-tiers";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-ux-audit";

const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;


export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// #4993 — headless /soleur:* skill resolution (fleet fix mirroring #4987 /
// PR #4989): `--plugin-dir plugins/soleur` registers the plugin (clone's tracked tree — #5091) under
// `--print` (a bare plugins/ dir is NOT auto-discovered in headless mode), and
// `Skill` (+`Task` for subagent fan-out) in --allowedTools gates skill invocation.
// Exported so a parity test can assert the `mcp__playwright__*` tokens in
// `--allowedTools` (what the CLI offers) stay in lockstep with
// CRON_MCP_ALLOWLISTS["cron-ux-audit"].tools (what the containment hook permits).
// A tool offered but not hook-permitted silently fails mid-run; the reverse is a
// dead grant. #5199.
export const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  AUDIT_MODEL,
  "--max-turns",
  "60",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,Task,Skill,mcp__playwright__browser_navigate,mcp__playwright__browser_take_screenshot,mcp__playwright__browser_resize,mcp__playwright__browser_close,mcp__playwright__browser_wait_for",
  "--plugin-dir",
  "plugins/soleur",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-ux-audit.yml lines 170-191 (the
// `prompt: |` block body, 12-space YAML indentation stripped).
const UX_AUDIT_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly
to main. Do NOT create commits. The skill only creates GitHub
issues when UX_AUDIT_DRY_RUN=false; in dry-run mode it writes
findings to stdout and to
\${GITHUB_WORKSPACE}/tmp/ux-audit/findings.json only.

MILESTONE RULE: Every gh issue create command MUST include
--milestone "Post-MVP / Later".

Run /soleur:ux-audit against the route list at
plugins/soleur/skills/ux-audit/references/route-list.yaml. The bot
fixture has already been seeded and storageState.json written to
\${UX_AUDIT_STORAGE_STATE}. Follow SKILL.md exactly.

Cap enforcement is mandatory:
  CAP_OPEN_ISSUES = 20   (refuse to file when reached)
  CAP_PER_RUN     = 5    (severity-ranked top-N filed per run)

Injection safety: all finding fields (title, body, hash) must be
written to files or env vars before \`gh issue create\` — never
interpolate agent output into bash \`run:\` commands directly.
`;


function buildSpawnEnv(
  installationToken: string,
  extra: Record<string, string> = {},
): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
    ...extra,
  };
}


async function uploadFindings(args: {
  workspaceDir: string;
  installationToken: string;
  logger: HandlerArgs["logger"];
}): Promise<void> {
  const { workspaceDir, installationToken, logger } = args;
  const findingsPath = join(workspaceDir, "findings.json");

  if (!existsSync(findingsPath)) {
    logger.info({ fn: "cron-ux-audit" }, "No findings.json found — skipping upload");
    return;
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceKey) {
    logger.warn({ fn: "cron-ux-audit" }, "Supabase env unset — skipping upload");
    return;
  }

  const runDate = new Date().toISOString().split("T")[0];
  const findings = await readFile(findingsPath, "utf-8");

  // Upload findings.json
  const uploadPath = `${runDate}/findings.json`;
  const uploadRes = await fetch(
    `${supabaseUrl}/storage/v1/object/ux-audit-artifacts/${uploadPath}`,
    {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: findings,
    },
  );
  if (!uploadRes.ok) {
    logger.warn(
      { fn: "cron-ux-audit", status: uploadRes.status },
      "findings.json upload failed",
    );
  }

  // Upload any screenshots (*.png in workspace)
  const files = await readdir(workspaceDir);
  const screenshots = files.filter((f) => f.endsWith(".png"));
  for (const screenshot of screenshots) {
    const screenshotPath = join(workspaceDir, screenshot);
    const screenshotData = await readFile(screenshotPath);
    const screenshotUploadPath = `${runDate}/${screenshot}`;
    await fetch(
      `${supabaseUrl}/storage/v1/object/ux-audit-artifacts/${screenshotUploadPath}`,
      {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "image/png",
        },
        body: screenshotData,
      },
    ).catch((err) => {
      logger.warn(
        { fn: "cron-ux-audit", screenshot, err: (err as Error).message },
        "screenshot upload failed",
      );
    });
  }

  logger.info(
    { fn: "cron-ux-audit", findingsUploaded: true, screenshotCount: screenshots.length },
    "findings uploaded to ux-audit-artifacts bucket",
  );
}

// =============================================================================
// Handler
// =============================================================================

export async function cronUxAuditHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // D6 (#5018) / #5046 PR-2: still Tier-2-deferred — the firewall landed but
  // this cron needs per-construct Bash-allowlist refinement or non-GitHub
  // egress coverage before restore (see TIER2_DEFERRED_CRONS). Posts an
  // honest on-schedule check-in and skips the claude spawn (no fail-closed
  // FAILED-issue/RED-monitor storm); the scheduled output issue visibly stops.
  if (
    await deferIfTier2Cron({
      cronName: "cron-ux-audit",
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      step,
      logger,
    })
  ) {
    return { ok: true };
  }

  // --- Step 1: mint installation token ---
  // #5199 — narrowed to the issue-creator least-privilege scope (contents:read
  // for the clone + issues:write for `gh issue create`/`gh label`) bounded to
  // the soleur repo. ux-audit never pushes or opens PRs, so push/PR capability
  // is denied at the TOKEN layer too — defense-in-depth beneath the containment
  // hook (mirrors cron-legal-audit / cron-agent-native-audit).
  const installationToken = await step.run(
    "mint-installation-token",
    async () =>
      mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        permissions: ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS,
        repositories: [REPO_NAME],
      }),
  );

  // --- Step 2: bot-fixture-seed ---
  await step.run("bot-fixture-seed", async () => {
    const botFixturePath = join(getPluginPath(), "skills/ux-audit/scripts/bot-fixture.ts");
    const mod = await import(botFixturePath) as { seed: () => Promise<void> };
    await mod.seed();
  });

  // --- Step 3: bot-signin + writeStorageState ---
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  let workspaceDir: string | null = null;

  try {
    // --- Step 4: setup ephemeral workspace ---
    const workspace = await step.run("setup-workspace", async () => {
      const base = await setupEphemeralWorkspace({ installationToken, cronName: "cron-ux-audit" });
      const wDir = join(base.ephemeralRoot, "workspace");

      // Per-fire .mcp.json overlay for Playwright MCP
      const playwrightProfileDir = join(wDir, "playwright-mcp-profile");
      await mkdir(playwrightProfileDir, { recursive: true });
      const mcpConfig = {
        mcpServers: {
          playwright: {
            command: "npx",
            // #5676 — silence the intended-by-design registry-metadata dial at
            // source. #5199 deliberately keeps registry.npmjs.org OFF the cron
            // egress allowlist, so the firewall (correctly) DROPS npx's spawn-time
            // registry check — generating steady, by-design `egress-blocked`
            // noise to Cloudflare's npmjs.org anycast pool (104.16.x.34). Passing
            // npm_config_prefer_offline makes npx resolve from the image-baked
            // _cacache and skip the registry dial when cache-warm, so the drop
            // stops being generated. prefer-offline (NOT offline): a cold cache
            // degrades to today's drop+baked-dep fallback rather than hard-failing
            // the cron. Do NOT allowlist registry.npmjs.org — that reverses #5199.
            // The MCP stdio launcher MERGES this `env` over a base that retains
            // PATH/HOME (so npx still spawns); the #5199 live dry-run on each apply
            // is the spawn-success check. Worst case if it were NOT inherited: the
            // drop persists and the baked-dep fallback holds — i.e. today's behavior,
            // never a hard cron break.
            env: { npm_config_prefer_offline: "true" },
            args: [
              // #5199 — pinned (was @latest). registry.npmjs.org is NOT in the
              // cron egress allowlist, so this resolves to the image-baked
              // dependency (package.json deps + npm ci --omit=dev) rather than a
              // runtime supply-chain fetch. Its playwright-core (1.61.0-alpha) is
              // aligned with the baked Chromium (the Dockerfile installs that
              // exact revision via `npx playwright@1.61.0-alpha-… install`).
              // 0.0.75 (not the newer 0.0.76) clears the bun minimum-release-age
              // supply-chain policy (3-day floor) so both lockfiles resolve it.
              "@playwright/mcp@0.0.75",
              `--user-data-dir=${playwrightProfileDir}`,
            ],
          },
        },
      };
      await writeFile(
        join(base.spawnCwd, ".mcp.json"),
        JSON.stringify(mcpConfig, null, 2) + "\n",
        "utf-8",
      );

      // Workspace dir for storageState + findings output
      await mkdir(wDir, { recursive: true, mode: 0o700 });

      return { ...base, workspaceDir: wDir };
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
    workspaceDir = workspace.workspaceDir;

    // --- Step 5: bot-signin → write storageState to workspace ---
    await step.run("bot-signin", async () => {
      const botSigninPath = join(getPluginPath(), "skills/ux-audit/scripts/bot-signin.ts");
      const mod = await import(botSigninPath) as {
        signIn: () => Promise<{ access_token: string; refresh_token: string; expires_in: number; expires_at: number; token_type: string; user: unknown }>;
        writeStorageState: (session: unknown, outPath: string, supabaseUrl: string, siteUrl: string) => void;
      };
      const session = await mod.signIn();
      const outPath = join(workspace.workspaceDir, "storage-state.json");
      mod.writeStorageState(
        session,
        outPath,
        process.env.SUPABASE_URL!,
        process.env.NEXT_PUBLIC_APP_URL!,
      );
      await chmod(outPath, 0o600);
    });

    // --- Step 6: claude-eval ---
    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        const storageStatePath = join(workspaceDir!, "storage-state.json");
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
          flags: CLAUDE_CODE_FLAGS,
          prompt: UX_AUDIT_PROMPT,
          maxTurnDurationMs: MAX_TURN_DURATION_MS,
          cronName: "cron-ux-audit",
          buildSpawnEnv: (token) => buildSpawnEnv(token, {
            // #5199 — restored to LIVE issue-filing. Defaults to "false" (files
            // the weekly scheduled-ux-audit issues, the whole point of the
            // restore); an operator can still set UX_AUDIT_DRY_RUN=true in the
            // env to validate a trigger without filing.
            UX_AUDIT_DRY_RUN: process.env.UX_AUDIT_DRY_RUN ?? "false",
            UX_AUDIT_STORAGE_STATE: storageStatePath,
          }),
          logger,
        });
      },
    );

    if (spawnResult.abortedByTimeout) {
      reportSilentFallback(
        new Error(
          `claude-eval aborted by timeout (${MAX_TURN_DURATION_MS}ms budget exceeded)`,
        ),
        {
          feature: "cron-ux-audit",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-ux-audit",
            durationMs: spawnResult.durationMs,
            maxMs: MAX_TURN_DURATION_MS,
          },
        },
      );
    } else if (!spawnResult.ok) {
      // Best-effort cron: a non-zero/no-artifact claude exit is NORMAL — the
      // findings upload is conditional ("No findings.json found — skipping
      // upload"), so a clean run with no findings is expected. The monitor's
      // liveness contract is "the pipeline ran end-to-end without an
      // INFRASTRUCTURE fault" (token mint, clone, parse), not "claude produced
      // an artifact today" — so do NOT page; the infra-fault early-returns above
      // keep their strict status=error. Pattern + rationale: cron-bug-fixer.ts
      // (PR #4727, incident 5127648 / #4730). warnSilentFallback (not a bare
      // logger.warn) is load-bearing — a pino logger.warn only adds a Sentry
      // breadcrumb (flushed solely on a later captureException a clean ok:true
      // run never produces) and lands in a Docker json-file stream Vector does
      // not tail, i.e. invisible without SSH
      // (cq-silent-fallback-must-mirror-to-sentry, hr-observability-layer-citation).
      warnSilentFallback(
        new Error("claude-eval exited non-zero — best-effort run, no artifact this cycle"),
        {
          feature: "cron-ux-audit",
          op: "claude-eval-nonzero-noop",
          message:
            "claude-eval exited non-zero (best-effort); cron monitor stays green (liveness, not success)",
          extra: {
            fn: "cron-ux-audit",
            exitCode: spawnResult.exitCode,
            durationMs: spawnResult.durationMs,
          },
        },
      );
    }

    // --- Step 7: upload findings ---
    await step.run("upload-findings", async () => {
      await uploadFindings({
        workspaceDir: workspaceDir!,
        installationToken,
        logger,
      });
    });

    // --- Step 8: bot-fixture-reset ---
    await step.run("bot-fixture-reset", async () => {
      const botFixturePath = join(getPluginPath(), "skills/ux-audit/scripts/bot-fixture.ts");
      const mod = await import(botFixturePath) as { reset: () => Promise<void> };
      await mod.reset();
    });

    // --- Step 9: sentry heartbeat (final POST) ---
    // The pipeline reached the end without an INFRA fault → healthy liveness
    // check-in regardless of claude's exit code (the non-zero exit is a
    // best-effort outcome, surfaced above, never a liveness failure).
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-ux-audit", logger });
    });

    return { ok: true };
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-ux-audit",
      op: "handler",
      message: "cron-ux-audit handler failed",
      extra: { fn: "cron-ux-audit" },
    });
    await step.run("sentry-heartbeat-error", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-ux-audit", logger });
    });
    return { ok: false };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-ux-audit").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-ux-audit",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-ux-audit", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================

export const cronUxAudit = inngest.createFunction(
  {
    id: "cron-ux-audit",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 1 * *" },
    { event: "cron/ux-audit.manual-trigger" },
  ],
  cronUxAuditHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
