"use client";

// Interactive LikeC4 C4-model visualizer with an editable DSL code tab.
// Server computes the layouted model (/api/kb/c4/project); this renders it
// client-side with clickable drill-down and lets the user edit the .c4 source.
// Loaded via next/dynamic({ ssr: false }) — @likec4/diagram is canvas/browser
// only. Gated upstream by the `c4-visualizer` flag (markdown-renderer).
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

type Diagnostic = { message: string; line: number; sourceFsPath: string };
type ProjectResponse = {
  dir: string;
  sources: Record<string, string>;
  dump: Record<string, unknown> | null;
  viewIds: string[];
  diagnostics: Diagnostic[];
};

const Spinner = () => (
  <div className="flex items-center justify-center p-8">
    <div className="h-5 w-5 animate-spin rounded-full border-2 border-soleur-border-default border-t-amber-400" />
  </div>
);

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

export default function C4Diagram({
  viewId,
  dirPath,
}: {
  viewId: string;
  dirPath: string;
}) {
  const [data, setData] = useState<ProjectResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<"diagram" | "code">("diagram");
  const [currentView, setCurrentView] = useState(viewId);

  const load = useCallback(async () => {
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
    void load();
  }, [load]);
  useEffect(() => {
    setCurrentView(viewId);
  }, [viewId]);

  const model = useMemo(() => {
    if (!data?.dump) return null;
    try {
      // dump is the layouted model's $data — create() round-trips it.
      return LikeC4Model.create(data.dump as unknown as LayoutedLikeC4ModelData);
    } catch {
      return null;
    }
  }, [data?.dump]);

  // ---- Code editor state -------------------------------------------------
  const files = useMemo(() => (data ? Object.keys(data.sources) : []), [data]);
  const [activeFile, setActiveFile] = useState<string>("");
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState<string | null>(null);

  useEffect(() => {
    if (files.length === 0) return;
    setActiveFile((prev) =>
      prev && files.includes(prev) ? prev : files.find((f) => f === "model.c4") ?? files[0],
    );
  }, [files]);
  useEffect(() => {
    if (data && activeFile) setDraft(data.sources[activeFile] ?? "");
  }, [data, activeFile]);

  const isDark =
    typeof document !== "undefined" &&
    document.documentElement.getAttribute("data-theme") !== "light";

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
      await load();
      setTab("diagram");
    } catch (e) {
      setSaveMsg(e instanceof Error ? e.message : "Save failed");
    } finally {
      setSaving(false);
    }
  }, [activeFile, dirPath, draft, load]);

  const dirty = data && activeFile ? draft !== (data.sources[activeFile] ?? "") : false;

  return (
    <div className="mb-4 overflow-hidden rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1/40">
      {/* Tab bar */}
      <div className="flex items-center gap-1 border-b border-soleur-border-default bg-soleur-bg-surface-2/40 px-2 py-1.5">
        {(["diagram", "code"] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`rounded px-2.5 py-1 text-xs font-medium capitalize transition-colors ${
              tab === t
                ? "bg-soleur-bg-base text-soleur-text-primary"
                : "text-soleur-text-muted hover:text-soleur-text-secondary"
            }`}
          >
            {t}
          </button>
        ))}
        <span className="ml-auto pr-1 text-[11px] text-soleur-text-muted">
          LikeC4 · {currentView}
        </span>
      </div>

      {loading && <Spinner />}

      {!loading && error && (
        <div className="p-4 text-sm text-red-400">⚠ {error}</div>
      )}

      {!loading && !error && data && (
        <>
          {/* Parse diagnostics (non-fatal warnings or fatal errors) */}
          {data.diagnostics.length > 0 && (
            <div className="border-b border-soleur-border-default bg-red-500/10 px-3 py-2 text-xs text-red-300">
              <p className="mb-1 font-semibold">
                {data.dump ? "Diagram warnings" : "Diagram has errors — fix the source in the Code tab"}
              </p>
              <ul className="space-y-0.5">
                {data.diagnostics.slice(0, 8).map((d, i) => (
                  <li key={i}>
                    line {d.line}: {d.message}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {tab === "diagram" &&
            (model ? (
              <div className="relative h-[600px] w-full">
                <LikeC4ModelProvider likec4model={model}>
                  <ViewCanvas
                    viewId={currentView}
                    onNavigate={(to) => setCurrentView(String(to))}
                  />
                </LikeC4ModelProvider>
              </div>
            ) : (
              <div className="p-6 text-sm text-soleur-text-muted">
                Nothing to render — fix the source in the Code tab.
              </div>
            ))}

          {tab === "code" && (
            <div className="flex flex-col">
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
              <CodeMirror
                value={draft}
                height="560px"
                theme={isDark ? oneDark : undefined}
                onChange={setDraft}
                basicSetup={{ lineNumbers: true, foldGutter: true }}
              />
            </div>
          )}
        </>
      )}
    </div>
  );
}
