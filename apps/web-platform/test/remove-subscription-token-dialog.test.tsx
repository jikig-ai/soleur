import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

const refresh = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh }),
  useSearchParams: () => new URLSearchParams(),
}));

import { RemoveSubscriptionTokenDialog } from "@/components/settings/remove-subscription-token-dialog";
import { describeCredentialBasis } from "@/lib/credential-basis";

const fetchMock = vi.fn();

function basis(oauthInEffect: boolean, hasApiKey: boolean) {
  return describeCredentialBasis({
    hasOauthToken: true,
    oauthInEffect,
    hasApiKey,
  })!;
}

function setup(
  b: ReturnType<typeof basis>,
  over: Partial<{
    onRemoved: (b: ReturnType<typeof basis>) => void;
    onAddApiKey: () => void;
  }> = {},
) {
  const onRemoved = over.onRemoved ?? vi.fn();
  const onAddApiKey = over.onAddApiKey ?? vi.fn();
  render(
    <RemoveSubscriptionTokenDialog
      basis={b}
      onRemoved={onRemoved}
      onAddApiKey={onAddApiKey}
    />,
  );
  return { onRemoved, onAddApiKey };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal("fetch", fetchMock);
});

describe("RemoveSubscriptionTokenDialog", () => {
  it("renders the control collapsed by default", () => {
    setup(basis(true, true));
    expect(
      screen.getByRole("button", { name: "Remove subscription token" }),
    ).toBeInTheDocument();
    expect(screen.queryByText("Remove subscription token?")).toBeNull();
  });

  it("variant A: title, exact body, Keep token has default focus, no Add an API key first", async () => {
    setup(basis(true, true));
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    expect(screen.getByText("Remove subscription token?")).toBeInTheDocument();
    expect(
      screen.getByText(
        "Conversations will use your Anthropic API key, and its usage charges apply. Conversations already open keep using the token until they end. Removing it here does not revoke it with Anthropic - revoke it in your Claude account if it may be exposed.",
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Keep token" })).toHaveFocus();
    expect(screen.getByRole("button", { name: "Remove token" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Add an API key first" })).toBeNull();
  });

  it("variant B: exact body and Add an API key first (calls onAddApiKey and closes)", async () => {
    const { onAddApiKey } = setup(basis(true, false));
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    expect(
      screen.getByText(
        /^You will have no sign-in for Claude until you add an API key, and chat will stop working\. Removing it here does not revoke it with Anthropic/,
      ),
    ).toBeInTheDocument();
    await userEvent.click(
      screen.getByRole("button", { name: "Add an API key first" }),
    );
    expect(onAddApiKey).toHaveBeenCalledTimes(1);
    expect(screen.queryByText("Remove subscription token?")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("variant C: neutral body, no billing claim, no Add an API key first", async () => {
    setup(basis(false, true));
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    expect(
      screen.getByText(
        /^Soleur is not using this token for conversations\. Removing deletes the saved copy\./,
      ),
    ).toBeInTheDocument();
    expect(screen.queryByText(/usage charges apply/)).toBeNull();
    expect(screen.queryByRole("button", { name: "Add an API key first" })).toBeNull();
  });

  it("Keep token closes the dialog without a request", async () => {
    setup(basis(true, true));
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Keep token" }));
    expect(screen.queryByText("Remove subscription token?")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("Remove token sends DELETE with exactly the oauth_token body, then notifies and refreshes", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ deleted: true }),
    });
    const b = basis(true, true);
    const { onRemoved } = setup(b);
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Remove token" }));

    await waitFor(() => expect(onRemoved).toHaveBeenCalledTimes(1));
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/keys");
    expect(init.method).toBe("DELETE");
    expect(JSON.parse(init.body)).toEqual({ credential_type: "oauth_token" });
    // The notice text is chosen from the props the user confirmed against.
    expect(onRemoved).toHaveBeenCalledWith(b);
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it("disables both buttons while the request is pending", async () => {
    let resolve!: (v: unknown) => void;
    fetchMock.mockReturnValue(new Promise((r) => (resolve = r)));
    setup(basis(true, true));
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Remove token" }));
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Keep token" })).toBeDisabled(),
    );
    const removing = screen.getAllByRole("button").find((x) =>
      /Removing/.test(x.textContent ?? ""),
    );
    expect(removing).toBeDefined();
    expect(removing).toBeDisabled();
    resolve({ ok: true, status: 200, json: async () => ({ deleted: true }) });
  });

  it("shows the server-failure alert on a non-OK response and keeps the dialog open", async () => {
    fetchMock.mockResolvedValue({
      ok: false,
      status: 500,
      json: async () => ({ error: "Failed to remove token" }),
    });
    const { onRemoved } = setup(basis(true, true));
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Remove token" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Failed to remove the token. Please try again.",
    );
    expect(onRemoved).not.toHaveBeenCalled();
    expect(refresh).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "Remove token" })).toBeEnabled();
  });

  it("shows the network alert when fetch rejects", async () => {
    fetchMock.mockRejectedValue(new Error("boom"));
    const { onRemoved } = setup(basis(true, true));
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    await userEvent.click(screen.getByRole("button", { name: "Remove token" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Network error. Please try again.",
    );
    expect(onRemoved).not.toHaveBeenCalled();
  });

  it("uses no native token-shaped text and never echoes a stored value", async () => {
    setup(basis(true, true));
    await userEvent.click(
      screen.getByRole("button", { name: "Remove subscription token" }),
    );
    expect(document.body.textContent).not.toMatch(/sk-ant-oat/);
  });
});
