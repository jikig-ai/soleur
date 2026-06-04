"use client";

// Shared building blocks for the LikeC4 visualizer, reused by both the inline
// markdown embed (c4-diagram.tsx) and the full-workspace split (c4-workspace.tsx).
// @likec4/diagram is canvas/browser-only — consumers must load via
// next/dynamic({ ssr: false }).
import { useCallback, useEffect, useMemo, useState } from "react";
import CodeMirror from "@uiw/react-codemirror";
import { oneDark } from "@codemirror/theme-one-dark";
import {
  LikeC4ModelProvider,
  LikeC4Diagram,
  useLikeC4ViewModel,
  type OnNavigateTo,
} from "@likec4/diagram";
import { LikeC4Model } from "@likec4/core/model";
import type { LayoutedLikeC4ModelData } from "@likec4/core/types";
import "@likec4/diagram/styles.css";

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

/** Fetch the precomputed LikeC4 project (model dump + .c4 sources) for a dir. */
export function useC4Project(dirPath: string) {
  const [data, setData] = useState<ProjectResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/kb/c4/project?dir=${encodeURIComponent(dirPath)}`,
      );
      if (!res.ok) {
        const j = await res.json().catch(() => ({}));
        throw new Error(j.error || `Request failed (${res.status})`);
      }
      setData((await res.json()) as ProjectResponse);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load diagram");
    } finally {
      setLoading(false);
    }
  }, [dirPath]);

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
  return (
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
  );
}

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
  useEffect(() => setCurrentView(initialViewId), [initialViewId]);
  useEffect(() => onViewChange?.(currentView), [currentView, onViewChange]);

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
      <div className="p-6 text-sm text-soleur-text-muted">
        Nothing to render — fix the source in the Code view.
      </div>
    );
  }
  return (
    <LikeC4ModelProvider likec4model={model}>
      <ViewCanvas
        viewId={currentView}
        onNavigate={(to) => setCurrentView(String(to))}
      />
    </LikeC4ModelProvider>
  );
}

/** Non-fatal warnings / fatal parse errors surfaced inline above the editor. */
export function C4Diagnostics({
  diagnostics,
  hasModel,
}: {
  diagnostics: Diagnostic[];
  hasModel: boolean;
}) {
  if (diagnostics.length === 0) return null;
  return (
    <div className="border-b border-soleur-border-default bg-red-500/10 px-3 py-2 text-xs text-red-300">
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
  onSaved: () => void | Promise<void>;
  height?: string;
}) {
  const files = useMemo(() => Object.keys(data.sources), [data.sources]);
  const [activeFile, setActiveFile] = useState<string>("");
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState<string | null>(null);

  useEffect(() => {
    if (files.length === 0) return;
    setActiveFile((prev) =>
      prev && files.includes(prev)
        ? prev
        : files.find((f) => f === "model.c4") ?? files[0],
    );
  }, [files]);
  useEffect(() => {
    if (activeFile) setDraft(data.sources[activeFile] ?? "");
  }, [data, activeFile]);

  const isDark =
    typeof document !== "undefined" &&
    document.documentElement.getAttribute("data-theme") !== "light";

  const dirty = activeFile ? draft !== (data.sources[activeFile] ?? "") : false;

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
      setSaveMsg("Saved — re-rendering…");
      await onSaved();
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
          onChange={setDraft}
          basicSetup={{ lineNumbers: true, foldGutter: true }}
        />
      </div>
    </div>
  );
}
