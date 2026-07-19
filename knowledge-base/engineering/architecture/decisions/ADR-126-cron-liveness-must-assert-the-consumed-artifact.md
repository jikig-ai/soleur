---
title: A cron's liveness signal must assert the artifact operators consume
status: accepted
date: 2026-07-20
issue: 6714
supersedes: null
---

# ADR-126: a cron's liveness signal must assert the artifact operators consume

## Context

`cron-community-monitor` posted a GREEN Sentry check-in every day from 2026-07-14 to 07-19 while
committing **no digest at all**. The monitor was not broken: it faithfully reported the thing it
was asked to report. It was asked to report the wrong thing.

The cron's check-in colour was driven by a single flag, `heartbeatOk`, derived from
`resolveOutputAwareOk` — "did a labelled GitHub **issue** land for today's date". That predicate is
a correct *persistence* gate: it answers "did the spawned agent produce output worth committing",
and it is what decides whether `safeCommitAndPr` runs at all. It is **not** a liveness signal,
because the artifact the operator actually consumes is the committed
`knowledge-base/support/community/<date>-digest.md` — not the issue.

Four independent paths could therefore post GREEN with no artifact:

1. **The discarded return value (the primary defect).** `safeCommitAndPr`'s result was not
   assigned. A `{status:"failed"}` or `{status:"no-changes"}` was silently dropped, so a failed
   persistence was indistinguishable from a healthy commit.
2. **The persistence gate had no `else`.** A RED or timed-out run skipped persistence entirely and
   left no trace on any operator-reachable surface.
3. **The date-dedup short-circuit.** It asserted only that a labelled *issue* existed for the date.
   Run 1 filing a genuine issue but losing its commit let run 2 dedup on that issue and post GREEN
   with nothing landed — the dedup itself manufacturing the failure mode.
4. **The Tier-2 defer.** It posts a GREEN check-in and skips the spawn, indistinguishable from a
   healthy run.

Diagnosis was itself blocked. The persistence path emitted **zero** `SOLEUR_*` markers, so the
question "which internal branch swallowed persistence" (H9 in the investigation's evidence table)
could not be answered from any operator-reachable surface: the deciding datum lived only in
Inngest's step-level run history, which ADR-030 binds to `127.0.0.1:8288` and which is therefore
unreachable without SSH (`hr-no-ssh-fallback-in-runbooks`). H9 is recorded UNKNOWN, not resolved.

## Decision

**A cron's Sentry check-in colour MUST be gated on the artifact its consumer actually reads.**
Where the deliverable is a committed file, "an issue was filed" is not evidence of liveness.

Concretely, for the claude-eval cron cohort:

1. **Split the signal by ADDITION, never by renaming.** `heartbeatOk` keeps its name *and* its role
   as the persistence gate; a separately-named `livenessOk` feeds the check-in. Both are applied to
   the posted colour. This is not stylistic: `cron-safe-commit-parity.test.ts` asserts the gate as
   **literal source text** across all 8 `MIGRATED_PROMPT` cohort files, and a prior PR deliberately
   preserved that shape. A rename would break a cohort invariant to fix a colour bug.
2. **Assert the commit, not the intent.** `SafeCommitResult`'s committed arm carries optional
   `paths?: string[]` (from the allowlist-matched scan) and `resumed?: true`. The handler consumes
   the return value and requires today's digest to appear in `paths`.
3. **`undefined` means NOT DETERMINED — never "nothing committed".** The replay-resume branch skips
   the allowlist scan, so it has nothing to report even though the artifact did land. Only that
   branch has a legitimate reason to leave `paths` undetermined, so `resumed` is what licenses an
   undetermined result to stay GREEN. Any *other* undetermined shape means the result contract
   drifted, and voting GREEN on an unknown is the exact failure being closed — so it stays RED.
4. **Every GREEN-with-no-artifact path must be enumerable.** Each of the four paths above emits a
   structured marker, including the Tier-2 defer (whose deferral set is empty at HEAD — it
   instruments a condition not currently occurring, deliberately, because the cost is one line and
   the alternative is a blind spot that already cost 4 of the 41 gap days).
5. **Dedup on the artifact, not on a proxy for it.** The short-circuit now requires both the issue
   *and* the dated digest committed on the default branch. It fails closed toward spawning: a
   duplicate digest is a paper cut, a missing digest is this incident.

**Markers are observability infrastructure and must be reachable by construction.** They are pino
**WARN** (level ≥ 40) — Vector's `app_container_warn_filter` ships only level ≥ 40 to Better Stack,
so an info-level marker never leaves the host and is invisible in precisely the incident it exists
for. They are **fail-open**: an emit failure must never propagate into the run it observes. They use
a **dedicated pino instance with no `hooks.logMethod`**, because the shared logger mirrors every
WARN+ line into a Sentry breadcrumb and a steady daily marker stream would evict genuine diagnostics
from the shared-scope ring buffer.

That dedicated instance has **no ADR-029 `renameUserIdToHash` formatter and no redact paths** — both
are shared-logger-only. Marker payloads therefore MUST carry no user id, email, secret, or other
regulated field. Adding one would silently bypass ADR-029. The per-marker tests assert the emitted
field set with `toEqual` rather than `toMatchObject` specifically so a leaked field fails the build.

## Consequences

**Positive.** The check-in now means what operators read it to mean. A lost digest pages within one
cron period instead of running silently green for six days. The markers make the four internal
branches distinguishable in Better Stack via
`scripts/betterstack-query.sh --grep SOLEUR_… --since <N>d`, without SSH — so the H9-class question
is answerable next time from the surface operators already have.

**Negative / accepted.** The cron can now go RED for a reason the *issue* stream looks healthy for,
which is the intended behaviour change and will read as "noisier" until the underlying persistence
faults are fixed. The dedup performs one extra GitHub contents read per run on the deduped path.
`livenessOk` is initialised `true` and falsified only by an OBSERVED negative — deliberately, so a
trailing-step throw preserves today's "output-present run stays GREEN" contract rather than
inverting `finalizeOutputAwareHeartbeat`'s `failed = threw && !heartbeatOk` into a retry that would
replay against an already-deleted `spawnCwd`.

**Cohort implication (not addressed here).** `resolveOutputAwareOk` is shared across the cron
cohort, so **every** producer whose real deliverable is a committed file rather than an issue has
this same blind spot. This ADR deliberately does not widen to the cohort; a follow-up audits each
producer's asserted-vs-consumed artifact against this decision.

## Alternatives considered

**Rename `heartbeatOk` to `outputOk` and add a new `heartbeatOk`.** Rejected: breaks the literal
source-text cohort invariant in `cron-safe-commit-parity.test.ts` across 8 files, to no benefit the
additive split does not already provide.

**Make `paths` required on the committed arm.** Rejected: ~38 handler and test consumers construct
that arm, so a required field is a breaking change to all of them for a purely additive signal —
and it would force the replay-resume branch to invent a value it cannot know.

**Treat `paths === undefined` as "nothing committed".** Rejected: it false-REDs every replay-resume,
i.e. it converts a correct run into a page. Undetermined and absent are different states and the
signal must not conflate them.

**Verify the digest by re-reading the repo after the commit.** Rejected as redundant: the commit
scan already knows exactly what it staged. A second read adds an API call and a new failure mode to
re-derive information the writer already had.

**Leave diagnosis to Inngest step history.** Rejected: ADR-030 binds it to `127.0.0.1:8288`, so it
is unreachable without SSH. That is what made H9 undecidable.
