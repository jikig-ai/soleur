import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

// feat-bash-autonomous-default-on — first-run consent soft-gate banner. Renders
// the LOCKED disclosure copy verbatim; "Got it" / opt-out buttons call the
// respond handler which writes the ack + releases the held command.

import {
  AutonomousDisclosureBanner,
  AUTONOMOUS_DISCLOSURE_COPY,
} from "@/components/chat/autonomous-disclosure-banner";

// LOCKED COPY (re-locked 2026-10-10, #9776 ask-gate; CLO ruling section 1) — assert the constant is verbatim.
const LOCKED =
  "Soleur runs commands automatically. It blocks a short list of risky " +
  "commands (curl, wget, sudo, …), but no blocklist is perfect. It also " +
  "pauses to ask before common forms of a force-push over, or deletion of, " +
  "your repository's default branch (which can erase its history on " +
  "GitHub), and before terraform destroy. It does not recognise every way " +
  "of writing those commands, or every other way to delete a repository or " +
  "tear down infrastructure, so such a command can still run without " +
  "asking. Other commands that look safe could still change or delete " +
  "files in this workspace. You can watch each step in the chat. Only " +
  "connect repos and accounts you trust.";

// CLO C3: the sentences that describe the lane never claim more than "pauses to ask".
const BANNED_FOR_THE_LANE = /\b(blocks|prevents?|protects?|safe to approve|guaranteed?|always)\b/i;
export function laneSentences(text: string): string[] {
  return text.split(/(?<=[.])\s+/).filter((x) => /pauses? to ask|pauses do not|does not recognise every way/i.test(x));
}

describe("AutonomousDisclosureBanner", () => {
  beforeEach(() => vi.clearAllMocks());

  test("disclosure copy is the LOCKED paragraph verbatim", () => {
    expect(AUTONOMOUS_DISCLOSURE_COPY).toBe(LOCKED);
  });

  test("copy no longer carries the removed claims and keeps the locked sentences (CLO section 1)", () => {
    for (const gone of [/hides your secrets/i, /always blocks/i, /backed up in git/i, /Until a stricter check ships/i]) {
      expect(AUTONOMOUS_DISCLOSURE_COPY).not.toMatch(gone);
    }
    for (const kept of [
      /no blocklist is perfect/,
      /does not recognise every way/,
      /pauses to ask/,
      /Other commands that look safe could still change or delete files in this workspace\./,
      /You can watch each step in the chat\./,
      /Only connect repos and accounts you trust\./,
      // The new text legitimately carries these tokens: the test must NOT assert their absence.
      /force-push/,
      /terraform destroy/,
      /without asking/,
    ]) {
      expect(AUTONOMOUS_DISCLOSURE_COPY).toMatch(kept);
    }
  });

  test("vocabulary guard (CLO C3): the lane sentences never say blocks, prevents, protects, safe to approve, guaranteed or always", () => {
    const sentences = laneSentences(AUTONOMOUS_DISCLOSURE_COPY);
    expect(sentences.length).toBeGreaterThanOrEqual(2); // the scan covered real sentences, not an empty list
    for (const sentence of sentences) expect(sentence).not.toMatch(BANNED_FOR_THE_LANE);
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
