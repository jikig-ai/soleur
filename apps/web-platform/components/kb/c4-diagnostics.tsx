"use client";

// The C4 diagnostics / staleness banner. Lives in its own light module (no
// CodeMirror, Mantine or @likec4/diagram) so tests can render the REAL banner;
// c4-shared.tsx re-exports it, so every import site is unchanged.
import { MODEL_LEVEL_LINE, type Diagnostic } from "@/lib/c4-model-shape";
import { C4_DIAGRAMS_DIR } from "@/lib/c4-constants";

/** Line 2 of the stale strip when the save carried no diagnostic (#8695). The
 *  server returns `rerendered:false` with no reason only when a newer source
 *  change superseded this save's render. That newer change may never render
 *  here — a push from outside Soleur emits no `c4_diagram_saved` frame the
 *  page can hear (#8739), and a render can fail — so the copy names the
 *  supersede, promises nothing, and points at the one action that works: Save
 *  stays enabled while the diagram is stale. Valid only when the `c4-edit`
 *  flag is ON — flag-off consumers resolve a different line via
 *  `staleActionLine` (CPO: no dead affordances in copy). */
export const SUPERSEDED_LINE =
  "A newer change to the diagram source was saved before this one was rendered, so this save did not update the diagram. Save again to render the latest version.";

/** Line 2 when `c4-edit` is OFF and the dir is Concierge-writable: the Code
 *  panel's Save is a dead affordance, so the action is the live one — the
 *  Concierge. "re-render this diagram" is the phrase the Concierge prompt
 *  addendum keys on (see route.ts's ZERO_VIEW_DIAGNOSTIC). */
export const CONCIERGE_ACTION_LINE =
  "Ask the Concierge to re-render this diagram.";

/** Line 2 when `c4-edit` is OFF and the dir is NOT Concierge-writable: neither
 *  in-app affordance can fix it — the fix is the repo-side export, and nothing
 *  refetches until a reload. */
export const OTHER_DIR_ACTION_LINE =
  "Re-run the diagram export for this folder in your repository, then reload the page.";

/** The fallback line-2 copy for the stale strip, resolved by the flag + dir —
 *  the consumers (c4-workspace, c4-diagram) hold both and pass the result via
 *  `staleAction`; this module must stay flag-free to keep the test seam light. */
export function staleActionLine(editEnabled: boolean, dirPath: string): string {
  if (editEnabled) return SUPERSEDED_LINE;
  return dirPath === C4_DIAGRAMS_DIR
    ? CONCIERGE_ACTION_LINE
    : OTHER_DIR_ACTION_LINE;
}

/**
 * #8966 — the save-outcome's contribution to the stale banner, decided once
 * for both consumers so the inline embed and the workspace can never drift.
 * The returned verdict applies ONLY when the reload's GET carried no `stale`
 * field (present is authoritative); callers handle that precedence.
 *
 * `apply:false` is the supersede shape — `rerendered:false` with NO diagnostic
 * means a newer save's render superseded this one, and its model commit is
 * already live: the diagram is likely FRESH, so the outcome defers to the GET
 * verdict instead of self-setting a possibly-false banner.
 */
export function staleOutcomeVerdict(
  rerendered: boolean,
  diagnostic?: string | null,
): { apply: true; stale: boolean; diagnostic: string | null } | { apply: false } {
  if (rerendered) return { apply: true, stale: false, diagnostic: null };
  if (diagnostic == null) return { apply: false };
  return { apply: true, stale: true, diagnostic };
}

function capitalizeFirst(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/**
 * Non-fatal warnings / fatal parse errors surfaced inline above the editor, plus
 * an honest "source edited" staleness note. The rendered diagram comes from a
 * precomputed `model.likec4.json` that the server re-renders after each `.c4`
 * save (#4964); staleness is derived server-side on every GET (#8966) and the
 * save's diagnostic (or the resolved `staleAction` line) says what to do. The
 * `stale` strip reuses this same banner slot — no new overlay/modal/toast.
 */
export function C4Diagnostics({
  diagnostics,
  hasModel,
  stale = false,
  staleDiagnostic = null,
  staleAction = SUPERSEDED_LINE,
}: {
  diagnostics: Diagnostic[];
  hasModel: boolean;
  /** True when the served model predates the current source (derived) or the
   *  last save this session committed the source but the server did not
   *  re-render the diagram. */
  stale?: boolean;
  /** The server's `rerenderDiagnostic` for that save, if any. Rendered as a
   *  React text node (never HTML); ignored unless `stale`. */
  staleDiagnostic?: string | null;
  /** Fallback line-2 when there is no save diagnostic — resolved by the caller
   *  via `staleActionLine` (flag × dir matrix). */
  staleAction?: string;
}) {
  if (diagnostics.length === 0 && !stale) return null;
  return (
    <div className="border-b border-soleur-border-default text-xs">
      {stale && (
        // aria-live: the banner appears without user action (derived verdict on
        // a refetch), so it must announce — a plain div is silent to SRs.
        <div
          aria-live="polite"
          className="bg-amber-500/10 px-3 py-2 text-amber-300"
        >
          <p className="font-semibold">
            Source edited — rendered diagram may be out of date
          </p>
          <p className="mt-0.5 text-amber-300/80">
            {staleDiagnostic ? capitalizeFirst(staleDiagnostic) : staleAction}
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
              // `line <= MODEL_LEVEL_LINE` is reserved for a diagnostic about the
              // whole model (the zero-view model, #8740), which has no source
              // line. A second producer or reader should move to a `kind` field.
              <li key={i}>
                {d.line > MODEL_LEVEL_LINE ? `line ${d.line}: ` : ""}
                {d.message}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
