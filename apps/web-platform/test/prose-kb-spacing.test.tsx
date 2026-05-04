import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";

describe("prose-kb spacing wrapper — long-form-document density variant", () => {
  it("descendant selectors target real DOM under .prose-kb wrapper (table fixture)", () => {
    const md = "before\n\n# Heading\n\npara\n\n| A | B |\n|---|---|\n| 1 | 2 |\n";
    const { container } = render(
      <article className="prose-kb">
        <MarkdownRenderer content={md} />
      </article>,
    );

    const wrapper = container.querySelector(".prose-kb");
    expect(wrapper, "prose-kb wrapper present").not.toBeNull();

    expect(wrapper!.querySelector("table"), ".prose-kb table selector targets DOM").not.toBeNull();
    expect(wrapper!.querySelectorAll(".prose-kb td").length).toBe(2);
    expect(wrapper!.querySelectorAll(".prose-kb th").length).toBe(2);
    expect(wrapper!.querySelector(".prose-kb h1")).not.toBeNull();
    expect(wrapper!.querySelectorAll(".prose-kb p").length).toBeGreaterThanOrEqual(2);
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

  it("globals.css declares unlayered .prose-kb rules (NOT inside @layer components)", () => {
    const cssPath = resolve(__dirname, "..", "app", "globals.css");
    const css = readFileSync(cssPath, "utf8");

    expect(css, ".prose-kb rules present in globals.css").toMatch(/\.prose-kb\s+(?:>\s*)?\w/);

    const componentsBlockMatch = css.match(/@layer\s+components\s*\{([\s\S]*?)\n\}/);
    if (componentsBlockMatch) {
      expect(
        componentsBlockMatch[1],
        ".prose-kb must NOT live inside @layer components — Tailwind v4 emits utilities in a later layer that would win regardless of specificity",
      ).not.toMatch(/\.prose-kb/);
    }

    const proseKbCount = (css.match(/\.prose-kb/g) ?? []).length;
    expect(proseKbCount, "expected ≥7 .prose-kb selectors covering h*/p/ul-ol/li/table/th-td/pre/blockquote").toBeGreaterThanOrEqual(7);
  });

  it("guard: chat/message-bubble.tsx does NOT contain the literal string 'prose-kb'", () => {
    const filePath = resolve(__dirname, "..", "components", "chat", "message-bubble.tsx");
    const src = readFileSync(filePath, "utf8");
    expect(src).not.toContain("prose-kb");
  });
});
