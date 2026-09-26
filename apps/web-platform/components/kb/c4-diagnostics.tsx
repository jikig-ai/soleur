"use client";

// The C4 diagnostics / staleness banner. Lives in its own light module (no
// CodeMirror, Mantine or @likec4/diagram) so tests can render the REAL banner;
// c4-shared.tsx re-exports it, so every import site is unchanged.
import { MODEL_LEVEL_LINE, type Diagnostic } from "@/lib/c4-model-shape";

/** Line 2 of the stale strip when the save carried no diagnostic (#8695). The
 *  server returns `rerendered:false` with no reason only when a newer source
 *  change superseded this save's render. That newer change may never render
 *  here — a push from outside Soleur emits no `c4_diagram_saved` frame the
 *  page can hear (#8739), and a render can fail — so the copy names the
 *  supersede, promises nothing, and points at the one action that works: Save
 *  stays enabled while the diagram is stale. */
export const SUPERSEDED_LINE =
  "A newer change to the diagram source was saved before this one was rendered, so this save did not update the diagram. Save again to render the latest version.";

function capitalizeFirst(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/**
 * Non-fatal warnings / fatal parse errors surfaced inline above the editor, plus
 * an honest "source edited" staleness note. The rendered diagram comes from a
 * precomputed `model.likec4.json` that the server re-renders after each `.c4`
 * save (#4964); when that re-render fails or is skipped, the diagram is stale
 * and the strip says why (the save's diagnostic) or, with no diagnostic, that
 * a newer change superseded it. The `stale` strip reuses this same banner slot
 * — no new overlay/modal/toast.
 */
export function C4Diagnostics({
  diagnostics,
  hasModel,
  stale = false,
  staleDiagnostic = null,
}: {
  diagnostics: Diagnostic[];
  hasModel: boolean;
  /** True when the last save this session committed the source but the server
   *  did not re-render the diagram, so it may not reflect the edit. */
  stale?: boolean;
  /** The server's `rerenderDiagnostic` for that save, if any. Rendered as a
   *  React text node (never HTML); ignored unless `stale`. */
  staleDiagnostic?: string | null;
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
            {staleDiagnostic
              ? capitalizeFirst(staleDiagnostic)
              : SUPERSEDED_LINE}
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
