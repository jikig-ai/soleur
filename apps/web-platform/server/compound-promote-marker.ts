// Structured, WARN-level, fail-open `SOLEUR_COMPOUND_PROMOTE_OUTCOME` marker
// (#8281, ADR-108 form) — the ONLY machine-readable outcome of the weekly
// compound-promote cron (the Sentry heartbeat proves liveness, not work).
//
// INVARIANT: the marker goes through THIS module's pino instance, never the
// Inngest ctx `logger`. The client deliberately passes no `logger:`
// (server/inngest/client.ts), so ctx.logger is Inngest's console-backed
// ProxyLogger and `warn(obj, msg)` through it renders via util.inspect as
// MULTI-LINE text — one journald row per line — which no field-isolated reader
// (runbook decode, the #8281 probe, Vector's JSON parse) can match. The same
// class already bit cert-reissue-marker.ts (H-T1/H-T2) and this cron on
// 2026-09-18 (PR #8276 post-merge; learning
// `knowledge-base/project/learnings/workflow-issues/2026-09-18-the-release-run-was-green-and-production-was-still-serving-the-previous-build.md`).
//
// WHY WARN, WHY A MARKER AT ALL: every terminal path returns a `status`, and
// until #8281 that string was returned into the void — the only signal was
// `postSentryHeartbeat({ ok: true })`, which proves LIVENESS and says nothing
// about WORK, so ten weeks of zero output were undiagnosable. Only pino WARN+
// transits Vector to Better Stack, so an `info` marker would recreate the
// blind spot.
//
// Same construction and the same four load-bearing properties (WARN, top-level
// boolean discriminator, fail-open, dedicated instance with no hook / formatter
// / redact) as server/cron-liveness-marker.ts — see its header for why each is
// required. The ONE free-text field is `error_message`; the caller caps it and
// the emitter shape-scrubs it HERE, so the boundary this module declares is
// enforced by this module and pinned by its own suite.
import pino from "pino";
import { redactGithubSourcedText } from "@/lib/safety/redaction-allowlist";

const log = pino({ base: { component: "compound-promote" } });

/**
 * The closed set of terminal statuses. A union rather than `string` so a
 * status outside the set is a TYPE error — the plan's Guard 1 mutation row 3
 * ("emit a status outside the known set → RED") is satisfied by the compiler
 * rather than by a regex, and the 8 literals cannot silently become 9.
 */
export type CompoundPromoteStatus =
  | "disabled"
  | "deduped"
  | "week-cap-reached"
  | "empty-corpus"
  | "anthropic-truncated"
  | "no-qualifying-clusters"
  | "completed"
  | "error";

export interface CompoundPromoteOutcome {
  status: CompoundPromoteStatus;
  corpus_count?: number;
  clusters_proposed?: number;
  clusters_opened?: number;
  /** One entry per refusal site that fired, in order. */
  refusals?: string[];
  /**
   * Bounded per-cluster refusal detail. Carries a cluster hash and a fixed
   * reason enum ONLY — never learning text or paths — so a recurring refusal of
   * the SAME cluster is distinguishable from a genuinely quiet corpus.
   */
  refusal_detail?: { cluster_hash: string; reason: string }[];
  /** Bytes of the corpus payload serialized into the Anthropic message. */
  corpus_input_bytes?: number;
  /**
   * Which trigger produced this run. BOTH triggers dispatch this same handler
   * (`{ cron: "0 0 * * 0" }` and `{ event: "...manual-trigger" }` are registered
   * on one function), so nothing downstream can tell them apart without this
   * field — and the #8281 soak probe's whole claim is about the SCHEDULED path.
   * Without it a manual fire during the soak window closes the tracker while
   * the weekly path stays dark.
   */
  trigger?: "cron" | "manual";
  /** Inngest run id — the join key to a Sentry event for the same run. */
  run_id?: string;
  /**
   * `error` only: the thrown error's class and its message after `safeDetail`
   * (control chars, 200-byte cap). The emitter additionally passes it through
   * `redactGithubSourcedText` (token / JWT / email / credential-URL shapes) —
   * the ONE free-text field this no-`redact` logger carries.
   */
  error_class?: string;
  error_message?: string;
}

/** Cap on `refusal_detail` entries so one pathological run cannot flood the sink. */
export const REFUSAL_DETAIL_CAP = 20;

/** Emit one `SOLEUR_COMPOUND_PROMOTE_OUTCOME` WARN marker. NEVER throws. */
export function emitOutcomeMarker(outcome: CompoundPromoteOutcome): void {
  try {
    log.warn(
      {
        SOLEUR_COMPOUND_PROMOTE_OUTCOME: true,
        fn: "cron-compound-promote",
        ...outcome,
        // Both arrays capped — `refusals` used to be spread uncapped, so the
        // "one pathological run cannot flood the sink" property held for only
        // one of the two. The total is recorded so a capped list is
        // distinguishable from a complete one.
        refusals: outcome.refusals?.slice(0, REFUSAL_DETAIL_CAP),
        refusal_detail: outcome.refusal_detail?.slice(0, REFUSAL_DETAIL_CAP),
        refusals_total: outcome.refusals?.length,
        // The one free-text field. `redactGithubSourcedText` is idempotent on
        // its own `[redacted-*]` output, so a caller that already scrubbed
        // (the handler does, for the Sentry copy) costs nothing here.
        ...(outcome.error_message === undefined
          ? {}
          : { error_message: redactGithubSourcedText(outcome.error_message) }),
      },
      "compound promote outcome",
    );
  } catch {
    // fail-open: a marker-emit failure must never propagate into the cron.
  }
}
