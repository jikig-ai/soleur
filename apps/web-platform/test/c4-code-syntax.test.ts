import { describe, it, expect } from "vitest";
import { StringStream } from "@codemirror/language";
import {
  c4StreamParser,
  clampFontPx,
  fontSizeForZoom,
  MIN_CODE_FONT_PX,
  MAX_CODE_FONT_PX,
  DEFAULT_CODE_FONT_PX,
  C4_SYNTAX_COLORS,
} from "@/components/kb/c4-code-syntax";

// Drive the pure StreamParser over a single line and collect (text, style)
// pairs. The tokenizer is a pure function over StringStream — no DOM, no
// CodeMirror view — so it is unit-testable directly per the plan (AC4).
function tokenize(line: string) {
  const stream = new StringStream(line, 2, 2);
  const state = c4StreamParser.startState!(2);
  const out: { text: string; style: string | null }[] = [];
  let guard = 0;
  while (!stream.eol() && guard++ < 5000) {
    stream.start = stream.pos;
    const style = c4StreamParser.token(stream, state);
    if (stream.pos === stream.start) stream.next(); // never spin
    out.push({ text: stream.string.slice(stream.start, stream.pos), style });
  }
  return out;
}

const styleOf = (line: string, word: string) =>
  tokenize(line).find((tk) => tk.text === word)?.style;

describe("c4-code-syntax — font-size helpers", () => {
  it("AC3: clampFontPx clamps to [MIN, MAX]", () => {
    expect(clampFontPx(8)).toBe(MIN_CODE_FONT_PX);
    expect(clampFontPx(8)).toBe(10);
    expect(clampFontPx(40)).toBe(MAX_CODE_FONT_PX);
    expect(clampFontPx(40)).toBe(24);
    expect(clampFontPx(15)).toBe(15);
  });

  it("AC1: default zoom resolves to 12px", () => {
    expect(DEFAULT_CODE_FONT_PX).toBe(12);
    expect(fontSizeForZoom(0)).toBe("12px");
  });

  it("AC2/AC3: fontSizeForZoom steps 1px per zoom unit and clamps", () => {
    expect(fontSizeForZoom(1)).toBe("13px");
    expect(fontSizeForZoom(3)).toBe("15px");
    expect(fontSizeForZoom(-1)).toBe("11px");
    // 12 - 5 = 7 → clamps up to MIN (10)
    expect(fontSizeForZoom(-5)).toBe("10px");
    // 12 + 20 = 32 → clamps down to MAX (24)
    expect(fontSizeForZoom(20)).toBe("24px");
  });
});

describe("c4-code-syntax — .c4 tokenizer (AC4)", () => {
  it("classifies LikeC4 keywords as keyword", () => {
    expect(styleOf("specification {", "specification")).toBe("keyword");
    expect(styleOf("model {", "model")).toBe("keyword");
    expect(styleOf("views {", "views")).toBe("keyword");
    expect(styleOf("  element backend", "element")).toBe("keyword");
    expect(styleOf("  relationship -> db", "relationship")).toBe("keyword");
  });

  it("leaves identifiers unstyled (null)", () => {
    expect(styleOf("  user = element", "user")).toBeNull();
    // a word that contains a keyword as a substring must NOT match
    expect(styleOf("  modelService = element", "modelService")).toBeNull();
  });

  it("classifies line comments", () => {
    const toks = tokenize("// a note");
    expect(toks[0].style).toBe("lineComment");
  });

  it("classifies block comments (single line)", () => {
    const toks = tokenize("/* hi */");
    expect(toks[0].style).toBe("blockComment");
  });

  it("tracks block-comment state across lines", () => {
    const stream1 = new StringStream("/* start", 2, 2);
    const state = c4StreamParser.startState!(2);
    c4StreamParser.token(stream1, state);
    expect(state.inBlockComment).toBe(true);
    // a following line stays in comment until the close
    const stream2 = new StringStream("still comment */ after", 2, 2);
    stream2.start = stream2.pos;
    expect(c4StreamParser.token(stream2, state)).toBe("blockComment");
    expect(state.inBlockComment).toBe(false);
  });

  it("classifies double- and single-quoted strings", () => {
    expect(styleOf('  title "Soleur"', '"Soleur"')).toBe("string");
    expect(styleOf("  title 'Soleur'", "'Soleur'")).toBe("string");
  });

  it("classifies #tag refs as meta", () => {
    expect(styleOf("  #external", "#external")).toBe("meta");
  });

  it("classifies braces / arrows as punctuation", () => {
    expect(styleOf("model {", "{")).toBe("punctuation");
    expect(styleOf("a -> b", "->")).toBe("punctuation");
  });
});

describe("c4-code-syntax — highlight colors are Soleur tokens (AC5)", () => {
  it("every syntax color references a --soleur-* var and uses no literal hex", () => {
    const values = Object.values(C4_SYNTAX_COLORS);
    expect(values.length).toBeGreaterThan(0);
    for (const v of values) {
      expect(v).toMatch(/^var\(--soleur-/);
      expect(v).not.toMatch(/#[0-9a-fA-F]{3,8}/);
    }
  });
});
