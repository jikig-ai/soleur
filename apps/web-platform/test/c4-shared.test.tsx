import { describe, it, expect, vi, beforeEach } from "vitest";
import { act, render, renderHook, screen, fireEvent, waitFor } from "@testing-library/react";

// c4-shared.tsx imports browser-only deps at module top (@likec4/diagram,
// @likec4/core/model, CodeMirror). Stub them so the REAL C4Diagnostics /
// C4CodePanel logic loads under happy-dom without pulling the canvas runtime.
vi.mock("@likec4/diagram", () => ({
  LikeC4ModelProvider: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  LikeC4Diagram: () => <div data-testid="likec4-diagram" />,
  useLikeC4ViewModel: () => null,
}));
vi.mock("@likec4/core/model", () => ({
  LikeC4Model: { create: () => ({}) },
}));
vi.mock("@codemirror/theme-one-dark", () => ({ oneDark: {} }));
vi.mock("@uiw/react-codemirror", () => ({
  default: ({
    value,
    onChange,
  }: {
    value: string;
    onChange?: (v: string) => void;
  }) => (
    <textarea
      data-testid="cm"
      value={value}
      onChange={(e) => onChange?.(e.target.value)}
    />
  ),
}));

import {
  C4Diagnostics,
  C4CodePanel,
  useC4Project,
  type ProjectResponse,
} from "@/components/kb/c4-shared";
import {
  staleActionLine,
  staleOutcomeVerdict,
  CONCIERGE_ACTION_LINE,
  OTHER_DIR_ACTION_LINE,
} from "@/components/kb/c4-diagnostics";

beforeEach(() => {
  vi.restoreAllMocks();
});

// The no-reason line 2 (#8695). Pinned literally here: it is user-facing copy,
// and the only no-diagnostic `rerendered:false` return is a supersede, so it
// must name that and never promise a refresh the page does not perform.
const SUPERSEDED =
  "A newer change to the diagram source was saved before this one was rendered, so this save did not update the diagram. Save again to render the latest version.";
const RATE_LIMIT_DIAG =
  "diagram not updated: GitHub's rate limit for this repository was reached. Save again in a few minutes.";

describe("C4Diagnostics — staleness indicator (Layer 1)", () => {
  it("renders nothing on a fresh load (no diagnostics, not stale)", () => {
    const { container } = render(
      <C4Diagnostics diagnostics={[]} hasModel={true} stale={false} />,
    );
    expect(container).toBeEmptyDOMElement();
    // No false-positive staleness warning on a clean load.
    expect(screen.queryByText(/out of date/i)).toBeNull();
  });

  it("shows the out-of-date warning when stale, even with no diagnostics", () => {
    render(<C4Diagnostics diagnostics={[]} hasModel={true} stale={true} />);
    expect(screen.getByText(/out of date/i)).toBeTruthy();
  });

  it("still renders diagnostics when present and not stale", () => {
    render(
      <C4Diagnostics
        diagnostics={[{ message: "bad ref", line: 3, sourceFsPath: "model.c4" }]}
        hasModel={true}
        stale={false}
      />,
    );
    expect(screen.getByText(/diagram warnings/i)).toBeTruthy();
    expect(screen.getByText(/bad ref/i)).toBeTruthy();
    expect(screen.queryByText(/out of date/i)).toBeNull();
  });
});

describe("C4Diagnostics — stale line 2 states the save diagnostic (#8695)", () => {
  it("(a) with a diagnostic: shows it capitalised, no supersede line, no refresh promise", () => {
    render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleDiagnostic={RATE_LIMIT_DIAG}
      />,
    );
    expect(screen.getByText(/out of date/i)).toBeTruthy();
    expect(
      screen.getByText(
        "Diagram not updated: GitHub's rate limit for this repository was reached. Save again in a few minutes.",
      ),
    ).toBeTruthy();
    expect(screen.queryByText(SUPERSEDED)).toBeNull();
    expect(screen.queryByText(/precomputed/i)).toBeNull();
    expect(screen.queryByText(/will refresh|refreshes/i)).toBeNull();
  });

  it("(b) without a diagnostic: shows the supersede line, no refresh promise", () => {
    render(<C4Diagnostics diagnostics={[]} hasModel={true} stale={true} />);
    expect(screen.getByText(SUPERSEDED)).toBeTruthy();
    expect(screen.queryByText(/will refresh|refreshes|precomputed/i)).toBeNull();
  });

  it("(b') an empty-string or null diagnostic falls back to the supersede line", () => {
    const { rerender } = render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleDiagnostic=""
      />,
    );
    expect(screen.getByText(SUPERSEDED)).toBeTruthy();
    rerender(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleDiagnostic={null}
      />,
    );
    expect(screen.getByText(SUPERSEDED)).toBeTruthy();
  });

  it("(c) not stale with a leftover diagnostic: renders nothing", () => {
    const { container } = render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={false}
        staleDiagnostic={RATE_LIMIT_DIAG}
      />,
    );
    expect(container).toBeEmptyDOMElement();
  });

  it("(d) a diagnostic containing markup renders as literal text, never an element", () => {
    const { container } = render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleDiagnostic="diagram not updated: <script>alert(1)</script><img src=x onerror=alert(2)>"
      />,
    );
    expect(container.querySelector("script")).toBeNull();
    expect(container.querySelector("img")).toBeNull();
    expect(
      screen.getByText(
        "Diagram not updated: <script>alert(1)</script><img src=x onerror=alert(2)>",
      ),
    ).toBeTruthy();
  });
});

// #8740: a model-level diagnostic (the zero-view model) has no source line.
describe("C4Diagnostics — model-level diagnostics carry no line prefix", () => {
  it.each([0, -1])("S1: line %i renders the message alone under the warnings header", (line) => {
    render(
      <C4Diagnostics
        diagnostics={[{ message: "M", line, sourceFsPath: "model.likec4.json" }]}
        hasModel={true}
      />,
    );
    expect(screen.getByText("Diagram warnings")).toBeTruthy();
    expect(screen.queryByText(/Diagram has errors/)).toBeNull();
    const items = screen.getAllByRole("listitem");
    expect(items).toHaveLength(1);
    expect(items[0].textContent).toBe("M");
    expect(screen.queryByText(/line -?\d/)).toBeNull();
  });

  // Line numbers start at 1, so line 1 (a file's first line) must keep its prefix.
  it.each([1, 3])("S2: positive line %i keeps the `line N:` prefix", (line) => {
    render(
      <C4Diagnostics
        diagnostics={[{ message: "bad ref", line, sourceFsPath: "model.c4" }]}
        hasModel={true}
      />,
    );
    expect(screen.getAllByRole("listitem")[0].textContent).toBe(`line ${line}: bad ref`);
  });
});

describe("C4CodePanel — honest save copy (Layer 1)", () => {
  const data: ProjectResponse = {
    dir: "knowledge-base/diagrams",
    sources: { "model.c4": "specification {}" },
    dump: { foo: 1 },
    viewIds: ["index"],
    diagnostics: [],
  };

  it("on a successful re-render: copy says diagram updated, onSaved(true) (Layer 2)", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({
        ok: true,
        json: async () => ({ commitSha: "x", rerendered: true }),
      }) as unknown as typeof fetch;
    const onSaved = vi.fn().mockResolvedValue(undefined);

    render(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={onSaved} />,
    );
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: "model { edited }" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    await waitFor(() => expect(onSaved).toHaveBeenCalledWith(true));
    // The source PUT still fires (no regression to the write path).
    expect(global.fetch).toHaveBeenCalledWith(
      "/api/kb/c4/knowledge-base/diagrams/model.c4",
      expect.objectContaining({ method: "PUT" }),
    );
    expect(screen.getByText(/diagram updated/i)).toBeTruthy();
    // No "re-rendering…" present-progressive lie.
    expect(screen.queryByText(/re-rendering/i)).toBeNull();
  });

  it("on a failed re-render: copy defers, onSaved(false) (Layer 2)", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({
        ok: true,
        json: async () => ({ commitSha: "x", rerendered: false }),
      }) as unknown as typeof fetch;
    const onSaved = vi.fn().mockResolvedValue(undefined);

    render(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={onSaved} />,
    );
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: "model { edited }" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    // No diagnostic → exactly ONE arg (toHaveBeenCalledWith compares all args).
    await waitFor(() => expect(onSaved).toHaveBeenCalledWith(false));
    // #8695: the only no-diagnostic failure is a supersede — say so, and do not
    // promise an update the page never performs.
    expect(
      screen.getByText(
        "Saved — a newer change was saved before this one was rendered.",
      ),
    ).toBeTruthy();
    expect(screen.queryByText(/after re-render/i)).toBeNull();
  });

  it("on a failed re-render WITH a diagnostic: copy shows the reason (#4966)", async () => {
    global.fetch = vi
      .fn()
      .mockResolvedValue({
        ok: true,
        json: async () => ({
          commitSha: "x",
          rerendered: false,
          rerenderDiagnostic:
            "Re-render failed: Could not resolve reference to ElementKind named 'container' (is spec.c4 present?)",
        }),
      }) as unknown as typeof fetch;
    const onSaved = vi.fn().mockResolvedValue(undefined);

    render(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={onSaved} />,
    );
    fireEvent.change(screen.getByTestId("cm"), {
      target: { value: "model { edited }" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^save$/i }));

    // #8695: the diagnostic is threaded to the parent so the stale banner can
    // show it (the embedded viewer unmounts this panel on save).
    await waitFor(() =>
      expect(onSaved).toHaveBeenCalledWith(
        false,
        "Re-render failed: Could not resolve reference to ElementKind named 'container' (is spec.c4 present?)",
      ),
    );
    // The actionable diagnostic replaces the generic no-diagnostic copy.
    expect(screen.getByText(/Could not resolve reference/i)).toBeTruthy();
    expect(screen.getByText(/is spec\.c4 present/i)).toBeTruthy();
  });

  it("#8695: Save stays reachable for an unchanged file while the diagram is stale (the banner says 'Save again')", () => {
    const { rerender } = render(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={vi.fn()} />,
    );
    const save = () => screen.getByRole("button", { name: /^save$/i }) as HTMLButtonElement;
    // Unchanged and not stale: nothing to save.
    expect(save().disabled).toBe(true);
    rerender(
      <C4CodePanel data={data} dirPath="knowledge-base/diagrams" onSaved={vi.fn()} allowResave />,
    );
    expect(save().disabled).toBe(false);
  });
});

describe("useC4Project — a response for a folder the page has left is discarded", () => {
  it("a reload bound to folder A that resolves after navigating to B does not overwrite B's data", async () => {
    const byDir: Record<string, string> = { A: "a-source", B: "b-source" };
    global.fetch = vi.fn(async (url: string) => {
      const dir = decodeURIComponent(String(url).split("dir=")[1]);
      return { ok: true, json: async () => ({ dir, sources: { "model.c4": byDir[dir] } }) };
    }) as unknown as typeof fetch;
    const { result, rerender } = renderHook(({ dir }) => useC4Project(dir), {
      initialProps: { dir: "A" },
    });
    await waitFor(() => expect(result.current.data?.dir).toBe("A"));
    const reloadForA = result.current.reload;
    rerender({ dir: "B" });
    await waitFor(() => expect(result.current.data?.dir).toBe("B"));
    await act(async () => {
      await reloadForA();
    });
    expect(result.current.data?.dir).toBe("B");
    expect(result.current.data?.sources["model.c4"]).toBe("b-source");
  });
});

// #9050 F9 — the endpoint guard above covers the cross-folder case only. Two
// in-flight reloads on the SAME endpoint race: last to resolve wins, so a
// slower stale read can overwrite a fresher one.
describe("useC4Project — a superseded same-endpoint reload is discarded", () => {
  function deferredFetch(sources: string[]) {
    const resolvers: Array<() => void> = [];
    let call = 0;
    global.fetch = vi.fn(
      () =>
        new Promise((resolve) => {
          const payload = {
            dir: "d",
            sources: { "model.c4": sources[call++] },
          };
          resolvers.push(() =>
            resolve({ ok: true, json: async () => payload } as Response),
          );
        }),
    ) as unknown as typeof fetch;
    return resolvers;
  }

  it("a slower first reload resolving after a faster second does not clobber the fresher data", async () => {
    const resolvers = deferredFetch(["stale-read", "fresh-read"]);
    const { result } = renderHook(() => useC4Project("d"));
    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(1));
    act(() => {
      void result.current.reload();
    });
    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(2));
    // The fresher (second) fetch lands first.
    await act(async () => {
      resolvers[1]();
    });
    await waitFor(() =>
      expect(result.current.data?.sources["model.c4"]).toBe("fresh-read"),
    );
    // The stale (first) fetch lands late — it must not overwrite.
    await act(async () => {
      resolvers[0]();
    });
    expect(result.current.data?.sources["model.c4"]).toBe("fresh-read");
  });

  it("a superseded reload does not clear loading while the fresher one is still in flight", async () => {
    const resolvers = deferredFetch(["stale-read", "fresh-read"]);
    const { result } = renderHook(() => useC4Project("d"));
    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(1));
    act(() => {
      void result.current.reload();
    });
    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(2));
    // The stale (first) fetch resolves while the fresh one is still pending.
    await act(async () => {
      resolvers[0]();
    });
    expect(result.current.loading).toBe(true);
    await act(async () => {
      resolvers[1]();
    });
    await waitFor(() =>
      expect(result.current.data?.sources["model.c4"]).toBe("fresh-read"),
    );
    expect(result.current.loading).toBe(false);
  });

  it("a superseded non-silent reload still clears loading when the superseding fetch is silent", async () => {
    const resolvers = deferredFetch(["mount-read", "stale-read", "fresh-read"]);
    const { result } = renderHook(() => useC4Project("d"));
    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(1));
    // Settle the initial mount fetch first so `loading` is a clean slate.
    await act(async () => {
      resolvers[0]();
    });
    await waitFor(() => expect(result.current.loading).toBe(false));
    // A non-silent reload claims the spinner, then a silent refetch supersedes
    // it — save outcomes refetch silently (#8739).
    act(() => {
      void result.current.reload();
    });
    expect(result.current.loading).toBe(true);
    act(() => {
      void result.current.reload({ silent: true });
    });
    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(3));
    // The superseded non-silent fetch resolves: it must still clear the
    // spinner it owns — the silent fetch never claimed it.
    await act(async () => {
      resolvers[1]();
    });
    expect(result.current.loading).toBe(false);
    await act(async () => {
      resolvers[2]();
    });
    expect(result.current.data?.sources["model.c4"]).toBe("fresh-read");
    expect(result.current.loading).toBe(false);
  });
});

// #8966 — the derived verdict must survive the response normalization intact:
// `stale:true`/`false` pass through, and ABSENT stays absent (undefined), never
// normalized to false — a false normalization would let an undervived read
// clear a banner a dropped frame earned.
describe("useC4Project — stale passthrough (#8966)", () => {
  async function load(payload: Record<string, unknown>) {
    global.fetch = vi.fn(async () => ({
      ok: true,
      json: async () => payload,
    })) as unknown as typeof fetch;
    const { result } = renderHook(() => useC4Project("engineering/diagrams"));
    await waitFor(() => expect(result.current.loading).toBe(false));
    return result.current.data;
  }

  it("stale:true is preserved", async () => {
    const data = await load({ dir: "d", sources: {}, dump: null, viewIds: [], diagnostics: [], stale: true });
    expect(data?.stale).toBe(true);
  });

  it("stale:false is preserved — a clean verdict is authoritative, not 'no banner info'", async () => {
    const data = await load({ dir: "d", sources: {}, dump: null, viewIds: [], diagnostics: [], stale: false });
    expect(data?.stale).toBe(false);
  });

  it("absent stays absent — undefined, never false", async () => {
    const data = await load({ dir: "d", sources: {}, dump: null, viewIds: [], diagnostics: [] });
    expect(data?.stale).toBeUndefined();
    expect("stale" in (data ?? {})).toBe(true); // key exists on the normalized shape…
    expect(data?.stale).toBeUndefined();       // …but the VALUE is absent
  });
});

// #8966 — the shared reconcile both banner consumers call. Pinned here once so
// the workspace and the embed can never drift on the supersede deferral.
describe("staleOutcomeVerdict — the shared reconcile (#8966)", () => {
  it("rerendered:true clears", () => {
    expect(staleOutcomeVerdict(true)).toEqual({
      apply: true,
      stale: false,
      diagnostic: null,
    });
  });

  it("rerendered:false WITH a diagnostic sets the banner with the reason", () => {
    expect(staleOutcomeVerdict(false, "rate limited")).toEqual({
      apply: true,
      stale: true,
      diagnostic: "rate limited",
    });
  });

  it("the supersede shape (rerendered:false, no diagnostic) DEFERS — never self-sets", () => {
    expect(staleOutcomeVerdict(false, null)).toEqual({ apply: false });
    expect(staleOutcomeVerdict(false)).toEqual({ apply: false });
  });
});

describe("staleActionLine — the flag × dir copy matrix (#8966)", () => {
  it("flag ON → the supersede line (Save is a live affordance)", () => {
    expect(staleActionLine(true, "engineering/architecture/diagrams")).toBe(
      SUPERSEDED,
    );
    expect(staleActionLine(true, "anywhere/else")).toBe(SUPERSEDED);
  });

  it("flag OFF + canonical dir → the Concierge line", () => {
    expect(staleActionLine(false, "engineering/architecture/diagrams")).toBe(
      CONCIERGE_ACTION_LINE,
    );
  });

  it("flag OFF + non-canonical dir → the export line", () => {
    expect(staleActionLine(false, "product/diagrams")).toBe(
      OTHER_DIR_ACTION_LINE,
    );
  });
});

describe("C4Diagnostics — staleAction resolves line 2 (#8966)", () => {
  it("uses staleAction as the no-diagnostic fallback", () => {
    render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleAction={CONCIERGE_ACTION_LINE}
      />,
    );
    expect(screen.getByText(CONCIERGE_ACTION_LINE)).toBeTruthy();
    expect(screen.queryByText(SUPERSEDED)).toBeNull();
  });

  it("a save diagnostic still wins over staleAction", () => {
    render(
      <C4Diagnostics
        diagnostics={[]}
        hasModel={true}
        stale={true}
        staleDiagnostic={RATE_LIMIT_DIAG}
        staleAction={CONCIERGE_ACTION_LINE}
      />,
    );
    expect(screen.queryByText(CONCIERGE_ACTION_LINE)).toBeNull();
    expect(screen.getByText(/rate limit/i)).toBeTruthy();
  });

  it("the amber strip announces itself — aria-live=polite", () => {
    render(<C4Diagnostics diagnostics={[]} hasModel={true} stale={true} />);
    const strip = document.querySelector('[aria-live="polite"]');
    expect(strip).toBeTruthy();
    expect(strip?.textContent).toContain("out of date");
  });
});
