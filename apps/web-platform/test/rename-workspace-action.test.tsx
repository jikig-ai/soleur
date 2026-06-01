import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { RenameWorkspaceAction } from "@/components/settings/rename-workspace-action";

// AC5: owner-only rename control on /dashboard/settings/team, prefilled with
// the current org name. Non-owners see the name but no edit affordance.

const ORG_ID = "00000000-0000-0000-0000-0000000000aa";

describe("RenameWorkspaceAction", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("owner sees the current name and a Rename control", () => {
    render(
      <RenameWorkspaceAction organizationId={ORG_ID} organizationName="My Workspace" isOwner />,
    );
    expect(screen.getByTestId("workspace-name").textContent).toBe("My Workspace");
    expect(screen.getByRole("button", { name: /rename/i })).toBeInTheDocument();
  });

  it("non-owner sees the name but no Rename control", () => {
    render(
      <RenameWorkspaceAction
        organizationId={ORG_ID}
        organizationName="My Workspace"
        isOwner={false}
      />,
    );
    expect(screen.getByTestId("workspace-name").textContent).toBe("My Workspace");
    expect(screen.queryByRole("button", { name: /rename/i })).not.toBeInTheDocument();
  });

  it("owner can rename: input is prefilled, POSTs the new name, updates display", async () => {
    const fetchMock = vi.fn(
      async (_url: string, _init?: RequestInit) =>
        new Response(JSON.stringify({ ok: true, name: "Acme Studio" }), { status: 200 }),
    );
    vi.stubGlobal("fetch", fetchMock);

    render(
      <RenameWorkspaceAction organizationId={ORG_ID} organizationName="My Workspace" isOwner />,
    );
    fireEvent.click(screen.getByRole("button", { name: /rename/i }));

    const input = screen.getByLabelText(/workspace name/i) as HTMLInputElement;
    expect(input.value).toBe("My Workspace"); // prefilled
    fireEvent.change(input, { target: { value: "Acme Studio" } });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/workspace/rename",
        expect.objectContaining({ method: "POST" }),
      );
    });
    const init = fetchMock.mock.calls[0][1]!;
    const sentBody = JSON.parse(init.body as string);
    expect(sentBody).toEqual({ organizationId: ORG_ID, name: "Acme Studio" });

    await waitFor(() => {
      expect(screen.getByTestId("workspace-name").textContent).toBe("Acme Studio");
    });
  });

  it("rejects empty/whitespace name without calling the API", () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    render(
      <RenameWorkspaceAction organizationId={ORG_ID} organizationName="My Workspace" isOwner />,
    );
    fireEvent.click(screen.getByRole("button", { name: /rename/i }));
    const input = screen.getByLabelText(/workspace name/i);
    fireEvent.change(input, { target: { value: "   " } });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    expect(fetchMock).not.toHaveBeenCalled();
    expect(screen.getByRole("alert")).toBeInTheDocument();
  });

  it("surfaces an error when the API call fails", async () => {
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ error: "rpc_failed" }), { status: 500 }),
    );
    vi.stubGlobal("fetch", fetchMock);

    render(
      <RenameWorkspaceAction organizationId={ORG_ID} organizationName="My Workspace" isOwner />,
    );
    fireEvent.click(screen.getByRole("button", { name: /rename/i }));
    fireEvent.change(screen.getByLabelText(/workspace name/i), {
      target: { value: "Acme Studio" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    await waitFor(() => {
      expect(screen.getByRole("alert")).toBeInTheDocument();
    });
    // Display name unchanged on failure.
    expect(screen.getByTestId("workspace-name").textContent).toBe("My Workspace");
  });
});
