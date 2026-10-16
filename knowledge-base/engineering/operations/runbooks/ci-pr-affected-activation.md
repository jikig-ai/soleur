---
category: ci
tags: [ci, affected-only, adr-276, s4, go-no-go, replay, activation]
date: 2026-10-16
---

# S4 affected-only PR runs: re-attempt and pre-activation runbook

**Issues:** #9729 (stage 4, stays open), #10448 (the decision the NO-GO left), #10414 (PR D, per-suite selection)
**Decision record:** ADR-276, `## Amendment 2026-10-16 (S4 PR C, #9729)`
**Tooling:** `scripts/ci-pr-affected-replay.py` (evidence), `scripts/ci-pr-affected-preactivation.sh` (read-only gate)

This runbook is for whoever re-attempts S4 after the 2026-10-16 NO-GO, or asks "may `CI_PR_AFFECTED` be turned on?".
Everything here is READ-ONLY. **Nothing in this runbook turns the lever on**, and no step here may be extended to do
so: activation is a separate, explicitly authorized step (ADR-276 S4) that needs a go-ahead naming the command.

## Where things stand

The lever (PR B) is shipped dark and locked and costs 0 billed minutes while `CI_PR_AFFECTED` is unset. PR C measured the
proposed per-suite rule and ruled **NO-GO** on index completeness (criterion b): about 190 of 630 suites name a tracked
path the index does not declare for them. The receipts are in the PR C spec directory (`receipts/`, archived at ship under
`specs/archive/<timestamp>-feat-one-shot-9729-ci-pr-c-affected-only/receipts/`, leaf names kept).

## 1. Entry condition for a re-attempt (CTO ruling, ADR-276 amendment item 5)

All of these, in this order:

1. The audit reports `gap_suites=0` and `unaudited=0`, or every remaining row carries a human-written `false-positive:`
   reason in the census style (the one directory suite `plugins/soleur` is `unaudited` until the audit reads it).
2. A ratchet that fails on any suite naming an undeclared tracked path is a **required** CI check.
3. The escape replay, the saving and the reader audit are re-run on a fresh window (below) and the go/no-go is re-ruled.

## 2. Re-run the evidence

Run from a checkout of the commit under test. Every command is read-only; the replay writes only under `--out`.

```bash
# a pinned tree: the audit reads the working tree, so audit a detached checkout of origin/main, never a dirty branch
git fetch origin main
git worktree add --detach /var/tmp/s4-audit origin/main
python3 -I scripts/ci-pr-affected-replay.py audit --root /var/tmp/s4-audit
git worktree remove --force /var/tmp/s4-audit
```

`audit` prints `gap` and `unaudited` lines and `SOLEUR_PR_AFFECTED_AUDIT suites=… always_on=… audited=… unaudited=…
gap_suites=… gap_refs=…`. It exits 0 only when `gap_suites=0` AND `unaudited=0`; `gap_suites=0` beside `unaudited>0` is not
a clean audit (a suite the audit never read is not a suite with no gaps). `always_on` suites run on every diff and are exempt.

```bash
OUT=/var/tmp/s4-replay
# the last 300 first-parent commits of main (resumable; --chunk I/K splits it; --reclassify re-reads every non-clean unit)
python3 -I scripts/ci-pr-affected-replay.py collect --out "$OUT" --commits 300 --base origin/main
# every failed merge_group run in the same window (--since/--until are UTC; the default is the commit window)
python3 -I scripts/ci-pr-affected-replay.py ejections --out "$OUT" --commits 300 --base origin/main
# the receipt text: rule hash, classes, routes, worst-case bound, saving, net saving against the 20% bar
python3 -I scripts/ci-pr-affected-replay.py aggregate "$OUT" --out "$OUT/replay-summary.txt"
# the one-sided 95% bound for K events in N
python3 -I scripts/ci-pr-affected-replay.py cp-upper 0 300
# GO iff every criterion passes: pass|fail|within-10%|unmeasured (the band applies to a and c only)
python3 -I scripts/ci-pr-affected-replay.py verdict --a pass --b fail --c unmeasured --d pass
```

Read the output with these limits in mind (they are in the receipt too):

- The commit population is survivorship-biased: every landed commit already passed the full battery on the identical tree.
  The ejections are the population that can hold an escape. `attributable` means a would-skip suite failed on at least two
  attempts of the identical tree AND attempt 1 failed the same suite (read from attempt 1's jobs and logs).
- A failed or truncated read is `not-evaluable` and counts in the worst-case numerator. It is never "no failure".
- `scripts/test-all-orphan-log-retention` is a known flake (more than 20 queue-run failures); expect `flake-cleared` rows for it.
- Criterion (c) must state which unit it measures: suite-minutes per full-battery main commit, or billed job-minutes per
  pull-request run. The two differ by the share of PR runs that execute the skippable suites.

## 3. The pre-activation gate

```bash
bash scripts/ci-pr-affected-preactivation.sh            # --help prints the prerequisites, the ADR lines and the exit codes
```

It prints one line per prerequisite and a final `SOLEUR_PR_AFFECTED_PREACTIVATION ready=<true|false> missing=<list>`.
Exit 0 = ready, 1 = at least one prerequisite unmet, 3 = could not decide (every missing prerequisite is unknown: no
network, a missing file), 2 = usage. Only `ready=true` with exit 0 means "every prerequisite is positively met"; it never
means "authorized". Authorization is a human act the script cannot satisfy.

The ADR lines the gate reads (each at the start of its own line; the LAST such line wins):

```text
Go/no-go receipt: <repo-relative path of the receipt, read from the committed tree>
Skippable set: <comma-separated gated groups (test-webplat, test-bun, test-scripts-heavy, test-scripts) or registered suite labels>
Waiver: heartbeat <non-empty reason>
```

The receipt's last non-blank line must be `SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=YYYY-MM-DD`, dated no
later than today and at most 60 days ago. A receipt that exists only as an untracked file or a symlink does not count.

## 4. What a GO would still owe

A GO only makes PR C's stage 2 buildable; it does not activate anything. Owed before any flip, per the ADR amendment: the
reduced-run read wired into `admin-merge-ready.sh` and `ci-head-verdict.sh`, the full-battery audit probe and its paging
route, the census split, and removal of the activation lock in the last commit of that PR. The flip itself needs an
explicit go-ahead that names the command, from the person who owns the budget.

## Rollback

The receipts and tooling can be deleted with no effect on any workflow. The lever's off switch is deleting the repository
variable; while the variable is absent the dark job is skipped and costs 0 billed minutes.
