// Leaf module (no runtime imports): the status set every race-safe FINALIZE write is guarded on.
import type { Conversation } from "@/lib/types";

/**
 * Status set the race-safe finalize helper guards on. Pinned to a `Conversation["status"]` literal subset via
 * `satisfies` so a future widening of the conversation-status enum is a TS error here rather than silent semantic drift
 * at every guarded site.
 *
 * Active-only BY DESIGN (#3463, #11303 / ADR-305): the result branch writes `waiting_for_user` as the normal turn-end
 * status, so a finalize that also accepted `waiting_for_user` would let a disconnect right after a clean result
 * overwrite it with `failed`. A disconnect or Stop while a review card is pending leaves the row `waiting_for_user`
 * (resumable; the 2-hour sweep completes it).
 */
export const ACTIVE_STATUSES_FOR_FINALIZE = [
  "active",
] as const satisfies ReadonlyArray<Conversation["status"]>;
