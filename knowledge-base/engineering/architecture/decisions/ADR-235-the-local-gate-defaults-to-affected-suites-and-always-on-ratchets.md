---
title: The local gate defaults to the affected set plus always-on ratchets; the full battery is CI or explicit --full
status: active
date: 2026-09-18
amends: ADR-181, ADR-183, ADR-196, ADR-133
related_adrs: [ADR-181, ADR-183, ADR-196, ADR-133, ADR-177]
---

# ADR-235: `test-all.sh` — the local gate defaults to the affected set plus always-on ratchets (#8322)

## Context

The local `test-all.sh` invocation ran the full battery unconditionally — ~46
minutes serial, measured. Three observations made the cost wrong, not merely
high:

- **The full battery finds nothing that the affected surface misses.** The
  #8270/#8231 review session produced 24 findings, 8 of them P1 — every one
  from affected suites, the always-on ratchets, review agents, or direct
  probes. The full battery produced zero findings.
- **The full battery is the contended resource.** Over roughly three hours the
  #8270 gate was refused twice (`rc=4`, `CAPACITY_CONTENDED
  reason=sibling_runs`) and expired once at its watcher cap, because five
  sibling worktrees were each attempting their own full gate on the same
  host. The affected set still carries the ~130 always-on ratchets (~22.5
  minutes on the measured `feat-one-shot-8231` serial baseline), so the win
  is roughly half the wall time plus exemption from the contention refusals —
  it is the narrow gate, not an opportunistic second battery.
- **Selection machinery already existed.** `scripts/lib/test-affected-paths.sh`
  did not; but the runner already computed the diff (`_diff_names`,
  `_diff_detect_ok`), already relevance-gated five suites via
  `test-relevance-paths.sh`'s `*_PATHS` arrays, and already had decline
  accounting (ADR-181). What was missing was the inverse: *positive selection*
  of what the diff can move, plus a ratchet floor that never narrows.

The merge gate is unchanged: CI's required `test` context runs the full
battery, sharded, on the PR head (ADR-183 — no local run is the merge gate).
What changes is the local default, which was the same battery paid at every
commit hook.

## Decision

1. **Local `test-all.sh` defaults to `--affected`.** A local non-CI invocation
   with no mode flag runs the suites the diff can move — classified
   `edge:consumed`, `edge:declared`, `edge:derived` through argv self-edges,
   source/import closure, name-stem resolution, and the declared edges in
   `scripts/lib/test-affected-paths.sh` — plus every `ALWAYS_ON_SUITES`
   repo-global ratchet (`*-live` scanners, runner-SUT suites, corpus linters).
   `edge:declared`/`edge:consumed` UNION with derivation rather than shadow
   it: a declared array records only what derivation could not reach at write
   time, so a dependency a suite gains afterwards widens its edge set instead
   of being declined behind a stale declaration.
   CI (`CI` set) and explicit `TEST_GROUP` group runs are unaffected; CI keeps
   the full battery.

2. **`--full` is the only spelling of the local full battery.** It arms the
   legacy force-all semantics (`_diff_touches` always true, the infra-arm
   conjunct) explicitly. `SOLEUR_TEST_FORCE_ALL=1` keeps its narrower
   relevance-only meaning and does NOT arm the infra conjunct — under affected
   mode it degrades the selection to full via the fallback ladder instead.

3. **Selection uncertainty fails toward coverage.** `AFFECTED_FALLBACK
   reason=undecidable-diff` (diff flags disagree), `reason=index-missing`
   (declarations lib absent), `reason=runner-changed` (the diff touches
   `test-all.sh` or the index itself), and `reason=force-all` each degrade the
   run to the full battery with a printed banner — never silently narrow. A
   gutted declarations file (`|ALWAYS_ON|` below the runner's
   `_MIN_ALWAYS_ON_DECLARED` floor — the *live-derived* `*-live` floor lives in
   the orphan linter's census) or an empty effective selection refuses `rc=4`
   (`AFFECTED_UNRESOLVED`) before anything runs.

4. **Affected mode is exempt from BOTH full-gate refusal arms.** ADR-196's
   subagent arm and sibling-contention arm now check the resolved mode: pure
   `--affected` runs proceed (they are the narrow gate the refusal exists to
   steer toward), `--full` runs refuse as before, and a run that DEGRADED to
   full re-checks both arms post-derivation — a degraded run IS a full battery,
   the thing the sibling guard exists to serialize. This is a deliberate
   deviation from the plan's "refusals unchanged" note, recorded so the
   reasoning is not re-derived: without it, every `git commit` on a branch that
   touches the runner or index (this one, permanently) would refuse while any
   sibling held a gate.

5. **Enumerate is never affected-filtered.** `--enumerate` and
   `--enumerate-commands` answer "what is registered" — they emit the full
   stream regardless of mode flags, and the affected classifier's own pre-pass
   is a nested `--enumerate-commands` self-call. This resolves the spec's
   ambiguity ("composes with `--enumerate`") in favour of the enumerate
   contract's consumers, which invoke it repeatedly to count registrations.

6. **`TEST_GROUP=<g>` is an explicit cross-cut, not the selection mechanism.**
   A non-`all` group ask force-selects that group's registrations rather than
   intersecting them away — an explicit ask must produce an executed suite, not
   a counted `not-affected` decline that sets `_infra_ran` on a suite that
   never ran (the Phase 0-reproduced false-coverage seam ADR-181's accounting
   would otherwise admit).

7. **Declines stay counted; the numerator subtracts them.** The ADR-181 decline
   machinery is preserved — `not-affected` is a fourth decline class with a
   distinct counter, included in the denominator and excluded from `passed`.
   The epilogue prints the `--full` recovery lever once, so a run with
   declines names its re-run.

8. **Token-level diff edges are deferred.** Spec FR2 listed diff-content token
   edges; both review panels converged on cutting them — they are a
   narrowing-only win that requires a second diff-content channel, and the
   unclassified→always-run rule already covers the gap at battery-cost, not
   correctness-cost.

## Consequences

- The local gate is minutes-scale by default. The serial battery still runs —
  on CI, and locally under `--full` or any fallback arm.
- **ADR-181's premise is narrowed, not reversed.** Relevance declines still
  exist for the five consumed-edge suites; what changes is that the *default*
  local run positively selects instead of running-everything-and-declining.
- **ADR-183's ship default moves.** `/ship` Phase 4 dispatches
  `battery-owed.sh` first; OWED (or any non-42 verdict) runs `--affected`,
  and `--full` is an explicit operator opt-in that outranks even a SKIPPABLE
  verdict — the operator who typed `--full` asked for the battery itself, not
  a dedup decision.
- **ADR-196's Decision 6 is stale in one direction.** It asserted the two
  git-hook invokers "invoke the full gate deliberately and both set
  `SOLEUR_ALLOW_FULL_GATE=1`". Post-#8322 both invoke `--affected` with no
  hatch — the exemption is structural, not a grant. The refusal arms still
  exist and still bind to full-shaped invocations; `fanout-suite-scope.test.sh`
  Arm 11 pins the matrix.
- **ADR-133's contention machinery is demoted to the rare full path.** The
  flock, the sibling census, and the preamble still gate full batteries; the
  common local run no longer pays the census's measured-full cost.
- A healthy affected run reports `N-k/N` with a `not-affected` breakdown —
  `N/N` is now the exception, and a reader must not read the smaller numerator
  as incompleteness.
- **Accepted niche: a diff that ONLY deletes a derivable SUT.** Edge
  registration filters on `[[ -e ]]`, so a pure deletion diff never matches an
  edge that no longer exists — a suite whose SUT vanishes in the same commit
  declines. This is bounded (deleting a SUT while keeping its test is rare,
  and always-on ratchets still run) and fixing it would mint dead edges for
  argv tokens that merely look like paths — the `[[ -e ]]` test is the garbage
  filter that keeps the edge set honest. Fail-safe via `unclassified` already
  covers the common case (the deletion removes the suite's only edge).

## Alternatives considered

| Alternative | Why not |
|---|---|
| Keep the full battery as the local default, `--affected` as opt-in | Inverts the measured value: the full battery produced zero of the 24 motivating findings while being refused three times for contention. The expensive default should be the opt-in. |
| Refusal arms still bind affected runs (plan's original FR8) | Would refuse every commit on runner/index-touching branches whenever a sibling holds a gate — the self-edge makes degraded-full the *common* case there, and the refusal would gate commits, not batteries. |
| Refuse affected runs that degrade under contention | That IS the design — degradation re-checks the arms. What changed is the *pure*-affected exemption. |
| Token-level diff edges | Narrowing-only win; needs a second diff-content channel; unclassified→always-run already fails safe. Deferred, not rejected. |
| Let enumerate filter by mode | Breaks every enumerate consumer that counts registrations; the classifier itself depends on the unfiltered stream. |

## References

- Issue: #8322; motivating review session: #8270/#8231; duplicate-full-run
  dedup: #8247 (`battery-owed.sh`); prior affected-test win: #8045.
- Plan: `knowledge-base/project/plans/archive/20260920-163321-feat-test-all-affected-gate-default-plan.md`
- Index: `scripts/lib/test-affected-paths.sh`; classifier + mode matrix:
  `scripts/test-all.sh`; mutation suite: `scripts/test-all-affected.test.sh`.
