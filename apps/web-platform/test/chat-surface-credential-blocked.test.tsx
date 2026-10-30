import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, within, act, fireEvent } from "@testing-library/react";
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

// Stub: the real prompt hides itself via localStorage / Notification state.
vi.mock("@/components/chat/notification-prompt", () => ({
  NotificationPrompt: ({ visible }: { visible: boolean }) =>
    visible ? <div data-testid="notification-prompt" /> : null,
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

  // Mutation guard: re-deriving `blocked` from lastError.code in the surface
  // would disable the composer here. The hook's flag is the only source.
  it.each([
    ["key_invalid", apiKeyInvalid],
    ["byok_key_missing", byokMissing],
  ])(
    "the hook's credentialBlocked flag is the single source: lastError.code=%s with credentialBlocked:false keeps the composer enabled and shows no helper line",
    async (_code, err) => {
      setWs({ lastError: err, credentialBlocked: false });
      await mountSurface();
      expect(screen.getByRole("textbox")).not.toBeDisabled();
      expect(screen.queryByTestId("credential-helper-reconnect")).toBeNull();
      expect(screen.queryByText(/Select Reconnect to continue/)).toBeNull();
    },
  );

  it("the helper status region is always mounted (announced when content appears) and empty when not blocked", async () => {
    setWs();
    const { rerenderSurface } = await mountSurface();
    const region = screen.getByTestId("credential-helper-status");
    expect(region).toHaveAttribute("role", "status");
    expect(region).toHaveAttribute("aria-live", "polite");
    expect(region).toBeEmptyDOMElement();

    setWs({ lastError: apiKeyInvalid, credentialBlocked: true });
    rerenderSurface();
    // Same node, now with content: a live region that was present beforehand.
    expect(screen.getByTestId("credential-helper-status")).toBe(region);
    expect(within(region).getByText(/Select Reconnect to continue/)).toBeInTheDocument();
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
    expect(within(status).getByTestId("credential-helper-reconnect")).toBeInTheDocument();
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
    await userEvent.click(screen.getByTestId("credential-helper-reconnect"));
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

  it("a refused ?msg= first-run send is not consumed: it is retried once the session re-confirms", async () => {
    mockSearchParams.set("msg", "hello from the dashboard");
    try {
      mockSendMessage.mockReturnValueOnce(false);
      setWs({ sessionConfirmed: true, messages: [] });
      const { rerenderSurface } = await mountSurface();
      await vi.waitFor(() => expect(mockSendMessage).toHaveBeenCalledTimes(1));
      expect(mockSendMessage).toHaveBeenLastCalledWith("hello from the dashboard");

      // Session re-confirms (e.g. after Reconnect) -> the message goes out again.
      setWs({ sessionConfirmed: false, messages: [] });
      rerenderSurface();
      setWs({ sessionConfirmed: true, messages: [] });
      rerenderSurface();
      await vi.waitFor(() => expect(mockSendMessage).toHaveBeenCalledTimes(2));
    } finally {
      mockSearchParams.delete("msg");
    }
  });

  it("a ?msg= first-run send refused on the FINAL attempt restores the text into the composer (the param is already stripped)", async () => {
    mockSearchParams.set("msg", "do not lose me");
    try {
      mockSendMessage.mockReturnValue(false);
      setWs({ sessionConfirmed: true, messages: [] });
      const { rerenderSurface } = await mountSurface();
      await vi.waitFor(() => expect(mockSendMessage).toHaveBeenCalledTimes(1));
      expect(screen.getByRole("textbox")).toHaveValue("");

      // Session re-confirms -> the one re-arm (final attempt) is refused too.
      setWs({ sessionConfirmed: false, messages: [] });
      rerenderSurface();
      setWs({ sessionConfirmed: true, messages: [] });
      rerenderSurface();
      await vi.waitFor(() => expect(mockSendMessage).toHaveBeenCalledTimes(2));
      await vi.waitFor(() => expect(screen.getByRole("textbox")).toHaveValue("do not lose me"));
    } finally {
      mockSendMessage.mockReset();
      mockSendMessage.mockImplementation(() => true);
      mockSearchParams.delete("msg");
    }
  });

  // A dropped gate/prompt response must leave the card actionable.
  describe("optimistic card resolution follows the send result", () => {
    const askUser = (): ChatMessage =>
      ({
        id: "ip-1",
        role: "assistant",
        content: "",
        type: "interactive_prompt",
        promptId: "pr-1",
        conversationId: "test-id",
        promptKind: "ask_user",
        promptPayload: { question: "Proceed?", options: ["Yes", "No"], multiSelect: false },
      }) as ChatMessage;

    it("does NOT resolve the interactive prompt when the response was not sent", async () => {
      const send = vi.fn(() => false);
      const resolve = vi.fn();
      setWs({
        realConversationId: "test-id",
        messages: [userMsg(), askUser()],
        sendInteractivePromptResponse: send,
        resolveInteractivePrompt: resolve,
      });
      await mountSurface({ conversationId: "test-id" });
      await userEvent.click(screen.getByRole("button", { name: "Yes" }));
      expect(send).toHaveBeenCalledTimes(1);
      expect(resolve).not.toHaveBeenCalled();
    });

    it("resolves the interactive prompt when the response was sent", async () => {
      const send = vi.fn(() => true);
      const resolve = vi.fn();
      setWs({
        realConversationId: "test-id",
        messages: [userMsg(), askUser()],
        sendInteractivePromptResponse: send,
        resolveInteractivePrompt: resolve,
      });
      await mountSurface({ conversationId: "test-id" });
      await userEvent.click(screen.getByRole("button", { name: "Yes" }));
      expect(resolve).toHaveBeenCalledTimes(1);
    });
  });

  // The 'Session Failed to Start' card's Reconnect must re-run the start/resume
  // effect (reset sessionStarted), or a NON-refusal resume failure (transient
  // "Auth probe failed" falls through, the rebind stays armed) is unrecoverable.
  it("a non-refusal resume failure: the session-timeout card's Reconnect resumes the captured id again", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    try {
      setWs({ sessionConfirmed: true, messages: [userMsg()] });
      const { rerenderSurface } = await mountSurface();
      expect(mockStartSession).toHaveBeenCalledTimes(1);

      // Credential Reconnect -> resume_session #1 for the captured id.
      setWs({
        lastError: apiKeyInvalid,
        credentialBlocked: true,
        rebindConversationId: CONV,
        sessionConfirmed: false,
        messages: [userMsg({ unanswered: true })],
      });
      rerenderSurface();
      fireEvent.click(within(screen.getByRole("alert")).getByRole("button", { name: "Reconnect" }));
      expect(mockResumeSession).toHaveBeenCalledTimes(1);
      expect(mockResumeSession).toHaveBeenLastCalledWith(CONV);

      // Transient error (not a refusal): hook leaves the id captured, no session_started.
      setWs({ lastError: null, credentialBlocked: false, rebindConversationId: CONV, sessionConfirmed: false, messages: [userMsg({ unanswered: true })] });
      rerenderSurface();
      await act(async () => {
        vi.advanceTimersByTime(10_500);
      });
      expect(screen.getByText("Session Failed to Start")).toBeInTheDocument();

      fireEvent.click(within(screen.getByText("Session Failed to Start").closest('[role="alert"]') as HTMLElement).getByRole("button", { name: "Reconnect" }));
      expect(mockReconnect).toHaveBeenCalledTimes(2);
      expect(mockResumeSession).toHaveBeenCalledTimes(2);
      expect(mockResumeSession).toHaveBeenLastCalledWith(CONV);
      expect(mockStartSession).toHaveBeenCalledTimes(1);
    } finally {
      vi.useRealTimers();
    }
  });

  // A refused gate / disclosure / prompt response keeps the card actionable AND
  // says why (role="alert"); no "Selected:" text, no notification prompt.
  describe("refused response feedback", () => {
    const gateMsg = (): ChatMessage =>
      ({
        id: "gate-1",
        role: "assistant",
        content: "",
        type: "review_gate",
        gateId: "g-1",
        question: "Ship it?",
        options: ["Approve", "Reject"],
      }) as ChatMessage;
    const disclosureMsg = (): ChatMessage =>
      ({
        id: "ad-1",
        role: "assistant",
        content: "",
        type: "autonomous_disclosure",
        gateId: "ad-g-1",
        existingWorkspace: false,
      }) as ChatMessage;
    const askUser = (): ChatMessage =>
      ({
        id: "ip-9",
        role: "assistant",
        content: "",
        type: "interactive_prompt",
        promptId: "pr-9",
        conversationId: "test-id",
        promptKind: "ask_user",
        promptPayload: { question: "Proceed?", options: ["Yes", "No"], multiSelect: false },
      }) as ChatMessage;
    const REFUSAL = "Couldn't send. Reconnect, then choose again.";

    it("review gate: refused send -> buttons re-enabled, no 'Selected:', refusal alert, NO notification prompt", async () => {
      const send = vi.fn(() => false);
      setWs({ realConversationId: "test-id", messages: [userMsg(), gateMsg()], sendReviewGateResponse: send });
      await mountSurface({ conversationId: "test-id" });
      await userEvent.click(screen.getByRole("button", { name: "Approve" }));
      expect(send).toHaveBeenCalledWith("g-1", "Approve");
      expect(screen.getByRole("alert")).toHaveTextContent(REFUSAL);
      expect(screen.getByRole("button", { name: "Approve" })).not.toBeDisabled();
      expect(screen.getByRole("button", { name: "Reject" })).not.toBeDisabled();
      expect(screen.queryByText(/Selected:/)).toBeNull();
      // Mutation guard for the `=== false` check in handleReviewGateResponse.
      expect(screen.queryByTestId("notification-prompt")).toBeNull();
    });

    it("review gate: a delivered send shows the notification prompt (positive control)", async () => {
      const send = vi.fn(() => true);
      setWs({ realConversationId: "test-id", messages: [userMsg(), gateMsg()], sendReviewGateResponse: send });
      await mountSurface({ conversationId: "test-id" });
      await userEvent.click(screen.getByRole("button", { name: "Approve" }));
      expect(screen.getByTestId("notification-prompt")).toBeInTheDocument();
      expect(screen.queryByText(REFUSAL)).toBeNull();
    });

    it("autonomous disclosure: refused send -> alert, banner stays actionable", async () => {
      const send = vi.fn(() => false);
      setWs({ realConversationId: "test-id", messages: [userMsg(), disclosureMsg()], sendAutonomousDisclosureResponse: send });
      await mountSurface({ conversationId: "test-id" });
      await userEvent.click(screen.getByRole("button", { name: "Got it" }));
      expect(send).toHaveBeenCalledWith("ad-g-1", "Got it");
      expect(screen.getByRole("alert")).toHaveTextContent(REFUSAL);
      expect(screen.getByRole("button", { name: "Got it" })).not.toBeDisabled();
    });

    it("interactive prompt: refused send -> alert, options stay actionable", async () => {
      const send = vi.fn(() => false);
      setWs({ realConversationId: "test-id", messages: [userMsg(), askUser()], sendInteractivePromptResponse: send });
      await mountSurface({ conversationId: "test-id" });
      await userEvent.click(screen.getByRole("button", { name: "Yes" }));
      expect(screen.getByRole("alert")).toHaveTextContent(REFUSAL);
      expect(screen.getByRole("button", { name: "Yes" })).not.toBeDisabled();
    });
  });
});
