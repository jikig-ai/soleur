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

Two findings from re-derivation reshape the work relative to the brief. The population is
**7 files / 11 floors**, not 5 / 7 — and the two additions are precisely the two files a
prior review pass had identified and then discarded for the wrong reason. Separately, the
conservation check is **not portable as written**: none of the 7 target suites has the
three-counter shape that makes `passes + fails == cases` a non-tautology, so property 2
requires introducing an independent case counter per suite rather than copying a block.

---

## Research Reconciliation — Brief vs. Codebase

Re-derived against the worktree at `feat-one-shot-anti-vacuity-floor-widen` (parent
`4a7e5cb08`) on 2026-08-16. Every row below was confirmed by reading the file, not by
pattern-matching.

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "Five suites… five files, seven floors" | **7 files, 11 floors** carry a floor whose failure arm calls the suite's own `fail`/`bad`. | Population is the 7 below. All 11 floors in scope. |
| `tmpfs-guard.test.sh` and `test-contention.test.sh` are false positives — "disk-watermark floors and not assertion floors at all" | **Both are true positives.** Each carries a disk-watermark floor *and* a separate assertion-cardinality guard routed through `fail`: `test-contention.test.sh` `# --- Minimum-cardinality guard` → `if [[ "$((pass_n + fails))" -lt 110 ]]; then fail …`; `tmpfs-guard.test.sh` → `if [[ "$pass_n" -lt 60 ]]; then fail …`. | Add both to the population. The earlier reviewer found the right files via the wrong hit; the correction discarded the *files* instead of the *reason*. |
| `preflight-check10-suite-integrity.test.sh` carries three floors (`:197, :270, :276`) | Carries **four**. Three route through `fail` (`:196, :269, :275` — one-line drift from the brief's numbers). A fourth at `:292` (`MIN_CHECKS`) is the suite's *own dispatch* floor and increments `FAIL` inline. The brief's three all measure the **SUT**; the one it missed is the only one measuring **this suite**. | All four in scope. `:292` is called out separately because its arm differs. |
| "the floor routes through `fail`/`bad`, AND the exit status reads that counter" is the population predicate | Sound, and it partitions the corpus cleanly — but it is narrower than the corpus of floor-bearing suites. **40 suites** carry an assertion-cardinality floor; 7 route through the assert function, 5 write the exit counter inline, 25 already report directly, 3 are fully compliant. | Predicate retained for the *fix* scope (7). The *meta-guard* population is widened to all 40 — see "Scope decision". |
| Floors need ratcheting; "every assertion that PR added was silently deletable (46 and 20 of slack)" | True of the reference suites' historical values, **but not of the 7 targets today**. 9 of 11 floors already sit at zero slack. Only two carry slack: `derive-app-domain-base` `CASES_RUN` (26 vs 28 measured) and `preflight-check10` `MIN_CHECKS` (11 vs 13 measured). | Ratchet exactly those two. Do not "re-ratchet" the nine already tight. |
| Task 5: "Register any new `scripts/*.test.sh` in `scripts/test-all.sh`" | **All 7 targets and `guard-vacuity-floor.test.sh` are already registered.** Verified by `grep -c` per file against `scripts/test-all.sh` — each returns 1. | No-op unless the work creates a new suite file. Retained as an AC that re-runs `scripts/lint-orphan-test-suites.sh`, which is the enforcing gate. |
| `build_mutant` "extracts the floor block by grepping `^if [[ "$cases" -lt `… the extractor needs generalizing" | Confirmed, and **larger than the grep**. `build_mutant` also hardcodes the counter declarations (`passes=0; fails=0; cases=0`), the neutering (`fail() { :; }`), the exit trailer (`[[ "$fails" -eq 0 ]]`), and a floor-block sanity anchor (`grep -q 'vacuity guard'`). Four hardcodings, not one. | Generalize all four via a declared per-suite contract — see Phase 3. |

### Premise Validation (Phase 0.6)

- `f84e508` — confirmed on `main` as `test(plugin): close the four guard-vacuity gaps, each proven by mutation`. Reference implementation present at `scripts/plugin-legacy-resolver-probe.test.sh` (floor + `ACCOUNTING CONSERVATION`) and `scripts/plugin-delivery-canary.test.sh`.
- Issue **#7553** (`test-all.sh's subagent full-gate refusal can never fire: nothing sets SOLEUR_SUBAGENT=1`) — confirmed **open**. Different subsystem. **Explicitly out of scope; must not be bundled and must not be closed by this PR.**
- Learning `knowledge-base/project/learnings/2026-08-13-the-fixture-shape-decided-what-the-assertion-could-possibly-catch.md` — confirmed present (8251 bytes).
- ADR ordinal: highest claimed across all **69** `origin/*` refs is **ADR-190**. Next free is **ADR-191**, *provisional* — re-derive immediately before merge.

---

## Research Insights

### Measured floor inventory (all suites run green, RC=0, on 2026-08-16)

Every number below came from executing the suite, not from reading it.

| # | File | Floor | Counter | Declared | Measured | Slack | Failure arm |
|---|---|---|---|---|---|---|---|
| 1 | `scripts/derive-app-domain-base.test.sh` | invocation | `CASES_RUN` | `-lt 26` | **28** | **2** | `fail` |
| 2 | `scripts/derive-app-domain-base.test.sh` | assertion | `passes` vs `EXPECTED_PASSES` | `-ne 34` | **34** | 0 | inline `fails+1` |
| 3 | `scripts/marketplace-manifest-validate.test.sh` | assertion | `ASSERTED` | `-lt 22` | **22** | 0 | `fail` |
| 4 | `scripts/verify-marketplace-ruleset.test.sh` | assertion | `ASSERTED` | `-lt 27` | **27** | 0 | `fail` |
| 5 | `scripts/digest-oracle-guard.test.sh` | assertion | `asserts` vs `MIN_ASSERTS` | `-ge 26` | **26** | 0 | `bad` |
| 6 | `scripts/test-contention.test.sh` | cardinality | `pass_n + fails` | `-lt 110` | **110** | 0 | `fail` |
| 7 | `scripts/tmpfs-guard.test.sh` | cardinality | `pass_n` | `-lt 60` | **60** | 0 | `fail` |
| 8 | `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | manifest | `n_manifest` vs `MIN_MANIFEST_LINES` | `-lt 126` | **126** | 0 | `fail` |
| 9 | `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | SUT tests | `n_pass` vs `MIN_TESTS` | `-lt 131` | **131** | 0 | `fail` |
| 10 | `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | SUT asserts | `n_expect` vs `MIN_ASSERTIONS` | `-lt 537` | **537** | 0 | `fail` |
| 11 | `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | own dispatch | `PASS + FAIL` vs `MIN_CHECKS` | `-lt 11` | **13** | **2** | inline `FAIL+1` |

Note the counter names differ across all seven suites (`passes`/`fails`, `PASS`/`FAIL`/`ASSERTED`,
`pass`/`fail`/`asserts`, `pass_n`/`fails`, `CASES_RUN`), and so do the assert-function names
(`pass`/`fail` vs `ok`/`bad`). Nothing here is safely pattern-substitutable.

### The conservation check is not portable — the central technical finding

`passes + fails == cases` is load-bearing only when `cases` is incremented **independently
of the verdict** — at assert *entry*, by a wrapper, before dispatching to pass or fail.
That is the shape in `plugin-legacy-resolver-probe.test.sh`. **None of the 7 targets has it.**

| Suite | Counter shape | Conservation as-written would be |
|---|---|---|
| `marketplace-manifest-validate` | `ASSERTED` incremented inside **both** `pass()` and `fail()` | **Tautology** — `PASS+FAIL` and `ASSERTED` move together by construction |
| `verify-marketplace-ruleset` | same shape | **Tautology** |
| `digest-oracle-guard` | `asserts` incremented inside **both** `ok()` and `bad()` | **Tautology** |
| `derive-app-domain-base` | `passes`/`fails`; `CASES_RUN` counts *script invocations*, not assertions | **Not expressible** at assertion level |
| `test-contention` | `pass_n`/`fails` only | **Not expressible** |
| `tmpfs-guard` | `pass_n`/`fails` only | **Not expressible** |
| `preflight-check10-suite-integrity` | `PASS`/`FAIL` only | **Not expressible** |

Copying the reference block into any of these ships a check that can never fail — exactly
the class `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
documents. **Property 2 therefore requires a real per-suite change**: introduce a `cases`
counter incremented at assert-helper entry, ahead of the verdict.

Two suites already carry partial defenses worth preserving rather than replacing:

- `derive-app-domain-base.test.sh` pins `passes` **exactly** at 34 via `EXPECTED_PASSES` and
  reports it with an inline `fails+1`. That arm survives a neutered `fail()` and is the
  substance of property 2 by a different route. Keep it; add the direct-exit reporting.
- `test-contention.test.sh` already carries a **positive control** (`# POSITIVE CONTROL`)
  that probes whether `pass()` and `fail()` both move their counters, using a brace group
  with a redirect specifically because `$( )` would discard the increments in a subshell.
  Keep it; it is complementary to conservation, not a substitute (it samples the helpers at
  one instant; conservation is an invariant over the whole run).

### Corpus classification (40 floor-bearing suites)

Derived mechanically over all 145 `*.test.sh` files under `scripts/` and `plugins/soleur/test/`.

| Tier | Predicate | Count | Status against the meta-guard's mutation arm |
|---|---|---|---|
| **1** | Floor's failure arm calls `fail`/`bad` | **7** | **Reddens** — this is the defect |
| **2** | Floor increments the exit counter inline (`FAIL=$((FAIL+1))`) | **5** | Passes — inline increment survives a neutered `fail()` |
| **3** | Floor reports directly (`>&2` + `exit 1`), no conservation | **25** | Passes |
| **—** | Fully compliant (floor + conservation) | **3** | Passes |

Tier 2: `generate-kb-index`, `main-health-monitor-workflow`, `net-issue-flow`,
`infra-config-activation-7220`, `infra-config-red-alert`.
Compliant: `plugin-delivery-canary`, `plugin-legacy-resolver-probe`, `guard-vacuity-floor`.

### Property List (Phase 0.6b)

1. A suite's anti-vacuity floor still fires when the suite's assertion machinery is neutered.
2. A suite whose assertions ran but whose verdicts were discarded exits non-zero.
3. A floor's threshold equals the suite's current count, so deleting any assertion is loud.
4. The meta-guard's coverage is not a hand-maintained list that silently omits a suite.
5. A suite in the meta-guard's population whose floor cannot be located fails loudly rather than being skipped.

### Cut List (Phase 0.6b)

| Mechanism the brief proposes | Property it buys | Already covered on `main`? | Disposition |
|---|---|---|---|
| Register new `scripts/*.test.sh` in `test-all.sh` (Task 5) | Suites actually run | **Yes** — all 7 already registered; `scripts/lint-orphan-test-suites.sh` is the enforcing gate and fails CI on any unregistered `scripts/*.test.sh` | **Cut as new work.** Retained only as a verification AC. |
| Ratchet all floors to current count (Task 3) | Property 3 | **Partly** — 9 of 11 already at zero slack | **Narrowed** to the two floors with slack (#1, #11). |
| A restated copy of each floor inside the meta-guard | Property 5 | N/A — the reference `build_mutant` already extracts from the real file precisely to avoid a second pin that drifts | **Cut.** Keep extraction-from-source. |

### Applicable institutional learnings

- `2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md` — a guard and the thing it guards cannot share a failure mode; the floor must `exit 1` directly *and* audit the accounting conservation law, not just the case count.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — a mutation matrix that mutates only the system under test cannot see a vacuous harness. Requires must-RED rows that break the *guard*, and at least one must-PASS input that is not the canonical.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — a floor indexed to its own input is not a floor. Thresholds must be absolute and hand-ratcheted; a floor derived from a variable the file computes descends with the thing it guards.
- `2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md` — a test asserting a guard's *shape* cannot see a guard that does not *run*; never use `sed` ranges, which re-arm after the terminator.
- `2026-08-10-the-lever-had-never-run-and-every-guard-was-satisfied-by-its-own-comment.md` — a counter incremented inside `$( )` is discarded to a subshell. Directly relevant: the `cases` counters this plan introduces must never be incremented inside command substitution.
- `2026-08-13-the-fixture-shape-decided-what-the-assertion-could-possibly-catch.md` (brief-cited) — fixture topology bounds what an assertion can possibly catch; validate that the mutant's success and failure paths are materially distinguishable before reading any row.
- `2026-08-13-the-guards-i-wrote-to-prove-the-fixes-had-the-defects-the-fixes-were-about.md` — a red control voids a mutation battery; require a GREEN unmutated control before reading any row.

### Repo conventions that constrain the work

- `scripts/*.test.sh` is **NOT** auto-globbed by `scripts/test-all.sh`; each needs an explicit `run_suite <label> bash scripts/<name>.test.sh`. `plugins/soleur/test/*.test.sh` **IS** auto-globbed. `scripts/lint-orphan-test-suites.sh` fails CI on any unregistered `scripts/*.test.sh`, anchored on the command shape rather than the label.
- `scripts/lint-shell-capture-exit.py` rejects **new** unprotected `x=$(grep …)` captures (class S1) and `count=$(grep -c …) || echo 0` double-emits (class S2). The baseline is keyed by path + class + normalised text, not line number, and **may only shrink**.
- `scripts/lint-guard-contract.py` requires, per `### Guard` entry: a non-placeholder `**Property.**`, a non-placeholder `**Assembly.**`, and a `**Mutation matrix**` with `MIN_MUTATION_ROWS = 3` data rows scoped to the span following that field.
- CI runs `bash scripts/test-all.sh scripts` (and `bun`, `webplat`) as matrix shards in `.github/workflows/ci.yml`.

### Skill description budget

No `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate or finalized in this plan. Check skipped per Phase 1.8.

---

## Scope decision

The brief's Task 2 says "apply all three properties to each suite found," and Task 4 says the
meta-guard must **derive** its population. Those two interact: whatever predicate the
meta-guard uses *is* the scope, so the predicate must be chosen deliberately.

**Decision: split the contract in two.**

- **Contract 1 — floor survives a neutered assertion machinery.** Population: **all 40**
  floor-bearing suites, derived by sweep. Tiers 2, 3 and the compliant three already pass it;
  only the 7 tier-1 suites redden. This satisfies "derive the population," makes the guard
  maximally wide, and needs no exemptions.
- **Contract 2 — accounting conservation present.** Population: the **7** tier-1 suites in
  this PR (we are already editing their assert helpers), plus the 3 already compliant. The
  remaining 30 go into an explicitly-floored **exemption ledger** carrying a tracking issue,
  where the ledger's size is asserted so it can only shrink.

This is bounded, leaves no silent gap, and avoids a 40-suite rewrite in one PR. The
alternative — applying conservation to all 40 now — is recorded under Alternatives Considered.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a CI shard (`test-scripts`) that fails on
every PR with a `[FATAL]` from `scripts/guard-vacuity-floor.test.sh`, blocking all merges
until reverted; or, in the worse and quieter direction, a green suite corpus in which a
neutered assertion helper still hides real failures — the exact state this work exists to end.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector.
The change touches only build-time test harnesses; it reads no credentials, writes no
persistent store, and emits no network traffic. No regulated-data surface is involved.

**Brand-survival threshold:** `none`. Rationale: the blast radius is the repo's own CI
signal, not a user-facing surface. No sensitive path per the preflight Check 6 regex is
touched, so no scope-out bullet is required.

---

## Open Code-Review Overlap

**None.** Queried 65 open `code-review` issues via `gh issue list --label code-review
--state open --json number,title,body --limit 200` and matched each planned file path
against every issue body with `jq --arg`. Zero matches for all of:
`scripts/guard-vacuity-floor.test.sh`, `scripts/derive-app-domain-base.test.sh`,
`scripts/marketplace-manifest-validate.test.sh`, `scripts/verify-marketplace-ruleset.test.sh`,
`scripts/digest-oracle-guard.test.sh`, `scripts/test-contention.test.sh`,
`scripts/tmpfs-guard.test.sh`,
`plugins/soleur/test/preflight-check10-suite-integrity.test.sh`, `scripts/test-all.sh`.

---

## Implementation Phases

### Phase 0 — Preconditions (no edits)

0.1 Re-run each of the 7 target suites and record the exact counts. The table in Research
Insights is the 2026-08-16 measurement; re-measure rather than trust it, because a sibling
merge can move a floor's true value.

0.2 Confirm `bash scripts/guard-vacuity-floor.test.sh` is green as-shipped (RC=0). A red
control voids everything downstream.

0.3 Capture the `lint-shell-capture-exit` baseline state:
`python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
must be clean **before** any edit, so a later failure is attributable to this work.

### Phase 1 — The contract declaration (the enabling change, before any consumer)

Phase order is load-bearing: the meta-guard in Phase 3 consumes the declaration this phase
produces. Building the consumer first would leave it unable to run against anything.

1.1 Define the machine-readable per-suite contract line, written immediately above each
covered floor:

```bash
# vacuity-contract: cases=<var> passes=<var> fails=<var> assert_fns=<fn>[,<fn>] anchor=<literal>
```

`anchor` is a literal string unique to that suite's floor block, used to prove the extracted
slice is the real floor rather than an empty one.

1.2 Add the contract line to **all 40** floor-bearing suites. For tiers 2 and 3 this is a
comment-only edit — no behavioural change — and it is what makes derivation possible without
the meta-guard having to parse arbitrary shell.

1.3 Document the contract in `knowledge-base/engineering/architecture/decisions/ADR-191-*.md`
(ordinal provisional — see Sharp Edges).

### Phase 2 — Harden the 7 tier-1 suites

For each suite, in this order — read the file first; the counter and function names differ
in every one:

2.1 **Introduce an independent `cases` counter.** Increment it at assert-helper *entry*,
before the verdict branch, never inside `$( )` (a subshell discards it — see the learning
on the lever that had never run). Where a suite has a "total" counter that is currently
incremented inside both the pass and fail helpers (`ASSERTED`, `asserts`), move that
increment to the entry point rather than adding a fourth counter.

2.2 **Re-report every floor directly.** Replace the `fail "…"` / `bad "…"` call with
`printf >&2` + `exit 1`, following the reference wording in
`scripts/plugin-legacy-resolver-probe.test.sh`. This covers the 9 floors whose arm is
`fail`/`bad`. The two inline-increment floors (#2, #11) keep working under a neutered
helper, but convert them too for uniformity — a single shape per suite is what makes the
extractor reliable.

2.3 **Add the accounting-conservation check**, reported directly, after the floor.

2.4 **Ratchet the two floors that carry slack**, using the Phase 0.1 measurement, not the
table: `derive-app-domain-base` `CASES_RUN` 26 → measured (28 on 2026-08-16), and
`preflight-check10-suite-integrity` `MIN_CHECKS` 11 → measured (13 on 2026-08-16). Note
that 2.1–2.3 will themselves add assertions to some suites; re-measure after the edits and
ratchet last.

2.5 Preserve `derive-app-domain-base`'s exact `EXPECTED_PASSES` pin and
`test-contention`'s positive control. Neither is redundant with conservation.

### Phase 3 — Generalize `scripts/guard-vacuity-floor.test.sh`

3.1 **Derive the candidate population.** Sweep `scripts/*.test.sh` and
`plugins/soleur/test/*.test.sh` for an assertion-cardinality floor using the marker family
actually present in the tree (`anti-vacuity`, `vacuity guard`, `cardinality guard`,
`assertion floor`, `assertion-count floor`, `MIN_ASSERT`, `MIN_CASES`, `MIN_CHECKS`,
`EXPECTED_MIN`). Emit set **A**.

3.2 **Read the declared contracts.** Emit set **B**.

3.3 **Reconciliation gate.** `A \ B` must be empty. Any candidate without a parseable
contract is a **FATAL naming the file** — never a skip. This is the "fail loudly" requirement.

3.4 **Generalize `build_mutant`** to read the contract rather than hardcode. All four
current hardcodings must go: the floor-block grep (`^if [[ "$cases" -lt `), the counter
declarations, the neutering (`fail() { :; }` → stub every name in `assert_fns`), and the
exit trailer. Extraction stays sourced from the real file — never a restated copy.

3.5 **Add a conservation mutation arm.** Today's arm forces `cases=0` and stubs `fail`,
which tests only the first half. Add a second mutant that leaves the counter at full value
and discards verdicts — the shape that actually bites — and assert it exits non-zero.

3.6 **Keep the negative control** and extend it: the pre-fix `fail`-routed shape must still
exit 0 under neutering, or the arms have stopped discriminating.

3.7 **Floor the meta-guard itself.** Two separate assertions: an absolute hand-ratcheted
`cases` floor (never derived from a variable this file computes), and a hand-ratcheted
minimum on the *derived population size*, so a sweep that silently matches nothing is loud.

3.8 **Exemption ledger for contract 2**, listing the 30 suites with the tracking issue, with
its size asserted so it can only shrink.

### Phase 4 — Registration and verification

4.1 If Phase 3 creates any new `scripts/*.test.sh`, register it in `scripts/test-all.sh`
(that directory is not auto-globbed). Otherwise no-op.

4.2 Run `bash scripts/lint-orphan-test-suites.sh` — the enforcing gate for registration.

4.3 Full verification battery (see Acceptance Criteria).

---

## Files to Edit

| Path | Change |
|---|---|
| `scripts/guard-vacuity-floor.test.sh` | Derive population; generalize `build_mutant`; add conservation arm; add population-size floor; exemption ledger |
| `scripts/derive-app-domain-base.test.sh` | Contract line; `cases` counter; direct-report both floors; ratchet `CASES_RUN` 26 → measured |
| `scripts/marketplace-manifest-validate.test.sh` | Contract line; move `ASSERTED` to entry; direct-report floor; conservation |
| `scripts/verify-marketplace-ruleset.test.sh` | Contract line; move `ASSERTED` to entry; direct-report floor; conservation |
| `scripts/digest-oracle-guard.test.sh` | Contract line; move `asserts` to entry; direct-report floor (`bad` → `printf`+`exit`); conservation |
| `scripts/test-contention.test.sh` | Contract line; `cases` counter; direct-report cardinality guard; conservation; preserve positive control |
| `scripts/tmpfs-guard.test.sh` | Contract line; `cases` counter; direct-report cardinality guard; conservation |
| `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | Contract line; `cases` counter; direct-report all four floors; conservation; ratchet `MIN_CHECKS` 11 → measured |
| 33 further `*.test.sh` (tiers 2, 3, compliant) | **Comment-only** — add the `vacuity-contract:` declaration line |
| `scripts/test-all.sh` | Only if Phase 3 creates a new suite file |

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-191-anti-vacuity-floor-contract.md` | Record the corpus-wide floor contract (ordinal provisional) |

---

## Guard Contract

### Guard 1 — Floor survives a neutered assertion machinery

**Property.** For every suite in the derived population, the suite exits non-zero when its
anti-vacuity floor is unsatisfied, even when every one of the suite's assert functions has
been replaced by a no-op.

**Assembly.** The chokepoint is `build_mutant` in `scripts/guard-vacuity-floor.test.sh`,
quantified over the population derived by the Phase 3.1 sweep of `scripts/*.test.sh` and
`plugins/soleur/test/*.test.sh` — not over a literal list of suite names, which is the
snapshot this guard replaces. For each member the guard reads the declared
`vacuity-contract:` line (counter names, assert-function names, floor anchor), extracts the
floor block from the real file at that anchor, and constructs a mutant. The declaration is
the assembly's structural join; the reconciliation gate in Phase 3.3 is what makes the
declared set and the swept set the same set.

**Mutation matrix**

| # | Edit | Must |
|---|---|---|
| 1 | Revert any one tier-1 suite's floor to its `fail "…"` / `bad "…"` form | RED |
| 2 | Delete the `vacuity-contract:` line from any covered suite | RED (fatal: candidate without a contract) |
| 3 | Add a new `*.test.sh` carrying an anti-vacuity floor and no contract line | RED (fatal, not skipped) |
| 4 | Point a contract's `anchor` at a string absent from the file | RED (extraction produced an empty slice) |
| 5 | Stub the guard's own sweep to emit an empty population | RED (population-size floor, Phase 3.7) |
| 6 | Name only the first of a two-function `assert_fns` pair in a contract | RED (the unstubbed helper keeps the floor alive, so the arm must notice the under-declaration) |

**Harness rows.** Must-RED on the suite itself: delete the negative control from
`guard-vacuity-floor.test.sh` — the remaining arms can no longer prove they discriminate, and
the `cases` floor must catch the missing assertion. Must-PASS on a non-canonical input: a
tier-3 suite (`scripts/rename-guard.test.sh`), which already reports its floor directly with
different counter names (`PASS`/`FAIL`/`TOTAL`/`EXPECTED_MIN`) and must pass every arm
unmodified — proving the guard accepts a compliant shape it did not author.

### Guard 2 — Population reconciliation

**Property.** No suite carrying an assertion-cardinality floor is absent from the
meta-guard's covered set without a written, counted exemption.

**Assembly.** Two independently-derived sets and the comparison between them, all inside
`scripts/guard-vacuity-floor.test.sh`: set A from the Phase 3.1 marker sweep over both suite
directories (`scripts/`, `plugins/soleur/test/`), set B from the `vacuity-contract:`
declarations, and the exemption ledger of Phase 3.8. The load-bearing point is that A is
derived from *floor markers in the file*, never from the contract lines — a single source
would make the check circular, since a suite with neither marker nor contract would satisfy
it. Both suite directories are in scope because the two globbing regimes differ
(`scripts/*.test.sh` is hand-registered, `plugins/soleur/test/*.test.sh` is auto-globbed) and
a sweep scoped to one would silently omit the other.

**Mutation matrix**

| # | Edit | Must |
|---|---|---|
| 1 | Remove one entry from the exemption ledger while its suite still lacks conservation | RED |
| 2 | Add a suite to the exemption ledger without a tracking issue reference | RED |
| 3 | Restrict the sweep to `scripts/` only, dropping `plugins/soleur/test/` | RED (ledger-size assertion detects the population shrink) |
| 4 | Grow the exemption ledger by one entry | RED (ledger may only shrink) |

**Harness rows.** Must-RED on the suite: replace the two-source derivation with a single
source (derive A from the contract lines), which makes the reconciliation vacuous — an
assertion must exist that fails when set A and set B share a producer. Must-PASS on a
non-canonical input: a suite whose floor marker text is `cardinality guard` rather than
`anti-vacuity` (`scripts/tmpfs-guard.test.sh`) must be swept into set A, proving the marker
family is a real family and not one literal.

### Guard 3 — Accounting conservation is non-tautological

**Property.** For every suite carrying a conservation check, the check can be driven red by
discarding a verdict — i.e. the case counter moves independently of the verdict counters.

**Assembly.** Each covered suite's assert-helper entry point — the site where `cases` is
incremented — and its `pass`/`fail` (or `ok`/`bad`) verdict branches. The property quantifies
over every assert helper in the suite, not the first: a suite with two entry points
(`assert_jq` plus a bare `pass`/`fail` idiom used inline) has two sites, and a conservation
check is only as good as the least-covered one. Verified per suite by the mutation rows
below rather than by reading the increment site, because a `cases` increment placed inside
`$( )` reads as correct and is discarded to a subshell.

**Mutation matrix**

| # | Edit | Must |
|---|---|---|
| 1 | Stub one suite's `fail`/`bad` to a no-op and introduce a genuine defect | RED via conservation, **not** via the count floor |
| 2 | Move a `cases` increment from the entry point into the verdict branch | RED (restores the tautology; the guard must detect it) |
| 3 | Move a `cases` increment inside `$( )` | RED (subshell discards it; conservation goes permanently unequal) |
| 4 | Delete the conservation block from a covered suite | RED |

**Harness rows.** Must-RED on the suite: replace mutation row 1's "genuine defect" fixture
with one whose assertion already passes — the row then cannot distinguish a working
conservation check from an absent one, and a control must fail. Must-PASS on a non-canonical
input: `scripts/plugin-delivery-canary.test.sh` unmodified — it has the three-counter shape
already and must pass every arm, proving the guard accepts the reference implementation it
was derived from.

---

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-191 — Anti-vacuity floor contract for bash test suites`** (ordinal
**provisional**; highest claimed across 69 `origin/*` refs is ADR-190).

Decision to record: every bash test suite carrying an anti-vacuity floor declares a
machine-readable `vacuity-contract:` line; floors report directly via `printf >&2` + `exit 1`
and never through the suite's own assert functions; and a suite with a floor but no contract
is a hard failure of the meta-guard rather than a skip. This is a new cross-cutting invariant
every suite author must honor, which is why it is an ADR and not a comment.

### C4 views

**No C4 impact.** Enumerated against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — 691 / 74 /
54 lines, read in full rather than grepped for the feature's own noun):

- **External human actors** — `founder` (Founder / Operator), `emailSender` (Inbound
  Correspondent, `#external`), `betaContact` (Beta Tester / Prospect, `#external`),
  `contributor` (Contributor / PR Author, `#external`). This change adds no actor and alters
  no actor's reach. Notably `contributor`'s description already states that operator-side
  execution of a checked-out PR head's tests is covered by neither the CI nor the preflight
  sandbox boundary; this work hardens what those suites *assert*, not who may run them, so
  that description remains accurate and needs no edit.
- **External systems** — `anthropic` (Anthropic API) and the vendor systems under `infra`.
  No new vendor, webhook, or outbound API.
- **Containers / data stores** — none touched. The change is confined to build-time test
  harnesses under `scripts/` and `plugins/soleur/test/`, neither of which is a modelled
  container; they execute inside the already-modelled CI and operator-workstation contexts.
- **Access relationships** — none change. No ownership, tenancy, or sharing edge is added
  or altered.

### Sequencing

The ADR is authored in this PR, not deferred. The contract is true the moment Phase 1 lands.

---

## Observability

**Skipped — not applicable.** Phase 2.9 fires on Files-to-Edit under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`, or on a new infrastructure surface.
This plan's edits are confined to repo-root `scripts/*.test.sh`,
`plugins/soleur/test/*.test.sh`, and `knowledge-base/`. None matches, and no persistent
runtime process, secret, vendor, or service is introduced. The failure signal for this work
is the CI shard's own exit status, which is already surfaced by `.github/workflows/ci.yml`.

## Encryption Posture

**Skipped — not applicable.** No persistent store (no `.tf`, no migration, no cloud-init,
no compose file) and no new cross-component connection.

## GDPR / Compliance Gate

**Skipped — not applicable.** No regulated-data surface: no schema, migration, auth flow,
API route, or `.sql` file; no LLM/external-API processing of operator data; no new artifact
distribution surface. Brand-survival threshold is `none`.

## Infrastructure-as-Code Routing Gate

**Skipped — not applicable.** No server, service, cron, vendor account, DNS record, cert,
secret, or firewall rule is introduced.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Pure test-infrastructure hardening with no product surface. The material
engineering risks are (a) the conservation check shipping as a tautology in suites that lack
an independent case counter — addressed by making the counter introduction an explicit
per-suite step rather than a copy-paste; (b) the meta-guard's generalization silently
narrowing coverage — addressed by the population-size floor and the two-source reconciliation
gate; and (c) CI blast radius, since a red `guard-vacuity-floor.test.sh` blocks the
`test-scripts` shard for every PR. Risk (c) argues for landing Phase 1 (comment-only contract
lines) and Phase 2 (suite hardening) before Phase 3 (the consumer), which the phase ordering
already enforces.

**Product/UX Gate:** not applicable — no path in Files to Create or Files to Edit matches the
UI-surface term list or glob superset; the mechanical override did not fire.

---

## Acceptance Criteria

### Pre-merge (PR)

1. `bash scripts/guard-vacuity-floor.test.sh` exits 0, and its output reports a derived
   population of **40** suites (not 2).
2. For each of the 7 tier-1 suites: unmutated run exits 0.
3. For each of the 7 tier-1 suites: with its own `fail`/`bad` stubbed to a no-op **and** a
   genuine defect introduced, the run exits **non-zero via the conservation check**, not via
   the count floor. Record the observed `[FATAL] accounting:` line per suite.
4. Every one of the 40 floor-bearing suites carries a parseable `vacuity-contract:` line;
   the reconciliation gate reports `A \ B` empty.
5. Removing the `vacuity-contract:` line from any one suite makes
   `scripts/guard-vacuity-floor.test.sh` exit non-zero with a message naming that file
   (proves fail-loud, not skip).
6. `grep -c 'cases=\$((cases + 1))' ` — or the suite's declared counter name — confirms the
   increment is **not** inside a `$( )` in any edited suite:
   `grep -nE '\$\([^)]*(cases|ASSERTED|asserts)[^)]*\+ 1' <each edited file>` returns nothing.
7. `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
   is clean, and `scripts/lint-shell-capture-exit.baseline.txt` has **not grown**
   (`wc -l` ≤ the Phase 0.3 value).
8. `shellcheck -S warning` is clean on every changed `.sh` file.
9. `bash scripts/lint-orphan-test-suites.sh` exits 0.
10. `python3 scripts/lint-guard-contract.py` accepts this plan's `## Guard Contract`
    (3 entries, each with non-placeholder Property + Assembly and ≥ 3 matrix rows).
11. `bash scripts/test-all.sh scripts` exits 0 (the CI shard that carries these suites).
12. The two slack-carrying floors are ratcheted to the **re-measured** post-edit counts, and
    the plan records both the pre-edit and post-edit numbers.
13. `ADR-191-*.md` exists, its ordinal re-verified free across all `origin/*` refs
    immediately before merge, and every artifact in this feature's set
    (`plans/`, `specs/feat-*/tasks.md`) names the same ordinal.
14. Issue **#7553** is neither referenced as `Closes` nor closed by this PR.

---

## Test Scenarios

Each scenario is stated as *mutation → guard reddens*, not *command → terminal output* —
the shape the Guard Contract gate exists to enforce.

| # | Mutation | Expected |
|---|---|---|
| T1 | `scripts/tmpfs-guard.test.sh`: restore `fail "cardinality guard: …"` in place of the direct report; stub `fail` | `guard-vacuity-floor.test.sh` RED, naming tmpfs-guard |
| T2 | `scripts/digest-oracle-guard.test.sh`: stub `bad() { :; }`, flip one arm's fixture so a row should fail | suite exits non-zero via `[FATAL] accounting:` |
| T3 | `scripts/marketplace-manifest-validate.test.sh`: move the `ASSERTED` increment back inside `pass()`/`fail()` | conservation becomes tautological; Guard 3 row 2 RED |
| T4 | Any covered suite: delete the `vacuity-contract:` line | meta-guard RED, fatal naming the file |
| T5 | New file `scripts/zz-probe.test.sh` with an anti-vacuity floor and no contract | meta-guard RED (fatal), and `lint-orphan-test-suites.sh` RED (unregistered) |
| T6 | Meta-guard: force the population sweep to return empty | population-size floor RED |
| T7 | Meta-guard: delete the negative control | `cases` floor RED |
| T8 | `plugins/soleur/test/preflight-check10-suite-integrity.test.sh`: delete two of the 13 checks | `MIN_CHECKS` floor RED at the ratcheted value (would have passed at 11) |
| T9 | `scripts/plugin-delivery-canary.test.sh` unmodified | meta-guard GREEN (must-PASS non-canonical control) |
| T10 | `scripts/rename-guard.test.sh` unmodified (tier 3, different counter names) | meta-guard GREEN (must-PASS non-canonical control) |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Conservation ships as a tautology.** Copying the reference block into a suite whose total counter moves inside the verdict helpers yields a check that can never fail. | Guard 3 mutation rows 2 and 3 exist precisely to drive this red. Per-suite counter introduction is an explicit step (Phase 2.1), never a copy-paste. |
| **A `cases` increment inside `$( )` is discarded.** Reads as correct; silently breaks conservation into a permanent inequality (or, worse, a permanent equality). | AC6 greps for it directly. `test-contention.test.sh`'s existing positive control documents the same trap and uses a brace group with a redirect. |
| **`set -euo pipefail` kills the script at a capture.** `x=$(cmd \| pipeline)` on a no-match dies **at the assignment**, making any `[[ -n "$x" ]] \|\| { echo FATAL; exit 2; }` guard below it unreachable — the suite dies closed but silent. | Use the brace form `{ cmd \|\| true; }` — a trailing `\|\| true` binds only to the last pipeline stage. Already the shape used in the current `build_mutant`. `lint-shell-capture-exit.py` catches regressions (AC7). |
| **Ratcheting a floor before the edits settle.** Phases 2.1–2.3 add assertions to some suites, so a floor set from the Phase 0.1 measurement will be wrong. | Ratchet **last** (Phase 2.4), from a re-measured green run. AC12 requires both numbers be recorded. |
| **CI blast radius.** A red `guard-vacuity-floor.test.sh` blocks the `test-scripts` shard on every PR. | Phase ordering lands the contract lines and suite hardening before the consumer. The meta-guard is expected to redden between Phase 1 and Phase 2 — that is correct, and it is why the two are one PR. |
| **"Equivalent mutant" asserted rather than proven.** | Any row claimed equivalent must be traced through both branches to a difference in observable output before it is recorded. A claim without that trace is rejected at review. |
| **ADR ordinal collision.** ADR-191 is provisional; siblings claim ordinals mid-pipeline and only surface post-squash on `main`. | Re-derive across all `origin/*` refs immediately before merge, and sweep `plans/` + `specs/feat-*/` for the old ordinal in the same edit if it moves (AC13). |
| **Scope creep to 40 suites.** Applying conservation everywhere in one PR is a large, review-hostile diff. | Contract 1 covers all 40 with comment-only edits for 33 of them; contract 2 is scoped to 7 + an explicitly-floored, shrink-only exemption ledger with a tracking issue. |

---

## Alternatives Considered

| Alternative | Why not chosen |
|---|---|
| **`build_mutant` parses counter names out of the extracted `if` line** instead of reading a declared contract | Avoids 40 comment edits, but infers the neutering targets and exit trailer from shell it cannot fully parse. The repo's own learnings warn against guards satisfied by inspection of their subject; a declared, auditable contract that a reconciliation gate cross-checks is the stronger shape. Also cannot express `assert_fns` when a suite has two helper names (`ok`/`bad`). |
| **Apply conservation to all 40 suites in this PR** | Correct end-state, but 40 assert-helper rewrites in one diff, most of them in suites that already satisfy contract 1. Deferred to the exemption ledger with a tracking issue and a shrink-only size assertion, so it cannot rot silently. |
| **Normalize every suite to `passes`/`fails`/`cases`** | Would make the extractor trivial, but rewrites counter names across 40 files and 145 suites' worth of call sites for a cosmetic gain, with a large chance of a missed reference. The contract line buys the same generality for one comment per file. |
| **Keep the hardcoded suite list, just extend it to 7** | Explicitly rejected by Task 4. A hand-maintained list is the snapshot that goes stale — the failure this whole PR is about. |
| **Restate each floor inside the meta-guard rather than extracting it** | A restated copy is a second pin, and the copy that drifts is the one that runs. The reference `build_mutant` already extracts from the real file for exactly this reason. |
| **Fold in issue #7553** (`SOLEUR_SUBAGENT` never set) | Different subsystem, explicitly out of scope per the brief. Left open, unreferenced. |

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is
  filled with a concrete artifact, a concrete (nil) exposure vector, and threshold `none`.
- **The ADR ordinal is provisional until merge.** ADR-191 was derived free across all 69
  `origin/*` refs on 2026-08-16. Siblings claim ordinals mid-pipeline and collide only
  post-squash. Re-run the probe before merge, and if it moves, sweep this plan, `tasks.md`,
  and any AC naming the ordinal in the same edit.
- **The floor inventory table is a 2026-08-16 measurement, not a contract.** Re-measure in
  Phase 0.1. A sibling merge can move any of these counts, and a floor set from a stale
  number is either a false failure or fresh slack.
- **Do not trust the tier classification as a substitute for reading each file.** It was
  derived mechanically and is reliable for *scoping*, but every counter name, helper name,
  and floor shape in the 7 targets differs, and Phase 2 must read each file.
