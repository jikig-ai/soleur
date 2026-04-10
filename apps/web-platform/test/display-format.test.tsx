import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { TeamNamesProvider, useTeamNames } from "@/hooks/use-team-names";
import type { DomainLeaderId } from "@/server/domain-leaders";

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

/** Helper: renders a consumer that displays getDisplayName and getBadgeLabel. */
function DisplayConsumer({ leaderId }: { leaderId: DomainLeaderId }) {
  const { getDisplayName, getBadgeLabel } = useTeamNames();
  return (
    <div>
      <span data-testid="display">{getDisplayName(leaderId)}</span>
      <span data-testid="badge">{getBadgeLabel(leaderId)}</span>
    </div>
  );
}

function renderWithNames(
  names: Record<string, string>,
  leaderId: DomainLeaderId,
) {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    json: () => Promise.resolve({ names, nudgesDismissed: [], namingPromptedAt: null }),
  });

  return act(async () => {
    render(
      <TeamNamesProvider>
        <DisplayConsumer leaderId={leaderId} />
      </TeamNamesProvider>,
    );
  });
}

describe("Display format: Name (Role)", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  it("shows 'Alex (CTO)' when CTO is named Alex", async () => {
    await renderWithNames({ cto: "Alex" }, "cto");
    expect(screen.getByTestId("display").textContent).toBe("Alex (CTO)");
  });

  it("shows 'CTO' when no custom name is set", async () => {
    await renderWithNames({}, "cto");
    expect(screen.getByTestId("display").textContent).toBe("CTO");
  });

  it("shows 'Sarah (CMO)' for named CMO", async () => {
    await renderWithNames({ cmo: "Sarah" }, "cmo");
    expect(screen.getByTestId("display").textContent).toBe("Sarah (CMO)");
  });

  it("badge shows first 3 chars of custom name uppercased", async () => {
    await renderWithNames({ cto: "Alex" }, "cto");
    expect(screen.getByTestId("badge").textContent).toBe("ALE");
  });

  it("badge shows role acronym when no custom name", async () => {
    await renderWithNames({}, "cto");
    expect(screen.getByTestId("badge").textContent).toBe("CTO");
  });

  it("badge shows first 3 chars for short names", async () => {
    await renderWithNames({ cfo: "Jo" }, "cfo");
    expect(screen.getByTestId("badge").textContent).toBe("JO");
  });
});
