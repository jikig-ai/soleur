"use client";

// Inline LikeC4 embed: a tabbed (Diagram | Code) widget rendered in place of a
// ```likec4-view fenced block inside normal markdown. The full-screen variant
// (diagram ‖ Concierge/Code) lives in c4-workspace.tsx and is what KB diagram
// pages use; this inline form is the fallback for embeds elsewhere.
// Loaded via next/dynamic({ ssr: false }) — @likec4/diagram is browser-only.
import { useState } from "react";
import {
  Spinner,
  useC4Project,
  C4Canvas,
  C4Diagnostics,
  C4CodePanel,
} from "@/components/kb/c4-shared";

export default function C4Diagram({
  viewId,
  dirPath,
}: {
  viewId: string;
  dirPath: string;
}) {
  const { data, error, loading, reload } = useC4Project(dirPath);
  const [tab, setTab] = useState<"diagram" | "code">("diagram");
  const [currentView, setCurrentView] = useState(viewId);
  // See c4-workspace.tsx: stale flips true only when the server's post-save
  // re-render (#4964) failed; on success the reloaded dump is fresh.
  const [stale, setStale] = useState(false);

  return (
    <div className="mb-4 overflow-hidden rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1/40">
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
          Architecture · {currentView}
        </span>
      </div>

      {loading && <Spinner />}
      {!loading && error && (
        <div className="p-4 text-sm text-red-400">⚠ {error}</div>
      )}

      {!loading && !error && data && (
        <>
          <C4Diagnostics
            diagnostics={data.diagnostics}
            hasModel={!!data.dump}
            stale={stale}
          />
          {tab === "diagram" && (
            <div className="relative h-[600px] w-full">
              <C4Canvas
                dump={data.dump}
                initialViewId={viewId}
                onViewChange={setCurrentView}
              />
            </div>
          )}
          {tab === "code" && (
            <div className="h-[600px]">
              <C4CodePanel
                data={data}
                dirPath={dirPath}
                height="560px"
                onSaved={async (rerendered) => {
                  await reload();
                  setStale(!rerendered);
                  setTab("diagram");
                }}
              />
            </div>
          )}
        </>
      )}
    </div>
  );
}
