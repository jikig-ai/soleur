import { describe, it, expect, vi } from "vitest";
import { render, fireEvent } from "@testing-library/react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const { mockCaptureMessage } = vi.hoisted(() => ({ mockCaptureMessage: vi.fn() }));
vi.mock("@sentry/nextjs", () => ({ captureMessage: mockCaptureMessage }));

import { WorkspaceIdentityTile } from "@/components/dashboard/workspace-identity-tile";

describe("WorkspaceIdentityTile", () => {
  it("renders a single uppercase initial from the workspace name", () => {
    const { getByTestId } = render(<WorkspaceIdentityTile name="Acme Studio" size="md" />);
    expect(getByTestId("workspace-identity-tile").textContent).toBe("A");
  });

  it("uppercases a lowercase first char", () => {
    const { getByTestId } = render(<WorkspaceIdentityTile name="summit labs" size="md" />);
    expect(getByTestId("workspace-identity-tile").textContent).toBe("S");
  });

  it("ignores leading whitespace when deriving the initial", () => {
    const { getByTestId } = render(<WorkspaceIdentityTile name="  personal" size="sm" />);
    expect(getByTestId("workspace-identity-tile").textContent).toBe("P");
  });

  it("falls back to '?' for an empty name", () => {
    const { getByTestId } = render(<WorkspaceIdentityTile name="" size="md" />);
    expect(getByTestId("workspace-identity-tile").textContent).toBe("?");
  });

  it("renders on a non-gold surface (FR6: not a gold square)", () => {
    const { getByTestId } = render(<WorkspaceIdentityTile name="Acme" size="md" />);
    const cls = getByTestId("workspace-identity-tile").className;
    expect(cls).not.toMatch(/accent-gold/);
    expect(cls).toMatch(/bg-soleur-bg-surface/);
  });

  describe("logo branch (AC7 / AC7c)", () => {
    const WS = "33333333-3333-3333-3333-333333333333";

    it("renders the stable proxy <img> (no signature) when hasLogo + workspaceId", () => {
      const { getByTestId, queryByText } = render(
        <WorkspaceIdentityTile name="Acme" size="md" workspaceId={WS} hasLogo />,
      );
      const img = getByTestId("workspace-logo-img") as HTMLImageElement;
      // AC7c: src is the STABLE path — no query string / signature.
      expect(img.getAttribute("src")).toBe(`/api/workspace/${WS}/logo`);
      expect(queryByText("A")).toBeNull(); // monogram suppressed while logo shows
    });

    it("falls back to the monogram + reports to Sentry on img onError (AC7)", () => {
      const { getByTestId } = render(
        <WorkspaceIdentityTile name="Acme" size="md" workspaceId={WS} hasLogo />,
      );
      fireEvent.error(getByTestId("workspace-logo-img"));
      expect(getByTestId("workspace-identity-tile").textContent).toBe("A");
      expect(mockCaptureMessage).toHaveBeenCalled();
    });

    it("resets the error state when workspaceId changes (rerender, not remount)", () => {
      const { getByTestId, queryByTestId, rerender } = render(
        <WorkspaceIdentityTile name="Acme" size="md" workspaceId={WS} hasLogo />,
      );
      fireEvent.error(getByTestId("workspace-logo-img"));
      expect(queryByTestId("workspace-logo-img")).toBeNull(); // errored → monogram
      const WS2 = "44444444-4444-4444-4444-444444444444";
      rerender(<WorkspaceIdentityTile name="Acme" size="md" workspaceId={WS2} hasLogo />);
      // New id → error reset → img re-renders against the new proxy path.
      const img = getByTestId("workspace-logo-img") as HTMLImageElement;
      expect(img.getAttribute("src")).toBe(`/api/workspace/${WS2}/logo`);
    });

    it("renders the monogram (no img) when hasLogo is false", () => {
      const { getByTestId, queryByTestId } = render(
        <WorkspaceIdentityTile name="Acme" size="md" workspaceId={WS} hasLogo={false} />,
      );
      expect(queryByTestId("workspace-logo-img")).toBeNull();
      expect(getByTestId("workspace-identity-tile").textContent).toBe("A");
    });
  });

  it("is pure presentational — imports neither OrgSwitcherContainer nor LiveRepoBadge (ADR-047 single-mount)", () => {
    const src = readFileSync(
      resolve(__dirname, "../components/dashboard/workspace-identity-tile.tsx"),
      "utf8",
    );
    // Assert no IMPORT of the data-bearing nav components (mentions in the
    // explanatory comment are fine — the invariant is "not imported").
    expect(src).not.toMatch(/^\s*import[^;]*OrgSwitcherContainer/m);
    expect(src).not.toMatch(/^\s*import[^;]*LiveRepoBadge/m);
  });
});
