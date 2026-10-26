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
import type { CreateNoActionReason, CreateRefusalClass } from "@/server/compound-promote-create";

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

/**
 * One refusal row. FLAT by design: a nested object would need any sink-side
 * transform to recurse, and a transform that recurses is one an added field can
 * slip past.
 *
 * CARRIES NO FREE TEXT, AND THAT IS THE POINT (#8427).
 *
 * An earlier revision of this change carried git's `detail` string here behind a
 * redact -> classify -> cap transform. Review falsified the control end to end:
 * the classifier only collapsed tokens containing `/`, so a proposal that created
 * a file at the repository ROOT — a name the model chooses freely, and which
 * `git diff-index` emits unquoted, spaces and all — passed through the classifier
 * byte for byte. Measured against git 2.55.0: a diff creating
 * `ALERT <arbitrary prose>.md` yielded `detail = "A ALERT <arbitrary prose>.md"`
 * in the emitted row. At ~198 characters per refused cluster and 20 entries that
 * is ~3,960 model-chosen characters per weekly run into a third-party processor
 * with no executed Art. 28(3) instrument.
 *
 * Every repair for that is a denylist over a string the model writes, which is
 * the shape ADR-211 rejects in this position. So the field is gone. What remains
 * is decidable by construction:
 *
 *   - `reason`       a closed enum, chosen by OUR code, one value per emit site
 *   - `diff_*`       numbers and booleans computed from the proposal, never its text
 *   - `cluster_hash` a sha256 hex digest
 *
 * That is the same posture the marker already takes everywhere else, and it is
 * what `error_message` — the ONE free-text field this no-`redact` logger carries
 * — is scoped against.
 *
 * The full, unelided diagnostic still reaches SENTRY via `reportSilentFallback`,
 * scrubbed by `redactGithubSourcedText` and capped by `safeDetail`. Forensics did
 * not move; only the third-party log row lost a field it could not carry safely.
 */
export interface RefusalDetailEntry {
  cluster_hash: string;
  reason: string;
  diff_len?: number;
  diff_fenced?: boolean;
  diff_header_pair?: boolean;
  diff_hunk?: boolean;
}

/**
 * Runtime copy of the status union (a type cannot be counted at runtime). A test pins its length
 * to 8 and its members to the union, so the eight literals cannot silently become nine.
 */
export const COMPOUND_PROMOTE_STATUSES = [
  "disabled",
  "deduped",
  "week-cap-reached",
  "empty-corpus",
  "anthropic-truncated",
  "no-qualifying-clusters",
  "completed",
  "error",
] as const satisfies readonly CompoundPromoteStatus[];

export interface CompoundPromoteOutcome {
  status: CompoundPromoteStatus;
  corpus_count?: number;
  clusters_proposed?: number;
  clusters_opened?: number;
  /** One entry per refusal site that fired, in order. */
  refusals?: string[];
  /**
   * Bounded per-cluster refusal detail. See {@link RefusalDetailEntry} for why
   * this carries no free-text field, and what was removed after review measured
   * the sink-side control failing.
   *
   * Widened by #8427 from `{cluster_hash, reason}` to add the proposal's
   * observable SHAPE. `git apply` answers an empty string, a whitespace-only
   * string, a fenced block and a hunk-less header pair with the byte-identical
   * message, so the reason alone cannot separate them. The shape fields do, and
   * they are numbers and booleans — never proposal content.
   */
  refusal_detail?: RefusalDetailEntry[];
  /** Bytes of the corpus payload serialized into the Anthropic message. */
  corpus_input_bytes?: number;
  /**
   * PATTERNS PATH ONLY (#8293): numbers and closed enums, never text. They are absent from a
   * scheduled-path row, which stays byte-identical to what it was before the layer existed.
   */
  input_source?: "corpus" | "patterns";
  /** Open pattern pages that loaded and validated. */
  patterns_open?: number;
  /** `failed` when the prior-outcome read could not be proven complete. */
  ledger_read?: "ok" | "failed";
  /** Proposals dropped because the same cluster hash was already proposed (open, merged, or closed under 60 days). */
  ledger_suppressed?: number;
  /** RAW search hit count, before identity and title filtering. */
  ledger_prs_scanned?: number;
  /** Bot-authored hits skipped for a title that no longer matches the builder's shape (warn-level, never fails the read). */
  ledger_title_skipped?: number;
  /**
   * Which trigger produced this run. BOTH triggers dispatch this same handler
   * (`{ cron: "0 0 * * 0" }` and `{ event: "...manual-trigger" }` are registered
   * on one function), so nothing downstream can tell them apart without this
   * field — and the #8281 soak probe's whole claim is about the SCHEDULED path.
   * Without it a manual fire during the soak window closes the tracker while
   * the weekly path stays dark.
   */
  trigger?: "cron" | "manual";
  /**
   * THE GATED CREATE ARM (#10550). Closed enums, booleans and numbers; never model text. EVERY field here is absent
   * from a scheduled-path row and from a manual `corpus` row, which stay byte-identical to before the arm existed.
   *
   *   - `create_requested`   a manual `patterns` run: whether the event carried `allow_create === true`. Present on
   *                          every such row (also the early terminal rows), so each switch-on is visible without SSH.
   *   - `kind`, `create_arm` emitted ONLY when the arm ran (`create_arm: "ran"`); an absent field means off.
   *   - `create_outcome`     `no_action` (the model declined, or the pattern is already proposed), `refused`, `opened`.
   *   - `create_refusal_class` the closed class of the ONE refusal reason `create-refused`; `create_detail` its closed
   *                          token (a field label plus a rule id, or a fixed phrase); the numbers explain a budget or
   *                          overlap refusal (cap and total, top-1 overlap score, rank of the nearest skill).
   */
  kind?: "create";
  create_requested?: boolean;
  create_arm?: "ran";
  create_outcome?: "no_action" | "refused" | "opened";
  create_no_action_reason?: CreateNoActionReason;
  create_refusal_class?: CreateRefusalClass;
  create_detail?: string;
  create_words?: number;
  create_cap?: number;
  create_total?: number;
  create_top1?: number;
  create_nearest_rank?: number;
  /** `input-size` refusals: the token bound, its ceiling and the input bytes (the bound is bytes / 4). */
  create_tokens?: number;
  create_max?: number;
  create_bytes?: number;
  /** `persist` collector refusals and `persist/bytes-differ`: the index into the six-path set. */
  create_path_index?: number;
  /** `scan` refusals: the index of the refused file (0 SKILL.md, 1 PURPOSE.md) and how many tools were missing. */
  create_file_index?: number;
  create_missing_tools?: number;
  /** `scan` / `readme-sync` refusals: the gate script's exit code; also `persist` refusals: the exit status of a failed git call. */
  create_exit?: number;
  /** `readme-sync` (paths that changed) and `persist/base-moved` (base blobs that moved). */
  create_changed_count?: number;
  /** The draft PR number when `create_outcome` is `opened`. */
  create_pr?: number;
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

/**
 * The ONLY numbers a create refusal may put on the marker: refusal `numbers` key -> marker field. A number the pure
 * module or a gate adds is Sentry-only (`extra`) until it is named here, so the marker's shape stays reviewed.
 */
export const CREATE_MARKER_NUMBERS = {
  words: "create_words",
  cap: "create_cap",
  total: "create_total",
  top1: "create_top1",
  nearest_rank: "create_nearest_rank",
  tokens: "create_tokens",
  max: "create_max",
  bytes: "create_bytes",
  path_index: "create_path_index",
  file_index: "create_file_index",
  missing_tools: "create_missing_tools",
  exit_code: "create_exit",
  changed_count: "create_changed_count",
} as const satisfies Record<string, keyof CompoundPromoteOutcome>;

/**
 * The numeric refusal keys that are SENTRY-ONLY on purpose: a create refusal may carry them in `numbers` (so they reach
 * the `create-refused` event's `extra`), and the handler never forwards them to the marker. Every number key the three
 * create modules pass is either a key of {@link CREATE_MARKER_NUMBERS} or listed here; a census test enforces it, so a
 * new number is a decision about the marker's shape, not an accident.
 */
export const CREATE_SENTRY_ONLY_NUMBERS = ["min_words", "max_words", "headroom", "threshold", "pr"] as const;

/** Cap on `refusal_detail` entries so one pathological run cannot flood the sink. */
export const REFUSAL_DETAIL_CAP = 20;

/** Emit one `SOLEUR_COMPOUND_PROMOTE_OUTCOME` WARN marker. NEVER throws. */
export function emitOutcomeMarker(outcome: CompoundPromoteOutcome): void {
  // Built BEFORE the try. A throw in here must not be swallowed by the fail-open
  // catch below — that would suppress the ENTIRE marker and render a broken run
  // indistinguishable from a quiet corpus, which is the blind spot #8281 exists
  // to close. Nothing in this map can throw today (it reads known fields off a
  // typed object), and keeping it outside the try is what makes that stay true.
  //
  // Entries are REBUILT by destructuring the known fields, never `{...entry}`.
  // A spread relays every future field straight into the row, and an allowlist
  // that decides which ENTRIES pass is not an allowlist of what they CARRY.
  const entries = outcome.refusal_detail?.slice(0, REFUSAL_DETAIL_CAP).map((e) => ({
    cluster_hash: e.cluster_hash,
    reason: e.reason,
    ...(e.diff_len === undefined ? {} : { diff_len: e.diff_len }),
    ...(e.diff_fenced === undefined ? {} : { diff_fenced: e.diff_fenced }),
    ...(e.diff_header_pair === undefined ? {} : { diff_header_pair: e.diff_header_pair }),
    ...(e.diff_hunk === undefined ? {} : { diff_hunk: e.diff_hunk }),
  }));

  try {
    log.warn(
      {
        ...outcome,
        // AFTER the spread, not before (#8427). These two are the marker's
        // machine-readability contract: `SOLEUR_COMPOUND_PROMOTE_OUTCOME` is the
        // top-level boolean discriminator every reader keys on. Placed before
        // `...outcome` they could be SHADOWED by a widened or dynamically
        // assembled outcome, and TypeScript's excess-property check fires only
        // on fresh object literals — it does not protect a spread.
        SOLEUR_COMPOUND_PROMOTE_OUTCOME: true,
        fn: "cron-compound-promote",
        // Both arrays capped — `refusals` used to be spread uncapped, so the
        // "one pathological run cannot flood the sink" property held for only
        // one of the two. The total is recorded so a capped list is
        // distinguishable from a complete one.
        refusals: outcome.refusals?.slice(0, REFUSAL_DETAIL_CAP),
        refusal_detail: entries,
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
