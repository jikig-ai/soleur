// TR9 PR-11 (closes #4468) — Migrated from the GHA
// scheduled-community-monitor workflow (deleted in the same PR per TR9
// I-13 hygiene). Sixth handler ported via the claude-code-spawn pattern;
// structural template is PR-7's cron-roadmap-review.ts.
//
// BUCKET II (kb-writer + pr-creator) — first bucket-ii migration in the
// claude-code-spawn cohort. CLO bucket-ii means more careful authorization
// context: the spawned agent writes KB files and creates issues; since
// #5111 the PLATFORM commits and opens the PR handler-side (the agent no
// longer runs git/gh persistence verbs). The buildSpawnEnv allowlist is
// wider than bucket-i (adds 7 community-platform vars for Discord,
// Bluesky, LinkedIn) but still uses the explicit-allowlist shape (NOT
// denylist / spread).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (50 min). Manual
//        SIGTERM→SIGKILL escalation via process-group kill (detached:true).
//   I4 — claude binary resolved at spawn time via filesystem checks; the
//        CLAUDE_BIN env var is the override hatch for fresh-host bootstraps.
//   I5 — Deterministic step.run return shape: {ok, exitCode, signal,
//        abortedByTimeout, durationMs}. stdout is NOT captured.
//   I6 — Event payloads emitted by cron-*.ts MUST carry actor: "platform".
//        (This handler emits none.)
//
// NAME NOTE: Sentry monitor slug "scheduled-community-monitor" pre-exists
// from the GHA era (apps/web-platform/infra/sentry/cron-monitors.tf). This
// PR mutates the resource in place (margin 60→30, runtime 10→55).
//
// SHAPE DIFF vs PR-7 cron-roadmap-review.ts:
//   - buildSpawnEnv is WIDER: adds DISCORD_WEBHOOK_URL, DISCORD_BOT_TOKEN,
//     DISCORD_GUILD_ID, BSKY_HANDLE, BSKY_APP_PASSWORD, LINKEDIN_ACCESS_TOKEN,
//     LINKEDIN_PERSON_URN (the community-router.sh platform scripts need
//     these to flip platforms from "disabled" → "enabled"), plus
//     LINKEDIN_ORG_ACCESS_TOKEN + LINKEDIN_ORG_ID (the org READ creds the
//     linkedin fetch-metrics/fetch-activity commands require — #4049).
//   - --max-turns 80 (was 50, orig 40 — see turn-budget rationale on
//     MAX_TURN_DURATION_MS); --allowedTools is NARROWER than the cohort
//     default (no WebSearch, WebFetch). (The original GHA workflow
//     scheduled-community-monitor.yml was deleted in #4468; this comment no
//     longer mirrors a live file.)
//   - Cron 0 8 * * * (daily 08:00 UTC, not weekly Monday 09:00).
//   - ISSUE CLOSURE SAFETY and ROADMAP.MD CONFLICT GUARD are N/A (prompt
//     has zero `gh issue close` calls and zero roadmap.md references).
//
// PLUGIN-LOADING — Verbatim PR-5 ephemeral-workspace pattern:
//   - repo/                          (in-handler `git clone --depth=1`)
//   - repo/plugins/soleur            (the clone's own tracked tree — #5091)
//   - repo/.claude/settings.json     (DEFAULT_SETTINGS overlay)
// Plugin resolution under headless `--print` requires the explicit
// `--plugin-dir plugins/soleur` flag — the plugins/soleur dir is NOT
// auto-discovered from spawn cwd in headless mode (the interactive
// marketplace/enabledPlugins trust flow does not run under --print). This
// producer's prompt invokes no /soleur:* skill, so it needs no flag change; the
// comment is corrected so the disproven spawn-cwd auto-discovery theory cannot
// mislead future edits. See #4993 / #4987.
//
// GH TOKEN — installation token minted via createProbeOctokit() →
// installation discovery → generateInstallationToken(installation.id), narrowed
// to DEFAULT_CRON_TOKEN_PERMISSIONS scoped to [REPO_NAME] (#5199).
// Injected as GH_TOKEN so the spawned claude can run the allowlisted
// `gh issue create`/`gh issue list`/`gh issue comment` + `gh label` verbs
// (persistence runs handler-side via safeCommitAndPr — #5111; the prompt forbids
// git/gh-pr verbs and the containment hook denies `gh api`).

import {
  redactToken,
  mintInstallationToken,
  deferIfTier2Cron,
  postSentryHeartbeat,
  resolveOutputAwareOk,
  digestIssueExistsForDate,
  digestCommittedOnDefaultBranch,
  injectRunDate,
  SCHEDULED_DIGEST_TITLE_PREFIX,
  ensureScheduledAuditIssue,
  finalizeOutputAwareHeartbeat,
  DeployInProgressError,
  DEFAULT_CRON_TOKEN_PERMISSIONS,
  REPO_NAME,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
  spawnClaudeEval,
  makeThrewSpawnResult,
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { safeCommitAndPr } from "./_cron-safe-commit";
import {
  emitCommunityDigestFile,
  emitCronDedupSkip,
  emitCronDigestLiveness,
  emitCronPersistSkipped,
  type CronDigestLivenessMarker,
} from "@/server/cron-liveness-marker";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-community-monitor";

const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;


// TURN BUDGET — `--max-turns 80` (CLAUDE_CODE_FLAGS below), MAX_TURN_DURATION_MS
// 50 min wall-clock. Raised from 50→80 turns on 2026-06-03 after Sentry
// WEB-PLATFORM-1Z: the spawn exited 1 with stdoutTail "Error: Reached max
// turns (50)" ~6 min into the run (turn-count exhaustion, NOT the wall-clock
// ceiling), so it never reached its final issue-create step and this
// always-create producer filed no `scheduled-community-monitor` issue —
// correctly turning the output-aware heartbeat RED. 80 matches the
// proven-healthy `cron-daily-triage` turn budget running through the same
// DEFAULT_CLAUDE_SETTINGS (daily-triage pairs 80 turns with a 60-min ceiling;
// we keep 50 min — see the in-band ratio below). The heavier 7-platform
// digest + KB-write + issue task (PR creation moved handler-side in #5111)
// no longer fit in 50 with error/retry headroom.
// The timeout-to-turns ratio
// is 50 min ÷ 80 = 0.625 min/turn — within the 0.55–1.2 peer band per the
// 2026-03-20-claude-code-action-max-turns-budget learning, so the 50-min
// wall-clock stays adequate (no MAX_TURN_DURATION_MS change needed).
export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";


// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8.
// Originally mirrored .github/workflows/scheduled-community-monitor.yml
// `claude_args` (--max-turns 50). Raised to 80 on 2026-06-03 — see the
// turn-budget rationale on MAX_TURN_DURATION_MS below.
//   --model claude-sonnet-5
//   --max-turns 80
//   --allowedTools Bash,Read,Write,Edit,Glob,Grep
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  EXECUTION_MODEL,
  "--max-turns",
  "80",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-community-monitor.yml lines 92-168 (the
// `prompt: |` block body, 12-space YAML indentation stripped).
// Verbatim-extraction discipline: anchor strings asserted by the test
// suite (cron-community-monitor.test.ts) to catch silent paraphrasing
// across plan→work cycles.
//
// LinkedIn collection note (#4049): the "LinkedIn (if enabled): … fetch-metrics"
// step below is LIVE — it runs on every fire. TIER2_DEFERRED_CRONS is empty
// (Tier-2 boundary fully restored, #5199), so deferIfTier2Cron is a defensive
// no-op that does NOT gate this cron. Verified live 2026-06-15 (manual run →
// digest #5357 carried real LinkedIn metrics: 3 followers, 2,137 impressions).
// If a future Tier-2 deferral re-adds "community-monitor" to the set, collection
// pauses behind the deferral heartbeat until restore.
const COMMUNITY_MONITOR_PROMPT = `You are a community monitoring agent. Your job is to generate a daily
community digest and create a GitHub Issue summarizing the findings.

IMPORTANT: This is an automated CI workflow. The AGENTS.md rule
Do NOT push directly to main.

MILESTONE RULE: Every gh issue create command must include --milestone "Post-MVP / Later".

## Instructions

1. **Detect platforms** using the community router:
   Run: bash plugins/soleur/skills/community/scripts/community-router.sh platforms
   This shows which platforms are enabled/disabled. If only GitHub and HN
   are enabled (no Discord or X), create a GitHub Issue titled
   "[Scheduled] Community Monitor - FAILED" with label
   "scheduled-community-monitor" explaining the misconfiguration, then stop.

2. **Collect data** from enabled platforms. IMPORTANT: batch commands
   into as few Bash calls as possible to conserve turns. Use \`;\` (not
   \`&&\`) to chain commands so failures don't halt the batch.
   IMPORTANT: the containment hook allowlists ONLY the literal command prefix
   \`bash plugins/soleur/skills/community/scripts/community-router.sh\`. You MUST
   write that full literal path in every invocation — do NOT assign it to a shell
   variable (a \`NAME=value\` prefix is denied) and do NOT abbreviate it; a
   variable-expanded form will be denied as non-allowlisted.
   Batch 1 (Discord + X + Bluesky — single Bash call):
   - Discord (if enabled): \`bash plugins/soleur/skills/community/scripts/community-router.sh discord guild-info; bash plugins/soleur/skills/community/scripts/community-router.sh discord members; bash plugins/soleur/skills/community/scripts/community-router.sh discord channels\`
     Then one more call to fetch messages for each channel ID from the output above.
   - X/Twitter (if enabled): append \`bash plugins/soleur/skills/community/scripts/community-router.sh x fetch-metrics\` to the same call.
     Do NOT call fetch-mentions or fetch-timeline (403 on Free tier).
   - Bluesky (if enabled): append \`bash plugins/soleur/skills/community/scripts/community-router.sh bsky get-metrics\` to the same call.
   - LinkedIn (if enabled): append \`bash plugins/soleur/skills/community/scripts/community-router.sh linkedin fetch-metrics\` to the same call (aggregate Company Page metrics: follower total + share statistics). Optionally also \`bash plugins/soleur/skills/community/scripts/community-router.sh linkedin fetch-activity\` for recent org post metadata. If either fails, log the error and continue.
   Batch 2 (GitHub + HN — single Bash call):
   - \`bash plugins/soleur/skills/community/scripts/community-router.sh github activity 1; bash plugins/soleur/skills/community/scripts/community-router.sh github contributors 1; bash plugins/soleur/skills/community/scripts/community-router.sh github discussions 1; bash plugins/soleur/skills/community/scripts/community-router.sh github repo-stats 1; bash plugins/soleur/skills/community/scripts/community-router.sh github fetch-interactions 1; bash plugins/soleur/skills/community/scripts/community-router.sh hn mentions --query soleur --limit 20; bash plugins/soleur/skills/community/scripts/community-router.sh hn trending --limit 30\`
   If any command in a batch fails, log the error and continue collecting the
   remaining platforms — but "continue" NEVER means the failure disappears from
   the digest. Every failed command MUST surface as an explicit
   "collection failed: <reason>" line in that platform's section (see step 4).
   Never omit a section, and never substitute a number from a previous digest,
   because a command failed.

3. **Read brand guide** at knowledge-base/marketing/brand-guide.md (section ## Voice)
   before writing any content. Match the brand voice in the digest.

4. **Generate digest** and write to knowledge-base/support/community/YYYY-MM-DD-digest.md
   (use today's date). Follow the digest file contract from the community-manager
   agent: frontmatter with period_start/period_end/generated_at — derive the
   period from the collectors' own \`period_days\`/\`since\` fields, never from the
   gap since the last committed digest, and never widen it to explain missing
   data. Then sections
   ## Period, ## Activity Summary, ## Top Contributors, and optional sections
   ## Trending Topics, ## GitHub Activity, ## X/Twitter Metrics,
   ## Bluesky Metrics, ## LinkedIn Activity, ## Hacker News Activity.
   The ## GitHub Activity section must include a **Repository Stats** sub-section
   with a table showing Stars, Forks, and Watchers counts, plus a list of
   new stargazers in the period (username and starred date) from the repo-stats data.
   Every one of those numbers must come from THIS run's repo-stats output. To
   distinguish "GitHub quiet" from "GitHub broken": if a github command FAILED,
   write an explicit "collection failed: <reason>" line under ## GitHub Activity
   instead of the affected numbers. Do NOT carry a Stars/Forks/Watchers value
   forward from a previous digest, do NOT label a stale number "(stale)", and do
   NOT estimate one — an absent number is correct, a plausible wrong number is not.
   If fetch-interactions returned any interactions, include a **Community Interactions**
   sub-section with a markdown table: | User | Issue/PR | Comment |. Each row shows
   the commenter, a link to the issue (e.g., #123), and a snippet of their comment.
   Omit this sub-section entirely if there are no external interactions.
   The ## LinkedIn Activity section (if LinkedIn was enabled) must report the
   aggregate Company Page metrics from fetch-metrics: total followers plus the
   aggregate post engagement (impressions, likes, comments, shares). Aggregate-
   only — never list individual followers, commenters, or likers. To distinguish
   "LinkedIn quiet" from "LinkedIn broken": if the LinkedIn fetch FAILED, write an
   explicit "collection failed: <reason>" line under ## LinkedIn Activity rather
   than silently omitting the section.
   Summarize and aggregate -- do not store raw message transcripts. Brief
   contextual quotes (under 100 chars) with attribution are acceptable.
   If the file already exists for today, overwrite it.

5. **Create GitHub Issue** titled "[Scheduled] Community Monitor - {{RUN_DATE}}"
   with label "scheduled-community-monitor". Include a condensed summary:
   platform status, key metrics, notable items, and a link to the digest file.

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under knowledge-base/support/community/ are persisted — keep all edits inside that path.
Creating the monitor issue above is REQUIRED: the platform only persists your changes after it verifies the issue exists.

CLONE DEPTH RULE: This workspace was cloned with --depth=1. Do NOT use \`git log\` for staleness analysis (every file appears "just touched"). Use GitHub Issue \`updatedAt\` timestamps via \`gh issue list --json updatedAt,number\` instead. The containment hook only allows the \`gh issue\` / \`gh label\` verbs listed above plus the community-router.sh script — do NOT reach for any other \`gh\` sub-command or the raw API.
`;

// Persistence allowlist (#5111): verbatim from the prompt's former scoped
// staging list (the dated digest directory).
// The dated digest lives directly under this dir as `<YYYY-MM-DD>-digest.md`.
// Single source of truth for the persistence allowlist, the workspace stat
// (marker 3) and the committed-artifact liveness assertion — a drifted copy in
// any one of the three would silently un-assert the artifact.
// EXPORTED so the three test suites that assert against the dated digest path
// derive it from this value instead of hardcoding a mirror. The comment below
// calls this the single source of truth; before the export it was not one.
export const COMMUNITY_DIGEST_DIR = "knowledge-base/support/community/";
const COMMUNITY_MONITOR_ALLOWED_PATHS = [COMMUNITY_DIGEST_DIR] as const;

// --- Collector-status sidecar (#6695) ---------------------------------------
//
// Every other failure channel the collectors have terminates in the spawned
// agent's context window: the scripts run as Bash tool calls INSIDE claude, so
// their stderr is captured by the tool, never by the claude process's own
// stderr, and never reaches spawnResult.stderrTail. resolveOutputAwareOk cannot
// close the gap either — it is a presence check on whether a labelled issue was
// updated in the run window, so a digest that fabricates its numbers and one
// that honestly reports "collection failed:" both resolve GREEN through it.
//
// The sidecar is the one deterministic path: the collector appends a JSONL
// record per dispatch and the handler reads it directly, with no LLM in the
// middle. It lives under spawnCwd but outside COMMUNITY_MONITOR_ALLOWED_PATHS,
// so safeCommitAndPr can never commit it, and teardown discards it.
const COLLECTOR_STATUS_DIRNAME = ".soleur-collector-status";
const COLLECTOR_STATUS_FILENAME = "collector-status.jsonl";

type CollectorStatusRecord = {
  collector?: string;
  command?: string;
  exit?: number;
  cause?: string;
  warn?: string;
};

type CollectorStatusReport = {
  present: boolean;
  records: CollectorStatusRecord[];
  failed: CollectorStatusRecord[];
};

export type CollectorStatusVerdict = {
  /** Records the collector reported as non-zero. Pages. */
  failed: CollectorStatusRecord[];
  /** Records carrying a latent truncation warning. Reported, does NOT page. */
  warned: CollectorStatusRecord[];
  /** No sidecar at all — the collector never ran or could not write. */
  missing: boolean;
};

export function classifyCollectorStatus(
  report: CollectorStatusReport,
): CollectorStatusVerdict {
  return {
    failed: report.failed,
    warned: report.records.filter((r) => Boolean(r.warn)),
    missing: !report.present,
  };
}

export async function readCollectorStatus(
  cwd: string,
): Promise<CollectorStatusReport> {
  // Lazy imports: a top-level node:fs binding would land in the static graph of
  // every sibling test that mocks node builtins with partial factories.
  const { readFile } = await import("node:fs/promises");
  const { join } = await import("node:path");
  const file = join(cwd, COLLECTOR_STATUS_DIRNAME, COLLECTOR_STATUS_FILENAME);

  let raw: string;
  try {
    raw = await readFile(file, "utf8");
  } catch {
    return { present: false, records: [], failed: [] };
  }

  const records: CollectorStatusRecord[] = [];
  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      records.push(JSON.parse(trimmed) as CollectorStatusRecord);
    } catch {
      // A malformed line is itself a collector defect, not a reason to drop the
      // whole report — count it as a failure so it cannot pass silently.
      records.push({ command: "unparseable", exit: 1, cause: "malformed-record" });
    }
  }
  return {
    present: true,
    records,
    failed: records.filter((r) => typeof r.exit === "number" && r.exit !== 0),
  };
}


// Spawn-env allowlist (NOT a denylist). PR-5 base shape + PR-11 community-
// monitor additions. The keys below are the COMPLETE set the spawned claude
// is allowed to see; anything not listed (notably RESEND_API_KEY, SENTRY_*,
// DOPPLER_*, GITHUB_APP_PRIVATE_KEY, SUPABASE_SERVICE_ROLE_KEY,
// INNGEST_SIGNING_KEY, INNGEST_EVENT_KEY, STRIPE_SECRET_KEY) is excluded.
//
// PR-11 additions (bucket-ii authorization): DISCORD_WEBHOOK_URL,
// DISCORD_BOT_TOKEN, DISCORD_GUILD_ID, BSKY_HANDLE, BSKY_APP_PASSWORD,
// LINKEDIN_ACCESS_TOKEN, LINKEDIN_PERSON_URN, X_API_KEY, X_API_SECRET,
// X_ACCESS_TOKEN, X_ACCESS_TOKEN_SECRET — the community-router.sh platform
// scripts need these to flip platforms from "disabled" → "enabled".
// #4049 additions (community READ surface): LINKEDIN_ORG_ACCESS_TOKEN and
// LINKEDIN_ORG_ID — the org read creds the linkedin fetch-metrics/fetch-activity
// commands require for aggregate Company Page insights. These are a distinct
// axis from the LINKEDIN_ACCESS_TOKEN/LINKEDIN_PERSON_URN posting creds that
// gate the router's platform "enabled" status.
// X_ALLOW_POST is deliberately EXCLUDED: it is the posting defense-in-depth
// guard (x-community.sh:611); the monitor is read-only and only the publisher
// (cron-content-publisher.ts) arms posting.
// Defensive: ONLY the platform secrets the community-router.sh needs, NOT a
// wholesale process.env passthrough.
function buildSpawnEnv(installationToken: string): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
    DISCORD_WEBHOOK_URL: process.env.DISCORD_WEBHOOK_URL,
    DISCORD_BOT_TOKEN: process.env.DISCORD_BOT_TOKEN,
    DISCORD_GUILD_ID: process.env.DISCORD_GUILD_ID,
    BSKY_HANDLE: process.env.BSKY_HANDLE,
    BSKY_APP_PASSWORD: process.env.BSKY_APP_PASSWORD,
    LINKEDIN_ACCESS_TOKEN: process.env.LINKEDIN_ACCESS_TOKEN,
    LINKEDIN_PERSON_URN: process.env.LINKEDIN_PERSON_URN,
    LINKEDIN_ORG_ACCESS_TOKEN: process.env.LINKEDIN_ORG_ACCESS_TOKEN,
    LINKEDIN_ORG_ID: process.env.LINKEDIN_ORG_ID,
    X_API_KEY: process.env.X_API_KEY,
    X_API_SECRET: process.env.X_API_SECRET,
    X_ACCESS_TOKEN: process.env.X_ACCESS_TOKEN,
    X_ACCESS_TOKEN_SECRET: process.env.X_ACCESS_TOKEN_SECRET,
  };
}

// =============================================================================
// Handler
// =============================================================================

export async function cronCommunityMonitorHandler({
  step,
  logger,
  attempt,
  maxAttempts,
  runId,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // D6 (#5018) / #5046 PR-2 — HISTORICAL. This cron was Tier-2-deferred from
  // a48c57e8d (2026-06-08) to ff42a3ef6 (2026-06-12) and is NOT deferred today:
  // TIER2_DEFERRED_CRONS is EMPTY at HEAD (_cron-shared.ts, "#5199 … the FINAL
  // restore"), so this call is a defensive no-op that returns false. The old
  // "still Tier-2-deferred" wording was stale and actively misled the #6714
  // investigation into attributing a 41-day digest gap to a 4-day defer window.
  // If the set is ever repopulated, this branch posts an honest on-schedule
  // check-in and skips the claude spawn (no fail-closed FAILED-issue/RED-monitor
  // storm) — a GREEN-with-no-artifact path, which is why it now emits
  // SOLEUR_CRON_TIER2_DEFERRED from deferIfTier2Cron.
  if (
    await deferIfTier2Cron({
      cronName: "cron-community-monitor",
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      step,
      logger,
    })
  ) {
    return { ok: true };
  }

  // Run-window start — the lower bound for the post-run output check. Captured
  // before the mint step (memoized across Inngest replays) so a replay reuses
  // the original window rather than re-stamping a later "now".
  const runStartedAt = await step.run(
    "run-started-at",
    async () => new Date().toISOString(),
  );

  // #5751 — producer-side date-dedup (Phase 0 verdict: H-A multiple serialized
  // invocations, compounded by H-C the stale-search-index in-prompt dedup
  // fallback, removed in #6143). On affected days two invocations (the 08:00 cron
  // + an operator manual-trigger, or a doubled delivery) each filed a full
  // `[Scheduled] Community Monitor - <date>` digest because that former in-prompt
  // rule read the lagging SEARCH index.
  // concurrency:{scope:"fn",limit:1} (registration below) serializes the two, so
  // the second's FRESH LIST read sees the first's issue. If a real digest already
  // exists for today, skip the eval and post a healthy OK heartbeat — do NOT fall
  // through to verify-output, whose run-window (updated_at >= THIS runStartedAt)
  // would exclude the earlier issue and false-RED the skip. Date anchor is
  // runStartedAt.slice(0,10) (replay-stable across the retries:1 memoization).
  const digestAlreadyExists = await step.run("dedup-digest-check", async () =>
    digestIssueExistsForDate({
      label: SENTRY_MONITOR_SLUG,
      titlePrefix: SCHEDULED_DIGEST_TITLE_PREFIX,
      date: runStartedAt.slice(0, 10),
      cronName: "cron-community-monitor",
    }),
  );
  // #6714 Phase 3.4 — the dedup early-return used to post GREEN and return on
  // issue-presence ALONE, which is a GREEN-with-no-artifact path by
  // construction. Observed shape: run 1 files a genuine digest issue but fails
  // to commit; run 2 dedups on that issue and posts GREEN with nothing landed —
  // the exact 2026-07-14 → 07-19 state, and it SURVIVES the captured-return and
  // livenessOk fixes below unless closed here. So the short-circuit now requires
  // BOTH the issue AND the dated digest committed on the default branch.
  const digestPath = `${COMMUNITY_DIGEST_DIR}${runStartedAt.slice(0, 10)}-digest.md`;
  const digestCommitted = digestAlreadyExists
    ? await step.run("dedup-digest-committed-check", async () =>
        digestCommittedOnDefaultBranch({
          path: digestPath,
          cronName: "cron-community-monitor",
        }),
      )
    : false;
  if (digestAlreadyExists) {
    // Marker 5 is emitted on BOTH outcomes — the dedup-and-return case and the
    // issue-without-artifact recovery case. An emit on only one of them could
    // not distinguish "healthy dedup" from "recovered from a lost artifact".
    emitCronDedupSkip({
      cron: "cron-community-monitor",
      date: runStartedAt.slice(0, 10),
      digest_committed: digestCommitted ? 1 : 0,
    });
  }
  if (digestAlreadyExists && digestCommitted) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-community-monitor",
        logger,
      });
    });
    return { ok: true };
  }

  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        permissions: DEFAULT_CRON_TOKEN_PERMISSIONS,
        repositories: [REPO_NAME],
      });
    },
  );

  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-community-monitor" });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    // #5728 G1 — a deploy-in-progress defer (ADR-078/#5686) is a benign fail-SAFE
    // skip, NOT a failure. Rethrow it bare with NO heartbeat so Inngest retries
    // after the container swap; posting ?status=error here would red-flag a
    // benign defer AND defeat the retry intent.
    if (err instanceof DeployInProgressError) throw err;
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-community-monitor",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-community-monitor" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-community-monitor", logger });
    });
    return { ok: false };
  }

  try {
    // #5728 — flag pattern. The body (claude-eval → verify-output →
    // safe-commit-pr) runs in an inner try whose throw sets `threw`; the single
    // terminal heartbeat is posted (or skipped-for-retry) by
    // finalizeOutputAwareHeartbeat below — NOT from a second catch-site (which,
    // under retries:1 memoization, would replay a stale `ok` while posting a
    // conflicting `error`). A throw before the heartbeat previously propagated
    // out → the heartbeat step never ran → silent `missed` (the 06-13→06-21
    // class). spawnResult is hoisted so the silence-hole audit issue can read it
    // even when a later step threw.
    let heartbeatOk = false;
    // #6695 — paging and persistence are separate decisions. A collector
    // failure must turn the monitor RED, but must NOT discard the digest that
    // honestly reports it: heartbeatOk also gates safe-commit-pr below, and an
    // operator with a red monitor and no digest has strictly less to act on.
    // So the collector gate raises this flag and it is applied to heartbeatOk
    // AFTER the persistence step, leaving the cohort-wide issue-verified gate
    // shape (asserted by cron-safe-commit-parity) untouched.
    let collectorSignalRed = false;
    // #6714 — the LIVENESS signal, split from heartbeatOk by ADDITION (R20:
    // heartbeatOk is asserted as literal source text by cron-safe-commit-parity
    // across all 8 MIGRATED_PROMPT cohort files, so it keeps its name AND its
    // role as the persistence gate). heartbeatOk answers "did a labelled issue
    // land"; livenessOk answers "did the digest the operator actually consumes
    // get COMMITTED". Applied to heartbeatOk below, alongside collectorSignalRed.
    //
    // Initialised FALSE and set true ONLY by an observed positive. An earlier
    // draft initialised it true ("no evidence the artifact is missing") and
    // justified that by the retry hazard below. Review falsified both halves:
    //
    //  1. It left the bug class REACHABLE. A throw anywhere between
    //     verify-output and the persistence gate leaves heartbeatOk true and
    //     livenessOk never falsified → `failed = threw && !heartbeatOk` is
    //     false → NO retry → terminal GREEN with nothing committed, on the
    //     FIRST attempt. That is verbatim the shape ADR-126 forbids.
    //  2. The retry hazard it claimed to avoid ALREADY EXISTS on main via the
    //     pre-existing `if (collectorSignalRed) heartbeatOk = false` below, so
    //     the fail-open default bought nothing main had not already lost.
    //
    // A liveness signal that votes GREEN on an UNOBSERVED artifact is precisely
    // the defect this file exists to close, so fail-closed is the only
    // defensible default. The retry consequence is handled properly by
    // `retryEligible: false` at the finalize call rather than by weakening the
    // signal — see the four-arm table below and ADR-126.
    let livenessOk = false;
    let threw = false;
    let spawnResult: SpawnResult | null = null;
    try {
      spawnResult = await step.run(
        "claude-eval",
        async (): Promise<SpawnResult> => {
          return spawnClaudeEval({
            spawnCwd: spawnCwd!,
            installationToken,
            flags: CLAUDE_CODE_FLAGS,
            prompt: injectRunDate(COMMUNITY_MONITOR_PROMPT, runStartedAt),
            maxTurnDurationMs: MAX_TURN_DURATION_MS,
            cronName: "cron-community-monitor",
            // Wrapped rather than folded into buildSpawnEnv: the status dir is
            // run-scoped (it depends on spawnCwd), while buildSpawnEnv is a
            // static secret allowlist shared with the substrate's signature.
            buildSpawnEnv: (token: string) => ({
              ...buildSpawnEnv(token),
              SOLEUR_COLLECTOR_STATUS_DIR: `${spawnCwd!}/${COLLECTOR_STATUS_DIRNAME}`,
            }),
            logger,
            runId,
            attempt,
          });
        },
      );

      if (spawnResult.abortedByTimeout) {
        reportSilentFallback(
          new Error(
            `claude-eval aborted by timeout (${MAX_TURN_DURATION_MS}ms budget exceeded)`,
          ),
          {
            feature: "cron-community-monitor",
            op: "claude-eval-timeout",
            message: "claude-eval aborted by AbortController",
            extra: {
              fn: "cron-community-monitor",
              durationMs: spawnResult.durationMs,
              maxMs: MAX_TURN_DURATION_MS,
            },
          },
        );
      }

      // --- output-aware heartbeat. This cron is an always-create producer — it
      //     writes a dated digest and files a GitHub issue summarizing the
      //     findings every run (even the no-platform-enabled path creates a titled
      //     issue) — so a clean exit that produced no `scheduled-community-monitor`
      //     issue in the run window turns the monitor RED (and emits
      //     `scheduled-output-missing`) instead of false-green on claude's exit
      //     code. Mirrors the 3 producers wired by PR #4714 (#4730). Infra faults
      //     still page via the early-return status=error heartbeats. ---
      heartbeatOk = await step.run("verify-output", async () =>
        resolveOutputAwareOk({
          spawnOk: spawnResult!.ok,
          label: SENTRY_MONITOR_SLUG,
          runStartedAt,
          cronName: "cron-community-monitor",
          stderrTail: spawnResult!.stderrTail,
          exitCode: spawnResult!.exitCode,
          stdoutTail: spawnResult!.stdoutTail,
        }),
      );

      // --- Collector-status gate (#6695). Deliberately placed BEFORE the
      //     persistence gate below: that branch is guarded on
      //     `heartbeatOk && !abortedByTimeout`, so reading the sidecar inside it
      //     would make the signal unreachable on exactly the runs it exists to
      //     catch. reportSilentFallback fires UNCONDITIONALLY on a non-zero
      //     record and heartbeatOk is set independently of resolveOutputAwareOk's
      //     return value — its catch branch falls back to the spawn exit code
      //     (deliberate fail-open, #5139) and would otherwise mask this. ---
      const collectorStatus = await step.run("verify-collector-status", async () =>
        readCollectorStatus(spawnCwd!),
      );

      const verdict = classifyCollectorStatus(collectorStatus);

      if (verdict.failed.length > 0) {
        const summary = verdict.failed
          .map((r) => `${r.command ?? "unknown"}(exit=${r.exit}${r.cause ? `, cause=${r.cause}` : ""})`)
          .join("; ");
        reportSilentFallback(
          new Error(`github collector reported failures: ${summary}`),
          {
            feature: "cron-community-monitor",
            op: "collector-status-failed",
            message: "one or more github collector commands exited non-zero",
            extra: { fn: "cron-community-monitor", failures: verdict.failed },
          },
        );
        collectorSignalRed = true;
      } else if (verdict.warned.length > 0) {
        // Truncation is latent, not present-tense: the run's data is correct,
        // but a future one may silently undercount. Reported so it is visible,
        // deliberately NOT paged -- a nightly page for a hypothetical is how a
        // signal stops being read. Without this branch the `warn` field would
        // be written and typed but consumed by nothing, which is the same
        // dead-end this PR exists to remove.
        reportSilentFallback(
          new Error(
            `github collector hit a per_page cap: ${verdict.warned
              .map((r) => `${r.command ?? "unknown"}(${r.warn})`)
              .join("; ")}`,
          ),
          {
            feature: "cron-community-monitor",
            op: "collector-status-warn",
            message: "a collector fetch returned exactly per_page items",
            extra: { fn: "cron-community-monitor", warned: verdict.warned },
          },
        );
      } else if (verdict.missing) {
        // Distinguished from "all collectors succeeded". The sidecar should
        // exist on every healthy run (the github commands are unconditional), so
        // its absence means the collector never ran or could not write. Reported
        // but NOT paged: this mechanism is new, and paging RED on its own
        // absence during rollout would be a self-inflicted outage. Revisit once
        // a few green runs confirm the write path.
        reportSilentFallback(
          new Error("collector-status sidecar absent after claude-eval"),
          {
            feature: "cron-community-monitor",
            op: "collector-status-missing",
            message: "no collector-status.jsonl was written by the spawned run (github collector only; sibling platforms do not yet record status)",
            extra: { fn: "cron-community-monitor", spawnCwd },
          },
        );
      }

      // --- Step 4.5: deterministic persistence (#5111, pattern from #5091 /
      //     cron-seo-aeo-audit.ts). Gated on the issue-verified output rather
      //     than the spawn exit code: exit-0-with-no-issue is unverified
      //     (possibly mid-edit) work that must not auto-merge, while
      //     issue-created + non-zero exit is the documented healthy #4747 case
      //     whose diff must not be discarded. (Caveat: resolveOutputAwareOk
      //     falls back to the spawn exit code when its GitHub verify-read
      //     THROWS — a tri-state gate is tracked in #5139.) abortedByTimeout also skips —
      //     a hard kill can land mid-edit, and the timeout is already loud via
      //     the reportSilentFallback above. Guard aborts / persistence failures
      //     self-report inside the helper (Sentry + issue comment).
      // #6714 marker 3 — THE signal that would have decided H9 on day one.
      // Stat'ing the digest in the workspace immediately BEFORE the gate splits
      // "the agent never wrote the file" from "the file was written but never
      // entered the commit". Emitted unconditionally (outside the gate) so a
      // skipped run is covered too, and outside step.run because it has no
      // side effect worth memoizing.
      //
      // Lazy imports for the SAME reason as readCollectorStatus above: a
      // top-level node:fs binding lands in the static graph of every sibling
      // test that mocks node builtins with partial factories.
      const { existsSync } = await import("node:fs");
      const { join: joinPath } = await import("node:path");
      emitCommunityDigestFile({
        cron: "cron-community-monitor",
        attempt: attempt ?? 0,
        digest_path: digestPath,
        present: existsSync(joinPath(spawnCwd!, digestPath)) ? 1 : 0,
      });
      if (heartbeatOk && !spawnResult.abortedByTimeout) {
        // #6714 R16a, THE PRIMARY DEFECT: this return value was DISCARDED, so a
        // {status:"failed"} or {status:"no-changes"} was silently dropped and
        // the monitor stayed GREEN with nothing committed.
        const commitResult = await step.run("safe-commit-pr", async () =>
          safeCommitAndPr({
            spawnCwd: spawnCwd!,
            installationToken,
            cronName: "cron-community-monitor",
            commitMessage: "docs: daily community digest",
            allowedPaths: COMMUNITY_MONITOR_ALLOWED_PATHS,
            runStartedAt,
            scheduledIssueLabel: SENTRY_MONITOR_SLUG,
            logger,
          }),
        );
        // The liveness table. `livenessOk` is FALSE until proven otherwise, so
        // only the two arms below can turn the run GREEN; everything else —
        // "no-changes", "failed", committed-without-today's-digest, and every
        // throw that never reaches here — falls through still RED.
        let livenessReason: CronDigestLivenessMarker["reason"] =
          "persistence-not-committed";
        if (commitResult.status === "committed") {
          if (commitResult.paths?.includes(digestPath)) {
            // THE POSITIVE: today's digest is demonstrably in the commit.
            // `includes` is membership, not position — the allowlist covers the
            // whole community directory, so the agent may land other files
            // beside the digest and the digest need not be first.
            livenessOk = true;
            livenessReason = "digest-committed";
          } else if (commitResult.paths === undefined) {
            // NOT DETERMINED (R21), never "nothing committed". But ONLY the
            // replay-resume branch has a legitimate reason to leave it
            // undetermined — it is the one path that skips the allowlist scan.
            // Any OTHER undetermined shape means the result contract drifted,
            // and voting GREEN on an unknown is exactly the failure this issue
            // is about, so it stays red.
            livenessOk = commitResult.resumed === true;
            livenessReason = commitResult.resumed
              ? "undetermined-replay-resume"
              : "undetermined-contract-drift";
          } else {
            // committed something, but not today's digest → stays RED.
            livenessReason = "digest-absent-from-commit";
          }
        }
        // Marker 6 — the VERDICT plus the arm that decided it. Without this the
        // RED arms are indistinguishable in Better Stack: marker 1 already
        // emitted `status:"committed"` from inside safeCommitAndPr before this
        // table ran.
        emitCronDigestLiveness({
          cron: "cron-community-monitor",
          run_id: runId ?? "unknown",
          attempt: attempt ?? 0,
          ok: livenessOk ? 1 : 0,
          reason: livenessReason,
        });
      } else {
        // #6714 marker 2 — this gate had NO else, so a RED or timed-out run
        // skipped persistence leaving no trace on any operator-reachable
        // surface. abortedByTimeout is checked first because a timed-out run is
        // also usually red, and the timeout is the more specific cause.
        emitCronPersistSkipped({
          cron: "cron-community-monitor",
          reason: spawnResult.abortedByTimeout ? "timeout" : "red",
        });
        // Nothing was persisted. If heartbeatOk is false the run is already RED;
        // the case this catches is a timed-out run whose issue landed, which was
        // GREEN-with-no-artifact before this line.
        livenessOk = false;
        emitCronDigestLiveness({
          cron: "cron-community-monitor",
          run_id: runId ?? "unknown",
          attempt: attempt ?? 0,
          ok: 0,
          reason: "persistence-skipped",
        });
      }
    } catch (err) {
      // #5728 G1 — a deploy-in-progress defer is benign (ADR-078/#5686): rethrow
      // bare with NO heartbeat so Inngest retries after the swap. Any OTHER throw
      // is a real failure — flag it; finalizeOutputAwareHeartbeat decides
      // error-vs-retry below. An output-PRESENT run that threw in a TRAILING step
      // (safe-commit-pr) stays GREEN — heartbeatOk is already true and the
      // persistence failure self-reports here.
      if (err instanceof DeployInProgressError) throw err;
      threw = true;
      const e = err as Error;
      const redactedMsg = redactToken(e.message ?? "", installationToken);
      const redacted = new Error(redactedMsg);
      redacted.name = e.name;
      reportSilentFallback(redacted, {
        feature: "cron-community-monitor",
        op: "handler-body-threw",
        message:
          "cron-community-monitor body threw before the terminal heartbeat",
        extra: {
          fn: "cron-community-monitor",
          attempt: attempt ?? 0,
          producedOutput: heartbeatOk,
        },
      });
    }

    // #6695 — applied HERE, after the inner try/catch closes, for two reasons.
    // (1) AFTER persistence: `heartbeatOk` also gates safeCommitAndPr, so
    //     lowering it at the collector gate would discard the very digest that
    //     honestly reports the failure -- a red monitor and nothing to read.
    // (2) OUTSIDE the try: as the try's LAST statement this was skipped whenever
    //     a trailing step threw, and the catch deliberately keeps heartbeatOk
    //     true for a trailing-step failure -- so the page was silently lost on
    //     exactly the compound-failure run. The catch falls through to here.
    if (collectorSignalRed) heartbeatOk = false;

    // #6714 — the liveness signal APPLIED. Same two reasons as #6695 above:
    // after persistence (heartbeatOk gates safeCommitAndPr, so lowering it any
    // earlier would discard the very digest whose absence we are reporting) and
    // outside the try (a trailing throw must not skip the page).
    //
    // Reachability note for the `threw && !heartbeatOk → retry` hazard called
    // out on the livenessOk declaration: livenessOk is falsified ONLY at the
    // tail of the try, with nothing throwing after it, and a throw out of
    // safe-commit-pr leaves it true by construction. So "threw AND liveness-red"
    // is unreachable here, and this line cannot induce a replay against the
    // already-deleted spawnCwd.
    if (!livenessOk) heartbeatOk = false;

    // --- Single authoritative terminal heartbeat (memoization-safe,
    //     final-attempt gated). On a genuine non-final failure the helper skips
    //     the whole heartbeat step and returns retry:true (we rethrow to trigger
    //     the Inngest retry, filing NO premature FAILED issue). On the post path,
    //     the Step-5 silence-hole fallback (#4960/#4978) files a FAILED audit
    //     issue when red, ordered BEFORE the heartbeat so the heartbeat stays the
    //     genuine last step. ---
    const { retry } = await finalizeOutputAwareHeartbeat({
      step,
      heartbeatOk,
      threw,
      attempt,
      maxAttempts,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-community-monitor",
      logger,
      // #6714 — a replay CANNOT recover any failure inside the guarded body:
      // `setup-workspace` is memoized, so attempt 1 reads back an ephemeralRoot
      // the `finally` below already deleted, and safeCommitAndPr then hits its
      // `workspace-lost` guard unconditionally — which comments a misleading
      // "PR withheld" + runbook pointer onto the operator's issue. This is what
      // lets livenessOk be honestly fail-closed without buying that useless
      // replay. Scoped precisely: throws BEFORE the try (token mint,
      // setup-workspace itself) are unaffected and still retry into a fresh
      // workspace, and DeployInProgressError still rethrows bare.
      retryEligible: false,
      onBeforeHeartbeat: heartbeatOk
        ? undefined
        : async () => {
            await step.run("ensure-audit-issue", async () => {
              try {
                await ensureScheduledAuditIssue({
                  label: SENTRY_MONITOR_SLUG,
                  titlePrefix: SCHEDULED_DIGEST_TITLE_PREFIX,
                  cronName: "cron-community-monitor",
                  runStartedAt,
                  spawnResult: spawnResult ?? makeThrewSpawnResult("cron-community-monitor"),
                  installationToken,
                });
              } catch (err) {
                reportSilentFallback(err, {
                  feature: "cron-community-monitor",
                  op: "ensure-audit-issue-failed",
                  message:
                    "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
                  extra: { fn: "cron-community-monitor", runStartedAt },
                });
              }
            });
          },
    });
    if (retry) {
      throw new Error(
        "cron-community-monitor failed on a non-final attempt; retrying",
      );
    }

    return { ok: heartbeatOk };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-community-monitor").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-community-monitor",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-community-monitor", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 8 * * * UTC — daily 08:00) + manual
// operator event `cron/community-monitor.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation
// across the Hetzner node (PR-1 / PR-4 / PR-5 precedent).

export const cronCommunityMonitor = inngest.createFunction(
  {
    id: "cron-community-monitor",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 8 * * *" },
    { event: "cron/community-monitor.manual-trigger" },
  ],
  cronCommunityMonitorHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
