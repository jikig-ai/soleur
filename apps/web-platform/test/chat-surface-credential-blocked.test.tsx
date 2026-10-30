import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { DomainLeaderId } from "@/server/domain-leaders";
import type { ChatMessage } from "@/lib/chat-state-machine";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

// #11525 — chat surface after a `key_invalid` / `byok_key_missing` card: the
// composer is disabled, a visible helper line carries the "saved" wording with
// an inline Reconnect (survives a dismissed card), Reconnect re-binds the
// session (one resume_session for the captured id, one-shot start_session
// fallback when refused), and Settings opens in a NEW tab so the chat survives.

const mockStartSession = vi.fn();
const mockResumeSession = vi.fn();
const mockSendMessage = vi.fn((..._args: unknown[]) => true);
const mockReconnect = vi.fn();

let wsReturn = createWebSocketMock();

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () =>
    createUseTeamNamesMock({
      getDisplayName: (id: DomainLeaderId) => id.toUpperCase(),
    }),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/dashboard/chat/new",
}));

// Passthrough wrapper so a test can call the surface's real `onSend` (the
// composer is disabled while blocked, so it cannot be driven by typing).
let capturedOnSend: ((m: string) => boolean | void) | null = null;
vi.mock("@/components/chat/chat-input", async (importOriginal) => {
  const mod = await importOriginal<typeof import("@/components/chat/chat-input")>();
  return {
    ...mod,
    ChatInput: (props: React.ComponentProps<typeof mod.ChatInput>) => {
      capturedOnSend = props.onSend as (m: string) => boolean | void;
      return <mod.ChatInput {...props} />;
    },
  };
});

const CONV = "22222222-2222-4222-8222-222222222222";

const oauthKeyInvalid = {
  code: "key_invalid",
  message: "We couldn't sign in to Claude with your connected subscription.",
  credentialScheme: "oauth_token" as const,
  action: { label: "Update key", href: "/dashboard/settings" },
};
const apiKeyInvalid = {
  code: "key_invalid",
  message: "Your API key is invalid or expired.",
  action: { label: "Update key", href: "/dashboard/settings" },
};
const byokMissing = {
  code: "byok_key_missing",
  message: "Add an API key in Settings to continue.",
  action: { label: "Add API key", href: "/dashboard/settings" },
};

const userMsg = (over: Partial<ChatMessage> = {}): ChatMessage =>
  ({ id: "user-1", role: "user", content: "please proceed", type: "text", ...over }) as ChatMessage;

function setWs(over: Parameters<typeof createWebSocketMock>[0] = {}) {
  wsReturn = createWebSocketMock({
    startSession: mockStartSession,
    resumeSession: mockResumeSession,
    sendMessage: mockSendMessage,
    reconnect: mockReconnect,
    ...over,
  });
}

async function mountSurface(props: Record<string, unknown> = {}) {
  const { ChatSurface } = await import("@/components/chat/chat-surface");
  // A fresh element per render: re-rendering the SAME element object would
  // bail out and never re-invoke the mocked hook.
  const make = () => <ChatSurface variant="full" conversationId="new" {...props} />;
  const utils = render(make());
  return { ...utils, rerenderSurface: () => utils.rerender(make()) };
}

describe("ChatSurface — credential blocked (#11525)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    capturedOnSend = null;
    setWs();
  });

  it("not blocked: composer enabled, no helper line, no Reconnect", async () => {
    await mountSurface();
    expect(screen.getByRole("textbox")).not.toBeDisabled();
    expect(screen.queryByText(/Select Reconnect to continue/)).toBeNull();
    expect(screen.queryByRole("button", { name: "Reconnect" })).toBeNull();
  });

  it("oauth key_invalid: composer disabled, oauth placeholder, helper line + inline Reconnect", async () => {
    setWs({
      lastError: oauthKeyInvalid,
      credentialBlocked: true,
      messages: [userMsg({ unanswered: true })],
    });
    await mountSurface();
    const box = screen.getByRole("textbox");
    expect(box).toBeDisabled();
    expect(box).toHaveAttribute("placeholder", "Update your token in Settings, then reconnect");

    const helper = screen.getByText("Saved your token in Settings? Select Reconnect to continue.");
    const status = helper.closest('[role="status"]') as HTMLElement;
    expect(status).not.toBeNull();
    expect(status).toHaveAttribute("aria-live", "polite");
    expect(within(status).getByRole("button", { name: "Reconnect" })).toBeInTheDocument();
  });

  it("api key key_invalid: key wording for placeholder and helper line", async () => {
    setWs({ lastError: apiKeyInvalid, credentialBlocked: true });
    await mountSurface();
    expect(screen.getByRole("textbox")).toHaveAttribute(
      "placeholder",
      "Update your key in Settings, then reconnect",
    );
    expect(screen.getByText("Saved your key in Settings? Select Reconnect to continue.")).toBeInTheDocument();
  });

  it("derives blocked from lastError.code even when the hook flag is false", async () => {
    setWs({ lastError: apiKeyInvalid, credentialBlocked: false });
    await mountSurface();
    expect(screen.getByRole("textbox")).toBeDisabled();
  });

  it("byok_key_missing: API Key Required card, Add API key in a new tab, blocked composer, no generic Error bubble", async () => {
    setWs({
      lastError: byokMissing,
      credentialBlocked: true,
      messages: [userMsg({ unanswered: true })],
    });
    await mountSurface();
    expect(screen.getByText("API Key Required")).toBeInTheDocument();
    const link = screen.getByText("Add API key").closest("a")!;
    expect(link).toHaveAttribute("href", "/dashboard/settings");
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
    expect(screen.getByRole("textbox")).toBeDisabled();
    expect(screen.queryByText(/^Error:/)).toBeNull();
    expect(screen.getByText("Saved your key in Settings? Select Reconnect to continue.")).toBeInTheDocument();
  });

  it("the oauth card opens Settings in a new tab; the card offers Reconnect", async () => {
    setWs({ lastError: oauthKeyInvalid, credentialBlocked: true });
    await mountSurface();
    expect(screen.getByText("Claude Sign-in Failed")).toBeInTheDocument();
    const link = screen.getByText("Update token").closest("a")!;
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
    const alert = screen.getByRole("alert");
    expect(within(alert).getByRole("button", { name: "Reconnect" })).toBeInTheDocument();
  });

  it("an unrelated error keeps the same-tab action (no target)", async () => {
    setWs({
      lastError: {
        code: "workspace_switch_required",
        message: "Switch workspace",
        action: { label: "Switch workspace", href: "/dashboard" },
      },
    });
    await mountSurface();
    const link = screen.getByText("Switch workspace", { selector: "a" });
    expect(link).not.toHaveAttribute("target");
    expect(screen.getByRole("textbox")).not.toBeDisabled();
  });

  it("dismissing the card hides it but keeps the composer disabled and the helper line + Reconnect", async () => {
    setWs({ lastError: oauthKeyInvalid, credentialBlocked: true });
    await mountSurface();
    await userEvent.click(screen.getByRole("button", { name: /dismiss/i }));
    expect(screen.queryByText("Claude Sign-in Failed")).toBeNull();
    expect(screen.getByRole("textbox")).toBeDisabled();
    const status = screen
      .getByText("Saved your token in Settings? Select Reconnect to continue.")
      .closest('[role="status"]') as HTMLElement;
    expect(within(status).getByRole("button", { name: "Reconnect" })).toBeInTheDocument();
  });

  it("installs no visibilitychange or focus listener for the blocked state (no tab-return hint)", async () => {
    const docSpy = vi.spyOn(document, "addEventListener");
    const winSpy = vi.spyOn(window, "addEventListener");
    const types = () =>
      [...docSpy.mock.calls, ...winSpy.mock.calls]
        .map(([t]) => String(t))
        .filter((t) => t === "visibilitychange" || t === "focus");

    const baseline = await mountSurface();
    const baseCount = types().length;
    baseline.unmount();
    docSpy.mockClear();
    winSpy.mockClear();

    setWs({ lastError: oauthKeyInvalid, credentialBlocked: true });
    await mountSurface();
    expect(types().filter((t) => t === "visibilitychange")).toHaveLength(0);
    expect(types().length).toBeLessThanOrEqual(baseCount);
    docSpy.mockRestore();
    winSpy.mockRestore();
  });

  it("handleSend refuses while blocked: returns false BEFORE onBeforeSend and sendMessage", async () => {
    const onBeforeSend = vi.fn();
    setWs({ lastError: oauthKeyInvalid, credentialBlocked: true });
    await mountSurface({ variant: "sidebar", sidebarProps: { onBeforeSend } });
    expect(capturedOnSend).not.toBeNull();
    expect(capturedOnSend!("lost")).toBe(false);
    expect(onBeforeSend).not.toHaveBeenCalled();
    expect(mockSendMessage).not.toHaveBeenCalled();
  });

  it("handleSend refuses when status is not connected (fixes the silent draft drop)", async () => {
    const onBeforeSend = vi.fn();
    setWs({ status: "connecting" });
    await mountSurface({ variant: "sidebar", sidebarProps: { onBeforeSend } });
    expect(capturedOnSend!("x")).toBe(false);
    expect(onBeforeSend).not.toHaveBeenCalled();
    expect(mockSendMessage).not.toHaveBeenCalled();
  });

  it("handleSend relays the hook's boolean when connected", async () => {
    const onBeforeSend = vi.fn();
    setWs();
    await mountSurface({ variant: "sidebar", sidebarProps: { onBeforeSend } });
    expect(capturedOnSend!("ok")).toBe(true);
    expect(onBeforeSend).toHaveBeenCalledWith("ok");
    expect(mockSendMessage).toHaveBeenCalledWith("ok");

    mockSendMessage.mockReturnValueOnce(false);
    expect(capturedOnSend!("refused")).toBe(false);
  });

  it("Reconnect re-binds: one resume_session for the captured id, never start_session again, no auto-resend", async () => {
    setWs({ messages: [userMsg()] });
    const { rerenderSurface } = await mountSurface();
    // Initial session start on mount.
    expect(mockStartSession).toHaveBeenCalledTimes(1);
    mockStartSession.mockClear();

    // The credential error arrives: hook captured the id and blocked.
    setWs({
      lastError: oauthKeyInvalid,
      credentialBlocked: true,
      rebindConversationId: CONV,
      messages: [userMsg({ unanswered: true })],
    });
    rerenderSurface();
    expect(mockResumeSession).not.toHaveBeenCalled();
    expect(mockReconnect).not.toHaveBeenCalled();

    await userEvent.click(
      within(screen.getByRole("alert")).getByRole("button", { name: "Reconnect" }),
    );

    expect(mockReconnect).toHaveBeenCalledTimes(1);
    expect(mockResumeSession).toHaveBeenCalledTimes(1);
    expect(mockResumeSession).toHaveBeenCalledWith(CONV);
    expect(mockStartSession).not.toHaveBeenCalled();
    expect(mockSendMessage).not.toHaveBeenCalled();
  });

  it("the helper-line Reconnect rebinds the same way", async () => {
    setWs({ messages: [userMsg()] });
    const { rerenderSurface } = await mountSurface();
    mockStartSession.mockClear();
    setWs({
      lastError: apiKeyInvalid,
      credentialBlocked: true,
      rebindConversationId: CONV,
      messages: [userMsg({ unanswered: true })],
    });
    rerenderSurface();
    await userEvent.click(screen.getByText("Saved your key in Settings? Select Reconnect to continue.").closest('[role="status"]')!.querySelector("button")!);
    expect(mockReconnect).toHaveBeenCalledTimes(1);
    expect(mockResumeSession).toHaveBeenCalledWith(CONV);
    expect(mockStartSession).not.toHaveBeenCalled();
  });

  it("Reconnect with no captured id starts a session (no resume)", async () => {
    setWs();
    const { rerenderSurface } = await mountSurface();
    mockStartSession.mockClear();
    setWs({ lastError: apiKeyInvalid, credentialBlocked: true, rebindConversationId: null });
    rerenderSurface();
    await userEvent.click(
      within(screen.getByRole("alert")).getByRole("button", { name: "Reconnect" }),
    );
    expect(mockReconnect).toHaveBeenCalledTimes(1);
    expect(mockResumeSession).not.toHaveBeenCalled();
    expect(mockStartSession).toHaveBeenCalledTimes(1);
  });

  it("a refused rebind falls back ONCE to startSession with the surface-held options", async () => {
    setWs({ messages: [userMsg()] });
    const { rerenderSurface } = await mountSurface({ initialContext: undefined });
    mockStartSession.mockClear();

    setWs({
      lastError: apiKeyInvalid,
      credentialBlocked: true,
      rebindConversationId: CONV,
      messages: [userMsg({ unanswered: true })],
    });
    rerenderSurface();
    await userEvent.click(
      within(screen.getByRole("alert")).getByRole("button", { name: "Reconnect" }),
    );
    expect(mockResumeSession).toHaveBeenCalledTimes(1);
    expect(mockStartSession).not.toHaveBeenCalled();

    // The server refused the resume: hook drops the id and raises rebindRefused.
    setWs({ rebindConversationId: null, rebindRefused: true, messages: [userMsg({ unanswered: true })] });
    rerenderSurface();
    expect(mockStartSession).toHaveBeenCalledTimes(1);
    expect(mockResumeSession).toHaveBeenCalledTimes(1);

    // Re-rendering again must not loop.
    rerenderSurface();
    expect(mockStartSession).toHaveBeenCalledTimes(1);
  });

  it("exactly one sendMessage after the rebind when the user re-sends", async () => {
    setWs({ messages: [userMsg()] });
    const { rerenderSurface } = await mountSurface({ variant: "sidebar", sidebarProps: {} });
    setWs({
      lastError: apiKeyInvalid,
      credentialBlocked: true,
      rebindConversationId: CONV,
      messages: [userMsg({ unanswered: true })],
    });
    rerenderSurface();
    await userEvent.click(
      within(screen.getByRole("alert")).getByRole("button", { name: "Reconnect" }),
    );
    // Hook cleared the blocked state after reconnect + session_started.
    setWs({ messages: [userMsg()] });
    rerenderSurface();
    expect(capturedOnSend!("again")).toBe(true);
    expect(mockSendMessage).toHaveBeenCalledTimes(1);
  });

  it("flags the unanswered user bubble with 'Not answered' and an sr-only explanation", async () => {
    setWs({ lastError: oauthKeyInvalid, credentialBlocked: true, messages: [userMsg({ unanswered: true })] });
    await mountSurface();
    expect(screen.getByText("Not answered")).toBeInTheDocument();
    const sr = screen.getByText("No reply was started");
    expect(sr.className).toContain("sr-only");
  });

  it("does not flag an ordinary user bubble", async () => {
    setWs({ messages: [userMsg()] });
    await mountSurface();
    expect(screen.queryByText("Not answered")).toBeNull();
  });
});
