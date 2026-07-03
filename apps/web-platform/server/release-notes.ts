// Shared release-notes fetch + sanitize (#5958). The single source of truth for
// the brand-critical PII-strip + security-down-detail hygiene applied to GitHub
// release bodies — imported by BOTH the weekly Discord digest cron
// (cron-weekly-release-digest.ts) and the in-app Releases page
// (/api/dashboard/releases). Extracted from the cron so the security regex has
// exactly one definition (Kieran plan-review) and so the route bundle never
// pulls the Inngest client.
//
// Token minting reuses the existing least-privilege GitHub App path
// (mintInstallationToken → generateInstallationToken, contents:read scoped to
// the soleur repo) per hr-github-app-auth-not-pat — NOT a PAT.

import {
  REPO_NAME,
  REPO_OWNER,
  mintInstallationToken,
} from "@/server/inngest/functions/_cron-shared";
import { reportSilentFallback } from "@/server/observability";

// --- Sanitize family (moved verbatim from cron-weekly-release-digest.ts) -----

// Word-boundaried: bare `rce` matches "sou-rce-" as a substring and would
// silently down-detail every release mentioning "source".
const SECURITY_DOWN_DETAIL_RE =
  /\bsecurity\b|vulnerab|\bcve\b|\bxss\b|\brce\b|\bssrf\b|\bcsrf\b|\binjection\b|privilege escalation|auth bypass|\bexploit\b|\b0day\b|deserializ|path traversal|prototype pollution|sandbox escape/i;
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const HANDLE_RE = /@[A-Za-z0-9][A-Za-z0-9-]*/g;
const CO_AUTHORED_RE = /^\s*co-authored-by:.*$/gim;

const MAX_RAW_BODY_CHARS = 10_000;
const MAX_RELEASE_BODY_CHARS = 1500;
const MAX_DERIVED_TITLE_CHARS = 150;

export interface RawGithubRelease {
  tag_name: string;
  name?: string | null;
  body?: string | null;
  published_at: string;
  draft: boolean;
  prerelease: boolean;
  html_url?: string;
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

// Release names for plugin/web releases are usually just the version tag
// (gh release create defaults the title to the tag), so a bare-version name
// carries zero reader value. When the name is version-shaped, the first
// changelog line (the squashed PR title) is the real content.
const VERSION_ONLY_TITLE_RE = /^[a-z-]*v?\d[\w.-]*$/i;

// The card TITLE renders in a plain <h2>, NOT through the markdown renderer, so
// any inline markdown in a derived title (a PR-title changelog line) would show
// literal `**`/backticks (#5958 follow-up). Flatten it to readable plain text:
// unwrap links, drop bold/italic/code/strikethrough markers, strip a leading
// heading marker. Only `*`/`**`/double-`_` emphasis is touched — single `_` is
// left intact so identifiers like `worktree_id` survive.
function stripInlineMarkdown(s: string): string {
  return s
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1") // images/links → their text
    .replace(/`+/g, "") // inline code fences
    .replace(/\*\*(.*?)\*\*/g, "$1") // bold **x**
    .replace(/__(.*?)__/g, "$1") // bold __x__
    .replace(/~~(.*?)~~/g, "$1") // strikethrough
    .replace(/(^|[^*])\*([^*\s][^*]*?)\*/g, "$1$2") // italic *x*
    .replace(/^#{1,6}\s+/, "") // leading heading marker
    .replace(/\s+/g, " ")
    .trim();
}

// Truncate on a word boundary (never mid-word) with an ellipsis.
function truncateAtWord(s: string, max: number): string {
  if (s.length <= max) return s;
  const cut = s.slice(0, max);
  const lastSpace = cut.lastIndexOf(" ");
  return `${(lastSpace > max * 0.6 ? cut.slice(0, lastSpace) : cut).trimEnd()}…`;
}

function deriveTitle(base: string, body: string): string {
  if (!VERSION_ONLY_TITLE_RE.test(base)) return base;
  for (const raw of body.split("\n")) {
    const line = raw.trim().replace(/^[-*]\s+/, "");
    if (!line || line.startsWith("#")) continue;
    // Strip PII + inline markdown BEFORE truncating — truncation could bisect an
    // email and leave a fragment the regexes no longer match (both are idempotent).
    const derived = stripInlineMarkdown(stripPii(line)).trim();
    return derived ? truncateAtWord(derived, MAX_DERIVED_TITLE_CHARS) : base;
  }
  return base;
}

// PII-strip (author dropped; @handles, emails, Co-Authored-By lines removed —
// release bodies derive from PR-body Changelogs which embed both) + security
// down-detail (matching releases render title-only; the body is withheld so no
// generated/rendered prose can widen an exploit window) + per-release truncation.
export function sanitizeReleases(releases: RawGithubRelease[]): SanitizedRelease[] {
  return releases.map((r) => {
    // Pre-bound BEFORE regexing — bounds ReDoS exposure on a large body.
    const rawBody = (r.body ?? "").slice(0, MAX_RAW_BODY_CHARS);
    const securitySensitive = SECURITY_DOWN_DETAIL_RE.test(`${r.name ?? ""}\n${rawBody}`);
    const base = (r.name || r.tag_name).trim();
    // deriveTitle already flattens markdown; also flatten the security-case name
    // (rendered title-only) so a name with markdown never shows literal markers.
    const title = stripInlineMarkdown(
      stripPii(securitySensitive ? base : deriveTitle(base, rawBody)),
    ).trim();
    const body = securitySensitive
      ? ""
      : stripPii(rawBody).slice(0, MAX_RELEASE_BODY_CHARS);
    return { tag: r.tag_name, title, body, securitySensitive };
  });
}

// --- In-app Releases page fetch (#5958) --------------------------------------

const RELEASES_PER_PAGE = 100;
const MAX_PAGES = 5;
const DEFAULT_LIMIT = 50;
const TOKEN_MIN_LIFETIME_MS = 60_000;

/** Semver bump of a release relative to the previous one (`null` = the oldest
 *  release in the fetched window, or a tag that doesn't parse). Powers the
 *  release-type filter. */
export type ReleaseBump = "major" | "minor" | "patch" | null;

/** A single card in the in-app Releases feed. `bodyMarkdown` is ALWAYS non-empty
 *  (fallback applied) so a card never renders blank (spec-flow Gap 1+3). */
export interface ReleaseCard {
  tag: string;
  title: string;
  bodyMarkdown: string;
  publishedAt: string;
  htmlUrl: string;
  securitySensitive: boolean;
  bump: ReleaseBump;
}

function parseWebVersion(tag: string): [number, number, number] | null {
  const m = /^web-v(\d+)\.(\d+)\.(\d+)/.exec(tag);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

// Bump of `tag` relative to the next-older release `prevTag`. Web versions
// increase monotonically, so a differing segment marks the bump kind.
function computeBump(tag: string, prevTag: string | undefined): ReleaseBump {
  const cur = parseWebVersion(tag);
  const prev = prevTag ? parseWebVersion(prevTag) : null;
  if (!cur || !prev) return null;
  if (cur[0] !== prev[0]) return "major";
  if (cur[1] !== prev[1]) return "minor";
  return "patch";
}

// Web-platform releases only: anchor on the digit so plugin `v3.x` (which
// interleaves ~100 releases/week) and infra `vinngest-v*` never surface.
function isWebRelease(r: RawGithubRelease): boolean {
  return /^web-v\d/.test(r.tag_name) && !r.draft && !r.prerelease;
}

function fallbackBody(s: SanitizedRelease): string {
  if (s.body) return s.body;
  return s.securitySensitive
    ? "Security and stability improvements."
    : "Behind-the-scenes improvements and fixes.";
}

/**
 * Fetch the app's `web-v*` GitHub Releases, newest first, cleaned for display.
 *
 * Paginates until `limit` matching releases are collected OR a page cap is hit —
 * a single `per_page=100` page can be almost entirely plugin tags, so a
 * single-page fetch would silently under-fill the feed (DHH plan-review). On
 * cap-before-limit, emits `releases-page-undercount` so the shortfall is
 * observable in Sentry rather than silent.
 */
export async function fetchWebReleases(opts?: {
  limit?: number;
}): Promise<ReleaseCard[]> {
  const limit = opts?.limit ?? DEFAULT_LIMIT;
  const token = await mintInstallationToken({
    tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
    permissions: { contents: "read" },
    repositories: [REPO_NAME],
  });

  const matched: RawGithubRelease[] = [];
  let hitCap = false;
  let page = 1;
  while (matched.length < limit) {
    if (page > MAX_PAGES) {
      hitCap = true;
      break;
    }
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
    for (const r of batch) if (isWebRelease(r)) matched.push(r);
    if (batch.length < RELEASES_PER_PAGE) break; // last page — no more to fetch
    page += 1;
  }

  if (hitCap) {
    reportSilentFallback(new Error("release page cap reached before limit"), {
      feature: "releases-page",
      op: "releases-page-undercount",
      message:
        "Hit the GitHub releases page cap before collecting the requested number of web-v* releases — the in-app feed may under-fill",
      extra: { collected: matched.length, limit, pages: MAX_PAGES },
    });
  }

  const slice = matched.slice(0, limit);
  const sanitized = sanitizeReleases(slice);
  return slice.map((r, i) => {
    const s = sanitized[i];
    return {
      tag: s.tag,
      title: s.title,
      bodyMarkdown: fallbackBody(s),
      publishedAt: r.published_at,
      htmlUrl: r.html_url ?? "",
      securitySensitive: s.securitySensitive,
      // `slice` is newest-first, so the next-older release is at i+1.
      bump: computeBump(r.tag_name, slice[i + 1]?.tag_name),
    };
  });
}
