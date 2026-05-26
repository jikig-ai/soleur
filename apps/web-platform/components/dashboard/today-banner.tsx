// PR-F (#3244, #3940) Phase 5 — RV14.
//
// Page-level disclosure banner rendered ONCE above the Today section.
// One DOM node, one screen-reader announcement, same legal guarantee as
// a per-card disclosure but without the visual noise. RV13 — imports the
// canonical constant from lib/legal/disclosures.ts so legal-copy edits
// flow through.

import { RUNTIME_COST_DISCLOSURE } from "@/lib/legal/disclosures";

export function TodayBanner() {
  return (
    <div
      role="note"
      className="mb-4 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-3 text-sm text-soleur-text-secondary"
    >
      {RUNTIME_COST_DISCLOSURE}
    </div>
  );
}
