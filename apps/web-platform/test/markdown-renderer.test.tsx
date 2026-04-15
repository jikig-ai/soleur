import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";

describe("MarkdownRenderer — chat markdown overflow (issue #2229)", () => {
  it("wraps output in a container with min-w-0 and overflow-wrap anywhere", () => {
    const longToken = "a".repeat(500);
    const { container } = render(<MarkdownRenderer content={longToken} />);
    const root = container.firstElementChild as HTMLElement | null;
    expect(root, "MarkdownRenderer must render a root wrapper element").not.toBeNull();

    const cls = root!.className;
    expect(cls).toContain("min-w-0");
    expect(cls).toContain("break-words");
    // Tailwind arbitrary value form for overflow-wrap: anywhere
    expect(cls).toContain("[overflow-wrap:anywhere]");
  });

  it("retains overflow-x-auto for fenced code blocks", () => {
    const md = "```ts\nconst x = 'a'.repeat(300);\n```";
    const { container } = render(<MarkdownRenderer content={md} />);
    const pre = container.querySelector("pre");
    expect(pre).not.toBeNull();
    expect(pre!.className).toContain("overflow-x-auto");
  });

  it("retains overflow-x-auto for GFM tables", () => {
    const md = "| A | B |\n|---|---|\n| 1 | 2 |\n";
    const { container } = render(<MarkdownRenderer content={md} />);
    const tableWrap = container.querySelector("div.overflow-x-auto");
    expect(tableWrap).not.toBeNull();
  });
});
