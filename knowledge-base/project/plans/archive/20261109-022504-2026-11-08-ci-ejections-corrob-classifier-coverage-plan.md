---
title: "ci: ejections merge_group corroboration + classifier coverage for the not-evaluable bucket"
date: 2026-11-08
slug: ci-ejections-corrob-classifier-coverage
branch: feat-one-shot-12428-12444-ejections-corrob-classifier
issue: 12428
lane: cross-domain
---

## Overview

One PR delivers the two CTO-ruled deliverables that gate the next criterion-a §4 evidence
re-run for `CI_PR_AFFECTED` (runbook:
`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §4/§5).

- **#12428 — ejections merge_group corroboration.** `cmd_ejections` in
  `scripts/ci-pr-affected-replay.py` lists refused merge_group runs via the search-indexed
  `?event=merge_group&created=…` listing; a run the index drops is invisible to its
  `total_count` guard and to the ejections population, biasing `cp95_upper_on_worst_case`
  toward a false GO on the only escape-bearing population. The 2026-11-08 CTO ruling on
  #12428 (binding) directs: pin every merge_group run whose `head_sha` is a landed
  first-parent commit through commit-keyed non-search reads over the window's ~300 commits,
  and corroborate refused runs through a per-PR expected-count oracle
  (`added_to_merge_queue`/`removed_from_merge_queue` issue-timeline events vs distinct
  `gh-readonly-queue/main/pr-N-*` head_branch names); a shortfall counts into worst_case
  under the existing conservative rule.
- **#12444 — classifier coverage for the not-evaluable bucket.** At n≈382 the re-run needs
  `worst_case ≤ 35` (cp95 < 12%). `FOLDED_JOBS` at HEAD already resolves 29/58. The two
  ruled routes: (a) a principled clearing rule for unsettled cancelled legs (~24 units —
  `test-webplat`, `affected-index-ratchet`, `test-scripts` legs whose `cancelled`
  conclusion is permanent and irreducibly not-evaluable without a route), extending the
  `cleared`/same-tree path; (b) fail-line extraction covering the 5
  `failed-job-without-fail-line` units. Full ruling on #10448/#12444.

Both rulings are binding: this plan builds them and does not re-litigate.

## Research Insights

**Premise validation (Phase 0.6).** #12428 OPEN (no closing PR), #12444 OPEN, #10448
CLOSED (it is the ruling document, cited as evidence, not a blocker). The 2026-11-08
comment on #12428 carries the binding ruling text + live-verified evidence (merge_group
`head_sha` == landed sha for `4fba0d5`/`9515a20`/`057f1e5`; check-runs resolves ephemeral
queue SHAs; PR 12390 timeline verified). `scripts/ci-pr-affected-replay.py:449-475`
(`corroborating_runs`), `cmd_ejections` (:724-819), `classify` (:579-621), `check_complete`
(:860-881) and `FAIL_LINE` (:224) all exist as cited. Collision pre-check: PR #12446 is
THIS branch's own one-shot draft — not a foreign work item. ADR corpus: ADR-276 (S4
activation) is the governing record; the mechanisms proposed (commit-keyed corroboration,
timeline oracle, classifier clearing route) extend its established evidence pattern — none
sits in a rejected-alternatives table.

**Live probes run this session (2026-11-08, all read-only):**

- `commits/{sha}/check-runs` on origin/main tip + 3 older commits: 111–247 check-runs,
  28–65 distinct `actions/runs/<id>` ids per commit → naive `corroborating_runs` reuse is
  ~300 × ~40 run reads ≈ **12k calls/window**; the ruled shape needs the bounded join below.
- `commits/{sha}/check-suites?per_page=100`: 127 suites on `0fb4a0f61`; every github-actions
  suite carries `head_branch` — `gh-readonly-queue/main/pr-N-<sha>` (merge_group) vs `main`
  (push) vs third-party apps (`claude`, `soleur-ai`, `entire`). This is the non-search,
  commit-keyed pivot that bounds the corroboration to ~4–5 pages/commit.
- `issues/12390/timeline`: `added_to_merge_queue`/`removed_from_merge_queue` events exist
  with `created_at` and `commit_id:null` — 4 adds / 4 removes (the count bound the ruling
  describes; sha-exactness is impossible, per the ruling's own dissent).
- `?event=merge_group&created=` listing: branch names are
  `gh-readonly-queue/main/pr-<N>-<group-sha>`; multiple runs share a branch (re-runs), so
  DISTINCT branch names ≈ queue entries — the correct observed-side for the oracle.
- The 5 `failed-job-without-fail-line` units decompose into three signatures (verified):
  (i) 2× runner-shutdown mid-suite — log ends `##[error]The runner has received a shutdown
  signal`/`##[error]The operation was canceled` + `Last suite started: <label>` marker, no
  `[FAIL]` line (jobs 124613574229 → `scripts/test-all-affected-b`, 126016312817 →
  `plugins/soleur/test/codeql-main-alert-gate.test.sh`); (ii) 2× job-log HTTP 404
  (BlobNotFound) whose check-run annotations carry `"The hosted runner lost communication
  with the server"` (jobs 125980654539, 127743275859); (iii) 1× real `[FAIL]` line the
  regex can't capture — `[FAIL] apps/web-platform [repo-wide+component] (90485ms)`
  (job 128273594206) — the label contains spaces and `[…]`, outside FAIL_LINE's
  `[A-Za-z0-9._/+-]+` charset.

**Property List (Phase 0.6b):**

- P1 — the ejections window listing's completeness is provable against non-search reads:
  dropped merge_group runs on landed shas become units; refused runs on ephemeral shas are
  bounded by the queue-event oracle.
- P2 — every unit in the not-evaluable bucket has a principled route to a verdict or a
  documented irreducible residual.
- P3 — the conservative rule is preserved: any residual unknown feeds `worst_case`,
  never silently `clean`.
- P4 — on a churn-heavy fresh window at n≈382, `worst_case ≤ 35` (cp95 < 12%) is
  reachable and durable.

**Mechanism check:** every mechanism the ruling names maps to a property with no existing
coverage — `cleared()` fires only inside the `would_skip_hit` arm (unsettled legs never
reach it), `corroborating_runs` exists but was never iterated over a window, no queue-event
read exists at all, `FAIL_LINE` can't capture the observed label shape. **Cut List:** none.
Considered and bounded instead of cut: verbatim `corroborating_runs` reuse at ~12k calls —
kept the semantics, bounded the enumeration via the check-suites join to satisfy the
ruling's own "bounded run reads" sizing (~300 check-runs + ~300 timeline reads).

**Relevant learnings:**
`2026-09-24-an-empty-api-search-is-not-evidence-of-absence` (search-parameter listings are
not authoritative — the whole premise); `2026-09-21-a-selector-that-settles-on-the-first-
qualifier` (run-discovery reads key on the wrong field unless pinned);
`2026-10-30-a-read-only-verifier-*` (refusal predicates must be validated against the
producer's real output — the timeline-annotation and shutdown-signature matches here are
read from live production records, not hypothesized shapes).

**Conventions:** `ReadError` is the fail-loud seam (never "nothing found"); units are
JSONL keyed `(kind, sha)`; the stub-`gh` suite (`fx`/`fx_err`/`fx_once`, `STUB-MISS`)
pins every API path the tool reads; `DECLARED_TOTAL` counts gated `mutate` sites.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-visible.
  `ci-pr-affected-replay.py` is an evidence/measuring tool and the advisory ratchet job;
  a wrong change makes a replay measurement lie or the advisory job red — no serving
  surface, no user data.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no vector — the
  change reads public Actions run/job/timeline metadata of this repo and writes receipts
  under knowledge-base.
- **Brand-survival threshold:** none — machinery-only change to a CI measurement script;
  the canonical sensitive-path regex matches none of the touched files.

## Implementation Phases

### Phase 1 — `cmd_ejections` corroboration (#12428)

`scripts/ci-pr-affected-replay.py`:

1. **Window commits always computed.** `cmd_ejections` currently derives `shas` only when
   `--since/--until` are absent (:731-738). Compute the `--commits`/`--base` first-parent
   list unconditionally: the corroboration anchor set is the window commits either way;
   explicit `--since/--until` still bounds `created_at` membership.
2. **Bounded landed-sha enumeration** — new `merge_group_runs_on(repo, sha)` beside
   `corroborating_runs` (reusing its trust rules: repo-namespace `details_url` regex,
   `total_count == seen` truncation refusal, fan-out cap):
   - `gh_pages("repos/%s/commits/%s/check-suites?per_page=100")` — paginated; collect
     `QUEUE_SUITE_IDS = {s["id"] for s in check_suites if s["app"]["slug"] == "github-actions"
     and (s["head_branch"] or "").startswith("gh-readonly-queue/")}` — the check-suites
     listing read carries the same `total_count == seen` truncation refusal as
     check-runs (CTO advisory 2026-11-08: a silently truncated suite list would
     under-enumerate the census).
   - `gh_pages("repos/%s/commits/%s/check-runs?per_page=100")` — paginated; take
     `details_url` run ids only from check_runs whose `check_suite.id ∈ QUEUE_SUITE_IDS`
     (the join that bounds run reads to queue-branch suites).
   - `actions/runs/{id}` per distinct id — keep `event == "merge_group" and
     path == CI_WORKFLOW_PATH and head_sha == sha` (same filters as `corroborating_runs`).
   - Per-commit read failure → one synthetic not-evaluable unit
     (`corroboration-read: <sha>`), never a silent skip; a commit yielding zero
     github-actions queue suites is a recorded zero, not an error (a commit whose main
     landing bypassed the queue legitimately has none — it is still reported in the
     corroboration block).
3. **Union the population (CTO pin 2026-11-08).** `listed_ids = {r["id"] for r in runs}`;
   `missing = [r for found in per_commit if r["id"] not in listed_ids and
   since <= r["created_at"] <= until]`; `runs = listed + missing` — `by_pr`, `fail_runs`,
   the conclusion histogram and `cleared()` all see the union (a dropped SUCCESS run
   clearing units via `cleared()` is desired). **Corroborated SUCCESS runs are
   `by_pr`/histogram clearing witnesses only — they are never written as ejection
   units** (a clean unit would inflate n and dilute the cp95 bound); corroborated
   **non-success** runs are units counted inside `refused`. Corroborated units carry
   `u["runs_via"] = "check-runs-window"` for receipt provenance; missing non-success
   runs are classified by the identical pipeline (`files_for`, `fill_selection`,
   `cleared`, `classify`) — they are real runs, not synthetic placeholders.
4. **Queue-event oracle.** `prs = {pr_of(r["head_branch"]) for r in runs} - {""}`;
   per PR, `gh_pages("repos/%s/issues/%s/timeline?per_page=100")` (paginated array docs)
   → `added = #{added_to_merge_queue with created_at ∈ window}`,
   `removed = #{removed_from_merge_queue ∈ window}` (recorded for the receipt);
   `observed = #{distinct head_branch names for this PR across runs}`;
   `shortfall_pr = max(0, added - observed)`. Each shortfall yields ONE synthetic unit:
   `base_unit("ejection", next_idx, "queue-oracle:pr-<N>-<i>")`, `u["pr"]=N`, `run=None`,
   `reason="queue-oracle-shortfall: pr-<N> added=<a> branches=<b>"` → `classify` classes it
   `not-evaluable` (no run) — the conservative worst_case count the ruling prescribes.
   A failed timeline read for PR N contributes ONE shortfall unit
   (`queue-oracle-read: pr-<N>`), not a hard fail — consistent with "a failed read is
   never nothing found" and keeps one bad PR from voiding a completed window. Both counts
   land in `ejections-window.json` (below).
5. **`ejections-window.json` schema** gains (existing keys keep their meaning):

   ```json
   {"since","until","runs":<listed total>,"refused":<listed+found non-success>,
    "conclusions":{<listed histogram>},
    "corroborated":{"commits":K,"merge_group_on_landed":M,"missing_ids":[...],
                    "missing_refused":Mr,"read_failures":F},
    "queue_oracle":{"prs":P,"added":A,"removed":R,"distinct_branches":B,
                    "shortfall":S,"read_failures":Q},
    "expected_units":<refused + S + F + Q>}
   ```

   `check_complete` (:878-880) compares the ejection-unit count to
   `meta.get("expected_units", meta["refused"])` — old-shape manifests (and the suite's
   `mkmeta` fixtures) still validate.
6. **Resume semantics.** Corroborated-run units key on `(kind, head_sha)` — stable across
   re-runs; oracle units key on the deterministic `"queue-oracle:pr-<N>-<i>"` sha-field;
   `--redo-unevaluable` drops and re-derives both (deterministic re-derivation each
   invocation). A shortfall that SHRINKS between invocations leaves stale keys →
   `expected_units` mismatch at `aggregate` → fail-loud (rc 2), never a silent pass.
7. **Docstring** (`ejections` section, :21, :48, `not-evaluable` :36, DECLARED LIMITS):
   name the corroboration arms, the oracle's count-bound nature, and the THREE documented
   residuals — (a) an `added_to_merge_queue` entry removed before the queue spawned a run
   over-counts expected (worst_case direction, per the conservative rule); (b) a queued PR
   whose EVERY run the index dropped is invisible to both arms (the ruling's own
   documented residual — events can't name a branch nobody listed); (c) observed can
   exceed in-window adds at window edges — a pre-window add whose run landed in-window
   makes observed > in-window added (verified live: pr-12390 4 adds vs 6 distinct
   branches), so `max(0, added - observed)` can mask a partial index drop at the edges
   (CTO AMEND 2026-11-08 — count bound is necessary-not-sufficient by construction).

### Phase 2 — classifier coverage (#12444)

`scripts/ci-pr-affected-replay.py`:

1. **FAIL_LINE label charset** (:224): `([A-Za-z0-9._/+-]+)` → `([ -~]+?)` — lazy
   printable-ASCII capture, so `[FAIL] apps/web-platform [repo-wide+component] (90485ms)`
   resolves to the full label and `[FAIL] bad\x1b]0;title\x07label (90ms)` still does NOT
   match (control bytes are outside `[ -~]` — the pinned row stays green). The suite stub
   already emits `(EXPECTED)` lines the alternation still rejects.
2. **Mid-termination reclass** in `suites_failed_in`/`fail_suites`: a suite-shard job
   whose log yields ZERO `[FAIL]`/`[KILLED]` lines AND contains the runner-shutdown
   signature (`##[error]The runner has received a shutdown signal` or
   `##[error]The operation was canceled`) is UNSETTLED, not `no-fail-line`: the job's
   conclusion was recorded `failure` but no suite verdict exists. The job name joins the
   unit's unsettled set; `unit["unsettled_detail"][job]` records
   `{"signature":"mid-termination","in_flight":<Last-suite-started label or null>}` for
   receipts. A log carrying ANY `[FAIL]`/`[KILLED]` line keeps the normal path (the
   verdict wins — the shutdown happened on a later suite).
3. **Log-read annotation probe**: on `fail_suites` ReadError (log 404/5xx), read
   `check-runs/{job_id}/annotations?per_page=100` once; an annotation containing
   `hosted runner lost communication` reclasses the job as unsettled
   (`{"signature":"runner-comms-loss"}` in `unsettled_detail`); any other annotation set
   or a failed probe stays `log-read` → not-evaluable (conservative; the match is a
   live-verified production string, and a wording change degrades to today's behavior).
4. **Unsettled-leg clearing** in `classify` (:615-616): between the `ne` arm and the
   `not-evaluable unsettled-jobs` verdict, consult a per-leg identical-tree witness —
   `flake-cleared`/`identical-tree-green` iff EVERY unsettled leg name has a witness:
   - **(ejections) existing `cleared()`** — a LATER same-PR run whose changed-file
     (name, blob) set is identical and whose conclusion is `success` clears the unit
     wholesale (a green merge_group run ran every leg).
   - **(both) attempt witness** — any earlier attempt `1..run_attempt-1` of the same run
     whose jobs list the leg name with `conclusion == "success"` (identical tree, same
     run). New helper `run_leg_green(repo, run_id, names, attempt)` sharing the
     `failing_jobs` pagination/guards.
   - **(commits) same-sha sibling witness** — any other FULL_EVENTS run on the same sha
     (`ci_runs`' `runs`, already fetched; `cmd_collect` passes them into the closure)
     whose latest-attempt jobs list the leg name `success`. Same sha = identical tree.
   `cmd_collect`'s `lambda unit: False` (:705) becomes a real closure over the picked
   run's attempts + sibling runs; `cmd_ejections`' `cleared` closure gains the attempt
   arm. An unreadable witness read is not evidence — the unit stays not-evaluable.
   `unit["unsettled_legs"]` records the leg names for receipt splits.
   Order is preserved: a real `would_skip_hit` or `ne` still decides first — the new arm
   only fires where `unsettled-jobs` fired before.
5. **`failing_jobs`** gains a success-name return (or a sibling helper) for the witness
   reads — names `∈ SETTLED` are currently discarded; the witness needs `success` names.
   `unsettled` semantics unchanged (`conclusion not in SETTLED`).

### Phase 3 — tests (`plugins/soleur/test/ci-pr-affected-replay.test.sh`)

New fixtures + assertion rows (the stub is path-keyed; new paths get `fx`/`fx_err`):

- check-suites/check-runs join: queue-branch github-actions suite → run id missing from
  the listing → corroborated unit exists with `runs_via=check-runs-window` and the normal
  classification; a missing SUCCESS run joins `by_pr` and clears a would-skip unit;
  `push`-branch and third-party suites contribute nothing; a failed commit read →
  `corroboration-read:` synthetic unit.
- oracle: 2 `added_to_merge_queue` events vs 1 distinct `pr-N-*` branch → 1 synthetic
  `queue-oracle-shortfall` unit; removed-before-processing over-count documented; timeline
  `fx_err` → `queue-oracle-read:` unit; a branch naming no PR contributes nothing.
- `expected_units`: aggregate accepts `refused + shortfall + read_failures`; a stale
  shortfall (file holds more oracle units than the new count) refuses rc 2.
- fail-line: `[FAIL] apps/web-platform [repo-wide+component] (90ms)` extracts the full
  label → resolves against `skipped_suites`; the control-byte row stays not-evaluable.
- mid-termination: shutdown-signature log, no `[FAIL]` → job unsettled → cleared by a
  later same-PR green run (ejections) / by an earlier-attempt green (both) /
  same-sha sibling green (commits); with no witness → `unsettled-jobs`.
- comms-loss: `fx_err404` on the job log + annotation fixture naming the runner →
  unsettled; annotation absent/different → `log-read` not-evaluable.
- `mutate` rows for each new arm (drop the join filter, accept a `push` suite, skip the
  annotation probe, clear unsettled without a witness, keep `[A-Za-z0-9._/+-]+` charset);
  `DECLARED_TOTAL` and the three registered `--rows` ranges updated in the same commit.

### Phase 4 — runbook §4 + live corroboration smoke

- `ci-pr-affected-activation.md` §4: replace the recorded-residual bullet (:161-168) with
  the built semantics — the landed-sha arm, the queue-event count bound, `expected_units`,
  and the three documented residuals (pre-processing adds over-count; all-dropped unmerged
  PRs invisible; window-edge observed>added masking a partial drop — CTO AMEND).
- Live smoke (bounded): `ejections --out /var/tmp/s4-corrob-smoke --commits 20
  --base origin/main` — exercises the join + oracle against the real repo; receipts
  (command, rc, corroboration block, oracle counts, per-unit `runs_via`) committed under
  `knowledge-base/project/specs/feat-one-shot-12428-12444-ejections-corrob-classifier/receipts/`.
- **Out of scope (named):** the full §4 evidence re-run on a fresh 300-commit window and
  the go/no-go re-ruling are sequenced post-merge; their authorization is the budget
  owner's reservation (same as row 5 of the sibling decision file). `CI_PR_AFFECTED`,
  the activation lock, PR D (#10414): not touched.

## Files to Edit

- `scripts/ci-pr-affected-replay.py` — `FAIL_LINE`, `failing_jobs`, `fail_suites`,
  `suites_failed_in`, `classify`, `cmd_collect` (same-tree closure), `cmd_ejections`
  (corroboration + oracle + window json), `check_complete`, docstrings.
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — fixtures, rows, mutations,
  `DECLARED_TOTAL`.
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — §4
  residual bullet → built semantics.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12428-12444-ejections-corrob-classifier/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-12428-12444-ejections-corrob-classifier/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-12428-12444-ejections-corrob-classifier/session-state.md`
- `knowledge-base/project/specs/feat-one-shot-12428-12444-ejections-corrob-classifier/receipts/` (smoke outputs)

Explicitly NOT edited: `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`,
`.github/workflows/ci.yml`, any ruleset file, `FOLDED_JOBS`/`ALWAYS_RUN_JOBS` (already
cover the folded names at HEAD — the parity test keeps them pinned to ci.yml).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200) searched with `jq --arg path`
for `scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`,
`ci-pr-affected-activation.md` and `ci-pr-affected` on 2026-11-08: no open issue names any
of them.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — measurement-tool change inside `scripts/` plus one
test suite and a runbook bullet. Product tier: NONE (no user-facing surface in Files to
Edit/Create; the `components/**/*.tsx`/`app/**` mechanical override does not fire).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "pin every merge_group run whose head_sha is a landed first-parent commit via the existing non-search `corroborating_runs` read … iterated over the window's 300 commits" [#12428 ruling] | Phase 1 items 1–3 (bounded variant of the ruled read — same commit-keyed family, run reads confined to queue-branch check-suites) | mapped |
| 2 | "corroborate refused runs via a non-search expected-count oracle (per-PR `added_to_merge_queue`/`removed_from_merge_queue` issue-timeline events vs distinct `gh-readonly-queue/main/pr-N-*` head_branch names observed in the listing; a shortfall counts into worst_case per the existing conservative rule)" [#12428 ruling] | Phase 1 item 4 | mapped |
| 3 | "a principled clearing rule for unsettled cancelled legs … a route that reclassifies them, e.g. extending the `cleared`/same-tree path" [#12444] | Phase 2 item 4 | mapped |
| 4 | "fail-line extraction for the 5 `failed-job-without-fail-line` units" [#12444] | Phase 2 items 1–3 (three verified signatures) | mapped |
| 5 | "in ONE PR, two CTO-ruled deliverables that gate the next criterion-a §4 evidence re-run" [dispatch] | whole plan; §4 re-run named out-of-scope pending budget-owner authorization | mapped |
| 6 | "Persist every decision as a row of the `| Item | Class | Ruling |` table in …/decision-challenges.md" [dispatch] | spec artifact | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| landed-sha corroboration | "pin every merge_group run whose head_sha is a landed first-parent commit" | asked |
| queue-event oracle | "per-PR `added_to_merge_queue`/`removed_from_merge_queue` issue-timeline events vs distinct … head_branch names" | asked |
| `expected_units`/window-json schema | — | inferred — justification: `check_complete` must compare the unit file against SOMETHING once corroboration adds units; a new key keeps `refused`'s meaning intact and old manifests valid |
| `runs_via=check-runs-window` marker | — | inferred — justification: the receipts must show which units the index dropped (the evidence the fix exists to produce), mirroring the collect-side `runs_via` precedent |
| unsettled same-tree clearing | "extending the `cleared`/same-tree path" | asked — witness set (attempt, same-sha sibling, later-PR run) is the rule's instantiation per population |
| FAIL_LINE charset widening | "fail-line extraction" | asked — one of the three verified signatures is exactly a label the current charset can't capture |
| mid-termination → unsettled reclass | "fail-line extraction" + "a principled clearing rule" | inferred — justification: a `failure`-concluded job with no verdict and a runner-shutdown signature IS an unsettled leg; routing it through the new clearing rule is the principled disposition, and it resolves 2 of the 5 units |
| annotation probe on log-read | "fail-line extraction" | inferred — justification: the two 404-log jobs' annotations carry the runner-comms-loss signature (verified live); without the probe those 2 units stay irreducibly not-evaluable |
| runbook §4 update | "whatever code/doc fix the cause implies" pattern from the sibling plan | asked — the residual bullet becomes false the day this lands |
| spec-dir artifacts, smoke receipts | — | inferred — the one-shot pipeline's artifact contract |
| `ejections-corroboration` reuse of `check-suites` join | — | inferred — justification: the ruled "bounded run reads" sizing is unreachable via verbatim `corroborating_runs` (measured ~12k calls/window); the join is the same non-search commit-keyed family bounded to ~4–5 pages/commit |

### Split Assessment

- Subsystems touched: 3 — `scripts`, `plugins/soleur`, `knowledge-base`
- Planned files: 3 edits, ~5 creates | Estimated changed lines: ~450 (SUT ~200, suite ~180, docs ~30, receipts ~40)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the dispatch mandates "in ONE PR" and the two deliverables
  share the unit pipeline, the window manifest and the same suite.

## Guard Contract

### Guard 1 — ejections window-listing corroboration (#12428)

**Property.** Every merge_group ci.yml run created inside the window whose head_sha is a
landed first-parent commit is present in the ejection population — proven by commit-keyed
reads, not the search index; and the refused population is count-bounded below by per-PR
`added_to_merge_queue` events, each shortfall yielding a worst_case unit. A dropped run
can never read as a complete clean population.

**Assembly.** `cmd_ejections` is the sole producer of the ejection population and
`units-ejections.jsonl`; `check_complete` is the chokepoint that enforces population ==
`expected_units`. The corroboration enumerates every window commit's queue-branch
github-actions check-suites — the join is what makes "every merge_group run on a landed
sha" a census rather than a listing. The oracle quantifies over every distinct
`pr-N-*` branch in the union.

**Mutation matrix.**

| Edit (design-level) | Expected | Suite driver |
|---|---|---|
| Skip the check-suites→check-runs join (trust the listing as authoritative) | index-dropped-run fixture → unit absent, `expected_units` under-counts | corroborated-missing fixture row |
| Filter suites on head_sha instead of `gh-readonly-queue/` head_branch | a `push`-event suite's run ids join the union → population polluted | wrong-branch suite fixture row |
| Swallow a failed commit read (no synthetic unit) | `fx_err` fixture → `corroboration-read:` unit missing → `expected_units` drifts | read-failure fixture row |
| Oracle compares run ids (not distinct branch names) to adds | a re-run pair on one branch counts as 2 → false shortfall / wrong count | re-run-on-one-branch fixture row |
| Shortfall recorded but excluded from `expected_units` | `aggregate` passes with fewer units than the bound requires | expected_units aggregate row |
| Corroboration reports "0 checked" and exits clean (vacuous dispatch) | window commits enumerate 0 → suite row asserting `corroborated.commits` equals the fixture's commit count reds | dispatch census row |

Harness rows: (a) delete a fixture's `check-suites` arm → the corroboration row must go
RED (a suite missing the new read stubs catches it via `STUB-MISS`); (b) must-PASS
non-canonical input — a merge_group run on a queue branch with conclusion `success`
correctly joins `by_pr` and never becomes a refused unit.

**Anchor.** `expected_units` is recomputed every invocation from live reads — a stored
floor can't go stale; the window json is evidence, not an authority.

### Guard 2 — unsettled-leg identical-tree clearing (#12444)

**Property.** A cancelled/never-settled leg becomes `flake-cleared` only when the
identical tree demonstrably ran that leg to `success` — a later same-PR identical-content
run (ejections), an earlier attempt of the same run, or a sibling run on the same sha
(commits); with no witness the unit stays `not-evaluable`. Clearing can never manufacture
a verdict the tree didn't produce.

**Assembly.** `classify` is the sole verdict producer; the unsettled arm is the one place
the new consult fires; the witness helpers share `failing_jobs`' truncation guards.

**Mutation matrix.**

| Edit (design-level) | Expected | Suite driver |
|---|---|---|
| Clear on ANY unsettled leg without requiring every leg witnessed | two-leg fixture with only one witnessed → unit must stay not-evaluable | partial-witness fixture row |
| Accept an EARLIER same-PR run or different-content run as the ejection witness | `cleared` semantics violated → red (already pinned) + new unsettled variant | earlier-success/different-blob rows |
| Count a `skipped`/`failure` sibling leg as the success witness | leg not green → not-evaluable | non-success sibling fixture row |
| Move the unsettled consult before the `would_skip_hit` arm | a real would-skip failure clears via a cancelled sibling → escape hidden | ordering mutation row |
| Mid-termination signature accepted when a `[FAIL]` line IS present | the verdict line must win → not-evaluable/no-fail-line path | fail-line-plus-shutdown row |
| Annotation probe accepts an unrelated annotation as comms-loss | wrong annotation → stays `log-read` | annotation-shape row |
| FAIL_LINE widened past printable ASCII | control-byte label row reds (already pinned) | charset mutation row |

Harness rows: (a) a witness fixture whose jobs read is `fx_err`'d must fail the unit
safely (no clearing on an unread witness); (b) must-PASS non-canonical — a commit unit
whose cancelled leg is green in a sibling PUSH run clears correctly.

**Anchor.** None — witness reads are live evidence; nothing stored is compared.

## Observability

The surface is an operator-run evidence tool: its observability IS its exit codes, its
stdout ledger and the `ejections-window.json` manifest it writes — there is no daemon to
lose. Every new read path reports through the same `ReadError` fail-loud seam.

```yaml
liveness_signal:
  what: "rc 0 + `replay ejections: wrote N units` + `corroborated`/`queue_oracle` blocks in ejections-window.json"
  cadence: per invocation (operator-run, §4 runbook)
  alert_target: operator reading the receipt
  configured_in: scripts/ci-pr-affected-replay.py (cmd_ejections print lines)
error_reporting:
  destination: stderr + ReadError → not-evaluable synthetic unit
  fail_loud: yes — a failed read is a counted unit, never a silent pass
failure_modes:
  - {mode: "index-dropped merge_group run", detection: "corroborated.missing_ids non-empty", alert_route: "ejections-window.json + expected_units census"}
  - {mode: "truncated/uncounted corroboration read", detection: "total_count != seen ReadError → corroboration-read: unit", alert_route: "unit in units-ejections.jsonl"}
  - {mode: "timeline oracle read failure", detection: "queue_oracle.read_failures > 0", alert_route: "queue-oracle-read: unit + window json"}
  - {mode: "population short/stale", detection: "units != expected_units", alert_route: "aggregate rc 2"}
logs:
  where: invocation stdout/stderr; units JSONL + ejections-window.json under --out; committed receipts under the spec dir
  retention: repo-committed receipts
discoverability_test:
  command: "python3 -I scripts/ci-pr-affected-replay.py verdict --a pass --b pass --c pass --d pass"
  expected_output: "computed=GO"
```

## Architecture Decision (ADR/C4)

Detection review: no ownership/tenancy boundary move, no new substrate, no new trust
boundary, no ADR reversal. The corroboration reuses the non-search commit-keyed pattern
`corroborating_runs` already established (ADR-276 amendment chain); the classifier routes
add verdict classes inside an existing decision tree.

### C4 views — no impact (enumeration per the completeness mandate)

Read `model.c4` (1111 lines), `views.c4`, `spec.c4` this session. For this feature:
(a) **external human actors** — none new: the operator already runs the tool; no new
publisher to `publicReader`; (b) **external systems/vendors** — GitHub Actions REST API,
already modeled on `engine -> github "Git operations and CI"`; the new endpoints
(check-suites, timeline, annotations) are more reads on that same edge; (c) **containers /
data stores** — none new: writes stay under `--out` and the spec-dir receipts;
(d) **actor↔surface access relationships** — unchanged: read-only `gh api` reads, same
credentials, same trust level. No `.c4` edit required.

## Acceptance Criteria

- AC1: `cmd_ejections` enumerates the window's `--commits`/`--base` first-parent commits
  unconditionally and, per commit, resolves merge_group ci.yml run ids via commit-keyed
  check-suites (github-actions + `gh-readonly-queue/` head_branch, `total_count == seen`
  guarded) joined to check-runs; every such run absent from the listing and created
  in-window joins the union — a corroborated SUCCESS run feeds `by_pr`/histogram and
  `cleared()` only (never a unit), while a corroborated non-success run is classified
  through the normal pipeline as a unit with `runs_via=check-runs-window`.
- AC2: The per-PR oracle counts `added_to_merge_queue` timeline events in-window vs
  distinct `pr-N-*` head_branch names in the union; each shortfall and each failed
  corroboration/oracle read yields exactly one `not-evaluable` synthetic unit, and
  `ejections-window.json` records `corroborated`, `queue_oracle` and `expected_units`.
- AC3: `aggregate` (`check_complete`) compares the ejection-unit count to
  `expected_units` (falling back to `refused` on old-shape manifests); a stale or short
  population refuses rc 2.
- AC4: `classify` clears an unsettled-leg unit to `flake-cleared`/`identical-tree-green`
  iff every unsettled leg has an identical-tree success witness (later same-PR
  identical-content run, earlier same-run attempt, or same-sha sibling run for commits);
  `unit["unsettled_legs"]`/`unsettled_detail` record the legs and signatures.
- AC5: `FAIL_LINE` captures printable-ASCII labels including spaces/brackets; control-byte
  labels still don't match; `[FAIL] apps/web-platform [repo-wide+component]` resolves.
- AC6: A suite-shard job log with a runner-shutdown signature and no `[FAIL]`/`[KILLED]`
  line classes the job unsettled (`mid-termination`); a log-read failure whose
  annotations carry the hosted-runner-comms-loss string classes the job unsettled
  (`runner-comms-loss`); anything else stays `log-read`/`no-fail-line`.
- AC7: `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` exits 0 including all new
  fixture rows and mutation kills; `DECLARED_TOTAL` and the three `--rows` ranges updated
  in the same commit.
- AC8: Runbook §4 names the built corroboration semantics and the two documented
  residuals; the stale recorded-residual bullet is replaced.
- AC9: Live smoke `ejections --commits 20 --base origin/main` completes rc 0 with the
  corroboration/oracle blocks populated; receipts committed under the spec dir.
- AC10: `python3 -I scripts/ci-pr-affected-replay.py ratchet` exits 0 on this branch
  (the audit must see no new gap pairs from new literal strings in the SUT).

## Test Scenarios

- `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` — full suite green (mutations
  included), all three registered `--rows` ranges.
- `python3 -I scripts/ci-pr-affected-replay.py ratchet` — exit 0.
- Live smoke `ejections --commits 20 --base origin/main --out /var/tmp/s4-corrob-smoke` —
  rc 0, `corroborated.commits=20`, oracle counts printed; `aggregate` rc 0.
- Fixture-driven (no live cost): a window whose listing drops one refused and one success
  merge_group run → refused unit classified via `check-runs-window`, success joins
  `by_pr` clearing; a PR with adds > branches → shortfall units; timeline `fx_err` →
  read-failure unit.

## Risks & Mitigations

- **Risk:** corroboration multiplies `gh` calls (~4–5 pages/commit ≈ 1,300–1,500 calls +
  ~150 timeline reads per window). **Mitigation:** the join bounds run reads to
  queue-branch suites (measured: naive reuse ≈ 12k); reads paginate through the existing
  retried `gh_pages`; each failure degrades to a counted synthetic unit, never a wrong
  verdict — and the count surfaces in `ejections-window.json`.
- **Risk:** the oracle's count bound over-counts (a queue entry removed before its run
  spawned; a boundary add whose run lands post-window). **Mitigation:** that IS the
  conservative rule — the ruling's own dissent accepts the bound; documented residuals go
  in the docstring + runbook. If a window shows a large spurious shortfall the receipt
  shows it (it can't hide).
- **Risk:** check-suite `head_branch` or annotation wording drifts upstream.
  **Mitigation:** the queue filter degrades to zero matched suites → zero expected runs →
  corroboration finds nothing to add (the pre-fix blind spot, never a false alarm);
  annotation wording miss → `log-read` not-evaluable, same as today. Both directions are
  safe; the suite stubs pin the current shapes.
- **Risk:** `cleared`/witness reads on cancelled-heavy windows add jobs calls.
  **Mitigation:** witness reads fire only for units entering the unsettled arm (~24 of 382
  in the measured window), bounded by attempts/siblings per run.

## Sharp Edges

- Do NOT trust figures quoted from issue comments — every signature above was re-derived
  live this session (job logs, check-suites, timeline, annotations); the work phase
  re-verifies the 5 units' dispositions against fresh reads, not this plan's enumeration.
- The stub `gh` collapses `created=` windows — oracle/timeline fixtures key on the full
  request path; `per_page=100` and pagination must appear in fixtures exactly as the SUT
  requests them or `STUB-MISS` fires.
- `unit_field` selects on `.sha` — oracle units' synthetic sha-field
  (`queue-oracle:pr-<N>-<i>`) must be selected with the literal key, not a hex prefix.
- `read_done` resume is keyed `(kind, sha)`: corroborated runs share head_shas with
  nothing else (a queue sha is unique to one run) — a collision in `done` would mean the
  run was seen under two identities, which is exactly what must not happen.
- `attempts_failed`/attempt reads use `attempts/{N}/jobs` — the attempt witness reads
  EARLIER attempts (`1..run_attempt-1`), never the latest attempt's own listing (that IS
  `filter=latest`, already read).
- The `test` aggregate job is in `ALWAYS_RUN_JOBS` — its presence in `failing` notes
  `always-run-job` and never makes a unit not-evaluable by itself.
- The widened `[ -~]+?` charset admits any printable label — including a noise line like
  `[FAIL] freeform words (90ms)`; a spurious capture is harmless because extraction only
  matters through the `skipped_suites` membership intersection, but the suite rows must
  prove the control-byte row and the `(EXPECTED)` lines still do not match.
- Deepen-pass compat check (Phase 4.45): `refused` semantics are preserved — new key is
  additive (`expected_units`), `mkmeta` fixtures and old manifests stay valid via the
  fallback; the unsettled consult never moves before `would_skip_hit`/`ne`, so no
  existing verdict class changes meaning. A commit landing outside the queue
  (direct push / `--admin`) legitimately has zero queue-branch suites — a recorded zero,
  not a read failure (ADR-276's own keying measurement: such shas exist).
- A `flake-cleared` unit counts toward neither attributable nor worst_case — the clearing
  route is what moves the bound; do not confuse "fewer not-evaluable" with "cheaper
  evidence" when writing the receipt.
