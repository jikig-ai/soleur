---
title: "feat: CI wall-clock tally dimension, #10865 wall-ceiling re-rule, and stem-minted-SUT derive walk"
date: 2026-11-03
slug: tally-ci-wall-ratchet-ceilings-and-derive-sut-walk
branch: feat-one-shot-11775-10865-extractor-batch
issue: 11775
lane: cross-domain
---

## Overview

One PR carrying three machinery items. (1) Issue #11775: add a CI wall-clock
dimension to `plugins/soleur/scripts/pipeline-tally.sh` and to the
`Pipeline-Tally:` machine line rendered per
`plugins/soleur/skills/ship/references/pipeline-tally-render.md`, sourced from
measured job/run timing with an explicit absent marker when timing is missing.
(2) Issue #10865: perform the owed re-rule of the observation-window probe's
PROVISIONAL wall ceilings in
`scripts/followthroughs/ratchet-observation-window-10865.sh` — a dated
runbook observation-log row with the measured series plus the two constants,
per the probe header rule (d) and the ADR-276 amendment schedule (30-day
trigger 2026-11-22, window opened 2026-10-23T15:41Z; the brief's "owed by
2026-11-20" is satisfied by doing it now). (3) The extractor-level fix for the
stem-minted-SUT derive gap recorded in
`knowledge-base/project/learnings/test-failures/2026-11-02-stem-minted-suts-are-never-walked-by-the-derive.md`:
the derive's closure BFS in `scripts/test-all.sh` never walks a stem-minted
SUT (`x.test.sh -> x.sh` pre-mints the edge), so a SUT's `source` lines mint
nothing; fixes per the learning: walk stem-minted SUTs and tolerate
`$(cd ... 2>/dev/null && pwd)` prefixes, retiring the declared-edge class
added by PR #11919.

## Research Insights

**Premise Validation.** Issues #11775 and #10865 are both OPEN with no closing
PR (checked `gh issue view` 2026-11-03). The cited learning file exists; the
declaration PR #11919 it references merged 2026-11-03. `pipeline-tally.sh`,
`pipeline-tally-render.md`, `ratchet-observation-window-10865.sh`, and the
`_affected_derive`/`_affected_edge_token` derive span in `scripts/test-all.sh`
all exist as cited. The learning's claim was verified directly: the BFS at
`scripts/test-all.sh` (`_affected_derive`, ~line 3905) seeds its queue with
only `_suite_file` and enqueues only edges minted *during* a walk, so the
stem-fan SUT edges minted before it are never walked; and the D1
`$(cd "<dir>" && pwd)` arm in `_affected_edge_token` does not match
`$(cd "<dir>" 2>/dev/null && pwd)` (redirect between target and `&&`), so the
greedy `$(cd*pwd)` fallback collapses the token to the file's own dir and
mints a nonexistent path that `-e` drops. Mechanism check against the ADR
corpus: ADR-242 decision 16 mandates `affected-prepass-bench.sh` selection
identity for derive-span edits — this change is a deliberate widening, so the
identity run uses the bench's explicit-allowance arms or a documented
base/head stream diff (see Guard 1); ADR-276 item 8 makes the drain-reveal
rule binding ("a PR that widens the audit's reach lands only together with
draining every pair it reveals, or dark behind an off-by-default option"); no
ADR rejects any proposed mechanism. Collision precheck: PR #11958 names both
issues but IS this pipeline's own draft (head = this branch); the foreign
`proc.sh` hits are other pipelines' test runs in their own worktrees, not
duplicate work. No open `s4-drain` PR — the claim is free. Live state:
main's advisory ratchet job is currently red (`exit=1 new-pair
live=1512 baseline=1510`, run 41576202102, job 125720159520) and the
observation window is PAUSED; one of the two live pairs
(`scripts/image-cve-triage` ↔ `scripts/betterstack-query.sh`, boundary
`scripts/image-cve-triage.sh:66` — a `$REPO_ROOT`-prefixed literal inside a
stem-minted SUT) is exactly the class this fix repairs.

**Property List.** (a) The tally ledger counts CI wall-clock as a real
dimension and the PR-body machine line carries it under the same `dim=N`
format. (b) Wall-clock is sourced from measured job/run timing, never a
hand-maintained table; missing timing renders an explicit absent marker,
never a fabricated 0. (c) The probe's PROVISIONAL ceilings get their owed
re-rule: whole-population measured series → CTO ruling → dated runbook row +
the two constants (+ every pin/fixture tracking them). (d) The derive walks
stem-minted SUTs so their `source`/invocation/`$VAR/path` tokens mint edges.
(e) `$(cd <dir> [<redirect>] && pwd[ -P])` prefixes resolve to the normalised
cd target, so `libdir="$(cd ... && pwd)"; source "$libdir/x.sh"` derives.
(f) Declared entries that existed only to cover the unwalked-SUT gap retire;
the ratchet baseline and suites track the change honestly (drain-reveal
fixpoint, `s4-drain` claim if the baseline is regenerated).

**Cut List.** (1) A `$libdir` map — property (e) is already bought by
var-resolution (`_vn`/`_vv` in `_affected_file_edges_uncached`) once the
`$(cd ...)` prefix is tolerated; a dedicated libdir convention adds a second
mechanism for the same property. (2) A new consumer/parser for the machine
line — the issue asks for the field in the existing render pair, not a new
reader; no in-repo parser exists to update (checked `git grep Pipeline-Tally`
— only ship SKILL.md + the render spec produce it). (3) A new bench mode for
widening — the verification is a documented stream-diff analysis (Guard 1),
not a new bench flag; the bench's `--added-edges` strip covers unchanged-sel
rows and the remaining sel 0→1 flips are asserted by the analysis recipe, not
by extending the tool.

**Relevant files.** `plugins/soleur/scripts/pipeline-tally.sh` (dim
enumeration: `_tally_dim` :258-265, `_tally_load` key loop :342-351,
`_tally_write` heredoc :367-386, `_tally_ledger_ok` :321-335, `show` :151-158
and its printer, `init --max-*` parsing, `capped=` whitelist);
`plugins/soleur/scripts/pipeline-tally.test.sh` (984 lines, every ledger
fixture embeds the full key set — 5th-dim churn);
`plugins/soleur/skills/ship/references/pipeline-tally-render.md` (machine
line + absent markers); `plugins/soleur/skills/ship/SKILL.md` (`incr
ci_cycles` call sites :2011,:2126,:2153,:2454,:2568 — the wall measurement
rides the same points); `scripts/followthroughs/ratchet-observation-window-10865.sh`
(`P95_MAX=240`/`MAX_MAX=285` :90-91, header (d) :24-27, status line :508,
verdict :528-529); `plugins/soleur/test/ci-pr-affected-replay.test.sh`
(ow_* fixtures pinning 240/285 at :3192-3255,:3698-3702,:3799-3801,:3896-3902);
`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
(ceilings :171,:274,:280, observation log :283+);
`knowledge-base/engineering/architecture/decisions/ADR-276-*.md` (item 6
ceilings, item 8 operating rules incl. drain claim + window restart, item
9(e) the measured series, 2026-11-02 amendment precedent); ADR-268 (machine
line contract); `scripts/test-all.sh` (`_affected_derive` :3803-3934 — stem
fan :3862-3891, `_PRINT_AFFECTED` early-out :3898-3904, BFS :3905-3928;
`_affected_edge_token` D1/greedy `$(cd)` arms; `_affected_file_edges_uncached`
var-collection + three extraction passes);
`scripts/test-affected-derive.test.sh` (extracted-block harness); the derive
cache `scripts/lib/test-affected-derive-cache.sh` (`_ADC_CODEFILES` :67-72 —
the span edit auto-invalidates every record via the code-hash preimage);
`scripts/lib/test-affected-paths.sh`
(`AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` :3341-3353, the
class's first member);
`scripts/ci-pr-affected-replay.py` (REACH doc — its own limits section names
the `$(cd)` gap at :105-106; no code change expected);
`scripts/affected-prepass-bench.sh` (`--added-edges` strips named `^path`
edges from head rows before byte-compare :686-706).

**Institutional learnings.**
`2026-11-02-stem-minted-suts-are-never-walked-by-the-derive.md` (the defect
and the named fixes — this plan implements them);
`2026-11-01-ratchet-repair-pair-disposition-moved-echoes-and-sut-source-boundary.md`
(declare-vs-accept is decided per-pair on the SUT-source boundary; ambiguity
resolves to the stricter default; `--print-baseline` is prune-only and
adopted only when it differs);
`2026-11-02-issue-prescribed-ratchet-remedy-can-be-wrong.md` (verify
mention-vs-read with the pre-acceptance grep before writing either row);
`2026-10-25-draining-an-index-by-declaring-edges-reveals-pairs...` (reveal
fixpoint discipline);
`2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md`
(verify on the merge tree, not the branch tip).

**Conventions.** Units not currency (ADR-056); fail-open tally contract
(exit 0 always, `SOLEUR_TALLY_ERROR` markers); squash merge drops trailers so
the PR body is the aggregation surface (ADR-268); the probe is read-only and
its constants carry dated re-rule comments; a drain PR is claimed by the
`s4-drain` label + a mirror comment on #10448 and restarts the observation
window on merge (ADR-276 item 8); oracle-touching PRs are auto-excluded from
the window's counts.

**Sequential-fallback disclosure.** This plan was authored inside a one-shot
pipeline subagent that cannot spawn nested subagents. The repo-research,
learnings-research, functional-overlap and CTO-ruling roles were executed
sequentially inline by this process against the agent definitions; no
parallel panel ran. `Reviewed-Coverage: sequential-fallback`.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| #10865 issue text: ceilings are 210/270 PROVISIONAL | Re-ruled to 240/285 on 2026-11-02 (ADR-276 amendment + probe :90-91) | Re-rule operates on the CURRENT 240/285, not the issue's stale 210/270 |
| Learning: `$(cd …)` prefixes are not followed | True for the `2>/dev/null`-redirect spelling; plain `$(cd "<dir>" && pwd)` IS handled (D1, #9307) | Fix targets the redirect/defeated spellings, not the whole `$(cd)` class |
| Learning implies audit cannot see the SUT | The AUDIT already reads the SUT via its naming walk and charges the pair; the gap is on the SELECTOR side | Fix lives in the derive (selector), and the audit's wider `pats` is what retires the pair — expect drain-reveal |
| Brief: re-rule "owed by 2026-11-20" | Issue/probe schedule the re-rule at window close or the 30-day trigger (2026-11-22), whichever first; window is open and PAUSED | The PR performs the re-rule now with the freshest pullable series |

## Problem Statement / Motivation

1. `pipeline-tally.sh` aggregates seats/ci_cycles/fix_rounds/agent_rounds but
   not CI wall-clock, so the tally cannot measure required-check batching
   cost under epic #11556 in the same tally as everything else (#11775).
2. The observation-window probe's wall ceilings are PROVISIONAL and owed a
   re-rule at window close or the 30-day trigger (~2026-11-22). The window is
   paused, not closed; the owed re-rule is the deliverable (#10865).
3. The derive's closure BFS never walks a stem-minted SUT, so every
   `x.test.sh ↔ x.sh` pair's SUT-source lines mint nothing — corpus-wide.
   Compensating `AFFECTED_*_PATHS` declarations (the class introduced for
   `inngest-a5-a6-owner-ask-10136`, PR #11919) are needed only because of the
   gap; the fix retires them.

## Proposed Solution

### Workstream A — `ci_wall_s` tally dimension (#11775)

Add a fifth dimension `ci_wall_s` (measured CI wall-clock seconds) with full
dim parity: `_tally_dim`, the `_tally_load`/`_tally_write` key sets, the
`_tally_ledger_ok` count-key whitelist and `capped=` vocabulary, `init
--max-ci-wall-s` flag parsing + validation, `gate`/`warned_` machinery (free —
the code is uniform), `show` output, and the header DIMENSIONS doc. Callers
incr it with seconds measured from real run timing (`gh run view <id> --json
startedAt,updatedAt` deltas on the CI run(s) a push drove, inside ship's
Phase-6/7 flow beside each `incr ci_cycles`); when no timing was measurable
the call is skipped and the dim stays 0. The render spec gains
`ci_wall_s=N` in the `tally:` line and `; ci_wall_s=N` in the machine line,
plus the absent-marker rule: a `ci_wall_s` count of 0 renders as an explicit
absent marker (never a fabricated zero), distinct from `SOLEUR_TALLY_ABSENT`
(whole-ledger absent). Note the partial-coverage caveat: unmeasured cycles
contribute nothing, so the number is a floor.

### Workstream B — observation-window wall-ceiling re-rule (#10865)

Reproduce the 2026-11-02 methodology at implementation time: pull every
non-cancelled `ci.yml` `pull_request`/`merge_group` run since the window
floor (the PR5/`s4-drain` floor 2026-10-26T21:59:35Z), read each
`affected-index-ratchet` job's `started_at`/`completed_at`, and compute the
whole-population p95/maximum plus a per-day p95 series. The CTO role rules
`P95_MAX`/`MAX_MAX` on that series (recorded `Ruled by CTO agent
(sequential-fallback), <date>` in decision-challenges.md and in the runbook
row); land the constants + comment updates + every test fixture pin +
runbook ceiling mentions + a dated observation-log row + a dated ADR-276
amendment (precedent: the 2026-11-02 amendment). If the ruled ceilings raise
per-unit spend beyond the stated 4,400 billed-min/week envelope, the ruling
is an operator (budget-owner) item, not a merge.

### Workstream C — derive walks stem-minted SUTs + `$(cd … redirect … && pwd)` tolerance

1. In `_affected_derive`: after the stem fan, seed the BFS frontier with
   every stem-minted candidate that resolves to a file (probe `f`), so the
   SUT's extraction runs and its `source`/invocation/`$VAR/path` tokens mint
   edges. Execution mode only — the `_PRINT_AFFECTED` early-out already
   returns for stem suites and stays untouched. Derive-cache `read`/`probe`
   rows are recorded automatically through `_affected_file_edges`, and the
   span edit changes `_ADC_CODEHASH`, invalidating stale records.
2. In `_affected_edge_token`: extend the D1 arm to tolerate a redirect
   between the cd target and `&& pwd` (e.g. `2>/dev/null`), keeping the
   greedy fallback and the widen-only `_alt` re-run unchanged.
3. Re-run the ratchet to a fixpoint: every pair the wider `pats` reveals is
   declared or accepted in the same PR (ADR-276 item 8); retire the
   `trusted-verdict.sh` entry of
   `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` (and any sibling
   entry the census shows existed solely for this gap) once `--print-selection`
   proves the derived edge; regenerate the baseline prune-only if covered
   pairs go stale. If the baseline is regenerated the PR claims `s4-drain`
   (label + mirror comment on #10448) per the drain claim — the window then
   counts only post-merge runs, which is the honest reading after an oracle
   change anyway.
4. Verify per the bench/Guard 1 recipe.

## Technical Considerations

- **Selection is deliberately widened.** The `byte-identical` mandate at
  `scripts/test-all.sh:3216` is satisfied by a documented widening proof,
  not by byte identity: base-vs-head `--print-selection` streams diffed with
  the invariant "no edge lost, no sel 1→0, no class regression; every added
  edge traces to a stem-minted SUT's extraction or a `$(cd)`-prefix
  resolution". The `--added-edges` bench arm covers the rows whose sel bit
  did not move.
- **DRAIN-REVEAL is real.** Wider `pats` widen the audit's naming walk → new
  gap pairs may appear; each is declared (real read) or accepted (mention,
  anchor-keyed, runbook reason vocabulary) in the same commit, re-running
  `audit --all-refs`/`ratchet` until `refs`/`files_read`/`gap_refs`/`stale`
  stop moving. The drain rubric's caps (round sizes, hold-backs, hot files)
  apply; an unmanageable first-round reveal is the signal to split, not to
  land dark — the ask explicitly wants the class retired.
- **The live red on main is adjacent, not ours.** Pair
  `image-cve-triage ↔ betterstack-query.sh` is predicted covered by this fix
  (SUT pass-3 `$REPO_ROOT/path` — needs only the walk, not the redirect fix);
  pair `betterstack-emitter-read ↔ image-cve-triage.sh` is a data-table
  mention inside another SUT and needs its own declare/accept disposition —
  take it only if still unrepaired at work time (author/fallback rule), and
  decide with the pre-acceptance grep, never by assuming.
- **`window opened=` floor.** If this PR carries `s4-drain` it restarts the
  observation window by design (ADR-276 item 8); the re-rule's series is
  whole-population regardless of floor.
- **Tally test churn.** The ledger heredoc gains keys; every fixture printf
  and `tally:` assertion in `pipeline-tally.test.sh` must carry the new key
  set — mechanical but wide.
- **Backward compat.** Old ledgers lacking `ci_wall_s` read as 0 (the
  `_tally_load` default); old consumers reading the machine line see one
  more `;`-separated field — format-preserving append.
- **Bash 3.2.** All derive edits honor the extraction anchors (`_AC_CLASS=""`
  at column 0 through `_affected_derive`'s closing `}`) the derive suite
  pins.

## User-Brand Impact

**If this lands broken, the user experiences:** a wrong CI selection — a
suite skipped for a diff that should run it (silent under-coverage in the
affected gate), a tally/machine line that misreports run cost, or an
observation-window probe whose ceilings no longer reflect measured reality
and either never closes #10865 or closes it on a false pass.

**If this leaks, the user's [data / workflow / money] is exposed via:** no
data surface — the surfaces are CI selection correctness and CI spend; a
mis-widened selection burns billed CI minutes (the 4,400-min/week envelope
the budget owner watches).

**Brand-survival threshold:** none — machinery-only change on
verification/observability surfaces; no user data, no product surface.

- threshold: none, reason: diff is confined to CI/test selection machinery,
  a counters ledger, an observability probe and knowledge-base docs — no
  user-data, auth, migration, secret or vendor surface is touched.

## Observability

```yaml
liveness_signal:
  what: the affected-index-ratchet job's marker line (`SOLEUR_PR_AFFECTED_RATCHET exit=… reason=… live=… baseline=…`) on every ci.yml pull_request/merge_group run, and the observation-window probe's nightly status/verdict line
  cadence: every CI run (ratchet); nightly sweeper (probe)
  alert_target: the sweeper's NOT YET/PASS comments on #10865; a red advisory job is visible on every PR check list
  configured_in: .github/workflows/ci.yml + scripts/followthroughs/ratchet-observation-window-10865.sh (already live — this PR measures, it does not create)
error_reporting:
  destination: job-log marker + `##[error]` annotation; tally `SOLEUR_TALLY_ERROR reason=<k>` on stderr
  fail_loud: ratchet exit 1 prints the pair class and the first named cause; probe exit 2 prints every unmet criterion; tally is fail-open BY CONTRACT (exit 0 always) so its loudness is the marker vocabulary, which this PR extends unchanged
failure_modes:
  - mode: derive widening reveals more pairs than the in-PR drain can carry
    detection: `ratchet` exit 1 `new-pair` on this PR's own run; the round-cap triage in the drain rubric
    alert_route: PR CI + the audit fixpoint report (--report)
  - mode: cd-prefix tolerance mints a WRONG edge (over-resolution)
    detection: Guard 1 stream-diff asserting every added edge traces to a stem SUT or a `$(cd)` arm; derive suite mutation rows
    alert_route: local gate + this PR's required `test` context
  - mode: ci_wall_s renders a fabricated zero when unmeasured
    detection: render-spec absent-marker rule + tally suite row asserting the marker at count 0
    alert_route: pipeline-tally.test.sh + ship render review
logs:
  where: job logs (Actions), sweeper comments on #10865, runbook observation log
  retention: Actions retention; runbook log is permanent
discoverability_test:
  command: bash plugins/soleur/scripts/pipeline-tally.sh selfcheck
  expected_output: "SOLEUR_TALLY_OK"
```

## Guard Contract

### Guard 1 — derive widening is monotone and traceable

**Property.** After the fix, every stem suite's derived edge set is a strict
superset of its pre-fix set, every added edge traces to the stem-minted
SUT's own extraction or a `$(cd … && pwd)` resolution, and selection may
only widen (sel 0→1 allowed, never 1→0, never a removed edge, never a class
regression).

**Assembly.** Every runnable registration's `_affected_derive` edge set —
the chokepoint is `--print-selection --paths=<probe>` output (base vs head
streams), plus the extracted-block harness in
`scripts/test-affected-derive.test.sh` for the mechanism itself.

**Mutation matrix.**

| # | Edit under test | Expected |
|---|---|---|
| 1 | Remove the SUT seeding from the BFS frontier (guard's own dispatch) | RED: the stem-SUT fixture suite loses `x-lib.sh` and the known-case check fails |
| 2 | Seed the frontier but skip `_affected_file_edges` for stem-minted files (second member never extracted) | RED: the second-SUT fixture (two stem candidates) mints only the first's edges |
| 3 | Narrow the `$(cd)` arm to require `2>/dev/null` verbatim (a `3>/dev/null` or `-P` spelling slips back to the greedy fallback) | RED: the spelling-matrix fixture loses the edge |
| 4 | Reorder the walk so SUTs are enqueued but their minted edges never re-enqueue (depth accounting) | RED: a SUT-that-sources-a-SUT fixture loses the transitive edge |
| 5 | Mutate the harness: make the fixture SUT absent (must-PASS input that is not the canonical) | PASS-adjacent: no stem edge exists, no walk launched, no error — proves the seeding is existence-gated |
| 6 | A declared edge that is now also derived | PASS: dedup via `_AC_ESET` keeps one entry; class stays edge:derived ∪ declared semantics |

**Anchor.** The base/head stream comparison is against the pre-change runner
on the same tree — a weakening that edits both the derive and the evidence
must also pass the derive suite's own extracted-block floor
(`declare -F _affected_derive` after anchor extraction) and the corpus
`--print-baseline` prune check.

### Guard 2 — tally absent marker is never a fabricated zero

**Property.** A `ci_wall_s` count of 0 (nothing measured) renders as the
declared absent marker on every render surface; a positive count renders
`ci_wall_s=N`; no code path renders `ci_wall_s=0` as if measured.

**Assembly.** The `show` printer, the render spec's machine-line rule, and
the `incr` call sites in ship — the chokepoints are the two render texts
plus the tally suite.

**Mutation matrix.**

| # | Edit under test | Expected |
|---|---|---|
| 1 | Drop `ci_wall_s` from the `show` printer (dispatch) | RED: tally suite's show-line assertion fails |
| 2 | Render `ci_wall_s=0` at count 0 (fabricated zero) | RED: marker row asserts the absent token, not `=0` |
| 3 | Add a measured incr then read the ledger (second-member / real path) | PASS-adjacent + RED-check: `ci_wall_s=N` renders, and a corrupt non-digit `ci_wall_s` is `unreadable`, never 0 |
| 4 | Old-schema ledger (no `ci_wall_s` key) | PASS: reads as 0 → absent marker (backward-compat row) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "[issue #11775] Add CI wall-clock to pipeline-tally.sh dimensions and the pipeline-tally-render.md machine line" | Workstream A; Files-to-Edit tally entries | mapped |
| 2 | "[issue #11775] The dimension must be sourced from measured job/run timing, not a hand-maintained table" | Workstream A measurement rule (gh run/job timing at each incr site) | mapped |
| 3 | "[issue #11775] The machine line stays machine-readable … with the wall-clock field added under the same dimension format" | `; ci_wall_s=N` append per ADR-268's format | mapped |
| 4 | "[issue #11775] Missing timing data degrades to an explicit absent marker, never a fabricated zero" | Absent-marker rule + Guard 2 | mapped |
| 5 | "[issue #10865] the wall_max re-rule owed by 2026-11-20 — read the issue body for what the re-rule requires" | Workstream B: series pull → CTO ruling → constants + dated row + pins | mapped |
| 6 | "[brief] walk stem-minted SUTs, tolerate `$(cd … 2>/dev/null && pwd)` prefixes, or a $libdir map — retiring the declared-edge class" | Workstream C items 1–3 (the `$libdir` map is cut — property (e) covered by var-resolution + cd tolerance) | mapped |
| 7 | "[brief] Do all 3 items in one PR" | This plan | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| `ci_wall_s` as the dim name + `init --max-ci-wall-s` parity | — | inferred — issue says "dimension" and "same dimension format"; parity is the only consistent reading |
| ADR-268 + ADR-276 dated amendments | — | inferred — both documents carry the contract being changed; amendment precedents exist |
| `s4-drain` claim if the baseline regenerates | — | inferred — mandated by ADR-276 item 8 drain claim, not optional |
| Repair disposition for the live `betterstack-emitter-read` pair | — | inferred — conditional, only if still unrepaired at work time (author/fallback rule) |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur/` (tally+render+ship), `scripts/` + `.github`-adjacent CI machinery (derive, probe, ratchet fixtures), `knowledge-base/` (runbook, ADRs)
- Planned files: ~10 | Estimated changed lines: ~450 (bulk is tally-fixture key churn + test rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the ask explicitly bundles all three; the three workstreams share the CI-machinery subsystem.

## Open Code-Review Overlap

One match: #7942 "Two mutation batteries in plugins/soleur/test/ are named
`*.mutation.sh` and run in no gate" — touches `plugins/soleur/test/` only by
naming convention; this PR edits `ci-pr-affected-replay.test.sh` (a
registered suite, not a `*.mutation.sh` battery). **Disposition:
acknowledge** — different concern; the scope-out stays open.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (CI
selection machinery, a metrics ledger, an observability probe). The
mechanical UI-surface scan found no UI-surface file in either Files list.

## Architecture Decision (ADR/C4)

### ADR

- **ADR-276** — append a dated amendment recording the owed re-rule of
  `P95_MAX`/`MAX_MAX` with the measured series (precedent: the 2026-11-02
  amendment; the 30-day trigger lands ~2026-11-22 and this PR performs it
  early with the fresh series).
- **ADR-268** — append a dated note that the `Pipeline-Tally:` machine line
  gains `ci_wall_s` as a fifth `dim=N` field with an explicit absent marker
  (the Decision text pins the four-field format).
- No new ADR: the derive change implements what ADR-242's closure design
  already intended (a bug fix on an existing surface), and the ceiling
  numbers are data, not architecture.

### C4 views

No C4 impact. Checked `model.c4`/`views.c4`/`spec.c4` against the rubric:
(a) external human actors — none added (the readers of PR bodies and issue
comments already exist as `founder`/`reader` surfaces); (b) external
systems/vendors — none added (GitHub the system already models CI/CD, and
the probe/tally read its existing API); (c) containers/data stores — none
new (the tally ledger already exists under the session-state root); (d)
actor↔surface access relationships — unchanged. This is internal
verification machinery.

### Sequencing

The ADR-276 amendment lands in this PR recording the re-rule as executed;
if the work-time ruling keeps the current constants the amendment records
"confirmed, unchanged" rather than inventing new values.

## Implementation Phases

### Phase 1 — `ci_wall_s` tally dimension

1. `pipeline-tally.sh`: add `ci_wall_s` to `_tally_dim` (+ `ci-wall-s`
   hyphen alias), the `_tally_load`/`_tally_write` key sets, the
   `_tally_ledger_ok` count-key and `capped=` whitelists, the `init
   --max-ci-wall-s` flag (+ `--max-ci_wall_s` underscore alias), the `show`
   printer, and the header DIMENSIONS/doc block.
2. `pipeline-tally-render.md`: `tally:` and `Pipeline-Tally:` lines gain
   `ci_wall_s`; add the absent-marker rule (count 0 → explicit absent
   token; positive → `ci_wall_s=N`; `SOLEUR_TALLY_ABSENT` unchanged).
3. `ship/SKILL.md`: at each `incr ci_cycles` site, measure the driven CI
   run's wall (`gh run view`/jobs `startedAt→completedAt` on the head-SHA
   run the push produced) and `incr ci_wall_s <seconds>` when measured;
   skip the incr when timing is unreadable (never post a fabricated 0).
4. `pipeline-tally.test.sh`: sweep every ledger fixture + `tally:` line for
   the new keys; add rows: incr/gate/cap on the new dim, `ci-wall-s` alias,
   absent-marker at 0, positive render, old-schema ledger read, corrupt
   `ci_wall_s` → `unreadable`.

### Phase 2 — wall-ceiling re-rule

5. Pull the whole-population series (non-cancelled ci.yml `pull_request` +
   `merge_group` runs since the floor; per-job `started_at`/`completed_at`
   for `affected-index-ratchet`; overall + since-2026-11-02 p95, maximum,
   daily p95, mean billed minutes).
6. Run the CTO ruling inline on the series (sequential-fallback; record in
   `decision-challenges.md`).
7. Apply the ruling: `P95_MAX`/`MAX_MAX` + comments in the probe; every pin
   in `ci-pr-affected-replay.test.sh` (`ow_u_p95_*`/`ow_u_max_*` helpers,
   `row_ow_slow`/`row_ow_max`/`row_ow_edge_pass` texts, the
   `^P95_MAX=`/`^MAX_MAX=` sentinel greps, the `ceiling-*-raised`/`ceiling-*-lt`
   mutate strings, `row_ow_timeout` text); runbook ceiling mentions + a dated
   observation-log row carrying the series + the ruling; dated ADR-276
   amendment. If the ruling is "keep 240/285": constants stay, the row and
   amendment still land, and the PROVISIONAL tag + "re-rule owed" verdict
   text come off (the ceilings are then final; the recheck trigger stays).

### Phase 3 — derive fix + drain

8. `_affected_derive`: seed the BFS frontier with existing stem-minted SUT
   files (probe `f` on each minted stem candidate), execution mode only.
9. `_affected_edge_token`: extend the D1 `$(cd)` arm past a redirect between
   target and `&& pwd` (`2>/dev/null`, `2>&1`, `-P`), normalising via
   `_affected_normpath` exactly as D1 does; keep the greedy fallback +
   `_alt` widen-only re-run.
10. `test-affected-derive.test.sh`: fixture rows — stem-minted SUT walk
    (x.test.sh + x.sh + sourced lib → edge minted), `$(cd … 2>/dev/null &&
    pwd)` spelling matrix, two-stem frontier, SUT→SUT transitivity,
    absent-SUT no-op; mutation rows per Guard 1.
11. Drain to fixpoint: `python3 -I scripts/ci-pr-affected-replay.py ratchet
    --report <f>` + `audit --all-refs`; declare real reads / accept mentions
    per the rubric (pre-acceptance grep per pair); retire the
    `trusted-verdict.sh` entry of `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS`
    once the derived edge is proven (`--print-selection` row); prune-regen
    `scripts/ci-pr-affected-audit.baseline.tsv` via `--print-baseline` iff it
    differs; claim `s4-drain` (label + mirror comment on #10448) iff the
    baseline is edited; handle the live `betterstack-emitter-read` pair only
    if still unrepaired.
12. Widening proof per Guard 1: base-runner vs head `--print-selection`
    streams on the bench's default probes + a probe path covering a
    stem-SUT-derived file; assert the monotone/traceable invariant; run the
    bench with `--added-edges <delta>` for the unchanged-sel rows.

### Phase 4 — docs, ADR, ship prep

13. Update affected docs (tally header block, derive comments, runbook,
    ADRs, learning's "out-of-scope follow-up" note → pointer to this PR).
14. Local gates: `pipeline-tally.test.sh`, `test-affected-derive.test.sh`,
    `ci-pr-affected-replay.test.sh`, the ratchet, `test-affected-kb-consumers.test.sh`,
    and the derive-cache suite; runner-change fallback acknowledged (a
    `test-all.sh`/paths-lib edit degrades `--affected` to the full battery —
    let CI's required `test` context carry it).

## Files to Create

- (none — all edits land in existing files)

## Files to Edit

- `plugins/soleur/scripts/pipeline-tally.sh` — fifth dim + flag + docs
- `plugins/soleur/scripts/pipeline-tally.test.sh` — key-set sweep + new rows
- `plugins/soleur/skills/ship/references/pipeline-tally-render.md` — machine line + absent marker
- `plugins/soleur/skills/ship/SKILL.md` — measured `incr ci_wall_s` call sites
- `scripts/followthroughs/ratchet-observation-window-10865.sh` — `P95_MAX`/`MAX_MAX` + comments (+ PROVISIONAL wording per the ruling)
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — ceiling fixture pins
- `scripts/test-all.sh` — `_affected_derive` SUT seeding + `_affected_edge_token` `$(cd)` arm
- `scripts/test-affected-derive.test.sh` — fixture + mutation rows
- `scripts/lib/test-affected-paths.sh` — retire the covered declaration entries (+ comments)
- `scripts/ci-pr-affected-audit.baseline.tsv` — prune-only regen iff stale
- `scripts/ci-pr-affected-audit.accept.tsv` — conditional: disposition rows for revealed mentions / the live pair
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — dated observation-log row + ceiling mentions
- `knowledge-base/engineering/architecture/decisions/ADR-276-*.md` — dated re-rule amendment
- `knowledge-base/engineering/architecture/decisions/ADR-268-*.md` — dated machine-line note

## Acceptance Criteria

- [ ] AC1: `pipeline-tally.sh init/incr/gate/show` recognise `ci_wall_s`
      (and the `ci-wall-s`/`--max-ci-wall-s` aliases) and `show` prints it
      alongside the other four dims; `pipeline-tally.test.sh` is green with
      the new key set.
- [ ] AC2: The `Pipeline-Tally:` machine line carries `; ci_wall_s=<N|ABSENT-marker>`
      and never renders `ci_wall_s=0` as a measured value.
- [ ] AC3: Every `incr ci_cycles` call site in `ship/SKILL.md` pairs with a
      measured-timing `incr ci_wall_s` that is skipped (not zeroed) when
      run timing is unreadable.
- [ ] AC4: `P95_MAX`/`MAX_MAX` carry the work-time-ruled values; the probe
      header, both constants' comments, every `ci-pr-affected-replay.test.sh`
      pin, and the runbook ceiling mentions agree; the dated observation-log
      row records the measured series + ruling; a dated ADR-276 amendment
      records the re-rule.
- [ ] AC5: For the `inngest-a5-a6-owner-ask-10136` suite,
      `scripts/test-all.sh --print-selection` shows
      `^scripts/lib/trusted-verdict.sh` in the derived edge set with the
      `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` entry removed —
      proven on the working tree.
- [ ] AC6: `ci-pr-affected-replay.py ratchet` exits 0 (`reason=pass`) on the
      PR tree with the regenerated-baseline diff being pure removals vs its
      base (or no baseline edit if nothing went stale); every pair revealed
      by the wider `pats` is declared or accepted in this PR.
- [ ] AC7: The Guard-1 stream-diff passes: no removed edge, no sel 1→0, no
      class regression, every added edge traceable to a stem SUT or a
      `$(cd)` arm; the derive suite's new fixture + mutation rows pass.
- [ ] AC8: If the baseline was edited, the PR carries the `s4-drain` label
      and a mirror comment exists on #10448 naming this PR's drain.
- [ ] AC9: `test-affected-derive.test.sh`,
      `ci-pr-affected-replay.test.sh`, `pipeline-tally.test.sh`, and the
      ratchet suite pass locally; the required `test` context is green in CI.
- [ ] AC10: The PR body references (does NOT close) #10865 — closing it
      belongs to the sweeper on a PASS — and carries `Closes #11775`.

## Test Scenarios

- `ci_wall_s`: init fresh/merge caps; incr N; gate STOP at cap; WARN band;
  `ci-wall-s` and `--max-ci_wall_s` aliases; absent-marker at 0 on both
  render surfaces; positive render; pre-dim ledger read; non-digit value →
  `unreadable`; `capped=ci_wall_s` latch.
- Ceilings: replay-suite rows re-pinned to the ruled values (`row_ow_slow`,
  `row_ow_max`, `row_ow_edge_pass` at the new boundaries, `ow_mutate`
  strings, sentinel greps) — plus the live probe output once post-merge for
  the runbook row.
- Derive: stem SUT sources a lib → edge; `$(cd dir 2>/dev/null && pwd)/x`
  → normalised edge; `$(cd dir && pwd -P)` still resolves; `$libdir=` var
  chain through a cd-prefix; two stem candidates both walked; SUT→SUT
  transitive; absent SUT is a no-op; dedup when a derived edge is also
  declared.
- Negative: a `$(cd "$(cmd)" …)` with an unresolvable target keeps the
  greedy fallback (widen-only); a redirect form that does NOT match the arm
  falls back identically.

## Success Metrics

- `--print-selection` on `README.md` + a stem-SUT-path probe shows strictly
  widened edge sets only where traceable.
- `ratchet exit=0 reason=pass live=<n> baseline=<n>` on the PR tree;
  baseline diff pure removals.
- The probe's next sweeper run prints the re-ruled ceilings in effect (the
  `wall p95 … is over <P95_MAX>` text, if it fires, names the new values).
- `tally: … ci_wall_s=N` appears in `show` after a measured CI cycle.

## Dependencies & Risks

- **Window restart.** If `s4-drain` is claimed, the #10865 window restarts
  at this merge — honest per ADR-276 item 8, and cheap while the window is
  already paused on main's red.
- **Main's ratchet is red** (`new-pair` live=1512); one pair is predicted
  repaired by this fix, the other needs a disposition — do not absorb the
  second pair silently.
- **Drain-reveal magnitude is unknown until the audit runs.** The rubric's
  round caps bound the work; a first-round reveal beyond caps splits the
  drain per the rubric, not the three-item bundle.
- **Tally is fail-open by contract** — the new dim must never change that
  (every new code path exits 0 on substrate failure).
- **Sequential-fallback** — research/ruling roles ran inline; review-phase
  seats still run normally in later stages.
- **No network-outage trigger** — the SSH/firewall checklist does not apply.
- **No SKILL.md `description:` edit** — the render file has no frontmatter
  description; budget check not applicable.

## References & Research

- Issues: #11775 (tally dim), #10865 (re-rule tracker — does not close),
  #10859 (PR3b, unaffected hold), #10448 (epic), #11226 (drain sentinel).
- Precedent: ADR-276 "Amendment 2026-11-02" (same re-rule shape); runbook
  `ci-pr-affected-activation.md` §The observation log.
- Verified commands: `gh issue view`, `gh api repos/.../actions/{runs,jobs}`,
  `gh run view`, `bash scripts/followthroughs/ratchet-observation-window-10865.sh`
  (ran 2026-11-03: `wall_p95_s=206 wall_max_s=284 units=260 truncated=1`,
  NOT YET — paused on red merge_group), `gh pr list --label s4-drain` (empty).
- External research: skipped — all three items are internal machinery with
  deep local context (Phase 1.6 decision).

## Enhancement Summary

deepen-plan ran 2026-11-03 in sequential-fallback (no nested subagents — the
per-section research/review roles were executed inline by the planning
process; `Reviewed-Coverage: sequential-fallback`).

### Gate verification

- 4.4 precedent-diff: N/A — no scheduled-work/cron surface introduced.
- 4.5 network-outage: N/A — no trigger tokens in scope.
- 4.55 downtime/cutover: N/A — no resource provisioning or state move.
- 4.6 User-Brand Impact: PASS — three required lines + none-threshold
  scope-out bullet present.
- 4.7 Observability: PASS — 5-field schema populated; discoverability
  command `bash plugins/soleur/scripts/pipeline-tally.sh selfcheck` →
  literal `SOLEUR_TALLY_OK`, allowlisted first token, <15 s, no ssh.
- 4.8 PAT-shaped variable: PASS — no PAT/GH_PAT/ghp_/github_pat tokens.
- 4.9 UI wireframe: N/A — no UI-surface file in either Files list.
- 4.10 Encryption posture: N/A — no new store or cross-component connection.
- 4.11 Guard Contract: PASS — `lint-guard-contract.py` clean; 2 guards,
  each Property/Assembly/mutation-matrix (≥3 rows incl. own-dispatch and
  must-pass rows).
- 4.12 Scope Check: PASS — one unfenced `## Scope Check`; every ask mapped
  to an item; the only `inferred` items carry justifications.
- 4.13 Task Design: N/A — no new autonomous-task surface.

### Key deepening applied during the pass

- The series-pull for the re-rule (task 3.1) uses the 2026-11-02 precedent:
  list non-cancelled `ci.yml` runs by event since the `s4-drain` floor, read
  each run's jobs via `actions/runs/<id>/jobs`, filter
  `name == "affected-index-ratchet"`, wall = `completed_at − started_at`;
  p95 is nearest-rank, matching the probe's own arithmetic
  (`rank = ceil(0.95 × n)` — see probe :467-469).
- The BFS seeding (task 4.1) must reuse the existing minted-edge snapshot
  mechanism (`_pre_n` index over `_AC_EDGES`) rather than re-deriving the
  stem list, so only candidates that actually minted an edge are probed —
  the stem fan emits up to 31 candidates per suite, most nonexistent.
- `pipeline-tally.sh`'s `show`/`incr`/`gate` are fail-open by contract; the
  absent-marker rule lives ONLY in render text, never in exit codes or
  verdict tokens (UNKNOWN/STOP/OK vocabulary is untouched).

### New considerations discovered

- The audit's `pats` include the full execution-mode closure, so the fix
  widens the audit's reach transitively — drain-reveal is in scope
  (ADR-276 item 8) and is budgeted into Phase 3 via the rubric's round caps.
- Main's advisory ratchet is red on an unrelated-second pair at plan time —
  absorbed only if still unrepaired at work time (decision-challenges.md).

