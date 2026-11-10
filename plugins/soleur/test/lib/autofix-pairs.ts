/**
 * The ONE parser for `AUTOFIX_PAIRS` in plugins/soleur/skills/model-launch-review/scripts/audit-models.sh.
 *
 * Two suites are driven by that table: plugins/soleur/test/model-launch-review.test.ts (the auditor's own
 * behaviour) and apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts (every RHS id must be
 * known by both pinned Claude platform binaries). A hand-copied parser per suite is how two readings of one
 * table drift apart, so both import this module. It is pure (no disk read; the callers read the script) so every
 * parse rule is exercised on synthetic sources.
 *
 * Rules (each one has a synthetic row in claude-cli-pin-knows-models.test.ts):
 *   - The block opens at a line starting `AUTOFIX_PAIRS=(` and ends at the first line that is ONLY `)`.
 *     A `)` inside a comment line does not end it (the old `/AUTOFIX_PAIRS=\(([\s\S]*?)\)/` read stopped there).
 *   - A comment line (first non-blank character `#`) is not a pair, so a commented-out pair is not live.
 *   - On a live line everything from an unquoted `#` on is a comment: `"a=b"  # was "c=d"` is ONE pair (a=b).
 *   - Every live token must be `from=to` (double-quoted or bare); anything else throws instead of being dropped.
 *   - No block, two blocks, or a block with no closing `)` line throws; it is never read as zero pairs.
 *
 * Floors live in `assertPairFloors`, separate from the parser, so a two-pair synthetic source exercises the
 * parser without tripping them.
 */

export type AutofixPair = readonly [from: string, to: string];

/** Raw pair count floor. 8 pairs before Haiku 5.5, +2 (dated and undated Haiku 4.5), +1 at Fable 5.2 = 11. */
export const MIN_AUTOFIX_PAIRS = 11;
/** Distinct RHS (current-id) floor: opus, sonnet, haiku, fable tiers. */
export const MIN_DISTINCT_TARGETS = 4;

const OPEN_RE = /^[ \t]*AUTOFIX_PAIRS=\((.*)$/;
const CLOSE_RE = /^[ \t]*\)[ \t]*$/;
const PAIR_RE = /^([^\s"=#]+)=([^\s"=#]+)$/;

/** Split one live line into its words, honouring double quotes and stopping at an unquoted `#`. */
function lineTokens(line: string, lineNo: number): string[] {
  const tokens: string[] = [];
  let cur = "";
  let inWord = false;
  let quoted = false;
  for (const ch of line) {
    if (quoted) {
      if (ch === '"') quoted = false;
      else cur += ch;
      continue;
    }
    if (ch === '"') {
      quoted = true;
      inWord = true;
      continue;
    }
    if (ch === " " || ch === "\t") {
      if (inWord) tokens.push(cur);
      cur = "";
      inWord = false;
      continue;
    }
    // Bash starts a comment only at the beginning of a word.
    if (ch === "#" && !inWord) break;
    cur += ch;
    inWord = true;
  }
  if (quoted) throw new Error(`AUTOFIX_PAIRS_PARSE: unterminated quote on audit-models.sh line ${lineNo}`);
  if (inWord) tokens.push(cur);
  return tokens;
}

/** Every live `from=to` pair of the `AUTOFIX_PAIRS=( ... )` block in `src`, in table order. */
export function parseAutofixPairs(src: string): AutofixPair[] {
  const lines = src.split("\n");
  const opens = lines.flatMap((l, i) => (OPEN_RE.test(l) ? [i] : []));
  if (opens.length !== 1) {
    throw new Error(
      `AUTOFIX_PAIRS_PARSE: expected exactly one line starting \`AUTOFIX_PAIRS=(\`, found ${opens.length}`,
    );
  }
  const start = opens[0];
  const body: Array<[string, number]> = [[OPEN_RE.exec(lines[start])![1], start + 1]];
  let closed = false;
  for (let i = start + 1; i < lines.length; i += 1) {
    if (CLOSE_RE.test(lines[i])) {
      closed = true;
      break;
    }
    body.push([lines[i], i + 1]);
  }
  if (!closed) throw new Error("AUTOFIX_PAIRS_PARSE: the AUTOFIX_PAIRS block has no closing line that is only `)`");

  const pairs: AutofixPair[] = [];
  for (const [line, lineNo] of body) {
    if (/^[ \t]*#/.test(line)) continue;
    for (const tok of lineTokens(line, lineNo)) {
      const m = PAIR_RE.exec(tok);
      if (!m) throw new Error(`AUTOFIX_PAIRS_PARSE: token ${JSON.stringify(tok)} on line ${lineNo} is not from=to`);
      pairs.push([m[1], m[2]] as const);
    }
  }
  return pairs;
}

/** The distinct `^claude-` RHS ids (the ids the repository declares current), sorted. */
export function distinctTargets(pairs: readonly AutofixPair[]): string[] {
  return [...new Set(pairs.map(([, to]) => to).filter((to) => to.startsWith("claude-")))].sort();
}

/**
 * Throws unless the table has at least `minPairs` pairs and `minTargets` distinct `^claude-` targets. A suite
 * that quantifies over the pairs passes vacuously over zero of them, so the real table is always floored.
 */
export function assertPairFloors(
  pairs: readonly AutofixPair[],
  minPairs: number = MIN_AUTOFIX_PAIRS,
  minTargets: number = MIN_DISTINCT_TARGETS,
): void {
  const problems: string[] = [];
  if (pairs.length < minPairs) problems.push(`AUTOFIX_PAIRS_FLOOR ${pairs.length} pairs parsed, floor ${minPairs}`);
  const targets = distinctTargets(pairs);
  if (targets.length < minTargets) {
    problems.push(`AUTOFIX_PAIRS_TARGET_FLOOR ${targets.length} distinct claude- targets [${targets.join(", ")}], floor ${minTargets}`);
  }
  if (problems.length > 0) {
    throw new Error(`${problems.join("; ")} — the AUTOFIX_PAIRS block in audit-models.sh was emptied, commented out, or no longer parses`);
  }
}
