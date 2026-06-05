# Learning: hand-rolling a CodeMirror 6 StreamLanguage for a DSL with no published grammar

## Problem

The LikeC4 `.c4` source viewer (`C4CodePanel` in `apps/web-platform/components/kb/c4-shared.tsx`)
rendered the DSL in a single undifferentiated color and at CodeMirror's default
~13–14px. We wanted per-editor syntax colors + a smaller default font + zoom
controls. There is **no published `@likec4/*` CodeMirror language package**
(`node_modules/@likec4/` = `core`, `diagram`, `styles` only — LikeC4's own editor
uses a Monaco/Langium stack server-side, not a CodeMirror grammar), so the
tokenizer had to be hand-rolled.

## Solution

A pure `.ts` module (`components/kb/c4-code-syntax.ts`) — no React, no DOM — holding:

- `c4StreamParser: StreamParser<C4State>` via `StreamLanguage.define(...)` —
  a conservative line tokenizer (keywords as whole-word set membership, `//`/`/* */`
  comments with a `{ inBlockComment }` state bit, quoted strings, `#tag` refs,
  braces/arrows).
- `c4HighlightStyle = HighlightStyle.define([...])` mapping lezer `tags` to
  `var(--soleur-*)` design tokens (theme-aware, no literal hex), layered via
  `syntaxHighlighting(...)`.
- `fontPxForZoom`/`fontSizeForZoom`/`codeFontTheme` — `EditorView.theme({ "&": { fontSize } })`
  scaling content + gutter, clamped to `[10px, 24px]`.

Wired into `C4CodePanel` as a theme-independent `extensions={[c4SyntaxExtensions, codeFontTheme(zoom)]}`
array (kept the existing `oneDark` chrome `theme` prop branching on `data-theme`).

## Key Insight

`StreamParser.token(stream, state)` returns a **style-tag NAME STRING** (`"keyword"`,
`"lineComment"`, `"string"`, `"meta"`, `"punctuation"`) — **NOT** a lezer `Tag` object.
`StreamLanguage` resolves those names against the `@lezer/highlight` `tags` table
internally; the `HighlightStyle` is the *other* half and maps `Tag` *objects*
(`t.keyword`, …) to CSS. This decoupling is what makes the tokenizer a pure
function over `StringStream` — unit-testable directly (construct a `StringStream`,
call `token()`, assert the returned string) without ever instantiating an
`EditorView`. happy-dom cannot lay out CodeMirror, so component tests must assert
the **props passed to `<CodeMirror>`** (extensions array by reference, `theme`
prop) rather than computed pixels.

CodeMirror enforces its own contract: if `token()` ever returns without advancing
`stream.pos`, `readToken` throws `"Stream parser failed to advance stream."` — so
the tokenizer's test harness should assert advancement rather than paper over it
with a defensive `stream.next()`.

## Prevention / verification

- Verify library APIs against the **installed** version, not memory: grep the
  `.d.ts` (`@codemirror/language/dist/index.d.ts` for `StreamParser.token`'s
  return type; `@lezer/highlight/dist/*.d.ts` for tag names — `brace`/`punctuation`/
  `meta`/`lineComment` vary across majors). A `node -e "require('pkg/package.json')"`
  probe fails on export-map-only packages; read the `.d.ts` instead.
- Tune the keyword set to the DSL's **actual** sources, not memory: the repo's
  real `.c4` files used `shape`/`notation` (added) and never `extends` (dropped) —
  confirmed by `grep`-ing `knowledge-base/engineering/architecture/diagrams/*.c4`.
- Ground a "colors use design tokens, no hex" assertion on structured data
  (export a `C4_SYNTAX_COLORS` record the `HighlightStyle` consumes) so the test
  reads `Object.values(...)` instead of regex-scanning source.

## Tags
category: best-practices
module: apps/web-platform/components/kb
