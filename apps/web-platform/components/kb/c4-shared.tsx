"use client";

// Shared building blocks for the LikeC4 visualizer, reused by both the inline
// markdown embed (c4-diagram.tsx) and the full-workspace split (c4-workspace.tsx).
// @likec4/diagram is canvas/browser-only — consumers must load via
// next/dynamic({ ssr: false }).
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import CodeMirror from "@uiw/react-codemirror";
import { oneDark } from "@codemirror/theme-one-dark";
import {
  c4SyntaxExtensions,
  codeFontTheme,
  fontPxForZoom,
  DEFAULT_CODE_FONT_PX,
  MIN_CODE_FONT_PX,
  MAX_CODE_FONT_PX,
} from "./c4-code-syntax";
import {
  LikeC4ModelProvider,
  LikeC4Diagram,
  useLikeC4ViewModel,
  type OnNavigateTo,
} from "@likec4/diagram";
import { LikeC4Model } from "@likec4/core/model";
import type { LayoutedLikeC4ModelData } from "@likec4/core/types";
import "@likec4/diagram/styles.css";
// Soleur re-theme — MUST come after the library styles so it wins on source
// order (defense-in-depth alongside the scoped-selector specificity in the file).
import "./c4-theme.css";

export type Diagnostic = { message: string; line: number; sourceFsPath: string };
export type ProjectResponse = {
  dir: string;
  sources: Record<string, string>;
  dump: Record<string, unknown> | null;
  viewIds: string[];
  diagnostics: Diagnostic[];
};

export const Spinner = () => (
  <div className="flex items-center justify-center p-8">
    <div className="h-5 w-5 animate-spin rounded-full border-2 border-soleur-border-default border-t-amber-400" />
  </div>
);

/**
 * Fetch the precomputed LikeC4 project (model dump + .c4 sources) for a dir.
 *
 * `options.url` overrides the default authenticated endpoint. The public
 * shared-document viewer passes `/api/shared/<token>/c4` (token-scoped, no auth,
 * no `.c4` sources); owner paths omit it and hit `/api/kb/c4/project?dir=…`.
 * The response is normalized so `sources`/`diagnostics` are always present even
 * when the public endpoint omits them (data-minimization).
 */
export function useC4Project(dirPath: string, options?: { url?: string }) {
  const [data, setData] = useState<ProjectResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const url = options?.url;
  const reload = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const endpoint =
        url ?? `/api/kb/c4/project?dir=${encodeURIComponent(dirPath)}`;
      const res = await fetch(endpoint);
      if (!res.ok) {
        const j = await res.json().catch(() => ({}));
        throw new Error(j.error || `Request failed (${res.status})`);
      }
      const json = (await res.json()) as Partial<ProjectResponse>;
      setData({
        dir: json.dir ?? dirPath,
        sources: json.sources ?? {},
        dump: json.dump ?? null,
        viewIds: json.viewIds ?? [],
        diagnostics: json.diagnostics ?? [],
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load diagram");
    } finally {
      setLoading(false);
    }
  }, [dirPath, url]);

  useEffect(() => {
    void reload();
  }, [reload]);

  return { data, error, loading, reload };
}

function ViewCanvas({
  viewId,
  onNavigate,
}: {
  viewId: string;
  onNavigate: OnNavigateTo;
}) {
  const vm = useLikeC4ViewModel(viewId);
  if (!vm) {
    return (
      <div className="p-6 text-sm text-soleur-text-muted">
        View <code className="text-soleur-accent-gold-fg">{viewId}</code> not found in the model.
      </div>
    );
  }
  // The .soleur-c4 scope wrapper is owned by C4Canvas (so both the inline
  // container AND the fullscreen portal overlay carry the scoped re-theme).
  return (
    <div className="h-full w-full">
      <LikeC4Diagram
        view={vm.$view}
        pannable
        zoomable
        fitView
        controls
        showNavigationButtons
        enableElementDetails
        enableRelationshipDetails
        enableFocusMode
        onNavigateTo={onNavigate}
      />
    </div>
  );
}

/** Maximize (enter-fullscreen) glyph. */
const MaximizeIcon = () => (
  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <polyline points="15 3 21 3 21 9" />
    <polyline points="9 21 3 21 3 15" />
    <line x1="21" y1="3" x2="14" y2="10" />
    <line x1="3" y1="21" x2="10" y2="14" />
  </svg>
);

/** Minimize (exit-fullscreen) glyph. */
const MinimizeIcon = () => (
  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <polyline points="4 14 10 14 10 20" />
    <polyline points="20 10 14 10 14 4" />
    <line x1="14" y1="10" x2="21" y2="3" />
    <line x1="3" y1="21" x2="10" y2="14" />
  </svg>
);

/**
 * Interactive diagram canvas with clickable drill-down. Owns the current view
 * (drill-down) state, seeded from `initialViewId` and reset when it changes.
 * `onViewChange` lets the parent mirror the active view (e.g. a status label).
 */
export function C4Canvas({
  dump,
  initialViewId,
  onViewChange,
}: {
  dump: Record<string, unknown> | null;
  initialViewId: string;
  onViewChange?: (viewId: string) => void;
}) {
  const [currentView, setCurrentView] = useState(initialViewId);
  // Fullscreen/expand toggle. The diagram subtree is re-parented into a
  // document.body portal when expanded (escapes the inline embed's h-[600px]
  // + overflow-hidden clip). Drill-down state (`currentView`) is lifted here
  // so it is shared across the inline ↔ fullscreen toggle; the LikeC4 canvas
  // re-fits its viewport on the re-parent (documented limitation — the view
  // navigation is preserved, the pan/zoom transform re-fits).
  const [expanded, setExpanded] = useState(false);
  const expandButtonRef = useRef<HTMLButtonElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const shouldReturnFocusRef = useRef(false);

  useEffect(() => setCurrentView(initialViewId), [initialViewId]);
  useEffect(() => onViewChange?.(currentView), [currentView, onViewChange]);

  // Esc closes the fullscreen overlay (mirrors typed-confirm-modal.tsx).
  useEffect(() => {
    if (!expanded) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault();
        setExpanded(false);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [expanded]);

  // Scroll-lock the page behind the overlay; restore the prior value on close.
  useEffect(() => {
    if (!expanded) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [expanded]);

  // Focus management: move focus into the overlay (close button) on open;
  // return focus to the expand button on close. The shouldReturnFocusRef guard
  // prevents stealing focus to the expand button on the initial mount.
  useEffect(() => {
    if (expanded) {
      shouldReturnFocusRef.current = true;
      const id = requestAnimationFrame(() => closeButtonRef.current?.focus());
      return () => cancelAnimationFrame(id);
    }
    if (shouldReturnFocusRef.current) {
      shouldReturnFocusRef.current = false;
      expandButtonRef.current?.focus();
    }
  }, [expanded]);

  const model = useMemo(() => {
    if (!dump) return null;
    try {
      return LikeC4Model.create(dump as unknown as LayoutedLikeC4ModelData);
    } catch {
      return null;
    }
  }, [dump]);

  if (!model) {
    return (
      <div className="soleur-c4 p-6 text-sm text-soleur-text-muted">
        Nothing to render — fix the source in the Code view.
      </div>
    );
  }

  // ONE diagram subtree. Rendered inline OR inside the portal overlay (never
  // both — they are mutually exclusive branches), so there is no second
  // LikeC4Diagram instance forking drill-down state.
  const canvas = (
    <LikeC4ModelProvider likec4model={model}>
      <ViewCanvas
        viewId={currentView}
        onNavigate={(to) => setCurrentView(String(to))}
      />
    </LikeC4ModelProvider>
  );

  // .soleur-c4 anchors the scoped Soleur re-theme (c4-theme.css). It is applied
  // to BOTH the inline wrapper and the portal overlay so the theme holds in
  // fullscreen exactly as inline.
  return (
    <div className="soleur-c4 relative h-full w-full">
      {!expanded ? (
        <>
          {canvas}
          <button
            ref={expandButtonRef}
            type="button"
            aria-label="Enter fullscreen"
            title="Expand to fullscreen"
            onClick={() => setExpanded(true)}
            className="absolute right-2 top-2 z-10 rounded-md border border-soleur-border-default bg-soleur-bg-base/80 p-1.5 text-soleur-text-muted backdrop-blur transition-colors hover:text-soleur-text-primary"
          >
            <MaximizeIcon />
          </button>
        </>
      ) : (
        <>
          <div className="flex h-full w-full items-center justify-center p-6 text-xs text-soleur-text-muted">
            Diagram open in fullscreen
          </div>
          {createPortal(
            // Tab focus-trap + aria-hidden on the background are intentionally
            // NOT implemented here — same deferral the shared modal precedent
            // documents (components/ui/typed-confirm-modal.tsx). Focus moves IN
            // on open and RETURNS on close (AC10); a full trap lands with the
            // shared modal-a11y primitive. z-50 matches the app's modal layer.
            <div
              role="dialog"
              aria-modal="true"
              aria-label="Architecture diagram (fullscreen)"
              className="soleur-c4 fixed inset-0 z-50 bg-soleur-bg-base"
            >
              {canvas}
              <button
                ref={closeButtonRef}
                type="button"
                aria-label="Exit fullscreen"
                title="Exit fullscreen (Esc)"
                onClick={() => setExpanded(false)}
                className="absolute right-3 top-3 z-10 flex items-center gap-1.5 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1/90 px-2 py-1.5 text-soleur-text-muted backdrop-blur transition-colors hover:text-soleur-text-primary"
              >
                <MinimizeIcon />
                <span className="text-[11px]">Esc</span>
              </button>
            </div>,
            document.body,
          )}
        </>
      )}
    </div>
  );
}

/**
 * Non-fatal warnings / fatal parse errors surfaced inline above the editor, plus
 * an honest "source edited" staleness note. The rendered diagram comes from a
 * precomputed `model.likec4.json` that is regenerated out-of-band (never at
 * runtime), so after a Save the diagram is stale until it is re-rendered. The
 * `stale` strip reuses this same banner slot — no new overlay/modal/toast.
 */
export function C4Diagnostics({
  diagnostics,
  hasModel,
  stale = false,
}: {
  diagnostics: Diagnostic[];
  hasModel: boolean;
  /** True once the user has saved a source edit this session — the precomputed
   *  diagram has not been re-rendered, so it may not reflect the edit. */
  stale?: boolean;
}) {
  if (diagnostics.length === 0 && !stale) return null;
  return (
    <div className="border-b border-soleur-border-default text-xs">
      {stale && (
        <div className="bg-amber-500/10 px-3 py-2 text-amber-300">
          <p className="font-semibold">
            Source edited — rendered diagram may be out of date
          </p>
          <p className="mt-0.5 text-amber-300/80">
            The diagram is precomputed; it refreshes after the model is
            re-rendered out-of-band.
          </p>
        </div>
      )}
      {diagnostics.length > 0 && (
        <div className="bg-red-500/10 px-3 py-2 text-red-300">
          <p className="mb-1 font-semibold">
            {hasModel
              ? "Diagram warnings"
              : "Diagram has errors — fix the source in the Code view"}
          </p>
          <ul className="space-y-0.5">
            {diagnostics.slice(0, 8).map((d, i) => (
              <li key={i}>
                line {d.line}: {d.message}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

/** Editable .c4 source panel (file tabs + CodeMirror + Save → PUT → reload). */
export function C4CodePanel({
  data,
  dirPath,
  onSaved,
  height = "100%",
}: {
  data: ProjectResponse;
  dirPath: string;
  /** Called after a successful save. `rerendered` is true when the server
   *  regenerated the diagram (the rendered model is fresh); false when the
   *  out-of-band re-render failed or was skipped (diagram may be stale). */
  onSaved: (rerendered: boolean) => void | Promise<void>;
  height?: string;
}) {
  const files = useMemo(() => Object.keys(data.sources), [data.sources]);
  const [activeFile, setActiveFile] = useState<string>("");
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState<string | null>(null);
  // Optimistic apply (F-A1): content the user has SUCCESSFULLY saved this
  // session, keyed by file. On a 200 PUT the GitHub commit is the source of
  // truth, but GET /project reads the on-disk workspace clone, which can lag —
  // a diverged/un-fast-forwardable clone (self-heal aborts to preserve un-pushed
  // session work) or Contents-API→fetch replica propagation lag returns the
  // PRE-edit text. Without this, the `[data, activeFile]` re-seed below clobbers
  // the editor back to the stale source and the save silently reverts. We keep
  // the just-saved content as the editor value until the reloaded source catches
  // up to it. Diagram staleness (the dump half) is surfaced honestly by the
  // existing Layer-1 banner (#4963) — this only fixes the source revert.
  const savedContentRef = useRef<Record<string, string>>({});
  // Per-editor font zoom (0 = default 12px), clamped to [10px, 24px]. Drives a
  // CodeMirror theme extension so content + gutter scale together — scoped to
  // this editor, independent of browser page zoom.
  const [zoom, setZoom] = useState(0);
  const currentFontPx = fontPxForZoom(zoom);
  const atMin = currentFontPx <= MIN_CODE_FONT_PX;
  const atMax = currentFontPx >= MAX_CODE_FONT_PX;
  // Language + Soleur-tokened syntax highlight (theme-independent) + font theme.
  const extensions = useMemo(
    () => [c4SyntaxExtensions, codeFontTheme(zoom)],
    [zoom],
  );

  useEffect(() => {
    if (files.length === 0) return;
    setActiveFile((prev) =>
      prev && files.includes(prev)
        ? prev
        : files.find((f) => f === "model.c4") ?? files[0],
    );
  }, [files]);
  useEffect(() => {
    if (!activeFile) return;
    const incoming = data.sources[activeFile] ?? "";
    const optimistic = savedContentRef.current[activeFile];
    if (optimistic !== undefined && incoming !== optimistic) {
      // The reloaded clone has not caught up to our just-saved content yet —
      // keep showing the saved text instead of reverting to the stale source.
      setDraft(optimistic);
      return;
    }
    // Clone caught up (incoming === optimistic) or no pending save — clear the
    // marker so future external edits to this file apply normally, then sync.
    if (optimistic !== undefined) delete savedContentRef.current[activeFile];
    setDraft(incoming);
  }, [data, activeFile]);

  const isDark =
    typeof document !== "undefined" &&
    document.documentElement.getAttribute("data-theme") !== "light";

  // Compare against the optimistically-saved content (if any) so a just-saved
  // file is not shown as "dirty" while the clone catches up; falls back to the
  // server source for files with no pending save.
  const baseline =
    (activeFile ? savedContentRef.current[activeFile] : undefined) ??
    (activeFile ? data.sources[activeFile] ?? "" : "");
  const dirty = activeFile ? draft !== baseline : false;

  const save = useCallback(async () => {
    setSaving(true);
    setSaveMsg(null);
    try {
      const res = await fetch(`/api/kb/c4/${dirPath}/${activeFile}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: draft }),
      });
      const j = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(j.error || `Save failed (${res.status})`);
      // F-A1: the commit landed on origin (200). Pin the saved content as the
      // optimistic editor value BEFORE onSaved triggers the parent reload(), so
      // a stale-clone GET /project cannot revert the editor to the pre-edit text.
      savedContentRef.current[activeFile] = draft;
      // Layer 2 (#4964): the server re-renders the diagram after a .c4 save.
      // `rerendered` reports whether that succeeded. On success the reloaded
      // dump is the fresh geometry; on failure the diagram stays stale and the
      // C4Diagnostics banner says so. Default true if the field is absent
      // (older server) so we don't false-warn.
      const rerendered = j?.rerendered !== false;
      // On a re-render failure the server may explain WHY (e.g. an unresolved
      // reference because spec.c4 is missing) so the user can fix their source
      // instead of staring at a silently-stale diagram (#4966).
      const diagnostic =
        typeof j?.rerenderDiagnostic === "string" ? j.rerenderDiagnostic : null;
      setSaveMsg(
        rerendered
          ? "Saved — diagram updated."
          : diagnostic
            ? `Saved — ${diagnostic}`
            : "Saved — diagram will update after re-render.",
      );
      await onSaved(rerendered);
    } catch (e) {
      setSaveMsg(e instanceof Error ? e.message : "Save failed");
    } finally {
      setSaving(false);
    }
  }, [activeFile, dirPath, draft, onSaved]);

  return (
    <div className="flex h-full flex-col">
      <div className="flex flex-wrap items-center gap-1 border-b border-soleur-border-default px-2 py-1.5">
        {files.map((f) => (
          <button
            key={f}
            onClick={() => setActiveFile(f)}
            className={`rounded px-2 py-0.5 font-mono text-[11px] transition-colors ${
              activeFile === f
                ? "bg-soleur-bg-base text-soleur-text-primary"
                : "text-soleur-text-muted hover:text-soleur-text-secondary"
            }`}
          >
            {f}
          </button>
        ))}
        <div className="ml-auto flex items-center gap-2">
          <div className="flex items-center gap-0.5 rounded border border-soleur-border-default px-0.5">
            <button
              type="button"
              aria-label="Decrease code font size"
              onClick={() =>
                setZoom((z) =>
                  Math.max(MIN_CODE_FONT_PX - DEFAULT_CODE_FONT_PX, z - 1),
                )
              }
              disabled={atMin}
              className="rounded px-1.5 py-0.5 text-[11px] text-soleur-text-muted transition-colors hover:text-soleur-text-secondary disabled:opacity-30"
            >
              A−
            </button>
            <button
              type="button"
              aria-label="Reset code font size"
              onClick={() => setZoom(0)}
              title="Reset code font size"
              className="min-w-[2.75rem] rounded px-1 py-0.5 text-center font-mono text-[11px] tabular-nums text-soleur-text-muted transition-colors hover:text-soleur-text-secondary"
            >
              {`${currentFontPx}px`}
            </button>
            <button
              type="button"
              aria-label="Increase code font size"
              onClick={() =>
                setZoom((z) =>
                  Math.min(MAX_CODE_FONT_PX - DEFAULT_CODE_FONT_PX, z + 1),
                )
              }
              disabled={atMax}
              className="rounded px-1.5 py-0.5 text-[11px] text-soleur-text-muted transition-colors hover:text-soleur-text-secondary disabled:opacity-30"
            >
              A+
            </button>
          </div>
          {saveMsg && (
            <span className="text-[11px] text-soleur-text-muted">{saveMsg}</span>
          )}
          <button
            onClick={() => void save()}
            disabled={saving || !dirty}
            className="rounded bg-soleur-accent-gold-fg/90 px-2.5 py-1 text-xs font-medium text-black disabled:opacity-40"
          >
            {saving ? "Saving…" : "Save"}
          </button>
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-auto">
        <CodeMirror
          value={draft}
          height={height}
          theme={isDark ? oneDark : undefined}
          extensions={extensions}
          onChange={setDraft}
          basicSetup={{ lineNumbers: true, foldGutter: true }}
        />
      </div>
    </div>
  );
}
