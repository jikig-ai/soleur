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
 * Shared by every TypeScript source-walk guard under test/ so they all read the
 * same comment-free text — a hand-copied regex stripper is the defect this
 * replaced, twice (learning 2026-06-12, then #8603).
 */
export function stripComments(src: string, fileName = "x.ts"): string {
  // The file name picks the parser's language variant (`.tsx` parses JSX).
  const file = ts.createSourceFile(fileName, src, ts.ScriptTarget.Latest, true);
  const ranges = new Map<number, number>();
  const collect = (list: ts.CommentRange[] | undefined) => {
    for (const r of list ?? []) ranges.set(r.pos, r.end);
  };
  // Walk every TOKEN, not just AST nodes: a comment right before a closing
  // `}` or `)` is leading trivia of that punctuation token, which
  // forEachChild never visits (the #8603 migration caught exactly that).
  const visit = (node: ts.Node) => {
    collect(ts.getLeadingCommentRanges(src, node.pos));
    collect(ts.getTrailingCommentRanges(src, node.end));
    for (const child of node.getChildren(file)) visit(child);
  };
  visit(file);

  const chars = src.split("");
  for (const [pos, end] of ranges) {
    for (let i = pos; i < end; i++) if (chars[i] !== "\n") chars[i] = " ";
  }
  return chars.join("");
}
