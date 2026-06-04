/**
 * AC5 (render) — the cc_router bubble renders the appended `commandBlocks`
 * as an inline monospace terminal block (no Approve/Deny buttons), with a
 * render-time redaction pass as the final belt-and-suspenders gate.
 */
import { describe, test, expect, vi } from "vitest";
import { render } from "@testing-library/react";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { MessageBubble } from "../components/chat/message-bubble";
import type { CommandBlock } from "../lib/chat-state-machine";

const GHS = "ghs_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5";

describe("MessageBubble command_stream terminal block (AC5 render)", () => {
  test("renders command + output as a monospace block", () => {
    const blocks: CommandBlock[] = [
      { command: "git status", output: "On branch main\nnothing to commit\n" },
    ];
    const { getByTestId, container } = render(
      <MessageBubble
        role="assistant"
        content="Running a command…"
        leaderId="cc_router"
        messageState="streaming"
        commandBlocks={blocks}
      />,
    );
    const wrap = getByTestId("command-stream-blocks");
    expect(wrap).toBeTruthy();
    const block = getByTestId("command-stream-block");
    expect(block.tagName.toLowerCase()).toBe("pre");
    expect(block.textContent).toContain("git status");
    expect(block.textContent).toContain("On branch main");
    // The prose content coexists with the terminal block.
    expect(container.textContent).toContain("Running a command…");
  });

  test("renders no terminal block when commandBlocks is empty/undefined", () => {
    const { queryByTestId } = render(
      <MessageBubble
        role="assistant"
        content="hello"
        leaderId="cc_router"
        messageState="done"
      />,
    );
    expect(queryByTestId("command-stream-blocks")).toBeNull();
  });

  test("renders multiple blocks in order", () => {
    const blocks: CommandBlock[] = [
      { command: "ls", output: "a.txt\n" },
      { command: "pwd", output: "/tmp\n" },
    ];
    const { getAllByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        leaderId="cc_router"
        messageState="streaming"
        commandBlocks={blocks}
      />,
    );
    const rendered = getAllByTestId("command-stream-block");
    expect(rendered).toHaveLength(2);
    expect(rendered[0].textContent).toContain("ls");
    expect(rendered[1].textContent).toContain("pwd");
  });

  test("render-time redaction gate strips a secret that survived into a persisted block", () => {
    // Simulate a replayed/persisted block that predates a redaction-rule fix:
    // the command STILL contains a raw token. Render must redact it.
    const blocks: CommandBlock[] = [
      { command: `git clone https://x-access-token:${GHS}@github.com/o/r`, output: "" },
    ];
    const { getByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        leaderId="cc_router"
        messageState="streaming"
        commandBlocks={blocks}
      />,
    );
    const block = getByTestId("command-stream-block");
    expect(block.textContent).not.toContain(GHS);
    expect(block.textContent).toContain("[redacted-key]");
  });

  test("has NO Approve/Deny buttons (executes inline, not a gate)", () => {
    const blocks: CommandBlock[] = [{ command: "echo hi", output: "hi\n" }];
    const { container } = render(
      <MessageBubble
        role="assistant"
        content=""
        leaderId="cc_router"
        messageState="streaming"
        commandBlocks={blocks}
      />,
    );
    expect(container.querySelectorAll("button")).toHaveLength(0);
  });

  test("renders the truncation marker carried in output", () => {
    const blocks: CommandBlock[] = [
      { command: "cat big", output: "first bytes\n[… truncated]", truncated: true },
    ];
    const { getByTestId } = render(
      <MessageBubble
        role="assistant"
        content=""
        leaderId="cc_router"
        messageState="streaming"
        commandBlocks={blocks}
      />,
    );
    expect(getByTestId("command-stream-block").textContent).toContain("[… truncated]");
  });
});
