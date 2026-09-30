// DO NOT add `vi.useFakeTimers()` to this file. The XHR progress mocks use
// manual triggers (see `fireProgress50` / `fireProgress100` / `completeUpload`
// in the "send with attachments" describe block). Mixing fake timers with
// `@testing-library/user-event` v14 hangs `await user.type/keyboard` calls —
// see testing-library/user-event#833 and react-testing-library#1197/#1198.
//
// Trigger-function ordering invariant: each `let fireXxx: () => void` is
// assigned inside `mockXhr.send.mockImplementation(...)`, which runs
// synchronously when `uploadWithProgress` calls `xhr.send(file)`. By the
// time `await userEvent.keyboard("{Enter}")` resolves, every trigger is
// populated. The non-null `!` assertion at each call site encodes that
// invariant; a future edit that moves the trigger before the keyboard
// event will produce a clear `TypeError` rather than a silent hang.
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ChatInput } from "@/components/chat/chat-input";

// Mock fetch for presign API calls
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

const GENERIC_COPY = "Upload failed. Check your connection and try again.";
const UNAVAILABLE_COPY = "Attachments are available once the conversation starts.";
const REAL_ID = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d";

describe("ChatInput — attachments", () => {
  const defaultProps = {
    onSend: vi.fn(),
    onAtTrigger: vi.fn(),
    onAtDismiss: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
    mockFetch.mockReset();
  });

  function setup(overrides = {}) {
    const props = { ...defaultProps, ...overrides };
    return render(<ChatInput {...props} />);
  }

  describe("paperclip button", () => {
    it("renders a paperclip/attach button", () => {
      setup();
      expect(screen.getByLabelText(/attach/i)).toBeInTheDocument();
    });

    it("clicking paperclip opens file input", async () => {
      setup();
      const attachBtn = screen.getByLabelText(/attach/i);
      await userEvent.click(attachBtn);
      // The hidden file input should exist
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      expect(fileInput).not.toBeNull();
    });
  });

  describe("client-side validation", () => {
    it("rejects files larger than 20 MB", async () => {
      setup();
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;

      const bigFile = new File(["x"], "huge.png", { type: "image/png" });
      Object.defineProperty(bigFile, "size", { value: 21 * 1024 * 1024 });

      fireEvent.change(fileInput, { target: { files: [bigFile] } });

      // Should not appear in preview strip
      await waitFor(() => {
        expect(screen.queryAllByTestId("attachment-preview")).toHaveLength(0);
      });
    });

    it("rejects unsupported file types", async () => {
      setup();
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;

      const exeFile = new File(["x"], "virus.exe", { type: "application/x-msdownload" });

      fireEvent.change(fileInput, { target: { files: [exeFile] } });

      // Should not appear in preview strip
      await waitFor(() => {
        expect(screen.queryAllByTestId("attachment-preview")).toHaveLength(0);
      });
    });

    it("rejects more than 5 files", async () => {
      setup();
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;

      const files = Array.from({ length: 6 }, (_, i) =>
        new File(["x"], `file${i}.png`, { type: "image/png" }),
      );

      fireEvent.change(fileInput, { target: { files } });

      // At most 5 should appear in the preview
      await waitFor(() => {
        const previews = screen.queryAllByTestId("attachment-preview");
        expect(previews.length).toBeLessThanOrEqual(5);
      });
    });
  });

  describe("attachment preview strip", () => {
    it("shows preview for valid attached files", async () => {
      setup();
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;

      const pngFile = new File(["x"], "screenshot.png", { type: "image/png" });

      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText(/screenshot\.png/)).toBeInTheDocument();
      });
    });

    it("remove button removes an attachment from preview", async () => {
      setup();
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;

      const pngFile = new File(["x"], "screenshot.png", { type: "image/png" });
      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText(/screenshot\.png/)).toBeInTheDocument();
      });

      const removeBtn = screen.getByLabelText(/remove screenshot\.png/i);
      await userEvent.click(removeBtn);

      expect(screen.queryByText(/screenshot\.png/)).not.toBeInTheDocument();
    });
  });

  describe("send with attachments", () => {
    let mockXhr: {
      open: ReturnType<typeof vi.fn>;
      setRequestHeader: ReturnType<typeof vi.fn>;
      send: ReturnType<typeof vi.fn>;
      abort: ReturnType<typeof vi.fn>;
      upload: { onprogress: ((e: Partial<ProgressEvent>) => void) | null };
      onload: (() => void) | null;
      onerror: (() => void) | null;
      onabort: (() => void) | null;
      status: number;
    };

    beforeEach(() => {
      mockXhr = {
        open: vi.fn(),
        setRequestHeader: vi.fn(),
        send: vi.fn(),
        abort: vi.fn(),
        upload: { onprogress: null },
        onload: null,
        onerror: null,
        onabort: null,
        status: 200,
      };
      // vitest 4: a mock invoked with `new` constructs an instance. Returning
      // an object from a `function`-keyword constructor makes that object the
      // instance, so the component's `new XMLHttpRequest()` yields `mockXhr`
      // and the per-test `mockXhr.send.mockImplementation(...)` triggers fire.
      vi.stubGlobal(
        "XMLHttpRequest",
        vi.fn(function () {
          return mockXhr;
        }),
      );
    });

    it("calls onSend with attachments after successful upload", async () => {
      const onSend = vi.fn();
      setup({ onSend });

      // Mock successful presign
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          uploadUrl: "https://storage.supabase.co/upload/signed/abc",
          storagePath: "user-1/conv-1/uuid.png",
        }),
      });

      // Manual trigger pattern — see top-of-file note.
      let completeUpload: () => void;
      mockXhr.send.mockImplementation(() => {
        completeUpload = () => mockXhr.onload?.();
      });

      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const pngFile = new File(["x"], "test.png", { type: "image/png" });
      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText(/test\.png/)).toBeInTheDocument();
      });

      // Type a message and send
      const textarea = screen.getByRole("textbox");
      await userEvent.type(textarea, "Check this out");
      await userEvent.keyboard("{Enter}");

      // Manually complete the upload so handleSubmit resolves deterministically.
      completeUpload!();

      await waitFor(() => {
        expect(onSend).toHaveBeenCalledWith(
          "Check this out",
          expect.arrayContaining([
            expect.objectContaining({
              storagePath: "user-1/conv-1/uuid.png",
              filename: "test.png",
              contentType: "image/png",
            }),
          ]),
        );
      });
    });

    it("shows incremental progress during XHR upload", async () => {
      setup();

      // Mock successful presign
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          uploadUrl: "https://storage.supabase.co/upload/signed/abc",
          storagePath: "user-1/conv-1/uuid.png",
        }),
      });

      // Manual trigger pattern: explicitly fire each progress event between
      // assertions so React commits the intermediate `att.progress = 50` state
      // before progress jumps to 100. The previous real-clock 0/10/20-ms triple
      // raced React's batching on slow CI workers (#2524, #2470).
      let fireProgress50: () => void;
      let fireProgress100: () => void;
      let completeUpload: () => void;
      mockXhr.send.mockImplementation(() => {
        fireProgress50 = () => mockXhr.upload.onprogress?.({ lengthComputable: true, loaded: 50, total: 100 });
        fireProgress100 = () => mockXhr.upload.onprogress?.({ lengthComputable: true, loaded: 100, total: 100 });
        completeUpload = () => mockXhr.onload?.();
      });

      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const pngFile = new File(["x"], "test.png", { type: "image/png" });
      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText(/test\.png/)).toBeInTheDocument();
      });

      // Send to trigger upload
      const textarea = screen.getByRole("textbox");
      await userEvent.type(textarea, "hi");
      await userEvent.keyboard("{Enter}");

      fireProgress50!();
      await waitFor(() => {
        expect(screen.getByText("50%")).toBeInTheDocument();
      });

      // Negative-space assertion: pins the #2524 regression class. If React
      // ever batched both progress events into a single commit (the original
      // bug), the test would have still passed when "50%" briefly appeared
      // and was immediately replaced by "Uploaded". Asserting "Uploaded" is
      // NOT yet visible at this checkpoint forces the intermediate render.
      expect(screen.queryByText("Uploaded")).not.toBeInTheDocument();

      fireProgress100!();
      await waitFor(() => {
        expect(screen.getByText("Uploaded")).toBeInTheDocument();
      });

      completeUpload!();
    });

    it("shows 'Uploaded' text when progress reaches 100%", async () => {
      setup();

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          uploadUrl: "https://storage.supabase.co/upload/signed/abc",
          storagePath: "user-1/conv-1/uuid.png",
        }),
      });

      // Manual triggers: fire progress=100 explicitly so React commits the
      // "Uploaded" intermediate state before handleSubmit resolves.
      let fireProgress100: () => void;
      let completeUpload: () => void;
      mockXhr.send.mockImplementation(() => {
        fireProgress100 = () => mockXhr.upload.onprogress?.({ lengthComputable: true, loaded: 100, total: 100 });
        completeUpload = () => mockXhr.onload?.();
      });

      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const pngFile = new File(["x"], "test.png", { type: "image/png" });
      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText(/test\.png/)).toBeInTheDocument();
      });

      const textarea = screen.getByRole("textbox");
      await userEvent.type(textarea, "hi");
      await userEvent.keyboard("{Enter}");

      fireProgress100!();

      // Wait for progress to reach 100% (renders "Uploaded" text)
      await waitFor(() => {
        expect(screen.getByText("Uploaded")).toBeInTheDocument();
      });

      // Now complete the upload to let handleSubmit finish
      completeUpload!();
    });

    it("shows error state on XHR upload failure", async () => {
      setup();

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          uploadUrl: "https://storage.supabase.co/upload/signed/abc",
          storagePath: "user-1/conv-1/uuid.png",
        }),
      });

      let fireNetworkError: () => void;
      mockXhr.send.mockImplementation(() => {
        fireNetworkError = () => mockXhr.onerror?.();
      });

      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const pngFile = new File(["x"], "test.png", { type: "image/png" });
      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText(/test\.png/)).toBeInTheDocument();
      });

      const textarea = screen.getByRole("textbox");
      await userEvent.type(textarea, "hi");
      await userEvent.keyboard("{Enter}");

      fireNetworkError!();

      await waitFor(() => {
        expect(screen.getByText(GENERIC_COPY)).toBeInTheDocument();
      });
      expect(screen.getByTestId("attachment-preview")).not.toHaveTextContent(/upload to storage failed/i);
    });

    it("aborts XHR when attachment is removed during upload", async () => {
      setup();

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          uploadUrl: "https://storage.supabase.co/upload/signed/abc",
          storagePath: "user-1/conv-1/uuid.png",
        }),
      });

      // XHR send starts but never completes (simulates in-flight upload).
      let fireProgress25: () => void;
      mockXhr.send.mockImplementation(() => {
        fireProgress25 = () => mockXhr.upload.onprogress?.({ lengthComputable: true, loaded: 25, total: 100 });
      });

      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const pngFile = new File(["x"], "test.png", { type: "image/png" });
      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText(/test\.png/)).toBeInTheDocument();
      });

      // Send to trigger upload
      const textarea = screen.getByRole("textbox");
      await userEvent.type(textarea, "hi");
      await userEvent.keyboard("{Enter}");

      fireProgress25!();

      // Wait for progress to appear (upload in flight)
      await waitFor(() => {
        expect(screen.getByText("25%")).toBeInTheDocument();
      });

      // Remove the attachment during upload
      const removeBtn = screen.getByLabelText(/remove test\.png/i);
      await userEvent.click(removeBtn);

      // XHR.abort() should have been called
      expect(mockXhr.abort).toHaveBeenCalled();
    });

    it("shows error on non-2xx XHR status (e.g., 403 expired presign)", async () => {
      setup();

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          uploadUrl: "https://storage.supabase.co/upload/signed/abc",
          storagePath: "user-1/conv-1/uuid.png",
        }),
      });

      mockXhr.status = 403;
      let completeUpload: () => void;
      mockXhr.send.mockImplementation(() => {
        completeUpload = () => mockXhr.onload?.();
      });

      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const pngFile = new File(["x"], "test.png", { type: "image/png" });
      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText(/test\.png/)).toBeInTheDocument();
      });

      const textarea = screen.getByRole("textbox");
      await userEvent.type(textarea, "hi");
      await userEvent.keyboard("{Enter}");

      completeUpload!();

      await waitFor(() => {
        expect(screen.getByText(GENERIC_COPY)).toBeInTheDocument();
      });
      expect(screen.getByTestId("attachment-preview")).not.toHaveTextContent(/upload to storage failed/i);
    });

    it("preserves errored attachments after send while clearing successful ones", async () => {
      setup();

      // First file: presign succeeds, XHR fails
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          uploadUrl: "https://storage.supabase.co/upload/signed/abc",
          storagePath: "user-1/conv-1/uuid.png",
        }),
      });

      let fireNetworkError: () => void;
      mockXhr.send.mockImplementation(() => {
        fireNetworkError = () => mockXhr.onerror?.();
      });

      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const pngFile = new File(["x"], "fail.png", { type: "image/png" });
      fireEvent.change(fileInput, { target: { files: [pngFile] } });

      await waitFor(() => {
        expect(screen.getByText(/fail\.png/)).toBeInTheDocument();
      });

      const textarea = screen.getByRole("textbox");
      await userEvent.type(textarea, "hi");
      await userEvent.keyboard("{Enter}");

      fireNetworkError!();

      // Errored attachment should persist with error message
      await waitFor(() => {
        expect(screen.getByText(GENERIC_COPY)).toBeInTheDocument();
        expect(screen.getByText(/fail\.png/)).toBeInTheDocument();
      });
      expect(screen.getByTestId("attachment-preview")).not.toHaveTextContent(/upload to storage failed/i);
    });
  });
  describe("markdown / plain-text attachments", () => {
    function stageFile(f: File) {
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      fireEvent.change(fileInput, { target: { files: [f] } });
    }

    it("stages a .md the browser reports with an empty type, labelled MD", async () => {
      setup();
      stageFile(new File(["# notes"], "2026-01-01-onboarding-notes.md", { type: "" }));

      const tile = await screen.findByTestId("attachment-preview");
      expect(tile).toHaveTextContent("MD");
      expect(tile).toHaveTextContent("2026-01-01-onboarding-notes.md");
      expect(tile).toHaveAttribute("title", "2026-01-01-onboarding-notes.md");
      expect(screen.queryByRole("alert")).toBeNull();
    });

    it("stages a .txt labelled TXT", async () => {
      setup();
      stageFile(new File(["hello"], "notes.txt", { type: "text/plain" }));
      expect(await screen.findByTestId("attachment-preview")).toHaveTextContent("TXT");
    });

    it("still labels a PDF as PDF", async () => {
      setup();
      stageFile(new File(["x"], "doc.pdf", { type: "application/pdf" }));
      expect(await screen.findByTestId("attachment-preview")).toHaveTextContent("PDF");
    });

    it("offers .md and .txt in the file picker", () => {
      setup();
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const accept = fileInput.getAttribute("accept") ?? "";
      expect(accept.split(",")).toEqual(expect.arrayContaining([".md", ".txt", "text/markdown"]));
    });

    it("surfaces a rejection as an alert", async () => {
      setup();
      stageFile(new File(["x"], "virus.exe", { type: "application/x-msdownload" }));
      const alert = await screen.findByRole("alert");
      expect(alert).toHaveTextContent('"virus.exe" is not a supported file type.');
    });

    it("rejects a 0-byte file as empty", async () => {
      setup();
      stageFile(new File([""], "empty.md", { type: "" }));
      expect(await screen.findByRole("alert")).toHaveTextContent('"empty.md" is empty.');
      expect(screen.queryAllByTestId("attachment-preview")).toHaveLength(0);
    });

    it("presigns and PUTs a .md with the canonical text/markdown type", async () => {
      const onSend = vi.fn();
      const mockXhr = {
        open: vi.fn(),
        setRequestHeader: vi.fn(),
        send: vi.fn(),
        abort: vi.fn(),
        upload: { onprogress: null as null | ((e: Partial<ProgressEvent>) => void) },
        onload: null as null | (() => void),
        onerror: null as null | (() => void),
        onabort: null as null | (() => void),
        status: 200,
      };
      vi.stubGlobal("XMLHttpRequest", vi.fn(function () { return mockXhr; }));
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          uploadUrl: "https://storage.supabase.co/upload/signed/abc",
          storagePath: "user-1/conv-1/uuid.md",
        }),
      });
      let completeUpload: () => void;
      mockXhr.send.mockImplementation(() => {
        completeUpload = () => mockXhr.onload?.();
      });

      setup({ onSend, conversationId: "conv-1" });
      stageFile(new File(["# notes"], "notes.md", { type: "" }));
      await screen.findByTestId("attachment-preview");

      await userEvent.type(screen.getByRole("textbox"), "see notes");
      await userEvent.keyboard("{Enter}");
      await waitFor(() => expect(mockXhr.send).toHaveBeenCalled());
      completeUpload!();

      const presignBody = JSON.parse(mockFetch.mock.calls[0]![1].body as string);
      expect(presignBody.contentType).toBe("text/markdown");
      expect(presignBody.filename).toBe("notes.md");
      expect(mockXhr.setRequestHeader).toHaveBeenCalledWith("Content-Type", "text/markdown");
      await waitFor(() => {
        expect(onSend).toHaveBeenCalledWith(
          "see notes",
          expect.arrayContaining([
            expect.objectContaining({ filename: "notes.md", contentType: "text/markdown" }),
          ]),
        );
      });
    });
  });

  describe("composer icon buttons render a glyph", () => {
    // happy-dom cannot measure layout, so this is the STRUCTURAL half of the
    // gate (the svg exists inside the right button and the button carries no
    // padding that would collapse it); the bounding-box half is the Playwright
    // e2e in cc-soleur-go-routing.e2e.ts.
    it("attach and send buttons each contain an svg and no base padding", () => {
      setup();
      for (const label of [/attach file/i, "Send message"]) {
        const btn = screen.getByLabelText(label);
        expect(btn.querySelector("svg")).not.toBeNull();
        const tokens = btn.className.split(/\s+/);
        expect(tokens).not.toContain("soleur-btn-pad");
        expect(tokens).not.toContain("px-6");
      }
    });

    it("the mobile @ button (text child) opts out of the text-button padding", () => {
      setup();
      const tokens = screen.getByLabelText("Mention a leader").className.split(/\s+/);
      expect(tokens).toContain("p-0");
    });
  });
  describe("while an attachment send is in flight", () => {
    function primeHangingUpload() {
      const mockXhr = {
        open: vi.fn(),
        setRequestHeader: vi.fn(),
        send: vi.fn(),
        abort: vi.fn(),
        upload: { onprogress: null as null | ((e: Partial<ProgressEvent>) => void) },
        onload: null as null | (() => void),
        onerror: null as null | (() => void),
        onabort: null as null | (() => void),
        status: 200,
      };
      vi.stubGlobal("XMLHttpRequest", vi.fn(function () { return mockXhr; }));
      mockFetch.mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({
          uploadUrl: "https://storage.supabase.co/upload/signed/abc",
          storagePath: "user-1/conv-1/uuid.md",
        }),
      });
      return mockXhr;
    }

    async function startSend() {
      const mockXhr = primeHangingUpload();
      const onSend = vi.fn();
      setup({ onSend, conversationId: "conv-1" });
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      fireEvent.change(fileInput, { target: { files: [new File(["# a"], "a.md", { type: "" })] } });
      await screen.findByTestId("attachment-preview");
      await userEvent.type(screen.getByRole("textbox"), "hi");
      await userEvent.keyboard("{Enter}");
      await waitFor(() => expect(mockXhr.send).toHaveBeenCalled());
      return { mockXhr, onSend };
    }

    it("ignores a drop until the upload settles", async () => {
      const { mockXhr } = await startSend();
      const before = screen.queryAllByTestId("attachment-preview").length;

      const zone = document.querySelector("div.relative") as HTMLElement;
      fireEvent.drop(zone, {
        dataTransfer: { files: [new File(["# b"], "b.md", { type: "" })] },
      });

      expect(screen.queryAllByTestId("attachment-preview")).toHaveLength(before);
      mockXhr.onload?.();
    });

    it("ignores a pasted file until the upload settles", async () => {
      const { mockXhr } = await startSend();
      const before = screen.queryAllByTestId("attachment-preview").length;

      fireEvent.paste(screen.getByRole("textbox"), {
        clipboardData: {
          files: [new File(["# c"], "c.md", { type: "" })],
          getData: () => "",
        },
      });

      expect(screen.queryAllByTestId("attachment-preview")).toHaveLength(before);
      mockXhr.onload?.();
    });

    it("returns focus to the textarea once the send finishes", async () => {
      const { mockXhr, onSend } = await startSend();
      // Browsers drop focus from a control that becomes disabled; happy-dom
      // does not model that, so park focus elsewhere and assert it is GIVEN BACK.
      const parking = document.createElement("input");
      document.body.appendChild(parking);
      parking.focus();
      expect(document.activeElement).toBe(parking);

      mockXhr.onload?.();
      await waitFor(() => expect(onSend).toHaveBeenCalled());
      const textarea = document.querySelector("textarea") as HTMLTextAreaElement;
      await waitFor(() => expect(document.activeElement).toBe(textarea));
      parking.remove();
    });
  });

  describe("attachments unavailable (conversationId === null) — first-run gate", () => {
    function stageViaInput(f: File) {
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      fireEvent.change(fileInput, { target: { files: [f] } });
    }
    const md = () => new File(["# a"], "a.md", { type: "" });

    it("paperclip is aria-disabled (not natively disabled) and stays focusable", () => {
      setup({ conversationId: null });
      const btn = screen.getByLabelText(/attach file/i);
      expect(btn).toHaveAttribute("aria-disabled", "true");
      expect(btn).not.toBeDisabled();
      expect(btn.className.split(/\s+/)).toContain("aria-disabled:opacity-50");
      btn.focus();
      expect(document.activeElement).toBe(btn);
    });

    it("paperclip carries a title and a described-by text explaining why", () => {
      setup({ conversationId: null });
      const btn = screen.getByLabelText(/attach file/i);
      expect(btn).toHaveAttribute("title", UNAVAILABLE_COPY);
      const describedBy = btn.getAttribute("aria-describedby");
      expect(describedBy).toBeTruthy();
      const desc = document.getElementById(describedBy!);
      expect(desc).not.toBeNull();
      expect(desc).toHaveTextContent(UNAVAILABLE_COPY);
    });

    it("an available paperclip has no aria-disabled, title or described-by (legacy undefined and a real id)", () => {
      for (const conversationId of [undefined, REAL_ID]) {
        const { unmount } = setup({ conversationId });
        const btn = screen.getByLabelText(/attach file/i);
        expect(btn).not.toHaveAttribute("aria-disabled");
        expect(btn).not.toHaveAttribute("aria-describedby");
        expect(btn).not.toHaveAttribute("title");
        unmount();
      }
    });

    it("clicking the paperclip opens no picker and shows the availability message", async () => {
      setup({ conversationId: null });
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const clickSpy = vi.spyOn(fileInput, "click");
      await userEvent.click(screen.getByLabelText(/attach file/i));
      expect(clickSpy).not.toHaveBeenCalled();
      expect(await screen.findByRole("alert")).toHaveTextContent(UNAVAILABLE_COPY);
    });

    it("positive control: with a real id the paperclip click opens the picker", async () => {
      setup({ conversationId: REAL_ID });
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      const clickSpy = vi.spyOn(fileInput, "click");
      await userEvent.click(screen.getByLabelText(/attach file/i));
      expect(clickSpy).toHaveBeenCalledTimes(1);
    });

    it("a dropped file is rejected with the availability message and nothing is staged", async () => {
      setup({ conversationId: null });
      const zone = document.querySelector("div.relative") as HTMLElement;
      fireEvent.drop(zone, { dataTransfer: { files: [md()] } });
      expect(await screen.findByRole("alert")).toHaveTextContent(UNAVAILABLE_COPY);
      expect(screen.queryAllByTestId("attachment-preview")).toHaveLength(0);
      expect(mockFetch).not.toHaveBeenCalled();
    });

    it("a pasted file is rejected with the availability message and nothing is staged", async () => {
      setup({ conversationId: null });
      fireEvent.paste(screen.getByRole("textbox"), {
        clipboardData: { files: [md()], getData: () => "" },
      });
      expect(await screen.findByRole("alert")).toHaveTextContent(UNAVAILABLE_COPY);
      expect(screen.queryAllByTestId("attachment-preview")).toHaveLength(0);
      expect(mockFetch).not.toHaveBeenCalled();
    });

    it("a file delivered through the input change event is also gated", async () => {
      setup({ conversationId: null });
      stageViaInput(md());
      expect(await screen.findByRole("alert")).toHaveTextContent(UNAVAILABLE_COPY);
      expect(screen.queryAllByTestId("attachment-preview")).toHaveLength(0);
      expect(mockFetch).not.toHaveBeenCalled();
    });

    it("positive control: the same drop with a real id stages a tile", async () => {
      setup({ conversationId: REAL_ID });
      const zone = document.querySelector("div.relative") as HTMLElement;
      fireEvent.drop(zone, { dataTransfer: { files: [md()] } });
      expect(await screen.findByTestId("attachment-preview")).toHaveTextContent("a.md");
      expect(screen.queryByRole("alert")).toBeNull();
    });

    it("transition null -> real id (session_started): a drop after the rerender stages a tile", async () => {
      const { rerender } = setup({ conversationId: null });
      const zone = () => document.querySelector("div.relative") as HTMLElement;
      fireEvent.drop(zone(), { dataTransfer: { files: [md()] } });
      expect(await screen.findByRole("alert")).toHaveTextContent(UNAVAILABLE_COPY);

      rerender(<ChatInput {...defaultProps} conversationId={REAL_ID} />);
      fireEvent.drop(zone(), { dataTransfer: { files: [md()] } });
      expect(await screen.findByTestId("attachment-preview")).toHaveTextContent("a.md");
    });

    it("transition real id -> null (reconnect): a drop after the rerender is rejected", async () => {
      const { rerender } = setup({ conversationId: REAL_ID });
      rerender(<ChatInput {...defaultProps} conversationId={null} />);
      const zone = document.querySelector("div.relative") as HTMLElement;
      fireEvent.drop(zone, { dataTransfer: { files: [md()] } });
      expect(await screen.findByRole("alert")).toHaveTextContent(UNAVAILABLE_COPY);
      expect(screen.queryAllByTestId("attachment-preview")).toHaveLength(0);
    });

    it("characterization: dragover and drop default are prevented even when unavailable", () => {
      setup({ conversationId: null });
      const zone = document.querySelector("div.relative") as HTMLElement;
      // fireEvent returns false when preventDefault() was called.
      expect(fireEvent.dragOver(zone, { dataTransfer: { files: [] } })).toBe(false);
      expect(fireEvent.drop(zone, { dataTransfer: { files: [md()] } })).toBe(false);
    });
  });

  describe("presign conversation id and tile copy", () => {
    function primeXhr() {
      const mockXhr = {
        open: vi.fn(),
        setRequestHeader: vi.fn(),
        send: vi.fn(),
        abort: vi.fn(),
        upload: { onprogress: null as null | ((e: Partial<ProgressEvent>) => void) },
        onload: null as null | (() => void),
        onerror: null as null | (() => void),
        onabort: null as null | (() => void),
        status: 200,
      };
      vi.stubGlobal("XMLHttpRequest", vi.fn(function () { return mockXhr; }));
      return mockXhr;
    }

    async function stageAndSend(props: Record<string, unknown>) {
      setup(props);
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      fireEvent.change(fileInput, { target: { files: [new File(["# a"], "a.md", { type: "" })] } });
      await screen.findByTestId("attachment-preview");
      await userEvent.click(screen.getByLabelText("Send message"));
    }

    it("characterization: the presign body carries the conversationId prop", async () => {
      primeXhr();
      mockFetch.mockResolvedValueOnce({ ok: false, status: 404, json: () => Promise.resolve({ error: "conversation_not_found" }) });
      await stageAndSend({ conversationId: REAL_ID });
      await waitFor(() => expect(mockFetch).toHaveBeenCalled());
      const body = JSON.parse(mockFetch.mock.calls[0]![1].body as string);
      expect(body.conversationId).toBe(REAL_ID);
    });

    it.each([
      ["conversation_not_found", 404, "This conversation isn't ready for attachments yet. Remove the file and attach it again."],
      ["file_too_large", 400, "File is empty or larger than 20 MB."],
      ["unsupported_file_type", 400, "This file type isn't supported. You can attach images, PDFs, .md or .txt files."],
      ["not_a_workspace_member", 403, "You don't have access to attach files to this conversation."],
      ["unauthorized", 401, "Your session expired. Sign in again to attach files."],
      ["upload_failed", 500, GENERIC_COPY],
      ["invalid_request", 400, GENERIC_COPY],
      ["some_future_code", 400, GENERIC_COPY],
    ])("presign error %s renders human copy on the tile, never the raw code", async (code, status, copy) => {
      primeXhr();
      mockFetch.mockResolvedValueOnce({ ok: false, status, json: () => Promise.resolve({ error: code }) });
      await stageAndSend({ conversationId: REAL_ID });
      const tile = await screen.findByTestId("attachment-preview");
      await waitFor(() => expect(tile).toHaveTextContent(copy));
      expect(tile).not.toHaveTextContent(code);
    });

    it("a staged file is presigned under the CURRENT id after the id changes (reconnect), not the id at staging time", async () => {
      primeXhr();
      const OTHER_ID = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c99";
      mockFetch.mockResolvedValueOnce({ ok: false, status: 404, json: () => Promise.resolve({ error: "conversation_not_found" }) });
      const { rerender } = setup({ conversationId: REAL_ID });
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      fireEvent.change(fileInput, { target: { files: [new File(["# a"], "a.md", { type: "" })] } });
      await screen.findByTestId("attachment-preview");

      rerender(<ChatInput {...defaultProps} conversationId={OTHER_ID} />);
      await userEvent.click(screen.getByLabelText("Send message"));
      await waitFor(() => expect(mockFetch).toHaveBeenCalled());
      expect(JSON.parse(mockFetch.mock.calls[0]![1].body as string).conversationId).toBe(OTHER_ID);
    });

    it("send while attachments became unavailable (id -> null): nothing presigned or sent, files stay staged, availability message shown", async () => {
      primeXhr();
      const onSend = vi.fn();
      const { rerender } = setup({ conversationId: REAL_ID, onSend });
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      fireEvent.change(fileInput, { target: { files: [new File(["# a"], "a.md", { type: "" })] } });
      await screen.findByTestId("attachment-preview");

      rerender(<ChatInput {...defaultProps} onSend={onSend} conversationId={null} />);
      await userEvent.click(screen.getByLabelText("Send message"));

      expect(mockFetch).not.toHaveBeenCalled();
      expect(onSend).not.toHaveBeenCalled();
      expect(screen.getAllByTestId("attachment-preview")).toHaveLength(1);
      expect(await screen.findByRole("alert")).toHaveTextContent(UNAVAILABLE_COPY);
    });

    it("a presign failure with an unparsable body falls back to the generic copy", async () => {
      primeXhr();
      mockFetch.mockResolvedValueOnce({ ok: false, status: 502, json: () => Promise.reject(new Error("bad json")) });
      await stageAndSend({ conversationId: REAL_ID });
      const tile = await screen.findByTestId("attachment-preview");
      await waitFor(() => expect(tile).toHaveTextContent(GENERIC_COPY));
      expect(tile).not.toHaveTextContent(/presign failed/i);
    });
  });
});
