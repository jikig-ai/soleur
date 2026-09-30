// Mounted ChatSurface tests for the first-run send flow (#9297) and the
// composer `conversationId` wiring. The ordering rules (upload-before-send,
// readiness, deadline, Sentry) live in first-run-send.test.ts; this file proves
// only what a mount can: the once-guard under StrictMode, the `fr=1` marker and
// its disqualifiers, the live-state ref wiring, the busy composer, the re-arm,
// and the real id reaching the real ChatInput.
//
// Do NOT add vi.useFakeTimers(): "exactly once" assertions use a settle step.
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, act, cleanup, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";
import { setPendingFiles, getPendingFiles, clearPendingFiles } from "@/lib/pending-attachments";
import type { AttachmentRef } from "@/lib/types";

const REAL_A = "0a1b2c3d-0000-4000-8000-00000000000a";
const REAL_B = "0a1b2c3d-0000-4000-8000-00000000000b";
const REAL_C = "0a1b2c3d-0000-4000-8000-00000000000c";

const mockSendMessage = vi.fn();
const mockStartSession = vi.fn();
const mockUpload = vi.fn();
const mockFetch = vi.fn();

let wsReturn = createWebSocketMock();

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

vi.mock("@/lib/upload-attachments", () => ({
  uploadPendingFiles: (files: File[], id: string) => mockUpload(files, id),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

// Stable router object + stable replace: a fresh object per render would churn
// the `router` effect dependency (see chat-surface-sidebar.test.tsx).
const mockSearchParams = new URLSearchParams();
const mockReplace = vi.fn();
const mockRouter = { replace: mockReplace, push: vi.fn(), back: vi.fn(), forward: vi.fn(), refresh: vi.fn(), prefetch: vi.fn() };
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => mockRouter,
  usePathname: () => "/dashboard/chat/new",
}));

import { ChatSurface } from "@/components/chat/chat-surface";

type Deferred<T> = { promise: Promise<T>; resolve: (v: T) => void };
function deferred<T>(): Deferred<T> {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

const pendingDeferreds: Deferred<AttachmentRef[]>[] = [];
function deferredUpload(): Deferred<AttachmentRef[]> {
  const d = deferred<AttachmentRef[]>();
  pendingDeferreds.push(d);
  return d;
}

function mdFile(name = "notes.md"): File {
  return new File(["synthetic"], name, { type: "text/markdown" });
}

function refFor(file: File, id: string): AttachmentRef {
  return {
    storagePath: `user/${id}/${file.name}`,
    filename: file.name,
    contentType: "text/markdown",
    sizeBytes: 9,
  };
}

function ws(over: Parameters<typeof createWebSocketMock>[0] = {}) {
  return createWebSocketMock({
    sendMessage: mockSendMessage,
    startSession: mockStartSession,
    status: "connected",
    sessionConfirmed: true,
    realConversationId: REAL_A,
    ...over,
  });
}

function surface(props: Partial<React.ComponentProps<typeof ChatSurface>> = {}) {
  return <ChatSurface variant="full" conversationId="new" {...props} />;
}

async function settle() {
  await act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });
}

function presignCalls() {
  return mockFetch.mock.calls.filter(
    (c) => typeof c[0] === "string" && (c[0] as string).includes("/api/attachments/presign"),
  );
}

describe("ChatSurface first-run attachments", () => {
  beforeEach(() => {
    clearPendingFiles();
    mockSendMessage.mockReset();
    mockStartSession.mockReset();
    mockUpload.mockReset();
    mockReplace.mockReset();
    mockFetch.mockReset();
    mockFetch.mockImplementation(async (url: string) => {
      if (typeof url === "string" && url.includes("/api/attachments/presign")) {
        return { ok: false, status: 404, json: async () => ({ error: "conversation_not_found" }) };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    });
    vi.stubGlobal("fetch", mockFetch);
    for (const key of [...mockSearchParams.keys()]) mockSearchParams.delete(key);
    pendingDeferreds.length = 0;
    wsReturn = ws();
  });

  afterEach(async () => {
    for (const d of pendingDeferreds) d.resolve([]);
    await settle();
    cleanup();
    clearPendingFiles();
  });

  describe("fr=1 first-run send", () => {
    it("files + msg: uploads once (StrictMode once-guard), then sends ONE message with refs", async () => {
      const f = mdFile();
      setPendingFiles([f]);
      mockSearchParams.set("msg", "hi");
      mockSearchParams.set("fr", "1");
      const d = deferredUpload();
      mockUpload.mockReturnValueOnce(d.promise);

      render(<React.StrictMode>{surface()}</React.StrictMode>);
      await settle();

      expect(mockUpload).toHaveBeenCalledTimes(1);
      expect(mockUpload).toHaveBeenCalledWith([f], REAL_A);
      // Upload first: nothing is sent while the upload is in flight.
      expect(mockSendMessage).not.toHaveBeenCalled();

      await act(async () => {
        d.resolve([refFor(f, REAL_A)]);
      });
      await settle();

      expect(mockSendMessage).toHaveBeenCalledTimes(1);
      expect(mockSendMessage).toHaveBeenCalledWith("hi", [refFor(f, REAL_A)]);
      expect(mockReplace).toHaveBeenCalledTimes(1);
      expect(mockReplace).toHaveBeenCalledWith("/dashboard/chat/new", { scroll: false });
      expect(getPendingFiles()).toEqual([]);
    });

    it("files only (no msg): uploads and sends exactly one message with empty text", async () => {
      const f = mdFile();
      setPendingFiles([f]);
      mockSearchParams.set("fr", "1");
      mockUpload.mockResolvedValueOnce([refFor(f, REAL_A)]);

      render(surface());
      await settle();

      expect(mockUpload).toHaveBeenCalledTimes(1);
      expect(mockSendMessage).toHaveBeenCalledTimes(1);
      expect(mockSendMessage).toHaveBeenCalledWith("", [refFor(f, REAL_A)]);
    });

    it("msg only (no files): sends exactly ONE message without waiting for an id", async () => {
      mockSearchParams.set("msg", "hi");
      wsReturn = ws({ realConversationId: null });

      render(<React.StrictMode>{surface()}</React.StrictMode>);
      await settle();

      expect(mockUpload).not.toHaveBeenCalled();
      expect(mockSendMessage).toHaveBeenCalledTimes(1);
      expect(mockSendMessage.mock.calls[0]).toEqual(["hi"]);
    });

    it("re-render after the first send does not re-send", async () => {
      mockSearchParams.set("msg", "hi");
      const { rerender } = render(<React.StrictMode>{surface()}</React.StrictMode>);
      await settle();
      wsReturn = ws({ realConversationId: REAL_B });
      rerender(<React.StrictMode>{surface()}</React.StrictMode>);
      await settle();
      expect(mockSendMessage).toHaveBeenCalledTimes(1);
    });

    it("the composer is disabled while the first-run send is in flight", async () => {
      const f = mdFile();
      setPendingFiles([f]);
      mockSearchParams.set("fr", "1");
      const d = deferredUpload();
      mockUpload.mockReturnValueOnce(d.promise);

      render(surface());
      await settle();

      const box = screen.getByPlaceholderText(/follow up or ask another question/i);
      expect(box).toBeDisabled();

      await act(async () => {
        d.resolve([refFor(f, REAL_A)]);
      });
      await settle();
      expect(screen.getByPlaceholderText(/follow up or ask another question/i)).not.toBeDisabled();
    });
  });

  describe("pending files are NEVER consumed without the full first-run gate", () => {
    type Case = {
      label: string;
      props?: Partial<React.ComponentProps<typeof ChatSurface>>;
      fr: boolean;
      resumed?: boolean;
    };
    const cases: Case[] = [
      { label: "fr marker absent", fr: false },
      { label: "conversationId is not 'new'", props: { conversationId: "abc" }, fr: true },
      { label: "sidebar variant", props: { variant: "sidebar" }, fr: true },
      { label: "resumed session", fr: true, resumed: true },
    ];

    it.each(cases)("with ?msg=hi: $label -> files stay staged, no upload, msg still sent", async (c) => {
      const f = mdFile();
      setPendingFiles([f]);
      mockSearchParams.set("msg", "hi");
      if (c.fr) mockSearchParams.set("fr", "1");
      if (c.resumed) {
        wsReturn = ws({
          resumedFrom: { conversationId: "prev", timestamp: "2026-01-01T00:00:00Z", messageCount: 2 },
        });
      }

      render(surface(c.props));
      await settle();

      expect(mockUpload).not.toHaveBeenCalled();
      expect(getPendingFiles()).toEqual([f]);
      // The msgParam path is unchanged for every route.
      expect(mockSendMessage).toHaveBeenCalledTimes(1);
      expect(mockSendMessage.mock.calls[0]).toEqual(["hi"]);
    });

    it.each(cases)("files-only: $label -> files stay staged, nothing sent", async (c) => {
      const f = mdFile();
      setPendingFiles([f]);
      if (c.fr) mockSearchParams.set("fr", "1");
      if (c.resumed) {
        wsReturn = ws({
          resumedFrom: { conversationId: "prev", timestamp: "2026-01-01T00:00:00Z", messageCount: 2 },
        });
      }

      render(surface(c.props));
      await settle();

      expect(mockUpload).not.toHaveBeenCalled();
      expect(mockSendMessage).not.toHaveBeenCalled();
      expect(getPendingFiles()).toEqual([f]);
    });
  });

  describe("live-state wiring and re-arm", () => {
    it("liveRef: socket drops during the upload -> nothing is sent into the dead socket", async () => {
      const f = mdFile();
      setPendingFiles([f]);
      mockSearchParams.set("msg", "hi");
      mockSearchParams.set("fr", "1");
      const d = deferredUpload();
      mockUpload.mockReturnValueOnce(d.promise);

      const { rerender } = render(surface());
      await settle();
      expect(mockUpload).toHaveBeenCalledTimes(1);

      // A reconnect: status down and sessionConfirmed reset. Mutating wsReturn
      // alone does not re-render, so rerender explicitly.
      wsReturn = ws({ status: "disconnected", sessionConfirmed: false });
      rerender(surface());
      await act(async () => {
        d.resolve([refFor(f, REAL_A)]);
      });
      await settle();

      expect(mockSendMessage).not.toHaveBeenCalled();
    });

    it("re-arm: new session during the upload -> re-uploads ONCE under the new id, then one send", async () => {
      const f = mdFile();
      setPendingFiles([f]);
      mockSearchParams.set("msg", "hi");
      mockSearchParams.set("fr", "1");
      const d1 = deferredUpload();
      const d2 = deferredUpload();
      mockUpload.mockReturnValueOnce(d1.promise).mockReturnValueOnce(d2.promise);

      const { rerender } = render(surface());
      await settle();
      expect(mockUpload).toHaveBeenCalledTimes(1);
      expect(mockUpload).toHaveBeenLastCalledWith([f], REAL_A);

      wsReturn = ws({ realConversationId: REAL_B });
      rerender(surface());
      await act(async () => {
        d1.resolve([refFor(f, REAL_A)]);
      });
      await settle();

      expect(mockSendMessage).not.toHaveBeenCalled();
      expect(mockUpload).toHaveBeenCalledTimes(2);
      expect(mockUpload).toHaveBeenLastCalledWith([f], REAL_B);

      await act(async () => {
        d2.resolve([refFor(f, REAL_B)]);
      });
      await settle();

      expect(mockSendMessage).toHaveBeenCalledTimes(1);
      expect(mockSendMessage).toHaveBeenCalledWith("hi", [refFor(f, REAL_B)]);
    });

    it("re-arm gives up after ONE retry (no third upload, no send)", async () => {
      const f = mdFile();
      setPendingFiles([f]);
      mockSearchParams.set("msg", "hi");
      mockSearchParams.set("fr", "1");
      const d1 = deferredUpload();
      const d2 = deferredUpload();
      mockUpload.mockReturnValueOnce(d1.promise).mockReturnValueOnce(d2.promise);

      const { rerender } = render(surface());
      await settle();

      wsReturn = ws({ realConversationId: REAL_B });
      rerender(surface());
      await act(async () => {
        d1.resolve([refFor(f, REAL_A)]);
      });
      await settle();
      expect(mockUpload).toHaveBeenCalledTimes(2);

      wsReturn = ws({ realConversationId: REAL_C });
      rerender(surface());
      await act(async () => {
        d2.resolve([refFor(f, REAL_B)]);
      });
      await settle();

      expect(mockUpload).toHaveBeenCalledTimes(2);
      expect(mockSendMessage).not.toHaveBeenCalled();
    });
  });

  describe("composer conversationId wiring (real ChatInput)", () => {
    async function stageAndSend() {
      const fileInput = document.querySelector("input[type='file']") as HTMLInputElement;
      fireEvent.change(fileInput, { target: { files: [mdFile()] } });
      const send = await screen.findByLabelText("Send message");
      await userEvent.click(send);
    }

    it("fresh conversation before session_started: paperclip is aria-disabled", async () => {
      wsReturn = ws({ realConversationId: null, sessionConfirmed: false });
      render(surface());
      await settle();
      expect(screen.getByLabelText("Attach file")).toHaveAttribute("aria-disabled", "true");
    });

    it("fresh conversation after a reconnect (stale id, sessionConfirmed=false): paperclip is aria-disabled", async () => {
      wsReturn = ws({ realConversationId: REAL_A, sessionConfirmed: false });
      render(surface());
      await settle();
      expect(screen.getByLabelText("Attach file")).toHaveAttribute("aria-disabled", "true");
    });

    it("fresh conversation with a confirmed session: presign carries the real id, never 'new'", async () => {
      wsReturn = ws({ realConversationId: REAL_A, sessionConfirmed: true });
      render(surface());
      await settle();
      expect(screen.getByLabelText("Attach file")).not.toHaveAttribute("aria-disabled", "true");

      await stageAndSend();
      await waitFor(() => expect(presignCalls().length).toBeGreaterThan(0));
      for (const c of presignCalls()) {
        const body = JSON.parse((c[1] as { body: string }).body);
        expect(body.conversationId).toBe(REAL_A);
        expect(body.conversationId).not.toBe("new");
      }
    });

    it("existing conversation route: presign carries realConversationId ?? route id", async () => {
      wsReturn = ws({ realConversationId: null });
      render(surface({ conversationId: "abc" }));
      await settle();
      await stageAndSend();
      await waitFor(() => expect(presignCalls().length).toBeGreaterThan(0));
      expect(JSON.parse((presignCalls()[0]![1] as { body: string }).body).conversationId).toBe("abc");
    });
  });
});
