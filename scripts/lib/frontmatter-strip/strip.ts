/**
 * frontmatter-strip contract — TypeScript implementation (byte-exact with
 * strip.sh / strip.py).
 *
 * Canonical contract lives in SPEC.md; `strip.sh` (perl-backed bash) and
 * `strip.py` (Python) are the byte-identical twins.
 * `scripts/lib/frontmatter-strip.test.sh` feeds shared fixtures to all THREE
 * and asserts byte-parity (issue #5999, ADR-094; third impl added for #6794).
 *
 * Imported by `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
 * so the weekly self-healing promoter measures the always-loaded byte budget on
 * the SAME frontmatter-stripped basis the commit gate
 * (`scripts/lint-agents-rule-budget.py`) uses, closing the raw-vs-stripped skew
 * #6461 accepted knowingly. Also runnable as a stdin->stdout filter:
 * `bun run strip.ts < file`.
 *
 * Behavior: iff the text BEGINS with the exact line `---` (starts with
 * `---\n`), drop from the start through the next line that is exactly `---`
 * (inclusive); everything after is verbatim. Opening `---` with NO matching
 * close consumes the whole text (empty output) — the malformed/over-strip
 * signal. No leading `---\n` -> unchanged. `\n` boundaries are ASCII 0x0A and
 * never occur inside a multibyte UTF-8 sequence, so line splitting is byte-safe
 * and matches strip.py exactly.
 *
 * Node-compatible APIs only (no `Bun` global, no `import.meta.main`): the
 * module is type-checked under `apps/web-platform/tsconfig.json`, which has no
 * `Bun` types.
 */

export function stripFrontmatter(text: string): string {
  if (!text.startsWith("---\n")) {
    return text;
  }
  const lines = text.split("\n");
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === "---") {
      return lines.slice(i + 1).join("\n");
    }
  }
  // Opening delimiter with no close — malformed; consume everything.
  return "";
}

// When executed directly as a filter (`bun run strip.ts < file`), act as a
// stdin->stdout filter. Guarded on argv[1] so importing the module (the cron)
// never touches stdio. `import.meta.main`/`Bun` are avoided deliberately (see
// header) — argv[1] is the script path under bun and node alike, and is NOT
// this file when webpack/node imports the module.
if (typeof process !== "undefined" && process.argv[1]?.endsWith("strip.ts")) {
  const chunks: Buffer[] = [];
  process.stdin.on("data", (c: Buffer) => chunks.push(c));
  process.stdin.on("end", () => {
    process.stdout.write(stripFrontmatter(Buffer.concat(chunks).toString("utf8")));
  });
}
