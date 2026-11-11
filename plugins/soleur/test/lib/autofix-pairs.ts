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
 *   - A `#` at the start of a line or after a blank starts a comment to end of line, so a commented-out pair is not
 *     live and `"a=b"  # was "c=d"` is ONE pair (a=b).
 *   - Every remaining blank-separated token must be `claude-<id>=claude-<id>` (double-quoted or bare, ids `[0-9a-z-]`);
 *     anything else — a single-quoted pair, an unbalanced quote, a non-claude side, a stray word — throws with its line
 *     number instead of being dropped.
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
// One table entry: `claude-<id>=claude-<id>`, bare or wrapped in a matched pair of double quotes.
const PAIR_RE = /^("?)(claude-[0-9a-z-]+)=(claude-[0-9a-z-]+)\1$/;

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
    const live = line.replace(/(^|[ \t])#.*$/, "").trim();
    if (live === "") continue;
    for (const tok of live.split(/[ \t]+/)) {
      const m = PAIR_RE.exec(tok);
      if (!m) throw new Error(`AUTOFIX_PAIRS_PARSE: token ${tok} on line ${lineNo} is not claude-<id>=claude-<id>`);
      pairs.push([m[2], m[3]] as const);
    }
  }
  return pairs;
}

/** The distinct RHS ids (the ids the repository declares current), sorted. PAIR_RE already made each one `claude-…`. */
export function distinctTargets(pairs: readonly AutofixPair[]): string[] {
  return [...new Set(pairs.map(([, to]) => to))].sort();
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
