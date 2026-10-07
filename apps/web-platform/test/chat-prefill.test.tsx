// #9557 — `?q=` command-palette prefill consumer. The command palette's
// "Ask an agent about <q>" fallback navigates to /dashboard/chat/new?q=<enc>
// (producer: components/command-palette/use-shortcuts.tsx). The param seeds
// the composer as draft text, NEVER auto-sends (auto-send is `?msg=`'s
// shipped contract, unchanged here), and is stripped via
// `router.replace(pathname, { scroll: false })` — the same convention as the
// `msg`/`fr` first-run strip.
//
// Two levels are pinned:
//  A) ChatInput `prefill` prop — latch semantics: applies at most once, only
//     into an EMPTY composer, never over a hydrated draftKey draft or typed
//     text; an empty prefill is a no-op, not a latch burn.
//  B) ChatSurface wiring — `?q=` reaches the composer only on the producer's
//     target surface (variant "full" + route id "new"), `?msg=` wins over
//     `?q=`, and the strip effect.
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, act } from "@testing-library/react";
import { ChatInput } from "@/components/chat/chat-input";
import { setControlledValue } from "./helpers/dom";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";
import {
  setPendingFiles,
  getPendingFiles,
  clearPendingFiles,
} from "@/lib/pending-attachments";
import type { AttachmentRef } from "@/lib/types";

const REAL_A = "0a1b2c3d-0000-4000-8000-00000000000a";

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

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/lib/upload-attachments", () => ({
  uploadPendingFiles: (files: File[], id: string) => mockUpload(files, id),
}));

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

// Stable router object + stable replace: a fresh object per render would churn
// the `router` effect dependency (see chat-surface-sidebar.test.tsx).
const mockSearchParams = new URLSearchParams();
const mockReplace = vi.fn();
const mockRouter = {
  replace: mockReplace,
  push: vi.fn(),
  back: vi.fn(),
  forward: vi.fn(),
  refresh: vi.fn(),
  prefetch: vi.fn(),
};
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => mockRouter,
  usePathname: () => "/dashboard/chat/new",
}));

import { ChatSurface } from "@/components/chat/chat-surface";

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

function composer(): HTMLTextAreaElement {
  return document.querySelector("textarea") as HTMLTextAreaElement;
}

describe("ChatInput — prefill prop (#9557)", () => {
  beforeEach(() => {
    try {
      sessionStorage.clear();
    } catch {
      /* noop */
    }
  });

  const commonProps = {
    onSend: vi.fn(),
    onAtTrigger: vi.fn(),
    onAtDismiss: vi.fn(),
  };

  it("seeds an empty composer with the prefill text and focuses it — never sends", () => {
    const onSend = vi.fn();
    render(<ChatInput {...commonProps} onSend={onSend} prefill="how do I deploy?" />);
    const ta = composer();
    expect(ta.value).toBe("how do I deploy?");
    expect(document.activeElement).toBe(ta);
    expect(onSend).not.toHaveBeenCalled();
  });

  it("applies a prefill that arrives after mount (useSearchParams may populate late)", () => {
    const { rerender } = render(<ChatInput {...commonProps} />);
    const ta = composer();
    expect(ta.value).toBe("");

    rerender(<ChatInput {...commonProps} prefill="late text" />);
    expect(ta.value).toBe("late text");
  });

  it("is latched — applies exactly once; a changed prefill is ignored", () => {
    const { rerender } = render(<ChatInput {...commonProps} prefill="first" />);
    const ta = composer();
    expect(ta.value).toBe("first");

    rerender(<ChatInput {...commonProps} prefill="second" />);
    expect(ta.value).toBe("first");

    // Discriminates the latch itself: clearing the text does NOT resurrect a
    // CHANGED prefill — an unlatched impl re-fires on the "second"→"third" prop
    // change and seeds the now-empty composer. (A same-string rerender would
    // not re-fire under [prefill] deps, so a distinct value is load-bearing.)
    act(() => setControlledValue(ta, ""));
    rerender(<ChatInput {...commonProps} prefill="third" />);
    expect(ta.value).toBe("");
  });

  it("never clobbers a hydrated draftKey draft — the param is consumed, clearing the draft does not resurrect it", () => {
    sessionStorage.setItem("draft:prefill", "existing draft");
    render(
      <ChatInput {...commonProps} draftKey="draft:prefill" prefill="param text" />,
    );
    const ta = composer();
    expect(ta.value).toBe("existing draft");

    act(() => setControlledValue(ta, ""));
    expect(ta.value).toBe("");
  });

  it("never clobbers text the user typed before a late prefill arrives", () => {
    const { rerender } = render(<ChatInput {...commonProps} />);
    const ta = composer();
    act(() => setControlledValue(ta, "typed"));

    rerender(<ChatInput {...commonProps} prefill="param text" />);
    expect(ta.value).toBe("typed");
  });

  it("an empty prefill is a no-op and does NOT burn the latch", () => {
    const { rerender } = render(<ChatInput {...commonProps} prefill="" />);
    const ta = composer();
    expect(ta.value).toBe("");

    // The latch must still be live: a subsequent non-empty prefill applies.
    rerender(<ChatInput {...commonProps} prefill="now it arrives" />);
    expect(ta.value).toBe("now it arrives");
  });
});

describe("ChatSurface — ?q= prefill (#9557)", () => {
  beforeEach(() => {
    mockSendMessage.mockReset();
    mockStartSession.mockReset();
    mockUpload.mockReset();
    clearPendingFiles();
    mockReplace.mockReset();
    // Reflect the real router: router.replace(pathname) clears the WHOLE query,
    // so a strip must never fire while a first-run param is still pending.
    mockReplace.mockImplementation(() => {
      for (const key of [...mockSearchParams.keys()]) mockSearchParams.delete(key);
    });
    mockFetch.mockReset();
    mockFetch.mockImplementation(async () => ({
      ok: false,
      status: 404,
      json: async () => ({}),
    }));
    vi.stubGlobal("fetch", mockFetch);
    for (const key of [...mockSearchParams.keys()]) mockSearchParams.delete(key);
    try {
      sessionStorage.clear();
    } catch {
      /* noop */
    }
    wsReturn = ws();
  });

  it("seeds the composer on the producer's target (full /chat/new), never auto-sends, strips via router.replace", async () => {
    mockSearchParams.set("q", "how do I deploy?");

    render(<React.StrictMode>{surface()}</React.StrictMode>);
    await settle();

    expect(composer().value).toBe("how do I deploy?");
    // Prefill is draft text, NOT a send.
    expect(mockSendMessage).not.toHaveBeenCalled();
    // Consumed params leave the URL — once, under StrictMode's effect replay.
    expect(mockReplace).toHaveBeenCalledTimes(1);
    expect(mockReplace).toHaveBeenCalledWith("/dashboard/chat/new", {
      scroll: false,
    });
    expect(mockSearchParams.get("q")).toBeNull();
  });

  it("?msg= + ?q= together: the msg auto-send wins and q never reaches the composer", async () => {
    mockSearchParams.set("msg", "send this");
    mockSearchParams.set("q", "ignore me");

    render(surface());
    await settle();

    expect(mockSendMessage).toHaveBeenCalledTimes(1);
    expect(mockSendMessage).toHaveBeenCalledWith("send this");
    expect(composer().value).toBe("");
    // The first-run strip removes the whole query — q included.
    expect(mockReplace).toHaveBeenCalledWith("/dashboard/chat/new", {
      scroll: false,
    });
    expect(mockSearchParams.get("q")).toBeNull();
  });

  it("?q= on a non-'new' conversationId is not applied and the foreign param is left alone", async () => {
    mockSearchParams.set("q", "param text");

    render(<ChatSurface variant="full" conversationId="abc" />);
    await settle();

    expect(composer().value).toBe("");
    expect(mockSendMessage).not.toHaveBeenCalled();
    expect(mockReplace).not.toHaveBeenCalled();
  });

  it("?q= on the sidebar variant is not applied and the foreign param is left alone", async () => {
    mockSearchParams.set("q", "param text");

    render(<ChatSurface variant="sidebar" conversationId="new" />);
    await settle();

    expect(composer().value).toBe("");
    expect(mockSendMessage).not.toHaveBeenCalled();
    expect(mockReplace).not.toHaveBeenCalled();
  });

  it("a non-empty draftKey draft is never clobbered by ?q= (param still consumed + stripped)", async () => {
    sessionStorage.setItem("draft:prefill", "existing draft");
    mockSearchParams.set("q", "param text");

    // draftKey reaches ChatInput through the surface regardless of variant;
    // it is the only path to a hydrated draft on mount in this harness.
    render(surface({ sidebarProps: { draftKey: "draft:prefill" } }));
    await settle();

    expect(composer().value).toBe("existing draft");
    expect(mockSendMessage).not.toHaveBeenCalled();
    expect(mockReplace).toHaveBeenCalledWith("/dashboard/chat/new", {
      scroll: false,
    });
  });

  it("empty ?q= is a no-op: nothing seeded, nothing sent", async () => {
    mockSearchParams.set("q", "");

    render(surface());
    await settle();

    expect(composer().value).toBe("");
    expect(mockSendMessage).not.toHaveBeenCalled();
  });

  // frParam is the strip guard's mutation-surviving arm: without it the
  // q-strip fires a SECOND replace alongside the first-run's own. Pinned via
  // replace arity — the first-run effect (earlier-ordered) consumes `fr` and
  // strips the whole query itself, so exactly one replace is correct.
  it("?q= + ?fr=1 with staged files: the first-run send wins, q never prefills, one replace total", async () => {
    const f = mdFile();
    setPendingFiles([f]);
    mockSearchParams.set("q", "param text");
    mockSearchParams.set("fr", "1");
    mockUpload.mockResolvedValueOnce([refFor(f, REAL_A)]);

    render(surface());
    await settle();

    expect(mockUpload).toHaveBeenCalledTimes(1);
    expect(mockSendMessage).toHaveBeenCalledTimes(1);
    expect(mockSendMessage).toHaveBeenCalledWith("", [refFor(f, REAL_A)]);
    // `fr` also excludes the prefill gate — a staged-files send must not
    // land with prefilled text parked beside it.
    expect(composer().value).toBe("");
    // The first-run's own strip is the ONLY replace; a second would mean the
    // q-strip fired on a pending first-run param — the guard's raison d'être.
    expect(mockReplace).toHaveBeenCalledTimes(1);
    expect(mockReplace).toHaveBeenCalledWith("/dashboard/chat/new", {
      scroll: false,
    });
    expect(getPendingFiles()).toEqual([]);
  });
});
