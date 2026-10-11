import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { BashAutonomousToggle } from "@/components/settings/bash-autonomous-toggle";

// Issue B part 2 (AC17) — the settings toggle + risk interstitial. Owner-gated;
// turning ON is gated behind an explicit risk confirmation; turning OFF is not.

const originalFetch = global.fetch;

beforeEach(() => {
  vi.restoreAllMocks();
});
afterEach(() => {
  global.fetch = originalFetch;
});

describe("BashAutonomousToggle", () => {
  test("renders nothing for a non-owner", () => {
    const { container } = render(
      <BashAutonomousToggle initialAutonomous={false} isOwner={false} />,
    );
    expect(container.firstChild).toBeNull();
  });

  test("turning ON shows the risk interstitial BEFORE any write", () => {
    const fetchSpy = vi.fn();
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));

    // Interstitial appears; NO write has happened yet.
    expect(screen.getByRole("alertdialog")).toBeTruthy();
    expect(
      screen.getByText(/no blocklist is perfect/i),
    ).toBeTruthy();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  // CLO ruling section 2 — verbatim (JSX renders &apos; as an apostrophe).
  const LOCKED_CONFIRM =
    "The Concierge will run non-blocked commands without asking, except that it pauses to ask before common forms of a force-push over, or deletion of, your repository's default branch (which can erase its history on GitHub), and before terraform destroy. The blocklist (curl, wget, sudo, …) still applies, but no blocklist is perfect. The pauses do not recognise every way of writing those commands, or every other way to delete a repository or tear down infrastructure, so such a command can still run without asking. Other commands that look safe could still change or delete files in this workspace. You can watch each step in the chat. Only turn this on for repos and accounts you trust.";

  test("interstitial carries the CLO paragraph verbatim and not the removed claims (#9776 ask-gate)", () => {
    global.fetch = vi.fn() as unknown as typeof fetch;
    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));
    const dialog = screen.getByRole("alertdialog");
    const text = (dialog.textContent ?? "").replace(/\s+/g, " ");
    expect(text).toContain(LOCKED_CONFIRM);
    for (const gone of [/backed up in git/i, /secret redaction/i, /Until a stricter check ships/i, /will run any non-blocked command/i]) {
      expect(text).not.toMatch(gone);
    }
    for (const kept of [/no blocklist is perfect/i, /pauses to ask/, /do not recognise every way/, /terraform destroy/, /without asking/]) {
      expect(text).toMatch(kept);
    }
  });

  test("vocabulary guard (CLO C3): the lane sentences in the confirm paragraph never claim blocks, prevents, protects, safe to approve, guaranteed or always", () => {
    const sentences = LOCKED_CONFIRM.split(/(?<=[.])\s+/).filter((x) => /pauses? to ask|pauses do not|do not recognise every way/i.test(x));
    expect(sentences.length).toBeGreaterThanOrEqual(2);
    for (const sentence of sentences) expect(sentence).not.toMatch(/\b(blocks|prevents?|protects?|safe to approve|guaranteed?|always)\b/i);
    // And the rendered text contains exactly those sentences (the guard reads the real bytes, not a copy).
    global.fetch = vi.fn() as unknown as typeof fetch;
    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));
    const text = (screen.getByRole("alertdialog").textContent ?? "").replace(/\s+/g, " ");
    for (const sentence of sentences) expect(text).toContain(sentence);
  });

  test("confirming the interstitial POSTs value:true", async () => {
    const fetchSpy = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ autonomous: true }),
    });
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));
    fireEvent.click(screen.getByRole("button", { name: /turn it on/i }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
    const [url, init] = fetchSpy.mock.calls[0];
    expect(url).toBe("/api/workspace/bash-autonomous");
    expect(JSON.parse(init.body)).toEqual({ value: true });
    await waitFor(() =>
      expect(screen.getByRole("switch").getAttribute("aria-checked")).toBe("true"),
    );
  });

  test("Cancel dismisses the interstitial without writing", () => {
    const fetchSpy = vi.fn();
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));
    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));

    expect(screen.queryByRole("alertdialog")).toBeNull();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  test("turning OFF writes immediately with NO interstitial", async () => {
    const fetchSpy = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ autonomous: false }),
    });
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={true} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));

    // No interstitial for OFF; write fires straight away with value:false.
    expect(screen.queryByRole("alertdialog")).toBeNull();
    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
    expect(JSON.parse(fetchSpy.mock.calls[0][1].body)).toEqual({ value: false });
  });

  test("non-owner write rejection (403) alerts and does not flip", async () => {
    const alertSpy = vi.fn();
    window.alert = alertSpy;
    const fetchSpy = vi.fn().mockResolvedValue({ ok: false, status: 403 });
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));
    fireEvent.click(screen.getByRole("button", { name: /turn it on/i }));

    await waitFor(() => expect(alertSpy).toHaveBeenCalled());
    expect(screen.getByRole("switch").getAttribute("aria-checked")).toBe("false");
  });
});
