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
    it("calls onSend with attachments after successful upload", async () => {
      const onSend = vi.fn();
      setup({ onSend });

      // Mock successful presign + upload
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({
            uploadUrl: "https://storage.supabase.co/upload/signed/abc",
            storagePath: "user-1/conv-1/uuid.png",
          }),
        })
        .mockResolvedValueOnce({ ok: true }); // PUT to storage

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
  });
});
