import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, fireEvent, waitFor } from "@testing-library/react";

vi.mock("@sentry/nextjs", () => ({ captureMessage: vi.fn() }));

import { WorkspaceLogoSettings } from "@/components/settings/workspace-logo-settings";

const WS = "55555555-5555-5555-5555-555555555555";

// Deterministic, fast dimension probe: stub Image so onload fires with a
// configurable square/non-square size (jsdom/happy-dom won't decode a blob URL).
let stubW = 64;
let stubH = 64;
class StubImage {
  onload: (() => void) | null = null;
  onerror: (() => void) | null = null;
  width = 0;
  height = 0;
  _src = "";
  set src(v: string) {
    this._src = v;
    this.width = stubW;
    this.height = stubH;
    queueMicrotask(() => this.onload?.());
  }
  get src() {
    return this._src;
  }
}

const fetchMock = vi.fn();

beforeEach(() => {
  stubW = 64;
  stubH = 64;
  vi.stubGlobal("Image", StubImage as unknown as typeof Image);
  vi.stubGlobal("fetch", fetchMock);
  URL.createObjectURL = vi.fn(() => "blob:stub");
  URL.revokeObjectURL = vi.fn();
  fetchMock.mockResolvedValue({ ok: true, status: 200, json: async () => ({ ok: true }) });
});
afterEach(() => {
  vi.unstubAllGlobals();
  fetchMock.mockReset();
});

function pngFile(bytes = 100) {
  return new File([new Uint8Array(bytes)], "logo.png", { type: "image/png" });
}
function selectFile(input: HTMLInputElement, file: File) {
  Object.defineProperty(input, "files", { value: [file], configurable: true });
  fireEvent.change(input);
}

describe("WorkspaceLogoSettings — non-owner gating (AC8b)", () => {
  it("renders a disabled control with an owners-only tooltip; no functional file input", () => {
    const { getByTestId, queryByTestId, getByText } = render(
      <WorkspaceLogoSettings workspaceId={WS} workspaceName="Acme" isOwner={false} initialHasLogo={false} />,
    );
    const btn = getByTestId("workspace-logo-upload-btn") as HTMLButtonElement;
    expect(btn.disabled).toBe(true);
    expect(btn.getAttribute("title")).toMatch(/owners can change the logo/i);
    expect(getByText(/owners can change the logo/i)).toBeTruthy();
    expect(queryByTestId("workspace-logo-file-input")).toBeNull();
  });
});

describe("WorkspaceLogoSettings — owner (AC4-mirror client checks + state union)", () => {
  it("rejects a JPG with the 'SVG and JPG aren't accepted' copy (no upload)", async () => {
    const { getByTestId, findByText } = render(
      <WorkspaceLogoSettings workspaceId={WS} workspaceName="Acme" isOwner initialHasLogo={false} />,
    );
    const input = getByTestId("workspace-logo-file-input") as HTMLInputElement;
    selectFile(input, new File([new Uint8Array(10)], "logo.jpg", { type: "image/jpeg" }));
    expect(await findByText(/SVG and JPG aren't accepted/i)).toBeTruthy();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects a >1 MB file (no upload)", async () => {
    const { getByTestId, findByText } = render(
      <WorkspaceLogoSettings workspaceId={WS} workspaceName="Acme" isOwner initialHasLogo={false} />,
    );
    const input = getByTestId("workspace-logo-file-input") as HTMLInputElement;
    selectFile(input, pngFile(1_100_000));
    expect(await findByText(/under 1 MB/i)).toBeTruthy();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects a non-square image client-side (no upload)", async () => {
    stubW = 64;
    stubH = 32;
    const { getByTestId, findByText } = render(
      <WorkspaceLogoSettings workspaceId={WS} workspaceName="Acme" isOwner initialHasLogo={false} />,
    );
    const input = getByTestId("workspace-logo-file-input") as HTMLInputElement;
    selectFile(input, pngFile());
    expect(await findByText(/square/i)).toBeTruthy();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("uploads a valid square PNG via POST and reaches success state", async () => {
    const { getByTestId, findByTestId } = render(
      <WorkspaceLogoSettings workspaceId={WS} workspaceName="Acme" isOwner initialHasLogo={false} />,
    );
    const input = getByTestId("workspace-logo-file-input") as HTMLInputElement;
    selectFile(input, pngFile());
    await findByTestId("workspace-logo-status-success");
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/workspace/logo",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("surfaces the server reject message in the error state", async () => {
    fetchMock.mockResolvedValue({
      ok: false,
      status: 422,
      json: async () => ({ error: "Logo must be a square image" }),
    });
    const { getByTestId, findByTestId } = render(
      <WorkspaceLogoSettings workspaceId={WS} workspaceName="Acme" isOwner initialHasLogo={false} />,
    );
    selectFile(getByTestId("workspace-logo-file-input") as HTMLInputElement, pngFile());
    await findByTestId("workspace-logo-status-error");
  });

  it("Remove issues a DELETE and drops back to no-logo", async () => {
    const { getByTestId } = render(
      <WorkspaceLogoSettings workspaceId={WS} workspaceName="Acme" isOwner initialHasLogo />,
    );
    fireEvent.click(getByTestId("workspace-logo-remove-btn"));
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/workspace/logo",
        expect.objectContaining({ method: "DELETE" }),
      ),
    );
  });
});
