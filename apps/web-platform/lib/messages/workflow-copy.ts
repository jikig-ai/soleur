// #1055 — Editorial label map for the per-workflow cost breakdown on the BYOK
// usage dashboard. Mirrors the `lib/messages/action-class-copy.ts` pattern: a
// technical identity source-of-truth lives elsewhere, and this file is the
// single editorial layer on top of it. Every consumer that RENDERS a workflow
// bucket to a founder reads `WORKFLOW_COPY[b].label`, never the wire value.
//
// Strings are transcribed from the copy spec, §12 "Bucket labels (28 each)":
//   knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md
// They carry a written editorial rationale (gerunds not imperatives; `one-shot`
// is the composite pipeline, not a peer stage). Nothing here is authored
// inline — a new string is a copy-spec edit first.
//
// TYPE-ONLY IMPORT, deliberately. `server/conversation-routing.ts` is NOT on
// `.dependency-cruiser.cjs`'s `VALUE_SAFE_PATH` allowlist (only
// domain-leaders | providers | team-names-validation | scope-grants/action-class-map
// are), so a value import from a module reachable by a client component would
// trip the client/server import-boundary gate. `WORKFLOW_NAMES` is not exported
// anyway. The `satisfies` rail below is a type-level check, so type-only is
// sufficient — and it is what makes a missing or extra bucket a COMPILE error
// rather than a runtime loop.
//
// BUCKET KEYS ARE THE FUNCTION'S KEYS, NOT THE COLUMN'S VALUES. Migration
// `136_workflow_cost_rollup.sql` normalises `active_workflow IS NULL` → 'legacy'
// and the `__unrouted__` storage sentinel → 'unrouted' so no `__`-prefixed
// sentinel ever crosses into TS ("SENTINEL NORMALISATION" in that file). The
// copy spec's §12 table lists the storage-side values (`__unrouted__`,
// `__legacy__`); the keys below are their normalised equivalents.

import type { WorkflowName } from "@/server/conversation-routing";

/** A row key emitted by `public.sum_user_mtd_cost_by_workflow`. */
export type WorkflowBucket = WorkflowName | "unrouted" | "legacy";

export interface WorkflowCopy {
  /** Founder-facing name. ≤ WORKFLOW_LABEL_MAX chars, no raw-slug characters. */
  label: string;
}

/** Copy spec §12 budget: "Bucket labels (28 each)". */
export const WORKFLOW_LABEL_MAX = 28;

export const WORKFLOW_COPY = {
  // Deliberately breaks the gerund pattern: `one-shot` is the whole
  // plan → work → review → ship pipeline in one dispatch, so it is usually the
  // LARGEST bucket. Naming it after a single stage would misinform.
  "one-shot": { label: "Idea to shipped" },
  brainstorm: { label: "Exploring an idea" },
  plan: { label: "Planning the work" },
  work: { label: "Doing the work" },
  review: { label: "Reviewing the code" },
  "drain-labeled-backlog": { label: "Clearing the backlog" },
  // States what happened, in plain past tense — not a system state, and not
  // something the founder is being asked to fix.
  unrouted: { label: "No workflow started" },
  // Self-explaining: the label itself says why the spend is unattributed, so
  // no per-bucket footnote is needed.
  legacy: { label: "Before workflow tracking" },
} as const satisfies Record<WorkflowBucket, WorkflowCopy>;

/**
 * Resolve a bucket key to its founder-facing label.
 *
 * Unknown keys fall back to the raw value. That path is reachable only on a
 * partial deploy — migration 032's CHECK enum widened ahead of the web bundle —
 * and showing the raw key is better than dropping money out of a breakdown that
 * promises "Nothing is left out". The caller mirrors the event to Sentry
 * (`server/api-usage.ts`, `op: "workflow-bucket-unmapped"`), so the fallback is
 * never silent per `cq-silent-fallback-must-mirror-to-sentry`.
 */
export function workflowLabel(bucket: string): string {
  return isWorkflowBucket(bucket) ? WORKFLOW_COPY[bucket].label : bucket;
}

/** Runtime membership test derived from the map itself — no value import. */
export function isWorkflowBucket(bucket: string): bucket is WorkflowBucket {
  return Object.prototype.hasOwnProperty.call(WORKFLOW_COPY, bucket);
}
