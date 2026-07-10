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
import { SwrTestProvider } from "../../helpers/swr-wrapper";

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

const OPTIONS = {
  labels: [
    { name: "bug", color: "d73a4a" },
    { name: "chore", color: "cccccc" },
  ],
  assignees: [{ login: "harry" }, { login: "ada" }],
  milestones: [
    { number: 1, title: "v1" },
    { number: 2, title: "v2" },
  ],
};

function renderEditable(
  props: Partial<React.ComponentProps<typeof IssueDetailSheet>> = {},
) {
  return render(
    <SwrTestProvider>
      <IssueDetailSheet
        open
        issue={issue({
          body: "the raw body",
          labels: ["bug"],
          assignees: ["harry"],
          milestone: { number: 1, title: "v1" },
        })}
        notFound={false}
        onClose={() => {}}
        onChangeStatus={() => {}}
        onReopen={() => {}}
        onUpdateTitle={() => {}}
        onUpdateFields={() => {}}
        {...props}
      />
    </SwrTestProvider>,
  );
}

describe("IssueDetailSheet — edit fields (edit-fields)", () => {
  it("edits the description body and calls onUpdateFields with { body }", async () => {
    const onUpdateFields = vi.fn().mockResolvedValue(undefined);
    renderEditable({ onUpdateFields });
    fireEvent.click(screen.getByLabelText("Edit description"));
    const textarea = screen.getByLabelText(
      "Edit description",
    ) as HTMLTextAreaElement;
    // Prefilled with the marker-STRIPPED body.
    expect(textarea.value).toBe("the raw body");
    fireEvent.change(textarea, { target: { value: "updated body" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(onUpdateFields).toHaveBeenCalledWith(
        "198",
        { body: "updated body", description: "updated body" },
        { body: "updated body" },
      ),
    );
  });

  it("allows saving an EMPTY body (unlike title)", async () => {
    const onUpdateFields = vi.fn().mockResolvedValue(undefined);
    renderEditable({ onUpdateFields });
    fireEvent.click(screen.getByLabelText("Edit description"));
    fireEvent.change(screen.getByLabelText("Edit description"), {
      target: { value: "" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(onUpdateFields).toHaveBeenCalledWith(
        "198",
        { body: "", description: "" },
        { body: "" },
      ),
    );
  });

  it("keeps the body editor open when the save fails (retryable)", async () => {
    const onUpdateFields = vi.fn().mockRejectedValue(new Error("boom"));
    renderEditable({ onUpdateFields });
    fireEvent.click(screen.getByLabelText("Edit description"));
    fireEvent.change(screen.getByLabelText("Edit description"), {
      target: { value: "x" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(onUpdateFields).toHaveBeenCalled());
    // Editor is still open (textarea present) for a retry.
    expect(screen.getByLabelText("Edit description")).toBeTruthy();
  });

  it("changes the milestone via the select (number → { milestone })", async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => OPTIONS,
    }) as unknown as typeof fetch;
    const onUpdateFields = vi.fn().mockResolvedValue(undefined);
    renderEditable({ onUpdateFields });
    const select = screen.getByLabelText("Change milestone");
    // Focus triggers the lazy options fetch so v2 becomes selectable.
    fireEvent.focus(select);
    await waitFor(() =>
      expect(within(select as HTMLSelectElement).getByText("v2")).toBeTruthy(),
    );
    fireEvent.change(select, { target: { value: "2" } });
    await waitFor(() =>
      expect(onUpdateFields).toHaveBeenCalledWith(
        "198",
        { milestone: { number: 2, title: "v2" } },
        { milestone: 2 },
      ),
    );
  });

  it("clears the milestone (No milestone → null)", async () => {
    const onUpdateFields = vi.fn().mockResolvedValue(undefined);
    renderEditable({ onUpdateFields });
    fireEvent.change(screen.getByLabelText("Change milestone"), {
      target: { value: "" },
    });
    await waitFor(() =>
      expect(onUpdateFields).toHaveBeenCalledWith(
        "198",
        { milestone: null },
        { milestone: null },
      ),
    );
  });

  it("edits labels from the fetched options and saves NON-status selection", async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => OPTIONS,
    }) as unknown as typeof fetch;
    const onUpdateFields = vi.fn().mockResolvedValue(undefined);
    renderEditable({ onUpdateFields });
    fireEvent.click(screen.getByLabelText("Edit labels"));
    // The options fetch resolves and the checklist appears.
    await waitFor(() =>
      expect(screen.getByLabelText("Labels editor")).toBeTruthy(),
    );
    // Add "chore" (bug is already selected from the issue).
    await waitFor(() => expect(screen.getByLabelText("chore")).toBeTruthy());
    fireEvent.click(screen.getByLabelText("chore"));
    fireEvent.click(
      within(screen.getByLabelText("Labels editor")).getByRole("button", {
        name: "Save",
      }),
    );
    await waitFor(() =>
      expect(onUpdateFields).toHaveBeenCalledWith(
        "198",
        { labels: ["bug", "chore"] },
        { labels: ["bug", "chore"] },
      ),
    );
  });

  it("edits assignees from the fetched options", async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => OPTIONS,
    }) as unknown as typeof fetch;
    const onUpdateFields = vi.fn().mockResolvedValue(undefined);
    renderEditable({ onUpdateFields });
    fireEvent.click(screen.getByLabelText("Edit assignees"));
    await waitFor(() =>
      expect(screen.getByLabelText("Assignees editor")).toBeTruthy(),
    );
    await waitFor(() => expect(screen.getByLabelText("ada")).toBeTruthy());
    fireEvent.click(screen.getByLabelText("ada"));
    fireEvent.click(
      within(screen.getByLabelText("Assignees editor")).getByRole("button", {
        name: "Save",
      }),
    );
    await waitFor(() =>
      expect(onUpdateFields).toHaveBeenCalledWith(
        "198",
        { assignees: ["harry", "ada"] },
        { assignees: ["harry", "ada"] },
      ),
    );
  });

  it("hides the field editors when onUpdateFields is absent", () => {
    renderSheet(); // no onUpdateFields
    expect(screen.queryByLabelText("Edit description")).toBeNull();
    expect(screen.queryByLabelText("Edit labels")).toBeNull();
    expect(screen.queryByLabelText("Change milestone")).toBeNull();
  });

  it("hides the field editors in read-only mode", () => {
    renderEditable({ readOnly: true });
    expect(screen.queryByLabelText("Edit description")).toBeNull();
    expect(screen.queryByLabelText("Edit labels")).toBeNull();
    expect(screen.queryByLabelText("Change milestone")).toBeNull();
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
