import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";

// feat-skip-api-key-onboarding (#4642) — AC6. NoApiKeyBanner self-fetches
// /api/byok/effective-status and renders ONLY when hasEffectiveKey === false.
// Copy branches on pendingDelegation: a grant-holder is told to accept the
// grant (one click), not to buy a separate Anthropic account.

import { NoApiKeyBanner } from "@/components/dashboard/no-api-key-banner";

function mockStatus(body: { hasEffectiveKey: boolean; pendingDelegation: boolean }) {
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue({ ok: true, json: async () => body }),
  );
}

beforeEach(() => vi.clearAllMocks());
afterEach(() => vi.unstubAllGlobals());

describe("NoApiKeyBanner (AC6)", () => {
  it("renders nothing when the user has an effective key", async () => {
    mockStatus({ hasEffectiveKey: true, pendingDelegation: false });
    const { container } = render(<NoApiKeyBanner />);
    // Give the self-fetch a tick to resolve; it must stay empty.
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    expect(container.querySelector('[role="region"]')).toBeNull();
  });

  it("keyless + no pending grant → add-key CTA to /dashboard/settings/services", async () => {
    mockStatus({ hasEffectiveKey: false, pendingDelegation: false });
    render(<NoApiKeyBanner />);
    const cta = await screen.findByRole("link", { name: /add.*key|settings/i });
    expect(cta.getAttribute("href")).toBe("/dashboard/settings/services");
    expect(screen.getByText(/tasks are disabled/i)).toBeTruthy();
  });

  it("keyless + pending grant → accept-grant copy + link to /dashboard/settings/team", async () => {
    mockStatus({ hasEffectiveKey: false, pendingDelegation: true });
    render(<NoApiKeyBanner />);
    const cta = await screen.findByRole("link", { name: /accept|grant|shared access/i });
    expect(cta.getAttribute("href")).toBe("/dashboard/settings/team");
    expect(screen.getByText(/granted shared access/i)).toBeTruthy();
  });

  it("renders nothing when the status fetch fails (safe degradation)", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network")));
    const { container } = render(<NoApiKeyBanner />);
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    expect(container.querySelector('[role="region"]')).toBeNull();
  });
});
