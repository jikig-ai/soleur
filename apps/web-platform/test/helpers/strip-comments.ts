import ts from "typescript";

/**
 * Blank out every comment in a TypeScript source so a source walk sees only
 * code. Comment ranges come from the real TypeScript parser, not a regex: a
 * regex over `/* … *\/` also fires on the `/*` inside a `//` comment or a
 * string (`bot-fix/*`, `functions/*.ts`), opening a phantom block that swallows
 * real code up to the next `*\/` — which hid hundreds of code lines from the
 * guards before #8603's review. Each comment character is replaced with a space
 * and newlines are kept, so line numbers and columns still match the file.
 *
 * Shared by model-tiers.test.ts (source walks) and
 * claude-cli-pin-knows-models.test.ts (model-id harvest) so both guards read
 * the same comment-free text.
 */
export function stripComments(src: string): string {
  const file = ts.createSourceFile("x.ts", src, ts.ScriptTarget.Latest, false);
  const ranges = new Map<number, number>();
  const collect = (list: ts.CommentRange[] | undefined) => {
    for (const r of list ?? []) ranges.set(r.pos, r.end);
  };
  const visit = (node: ts.Node) => {
    collect(ts.getLeadingCommentRanges(src, node.pos));
    collect(ts.getTrailingCommentRanges(src, node.end));
    ts.forEachChild(node, visit);
  };
  visit(file);
  // Comments after the last token hang off the end-of-file token.
  collect(ts.getLeadingCommentRanges(src, file.endOfFileToken.pos));

  const chars = src.split("");
  for (const [pos, end] of ranges) {
    for (let i = pos; i < end; i++) if (chars[i] !== "\n") chars[i] = " ";
  }
  return chars.join("");
}
