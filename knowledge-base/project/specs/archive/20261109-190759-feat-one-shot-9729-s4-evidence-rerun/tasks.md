# Tasks — feat-one-shot-9729-s4-evidence-rerun

Plan: `knowledge-base/project/plans/2026-11-09-feat-s4-affected-ci-evidence-rerun-plan.md`
Issues: #9729 (Ref — stays open, no `Closes`), #10448 (Ref), #12456 (optional context)
PR: #12477 (draft)
Epic: S4 affected-only CI, fourth go/no-go re-ruling (ADR-276 amendment item 5; budget-owner
authorization given in-session 2026-11-09). Non-activating throughout.

## Phase 0 — Pin the window, verify entry conditions, launch long poles (~20 min active)

+ 0.1 `git fetch origin main`; record `BASE=$(git rev-parse origin/main)` + UTC timestamp into
  `receipts/commands.txt`. One fetch for the whole run — do NOT re-fetch mid-run.
+ 0.2 Writer exclusivity: `pgrep -af 'ci-pr-affected-replay'` must be empty;
  `test ! -e /var/tmp/s4-rerun-9729-r4`. Abort/relocate on a live writer or orphaned dir
  (adoption needs the runbook's two proofs; a fresh dir needs none).
+ 0.3 Smoke the gh seam: `python3 -I scripts/ci-pr-affected-replay.py collect --out /var/tmp/s4-smoke --commits 2 --chunk 1/1 --base origin/main` (expect rc 0, both units classified,
  `runs_via` set); `rm -rf /var/tmp/s4-smoke`.
+ 0.4 Entry condition 2 re-assert: `grep affected-index-ratchet scripts/required-checks.txt`.
+ 0.5 Pinned audit (entry condition 1):
  `git worktree add --detach /var/tmp/s4-audit origin/main`, then
  `python3 -I scripts/ci-pr-affected-replay.py audit --root /var/tmp/s4-audit --all-refs --accept /var/tmp/s4-audit/scripts/ci-pr-affected-audit.accept.tsv > /var/tmp/s4-audit.out` (~3 min),
  plus the bare spelling `audit --root /var/tmp/s4-audit --all-refs > /var/tmp/s4-audit-bare.out`.
  Expect `unaudited=0 gap_suites=0 stale=0`, exit 0. Non-zero → record rows verbatim, criterion (b)
  is `fail` — never drain inside this PR.
+ 0.6 `cd /var/tmp/s4-audit && bash <worktree>/scripts/ci-pr-affected-preactivation.sh > /var/tmp/preactivation.out`, then `git worktree remove --force /var/tmp/s4-audit`.
+ 0.7 Launch four collect legs in background:
  `python3 -I scripts/ci-pr-affected-replay.py collect --out /var/tmp/s4-rerun-9729-r4 --commits 300 --chunk I/4 --base origin/main` for I=1..4 (~40 min wall; per-unit resumable).
+ 0.8 When all four legs exit: `python3 -I scripts/ci-pr-affected-replay.py ejections --out /var/tmp/s4-rerun-9729-r4 --commits 300 --base origin/main` (~25 min).

## Phase 1 — Aggregate + criterion (a)

+ 1.1 `python3 -I scripts/ci-pr-affected-replay.py aggregate /var/tmp/s4-rerun-9729-r4 --expect-commits 300 --out /var/tmp/s4-rerun-9729-r4/replay-summary.txt`. rc 2 = integrity refusal:
  diagnose, never hand-edit JSONL.
+ 1.2 `python3 -I scripts/ci-pr-affected-replay.py cp-upper <worst-case numerator> <N>`.
+ 1.3 Extract classes/routes/runs_via histogram → `histograms.txt`, `replay-commits.tsv`.
  Record which corroboration arms fired (`check-runs`, `corroborated-no-run`,
  `check-runs-window`, `queue-oracle:*` synthetic units) and the not-evaluable composition vs R3.

## Phase 2 — Criterion (b)

+ 2.1 Status = Phase-0 audit exit code; record the `SOLEUR_PR_AFFECTED_AUDIT` line +
  `refs`/`files_read`.

## Phase 3 — Criterion (c): fresh baseline + saving sample

+ 3.1 `bash scripts/ci-demand-census.sh --start <t0> --end <t1> --workflow ci.yml --summary` over
  two adjacent closed 12 h windows ending before work starts → `census-w1.txt`, `census-w2.txt`;
  combine per the script's LONGER SPANS recipe → baseline M; bar = 0.20·M. Extract STEM rows for
  the gated legs' run share + the `affected-index-ratchet`/`pr-selection` debits.
+ 3.2 Sample: 20 most recent completed `pull_request` `success` runs; resolve PRs (run
  `pull_requests`, else `gh pr list --head <branch> --state all -L 1`); changed files via
  `gh api repos/jikig-ai/soleur/pulls/<n>/files`; selection via
  `env -u CI -u SOLEUR_TEST_FORCE_ALL bash scripts/test-all.sh --print-selection --paths=<list>`;
  price `sel=0` non-`always_on` rows via `suite-durations{,-heavy}.tsv`.
+ 3.3 Both readings (per-full-run net of ~1 + ~3.4 min debits; population-weighted by leg share) →
  status `pass`/`fail`/`within-10%`. Timing leg: cite the PR C `sel-s-canary.md` unchanged.
+ 3.4 Write `receipts/criterion-c.md` (method, raw rows, both readings, stated limits).

## Phase 4 — Criterion (d): reader audit

+ 4.1 `bash scripts/test-affected-kb-consumers.test.sh` (expect exit 0); KB-mention census;
  `test-affected-kb-consumers.baseline.txt` row counts; `apps/web-platform [repo-wide+component]`
  `edge:consumed` check on a README-only diff → `receipts/reader-audit.md`.

## Phase 5 — Verdict, receipts, record

+ 5.1 `python3 -I scripts/ci-pr-affected-replay.py verdict --a <s> --b <s> --c <s> --d <s>` —
  read `computed=` on stdout; never `&&`-chain (exit 0 always).
+ 5.2 Commit `receipts/` (README.md, commands.txt, go-no-go.md ending in
  `SOLEUR_PR_AFFECTED_VERDICT verdict=<v> ruled=<confirmed|pending> date=2026-11-09`,
  replay-summary.txt, replay-commits.tsv, histograms.txt, ejections-window.json,
  index-audit{,-bare-noaccept}.out, index-audit.err, preactivation.out, criterion-c.md,
  census-w{1,2}.txt, reader-audit.md).
+ 5.3 Append `## Amendment 2026-11-09 (S4 go/no-go re-ruling, #9729)` to ADR-276 + dated
  `### Stage status` line + `Go/no-go receipt:` line + non-activation paragraph. (Inferred item.)
+ 5.4 Append one dated bullet under runbook §2 (window, counts, computed verdict, deciding
  criterion, receipt path, `missing=` line).
+ 5.5 `gh issue comment 9729` — verdict, criteria table, remaining blockers. (Inferred item.)
+ 5.6 Non-activation invariants: `git diff --name-only origin/main...HEAD` shows only
  `knowledge-base/`; `readonly PR_AFFECTED_LOCKED=1` still present; `CI_PR_AFFECTED` variable
  still 404; no `Closes` token in the PR.
