import {
  describe,
  it,
  expect,
  vi,
  beforeEach,
  afterEach,
} from "vitest";
import {
  render,
  screen,
  fireEvent,
  createEvent,
  waitFor,
  cleanup,
  act,
} from "@testing-library/react";
import { ShortcutsProvider } from "@/components/command-palette/use-shortcuts";
import { CommandPalette } from "@/components/command-palette/command-palette";
import { HelpOverlay } from "@/components/command-palette/help-overlay";

// next/navigation router — capture push() for navigate-effect assertions.
const routerPush = vi.hoisted(() => vi.fn());
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: routerPush, replace: vi.fn(), prefetch: vi.fn() }),
}));

// Observability — assert the strict non-409 failure path reports to Sentry.
const reportSilentFallback = vi.hoisted(() => vi.fn());
vi.mock("@/lib/client-observability", () => ({ reportSilentFallback }));

const KB_TREE = {
  tree: {
    name: "kb",
    type: "directory",
    children: [
      { name: "README.md", type: "file", path: "README.md" },
      {
        name: "guides",
        type: "directory",
        children: [
          { name: "onboarding.md", type: "file", path: "guides/onboarding.md" },
        ],
      },
    ],
  },
  needsReconnect: false,
};

const PROTECTED_ROUTINE = {
  fnId: "cron-content-publisher",
  description: "Publishes content.",
  domain: "Marketing",
  ownerRole: "CMO",
  scheduleLabel: "Daily 14:00 UTC",
  manualTrigger: "confirm",
  lastRun: null,
};
const ALLOWED_ROUTINE = {
  fnId: "cron-daily-triage",
  description: "Triages issues.",
  domain: "Operations",
  ownerRole: "COO",
  scheduleLabel: "Daily 04:00 UTC",
  manualTrigger: "allowed",
  lastRun: { status: "completed", started_at: new Date().toISOString() },
};

function mockFetch(opts: {
  kb?: unknown;
  kbStatus?: number;
  routines?: unknown[];
  runStatus?: number;
  runError?: string;
} = {}) {
  return vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    if (url.includes("/api/dashboard/routines/run") && init?.method === "POST") {
      const status = opts.runStatus ?? 202;
      return {
        ok: status < 400,
        status,
        json: async () => ({
          dispatched: "evt",
          error: opts.runError ?? "confirmation_required",
        }),
      } as Response;
    }
    if (url.includes("/api/dashboard/routines")) {
      return {
        ok: true,
        status: 200,
        json: async () => ({
          routines: opts.routines ?? [ALLOWED_ROUTINE, PROTECTED_ROUTINE],
        }),
      } as Response;
    }
    // /api/kb/tree
    const kbStatus = opts.kbStatus ?? 200;
    return {
      ok: kbStatus < 400,
      status: kbStatus,
      json: async () => opts.kb ?? KB_TREE,
    } as Response;
  });
}

function renderPalette(
  props: Partial<{
    isAdmin: boolean;
    enabled: boolean;
    onToggleSidebar: () => void;
    onEscape: () => void;
  }> = {},
) {
  return render(
    <ShortcutsProvider
      enabled={props.enabled ?? true}
      isAdmin={props.isAdmin ?? false}
      onToggleSidebar={props.onToggleSidebar ?? (() => {})}
      onEscape={props.onEscape}
    >
      <input data-testid="outside-input" />
      <CommandPalette />
    </ShortcutsProvider>,
  );
}

function pressKey(
  key: string,
  opts: { meta?: boolean; target?: Element | Document } = {},
) {
  act(() => {
    fireEvent.keyDown(opts.target ?? document.body, {
      key,
      metaKey: opts.meta ?? false,
    });
  });
}

// Like pressKey but returns the dispatched event so `ev.defaultPrevented` (the
// preventDefault flag) is assertable. `fireEvent` self-wraps in act, so the act
// wrap flushes runEffect's state update — it is NOT what makes the boolean
// readable (that is synchronous). Reads the flag directly (test-design review).
function pressKeyEvent(
  key: string,
  opts: {
    meta?: boolean;
    ctrl?: boolean;
    shift?: boolean;
    target?: Element | Document;
  } = {},
) {
  const target = opts.target ?? document.body;
  const ev = createEvent.keyDown(target, {
    key,
    metaKey: opts.meta ?? false,
    ctrlKey: opts.ctrl ?? false,
    shiftKey: opts.shift ?? false,
  });
  act(() => {
    fireEvent(target, ev);
  });
  return ev;
}

beforeEach(() => {
  routerPush.mockClear();
  reportSilentFallback.mockClear();
  // cmdk calls scrollIntoView on selection; happy-dom lacks it.
  Element.prototype.scrollIntoView = vi.fn();
  vi.stubGlobal("fetch", mockFetch());
  try {
    localStorage.clear();
  } catch {
    /* ignore */
  }
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("CommandPalette — open / suppression", () => {
  it("opens on ⌘K from the body and shows the dense groups", async () => {
    renderPalette();
    pressKey("k", { meta: true });
    expect(
      await screen.findByLabelText("Command palette search"),
    ).toBeInTheDocument();
    expect(screen.getByText("Dashboard")).toBeInTheDocument();
    expect(screen.getByText("Inbox")).toBeInTheDocument();
    // Ask-an-agent hero is always present.
    expect(screen.getByTestId("cmd-ask-agent")).toBeInTheDocument();
  });

  it("does NOT open when focus is in an editable element (⌘K suppressed)", () => {
    renderPalette();
    const input = screen.getByTestId("outside-input");
    pressKey("k", { meta: true, target: input });
    expect(
      screen.queryByLabelText("Command palette search"),
    ).not.toBeInTheDocument();
  });

  it("admin-gates the Analytics nav item to isAdmin", async () => {
    const { unmount } = renderPalette({ isAdmin: false });
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    expect(screen.queryByText("Analytics")).not.toBeInTheDocument();
    unmount();

    renderPalette({ isAdmin: true });
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    expect(screen.getByText("Analytics")).toBeInTheDocument();
  });
});

describe("CommandPalette — direct shortcut hints (FR3/AC4)", () => {
  it("renders the go-to key hint on each nav row and G C on the ask hero", async () => {
    renderPalette();
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    // Each nav row shows its `G <letter>` hint.
    expect(screen.getByText("G D")).toBeInTheDocument(); // Dashboard
    expect(screen.getByText("G I")).toBeInTheDocument(); // Inbox
    expect(screen.getByText("G W")).toBeInTheDocument(); // Workstream
    expect(screen.getByText("G K")).toBeInTheDocument(); // Knowledge Base
    expect(screen.getByText("G R")).toBeInTheDocument(); // Routines
    // The ask hero shows its GLOBAL summon binding, not the palette-only ⌘↵.
    const ask = screen.getByTestId("cmd-ask-agent");
    expect(ask).toHaveTextContent("G C");
    expect(ask).not.toHaveTextContent("⌘↵");
  });

  it("omits the Analytics row + hint for a non-admin, shows G A for an admin", async () => {
    const { unmount } = renderPalette({ isAdmin: false });
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    expect(screen.queryByText("Analytics")).not.toBeInTheDocument();
    expect(screen.queryByText("G A")).not.toBeInTheDocument();
    unmount();

    renderPalette({ isAdmin: true });
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    expect(screen.getByText("Analytics")).toBeInTheDocument();
    expect(screen.getByText("G A")).toBeInTheDocument();
  });
});

describe("CommandPalette — direct go-to sequences (FR1/FR2/AC2/AC3/AC9)", () => {
  it("navigates on `g` then `d`", () => {
    renderPalette();
    pressKey("g");
    pressKey("d");
    expect(routerPush).toHaveBeenCalledWith("/dashboard");
  });

  it("routes every mapped second key, including `g c` → chat", () => {
    renderPalette();
    for (const [k, href] of [
      ["i", "/dashboard/inbox"],
      ["w", "/dashboard/workstream"],
      ["k", "/dashboard/kb"],
      ["r", "/dashboard/routines"],
      ["c", "/dashboard/chat/new"],
    ] as const) {
      routerPush.mockClear();
      pressKey("g");
      pressKey(k);
      expect(routerPush).toHaveBeenCalledWith(href);
    }
  });

  it("`g` then Escape aborts the prefix and SWALLOWS Escape (drawer not closed, AC9)", () => {
    const onEscape = vi.fn();
    renderPalette({ onEscape });
    pressKey("g");
    pressKey("Escape");
    expect(routerPush).not.toHaveBeenCalled();
    // The swallowed Escape must NOT fall through to the drawer-close handler…
    expect(onEscape).not.toHaveBeenCalled();
    // …but a bare Escape (no pending prefix) still closes the drawer.
    pressKey("Escape");
    expect(onEscape).toHaveBeenCalledTimes(1);
  });

  it("`g` then a chord (⌘K) still opens the palette (listener fall-through)", async () => {
    renderPalette();
    pressKey("g");
    pressKey("k", { meta: true });
    expect(
      await screen.findByLabelText("Command palette search"),
    ).toBeInTheDocument();
    expect(routerPush).not.toHaveBeenCalled();
  });

  it("a lone modifier keydown mid-sequence does not break `g` … `d`", () => {
    renderPalette();
    pressKey("g");
    pressKey("Shift");
    pressKey("d");
    expect(routerPush).toHaveBeenCalledWith("/dashboard");
  });

  it("does not arm while focus is in an editable element", () => {
    renderPalette();
    const input = screen.getByTestId("outside-input");
    pressKey("g", { target: input });
    pressKey("d", { target: input });
    expect(routerPush).not.toHaveBeenCalled();
  });

  it("`g` then an unmapped key aborts, and a fresh `g d` still works", () => {
    renderPalette();
    pressKey("g");
    pressKey("x");
    expect(routerPush).not.toHaveBeenCalled();
    pressKey("g");
    pressKey("d");
    expect(routerPush).toHaveBeenCalledWith("/dashboard");
  });

  it("navigates when the second key lands within the 1500ms window", () => {
    vi.useFakeTimers();
    try {
      renderPalette();
      pressKey("g");
      vi.advanceTimersByTime(1400);
      pressKey("d");
      expect(routerPush).toHaveBeenCalledWith("/dashboard");
    } finally {
      vi.useRealTimers();
    }
  });

  it("expires the prefix when the second key comes after the 1500ms window", () => {
    vi.useFakeTimers();
    try {
      renderPalette();
      pressKey("g");
      vi.advanceTimersByTime(1600);
      pressKey("d");
      expect(routerPush).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });

  it("does not arm while an app modal (role=dialog aria-modal) is open", () => {
    renderPalette();
    // Simulate an open app modal (e.g. new-issue-dialog) — a go-sequence fired
    // from a button inside it must NOT navigate away and discard unsaved input.
    const modal = document.createElement("div");
    modal.setAttribute("role", "dialog");
    modal.setAttribute("aria-modal", "true");
    document.body.appendChild(modal);
    try {
      pressKey("g");
      pressKey("d");
      expect(routerPush).not.toHaveBeenCalled();
    } finally {
      document.body.removeChild(modal);
    }
  });

  it("admin-gates `g a`: inert for a non-admin, navigates for an admin", () => {
    const { unmount } = renderPalette({ isAdmin: false });
    pressKey("g");
    pressKey("a");
    expect(routerPush).not.toHaveBeenCalled();
    unmount();

    renderPalette({ isAdmin: true });
    pressKey("g");
    pressKey("a");
    expect(routerPush).toHaveBeenCalledWith("/dashboard/admin/analytics");
  });

  it("is inert when shortcutsEnabled=false (WCAG turn-off)", async () => {
    localStorage.setItem("soleur:shortcuts.enabled", "0");
    renderPalette();
    await act(async () => {});
    pressKey("g");
    pressKey("d");
    expect(routerPush).not.toHaveBeenCalled();
  });

  it("is inert when the command-palette flag is off (enabled=false)", () => {
    renderPalette({ enabled: false });
    pressKey("g");
    pressKey("d");
    expect(routerPush).not.toHaveBeenCalled();
  });
});

describe("CommandPalette — Super/Meta accelerators (⌘D/⌘I/⌘R/⌘A/⌘C)", () => {
  // AC7 — meta+letter navigates AND cancels the native action (preventDefault).
  it.each([
    ["d", "/dashboard"],
    ["i", "/dashboard/inbox"],
    ["r", "/dashboard/routines"],
  ] as const)("⌘%s navigates to %s and cancels the native action", (k, href) => {
    routerPush.mockClear();
    renderPalette();
    const ev = pressKeyEvent(k, { meta: true });
    expect(routerPush).toHaveBeenCalledWith(href);
    expect(ev.defaultPrevented).toBe(true);
  });

  // AC7b — ⌘C yields to native copy when a non-empty selection exists.
  it("⌘C with NO selection opens chat and cancels", () => {
    vi.stubGlobal("getSelection", () => ({
      isCollapsed: true,
      toString: () => "",
    }));
    renderPalette();
    const ev = pressKeyEvent("c", { meta: true });
    expect(routerPush).toHaveBeenCalledWith("/dashboard/chat/new");
    expect(ev.defaultPrevented).toBe(true);
  });

  it("⌘C with an active non-editable selection yields to native copy (not canceled)", () => {
    vi.stubGlobal("getSelection", () => ({
      isCollapsed: false,
      toString: () => "picked text",
    }));
    renderPalette();
    const ev = pressKeyEvent("c", { meta: true });
    expect(routerPush).not.toHaveBeenCalled();
    expect(ev.defaultPrevented).toBe(false);
  });

  // AC8 — admin gate owns ⌘A: inert (native select-all preserved) for a
  // non-admin; navigates + cancels for an admin.
  it("⌘A is inert (native select-all preserved) for a non-admin", () => {
    renderPalette({ isAdmin: false });
    const ev = pressKeyEvent("a", { meta: true });
    expect(routerPush).not.toHaveBeenCalled();
    expect(ev.defaultPrevented).toBe(false);
  });

  it("⌘A navigates to Analytics and cancels for an admin", () => {
    renderPalette({ isAdmin: true });
    const ev = pressKeyEvent("a", { meta: true });
    expect(routerPush).toHaveBeenCalledWith("/dashboard/admin/analytics");
    expect(ev.defaultPrevented).toBe(true);
  });

  // AC9 — suppression matrix. Each condition: ⌘D is inert (no routerPush).
  it("is inert when focus is in an editable element (native ⌘D preserved)", () => {
    renderPalette();
    const input = screen.getByTestId("outside-input");
    pressKeyEvent("d", { meta: true, target: input });
    expect(routerPush).not.toHaveBeenCalled();
  });

  it("is inert while an app modal (role=dialog aria-modal) is open", () => {
    renderPalette();
    const modal = document.createElement("div");
    modal.setAttribute("role", "dialog");
    modal.setAttribute("aria-modal", "true");
    document.body.appendChild(modal);
    try {
      const ev = pressKeyEvent("d", { meta: true });
      expect(routerPush).not.toHaveBeenCalled();
      // Native action preserved under a modal (we did not preventDefault).
      expect(ev.defaultPrevented).toBe(false);
    } finally {
      document.body.removeChild(modal);
    }
  });

  it("is inert while the palette is open (focus on body proves the guard)", async () => {
    renderPalette();
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    routerPush.mockClear();
    pressKeyEvent("d", { meta: true });
    expect(routerPush).not.toHaveBeenCalled();
  });

  it("is inert while the help overlay is open (focus on body proves the guard)", async () => {
    render(
      <ShortcutsProvider enabled isAdmin={false} onToggleSidebar={() => {}}>
        <HelpOverlay />
        <CommandPalette />
      </ShortcutsProvider>,
    );
    pressKey("/", { meta: true });
    await screen.findByLabelText("Search keyboard shortcuts");
    routerPush.mockClear();
    pressKeyEvent("d", { meta: true });
    expect(routerPush).not.toHaveBeenCalled();
  });

  it("is inert when the command-palette flag is off (enabled=false)", () => {
    renderPalette({ enabled: false });
    pressKeyEvent("d", { meta: true });
    expect(routerPush).not.toHaveBeenCalled();
  });

  it("is inert when shortcutsEnabled=false (WCAG turn-off)", async () => {
    localStorage.setItem("soleur:shortcuts.enabled", "0");
    renderPalette();
    await act(async () => {});
    pressKeyEvent("d", { meta: true });
    expect(routerPush).not.toHaveBeenCalled();
  });

  // AC10 — precedence: resolveShortcut wins ⌘K; the g-leader still works.
  it("⌘K still opens the palette (not intercepted by resolveNavChord)", async () => {
    renderPalette();
    pressKey("k", { meta: true });
    expect(
      await screen.findByLabelText("Command palette search"),
    ).toBeInTheDocument();
    expect(routerPush).not.toHaveBeenCalled();
  });

  it("`g d` still navigates (g-leader unchanged)", () => {
    renderPalette();
    pressKey("g");
    pressKey("d");
    expect(routerPush).toHaveBeenCalledWith("/dashboard");
  });

  // AC10b — armed-prefix × Super-chord hand-off (real timers). The pre-existing
  // :459 prefix-clear consumes `g` before the accelerator branch runs, so ⌘D
  // navigates exactly once and a subsequent bare `d` does NOT re-navigate.
  it("armed `g` then ⌘D navigates once; a following bare `d` does not re-navigate", () => {
    renderPalette();
    pressKey("g");
    pressKeyEvent("d", { meta: true });
    expect(routerPush).toHaveBeenCalledTimes(1);
    expect(routerPush).toHaveBeenCalledWith("/dashboard");
    pressKeyEvent("d");
    expect(routerPush).toHaveBeenCalledTimes(1);
  });

  it("armed `g` then ⌘K opens the palette (no navigation)", async () => {
    renderPalette();
    pressKey("g");
    pressKey("k", { meta: true });
    expect(
      await screen.findByLabelText("Command palette search"),
    ).toBeInTheDocument();
    expect(routerPush).not.toHaveBeenCalled();
  });
});

describe("CommandPalette — accelerator hint is Apple-only (AC12)", () => {
  it("renders ONLY the g-seq (no accel chip) on happy-dom's non-Apple default", async () => {
    renderPalette();
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    expect(screen.getByText("G D")).toBeInTheDocument(); // Dashboard g-seq
    expect(screen.getByText("G W")).toBeInTheDocument(); // Workstream g-seq
    // No accelerator chip off-mac (would be an unreachable "Ctrl+D").
    expect(screen.queryByText("⌘D")).not.toBeInTheDocument();
  });

  it("renders BOTH ⌘D and G D on Apple; Workstream stays g-seq-only", async () => {
    vi.stubGlobal("navigator", {
      platform: "MacIntel",
      userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
    });
    renderPalette();
    // Provider reads the platform in a mount effect — let it settle.
    await act(async () => {});
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    expect(screen.getByText("⌘D")).toBeInTheDocument(); // Dashboard accel
    expect(screen.getByText("G D")).toBeInTheDocument(); // Dashboard g-seq
    // Workstream has no accel — only its g-seq.
    expect(screen.getByText("G W")).toBeInTheDocument();
    expect(screen.queryByText("⌘W")).not.toBeInTheDocument();
  });
});

describe("CommandPalette — empty state", () => {
  it("shows an 'Ask an agent about <q>' fallback that opens chat with the query", async () => {
    renderPalette();
    pressKey("k", { meta: true });
    const search = await screen.findByLabelText("Command palette search");
    fireEvent.change(search, { target: { value: "refund policy" } });
    const ask = await screen.findByTestId("cmd-ask-agent");
    expect(ask).toHaveTextContent("Ask an agent about “refund policy”");
    fireEvent.click(ask);
    expect(routerPush).toHaveBeenCalledWith(
      "/dashboard/chat/new?q=refund%20policy",
    );
  });
});

// Render, open the palette, and drill into a nested sub-page via its parent
// entry. (Callers stub a custom fetch BEFORE calling this; the drill triggers
// the lazy fetch, so the stub must already be in place.)
async function openAndDrill(
  parentTestId: "cmd-page-kb" | "cmd-page-workflows" | "cmd-page-settings",
) {
  renderPalette();
  pressKey("k", { meta: true });
  await screen.findByLabelText("Command palette search");
  fireEvent.click(screen.getByTestId(parentTestId));
}

describe("CommandPalette — nested pages (submenus)", () => {
  it("shows Knowledge Base + Workflows as single entries on the root (not flat lists)", async () => {
    renderPalette();
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    // Parent entries present…
    expect(screen.getByTestId("cmd-page-kb")).toBeInTheDocument();
    expect(screen.getByTestId("cmd-page-workflows")).toBeInTheDocument();
    // …and the individual docs / routine rows are NOT flat on the root.
    expect(screen.queryByText("README.md")).not.toBeInTheDocument();
    expect(
      screen.queryByTestId("cmd-run-cron-daily-triage"),
    ).not.toBeInTheDocument();
  });

  it("drills into Knowledge Base on Enter/click and lists the docs", async () => {
    await openAndDrill("cmd-page-kb");
    expect(await screen.findByText("README.md")).toBeInTheDocument();
    expect(screen.getByText("onboarding.md")).toBeInTheDocument();
    // A back affordance is present.
    expect(screen.getByTestId("cmd-back")).toBeInTheDocument();
  });

  it("drills into Workflows on Enter/click and lists the routines", async () => {
    await openAndDrill("cmd-page-workflows");
    expect(
      await screen.findByTestId("cmd-run-cron-daily-triage"),
    ).toBeInTheDocument();
    expect(
      screen.getByTestId("cmd-run-cron-content-publisher"),
    ).toBeInTheDocument();
  });

  it("shows Settings as a single drill-in entry, with the settings items NOT flat on the root", async () => {
    renderPalette();
    pressKey("k", { meta: true });
    await screen.findByLabelText("Command palette search");
    // The Settings drill trigger is present on the root…
    expect(screen.getByTestId("cmd-page-settings")).toBeInTheDocument();
    // …but the individual settings destinations are NOT flat on the root.
    expect(screen.queryByText("All settings")).not.toBeInTheDocument();
    expect(screen.queryByText("Billing")).not.toBeInTheDocument();
    expect(screen.queryByText("Audit log")).not.toBeInTheDocument();
  });

  it("drills into Settings on Enter/click and lists the settings items", async () => {
    await openAndDrill("cmd-page-settings");
    expect(
      await screen.findByTestId("cmd-settings-settings:/dashboard/settings"),
    ).toBeInTheDocument();
    expect(screen.getByText("All settings")).toBeInTheDocument();
    expect(screen.getByText("Team")).toBeInTheDocument();
    expect(screen.getByText("Billing")).toBeInTheDocument();
    expect(screen.getByText("Audit log")).toBeInTheDocument();
    expect(screen.getByTestId("cmd-back")).toBeInTheDocument();
  });

  it("navigates to a settings destination on select", async () => {
    await openAndDrill("cmd-page-settings");
    fireEvent.click(await screen.findByText("Team"));
    expect(routerPush).toHaveBeenCalledWith("/dashboard/settings/team");
  });

  it("returns to the root menu via the Back row", async () => {
    await openAndDrill("cmd-page-kb");
    await screen.findByText("README.md");
    fireEvent.click(screen.getByTestId("cmd-back"));
    // Back on root: parent entries visible again, docs gone.
    expect(screen.getByTestId("cmd-page-workflows")).toBeInTheDocument();
    expect(screen.queryByText("README.md")).not.toBeInTheDocument();
  });
});

describe("CommandPalette — loading state", () => {
  it("shows a branded, contextual loading row while the KB tree is in flight", async () => {
    // A fetch that never resolves so the loading phase stays observable.
    vi.stubGlobal(
      "fetch",
      vi.fn(() => new Promise<Response>(() => {})),
    );
    renderPalette();
    pressKey("k", { meta: true });
    fireEvent.click(await screen.findByTestId("cmd-page-kb"));

    const loading = await screen.findByTestId("cmd-kb-loading");
    expect(loading).toHaveTextContent(/loading your knowledge base/i);
    // The bare, unstyled "Searching…" is gone.
    expect(screen.queryByText("Searching…")).toBeNull();
  });

  it("shows a contextual loading row while workflows are in flight", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => new Promise<Response>(() => {})),
    );
    renderPalette();
    pressKey("k", { meta: true });
    fireEvent.click(await screen.findByTestId("cmd-page-workflows"));

    const loading = await screen.findByTestId("cmd-routines-loading");
    expect(loading).toHaveTextContent(/loading your workflows/i);
  });
});

describe("CommandPalette — KB error states", () => {
  it("renders a reconnect row on needsReconnect inside the KB page", async () => {
    vi.stubGlobal(
      "fetch",
      mockFetch({ kb: { tree: { children: [] }, needsReconnect: true } }),
    );
    await openAndDrill("cmd-page-kb");
    expect(await screen.findByTestId("cmd-kb-reconnect")).toBeInTheDocument();
    // The Back row keeps the rest of the palette reachable.
    expect(screen.getByTestId("cmd-back")).toBeInTheDocument();
  });

  it("renders an unavailable row on a 503 KB error", async () => {
    vi.stubGlobal("fetch", mockFetch({ kbStatus: 503 }));
    await openAndDrill("cmd-page-kb");
    expect(await screen.findByTestId("cmd-kb-error")).toBeInTheDocument();
  });
});

describe("CommandPalette — run routine", () => {
  it("runs an allowed routine (202) with no error affordance", async () => {
    await openAndDrill("cmd-page-workflows");
    const row = await screen.findByTestId("cmd-run-cron-daily-triage");
    fireEvent.click(row);
    await waitFor(() =>
      expect(
        screen.queryByTestId("cmd-run-error-cron-daily-triage"),
      ).not.toBeInTheDocument(),
    );
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("shows a confirm modal on 409, then dispatches confirmed:true → 202", async () => {
    // First POST → 409 (protected, unconfirmed); after confirm → 202.
    let posted = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = typeof input === "string" ? input : input.toString();
        if (url.includes("/routines/run") && init?.method === "POST") {
          posted += 1;
          const status = posted === 1 ? 409 : 202;
          return {
            ok: status < 400,
            status,
            json: async () => ({ error: "confirmation_required" }),
          } as Response;
        }
        if (url.includes("/api/dashboard/routines")) {
          return {
            ok: true,
            status: 200,
            json: async () => ({ routines: [PROTECTED_ROUTINE] }),
          } as Response;
        }
        return { ok: true, status: 200, json: async () => KB_TREE } as Response;
      }),
    );
    await openAndDrill("cmd-page-workflows");
    const row = await screen.findByTestId("cmd-run-cron-content-publisher");
    fireEvent.click(row);
    const confirm = await screen.findByTestId("cmd-confirm-run");
    expect(screen.getByTestId("cmd-confirm-modal")).toBeInTheDocument();
    fireEvent.click(confirm);
    await waitFor(() =>
      expect(screen.queryByTestId("cmd-confirm-modal")).not.toBeInTheDocument(),
    );
    expect(posted).toBe(2);
  });

  it("surfaces an inline error AND reports to Sentry on a 502", async () => {
    vi.stubGlobal(
      "fetch",
      mockFetch({
        routines: [ALLOWED_ROUTINE],
        runStatus: 502,
        runError: "dispatch_failed",
      }),
    );
    await openAndDrill("cmd-page-workflows");
    const row = await screen.findByTestId("cmd-run-cron-daily-triage");
    fireEvent.click(row);
    expect(
      await screen.findByTestId("cmd-run-error-cron-daily-triage"),
    ).toBeInTheDocument();
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(reportSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "command-palette.run-routine",
      extra: { fnId: "cron-daily-triage" },
    });
  });
});

describe("CommandPalette — ⌘B migration & WCAG turn-off", () => {
  it("fires onToggleSidebar exactly once on ⌘B (no double-fire)", () => {
    const onToggleSidebar = vi.fn();
    renderPalette({ onToggleSidebar });
    pressKey("b", { meta: true });
    expect(onToggleSidebar).toHaveBeenCalledTimes(1);
  });

  it("disables the WHOLE listener (⌘K AND ⌘B) when shortcutsEnabled=false", async () => {
    localStorage.setItem("soleur:shortcuts.enabled", "0");
    const onToggleSidebar = vi.fn();
    renderPalette({ onToggleSidebar });
    // Provider syncs the pref in a mount effect; let it settle.
    await act(async () => {});
    pressKey("k", { meta: true });
    pressKey("b", { meta: true });
    expect(
      screen.queryByLabelText("Command palette search"),
    ).not.toBeInTheDocument();
    expect(onToggleSidebar).not.toHaveBeenCalled();
  });
});
