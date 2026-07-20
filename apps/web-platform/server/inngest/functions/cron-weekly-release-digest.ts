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
  postAnthropicMessage,
  postDiscordWebhook,
  postSentryHeartbeat,
  redactToken,
  type HandlerArgs,
} from "./_cron-shared";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";
import {
  sanitizeReleases,
  type RawGithubRelease,
  type SanitizedRelease,
} from "@/server/release-notes";

const FUNCTION_NAME = "cron-weekly-release-digest";
const SENTRY_MONITOR_SLUG = "cron-weekly-release-digest";

const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;
// Never-downgrade-shaped (ADR-053): unattended public brand-voice surface at
// single-user-incident threshold — judgment-adjacent, NOT a mechanical step;
// do not sweep to haiku. Concrete ID per the ADR-053 cron-constants
// lifecycle (matches cron-compound-promote.ts); the sonnet pin is now
// sourced from the EXECUTION_MODEL registry constant (consolidated in #5106).
const ANTHROPIC_MODEL = EXECUTION_MODEL;
const ANTHROPIC_MAX_TOKENS = 2048;
const ANTHROPIC_TIMEOUT_MS = 60_000;
// Structured-output schema (#5186): guarantees schema-valid JSON so the response
// needs no fence-stripping. `additionalProperties: false` is REQUIRED on every
// object; numeric/array constraints (maxItems) are NOT supported by the API —
// the MAX_HIGHLIGHTS cap stays a post-parse TS slice below, and the eligible-tag
// filter stays load-bearing (the model can still emit an out-of-window tag).
const CURATE_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["highlights"],
  properties: {
    highlights: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["tag", "title", "why"],
        properties: {
          tag: { type: "string" },
          title: { type: "string" },
          why: { type: "string" },
        },
      },
    },
  },
} as const;
const MAX_HIGHLIGHTS = 5;
const DISCORD_CONTENT_MAX = 2000;
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
// The repo measures ~100 releases/week live — a single per_page=100 page has
// ZERO headroom (review git-history P2). Paginate up to 3 pages and warn
// loudly if the window is still truncated.
const RELEASES_PER_PAGE = 100;
const RELEASES_MAX_PAGES = 3;

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
- **Quiet week (zero user-facing releases — internal-infra-only weeks count as quiet):** post one line only, e.g. "Quiet week at the forge — heads-down on the next release. See you next Friday." Never pad with filler highlights or restate old releases as new.`;

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
      const start = new Date(candidate.getTime() - WEEK_MS);
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

// Sanitize (PII strip + security down-detail) + release types now live in the
// shared `@/server/release-notes` module (imported above) so the in-app
// Releases page reuses the exact same brand-critical hygiene (#5958).

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
    .slice(0, MAX_HIGHLIGHTS)
    .map((r) => ({ tag: r.tag, title: r.title, why: r.title }));
}

// Suppress Discord-active markup in untrusted text. Order is load-bearing
// (formatTailForIssue precedent): backslash FIRST, else attacker-supplied
// `\<@id>` becomes `\\<@id>` and the literal-backslash consumes our escape,
// rendering the mention chip live (review security P2-1). `[` is escaped to
// break masked-link syntax `[text](url)` (P2-2). Mention PINGS are already
// impossible (allowed_mentions parse:[] at the API layer); this prevents
// silent mention/link RENDERING.
export function escapeDiscordMarkup(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/</g, "\\<").replace(/\[/g, "\\[");
}

// Free-text fields (LLM `why`, fallback titles) must not carry clickable
// URLs into a public brand-voice post — Discord autolinks bare URLs, and a
// phishing link in Soleur's voice is materially worse than plain text
// (review security P2-2 / user-impact F1). Tags and the static quiet-week
// line never carry URLs by construction.
export function stripUrls(s: string): string {
  return s.replace(/https?:\/\/\S+/gi, "‹link›");
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
    ...input.highlights.map((h) => `• ${escapeDiscordMarkup(stripUrls(h.why))}`),
  ];
  if (input.remainder.count > 0) {
    lines.push(
      "",
      `…plus ${input.remainder.count} more releases, ${escapeDiscordMarkup(input.remainder.fromTag)} → ${escapeDiscordMarkup(input.remainder.toTag)}`,
    );
  }
  const content = lines.join("\n");
  if (content.length <= DISCORD_CONTENT_MAX) return content;
  // Truncation-safe: never cut between an escape backslash and its target,
  // or mid-surrogate-pair (review git-history P3).
  const truncated = content
    .slice(0, DISCORD_CONTENT_MAX - 1)
    .replace(/\\+$/, "")
    .replace(/[\uD800-\uDBFF]$/, "");
  return `${truncated}…`;
}

// --- Anthropic curation ------------------------------------------------------

async function curateViaAnthropic(releases: SanitizedRelease[]): Promise<Highlight[]> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");

  const { text, stopReason } = await postAnthropicMessage({
    apiKey,
    model: ANTHROPIC_MODEL,
    maxTokens: ANTHROPIC_MAX_TOKENS,
    messages: [{ role: "user", content: buildCuratePrompt(releases) }],
    timeoutMs: ANTHROPIC_TIMEOUT_MS,
    outputConfig: { format: { type: "json_schema", schema: CURATE_OUTPUT_SCHEMA } },
  });
  if (stopReason === "max_tokens") {
    // The curate step's catch mirrors this to Sentry — no duplicate warn.
    throw new Error("anthropic response truncated");
  }
  if (!text) throw new Error("empty anthropic response");

  // Structured output guarantees schema-valid JSON — parse directly, no fence strip.
  const parsed = JSON.parse(text) as { highlights?: unknown };
  if (!parsed || !Array.isArray(parsed.highlights)) {
    throw new Error("anthropic response shape invalid");
  }
  // Verbatim-or-less (spec TR3): tags must come from the window's API data —
  // hallucinated tags are discarded, repeats deduped (a model echoing one
  // valid tag N times must not render N duplicate bullets); zero valid
  // highlights falls back.
  const eligibleTags = new Set(releases.map((r) => r.tag));
  const seenTags = new Set<string>();
  const isHighlight = (h: Record<string, unknown>): h is Record<string, string> =>
    typeof h?.tag === "string" &&
    eligibleTags.has(h.tag) &&
    typeof h?.title === "string" &&
    typeof h?.why === "string";
  const valid: Highlight[] = [];
  for (const h of parsed.highlights as Array<Record<string, unknown>>) {
    if (!isHighlight(h) || seenTags.has(h.tag)) continue;
    seenTags.add(h.tag);
    valid.push({ tag: h.tag, title: h.title, why: h.why });
    if (valid.length >= MAX_HIGHLIGHTS) break;
  }
  if (valid.length === 0) throw new Error("no valid highlights in anthropic response");
  return valid;
}

// --- Handler -----------------------------------------------------------------

export async function cronWeeklyReleaseDigestHandler(args: HandlerArgs) {
  const { step, logger } = args;
  // Hoisted so the handler-level catch can redact it from error messages
  // (cron-weekly-analytics tail precedent). Stays "" on memoized replays —
  // a token can only appear in errors thrown by the invocation that minted it.
  let installationToken = "";
  try {
    const fetched = await step.run("fetch-releases", async () => {
      // Clock read lives INSIDE the step so the window is memoized with the
      // data: Inngest re-executes the handler body per step boundary, and a
      // run straddling Friday 15:00 UTC must not flip windows between steps
      // (review data-integrity P2; 4 agents concurred). ISO strings only —
      // step outputs round-trip through JSON.
      const window = computeWindow(new Date());
      const startMs = window.start.getTime();
      const endMs = window.end.getTime();

      const token = await mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        // Least-privilege (hr-github-app-auth-not-pat): releases read needs
        // contents:read only — do NOT reuse the wider issue-creator preset.
        permissions: { contents: "read" },
        repositories: [REPO_NAME],
      });
      installationToken = token;

      // ~100 releases/week measured live — paginate until the page is short,
      // the oldest entry predates the window, or the page cap is hit.
      // /releases orders by created_at desc (window filters on published_at —
      // a long-draft release can still slip past the cap; warned below).
      const all: RawGithubRelease[] = [];
      let truncated = false;
      for (let page = 1; page <= RELEASES_MAX_PAGES; page++) {
        const resp = await fetch(
          `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=${RELEASES_PER_PAGE}&page=${page}`,
          {
            headers: {
              authorization: `Bearer ${token}`,
              accept: "application/vnd.github+json",
            },
          },
        );
        if (!resp.ok) throw new Error(`GitHub releases API ${resp.status}`);
        const batch = (await resp.json()) as RawGithubRelease[];
        all.push(...batch);
        if (batch.length < RELEASES_PER_PAGE) break;
        const oldest = batch[batch.length - 1];
        if (oldest && new Date(oldest.published_at).getTime() <= startMs) break;
        if (page === RELEASES_MAX_PAGES) truncated = true;
      }
      if (truncated) {
        reportSilentFallback(new Error("release window truncated at page cap"), {
          feature: FUNCTION_NAME,
          op: "fetch-releases",
          message: "More in-window releases exist than the page cap fetched — digest undercounts",
          extra: { fn: FUNCTION_NAME, pages: RELEASES_MAX_PAGES },
        });
      }

      const inWindow = all.filter((r) => {
        if (r.draft || r.prerelease) return false;
        const t = new Date(r.published_at).getTime();
        return t > startMs && t <= endMs;
      });
      // Range line reads oldest -> newest by published_at (created_at API
      // ordering can misplace long-drafted releases — review DI P3).
      const byPublished = [...inWindow].sort(
        (a, b) => new Date(a.published_at).getTime() - new Date(b.published_at).getTime(),
      );
      const eligible = sanitizeReleases(inWindow.filter((r) => isHighlightEligible(r.tag_name)));
      logger.info(
        { fn: FUNCTION_NAME, weekKey: window.weekKey, total: inWindow.length, eligible: eligible.length },
        "fetched releases for window",
      );
      return {
        eligible,
        totalCount: inWindow.length,
        fromTag: byPublished[0]?.tag_name ?? "",
        toTag: byPublished[byPublished.length - 1]?.tag_name ?? "",
        weekKey: window.weekKey,
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
        const highlights = await curateViaAnthropic(fetched.eligible);
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
      // No #general fallback (spec FR6) — missing/empty/malformed secret is a
      // failure. The shape guard also prevents undici's "Failed to parse URL
      // from <url>" TypeError from embedding the secret in an error message
      // that the tail ships to Sentry (review code-quality P2-1). Single
      // Sentry report via the handler-level catch — no in-step duplicate.
      const url = process.env.DISCORD_RELEASES_WEBHOOK_URL;
      if (!url || !url.startsWith("https://discord.com/api/webhooks/")) {
        throw new Error("DISCORD_RELEASES_WEBHOOK_URL missing, empty, or malformed");
      }
      const content = renderDigest({
        highlights: curated.highlights,
        remainder: {
          count: Math.max(0, fetched.totalCount - curated.highlights.length),
          fromTag: fetched.fromTag,
          toTag: fetched.toTag,
        },
        weekKey: fetched.weekKey,
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
      weekKey: fetched.weekKey,
      highlights: curated.highlights.length,
      fallback: curated.fallback,
    };
  } catch (err) {
    // Handler-level catch (cron-weekly-analytics tail precedent): a check-in
    // is ALWAYS attempted — never throw-without-heartbeat. The heartbeat is a
    // direct best-effort call (not step.run: steps may be unavailable after a
    // StepError, and a failed heartbeat must not mask the original error).
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "weekly release digest failed", installationToken);
    reportSilentFallback(new Error(redactedMsg), {
      feature: FUNCTION_NAME,
      op: "handler-top-level",
      message: redactedMsg,
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
