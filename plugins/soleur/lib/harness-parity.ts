/**
 * Harness parity — every component reference in plugin prose is the canonical `soleur:<name>`.
 *
 * ADR-226 (#8299). A skill, command or agent named in a SKILL.md / command doc is read by an
 * agent on FOUR harnesses (Claude, Grok Build, Codex, Devin), and each harness has its own
 * invocation syntax (`/plan`, `/soleur:plan`, `$soleur:plan`, `soleur:plan`). The doc must name
 * the component in the one shape every adapter resolves — `soleur:<name>` for skills and
 * commands, the registry id for agents — and leave rendering to `formatSkillInvocation` /
 * `spawnAgent` in `harness.ts`.
 *
 * This module is an ALLOWLIST over a closed index (AP-025 / ADR-202: a state predicate is
 * complete by construction; a list of forbidden forms cannot be proven complete). The index is
 * derived from the tree, never listed: skill directories, command files, and the agent registry
 * (`discoverAgentPaths()` — the same function Grok's compat stubs are generated from). Anything
 * that names a known component in a context the allowlist does not admit is NONCANONICAL.
 *
 * Four chokepoints, none a member list (plan v3 §Guard Contract):
 *   1. POPULATION_GLOBS — which docs are examined, each carrying its region policy;
 *   2. INDEX_GLOBS + the registry — which names are known;
 *   3. classifyDoc — the single verdict site: BOUNDARY, the path class, the token class, the
 *      trailing-glue strip, rules R1–R9 and the marker grammar;
 *   4. the tree test's own literal pathspecs for the index invariant (harness-parity-tree.test.ts).
 * `census` folds and `fixDoc` inverts; neither decides.
 *
 * The permanent fixtures in test/harness-parity.test.ts pin every constant below. Weakening the
 * gate means editing a constant AND the fixture that pins it, in one reviewable diff.
 */

import { execFileSync } from "child_process";
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  PLUGIN_ROOT,
  discoverAgentPaths,
  pathToAgentId,
  agentIdToGrokSubagentType,
} from "./agent-registry";

export type RegionPolicy = "skill" | "command";

export type Verdict = "CANONICAL" | "BARE" | "PATH" | "NONCANONICAL" | "UNKNOWN-NS" | "EXEMPT";

/** Which rule produced a NONCANONICAL verdict — the census's shape split. */
export type Shape =
  | "ns-sigil" // R1: `/soleur:x`, `$soleur:x`, `/soleur:<metavar>`
  | "agent-mention" // R4: `@agent-soleur:product:cpo`
  | "grok-stem" // R5: `soleur-product-cpo` in prose
  | "sigil-skill" // R8: `/plan`, `$plan`, `%plan`
  | "bare-agent-leaf" // R6b: `Task cpo(…)`, "the `cpo`"
  | "sigil-agent-leaf" // R6b with a sigil: `/cpo`
  | "hyphen-absorbed"; // R9: `@agent-cpo`, `@agent-soleur-product-cpo`

/**
 * Harness attribution decorates the message and the report split. It is a LOCAL lookup over
 * (shape, preceding character) and never participates in the verdict, so an incomplete table
 * cannot blind the gate — `unrecognised` is the catch-all.
 */
export type Attribution =
  | "grok" // `/name` (grok slash) or a hyphen stem
  | "claude-devin" // `/soleur:name`
  | "codex" // `$soleur:name`
  | "claude-agent" // `@agent-soleur:…`
  | "claude-leaf" // `@agent-<leaf>`
  | "grok-stem" // `soleur-a-b` in prose
  | "bare-leaf" // an agent leaf with no namespace — dead on grok
  | "unrecognised"; // any sigil nobody has thought of

export interface PopulationGlob {
  readonly pathspec: string;
  readonly regionPolicy: RegionPolicy;
}

/**
 * The names the index is built from. Separate from POPULATION_GLOBS on purpose (spec-flow #7b):
 * emptying the population fires "0 docs examined", never the index invariant, and vice versa.
 * `:(glob)` magic is load-bearing — a plain `skills/*\/SKILL.md` pathspec crosses `/` in git and
 * would enumerate `skills/x/references/SKILL.md` as a skill named `references` (arch F5).
 */
export const INDEX_GLOBS = {
  skills: ":(glob)plugins/soleur/skills/*/SKILL.md",
  commands: ":(glob)plugins/soleur/commands/*.md",
} as const;

/**
 * The docs examined. `regionPolicy` is derived from WHICH glob matched, so one constant carries
 * both membership and policy; widening the population is one line (NG-P, #8317).
 */
export const POPULATION_GLOBS: readonly PopulationGlob[] = [
  { pathspec: ":(glob)plugins/soleur/skills/*/SKILL.md", regionPolicy: "skill" },
  { pathspec: ":(glob)plugins/soleur/commands/*.md", regionPolicy: "command" },
  // The Codex and Devin front doors: the same routing prose one harness over (arch F6).
  { pathspec: ":(glob)plugins/soleur/codex/skills/*/SKILL.md", regionPolicy: "skill" },
  { pathspec: ":(glob)plugins/soleur/devin/skills/*/SKILL.md", regionPolicy: "skill" },
];

/** Docs excluded by path, each with the reason it is not wrapped in a region instead. */
export const EXCLUDED_BY_PATH: ReadonlyMap<string, string> = new Map([
  [
    "plugins/soleur/commands/help.md",
    "its subject is the per-harness typed forms; 117 of 155 lines would be region-exempt, which is a whole-file exemption wearing markers (DHH #5)",
  ],
]);

/**
 * BOUNDARY — the allowlist of characters permitted immediately before a reference. Each member
 * has a measured prose reason; no harness uses any of them as an invocation sigil (every
 * `formatSkillInvocation` branch and `formatAgentSpawn` read). Anything NOT in the set — `/`,
 * `$`, `@`, `!`, `%`, `~`, `\`, and any character nobody has thought of — is a sigil. Authors
 * who collide with the set (a shell `$work`, a glob `"$d"/rclone-*`) brace or rename the
 * identifier; BOUNDARY is never widened to admit a sigil.
 */
export const BOUNDARY: ReadonlySet<string> = new Set([
  " ", // whitespace — prose
  "\t",
  "`", // inline code: `soleur:plan`
  '"', // quoted string
  "'",
  "(", // parenthetical / call: Skill(soleur:go)
  "[", // markdown link text
  "{", // brace: `${work}` — the sanctioned way to keep a shell variable out of the gate
  "*", // emphasis: **work**
  "<", // angle: <plan>
  ">", // blockquote / angle close
  "|", // table cell
  ",", // list separator
  ";",
  ".", // dotfile / extension: `.go`
  "=", // KEY=value
  "+", // plan+work
  "&", // URL query and shell `&&`
  "?", // URL query
  "#", // markdown anchor `#plan-heading` and issue refs `#NNNN` (simplicity F6)
  "→", // plan→work
  "—", // em dash
  "–", // en dash
]);

/**
 * The path class — the SECOND verdict-deciding allowlist. `pathctx` holds when the character
 * before the token is `/` and the character before THAT is a path character, so `skills/plan`,
 * `./plan`, `https://a/plan` and `../plan` are path components while `` `/plan` `` and `(/plan)`
 * are grok slashes. Its own fixture (path.md) and mutation row (N5b — add a backtick here and
 * grok-slash.md goes PATH).
 */
export const PATH_PREV = /[A-Za-z0-9_./]/;

/**
 * The token class: a maximal run of `[A-Za-z0-9_:-]`. `:` so `soleur:product:cpo` is one token;
 * `-` so `deepen-plan` and `re-plan` are whole tokens that name nothing rather than a bare `plan`
 * (N5c). `_` for shell identifiers.
 */
export const TOKEN = /[A-Za-z0-9_:-]+/g;

/**
 * Trailing glue stripped for index lookup only: `/ship:` and `/work:` glued the colon and escaped
 * the index in v2 (Kieran #1). The RAW token is kept for R1/R4 so `/soleur:<metavar>` still trips
 * the namespace sentinel, and for the printed site.
 */
export const TRAILING_GLUE = /[:_-]+$/;

/** The one region kind, honoured only where regionPolicy is `command`. */
export const HONOURED_REGION = "harness-forms";

/**
 * Marker grammar (arch F4, spec-flow #7a, Kieran #9). A marker is a whole line that, after
 * trimming spaces and tabs ONLY, equals the strict form byte-for-byte. A line the loose form
 * matches but the strict form does not is RED "malformed marker" — case, CRLF (the `\r`
 * survives the trim on purpose), inline text. Markers with any OTHER name are transparent:
 * ordinary content lines that never open or close anything.
 */
export const MARKER_STRICT = /^<!-- harness-forms:(start|end) -->$/;
export const MARKER_LOOSE = /<!--\s*harness-forms\s*:\s*(start|end)\s*-->/i;

export interface Index {
  /** Skill directory names ∪ command basenames (`plan`, `go`, …). */
  readonly skillNames: ReadonlySet<string>;
  /** `soleur:<skill|command>` ∪ registry agent ids — 165 today. */
  readonly canonicalIds: ReadonlySet<string>;
  /** Registry agent ids, in discovery order. */
  readonly agentIds: readonly string[];
  /** Last `:` segment of each agent id → id. Leaves are unique (asserted by the tree test). */
  readonly agentLeaves: ReadonlyMap<string, string>;
  /** `agentIdToGrokSubagentType(id)` → id. */
  readonly grokStems: ReadonlyMap<string, string>;
}

export interface Doc {
  readonly path: string;
  readonly text: string;
  readonly regionPolicy: RegionPolicy;
}

export interface Site {
  readonly path: string;
  readonly line: number;
  readonly col: number;
  /** The token as matched, trailing glue included. */
  readonly raw: string;
  /** `raw` with trailing glue stripped — the index key. */
  readonly token: string;
  /** The character before the token; `"\n"` at line start. */
  readonly before: string;
  readonly verdict: Verdict;
  readonly shape?: Shape;
  readonly attribution?: Attribution;
  /** The canonical id to write instead. */
  readonly fix?: string;
  /** `path:line: <site> — <attribution>; write <fix>[ — tail]`; empty for permitted verdicts. */
  readonly message: string;
}

export interface DocResult {
  readonly path: string;
  readonly regionPolicy: RegionPolicy;
  readonly sites: readonly Site[];
  /** Marker-grammar errors; any entry is RED for the doc. */
  readonly errors: readonly string[];
  readonly counts: Readonly<Record<Verdict, number>>;
}

export interface CensusResult {
  readonly docs: readonly DocResult[];
  readonly docsExamined: number;
  readonly docsWithNoncanonical: number;
  readonly totals: Readonly<Record<Verdict, number>>;
  readonly noncanonical: readonly Site[];
  readonly unknownNs: readonly Site[];
  readonly errors: readonly string[];
  readonly attribution: Readonly<Record<Attribution, number>>;
}

const VERDICTS: readonly Verdict[] = ["CANONICAL", "BARE", "PATH", "NONCANONICAL", "UNKNOWN-NS", "EXEMPT"];
const ATTRIBUTIONS: readonly Attribution[] = [
  "grok",
  "claude-devin",
  "codex",
  "claude-agent",
  "claude-leaf",
  "grok-stem",
  "bare-leaf",
  "unrecognised",
];

function zeroCounts<K extends string>(keys: readonly K[]): Record<K, number> {
  return Object.fromEntries(keys.map((k) => [k, 0])) as Record<K, number>;
}

/** Repo root derived from the module's own location, so `bun test` from `plugins/soleur/` resolves (spec-flow #7d). */
export const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");

/** `git ls-files --full-name <pathspecs>` from REPO_ROOT — the pathspecs are repo-rooted, never cwd-relative. */
function gitLsFiles(pathspecs: readonly string[]): string[] {
  const out = execFileSync("git", ["ls-files", "--full-name", "--", ...pathspecs], {
    cwd: REPO_ROOT,
    encoding: "utf-8",
  });
  return out.split("\n").filter((l) => l.length > 0);
}

/** Read the index from the tree: never a listed set. */
export function readIndex(): Index {
  const skills = gitLsFiles([INDEX_GLOBS.skills]).map((p) => {
    const parts = p.split("/");
    return parts[parts.length - 2];
  });
  const commands = gitLsFiles([INDEX_GLOBS.commands]).map((p) => {
    const parts = p.split("/");
    return parts[parts.length - 1].replace(/\.md$/, "");
  });
  const agentIds = discoverAgentPaths().map(pathToAgentId);
  const skillNames = new Set([...skills, ...commands]);
  const canonicalIds = new Set([...[...skillNames].map((n) => `soleur:${n}`), ...agentIds]);
  const agentLeaves = new Map<string, string>();
  const grokStems = new Map<string, string>();
  for (const id of agentIds) {
    const leaf = id.split(":").pop() as string;
    agentLeaves.set(leaf, id);
    grokStems.set(agentIdToGrokSubagentType(id), id);
  }
  return { skillNames, canonicalIds, agentIds, agentLeaves, grokStems };
}

/** Turn a `:(glob)` pathspec into a regex over the full repo-relative path. */
function globToRegex(pathspec: string): RegExp {
  const body = pathspec.replace(/^:\(glob\)/, "");
  const escaped = body.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, "[^/]+");
  return new RegExp(`^${escaped}$`);
}

/** Which policy a repo-relative path carries, derived from the matching population glob. */
export function regionPolicyForPath(
  path: string,
  globs: readonly PopulationGlob[] = POPULATION_GLOBS,
): RegionPolicy | undefined {
  for (const g of globs) if (globToRegex(g.pathspec).test(path)) return g.regionPolicy;
  return undefined;
}

/** The only I/O in the module besides readIndex: enumerate the population and read each doc. */
export function readPopulation(globs: readonly PopulationGlob[] = POPULATION_GLOBS): Doc[] {
  const docs: Doc[] = [];
  const seen = new Set<string>();
  for (const g of globs) {
    for (const path of gitLsFiles([g.pathspec])) {
      if (seen.has(path) || EXCLUDED_BY_PATH.has(path)) continue;
      seen.add(path);
      docs.push({ path, text: readFileSync(resolve(REPO_ROOT, path), "utf-8"), regionPolicy: g.regionPolicy });
    }
  }
  return docs;
}

interface Classified {
  verdict: Verdict;
  shape?: Shape;
  fix?: string;
}

/**
 * Classify one token. `raw` as matched, `before` the preceding character (`"\n"` at line start),
 * `prev2` the character before that (`""` when absent).
 */
function classifyToken(raw: string, before: string, prev2: string, index: Index): Classified | undefined {
  const t = raw.replace(TRAILING_GLUE, "");
  const atb = before === "\n" || BOUNDARY.has(before);
  const pathctx = before === "/" && PATH_PREV.test(prev2);

  // R1–R3: the namespace sentinel. `raw`, not `t`, so `/soleur:<metavar>` (raw `soleur:`) trips R1.
  if (raw.startsWith("soleur:")) {
    if (!atb) return { verdict: "NONCANONICAL", shape: "ns-sigil", fix: raw.replace(TRAILING_GLUE, "") || raw };
    return index.canonicalIds.has(t) ? { verdict: "CANONICAL" } : { verdict: "UNKNOWN-NS" };
  }
  // R4: `@agent-soleur:product:cpo` — the namespace appears inside the token.
  if (raw.includes("soleur:")) {
    const at = raw.indexOf("soleur:");
    return { verdict: "NONCANONICAL", shape: "agent-mention", fix: raw.slice(at).replace(TRAILING_GLUE, "") };
  }
  // R5 / R7: a grok hyphen stem, derived by the adapter's own function.
  const stemId = index.grokStems.get(t);
  if (stemId !== undefined) {
    return pathctx ? { verdict: "PATH" } : { verdict: "NONCANONICAL", shape: "grok-stem", fix: stemId };
  }
  // R6 / R7 / R8: a skill or command name.
  if (index.skillNames.has(t)) {
    if (atb) return { verdict: "BARE" };
    if (pathctx) return { verdict: "PATH" };
    return { verdict: "NONCANONICAL", shape: "sigil-skill", fix: `soleur:${t}` };
  }
  // R6b / R7: an agent leaf. Never a prose word; a bare leaf maps to no Grok stub.
  const leafId = index.agentLeaves.get(t);
  if (leafId !== undefined) {
    if (pathctx) return { verdict: "PATH" };
    return { verdict: "NONCANONICAL", shape: atb ? "bare-agent-leaf" : "sigil-agent-leaf", fix: leafId };
  }
  // R9: a sigil absorbed into a hyphenated token (`@agent-cpo`, `$x-plan`). Path components
  // (`…-feature-plan.md`) are excluded by the pathctx clause; prose compounds after whitespace
  // (`deepen-plan`, `re-plan`) never reach here because they are atb.
  if (!atb && !pathctx) {
    const parts = t.split("-");
    for (let i = 1; i < parts.length; i++) {
      const suffix = parts.slice(i).join("-");
      if (index.skillNames.has(suffix)) return { verdict: "NONCANONICAL", shape: "hyphen-absorbed", fix: `soleur:${suffix}` };
      const leaf = index.agentLeaves.get(suffix);
      if (leaf !== undefined) return { verdict: "NONCANONICAL", shape: "hyphen-absorbed", fix: leaf };
      const stem = index.grokStems.get(suffix);
      if (stem !== undefined) return { verdict: "NONCANONICAL", shape: "hyphen-absorbed", fix: stem };
    }
  }
  return undefined;
}

/** Local decoration: which harness's form this is. Never a verdict input. */
function attribute(shape: Shape, before: string): Attribution {
  switch (shape) {
    case "ns-sigil":
      return before === "/" ? "claude-devin" : before === "$" ? "codex" : "unrecognised";
    case "sigil-skill":
      return before === "/" ? "grok" : "unrecognised";
    case "agent-mention":
      return before === "@" ? "claude-agent" : "unrecognised";
    case "hyphen-absorbed":
      return before === "@" ? "claude-leaf" : "unrecognised";
    case "grok-stem":
      return "grok-stem";
    case "bare-agent-leaf":
      return "bare-leaf";
    case "sigil-agent-leaf":
      return "unrecognised";
  }
}

const ATTRIBUTION_LABEL: Readonly<Record<Attribution, string>> = {
  grok: "grok",
  "claude-devin": "claude/devin",
  codex: "codex",
  "claude-agent": "claude",
  "claude-leaf": "claude",
  "grok-stem": "grok",
  "bare-leaf": "bare agent leaf, dead on grok",
  unrecognised: "unrecognised sigil",
};

const BRACE_TAIL = " — or, if this is not a component reference, brace/rename the identifier";

/** Classify one doc. Pure: `text` in, sites and marker errors out. */
export function classifyDoc(text: string, index: Index, regionPolicy: RegionPolicy, path = "<doc>"): DocResult {
  const sites: Site[] = [];
  const errors: string[] = [];
  const counts = zeroCounts(VERDICTS);
  const lines = text.split("\n");
  let regionOpenAt: number | undefined;

  lines.forEach((line, i) => {
    const lineNo = i + 1;
    const trimmed = line.replace(/^[ \t]+|[ \t]+$/g, "");
    const strict = MARKER_STRICT.exec(trimmed);
    if (strict) {
      if (strict[1] === "start") {
        if (regionOpenAt !== undefined) errors.push(`${path}:${lineNo}: ${HONOURED_REGION}:start while a region is open`);
        else regionOpenAt = lineNo;
      } else if (regionOpenAt === undefined) {
        errors.push(`${path}:${lineNo}: stray ${HONOURED_REGION}:end with no open region`);
      } else {
        regionOpenAt = undefined;
      }
      return;
    }
    if (MARKER_LOOSE.test(line)) {
      errors.push(`${path}:${lineNo}: malformed marker ${JSON.stringify(line)} — expected exactly <!-- ${HONOURED_REGION}:start --> or <!-- ${HONOURED_REGION}:end --> on its own line`);
      return;
    }
    const exempt = regionOpenAt !== undefined && regionPolicy === "command";

    for (const m of line.matchAll(TOKEN)) {
      const raw = m[0];
      const s = m.index ?? 0;
      const before = s > 0 ? line[s - 1] : "\n";
      const prev2 = s > 1 ? line[s - 2] : "";
      const c = classifyToken(raw, before, prev2, index);
      if (c === undefined) continue;
      const token = raw.replace(TRAILING_GLUE, "");
      let verdict = c.verdict;
      if (exempt && verdict === "NONCANONICAL") verdict = "EXEMPT";
      counts[verdict] += 1;
      if (verdict !== "NONCANONICAL") {
        sites.push({ path, line: lineNo, col: s + 1, raw, token, before, verdict, message: "" });
        continue;
      }
      const shape = c.shape as Shape;
      const attribution = attribute(shape, before);
      // Printed as `before + raw` when the sigil is a character, so found and fix never read
      // identically (spec-flow #6); bare leaves print the token alone.
      const atb = before === "\n" || BOUNDARY.has(before);
      const site = atb ? raw : `${before}${raw}`;
      const tail = attribution === "unrecognised" || attribution === "bare-leaf" ? BRACE_TAIL : "";
      const message = `${path}:${lineNo}: ${site} — ${ATTRIBUTION_LABEL[attribution]}; write ${c.fix}${tail}`;
      sites.push({ path, line: lineNo, col: s + 1, raw, token, before, verdict, shape, attribution, fix: c.fix, message });
    }
  });

  if (regionOpenAt !== undefined) errors.push(`${path}:${regionOpenAt}: ${HONOURED_REGION}:start never closed`);
  return { path, regionPolicy, sites, errors, counts };
}

/** Fold per-doc results. Throws on an empty population (N4) — a clean census over nothing is not clean. */
export function census(docs: readonly Doc[], index: Index): CensusResult {
  if (docs.length === 0) throw new Error("harness-parity: 0 docs examined");
  const results = docs.map((d) => classifyDoc(d.text, index, d.regionPolicy, d.path));
  const totals = zeroCounts(VERDICTS);
  const attribution = zeroCounts(ATTRIBUTIONS);
  const noncanonical: Site[] = [];
  const unknownNs: Site[] = [];
  const errors: string[] = [];
  let docsWithNoncanonical = 0;
  for (const r of results) {
    for (const v of VERDICTS) totals[v] += r.counts[v];
    errors.push(...r.errors);
    let any = false;
    for (const s of r.sites) {
      if (s.verdict === "NONCANONICAL") {
        any = true;
        noncanonical.push(s);
        attribution[s.attribution as Attribution] += 1;
      } else if (s.verdict === "UNKNOWN-NS") {
        unknownNs.push(s);
      }
    }
    if (any) docsWithNoncanonical += 1;
  }
  return { docs: results, docsExamined: results.length, docsWithNoncanonical, totals, noncanonical, unknownNs, errors, attribution };
}

/**
 * The mechanical inverse for the sigil-plus-known-name shapes: `/soleur:x` and `$soleur:x` (R1),
 * `@agent-soleur:x` (R4), and grok `/x` for a known skill (R8). Never a bare leaf or a hyphen
 * mention (the sentence around them changes — hand edits), never an honoured region, never `$x` (a shell
 * variable that happens to be a skill name is braced by the author, not rewritten). Idempotent:
 * every rewrite yields a canonical token that classifies R2 on the next pass.
 */
export function fixDoc(text: string, index: Index, regionPolicy: RegionPolicy = "skill"): string {
  let inRegion = false;
  return text
    .split("\n")
    .map((line) => {
      // Mirror the classifier's region state so a `command` doc's honoured region is left alone;
      // malformed markers are content here (the classifier reports them, the fixer never edits them).
      const strict = MARKER_STRICT.exec(line.replace(/^[ \t]+|[ \t]+$/g, ""));
      if (strict) {
        inRegion = strict[1] === "start";
        return line;
      }
      if (inRegion && regionPolicy === "command") return line;
      let out = "";
      let last = 0;
      for (const m of line.matchAll(TOKEN)) {
        const raw = m[0];
        const s = m.index ?? 0;
        const before = s > 0 ? line[s - 1] : "\n";
        const prev2 = s > 1 ? line[s - 2] : "";
        const c = classifyToken(raw, before, prev2, index);
        if (c === undefined || c.verdict !== "NONCANONICAL") continue;
        let replacement: string | undefined;
        if (c.shape === "ns-sigil" && (before === "/" || before === "$")) replacement = raw;
        else if (c.shape === "agent-mention" && before === "@" && raw.startsWith("agent-soleur:")) replacement = raw.slice("agent-".length);
        else if (c.shape === "sigil-skill" && before === "/") replacement = `soleur:${raw}`;
        if (replacement === undefined) continue;
        out += line.slice(last, s - 1) + replacement;
        last = s + raw.length;
      }
      return out + line.slice(last);
    })
    .join("\n");
}

/** Human report for the CLI and the tree test's failure output. */
export function formatReport(result: CensusResult): string {
  const lines: string[] = [];
  lines.push(
    `harness-parity: ${result.docsExamined} docs examined, ${result.noncanonical.length} non-canonical sites in ${result.docsWithNoncanonical} docs, ` +
      `${result.totals.CANONICAL} canonical, ${result.unknownNs.length} unknown-ns, ${result.totals.EXEMPT} exempt, ${result.errors.length} marker errors`,
  );
  lines.push(
    "attribution: " + ATTRIBUTIONS.map((a) => `${a} ${result.attribution[a]}`).join(" / "),
  );
  const perDoc = result.docs
    .filter((d) => d.counts.NONCANONICAL > 0)
    .sort((a, b) => b.counts.NONCANONICAL - a.counts.NONCANONICAL)
    .map((d) => `  ${d.counts.NONCANONICAL}\t${d.path}`);
  if (perDoc.length > 0) lines.push("docs:", ...perDoc);
  if (result.unknownNs.length > 0) {
    lines.push("unknown-ns:", ...result.unknownNs.map((s) => `  ${s.path}:${s.line}: ${s.raw}`));
  }
  if (result.errors.length > 0) lines.push("marker errors:", ...result.errors.map((e) => `  ${e}`));
  if (result.noncanonical.length > 0) lines.push("sites:", ...result.noncanonical.map((s) => `  ${s.message}`));
  return lines.join("\n");
}
