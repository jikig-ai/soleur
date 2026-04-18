// Allowlist-based prop sanitization + log sanitization for
// /api/analytics/track. Sibling module per cq-nextjs-route-files-http-only-exports.

import { sanitizeForLog } from "@/lib/log-sanitize";

// Adding a key requires security review — keep this module as the single chokepoint.
const ALLOWED_PROP_KEYS = new Set<string>(["path"]);

const MAX_PROP_STRING_LEN = 200;
// Cap the dropped-key log to prevent log flooding when an attacker crafts
// props with thousands of random keys.
const MAX_DROPPED_KEYS_LOGGED = 20;

// ReDoS bound: scrub regexes run in O(n) per the character classes below,
// but we still hard-cap input length before the regex engine sees it. The
// cap is 2× the output cap so a worst-case email straddling the output
// boundary still scrubs cleanly. Any input longer than this is truncated
// pre-scrub — an attacker cannot force the engine to walk an unbounded
// string.
const MAX_SCRUB_INPUT_LEN = MAX_PROP_STRING_LEN * 2;

export type ScrubPatternName = "email" | "uuid" | "id";

// Historical backlog and dashboard audit: see
// knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md and
// plausible-dashboard-filter-audit.md.
//
// Scrub patterns for the `path` prop (#2462). Ordered: email first (unique
// `@` anchor), then any UUID shape, then 6+ digit runs. Each entry is
// applied with a single `.replace()` — no `.test()` gate — because `/g`
// regexes carry `lastIndex` state and alternating with `.test()` is a
// latent footgun (PR #2462 review P1). `.replace()` internally resets
// `lastIndex` on each call, so this shape is reuse-safe.
//
// Email regex:
//   [^\s/@]+        local part — no whitespace, no slashes, no literal @.
//                   Also rejects NBSP/tab bypasses that a bare `\S` would
//                   let through since `\s` includes those.
//   (?:@|%40)       literal or percent-encoded @ — catches buggy callers
//                   that encode path segments.
//   [^\s/@]+\.      domain label + dot anchor.
//   [^\s/@]+        top-level domain.
// Slashes are excluded on both sides so the match stays inside one path
// segment — `\S+@\S+\.\S+` would greedy-match across `/` and collapse the
// whole path.
//
// UUID regex: any 8-4-4-4-12 hex with optional percent-encoded hyphens
// (`%2D`). Intentionally NOT restricted to v4 — v1 UUIDs contain MAC +
// timestamp (stronger PII than v4) and must not be allowed to leak
// through a "v4-only" narrow match. The dashed-hex shape is never a
// legitimate path token.
//
// Digit regex: 6+ consecutive decimal digits. Dates (`2026-04-17`) and
// versions (`v12.4.1`) pass through because hyphens/dots split runs to
// ≤4 digits. Rare 6+-digit path slugs are the documented trade-off
// (brainstorm §"Key Decisions").
const SCRUB_PATTERNS: ReadonlyArray<{
  name: ScrubPatternName;
  re: RegExp;
  sentinel: string;
}> = [
  {
    name: "email",
    re: /[^\s/@]+(?:@|%40)[^\s/@]+\.[^\s/@]+/gi,
    sentinel: "[email]",
  },
  {
    name: "uuid",
    re: /[0-9a-f]{8}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{12}/gi,
    sentinel: "[uuid]",
  },
  { name: "id", re: /\d{6,}/g, sentinel: "[id]" },
];

function scrubPath(value: string): {
  clean: string;
  scrubbed: ScrubPatternName[];
} {
  // Length-bound BEFORE regex to cut ReDoS surface; the post-scrub slice
  // (MAX_PROP_STRING_LEN) still applies in the caller. Sentinels are
  // shorter than their originals so this never splits a completed match.
  const bounded =
    value.length > MAX_SCRUB_INPUT_LEN
      ? value.slice(0, MAX_SCRUB_INPUT_LEN)
      : value;
  // Run the log-safe pass first so CRLF / U+2028 / U+2029 / DEL cannot
  // reach Plausible's dashboard (or downstream CSV exports, which treat
  // LS/PS as row breaks — log injection into the analytics pipeline, not
  // just app logs).
  let out = sanitizeForLog(bounded);
  const scrubbed: ScrubPatternName[] = [];
  for (const { name, re, sentinel } of SCRUB_PATTERNS) {
    const next = out.replace(re, sentinel);
    if (next !== out) {
      scrubbed.push(name);
      out = next;
    }
  }
  return { clean: out, scrubbed };
}

export function sanitizeProps(
  props: Record<string, unknown> | undefined,
): {
  clean: Record<string, unknown>;
  dropped: string[];
  scrubbed: ScrubPatternName[];
} {
  if (!props) return { clean: {}, dropped: [], scrubbed: [] };
  const clean: Record<string, unknown> = {};
  const dropped: string[] = [];
  let scrubbedOut: ScrubPatternName[] = [];
  for (const [k, v] of Object.entries(props)) {
    if (!ALLOWED_PROP_KEYS.has(k)) {
      if (dropped.length < MAX_DROPPED_KEYS_LOGGED) dropped.push(k);
      continue;
    }
    if (k === "path" && typeof v === "string") {
      // Scrub BEFORE slice (FR4): emails can extend past 200 chars, and
      // slicing first would leak a partial pattern. scrubPath already
      // length-bounds to MAX_SCRUB_INPUT_LEN to cap regex runtime.
      const { clean: scrubbedVal, scrubbed } = scrubPath(v);
      scrubbedOut = scrubbed;
      clean[k] = scrubbedVal.slice(0, MAX_PROP_STRING_LEN);
    } else {
      clean[k] = typeof v === "string" ? v.slice(0, MAX_PROP_STRING_LEN) : v;
    }
  }
  return { clean, dropped, scrubbed: scrubbedOut };
}

// Re-export the shared log sanitizer. Body lives in lib/log-sanitize.ts so
// rejectCsrf (in lib/auth/validate-origin.ts) shares the same regex.
export { sanitizeForLog };
