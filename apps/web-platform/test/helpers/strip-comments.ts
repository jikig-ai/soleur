/**
 * Blank out comment lines so the verbatim `--model claude-…` GHA-mirror
 * comments are not flagged. Removes block comments wholesale, then blanks any
 * line whose first non-whitespace content begins a comment (`//` or a `*`
 * jsdoc/block continuation). Comment lines are mapped to "" (not filtered) so
 * the surviving line indices still match the real file line numbers in the
 * offender report. Code lines are left intact — never truncated at `//` — so a
 * raw literal preceded by a string containing `//` cannot slip through as a
 * false-negative (fail-safe: an over-strict match is preferable to a missed
 * literal in a drift guard).
 *
 * Shared by model-tiers.test.ts (source walks) and
 * claude-cli-pin-knows-models.test.ts (model-id harvest) so both guards read
 * the same comment-stripped text (#8603).
 */
export function stripComments(src: string): string {
  const noBlock = src.replace(/\/\*[\s\S]*?\*\//g, "");
  return noBlock
    .split("\n")
    .map((line) => {
      const trimmed = line.trimStart();
      return trimmed.startsWith("//") || trimmed.startsWith("*") ? "" : line;
    })
    .join("\n");
}
