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
  waitFor,
  cleanup,
  act,
} from "@testing-library/react";
import { ShortcutsProvider } from "@/components/command-palette/use-shortcuts";
import { CommandPalette } from "@/components/command-palette/command-palette";

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
  props: Partial<{ isAdmin: boolean; onToggleSidebar: () => void }> = {},
) {
  return render(
    <ShortcutsProvider
      enabled
      isAdmin={props.isAdmin ?? false}
      onToggleSidebar={props.onToggleSidebar ?? (() => {})}
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
async function openAndDrill(parentTestId: "cmd-page-kb" | "cmd-page-workflows") {
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

  it("returns to the root menu via the Back row", async () => {
    await openAndDrill("cmd-page-kb");
    await screen.findByText("README.md");
    fireEvent.click(screen.getByTestId("cmd-back"));
    // Back on root: parent entries visible again, docs gone.
    expect(screen.getByTestId("cmd-page-workflows")).toBeInTheDocument();
    expect(screen.queryByText("README.md")).not.toBeInTheDocument();
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
