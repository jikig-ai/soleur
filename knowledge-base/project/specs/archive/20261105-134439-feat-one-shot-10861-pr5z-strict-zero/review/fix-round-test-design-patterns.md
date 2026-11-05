# Fix-round review — test-design-reviewer + pattern-recognition-specialist

- **PR:** #12127 (`jikig-ai/soleur`), worktree `feat-one-shot-10861-pr5z-strict-zero`
- **HEAD reviewed:** `73f497e48a` (fix commit "review: strict-zero contract sweep + remedy-tail gate (P2/P3)")
- **Fix diff audited:** `git diff 79db88e18b..HEAD` — the 4 functional files (`scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, `.github/workflows/ci.yml`, runbook §7). The other 7 entries in the range are prior round's committed review reports, not code.
- **Probe workspace:** `/tmp/soleur-fr.Td9n` (mktemp, per seat rules; two fixture git repos + one mutant SUT copy; no live-tree edits, no full `test-all.sh`).

---

## Verdict per question

### (a) Do the new assertions pin the properties they name? Can a mutant suppress the remedy tail under base-absent and still pass — incl. a `names &`-only gate regression?

**PASS — pinned on both faces, verified by live probe.**

The gate at `replay.py:2092` (`if base_text is not None and names & {"stale-line","baseline-dup","baseline-order","grown"}`) is pinned in both directions:

| Mutant | Caught by | Probe evidence |
|---|---|---|
| `names &`-only (revert of the fix; tail fires under base-absent) | `row_rt_big_baseline` (:2511): `grep -q '^baseline-dup\t'` + `! grep -q -- '--print-baseline' <<<"$ROUTALL"` | Mutant copy (`base_text is not None and ` elided) run on the reintroduced+dup fixture printed `remedy: delete the offending line(s) … ratchet --print-baseline > …` — the `!` conjunct goes red. Confirmed discriminating. |
| Suppress tail unconditionally (`if False:` / drop the block) | `row_rt_text_stale` (:2567) whole-stdout golden — it requires the two tail remedy lines verbatim under base-present, and its chk label (:2944) says exactly that ("the only --print-baseline recipe, the whole stdout golden") | Positive control: real SUT on a base-present repo with a stale line emitted the golden-shaped tail verbatim. |
| Suppress-by-short-circuit (skip findings when `base_text is None`, so no dup/stale detail prints) | `row_rt_big_baseline`: `grep -q '^baseline-dup\t'` requires the co-fired line-level findings under the reintroduced marker | Real SUT on reintroduced+dup printed `baseline-dup\tscripts/bl-dup.tsv\t…` — co-fire confirmed live. |

Depth note (observation, not a finding): inside `row_rt_reintroduced` arm 1 (`std adopt`, bl-ok.tsv) the `! --print-baseline` conjunct is **non-discriminating for the `names &`-only mutant specifically** — the baseline's only line is live under `L-std`, so `names={baseline-reintroduced}` and the tail wouldn't fire even unmutated. That conjunct still discriminates mutants that emit the regenerate remedy unconditionally on the reintroduced path (e.g. print-baseline inside the reintroduced remedy list, tail appended per-finding). The `names &`-only regression is covered suite-wide by `row_rt_big_baseline`; the arm-1 conjunct is a correctly-placed invariant, not a hole.

### (b) Is `row_rt_big_baseline`'s new control flow correct (`rt_is` rc semantics: r==0 = row passed, then conjuncts)?

**PASS.** `rt_is` (:2350) returns 0 iff `RC` matched the expected exit AND `rt_marker` matched — i.e. `r==0` means "this ratchet call produced the asserted verdict". `r=$?` is captured immediately after `rt_is`, before `(( SECONDS - t0 < 25 ))` can clobber `$?`. Conjunct order — budget, then `[[ "$r" -eq 0 ]]`, then the dup detail, then the `! --print-baseline` absence — is a strict strengthening of the old `(( budget )) && return "$r"; return 1`: any failure of `rt_is`, the budget, or either new property lands on `return 1`. The grep forms are right: `'^baseline-dup'$'\t'` concatenates to a `^`-anchored BRE with a literal TAB (output line is `baseline-dup<TAB>scripts/bl-big.tsv<TAB><shown>`), and `--` guards the `--print-baseline` pattern against option parsing — both idioms match sibling rows (:2473, :2475). `ROUTALL` (stdout+stderr) is the right sink: the remedy tail goes to `out`, but checking the union also covers a future move of diagnostics to stderr, consistent with `row_rt_deleted`.

### (c) Is assertion depth now symmetric with sibling rows?

**PASS.** After the fix the baseline-state block is uniform:

| Row | exit+marker | detail pin | remedy pin | absence pin |
|---|---|---|---|---|
| `row_rt_reintroduced` :2473 | `rt_in` ×2 | `grep -qxF` full detail line (stronger than siblings' `-q`) | — | `!grown`, `!--print-baseline` (ROUTALL) |
| `row_rt_reintroduced_newpair` :2474 | `rt_in` | `grep -qxF` co-fired `new-pair` line | — | — |
| `row_rt_deleted` :2475 | `rt_in` | `grep -qxF` restore remedy | — | `!--print-baseline` (ROUTALL) |
| `row_rt_big_baseline` :2511 | `rt_is` | `grep -q '^baseline-dup\t'` co-fire | — | `!--print-baseline` (ROUTALL) + 25 s budget |
| `row_rt_text_stale` :2567 | rc + golden | whole-stdout equality incl. both tail lines | — | — |

The co-fired-detail pattern (reintroduced_newpair's `new-pair` line ↔ big_baseline's `baseline-dup` line) and the `!--print-baseline` absence pattern (deleted ↔ reintroduced ↔ big_baseline) are now symmetric. The chk label at :2970 (`…always reports baseline-reintroduced changes no verdict`) now agrees with the fixture comment at :2285 and the row comment at :2515 — it was the last "adoption" straggler in the labels.

### (d) Any remaining text contradicting strict zero in the touched files?

**One P2, plus P3 stragglers.**

- **P2** — runbook `:213–214` still speaks pre-strict-zero: "A rename or move of a path **a baselined suite** names reads as a new pair **(growth, exit 1)**: a rename of **a baselined path or suite** is a **drain-class PR** … rename-carry (an exact one-to-one rename of a pair already in the base baseline) is a PR3b entry condition". Under strict zero `grown` cannot fire on the default path (the same file's own reason table at :189 says "`grown` needs a base baseline"); nothing is "baselined"; "drain" has nothing left to drain; and rename-carry's stated precondition (pairs in a base baseline) is empty-set. The actionable advice (declare/accept the renamed pairs in the same PR; expect red while advisory) survives, so operator harm is a mis-labelled token and dead vocabulary — but this paragraph escaped the sweep that correctly rewrote :155, :185–189 and :209–211.
- **P3** — mutate names `ratchet-adoption-refused` (:4889) and `ratchet-unresolved-base-is-an-adoption` (:4895) keep the retired "adoption" word; both mutants remain valid and discriminating (the first is what `! grep '^grown'` in arm 1 kills). Cosmetic only.
- **P3** — runbook :186 `new-pair` row still says "not in the baseline"; vacuously true on the default path and accurate for `--baseline` invocations. Borderline nit, leave or fold into the :213 fix.
- Clean: ci.yml comment (:399–403), replay.py RATCHET help (:135–141), BASELINE STATE table (:151–153 — "Present at both: equality" is correct for `--baseline`/old-base invocations and the table is explicitly framed as covering all four states), `--print-baseline` help (:157–158, mechanism honestly described; runbook :223 supplies the "never re-create" rule), section banner :1747, chk :2899/:2944.

---

## Findings

| # | Sev | Where | What |
|---|---|---|---|
| 1 | **P2** | `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md:213–214` | Residual pre-strict-zero wording escaped the sweep: "baselined suite/path", token `growth` (unreachable on the default path — the file's own table at :189 agrees), "drain-class PR", rename-carry keyed on "a pair already in the base baseline". Reword to `new-pair` / declare-or-accept-in-the-same-PR vocabulary. |
| 2 | **P3** | `plugins/soleur/test/ci-pr-affected-replay.test.sh:4889,4895` | Two `mutate` names still say "adoption"; rename for vocabulary uniformity (mutants unaffected). |
| 3 | **P3** | runbook `:186` | `new-pair` "not in the baseline" phrasing is vacuous under strict zero; harmless. |

Optional hardening (not a finding): the mutation battery has no row mutating `replay.py:2092` itself. Unnecessary — the two behavioral faces (tail absent under base-absent via big_baseline; tail present under base-present via the :2567 golden) are already proven red by live probes — but a `mutate ratchet-remedy-tail-under-reintroduced 'if base_text is not None and names &' 'if names &' row_rt_big_baseline` row would make the battery self-describing at zero behavioral cost.

No P1.

## Test-quality score (changed assertions only)

| Property | Score | Notes |
|---|---|---|
| Understandable | 8/10 | Row comments name each pinned property; chk labels match fixtures |
| Maintainable | 7/10 | `-qxF`/golden pins message bytes — intentionally brittle per suite convention |
| Repeatable | 9/10 | Deterministic fixtures; `SECONDS` budget retained, no wall-clock assertion |
| Atomic | 8/10 | One property per conjunct; arm-2 is a second scenario, consistent with suite style |
| Necessary | 9/10 | Pins exactly the regression class this fix closes |
| Granular | 9/10 | Each conjunct fails pointing at a named line |
| Fast | 9/10 | Greps on captured output; the 150k-line run keeps its 25 s budget |
| First (TDD) | 6/10 | Fix-commit shape; ordering not independently verifiable |

**Test Quality Score: 8.0 / 10 (Grade: B)**

### Pyramid

| File | Layer | Signals | Verdict | Confidence |
|---|---|---|---|---|
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` | unit | `*.test.sh` path; existing suite, modified not added; registered `measured` weight rows (`scripts/suite-durations.tsv:189–191`, shards -a/-b/-c) | PASS | high |

### Patterns observed

- Positive: the gate reuses the file's own presence-guard idiom (`base_text is not None and …`, same shape as the `grown` check at :2075); the baseline-state semantics stay table-driven rather than flag-scattered.
- Positive: fix pairs each "absence" assertion with a "co-fire still prints" assertion (dup detail + `! --print-baseline`) — absence pins can't silently pass because the SUT stopped emitting the block.
- Anti-pattern (elsewhere, pre-existing): runbook §7 mixes state-table vocabulary across the strict-zero boundary in one section; the :213–214 paragraph is the leftover.

## Probe log (all in `/tmp/soleur-fr.Td9n`)

1. `repo` (base: full fixture incl. `plugins/soleur/scripts/lint-ratchet.py`, no baseline; HEAD adds `bl-ok.tsv`, `bl-dup.tsv`): real SUT → `baseline-reintroduced`, `stale-line`/`baseline-dup` co-fires, **no** `--print-baseline` (both arms) — fix confirmed live.
2. Mutant `replay-mut.py` (`names &`-only gate, applied to a copy): same arm emits the regenerate tail incl. `--print-baseline` — proves `row_rt_big_baseline`'s absence conjunct discriminates.
3. `repo2` (baseline committed at base, stale at HEAD): real SUT emits the two-line tail verbatim matching the :2567 golden shape — proves the tail still fires under base-present.
