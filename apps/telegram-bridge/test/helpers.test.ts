import { describe, test, expect } from "bun:test";
import {
  escapeHtml,
  markdownToHtml,
  chunkMessage,
  stripHtmlTags,
  formatStatusText,
  MAX_CHUNK_SIZE,
} from "../src/helpers";
import type { TurnStatus } from "../src/types";

// ---------------------------------------------------------------------------
// escapeHtml
// ---------------------------------------------------------------------------

describe("escapeHtml", () => {
  test("escapes ampersands", () => {
    expect(escapeHtml("A&B")).toBe("A&amp;B");
  });

  test("escapes angle brackets", () => {
    expect(escapeHtml("<script>alert('xss')</script>")).toBe(
      "&lt;script&gt;alert('xss')&lt;/script&gt;",
    );
  });

  test("preserves safe characters", () => {
    expect(escapeHtml("hello world 123")).toBe("hello world 123");
  });

  test("escapes all three in one string", () => {
    expect(escapeHtml("<b>A&B</b>")).toBe("&lt;b&gt;A&amp;B&lt;/b&gt;");
  });
});

// ---------------------------------------------------------------------------
// markdownToHtml
// ---------------------------------------------------------------------------

describe("markdownToHtml", () => {
  test("converts code blocks", () => {
    const input = "```ts\nconst x = 1;\n```";
    const result = markdownToHtml(input);
    expect(result).toContain("<pre>");
    expect(result).toContain("const x = 1;");
    expect(result).toContain("</pre>");
  });

  test("converts inline code", () => {
    expect(markdownToHtml("use `foo()` here")).toContain("<code>foo()</code>");
  });

  test("converts bold **text**", () => {
    expect(markdownToHtml("**bold** text")).toContain("<b>bold</b>");
  });

  test("converts bold __text__", () => {
    expect(markdownToHtml("__bold__ text")).toContain("<b>bold</b>");
  });

  test("converts italic *text*", () => {
    expect(markdownToHtml("*italic* text")).toContain("<i>italic</i>");
  });

  test("converts headings to bold", () => {
    expect(markdownToHtml("## Title")).toContain("<b>Title</b>");
  });

  test("strips markdown links", () => {
    expect(markdownToHtml("[click here](https://example.com)")).toBe("click here");
  });

  test("escapes HTML in plain text", () => {
    const result = markdownToHtml("use <div> tags");
    expect(result).toContain("&lt;div&gt;");
    expect(result).not.toContain("<div>");
  });

  test("preserves HTML entities in code blocks", () => {
    const result = markdownToHtml("```\n<div>\n```");
    expect(result).toContain("&lt;div&gt;");
  });

  test("handles mixed formatting", () => {
    const result = markdownToHtml("**bold** and `code` and *italic*");
    expect(result).toContain("<b>bold</b>");
    expect(result).toContain("<code>code</code>");
    expect(result).toContain("<i>italic</i>");
  });
});

// ---------------------------------------------------------------------------
// chunkMessage
// ---------------------------------------------------------------------------

describe("chunkMessage", () => {
  test("returns single chunk for short text", () => {
    const chunks = chunkMessage("short text");
    expect(chunks).toEqual(["short text"]);
  });

  test("returns single chunk at exact boundary", () => {
    const text = "x".repeat(MAX_CHUNK_SIZE);
    expect(chunkMessage(text)).toEqual([text]);
  });

  test("splits on double newline within limit", () => {
    const first = "a".repeat(3500);
    const second = "b".repeat(3500);
    const text = first + "\n\n" + second;
    const chunks = chunkMessage(text);
    expect(chunks.length).toBe(2);
    expect(chunks[0]).toBe(first);
    expect(chunks[1]).toBe(second);
  });

  test("hard-splits when no double newline", () => {
    const text = "x".repeat(MAX_CHUNK_SIZE + 100);
    const chunks = chunkMessage(text);
    expect(chunks.length).toBe(2);
    expect(chunks[0].length).toBe(MAX_CHUNK_SIZE);
    expect(chunks[1].length).toBe(100);
  });

  test("handles empty string", () => {
    expect(chunkMessage("")).toEqual([""]);
  });

  test("produces correct chunks for very long text", () => {
    const text = "x".repeat(12000);
    const chunks = chunkMessage(text);
    expect(chunks.length).toBe(3);
    for (const chunk of chunks) {
      expect(chunk.length).toBeLessThanOrEqual(MAX_CHUNK_SIZE);
    }
    expect(chunks.join("").length).toBe(12000);
  });
});

// ---------------------------------------------------------------------------
// stripHtmlTags
// ---------------------------------------------------------------------------

describe("stripHtmlTags", () => {
  test("removes all HTML tags", () => {
    expect(stripHtmlTags("<b>bold</b>")).toBe("bold");
  });

  test("handles nested tags", () => {
    expect(stripHtmlTags("<div><b>x</b></div>")).toBe("x");
  });

  test("preserves text without tags", () => {
    expect(stripHtmlTags("no tags here")).toBe("no tags here");
  });
});

// ---------------------------------------------------------------------------
// formatStatusText
// ---------------------------------------------------------------------------

describe("formatStatusText", () => {
  function makeStatus(overrides: Partial<TurnStatus> = {}): TurnStatus {
    return {
      chatId: 1,
      messageId: 1,
      startTime: Date.now(),
      tools: [],
      lastEditTime: Date.now(),
      typingTimer: setTimeout(() => {}, 0),
      ...overrides,
    };
  }

  test("returns 'Thinking...' when fresh and no tools", () => {
    const status = makeStatus({ startTime: Date.now() });
    expect(formatStatusText(status)).toBe("Thinking...");
  });

  test("shows elapsed seconds after 2s", () => {
    const status = makeStatus({ startTime: Date.now() - 5000 });
    const result = formatStatusText(status);
    expect(result).toMatch(/Working\.\.\. \(\d+s\)/);
  });

  test("shows tool names", () => {
    const status = makeStatus({
      startTime: Date.now() - 5000,
      tools: ["Read", "Edit"],
    });
    const result = formatStatusText(status);
    expect(result).toContain("Read, Edit");
  });

  test("truncates to last 5 tools", () => {
    const status = makeStatus({
      startTime: Date.now() - 5000,
      tools: ["A", "B", "C", "D", "E", "F", "G"],
    });
    const result = formatStatusText(status);
    expect(result).not.toContain("A,");
    expect(result).not.toContain("B,");
    expect(result).toContain("C, D, E, F, G");
  });

  test("shows Working with seconds and tools", () => {
    const status = makeStatus({
      startTime: Date.now() - 12000,
      tools: ["Read", "Edit"],
    });
    const result = formatStatusText(status);
    expect(result).toMatch(/Working\.\.\. \(1[0-2]s/);
    expect(result).toContain("Read, Edit");
  });
});
