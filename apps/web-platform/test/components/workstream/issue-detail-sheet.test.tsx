import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import type { WorkstreamIssue } from "@/lib/workstream";
import { IssueDetailSheet } from "@/components/workstream/issue-detail-sheet";

function issue(over: Partial<WorkstreamIssue> = {}): WorkstreamIssue {
  return {
    id: "198",
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

// Default props — the write handlers are stubbed unless a test overrides them.
function renderSheet(props: Partial<React.ComponentProps<typeof IssueDetailSheet>> = {}) {
  return render(
    <IssueDetailSheet
      open
      issue={issue()}
      notFound={false}
      onClose={() => {}}
      onChangeStatus={() => {}}
      onReopen={() => {}}
      onUpdateTitle={() => {}}
      {...props}
    />,
  );
}

beforeEach(() => {
  Object.defineProperty(window, "innerHeight", {
    writable: true,
    configurable: true,
    value: 800,
  });
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("IssueDetailSheet — display rows", () => {
  it("renders the two distinct Assignee(role) and User rows + description", () => {
    renderSheet();
    const dialog = screen.getByRole("dialog", { name: "Issue 198" });
    expect(within(dialog).getByText("Assignee (role)")).toBeTruthy();
    expect(within(dialog).getByText(/Chief Technology/)).toBeTruthy();
    expect(within(dialog).getByText("User")).toBeTruthy();
    expect(within(dialog).getByText("Harry Cole")).toBeTruthy();
    expect(within(dialog).getByText(/Connect the board/)).toBeTruthy();
  });

  it("omits the User row cleanly when no user is set", () => {
    renderSheet({ issue: issue({ user: undefined }) });
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).queryByText("User")).toBeNull();
  });

  it("renders 'Soleur · initiated by <login>' for a bot-created issue", () => {
    renderSheet({
      issue: issue({
        creator: {
          login: "soleur-ai[bot]",
          isSoleur: true,
          initiatorLogin: "harry",
          display: { name: "harry", initials: "HA" },
        },
      }),
    });
    expect(screen.getByText("Soleur · initiated by harry")).toBeTruthy();
  });
});

describe("IssueDetailSheet — status write (AC2/AC7)", () => {
  it("moves the card via the status select (persisted, no 'not saved' note)", () => {
    const onChangeStatus = vi.fn();
    renderSheet({ onChangeStatus });
    fireEvent.change(screen.getByLabelText("Change status"), {
      target: { value: "blocked" },
    });
    expect(onChangeStatus).toHaveBeenCalledWith("198", "blocked");
    expect(screen.queryByText(/aren.?t saved yet/i)).toBeNull();
  });
});

describe("IssueDetailSheet — close / reopen (AC10)", () => {
  it("closes with a reason (both reasons land in Done)", () => {
    const onChangeStatus = vi.fn();
    renderSheet({ onChangeStatus });
    fireEvent.click(screen.getByRole("button", { name: /close issue/i }));
    fireEvent.click(screen.getByRole("button", { name: /not planned/i }));
    expect(onChangeStatus).toHaveBeenCalledWith("198", "done", "not_planned");
  });

  it("offers Reopen for a closed (done) issue → onReopen", () => {
    const onReopen = vi.fn();
    renderSheet({ issue: issue({ status: "done" }), onReopen });
    // No "Close issue" for an already-closed issue; Reopen is shown.
    expect(screen.queryByRole("button", { name: /close issue/i })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: /reopen issue/i }));
    expect(onReopen).toHaveBeenCalledWith("198");
  });
});

describe("IssueDetailSheet — inline title edit (AC: FR3)", () => {
  it("edits the title and calls onUpdateTitle on save", async () => {
    const onUpdateTitle = vi.fn().mockResolvedValue(undefined);
    renderSheet({ onUpdateTitle });
    fireEvent.click(screen.getByRole("button", { name: /edit title/i }));
    const input = screen.getByLabelText("Edit title") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "Renamed" } });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));
    await waitFor(() =>
      expect(onUpdateTitle).toHaveBeenCalledWith("198", "Renamed"),
    );
  });
});

describe("IssueDetailSheet — board precedence + read-only (AC11/AC14)", () => {
  it("disables the status select on the org board while the grant is absent, but Close still works", () => {
    const onChangeStatus = vi.fn();
    renderSheet({
      onKanbanOrg: true,
      boardPrecedence: true,
      onChangeStatus,
    });
    expect(
      (screen.getByLabelText("Change status") as HTMLSelectElement).disabled,
    ).toBe(true);
    // Close/reopen remain available.
    fireEvent.click(screen.getByRole("button", { name: /close issue/i }));
    fireEvent.click(screen.getByRole("button", { name: /completed/i }));
    expect(onChangeStatus).toHaveBeenCalledWith("198", "done", "completed");
  });

  it("shows the Project-board sync note only for the org repo", () => {
    const { rerender } = renderSheet({ onKanbanOrg: false });
    expect(screen.queryByText(/Project board/i)).toBeNull();
    rerender(
      <IssueDetailSheet
        open
        issue={issue()}
        notFound={false}
        onKanbanOrg
        onClose={() => {}}
        onChangeStatus={() => {}}
        onReopen={() => {}}
        onUpdateTitle={() => {}}
      />,
    );
    expect(screen.getByText(/Project board/i)).toBeTruthy();
  });

  it("read-only disables status + hides write affordances with a hint", () => {
    renderSheet({ readOnly: true });
    expect(
      (screen.getByLabelText("Change status") as HTMLSelectElement).disabled,
    ).toBe(true);
    expect(screen.queryByRole("button", { name: /close issue/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /edit title/i })).toBeNull();
    expect(screen.getByText(/read-only access/i)).toBeTruthy();
  });
});

describe("IssueDetailSheet — not found", () => {
  it("renders Issue-not-found state with Back to board", () => {
    const onClose = vi.fn();
    renderSheet({ issue: null, notFound: true, onClose });
    expect(screen.getByText("Issue not found")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: /back to board/i }));
    expect(onClose).toHaveBeenCalled();
  });
});
