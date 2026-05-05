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

  it("co-mounted instances do NOT share `wrapCode` / `nofollow` — review #2380", () => {
    const md = "```ts\nconst x = 1;\n```\n\n[link](https://example.com)";
    const { container } = render(
      <div>
        <div data-testid="sidebar">
          <MarkdownRenderer content={md} wrapCode={true} nofollow={false} />
        </div>
        <div data-testid="full">
          <MarkdownRenderer content={md} wrapCode={false} nofollow={true} />
        </div>
      </div>,
    );

    const sidebarPre = container
      .querySelector('[data-testid="sidebar"] pre') as HTMLPreElement;
    const fullPre = container
      .querySelector('[data-testid="full"] pre') as HTMLPreElement;
    expect(sidebarPre.className).toMatch(/whitespace-pre-wrap/);
    expect(sidebarPre.className).not.toMatch(/overflow-x-auto/);
    expect(fullPre.className).toMatch(/overflow-x-auto/);
    expect(fullPre.className).not.toMatch(/whitespace-pre-wrap/);

    const sidebarA = container
      .querySelector('[data-testid="sidebar"] a') as HTMLAnchorElement;
    const fullA = container
      .querySelector('[data-testid="full"] a') as HTMLAnchorElement;
    expect(sidebarA.getAttribute("rel")).toBe("noopener noreferrer");
    expect(fullA.getAttribute("rel")).toBe("nofollow noopener noreferrer");
  });
});

describe("MarkdownRenderer — table column widths (shared-doc readability)", () => {
  const tableMd =
    "| ConfigurationKey | Value | Description |\n" +
    "|---|---|---|\n" +
    "| timeout | 30 | request timeout in seconds |\n";

  it("renders the table with auto width (not w-full forced fill)", () => {
    const { container } = render(<MarkdownRenderer content={tableMd} />);
    const table = container.querySelector("table");
    expect(table).not.toBeNull();
    expect(table!.className).toContain("w-auto");
    expect(table!.className).not.toMatch(/(^|\s)w-full(\s|$)/);
  });

  it("renders header cells with whitespace-nowrap so column names don't break mid-word", () => {
    const { container } = render(<MarkdownRenderer content={tableMd} />);
    const headers = container.querySelectorAll("th");
    expect(headers.length).toBeGreaterThan(0);
    headers.forEach((th) => {
      expect(th.className).toContain("whitespace-nowrap");
      // Regression guard: th must not silently re-acquire w-full (would defeat the auto-layout fix).
      expect(th.className).not.toMatch(/(^|\s)w-full(\s|$)/);
    });
  });

  it("renders data cells with a min/max width band so columns are readable", () => {
    const { container } = render(<MarkdownRenderer content={tableMd} />);
    const cells = container.querySelectorAll("td");
    expect(cells.length).toBeGreaterThan(0);
    cells.forEach((td) => {
      expect(td.className).toContain("min-w-[8ch]");
      expect(td.className).toContain("max-w-[40ch]");
      expect(td.className).toContain("align-top");
      // Regression guard: td must not silently re-acquire w-full (would override the band).
      expect(td.className).not.toMatch(/(^|\s)w-full(\s|$)/);
    });
  });
});
