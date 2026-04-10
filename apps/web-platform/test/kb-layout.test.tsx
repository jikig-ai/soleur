import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";

// Stable mock references (avoid useEffect re-fires)
const mockPush = vi.fn();
const mockRouter = { push: mockPush, back: vi.fn(), forward: vi.fn(), refresh: vi.fn(), replace: vi.fn(), prefetch: vi.fn() };
let mockPathname = "/dashboard/kb";

vi.mock("next/navigation", () => ({
  useRouter: () => mockRouter,
  usePathname: () => mockPathname,
}));

// Mock fetch for /api/kb/tree
const mockTree = {
  tree: {
    name: "root",
    type: "directory",
    path: "",
    children: [
      {
        name: "engineering",
        type: "directory",
        path: "engineering",
        children: [
          {
            name: "specs",
            type: "directory",
            path: "engineering/specs",
            children: [
              { name: "file.md", type: "file", path: "engineering/specs/file.md" },
            ],
          },
        ],
      },
      { name: "INDEX.md", type: "file", path: "INDEX.md" },
    ],
  },
};

beforeEach(() => {
  vi.clearAllMocks();
  mockPathname = "/dashboard/kb";
  global.fetch = vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: () => Promise.resolve(mockTree),
  });
});

describe("KbLayout", () => {
  it("renders FileTree in sidebar when viewing a content file", async () => {
    mockPathname = "/dashboard/kb/engineering/specs/file.md";

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <KbLayout>
        <div data-testid="content-page">File content here</div>
      </KbLayout>,
    );

    // Wait for tree to load
    const nav = await screen.findByRole("navigation", {
      name: /knowledge base file tree/i,
    });
    expect(nav).toBeInTheDocument();

    // Content should also render
    expect(screen.getByTestId("content-page")).toBeInTheDocument();
  });

  it("renders search overlay in sidebar when viewing a content file", async () => {
    mockPathname = "/dashboard/kb/engineering/specs/file.md";

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );

    // Wait for tree to load, then check search input is present
    await screen.findByRole("navigation", {
      name: /knowledge base file tree/i,
    });
    expect(screen.getByPlaceholderText("Search files...")).toBeInTheDocument();
  });

  it("does not render FileTree twice at root path", async () => {
    mockPathname = "/dashboard/kb";

    const { default: KbLayout } = await import(
      "@/app/(dashboard)/dashboard/kb/layout"
    );

    render(
      <KbLayout>
        <div data-testid="page-content">page content</div>
      </KbLayout>,
    );

    await screen.findByRole("navigation", {
      name: /knowledge base file tree/i,
    });

    // Should only have one navigation element (tree rendered once in sidebar)
    const navs = screen.getAllByRole("navigation", {
      name: /knowledge base file tree/i,
    });
    expect(navs).toHaveLength(1);
  });
});
