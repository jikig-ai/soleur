// WikiSkill Phase 2 (#10550) -- the PURE half of the gated new-skill create arm.
//
// The proposer never authors a file. The model returns structured fields; THIS module validates every string
// against a shape ALLOWLIST, ranks the proposal against the existing skills, checks the description budget, and
// renders SKILL.md, PURPOSE.md and the Cursor stub from fixed templates. The spawn-based gates (security scan,
// README count sync) live in `compound-promote-create-gates.ts`; the handler wiring is a later commit.
//
// Design contract (plan 2026-10-26-feat-wikiskill-phase-2-gated-new-skill-creation-plan.md, Guards 1, 2 and 4):
//   - Every numeric rule is an exported constant read by the prompt, the check and the PR-body trailer
//     (a threshold that lives only in a prompt is a request, not a constraint).
//   - Every gate fails CLOSED on input it cannot measure (malformed frontmatter, unreadable cap, empty render).
//   - Refusal `detail` values are closed tokens built from constants, never model text.
//   - Nothing here reads a secret, spawns a process or touches the network.
//
// Import-cycle note: `PII_REGEX` and `CREDENTIAL_RE` are imported from the handler module so a change there moves
// this gate (they must not be re-derived). The handler will import this module in the wiring commit, so the edge
// is a cycle; it is safe because both names are used only inside function bodies, never at module load.

import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { parse as parseYaml } from "yaml";
import { z } from "zod";
import { CREDENTIAL_RE, PII_REGEX } from "@/server/inngest/functions/cron-compound-promote";
import { fenceBlock, renderPatternIndex, untrustedDataSentence, type PatternPage } from "@/server/compound-promote-patterns";

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
/** CTO F3: hard ceiling on index + skill list; refuse, never truncate. */
export const CREATE_INPUT_MAX_TOKENS = 12000;
/**
 * The documented bound used to turn bytes into tokens: bytes / 4, rounded up. It is a heuristic (no tokenizer
 * exists under server/), measured in Phase 0 at ~9.8k tokens for the real index plus model-visible skill list.
 * Under a pessimistic bytes / 3 the real input would be ~13k; the gate states the bound it uses and refuses
 * whenever THAT bound exceeds the ceiling.
 */
export const CREATE_INPUT_BYTES_PER_TOKEN = 4;
/** CTO F3: output cap of the single create-propose call. */
export const CREATE_MAX_TOKENS = 3000;
/** The server's top-K overlap ranking the model's `nearest_skill` must appear in. */
export const OVERLAP_TOP_K = 3;
/**
 * A create is refused as `prefer-patch` when the best existing skill overlaps the proposal at or above this score
 * (IDF-weighted cosine over word stems, see `rankOverlap`). Calibrated on two synthesized evidence fixtures
 * (git-worktree, pencil-setup patch targets) and four synthetic negatives; the numbers are recorded in the
 * Phase 3 commit message and printed by the calibration test.
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

/** The `checkCreate` gates, in the order they run. A passing verdict carries the list of those that ran. */
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

// Slugs that name a command stem or a Cursor bare name; a skill may never take them.
const RESERVED_SLUGS: ReadonlySet<string> = new Set(["go", "sync", "help", "version"]);
const SLUG_FORMAT_RE = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const SLUG_MIN = 3;
const SLUG_MAX = 41;
const SKILL_NAME_RE = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
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
  purpose: { origin: string; patterns_addressed: string };
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
      overlap: { top1Name: string; top1: number; nearestRank: number; top3: string[] };
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
  /** Paths under agents/, e.g. `engineering/review/foo.md`. */
  agentPaths: readonly string[];
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
    purpose: {
      type: "object",
      additionalProperties: false,
      required: ["origin", "patterns_addressed"],
      properties: {
        origin: { type: "string" },
        patterns_addressed: { type: "string" },
      },
    },
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
  purpose: z.strictObject({ origin: z.string(), patterns_addressed: z.string() }),
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

export type ShapeKind = "description" | "item" | "field" | "ident";

const PRINTABLE_ASCII_RE = /^[\x20-\x7e]+$/;
const LEADING_OK_RE = /^[A-Za-z0-9]/;
// Characters that change how a markdown renderer, an HTML sink or the harness reads what follows.
const MARKUP_RE = /[<>[\]{}|\\$@~]/;
const URL_RE = /:\/\/|www\./i;
const RULE_ID_RE = /(?:^|[^a-z0-9])(?:hr|wg|cq|rf|pdr|cm)-[a-z0-9]/i;
const PATH_TOKEN_RE = /(?:^|[^a-z0-9])(?:scripts|references|assets|skills)\//i;
const SOLEUR_TOKEN_RE = /soleur\s*:/i;
const COMMAND_FORM_RE = /(?:^|\s)\/[A-Za-z]/;
const CLAIM_WORD_RE = /\b(?:guarantee(?:s|d)?|compliant|compliance|certified|secure|your workspace)\b/i;

function maxCharsFor(kind: ShapeKind): number {
  if (kind === "item") return CREATE_ITEM_MAX_CHARS;
  if (kind === "ident") return CREATE_SLUG_IDENT_MAX;
  return CREATE_FIELD_MAX_CHARS;
}
const CREATE_SLUG_IDENT_MAX = 60;

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
  if (CLAIM_WORD_RE.test(value)) return "claim-word";
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
    { label: "pattern_slug", value: p.pattern_slug, kind: "ident" },
    { label: "slug", value: p.slug, kind: "ident" },
    { label: "description", value: p.description, kind: "description" },
    { label: "nearest_skill", value: p.nearest_skill, kind: "ident" },
    { label: "patch_rejection_reason", value: p.patch_rejection_reason, kind: "field" },
    { label: "purpose.origin", value: p.purpose.origin, kind: "field" },
    { label: "purpose.patterns_addressed", value: p.purpose.patterns_addressed, kind: "field" },
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

function assertSlug(slug: string): void {
  if (slug.length < SLUG_MIN || slug.length > SLUG_MAX || !SLUG_FORMAT_RE.test(slug)) {
    throw new Error("create: invalid slug");
  }
}

/** The closed six-path set, in the fixed order (CTO F1). */
export function createPathList(slug: string): readonly string[] {
  assertSlug(slug);
  return [
    `plugins/soleur/skills/${slug}/SKILL.md`,
    `plugins/soleur/skills/${slug}/PURPOSE.md`,
    `plugins/soleur/cursor/skills/soleur-${slug}/SKILL.md`,
    "README.md",
    "plugins/soleur/README.md",
    PROMOTION_LOG_PATH,
  ];
}

export type PathSetVerdict = { ok: true } | { ok: false; detail: "path-count" | "unexpected-path" | "missing-path" | "duplicate-path" };

/** Set equality with the six paths: a seventh path (or a `scripts/` file) is refused; order does not matter. */
export function checkCreatePathSet(slug: string, paths: readonly string[]): PathSetVerdict {
  const want = createPathList(slug);
  if (new Set(paths).size !== paths.length) return { ok: false, detail: "duplicate-path" };
  if (paths.length > want.length) return { ok: false, detail: "path-count" };
  for (const p of paths) if (!want.includes(p)) return { ok: false, detail: "unexpected-path" };
  for (const w of want) if (!paths.includes(w)) return { ok: false, detail: "missing-path" };
  return { ok: true };
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

/** Paths under `<pluginRoot>/agents`, relative and recursive, markdown only. A missing directory is `[]`. */
export function readAgentPaths(pluginRoot: string): string[] {
  const out: string[] = [];
  const walk = (dir: string, prefix: string): void => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      const rel = prefix ? `${prefix}/${e.name}` : e.name;
      if (e.isDirectory()) walk(join(dir, e.name), rel);
      else if (e.isFile() && e.name.endsWith(".md")) out.push(rel);
    }
  };
  walk(join(pluginRoot, "agents"), "");
  return out;
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
 * The cluster hash over a pattern's evidence keys. Byte-identical to `computeClusterHash` in the handler (sorted,
 * newline-joined, trailing newline, sha256 hex), so the branch, PR title and ledger shapes are unchanged and a
 * pattern with an existing patch PR is suppressed for create too (CTO F2).
 */
export function createClusterHash(evidence: readonly string[]): string {
  const sorted = [...evidence].sort();
  return createHash("sha256")
    .update(sorted.join("\n") + "\n")
    .digest("hex");
}

// =============================================================================
// Prompt (reads every constant)
// =============================================================================

export type PrepareCreateResult =
  | CreateRefusal
  | { kind: "ready"; prompt: string; maxTokens: number; inputBytes: number; inputTokensBound: number };

/**
 * Build the single create-propose prompt, or refuse before any model call. The input is the pattern index plus the
 * MODEL-VISIBLE skill list (a user-invoked skill is not offered as a nearest skill); over the ceiling is refused,
 * never truncated. The bound used is `CREATE_INPUT_BYTES_PER_TOKEN` and is stated in the refusal numbers.
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
  return { kind: "ready", prompt, maxTokens: CREATE_MAX_TOKENS, inputBytes, inputTokensBound };
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
  if (p.slug.length < SLUG_MIN || p.slug.length > SLUG_MAX || !SLUG_FORMAT_RE.test(p.slug)) return refuse("slug", "format");
  gates.push("slug-format");

  // shape over EVERY model string
  const strings = collectModelStrings(p);
  if (strings.length < 11) return refuse("model-invalid", "no-strings"); // the minimum a valid create carries
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
  if (RESERVED_SLUGS.has(p.slug)) return refuse("slug", "reserved");
  if (c.skillDirs.includes(p.slug) || c.skills.some((s) => s.name === p.slug)) return refuse("slug", "skill-exists");
  const agents = agentNames(c.agentPaths);
  if (agents.leaves.has(p.slug)) return refuse("slug", "agent-exists");
  if (agents.cursor.has(`soleur-${p.slug}`)) return refuse("slug", "cursor-name-exists");
  const slugPrefixes = [`plugins/soleur/skills/${p.slug}/`, `plugins/soleur/cursor/skills/soleur-${p.slug}/`];
  if (c.openPrPaths.some((path) => slugPrefixes.some((pre) => path.startsWith(pre)))) return refuse("slug", "open-pr-slug");
  gates.push("collision");

  // prefer-patch
  if (c.skills.length === 0) return refuse("prefer-patch", "no-skill-list");
  if (!SKILL_NAME_RE.test(p.nearest_skill) || !c.skills.some((s) => s.name === p.nearest_skill)) return refuse("prefer-patch", "nearest-missing");
  const ranked = rankOverlap(proposalOverlapText(p), c.skills);
  const names = ranked.map((r) => r.name);
  const nearestRank = names.indexOf(p.nearest_skill) + 1;
  const top3 = names.slice(0, OVERLAP_TOP_K);
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
    overlap: { top1Name: ranked[0].name, top1, nearestRank, top3 },
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
      "See [PURPOSE.md](./PURPOSE.md) for why this skill exists, the nearest existing skill, and its history.",
    ].join("\n") + "\n"
  );
}

/**
 * PURPOSE.md: fills the closed slot set of the template (the single source of the headings and the fixed
 * attribution). The template is validated against the closed slot set first; model text is substituted in ONE pass so
 * a slot-looking string in a model field is never re-expanded.
 */
export function renderPurposeMd(template: string, p: CreateProposal, opts: { date: string }): string {
  if (!DATE_RE.test(opts.date)) throw new Error("create: bad date");
  const found = [...template.matchAll(/\{\{([^{}]*)\}\}/g)].map((m) => m[1]);
  const want = new Set<string>(PURPOSE_TEMPLATE_SLOTS);
  if (found.some((s) => !want.has(s)) || [...want].some((s) => !found.includes(s))) throw new Error("create: purpose template slot set changed");
  if (template.replace(/\{\{[A-Z_]+\}\}/g, "").match(/\{\{|\}\}/)) throw new Error("create: purpose template slot malformed");
  const values: Record<(typeof PURPOSE_TEMPLATE_SLOTS)[number], string> = {
    SKILL_NAME: p.slug,
    ORIGIN: p.purpose.origin,
    PATTERNS_ADDRESSED: `- ${p.pattern_slug}\n\n${p.purpose.patterns_addressed}`,
    NEAREST_SKILL: `Nearest existing skill: ${p.nearest_skill}.`,
    PATCH_REJECTION_REASON: p.patch_rejection_reason,
    MERGE_RETIRE_CANDIDATES: p.merge_retire_candidates.length > 0 ? bullets(p.merge_retire_candidates) : "- None identified.",
    EVOLUTION_HISTORY: `- ${opts.date}: created as a draft by the automated proposer from the pattern page named above, pending human review.`,
  };
  return template.replace(/\{\{([A-Z_]+)\}\}/g, (_m, slot: keyof typeof values) => values[slot]);
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

export type RenderedVerdict = { kind: "ok"; filesChecked: number } | CreateRefusal;

function sizeOk(text: string): boolean {
  return Buffer.byteLength(text, "utf8") <= CREATE_FILE_MAX_BYTES && text.split("\n").length - 1 <= CREATE_FILE_MAX_LINES;
}

/**
 * The gate over the RENDERED bytes (Guard 1 rows 2 and 5): non-empty, within the size caps, no PII or credential shape,
 * no fence or backtick outside the fixed Grok block, exactly the one `./PURPOSE.md` link in SKILL.md and none in
 * PURPOSE.md, exactly `name` + `description` frontmatter that matches the proposal, exactly one canonical Grok block,
 * and a stub equal to what the pure renderer produces for this skill.
 */
export function checkRenderedCreate(files: RenderedFiles, p: CreateProposal, grokBlock: string): RenderedVerdict {
  for (const [label, text] of [["skill", files.skillMd], ["purpose", files.purposeMd], ["stub", files.stub]] as const) {
    if (text.trim().length === 0) return refuse("shape", `empty:${label}`);
  }
  if (!sizeOk(files.skillMd)) return refuse("shape", "size:skill");
  if (!sizeOk(files.purposeMd)) return refuse("shape", "size:purpose");
  for (const [label, text] of [["skill", files.skillMd], ["purpose", files.purposeMd], ["stub", files.stub]] as const) {
    const hit = screenProblem(text);
    if (hit) return refuse("shape", `rendered-${label}:${hit}`);
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
  return { kind: "ok", filesChecked: 3 };
}

export type RenderCreateResult = { kind: "rendered"; files: RenderedFiles } | CreateRefusal;

/** Render all three files from a validated proposal and run the rendered-output gate. Template errors refuse (class shape). */
export function renderCreateFiles(args: { proposal: CreateProposal; grokBlock: string; purposeTemplate: string; date: string }): RenderCreateResult {
  let files: RenderedFiles;
  try {
    files = {
      skillMd: renderSkillMd(args.proposal, args.grokBlock),
      purposeMd: renderPurposeMd(args.purposeTemplate, args.proposal, { date: args.date }),
      stub: renderCursorSkillStub({ folder: args.proposal.slug, description: args.proposal.description, disableModel: false }),
    };
  } catch {
    return refuse("shape", "render");
  }
  const v = checkRenderedCreate(files, args.proposal, args.grokBlock);
  return v.kind === "ok" ? { kind: "rendered", files } : v;
}
