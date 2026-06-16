import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, within } from "@testing-library/react";
import type { ConversationWithPreview } from "@/hooks/use-conversations";

// RED phase for plan 2026-04-29-feat-command-center-conversation-nav.
//
// Phase 2 + Phase 3 combined: layout shape AND rail behaviour. The plan
// explicitly notes Phase 2's GREEN is deferred until Phase 3 lands the
// rail (tasks.md 2.4); here we land both at once because the layout
// imports the rail and typecheck would otherwise break between phases.

// next/navigation: useParams + useRouter for active-row + footer link.
const { paramsMock, pushMock } = vi.hoisted(() => ({
  paramsMock: vi.fn<() => Record<string, string>>(() => ({})),
  pushMock: vi.fn(),
}));
vi.mock("next/navigation", () => ({
  useParams: paramsMock,
  useRouter: () => ({ push: pushMock }),
  usePathname: () => "/dashboard/chat/conv-1",
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn().mockResolvedValue({
    auth: { getUser: vi.fn().mockResolvedValue({ data: { user: null }, error: null }) },
  }),
}));
vi.mock("@/lib/feature-flags/server", () => ({
  isByokDelegationsEnabled: vi.fn().mockResolvedValue(false),
}));
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentOrganizationId: vi.fn().mockResolvedValue(null),
  resolveCurrentWorkspaceId: vi.fn().mockImplementation((userId: string) => Promise.resolve(userId)),
}));
vi.mock("@/server/byok-delegation-ui-resolver", () => ({
  resolveGranteeDelegation: vi.fn().mockResolvedValue(null),
  resolveGranteeAcceptanceStatus: vi.fn().mockResolvedValue({ accepted: false, acceptedAt: null, sideLetterVersion: null }),
}));

// useConversations is mocked to control the row set the rail receives.
const { useConversationsMock } = vi.hoisted(() => ({
  useConversationsMock: vi.fn(),
}));
vi.mock("@/hooks/use-conversations", async (importOriginal) => {
  const actual = await importOriginal<
    typeof import("@/hooks/use-conversations")
  >();
  return {
    ...actual,
    useConversations: useConversationsMock,
  };
});

function makeConversation(
  overrides: Partial<ConversationWithPreview> = {},
): ConversationWithPreview {
  return {
    id: "conv-1",
    user_id: "user-1",
    repo_url: "https://github.com/acme/repo",
    domain_leader: "cto",
    session_id: null,
    status: "active",
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: new Date().toISOString(),
    created_at: new Date().toISOString(),
    archived_at: null,
    title: "Test conversation",
    preview: null,
    lastMessageLeader: null,
    ...overrides,
  };
}

function setRailHook(
  conversations: ConversationWithPreview[],
  overrides: Partial<{ loading: boolean; error: string | null }> = {},
) {
  useConversationsMock.mockReturnValue({
    conversations,
    loading: overrides.loading ?? false,
    error: overrides.error ?? null,
    refetch: vi.fn(),
    archiveConversation: vi.fn(),
    unarchiveConversation: vi.fn(),
    updateStatus: vi.fn(),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  paramsMock.mockReturnValue({});
  setRailHook([]);
  localStorage.clear();
});

afterEach(() => {
  cleanup();
});

describe("ChatLayout (server component shell)", () => {
  it("portals <ConversationsRail /> into the rail slot, alongside its children (ADR-047)", async () => {
    paramsMock.mockReturnValue({ conversationId: "conv-1" });
    setRailHook([makeConversation({ id: "conv-1", title: "Hello" })]);

    const { default: ChatLayout } = await import(
      "@/app/(dashboard)/dashboard/chat/layout"
    );
    const { RailSlotHarness } = await import("./helpers/rail-slot-harness");

    const children = <div data-testid="chat-page">child</div>;
    // The rail no longer lives in a sibling <aside>; it is portaled into the
    // single nav rail's slot. The harness supplies a slot node so the portal
    // resolves in isolation.
    render(<RailSlotHarness>{await ChatLayout({ children })}</RailSlotHarness>);

    expect(screen.getByTestId("conversations-rail")).toBeInTheDocument();
    expect(screen.getByTestId("chat-page")).toBeInTheDocument();
  });
});

describe("ConversationsRail", () => {
  // The "≤15 rows" cap is enforced by `useConversations({ limit: 15 })`
  // at the data layer — see `use-conversations-limit.test.tsx` for the
  // hook→Supabase contract assertion. The rail trusts the hook contract
  // and renders whatever it returns; layering a defensive `.slice(0, 15)`
  // on top would be Speculative Generality (code-quality F2 in PR #3021
  // review). This file therefore covers rail behaviour only — render
  // shape, active-row, footer link, empty state, badge labels, collapse —
  // with the hook mocked to return the desired row count per test.

  it("renders all rows the hook returns (rail trusts the limit contract)", async () => {
    const rows = Array.from({ length: 5 }, (_, i) =>
      makeConversation({ id: `conv-${i}`, title: `Row ${i}` }),
    );
    setRailHook(rows);

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    render(<ConversationsRail />);

    const rendered = screen.getAllByRole("link", { name: /Row \d+/ });
    expect(rendered).toHaveLength(5);
  });

  it("marks the active row with aria-current='page' (matches useParams.conversationId)", async () => {
    paramsMock.mockReturnValue({ conversationId: "conv-active" });
    setRailHook([
      makeConversation({ id: "conv-other", title: "Other" }),
      makeConversation({ id: "conv-active", title: "Active one" }),
    ]);

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    render(<ConversationsRail />);

    const active = screen.getByRole("link", { name: /Active one/ });
    expect(active).toHaveAttribute("aria-current", "page");

    const other = screen.getByRole("link", { name: /Other/ });
    expect(other).not.toHaveAttribute("aria-current", "page");
  });

  it("renders a persistent '+ New conversation' affordance in the header when conversations exist (AC1)", async () => {
    // The rail's ONLY new-conversation entry point used to be the empty-state
    // CTA, which vanishes the moment one conversation exists. A persistent
    // header affordance must be present even with a non-empty list.
    setRailHook([makeConversation({ id: "c1", title: "Existing one" })]);

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    render(<ConversationsRail />);

    const newConv = screen.getByRole("link", { name: "New conversation" });
    expect(newConv).toHaveAttribute("href", "/dashboard/chat/new");
  });

  it("does NOT render the '+ New conversation' affordance when collapsed (AC2)", async () => {
    // The whole rail is DOM-removed when collapsed (returns null before the
    // header), so the affordance must be absent — the both-toggle-states check.
    setRailHook([makeConversation({ id: "c1", title: "Row alpha" })]);

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    const { RailCollapsedProvider } = await import(
      "@/components/dashboard/rail-slot"
    );
    render(
      <RailCollapsedProvider value={true}>
        <ConversationsRail />
      </RailCollapsedProvider>,
    );

    expect(
      screen.queryByRole("link", { name: "New conversation" }),
    ).not.toBeInTheDocument();
  });

  it("renders 'View all in Dashboard' footer link to /dashboard", async () => {
    setRailHook([makeConversation()]);

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    render(<ConversationsRail />);

    const link = screen.getByRole("link", {
      name: /view all in dashboard/i,
    });
    expect(link).toHaveAttribute("href", "/dashboard");
  });

  it("renders a labeled empty-state CTA (never a blank rail) when there are zero rows (AC6)", async () => {
    setRailHook([]);

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    render(<ConversationsRail />);

    const empty = screen.getByTestId("conversations-rail-empty");
    expect(empty).toHaveTextContent(/no conversations yet/i);
    const cta = within(empty).getByRole("link", { name: /start one/i });
    expect(cta).toHaveAttribute("href", "/dashboard/chat/new");
  });

  it("renders a retryable error state (NOT the empty CTA) when the hook reports an error with no rows", async () => {
    // Transient /api/workspace/active-repo failure: the hook sets `error` and
    // returns an empty list. The rail must NOT show "No conversations yet —
    // Start one" (which reads as "you have no conversations" — a lie when the
    // list merely failed to load). See review: user-impact FINDING 1.
    setRailHook([], { error: "Failed to resolve the active repository" });

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    render(<ConversationsRail />);

    const errorState = screen.getByTestId("conversations-rail-error");
    expect(errorState).toHaveTextContent(/couldn.t load conversations/i);
    expect(within(errorState).getByRole("button", { name: /retry/i })).toBeInTheDocument();
    // The misleading empty CTA must be absent on the error path.
    expect(screen.queryByTestId("conversations-rail-empty")).not.toBeInTheDocument();
  });

  it("keeps rendering last-known rows when a refetch errors (failed refetch never blanks the rail)", async () => {
    setRailHook([makeConversation({ id: "c1", title: "Kept row" })], {
      error: "Failed to resolve the active repository",
    });

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    render(<ConversationsRail />);

    expect(screen.getByRole("link", { name: /Kept row/ })).toBeInTheDocument();
    expect(screen.queryByTestId("conversations-rail-error")).not.toBeInTheDocument();
    expect(screen.queryByTestId("conversations-rail-empty")).not.toBeInTheDocument();
  });

  it("renders the inline status badge with founder-language labels", async () => {
    setRailHook([
      makeConversation({ id: "c1", title: "Row alpha", status: "waiting_for_user" }),
      makeConversation({ id: "c2", title: "Row beta", status: "active" }),
      makeConversation({ id: "c3", title: "Row gamma", status: "completed" }),
      makeConversation({ id: "c4", title: "Row delta", status: "failed" }),
    ]);

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    render(<ConversationsRail />);

    // Plan-specified rail mapping (distinct from STATUS_LABELS used by /dashboard).
    expect(screen.getByText("Needs your decision")).toBeInTheDocument();
    expect(screen.getByText("In progress")).toBeInTheDocument();
    expect(screen.getByText("Done")).toBeInTheDocument();
    expect(screen.getByText("Needs attention")).toBeInTheDocument();
  });

  // AC2 — when the unified rail is collapsed, the rich conversation rows are
  // DOM-removed (they have no coherent icon-only form at 56px) so they cannot
  // clip. The stable `conversations-rail` wrapper lives in the portal component
  // (unchanged); here we assert the rows themselves leave the DOM.
  it("DOM-removes the conversation rows when collapsed (AC2)", async () => {
    setRailHook([
      makeConversation({ id: "c1", title: "Row alpha" }),
      makeConversation({ id: "c2", title: "Row beta" }),
      makeConversation({ id: "c3", title: "Row gamma" }),
    ]);

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    const { RailCollapsedProvider } = await import(
      "@/components/dashboard/rail-slot"
    );
    render(
      <RailCollapsedProvider value={true}>
        <ConversationsRail />
      </RailCollapsedProvider>,
    );

    expect(screen.queryByText("Recent conversations")).not.toBeInTheDocument();
    expect(
      screen.queryByRole("link", { name: /Row alpha/ }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("link", { name: /view all in dashboard/i }),
    ).not.toBeInTheDocument();
  });

  // AC4 — expanded (the implicit default of the provider): rows present, so AC2
  // is not satisfied vacuously by an always-empty rail.
  it("keeps the conversation rows present when expanded (AC4)", async () => {
    setRailHook([makeConversation({ id: "c1", title: "Row alpha" })]);

    const { ConversationsRail } = await import(
      "@/components/chat/conversations-rail"
    );
    const { RailCollapsedProvider } = await import(
      "@/components/dashboard/rail-slot"
    );
    render(
      <RailCollapsedProvider value={false}>
        <ConversationsRail />
      </RailCollapsedProvider>,
    );

    expect(screen.getByText("Recent conversations")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Row alpha/ })).toBeInTheDocument();
  });

  // ADR-047: the conversations rail no longer owns a collapse button or ⌘B —
  // the unified nav rail owns collapse (covered in
  // dashboard-sidebar-collapse.test.tsx). The rail just renders the list.
});
