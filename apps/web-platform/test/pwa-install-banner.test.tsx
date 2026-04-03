import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// Store original UA for restoration
const originalUA = navigator.userAgent;

function setUserAgent(ua: string) {
  Object.defineProperty(navigator, "userAgent", {
    value: ua,
    writable: true,
    configurable: true,
  });
}

describe("PwaInstallBanner", () => {
  afterEach(() => {
    setUserAgent(originalUA);
  });

  it("renders for iOS Safari user when not dismissed", async () => {
    setUserAgent(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
    );
    const { PwaInstallBanner } = await import(
      "@/components/chat/pwa-install-banner"
    );
    render(<PwaInstallBanner dismissed={false} onDismiss={vi.fn()} />);
    expect(
      screen.getByText("Add Soleur to Your Home Screen"),
    ).toBeInTheDocument();
  });

  it("does not render for Chrome on iOS", async () => {
    setUserAgent(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0.0.0 Mobile/15E148 Safari/604.1",
    );
    const { PwaInstallBanner } = await import(
      "@/components/chat/pwa-install-banner"
    );
    render(<PwaInstallBanner dismissed={false} onDismiss={vi.fn()} />);
    expect(
      screen.queryByText("Add Soleur to Your Home Screen"),
    ).not.toBeInTheDocument();
  });

  it("does not render for Android", async () => {
    setUserAgent(
      "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    );
    const { PwaInstallBanner } = await import(
      "@/components/chat/pwa-install-banner"
    );
    render(<PwaInstallBanner dismissed={false} onDismiss={vi.fn()} />);
    expect(
      screen.queryByText("Add Soleur to Your Home Screen"),
    ).not.toBeInTheDocument();
  });

  it("does not render when dismissed", async () => {
    setUserAgent(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
    );
    const { PwaInstallBanner } = await import(
      "@/components/chat/pwa-install-banner"
    );
    render(<PwaInstallBanner dismissed={true} onDismiss={vi.fn()} />);
    expect(
      screen.queryByText("Add Soleur to Your Home Screen"),
    ).not.toBeInTheDocument();
  });

  it("calls onDismiss when dismiss button clicked", async () => {
    setUserAgent(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
    );
    const onDismiss = vi.fn();
    const { PwaInstallBanner } = await import(
      "@/components/chat/pwa-install-banner"
    );
    render(<PwaInstallBanner dismissed={false} onDismiss={onDismiss} />);
    const dismissBtn = screen.getByRole("button", { name: /dismiss/i });
    await userEvent.click(dismissBtn);
    expect(onDismiss).toHaveBeenCalledOnce();
  });
});
