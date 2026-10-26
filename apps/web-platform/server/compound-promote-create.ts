// WikiSkill Phase 2 (#10550) -- the PURE half of the gated new-skill create arm (plan 2026-10-26, Guards 1, 2 and 4).
//
// The model returns structured fields; this module validates every string against a shape allowlist, ranks the
// proposal against the existing skills, checks the description budget and renders SKILL.md, PURPOSE.md and the Cursor
// stub from fixed templates. Spawn-based gates live in `compound-promote-create-gates.ts`, the wiring in the arm.
//
//   - Every numeric rule is an exported constant read by the prompt, the check and the PR-body trailer.
//   - Every gate fails CLOSED on input it cannot measure. Refusal `detail` values are closed tokens, never model text.
//   - Nothing here reads a secret, spawns a process or touches the network.
//
// `PII_REGEX`, `CREDENTIAL_RE` and the cluster hash come from the leaf module `compound-promote-screens.ts`, so there
// is no import edge from here to the handler.

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { parse as parseYaml } from "yaml";
import { z } from "zod";
import { CREDENTIAL_RE, PII_REGEX, computeClusterHash } from "@/server/compound-promote-screens";
import { SLUG_RE as PATTERN_SLUG_RE, fenceBlock, renderPatternIndex, untrustedDataSentence, type PatternPage } from "@/server/compound-promote-patterns";

// =============================================================================
// Constants (each read by prompt, check and PR-body trailer)
// =============================================================================

/** CTO T2: the new description is at most this many words. */
export const CREATE_DESCRIPTION_MAX_WORDS = 30;
/** CTO T2: and at least this many (a one-line stub description routes nothing). */
export const CREATE_DESCRIPTION_MIN_WORDS = 12;
/** Convention every skill description follows (third person). */
export const CREATE_DESCRIPTION_PREFIX = "This skill should be used";
/** CTO T4: create-specific caps, applied to SKILL.md and PURPOSE.md separately (the stub is exempt). */
export const CREATE_FILE_MAX_LINES = 60;
export const CREATE_FILE_MAX_BYTES = 3072;
export const CREATE_LIST_MAX_ITEMS = 6;
/** Per-string caps. `description` is also bounded by word count. */
export const CREATE_ITEM_MAX_CHARS = 160;
export const CREATE_FIELD_MAX_CHARS = 300;
/** Cap for a model-named skill identifier (the new slug is further bounded by SLUG_MAX). */
export const CREATE_SLUG_IDENT_MAX = 60;
/** CTO F3: hard ceiling on index + skill list; refuse, never truncate. */
export const CREATE_INPUT_MAX_TOKENS = 12000;
/** Bytes-to-tokens bound (bytes / 4, rounded up); a heuristic, no tokenizer exists under server/. Phase 0 measured ~9.8k. */
export const CREATE_INPUT_BYTES_PER_TOKEN = 4;
/** CTO F3: output cap of the single create-propose call. */
export const CREATE_MAX_TOKENS = 3000;
/** The server's top-K overlap ranking the model's `nearest_skill` must appear in. */
export const OVERLAP_TOP_K = 3;
/**
 * A create is refused as `prefer-patch` when ANY existing skill (user-invoked ones included) overlaps the proposal at
 * or above this score (IDF-weighted cosine over word stems, see `rankOverlap`). Calibrated on two synthesized evidence
 * fixtures and four synthetic negatives; the calibration test prints the numbers and pins the literal.
 */
export const OVERLAP_REFUSE_THRESHOLD = 0.16;
/** A skills tree with fewer SKILL.md files than this is a broken read, not a clean count. */
export const CREATE_MIN_SKILL_POPULATION = 50;

export const PROMOTION_LOG_PATH = "knowledge-base/project/learnings/promotion-log.md";
export const PURPOSE_TEMPLATE_PATH = "plugins/soleur/skills/skill-creator/templates/purpose.md";
export const GROK_BLOCK_SOURCE_PATH = "plugins/soleur/skills/plan/SKILL.md";
export const COMPONENTS_TEST_PATH = "plugins/soleur/test/components.test.ts";
/** The fixed PR-body line that marks a create PR (CTO F2); never a new Tier vocabulary. */
export const CREATE_PR_BODY_LINE = "CREATE (new skill)";

/** CTO "missed fork": ONE refusal reason with a closed `class`. */
export const CREATE_REFUSAL_CLASSES = [
  "week-cap",
  "create-open",
  "index-empty",
  "input-size",
  "model-invalid",
  "shape",
  "slug",
  "prefer-patch",
  "budget",
  "scan",
  "readme-sync",
  "stub-drift",
  "persist",
] as const;
export type CreateRefusalClass = (typeof CREATE_REFUSAL_CLASSES)[number];

export const CREATE_NO_ACTION_REASONS = ["no-pattern-qualifies", "all-owned", "other"] as const;
export type CreateNoActionReason = (typeof CREATE_NO_ACTION_REASONS)[number];

/** The `checkCreate` gates, in the order they run; a passing verdict lists those that ran (a vacuous pass is visible). */
export const CREATE_GATES = [
  "schema",
  "slug-format",
  "shape",
  "pii",
  "ledger",
  "collision",
  "prefer-patch",
  "budget",
] as const;
export type CreateGate = (typeof CREATE_GATES)[number];

/** The closed PURPOSE.md template slot set. The renderer fills exactly these; the template test pins the same set. */
export const PURPOSE_TEMPLATE_SLOTS = [
  "SKILL_NAME",
  "ORIGIN",
  "PATTERNS_ADDRESSED",
  "NEAREST_SKILL",
  "PATCH_REJECTION_REASON",
  "MERGE_RETIRE_CANDIDATES",
  "EVOLUTION_HISTORY",
] as const;

/** The screens are the handler's own regexes (identity), exported so a test can pin that. */
export const CREATE_SCREENS = { pii: PII_REGEX, credential: CREDENTIAL_RE } as const;

// Static floor of slugs that name a command stem or a Cursor bare name; the commands directory adds to it.
const RESERVED_SLUG_FLOOR: readonly string[] = ["go", "sync", "help", "version"];
// YAML 1.1 reads these bare scalars as booleans or null, so a skill named so would not round-trip through frontmatter.
const YAML_WORD_SLUGS: ReadonlySet<string> = new Set(["y", "n", "yes", "no", "on", "off", "true", "false", "null"]);
const SLUG_FORMAT_RE = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const SLUG_MIN = 3;
const SLUG_MAX = 41;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// =============================================================================
// Verdict union
// =============================================================================

export interface SkillRecord {
  name: string;
  description: string;
  /** `disable-model-invocation: true` -- absent from the model's skill listing, spends no description budget (ADR-236). */
  disableModelInvocation: boolean;
}

export interface CreateProposal {
  decision: "create";
  pattern_slug: string;
  slug: string;
  description: string;
  nearest_skill: string;
  patch_rejection_reason: string;
  when_to_use: string[];
  steps: string[];
  sharp_edges: string[];
  merge_retire_candidates: string[];
}

export interface CreateRefusal {
  kind: "refused";
  class: CreateRefusalClass;
  /** A closed token (field label plus rule id, or a fixed phrase). Never model text. */
  detail: string;
  /** Numbers only, for the marker. */
  numbers?: Record<string, number>;
}

export type CreateVerdict =
  | { kind: "no_action"; reason: CreateNoActionReason }
  | { kind: "suppressed"; clusterHash: string }
  | CreateRefusal
  | {
      kind: "create";
      proposal: CreateProposal;
      clusterHash: string;
      gates: readonly CreateGate[];
      overlap: { top1Name: string; top1: number; nearestRank: number };
      words: number;
      cap: number;
      total: number;
      headroom: number;
    };

export interface CreateContext {
  patterns: readonly PatternPage[];
  /** Every skill that has a SKILL.md in the clone (ranking population). */
  skills: readonly SkillRecord[];
  /** Every directory under skills/, including one with no SKILL.md (collision population). */
  skillDirs: readonly string[];
  /** Paths under agents/, e.g. `engineering/review/foo.md` (from `readAgentPaths`, which fails closed). */
  agentPaths: readonly string[];
  /** Directory names under plugins/soleur/cursor/skills, e.g. `soleur-ship` (from `readCursorDirs`). */
  cursorDirs: readonly string[];
  /** Basenames of plugins/soleur/commands/*.md without `.md` (from `readCommandNames`; `[]` when unreadable). */
  commandNames: readonly string[];
  /** Paths touched by open PRs (the handler's `scanOpenPrSkillPaths`). */
  openPrPaths: readonly string[];
  /** Measured from the clone with the SAME counter as the bun test; `null` = unreadable (refuse). */
  budget: { total: number; cap: number } | null;
  /** The handler's ledger predicate over a cluster hash. */
  isHashSuppressed: (hash: string) => boolean;
}

function refuse(cls: CreateRefusalClass, detail: string, numbers?: Record<string, number>): CreateRefusal {
  return numbers ? { kind: "refused", class: cls, detail, numbers } : { kind: "refused", class: cls, detail };
}

// =============================================================================
// Model output schema
// =============================================================================

/** Structured-output schema for the single create-propose call (every object closed). */
export const CREATE_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["decision"],
  properties: {
    decision: { type: "string", enum: ["create", "no_action"] },
    reason_class: { type: "string", enum: [...CREATE_NO_ACTION_REASONS] },
    pattern_slug: { type: "string" },
    slug: { type: "string" },
    description: { type: "string" },
    nearest_skill: { type: "string" },
    patch_rejection_reason: { type: "string" },
    when_to_use: { type: "array", items: { type: "string" } },
    steps: { type: "array", items: { type: "string" } },
    sharp_edges: { type: "array", items: { type: "string" } },
    merge_retire_candidates: { type: "array", items: { type: "string" } },
  },
} as const;

const list = (min: number, max: number) => z.array(z.string()).min(min).max(max);
const NoActionSchema = z.strictObject({
  decision: z.literal("no_action"),
  reason_class: z.enum(CREATE_NO_ACTION_REASONS),
});
const CreateSchema = z.strictObject({
  decision: z.literal("create"),
  pattern_slug: z.string(),
  slug: z.string(),
  description: z.string(),
  nearest_skill: z.string(),
  patch_rejection_reason: z.string(),
  when_to_use: list(1, CREATE_LIST_MAX_ITEMS),
  steps: list(1, CREATE_LIST_MAX_ITEMS),
  sharp_edges: list(1, CREATE_LIST_MAX_ITEMS),
  merge_retire_candidates: list(0, CREATE_LIST_MAX_ITEMS),
});
const OutputSchema = z.discriminatedUnion("decision", [NoActionSchema, CreateSchema]);

/** Parse the model's text as JSON; anything else is `undefined` (never throws). */
export function parseCreateModelText(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

// =============================================================================
// Shape allowlist
// =============================================================================

/**
 * `ident` = the new slug; `ref` = a model-named EXISTING skill and `pattern-ref` = a pattern slug, both validated
 * against the server's own lists afterwards, so they skip the claim-word and instruction-risk phrase rules (a real
 * skill may be called gdpr-gate) but keep every structural rule.
 */
export type ShapeKind = "description" | "item" | "field" | "ident" | "ref" | "pattern-ref";

// The pattern reader's own slug limit ({0,80} after the first character), so a legitimate page slug is not refused.
const PATTERN_SLUG_MAX = (() => {
  const n = Number(/\{0,(\d+)\}/.exec(PATTERN_SLUG_RE.source)?.[1]);
  if (!Number.isInteger(n)) throw new Error("create: cannot derive the pattern slug limit");
  return n + 1;
})();

const REF_NAME_RE = /^[a-z0-9][a-z0-9-]*$/;
const PRINTABLE_ASCII_RE = /^[\x20-\x7e]+$/;
const LEADING_OK_RE = /^[A-Za-z0-9]/;
// Characters that change how a markdown renderer, an HTML sink or the harness reads what follows.
const MARKUP_RE = /[<>[\]{}|\\$@~]/;
const URL_RE = /:\/\/|www\./i;
const RULE_ID_RE = /(?:^|[^a-z0-9])(?:hr|wg|cq|rf|pdr|cm)-[a-z0-9]/i;
const PATH_TOKEN_RE = /(?:^|[^a-z0-9])(?:scripts|references|assets|skills)\//i;
const SOLEUR_TOKEN_RE = /soleur\s*:/i;
const COMMAND_FORM_RE = /(?:^|\s)\/[A-Za-z]/;
/** Words (and one phrase) a created skill may not use to claim a property; read by the prompt and the check. */
export const CREATE_CLAIM_WORDS: readonly string[] = [
  "guarantee", "guarantees", "guaranteed", "compliant", "compliance", "certified", "secure", "your workspace",
  "private", "encrypted", "safe", "safety", "audited", "gdpr", "warranty", "ensures", "100%",
];
// Lookarounds instead of \b so the entry "100%" (non-word last character) is bounded the same way as the words.
const CLAIM_WORD_RE = new RegExp(`(?<![A-Za-z0-9])(?:${CREATE_CLAIM_WORDS.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})(?![A-Za-z0-9])`, "i");

function maxCharsFor(kind: ShapeKind): number {
  if (kind === "item") return CREATE_ITEM_MAX_CHARS;
  if (kind === "ident" || kind === "ref") return CREATE_SLUG_IDENT_MAX;
  if (kind === "pattern-ref") return PATTERN_SLUG_MAX;
  return CREATE_FIELD_MAX_CHARS;
}

/**
 * R1: a case-insensitive, word-bounded phrase denylist over text a reader might follow. It is a TRIPWIRE, not a
 * control (a paraphrase evades it); the controls are the draft PR, mergeMode none, the LOW-RISK scan and the human
 * reviewer. The verbs gate the credential nouns so the bare words token, secret and password stay usable.
 */
const SENSITIVE_NOUN = "(?:token|secret|credential|password|passphrase|api[- ]?key)s?";
const EXFIL_VERB = "(?:read|print|post|send|include|upload|paste|echo|cat|copy|dump|leak|reveal|share|display|email|transmit)";
export const INSTRUCTION_RISK_GROUPS = [
  {
    id: "destructive",
    label: "destructive or privileged commands (recursive delete, force push, sudo, chmod, hard reset, dropping tables, deleting everything)",
    re: /\brm\s+-[a-z]*[rf]|\bforce[- ]push|\bpush\s+(?:--force|-f)\b|\b(?:sudo|chmod|chown|mkfs)\b|\bgit\s+reset\s+--hard|\bdrop\s+(?:table|database|schema)\b|\bdelete\s+(?:all|every|everything)\b/i,
  },
  {
    id: "exec-net",
    label: "code execution or network tools (eval, curl, wget, base64, ssh)",
    re: /\b(?:eval|curl|wget|base64|ssh|scp)\b/i,
  },
  {
    id: "exfiltration",
    label: "reading or sending secrets (exfiltrating data, private keys, env files, or printing, posting or pasting tokens, passwords and credentials)",
    re: new RegExp(`exfiltrat|\\bprivate\\s+key|\\bssh\\s+key|\\benv(?:ironment)?\\s+file|\\.env\\b|\\b${EXFIL_VERB}\\b[^.]{0,40}?\\b${SENSITIVE_NOUN}\\b`, "i"),
  },
  {
    id: "override",
    label: "overriding instructions (ignore, disregard or forget earlier guidance, bypass, override instructions, the system prompt)",
    re: /\b(?:ignore|disregard|forget)\b[^.]{0,40}?\b(?:previous|prior|above|all|earlier)\b|\bbypass(?:es|ed|ing)?\b|\boverrid\w*\b[^.]{0,40}?\binstructions?\b|\bsystem\s+prompt\b/i,
  },
] as const;

/** The id of the first denylist group `text` hits, else `null`. */
export function instructionRiskProblem(text: string): string | null {
  for (const g of INSTRUCTION_RISK_GROUPS) if (g.re.test(text)) return g.id;
  return null;
}

/**
 * The shape allowlist for ONE model string. Returns the first rule that refuses it (a closed token) or `null`.
 * Plain printable ASCII only, so every refusal below is a rule over a string the model cannot encode around.
 */
export function shapeProblem(value: string, kind: ShapeKind): string | null {
  if (value.trim().length === 0) return "empty";
  if (!PRINTABLE_ASCII_RE.test(value)) return "non-ascii";
  if (value.length > maxCharsFor(kind)) return "length";
  if (!LEADING_OK_RE.test(value)) return "leading-char";
  if (value.includes("`")) return "backtick";
  if (MARKUP_RE.test(value)) return "markup";
  if (URL_RE.test(value)) return "url";
  if (RULE_ID_RE.test(value)) return "rule-id";
  if (PATH_TOKEN_RE.test(value)) return "path-token";
  if (SOLEUR_TOKEN_RE.test(value)) return "soleur-token";
  if (COMMAND_FORM_RE.test(value)) return "command-form";
  if (kind === "ref" && !REF_NAME_RE.test(value)) return "ref-format";
  if (kind === "pattern-ref" && !PATTERN_SLUG_RE.test(value)) return "ref-format";
  if (kind !== "ref" && kind !== "pattern-ref") {
    if (instructionRiskProblem(value)) return "instruction-risk";
    if (CLAIM_WORD_RE.test(value)) return "claim-word";
  }
  if (kind === "description") {
    if (value.includes('"')) return "quote";
    if (!value.startsWith(CREATE_DESCRIPTION_PREFIX)) return "description-prefix";
  }
  return null;
}

function screenProblem(value: string): "pii" | "credential" | null {
  if (CREDENTIAL_RE.test(value)) return "credential";
  if (PII_REGEX.test(value)) return "pii";
  return null;
}

interface LabeledString {
  label: string;
  value: string;
  kind: ShapeKind;
}

/** Every model-authored string, labelled by a fixed field name (and index) used in refusal details. */
export function collectModelStrings(p: CreateProposal): LabeledString[] {
  const out: LabeledString[] = [
    { label: "pattern_slug", value: p.pattern_slug, kind: "pattern-ref" },
    { label: "slug", value: p.slug, kind: "ident" },
    { label: "description", value: p.description, kind: "description" },
    { label: "nearest_skill", value: p.nearest_skill, kind: "ref" },
    { label: "patch_rejection_reason", value: p.patch_rejection_reason, kind: "field" },
  ];
  const lists: Array<[string, string[]]> = [
    ["when_to_use", p.when_to_use],
    ["steps", p.steps],
    ["sharp_edges", p.sharp_edges],
    ["merge_retire_candidates", p.merge_retire_candidates],
  ];
  for (const [name, items] of lists) items.forEach((value, i) => out.push({ label: `${name}[${i}]`, value, kind: "item" }));
  return out;
}

// =============================================================================
// Paths
// =============================================================================

/** The one slug rule: kebab-case, 3 to 41 characters, starting with a letter. */
export function isValidSlug(slug: string): boolean {
  return slug.length >= SLUG_MIN && slug.length <= SLUG_MAX && SLUG_FORMAT_RE.test(slug);
}

/** The closed six-path set, in the fixed order (CTO F1). */
export function createPathList(slug: string): readonly string[] {
  if (!isValidSlug(slug)) throw new Error("create: invalid slug");
  return [
    `plugins/soleur/skills/${slug}/SKILL.md`,
    `plugins/soleur/skills/${slug}/PURPOSE.md`,
    `plugins/soleur/cursor/skills/soleur-${slug}/SKILL.md`,
    "README.md",
    "plugins/soleur/README.md",
    PROMOTION_LOG_PATH,
  ];
}

// =============================================================================
// Budget counter (mirrors plugins/soleur/test/components.test.ts exactly)
// =============================================================================

/** Same split the bun test uses: `split(/\s+/)` then drop empties. */
export function countWords(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

export type WordCountResult =
  | { ok: true; total: number; skills: number; disabled: number; records: SkillRecord[]; dirs: string[] }
  | { ok: false; detail: string };

// The same frontmatter split `parseComponent()` in plugins/soleur/test/helpers.ts uses.
const FRONTMATTER_RE = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/;

/**
 * Count model-visible description words over `<pluginRoot>/skills/*\/SKILL.md`, the way `discoverSkills()` and
 * `parseComponent()` do: skip `disable-model-invocation === true`, then `split(/\s+/)`. Unlike the bun test this
 * FAILS CLOSED: a missing frontmatter, an unparseable one, a non-string or absent description, or a population
 * below `minSkills` is `{ok:false}`, never a quiet 0.
 */
export function countDescriptionWords(pluginRoot: string, opts?: { minSkills?: number }): WordCountResult {
  const minSkills = opts?.minSkills ?? CREATE_MIN_SKILL_POPULATION;
  const skillsDir = join(pluginRoot, "skills");
  let dirs: string[];
  try {
    dirs = readdirSync(skillsDir, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort();
  } catch {
    return { ok: false, detail: "skills-dir-unreadable" };
  }
  const records: SkillRecord[] = [];
  let total = 0;
  let disabled = 0;
  for (const dir of dirs) {
    const file = join(skillsDir, dir, "SKILL.md");
    if (!existsSync(file)) continue;
    let raw: string;
    try {
      raw = readFileSync(file, "utf8");
    } catch {
      return { ok: false, detail: "skill-unreadable" };
    }
    const m = FRONTMATTER_RE.exec(raw);
    if (!m) return { ok: false, detail: "frontmatter-missing" };
    let fm: unknown;
    try {
      fm = parseYaml(m[1]) ?? {};
    } catch {
      return { ok: false, detail: "frontmatter-unparseable" };
    }
    if (typeof fm !== "object" || fm === null || Array.isArray(fm)) return { ok: false, detail: "frontmatter-not-a-map" };
    const rec = fm as Record<string, unknown>;
    const description = rec.description;
    if (typeof description !== "string") return { ok: false, detail: "description-not-a-string" };
    const off = rec["disable-model-invocation"] === true;
    records.push({ name: dir, description, disableModelInvocation: off });
    if (off) {
      disabled += 1;
      continue;
    }
    total += countWords(description);
  }
  if (records.length < Math.max(1, minSkills)) return { ok: false, detail: "population-below-floor" };
  return { ok: true, total, skills: records.length, disabled, records, dirs };
}

/**
 * Read `SKILL_DESCRIPTION_WORD_BUDGET` from the source of `components.test.ts`. Anchored to the line-start constant
 * assignment so a digit run in the history comment (or a commented-out earlier value) can never win; anything other
 * than exactly one positive integer assignment is `null` (fail closed).
 */
export function readBudgetCap(source: string): number | null {
  const matches = [...source.matchAll(/^const SKILL_DESCRIPTION_WORD_BUDGET = (\d+);/gm)];
  if (matches.length !== 1) return null;
  const n = Number(matches[0][1]);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
}

/** An agents tree with fewer markdown files than this is a broken read, not a clean listing. */
export const CREATE_MIN_AGENT_POPULATION = 30;

export type AgentPathsResult = { ok: true; paths: string[] } | { ok: false; detail: "agents-dir-unreadable" | "agents-below-floor" };

/**
 * Paths under `<pluginRoot>/agents`, relative and recursive, markdown only. FAILS CLOSED: any unreadable directory or a
 * population below `minEntries` is `{ok:false}` (an empty list would silently drop the agent-name collision check).
 */
export function readAgentPaths(pluginRoot: string, opts?: { minEntries?: number }): AgentPathsResult {
  const out: string[] = [];
  const walk = (dir: string, prefix: string): boolean => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return false;
    }
    for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      const rel = prefix ? `${prefix}/${e.name}` : e.name;
      if (e.isDirectory()) {
        if (!walk(join(dir, e.name), rel)) return false;
      } else if (e.isFile() && e.name.endsWith(".md")) out.push(rel);
    }
    return true;
  };
  if (!walk(join(pluginRoot, "agents"), "")) return { ok: false, detail: "agents-dir-unreadable" };
  if (out.length < Math.max(1, opts?.minEntries ?? CREATE_MIN_AGENT_POPULATION)) return { ok: false, detail: "agents-below-floor" };
  return { ok: true, paths: out };
}

export type CursorDirsResult = { ok: true; dirs: string[] } | { ok: false; detail: "cursor-dir-unreadable" | "cursor-below-floor" };

/** Directory names under `<pluginRoot>/cursor/skills` (the stub folders `soleur-<slug>`). Fails closed like `readAgentPaths`. */
export function readCursorDirs(pluginRoot: string, opts?: { minEntries?: number }): CursorDirsResult {
  let dirs: string[];
  try {
    dirs = readdirSync(join(pluginRoot, "cursor", "skills"), { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort();
  } catch {
    return { ok: false, detail: "cursor-dir-unreadable" };
  }
  if (dirs.length < Math.max(1, opts?.minEntries ?? CREATE_MIN_SKILL_POPULATION)) return { ok: false, detail: "cursor-below-floor" };
  return { ok: true, dirs };
}

/** Basenames of `<pluginRoot>/commands/*.md`. Unreadable is `[]`: the static reserved floor still applies. */
export function readCommandNames(pluginRoot: string): string[] {
  try {
    return readdirSync(join(pluginRoot, "commands"), { withFileTypes: true })
      .filter((e) => e.isFile() && e.name.endsWith(".md"))
      .map((e) => e.name.replace(/\.md$/, ""))
      .sort();
  } catch {
    return [];
  }
}

/** The refusal for a collision population that could not be measured (the arm maps a failed reader result to it). */
export function unmeasurableCollisionRefusal(detail: string): CreateRefusal {
  return refuse("slug", detail);
}

// =============================================================================
// Overlap ranking
// =============================================================================

const STOPWORDS: ReadonlySet<string> = new Set([
  "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "in", "into", "is", "it", "its", "of", "on",
  "or", "that", "the", "their", "then", "this", "to", "when", "with", "without", "via", "than", "not", "no", "can",
  "skill", "should", "used", "use", "using", "needs", "need", "while", "each", "every", "any", "all", "also",
]);

function stem(word: string): string {
  return word.length > 4 ? word.replace(/(?:ing|ed|es|s|e)$/, "") : word;
}

/** Lowercase word stems, stopwords and boilerplate removed, de-duplicated. */
export function overlapTokens(text: string): string[] {
  const out = new Set<string>();
  for (const raw of text.toLowerCase().match(/[a-z0-9]+/g) ?? []) {
    if (STOPWORDS.has(raw)) continue;
    const s = stem(raw);
    if (s.length > 1) out.add(s);
  }
  return [...out];
}

/** The text of a proposal that represents what it would own: slug words, description and when-to-use bullets. */
export function proposalOverlapText(p: { slug: string; description: string; when_to_use: readonly string[] }): string {
  return `${p.slug.replace(/-/g, " ")} ${p.description} ${p.when_to_use.join(" ")}`;
}

/**
 * Rank every skill by IDF-weighted cosine similarity (binary term frequency; IDF over the skill population) between
 * the proposal text and `name + description`. Deterministic: score descending, then name ascending. Scores are in
 * [0, 1]; an empty proposal scores 0 against everything.
 */
export function rankOverlap(text: string, skills: readonly SkillRecord[]): Array<{ name: string; score: number }> {
  const docs = skills.map((s) => ({ name: s.name, tokens: new Set(overlapTokens(`${s.name.replace(/-/g, " ")} ${s.description}`)) }));
  const n = docs.length;
  const df = new Map<string, number>();
  for (const d of docs) for (const t of d.tokens) df.set(t, (df.get(t) ?? 0) + 1);
  const idf = (t: string): number => Math.log(1 + (n + 1) / ((df.get(t) ?? 0) + 1));
  const q = new Set(overlapTokens(text));
  let qNorm = 0;
  for (const t of q) qNorm += idf(t) ** 2;
  const ranked = docs.map((d) => {
    let dNorm = 0;
    let dot = 0;
    for (const t of d.tokens) {
      const w = idf(t);
      dNorm += w * w;
      if (q.has(t)) dot += w * w;
    }
    const score = qNorm > 0 && dNorm > 0 ? dot / (Math.sqrt(qNorm) * Math.sqrt(dNorm)) : 0;
    return { name: d.name, score };
  });
  return ranked.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
}

// =============================================================================
// Ledger hash
// =============================================================================

/**
 * The cluster hash over a pattern's evidence keys. It IS the handler's `computeClusterHash` (one function, from the
 * leaf module): the branch, PR title and ledger shapes are unchanged and a pattern with an existing patch PR is
 * suppressed for create too (CTO F2).
 */
export const createClusterHash = computeClusterHash;

// =============================================================================
// Prompt (reads every constant)
// =============================================================================

export type PrepareCreateResult =
  | CreateRefusal
  | { kind: "ready"; prompt: string; maxTokens: number };

/**
 * Build the single create-propose prompt, or refuse before any model call. The input is the pattern index plus the
 * MODEL-VISIBLE skill list (a user-invoked skill is not offered as a nearest skill); over the ceiling is refused,
 * never truncated.
 */
export function prepareCreate(args: { patterns: readonly PatternPage[]; skills: readonly SkillRecord[]; nonce: string }): PrepareCreateResult {
  if (args.patterns.length === 0) return refuse("index-empty", "no-open-patterns");
  const visible = args.skills.filter((s) => !s.disableModelInvocation);
  const skillList = visible.map((s) => `- ${s.name}: ${s.description.replace(/\s+/g, " ").trim()}`).join("\n");
  const index = renderPatternIndex(args.patterns, args.nonce);
  const skillBlock = fenceBlock(args.nonce, "skill-list", skillList);
  const inputBytes = Buffer.byteLength(index, "utf8") + Buffer.byteLength(skillBlock, "utf8");
  const inputTokensBound = Math.ceil(inputBytes / CREATE_INPUT_BYTES_PER_TOKEN);
  if (inputTokensBound > CREATE_INPUT_MAX_TOKENS) {
    return refuse("input-size", "over-ceiling", { tokens: inputTokensBound, max: CREATE_INPUT_MAX_TOKENS, bytes: inputBytes });
  }
  const prompt = [
    "You decide whether ONE recurring pattern deserves a brand-new skill. Prefer patching an existing skill.",
    untrustedDataSentence(args.nonce),
    "",
    "Return no_action unless a pattern is mature, no existing skill owns it, and a patch to the nearest skill would bury it.",
    `no_action needs a reason_class from: ${CREATE_NO_ACTION_REASONS.join(", ")}.`,
    "",
    "A create returns structured fields only. You never write a file, a diff, frontmatter or a heading; the server renders them.",
    `- slug: kebab-case, ${SLUG_MIN} to ${SLUG_MAX} characters, not an existing skill or agent name.`,
    `- description: ${CREATE_DESCRIPTION_MIN_WORDS} to ${CREATE_DESCRIPTION_MAX_WORDS} words, starting with "${CREATE_DESCRIPTION_PREFIX}", routing text only. The total description budget is shared and nearly full.`,
    `- nearest_skill: the existing skill closest to this pattern (from the skill list), and patch_rejection_reason: why a patch to it is wrong.`,
    `- when_to_use, steps, sharp_edges: 1 to ${CREATE_LIST_MAX_ITEMS} short plain sentences each (at most ${CREATE_ITEM_MAX_CHARS} characters). merge_retire_candidates: 0 to ${CREATE_LIST_MAX_ITEMS}.`,
    `- Each file the server renders must stay under ${CREATE_FILE_MAX_LINES} lines and ${CREATE_FILE_MAX_BYTES} bytes: be brief.`,
    "- Plain ASCII text only. No backticks, code fences, links, URLs, paths, HTML, rule ids, command names, or the word soleur followed by a colon.",
    "- Never claim a guarantee, certification, compliance or security property. Never restate or relax a hard rule.",
    `- A server-side overlap check refuses a create whose overlap with any existing skill reaches ${OVERLAP_REFUSE_THRESHOLD.toFixed(2)}; your nearest_skill must be among the server's top ${OVERLAP_TOP_K} matches.`,
    "- pattern_slug must be exactly the slug of one pattern in the index.",
    "",
    index,
    "",
    skillBlock,
  ].join("\n");
  return { kind: "ready", prompt, maxTokens: CREATE_MAX_TOKENS };
}

// =============================================================================
// checkCreate
// =============================================================================

function agentNames(agentPaths: readonly string[]): { leaves: Set<string>; cursor: Set<string> } {
  const leaves = new Set<string>();
  const cursor = new Set<string>();
  for (const rel of agentPaths) {
    const stem = rel.replace(/\.md$/i, "");
    leaves.add(stem.split("/").pop() ?? stem);
    cursor.add(`soleur-${stem.replaceAll("/", "-")}`);
  }
  return { leaves, cursor };
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}

/**
 * The create admission chokepoint for the MODEL's output (Guard 1). Gate order is fixed; every refusal carries a
 * closed class and a closed detail token. A passing verdict lists the gates that ran, so a vacuous pass (zero gates)
 * is distinguishable from a real one.
 */
export function checkCreate(raw: unknown, c: CreateContext): CreateVerdict {
  const gates: CreateGate[] = [];

  // schema
  const parsed = OutputSchema.safeParse(raw);
  if (!parsed.success) return refuse("model-invalid", "schema");
  if (parsed.data.decision === "no_action") return { kind: "no_action", reason: parsed.data.reason_class };
  const p = parsed.data as CreateProposal;
  const page = c.patterns.find((x) => x.slug === p.pattern_slug);
  if (!page) return refuse("model-invalid", "unknown-pattern");
  gates.push("schema");

  // slug format (narrower than the shape rules; reported as class slug)
  if (!isValidSlug(p.slug)) return refuse("slug", "format");
  if (YAML_WORD_SLUGS.has(p.slug)) return refuse("slug", "yaml-word");
  gates.push("slug-format");

  // shape over EVERY model string
  const strings = collectModelStrings(p);
  for (const s of strings) {
    const rule = shapeProblem(s.value, s.kind);
    if (rule) return refuse("shape", `${s.label}:${rule}`);
  }
  gates.push("shape");

  // PII / credential over EVERY model string
  for (const s of strings) {
    const hit = screenProblem(s.value);
    if (hit) return refuse("shape", `${s.label}:${hit}`);
  }
  gates.push("pii");

  // ledger
  const clusterHash = createClusterHash(page.evidence);
  if (c.isHashSuppressed(clusterHash)) return { kind: "suppressed", clusterHash };
  gates.push("ledger");

  // collision
  if (RESERVED_SLUG_FLOOR.includes(p.slug) || c.commandNames.includes(p.slug)) return refuse("slug", "reserved");
  if (c.skillDirs.includes(p.slug) || c.skills.some((s) => s.name === p.slug)) return refuse("slug", "skill-exists");
  const agents = agentNames(c.agentPaths);
  if (agents.leaves.has(p.slug)) return refuse("slug", "agent-exists");
  if (agents.cursor.has(`soleur-${p.slug}`)) return refuse("slug", "cursor-name-exists");
  if (c.cursorDirs.includes(`soleur-${p.slug}`)) return refuse("slug", "cursor-dir-exists");
  const slugPrefixes = [`plugins/soleur/skills/${p.slug}/`, `plugins/soleur/cursor/skills/soleur-${p.slug}/`];
  if (c.openPrPaths.some((path) => slugPrefixes.some((pre) => path.startsWith(pre)))) return refuse("slug", "open-pr-slug");
  gates.push("collision");

  // prefer-patch. One ranking over EVERY skill (a user-invoked skill still owns its area, so the threshold sees it);
  // the nearest skill is ranked among the skills the model was shown, because that is the list it chose from.
  const hidden = new Set(c.skills.filter((s) => s.disableModelInvocation).map((s) => s.name));
  if (!c.skills.some((s) => s.name === p.nearest_skill && !s.disableModelInvocation)) return refuse("prefer-patch", "nearest-missing");
  const ranked = rankOverlap(proposalOverlapText(p), c.skills);
  const nearestRank = ranked.filter((r) => !hidden.has(r.name)).findIndex((r) => r.name === p.nearest_skill) + 1;
  const top1 = round3(ranked[0].score);
  if (nearestRank > OVERLAP_TOP_K) {
    return refuse("prefer-patch", "nearest-not-top3", { nearest_rank: nearestRank, top1 });
  }
  if (ranked[0].score >= OVERLAP_REFUSE_THRESHOLD) {
    return refuse("prefer-patch", "overlap", { top1, threshold: OVERLAP_REFUSE_THRESHOLD, nearest_rank: nearestRank });
  }
  const nearestPrefix = `plugins/soleur/skills/${p.nearest_skill}/`;
  if (c.openPrPaths.some((path) => path.startsWith(nearestPrefix))) return refuse("prefer-patch", "open-pr-nearest", { top1 });
  gates.push("prefer-patch");

  // budget
  if (!c.budget || !Number.isFinite(c.budget.total) || !Number.isFinite(c.budget.cap)) return refuse("budget", "unreadable");
  const words = countWords(p.description);
  if (words < CREATE_DESCRIPTION_MIN_WORDS || words > CREATE_DESCRIPTION_MAX_WORDS) {
    return refuse("budget", "words-out-of-range", { words, min: CREATE_DESCRIPTION_MIN_WORDS, max: CREATE_DESCRIPTION_MAX_WORDS });
  }
  const headroom = c.budget.cap - c.budget.total;
  if (words > headroom) {
    return refuse("budget", "over-headroom", { words, total: c.budget.total, cap: c.budget.cap, headroom });
  }
  gates.push("budget");

  return {
    kind: "create",
    proposal: p,
    clusterHash,
    gates,
    overlap: { top1Name: ranked[0].name, top1, nearestRank },
    words,
    cap: c.budget.cap,
    total: c.budget.total,
    headroom,
  };
}

// =============================================================================
// Renderers
// =============================================================================

const GROK_START = "<!-- grok-harness-invoke:start -->";
const GROK_END = "<!-- grok-harness-invoke:end -->";

/**
 * The canonical Grok invoke block, read from `plugins/soleur/skills/plan/SKILL.md` (the single source): start-marker
 * line through end-marker line, each line newline-terminated (the convention the md5 pin in
 * `grok-harness-invoke.test.ts` was computed under). Throws on a missing, reversed or duplicated block.
 */
export function readGrokBlock(planSkillMd: string): string {
  const lines = planSkillMd.split("\n");
  const starts = lines.flatMap((l, i) => (l === GROK_START ? [i] : []));
  const ends = lines.flatMap((l, i) => (l === GROK_END ? [i] : []));
  if (starts.length !== 1 || ends.length !== 1 || ends[0] < starts[0]) throw new Error("create: grok block not found exactly once");
  return lines.slice(starts[0], ends[0] + 1).join("\n") + "\n";
}

/** The one fixed line of SKILL.md that links PURPOSE.md. */
const SKILL_PURPOSE_LINE = "See [PURPOSE.md](./PURPOSE.md) for why this skill exists, the nearest existing skill, and its history.";

const bullets = (items: readonly string[]): string => items.map((i) => `- ${i}`).join("\n");

function titleFromSlug(slug: string): string {
  return slug
    .split("-")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

/** SKILL.md: exactly name + description frontmatter, the Grok block, three fixed headings, ONE ./PURPOSE.md link. */
export function renderSkillMd(p: CreateProposal, grokBlock: string): string {
  return (
    [
      "---",
      `name: ${p.slug}`,
      `description: "${p.description}"`,
      "---",
      "",
      grokBlock.replace(/\n$/, ""),
      "",
      `# ${titleFromSlug(p.slug)}`,
      "",
      "## When to use",
      "",
      bullets(p.when_to_use),
      "",
      "## Steps",
      "",
      bullets(p.steps),
      "",
      "## Sharp edges",
      "",
      bullets(p.sharp_edges),
      "",
      SKILL_PURPOSE_LINE,
    ].join("\n") + "\n"
  );
}

export interface PurposeOpts {
  /** The memoized run date, YYYY-MM-DD. */
  date: string;
  /** Number of evidence entries of the chosen pattern page (server data, never model text). */
  evidenceCount: number;
}

/** Fixed server text for the slots the model does not write. ASCII only, no backticks or links. */
function purposeValues(p: CreateProposal, o: PurposeOpts): Record<(typeof PURPOSE_TEMPLATE_SLOTS)[number], string> {
  if (!DATE_RE.test(o.date)) throw new Error("create: bad date");
  if (!Number.isInteger(o.evidenceCount) || o.evidenceCount < 1) throw new Error("create: bad evidence count");
  const entries = o.evidenceCount === 1 ? "entry" : "entries";
  return {
    SKILL_NAME: p.slug,
    ORIGIN: `Proposed by the compound-promote create arm on ${o.date} from pattern ${p.pattern_slug} (${o.evidenceCount} evidence ${entries}); the merge record is the review record.`,
    PATTERNS_ADDRESSED: `- ${p.pattern_slug}`,
    NEAREST_SKILL: `Nearest existing skill: ${p.nearest_skill}.`,
    PATCH_REJECTION_REASON: p.patch_rejection_reason,
    MERGE_RETIRE_CANDIDATES: p.merge_retire_candidates.length > 0 ? bullets(p.merge_retire_candidates) : NO_MERGE_RETIRE_LINE,
    EVOLUTION_HISTORY: `- ${o.date}: created as a draft by the compound-promote create arm; the merge record is the review record.`,
  };
}

const NO_MERGE_RETIRE_LINE = "- None identified.";

/**
 * PURPOSE.md: fills the closed slot set of the template (the single source of the headings and the fixed
 * attribution). The template is validated against the closed slot set first; text is substituted in ONE pass so a
 * slot-looking string in a model field is never re-expanded. Only `patch_rejection_reason` and the merge-retire
 * bullets are model text; origin, patterns and history are rendered from server data (R3).
 */
export function renderPurposeMd(template: string, p: CreateProposal, opts: PurposeOpts): string {
  const values = purposeValues(p, opts);
  const found = [...template.matchAll(/\{\{([^{}]*)\}\}/g)].map((m) => m[1]);
  const want = new Set<string>(PURPOSE_TEMPLATE_SLOTS);
  if (found.some((s) => !want.has(s)) || [...want].some((s) => !found.includes(s))) throw new Error("create: purpose template slot set changed");
  if (template.replace(/\{\{[A-Z_]+\}\}/g, "").match(/\{\{|\}\}/)) throw new Error("create: purpose template slot malformed");
  return template.replace(/\{\{([A-Z_]+)\}\}/g, (_m, slot: keyof typeof values) => values[slot]);
}

/** The exact PURPOSE.md lines that are server text (template prose plus the rendered server sentences), exempt from the rendered instruction-risk scan. */
export function purposeFixedLines(template: string, p: CreateProposal, opts: PurposeOpts): string[] {
  const v = purposeValues(p, opts);
  const templateProse = template.split("\n").filter((l) => l.trim() !== "" && !l.startsWith("#") && !/\{\{[A-Z_]+\}\}/.test(l));
  return [...templateProse, v.ORIGIN, v.PATTERNS_ADDRESSED, v.NEAREST_SKILL, v.EVOLUTION_HISTORY, NO_MERGE_RETIRE_LINE];
}

// -- Cursor stub: a pure duplicate of plugins/soleur/scripts/sync-cursor-name-map.ts, pinned byte-for-byte by the
//    parity suite over EVERY real skill folder plus a synthetic new-skill fixture (Guard 4). Phase 0 (CTO G3) showed
//    the unmodified generator does not run in the runner image (bun absent, `yaml` unresolvable under node), so this
//    stays. A generator change turns the parity suite red instead of drifting silently.
export const CURSOR_STUB_HEADER =
  "On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.";
const CURSOR_BARE_SKILLS: ReadonlySet<string> = new Set(["go", "sync"]);
const CURSOR_MODEL_DISABLED: ReadonlySet<string> = new Set(["plan", "help", "review"]);

function cursorYamlQuote(value: string): string {
  const escaped = value
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")
    .replace(/\t/g, "\\t")
    // eslint-disable-next-line no-control-regex -- byte-for-byte mirror of yamlQuote in sync-cursor-name-map.ts
    .replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, (ch) => `\\u${ch.charCodeAt(0).toString(16).padStart(4, "0")}`);
  return `"${escaped}"`;
}

export function cursorSkillName(folder: string): string {
  return CURSOR_BARE_SKILLS.has(folder) ? folder : `soleur-${folder}`;
}

export function renderCursorSkillStub(args: { folder: string; description: string | null; disableModel: boolean }): string {
  const target = args.folder === "go" || args.folder === "sync" || args.folder === "help" ? `commands/${args.folder}.md` : `skills/${args.folder}/SKILL.md`;
  const lines = ["---", `name: ${cursorSkillName(args.folder)}`];
  if (args.description !== null) lines.push(`description: ${cursorYamlQuote(args.description)}`);
  if (CURSOR_MODEL_DISABLED.has(args.folder) || args.disableModel) lines.push("disable-model-invocation: true");
  lines.push("---", "", CURSOR_STUB_HEADER, "", `Read \`${target}\`, relative to the plugin root.`, "");
  return lines.join("\n");
}

// =============================================================================
// Rendered-output gate
// =============================================================================

export interface RenderedFiles {
  skillMd: string;
  purposeMd: string;
  stub: string;
}

export type RenderedVerdict = { kind: "ok" } | CreateRefusal;

function sizeOk(text: string): boolean {
  return Buffer.byteLength(text, "utf8") <= CREATE_FILE_MAX_BYTES && text.split("\n").length - 1 <= CREATE_FILE_MAX_LINES;
}

/**
 * The gate over the RENDERED bytes (Guard 1 rows 2 and 5): non-empty, within the size caps, no PII or credential shape,
 * no fence or backtick outside the fixed Grok block, exactly the one `./PURPOSE.md` link in SKILL.md and none in
 * PURPOSE.md, exactly `name` + `description` frontmatter that matches the proposal, exactly one canonical Grok block,
 * and a stub equal to what the pure renderer produces for this skill.
 */
export function checkRenderedCreate(files: RenderedFiles, p: CreateProposal, grokBlock: string, fixedLines: readonly string[] = []): RenderedVerdict {
  for (const [label, text] of [["skill", files.skillMd], ["purpose", files.purposeMd], ["stub", files.stub]] as const) {
    if (text.trim().length === 0) return refuse("shape", `empty:${label}`);
  }
  if (!sizeOk(files.skillMd)) return refuse("shape", "size:skill");
  if (!sizeOk(files.purposeMd)) return refuse("shape", "size:purpose");
  for (const [label, text] of [["skill", files.skillMd], ["purpose", files.purposeMd], ["stub", files.stub]] as const) {
    const hit = screenProblem(text);
    if (hit) return refuse("shape", `rendered-${label}:${hit}`);
  }

  // Instruction-risk over the MODEL-DERIVED segments: the Grok block, headings, blank lines, the fixed PURPOSE link
  // line and the exact fixed lines the renderer supplied (template text, server sentences) are exempt; a golden test
  // proves those clean. A model line that merely RESEMBLES a fixed line is not exempt (exact match only).
  const exempt = new Set<string>([SKILL_PURPOSE_LINE, ...fixedLines]);
  for (const [label, text] of [["skill", files.skillMd.replace(grokBlock, "")], ["purpose", files.purposeMd]] as const) {
    const segments = text.split("\n").filter((l) => l.trim() !== "" && !l.startsWith("#") && l !== "---" && !exempt.has(l));
    if (instructionRiskProblem(segments.join("\n"))) return refuse("shape", `instruction-risk:${label}`);
  }

  // SKILL.md
  const grokCount = files.skillMd.split(GROK_START).length - 1;
  if (grokCount !== 1 || !files.skillMd.includes(grokBlock)) return refuse("shape", "grok-block");
  const outsideGrok = files.skillMd.replace(grokBlock, "");
  if (outsideGrok.includes("`") || /^\s*(?:```|~~~)/m.test(outsideGrok)) return refuse("shape", "fence:skill");
  if ((files.skillMd.match(/\]\(/g) ?? []).length !== 1 || (files.skillMd.match(/\]\(\.\/PURPOSE\.md\)/g) ?? []).length !== 1) {
    return refuse("shape", "purpose-link");
  }
  const fm = FRONTMATTER_RE.exec(files.skillMd);
  if (!fm) return refuse("shape", "frontmatter");
  let fmObj: unknown;
  try {
    fmObj = parseYaml(fm[1]);
  } catch {
    return refuse("shape", "frontmatter");
  }
  const keys = typeof fmObj === "object" && fmObj !== null ? Object.keys(fmObj) : [];
  if (keys.length !== 2 || keys[0] !== "name" || keys[1] !== "description") return refuse("shape", "frontmatter-keys");
  const rec = fmObj as Record<string, unknown>;
  if (rec.name !== p.slug || rec.description !== p.description) return refuse("shape", "frontmatter-values");

  // PURPOSE.md
  if (files.purposeMd.includes("](") || files.purposeMd.includes("`") || /^\s*(?:```|~~~)/m.test(files.purposeMd)) {
    return refuse("shape", "fence:purpose");
  }
  if (/\{\{|\}\}/.test(files.purposeMd)) return refuse("shape", "slot-left:purpose");

  // Stub
  const wantStub = renderCursorSkillStub({ folder: p.slug, description: p.description, disableModel: false });
  if (files.stub !== wantStub) return refuse("stub-drift", "stub-differs");
  return { kind: "ok" };
}

export type RenderCreateResult = { kind: "rendered"; files: RenderedFiles } | CreateRefusal;

/** Render all three files from a validated proposal and run the rendered-output gate. Template errors refuse (class shape). */
export function renderCreateFiles(args: {
  proposal: CreateProposal;
  grokBlock: string;
  purposeTemplate: string;
  date: string;
  /** Evidence entries of the chosen pattern page (`page.evidence.length`). */
  evidenceCount: number;
}): RenderCreateResult {
  let files: RenderedFiles;
  let fixed: string[];
  try {
    const opts = { date: args.date, evidenceCount: args.evidenceCount };
    fixed = purposeFixedLines(args.purposeTemplate, args.proposal, opts);
    files = {
      skillMd: renderSkillMd(args.proposal, args.grokBlock),
      purposeMd: renderPurposeMd(args.purposeTemplate, args.proposal, opts),
      stub: renderCursorSkillStub({ folder: args.proposal.slug, description: args.proposal.description, disableModel: false }),
    };
  } catch {
    return refuse("shape", "render");
  }
  const v = checkRenderedCreate(files, args.proposal, args.grokBlock, fixed);
  return v.kind === "ok" ? { kind: "rendered", files } : v;
}
