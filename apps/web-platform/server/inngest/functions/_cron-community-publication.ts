// #7122 — schema-constrained, handler-side publication for cron-community-monitor.
//
// The spawned agent only COLLECTS and CLASSIFIES; its single deliverable is its
// final message, a one-line compact JSON draft. This module is the only path
// from that message to a public string:
//
//   parseCommunityDraft(message)  -> closed-schema validation (integers, closed
//                                    enums; there is NO free-text field)
//   renderCommunityPublication()  -> fixed templates; model output selects
//                                    values inside them and nothing else
//   writeDigestFileContained()    -> the one committed file, written handler-side
//   upsertDigestIssue()           -> the one public issue, written handler-side
//
// One metrics table (COMMUNITY_METRICS) drives the schema, the renderer and the
// example embedded in the agent prompt, so a key added in one place appears in
// all three. The schema bounds STRUCTURE, not truth: an injection can still pick
// in-range numbers or enum members (accepted residual, see ADR-272).
//
// TRIPWIRE: the only zod constructors this module may use are the closed-domain
// ones (strict objects, enums, literals, integers, numbers, booleans, arrays). A
// source test fails on any other constructor, so a free-text field cannot be
// added without editing that test deliberately.

import { z } from "zod";
import { warnSilentFallback } from "@/server/observability";
import {
  AUDIT_SELF_REPORT_BODY_PREFIX,
  SCHEDULED_DIGEST_TITLE_PREFIX,
  isRealScheduledDigest,
} from "./_cron-shared";

// =============================================================================
// Closed vocabularies
// =============================================================================

export const COMMUNITY_PLATFORMS = [
  "discord",
  "github",
  "x",
  "bluesky",
  "linkedin",
  "hn",
] as const;
export type CommunityPlatform = (typeof COMMUNITY_PLATFORMS)[number];

export const COMMUNITY_STATUSES = ["collected", "partial", "failed", "disabled"] as const;
export type CommunityStatus = (typeof COMMUNITY_STATUSES)[number];

export const COMMUNITY_FAILURE_CAUSES = [
  "auth",
  "rate-limit",
  "timeout",
  "output-too-large",
  "script-error",
  "not-configured",
  "unknown",
] as const;
export type CommunityFailureCause = (typeof COMMUNITY_FAILURE_CAUSES)[number];

export const COMMUNITY_TOPIC_CATEGORIES = [
  "infrastructure",
  "ci-testing",
  "security",
  "product",
  "growth-marketing",
  "documentation",
  "legal-compliance",
  "community",
  "other",
] as const;
export type CommunityTopicCategory = (typeof COMMUNITY_TOPIC_CATEGORIES)[number];

/** Rendered labels. Handler constants: the only words besides numbers a reader sees. */
const PLATFORM_LABELS: Record<CommunityPlatform, string> = {
  discord: "Discord",
  github: "GitHub",
  x: "X/Twitter",
  bluesky: "Bluesky",
  linkedin: "LinkedIn",
  hn: "Hacker News",
};

const TOPIC_LABELS: Record<CommunityTopicCategory, string> = {
  infrastructure: "Infrastructure",
  "ci-testing": "CI and testing",
  security: "Security",
  product: "Product",
  "growth-marketing": "Growth and marketing",
  documentation: "Documentation",
  "legal-compliance": "Legal and compliance",
  community: "Community",
  other: "Other",
};

export const MAX_TOPICS = COMMUNITY_TOPIC_CATEGORIES.length;

/**
 * The collection window, in days. A HANDLER constant, not a draft field: the
 * collectors are invoked with a fixed 1-day window (see the prompt), so period_start,
 * period_end and the "Last 1 day" wording are derived from this and the run date, and
 * the model cannot present a number measured over one day as a week's.
 */
export const COMMUNITY_PERIOD_DAYS = 1;

/**
 * Final-message cap. The substrate truncates at the same figure (FINAL_MESSAGE_CAP_BYTES in
 * _cron-claude-eval-substrate.ts) and flags it; a parity test in cron-community-monitor.test.ts
 * pins the pair.
 */
export const COMMUNITY_FINAL_MESSAGE_MAX_BYTES = 16 * 1024;

// =============================================================================
// The metrics table (single source for schema, renderer and the prompt example)
// =============================================================================

type MetricSpec =
  | { readonly kind: "int"; readonly label: string; readonly max: number }
  | { readonly kind: "pct"; readonly label: string; readonly max: 100 };

// Caps are deliberately REALISTIC for a young open-source project, not 1e9: the
// integers are a covert encoding channel for any secret that reaches the agent's
// context, and a test asserts the total encodable bits stay under a budget.
export const COMMUNITY_METRICS = {
  discord: {
    members: { kind: "int", label: "Members", max: 99_999 },
    channels: { kind: "int", label: "Channels", max: 999 },
    messages: { kind: "int", label: "Messages", max: 99_999 },
  },
  github: {
    stars: { kind: "int", label: "Stars", max: 99_999 },
    forks: { kind: "int", label: "Forks", max: 9_999 },
    watchers: { kind: "int", label: "Watchers", max: 9_999 },
    newStargazers: { kind: "int", label: "New stargazers", max: 999 },
    commits: { kind: "int", label: "Commits", max: 999 },
    issuesTouched: { kind: "int", label: "Issues touched", max: 999 },
    pullsTouched: { kind: "int", label: "Pull requests touched", max: 999 },
    externalContributors: { kind: "int", label: "External contributors", max: 999 },
    externalInteractions: { kind: "int", label: "External interactions", max: 999 },
  },
  x: {
    followers: { kind: "int", label: "Followers", max: 999_999 },
    posts: { kind: "int", label: "Posts", max: 99_999 },
  },
  bluesky: {
    followers: { kind: "int", label: "Followers", max: 999_999 },
    posts: { kind: "int", label: "Posts", max: 99_999 },
  },
  linkedin: {
    followers: { kind: "int", label: "Followers", max: 999_999 },
    impressions: { kind: "int", label: "Impressions", max: 9_999_999 },
    likes: { kind: "int", label: "Likes", max: 99_999 },
    comments: { kind: "int", label: "Comments", max: 99_999 },
    shares: { kind: "int", label: "Shares", max: 99_999 },
    engagementRatePct: { kind: "pct", label: "Engagement rate", max: 100 },
  },
  hn: {
    mentions: { kind: "int", label: "Soleur mentions", max: 999 },
  },
} as const satisfies Record<CommunityPlatform, Record<string, MetricSpec>>;

type MetricsTable = typeof COMMUNITY_METRICS;

export type CommunityDraft = {
  platforms: {
    [P in CommunityPlatform]: {
      status: CommunityStatus;
      failureCause?: CommunityFailureCause;
      metrics: { [K in keyof MetricsTable[P]]: number };
    };
  };
  topics: { category: CommunityTopicCategory; count: number }[];
};

// Widened view used by the generic (table-driven) code below. The table is the
// source of truth, so the loops are generic and the exported type stays precise.
type AnyMetricsTable = Record<CommunityPlatform, Record<string, MetricSpec>>;
const TABLE: AnyMetricsTable = COMMUNITY_METRICS;

export const TOPIC_COUNT_MAX = 999;

// =============================================================================
// Schema
// =============================================================================

function metricSchema(spec: MetricSpec) {
  return spec.kind === "pct"
    ? z.number().min(0).max(spec.max)
    : z.int().min(0).max(spec.max);
}

function buildMetricsSchema(platform: CommunityPlatform) {
  const shape: Record<string, ReturnType<typeof metricSchema>> = {};
  for (const [key, spec] of Object.entries(TABLE[platform])) {
    shape[key] = metricSchema(spec);
  }
  return z.strictObject(shape);
}

function buildPlatformSchema(platform: CommunityPlatform) {
  return z
    .strictObject({
      status: z.enum(COMMUNITY_STATUSES),
      failureCause: z.enum(COMMUNITY_FAILURE_CAUSES).optional(),
      metrics: buildMetricsSchema(platform),
    })
    .superRefine((value, ctx) => {
      // failureCause is required iff the platform is partial/failed, forbidden
      // otherwise. Messages are never read (codes carry zod `code` + path only).
      const needsCause = value?.status === "partial" || value?.status === "failed";
      const hasCause = value?.failureCause !== undefined;
      if (needsCause !== hasCause) {
        ctx.addIssue({ code: "custom", message: "failureCause mismatch", path: ["failureCause"] });
      }
    });
}

const platformsShape = Object.fromEntries(
  COMMUNITY_PLATFORMS.map((p) => [p, buildPlatformSchema(p)]),
) as Record<CommunityPlatform, ReturnType<typeof buildPlatformSchema>>;

const topicSchema = z.strictObject({
  category: z.enum(COMMUNITY_TOPIC_CATEGORIES),
  count: z.int().min(0).max(TOPIC_COUNT_MAX),
});

const draftSchema = z.strictObject({
  platforms: z.strictObject(platformsShape),
  topics: z
    .array(topicSchema)
    .max(MAX_TOPICS)
    .superRefine((topics, ctx) => {
      const seen = new Set<string>();
      for (const t of topics) {
        if (seen.has(t.category)) {
          ctx.addIssue({ code: "custom", message: "duplicate topic category", path: [] });
          return;
        }
        seen.add(t.category);
      }
    }),
});

// =============================================================================
// Parse
// =============================================================================

export type CommunityDraftRejection = {
  ok: false;
  reason: "missing" | "oversized" | "parse" | "schema";
  codes: string[];
};
export type CommunityDraftResult =
  | { ok: true; draft: CommunityDraft }
  | CommunityDraftRejection;

// Path segments allowed into a code: only keys the schema itself defines (or an
// array index). Anything else is replaced, so no model-chosen text can ride a
// code into Sentry via the path of an issue.
const KNOWN_SEGMENTS: ReadonlySet<string> = new Set([
  "platforms",
  "topics",
  "status",
  "failureCause",
  "metrics",
  "category",
  "count",
  ...COMMUNITY_PLATFORMS,
  ...COMMUNITY_PLATFORMS.flatMap((p) => Object.keys(TABLE[p])),
]);

const MAX_CODES = 24;

function pathToCode(path: ReadonlyArray<PropertyKey>): string {
  if (path.length === 0) return "$";
  return path
    .map((seg) =>
      typeof seg === "number"
        ? String(seg)
        : typeof seg === "string" && KNOWN_SEGMENTS.has(seg)
          ? seg
          : "?",
    )
    .join(".");
}

/**
 * Validate the agent's final message against the closed draft schema.
 *
 * `codes` are `<zod code>@<schema-known path>` only. NEVER the key names of an
 * `unrecognized_keys` issue and NEVER a message: both can carry attacker text.
 */
export function parseCommunityDraft(
  finalMessage: string | undefined,
  opts: { truncated?: boolean } = {},
): CommunityDraftResult {
  if (opts.truncated === true) {
    return { ok: false, reason: "oversized", codes: ["oversized"] };
  }
  const text = typeof finalMessage === "string" ? finalMessage.trim() : "";
  // The two-character empty-string stand-in is how the substrate's tail renders a
  // result-less run; treat it as absent too.
  if (text === "" || text === '""') {
    return { ok: false, reason: "missing", codes: ["missing"] };
  }
  if (Buffer.byteLength(text, "utf8") > COMMUNITY_FINAL_MESSAGE_MAX_BYTES) {
    return { ok: false, reason: "oversized", codes: ["oversized"] };
  }
  // Exactly ONE line of compact JSON: no fence, no narration, no pretty-printing.
  if (/[\r\n]/.test(text)) {
    return { ok: false, reason: "parse", codes: ["multi-line"] };
  }
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    // The JSON.parse message echoes a slice of the input; never forward it.
    return { ok: false, reason: "parse", codes: ["invalid-json"] };
  }
  const result = draftSchema.safeParse(raw);
  if (!result.success) {
    const codes: string[] = [];
    for (const issue of result.error.issues) {
      const code = `${issue.code}@${pathToCode(issue.path)}`;
      if (!codes.includes(code)) codes.push(code);
      if (codes.length >= MAX_CODES) break;
    }
    return { ok: false, reason: "schema", codes };
  }
  return { ok: true, draft: result.data as CommunityDraft };
}

/**
 * Structural read of the final-message fields of the substrate's SpawnResult. It
 * takes only the two fields it needs (not the SpawnResult type) so this module
 * does not import the substrate, keeping the module graph acyclic and light.
 */
export function readFinalMessage(
  spawn: { finalMessage?: string; finalMessageTruncated?: boolean } | null | undefined,
): { text: string | undefined; truncated: boolean } {
  return {
    text: typeof spawn?.finalMessage === "string" ? spawn.finalMessage : undefined,
    truncated: spawn?.finalMessageTruncated === true,
  };
}

// =============================================================================
// Example draft (embedded in the prompt)
// =============================================================================

/**
 * The one-line compact JSON example the agent prompt embeds. Generated from the
 * table and the closed enums, so it cannot drift from the schema (a test feeds it
 * back through parseCommunityDraft).
 */
export function buildExampleDraftLine(): string {
  const platforms: Record<string, unknown> = {};
  for (const p of COMMUNITY_PLATFORMS) {
    const metrics: Record<string, number> = {};
    for (const key of Object.keys(TABLE[p])) metrics[key] = 0;
    platforms[p] = { status: "collected", metrics };
  }
  return JSON.stringify({
    platforms,
    topics: [{ category: "other", count: 0 }],
  });
}

// =============================================================================
// Render
// =============================================================================

export type GithubOverride = {
  status: "failed" | "partial";
  failureCause: CommunityFailureCause;
};

export type RenderOptions = {
  /** Replay-stable UTC date, YYYY-MM-DD. */
  runDate: string;
  /** `owner/name` slug, used only for the click-through links. */
  repo: string;
  /**
   * The REAL run timestamp (ISO 8601 UTC instant), the handler's replay-stable
   * `runStartedAt`. It becomes the digest's `generated_at`; a fabricated midnight
   * would mislead any consumer that reads the frontmatter.
   */
  generatedAt: string;
  /** Collector-sidecar truth: replaces the model's github metrics entirely. */
  githubOverride?: GithubOverride;
};

// The committed digest directory: defined HERE and re-exported by the handler as
// COMMUNITY_DIGEST_DIR (single definition; the handler already imports this module).
export const COMMUNITY_DIGEST_DIR_PATH = "knowledge-base/support/community/";

const RUN_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const GENERATED_AT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const REPO_RE = /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/;

function shiftDate(runDate: string, days: number): string {
  const ms = Date.parse(`${runDate}T00:00:00Z`);
  if (Number.isNaN(ms)) throw new Error("renderCommunityPublication: invalid runDate");
  return new Date(ms + days * 86_400_000).toISOString().slice(0, 10);
}

function renderValue(spec: MetricSpec, value: number): string {
  // toFixed keeps 1e-7 / 1e+21 exponent forms out of the output. Integers are
  // bounded far below the exponent threshold by their caps.
  return spec.kind === "pct" ? `${value.toFixed(1)}%` : String(value);
}

type EffectivePlatform = {
  status: CommunityStatus;
  failureCause?: CommunityFailureCause;
  metrics: Record<string, number>;
  /** The collector disagrees with (or could not confirm) the model's numbers. */
  metricsWithheld: boolean;
};

function effectivePlatform(
  draft: CommunityDraft,
  platform: CommunityPlatform,
  githubOverride: GithubOverride | undefined,
): EffectivePlatform {
  if (platform === "github" && githubOverride) {
    return {
      status: githubOverride.status,
      failureCause: githubOverride.failureCause,
      metrics: {},
      metricsWithheld: true,
    };
  }
  const p = draft.platforms[platform];
  return {
    status: p.status,
    failureCause: p.failureCause,
    metrics: p.metrics as Record<string, number>,
    // A failed or disabled platform has no meaningful numbers to show.
    metricsWithheld: p.status === "failed" || p.status === "disabled",
  };
}

function headline(platform: CommunityPlatform, eff: EffectivePlatform): string {
  if (eff.status === "disabled") return "disabled";
  if (eff.status === "failed") return `collection failed: ${eff.failureCause ?? "unknown"}`;
  if (eff.metricsWithheld) {
    return `metrics withheld: collector status not verified (${eff.failureCause ?? "unknown"})`;
  }
  const parts = Object.entries(TABLE[platform]).map(
    ([key, spec]) => `${spec.label} ${renderValue(spec, eff.metrics[key] ?? 0)}`,
  );
  const base = parts.join(", ");
  // A partial platform's numbers are shown only under an explicit label, and the
  // label says a 0 may be a metric the collector could not obtain (the schema has
  // no "absent" value, so 0 is how an unavailable metric arrives).
  return eff.status === "partial"
    ? `partial (${eff.failureCause ?? "unknown"}; a 0 may mean unavailable): ${base}`
    : base;
}

export function renderCommunityPublication(
  draft: CommunityDraft,
  opts: RenderOptions,
): { digestMarkdown: string; issueTitle: string; issueBody: string } {
  const { runDate, repo, githubOverride, generatedAt } = opts;
  if (!RUN_DATE_RE.test(runDate)) {
    throw new Error("renderCommunityPublication: runDate must be YYYY-MM-DD");
  }
  if (!REPO_RE.test(repo)) {
    throw new Error("renderCommunityPublication: repo must be owner/name");
  }
  if (typeof generatedAt !== "string" || !GENERATED_AT_RE.test(generatedAt) || Number.isNaN(Date.parse(generatedAt))) {
    throw new Error("renderCommunityPublication: generatedAt must be an ISO UTC instant");
  }
  const periodDays = COMMUNITY_PERIOD_DAYS;
  const periodStart = shiftDate(runDate, -periodDays);
  const issuesUrl = `https://github.com/${repo}/issues`;
  const pullsUrl = `https://github.com/${repo}/pulls`;
  const digestUrl = `https://github.com/${repo}/blob/main/${COMMUNITY_DIGEST_DIR_PATH}${runDate}-digest.md`;
  const dayWord = periodDays === 1 ? "day" : "days";

  const effective = Object.fromEntries(
    COMMUNITY_PLATFORMS.map((p) => [p, effectivePlatform(draft, p, githubOverride)]),
  ) as Record<CommunityPlatform, EffectivePlatform>;

  const summaryRows = COMMUNITY_PLATFORMS.map(
    (p) => `| ${PLATFORM_LABELS[p]} | ${effective[p].status} | ${headline(p, effective[p])} |`,
  );
  const summaryTable = [
    "| Platform | Status | Headline |",
    "|----------|--------|----------|",
    ...summaryRows,
  ].join("\n");

  const topicLines = draft.topics.map((t) => `- ${TOPIC_LABELS[t.category]}: ${t.count}`);
  const topicsBlock =
    topicLines.length > 0 ? topicLines.join("\n") : "No topic activity was classified this period.";

  const digestMarkdown = [
    "---",
    `period_start: ${periodStart}`,
    `period_end: ${runDate}`,
    `generated_at: ${generatedAt}`,
    "---",
    "",
    `# Community Digest - ${runDate}`,
    "",
    "## Period",
    "",
    `Last ${periodDays} ${dayWord}, ${periodStart} to ${runDate}.`,
    "",
    "## Activity Summary",
    "",
    summaryTable,
    "",
    "## Trending Topics",
    "",
    topicsBlock,
    "",
    "## Follow-up",
    "",
    "Counts only. Names, quotes and message text are not recorded in this digest.",
    `Review inbound items: ${issuesUrl} and ${pullsUrl}`,
    "",
  ].join("\n");

  const issueTitle = `${SCHEDULED_DIGEST_TITLE_PREFIX} ${runDate}`;

  // Must never start with AUDIT_SELF_REPORT_BODY_PREFIX: the dedup predicate keys
  // on it to tell the FAILED audit stub from a real digest.
  const issueBody = [
    `Daily community digest for ${runDate} (last ${periodDays} ${dayWord}).`,
    "",
    summaryTable,
    "",
    "Topics",
    "",
    topicsBlock,
    "",
    `Digest file: ${digestUrl}`,
    `Inbound items: ${issuesUrl} and ${pullsUrl}`,
    "",
  ].join("\n");
  if (issueBody.startsWith(AUDIT_SELF_REPORT_BODY_PREFIX)) {
    throw new Error("renderCommunityPublication: issue body collides with the audit prefix");
  }

  return { digestMarkdown, issueTitle, issueBody };
}

// =============================================================================
// Contained digest write
// =============================================================================

/**
 * Write the rendered digest into the workspace without following links.
 *
 * Every ancestor under `spawnCwd` is lstat'ed and a symlink (or non-directory) is
 * refused; an existing target is unlinked (never written through), and the file is
 * created with `wx` so a racing link cannot be followed either. `node:fs` is
 * imported lazily: a top-level binding would land in the static graph of every
 * sibling test that mocks node builtins with partial factories.
 */
export async function writeDigestFileContained(
  spawnCwd: string,
  relPath: string,
  text: string,
): Promise<void> {
  const { lstat, mkdir, unlink, writeFile } = await import("node:fs/promises");
  const { join, isAbsolute } = await import("node:path");

  const segments = relPath.split("/");
  if (
    relPath === "" ||
    isAbsolute(relPath) ||
    segments.some((s) => s === "" || s === "." || s === "..")
  ) {
    throw new Error("writeDigestFileContained: relPath must be a clean relative path");
  }

  let current = spawnCwd;
  for (const segment of segments.slice(0, -1)) {
    current = join(current, segment);
    let st;
    try {
      st = await lstat(current);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
      try {
        await mkdir(current);
      } catch (mkErr) {
        if ((mkErr as NodeJS.ErrnoException).code !== "EEXIST") throw mkErr;
      }
      st = await lstat(current);
    }
    if (st.isSymbolicLink() || !st.isDirectory()) {
      throw new Error("writeDigestFileContained: ancestor is not a plain directory");
    }
  }

  const target = join(current, segments[segments.length - 1]);
  let existing;
  try {
    existing = await lstat(target);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
  }
  if (existing) {
    if (existing.isDirectory()) {
      throw new Error("writeDigestFileContained: target is a directory");
    }
    // unlink removes a symlink itself, never the file it points at.
    await unlink(target);
  }
  await writeFile(target, text, { flag: "wx", mode: 0o644 });
}

// =============================================================================
// Issue upsert
// =============================================================================

/** Minimal structural view of the Octokit `request` entry point. */
export type CommunityOctokit = {
  request(route: string, params?: Record<string, unknown>): Promise<{ data: unknown }>;
};

export const COMMUNITY_DIGEST_MILESTONE = "Post-MVP / Later" as const;

const API_VERSION_HEADERS = { "X-GitHub-Api-Version": "2022-11-28" } as const;
const UPSERT_MAX_ATTEMPTS = 3;
/** Page size of the digest-for-today read. Equal to the pre-spawn dedup read's (see findExisting). */
export const DIGEST_LIST_PAGE_SIZE = 10;
const UPSERT_BASE_DELAY_MS = 1_000;

type IssueRow = {
  number?: number;
  title?: string | null;
  body?: string | null;
  pull_request?: unknown;
  user?: { type?: string | null; login?: string | null } | null;
};

function isRetryable(err: unknown): boolean {
  const status = (err as { status?: number } | null)?.status;
  return typeof status === "number" && (status >= 500 || status === 429);
}

async function sleepMs(ms: number): Promise<void> {
  if (ms <= 0) return;
  await new Promise<void>((resolve) => setTimeout(resolve, ms));
}

export async function upsertDigestIssue(args: {
  octokit: CommunityOctokit;
  owner: string;
  repo: string;
  runDate: string;
  title: string;
  body: string;
  label: string;
  milestoneTitle: typeof COMMUNITY_DIGEST_MILESTONE;
  cronName: string;
  /**
   * Author login of a PATCHable issue: the App's `<slug>[bot]` login. REQUIRED and
   * resolved by the caller from the authoritative source (`getAppSlug()`, GET /app),
   * never from a build-time env default: a wrong value fails open to a duplicate issue.
   */
  appLogin: string;
  /** Base backoff in ms (doubles per attempt). Tests inject 0. */
  retryDelayMs?: number;
}): Promise<{ issueNumber: number; via: "created" | "patched" }> {
  const {
    octokit,
    owner,
    repo,
    runDate,
    title,
    body,
    label,
    milestoneTitle,
    cronName,
    appLogin,
    retryDelayMs = UPSERT_BASE_DELAY_MS,
  } = args;

  const canonicalTitle = `${SCHEDULED_DIGEST_TITLE_PREFIX} ${runDate}`;
  if (title !== canonicalTitle) {
    throw new Error("upsertDigestIssue: title is not the canonical digest title");
  }

  // FAIL-CLOSED: a read error propagates. Falling open to a create here would
  // double-file whenever the list read hiccups.
  //
  // READ SHAPE: label-filtered, state=all (a closed digest is still today's),
  // newest-first, one page of DIGEST_LIST_PAGE_SIZE. The pre-spawn dedup read
  // (digestIssueExistsForDate in _cron-shared.ts) uses the SAME page size and order,
  // so both ask the same question of the same window. The ONE difference is
  // deliberate: that read is author-agnostic (any real digest for today means "a
  // digest exists", and it fails OPEN), while this one only accepts a PATCH target
  // authored by the App bot (so a human-opened look-alike is never overwritten) and
  // fails CLOSED.
  let loginMismatchWarned = false;
  const findExisting = async (): Promise<number | undefined> => {
    const res = await octokit.request("GET /repos/{owner}/{repo}/issues", {
      owner,
      repo,
      state: "all",
      labels: label,
      sort: "created",
      direction: "desc",
      per_page: DIGEST_LIST_PAGE_SIZE,
      headers: API_VERSION_HEADERS,
    });
    if (!Array.isArray(res.data)) {
      throw new Error("upsertDigestIssue: issues list returned a non-array body");
    }
    const rows = res.data as IssueRow[];
    // Everything that qualifies EXCEPT the author's login.
    const candidates = rows.filter(
      (i) =>
        !i.pull_request &&
        i.user?.type === "Bot" &&
        i.title === canonicalTitle &&
        isRealScheduledDigest(
          { title: i.title, body: i.body },
          runDate,
          SCHEDULED_DIGEST_TITLE_PREFIX,
        ) &&
        Number.isInteger(i.number) &&
        (i.number as number) > 0,
    );
    const match = candidates.find((i) => i.user?.login === appLogin);
    if (match === undefined && candidates.length > 0 && !loginMismatchWarned) {
      // A Bot-authored canonical digest exists for today but under a login other than
      // the one we expect: the expected login is stale (App rename, slug drift) and
      // this run is about to create a duplicate. Say so instead of doing it silently.
      loginMismatchWarned = true;
      warnSilentFallback(new Error("digest issue author login does not match the App bot login"), {
        feature: cronName,
        op: "community-publication-bot-login-mismatch",
        message:
          "A bot-authored digest for today exists under a different login than the resolved App login; a duplicate will be created",
        extra: { fn: cronName, issueNumber: candidates[0].number },
      });
    }
    return match?.number;
  };

  let milestoneNumber: number | undefined;
  let milestoneResolved = false;
  const resolveMilestone = async (): Promise<number | undefined> => {
    if (milestoneResolved) return milestoneNumber;
    milestoneResolved = true;
    try {
      const res = await octokit.request("GET /repos/{owner}/{repo}/milestones", {
        owner,
        repo,
        state: "open",
        per_page: 100,
        headers: API_VERSION_HEADERS,
      });
      const rows = Array.isArray(res.data) ? (res.data as { number?: number; title?: string }[]) : [];
      const hit = rows.find((m) => m.title === milestoneTitle && Number.isInteger(m.number));
      milestoneNumber = hit?.number;
    } catch (err) {
      warnSilentFallback(err, {
        feature: cronName,
        op: "community-publication-milestone-lookup-failed",
        message: "Milestone lookup failed; creating the digest issue without a milestone",
        extra: { fn: cronName, milestoneTitle },
      });
      return undefined;
    }
    if (milestoneNumber === undefined) {
      warnSilentFallback(new Error("milestone not found among open milestones"), {
        feature: cronName,
        op: "community-publication-milestone-missing",
        message: "Open milestone not found; creating the digest issue without a milestone",
        extra: { fn: cronName, milestoneTitle },
      });
    }
    return milestoneNumber;
  };

  let lastErr: unknown;
  for (let attempt = 1; attempt <= UPSERT_MAX_ATTEMPTS; attempt++) {
    try {
      // Re-reading on every attempt means a POST that 5xx'd after the server
      // created the issue is found (and PATCHed) instead of duplicated.
      const existing = await findExisting();
      if (existing !== undefined) {
        // body ONLY: never state, title, labels or assignees; never reopens.
        await octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
          owner,
          repo,
          issue_number: existing,
          body,
          headers: API_VERSION_HEADERS,
        });
        return { issueNumber: existing, via: "patched" };
      }
      const milestone = await resolveMilestone();
      const created = await octokit.request("POST /repos/{owner}/{repo}/issues", {
        owner,
        repo,
        title,
        body,
        labels: [label],
        ...(milestone !== undefined ? { milestone } : {}),
        headers: API_VERSION_HEADERS,
      });
      const number = (created.data as { number?: number } | null)?.number;
      if (!Number.isInteger(number) || (number as number) <= 0) {
        throw new Error("upsertDigestIssue: create response carried no issue number");
      }
      return { issueNumber: number as number, via: "created" };
    } catch (err) {
      lastErr = err;
      if (!isRetryable(err) || attempt === UPSERT_MAX_ATTEMPTS) throw err;
      await sleepMs(retryDelayMs * 2 ** (attempt - 1));
    }
  }
  throw lastErr;
}

/**
 * PATCH an issue's body and nothing else (never state, title, labels or
 * assignees, so a closed issue stays closed). Used by the handler to replace the
 * rendered digest with the fixed "not committed" notice when the commit does not
 * land. Bounded retry on 5xx/429; any other failure throws.
 */
export async function patchIssueBody(args: {
  octokit: CommunityOctokit;
  owner: string;
  repo: string;
  issueNumber: number;
  body: string;
  /** Base backoff in ms (doubles per attempt). Tests inject 0. */
  retryDelayMs?: number;
}): Promise<void> {
  const { octokit, owner, repo, issueNumber, body, retryDelayMs = UPSERT_BASE_DELAY_MS } = args;
  if (!Number.isInteger(issueNumber) || issueNumber <= 0) {
    throw new Error("patchIssueBody: issueNumber must be a positive integer");
  }
  for (let attempt = 1; ; attempt++) {
    try {
      await octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
        owner,
        repo,
        issue_number: issueNumber,
        body,
        headers: API_VERSION_HEADERS,
      });
      return;
    } catch (err) {
      if (!isRetryable(err) || attempt >= UPSERT_MAX_ATTEMPTS) throw err;
      await sleepMs(retryDelayMs * 2 ** (attempt - 1));
    }
  }
}
