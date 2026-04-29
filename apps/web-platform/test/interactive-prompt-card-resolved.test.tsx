/**
 * AC5 / TS6 (#3018 plan 2026-04-29) — RED tests for the compact resolved
 * render of `<InteractivePromptCard>`.
 *
 * Each of the 6 variants (`ask_user`, `plan_preview`, `diff`,
 * `bash_approval`, `todo_write`, `notebook_edit`) MUST collapse to a
 * single-row checkmark + verb summary when `resolved === true` AND
 * `selectedResponse !== undefined`. Mirror pattern: `ReviewGateCard:40-49`.
 *
 * The resolved row MUST preserve `data-prompt-kind` and `data-prompt-id`
 * so existing test seams (`cc-soleur-go-end-to-end-render.test.tsx`)
 * still locate the card.
 */
import { describe, test, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";

import { InteractivePromptCard } from "@/components/chat/interactive-prompt-card";
import type { TodoItem } from "@/lib/types";

describe("InteractivePromptCard — resolved compact row (AC5 / TS6)", () => {
  test("bash_approval / approve: one svg + 'Approved' + no buttons / pre / cwd", () => {
    const { container } = render(
      <InteractivePromptCard
        kind="bash_approval"
        promptId="p-bash-1"
        conversationId="c1"
        payload={{ command: "rm -rf /tmp/foo", cwd: "/ws", gated: true }}
        resolved={true}
        selectedResponse="approve"
        onRespond={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.queryByText(/cwd:/)).toBeNull();
    // No <pre> block carrying the full command.
    expect(container.querySelector("pre")).toBeNull();
    expect(screen.getByText(/Approved/)).toBeInTheDocument();
    // Exactly one inline checkmark svg.
    expect(container.querySelectorAll("svg")).toHaveLength(1);

    // data-prompt-kind / data-prompt-id seams preserved on the resolved row.
    const row = container.querySelector('[data-prompt-kind="bash_approval"]');
    expect(row).not.toBeNull();
    expect(row?.getAttribute("data-prompt-id")).toBe("p-bash-1");
  });

  test("bash_approval / deny: 'Denied' verb, no buttons", () => {
    const { container } = render(
      <InteractivePromptCard
        kind="bash_approval"
        promptId="p-bash-2"
        conversationId="c1"
        payload={{ command: "curl evil.example", cwd: "/ws", gated: true }}
        resolved={true}
        selectedResponse="deny"
        onRespond={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button")).toBeNull();
    expect(container.querySelector("pre")).toBeNull();
    expect(screen.queryByText(/cwd:/)).toBeNull();
    expect(screen.getByText(/Denied/)).toBeInTheDocument();
    expect(container.querySelectorAll("svg")).toHaveLength(1);
  });

  test("ask_user / single-select: chosen option appears, no buttons / chips", () => {
    const { container } = render(
      <InteractivePromptCard
        kind="ask_user"
        promptId="p-ask-1"
        conversationId="c1"
        payload={{ question: "Continue?", options: ["yes", "no"], multiSelect: false }}
        resolved={true}
        selectedResponse="yes"
        onRespond={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button")).toBeNull();
    // Question text is part of the interactive UI; should NOT appear on the
    // resolved row (the row carries only the chosen value).
    expect(screen.queryByText(/Continue\?/)).toBeNull();
    expect(screen.getByText(/yes/)).toBeInTheDocument();
    expect(container.querySelectorAll("svg")).toHaveLength(1);

    const row = container.querySelector('[data-prompt-kind="ask_user"]');
    expect(row).not.toBeNull();
    expect(row?.getAttribute("data-prompt-id")).toBe("p-ask-1");
  });

  test("ask_user / multi-select: joined selections appear, no checkboxes", () => {
    const { container } = render(
      <InteractivePromptCard
        kind="ask_user"
        promptId="p-ask-2"
        conversationId="c1"
        payload={{
          question: "Pick all",
          options: ["a", "b", "c"],
          multiSelect: true,
        }}
        resolved={true}
        selectedResponse={["a", "c"]}
        onRespond={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button")).toBeNull();
    expect(container.querySelectorAll("input[type=checkbox]")).toHaveLength(0);
    // Chosen values appear (joined); the question itself is gone.
    expect(screen.queryByText(/Pick all/)).toBeNull();
    expect(screen.getByText(/a, c/)).toBeInTheDocument();
    expect(container.querySelectorAll("svg")).toHaveLength(1);
  });

  test("plan_preview / accept: 'Accepted' verb, no buttons / pre", () => {
    const { container } = render(
      <InteractivePromptCard
        kind="plan_preview"
        promptId="p-plan-1"
        conversationId="c1"
        payload={{ markdown: "# Plan\n\nDo the thing." }}
        resolved={true}
        selectedResponse="accept"
        onRespond={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button")).toBeNull();
    expect(container.querySelector("pre")).toBeNull();
    expect(screen.getByText(/Accepted/)).toBeInTheDocument();
    expect(container.querySelectorAll("svg")).toHaveLength(1);
  });

  test("plan_preview / iterate: 'Iterated' verb, no buttons / pre", () => {
    const { container } = render(
      <InteractivePromptCard
        kind="plan_preview"
        promptId="p-plan-2"
        conversationId="c1"
        payload={{ markdown: "# Plan" }}
        resolved={true}
        selectedResponse="iterate"
        onRespond={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button")).toBeNull();
    expect(container.querySelector("pre")).toBeNull();
    expect(screen.getByText(/Iterated/)).toBeInTheDocument();
    expect(container.querySelectorAll("svg")).toHaveLength(1);
  });

  test("diff / ack: 'Acknowledged' verb, no buttons", () => {
    const { container } = render(
      <InteractivePromptCard
        kind="diff"
        promptId="p-diff-1"
        conversationId="c1"
        payload={{ path: "src/foo.ts", additions: 3, deletions: 1 }}
        resolved={true}
        selectedResponse="ack"
        onRespond={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.getByText(/Acknowledged/)).toBeInTheDocument();
    expect(container.querySelectorAll("svg")).toHaveLength(1);

    const row = container.querySelector('[data-prompt-kind="diff"]');
    expect(row).not.toBeNull();
    expect(row?.getAttribute("data-prompt-id")).toBe("p-diff-1");
  });

  test("todo_write / ack: 'Acknowledged' verb, no buttons / list", () => {
    const items: TodoItem[] = [
      { id: "1", content: "first", status: "pending" },
      { id: "2", content: "second", status: "in_progress" },
    ];
    const { container } = render(
      <InteractivePromptCard
        kind="todo_write"
        promptId="p-todo-1"
        conversationId="c1"
        payload={{ items }}
        resolved={true}
        selectedResponse="ack"
        onRespond={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button")).toBeNull();
    expect(container.querySelectorAll("ul")).toHaveLength(0);
    expect(screen.getByText(/Acknowledged/)).toBeInTheDocument();
    expect(container.querySelectorAll("svg")).toHaveLength(1);
  });

  test("notebook_edit / ack: 'Acknowledged' verb, no buttons / cell chips", () => {
    const { container } = render(
      <InteractivePromptCard
        kind="notebook_edit"
        promptId="p-nb-1"
        conversationId="c1"
        payload={{ notebookPath: "nb.ipynb", cellIds: ["c1", "c2"] }}
        resolved={true}
        selectedResponse="ack"
        onRespond={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button")).toBeNull();
    // The interactive variant renders cell-id chips as <span> pills; the
    // resolved row carries only the verb, so they should be gone.
    expect(screen.queryByText(/^c1$/)).toBeNull();
    expect(screen.queryByText(/^c2$/)).toBeNull();
    expect(screen.getByText(/Acknowledged/)).toBeInTheDocument();
    expect(container.querySelectorAll("svg")).toHaveLength(1);

    const row = container.querySelector('[data-prompt-kind="notebook_edit"]');
    expect(row).not.toBeNull();
    expect(row?.getAttribute("data-prompt-id")).toBe("p-nb-1");
  });
});
