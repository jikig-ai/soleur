---
title: "Widen the anti-vacuity floor hardening across the bash suite corpus"
date: 2026-08-16
slug: feat-widen-anti-vacuity-floor
branch: feat-one-shot-anti-vacuity-floor-widen
lane: procedural
type: refactor
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Overview

Commit `f84e508` (merged 2026-08-16) hardened two delivery-path suites against a defect
in which a suite's own anti-vacuity floor is enforced *through* the assertion machinery
the floor exists to survive. This plan extends that hardening to the rest of the bash
suite corpus and replaces the hardcoded two-suite population in
`scripts/guard-vacuity-floor.test.sh` with a derived one.

The defect has two halves. The first: a floor that reports by calling `fail`/`bad`
increments the same counter the suite's exit status reads, so neutering that function
silences both the assertion rows and the floor meant to notice the silence — the suite
prints a total and exits 0. The second, and the one that actually bites: the floor only
catches *"no assertions ran"*. It cannot catch *"assertions ran and their verdicts were
discarded"*, because the case counter is incremented by the assert helpers and never by
`fail`. Stub `fail` to a no-op in a real suite and the counter stays at full value, the
floor is satisfied, and the run exits 0 with real failures hidden.

The reference fix carries three properties: a floor that reports with `printf >&2` +
`exit 1` directly; an accounting-conservation check that `passes + fails` equals `cases`,
also reported directly; and floors ratcheted to the exact current count with zero slack.

---

## Deepen-Plan Revisions

Three review passes ran against the first draft. Each falsified something by **construction
or measurement**, not by argument, and the plan below is the revised one. Recorded here
because the reasoning matters more than the conclusions.

| # | First draft said | Measurement | Revision |
|---|---|---|---|
| **R1** | A declared `# vacuity-contract:` comment on 40 suites is required, because "nothing here is safely pattern-substitutable" and `ok`/`bad` suites cannot be handled generically. | A ~20-line generic `build_mutant` with **zero** declarations discriminated **8/8** — every tier-1 suite exited 0 (the defect), all three compliant suites exited non-zero. `command_not_found_handle() { return 0; }` neuters *every* helper name at once, including `ok`/`bad`. | **Contract-line design cut entirely.** Derivation replaces declaration. 33 files no longer touched. |
| **R2** | Population is 40, swept from `scripts/*.test.sh` + `plugins/soleur/test/*.test.sh`. | Repo-wide, **74** suites carry an assertion floor, across **9** directories. `apps/web-platform/infra/` alone holds **28**. Worse, `scripts/*.test.sh` is a *non-recursive* glob (59 files) while the classification used recursive `find` (78) — so the plan's own tier-2 member `scripts/followthroughs/infra-config-activation-7220.test.sh` was outside the sweep that was supposed to find it. | **Scope restated with a counted directory ledger** and a closure identity: `covered + excluded == total swept repo-wide`. |
| **R3** | The mutation arm asserts `rc != 0`. | `build_mutant` slices from the floor's `if`, so a threshold assigned on the **preceding** line is unbound. Under `set -u` the mutant dies *before reaching the floor* — rc=1 for both the pre-fix and post-fix forms. **8 of 11 target floors are equivalent mutants** this way. Reproduced: `MIN_ASSERTS: unbound variable`. | **Reason-asserting oracle.** The arm requires the floor's own `[FATAL]` sentinel on stderr, and classifies `unbound variable` / `command not found` / rc=2 as a distinct, loud **construction failure**. Extraction widened to carry threshold bindings. |
| **R4** | Conservation is fixed by "moving the `ASSERTED` increment to the assert-helper entry point". | For `ok`/`bad` suites there **is no entry point** — the increment is already inside both helpers, which is what makes it a tautology. Stubbing `bad()` drops `fail++` *and* `asserts++` together, so `pass + fail == asserts` still holds. Verified: neutered `bad()` printed `conservation GREEN — defect hidden`, RC=0. | Conservation requires **call-site** `cases` increments (the reference's shape), a per-suite rewrite of 22-27 sites each. Cost stated honestly; a lint added so a missed site cannot rot. |
| **R5** | Preserve `test-contention`'s positive control unchanged. | The control deliberately **rolls back** `pass_n` and `fails` after probing the helpers. A `cases` counter incremented alongside is *not* rolled back, so `passes + fails == cases` would be permanently false by exactly 2 — the suite red on every green run. | Control's rollback extended to `cases`, with a note on why restoring it does not defeat the probe. |
| **R6** | `preflight-check10`'s four floors are all in the mutation population. | Three are **nested and indented** inside an enclosing `if`, and read inputs (`n_manifest`, `n_pass`, `n_expect`, `$MANIFEST`) computed by surrounding code. A truncate-and-run mutant of a nested block is not a runnable program; it dies at an unbound variable. | Those three are **declared out of the mutation arm with a written reason**, and still get direct-exit conversion. Only the `MIN_CHECKS` self-dispatch floor is mutation-tested. |
| **R7** | 9 of 11 floors are at zero slack; only two need ratcheting. | Two floors **self-count**: `derive-app-domain-base`'s floor `else` branch calls `pass(…)` (counted by `EXPECTED_PASSES=34`, pinned *exactly*), and `digest-oracle-guard`'s success arm `ok "assertion floor met…"` increments `asserts`, the floor's own input. Converting either to `printf`+`exit 1` **removes an assertion** and turns the suite red. | Both added to the re-ratchet list. `digest-oracle-guard`'s floor is additionally **inverted** (`-ge`), so conversion means inverting the predicate and dropping the `else`, not swapping a call. |
| **R8** | AC3 verifies conservation per suite. | It was a one-time, hand-run, seven-way manual experiment recorded as prose — never re-run by CI, so a later regression to a tautological check is invisible. Guard 2's ledger row was likewise undrivable. | The conservation arm is a **loop over the derived population**, mirroring the floor arm. |

Carried through unchanged: the population re-derivation that found 7 files instead of 5, the
tautology identification, the extraction-not-restatement principle, the ADR/C4 work, the
Observability block, and the refusal to bundle #7553.

---

## Research Reconciliation — Brief vs. Codebase

Re-derived against the worktree at `feat-one-shot-anti-vacuity-floor-widen` (parent
`4a7e5cb08`) on 2026-08-16. Every row was confirmed by reading or running, not by
pattern-matching.

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "Five suites… five files, seven floors" | **7 files, 11 floors** carry a floor whose failure arm calls the suite's own `fail`/`bad`. | Population is the 7 below. All 11 floors in scope. |
| `tmpfs-guard.test.sh` and `test-contention.test.sh` are false positives — "disk-watermark floors and not assertion floors at all" | **Both are true positives.** Each carries a disk-watermark floor *and* a separate assertion-cardinality guard routed through `fail`: `test-contention.test.sh` → `if [[ "$((pass_n + fails))" -lt 110 ]]; then fail …`; `tmpfs-guard.test.sh` → `if [[ "$pass_n" -lt 60 ]]; then fail …`. | Add both. The earlier reviewer found the right files via the wrong hit; the correction discarded the *files* instead of the *reason*. |
| `preflight-check10-suite-integrity.test.sh` carries three floors (`:197, :270, :276`) | Carries **four**. Three route through `fail` (`:196, :269, :275`); a fourth at `:292` (`MIN_CHECKS`) is the suite's *own dispatch* floor and increments `FAIL` inline. The brief's three all measure the **SUT**; the one it missed is the only one measuring **this suite**. | All four get direct-exit conversion. Only `:292` enters the mutation arm (R6). |
| "the floor routes through `fail`/`bad`, AND the exit status reads that counter" is the population predicate | Sound, and it partitions cleanly — but it is narrower than the corpus of floor-bearing suites. | Predicate retained for the *fix* scope (7). The *guard* population is the swept corpus — see "Scope decision". |
| Floors need ratcheting; "every assertion that PR added was silently deletable (46 and 20 of slack)" | True of the reference suites historically, **not of the 7 targets today**. 9 of 11 floors sit at zero slack. Two carry slack: `derive-app-domain-base` `CASES_RUN` (26 vs 28) and `preflight-check10` `MIN_CHECKS` (11 vs 13). | Ratchet those two, **plus** the two self-counting floors that conversion will move (R7). |
| Task 5: "Register any new `scripts/*.test.sh` in `scripts/test-all.sh`" | **Every target already runs.** The 6 targets under `scripts/` plus `guard-vacuity-floor.test.sh` are explicitly registered (`grep -c` returns 1 each). The 7th, `plugins/soleur/test/preflight-check10-suite-integrity.test.sh`, is **correctly absent** — that directory is auto-globbed, and an explicit line would double-run it. | No-op unless the work creates a new suite file. Retained as an AC running `scripts/lint-orphan-test-suites.sh`. |
| `build_mutant` "extracts the floor block by grepping `^if [[ "$cases" -lt `… the extractor needs generalizing" | Confirmed, and **much larger than the grep**. It also hardcodes the counter declarations, the neutering, the exit trailer, and a floor-block sanity anchor. Beyond that, the `^`-anchor silently misses **indented** floors, and slicing from the `if` line drops threshold bindings (R3). | Rebuilt in Phase 3 around derivation + a reason-asserting oracle. |

### Premise Validation (Phase 0.6)

Independently verified live by a dedicated agent; all eight claims confirmed.

- `f84e508` — confirmed on `main` as `test(plugin): close the four guard-vacuity gaps, each proven by mutation (#7550)`.
- Reference implementation confirmed in both `scripts/plugin-legacy-resolver-probe.test.sh` (floor at `:521`, conservation at `:538`) and `scripts/plugin-delivery-canary.test.sh` (floor at `:1055`, conservation at `:1072`), each reporting via `printf >&2` + `exit 1`.
- Issue **#7553** (`test-all.sh's subagent full-gate refusal can never fire: nothing sets SOLEUR_SUBAGENT=1`) — confirmed **open**. Different subsystem. **Out of scope; must not be bundled and must not be closed.**
- Learning `knowledge-base/project/learnings/2026-08-13-the-fixture-shape-decided-what-the-assertion-could-possibly-catch.md` — confirmed present.
- ADR ordinal: highest **on disk** is ADR-186; highest **claimed across all 69 `origin/*` refs** is ADR-190. Next free is **ADR-191**, *provisional* — re-derive immediately before merge.

---

## Research Insights

### Measured floor inventory (all suites run green, RC=0, on 2026-08-16)

Every number came from executing the suite.

| # | File | Floor | Counter | Declared | Measured | Slack | Failure arm |
|---|---|---|---|---|---|---|---|
| 1 | `scripts/derive-app-domain-base.test.sh` | invocation | `CASES_RUN` | `-lt 26` | **28** | **2** | `fail` |
| 2 | `scripts/derive-app-domain-base.test.sh` | assertion | `passes` vs `EXPECTED_PASSES` | `-ne 34` | **34** | 0 | inline `fails+1` |
| 3 | `scripts/marketplace-manifest-validate.test.sh` | assertion | `ASSERTED` | `-lt 22` | **22** | 0 | `fail` |
| 4 | `scripts/verify-marketplace-ruleset.test.sh` | assertion | `ASSERTED` | `-lt 27` | **27** | 0 | `fail` |
| 5 | `scripts/digest-oracle-guard.test.sh` | assertion | `asserts` vs `MIN_ASSERTS` | **`-ge 26`** (inverted) | **26** at check, 27 total | 0 | `bad` |
| 6 | `scripts/test-contention.test.sh` | cardinality | `pass_n + fails` | `-lt 110` | **110** | 0 | `fail` |
| 7 | `scripts/tmpfs-guard.test.sh` | cardinality | `pass_n` | `-lt 60` | **60** | 0 | `fail` |
| 8 | `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | manifest (SUT) | `n_manifest` | `-lt 126` | **126** | 0 | `fail` (nested) |
| 9 | `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | tests (SUT) | `n_pass` | `-lt 131` | **131** | 0 | `fail` |
| 10 | `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | asserts (SUT) | `n_expect` | `-lt 537` | **537** | 0 | `fail` |
| 11 | `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | own dispatch | `PASS + FAIL` vs `MIN_CHECKS` | `-lt 11` | **13** | **2** | inline `FAIL+1` |

Counter names differ across all seven suites (`passes`/`fails`, `PASS`/`FAIL`/`ASSERTED`,
`pass`/`fail`/`asserts`, `pass_n`/`fails`, `CASES_RUN`), as do helper names (`pass`/`fail`
vs `ok`/`bad`), floor polarity (`-lt` vs `-ge`), and indentation.

**Two floors self-count (R7).** Row 1's `else` branch calls `pass "anti-vacuity floor: …"`,
which `EXPECTED_PASSES=34` pins *exactly*; row 5's success arm `ok "assertion floor met …"`
increments `asserts`, the floor's own input. Converting either to a direct exit **deletes an
assertion**, dropping the suite below its own pin. Both must be re-ratcheted in the same edit.

### Conservation is not portable — the central technical finding

`passes + fails == cases` is load-bearing only when `cases` is incremented **independently of
the verdict**. **None of the 7 targets has that shape.**

| Suite | Counter shape | Conservation as-written |
|---|---|---|
| `marketplace-manifest-validate` | `ASSERTED` incremented inside **both** `pass()` and `fail()` | **Tautology** |
| `verify-marketplace-ruleset` | same shape | **Tautology** |
| `digest-oracle-guard` | `asserts` incremented inside **both** `ok()` and `bad()` | **Tautology** |
| `derive-app-domain-base` | `passes`/`fails`; `CASES_RUN` counts *script invocations* | **Not expressible** at assertion level |
| `test-contention` | `pass_n`/`fails` only | **Not expressible** |
| `tmpfs-guard` | `pass_n`/`fails` only | **Not expressible** |
| `preflight-check10-suite-integrity` | `PASS`/`FAIL` only | **Not expressible** |

Measured (R4): with `ok`/`bad` both bumping `asserts`, stubbing `bad()` drops the verdict
*and* the count together — `pass=2 fail=0 asserts=2`, `conservation GREEN — defect hidden`,
RC=0. So "move the increment to the entry point" is not available for these suites: **there is
no entry point.** The reference increments `cases` at the **call site** — `plugin-legacy-resolver-probe.test.sh`
has bare `cases=$((cases + 1))` at seven distinct sites, with `pass()`/`fail()` touching only
`passes`/`fails`. Porting that means 22-27 call-site edits per suite, and **any missed site makes
conservation permanently unequal and the suite permanently red**. Phase 2 states this cost and
adds a lint so a future contributor cannot silently omit one.

### Corpus scope — the true population is 74, not 40

Derived repo-wide over every tracked `*.test.sh` using the structural floor-shape signal.

| Directory | Floor-bearing | In this PR's guard scope? |
|---|---|---|
| `scripts/` | 30 | **yes** |
| `apps/web-platform/infra/` | **28** | no — deferred, counted |
| `plugins/soleur/test/` | 9 | **yes** |
| `.claude/hooks/` | 2 | no — deferred, counted |
| `scripts/followthroughs/` | 1 | **yes** (recursive) |
| `plugins/soleur/skills/{incident,git-worktree}/test/` | 2 | no — deferred, counted |
| `apps/web-platform/scripts/` + `scripts/lib/` | 2 | no — deferred, counted |
| **Total** | **74** | **40 covered / 34 deferred** |

The prose in the first draft said `scripts/*.test.sh` — a **non-recursive** glob matching 59
files, where recursive `find` matches 78. That discrepancy alone would have excluded
`scripts/followthroughs/infra-config-activation-7220.test.sh`, a suite the plan had itself
classified into the population. The sweep is therefore specified as a recursive enumeration
over tracked files, never a shell glob.

### Applicable institutional learnings

- `2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md` — a guard and the thing it guards cannot share a failure mode; the floor must `exit 1` directly *and* audit the conservation law.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — a matrix that mutates only the SUT cannot see a vacuous harness; needs must-RED rows against the guard and a must-PASS input that is not the canonical.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — a floor indexed to its own input is not a floor; thresholds must be absolute and hand-ratcheted.
- `2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md` — a test asserting a guard's *shape* cannot see a guard that does not *run*; never use `sed` ranges, which re-arm after the terminator.
- `2026-08-10-the-lever-had-never-run-and-every-guard-was-satisfied-by-its-own-comment.md` — a counter incremented inside `$( )` is discarded to a subshell. Directly binding: the `cases` counters introduced here must never sit inside command substitution.
- `2026-08-13-the-fixture-shape-decided-what-the-assertion-could-possibly-catch.md` (brief-cited) — fixture topology bounds what an assertion can catch; confirm the mutant's success and failure paths differ materially before reading any row. **R3 is exactly this failure**: 8 of 11 mutants had identical output on both branches.
- `2026-08-13-the-guards-i-wrote-to-prove-the-fixes-had-the-defects-the-fixes-were-about.md` — a red control voids a battery; require a GREEN unmutated control first.

### Repo conventions that constrain the work

- `scripts/*.test.sh` is **NOT** auto-globbed by `scripts/test-all.sh`; each needs an explicit `run_suite`. `plugins/soleur/test/*.test.sh` **IS** auto-globbed. `scripts/lint-orphan-test-suites.sh` fails CI on any unregistered `scripts/*.test.sh`, anchored on the `run_suite` command shape — and it already implements both halves of a population floor (a minimum-cardinality guard *and* a zero-match glob guard). Phase 3.7 mirrors it rather than re-deriving.
- `scripts/lint-shell-capture-exit.py` rejects **new** unprotected `x=$(grep …)` captures (S1) and `count=$(grep -c …) || echo 0` double-emits (S2). Baseline keyed by path + class + normalised text; **may only shrink**.
- `scripts/lint-guard-contract.py` requires per `### Guard` entry: non-placeholder `**Property.**`, non-placeholder `**Assembly.**`, and a `**Mutation matrix**` with `MIN_MUTATION_ROWS = 3` rows.
- CI runs `bash scripts/test-all.sh scripts` (plus `bun`, `webplat`) as matrix shards in `.github/workflows/ci.yml`.

### Skill description budget

No `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate or finalized. Check skipped per Phase 1.8.

---

## Scope decision

Whatever predicate the meta-guard uses *is* the scope, so it is chosen deliberately.

- **Property 1 (floor survives a neutered assertion machinery)** — enforced over the
  **40 suites in `scripts/` (recursive) + `plugins/soleur/test/`**, derived by sweep with no
  declarations and no per-suite exemptions. Tiers 2-3 and the compliant three pass today; only
  the 7 tier-1 suites redden. Three of `preflight-check10`'s four floors are declared out of
  the *mutation* arm (R6) with a written reason, and still receive the fix.
- **Property 2 (accounting conservation)** — applied to the **7** tier-1 suites, whose assert
  helpers this PR already edits, and enforced by an automated loop (R8), not a one-time manual
  experiment. Retained rather than deferred because it catches a strictly different fault: the
  floor catches *"no assertions ran"*, conservation catches *"verdicts discarded"*. The brief
  measured that exact state — `45 passed, 0 failed (48 assertions)`, RC=0, real defect present.
- **Property 3 (ratcheted floors)** — the two slack-carrying floors plus the two self-counting
  floors conversion will move (R7).
- **Deferred, counted, not silent** — the 34 floor-bearing suites in `apps/web-platform/infra/`,
  `.claude/hooks/`, `plugins/soleur/skills/*/test/`, `apps/web-platform/scripts/` and
  `scripts/lib/`. They are held in a **directory-level** ledger with a tracking issue.

**The closure identity is what makes the deferral safe.** Rather than a shrink-only ratchet on
a list of things deliberately not done — which would fail CI on bookkeeping the moment someone
adds a legitimate new suite — the guard asserts:

```
covered + deferred == total floor-bearing suites found repo-wide
```

A new floor-bearing suite anywhere in the repo increments the right-hand side; if it lands in
neither list the identity breaks and the guard reddens naming the file. That is structural,
non-circular, cheap, and it cannot be satisfied by a stale list.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a CI shard (`test-scripts`) failing on every PR
with a `[FATAL]` from `scripts/guard-vacuity-floor.test.sh`, blocking all merges until reverted;
or, quieter and worse, a green suite corpus in which a neutered assertion helper still hides
real failures — the state this work exists to end.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The
change touches only build-time test harnesses; it reads no credentials, writes no persistent
store, and emits no network traffic. No regulated-data surface is involved.

**Brand-survival threshold:** `none`. The blast radius is the repo's own CI signal, not a
user-facing surface. No sensitive path per the preflight Check 6 regex is touched, so no
scope-out bullet is required.

---

## Open Code-Review Overlap

**None.** Queried 65 open `code-review` issues via `gh issue list --label code-review --state
open --json number,title,body --limit 200` and matched each planned file path against every
issue body with `jq --arg`. Zero matches across all planned files.

---

## Implementation Phases

### Phase 0 — Preconditions (no edits)

0.1 Re-run each of the 7 target suites; record exact counts. The inventory table is a
2026-08-16 measurement — a sibling merge can move any of it.

0.2 `bash scripts/guard-vacuity-floor.test.sh` must be GREEN as shipped. A red control voids
every downstream reading.

0.3 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
must be clean **before** any edit; record the baseline's `wc -l`.

0.4 Re-derive the repo-wide corpus count (74 on 2026-08-16) and the covered/deferred split.
These feed the Phase 3.7 closure identity and must not be copied from this document.

### Phase 1 — Record the invariant

1.1 Author `knowledge-base/engineering/architecture/decisions/ADR-191-*.md` (ordinal
provisional) recording the cross-cutting invariant: **a suite's anti-vacuity floor reports with
`printf >&2` + `exit 1` directly and never through the suite's own assert functions**, and the
corpus is swept by a meta-guard that mutation-tests every floor it can construct a runnable
mutant for. This is an obligation on every future suite author, mechanically enforced from
Phase 3 — which is what makes it ADR-shaped.

1.2 Add **AP-023** to `knowledge-base/engineering/architecture/principles-register.md`
referencing ADR-191, enforcement `hook (CI-required suite: scripts/guard-vacuity-floor.test.sh
via test-all.sh)`. Precedent: AP-021 and AP-022 are both CI-enforced lint invariants of the
same shape.

No contract-line rollout (R1): 33 files the first draft would have touched are untouched.

### Phase 2 — Harden the 7 tier-1 suites

Read each file first; counter names, helper names, floor polarity, and indentation differ in
every one. Do not pattern-substitute.

2.1 **Introduce an independent `cases` counter, incremented at the CALL SITE** (R4), following
`scripts/plugin-legacy-resolver-probe.test.sh`'s shape — `pass()`/`fail()` touch only the
verdict counters. Never inside `$( )`; a subshell discards it.
  - `marketplace-manifest-validate` (22 sites), `verify-marketplace-ruleset` (27),
    `digest-oracle-guard` (26): the existing `ASSERTED`/`asserts` increment moves **out** of
    both verdict helpers to each call site. Roughly 7 bare sites plus every wrapper
    (`expect_rc`, `expect_mut`) per suite — enumerate, do not sample.
  - `derive-app-domain-base`, `test-contention`, `tmpfs-guard`, `preflight-check10`: introduce
    a new `cases` counter; none exists.

2.2 **Add a call-site coverage lint** so the invariant cannot rot: for each covered suite,
assert that no verdict-function call site is reachable without a preceding `cases` increment.
Without it, a future contributor adding a bare `pass "…"` makes conservation permanently
unequal and the suite red for a reason that reads as a harness bug.

2.3 **Re-report every floor directly** — replace `fail "…"` / `bad "…"` with `printf >&2` +
`exit 1`. Two floors need more than a call swap:
  - `digest-oracle-guard` (R7/P1-6): the predicate is **inverted** (`-ge`) with the success arm
    calling `ok`. Conversion means inverting to `-lt`, dropping the `else`, and **deleting the
    `ok` row** — an assertion the suite currently counts.
  - `derive-app-domain-base`: the floor's `else` calls `pass(…)`, counted by the exact
    `EXPECTED_PASSES` pin. Same deletion effect.
  Convert the two inline-increment floors too, so each suite has one shape.

2.4 **Add the accounting-conservation check** per suite, reported directly, after the floor.

2.5 **Fix `test-contention`'s positive control** (R5). It rolls back `pass_n` and `fails` after
probing the helpers; the new `cases` increments must be rolled back with them, or conservation
is permanently false by 2 and the suite is red on every run. Restoring `cases` does **not**
defeat the probe: the probe's assertion is that the counters *moved*, which is checked before
the rollback.

2.6 **Move `tmpfs-guard`'s floor onto `cases`** (P2-4). It currently reads `pass_n`, so a run
with genuine failures lowers the pass count and trips a *cardinality* message for a
non-cardinality problem. `test-contention` already fixed exactly this class — its comment
records reporting `"cardinality guard: only 64 ran"` on a run whose real problem was two
failures.

2.7 **Ratchet last**, from a re-measured green run, since 2.1-2.6 change the counts:
  - `derive-app-domain-base` `CASES_RUN` 26 → measured (28 on 2026-08-16)
  - `preflight-check10` `MIN_CHECKS` 11 → measured (13 on 2026-08-16)
  - `derive-app-domain-base` `EXPECTED_PASSES` 34 → post-conversion measured (R7)
  - `digest-oracle-guard` `MIN_ASSERTS` 26 → post-conversion measured (R7)
  Record pre- and post-edit numbers for each.

2.8 Preserve `derive-app-domain-base`'s exact `EXPECTED_PASSES` pin (re-ratcheted, not removed)
— it is the substance of property 2 by a different route and survives a neutered `fail()`.

### Phase 3 — Rebuild `scripts/guard-vacuity-floor.test.sh`

3.1 **Derive the population from floor SHAPE, unioned with marker prose.** Enumerate tracked
`*.test.sh` **recursively** (never a shell glob — R2) under `scripts/` and
`plugins/soleur/test/`.
  - **Signal 1 (structural, primary):** a `-lt`/`-ge` comparison whose compared expression
    references the suite's assertion counters. Must match **indented** floors — the current
    `^if [[` anchor silently misses `preflight-check10:196`.
  - **Signal 2 (prose, secondary):** the marker family (`anti-vacuity`, `vacuity guard`,
    `cardinality guard`, `assertion floor`, `MIN_ASSERT`, `MIN_CASES`, `MIN_CHECKS`,
    `EXPECTED_MIN`, …).
  - Set A = union. Signal 1 alone missed 15 prose-only files; signal 2 alone missed
    `plugins/soleur/test/terraform-drift-step-order.test.sh`, which carries a real floor
    (`if [[ "$((PASS + FAIL))" -lt 6 ]]`) whose prose matches no marker word. Prose is
    author-controlled and drifts; shape is structure. Neither signal alone is the population.

3.2 **Build a runnable mutant, with no declarations** (R1):
  - Neuter every helper at once with `command_not_found_handle() { return 0; }`. The mutant
    carries only the floor block, never the suite's helper definitions, so every helper name is
    an unfound command. Strictly stronger than a declared list, which can be under-declared.
  - **Widen the slice backward** over the contiguous assignment lines preceding the floor, so
    threshold bindings (`MIN_ASSERTS=26`, `EXPECTED_MIN=16`) are present (R3). Zero only the
    *counter* variables; preserve thresholds at their real values — zeroing a threshold inverts
    a `-ge` floor's polarity and destroys discrimination.
  - Append `exit 0` rather than reconstructing each suite's trailer. This tests the property
    directly: does the floor block *itself* exit non-zero?

3.3 **Assert the REASON, not the exit code** (R3 — the single most important fix). Capture the
mutant's stderr. Require the floor's own `[FATAL]`-class sentinel. Classify `unbound variable`,
`command not found`, and rc=2 as a distinct **construction failure** with its own loud verdict —
never as a pass. Without this, a mutant that dies before reaching the floor is indistinguishable
from a floor that fired, and 8 of 11 target floors do exactly that today.

3.4 **Declare the unreachable floors out, with a written reason** (R6).
`preflight-check10`'s three SUT floors are nested inside an enclosing `if` and read inputs
computed by surrounding code, so a truncate-and-run mutant of them is not a runnable program.
They are excluded from the *mutation* arm by name and reason, counted, and still receive the
Phase 2.3 conversion. Shipping a crash-green arm for them would be worse than excluding them.

3.5 **Loop the conservation arm over the population** (R8), mirroring the floor arm: per suite,
stub the verdict helpers, assert the run exits non-zero **and** that the message matches the
conservation arm rather than the floor arm. Not a single mutant, and not a manual experiment.

3.6 **Keep and extend the negative control.** The pre-fix `fail`-routed shape must still exit 0
under neutering, or the arms have stopped discriminating.

3.7 **Floor the guard itself**, mirroring `scripts/lint-orphan-test-suites.sh`'s existing
minimum-cardinality + zero-match pair: an absolute hand-ratcheted `cases` floor, a hand-ratcheted
minimum on the derived population, and the **closure identity** `covered + deferred == total
floor-bearing found repo-wide`. None derived from a variable this file computes.

3.8 **Add a synthesized out-of-population must-PASS control** (P1-2). Both first-draft "controls"
were population members already exercised by the main loop, so they asserted nothing beyond it. A
real control is a fixture suite built to the contract with third counter names, asserted green
through every arm.

3.9 File the tracking issue for the 34 deferred floor-bearing suites.

### Phase 4 — Registration and verification

4.1 Register any new `scripts/*.test.sh` in `scripts/test-all.sh` (not auto-globbed). Expected
no-op — all existing targets already run.

4.2 `bash scripts/lint-orphan-test-suites.sh` → exit 0.

4.3 Full verification battery (see Acceptance Criteria).

---

## Files to Edit

| Path | Change |
|---|---|
| `scripts/guard-vacuity-floor.test.sh` | Derive population (shape ∪ prose, recursive); declaration-free `build_mutant`; reason-asserting oracle; conservation loop; closure identity; synthesized control |
| `scripts/derive-app-domain-base.test.sh` | Call-site `cases`; direct-report both floors; re-ratchet `CASES_RUN` **and** `EXPECTED_PASSES` |
| `scripts/marketplace-manifest-validate.test.sh` | `ASSERTED` → call sites (22); direct-report floor; conservation |
| `scripts/verify-marketplace-ruleset.test.sh` | `ASSERTED` → call sites (27); direct-report floor; conservation |
| `scripts/digest-oracle-guard.test.sh` | `asserts` → call sites (26); **invert `-ge` floor**, drop `else`, direct-report; conservation; re-ratchet `MIN_ASSERTS` |
| `scripts/test-contention.test.sh` | Call-site `cases`; direct-report cardinality guard; conservation; **extend positive-control rollback to `cases`** |
| `scripts/tmpfs-guard.test.sh` | Call-site `cases`; direct-report cardinality guard; **move floor onto `cases`**; conservation |
| `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | Call-site `cases`; direct-report all four floors; conservation; re-ratchet `MIN_CHECKS` |
| `knowledge-base/engineering/architecture/principles-register.md` | Add AP-023 |
| `scripts/test-all.sh` | Only if Phase 3 creates a new suite file |

**8 suite files + 2 supporting files.** The first draft's "33 further comment-only edits" are cut.

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-191-anti-vacuity-floor-contract.md` | Record the direct-exit floor invariant (ordinal provisional) |
| A synthesized control fixture under `scripts/` or a test-fixture dir | Out-of-population must-PASS control (Phase 3.8) |

---

## Guard Contract

### Guard 1 — A floor survives a neutered assertion machinery

**Property.** For every suite in the derived population for which a runnable mutant can be
constructed, the suite exits non-zero **because its floor fired** — evidenced by the floor's own
sentinel on stderr — when every assert function has been replaced by a no-op.

**Assembly.** The chokepoint is `build_mutant` plus the reason-asserting oracle in
`scripts/guard-vacuity-floor.test.sh`, quantified over the population derived in Phase 3.1 — a
**recursive** enumeration of tracked `*.test.sh` under `scripts/` and `plugins/soleur/test/`,
union of a structural floor-shape signal and a marker-prose signal. Not a literal list of suite
names (the snapshot this replaces), and not a shell glob (non-recursive globs excluded a suite
the plan had itself classified). For each member the extractor widens the slice backward over
contiguous assignment lines so threshold bindings are bound, zeroes only counter variables,
neuters all helpers via `command_not_found_handle`, and appends `exit 0`. Floors for which a
runnable mutant cannot be built — `preflight-check10`'s three nested SUT floors — are excluded
by name with a written reason and counted, never silently skipped.

**Mutation matrix**

| # | Edit | Must |
|---|---|---|
| 1 | Revert any tier-1 suite's floor to its `fail "…"` / `bad "…"` form | RED **with the floor sentinel absent** — not merely rc≠0 |
| 2 | Remove the backward slice-widening so a threshold is unbound | RED as **construction failure**, never as a pass (this is R3, the 8-of-11 equivalent-mutant class) |
| 3 | Replace the reason assertion with a bare `rc != 0` check | RED — a crash must stop being indistinguishable from a fired floor |
| 4 | Zero a threshold variable along with the counters | RED — inverts `digest-oracle-guard`'s `-ge` floor and destroys discrimination |
| 5 | Restrict the sweep to a non-recursive `scripts/*.test.sh` glob | RED — population floor + closure identity catch the shrink |
| 6 | Restore the `^if [[` anchor so indented floors are missed | RED — `preflight-check10:196` leaves the population |
| 7 | Stub the guard's own sweep to emit an empty population | RED — population-size floor (guard's own dispatch) |

**Harness rows.** Must-RED on the suite itself: delete the negative control — the remaining arms
can no longer prove they discriminate, and the guard's `cases` floor must catch the missing
assertion. Must-PASS on a non-canonical input: the **synthesized fixture suite** of Phase 3.8,
built to the contract with counter names appearing nowhere in the repo and sitting outside the
derived population — it must pass every arm unmodified. The first draft used `rename-guard` and
`plugin-delivery-canary` here; both are population members already exercised by the main loop, so
neither asserted anything beyond it.

### Guard 2 — The population is closed over the repo

**Property.** Every floor-bearing suite in the repository is either in the guard's covered
population or in the counted deferral ledger — never in neither.

**Assembly.** Three independently-derived quantities inside `scripts/guard-vacuity-floor.test.sh`
and the identity binding them: the covered population (Phase 3.1, recursive, shape ∪ prose over
`scripts/` and `plugins/soleur/test/`), the directory-level deferral ledger (34 suites across
`apps/web-platform/infra/`, `.claude/hooks/`, `plugins/soleur/skills/*/test/`,
`apps/web-platform/scripts/`, `scripts/lib/`), and a **repo-wide** structural sweep over every
tracked `*.test.sh` that yields the total. The load-bearing choice is that the total is swept
independently, from floor shape, over the whole repo — so it cannot be satisfied by either list
going stale, and a new floor-bearing suite in a directory nobody anticipated breaks the identity
rather than disappearing. A shrink-only ratchet on the ledger was considered and rejected: it
would fail CI on bookkeeping the moment a legitimate new suite appeared.

**Mutation matrix**

| # | Edit | Must |
|---|---|---|
| 1 | Add a floor-bearing `*.test.sh` in a directory in neither list | RED — closure identity breaks, naming the file |
| 2 | Remove one directory from the deferral ledger without covering it | RED — `covered + deferred < total` |
| 3 | Scope the repo-wide total sweep to the covered directories only | RED — the identity becomes trivially true; an assertion must exist that the total's scope is strictly wider than the covered scope |
| 4 | Drop the structural signal, deriving the total from marker prose alone | RED — `terraform-drift-step-order.test.sh` leaves the total |
| 5 | Count a deferred suite in both lists | RED — double-counting satisfies the identity while covering nothing |

**Harness rows.** Must-RED on the suite: derive the repo-wide total from the same expression that
produces the covered set, making the identity circular — an assertion must fail when the two
share a producer. Must-PASS on a non-canonical input: a floor-bearing suite in a **deferred**
directory (e.g. any of the 28 under `apps/web-platform/infra/`) must leave the guard green — the
ledger is a legitimate answer, not a failure, so the guard must accept a compliant deferral it
did not author.

### Guard 3 — Accounting conservation is non-tautological

**Property.** For every suite carrying a conservation check, the check can be driven red by
discarding a verdict — the case counter moves independently of the verdict counters.

**Assembly.** Every `cases` increment site in each covered suite — **call sites**, not helper
interiors, which is what makes the identity non-tautological — together with the `pass`/`fail`
(or `ok`/`bad`) verdict branches, and the Phase 3.5 arm that loops over the covered population
executing each suite's real helpers. The property quantifies over every call site, not the first:
`marketplace-manifest-validate` has ~7 bare sites plus wrappers against 22 assertions, and a
conservation check is only as good as its least-covered site. Verified by the mutation rows and
by the Phase 2.2 call-site lint, never by reading the increment site — a `cases` increment inside
`$( )` reads as correct and is discarded to a subshell.

**Mutation matrix**

| # | Edit | Must |
|---|---|---|
| 1 | Stub a suite's `fail`/`bad` to a no-op and introduce a genuine defect | RED **via the conservation sentinel**, not the floor sentinel |
| 2 | Move a `cases` increment from a call site back inside the verdict helper | RED — restores the tautology; this is the R4 shape that printed `conservation GREEN — defect hidden` |
| 3 | Move a `cases` increment inside `$( )` | RED — subshell discards it |
| 4 | Delete one call site's `cases` increment | RED via the Phase 2.2 call-site lint |
| 5 | Restore `test-contention`'s control rollback without including `cases` | RED — permanently unequal by 2, on a green run |

**Harness rows.** Must-RED on the suite: replace row 1's genuine-defect fixture with one whose
assertion already passes — the row can then no longer distinguish a working conservation check
from an absent one, and a control must fail. Must-PASS on a non-canonical input: the synthesized
fixture of Phase 3.8, carrying call-site increments under third counter names, must pass every
arm — proving the guard accepts a compliant shape it did not author. `plugin-delivery-canary` is
**not** valid here: it is the canonical input, named in the loop this work replaces.

---

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-191 — Anti-vacuity floor contract for bash test suites`** (ordinal **provisional**;
highest on disk is ADR-186, highest claimed across 69 `origin/*` refs is ADR-190).

Decision: a suite's anti-vacuity floor reports via `printf >&2` + `exit 1` directly and never
through the suite's own assert functions; conservation is asserted from a case counter
incremented at call sites; and the corpus is swept by a meta-guard whose population is derived
from floor shape, closed over the repository by a counted identity. A new cross-cutting invariant
every suite author must honor — hence an ADR, not a comment. Mirrored as **AP-023** in the
principles register (Phase 1.2).

### C4 views

**No C4 impact.** Enumerated against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — 691 / 74 / 54
lines, read rather than grepped for the feature's own noun):

- **External human actors** — `founder`, `emailSender` (`#external`), `betaContact`
  (`#external`), `contributor` (`#external`). No actor added; no actor's reach altered.
  `contributor`'s description already states that operator-side execution of a checked-out PR
  head's tests falls outside both the CI and preflight-sandbox boundaries; this work hardens what
  those suites *assert*, not who may run them, so it remains accurate and needs no edit.
- **External systems** — `anthropic` and the vendor systems under `infra`. No new vendor,
  webhook, or outbound API.
- **Containers / data stores** — none touched. Build-time test harnesses under `scripts/` and
  `plugins/soleur/test/` are not modelled containers; they execute inside the already-modelled
  CI and operator-workstation contexts.
- **Access relationships** — none change. No ownership, tenancy, or sharing edge added or altered.

### Sequencing

The ADR and AP-023 are authored in this PR. The invariant is true the moment Phase 2 lands.

---

## Observability

The deliverable is a CI-time gate, so its observability surface is the CI shard's own signal
rather than a runtime telemetry sink. Declared against the 5-field schema because the
Files-to-Edit list is not pure-docs.

```yaml
liveness_signal:
  what: "scripts/guard-vacuity-floor.test.sh reports the derived population size, the covered+deferred==total closure identity, and a passed/failed/assertions total on every run; a population below the ratcheted minimum or a broken identity is a hard failure"
  cadence: "every push and pull_request, via the test-scripts matrix shard in .github/workflows/ci.yml"
  alert_target: "the GitHub Actions check-run for the test-scripts shard; a red shard blocks merge"
  configured_in: ".github/workflows/ci.yml (matrix shard `test-scripts` -> bash scripts/test-all.sh scripts)"

error_reporting:
  destination: "GitHub Actions job log and check-run conclusion; each failure prints a [FATAL] line to stderr naming the suite and the arm (floor, conservation, construction-failure, or closure)"
  fail_loud: "yes — every arm exits non-zero with a named cause, and a mutant that dies before reaching the floor is reported as a construction failure rather than counted as a pass"

failure_modes:
  - mode: "A covered suite's floor is reverted to a fail()/bad()-routed form"
    detection: "Guard 1 mutation arm — the mutant exits 0, or exits non-zero without the floor sentinel"
    alert_route: "test-scripts shard red; [FATAL] names the suite"
  - mode: "A mutant dies at an unbound threshold before evaluating the floor (the R3 equivalent-mutant class)"
    detection: "reason-asserting oracle classifies unbound-variable/command-not-found/rc=2 as a construction failure"
    alert_route: "test-scripts shard red, distinct verdict from a fired floor"
  - mode: "A floor-bearing suite appears in a directory in neither the covered population nor the deferral ledger"
    detection: "Guard 2 closure identity covered + deferred == repo-wide total"
    alert_route: "test-scripts shard red; FATAL names the file"
  - mode: "A conservation check regresses to a tautology (cases increment moved back into a verdict helper)"
    detection: "Guard 3 loop arm plus the Phase 2.2 call-site lint"
    alert_route: "test-scripts shard red at PR time"
  - mode: "A covered suite becomes an orphan (present but unregistered, so its floor never runs)"
    detection: "scripts/lint-orphan-test-suites.sh, anchored on the run_suite command shape"
    alert_route: "test-scripts shard red"

logs:
  where: "GitHub Actions job logs for the test-scripts shard; locally, the suites' own stdout/stderr"
  retention: "GitHub Actions default log retention (90 days); no separate sink"

discoverability_test:
  command: "bash scripts/guard-vacuity-floor.test.sh"
  expected_output: "the derived population and the closure identity are printed, every arm passes, and the run ends with a Total line and exit 0 — e.g. `Total: N passed, 0 failed (N assertions)`"
```

No `credentials_required` declaration: the probe is a local bash run over repo files with no
credential, network, or vendor dependency, so an unauthenticated probe verifies the property in
full.

## Encryption Posture

**Skipped — not applicable.** No persistent store (no `.tf`, migration, cloud-init, or compose
file) and no new cross-component connection.

## GDPR / Compliance Gate

**Skipped — not applicable.** No regulated-data surface; no schema, migration, auth flow, API
route, or `.sql` file; no LLM/external-API processing of operator data; no new distribution
surface. Threshold is `none`.

## Infrastructure-as-Code Routing Gate

**Skipped — not applicable.** No server, service, cron, vendor account, DNS record, cert, secret,
or firewall rule introduced.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Pure test-infrastructure hardening with no product surface. Three review passes
each falsified a load-bearing design claim by construction, and the plan above is the revised
one. The residual engineering risks are (a) conservation regressing to a tautology — addressed by
call-site increments, an automated loop arm, and a call-site lint; (b) the mutation battery
reporting its own baseline because mutants crash before reaching the floor — addressed by the
reason-asserting oracle, which is the single highest-value change in this plan; (c) population
omission — addressed by the closure identity rather than a hand-maintained list; and (d) CI blast
radius, since a red `guard-vacuity-floor.test.sh` blocks the `test-scripts` shard for every PR,
which is why Phase 2 lands the suite fixes before Phase 3 tightens the guard.

**Product/UX Gate:** not applicable — no path in Files to Create or Files to Edit matches the
UI-surface term list or glob superset; the mechanical override did not fire.

---

## Acceptance Criteria

### Pre-merge (PR)

1. `bash scripts/guard-vacuity-floor.test.sh` exits 0 and reports a derived population **≥ the
   ratcheted minimum** (40 on 2026-08-16), together with the closure identity
   `covered + deferred == total`. Re-derive at implementation time; the ratchet is a floor, not
   a pinned equality.
2. For each of the 7 tier-1 suites, with its own `fail`/`bad` stubbed to a no-op **and** a
   genuine defect introduced: the run exits non-zero **via the conservation sentinel**, not the
   floor sentinel. Verified by the Phase 3.5 loop, not by hand.
3. Reverting any one tier-1 floor to its `fail`-routed form makes the guard exit non-zero, and
   the failure names *floor did not fire*, not merely a non-zero exit.
4. Removing the Phase 3.2 slice-widening makes the guard report a **construction failure** for
   the affected suites — never a pass. This is the regression pin for the R3 equivalent-mutant
   class that made 8 of 11 floors untested.
5. `plugins/soleur/test/terraform-drift-step-order.test.sh` is in the derived population — the
   regression pin for the marker-sweep miss (its floor matches no marker word, so it can only
   enter via the structural signal).
6. `plugins/soleur/test/preflight-check10-suite-integrity.test.sh:196` (indented) is in the
   derived population — the regression pin for the `^if [[` anchor gap.
7. Adding a floor-bearing `*.test.sh` in a directory in neither list breaks the closure identity
   and the guard names the file.
8. No `cases` increment sits inside a command substitution:
   `grep -nE '\$\([^)]*(cases|ASSERTED|asserts)[^)]*\+ 1' <each edited file>` returns nothing.
9. The Phase 2.2 call-site lint passes, and deleting any one call-site `cases` increment drives
   it red.
10. `scripts/test-contention.test.sh` runs green with conservation enabled — the positive
    control's rollback covers `cases` (R5 regression pin).
11. `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
    is clean and the baseline has **not grown** (`wc -l` ≤ the Phase 0.3 value).
12. `shellcheck -S warning` clean on every changed `.sh` file.
13. `bash scripts/test-all.sh scripts` exits 0.
14. All four re-ratcheted floors (Phase 2.7) sit at their re-measured post-edit counts, with
    pre- and post-edit numbers recorded.
15. `ADR-191-*.md` and the AP-023 register row exist; the ordinal is re-verified free across all
    `origin/*` refs immediately before merge, and every artifact naming it (`plans/`,
    `specs/feat-*/tasks.md`) is swept in the same edit if it moves.

Cut as ceremony (they restated phase instructions or duplicated unconditional CI gates rather
than encoding checkable post-conditions): "unmutated run exits 0" (subsumed by AC13),
"every suite carries a contract line" (mechanism cut), the standalone
`lint-orphan-test-suites.sh` / `lint-guard-contract.py` invocations (unconditional on every PR),
"the plan records both numbers" (documentation instruction, folded into AC14), and
"issue #7553 is not referenced" (an anti-AC asserting an absence of action).

---

## Test Scenarios

Stated as *mutation → guard reddens*, never *command → output*.

| # | Mutation | Expected |
|---|---|---|
| T1 | `tmpfs-guard`: restore `fail "cardinality guard: …"` in place of the direct report; stub `fail` | Guard 1 RED, naming tmpfs-guard, citing floor-did-not-fire |
| T2 | `digest-oracle-guard`: stub `bad() { :; }`, flip one fixture so a row should fail | RED via the conservation sentinel |
| T3 | `marketplace-manifest-validate`: move the `ASSERTED` increment from call sites back inside `pass()`/`fail()` | Guard 3 row 2 RED **via the call-site lint and the loop arm** — the first draft asserted this was RED with nothing able to detect it |
| T4 | Remove the slice-widening so `MIN_ASSERTS` is unbound in the mutant | Construction failure reported; **not** a pass |
| T5 | Add `scripts/zz-probe.test.sh` with a floor, in a covered directory | Enters the population automatically (self-widening); no author action needed |
| T6 | Add a floor-bearing suite under `apps/cla-evidence/` (neither covered nor deferred) | Guard 2 closure identity RED, naming the file |
| T7 | Force the population sweep to return empty | Population-size floor RED |
| T8 | Delete the negative control | Guard's own `cases` floor RED |
| T9 | `preflight-check10`: delete two of the 13 checks | `MIN_CHECKS` floor RED at the ratcheted value (would have passed at 11) |
| T10 | `test-contention`: run unmodified with conservation enabled | GREEN — the control's rollback covers `cases` |
| T11 | Synthesized fixture suite (third counter names, outside the population), unmodified | GREEN through every arm — the genuine non-canonical must-PASS control |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The battery reports its own baseline.** A mutant that dies at an unbound threshold exits non-zero and is scored a pass, so the arm proves nothing. Measured: 8 of 11 target floors behave this way. | The reason-asserting oracle (Phase 3.3) requires the floor's sentinel and classifies crashes as construction failures. AC4 is its regression pin. This is the highest-value change in the plan. |
| **Conservation ships as a tautology.** For `ok`/`bad` suites the total counter moves inside both verdict helpers, so the identity holds under the exact fault. | Call-site increments (Phase 2.1), the call-site lint (2.2), the loop arm (3.5), and Guard 3 rows 2-4. |
| **A missed call site makes a suite permanently red** for a reason that reads as a harness bug. | The Phase 2.2 lint asserts no verdict call site is reachable without a preceding increment; AC9 drives it red. |
| **Converting a self-counting floor deletes an assertion** and drops the suite below its own exact pin. | Phase 2.7 re-ratchets all four affected floors from a re-measured run, after 2.1-2.6 settle. |
| **`test-contention`'s control makes conservation permanently false by 2.** | Phase 2.5 extends the rollback to `cases`; AC10 pins it. |
| **A nested floor yields a mutant that is not a runnable program.** | Phase 3.4 declares `preflight-check10`'s three SUT floors out of the mutation arm by name and reason, counted. They still get the fix. A crash-green arm would be worse than an honest exclusion. |
| **Population omission.** ~46% of the repo's floor-bearing suites are outside this PR's scope. | The closure identity makes the omission counted and visible, and breaks loudly when a new suite lands in neither list. Tracking issue filed in Phase 3.9. |
| **`set -euo pipefail` kills the script at a capture.** `x=$(cmd \| pipeline)` on a no-match dies **at the assignment**, so a `[[ -n "$x" ]] \|\| { echo FATAL; exit 2; }` guard below it is unreachable. | Use the brace form `{ cmd \|\| true; }`; a trailing `\|\| true` binds only to the last stage. `lint-shell-capture-exit.py` catches regressions (AC11). |
| **"Equivalent mutant" asserted rather than proven.** The first draft carried one (a row assuming the floor still called a helper the fix had removed). | Any row claimed equivalent must be traced through both branches to a difference in observable output before it is recorded. Rejected at review otherwise. |
| **CI blast radius.** A red guard blocks the `test-scripts` shard on every PR. | Phase 2 lands the suite fixes before Phase 3 tightens the guard. |
| **ADR ordinal collision.** ADR-191 is provisional. | Re-derive across all `origin/*` refs immediately before merge; sweep `plans/` + `specs/feat-*/` for the old ordinal in the same edit if it moves (AC15). |

---

## Alternatives Considered

| Alternative | Why not chosen |
|---|---|
| **Declared per-suite `# vacuity-contract:` lines on 40 suites** (the first draft's design) | **Falsified by construction.** A generic `build_mutant` with zero declarations discriminated 8/8. `command_not_found_handle` neuters every helper name at once, including `ok`/`bad` — the case the rejection was built on. The design also replaced a hardcoded list of 2 with a hand-maintained obligation on 40, the same failure class at larger scale, and a contract line is precisely the "second pin" the existing guard's own comment warns against. |
| **Scope the guard to the reference's two directories and call it done** | Leaves 34 floor-bearing suites silently uncovered. The closure identity makes them counted instead. |
| **Widen to all 74 suites in this PR** | Correct end-state, but `apps/web-platform/infra/`'s 28 suites are a different subsystem with their own runner (`run-registered-suites.sh`). Deferred with a tracking issue and a closure identity that cannot go stale. |
| **Shrink-only exemption ledger of 30 individual suites** | A ratchet on a list of things deliberately not done: adding a legitimate new floor-bearing suite would fail CI on bookkeeping, and the predictable response is to edit the assertion. Replaced by the directory-level ledger plus the closure identity. |
| **Keep the hardcoded suite list, just extend it to 7** | Explicitly rejected by the brief's Task 4. A hand-maintained list is the snapshot that goes stale — the failure this PR is about. |
| **Restate each floor inside the meta-guard rather than extracting it** | A restated copy is a second pin, and the copy that drifts is the one that runs. |
| **Normalize every suite to `passes`/`fails`/`cases`** | Would simplify extraction but rewrites counter names across the corpus for a cosmetic gain, with a high chance of a missed reference. Derivation buys the same generality for nothing. |
| **Fold in issue #7553** (`SOLEUR_SUBAGENT` never set) | Different subsystem, explicitly out of scope. Left open and unreferenced. |

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase
  4.6. This plan's section names a concrete artifact, a concrete (nil) exposure vector, and
  threshold `none`.
- **The ADR ordinal is provisional until merge.** ADR-191 was free across all 69 `origin/*` refs
  on 2026-08-16 (highest on disk: ADR-186; highest claimed on a branch: ADR-190). Siblings claim
  ordinals mid-pipeline and collide only post-squash. Re-run the probe before merge and sweep
  every artifact naming it if it moves.
- **The floor inventory and the corpus counts are 2026-08-16 measurements, not contracts.**
  Re-measure in Phase 0.1 and 0.4. A floor set from a stale number is either a false failure or
  fresh slack.
- **Never specify the sweep as a shell glob.** `scripts/*.test.sh` is non-recursive (59 files)
  while the corpus under `scripts/` is 78. That gap silently excluded a suite this plan had
  already classified into its own population.
- **Do not trust the tier classification as a substitute for reading each file.** It is reliable
  for scoping, but counter names, helper names, floor polarity (`-lt` vs `-ge`), indentation, and
  self-counting `else` arms all differ across the seven targets.
- **A non-zero exit is not evidence a floor fired.** Under `set -u` a mutant missing a binding
  dies before the floor with the same exit code. Always assert the reason.
