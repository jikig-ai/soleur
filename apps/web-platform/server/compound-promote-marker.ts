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

/**
 * One refusal row. FLAT by design: a nested object would need the sink's
 * transform to recurse, and a transform that recurses is one an added field can
 * slip past.
 */
export interface RefusalDetailEntry {
  cluster_hash: string;
  reason: string;
  detail?: string;
  diff_len?: number;
  diff_fenced?: boolean;
  diff_header_pair?: boolean;
  diff_hunk?: boolean;
}

/** Cap applied to `detail` AFTER redaction and classification. Characters. */
const DETAIL_CAP = 200;

/**
 * Path-shaped tokens in `detail`, matched loosely on purpose: the goal is to
 * catch anything a model could pass off as a path, not to parse paths.
 */
const PATH_TOKEN_RE = /[A-Za-z0-9_.\-/]*\/[A-Za-z0-9_.\-/]*/g;

/**
 * Prefixes whose IDENTITY is the diagnostic worth keeping — which corpus the
 * proposal targeted. Anything else collapses to a constant.
 */
const CLASSIFIED_PREFIXES: readonly string[] = [
  "AGENTS.rules.md",
  "plugins/soleur/skills/",
  "knowledge-base/project/learnings/",
  ".github/workflows/",
];

/**
 * CLASSIFY the path, do not relay it (#8427).
 *
 * The risk here is not incidental disclosure of repository content — it is that
 * `detail` is at two arms a model-CHOSEN string, i.e. a controlled write channel
 * into a third-party processor. Eliding one directory's slugs would do nothing
 * about that. Collapsing every path-shaped token to a fixed vocabulary reduces
 * the channel from 200 free characters to a few bits while preserving the
 * diagnostic the marker actually owes. The full path stays in the Sentry copy.
 *
 * Non-path stderr (`error: corrupt patch at line 3`) passes through unchanged;
 * this classifies path-shaped TOKENS, not the whole string.
 */
function classifyPaths(s: string): string {
  // A FUNCTION replacement, never a string one: a string replacement containing
  // `$&`, "$`" or `$'` would make attacker input live. A function makes those
  // sequences inert by construction.
  return s.replace(PATH_TOKEN_RE, (tok) => {
    if (tok === "" || !tok.includes("/")) return tok;
    const hit = CLASSIFIED_PREFIXES.find((pre) => tok.startsWith(pre));
    return hit === undefined ? "[unclassified-path]" : `${hit}[elided]`;
  });
}

/**
 * Surrogate-safe cap. `.slice(0, N)` counts UTF-16 code units and can leave a
 * lone high surrogate; `Array.from` iterates code points.
 */
function capChars(s: string, n: number): string {
  const cps = Array.from(s);
  return cps.length <= n ? s : cps.slice(0, n).join("");
}

/**
 * redact -> classify -> cap, in that order.
 *
 * ORDER IS LOAD-BEARING. `redactGithubSourcedText` substitutes `[redacted-…]`
 * markers that are LONGER than some shapes they replace, so a cap applied first
 * can be exceeded by the time the row is written; and a cap applied before
 * redaction halves a straddling credential into a fragment no pattern matches.
 */
function transformDetail(detail: string): string {
  return capChars(classifyPaths(redactGithubSourcedText(detail)), DETAIL_CAP);
}

export interface CompoundPromoteOutcome {
  status: CompoundPromoteStatus;
  corpus_count?: number;
  clusters_proposed?: number;
  clusters_opened?: number;
  /** One entry per refusal site that fired, in order. */
  refusals?: string[];
  /**
   * Bounded per-cluster refusal detail.
   *
   * #8427 widened this beyond `{cluster_hash, reason}`. The old doc comment
   * claimed it carries "a fixed reason enum ONLY — never learning text or
   * paths"; that is no longer true and the widening is the point of the change.
   * A run could report `clusters_proposed: 2, clusters_opened: 0` with both
   * refusals reading `diff-underivable`, and nothing in the row said whether the
   * proposer had emitted a malformed patch, an empty one, or a fenced one.
   *
   * WHAT `detail` IS: attacker-influenced text. At two `checkDiffPaths` arms it
   * is not git's diagnosis at all but a VERBATIM MODEL-CHOSEN string — the
   * `path-refused` arm returns the offending path, and the `structural-op` arms
   * return `${status} ${path}`, where the path is whatever the model wrote into
   * its diff. A prompt-injected proposer would otherwise get a free-text write
   * channel into a third-party processor, weekly, on every refused cluster.
   * {@link emitOutcomeMarker} therefore REDACTS, CLASSIFIES and CAPS it; see
   * the transform there. This field is the untransformed input to that sink.
   *
   * PRODUCER/SINK CAP ASYMMETRY (deliberate). `error_message` is capped at the
   * PRODUCER (`safeDetail`, 200 chars) and `detail` is capped HERE, at the sink,
   * AFTER redaction. Capping `detail` upstream would cut a credential in half
   * before `redactGithubSourcedText` could match it — its patterns carry several
   * unbounded runs — so the only cut ahead of redaction is that function's own
   * `MAX_INPUT_LEN`, which appends an explicit marker and is designed for it.
   *
   * The `diff_*` fields are the proposal's observable SHAPE, never its content:
   * `git apply` answers an empty string, a whitespace-only string, a fenced
   * block and a hunk-less header pair with the byte-identical message, so the
   * reason alone cannot separate them. Numbers and booleans only.
   */
  refusal_detail?: RefusalDetailEntry[];
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
        // Every surviving entry is REBUILT by destructuring the known fields,
        // never `{...entry, detail: t(entry.detail)}`. A spread would relay any
        // future field straight around the transform — and an allowlist that
        // decides which entries pass is not an allowlist of what they carry.
        refusal_detail: outcome.refusal_detail
          ?.slice(0, REFUSAL_DETAIL_CAP)
          .map((e) => ({
            cluster_hash: e.cluster_hash,
            reason: e.reason,
            ...(e.detail === undefined ? {} : { detail: transformDetail(e.detail) }),
            ...(e.diff_len === undefined ? {} : { diff_len: e.diff_len }),
            ...(e.diff_fenced === undefined ? {} : { diff_fenced: e.diff_fenced }),
            ...(e.diff_header_pair === undefined
              ? {}
              : { diff_header_pair: e.diff_header_pair }),
            ...(e.diff_hunk === undefined ? {} : { diff_hunk: e.diff_hunk }),
          })),
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
