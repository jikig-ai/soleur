/**
 * #11525 — a REFUSED response (the handler returns `false`: credential-blocked
 * chat or closed socket) must leave the card actionable AND say why. The review
 * gate used to stay on a permanent spinner (`pending` never cleared).
 */
import { describe, test, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

import { ReviewGateCard } from "@/components/chat/review-gate-card";
import { AutonomousDisclosureBanner } from "@/components/chat/autonomous-disclosure-banner";
import { InteractivePromptCard } from "@/components/chat/interactive-prompt-card";
import { REFUSED_SEND_MESSAGE } from "@/components/chat/refused-send-notice";

const gate = { gateId: "g1", question: "Ship it?", options: ["Approve", "Reject"] };

describe("ReviewGateCard — refused send", () => {
  test("click -> refused (false): options re-enabled, no 'Selected:', role=alert refusal line", async () => {
    const onSelect = vi.fn(() => false);
    render(<ReviewGateCard {...gate} onSelect={onSelect} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(onSelect).toHaveBeenCalledWith("g1", "Approve");
    expect(screen.getByRole("alert")).toHaveTextContent(REFUSED_SEND_MESSAGE);
    expect(screen.getByRole("button", { name: "Approve" })).not.toBeDisabled();
    expect(screen.getByRole("button", { name: "Reject" })).not.toBeDisabled();
    expect(screen.getByRole("group")).toHaveAttribute("aria-busy", "false");
    expect(screen.queryByText(/Selected:/)).toBeNull();
  });

  test("a second click after a refusal is accepted and clears the refusal line", async () => {
    const onSelect = vi.fn().mockReturnValueOnce(false).mockReturnValue(true);
    render(<ReviewGateCard {...gate} onSelect={onSelect} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(screen.getByRole("alert")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Reject" }));
    expect(onSelect).toHaveBeenCalledTimes(2);
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.getByRole("group")).toHaveAttribute("aria-busy", "true"); // pending, awaiting resolve
  });

  test("an accepted send (true / void) keeps the pending state and shows no refusal", async () => {
    render(<ReviewGateCard {...gate} onSelect={vi.fn(() => true)} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.getByRole("button", { name: "Reject" })).toBeDisabled();
  });
});

describe("AutonomousDisclosureBanner — refused send", () => {
  test("refused: role=alert line, button stays enabled; accepted retry clears it", async () => {
    const onRespond = vi.fn().mockReturnValueOnce(false).mockReturnValue(true);
    render(<AutonomousDisclosureBanner gateId="d1" existingWorkspace={false} onRespond={onRespond} />);
    await userEvent.click(screen.getByRole("button", { name: "Got it" }));
    expect(screen.getByRole("alert")).toHaveTextContent(REFUSED_SEND_MESSAGE);
    expect(screen.getByRole("button", { name: "Got it" })).not.toBeDisabled();
    await userEvent.click(screen.getByRole("button", { name: "Got it" }));
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("existing-workspace variant shows the same refusal line", async () => {
    render(<AutonomousDisclosureBanner gateId="d1" existingWorkspace onRespond={vi.fn(() => false)} />);
    await userEvent.click(screen.getByRole("button", { name: "Ask me each time" }));
    expect(screen.getByRole("alert")).toHaveTextContent(REFUSED_SEND_MESSAGE);
  });
});

describe("InteractivePromptCard — refused send", () => {
  const props = {
    promptId: "p1",
    conversationId: "c1",
    kind: "ask_user" as const,
    payload: { question: "Proceed?", options: ["Yes", "No"], multiSelect: false },
  };

  test("refused: role=alert line, options stay enabled; accepted retry clears it", async () => {
    const onRespond = vi.fn().mockReturnValueOnce(false).mockReturnValue(true);
    render(<InteractivePromptCard {...props} onRespond={onRespond} />);
    await userEvent.click(screen.getByRole("button", { name: "Yes" }));
    expect(onRespond).toHaveBeenCalledWith({ kind: "ask_user", response: "Yes" });
    expect(screen.getByRole("alert")).toHaveTextContent(REFUSED_SEND_MESSAGE);
    expect(screen.getByRole("button", { name: "Yes" })).not.toBeDisabled();
    await userEvent.click(screen.getByRole("button", { name: "No" }));
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("accepted (true) shows no refusal line", async () => {
    render(<InteractivePromptCard {...props} onRespond={vi.fn(() => true)} />);
    await userEvent.click(screen.getByRole("button", { name: "Yes" }));
    expect(screen.queryByRole("alert")).toBeNull();
  });
});
