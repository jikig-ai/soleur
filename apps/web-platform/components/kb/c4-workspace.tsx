"use client";

// Full-screen LikeC4 workspace for KB diagram pages: the interactive diagram on
// the LEFT, and on the RIGHT a window that toggles between the Soleur Concierge
// (open by default, scoped to this document so it can edit the diagram) and the
// raw .c4 code editor. Loaded via next/dynamic({ ssr: false }) from the KB page
// — @likec4/diagram is canvas/browser-only.
import { useState } from "react";
import { Group, Panel, Separator } from "react-resizable-panels";
import { KbChatContent } from "@/components/chat/kb-chat-content";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import {
  Spinner,
  useC4Project,
  C4Canvas,
  C4Diagnostics,
  C4CodePanel,
} from "@/components/kb/c4-shared";

function ResizeHandle() {
  return (
    <Separator className="group relative w-1 bg-transparent transition-colors duration-150 hover:bg-soleur-text-secondary/50 active:bg-amber-500/50 data-[resize-handle-active]:bg-amber-500/50">
      <div className="absolute inset-y-0 left-1/2 flex -translate-x-1/2 flex-col items-center justify-center gap-0.5">
        <span className="h-0.5 w-0.5 rounded-full bg-soleur-text-muted group-hover:bg-soleur-text-secondary" />
        <span className="h-0.5 w-0.5 rounded-full bg-soleur-text-muted group-hover:bg-soleur-text-secondary" />
        <span className="h-0.5 w-0.5 rounded-full bg-soleur-text-muted group-hover:bg-soleur-text-secondary" />
      </div>
    </Separator>
  );
}

export default function C4Workspace({
  viewId,
  dirPath,
  contextPath,
  notes,
}: {
  viewId: string;
  dirPath: string;
  /** KB-relative path (e.g. "knowledge-base/.../c4-model.md") the Concierge is scoped to. */
  contextPath: string;
  /** Remaining prose (diagram block stripped) for the collapsible Notes strip. */
  notes?: string;
}) {
  const { data, error, loading, reload } = useC4Project(dirPath);
  const [rightTab, setRightTab] = useState<"concierge" | "code">("concierge");
  const [currentView, setCurrentView] = useState(viewId);
  // When collapsed, the right panel (Concierge/Code) + its resize handle are
  // unmounted so the diagram takes full width. This is a deliberate unmount-on-
  // collapse choice (not CSS-hide): ChatSurface re-resumes the thread from the
  // server via `resumeByContextPath` and restores the draft from sessionStorage
  // (`draftKey`) on reveal, so no in-progress content is lost — the panel just
  // re-hydrates with a "Continuing from…" banner. Reveal is driven by the gold
  // pill on the full-width diagram (the shared KbChatTrigger stays suppressed on
  // C4 docs to avoid double-mounting a second Concierge — see page.tsx).
  const [conciergeCollapsed, setConciergeCollapsed] = useState(false);

  return (
    <div className="flex h-full min-h-0 flex-col">
      <Group orientation="horizontal" className="h-full min-h-0 flex-1">
        {/* LEFT — interactive diagram (+ collapsible Notes) */}
        <Panel minSize="35%">
          <div className="relative flex h-full min-h-0 flex-col">
            {/* Reveal control — shown only when the Concierge is collapsed so the
                user can reopen it on the full-width diagram. */}
            {conciergeCollapsed && (
              <button
                type="button"
                aria-label="Open Concierge"
                onClick={() => setConciergeCollapsed(false)}
                className="absolute right-3 top-3 z-10 inline-flex items-center gap-1.5 rounded-full bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end px-3.5 py-1.5 text-xs font-medium text-soleur-text-on-accent shadow-lg transition-opacity hover:opacity-90"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
                  <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                </svg>
                Open Concierge
              </button>
            )}
            {loading && <Spinner />}
            {!loading && error && (
              <div className="p-4 text-sm text-red-400">⚠ {error}</div>
            )}
            {!loading && !error && data && (
              <>
                <C4Diagnostics
                  diagnostics={data.diagnostics}
                  hasModel={!!data.dump}
                />
                <div className="relative min-h-0 flex-1">
                  <C4Canvas
                    dump={data.dump}
                    initialViewId={viewId}
                    onViewChange={setCurrentView}
                  />
                </div>
                {notes && notes.trim().length > 0 && (
                  <details className="shrink-0 border-t border-soleur-border-default bg-soleur-bg-surface-1/40 px-4 py-2 text-sm">
                    <summary className="cursor-pointer text-xs font-medium text-soleur-text-muted hover:text-soleur-text-secondary">
                      Notes
                    </summary>
                    <div className="prose-kb mt-2 max-h-48 overflow-y-auto">
                      <MarkdownRenderer
                        content={notes}
                        enableC4={false}
                        c4DirPath={dirPath}
                      />
                    </div>
                  </details>
                )}
              </>
            )}
          </div>
        </Panel>

        {!conciergeCollapsed && <ResizeHandle />}

        {/* RIGHT — Concierge (default) / Code toggle. Unmounted when collapsed
            so the diagram pane takes full width. */}
        {!conciergeCollapsed && (
        <Panel defaultSize="38%" minSize="28%" maxSize="60%">
          <div className="flex h-full min-h-0 flex-col border-l border-soleur-border-default">
            <div className="flex shrink-0 items-center gap-1 border-b border-soleur-border-default bg-soleur-bg-surface-2/40 px-2 py-1.5">
              {(
                [
                  ["concierge", "Concierge"],
                  ["code", "Code"],
                ] as const
              ).map(([t, label]) => (
                <button
                  key={t}
                  onClick={() => setRightTab(t)}
                  className={`rounded px-2.5 py-1 text-xs font-medium transition-colors ${
                    rightTab === t
                      ? "bg-soleur-bg-base text-soleur-text-primary"
                      : "text-soleur-text-muted hover:text-soleur-text-secondary"
                  }`}
                >
                  {label}
                </button>
              ))}
              <div className="ml-auto flex items-center gap-1.5 pr-1">
                <span className="text-[11px] text-soleur-text-muted">
                  Architecture · {currentView}
                </span>
                <button
                  type="button"
                  aria-label="Collapse Concierge"
                  onClick={() => setConciergeCollapsed(true)}
                  className="rounded p-1 text-soleur-text-muted transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-secondary"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="13 17 18 12 13 7" />
                    <polyline points="6 17 11 12 6 7" />
                  </svg>
                </button>
              </div>
            </div>

            <div className="relative min-h-0 flex-1">
              {/* Concierge stays mounted across the Concierge/Code tab toggle so
                  the thread persists; visibility is CSS-driven. */}
              <div className={rightTab === "concierge" ? "h-full" : "hidden"}>
                <KbChatContent
                  contextPath={contextPath}
                  onClose={() => setConciergeCollapsed(true)}
                  visible={rightTab === "concierge"}
                />
              </div>
              {rightTab === "code" && (
                <div className="h-full">
                  {data ? (
                    <C4CodePanel
                      data={data}
                      dirPath={dirPath}
                      onSaved={reload}
                    />
                  ) : (
                    <Spinner />
                  )}
                </div>
              )}
            </div>
          </div>
        </Panel>
        )}
      </Group>
    </div>
  );
}
