// Statutory rules contract for operator-inbox email triage.
//
// PURE + CODE-STATIC: no I/O, no env reads, no imports from other server
// modules. Inngest functions, API routes, the email detail page, and agent
// tools all import this module — keep it client-free.
//
// The registry is the single system-of-record for statutory periods: clock
// display derives from `received_at` + `dueRule` (no clock columns in the
// DB). First match wins, evaluated in pinned priority order:
//   breach > service-of-process > dsar > regulator
// Probe markers are NOT a statutory class — `matchProbeToken` handles them
// separately and the match functions never return a probe rule.
//
// Keyword sets err broad (recall over precision — a false positive costs one
// extra escalation; a false negative eats an Art. 12 clock). EN + FR
// statutory vocabulary minimum. All patterns are word-boundary anchored so
// acronyms (DSAR/RGPD/CNIL) never match inside longer words; whitespace
// inside phrases uses `\s+` (matches U+00A0 in JS). Unicode separator
// characters appear ONLY as escape sequences, never as literals
// (cq-regex-unicode-separators-escape-only).

export type StatutoryClass = "breach" | "service-of-process" | "dsar" | "regulator";

export type DueRule =
  | { kind: "hours"; hours: number; label: string }
  | { kind: "calendar-month"; label: string };

export interface StatutoryRule {
  ruleId: string;
  statutoryClass: StatutoryClass;
  senderPatterns: RegExp[];
  keywordPatterns: RegExp[];
  /** Rule only participates in the body pass (skipped by matchStatutoryMetadata). */
  bodyOnly?: boolean;
  dueRule: DueRule;
  /** Anchor into knowledge-base/legal/statutory-response-catalog.md. */
  catalogAnchor: string;
  /** 1-2 sentence plain statement of the obligation + period. */
  catalogExcerpt: string;
}

const VERIFY_INSTRUMENT_DUE: DueRule = {
  kind: "calendar-month",
  label: "verify the instrument's own deadline",
};

export const STATUTORY_RULES: readonly StatutoryRule[] = [
  {
    ruleId: "breach-art33",
    statutoryClass: "breach",
    senderPatterns: [],
    keywordPatterns: [
      /\bpersonal\s+data\s+breach\b/i,
      /\bdata\s+breach\b/i,
      /\bsecurity\s+breach\b/i,
      /\bbreach\s+notification\b/i,
      /\bbreach\s+of\s+(?:personal\s+)?data\b/i,
      /\bviolation\s+de\s+donn[eé]es\b/i,
      /\bnotification\s+de\s+violation\b/i,
      /\b(?:article|art\.?)\s*33\s+(?:of\s+the\s+|du\s+)?(?:GDPR|RGPD)\b/i,
    ],
    dueRule: {
      kind: "hours",
      hours: 72,
      label: "notify the supervisory authority within 72 hours (GDPR Art. 33)",
    },
    catalogAnchor: "statutory-response-catalog.md#breach",
    catalogExcerpt:
      "A personal data breach must be notified to the competent supervisory authority " +
      "without undue delay and, where feasible, within 72 hours of becoming aware of it " +
      "(GDPR Art. 33).",
  },
  {
    ruleId: "service-of-process",
    statutoryClass: "service-of-process",
    senderPatterns: [/\bhuissier\b/i, /\bprocess[._-]?server\b/i],
    keywordPatterns: [
      /\bservice\s+of\s+process\b/i,
      /\bsummons\b/i,
      /\bsubpoena\b/i,
      /\bwrit\s+of\s+\w+/i,
      /\bassignation\b/i,
      /\bcitation\s+[aà]\s+compara[iî]tre\b/i,
      /\blegal\s+proceedings\s+against\b/i,
      /\bcourt\s+order\b/i,
    ],
    dueRule: VERIFY_INSTRUMENT_DUE,
    catalogAnchor: "statutory-response-catalog.md#service-of-process",
    catalogExcerpt:
      "Service of legal process (summons, subpoena, assignation) carries the deadline " +
      "stated in the instrument itself — read the document and calendar that date; the " +
      "one-month default here is only a safety net.",
  },
  {
    ruleId: "dsar-art15",
    statutoryClass: "dsar",
    senderPatterns: [],
    keywordPatterns: [
      /\bdata\s+subject\s+access\s+request\b/i,
      /\bsubject\s+access\s+request\b/i,
      /\bDSARs?\b/i,
      /\baccess\s+to\s+my\s+personal\s+data\b/i,
      /\bright\s+of\s+access\b/i,
      /\bright\s+to\s+erasure\b/i,
      /\bcopy\s+of\s+(?:all\s+)?(?:my|the)\s+personal\s+data\b/i,
      /\b(?:article|art\.?)\s*15\s+(?:of\s+the\s+|du\s+)?(?:GDPR|RGPD)\b/i,
      /\bdemande\s+d['’]acc[eè]s\b/i,
      /\bdroit\s+d['’]acc[eè]s\b/i,
      /\bacc[eè]s\s+[aà]\s+mes\s+donn[eé]es\b/i,
      /\bdemande\s+d['’]effacement\b/i,
      /\bdroit\s+[aà]\s+l['’]effacement\b/i,
      /\beffacement\s+de\s+mes\s+donn[eé]es\b/i,
      /\bRGPD\b/i,
    ],
    dueRule: {
      kind: "calendar-month",
      label: "respond within one calendar month (GDPR Art. 12(3))",
    },
    catalogAnchor: "statutory-response-catalog.md#dsar",
    catalogExcerpt:
      "A data subject access (or erasure) request must be answered without undue delay " +
      "and at the latest within one calendar month of receipt (GDPR Art. 12(3)); the " +
      "clock runs from the day the request arrived.",
  },
  {
    ruleId: "regulator-contact",
    statutoryClass: "regulator",
    senderPatterns: [/@cnil\.fr\b/i, /@ico\.org\.uk\b/i, /@edpb\.europa\.eu\b/i],
    keywordPatterns: [
      /\bCNIL\b/i,
      /\bsupervisory\s+authority\b/i,
      /\bdata\s+protection\s+authority\b/i,
      /\bdata\s+protection\s+commission(?:er)?\b/i,
      // Case-sensitive on purpose: lowercase "ico" appears in filenames
      // (favicon.ico) and ordinary words; the regulator writes "ICO".
      /\bICO\b/,
      /\bautorit[eé]\s+de\s+contr[oô]le\b/i,
      /\bmise\s+en\s+demeure\b/i,
    ],
    dueRule: VERIFY_INSTRUMENT_DUE,
    catalogAnchor: "statutory-response-catalog.md#regulator",
    catalogExcerpt:
      "Correspondence from a supervisory authority (CNIL, ICO, any EU DPA) states its " +
      "own response period — verify the deadline in the letter itself; treat one month " +
      "as the outer default while you confirm it.",
  },
];

// Standing not-legal-advice framing for statutory reminders (#6798).
//
// #6781 made the statutory backstop RELIABLE, and a reliable computed reminder
// invites the recipient to treat it as authoritative and stop tracking their
// own clock (detrimental reliance). The reminder is a best-effort backstop
// computed from `received_at` + the registry `dueRule` — it is NOT the operator's
// legal deadline of record, and for at least one rule (`breach-art33`, whose 72h
// runs from AWARENESS, not receipt) the computed date can be LATER than the true
// statutory deadline. Per #6798, the copy that the operator now depends on must
// say so. Each rule's `catalogExcerpt` states its own clock origin verbatim
// (e.g. "within 72 hours of becoming aware of it", "within one calendar month of
// receipt"); render THAT alongside this standing notice rather than encoding a
// second, drift-prone clock-origin field.
//
// Final wording is CLO-reviewed before ship (#6798 acceptance bullet 3).
export const NOT_LEGAL_ADVICE_NOTICE =
  "This is an automated reminder, not legal advice. The date shown is computed " +
  "from when this item was received and is a best-effort backstop — you remain " +
  "responsible for confirming the real deadline. Some clocks (for example a data " +
  "breach) run from a different starting point than the one used here.";

export const PROBE_MARKER_PREFIX = "SOLEUR-PROBE-";

const PROBE_TOKEN_PATTERN = new RegExp(
  PROBE_MARKER_PREFIX +
    "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})",
);

/**
 * Extracts the uuid token from a `SOLEUR-PROBE-<uuid>` subject marker.
 * Returns null when the marker is absent or carries no well-formed token.
 * Probe handling is deliberately separate from the statutory registry —
 * probes must short-circuit before the LLM and never produce statutory rows.
 */
export function matchProbeToken(subject: string): string | null {
  const match = PROBE_TOKEN_PATTERN.exec(subject);
  return match ? match[1] : null;
}

// Filenames glue words with `_`/`-`/`.` (DSAR_request.pdf), which defeats
// `\b` and `\s+` phrase patterns. Build a separator-normalized variant and
// test patterns against both forms.
function separatorNormalized(value: string): string {
  return value.replace(/[_.\-]+/g, " ");
}

function anyPatternMatches(patterns: RegExp[], haystacks: string[]): boolean {
  return patterns.some((pattern) => haystacks.some((haystack) => pattern.test(haystack)));
}

/**
 * Metadata pass: subject + sender + already-captured attachment filenames.
 * Runs before any body fetch so the statutory fast-path never depends on it.
 * First match in registry priority order wins. Never returns a probe rule.
 */
export function matchStatutoryMetadata(input: {
  subject: string;
  sender: string;
  attachmentFilenames?: string[];
}): StatutoryRule | null {
  const keywordHaystacks: string[] = [input.subject, separatorNormalized(input.subject)];
  for (const filename of input.attachmentFilenames ?? []) {
    keywordHaystacks.push(filename, separatorNormalized(filename));
  }

  for (const rule of STATUTORY_RULES) {
    if (rule.bodyOnly) continue;
    if (anyPatternMatches(rule.senderPatterns, [input.sender])) return rule;
    if (anyPatternMatches(rule.keywordPatterns, keywordHaystacks)) return rule;
  }
  return null;
}

/**
 * Body keyword pass. Callers should pass plain text — run HTML-only bodies
 * through `normalizeEmailHtml` first (entities, soft hyphens, and
 * tag-interleaving otherwise split keywords). Never returns a probe rule.
 */
export function matchStatutoryBody(bodyText: string): StatutoryRule | null {
  const haystacks = [bodyText];
  for (const rule of STATUTORY_RULES) {
    if (anyPatternMatches(rule.keywordPatterns, haystacks)) return rule;
  }
  return null;
}

const THIN_BODY_MAX_CHARS = 80;

const STUB_BODY_PATTERNS: RegExp[] = [
  /\bsee\s+(?:the\s+)?attach(?:ed|ment)\b/i,
  /\bplease\s+find\s+attached\b/i,
  /\battached\s+(?:please\s+find|herewith)\b/i,
  /\bvoir\s+(?:la\s+)?pi[eè]ce\s+jointe\b/i,
  /\bci[\s-]?joint/i,
];

/**
 * Stub/short body heuristic for the thin-body + attachments escalation: a
 * PDF-only DSAR letter ("see attached") must not slip through as a vague
 * summary. Recall over precision — thin only costs one extra escalation.
 */
export function isThinBody(bodyText: string | null): boolean {
  if (bodyText === null) return true;
  const collapsed = bodyText.replace(/\s+/g, " ").trim();
  if (collapsed.length === 0) return true;
  if (collapsed.length < THIN_BODY_MAX_CHARS) return true;
  return STUB_BODY_PATTERNS.some((pattern) => pattern.test(collapsed));
}

// Tags whose boundaries separate words; everything else (span/b/i/wbr/...)
// is inline and must be stripped to "" so it cannot split a keyword.
const BLOCK_TAG_PATTERN =
  /<\/?(?:p|div|br|hr|li|ul|ol|tr|td|th|table|thead|tbody|h[1-6]|blockquote|pre|section|article|header|footer|address)\b[^>]*\/?>/gi;

function decodeNumericEntity(_match: string, decimal?: string, hex?: string): string {
  const codePoint = decimal !== undefined ? parseInt(decimal, 10) : parseInt(hex ?? "", 16);
  if (!Number.isFinite(codePoint) || codePoint < 0 || codePoint > 0x10ffff) return " ";
  try {
    return String.fromCodePoint(codePoint);
  } catch {
    return " ";
  }
}

/**
 * HTML-only body → plain text for the keyword pass: strip script/style
 * blocks, drop tags (block tags become spaces, inline tags vanish), decode
 * common entities, remove soft hyphens (U+00AD) and zero-width characters
 * (U+200B-U+200D, U+FEFF), and collapse whitespace — so entities, soft
 * hyphens, and tag-interleaving cannot split statutory keywords.
 */
export function normalizeEmailHtml(html: string): string {
  // Strip every `<...>` tag, looped until the string stops changing, so a
  // single pass cannot be defeated by nested/partial tags such as
  // `<scr<script>ipt>` (CodeQL js/incomplete-multi-character-sanitization).
  const stripTags = (s: string): string => {
    let prev: string;
    do {
      prev = s;
      s = s.replace(/<[^>]*>/g, "");
    } while (s !== prev);
    return s;
  };

  // 1. Remove <script>/<style> BLOCKS (tag + content) so JS/CSS source cannot
  //    pollute the keyword pass. The closing-tag pattern uses `[^>]*>` (not
  //    `\s*>`) so malformed closers like `</script foo>` still match (CodeQL
  //    js/bad-tag-filter); looped to defeat nested partials.
  let text = html;
  const BLOCK_ELEMENT = /<(script|style)\b[^>]*>[\s\S]*?<\/\1[^>]*>/gi;
  let prev: string;
  do {
    prev = text;
    text = text.replace(BLOCK_ELEMENT, " ");
  } while (text !== prev);

  // 2. Comments + block tags \u2192 spaces, then strip every remaining tag.
  text = stripTags(
    text.replace(/<!--[\s\S]*?-->/g, " ").replace(BLOCK_TAG_PATTERN, " "),
  );

  // 3. Decode entities (this can re-introduce `<`/`>` from `&lt;`/`&gt;`).
  text = text
    .replace(/&#(\d+);|&#x([0-9a-fA-F]+);/g, decodeNumericEntity)
    .replace(/&nbsp;/gi, " ")
    .replace(/&shy;/gi, "\u00AD")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&apos;/gi, "'")
    .replace(/&amp;/gi, "&");

  // 4. FINAL tag strip (looped) \u2014 neutralises any `<tag>` reintroduced by the
  //    entity decode in step 3, so the keyword-pass output can NEVER contain a
  //    `<script` sequence (CodeQL js/incomplete-multi-character-sanitization).
  //    This is text extraction for keyword matching, never rendered HTML, so
  //    discarding entity-encoded angle-bracket content is correct, not lossy.
  text = stripTags(text);

  return text
    .replace(/[\u00AD\u200B-\u200D\uFEFF]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

const MONTH_LABELS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
] as const;

/**
 * Due date from `received_at` + the registry dueRule (UTC).
 * - "hours": exactly +N hours.
 * - "calendar-month": same day next month, clamped to that month's last day
 *   (GDPR Art. 12(3) calendar-month semantics — Jan 31 → Feb 28/29, never a
 *   naive +30 days). Time of day is preserved.
 */
export function computeDueDate(receivedAtIso: string, dueRule: DueRule): Date {
  const received = new Date(receivedAtIso);
  if (Number.isNaN(received.getTime())) {
    throw new Error(`computeDueDate: unparseable receivedAtIso ${JSON.stringify(receivedAtIso)}`);
  }
  if (dueRule.kind === "hours") {
    return new Date(received.getTime() + dueRule.hours * 3_600_000);
  }
  const year = received.getUTCFullYear();
  const monthIndex = received.getUTCMonth();
  // Date.UTC(year, monthIndex + 2, 0) = last day of the month after next-1,
  // i.e. the last day of the target (next) month; handles year rollover.
  const lastDayOfNextMonth = new Date(Date.UTC(year, monthIndex + 2, 0)).getUTCDate();
  const clampedDay = Math.min(received.getUTCDate(), lastDayOfNextMonth);
  return new Date(
    Date.UTC(
      year,
      monthIndex + 1,
      clampedDay,
      received.getUTCHours(),
      received.getUTCMinutes(),
      received.getUTCSeconds(),
      received.getUTCMilliseconds(),
    ),
  );
}

/**
 * Human string for UI: "due <date> — <label>". Hour-based deadlines include
 * the UTC time (a 72-hour breach clock cares about the hour); calendar-month
 * deadlines show the date only. Deterministic — no locale/ICU dependence.
 */
export function formatDueDate(receivedAtIso: string, dueRule: DueRule): string {
  const due = computeDueDate(receivedAtIso, dueRule);
  const datePart = `${due.getUTCDate()} ${MONTH_LABELS[due.getUTCMonth()]} ${due.getUTCFullYear()}`;
  if (dueRule.kind === "hours") {
    const hh = String(due.getUTCHours()).padStart(2, "0");
    const mm = String(due.getUTCMinutes()).padStart(2, "0");
    return `due ${datePart}, ${hh}:${mm} UTC — ${dueRule.label}`;
  }
  return `due ${datePart} — ${dueRule.label}`;
}
