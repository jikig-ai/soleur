// Pure promotion library for cron-content-publisher (Phase 1).
//
// NO I/O — every function here is deterministic and unit-testable. The publisher
// cron (cron-content-publisher.ts) wires these against the ephemeral clone's
// filesystem; keeping the logic pure lets the slot math, readiness gate, and the
// targeted-mutation contract be pinned without standing up a git workspace.
//
// Frontmatter semantics mirror scripts/content-publisher.sh verbatim so a file
// this lib schedules is a file the bash publisher will post:
//   - field parsing = the awk `parse_frontmatter` + `get_frontmatter_field`
//     contract (only read status/publish_date/channels lines; never split the
//     whole block on ':' — learning 2026-04-28-awk-field-split-on-colon).
//   - channel→section = channel_to_section() (:178).
//   - Liquid-marker rejection = validate_no_liquid_markers() (:111).
//   - "non-empty mapped section" = extract_section() (:192) meaningful-content.
//
// The mutation (applyPromotion) is a TARGETED line replacement, NOT a
// gray-matter round-trip — matter.stringify coerces/reorders YAML 1.1 dates
// (learning 2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap).

// =============================================================================
// Constants
// =============================================================================

/** Rolling window (days) over which drafts are assigned to Tue/Thu slots. */
export const HORIZON_DAYS = 28;

/** Promotable weekdays by getUTCDay: Tuesday=2, Thursday=4. */
export const PROMOTION_WEEKDAYS = [2, 4] as const;

/**
 * Maps a frontmatter channel token to its body section heading. Mirrors
 * content-publisher.sh channel_to_section() (:178). Unknown channels (blog,
 * hackernews, indiehackers, reddit, …) have no local section — they return
 * undefined and never satisfy the "non-empty mapped section" gate.
 */
const CHANNEL_TO_SECTION: Record<string, string> = {
  discord: "Discord",
  x: "X/Twitter Thread",
  "linkedin-personal": "LinkedIn Personal",
  "linkedin-company": "LinkedIn Company Page",
  bluesky: "Bluesky",
};

// =============================================================================
// Types
// =============================================================================

export interface ParsedFrontmatter {
  status?: string;
  publishDate?: string;
  channels: string[];
}

export interface PromotionInput {
  path: string;
  raw: string;
}

export interface PlannedPromotion {
  path: string;
  publishDate: string;
}

// =============================================================================
// Frontmatter parsing
// =============================================================================

/** Split raw file into its frontmatter block and body (bytes after 2nd `---`). */
export function splitFrontmatter(raw: string): { frontmatter: string; body: string } {
  const lines = raw.split("\n");
  if (lines[0]?.trim() !== "---") return { frontmatter: "", body: raw };
  let end = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === "---") {
      end = i;
      break;
    }
  }
  if (end === -1) return { frontmatter: "", body: raw };
  return {
    frontmatter: lines.slice(1, end).join("\n"),
    body: lines.slice(end + 1).join("\n"),
  };
}

/** Strip a single pair of surrounding double quotes (awk `sed 's/^"..."$/\1/'`). */
function stripQuotes(v: string): string {
  const m = v.match(/^"(.*)"$/);
  return m ? m[1] : v;
}

/**
 * Read status/publish_date/channels from a content file's frontmatter. Only
 * those three field lines are inspected — a title containing ':' can never
 * corrupt a field (learning 2026-04-28-awk-field-split-on-colon).
 */
export function parseContentFrontmatter(raw: string): ParsedFrontmatter {
  const { frontmatter } = splitFrontmatter(raw);
  const result: ParsedFrontmatter = { channels: [] };
  if (!frontmatter) return result;

  for (const line of frontmatter.split("\n")) {
    const field = (name: string): string | undefined => {
      // Anchor on the field name so `status:` never matches a title's inline
      // "status:" text; the whole rest of the line is the value.
      const m = line.match(new RegExp(`^${name}:\\s*(.*)$`));
      return m ? stripQuotes(m[1].trimEnd()) : undefined;
    };
    const status = field("status");
    if (status !== undefined) result.status = status;
    const publishDate = field("publish_date");
    if (publishDate !== undefined) result.publishDate = publishDate;
    const channels = field("channels");
    if (channels !== undefined) {
      result.channels = channels
        .split(",")
        .map((c) => c.trim())
        .filter((c) => c.length > 0);
    }
  }
  return result;
}

// =============================================================================
// Readiness gate
// =============================================================================

/** Any Liquid/Jinja marker in the body → not publishable (:111). */
function hasLiquidMarker(body: string): boolean {
  return (
    body.includes("{{") ||
    body.includes("}}") ||
    body.includes("{%") ||
    body.includes("%}")
  );
}

/**
 * Extract a `## heading` section's meaningful content. Mirrors
 * content-publisher.sh extract_section() (:192): lines between the heading and
 * the next `## ` (or EOF), minus `---` rules and leading blanks, with the
 * "Not scheduled for" placeholder treated as empty.
 */
function extractSection(body: string, heading: string): string {
  const lines = body.split("\n");
  const collected: string[] = [];
  let found = false;
  for (const line of lines) {
    if (line.startsWith("## ")) {
      const trimmed = line.replace(/\s+$/, "");
      if (trimmed === `## ${heading}`) {
        found = true;
        continue;
      }
      if (found) break;
    }
    if (found) collected.push(line);
  }
  const noRules = collected.filter((l) => l.trim() !== "---");
  const content = noRules.join("\n").replace(/^\s*\n/, "").trim();
  if (content.includes("Not scheduled for")) return "";
  return content;
}

/** True if at least one declared, known channel maps to a non-empty section. */
function hasNonEmptyMappedSection(channels: string[], body: string): boolean {
  return channels.some((ch) => {
    const heading = CHANNEL_TO_SECTION[ch];
    if (!heading) return false;
    return extractSection(body, heading).length > 0;
  });
}

/**
 * A draft is promotable iff: status === "draft", ≥1 channel declared, the body
 * carries no unrendered Liquid marker, AND ≥1 declared channel has a non-empty
 * mapped section (else the publisher would flip it to `published` while posting
 * nothing — the silent-nothing trap). Excludes parked/stale/published.
 */
export function isReadyDraft(parsed: ParsedFrontmatter, body: string): boolean {
  if (parsed.status !== "draft") return false;
  if (parsed.channels.length === 0) return false;
  if (hasLiquidMarker(body)) return false;
  if (!hasNonEmptyMappedSection(parsed.channels, body)) return false;
  return true;
}

// =============================================================================
// Slot math
// =============================================================================

function toISODate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/**
 * Enumerate `YYYY-MM-DD` for weekday ∈ {Tue=2, Thu=4} from `from` INCLUSIVE
 * through `from + horizonDays` (inclusive), skipping any date in `occupied`.
 * Deterministic and UTC-based (getUTCDay).
 */
export function nextTueThuSlots(
  from: Date,
  occupied: Set<string>,
  horizonDays: number,
): string[] {
  const slots: string[] = [];
  const start = Date.UTC(
    from.getUTCFullYear(),
    from.getUTCMonth(),
    from.getUTCDate(),
  );
  const dayMs = 24 * 60 * 60 * 1000;
  for (let i = 0; i <= horizonDays; i++) {
    const d = new Date(start + i * dayMs);
    if (!(PROMOTION_WEEKDAYS as readonly number[]).includes(d.getUTCDay())) {
      continue;
    }
    const iso = toISODate(d);
    if (occupied.has(iso)) continue;
    slots.push(iso);
  }
  return slots;
}

// =============================================================================
// Planning
// =============================================================================

/**
 * Assign ready drafts (deterministic filename-asc order) to the next free
 * Tue/Thu slots within the horizon. Stops when either the ready drafts or the
 * horizon slots are exhausted — a backlog larger than the horizon drains across
 * subsequent daily runs as the window rolls (never a permanent per-draft skip).
 */
export function planPromotions(args: {
  files: PromotionInput[];
  today: Date;
  occupied: Set<string>;
  horizonDays: number;
}): PlannedPromotion[] {
  const { files, today, occupied, horizonDays } = args;
  const ready = files
    .filter((f) => {
      const parsed = parseContentFrontmatter(f.raw);
      const { body } = splitFrontmatter(f.raw);
      return isReadyDraft(parsed, body);
    })
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));

  const slots = nextTueThuSlots(today, occupied, horizonDays);
  const plan: PlannedPromotion[] = [];
  for (let i = 0; i < ready.length && i < slots.length; i++) {
    plan.push({ path: ready[i].path, publishDate: slots[i] });
  }
  return plan;
}

// =============================================================================
// Mutation
// =============================================================================

/**
 * Promote a draft's frontmatter via TARGETED line replacement: flip
 * `status: draft` → `status: scheduled` and rewrite `publish_date:` to the
 * assigned date, UNQUOTED (matching the corpus convention `publish_date:
 * 2026-05-14`). Every other byte is preserved. Idempotent: a file that is not
 * `status: draft` is returned unchanged (load-bearing for Inngest replay and
 * the daily re-scan — learning 2026-06-14-inngest-consolidate-write-and-commit).
 */
export function applyPromotion(raw: string, publishDate: string): string {
  // Guard first: only a `status: draft` line makes this file promotable. Absent
  // it (already scheduled, or any other status) the call is a pure no-op.
  if (!/^status: draft$/m.test(raw)) return raw;
  return raw
    .replace(/^publish_date:.*$/m, `publish_date: ${publishDate}`)
    .replace(/^status: draft$/m, "status: scheduled");
}
