# Tasks — Widen the anti-vacuity floor hardening

Plan: `knowledge-base/project/plans/2026-08-16-feat-widen-anti-vacuity-floor-plan.md`
Branch: `feat-one-shot-anti-vacuity-floor-widen`
Lane: `procedural`

**Revised after three deepen-plan review passes.** The contract-line design (R1) and the
40-suite corpus figure (R2) were both falsified by measurement; see the plan's
`## Deepen-Plan Revisions` table before starting. Phase order is load-bearing.

---

## Phase 0 — Preconditions (no edits)

- [x] 0.1 Re-run each of the 7 target suites; record exact counts. Do **not** trust the plan's
      2026-08-16 table.
  - [x] 0.1.1 `bash scripts/derive-app-domain-base.test.sh` → `CASES_RUN`, `passes`
  - [x] 0.1.2 `bash scripts/marketplace-manifest-validate.test.sh` → `ASSERTED`
  - [x] 0.1.3 `bash scripts/verify-marketplace-ruleset.test.sh` → `ASSERTED`
  - [x] 0.1.4 `bash scripts/digest-oracle-guard.test.sh` → `asserts` (note: floor is `-ge`)
  - [x] 0.1.5 `bash scripts/test-contention.test.sh` → `pass_n + fails`
  - [x] 0.1.6 `bash scripts/tmpfs-guard.test.sh` → `pass_n`
  - [x] 0.1.7 `bash plugins/soleur/test/preflight-check10-suite-integrity.test.sh` →
        `PASS+FAIL`, `n_manifest`, `n_pass`, `n_expect`
- [x] 0.2 `bash scripts/guard-vacuity-floor.test.sh` → must be GREEN as shipped. A red control
      voids every downstream reading.
- [x] 0.3 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
      → clean **before** any edit. Record the baseline's `wc -l`.
- [x] 0.4 Re-derive the repo-wide corpus (74 on 2026-08-16) and the covered/deferred split
      (40 / 34). These feed the Phase 3.7 closure identity — do not copy from the plan.

## Phase 1 — Record the invariant

- [x] 1.1 Author `knowledge-base/engineering/architecture/decisions/ADR-193-*.md` (ordinal
      **provisional**): floors report `printf >&2` + `exit 1` directly, never through the
      suite's assert functions; conservation from call-site increments; population derived
      from floor shape and closed over the repo.
- [x] 1.2 Add **AP-023** to `knowledge-base/engineering/architecture/principles-register.md`
      referencing ADR-193, enforcement `hook (CI-required suite: scripts/guard-vacuity-floor.test.sh
      via test-all.sh)`. Precedent: AP-021, AP-022.
- [x] 1.3 **No contract-line rollout** (R1). The 33 comment-only edits are cut.

## Phase 2 — Harden the 7 tier-1 suites

Read each file first. Counter names, helper names, floor polarity, and indentation all differ.

- [x] 2.1 Introduce an independent `cases` counter incremented at the **CALL SITE** (R4), the
      `plugin-legacy-resolver-probe` shape. `pass()`/`fail()` touch only verdict counters.
      Never inside `$( )`.
  - [x] 2.1.1 `marketplace-manifest-validate` (~22 sites): move `ASSERTED` out of both helpers
  - [x] 2.1.2 `verify-marketplace-ruleset` (~27 sites): move `ASSERTED` out of both helpers
  - [x] 2.1.3 `digest-oracle-guard` (~26 sites): move `asserts` out of `ok()`/`bad()`
  - [x] 2.1.4 `derive-app-domain-base`, `test-contention`, `tmpfs-guard`,
        `preflight-check10`: introduce a new `cases` counter (none exists)
  - [x] 2.1.5 Enumerate every bare call site **and** every wrapper (`expect_rc`, `expect_mut`,
        `assert_jq`) per suite — do not sample. A missed site makes conservation permanently
        unequal and the suite permanently red.
- [ ] 2.2 Add the **call-site coverage lint**: per covered suite, assert no verdict-function
      call site is reachable without a preceding `cases` increment.
- [x] 2.3 Re-report every floor directly (`printf >&2` + `exit 1`). Two need more than a call swap:
  - [x] 2.3.1 `digest-oracle-guard`: predicate is **inverted** (`-ge`) with the success arm
        calling `ok`. Invert to `-lt`, drop the `else`, delete the `ok` row.
  - [x] 2.3.2 `derive-app-domain-base`: floor's `else` calls `pass(…)`, counted by the exact
        `EXPECTED_PASSES` pin. Same deletion effect.
  - [x] 2.3.3 Convert the two inline-increment floors too, so each suite has one shape.
- [x] 2.4 Add the accounting-conservation check per suite, reported directly, after the floor.
- [x] 2.5 Fix `test-contention`'s positive control (R5): its rollback of `pass_n`/`fails` must
      also cover `cases`, or conservation is permanently false by 2 and the suite is red on
      every run. Restoring `cases` does not defeat the probe — the probe asserts the counters
      *moved*, checked before the rollback.
- [x] 2.6 Move `tmpfs-guard`'s floor onto `cases` (it currently reads `pass_n`, so real
      failures trip a *cardinality* message for a non-cardinality problem — the class
      `test-contention` already fixed).
- [x] 2.7 **Ratchet last**, from a re-measured green run (2.1–2.6 change the counts):
  - [x] 2.7.1 `derive-app-domain-base` `CASES_RUN` 26 → re-measured (28 on 2026-08-16)
  - [x] 2.7.2 `preflight-check10` `MIN_CHECKS` 11 → re-measured (13 on 2026-08-16)
  - [x] 2.7.3 `derive-app-domain-base` `EXPECTED_PASSES` 34 → post-conversion measured (R7)
  - [x] 2.7.4 `digest-oracle-guard` `MIN_ASSERTS` 26 → post-conversion measured (R7)
  - [x] 2.7.5 Record pre- and post-edit numbers for each (AC14)
- [x] 2.8 Preserve (re-ratcheted, not removed) `derive-app-domain-base`'s exact
      `EXPECTED_PASSES` pin — it survives a neutered `fail()` and is property 2 by another route.

## Phase 3 — Rebuild `scripts/guard-vacuity-floor.test.sh`

- [x] 3.1 Derive the population from floor **SHAPE** unioned with marker prose. Enumerate
      tracked `*.test.sh` **recursively** under `scripts/` and `plugins/soleur/test/` —
      **never a shell glob** (`scripts/*.test.sh` is non-recursive: 59 vs 78).
  - [x] 3.1.1 Signal 1 (structural, primary): a `-lt`/`-ge` comparison against the suite's
        assertion counters. **Must match indented floors** — the `^if [[` anchor misses
        `preflight-check10:196`.
  - [x] 3.1.2 Signal 2 (prose, secondary): the marker family.
  - [x] 3.1.3 Regression pins: `terraform-drift-step-order.test.sh` enters via signal 1 only;
        `preflight-check10:196` enters only if indentation is handled.
- [x] 3.2 Build a runnable mutant with **no declarations** (R1):
  - [x] 3.2.1 `command_not_found_handle() { return 0; }` — neuters every helper at once
  - [x] 3.2.2 **Widen the slice backward** over contiguous assignment lines so thresholds bind
  - [x] 3.2.3 Zero only **counter** variables; preserve thresholds (zeroing one inverts a
        `-ge` floor and destroys discrimination)
  - [x] 3.2.4 Append `exit 0` rather than reconstructing each suite's trailer
- [x] 3.3 **Assert the REASON, not the exit code** (R3 — highest-value change). Capture stderr,
      require the floor's own sentinel, and classify `unbound variable` / `command not found` /
      rc=2 as a distinct loud **construction failure**.
- [ ] 3.4 Declare `preflight-check10`'s three nested SUT floors **out of the mutation arm** by
      name and reason, counted (R6). They still get the 2.3 conversion.
- [ ] 3.5 **Loop the conservation arm over the population** (R8): per suite, stub the verdict
      helpers, assert non-zero exit **and** that the message is the conservation sentinel, not
      the floor sentinel.
- [x] 3.6 Keep and extend the negative control.
- [x] 3.7 Floor the guard itself, mirroring `scripts/lint-orphan-test-suites.sh`: an absolute
      hand-ratcheted `cases` floor, a population-size minimum, and the **closure identity**
      `covered + deferred == repo-wide total`.
- [x] 3.8 Add a **synthesized out-of-population must-PASS control** with third counter names.
      (The first draft's two "controls" were population members and asserted nothing.)
- [ ] 3.9 File the tracking issue for the 34 deferred floor-bearing suites.

## Phase 4 — Registration and verification

- [x] 4.1 Register any new `scripts/*.test.sh` in `scripts/test-all.sh` (not auto-globbed).
      Expected no-op.
- [x] 4.2 `bash scripts/lint-orphan-test-suites.sh` → exit 0.
- [ ] 4.3 Verification battery (mirrors Acceptance Criteria):
  - [ ] 4.3.1 Guard exits 0; population ≥ ratcheted minimum; closure identity holds
  - [ ] 4.3.2 Per suite: stub `fail`/`bad` + real defect → non-zero **via conservation sentinel**
  - [ ] 4.3.3 Revert a floor to `fail`-routed → RED naming *floor did not fire*
  - [ ] 4.3.4 Remove slice-widening → **construction failure**, never a pass
  - [ ] 4.3.5 `terraform-drift-step-order` and `preflight-check10:196` both in the population
  - [ ] 4.3.6 Floor-bearing suite in an unlisted directory → closure identity RED
  - [ ] 4.3.7 `grep -nE '\$\([^)]*(cases|ASSERTED|asserts)[^)]*\+ 1' <edited files>` → empty
  - [ ] 4.3.8 Call-site lint passes; deleting one increment drives it red
  - [ ] 4.3.9 `test-contention` green with conservation enabled
  - [ ] 4.3.10 `lint-shell-capture-exit.py` clean; baseline not grown
  - [ ] 4.3.11 `shellcheck -S warning` clean on every changed `.sh`
  - [ ] 4.3.12 `bash scripts/test-all.sh scripts` → exit 0
- [ ] 4.4 Re-derive the ADR ordinal across **all** `origin/*` refs immediately before merge. If
      it moves, sweep the plan, this file, and any AC naming it in the same edit.
- [ ] 4.5 Confirm issue **#7553** is neither referenced as `Closes` nor closed.

---

## Traps

- **A non-zero exit is not evidence a floor fired.** Under `set -u` a mutant missing a binding
  dies before the floor with the same exit code. 8 of 11 target floors behave this way today.
  Always assert the reason.
- **Conservation whose case counter moves inside the verdict helper is a tautology** and can
  never fail. Measured: neutered `bad()` printed `conservation GREEN — defect hidden`, RC=0.
- A `$(cmd | pipeline)` capture under `set -euo pipefail` dies **at the assignment** on a
  no-match, making a `[[ -n "$x" ]] || { echo FATAL; exit 2; }` guard below it unreachable.
  Use `{ cmd || true; }`; a trailing `|| true` binds only to the last stage.
- A `cases` increment inside `$( )` is discarded to a subshell.
- Never set a floor by guessing. Run the suite, count, then set it — and ratchet **after** the
  conversions, which delete assertions in two self-counting suites.
- "Equivalent mutant" is a claim requiring proof — trace both branches to a difference in
  observable output before recording it.
- Never specify the sweep as a shell glob; `scripts/*.test.sh` is non-recursive.


---

## Completion Record — 2026-08-16

Measured on this branch, not copied from the plan. Every number below came from running the
thing.

### Population, re-derived (the plan's figures were a 2026-08-16 snapshot and `main` moved)

| Quantity | Plan | Measured here |
|---|---|---|
| Floor-bearing suites repo-wide | 74 | **84** |
| Covered (`scripts/` + `plugins/soleur/test/`, recursive) | 40 | **41** |
| Declared-deferred | 34 | **43** |
| Floors that FIRE under a neutered assertion machinery | — | **24** |
| Floors whose mutant is not independently runnable | 3 (named) | **17** (counted, ratcheted) |
| `scripts/` recursive vs non-recursive glob | 78 / 59 | **80 / 61** |

### Suites hardened: 10, not 7

The brief listed five files / seven floors; the plan re-derived seven files / eleven floors.
The rebuilt guard, deriving its own population, found **three more** genuine instances the
brief and the plan both missed — `plugins/soleur/test/net-issue-flow.test.sh`,
`scripts/followthroughs/infra-config-activation-7220.test.sh`,
`scripts/infra-config-red-alert.test.sh`. That is the derivation doing the job a hardcoded
list cannot.

Per-suite green totals after hardening: marketplace-manifest-validate 22, verify-marketplace-ruleset 27,
digest-oracle-guard 26, derive-app-domain-base 33, test-contention 110, tmpfs-guard 60,
preflight-check10 13, net-issue-flow 84, infra-config-activation-7220 17, infra-config-red-alert 29.

### Ratchets moved (all measured post-edit, none guessed)

| Suite | Threshold | Before | After |
|---|---|---|---|
| `derive-app-domain-base` | `CASES_RUN` floor | 26 | **28** |
| `derive-app-domain-base` | `EXPECTED_PASSES` | 34 | **33** (one deleted floor row) |
| `preflight-check10` | `MIN_CHECKS` | 11 | **13** |
| `digest-oracle-guard` | `MIN_ASSERTS` | 26 | **26** (unchanged, and that is measured — the deleted `ok` row was counted AFTER the floor's comparison) |
| `tmpfs-guard` | floor counter | `pass_n` 60 | **`cases` 60** (re-pointed) |
| `test-contention` | floor counter | `pass_n+fails` 110 | **`cases` 110** (re-pointed) |

### Deviations from the plan — stated, not silent

1. **Task 2.2 (standalone call-site coverage lint) was NOT built as a separate lint script.**
   Replaced by three checks that are sound and cheap: the guard asserts statically that no
   conserving suite increments its case counter inside a verdict helper body or inside a
   command substitution, and each suite's conservation check now diagnoses BOTH directions —
   too few verdicts means a discarded verdict, too many means a call site with no increment.
   A missing increment is therefore caught at the next run with a message that names it as a
   harness bug. Reason for the deviation: a bash-parsing lint that decides "is this call site
   reachable without a preceding increment" is itself high-risk vacuous code, which is the
   exact defect class this PR exists to close.
2. **Task 3.5 (conservation arm as a loop RUNNING each covered suite) is implemented
   statically.** Running ~41 full suites would make the meta-guard as slow and flaky as the
   batteries it guards, contradicting the guard's own design constraint (it currently runs in
   ~18s and runs no guarded suite to completion). Conservation is proven per-suite by mutation
   at authoring time — recorded in each commit message — and pinned structurally in the guard.
3. **Task 3.4 (name `preflight-check10`'s three nested SUT floors out of the mutation arm)**
   is handled generically instead: any floor whose mutant is not a runnable program is
   classified CONSTRUCTION, named in the output, and capped by a shrink-only ratchet. A
   by-name exclusion list would be the stale-snapshot antipattern this PR removes.
4. **AC8's literal command is unsatisfiable as written** and was corrected. The plan specifies
   `grep -nE '\$\([^)]*(cases|ASSERTED|asserts)[^)]*\+ 1'`; `\$\(` matches the first two
   characters of the ARITHMETIC expansion `$((cases + 1))`, so the pattern fires on every
   correct increment — including on the committed reference file. Four independent agents hit
   this. The property intended (no increment inside a COMMAND substitution) is expressed as
   `\$\([^(]…` and returns clean on every edited file.

### Guard mutation battery — 7/7 caught, green unmutated control

| # | Mutation | Caught by |
|---|---|---|
| M1 | Revert a tier-1 floor to its `fail()`-routed form | arm 1, naming the suite |
| M2 | Remove the backward slice-widening (thresholds unbound) | construction-failure ratchet |
| M3 | Degrade the oracle to a bare `rc != 0` | construction control |
| M4 | Restrict the sweep to a non-recursive glob | circularity arm + firing ratchet |
| M5 | Force the population sweep empty | population floor |
| M6 | Delete the negative control | accounting conservation |
| M7 | Floor-bearing suite in an uncovered directory | closure, naming the file |

**M7 initially SURVIVED and that was a real defect in the guard**, not a battery bug: the
first version derived `deferred` as "everything not covered", making
`covered + deferred == total` an identity by construction that could never fail. Both scopes
are now declared regexes with an UNCLASSIFIED bucket that must be empty. The plan's Guard 2
row 3 predicted exactly this shape; it still shipped in the first draft and only mutation
caught it.


---

## Addendum — 2026-08-16, post-review

The Completion Record above was written before the review panel ran. Several of its numbers
were **wrong**, and the corrections matter more than the originals. Recorded as an addendum
rather than an edit: the originals are what a green guard reported, and the gap between them
is the finding.

### Corrected population

| Quantity | Recorded above | Measured after review |
|---|---|---|
| Floor-bearing repo-wide | 84 | **97** |
| Covered | 41 | **51** |
| Declared-deferred | 43 | **46** |
| Floors that FIRE | 24 | **36** |
| NO_FIRE | 0 | **0** (after fixing 7 more suites) |
| Mutant not constructible | 17 | **15** |
| Suites hardened | 10 | **17** |

### Why the originals were wrong — four fail-open defects in the guard itself

1. **The oracle matched its own temp path.** The FIRES sentinel ran under `grep -i` and
   included `vacuit`, while every mutant lives under a directory this file names
   `vacuity-floor-meta.XXXX`, which bash prints as the path prefix of its diagnostics. A
   crashing mutant matched FIRES on its own filename; `-i` also made `FATAL` match git's
   `fatal:`. Correcting it moved the reported firing population **51 → 32** before the
   remaining fixes brought it to 36. Caught by ARM 8, the control that exists for this.
2. **CONSTRUCTION was tested before FIRES**, and `|| [[ $rc -eq 2 ]]` forced it unconditionally
   — 2 being this repo's own fatal convention. Compliant floors whose phrasing sat outside a
   hardcoded allowlist were booked as permanent debt.
3. **The derivation missed the arithmetic form** `(( total < MIN ))` and matched COMMENTS and
   HEREDOC bodies. The guard's own header comment was scored a floor and sliced 277 lines of
   the guard into an executed mutant.
4. **The slice refused to cross `$((`.** Arithmetic expansion is safe to carry into a mutant;
   only command substitution is not. Rejecting both left compliant floors unbound.

### A correction to my own widening

`-gt` and `-eq` were added to the operator set and **reverted**: `-gt` is the shape of a
suite's final exit gate (`if [[ "$FAIL" -gt 0 ]]`) and `-eq` of an ordinary assertion, so
admitting them reported 13 "non-firing floors" that were neither floors nor broken. Widening a
matcher moves the error to the other side, and every fixture sat on the must-trip side.

### Ratchets, all proven at zero slack

`MIN_FIRING_SUITES=36` (37 → RED), `MAX_CONSTRUCTION_FAILURES=15` (14 → RED),
`MIN_CONSERVING=18` (19 → RED), `MAX_DEFERRED=46`, `MIN_META_CASES=19`.

### New arms, each mutation-proven

- **8b permissiveness bound** — nothing bounded the oracle in the loose direction, and both
  ratchets move that way. Adding `|expected|error` to the vocabulary now reds.
- **10d** the CASE counter must not move inside a verdict helper (ADR-193 decision #2,
  previously claimed in a comment and enforced nowhere).
- **10e** conservation is EXECUTED, not just spelled. Arms 10a-10d are static and all
  satisfied by a gutted comparison; replacing the condition with `if false` had left the guard
  byte-identical green.
- **ARM 6 deleted** as subsumed by ARM 3 + ARM 5b.

### ADR ordinal

**ADR-191 → ADR-193.** Both 191 and 192 were claimed by sibling branches after the original
probe. Three of the ADR's claims were also corrected: it described the *rejected* closure
identity as shipped, said "seven suites" where ten were hardened, and asserted every covered
suite is mutation-tested when those whose mutant cannot be built are counted separately.

### Deferral

Issue **#7580** filed for the 8 measured NO_FIRE suites in deferred directories, with the 33
CONSTRUCTION listed separately as a measurement task rather than a fix backlog, and the
per-scope-ratchet constraint recorded.
