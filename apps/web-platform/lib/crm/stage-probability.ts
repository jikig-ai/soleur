// Canonical stage -> win-probability map for the beta-CRM pipeline
// (feat-beta-conversation-capture #6165, ADR-102 §6).
//
// SINGLE SOURCE OF TRUTH for the pipeline stage enum. Two consumers:
//   1. The migration `126_beta_crm.sql` `stage`/`to_stage` CHECK sets MUST
//      equal `Object.keys(STAGE_PROBABILITY)`. A drift-guard test
//      (crm-tools.test.ts) fails the build on divergence — this is the map's
//      real merge-time consumer.
//   2. `pipeline-analyst` (a markdown agent) *references* these weights when
//      it reasons about weighted pipeline; it does NOT import this module
//      (arch review P2-2). The weighted-forecasting TS consumer is deferred
//      (CFO: forecasting is theater at 0 deals — capture the fields now).
//
// Tenant-generic: no Soleur-specific stage names. A future tenant config can
// own its own map; the CHECK enum is derived from whatever this map declares.
// `SCHEMA_VERSION` bumps when the stage set changes so a stored transition
// history can be interpreted against the map version that produced it.

/**
 * Ordered pipeline stages mapped to their win probability in [0, 1].
 * `new` is the insert default (migration `stage NOT NULL DEFAULT 'new'`).
 * `closed_lost` is terminal at probability 0; `closed_won` terminal at 1.
 */
export const STAGE_PROBABILITY = {
  new: 0.0,
  contacted: 0.1,
  qualified: 0.25,
  evaluating: 0.5,
  committed: 0.8,
  closed_won: 1.0,
  closed_lost: 0.0,
} as const;

export type Stage = keyof typeof STAGE_PROBABILITY;

/** The canonical stage list, in pipeline order. */
export const STAGES = Object.keys(STAGE_PROBABILITY) as Stage[];

/**
 * The linear conversion funnel — every stage except the terminal `closed_lost`
 * branch. Single source for both the funnel API compute (app/api/crm/funnel)
 * and the UI (components/crm), which previously derived this filter twice
 * (review P3-1). `closed_won` remains the terminal funnel stage.
 */
export const FUNNEL_STAGES = STAGES.filter((s) => s !== "closed_lost");

/**
 * Bump when the stage SET changes (add/remove/rename). Lets a stored
 * `beta_contact_stage_transitions` history be read against the map version
 * that produced it. Not the app version — this is the stage-contract version.
 */
export const SCHEMA_VERSION = 1;

/** Default insert stage — mirrors the migration column default. */
export const DEFAULT_STAGE: Stage = "new";
