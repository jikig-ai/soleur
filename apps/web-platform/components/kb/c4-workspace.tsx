"use client";

// Full-screen LikeC4 workspace for KB diagram pages: the interactive diagram on
// the LEFT, and on the RIGHT a window that toggles between the Soleur Concierge
// (open by default, scoped to this document so it can edit the diagram) and the
// raw .c4 code editor. Loaded via next/dynamic({ ssr: false }) from the KB page
// — @likec4/diagram is canvas/browser-only.
import { useContext, useState } from "react";
import { Group, Panel, Separator } from "react-resizable-panels";
import { KbChatContent } from "@/components/chat/kb-chat-content";
import { KbChatContext } from "@/components/kb/kb-chat-context";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import {
  Spinner,
  useC4Project,
  C4Canvas,
  C4Diagnostics,
  C4CodePanel,
} from "@/components/kb/c4-shared";
import { useOptionalFeatureFlag } from "@/components/feature-flags/provider";
import { C4_EDIT_FLAG } from "@/lib/c4-constants";

function ResizeHandle() {
  // Active/drag wash is brand gold (`soleur-accent-gold-fill/70`), grey on hover
  // — consistent with the nav-rail grip. Double-click-to-collapse is
  // intentionally NOT wired here: this is a between-pane splitter with no
  // collapsed-width state, so a collapse gesture has no coherent target (AC10).
  return (
    <Separator className="group relative w-1 bg-transparent transition-colors duration-150 hover:bg-soleur-text-secondary/50 active:bg-soleur-accent-gold-fill/70 data-[resize-handle-active]:bg-soleur-accent-gold-fill/70">
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
  // feat-c4-viewer-remove-code-panel-gate-edit: the user-direct Code editor is
  // gated behind `c4-edit` (default OFF). When OFF, the Code tab + panel are not
  // rendered and a hint points users to the Concierge (the only live KB writer).
  // Non-throwing read so provider-less render surfaces treat "no flag" as off.
  const c4EditEnabled = useOptionalFeatureFlag(C4_EDIT_FLAG);
  const [rightTab, setRightTab] = useState<"concierge" | "code">("concierge");
  // True only when the server FAILED to re-render after a save (#4964). On a
  // successful save the server regenerates model.likec4.json out-of-process and
  // the reloaded dump is fresh, so stale stays false; if the re-render failed it
  // flips true and the C4Diagnostics banner honestly says the diagram is stale.
  const [stale, setStale] = useState(false);
  // Reveal/collapse is LIFTED to KbChatContext so the SHARED top-bar trigger
  // ("Ask about this document", in KbContentHeader) drives it — consistent with
  // the markdown viewer. The C4 page keeps setSuppressSidebar(true) so the
  // desktop side panel stays unmounted (no double-mount); a DISTINCT context
  // signal (embeddedConciergeOpen) controls THIS embedded panel.
  //
  // When collapsed, the right panel (Concierge/Code) + its resize handle are
  // unmounted so the diagram takes full width — a deliberate unmount-on-collapse
  // choice (not CSS-hide): ChatSurface re-resumes the thread from the server via
  // `resumeByContextPath` and restores the draft from sessionStorage (`draftKey`)
  // on reveal, so no in-progress content is lost (re-hydrates with a
  // "Continuing from…" banner).
  //
  // Falls back to local state when rendered outside a KbChatContext provider
  // (defensive — the production page always provides one).
  const chatCtx = useContext(KbChatContext);
  const [localCollapsed, setLocalCollapsed] = useState(false);
  const conciergeCollapsed =
    chatCtx?.embeddedConciergeOpen !== undefined
      ? !chatCtx.embeddedConciergeOpen
      : localCollapsed;
  // Reveal is driven by the shared top-bar trigger (KbContentHeader →
  // KbChatTrigger → revealEmbeddedConcierge); C4Workspace only owns COLLAPSE
  // (the chevron + the KbChatContent X). The local-state fallback exists only
  // for the no-provider render path (defensive).
  const collapseConcierge = () => {
    if (chatCtx?.collapseEmbeddedConcierge) chatCtx.collapseEmbeddedConcierge();
    else setLocalCollapsed(true);
  };

  return (
    <div className="flex h-full min-h-0 flex-col">
      <Group orientation="horizontal" className="h-full min-h-0 flex-1">
        {/* LEFT — interactive diagram (+ collapsible Notes). Reveal is driven by
            the shared top-bar "Ask about this document" trigger (KbContentHeader),
            consistent with the markdown viewer — the bespoke floating
            "Open Concierge" pill was removed in the UX-consistency pass. */}
        <Panel minSize="35%">
          <div className="relative flex h-full min-h-0 flex-col">
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
                <div className="relative min-h-0 flex-1">
                  <C4Canvas dump={data.dump} initialViewId={viewId} />
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
              {c4EditEnabled ? (
                (
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
                ))
              ) : (
                // Discoverability hint (AC10): the Code editor is gated OFF, so
                // tell the user the Concierge is how diagrams are edited. A
                // single muted line — no new component/flow. The lone "Concierge"
                // tab is dropped (single tab = noise) but the collapse chevron stays.
                <span className="px-1 text-xs text-soleur-text-muted">
                  To change this diagram, ask the Concierge.
                </span>
              )}
              <div className="ml-auto flex items-center gap-1.5 pr-1">
                <button
                  type="button"
                  aria-label="Collapse Concierge"
                  onClick={collapseConcierge}
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
                  onClose={collapseConcierge}
                  visible={rightTab === "concierge"}
                />
              </div>
              {c4EditEnabled && rightTab === "code" && (
                <div className="h-full">
                  {data ? (
                    <C4CodePanel
                      data={data}
                      dirPath={dirPath}
                      onSaved={async (rerendered) => {
                        await reload();
                        // Stale only when the server could NOT re-render; on a
                        // successful re-render the reloaded dump is fresh.
                        setStale(!rerendered);
                      }}
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
