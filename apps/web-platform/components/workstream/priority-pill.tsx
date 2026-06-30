// Shared priority indicator (accent bar + color-matched label inside a subtle
// pill). Used on the card and in the detail Sheet so the two surfaces never
// drift. Addendum item 3: a legible labeled pill, not an ambiguous dot.

import {
  priorityBarClass,
  priorityLabel,
  priorityPillClass,
  type WorkstreamPriority,
} from "@/lib/workstream";

export function PriorityPill({ priority }: { priority: WorkstreamPriority }) {
  return (
    <span className="inline-flex items-center gap-1 rounded bg-soleur-bg-surface-2/60 px-1.5 py-0.5">
      <span
        aria-hidden="true"
        className={`h-2 w-[3px] rounded-full ${priorityBarClass(priority)}`}
      />
      <span className={`text-[11px] font-medium ${priorityPillClass(priority)}`}>
        {priorityLabel(priority)}
      </span>
    </span>
  );
}
