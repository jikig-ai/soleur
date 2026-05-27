import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { InviteMemberModal } from "@/components/settings/invite-member-modal";

const WORKSPACE_ID = "ws-1";

describe("InviteMemberModal", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: () => Promise.resolve({}) }));
  });

  it("renders nothing when open=false", () => {
    const { container } = render(
      <InviteMemberModal open={false} workspaceId={WORKSPACE_ID} onClose={() => {}} />,
    );
    expect(container.querySelector("[role=\"dialog\"]")).toBeNull();
  });

  it("renders form when open=true", () => {
    render(
      <InviteMemberModal open={true} workspaceId={WORKSPACE_ID} onClose={() => {}} />,
    );
    expect(screen.getByText(/Invite member/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Email address/i)).toBeInTheDocument();
  });

  it("Send invite CTA disabled until attestation checkbox is checked", () => {
    render(
      <InviteMemberModal open={true} workspaceId={WORKSPACE_ID} onClose={() => {}} />,
    );
    const submit = screen.getByRole("button", { name: /send invite/i });
    expect(submit).toBeDisabled();

    const input = screen.getByLabelText(/Email address/i);
    fireEvent.change(input, { target: { value: "harry@jikigai.com" } });
    expect(submit).toBeDisabled();

    const checkbox = screen.getByLabelText(/employee or contractor/i);
    fireEvent.click(checkbox);
    expect(submit).not.toBeDisabled();
  });

  it("submit posts to invite endpoint with email and attestation text", async () => {
    const onClose = vi.fn();
    const mockFetch = vi.fn().mockResolvedValue({ ok: true, json: () => Promise.resolve({}) });
    vi.stubGlobal("fetch", mockFetch);

    render(
      <InviteMemberModal open={true} workspaceId={WORKSPACE_ID} onClose={onClose} />,
    );
    fireEvent.change(screen.getByLabelText(/Email address/i), {
      target: { value: "harry@jikigai.com" },
    });
    fireEvent.click(screen.getByLabelText(/employee or contractor/i));
    fireEvent.click(screen.getByRole("button", { name: /send invite/i }));

    await vi.waitFor(() => {
      expect(mockFetch).toHaveBeenCalled();
    });
    const [url, init] = mockFetch.mock.calls[0];
    expect(url).toBe("/api/workspace/invite-member");
    expect(init.method).toBe("POST");
    const body = JSON.parse(init.body as string);
    expect(body.workspaceId).toBe(WORKSPACE_ID);
    expect(body.email).toBe("harry@jikigai.com");
    expect(body.role).toBe("member");
    expect(body.attestationText).toMatch(/employee or contractor/i);
  });
});
