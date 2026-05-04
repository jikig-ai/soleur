import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";

const KB_SELECTORS = ["h1", "h2", "h3", "p", "ul", "ol", "li", "th", "td", "pre", "blockquote"] as const;

describe("prose-kb spacing wrapper — long-form-document density variant", () => {
  it("descendant selectors target real DOM under .prose-kb wrapper (table fixture)", () => {
    const md = "# Heading\n\npara\n\n| A | B |\n|---|---|\n| 1 | 2 |\n";
    const { container } = render(
      <article className="prose-kb">
        <MarkdownRenderer content={md} />
      </article>,
    );

    const wrapper = container.querySelector(".prose-kb");
    expect(wrapper, "prose-kb wrapper present").not.toBeNull();
    expect(wrapper!.querySelector(".prose-kb h1")).not.toBeNull();
    expect(wrapper!.querySelector(".prose-kb table")).not.toBeNull();
    expect(wrapper!.querySelectorAll(".prose-kb td").length).toBe(2);
    expect(wrapper!.querySelectorAll(".prose-kb th").length).toBe(2);
  });

  it("table-wrapper margin selector resolves: .prose-kb div:has(> table) matches exactly the renderer's overflow-x-auto wrapper", () => {
    // Regression guard for the original `.prose-kb > div:has(> table)` selector,
    // which uses the direct-child combinator after `.prose-kb`. MarkdownRenderer
    // emits an outer `<div class="min-w-0 ...">` BEFORE the table-wrapper
    // `<div class="overflow-x-auto">`, so the `>` form matches zero elements
    // and the wrapper's `mb-3` keeps winning. The fix is the descendant form.
    const md = "| A | B |\n|---|---|\n| 1 | 2 |\n";
    const { container } = render(
      <article className="prose-kb">
        <MarkdownRenderer content={md} />
      </article>,
    );

    const directChildOnly = container.querySelectorAll(".prose-kb > div:has(> table)");
    const descendant = container.querySelectorAll(".prose-kb div:has(> table)");

    expect(directChildOnly.length, "direct-child :has() form does NOT match because the renderer interposes its root wrapper").toBe(0);
    expect(descendant.length, "descendant :has() form matches the table-scroll wrapper").toBe(1);
    expect(descendant[0].className).toContain("overflow-x-auto");
  });

  it("renders three sequential h2 elements as descendants of .prose-kb", () => {
    const md = "## one\n\n## two\n\n## three\n";
    const { container } = render(
      <article className="prose-kb">
        <MarkdownRenderer content={md} />
      </article>,
    );

    expect(container.querySelectorAll(".prose-kb h2").length).toBe(3);
  });

  it("renders ul + 3 li children under .prose-kb", () => {
    const md = "- a\n- b\n- c\n";
    const { container } = render(
      <article className="prose-kb">
        <MarkdownRenderer content={md} />
      </article>,
    );

    const ul = container.querySelector(".prose-kb ul");
    expect(ul).not.toBeNull();
    expect(ul!.querySelectorAll("li").length).toBe(3);
  });

  it("WITHOUT prose-kb wrapper, .prose-kb selectors match nothing (chat-bubble path)", () => {
    const md = "# Heading\n\npara\n\n| A | B |\n|---|---|\n| 1 | 2 |\n";
    const { container } = render(<MarkdownRenderer content={md} />);

    expect(container.querySelectorAll(".prose-kb").length).toBe(0);
    expect(container.querySelectorAll(".prose-kb table").length).toBe(0);
    expect(container.querySelectorAll(".prose-kb td").length).toBe(0);
    expect(container.querySelectorAll(".prose-kb p").length).toBe(0);

    const tableWrap = container.querySelector("div.overflow-x-auto");
    expect(tableWrap).not.toBeNull();
    expect(tableWrap!.className).toContain("mb-3");
  });

  it("globals.css declares each .prose-kb selector unlayered (NOT inside @layer components)", () => {
    const cssPath = resolve(__dirname, "..", "app", "globals.css");
    const css = readFileSync(cssPath, "utf8");

    for (const selector of KB_SELECTORS) {
      const pattern = new RegExp(`\\.prose-kb\\s+(?:[\\w.,#:[\\]"'=\\s]+,\\s*)?${selector}\\b`);
      expect(css, `expected globals.css to declare .prose-kb ${selector} rule`).toMatch(pattern);
    }
    expect(css, "expected .prose-kb table-scroll-wrapper rule via :has(> table)").toMatch(
      /\.prose-kb\s+div:has\(>\s*table\)/,
    );

    const componentsBlockMatch = css.match(/@layer\s+components\s*\{([\s\S]*?)\n\}/);
    expect(
      componentsBlockMatch,
      "expected an @layer components block in globals.css as anchor for the negative cascade-placement assertion",
    ).not.toBeNull();
    expect(
      componentsBlockMatch![1],
      ".prose-kb must NOT live inside @layer components — Tailwind v4 emits utilities in a later layer that would win regardless of specificity",
    ).not.toMatch(/\.prose-kb/);
  });

  it("guard: chat/message-bubble.tsx does NOT contain the literal string 'prose-kb'", () => {
    const filePath = resolve(__dirname, "..", "components", "chat", "message-bubble.tsx");
    const src = readFileSync(filePath, "utf8");
    expect(src).not.toContain("prose-kb");
  });
});
