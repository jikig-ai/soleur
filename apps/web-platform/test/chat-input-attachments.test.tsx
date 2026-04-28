// DO NOT add `vi.useFakeTimers()` to this file. The XHR progress mocks use
// manual triggers (see `fireProgress50` / `fireProgress100` / `completeUpload`
// in the "send with attachments" describe block). Mixing fake timers with
// `@testing-library/user-event` v14 hangs `await user.type/keyboard` calls —
// see testing-library/user-event#833 and react-testing-library#1197/#1198.
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ChatInput } from "@/components/chat/chat-input";

// Mock fetch for presign API calls
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

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
      vi.stubGlobal("XMLHttpRequest", vi.fn(() => mockXhr));
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

      let fireError: () => void;
      mockXhr.send.mockImplementation(() => {
        fireError = () => mockXhr.onerror?.();
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

      fireError!();

      await waitFor(() => {
        expect(screen.getByText(/upload to storage failed/i)).toBeInTheDocument();
      });
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
        expect(screen.getByText(/upload to storage failed/i)).toBeInTheDocument();
      });
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

      let fireError: () => void;
      mockXhr.send.mockImplementation(() => {
        fireError = () => mockXhr.onerror?.();
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

      fireError!();

      // Errored attachment should persist with error message
      await waitFor(() => {
        expect(screen.getByText(/upload to storage failed/i)).toBeInTheDocument();
        expect(screen.getByText(/fail\.png/)).toBeInTheDocument();
      });
    });
  });
});
