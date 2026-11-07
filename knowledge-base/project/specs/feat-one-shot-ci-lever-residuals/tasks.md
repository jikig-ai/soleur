# Tasks — feat-one-shot-ci-lever-residuals

Plan: `knowledge-base/project/plans/2026-11-07-chore-ci-lever-residuals-plan.md`
Issues: #12016 (Closes), #9323 (Ref — verdict-conditional close), #9729 (Ref — stays open)
PR: #12354 (draft)

## Phase 0 — Recon kickoff (background the long poles first)

- 0.1 `git fetch origin main`; start chunked replay in background:
  `python3 -I scripts/ci-pr-affected-replay.py collect --out /var/tmp/s4-replay --commits 300 --base origin/main`
  (resumable; `--chunk I/K` to parallelize; ~2.5 h serial per runbook §4).
- 0.2 Pinned fresh audit on a detached `origin/main` worktree:
  `git worktree add --detach /var/tmp/s4-audit origin/main` then
  `python3 -I scripts/ci-pr-affected-replay.py audit --root /var/tmp/s4-audit --all-refs > /var/tmp/s4-audit.out`.
  Expected: `gap_suites=0 unaudited=0 stale=0`. Any `stale`/gap row → drain in-PR
  (declare edge or accept row, re-run to fixpoint) before the re-ruling.
- 0.3 `python3 -I scripts/ci-pr-affected-replay.py ejections --out /var/tmp/s4-replay --commits 300 --base origin/main`
  after collect completes (~25 min).

## Phase 1 — #12016 price refresh + drift arm (Guard Contract first)

- 1.1 RED: add fixture rows to `plugins/soleur/test/regenerate-shard-manifest.test.sh`
  for `PRICE_DRIFT_ROW` (over bound both directions, under bound, timed<3 suppression,
  second-member) — confirm they fail before implementing.
- 1.2 Implement in `scripts/regenerate-shard-manifest.py` `drift_report_group()`:
  emit `PRICE_DRIFT_ROW <group> <label> <committed_ms> <fresh_ms> <timed>/<sampled>`
  for `src=measured` labels where `timed>=3`, `max(f,c)/min(f,c) >= 4.0`,
  `|f-c| >= 120000`; update the emission-contract docstring.
- 1.3 RED→GREEN same loop for `scripts/watch-shard-balance-11564.test.sh`
  (flag parse, sentinel identity strips magnitudes, second-member, must-PASS rows).
- 1.4 Implement in `scripts/watch-shard-balance-11564.sh` step (4):
  `PRICE_DRIFT_ROW *` → `price-drift` finding.
- 1.5 Refresh `scripts/suite-durations.tsv` exactly two rows:
  `scripts/test-all-group-affected` → 349500; `.claude/hooks/git-commit-secret-scan.test.sh` → 297100.
- 1.6 Run both suites green; run `lint-guard-contract.py` on the plan's Guard Contract.

## Phase 2 — #9323 re-measure

- 2.1 Add `PBG_UNBOUNDED=1` operator seam to `scripts/followthroughs/pr-battery-gate-saving-9323.sh`
  (:88 budget block + header note); `PBG_BUDGET_S` ≤300 validation unchanged.
- 2.2 Cover the seam in `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh`.
- 2.3 Local run (background, no deadline):
  `GH_TOKEN="$(gh auth token)" PBG_UNBOUNDED=1 bash scripts/followthroughs/pr-battery-gate-saving-9323.sh`.
- 2.4 Branch on the verdict output:
  - PASS → `gh issue comment 9323` with the verbatim output; `gh issue close 9323`;
    retire per the probe's RETIREMENT block (delete `.sh` + `.test.sh`,
    `run_suite` line at `scripts/test-all.sh:7091`, `suite-shard-legs.tsv:438`,
    `suite-durations.tsv:436`, ADR-262 Consequences :132 mention).
  - FAIL → comment the output on #9323; leave open; record the widen-vs-revert
    decision on the issue (operator scope call).
  - NOT YET → comment the attempt numbers on #9323; file the starvation fix
    (parallel artifact reads / resumable progress) as a follow-up issue.

## Phase 3 — #9729 go/no-go re-ruling (non-activating)

- 3.1 `aggregate` the replay:
  `python3 -I scripts/ci-pr-affected-replay.py aggregate /var/tmp/s4-replay --expect-commits 300 --out /var/tmp/s4-replay/replay-summary.txt`;
  `cp-upper` for the worst-case bound → criterion (a).
- 3.2 Criterion (b): Phase-0.2 audit exit code.
- 3.3 Criterion (c) in billed job-minutes per pull_request run:
  - baseline: `bash scripts/ci-demand-census.sh --start <t0> --end <t1> --workflow ci.yml --summary`
    over a recent closed window; bar = 20% of measured baseline.
  - saving: sample recent completed pull_request runs; per PR take the changed-file
    list (`gh api repos/jikig-ai/soleur/pulls/<n>/files`), run
    `env -u CI -u SOLEUR_TEST_FORCE_ALL bash scripts/test-all.sh --print-selection --paths=<list>`,
    price the would-be-skipped set via `suite-durations{,-heavy}.tsv`, subtract
    ~1 billed min selection + ~3.4 billed min advisory-ratchet overhead.
  - timing leg: cite PR C canary (cold 146 s / warm 13 s, ≤120 s bar).
  - write method + data to `specs/<branch>/receipts/criterion-c.md`.
- 3.4 Criterion (d): `bash scripts/test-affected-kb-consumers.test.sh` +
  dropped-consumer census → `receipts/reader-audit.md`.
- 3.5 `python3 scripts/ci-pr-affected-replay.py verdict --a <s> --b <s> --c <s> --d <s>`;
  read `computed=` (exit code carries no verdict).
- 3.6 CTO confirmation spawn if available; else record `pending - assumed` (already in
  `decision-challenges.md`).
- 3.7 Commit `receipts/go-no-go.md` ending in
  `SOLEUR_PR_AFFECTED_VERDICT verdict=<v> ruled=<…> date=<YYYY-MM-DD>` + supporting receipts.
- 3.8 Append `## Amendment <date> (S4 go/no-go re-ruling, #9729)` to ADR-276
  (verdict, four criterion figures, `Go/no-go receipt:` line, non-activation statement)
  + a dated `### Stage status` line.
- 3.9 Update runbook `ci-pr-affected-activation.md` §2 "Where things stand".
- 3.10 `gh issue comment 9729` — verdict, criteria table, remaining blockers
  (PR3b #10859/#12329, budget-owner go-ahead, admin-side control, stage-2 build).

## Phase 4 — Consolidate

- 4.1 Verify nothing activated: `git diff --name-only` excludes `ci.yml`,
  `required-checks.txt`, `ci-pr-selection.sh`, any ruleset/infra file.
- 4.2 Fill PR #12354 body (via ship): `Closes #12016`, `Ref #9323`, `Ref #9729`.
- 4.3 Resolve/update `decision-challenges.md` rows where work-time evidence lands.
