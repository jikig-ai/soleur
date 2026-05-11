import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

let mockPathname = "/dashboard/kb";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => mockPathname,
}));

vi.mock("next/dynamic", () => ({
  __esModule: true,
  default: () => () => null,
}));

vi.mock("@/components/kb/file-tree", () => ({
  FileTree: () => <div data-testid="file-tree">file tree</div>,
}));

vi.mock("@/components/kb/search-overlay", () => ({
  SearchOverlay: () => <div data-testid="search-overlay">search</div>,
}));

vi.mock("@/components/kb", () => ({
  DesktopPlaceholder: () => <div data-testid="desktop-placeholder" />,
  EmptyState: () => null,
  KbErrorBoundary: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  LoadingSkeleton: () => null,
  NoProjectState: () => null,
  UnknownError: () => null,
  WorkspaceNotReady: () => null,
}));

vi.mock("@/components/kb/get-ancestor-paths", () => ({
  getAncestorPaths: () => [],
}));

// Desktop layout (transition contract lives here).
vi.mock("@/hooks/use-media-query", () => ({
  useMediaQuery: () => true,
}));

import KbLayout from "@/app/(dashboard)/dashboard/kb/layout";

describe("KB sidebar transition contract (desktop)", () => {
  beforeEach(() => {
    mockPathname = "/dashboard/kb";
    localStorage.clear();
    vi.stubGlobal(
      "fetch",
      vi.fn((url: string) => {
        if (url === "/api/kb/tree") {
          return Promise.resolve({
            ok: true,
            status: 200,
            json: () =>
              Promise.resolve({
                tree: {
                  name: "root",
                  children: [{ name: "file.md", children: [] }],
                },
              }),
          });
        }
        if (url === "/api/flags") {
          return Promise.resolve({
            ok: true,
            status: 200,
            json: () => Promise.resolve({}),
          });
        }
        return Promise.resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({}),
        });
      }),
    );
  });

  afterEach(() => {
    localStorage.clear();
    vi.unstubAllGlobals();
  });

  function getSidebarAside(): HTMLElement | null {
    // The file-tree <aside> is the first <aside> in the desktop layout
    // (KbDesktopLayout renders it as the sole <aside> sibling of the inner
    // <Group>; mobile <aside> is gated by `hidden md:block`, but in desktop
    // mode here the mobile layout isn't mounted at all).
    return document.querySelector("aside");
  }

  it("aside has md:transition-[width] md:duration-200 md:ease-out in OPEN state", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    const aside = getSidebarAside();
    expect(aside).not.toBeNull();
    expect(aside?.className).toMatch(/(?:^|\s)md:transition-\[width\](?:\s|$)/);
    expect(aside?.className).toMatch(/\bmd:duration-200\b/);
    expect(aside?.className).toMatch(/\bmd:ease-out\b/);
  });

  it("aside KEEPS md:transition-[width] in COLLAPSED state (#3573 lesson: class is unconditional)", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    await userEvent.click(screen.getByLabelText("Collapse file tree"));
    const aside = getSidebarAside();
    expect(aside?.className).toMatch(/(?:^|\s)md:transition-\[width\](?:\s|$)/);
    expect(aside?.className).toMatch(/\bmd:duration-200\b/);
    expect(aside?.className).toMatch(/\bmd:ease-out\b/);
  });

  it("collapsed aside contributes zero width (md:w-0 + md:border-r-0 + md:overflow-hidden)", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    await userEvent.click(screen.getByLabelText("Collapse file tree"));
    const aside = getSidebarAside();
    expect(aside?.className).toMatch(/\bmd:w-0\b/);
    expect(aside?.className).toMatch(/\bmd:overflow-hidden\b/);
    expect(aside?.className).toMatch(/\bmd:border-r-0\b/);
  });

  it("expanded aside has md:w-72 (and NOT md:w-0)", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    const aside = getSidebarAside();
    expect(aside?.className).toMatch(/\bmd:w-72\b/);
    expect(aside?.className).not.toMatch(/\bmd:w-0\b/);
  });

  it("aside has NO padding (so md:w-0 collapses fully; #3585 sliver lesson)", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    const aside = getSidebarAside();
    // Padding on the aside + box-border + md:w-0 forces a 32px sliver.
    expect(aside?.className).not.toMatch(/\bpx-\d+\b/);
    expect(aside?.className).not.toMatch(/\bpy-\d+\b/);
    expect(aside?.className).not.toMatch(/\bp-\d+\b/);
  });

  it("inner wrapper holds fixed w-72 so contents stay anchored during transition (#3584 lesson)", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    const aside = getSidebarAside();
    const wrapper = aside?.firstElementChild as HTMLElement | null;
    expect(wrapper).not.toBeNull();
    expect(wrapper?.className).toMatch(/\bw-72\b/);
  });

  it("aside is inert when collapsed", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    await userEvent.click(screen.getByLabelText("Collapse file tree"));
    const aside = getSidebarAside();
    // React renders `inert={true}` as the boolean attribute "inert".
    expect(aside?.hasAttribute("inert")).toBe(true);
  });

  it("aside is NOT inert when expanded", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    const aside = getSidebarAside();
    expect(aside?.hasAttribute("inert")).toBe(false);
  });

  it("KbDocShell content well carries md:transition-[padding] md:duration-200 md:ease-out in OPEN state", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    const well = document.querySelector(".min-h-0.flex-1.overflow-y-auto");
    expect(well).not.toBeNull();
    expect(well?.className).toMatch(/(?:^|\s)md:transition-\[padding\](?:\s|$)/);
    expect(well?.className).toMatch(/\bmd:duration-200\b/);
    expect(well?.className).toMatch(/\bmd:ease-out\b/);
  });

  it("KbDocShell content well KEEPS md:transition-[padding] in COLLAPSED state (#3573 lesson)", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    await userEvent.click(screen.getByLabelText("Collapse file tree"));
    const well = document.querySelector(".min-h-0.flex-1.overflow-y-auto");
    expect(well).not.toBeNull();
    expect(well?.className).toMatch(/(?:^|\s)md:transition-\[padding\](?:\s|$)/);
    expect(well?.className).toMatch(/\bmd:duration-200\b/);
    expect(well?.className).toMatch(/\bmd:ease-out\b/);
  });

  it("collapse toggle button still works on desktop", async () => {
    render(
      <KbLayout>
        <div>content</div>
      </KbLayout>,
    );
    await screen.findByTestId("file-tree");
    const collapseBtn = screen.getByLabelText("Collapse file tree");
    await userEvent.click(collapseBtn);
    expect(screen.getByLabelText("Expand file tree")).toBeInTheDocument();
  });
});
