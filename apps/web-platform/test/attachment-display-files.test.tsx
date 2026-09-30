import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { AttachmentDisplay } from "@/components/chat/attachment-display";

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

function att(over: Partial<{ filename: string; contentType: string; sizeBytes: number; storagePath: string }>) {
  return {
    storagePath: `u/c/${Math.random().toString(36).slice(2)}.md`,
    filename: "notes.md",
    contentType: "text/markdown",
    sizeBytes: 300,
    ...over,
  };
}

beforeEach(() => {
  mockFetch.mockReset();
  mockFetch.mockResolvedValue({ json: async () => ({ url: "https://example.test/signed" }) });
});

describe("AttachmentDisplay — file chips", () => {
  it("labels a note under 1 KB as <1 KB rather than 0 KB", async () => {
    render(<AttachmentDisplay attachments={[att({ sizeBytes: 300 })]} />);
    expect(await screen.findByText("<1 KB")).toBeInTheDocument();
    expect(screen.queryByText("0 KB")).toBeNull();
  });

  it("still rounds larger files to KB", async () => {
    render(<AttachmentDisplay attachments={[att({ sizeBytes: 5 * 1024 })]} />);
    expect(await screen.findByText("5 KB")).toBeInTheDocument();
  });

  it("sends the filename with the signed-URL request so the download is named", async () => {
    const a = att({ filename: "2026-01-01-notes.md" });
    render(<AttachmentDisplay attachments={[a]} />);
    await waitFor(() => expect(mockFetch).toHaveBeenCalled());
    const body = JSON.parse(mockFetch.mock.calls[0]![1].body as string);
    expect(body).toEqual({ storagePath: a.storagePath, filename: "2026-01-01-notes.md" });
  });
});
