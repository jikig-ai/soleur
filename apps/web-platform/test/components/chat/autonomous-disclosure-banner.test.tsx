import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

// feat-bash-autonomous-default-on — first-run consent soft-gate banner. Renders
// the LOCKED disclosure copy verbatim; "Got it" / opt-out buttons call the
// respond handler which writes the ack + releases the held command.

import {
  AutonomousDisclosureBanner,
  AUTONOMOUS_DISCLOSURE_COPY,
} from "@/components/chat/autonomous-disclosure-banner";

// LOCKED COPY (plan §"LOCKED COPY") — assert the constant is verbatim.
const LOCKED =
  "Soleur runs commands automatically to get work done. It always blocks " +
  "clearly dangerous commands (curl, wget, sudo, …) and hides your secrets — " +
  "but no blocklist is perfect. A command that looks safe could still change " +
  "or delete files in this workspace. Your work is backed up in git, and you " +
  "can watch every command run in the chat. Only connect repos and accounts " +
  "you trust.";

describe("AutonomousDisclosureBanner", () => {
  beforeEach(() => vi.clearAllMocks());

  test("disclosure copy is the LOCKED paragraph verbatim", () => {
    expect(AUTONOMOUS_DISCLOSURE_COPY).toBe(LOCKED);
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
