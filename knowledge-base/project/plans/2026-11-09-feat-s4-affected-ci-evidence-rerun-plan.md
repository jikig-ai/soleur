---
title: "ci: re-run S4 affected-CI evidence and re-rule go/no-go on a fresh 300-commit window (#9729)"
type: chore
date: 2026-11-09
slug: s4-affected-ci-evidence-rerun
branch: feat-one-shot-9729-s4-evidence-rerun
issue: 9729
closes: []
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# ci: re-run S4 affected-CI evidence and re-rule go/no-go on a fresh 300-commit window (#9729)

## Overview

Re-run the S4 affected-only-CI evidence bundle prescribed by runbook
`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §3/§4 — the strict-zero
audit on a detached `origin/main` checkout, the escape replay plus ejections on a fresh 300-commit
window of `origin/main`, the criterion-(c) saving re-measurement and the criterion-(d) reader audit —
then re-rule the go/no-go and record the result. This is the **fourth** re-ruling under epic #9729
(open, parked; this PR does not close it): the three prior windows computed `NO-GO`, every time on
criterion (a)'s worst-case bound, with the failing numerator dominated first by `unclassified-job`
name drift (eliminated by the term-1 allowlist in R3), then by `failed-job-without-fail-line` and
unsettled suite legs. This window is the first to exercise the merged ejections-corroboration and
classifier-coverage fixes (94db41c89b "ejections merge_group corroboration + classifier unsettled-leg
coverage (#12446)", a2fe028227 "#9323 escape classifier Arm A (#12439)"), both merged 2026-11-09 —
the measurement is precisely a read on whether those fixes shrink the not-evaluable bucket under the
12% bound. Budget-owner authorization for the re-run and the re-ruling was given by the operator
in-session on 2026-11-09.

Every command is read-only against the repository; the replay writes only under `--out` in `/var/tmp`;
all `gh api` calls are reads. **Nothing in this PR activates anything:** no `CI_PR_AFFECTED` variable
is set, `PR_AFFECTED_LOCKED` stays in `scripts/ci-pr-selection.sh`, no ci.yml/ruleset/required-checks
edit, no stage-2 build. Even a GO verdict only makes the stage-2 build *buildable* — the
pre-activation gate independently reads `missing=lock,artifacts,verdict,prereq5`, and the flip needs
a budget-owner go-ahead naming the command.

## Problem Statement / Motivation

ADR-276's 2026-10-16 amendment (item 5) ordered the re-ruling once the index drain reached strict
zero; the 2026-11-07 and two 2026-11-08 re-rulings all answered NO-GO on criterion (a) with the
recorded diagnosis "the fix for criterion-a pressure is classifier coverage, not more reads". The
classifier-coverage fixes landed this morning. The evidence question they were built to answer —
does the worst-case bound now certify under 12%? — has no committed measurement yet. The pre-flight
gate (`scripts/ci-pr-affected-preactivation.sh`) still reads
`missing=lock,artifacts,verdict,prereq5` against the r3 receipt, so a fresh re-ruling is the only
path that moves the recorded state.

## Proposed Solution

Execute the runbook §4 recipe verbatim on a fresh window, mirroring the receipt shape of the R3
re-ruling (`specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/r3/`) and the
criterion-a rerun (`specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/receipts/rerun/`):

1. Pin the window with a single `git fetch origin main`; record the resolved SHA in `commands.txt`.
2. Fresh pinned-tree `audit` on a detached `origin/main` worktree, **both** spellings (with and
   without `--accept`; the plain `audit` does not auto-load the accept file — R3 disclosure), plus a
   `preactivation` read inside the same detached tree (`tree=head-is-main`).
3. `collect --commits 300` chunked `--chunk I/4` in four parallel legs (~2.5 h serial → ~40 min
   wall; per-unit resumable), then `ejections --commits 300` into the same `--out` (~25 min).
4. `aggregate --expect-commits 300` → `replay-summary.txt`; `cp-upper` for the bound.
5. Criterion (c): fresh baseline via `scripts/ci-demand-census.sh` over two adjacent closed 12-hour
   windows; 20-run saving sample; both readings (per-full-run and population-weighted).
6. Criterion (d): `scripts/test-affected-kb-consumers.test.sh` + the KB-mention census →
   `reader-audit.md`.
7. `verdict --a --b --c --d` (read `computed=`; the exit code carries no verdict) →
   `receipts/go-no-go.md` ending in the `SOLEUR_PR_AFFECTED_VERDICT` machine line.
8. Record: ADR-276 `## Amendment 2026-11-09 (S4 go/no-go re-ruling, #9729)` + dated stage-status line
   + `Go/no-go receipt:` line (the convention every prior re-ruling followed — inferred scope item);
   one dated bullet appended to runbook §2; a result comment on #9729 (convention — inferred).

## Technical Approach

### Architecture

No architecture change. The measurement runs the committed tooling unmodified:
`scripts/ci-pr-affected-replay.py` (collect/ejections/aggregate/verdict/cp-upper/audit),
`scripts/ci-pr-affected-preactivation.sh`, `scripts/ci-demand-census.sh`,
`scripts/test-affected-kb-consumers.test.sh`, `scripts/test-all.sh --print-selection`,
`scripts/suite-durations{,-heavy}.tsv`. All replay output lives under `/var/tmp/s4-rerun-9729-r4`;
receipts are the committed copies.

### Implementation Phases

#### Phase 0 — Pin the window, verify entry conditions, launch long poles (~20 min active)

+ `git fetch origin main`; record `BASE=$(git rev-parse origin/main)` in `receipts/commands.txt`
  with the timestamp. **One fetch for the whole run** — the local `origin/main` ref pins the window;
  never re-fetch mid-run (the stale-window hazard #12456 tracks is collect-side, mitigated
  procedurally here).
+ Writer exclusivity check before any launch: `pgrep -af 'ci-pr-affected-replay'` and
  `test ! -e /var/tmp/s4-rerun-9729-r4` — two writers on one `--out` is the forbidden configuration;
  an orphaned `--out` is adopted only after the runbook's TWO proofs (byte-identical writer trees +
  per-idx `sha == rev_list(<window-tip>)[idx]`). Fresh dir, no adoption expected.
+ Smoke the live `gh` seam: `collect --out /var/tmp/s4-smoke --commits 2 --chunk 1/1 --base origin/main`
  (expect rc 0); `rm -rf /var/tmp/s4-smoke` after.
+ Entry condition 2 verify: `grep affected-index-ratchet scripts/required-checks.txt` (required
  since PR3b #12329 — confirmed at :251 during planning; re-assert at work time).
+ Pinned audit (entry condition 1): `git worktree add --detach /var/tmp/s4-audit origin/main`;
  `python3 -I scripts/ci-pr-affected-replay.py audit --root /var/tmp/s4-audit --all-refs --accept /var/tmp/s4-audit/scripts/ci-pr-affected-audit.accept.tsv > /var/tmp/s4-audit.out` (~3 min);
  plus the bare spelling `audit --root /var/tmp/s4-audit --all-refs > /var/tmp/s4-audit-bare.out`
  (the pre-exemption set — both committed, matching r3).
  Expect `unaudited=0 gap_suites=0 stale=0`, exit 0. **A non-zero audit is criterion-(b) evidence,
  not a to-do**: record the failing rows verbatim and rule (b) `fail` — draining is a separate
  `s4-drain` PR per the runbook's drain rubric, never this evidence PR.
+ `cd /var/tmp/s4-audit && bash <repo>/scripts/ci-pr-affected-preactivation.sh > /var/tmp/preactivation.out`
  (committed as `receipts/preactivation.out`), then `git worktree remove --force /var/tmp/s4-audit`.
+ Launch four collect legs in parallel:
  `python3 -I scripts/ci-pr-affected-replay.py collect --out /var/tmp/s4-rerun-9729-r4 --commits 300 --chunk I/4 --base origin/main` for I=1..4 (background; ~40 min wall; each writes
  `units-commits-<I>-of-4.jsonl`, resumable per unit).
+ After all four legs exit: `python3 -I scripts/ci-pr-affected-replay.py ejections --out /var/tmp/s4-rerun-9729-r4 --commits 300 --base origin/main` (~25 min; prints the conclusion
  histogram; writes `ejections-window.json` with `corroborated`, `queue_oracle`, `expected_units`).

#### Phase 1 — Aggregate and criterion (a)

+ `python3 -I scripts/ci-pr-affected-replay.py aggregate /var/tmp/s4-rerun-9729-r4 --expect-commits 300 --out /var/tmp/s4-rerun-9729-r4/replay-summary.txt` — rc 2 on an incomplete/mismatched dir is
  the integrity gate doing its job (duplicate units, missing ejections file, count ≠ expected_units);
  never hand-edit the JSONL to satisfy it (the R3 dedup was byte-identical adjacent rows from a
  double writer, a different situation).
+ `python3 -I scripts/ci-pr-affected-replay.py cp-upper <worst-case numerator> <N>` for the bound.
+ Extract: commit classes, ejection classes/routes, `runs_via` histogram (whether the
  `check-runs`/`corroborated-no-run`/`check-runs-window` arms fired — the corroboration paths this
  window exists to exercise), the not-evaluable composition vs R3 (unsettled legs, no-fail-line,
  unclassified), point estimate, worst-case numerator → status. Write `histograms.txt` and
  `replay-commits.tsv`.

#### Phase 2 — Criterion (b)

+ Status = the Phase-0 audit exit code (0 = pass). Record the `SOLEUR_PR_AFFECTED_AUDIT` summary
  line verbatim plus `refs`/`files_read` (reach-movement evidence even when gaps stay zero) and any
  `stale`/`unaudited`/`gap` rows.

#### Phase 3 — Criterion (c): fresh baseline + saving sample

+ Baseline: `bash scripts/ci-demand-census.sh --start <t0> --end <t1> --workflow ci.yml --summary`
  over two adjacent closed 12-hour windows ending before work starts (the script's max span);
  combine per its LONGER SPANS recipe (`TOTAL_JOB_SECONDS` + runs summed, per-run recomputed) →
  baseline M min/pull_request-run; bar = 0.20·M. Save `census-w1.txt`, `census-w2.txt`; extract the
  STEM rows for the gated legs' run share (`test-scripts`, `test-scripts-heavy`, `test-webplat`,
  `test-bun`) and the `affected-index-ratchet`/`pr-selection` debit readings.
+ Saving: the 20 most recent completed `pull_request` `success` runs
  (`gh run list --workflow ci.yml --event pull_request --status success -L 20`); resolve each PR
  (run `pull_requests` array, else `gh pr list --head <branch> --state all -L 1` — merged-PR runs
  return an empty array since R3); changed files via `gh api repos/jikig-ai/soleur/pulls/<n>/files`;
  selection via `env -u CI -u SOLEUR_TEST_FORCE_ALL bash scripts/test-all.sh --print-selection --paths=<list>`;
  price `sel=0` non-`always_on` rows via `suite-durations{,-heavy}.tsv` (absent label = 1.18 s lower
  bound). Record the raw row table.
+ Readings: (1) sampled full-battery mean gross − ~1 min `pr-selection` − ~3.4 min/run ratchet
  debit; (2) population-weighted by the priced leg's run share (the bar's own denominator). Status:
  `pass` / `fail` / `within-10%` per the verdict contract. Timing leg: cite the PR C canary
  (`specs/archive/<ts>-feat-one-shot-9729-ci-pr-c-affected-only/receipts/sel-s-canary.md` — cold
  146 s / warm 13 s → ~29 s job path ≤ 120 s) unchanged; re-assert only if the selection code path
  changed since (it has not — `git log` on `scripts/ci-pr-selection.sh` is the check).
+ Write `receipts/criterion-c.md` (method, raw rows, both readings, stated limits).

#### Phase 4 — Criterion (d): reader audit

+ `bash scripts/test-affected-kb-consumers.test.sh` (expect exit 0); KB-mention census
  (`git grep -l "knowledge-base" -- 'apps/web-platform/**/*.test.*' 'apps/web-platform/test' | wc -l`);
  `scripts/test-affected-kb-consumers.baseline.txt` row census (covered vs `false-positive:`);
  the `apps/web-platform [repo-wide+component]` `edge:consumed` check on a README-only diff.
+ Write `receipts/reader-audit.md` with the blind-spot paragraph from the census header.

#### Phase 5 — Verdict, receipts, record

+ `python3 -I scripts/ci-pr-affected-replay.py verdict --a <s> --b <s> --c <s> --d <s>` —
  read `computed=GO|NO-GO|UNDECIDED reason=...` on stdout; never `&&`-chain it (exit 0 always).
+ Commit `knowledge-base/project/specs/feat-one-shot-9729-s4-evidence-rerun/receipts/`:
  `README.md`, `commands.txt`, `go-no-go.md` (criterion table + why-the-deciding-criterion-decides
  + non-activation statement + terminal
  `SOLEUR_PR_AFFECTED_VERDICT verdict=<v> ruled=<confirmed|pending> date=2026-11-09`),
  `replay-summary.txt`, `replay-commits.tsv`, `histograms.txt`, `ejections-window.json`,
  `index-audit.out`, `index-audit-bare-noaccept.out`, `index-audit.err`, `preactivation.out`,
  `criterion-c.md`, `census-w1.txt`, `census-w2.txt`, `reader-audit.md`.
+ Append to ADR-276: `## Amendment 2026-11-09 (S4 go/no-go re-ruling, #9729)` (status stays
  `adopting`; the four criterion figures; verdict; full non-activation paragraph; the
  `Go/no-go receipt: knowledge-base/project/specs/feat-one-shot-9729-s4-evidence-rerun/receipts/go-no-go.md`
  line — the LAST such line wins for the gate; note ship archives the spec dir and the gate reads
  the archived copy) plus a dated `### Stage status` line. **Inferred item** — see Scope Check.
+ Append one dated bullet under runbook `ci-pr-affected-activation.md` §2 (window, population
  counts, `computed=<v>`, the deciding criterion, receipt path, `missing=` gate line,
  retire-vs-schedule stays operator-owned per #10448).
+ `gh issue comment 9729` with the verdict, the criteria table and the remaining blockers.
  **Inferred item** — convention from R2/R3; the epic stays open.
+ Non-activation invariants, asserted in the PR diff:
  `git diff --name-only origin/main...HEAD` contains only `knowledge-base/` paths;
  `grep -n 'readonly PR_AFFECTED_LOCKED=1' scripts/ci-pr-selection.sh` still matches;
  `gh api repos/jikig-ai/soleur/actions/variables/CI_PR_AFFECTED` still 404.

## Alternative Approaches Considered

| Option | Why rejected |
|---|---|
| Re-run criterion (a) only (like the #10862 rerun) | §3.3 prescribes replay + saving + reader audit re-run *and* the re-rule — a partial pass leaves the record `unmeasured` on b/c/d and cannot produce a GO. |
| Adopt a sibling session's in-flight `--out` | The runbook's two-proofs rule (byte-identical writer trees + per-idx sha check) plus the #12456 stale-window risk make a fresh window the clean reading; a fresh `--out` is cheap. |
| Serial collect (no `--chunk`) | ~2.5 h wall vs ~40 min for identical output; resumability is per-unit either way. |
| Drain any audit residual inside this PR | The drain rubric makes drains their own labelled PRs; a non-zero audit here is criterion-(b) *evidence*, recorded as `fail`, not repaired. |
| Skip the criterion-(c) re-measurement and carry R3's `within-10%` | The criterion demands a *fresh* baseline and sample — R3 itself re-measured; carrying a stale reading would misreport the criterion. |

## User-Brand Impact

+ **If this lands broken, the user experiences:** a wrongly-recorded S4 verdict in ADR-276 and the
  runbook — e.g. a false GO misleading the next lever decision, or a false NO-GO burying a working
  lever. No end-user surface: the whole diff is repo-internal CI evidence docs (`meta/machinery`).
+ **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure — the
  replay reads public-to-`gh`-auth Actions data (run ids, commit SHAs, suite names, timings) with the
  operator's own token; receipts contain CI metadata only; all writes are local `/var/tmp` + docs.
+ **Brand-survival threshold:** `none`
+ **Threshold decision (challengeable):** the diff touches only `knowledge-base/` docs and receipts —
  verified zero matches against the canonical `SENSITIVE_PATH_RE` (preflight Check 6 Step 6.1) over
  the file list below, so the next tier does not apply.

## Observability

The deliverable is a multi-hour measurement run, not a service — the observability target is the
run's own resumability and failure visibility (a stalled or double-written `--out` is the property
that matters).

```yaml
liveness_signal:
  what: "per-unit JSONL appends under /var/tmp/s4-rerun-9729-r4 (units-commits-<I>-of-4.jsonl for collect; units-ejections.jsonl for ejections) — the chunk manifests are the resumability evidence; a leg with no append for >3x the ~21-28 s per-unit cadence is stalled"
  cadence: "per-unit (~21-28 s/commit; ejection units similar)"
  alert_target: "the executing session's transcript (the pipeline monitors its own legs; no external pager — a one-shot measurement, not a daemon)"
  configured_in: "scripts/ci-pr-affected-replay.py (the --out manifest layout is the writer's own)"
error_reporting:
  destination: "the replay legs' stdout/stderr captured to receipts/commands.txt-adjacent logs and the session transcript"
  fail_loud: "non-zero leg rc (collect/ejections/audit rc 3 = read failure, rc 4 = internal); aggregate rc 2 on an incomplete or mismatched --out; an aggregate refusal is a stop, never a hand-edit"
failure_modes:
  - mode: "interrupted collect/ejections leg (session kill, API outage)"
    detection: "JSONL row count < chunk share; re-running the same --chunk command resumes per-unit (read_done)"
    alert_route: "the session transcript + aggregate --expect-commits 300 rc 2 at the gate"
  - mode: "origin/main moves mid-run appending stale-window units (#12456 class)"
    detection: "single-fetch pinning + the recorded BASE sha in commands.txt; per-idx sha verification before any adoption"
    alert_route: "aggregate's duplicated/extra-unit refusal (rc 2)"
  - mode: "second concurrent writer on the same --out (forbidden configuration)"
    detection: "the Phase-0 pgrep exclusivity check; byte-identical adjacent duplicate rows are the R3 signature"
    alert_route: "aggregate's 'two chunk layouts' refusal (rc 2)"
  - mode: "gh API transient failures / search-index drops"
    detection: "not-evaluable units + runs_via histogram in replay-summary.txt; ejections-window.json expected_units vs unit count"
    alert_route: "visible in the criterion-(a) numerator — conservative by contract, never suppressed"
logs:
  where: "/var/tmp/s4-rerun-9729-r4/* (commands.txt, replay-summary.txt, ejections-window.json, JSONL manifests) + committed copies under receipts/"
  retention: "/var/tmp is ephemeral — the committed receipts are the durable record; that is exactly why they are a deliverable"
discoverability_test:
  command: "grep -l SOLEUR_PR_AFFECTED_VERDICT knowledge-base/project/specs/feat-one-shot-9729-s4-evidence-rerun/receipts/go-no-go.md"
  expected_output: "knowledge-base/project/specs/feat-one-shot-9729-s4-evidence-rerun/receipts/go-no-go.md"
```

No soak enrollment (Phase 2.9.1): the re-ruling is a one-shot measurement, not a time-gated
criterion. No new autonomous-task surface (Phase 2.9.3).

## Architecture Decision (ADR/C4)

### ADR

+ **ADR-276 (append-only amendment, in-scope task):** `## Amendment 2026-11-09 (S4 go/no-go
  re-ruling, #9729)` + dated `### Stage status` line — the Decision-3(g) record this evidence step
  owes; non-activating (no flip, no lock removal, no ci.yml/ruleset/required-checks/infra edit).
+ **No new ADR:** the plan executes a measurement ADR-276 already ordered (item 5 of the 2026-10-16
  amendment); a fresh GO/NO-GO verdict is recorded *inside* ADR-276, not as a new number. A GO does
  not change the Decision — it satisfies a prerequisite the Decision names.

### C4 views

No C4 impact. Enumeration checked against `model.c4`/`views.c4`/`spec.c4` (all three read
2026-11-09): (a) external human actors — none added (the replay is repo automation run by the
existing `founder` operator; no new sender/recipient/role); (b) external systems/vendors — none
added (`gh api` reads hit the already-modelled `github` external; no new store or edge);
(c) containers/data-stores — none (receipts are committed markdown; `/var/tmp` scratch is not a
modelled store); (d) actor↔surface access relationships — unchanged (read-only). The C4 validation
tests (`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`) are unaffected.

### Sequencing

The amendment lands in this PR. If the verdict is GO, activation remains a separately authorized
step — the budget owner's go-ahead naming the command, plus the §6 items (admin-side control
decision, stage-2 reduced-run read, lock removal in the stage-2 PR's last commit) — recorded in the
amendment, not deferred to a silently-untracked issue. If NO-GO again, the retire-vs-schedule call
returns to the operator per #10448 — an operator (scope/priority) call, never a silent close.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Re-run the S4 affected-CI evidence and re-rule go/no-go per knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md sections 3 and 4, on a fresh 300-commit window of origin/main" | Phase 0–5 whole; §4 commands verbatim | mapped |
| 2 | "receipts under the branch's spec dir" | Phase 5 receipts/ commit | mapped |
| 3 | "an appended observation-log line in the runbook's section 2" | Phase 5 §2 dated bullet | mapped |
| 4 | "the computed verdict with criterion detail" | go-no-go.md criterion table + `verdict` output | mapped |
| 5 | "Out of scope — do not do, do not propose: setting the CI_PR_AFFECTED repository variable, removing the PR_AFFECTED_LOCKED lock, ruleset changes, the stage-2 build itself, any deploy or activation" | Non-activation invariants (Phase 5 + ACs); no phase touches them | mapped |
| 6 | "the long-running collect/ejections legs need resumability evidence (--chunk manifests) and the discoverability_test.command must run without SSH" | Observability block | mapped |
| 7 | "cite it in the plan frontmatter. Do NOT use `Closes #N` anywhere" | `issue: 9729`, `closes: []`; no `Closes` token anywhere in the PR | mapped |
| 8 | "Open adjacent issue #12456 (stale-window pinning in collect) is optional context for the plan, not required scope" | Phase 0 single-fetch pinning + Dependencies & Risks note | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| §4 command sequence (detached audit, chunked collect, ejections, aggregate, cp-upper) | "per …runbook… sections 3 and 4" | asked |
| Criterion-(c) census + 20-run sample | "re-run the S4 affected-CI evidence" (§4 prescribes the saving re-run; R3 receipts fix the method) | asked |
| Criterion-(d) reader audit | "re-run the S4 affected-CI evidence" (§3.3: "the saving and the reader audit are re-run") | asked |
| `receipts/` under spec dir | "receipts under the branch's spec dir" | asked |
| Runbook §2 dated bullet | "an appended observation-log line in the runbook's section 2" | asked |
| `preactivation.out` capture | — | inferred — every prior re-ruling committed it; it is the gate's own read of `missing=`, evidence the non-activation statement cites |
| ADR-276 amendment + `Go/no-go receipt:` line | — | inferred — Decision 3(g) makes the stage's PR append the amendment; every prior re-ruling (2026-11-07, both 2026-11-08) recorded the verdict this way; the gate's `verdict=` prerequisite reads the receipt path from the ADR line, so skipping it breaks the record-of-record chain |
| `gh issue comment 9729` | — | inferred — convention from R2/R3; keeps the parked epic's record complete; harmless to descope |
| `decision-challenges.md` rows | pipeline rule — technical rulings without spawn capability record `pending - assumed` | inferred |

### Split Assessment

+ Subsystems touched: 1 — `knowledge-base/` (docs + receipts only; zero code)
+ Planned files: ~17 (plan, tasks, decision-challenges, ~12 receipt files, runbook edit, ADR append)
+ Estimated changed lines: ~600 (receipt contents dominate; code diff = 0)
+ Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
+ Recommendation: single PR — one coherent evidence deliverable under one epic ref.

## Acceptance Criteria

### Functional Requirements

+ [ ] FR1 — Fresh pinned audit: `audit --root /var/tmp/s4-audit --all-refs --accept <pinned>` on a
  detached `origin/main` worktree; its exit code, `SOLEUR_PR_AFFECTED_AUDIT` summary line
  (`suites= always_on= audited= unaudited= gap_suites= gap_refs= accepted= stale= refs= files_read=`)
  and the bare-no-accept run are committed (`index-audit.out`, `index-audit-bare-noaccept.out`,
  `index-audit.err`).
+ [ ] FR2 — Replay integrity: `aggregate /var/tmp/s4-rerun-9729-r4 --expect-commits 300` accepts the
  directory (rc 0) — 300 commit units across `units-commits-{1..4}-of-4.jsonl`, an
  `ejections-window.json` whose unit count satisfies `expected_units`, `replay-summary.txt`
  committed.
+ [ ] FR3 — Criterion statuses measured: (a) point estimate + cp95 bound on the worst-case numerator
  from the summary; (b) audit exit code; (c) fresh baseline + sampled saving, both readings, status
  per the band; (d) census + baseline counts + `edge:consumed` check. Each lands in `go-no-go.md`
  with its receipt link.
+ [ ] FR4 — Verdict: `verdict --a --b --c --d` output committed verbatim; `go-no-go.md` ends with
  `SOLEUR_PR_AFFECTED_VERDICT verdict=<GO|NO-GO|UNDECIDED> ruled=<confirmed|pending> date=2026-11-09`.
+ [ ] FR5 — Runbook §2 gains exactly one dated bullet (2026-11-09) recording window, population
  counts, computed verdict, deciding criterion and receipt path; no other runbook section is edited.
+ [ ] FR6 — ADR-276 gains `## Amendment 2026-11-09 (S4 go/no-go re-ruling, #9729)` + a dated
  `### Stage status` line + a `Go/no-go receipt:` line pointing at the new receipt, with the full
  non-activation paragraph. (Inferred item — see Scope Check.)
+ [ ] FR7 — `receipts/preactivation.out` committed, captured from the detached `origin/main` tree
  (`tree=head-is-main`).

### Non-Functional Requirements

+ [ ] NFR1 — Non-activation: `git diff --name-only origin/main...HEAD` lists only
  `knowledge-base/` paths; `readonly PR_AFFECTED_LOCKED=1` still present in
  `scripts/ci-pr-selection.sh`; `gh api repos/jikig-ai/soleur/actions/variables/CI_PR_AFFECTED`
  still 404; no `Closes` token anywhere in the PR (issue stays open).
+ [ ] NFR2 — Window integrity: one `git fetch` for the run; `commands.txt` records the resolved
  `origin/main` SHA + timestamp; no `--out` adoption without the runbook's two proofs; a `pgrep`
  exclusivity check precedes every writer launch.
+ [ ] NFR3 — Reproducibility: `commands.txt` lists every replay invocation with its rc; receipts
  state which `runs_via` arms fired so a reader can tell whether corroboration was exercised live.
+ [ ] NFR4 — Resumability: collect chunked 4-way so any leg re-runs per-unit (`read_done`); a
  stopped run resumes, it never restarts.

### Quality Gates

+ [ ] QG1 — No unit hand-editing to satisfy `aggregate`; an rc-2 refusal is diagnosed and re-measured,
  never patched.
+ [ ] QG2 — No counterfactual re-grading: not-evaluable stays in the worst-case numerator; any
  "had these been classifiable" arithmetic is recorded as commentary only (R3 convention).
+ [ ] QG3 — `verdict` is never `&&`-chained; `computed=` is read from stdout (exit 0 always).

## Test Scenarios

+ Given a detached `/var/tmp/s4-audit` at `origin/main`, when `audit --all-refs --accept <pinned>`
  runs, then it exits 0 with `unaudited=0 gap_suites=0 stale=0` (expected; a non-zero arm is
  handled per Phase 0 — recorded as criterion-(b) fail, not drained). `integration`
+ Given `pgrep -af ci-pr-affected-replay` finds no writer and `/var/tmp/s4-rerun-9729-r4` is absent,
  when the smoke `collect --commits 2 --chunk 1/1` runs, then it exits 0 with both units classified
  and `runs_via` set. `integration`
+ Given 4 collect legs writing separate `units-commits-<I>-of-4.jsonl`, when one leg is killed and
  re-run with the same `--chunk`, then it resumes from `read_done` rows without duplicates.
  `integration` (resume-on-interrupt; exercised only if an interrupt occurs — the manifest shape is
  asserted instead by `aggregate` accepting the dir).
+ Given the ejections listing corroborates against `expected_units`, when `aggregate` runs, then the
  unit count matches `ejections-window.json` (else rc 2 — the gate doing its job). `integration`
+ Given all four criterion statuses, when `verdict` runs, then `computed=` on stdout matches the
  hand-computed rule (GO iff all pass; NO-GO iff any fails outside the band; else UNDECIDED).
  `unit` (the arithmetic is the script's; the check is reading `computed=` not the exit code).

## Success Metrics

+ A committed `receipts/` set matching the R3/rerun shape with `commands.txt` showing every rc.
+ `computed=` produced by `verdict` (not paraphrased) with the four per-criterion statuses and
  figures in `go-no-go.md`.
+ One §2 observation bullet; one ADR-276 amendment; zero non-`knowledge-base/` diff paths.

## Dependencies & Risks

+ **Wall time:** ~40 min chunked collect (4 legs) + ~25 min ejections + ~3 min audit + ~1 h
  criterion-(c) API reads. Budget for ~2.5 h elapsed.
+ **gh API quota** (~1,000 req/repo/hr shared, the sweeper token budget note): collect does
  ~1 read/commit plus corroboration retries; ejections reads runs/jobs/logs per refused unit. A
  rate-limit stall surfaces as `not-evaluable` inflation or a leg rc — resumable, never suppressed.
+ **Sibling writers:** the Phase-0 `pgrep` + dir-absence check is the only guard; a collision
  found mid-flight is the R3 duplicate-row defect — stop, prove or re-dir.
+ **Stale-window risk (#12456, optional context):** `collect` does not pin the window tip; the
  single-fetch procedure pins it locally. If `origin/main` moves mid-run anyway (someone re-fetches),
  appended units are stale-window units — per-idx sha verification before adoption, else re-run.
+ **Not-evaluable composition may not shrink:** the fixes target classification coverage
  (unsettled legs, allowlist drift) and corroboration (index drops); `failed-job-without-fail-line`
  and genuinely-cancelled runs may persist — that outcome is *the measurement*, not a defect of it.
+ **Criterion (c) denominator drift:** the fresh baseline may move the bar again (120.17 → 102.21
  between R2 and R3); both readings are recorded so a band landing is unambiguous.
+ **ADR-276 amendment is inferred scope:** if review descopes it, the receipt still carries the
  verdict; the gate's `verdict=` prerequisite then keeps reading the older receipt — disclosed in
  Scope Check, not hidden.

## Hypotheses

The plan Phase-1.4 network-outage trigger fired on the substring `SSH` in the brief's
"discoverability_test.command must run without SSH". This plan contains no network-connectivity
hypothesis at all: every command is local or read-only `gh api` HTTPS; no host is contacted over
SSH and no outage is being diagnosed. L3→L7 layers are **not applicable** (opt-out justification,
per the checklist's opt-out arm): there is no SSH path in scope — the artifact proving it is the §4
command block itself (git/python3/gh only, and the committed `ci-pr-affected-replay.py --help`
naming `gh api` as its only remote seam).

## Research Insights

### Premise Validation (Phase 0.6)

+ **#9729** — verified OPEN, `priority/p3-low`, parked epic ("ci: S4 PR affected-only suite set,
  merge_group keeps the full battery (#9721 stage 4, parked)"). **#12456** — verified OPEN
  ("replay collect: pin the rev-list window tip in --out…"), optional context only.
+ **Runbook** — `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` read in
  full; §3 entry conditions and §4 commands confirmed verbatim against the current script's
  `--help` (subcommands and flags unchanged: `collect/ejections/aggregate/verdict/cp-upper/audit/
  ratchet/glob-rate`; `ejections-window.json` now carries `corroborated`/`queue_oracle`/
  `expected_units` and `aggregate` refuses a mismatched unit count — the merged corroboration fix).
+ **Tooling** — `scripts/ci-pr-affected-replay.py`, `ci-pr-affected-preactivation.sh`,
  `ci-pr-affected-audit.accept.tsv`, `test-affected-kb-consumers.test.sh`, `ci-demand-census.sh`,
  `suite-durations{,-heavy}.tsv`, `suite-shard-legs.tsv` all present at HEAD.
+ **HEAD tree** — `af764001ee` (origin/main tip) + one init commit; includes both merged fixes
  (94db41c89b at HEAD~1; a2fe028227 earlier today). `readonly PR_AFFECTED_LOCKED=1` still at
  `scripts/ci-pr-selection.sh:90`; `affected-index-ratchet` in `scripts/required-checks.txt:251`
  (required — entry condition 2 already met).
+ **Receipt shape** — R3 (`…/receipts/r3/`) and the criterion-a rerun (`…/receipts/rerun/`) read;
  the full-re-ruling receipt set is mirrored in Phase 5.
+ **Collision precheck** — `collision-precheck.sh 9729` exit 10: the only PR naming #9729 is this
  branch's own auto-created draft PR #12477; foreign `test-all.sh` processes belong to a sibling
  worktree (`feat-one-shot-cloud-sandbox-gh-auth-missing`) — informational, not a `--out` writer.
+ Nothing stale: every cited artifact exists; every cited mechanism is committed.

### Property List (Phase 0.6b)

1. A fresh 300-commit window of `origin/main` is measured by the committed replay tool.
2. The audit reading is strict-zero on a detached `origin/main` tree (entry condition 1).
3. The verdict is computed by `verdict`, with criterion-level statuses traceable to receipts.
4. Evidence is durable (committed receipts) and resumable (chunk manifests).
5. The runbook's §2 observation log gains the dated entry; nothing else mutates.

### Cut List (Phase 0.6b)

+ No new mechanism proposed: the replay, preactivation, census and selector are the existing
  machinery; the plan adds zero code. Nothing to cut — the only deliverables are measurements,
  receipts and doc records.

### Files & Authorities

+ `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — §1 gate, §2 log,
  §3 entry conditions, §4 recipe, §5 criteria, §6 GO-owes, §7 ratchet.
+ `scripts/ci-pr-affected-replay.py --help` — THE authority for the rule, classes, REACH, DECLARED
  LIMITS, RATCHET, exit codes (`verdict`/`cp-upper` always exit 0).
+ `scripts/ci-pr-affected-preactivation.sh` — the seven prerequisites; receipt line accepts
  `verdict=(GO|NO-GO|UNDECIDED) ruled=(confirmed|pending)`; reads `Go/no-go receipt:` (last line
  wins), `Skippable set:`, `Waiver:` from ADR-276.
+ `knowledge-base/engineering/architecture/decisions/ADR-276-*.md` — Decision 3(g) recording
  convention; `## Amendment 2026-11-07/2026-11-08` re-ruling shape; current `Go/no-go receipt:`
  line at :662 points at the archived r3 receipt.
+ Prior receipts: `specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/r3/`
  (go-no-go.md, criterion-c.md, reader-audit.md, index-audit*.out, preactivation.out,
  ejections-window.json, replay-summary.txt, replay-commits.tsv, census-w{1,2}.txt,
  adoption-note.md) and `specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/receipts/rerun/`
  (README.md, commands.txt, histograms.txt, replay-summary.tsv).
+ Institutional learnings applied: the R3 collection-integrity note (two writers on one `--out` is
  the forbidden configuration; byte-identical adjacent duplicates are its signature);
  `2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md` (audit on the
  pinned tree, never the branch tip — already §4's detached-worktree rule);
  `2026-11-08-converting-changed-path-readers-…` (read failure ≠ "no match" — mirrors the replay's
  own "a failed READ is never 'no failure'" contract).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI-machinery evidence re-run producing committed receipts
and two doc appends; no user-facing surface, no spend change (read-only API calls), no legal,
marketing, sales or support surface.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (2026-11-09, 200 fetched) contains no issue
whose body names `ci-pr-affected-activation.md` or `ci-pr-affected-replay` (the only repo paths this
plan touches besides new spec-dir files). Check ran, zero matches.

## References & Research

### Internal References

+ Runbook: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §1–§7
+ Decision record: `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`
  (`## Amendment 2026-10-16 (S4 PR C, #9729)` item 5; `## Amendment 2026-11-07`/`2026-11-08` re-rulings)
+ Tooling: `scripts/ci-pr-affected-replay.py`, `scripts/ci-pr-affected-preactivation.sh`,
  `scripts/ci-demand-census.sh`, `scripts/test-affected-kb-consumers.test.sh`,
  `scripts/test-all.sh`, `scripts/suite-durations{,-heavy}.tsv`
+ Prior receipts: `knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/r3/`,
  `knowledge-base/project/specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/receipts/rerun/`
+ Prior plan of the same class: `knowledge-base/project/plans/archive/20261108-080841-2026-11-07-chore-ci-lever-residuals-plan.md`

### Related Work

+ Issue #9729 (epic, open — ref only, never `Closes`); issue #10448 (the decision the NO-GO left);
  issue #12456 (optional context: stale-window pinning in collect); issue #10414 (PR D per-suite
  selection); PR #12477 (this branch's draft).
+ Merged fixes this window exercises: #12446 (ejections corroboration + classifier coverage),
  #12439 (escape classifier Arm A + R3 re-ruling), #12329 (PR3b required ratchet).
