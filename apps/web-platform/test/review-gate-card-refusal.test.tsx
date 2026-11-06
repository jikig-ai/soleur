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
import { REFUSED_SEND_MESSAGE, credentialRefusedMessage } from "@/components/chat/refused-send-notice";

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

  test("an accepted send (true) keeps the pending state and shows no refusal", async () => {
    render(<ReviewGateCard {...gate} onSelect={vi.fn(() => true)} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.getByRole("button", { name: "Reject" })).toBeDisabled();
  });

  test("a void return is an accepted send, NOT a refusal (only an explicit false refuses)", async () => {
    render(<ReviewGateCard {...gate} onSelect={vi.fn(() => undefined)} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(screen.queryByRole("alert")).toBeNull();
    expect(screen.getByRole("button", { name: "Reject" })).toBeDisabled();
  });

  test("credential-blocked refusal tells the user to fix the key and re-send, not 'choose again'", async () => {
    render(<ReviewGateCard {...gate} refusal={{ reason: "credential", noun: "token" }} onSelect={vi.fn(() => false)} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(screen.getByRole("alert")).toHaveTextContent(credentialRefusedMessage("token"));
    expect(screen.getByRole("alert")).not.toHaveTextContent("choose again");
  });

  test("a second refusal re-announces: the alert node is REMOUNTED", async () => {
    render(<ReviewGateCard {...gate} onSelect={vi.fn(() => false)} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    const first = screen.getByRole("alert");
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    const second = screen.getByRole("alert");
    expect(second).not.toBe(first);
    expect(first.isConnected).toBe(false);
  });

  test("the refusal line clears when the reset signal changes", async () => {
    const onSelect = vi.fn(() => false);
    const { rerender } = render(<ReviewGateCard {...gate} resetKey={0} onSelect={onSelect} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(screen.getByRole("alert")).toBeInTheDocument();
    rerender(<ReviewGateCard {...gate} resetKey={1} onSelect={onSelect} />);
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("not shown once resolved", async () => {
    const onSelect = vi.fn(() => false);
    const { rerender } = render(<ReviewGateCard {...gate} onSelect={onSelect} />);
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(screen.getByRole("alert")).toBeInTheDocument();
    rerender(<ReviewGateCard {...gate} resolved onSelect={onSelect} />);
    expect(screen.queryByRole("alert")).toBeNull();
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

  test("a void return is an accepted response, NOT a refusal", async () => {
    render(<AutonomousDisclosureBanner gateId="d1" existingWorkspace={false} onRespond={vi.fn(() => undefined)} />);
    await userEvent.click(screen.getByRole("button", { name: "Got it" }));
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("credential-blocked refusal tells the user to fix the key and re-send", async () => {
    render(
      <AutonomousDisclosureBanner
        gateId="d1"
        existingWorkspace={false}
        refusal={{ reason: "credential", noun: "key" }}
        onRespond={vi.fn(() => false)}
      />,
    );
    await userEvent.click(screen.getByRole("button", { name: "Got it" }));
    expect(screen.getByRole("alert")).toHaveTextContent(credentialRefusedMessage("key"));
  });

  test("a second refusal re-announces: the alert node is REMOUNTED", async () => {
    render(<AutonomousDisclosureBanner gateId="d1" existingWorkspace={false} onRespond={vi.fn(() => false)} />);
    await userEvent.click(screen.getByRole("button", { name: "Got it" }));
    const first = screen.getByRole("alert");
    await userEvent.click(screen.getByRole("button", { name: "Got it" }));
    expect(screen.getByRole("alert")).not.toBe(first);
    expect(first.isConnected).toBe(false);
  });

  test("the refusal line clears when the reset signal changes", async () => {
    const onRespond = vi.fn(() => false);
    const { rerender } = render(<AutonomousDisclosureBanner gateId="d1" existingWorkspace={false} resetKey={0} onRespond={onRespond} />);
    await userEvent.click(screen.getByRole("button", { name: "Got it" }));
    expect(screen.getByRole("alert")).toBeInTheDocument();
    rerender(<AutonomousDisclosureBanner gateId="d1" existingWorkspace={false} resetKey={1} onRespond={onRespond} />);
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("not shown once resolved", async () => {
    const onRespond = vi.fn(() => false);
    const { rerender } = render(<AutonomousDisclosureBanner gateId="d1" existingWorkspace={false} onRespond={onRespond} />);
    await userEvent.click(screen.getByRole("button", { name: "Got it" }));
    rerender(<AutonomousDisclosureBanner gateId="d1" existingWorkspace={false} resolved onRespond={onRespond} />);
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

  test("a void return is an accepted response, NOT a refusal", async () => {
    render(<InteractivePromptCard {...props} onRespond={vi.fn(() => undefined)} />);
    await userEvent.click(screen.getByRole("button", { name: "Yes" }));
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("credential-blocked refusal tells the user to fix the token and re-send", async () => {
    render(
      <InteractivePromptCard
        {...props}
        refusal={{ reason: "credential", noun: "token" }}
        onRespond={vi.fn(() => false)}
      />,
    );
    await userEvent.click(screen.getByRole("button", { name: "Yes" }));
    expect(screen.getByRole("alert")).toHaveTextContent(credentialRefusedMessage("token"));
  });

  test("the refusal line renders INSIDE the card subtree ([data-prompt-id])", async () => {
    const { container } = render(<InteractivePromptCard {...props} onRespond={vi.fn(() => false)} />);
    await userEvent.click(screen.getByRole("button", { name: "Yes" }));
    const shell = container.querySelector("[data-prompt-id]");
    expect(shell).not.toBeNull();
    expect(shell!.contains(screen.getByRole("alert"))).toBe(true);
  });

  test("a second refusal re-announces: the alert node is REMOUNTED", async () => {
    render(<InteractivePromptCard {...props} onRespond={vi.fn(() => false)} />);
    await userEvent.click(screen.getByRole("button", { name: "Yes" }));
    const first = screen.getByRole("alert");
    await userEvent.click(screen.getByRole("button", { name: "Yes" }));
    expect(screen.getByRole("alert")).not.toBe(first);
    expect(first.isConnected).toBe(false);
  });

  test("the refusal line clears when the reset signal changes", async () => {
    const onRespond = vi.fn(() => false);
    const { rerender } = render(<InteractivePromptCard {...props} resetKey={0} onRespond={onRespond} />);
    await userEvent.click(screen.getByRole("button", { name: "Yes" }));
    expect(screen.getByRole("alert")).toBeInTheDocument();
    rerender(<InteractivePromptCard {...props} resetKey={1} onRespond={onRespond} />);
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("not shown once resolved", async () => {
    const onRespond = vi.fn(() => false);
    const { rerender } = render(<InteractivePromptCard {...props} onRespond={onRespond} />);
    await userEvent.click(screen.getByRole("button", { name: "Yes" }));
    rerender(<InteractivePromptCard {...props} resolved selectedResponse="Yes" onRespond={onRespond} />);
    expect(screen.queryByRole("alert")).toBeNull();
  });
});
