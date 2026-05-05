// DO NOT add `vi.useFakeTimers()` to this file. See sibling
// `chat-input-attachments.test.tsx` for the rationale (testing-library
// hangs with fake timers + user-event v14).
//
// #3254 — paste guard for `[Image #N]` SDK-CLI placeholders. When the
// user pastes text that contains the markers (e.g., from another
// claude-code session, a Warp terminal block, or any source where image
// bytes were already flattened to text), the textarea must reject the
// paste and surface an `attachError` toast. The actual image bytes
// never reached the clipboard, so accepting the text would persist a
// known-broken artifact and trigger a hallucinated response.
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { ChatInput } from "@/components/chat/chat-input";

vi.stubGlobal("fetch", vi.fn());

describe("ChatInput — paste guard for [Image #N] placeholders (#3254)", () => {
  const defaultProps = {
    onSend: vi.fn(),
    onAtTrigger: vi.fn(),
    onAtDismiss: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  function setup(overrides = {}) {
    const props = { ...defaultProps, ...overrides };
    return render(<ChatInput {...props} />);
  }

  function pasteText(text: string) {
    const textarea = screen.getByRole("textbox") as HTMLTextAreaElement;
    fireEvent.paste(textarea, {
      clipboardData: {
        files: [],
        getData: (mime: string) => (mime === "text/plain" ? text : ""),
      },
    });
    return textarea;
  }

  it("rejects pasted text containing a single [Image #1] marker — textarea unchanged + toast renders", async () => {
    setup();
    const textarea = pasteText("see [Image #1]");

    expect(textarea.value).toBe("");

    await waitFor(() => {
      expect(screen.getByText(/image placeholder/i)).toBeInTheDocument();
    });
  });

  it("counts multiple placeholders in the toast copy (plural)", async () => {
    setup();
    pasteText("[Image #1] [Image #2] [Image #3]");

    await waitFor(() => {
      expect(screen.getByText(/3 image placeholders/i)).toBeInTheDocument();
    });
  });

  it("uses singular wording for a single placeholder", async () => {
    setup();
    pasteText("[Image #1]");

    await waitFor(() => {
      // "1 image placeholder" (singular) — no trailing 's'
      expect(screen.getByText(/1 image placeholder\b/i)).toBeInTheDocument();
    });
  });

  it("ALLOWS pasted text without placeholders to flow through normally", async () => {
    setup();
    const textarea = screen.getByRole("textbox") as HTMLTextAreaElement;

    // No `e.preventDefault()` should be called — textarea accepts the paste.
    fireEvent.paste(textarea, {
      clipboardData: {
        files: [],
        getData: (mime: string) =>
          mime === "text/plain" ? "what is this code doing?" : "",
      },
    });

    // No error toast should render.
    expect(screen.queryByText(/image placeholder/i)).not.toBeInTheDocument();
  });

  it("ALLOWS lowercase [image #1] (not the SDK marker — fixed-case only)", async () => {
    setup();
    pasteText("see [image #1]");

    expect(screen.queryByText(/image placeholder/i)).not.toBeInTheDocument();
  });
});
