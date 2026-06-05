// CodeMirror 6 language + highlight + font-size extensions for the LikeC4 `.c4`
// source viewer (C4CodePanel in c4-shared.tsx). Pure module — no React, no DOM —
// so the tokenizer and font-size helpers are unit-testable directly. There is no
// published @likec4/* CodeMirror grammar, so the DSL tokenizer is hand-rolled via
// StreamLanguage. Highlight colors reference the same `--soleur-*` design tokens
// c4-theme.css uses (never literal hex) so they flip with `data-theme`.
import {
  StreamLanguage,
  HighlightStyle,
  syntaxHighlighting,
  type StreamParser,
} from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import { EditorView } from "@codemirror/view";
import type { Extension } from "@codemirror/state";

/** LikeC4 DSL keywords, matched whole-word (set membership after `\w+` match). */
export const KEYWORDS = new Set([
  "specification",
  "model",
  "views",
  "view",
  "dynamic",
  "element",
  "relationship",
  "tag",
  "color",
  "technology",
  "style",
  "extend",
  "extends",
  "link",
  "icon",
  "include",
  "exclude",
  "group",
  "of",
  "with",
  "autoLayout",
  "title",
  "description",
  "navigateTo",
  "where",
  "this",
  "it",
]);

export interface C4State {
  inBlockComment: boolean;
}

// StreamParser.token returns a *style tag NAME STRING* (e.g. "keyword",
// "lineComment") — NOT a Tag object. StreamLanguage resolves those names against
// the lezer `tags` table internally; c4HighlightStyle (below) is the other half,
// mapping the resolved Tag objects to CSS. Tokenizer is deliberately conservative:
// when unsure, consume one char and emit null so identifiers stay the base color.
export const c4StreamParser: StreamParser<C4State> = {
  name: "c4",
  startState: () => ({ inBlockComment: false }),
  token(stream, state) {
    if (state.inBlockComment) {
      if (stream.match(/^.*?\*\//)) state.inBlockComment = false;
      else stream.skipToEnd();
      return "blockComment";
    }
    if (stream.eatSpace()) return null;
    if (stream.match("/*")) {
      // Same-line close? then it's a self-contained block comment.
      if (stream.match(/^.*?\*\//)) return "blockComment";
      state.inBlockComment = true;
      stream.skipToEnd();
      return "blockComment";
    }
    if (stream.match("//")) {
      stream.skipToEnd();
      return "lineComment";
    }
    if (
      stream.match(/^"(?:[^"\\]|\\.)*"/) ||
      stream.match(/^'(?:[^'\\]|\\.)*'/)
    ) {
      return "string";
    }
    if (stream.match(/^#[A-Za-z][\w-]*/)) return "meta"; // #tag
    if (stream.match(/^[A-Za-z_]\w*/)) {
      return KEYWORDS.has(stream.current()) ? "keyword" : null;
    }
    if (stream.match("->") || stream.match(/^[{}();]/)) return "punctuation";
    stream.next(); // conservative fallthrough
    return null;
  },
};

export const c4Language = StreamLanguage.define(c4StreamParser);

// Semantic token → Soleur design-token map. Kept as plain data (not buried in the
// HighlightStyle.define call) so AC5 can assert "every color is a --soleur-* var,
// no literal hex" without reading source text.
export const C4_SYNTAX_COLORS = {
  keyword: "var(--soleur-accent-gold-fg)",
  comment: "var(--soleur-text-muted)",
  string: "var(--soleur-text-secondary)",
  meta: "var(--soleur-accent-gold-text)",
  punctuation: "var(--soleur-text-muted)",
} as const;

export const c4HighlightStyle = HighlightStyle.define([
  { tag: t.keyword, color: C4_SYNTAX_COLORS.keyword },
  {
    tag: [t.lineComment, t.blockComment, t.comment],
    color: C4_SYNTAX_COLORS.comment,
    fontStyle: "italic",
  },
  { tag: t.string, color: C4_SYNTAX_COLORS.string },
  { tag: t.meta, color: C4_SYNTAX_COLORS.meta },
  { tag: [t.brace, t.punctuation], color: C4_SYNTAX_COLORS.punctuation },
]);

/** Language + highlight, theme-independent (applies in both light and dark). */
export const c4SyntaxExtensions: Extension = [
  c4Language,
  syntaxHighlighting(c4HighlightStyle),
];

export const MIN_CODE_FONT_PX = 10;
export const MAX_CODE_FONT_PX = 24;
export const DEFAULT_CODE_FONT_PX = 12;

/** Clamp a px value to the supported code-font range. */
export const clampFontPx = (px: number): number =>
  Math.min(MAX_CODE_FONT_PX, Math.max(MIN_CODE_FONT_PX, px));

/** Map an integer zoom step (0 = default) to a clamped `"<n>px"` string. */
export const fontSizeForZoom = (zoom: number): string =>
  `${clampFontPx(DEFAULT_CODE_FONT_PX + zoom)}px`;

/** EditorView theme scaling content + gutter font-size together for the zoom. */
export const codeFontTheme = (zoom: number): Extension =>
  EditorView.theme({
    "&": { fontSize: fontSizeForZoom(zoom) },
    ".cm-gutters": { fontSize: fontSizeForZoom(zoom) },
  });
