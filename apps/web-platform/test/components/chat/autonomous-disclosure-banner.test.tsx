import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

// feat-bash-autonomous-default-on — first-run consent soft-gate banner. Renders
// the LOCKED disclosure copy verbatim; "Got it" / opt-out buttons call the
// respond handler which writes the ack + releases the held command.

import {
  AutonomousDisclosureBanner,
  AUTONOMOUS_DISCLOSURE_COPY,
} from "@/components/chat/autonomous-disclosure-banner";

// LOCKED COPY (re-locked 2026-10-08, #9776) — assert the constant is verbatim.
const LOCKED =
  "Soleur runs commands automatically. It blocks a short list of risky " +
  "commands (curl, wget, sudo, …), but no blocklist is perfect. Until a " +
  "stricter check ships, it can force-push over your repository's default " +
  "branch (erasing its history on GitHub) or run infrastructure teardown " +
  "(terraform destroy) without asking. Other commands that look safe could " +
  "still change or delete files in this workspace. You can watch each step " +
  "in the chat. Only connect repos and accounts you trust.";

describe("AutonomousDisclosureBanner", () => {
  beforeEach(() => vi.clearAllMocks());

  test("disclosure copy is the LOCKED paragraph verbatim", () => {
    expect(AUTONOMOUS_DISCLOSURE_COPY).toBe(LOCKED);
  });

  test("copy no longer carries the removed false claims", () => {
    expect(AUTONOMOUS_DISCLOSURE_COPY).not.toMatch(/hides your secrets/i);
    expect(AUTONOMOUS_DISCLOSURE_COPY).not.toMatch(/always blocks/i);
    expect(AUTONOMOUS_DISCLOSURE_COPY).not.toMatch(/backed up in git/i);
    expect(AUTONOMOUS_DISCLOSURE_COPY).toMatch(/force-push/);
    expect(AUTONOMOUS_DISCLOSURE_COPY).toMatch(/terraform destroy/);
  });

  test("renders the LOCKED copy in the DOM", () => {
    render(
      <AutonomousDisclosureBanner
        gateId="g1"
        existingWorkspace={false}
        onRespond={vi.fn()}
      />,
    );
    expect(screen.getByText(LOCKED)).toBeTruthy();
  });

  test("default-ON workspace shows a single 'Got it' that calls onRespond", () => {
    const onRespond = vi.fn();
    render(
      <AutonomousDisclosureBanner
        gateId="g1"
        existingWorkspace={false}
        onRespond={onRespond}
      />,
    );
    expect(screen.queryByText("Keep autonomous on")).toBeNull();
    fireEvent.click(screen.getByText("Got it"));
    expect(onRespond).toHaveBeenCalledWith("g1", "Got it");
  });

  test("existing workspace offers the opt-out (Keep on / Ask each)", () => {
    const onRespond = vi.fn();
    render(
      <AutonomousDisclosureBanner
        gateId="g2"
        existingWorkspace={true}
        onRespond={onRespond}
      />,
    );
    fireEvent.click(screen.getByText("Keep autonomous on"));
    expect(onRespond).toHaveBeenCalledWith("g2", "Keep autonomous on");
    fireEvent.click(screen.getByText("Ask me each time"));
    expect(onRespond).toHaveBeenCalledWith("g2", "Ask me each time");
  });

  test("uses sharp corners (rounded-none) on the card", () => {
    const { container } = render(
      <AutonomousDisclosureBanner
        gateId="g1"
        existingWorkspace={false}
        onRespond={vi.fn()}
      />,
    );
    const card = container.querySelector(
      '[data-message-type="autonomous_disclosure"]',
    );
    expect(card?.className).toContain("rounded-none");
  });
});
