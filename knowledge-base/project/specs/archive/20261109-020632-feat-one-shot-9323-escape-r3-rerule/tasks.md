# Tasks — feat-one-shot-9323-escape-r3-rerule

Derived from `knowledge-base/project/plans/2026-11-08-feat-9323-escape-triage-r3-rerule-plan.md`.
One PR carries both items. Stage 4 stays NON-ACTIVATED throughout (AC8).

## Phase 0 — Coordination snapshot (blocking, cheap)

- [x] 0.1 `gh run view 42483264409 --json status,conclusion` and `gh run view 42483264452 --json status,conclusion`; record terminal states for the #9323 comment (plan-time readings: `success` / `in_progress`).
- [x] 0.2 Inventory `/var/tmp/s4-r3-20261108/` and the `s4-r3-replay` worktree processes. If the collect is alive: adopt it as the R3 evidence base (record in `receipts/r3/adoption-note.md`). If dead/stale: rerun `collect` against the same `--out` (resumable) or a fresh `OUT=/var/tmp/s4-r3-<date>`. Never run two concurrent collects.

## Phase 1 — Item 1: #9323 escape triage

- [x] 1.1 Ruling already taken at plan time (Arm A — fix the probe's escape classification; `decision-challenges.md` row 1, sequential-fallback CTO execution, disclosed). Verify the row survives the parent's batched technical-ruling gate unchanged; if the gate re-adjudicates and changes the arm, implement the new ruling instead (AC1).
- [x] 1.2 Confirm `decision-challenges.md` carries the `Ruled by CTO agent, 2026-11-08:` row (AC1).
- [x] 1.3 Implement the ruled arm (AC2):
  - Arm A: `_pbg_w_esc` in `scripts/followthroughs/pr-battery-gate-saving-9323.sh` — on red push-run conclusions read the run's jobs via the existing `api()` primitive; escape iff ≥1 failed job matches `test-scripts*` (:281 prefix); all-failed-outside-gated-set → unrelated bucket (reported, never counted); jobs-read failure → `pending`, never `ok`; update header + `need_min` comments.
  - Arm B: widen `scripts/lib/test-relevance-paths.sh` per ADR-262 R1.
  - Arm C: revert the PR-9324 gate machinery.
- [x] 1.4 (Arm A) Extend `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` with Guard Contract matrix rows 1-6 (AC3).
- [x] 1.5 `GH_TOKEN=… PBG_UNBOUNDED=1 bash scripts/followthroughs/pr-battery-gate-saving-9323.sh`; post the corrected verdict comment on #9323 quoting rerun terminal states, the disposition, and the honest output verbatim (AC4). State plainly whether the corrected classifier makes PASS reachable and a sweeper close on PASS warranted.
- [x] 1.6 Sweep the probe RETIREMENT block (:80-82) for instructions the change falsifies.

## Phase 2 — Item 2: #9729 R3 re-ruling

- [x] 2.1 `python3 -I scripts/ci-pr-affected-replay.py collect --out <OUT> --commits 300 --base origin/main` (adopted or fresh per 0.2; `--chunk I/K` if parallelism needed).
- [x] 2.2 `python3 -I scripts/ci-pr-affected-replay.py ejections --out <OUT> --commits 300 --base origin/main`.
- [x] 2.3 `python3 -I scripts/ci-pr-affected-replay.py aggregate <OUT> --expect-commits 300 --out <OUT>/replay-summary.txt` + `cp-upper` reads.
- [x] 2.4 Criterion b: detached worktree at `origin/main`; `audit --root /var/tmp/s4-audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv` + the bare no-accept run; remove the worktree.
- [x] 2.5 Criterion c: `scripts/ci-demand-census.sh` over two adjacent closed 12h windows → fresh baseline; 20-PR sampled saving per the `receipts/criterion-c.md` recipe; canary ≤120 s.
- [x] 2.6 Criterion d: `bash scripts/test-affected-kb-consumers.test.sh` + reader census → `reader-audit.md`.
- [x] 2.7 `verdict --a <s> --b <s> --c <s> --d <s>` → read `computed=` (exit code carries no verdict).
- [x] 2.8 Commit all 13 receipts under `knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/r3/` incl. `go-no-go.md` ending `SOLEUR_PR_AFFECTED_VERDICT verdict=<V> ruled=confirmed date=2026-11-08` (AC5).
- [x] 2.9 ADR-276: `## Amendment 2026-11-08 (S4 go/no-go third re-ruling, #9729)` + new LAST `Go/no-go receipt:` line → `receipts/r3/go-no-go.md` (AC7).
- [x] 2.10 Runbook `ci-pr-affected-activation.md` §2: dated third-ruling status line (AC10).
- [x] 2.11 `bash scripts/ci-pr-affected-preactivation.sh` from a detached `origin/main` checkout → `receipts/r3/preactivation.out` (AC12).
- [x] 2.12 Verdict comment on #9729: `computed=<V> reason=…`, criterion table, non-activation statement, receipts path (AC6).

## Phase 3 — Ship

- [x] 3.1 Non-activation sweep (AC8): lock line present; `vars.CI_PR_AFFECTED` at ci.yml:399; `git diff --name-only origin/main...HEAD` shows no activation-surface file.
- [x] 3.2 PR body: `Ref #9323` / `Ref #9729` — no `Closes`/`Fixes`/`Resolves` (AC9); restate the term-1 allowlist verification (AC11).
- [x] 3.3 Commit `decision-challenges.md` amendments if later phases surface new rows.

## Acceptance mapping

Each task maps to plan ACs: 1.1-1.2 → AC1; 1.3 → AC2; 1.4 → AC3; 1.5 → AC4; 2.8 → AC5; 2.12 → AC6; 2.9 → AC7; 3.1 → AC8; 3.2 → AC9/AC11; 2.10 → AC10; 2.11 → AC12.
