/**
 * Stage 4 (#2886) — RED-first tests for `<InteractivePromptCard>`.
 *
 * One `describe` per `kind`. Per `cq-mutation-assertions-pin-exact-post-state`,
 * `.toBe()` for primitive response values and `.toEqual()` for arrays.
 *
 * No layout-engine assertions per `cq-jsdom-no-layout-gated-assertions` —
 * everything keys off `data-prompt-kind` and visible button text.
 */
import { describe, test, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { InteractivePromptCard } from "@/components/chat/interactive-prompt-card";
import type { InteractivePromptResponsePayload } from "@/lib/types";

describe("InteractivePromptCard ask_user", () => {
  test("renders question + options as buttons; click invokes onRespond with the choice", () => {
    const onRespond = vi.fn();
    const { container } = render(
      <InteractivePromptCard
        promptId="pr-1"
        conversationId="c-1"
        kind="ask_user"
        payload={{ question: "Pick one", options: ["alpha", "beta"], multiSelect: false }}
        onRespond={onRespond}
      />,
    );
    expect(container.querySelector('[data-prompt-kind="ask_user"]')).not.toBeNull();
    expect(screen.getByText("Pick one")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "alpha" }));
    expect(onRespond).toHaveBeenCalledTimes(1);
    const arg = onRespond.mock.calls[0][0] as InteractivePromptResponsePayload;
    expect(arg.kind).toBe("ask_user");
    if (arg.kind === "ask_user") {
      // Single-select returns string.
      expect(arg.response).toBe("alpha");
    }
  });

  test("multiSelect=true uses checkbox-pattern + Submit button; submits selected array", () => {
    const onRespond = vi.fn();
    render(
      <InteractivePromptCard
        promptId="pr-2"
        conversationId="c-1"
        kind="ask_user"
        payload={{ question: "Pick many", options: ["a", "b", "c"], multiSelect: true }}
        onRespond={onRespond}
      />,
    );
    fireEvent.click(screen.getByRole("checkbox", { name: "a" }));
    fireEvent.click(screen.getByRole("checkbox", { name: "c" }));
    fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    expect(onRespond).toHaveBeenCalledTimes(1);
    const arg = onRespond.mock.calls[0][0] as InteractivePromptResponsePayload;
    expect(arg.kind).toBe("ask_user");
    if (arg.kind === "ask_user") {
      expect(arg.response).toEqual(["a", "c"]);
    }
  });

  test("resolved=true disables buttons and shows selectedResponse", () => {
    const onRespond = vi.fn();
    const { container } = render(
      <InteractivePromptCard
        promptId="pr-3"
        conversationId="c-1"
        kind="ask_user"
        payload={{ question: "Pick", options: ["x", "y"], multiSelect: false }}
        onRespond={onRespond}
        resolved={true}
        selectedResponse="x"
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "x" }));
    expect(onRespond).not.toHaveBeenCalled();
    expect(container.textContent).toContain("x");
  });
});

describe("InteractivePromptCard ask_user multi-select rehydration (review F17 #2886)", () => {
  test("resolved=true with multiSelect=true checkboxes are pre-checked from selectedResponse", () => {
    const onRespond = vi.fn();
    const { container } = render(
      <InteractivePromptCard
        promptId="pr-rehydrate"
        conversationId="c-1"
        kind="ask_user"
        payload={{ question: "Pick", options: ["a", "b", "c"], multiSelect: true }}
        onRespond={onRespond}
        resolved={true}
        selectedResponse={["a", "c"]}
      />,
    );
    const a = container.querySelector('input[type="checkbox"][aria-label="a"]');
    const b = container.querySelector('input[type="checkbox"][aria-label="b"]');
    const c = container.querySelector('input[type="checkbox"][aria-label="c"]');
    expect((a as HTMLInputElement | null)?.checked).toBe(true);
    expect((b as HTMLInputElement | null)?.checked).toBe(false);
    expect((c as HTMLInputElement | null)?.checked).toBe(true);
  });
});

describe("InteractivePromptCard plan_preview", () => {
  test("Accept button calls onRespond with response='accept'", () => {
    const onRespond = vi.fn();
    render(
      <InteractivePromptCard
        promptId="pr-4"
        conversationId="c-1"
        kind="plan_preview"
        payload={{ markdown: "# Plan\nDo work" }}
        onRespond={onRespond}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /accept/i }));
    const arg = onRespond.mock.calls[0][0] as InteractivePromptResponsePayload;
    expect(arg.kind).toBe("plan_preview");
    if (arg.kind === "plan_preview") {
      expect(arg.response).toBe("accept");
    }
  });

  test("Iterate button calls onRespond with response='iterate'", () => {
    const onRespond = vi.fn();
    render(
      <InteractivePromptCard
        promptId="pr-5"
        conversationId="c-1"
        kind="plan_preview"
        payload={{ markdown: "Plan body" }}
        onRespond={onRespond}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /iterate/i }));
    const arg = onRespond.mock.calls[0][0] as InteractivePromptResponsePayload;
    if (arg.kind === "plan_preview") {
      expect(arg.response).toBe("iterate");
    }
  });
});

describe("InteractivePromptCard plan_preview resolved-state grammar (review F14 #2886)", () => {
  test.each([
    ["accept", /Plan accepted/],
    ["iterate", /Plan iterated/],
  ])("resolved=true with selectedResponse='%s' renders correctly", (sel, re) => {
    const { container } = render(
      <InteractivePromptCard
        promptId={`pr-grammar-${sel}`}
        conversationId="c-1"
        kind="plan_preview"
        payload={{ markdown: "Plan body" }}
        onRespond={() => {}}
        resolved={true}
        selectedResponse={sel as "accept" | "iterate"}
      />,
    );
    expect(container.textContent).toMatch(re);
    // Regression: must NOT produce double-e or trailing-d artifacts.
    expect(container.textContent).not.toMatch(/iterateed/);
    expect(container.textContent).not.toMatch(/acceptd/);
  });
});

describe("InteractivePromptCard bash_approval resolved-state grammar (review F14 #2886)", () => {
  test.each([
    ["approve", /approved/],
    ["deny", /denied/],
  ])("resolved=true with selectedResponse='%s' renders correctly", (sel, re) => {
    const { container } = render(
      <InteractivePromptCard
        promptId={`pr-bash-grammar-${sel}`}
        conversationId="c-1"
        kind="bash_approval"
        payload={{ command: "ls", cwd: "/", gated: true }}
        onRespond={() => {}}
        resolved={true}
        selectedResponse={sel as "approve" | "deny"}
      />,
    );
    expect(container.textContent).toMatch(re);
    // Regression: never "approved" + extra "d" / "denied" + extra "d".
    expect(container.textContent).not.toMatch(/approveded/);
    expect(container.textContent).not.toMatch(/deniedd/);
  });
});

describe("InteractivePromptCard diff", () => {
  test("renders summary with path/additions/deletions; Acknowledge → response='ack'", () => {
    const onRespond = vi.fn();
    const { container } = render(
      <InteractivePromptCard
        promptId="pr-6"
        conversationId="c-1"
        kind="diff"
        payload={{ path: "src/foo.ts", additions: 5, deletions: 2 }}
        onRespond={onRespond}
      />,
    );
    expect(container.textContent).toContain("src/foo.ts");
    expect(container.textContent).toContain("+5");
    expect(container.textContent).toContain("-2");
    fireEvent.click(screen.getByRole("button", { name: /acknowledge/i }));
    const arg = onRespond.mock.calls[0][0] as InteractivePromptResponsePayload;
    if (arg.kind === "diff") {
      expect(arg.response).toBe("ack");
    }
  });
});

describe("InteractivePromptCard bash_approval", () => {
  test("gated=true shows Approve/Deny buttons; renders command as escaped text", () => {
    const onRespond = vi.fn();
    const { container } = render(
      <InteractivePromptCard
        promptId="pr-7"
        conversationId="c-1"
        kind="bash_approval"
        payload={{ command: "<script>alert(1)</script>", cwd: "/x", gated: true }}
        onRespond={onRespond}
      />,
    );
    // Command renders as visible text, not as an executed tag.
    expect(container.querySelector("script")).toBeNull();
    expect(container.textContent).toContain("<script>alert(1)</script>");
    fireEvent.click(screen.getByRole("button", { name: /approve/i }));
    const arg = onRespond.mock.calls[0][0] as InteractivePromptResponsePayload;
    if (arg.kind === "bash_approval") {
      expect(arg.response).toBe("approve");
    }
  });

  test("gated=false renders auto-display only without buttons", () => {
    const onRespond = vi.fn();
    render(
      <InteractivePromptCard
        promptId="pr-8"
        conversationId="c-1"
        kind="bash_approval"
        payload={{ command: "ls", cwd: "/", gated: false }}
        onRespond={onRespond}
      />,
    );
    expect(screen.queryByRole("button", { name: /approve/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /deny/i })).toBeNull();
  });

  test("Deny button → response='deny'", () => {
    const onRespond = vi.fn();
    render(
      <InteractivePromptCard
        promptId="pr-9"
        conversationId="c-1"
        kind="bash_approval"
        payload={{ command: "rm -rf /", cwd: "/", gated: true }}
        onRespond={onRespond}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /deny/i }));
    const arg = onRespond.mock.calls[0][0] as InteractivePromptResponsePayload;
    if (arg.kind === "bash_approval") {
      expect(arg.response).toBe("deny");
    }
  });
});

describe("InteractivePromptCard todo_write", () => {
  test("renders count and item list; Acknowledge → response='ack'", () => {
    const onRespond = vi.fn();
    const { container } = render(
      <InteractivePromptCard
        promptId="pr-10"
        conversationId="c-1"
        kind="todo_write"
        payload={{
          items: [
            { id: "t1", content: "First", status: "pending" },
            { id: "t2", content: "Second", status: "in_progress" },
          ],
        }}
        onRespond={onRespond}
      />,
    );
    expect(container.textContent).toContain("2 todos");
    expect(container.textContent).toContain("First");
    fireEvent.click(screen.getByRole("button", { name: /acknowledge/i }));
    const arg = onRespond.mock.calls[0][0] as InteractivePromptResponsePayload;
    if (arg.kind === "todo_write") {
      expect(arg.response).toBe("ack");
    }
  });
});

describe("InteractivePromptCard notebook_edit", () => {
  test("renders count + cell ids + path; Acknowledge → response='ack'", () => {
    const onRespond = vi.fn();
    const { container } = render(
      <InteractivePromptCard
        promptId="pr-11"
        conversationId="c-1"
        kind="notebook_edit"
        payload={{ notebookPath: "n.ipynb", cellIds: ["c1", "c2", "c3"] }}
        onRespond={onRespond}
      />,
    );
    expect(container.textContent).toContain("3 cells");
    expect(container.textContent).toContain("n.ipynb");
    fireEvent.click(screen.getByRole("button", { name: /acknowledge/i }));
    const arg = onRespond.mock.calls[0][0] as InteractivePromptResponsePayload;
    if (arg.kind === "notebook_edit") {
      expect(arg.response).toBe("ack");
    }
  });
});
