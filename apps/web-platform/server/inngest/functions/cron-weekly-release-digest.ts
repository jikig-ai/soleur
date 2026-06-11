// #5080 — weekly community release digest (Discord #releases).
//
// Pure-TS Inngest cron (closest sibling: cron-weekly-analytics.ts — same
// registration block + handler-level catch-then-heartbeat tail; Anthropic
// call shape mirrors cron-compound-promote.ts). Fires Friday 15:00 UTC,
// enumerates the week's GitHub Releases ((start, end] window ending Friday),
// sanitizes (PII-strip + security down-detail), curates 3-5 highlights via a
// direct Anthropic Messages API call with a deterministic feat>fix>chore
// fallback, renders ONE payload shape, and POSTs to the #releases webhook.
//
// ADR-033 invariants: I1 (step.run for I/O), I2 (operator key, no BYOK),
// I5 (deterministic return).
//
// Failure contract (spec TR6): steps THROW on failure (Inngest grants one
// step retry); the handler-level catch sends a best-effort ok:false Sentry
// check-in and returns { ok: false } — never throw-without-heartbeat. The
// Sentry monitor is the sole liveness layer (catch-and-return marks the run
// COMPLETED; Inngest-native failure events never fire — by design).
//
// No #general fallback (spec FR6): a missing/empty/dead
// DISCORD_RELEASES_WEBHOOK_URL is a FAILURE (red monitor), not a reroute —
// a fallback would keep the monitor green while #releases stays dead.

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  mintInstallationToken,
  postDiscordWebhook,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";

const FUNCTION_NAME = "cron-weekly-release-digest";
const SENTRY_MONITOR_SLUG = "cron-weekly-release-digest";

const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;
// Never-downgrade-shaped (ADR-053): unattended public brand-voice surface at
// single-user-incident threshold — judgment-adjacent, NOT a mechanical step;
// do not sweep to haiku. Concrete ID per the ADR-053 cron-constants
// lifecycle (matches cron-compound-promote.ts); registry consolidation
// deferred to #5106.
const ANTHROPIC_MODEL = "claude-sonnet-4-6";
const ANTHROPIC_MAX_TOKENS = 2048;
const ANTHROPIC_TIMEOUT_MS = 60_000;
const MAX_RELEASE_BODY_CHARS = 1500;
const DISCORD_CONTENT_MAX = 2000;

// Operational prompt rules. AUTHORITATIVE COPY — knowledge-base/ is NOT in
// the container image (docker_context is apps/web-platform), so a runtime
// file read would be dead code falling to a fallback on every prod run.
// The human-readable source lives in knowledge-base/marketing/brand-guide.md
// under "#### Release Digest"; byte-sync is asserted by the unit test
// (drift lockstep — brand-guide edits that skip this constant fail CI).
export const RELEASE_DIGEST_RULES = `#### Release Digest

Automated weekly post to #releases (Fridays). These are operational rules for unattended generation — follow exactly:

- **Format:** 3-5 highlight bullets, each one sentence in the shape "what shipped + why it matters to a founder." Close with exactly one remainder line: "…plus N more releases, vA → vB." Total post ≤2000 characters. No @-mentions, no contributor names, no commit hashes, no links unless they appear in the release notes.
- **Selection rubric:** rank candidate releases by (1) founder impact — something a user can now do, stop doing, or stop worrying about; (2) breadth — affects most users, not one niche config; (3) novelty — new capability beats fix beats chore. Never rank by commit count, diff size, or release frequency.
- **Tone:** declarative, concrete, builder-to-builder. Lead each bullet with the outcome, not the component name. State only what shipped — no roadmap promises, no hype adjectives ("game-changing," "massive"), no "just/simply," no "AI-powered." Use a number only if it appears verbatim in the source release notes. Structural emoji (arrows, checkmarks) sparingly; decorative emoji never.
- **Example highlight:** "Release notifications now land in Slack instead of Discord DMs — your team sees ships where they already work."
- **Quiet week (zero releases):** post one line only, e.g. "Quiet week at the forge — heads-down on the next release. See you next Friday." Never pad with filler highlights or restate old releases as new.`;

// --- Pure helpers (exported for unit tests) ---------------------------------

export interface DigestWindow {
  start: Date;
  end: Date;
  weekKey: string;
}

// Window end = most recent Friday 15:00 UTC <= now; window = (end-7d, end]
// (half-open, end-inclusive: a release published exactly at Friday 15:00:00
// belongs to the closing week, never double-counted). Manual triggers on
// other days resolve to the same window as the natural fire.
export function computeWindow(now: Date): DigestWindow {
  for (let i = 0; i <= 7; i++) {
    const candidate = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - i, 15, 0, 0),
    );
    if (candidate.getUTCDay() === 5 && candidate.getTime() <= now.getTime()) {
      const start = new Date(candidate.getTime() - 7 * 24 * 60 * 60 * 1000);
      return { start, end: candidate, weekKey: candidate.toISOString().slice(0, 10) };
    }
  }
  // Unreachable: any 8-day span contains a Friday.
  throw new Error("computeWindow: no Friday found");
}

// Highlight-eligible iff the tag is plugin (v<digit>...) or web-platform
// (web-v<digit>...). Anchored on the DIGIT: vinngest-v* starts with "v" but
// NOT "v<digit>" — a bare v-prefix match would headline infra bootstrap
// releases (the Kieran-P0 collision class). telegram-v*, vinngest-v*, and
// future families count toward the remainder aggregate only.
export function isHighlightEligible(tag: string): boolean {
  return /^v\d/.test(tag) || /^web-v\d/.test(tag);
}

const SECURITY_DOWN_DETAIL_RE = /security|vulnerab|CVE-\d|xss|rce|injection|privilege escalation/i;
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const HANDLE_RE = /@[A-Za-z0-9][A-Za-z0-9-]*/g;
const CO_AUTHORED_RE = /^\s*co-authored-by:.*$/gim;

export interface RawGithubRelease {
  tag_name: string;
  name?: string | null;
  body?: string | null;
  published_at: string;
  draft: boolean;
  prerelease: boolean;
  author?: { login?: string } | null;
}

export interface SanitizedRelease {
  tag: string;
  title: string;
  body: string;
  securitySensitive: boolean;
}

function stripPii(s: string): string {
  return s.replace(CO_AUTHORED_RE, "").replace(EMAIL_RE, "").replace(HANDLE_RE, "");
}

// PII-strip (spec TR4: author dropped; @handles, emails, Co-Authored-By
// lines removed — release bodies derive from PR-body Changelogs which embed
// both) + security down-detail (spec TR2: matching releases render
// title-only; the body is withheld from the LLM input so generated prose
// cannot widen an exploit window) + per-release truncation.
export function sanitizeReleases(releases: RawGithubRelease[]): SanitizedRelease[] {
  return releases.map((r) => {
    const title = stripPii(r.name || r.tag_name).trim();
    const rawBody = r.body ?? "";
    const securitySensitive = SECURITY_DOWN_DETAIL_RE.test(`${r.name ?? ""}\n${rawBody}`);
    const body = securitySensitive
      ? ""
      : stripPii(rawBody).slice(0, MAX_RELEASE_BODY_CHARS);
    return { tag: r.tag_name, title, body, securitySensitive };
  });
}

export interface Highlight {
  tag: string;
  title: string;
  why: string;
}

// Closed input set (spec TR1): the prompt carries ONLY sanitized published
// release titles/bodies plus the brand rules constant. Output is highlights
// only — the remainder line is computed by code from data the handler
// already holds, never echoed through the model.
export function buildCuratePrompt(releases: SanitizedRelease[]): string {
  const payload = releases.map((r) => ({
    tag: r.tag,
    title: r.title,
    body: r.securitySensitive ? "(security fix — title only)" : r.body,
  }));
  return [
    "You curate Soleur's weekly community release digest. Follow these brand rules exactly:",
    "",
    RELEASE_DIGEST_RULES,
    "",
    "From the releases below, pick 3-5 highlights (fewer if fewer qualify). For each, write `why`: one sentence, what shipped + why it matters to a founder, summarizing ONLY what the release notes state — never add technical detail absent from the source.",
    'Respond with ONLY a JSON object: {"highlights":[{"tag":"<tag from the list>","title":"<title from the list>","why":"<one sentence>"}]}',
    "",
    "Releases (sanitized, published):",
    JSON.stringify(payload),
  ].join("\n");
}

const CONVENTIONAL_RANK: Array<[RegExp, number]> = [
  [/^feat/i, 0],
  [/^fix/i, 1],
  [/^chore/i, 3],
];

function rankOf(title: string): number {
  for (const [re, rank] of CONVENTIONAL_RANK) {
    if (re.test(title)) return rank;
  }
  return 2;
}

// Deterministic fallback (spec FR4): rank feat > fix > (other) > chore,
// verbatim titles — the week is posted even when the LLM path fails.
export function deterministicFallback(releases: SanitizedRelease[]): Highlight[] {
  return [...releases]
    .sort((a, b) => rankOf(a.title) - rankOf(b.title))
    .slice(0, 5)
    .map((r) => ({ tag: r.tag, title: r.title, why: r.title }));
}

// Suppress Discord markup specials in untrusted text (<@id>, <#id>,
// <https://…> disguised links). Mention PINGS are already impossible
// (allowed_mentions parse:[] at the API layer); this prevents silent
// mention/link RENDERING from release-note text.
function escapeDiscordMarkup(s: string): string {
  return s.replace(/</g, "\\<");
}

export interface DigestRender {
  highlights: Highlight[];
  remainder: { count: number; fromTag: string; toTag: string };
  weekKey: string;
}

const QUIET_WEEK_LINE =
  "Quiet week at the forge — heads-down on the next release. See you next Friday.";

// Single renderer over one intermediate shape: the LLM path, deterministic
// fallback, and quiet week (empty highlights) all flow through here, so the
// allowed_mentions/escape/length invariants live in exactly one place.
// Escaping runs BEFORE the length measurement — escaping must never
// re-expand a truncated payload past the Discord limit.
export function renderDigest(input: DigestRender): string {
  if (input.highlights.length === 0) return QUIET_WEEK_LINE;
  const lines = [
    `**Soleur this week** (week of ${input.weekKey})`,
    "",
    ...input.highlights.map((h) => `• ${escapeDiscordMarkup(h.why)}`),
  ];
  if (input.remainder.count > 0) {
    lines.push(
      "",
      `…plus ${input.remainder.count} more releases, ${escapeDiscordMarkup(input.remainder.fromTag)} → ${escapeDiscordMarkup(input.remainder.toTag)}`,
    );
  }
  const content = lines.join("\n");
  if (content.length <= DISCORD_CONTENT_MAX) return content;
  return `${content.slice(0, DISCORD_CONTENT_MAX - 1)}…`;
}

// --- Anthropic curation ------------------------------------------------------

async function curateViaAnthropic(
  releases: SanitizedRelease[],
  logger: HandlerArgs["logger"],
): Promise<Highlight[]> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");

  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: ANTHROPIC_MAX_TOKENS,
      messages: [{ role: "user" as const, content: buildCuratePrompt(releases) }],
    }),
    signal: AbortSignal.timeout(ANTHROPIC_TIMEOUT_MS),
  });
  if (!resp.ok) throw new Error(`Anthropic API ${resp.status}`);

  const data = (await resp.json()) as {
    content?: Array<{ text?: string }>;
    stop_reason?: string;
  };
  if (data.stop_reason === "max_tokens") {
    logger.warn({ fn: FUNCTION_NAME }, "anthropic-response-truncated");
    throw new Error("anthropic response truncated");
  }
  const text = data.content?.[0]?.text;
  if (!text) throw new Error("empty anthropic response");

  const parsed = JSON.parse(text) as { highlights?: unknown };
  if (!parsed || !Array.isArray(parsed.highlights)) {
    throw new Error("anthropic response shape invalid");
  }
  // Verbatim-or-less (spec TR3): tags must come from the window's API data —
  // hallucinated tags are discarded; zero valid highlights falls back.
  const eligibleTags = new Set(releases.map((r) => r.tag));
  const valid = (parsed.highlights as Array<Record<string, unknown>>)
    .filter(
      (h) =>
        typeof h?.tag === "string" &&
        eligibleTags.has(h.tag) &&
        typeof h?.title === "string" &&
        typeof h?.why === "string",
    )
    .slice(0, 5) as unknown as Highlight[];
  if (valid.length === 0) throw new Error("no valid highlights in anthropic response");
  return valid;
}

// --- Handler -----------------------------------------------------------------

export async function cronWeeklyReleaseDigestHandler(args: HandlerArgs) {
  const { step, logger } = args;
  try {
    const window = computeWindow(new Date());

    const fetched = await step.run("fetch-releases", async () => {
      const token = await mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        // Least-privilege (hr-github-app-auth-not-pat): releases read needs
        // contents:read only — do NOT reuse the wider issue-creator preset.
        permissions: { contents: "read" },
        repositories: [REPO_NAME],
      });
      const resp = await fetch(
        `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=100`,
        {
          headers: {
            authorization: `Bearer ${token}`,
            accept: "application/vnd.github+json",
          },
        },
      );
      if (!resp.ok) throw new Error(`GitHub releases API ${resp.status}`);
      const all = (await resp.json()) as RawGithubRelease[];
      const startMs = window.start.getTime();
      const endMs = window.end.getTime();
      const inWindow = all.filter((r) => {
        if (r.draft || r.prerelease) return false;
        const t = new Date(r.published_at).getTime();
        return t > startMs && t <= endMs;
      });
      // /releases orders by created_at desc -> first = newest. The range
      // line reads oldest -> newest.
      const tags = inWindow.map((r) => r.tag_name);
      const eligible = sanitizeReleases(inWindow.filter((r) => isHighlightEligible(r.tag_name)));
      logger.info(
        { fn: FUNCTION_NAME, weekKey: window.weekKey, total: inWindow.length, eligible: eligible.length },
        "fetched releases for window",
      );
      return {
        eligible,
        totalCount: inWindow.length,
        fromTag: tags[tags.length - 1] ?? "",
        toTag: tags[0] ?? "",
      };
    });

    const curated = await step.run("curate", async () => {
      if (fetched.eligible.length === 0) {
        return { highlights: [] as Highlight[], fallback: false };
      }
      // Anthropic failure is caught INSIDE this step (fallback marker) so a
      // transient LLM error never consumes the function retry — the
      // deterministic fallback posts the week regardless (spec FR4).
      try {
        const highlights = await curateViaAnthropic(fetched.eligible, logger);
        return { highlights, fallback: false };
      } catch (err) {
        reportSilentFallback(err as Error, {
          feature: FUNCTION_NAME,
          op: "anthropic-curate",
          message: "LLM curation failed — deterministic fallback rendered",
          extra: { fn: FUNCTION_NAME, eligible: fetched.eligible.length },
        });
        return { highlights: deterministicFallback(fetched.eligible), fallback: true };
      }
    });

    await step.run("post-discord", async () => {
      // No #general fallback (spec FR6) — missing/empty secret is a failure.
      const url = process.env.DISCORD_RELEASES_WEBHOOK_URL;
      if (!url || url.trim() === "") {
        reportSilentFallback(new Error("DISCORD_RELEASES_WEBHOOK_URL missing or empty"), {
          feature: FUNCTION_NAME,
          op: "post-discord",
          message: "#releases webhook secret missing — digest NOT posted (no fallback by design)",
          extra: { fn: FUNCTION_NAME },
        });
        throw new Error("DISCORD_RELEASES_WEBHOOK_URL missing or empty");
      }
      const content = renderDigest({
        highlights: curated.highlights,
        remainder: {
          count: Math.max(0, fetched.totalCount - curated.highlights.length),
          fromTag: fetched.fromTag,
          toTag: fetched.toTag,
        },
        weekKey: window.weekKey,
      });
      // THROW on non-2xx so Inngest's retries:1 grants one step retry on a
      // transient failure; the handler-level catch below converts the
      // post-exhaustion StepError into an ok:false check-in.
      const resp = await postDiscordWebhook({
        webhookUrl: url,
        content,
        username: "Soleur Releases",
      });
      if (!resp.ok) throw new Error(`Discord webhook returned ${resp.status}`);
    });

    await step.run("sentry-heartbeat", () =>
      postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: FUNCTION_NAME,
        logger,
      }),
    );
    return {
      ok: true,
      weekKey: window.weekKey,
      highlights: curated.highlights.length,
      fallback: curated.fallback,
    };
  } catch (err) {
    // Handler-level catch (cron-weekly-analytics tail precedent): a check-in
    // is ALWAYS attempted — never throw-without-heartbeat. The heartbeat is a
    // direct best-effort call (not step.run: steps may be unavailable after a
    // StepError, and a failed heartbeat must not mask the original error).
    const e = err as Error;
    reportSilentFallback(e, {
      feature: FUNCTION_NAME,
      op: "handler-top-level",
      message: e.message ?? "weekly release digest failed",
    });
    try {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: FUNCTION_NAME,
        logger,
      });
    } catch {
      // best-effort
    }
    return { ok: false };
  }
}

export const cronWeeklyReleaseDigest = inngest.createFunction(
  {
    id: FUNCTION_NAME,
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 15 * * 5" },
    { event: "cron/weekly-release-digest.manual-trigger" },
  ],
  cronWeeklyReleaseDigestHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
