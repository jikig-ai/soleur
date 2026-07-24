import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { TransferOwnershipDialog } from "@/components/settings/transfer-ownership-dialog";

const PROPS = {
  targetEmail: "harry@jikigai.com",
  confirmationTarget: "Test Workspace",
  workspaceId: "ws-1",
  targetUserId: "user-member",
  onClose: vi.fn(),
  onSuccess: vi.fn(),
};

describe("TransferOwnershipDialog", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    PROPS.onClose = vi.fn();
    PROPS.onSuccess = vi.fn();
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: true, json: () => Promise.resolve({ ok: true, attestationId: "att-1" }) }),
    );
  });

  it("renders the dialog with warning and confirmation input", () => {
    render(<TransferOwnershipDialog {...PROPS} />);
    expect(screen.getByText("Transfer ownership")).toBeInTheDocument();
    expect(screen.getByText(/cannot be undone/i)).toBeInTheDocument();
    expect(screen.getByText(/GDPR controller designation/i)).toBeInTheDocument();
    expect(screen.getByPlaceholderText(PROPS.confirmationTarget)).toBeInTheDocument();
  });

  it("transfer button is disabled until confirmation matches", () => {
    render(<TransferOwnershipDialog {...PROPS} />);
    const transferBtn = screen.getByRole("button", { name: /transfer ownership/i });
    expect(transferBtn).toBeDisabled();

    fireEvent.change(screen.getByPlaceholderText(PROPS.confirmationTarget), {
      target: { value: "wrong text" },
    });
    expect(transferBtn).toBeDisabled();

    fireEvent.change(screen.getByPlaceholderText(PROPS.confirmationTarget), {
      target: { value: "Test Workspace" },
    });
    expect(transferBtn).not.toBeDisabled();
  });

  it("confirmation is case-insensitive", () => {
    render(<TransferOwnershipDialog {...PROPS} />);
    fireEvent.change(screen.getByPlaceholderText(PROPS.confirmationTarget), {
      target: { value: "test workspace" },
    });
    expect(screen.getByRole("button", { name: /transfer ownership/i })).not.toBeDisabled();
  });

  it("submits transfer with correct payload", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ ok: true, attestationId: "att-1" }),
    });
    vi.stubGlobal("fetch", mockFetch);

    render(<TransferOwnershipDialog {...PROPS} />);
    fireEvent.change(screen.getByPlaceholderText(PROPS.confirmationTarget), {
      target: { value: "Test Workspace" },
    });
    fireEvent.click(screen.getByRole("button", { name: /transfer ownership/i }));

    await vi.waitFor(() => {
      expect(mockFetch).toHaveBeenCalled();
    });
    const [url, init] = mockFetch.mock.calls[0];
    expect(url).toBe("/api/workspace/transfer-ownership");
    expect(init.method).toBe("POST");
    const body = JSON.parse(init.body as string);
    expect(body.workspaceId).toBe("ws-1");
    expect(body.newOwnerUserId).toBe("user-member");
    expect(body.attestationText).toMatch(/voluntarily transfer ownership/i);
  });

  it("displays error message on API failure", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        json: () => Promise.resolve({ error: "target_not_member" }),
      }),
    );

    render(<TransferOwnershipDialog {...PROPS} />);
    fireEvent.change(screen.getByPlaceholderText(PROPS.confirmationTarget), {
      target: { value: "Test Workspace" },
    });
    fireEvent.click(screen.getByRole("button", { name: /transfer ownership/i }));

    await vi.waitFor(() => {
      expect(screen.getByText(/not a member/i)).toBeInTheDocument();
    });
  });

  it("calls onClose when Cancel is clicked", () => {
    render(<TransferOwnershipDialog {...PROPS} />);
    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));
    expect(PROPS.onClose).toHaveBeenCalled();
  });

  it("calls onClose on Escape key", () => {
    render(<TransferOwnershipDialog {...PROPS} />);
    fireEvent.keyDown(document, { key: "Escape" });
    expect(PROPS.onClose).toHaveBeenCalled();
  });

  it("calls onClose on backdrop click", () => {
    render(<TransferOwnershipDialog {...PROPS} />);
    // The ResponsiveModal shell renders role="dialog" on the panel and wraps it
    // in a backdrop element; clicking the backdrop (the panel's parent) closes.
    const backdrop = screen.getByRole("dialog").parentElement as HTMLElement;
    fireEvent.click(backdrop);
    expect(PROPS.onClose).toHaveBeenCalled();
  });
});
