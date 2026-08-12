---
title: The local gate may decline to execute a suite, and every decline is a counted verdict
status: active
date: 2026-08-11
amends: ADR-177
related_adrs: [ADR-133, ADR-177]
---

# ADR-181: `test-all.sh` — relevance-gated suites, and declines that count

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
helper increments both `suites` and a new `skipped` counter, and the decline joins the BREAKDOWN
line ADR-177 established — emitted only when something was killed or declined, immediately before
the terminal marker:

```
=== 292 suites: 289 passed, 0 failed, 0 killed (…), 3 skipped (declined — not relevant to this diff) ===
=== 289/292 suites passed ===
```

**The terminal marker is preserved byte-for-byte, whole.** An earlier revision of this decision
appended `(F failed, S skipped)` to the marker itself, which orphaned every anchored poll of it
and cost a commit spent updating three SKILL.md files to cope. ADR-177's separate-line shape is
strictly better and is adopted here instead: the marker never changes, so no reader is orphaned,
and the breakdown carries the detail. Ordering is load-bearing — both lines are `=== …`-shaped,
so the marker must be LAST for "match the runner's last emitted line" to stay correct.

The numerator **excludes** skips (as it already excludes killed) — with declines counted in
`suites` but not in `failed`, the old expression would have reported a declined suite as PASSED, a
green that is not evidence produced by the very change that added the gate. A consequence worth
naming: on a local run whose diff touches neither battery nor `apps/web-platform/infra/`, the
marker now reads `N-3/N`, so `N/N` is no longer the ordinary local green spelling. The rc file and
the breakdown line are the verdict; the marker is the completion signal.

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

**5. A spawned subagent cannot run the full gate.** `test-all.sh` exits **4** when
`SOLEUR_SUBAGENT=1` is set without `SOLEUR_ALLOW_FULL_GATE=1`, before `tc_acquire` and before the
first suite, so a refused run costs nothing and never takes the advisory lock a legitimate
sibling is queued on. This is recorded here rather than left to prose because it changes the same
surface: three agents running suites concurrently inflated a battery measurement 1.9x, and this
runner now GATES suites on measured cost, so a corrupted measurement propagates into what runs at
all. `4` is deliberately not `3` — see the ADR-177 addendum.

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

**Also harder.** Reading `N/M suites passed` now requires reading the preceding breakdown line to
know whether the run covered everything, and `N/N` is no longer the ordinary local spelling. That
cost is deliberate: the alternative was a number that could not distinguish a gated suite from a
de-registered one.

## What this does NOT claim

- It does **not** claim the gated suites are less important. It claims a diff that cannot reach
  them is not evidence about them either way.
- It does **not** make local green equivalent to CI green. It makes the *difference* visible and
  named, where previously it was invisible.
- It does **not** apply to CI, the merge gate, or `main-health-monitor`. In all three the decline
  is unreachable by construction, not by convention.

## Addendum — 2026-08-12 (#7494)

Append-only, per the corpus convention this ADR itself used when it wrote
`## Addendum — 2026-08-11 (ADR-181)` into ADR-177. The body above records what was decided on
2026-08-11; nothing in it is edited here. Where this addendum corrects a figure or a sentence in
that body, it says so explicitly rather than rewriting it — citation-by-date is what
`principles-register.md` relies on.

### 1. The gated set grows from two batteries to four suites

`C4_PRODUCER_PATHS` gates `plugins/soleur/test/c4-from-components.test.sh`; `GITHUB_SCRIPTS_SUITE_PATHS`
gates `.github/scripts/test/run-all.sh`. Measured skip rates over the last 80 commits on
`origin/main`, replayed with the runtime matcher's own semantics (unanchored `grep -F` of each
declared path against the commit's unioned name blob): **96%** and **56%**. These are **ceilings** —
the runtime unit also folds in uncommitted and untracked work, which can only make a gate arm more
often.

**Predicate-shape rule this change establishes: prefer a directory pathspec over a file
enumeration when the skip rate is unchanged.** A directory is closed under future additions; a file
list is a snapshot that rots on the next arrival. `plugins/soleur/lib` and `.github` are declared
as directories, and the cost was measured at zero (96% either way, because `plugins/soleur/lib/`
appears in 1 of the last 80 commits).

### 2. `N-3/N` in the Decision above is now `N-5/N`

The Decision states *"the marker now reads `N-3/N`, so `N/N` is no longer the ordinary local green
spelling"*, and its worked example shows `3 skipped`. With four relevance-gated suites plus the
infra runner's `not_in_diff` decline, an ordinary docs-only local run declines **five**. This is the
highest-traffic sentence in the ADR: an operator anchored on `N-3/N` reads a healthy run as a
defect. Corrected here rather than silently in the body.

`scripts/test-all.sh` now also prints the recovery lever once when anything was declined
(`SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh`). It previously appeared exactly once in the
whole runner — inside `_diff_touches`'s early return — and was printed nowhere, while the infra
runner advertised its own lever in two places. A decline is only safe while it stays actionable.

### 3. Mitigation layer 3 does not generalise — the stack is four layers for the batteries and three for the new suites

The Consequences list gives *"Both batteries already hard-abort on a missing declared path"* as one
of four stale-predicate mitigations. The c4 suite does the **opposite**: it *degrades*
(`status=degraded reason=likec4-unavailable` → SKIP). So that layer is unavailable for the two
newly gated suites, and the mitigation stack must be read per-suite, not as a blanket four.

**Corollary, and it is the sharper half: the re-run command `skip_suite` prints for the c4 suite
can exit 0 while producing no evidence.** In a degraded `likec4` state the recovery path itself
carries the green-that-is-not-evidence shape this ADR exists to close. A reader who follows the
printed command and sees exit 0 has not necessarily obtained the coverage the decline withheld.

### 4. Two soundness gaps closed in `scripts/lint-orphan-test-suites.sh`

- **`RELEVANCE_ARRAYS` had no dispatch floor.** Emptying it made the entire anti-rot block iterate
  zero times while the linter printed `orphan test suites: none`. The floor is now **derived** from
  the runner (`grep -c` of the `_diff_touches "${ARRAY[@]}"` call shape), not a literal — which
  catches strictly more: a literal can only see the list shrink, while a derived `want` also
  catches a gate added to `test-all.sh` and never registered.
  **The character class is `[A-Z0-9_]+`, not `[A-Z_]+`.** Measured during implementation: the
  digit-free form counted 3 of 4 gates, because `C4_PRODUCER_PATHS` carries a digit. That
  under-counts `want`, so the floor is satisfied by a shorter list and passes over exactly the gate
  it could not see — the worst possible failure shape for a floor.
- **The `TEST_RELEVANCE_PREFIXES` invariant was enforced by nothing.** `test-relevance-paths.sh`
  states it in prose (*"the union of the top-level prefixes every declared path lives under"*);
  measured, the linter referenced that array **0** times. A declared path outside every prefix is
  invisible to the untracked-file arm, so a session that ADDS a target there and runs the gate
  before committing gets the suite declined on the one diff that needed it.

### 5. The declaration contract is FIVE sites, not four

Decision 3 above enumerates the contract. The fifth is `TEST_RELEVANCE_PREFIXES`. The full list now
lives in a `HOW TO ADD A RELEVANCE GATE` block at the top of `scripts/lib/test-relevance-paths.sh`,
where a reader adding a gate actually lands — three of the five were previously discoverable only
by reading an archived plan.

### 6. Alternatives Considered (additions)

- **Gate the `apps/web-platform` vitest suite — REJECTED on measurement.** Its honest predicate is
  reached by 75 of the last 80 commits (~6-7% skip), because the suite contains genuine repo-wide
  parity guards that pin the rate near-constant. The originally proposed lever does not exist:
  `vitest --shard=K/N` partitions the *collected* set arithmetically and cannot select by path. And
  the cheap-looking derivation is unsound — 156 test files reference `knowledge-base/`, 54 of those
  also call `readFileSync`, and the literals are synthetic in-memory fixtures indistinguishable by
  grep from real reads. Tracked as a **sized** deferral in **#7498**, against a live 48%
  counterfactual (39 of 80 commits touch no `apps/web-platform/` file), not a floor that cannot
  fire.
- **A static `skip_suite` pairing check in the linter — REJECTED, and it was broken on arrival.**
  `RELEVANCE_ARRAYS` maps an array to its battery's **file path**; `skip_suite`'s first argument is
  a **display label**, and in this repo the two differ for both existing batteries. Verified: the
  proposed grep matched **neither**. It would have reddened a clean tree for two correctly-wired
  suites — and because the two new arrays happen to have `label == path`, 2 of 4 would have passed,
  so the failure would have read as real drift. The property is already asserted behaviourally, and
  a behavioural assertion that the skip *fires with the right label* is strictly stronger than a
  static grep.

### 7. Consequences — and an explicit refusal to state a wall-clock saving

**No aggregate per-run saving is claimed, and none should be quoted from this change.** #7494 was
filed quoting 429 s for the c4 suite and 95 s for the `.github` runner. Re-measured during
implementation, three consecutive reps of an **unchanged** tree gave 23 s / 34 s / 91 s for the
first and 163 s / 205 s for the second — taken while two sibling `test-all.sh` runs from another
worktree were active. The spread is wider than the quantities being compared, and it moves in
*both* directions relative to the filed figures, so this machine cannot resolve the cost.
`cq-ac-must-not-depend-on-concurrent-sessions` is applied here to the *justification*, not only to
an acceptance criterion: the decision variable is the **skip rate**, which is a deterministic
`git log` replay that load cannot touch. Decision 5 of this ADR already records a measured 1.9x
contention inflation; this is the same effect, observed again.

**The two new suites' CI protection is ASYMMETRIC.** `.github/scripts/test/run-all.sh` has a
second, independent CI home — the `guard-script-fixture-tests` job in `pr-quality-guards.yml`,
required and path-filter-free. The c4 suite has **exactly one**: `bash scripts/test-all.sh scripts`
in `ci.yml`. Its CI coverage therefore rests entirely on the `CI` early return *inside the file
this change edits*. If those early returns were altered, that suite would run in zero runners
everywhere at once and nothing outside `test-all.sh` would notice — which is why the merge-base
byte-identity check on `run_suite` / `skip_suite` / `_diff_touches` is the load-bearing criterion
for changes in this area, not the skip rates.
