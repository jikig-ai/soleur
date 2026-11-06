# Architecture Review — PR #11603 (feat-one-shot-11600-job-log-step-attribution)

**Seat:** soleur:engineering:review:architecture-strategist
**Scope:** `git diff origin/main...HEAD` — `scripts/followthroughs/web-first-deploy-10585.sh` (+94/−20),
its test suite (+143/−2), `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
(+16), and spec artifacts (plan 273, decision-challenges 31, session-state 34, tasks 37).
**Suite status:** `web-first-deploy-10585.test.sh` — **69 passed, 0 failed** (verified locally).

## Verdict: SHIP — no blocking findings (P1: 0, P2: 1, P3: 3)

---

## 1. Architecture Overview

`scripts/followthroughs/` is a fleet of ~180 **self-contained, single-file probes** — no shared lib,
no cross-script sourcing; each carries its own stub-`gh` test harness. The domain convention for
shared knowledge is the doctrine file (`followthrough-convention.md`), not a library. This PR adds a
second carrier of the attribution-expired recovery idiom (region-slice on `##[group]Run` headers
keyed on the step's `started_at`, global CR+BOM strip), adapted verbatim from
`git-data-boot-poll-8178.sh:204-207`, with sibling probes explicitly deferred to #11607 (filed).

## 2. Change Assessment

The change fits the architecture cleanly:

- **No boundary or contract changes.** Exit-code map (5/2/3/78, never 0/1) unchanged; the sweeper's
  rc→word map untouched; the jobs-API jq gained one internal column (`started_at`) — not an interface.
- **`emit_rows` is the right chokepoint.** The original #9905 bug class was two copies of the
  emitted-vs-echoed filter drifting. Extracting one awk filter consumed by BOTH the named anchor
  (`print $3 | emit_rows`) and the recovered region (`emit_rows <<<"$region"`) makes that drift
  structurally impossible inside this script. Confirmed the named-path output is byte-equivalent to
  the pre-change inline awk (same `ts`/`line` derivation, same ANSI-ESC drop).
- **BOM/CR strip hoisted ahead of ALL consumers** (`web-first-deploy-10585.sh:287-288`) is a real
  fix, not hygiene: previously a BOM'd section-head line could feed a BOM-prefixed timestamp into
  `ts_to_epoch` → false CANNOT ESTABLISH on the named path.
- **Fail-safe degradation is preserved everywhere new:** `started_at // "-"` → strict regex gate →
  `recovery_cause` diagnostics; empty region / no started_at / patternless region all collapse to
  the existing success-job tripwire (`exit 3`), never a quiet pass. Failure jobs keep the named
  path's best-effort posture — consistent with the probe's documented semantics.
- **Deliberate strictness asymmetry (verified correct, P3 note):** the recovery path tripwires a
  non-empty-but-patternless region; the named path tolerates the same shape. Correct — named
  attribution cannot mis-bind a step; a sliced region can select an adjacent step's output.
- **Verbatim reuse verified:** the region awk is byte-identical to 8178's modulo indentation,
  including the `//` global BOM strip that 8178's comment documents as a hard-won fix. Copying the
  corrected form is the right move; re-deriving it is exactly how the original bug happened.

## 3. Compliance Check

- **AP-011 (ADRs for architecture decisions):** No ADR required — this is an internal probe repair,
  not a new service, boundary, or infrastructure change. The runbook's new "Sharp edges for
  `gh run view --log` probes" section is the correct doctrine vehicle per the followthrough
  convention itself (which prescribes the runbook as the pattern registry).
- **Self-contained-probe convention:** Honored — no new dependencies, no sourcing, no new files in
  the script's runtime path.
- **Never-quiet-on-unmeasured doctrine:** Strengthened, not weakened — attribution expiry now reads
  CANNOT ESTABLISH with a named cause instead of silent population-0 or a bare "log shape drifted."
- **Test architecture:** Fixture fidelity is high and load-bearing — per-section BOM with a bare
  stream head (matching the measured 14/15 BOM'd headers on job 106093730126), a pre-`started_at`
  prelude exercising the `ts >= ps` skip gate, an EOF-terminated region arm, a mixed-attribution
  supersession arm, and a `started_at: null` arm. The anti-vacuity floor moved 30→69 in step with
  the added cases. The `job()`/`ulog()` builders document *why* each element exists (mutation-pin
  rationale for the second BOM'd section).

## 4. Risk Analysis & Findings

### P2-1 — Region-slice idiom is now copy #2; #11607 makes it copies #3–4 (drift surface)

The derivation (BOM strip + `##[group]Run`/`started_at` region awk) now lives verbatim in two
scripts, and #11607 will add `web-fresh-boot-zot-8651.sh` and `git-data-rehearsal-evidence.sh` —
four independent copies of code that has already needed one subtle fix (the `//`-vs-`/` BOM defect
that made 8178 take its own `_cannot` arm on every real log). A future correction will have to be
propagated by hand, and 8178's own history shows the failure is silent.

*Mitigations already in place:* the runbook section names the derivation precisely, and this
script's header cites `git-data-boot-poll-8178.sh` as the source. The self-contained-probe
convention (no `lib/` exists anywhere under `scripts/followthroughs/`) weighs against a quick
extraction now.

*Recommendation:* when #11607 lands, either (a) extract the idiom into a shared
`scripts/followthroughs/lib/` unit the carriers source, or (b) add a normalized-parity check that
pins all carriers' region-awk blocks to the same text, the way logic-parity drift guards work for
workflow scripts. Failing both, ensure each new copy carries the same "derived from 8178; keep in
parity" provenance header this one has.

### P3-1 — Recovery is gated on an EMPTY named-path trail (partial attribution suppresses it)

Recovery runs only under `[[ -z "$trail" ]]`. If GitHub ever returns a partially-attributed log —
a stray named line plus the trail step's real output under `UNKNOWN STEP` — the non-empty named
trail suppresses recovery and could quiet-miss a proven boot (e.g., pointer attributed, `ready`
expired → "no proven boot"). Attribution expiry is all-or-nothing per job today, so this is
theoretical; a one-line comment pinning the all-or-nothing assumption would keep the next reader
from "fixing" the gate asymmetrically.

### P3-2 — `emit_rows` emits a bare `\t` row for a space-less / empty-$3 input line

A step-matched log line with an empty third field (or a region line with no space) flows through
`emit_rows` as `ts=""`, `content=""` → a `\t` row, making `trail` non-empty and suppressing both
recovery and the success tripwire. This is **pre-existing** behavior carried verbatim from the old
inline awk — recorded so a future hardening isn't applied to only one of the two callers.

### P3-3 — Path-strictness asymmetry is load-bearing (do not symmetrize)

Recovery downgrades a non-empty-but-patternless region to `trail=""` (tripwire), while the named
path accepts the same shape as a valid empty trail. This is correct and documented in-code — a
mis-bound region returning an adjacent step's chatter is a real failure mode; a named anchor
cannot mis-bind. Flagged so reviewers don't collapse the branches.

## 5. Recommendations

1. (P2-1) Address the multi-copy drift surface at #11607: shared lib or parity guard, or at minimum
   the provenance header on every carrier.
2. (P3-1) Optional one-line comment noting recovery assumes all-or-nothing attribution expiry.
3. No other changes requested — the design is cohesive, the test matrix covers the recovery arms
   (success/failure conclusion, missing `started_at`, early/absent header, EOF region, ANSI filter
   reuse, cross-mode supersession), and the runbook codifies the pattern for the sibling probes to
   come.
