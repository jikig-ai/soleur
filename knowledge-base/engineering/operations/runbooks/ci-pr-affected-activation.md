---
category: ci
tags: [ci, affected-only, adr-276, s4, go-no-go, replay, activation]
date: 2026-10-16
---

# S4 affected-only PR runs: re-attempt and pre-activation runbook

**Issues:** #9729 (stage 4, stays open), #10448 (the decision the NO-GO left), #10414 (PR D, per-suite selection)
**Decision record:** ADR-276, `## Amendment 2026-10-16 (S4 PR C, #9729)`
**Tooling:** `scripts/ci-pr-affected-replay.py` (evidence), `scripts/ci-pr-affected-preactivation.sh` (read-only gate)

This runbook is for whoever re-attempts S4 after the 2026-10-16 NO-GO, or asks "may `CI_PR_AFFECTED` be flipped?".
Everything here is READ-ONLY. **Nothing in this runbook turns the lever on**, and no step here may be extended to do
so: activation is a separate, explicitly authorized step (ADR-276 S4) that needs a go-ahead naming the command.

**To answer "may it be flipped?", run the gate first (section 1).** The rest is for producing the evidence a GO would rest on.

## 1. The pre-activation gate

```bash
git fetch origin main                                         # the gate reads the COMMITTED tree and wants HEAD to be the tip of main:
git status -sb | head -1                                      # run it from a checkout (or a detached worktree) at origin/main
bash scripts/ci-pr-affected-preactivation.sh                  # needs gh (authenticated for reads), jq, git, GNU date; --help prints all of this
```

It prints one line per prerequisite, the information-only `ac9c=` line, and a final
`SOLEUR_PR_AFFECTED_PREACTIVATION ready=<true|false> missing=<list>`. The seven prerequisites and the closed set of values each prints:

| Line | Met when | Other values it prints |
|---|---|---|
| `variable=` | `absent` (the variable read is 404 and the 100-item variable list is complete and does not name it) | `present`, `unknown(...)` |
| `org_variables=` | `0` organization variables resolve through `vars` | `<n>`, `unknown(http=<status>)` or `unknown(unparseable)` |
| `lock=` | `absent` (no line of the committed driver names `PR_AFFECTED_LOCKED` except as a plain `$PR_AFFECTED_LOCKED` or `${PR_AFFECTED_LOCKED:-…}` read) | `present`, `unknown(driver-missing)`, `unknown(driver-has-no-code)` |
| `artifacts=` | `ok` (the Guard 3 read, its call site and an executable audit script are committed, and the newest `full-battery-audit` job on main succeeded) | `missing:<list>`, `no-audit-run`, `audit-run-<conclusion>` (`audit-run-pending` for an unfinished newest run), `unknown(...)` |
| `verdict=` | `GO-confirmed` (the receipt at HEAD ends in a `verdict=GO ruled=confirmed` line dated within 60 days) | `<verdict>-<ruled>` (for example `NO-GO-confirmed`), `stale(age_days=<n>)`, `no-machine-line`, `receipt-absent`, `no-receipt-recorded`, `unknown(...)`; `(receipt-archived)` is appended when the archived copy was read |
| `prereq5=` | `ok` or `ok(heartbeat-waived)` (a non-empty skippable set of gated groups or registered suites, and the Better Stack follow-up closed AS COMPLETED or waived) | `skippable-set-empty`, `skippable-set-unrecognised(<item>)`, `heartbeat-open`, `heartbeat-closed-<reason>`, `unknown(...)` |
| `tree=` | `head-is-main` (HEAD is the API's tip of main) | `head-is-not-main(head=<sha7>,main=<sha7>)`, `unknown(...)` |

Exit codes: 0 `ready=true`; 1 at least one prerequisite is unmet; 3 nothing is unmet but something could not be read (no network, a
missing file): the gate could not decide; 2 usage. Only `ready=true` with exit 0 means "every prerequisite is positively met". **It never
means "authorized", and it does not recompute the evidence behind a GO**: a hand-written GO line passes the `verdict` reader, so read the
receipt it names. Authorization is a human act the script cannot satisfy.

The ADR lines the gate reads (each at the start of its own line; the LAST such line wins):

```text
Go/no-go receipt: <repo-relative path of the receipt, read from the committed tree>
Skippable set: <comma-separated gated groups (test-webplat, test-bun, test-scripts-heavy) or registered suite labels>
Waiver: heartbeat <non-empty reason>
```

The receipt's last non-blank line must be `SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=YYYY-MM-DD`, dated no
later than today and at most 60 days ago. A receipt that exists only as an untracked file, a symlink or a working-tree edit does not
count. The default heartbeat follow-up is issue 10415 (`--heartbeat-issue N` to change it); `Waiver: heartbeat <reason>` stands in for that
follow-up and for nothing else.

## 2. Where things stand

The lever (PR B) is shipped dark and locked and costs 0 billed minutes while `CI_PR_AFFECTED` is unset. PR C measured the proposed
per-suite rule and ruled **NO-GO** on index completeness (criterion b): 190 of 630 registered suites (190 of the 515 audited) name a tracked
path the index does not declare for them, on the pinned tree `abbd36a696` (a tree that includes this PR's two new suites reads 192 of 631, so
a re-run on a later tree will not print 190). The receipts are in the PR C spec directory (`receipts/`, archived at ship under
`specs/archive/<timestamp>-feat-one-shot-9729-ci-pr-c-affected-only/receipts/`, leaf names kept).

## 3. Entry condition for a re-attempt (CTO ruling, ADR-276 amendment item 5)

All of these, in this order:

1. The audit exits 0: `gap_suites=0` and `unaudited=0` after the human exemptions in an `--accept` file (one row per exempted name,
   `suite<TAB>path-or-*<TAB>false-positive: <reason>`, the reason mandatory; the one directory suite `plugins/soleur` is `unaudited` until
   the audit reads it or a `*` row accepts it). `unaudited` rows must be READ or accepted by a human, never argued away.
2. A ratchet that fails on any suite naming an undeclared tracked path is a **required** CI check.
3. The escape replay, the saving and the reader audit are re-run on a fresh window (section 4) and the go/no-go is re-ruled.

## 4. Re-run the evidence

Run from a checkout of the commit under test. Every command is read-only; the replay writes only under `--out`. The replay runs the
selector once per commit and once per failed queue run (about 21 to 28 s each on a warm cache: roughly 2.5 hours serially for 356 units),
so use `--chunk I/K` for the commit population and expect the ejections to take about 25 minutes.

```bash
# a pinned tree: the audit reads the working tree, so audit a detached checkout of origin/main, never a dirty branch
git fetch origin main
git worktree add --detach /var/tmp/s4-audit origin/main
python3 -I scripts/ci-pr-affected-replay.py audit --root /var/tmp/s4-audit --all-refs > /var/tmp/s4-audit.out   # ~3 minutes
git worktree remove --force /var/tmp/s4-audit
```

`audit` prints `gap` and `unaudited` lines and `SOLEUR_PR_AFFECTED_AUDIT suites=… always_on=… audited=… unaudited=… gap_suites=…
gap_refs=… accepted=…`. It exits 0 only when no gap and no unaudited suite remain; `gap_suites=0` beside `unaudited>0` is not a clean
audit (a suite the audit never read is not a suite with no gaps). `always_on` suites run on every diff and are exempt. The audit sees literal path names only: a path assembled from a variable, or read through a helper the audit does not follow, is invisible to it, so `gap_suites=0` is a lower bound, never proof of completeness. Edges are read with
the selector's own grammar (`^dir/` prefix, `^file` exact, `^glob:` bash glob), not as regexes. Tally the most frequent undeclared paths
from the `--all-refs` output (the default prints only the first six per suite).

```bash
OUT=/var/tmp/s4-replay
# the last 300 first-parent commits of main (resumable; --chunk I/K splits it; --reclassify re-reads every non-clean unit)
python3 -I scripts/ci-pr-affected-replay.py collect --out "$OUT" --commits 300 --base origin/main
# every refused merge_group run (every conclusion except success, cancelled included) in the same window; prints the conclusion histogram
# and writes ejections-window.json, the count aggregate checks the population against
python3 -I scripts/ci-pr-affected-replay.py ejections --out "$OUT" --commits 300 --base origin/main
# the receipt text: rule hash, classes, routes, worst-case bound, saving, net saving against the 20% bar.
# It refuses (rc 2) a directory with no ejections file or no ejections-window.json, an ejection population that is not the window's refused count,
# missing or duplicated commit units, or a count other than --expect-commits.
python3 -I scripts/ci-pr-affected-replay.py aggregate "$OUT" --expect-commits 300 --out "$OUT/replay-summary.txt"
# the one-sided 95% bound for K events in N (prints a fraction: 0.009936 is 0.99%)
python3 -I scripts/ci-pr-affected-replay.py cp-upper 0 300
```

Read the output with these limits in mind (they are in the receipt too):

- The commit population is survivorship-biased: every landed commit already passed the full battery on the identical tree.
  The ejections are the population that can hold an escape. `attributable` means a would-skip suite failed on at least two
  attempts of the identical tree AND attempt 1 failed the same suite (read from attempt 1's jobs and logs).
- A failed or truncated read is `not-evaluable` and counts in the worst-case numerator. It is never "no failure". A failing job that is
  in neither the suite-shard family nor ci.yml's job list is `unclassified-job`, also `not-evaluable`.
- `scripts/test-all-orphan-log-retention` is a known flake (more than 20 queue-run failures); expect `flake-cleared` rows for it.

## 5. The four criteria and the verdict

GO iff every criterion passes. Each is supplied to `verdict` as a status; the command computes, it does not measure:

| Criterion | What it asks | How to get its status |
|---|---|---|
| a | escape rate: point estimate (attributable plus unverified) at most 2% and the 95% bound on the worst-case numerator under 12% | `aggregate` (`cp95_upper_on_worst_case=` and the point percentage) |
| b | zero unexplained index gaps | `audit` exit code (0 = pass); a gap is a measurement, no 10% band applies |
| c | net saving at least 20% of the 99.8 baseline in billed job-minutes per PULL-REQUEST run, and restored selection plus overhead at most 120 s | the saving leg needs a per-PR-run measurement (the replay prints suite-minutes per commit, a different unit); the timing leg is the canary in `receipts/sel-s-canary.md` |
| d | every documentation-mentioning test file classified, none a real reader inside a skippable suite | `bash scripts/test-affected-kb-consumers.test.sh` plus the census in `receipts/reader-audit.md` |

```bash
python3 -I scripts/ci-pr-affected-replay.py verdict --a pass --b fail --c unmeasured --d pass
# prints: computed=GO|NO-GO|UNDECIDED reason=...   (statuses: pass | fail | within-10% | unmeasured; the band applies to a and c only)
```

`verdict` exits 0 whatever it prints: **read `computed=`, the exit code carries no verdict.** Do not chain it with `&&` as a gate.

## 6. What a GO would still owe

A GO only makes PR C's stage 2 buildable; it does not activate anything. Owed before any flip, per the ADR amendment: the
reduced-run read wired into `admin-merge-ready.sh` and `ci-head-verdict.sh`, the full-battery audit probe and its paging
route, the census split, and removal of the activation lock in the last commit of that PR. The flip itself needs an
explicit go-ahead that names the command, from the person who owns the budget.

## Rollback

The receipts and tooling can be deleted with no effect on any workflow. The lever's off switch is deleting the repository
variable; while the variable is absent the dark job is skipped and costs 0 billed minutes.
