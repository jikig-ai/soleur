import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
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

  it("list variant (the default) renders on a non-gold surface so dropdown rows keep the current-row gold-ring distinction", () => {
    const { getByTestId } = render(<WorkspaceIdentityTile name="Acme" size="md" />);
    const cls = getByTestId("workspace-identity-tile").className;
    expect(cls).not.toMatch(/accent-gold|accent-gradient/);
    expect(cls).toMatch(/bg-soleur-bg-surface/);
  });

  it("identity variant renders a BOLD gold-gradient anchor (D4-bolder direction, #4915 follow-up: the active-workspace identity tile IS the sanctioned gold use — supersedes the original FR6 'non-gold tile' for this variant only)", () => {
    const { getByTestId } = render(
      <WorkspaceIdentityTile name="Acme" size="lg" variant="identity" />,
    );
    const cls = getByTestId("workspace-identity-tile").className;
    expect(cls).toMatch(/from-soleur-accent-gradient-start/);
    expect(cls).toMatch(/to-soleur-accent-gradient-end/);
    // dark monogram on gold (high contrast — never white-on-gold)
    expect(cls).toMatch(/text-soleur-text-on-accent/);
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
