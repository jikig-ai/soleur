"use client";

// The C4 diagnostics / staleness banner. Lives in its own light module (no
// CodeMirror, Mantine or @likec4/diagram) so tests can render the REAL banner;
// c4-shared.tsx re-exports it, so every import site is unchanged.
import type { Diagnostic } from "./c4-shared";

/** Line 2 of the stale strip when the save carried no diagnostic (#8695). The
 *  server returns `rerendered:false` with no reason only when a newer source
 *  change superseded this save's render; nothing on this page reloads on its
 *  own, so the copy names the supersede and promises no refresh. */
export const SUPERSEDED_LINE =
  "A newer change to the diagram source was saved before this one was rendered. Reopen the diagram to see the latest version.";

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
