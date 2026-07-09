import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import type { WorkstreamIssue } from "@/lib/workstream";
import { IssueDetailSheet } from "@/components/workstream/issue-detail-sheet";

// Desktop matchMedia so the Sheet renders inline (no portal).
function installMatchMedia(desktop: boolean) {
  vi.stubGlobal(
    "matchMedia",
    vi.fn((query: string) => ({
      matches: desktop && query.includes("min-width"),
      media: query,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  );
}

function issue(over: Partial<WorkstreamIssue> = {}): WorkstreamIssue {
  return {
    id: "SOLAA-198",
    title: "Wire Workstream board to live issue store",
    description: "Connect the board to the live store.",
    status: "in_progress",
    priority: "high",
    assigneeRole: "cto",
    user: { name: "Harry Cole", initials: "HC" },
    createdAt: "2026-06-24T09:00:00.000Z",
    updatedAt: "2026-06-26T08:00:00.000Z",
    ...over,
  };
}

beforeEach(() => {
  vi.unstubAllGlobals();
  Object.defineProperty(window, "innerHeight", {
    writable: true,
    configurable: true,
    value: 800,
  });
  installMatchMedia(true);
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("IssueDetailSheet", () => {
  it("renders the two distinct Assignee(role) and User rows + description", () => {
    render(
      <IssueDetailSheet
        open
        issue={issue()}
        notFound={false}
        onClose={() => {}}
        onChangeStatus={() => {}}
      />,
    );
    const dialog = screen.getByRole("dialog", { name: "Issue SOLAA-198" });
    expect(within(dialog).getByText("Assignee (role)")).toBeTruthy();
    expect(within(dialog).getByText(/Chief Technology/)).toBeTruthy();
    // Distinct User row with the specific person.
    expect(within(dialog).getByText("User")).toBeTruthy();
    expect(within(dialog).getByText("Harry Cole")).toBeTruthy();
    expect(within(dialog).getByText(/Connect the board/)).toBeTruthy();
  });

  it("omits the User row cleanly when no user is set", () => {
    render(
      <IssueDetailSheet
        open
        issue={issue({ user: undefined })}
        notFound={false}
        onClose={() => {}}
        onChangeStatus={() => {}}
      />,
    );
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).queryByText("User")).toBeNull();
  });

  it("renders the 'Created by' row for a human author", () => {
    render(
      <IssueDetailSheet
        open
        issue={issue({
          creator: {
            login: "octocat",
            isSoleur: false,
            display: { name: "octocat", initials: "OC" },
          },
        })}
        notFound={false}
        onClose={() => {}}
        onChangeStatus={() => {}}
      />,
    );
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).getByText("Created by")).toBeTruthy();
    expect(within(dialog).getByText("octocat")).toBeTruthy();
  });

  it("renders 'Soleur · initiated by <login>' for a bot-created issue", () => {
    render(
      <IssueDetailSheet
        open
        issue={issue({
          creator: {
            login: "soleur-ai[bot]",
            isSoleur: true,
            initiatorLogin: "harry",
            display: { name: "harry", initials: "HA" },
          },
        })}
        notFound={false}
        onClose={() => {}}
        onChangeStatus={() => {}}
      />,
    );
    const dialog = screen.getByRole("dialog");
    expect(
      within(dialog).getByText("Soleur · initiated by harry"),
    ).toBeTruthy();
  });

  it("omits the 'Created by' row cleanly when no creator is set", () => {
    render(
      <IssueDetailSheet
        open
        issue={issue({ creator: undefined })}
        notFound={false}
        onClose={() => {}}
        onChangeStatus={() => {}}
      />,
    );
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).queryByText("Created by")).toBeNull();
  });

  it("moves the card via the status select (optimistic) with a non-persistence note", () => {
    const onChangeStatus = vi.fn();
    render(
      <IssueDetailSheet
        open
        issue={issue()}
        notFound={false}
        onClose={() => {}}
        onChangeStatus={onChangeStatus}
      />,
    );
    fireEvent.change(screen.getByLabelText("Change status"), {
      target: { value: "done" },
    });
    expect(onChangeStatus).toHaveBeenCalledWith("SOLAA-198", "done");
    expect(screen.getByText(/aren.?t saved yet/i)).toBeTruthy();
  });

  it("renders Issue-not-found state with Back to board", () => {
    const onClose = vi.fn();
    render(
      <IssueDetailSheet
        open
        issue={null}
        notFound
        onClose={onClose}
        onChangeStatus={() => {}}
      />,
    );
    expect(screen.getByText("Issue not found")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: /back to board/i }));
    expect(onClose).toHaveBeenCalled();
  });
});
