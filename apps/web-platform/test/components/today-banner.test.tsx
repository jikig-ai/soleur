import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { TodayBanner } from "@/components/dashboard/today-banner";
import { RUNTIME_COST_DISCLOSURE } from "@/lib/legal/disclosures";

// PR-F (#3244, #3940) Phase 5 — disclosure banner for the dashboard Today
// section.
//
// RV13 (Kieran P2.3) — the literal disclosure text lives in
// lib/legal/disclosures.ts as an exported constant; the component imports
// the constant. Tests gate on the imported value (NOT a free literal) so
// legal-copy changes flow through to every render site without test churn.
// RV14 — page-level banner above the Today section (one DOM node, not
// per-card).

describe("TodayBanner", () => {
  it("renders the RUNTIME_COST_DISCLOSURE constant value (not a free literal)", () => {
    render(<TodayBanner />);
    expect(screen.getByText(RUNTIME_COST_DISCLOSURE)).toBeInTheDocument();
  });

  it("the constant contains the load-bearing 'disclaims warranty for runtime cost' substring (BSL parity)", () => {
    expect(RUNTIME_COST_DISCLOSURE).toMatch(/disclaims warranty for runtime cost/);
  });

  it("renders inside an element with role=note so screen readers announce it once per page", () => {
    render(<TodayBanner />);
    expect(screen.getByRole("note")).toHaveTextContent(RUNTIME_COST_DISCLOSURE);
  });
});
