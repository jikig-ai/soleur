---
title: The local gate may decline to execute a suite, and every decline is a counted verdict
status: active
date: 2026-08-11
---

# ADR-178: `test-all.sh` — relevance-gated suites, and declines that count

## Context

A full local `scripts/test-all.sh` run measured roughly 45 minutes across ~289 suites, and its
`TEST_TIMING_LOG` showed two mutation batteries holding **38.6%** of that wall clock:

| Suite | Measured | Share |
|---|---:|---:|
| `tests/scripts/registry-gate-mutation-battery` | 860,692 ms (~14.3 min) | ~31.6% |
| `scripts/cf-tunnel-liveness-gate-mutations` | 189,289 ms (~3.2 min) | ~7.0% |

Both guard narrow paths that most PRs never touch. The runner already had this pattern — the
infra relevance gate runs `apps/web-platform/infra/run-registered-suites.sh` only when the diff
touches that directory — but it was expressed as an `if` wrapped around a `run_suite` call, and
that shape carries a defect.

`run_suite` increments `suites` on **entry**. Wrapping the call in an `if` therefore removes the
suite from the denominator entirely, so `N/N suites passed` reads **identically** whether a suite
was deliberately gated or had been silently DE-REGISTERED. That is the #3366 class one level up:
a suite running in zero runners behind a green summary. Generalising the `if` shape to two more
suites would have multiplied a known defect rather than reusing a known-good pattern.

There is a second force. `run_suite` is the function every one of the ~289 suites flows through,
so a change to it has a genuinely repo-wide blast radius, and a future engineer reading only the
existing ADRs would be misled about what `N/N suites passed` now means. That is what makes this a
decision worth recording rather than an optimisation worth committing.

## Decision

`scripts/test-all.sh` gains a **third suite outcome** beside pass and fail: a suite may be
DECLINED because the run's diff touches nothing it guards. Four properties are load-bearing.

**1. A decline is a counted verdict, not an absence.** A `skip_suite <label> <reason> <rerun-cmd>`
helper increments both `suites` and a new `skipped` counter. The terminal summary becomes:

```
=== 287/289 suites passed (0 failed, 2 skipped) ===
```

The `=== N/M suites passed` **prefix is preserved byte-for-byte**. It is the documented poll
target for long runs (`plugins/soleur/skills/one-shot/SKILL.md`) and is quoted as the thing to
read in roughly thirty learnings; substituting the whole line would orphan every one of those
readers at once. The numerator now **excludes** skips — with declines counted in `suites` but not
in `failed`, the old expression would have reported a declined suite as PASSED, a green that is
not evidence produced by the very change that added the gate.

**2. Every decline is loud and actionable.** It prints the suite label, a machine-readable reason,
and the exact command that re-runs it, and it writes `skip=<reason>` to `TEST_TIMING_LOG` as a
**labelled** field 3. Field 3 already carries the bare `FAIL` marker, so an unlabelled append
would be positionally ambiguous across the ok / FAIL / skip shapes — the same reasoning the
existing `tmp_delta=` field already applies.

**3. Predicates are declared as data, referenced by name, and asserted to resolve.** Both path
lists live in `scripts/lib/test-relevance-paths.sh` as declarations only — no `set -e`, no side
effects — and are sourced by `test-all.sh` and by `scripts/lint-orphan-test-suites.sh`.

- **No path literal may appear on a `run_suite` line.** `lint-orphan-test-suites.sh`'s per-suite
  anchor is satisfied by any `scripts/*.test.sh` appearing after the `run_suite ` token, so an
  inline predicate list would satisfy the registration check for a **different** suite than the
  one executed — and deleting that suite's real registration would still report `orphan test
  suites: none`. `skip_suite ` cannot match `^[[:space:]]*run_suite `, so the sibling helper is
  invisible to that anchor by construction.
- **Each array contains its own battery file.** That single element makes new-target drift
  self-correcting: a commit teaching a battery to mutate something new necessarily edits the
  battery, necessarily matches the predicate, and necessarily runs the suite.
- **The data file is sourced fail-CLOSED.** Absent predicates would decline every gated suite
  while the summary still read green, so a missing file exits 2 rather than degrading. This is
  deliberately unlike the sibling contention lib, which is observe-only and degrades to no-ops.

**4. A decline is UNREACHABLE under CI, not merely detected.** `_diff_touches` returns true
unconditionally when `CI` is set or `SOLEUR_TEST_FORCE_ALL=1`, and an undeterminable diff runs
everything (fail-SAFE). Making the decline unreachable is both stronger and smaller than asserting
it did not happen: on `main` both diff refs resolve and return **empty**, so `_diff_detect_ok` is
1 and the fail-SAFE arm does not rescue it — every gated suite would decline and an
"assert no skips occurred" check would have reddened `main-health-monitor` every six hours.

**Scope.** This is a **local-run optimisation only**. CI runs everything by construction, and
`main-health-monitor` runs the full un-gated set every six hours (Inngest cron
`cron-main-health-monitor`, `0 */6 * * *`). The infra runner's own pre-existing decline is
deliberately **not** forced under CI: infra has dedicated coverage via `infra-validation.yml` plus
that monitor's separate `TEST_GROUP=infra` step, whereas the two batteries have no CI home outside
the scripts shard — which is exactly why the CI bypass must reach them and not it.

## Alternatives Considered

- **`run_suite --skip-if-not-relevant "<inline paths>"`** — REJECTED. Inline paths on a
  `run_suite` line false-match the orphan linter's per-suite anchor (above), so a predicate path
  could register a suite that was never executed. The reasoning was already written twenty lines
  away in that linter, where `REQUIRED_RUNNERS` anchors on the **command** rather than the label.
- **A `run_suite_if_relevant` wrapper** — REJECTED. Breaks the literal `run_suite ` token the
  linter anchors on, disarming registration detection for the wrapped suites.
- **Keeping the `if`-around-`run_suite` shape** — REJECTED. That shape *is* the denominator drift;
  generalising it would have spread the defect to two more suites.
- **A CI assertion that no skip occurred** — REJECTED. Would have reddened `main-health-monitor`
  every six hours (see Decision 4). Forcing the predicate true under `CI` deletes the assertion
  entirely and is strictly stronger.
- **`TEST_GROUP=heavy` as the escape hatch** — REJECTED. `TEST_GROUP` is a shard **partition**
  selector validated by a fail-closed `case`; a value meaning "all, plus force" breaks the
  invariant every `want_*` helper reads. `SOLEUR_TEST_FORCE_ALL=1` is orthogonal to the partition.
- **A relevance manifest file + a dedicated linter + an `--explain` mode** — REJECTED. Three new
  artifacts duplicating data the batteries already declare, plus a drift-detector for the
  duplication it had just created. Two arrays in a data file and ~25 lines folded into the
  existing linter carry the same guarantee.
- **Set-equality between the arrays and the batteries' own declarations** — REJECTED. The
  batteries declare their dependencies in four incompatible shapes — shell variables, a bare
  inline literal, an unquoted `for` list, and a *transitive* dependency living in a sibling
  suite's `W7_EXPECTED` — so the checker would be a second implementation of the batteries'
  semantics written by the same author in the same session, inheriting the same blind spot.
  Battery self-inclusion, the batteries' own hard-aborts on a missing declared path, and
  unconditional CI cover the window instead.
- **A new nightly workflow for the gated set** — REJECTED, because it already exists.
  `main-health-monitor.yml` runs the full un-gated gate every six hours. It has no `schedule:`
  block (scheduling moved to Inngest as the single substrate), which is why a
  `grep -l 'schedule:'` sweep reports it absent; grep for the thing being scheduled, not the
  scheduling keyword.

## Consequences

**Easier.** A typical local full-gate run on a diff touching neither battery drops by ~38.6%,
from ≈45 min to ≈28 min, with zero coverage loss: those suites guard paths the diff does not
touch, CI runs them regardless, and the monitor re-runs everything every six hours. A declined
suite is now visibly declined rather than silently absent, and the pre-existing infra denominator
drift is retired in the same change.

**Harder — and this is the risk to name.** A predicate can go **stale**: a declared path is
renamed, the predicate stops matching, and the suite is declined locally forever — because the
edit that broke the predicate is the edit that would otherwise have re-armed it. No later change
fixes it, which makes this the single most likely way this decision ships a green that is not
evidence. Four layers mitigate it, and deliberately none of them re-runs the predicate's own
logic:

1. `scripts/lint-orphan-test-suites.sh` asserts every declared element resolves via
   `git ls-files --error-unmatch`, that each array contains its own battery path, that no array is
   empty (a fail-closed vacuity guard — without it every other check passes over nothing), and
   that `test-all.sh` still *references* each array.
2. Each array contains its own battery file, so a commit adding a mutation target runs the suite.
3. Both batteries already hard-abort on a missing declared path.
4. CI and the six-hourly monitor run everything, where a decline is unreachable.

**Also harder.** Reading `N/M suites passed` now requires reading the parenthesised breakdown to
know whether the run covered everything. That cost is deliberate: the alternative was a number
that could not distinguish a gated suite from a de-registered one.

## What this does NOT claim

- It does **not** claim the gated suites are less important. It claims a diff that cannot reach
  them is not evidence about them either way.
- It does **not** make local green equivalent to CI green. It makes the *difference* visible and
  named, where previously it was invisible.
- It does **not** apply to CI, the merge gate, or `main-health-monitor`. In all three the decline
  is unreachable by construction, not by convention.
