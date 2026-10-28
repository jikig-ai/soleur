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
   `suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>`, or `suite<TAB>*<TAB>-<TAB>-<TAB>false-positive: <reason>` for a
   suite with no tracked input at all; the reason is mandatory. The anchor is the first 12 hex of sha256 over the source line with its
   whitespace collapsed (`" ".join(line.split())`), the ordinal counts the lines whose collapsed whitespace form (`" ".join(line.split())`) is hashed to the same anchor, in the suite file then its
   sourced libraries; `--all-refs` prints both. A row whose anchor matches no live line, or whose pair is no longer a gap, is `stale` and
   fails the audit. The 3-column row of earlier revisions is retired and exits 2. The directory suite `plugins/soleur` is now audited
   (its bun-discoverable test files are scanned); a tracked file that cannot be read makes its suite `unaudited`, and a `*` row accepts only a suite that has no tracked input at all. Otherwise it is `stale`, with one of two reasons: `star-row-tracked-suite` when git tracks the suite's input but the work tree lost or cannot open it (deleted, dangling symlink, link to a directory), and `star-row-unreadable-members` when the suite has readable inputs and some member cannot be read). `unaudited` rows must be READ or accepted by a human, never argued away.
2. A ratchet that fails on any suite naming an undeclared tracked path is a **required** CI check. (Status: the ratchet exists as the advisory job `affected-index-ratchet` since S4 index completion PR3a, #10448; it becomes a required context in PR3b, #10859, after the observation window of section 7 and the budget owner's go-ahead. Section 7 is how to run it.)
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

`audit` prints `gap`, `unaudited` and `stale` lines and `SOLEUR_PR_AFFECTED_AUDIT suites=… always_on=… audited=… unaudited=… gap_suites=…
gap_refs=… accepted=… stale=… refs=… files_read=…` (a stale row also exits 1; `suites` counts selector rows; `always_on`, `audited`, `unaudited` and `gap_suites` are per suite label (rows sharing a label are one suite, and `audited` never counts a label that is also unaudited or always_on); `gap_refs`, `refs` and `accepted` count (label, path) pairs (`refs` before any exemption, `gap_refs` after, `accepted` plus one per suite accepted whole by a `*` row); `stale` counts accept-row entries; `files_read` is the number of distinct files read, so a change of the audit's reach shows even when the gaps do not move). It exits 0 only when no gap and no unaudited suite remain; `gap_suites=0` beside `unaudited>0` is not a clean
audit (a suite the audit never read is not a suite with no gaps). `always_on` suites run on every diff and are exempt. The audit sees literal path names only: a path assembled from a variable, or read through a helper the audit does not follow, is invisible to it, so `gap_suites=0` is a lower bound, never proof of completeness. Edges are read with
the selector's own grammar (`^dir/` prefix, `^file` exact, `^glob:` bash glob), not as regexes. Tally the most frequent undeclared paths
from the `--all-refs` output (the default prints only the first six per suite).

What the audit reads is frozen, and `python3 scripts/ci-pr-affected-replay.py --help` (the REACH and DECLARED LIMITS sections of its docstring) is the single place that defines it: the suite's own file; the `source` closure of it to depth 8, operands resolved against the including file for `$(dirname ...)`, `$SCRIPT_DIR`, `$HERE` and `$DIR` and against the repo root for `$REPO_ROOT`, `$ROOT_DIR`, any other `$X` and a bare path; and the code files the suite's own selector row lists that an already-read text names, to depth 8, each with its own source closure. `gap_suites=0` is literal-name completeness over what the audit reads, necessary but not sufficient. The limits that matter most when reading a clean result: hops are `source` and `.` only (not `bash x.sh`, `VAR=path; source "$VAR"`, python imports, or a prefix assigned from `cd ... && pwd`), and data files in `pats` are never scanned.

Reach moves through declared edges and through the text of files it reads (the drain-reveal rule): declaring a code file as an edge makes the audit read it, which can reveal more pairs, and it can shift the ordinals of accept rows (a `stale ... anchor-not-live` row). So accept an anchor-keyed row when the suite does not read or execute the file, declare an edge only when it does, and re-run the audit until `refs`, `files_read`, `gap_refs` and `stale` stop changing.

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

## 7. The ratchet (S4 index completion PR3a, #10448)

The audit exits 1 on `main` today (the committed baseline holds whatever `wc -l scripts/ci-pr-affected-audit.baseline.tsv` reports, which is the number to quote; dated measurements: 294 gap suites and 1,884 gap pairs on `4da1673510` when PR3a was built,
1,886 baseline lines on `33feda184e`, and the count after the PR4 drain is in the PR4 body), so a check that simply required the audit to pass could never
be green. `python3 -I scripts/ci-pr-affected-replay.py ratchet` is the audit as a **ratchet**: the live set of `(suite, undeclared tracked path)` pairs, after the `--accept`
exemptions, must EQUAL the committed shrink-only baseline `scripts/ci-pr-affected-audit.baseline.tsv`, and the baseline may only lose pairs against its base. Its contract
(exit codes, the order of the checks, the baseline-state table, the formats) is the RATCHET section of `python3 scripts/ci-pr-affected-replay.py --help`; this section is how to
operate it. What a green ratchet means is the one wording of section 4: literal-name completeness over what the audit reads, necessary but not sufficient. The
declared limits of that reading (what the audit cannot see: computed names, comment and heredoc text, glued or generated paths, and the others) are stated as mechanisms in the DECLARED LIMITS section of
`python3 scripts/ci-pr-affected-replay.py --help`; they are pointed at here and in the ADR-276 amendment, not copied, so two copies cannot drift, and the failure text carries none of them: read a green run against that list.

### The dark phase

Until PR3b (#10859) the job `affected-index-ratchet` in `.github/workflows/ci.yml` is **advisory**: job-level `continue-on-error: true`, absent from `scripts/required-checks.txt`, the
canonical ruleset JSON and `infra/github`, and it runs on `pull_request` and `merge_group` only (never on push, so it cannot red the `CI` run that `web-platform-release.yml`
reads before a deploy). It costs about 3.4 billed minutes per run (a 3 to 4 minute range), about 4,400 minutes a week (about 2.8% of the weekly total), of which about 2,250 on draft pushes (about +11% on each draft push).
Draft, docs-only and bot PRs are NOT skipped: the job is in the always-on sets `UNGATED_PINNED` and `LIGHT_PINNED`, by ruling (CTO, 2026-10-23), because a `draft-light` condition would skip it on every light draft push and the
window could then never observe a draft PR or the draft-push datapoint PR3b needs. The stop for this cost is the 30-day trigger of the ADR amendment (item 7), and it lowers the net saving that criterion (c) is measured against.
Ceilings: 210 s p95 wall, 270 s maximum, `timeout-minutes: 5`; the two ceilings are PROVISIONAL (see the observation log). How to read a run:

- the **marker line** in the job log, the last line the script prints: `SOLEUR_PR_AFFECTED_RATCHET exit=<0|1|2> reason=<token> live=<n> baseline=<n>`;
- the **annotation** the workflow step emits from the exit code, `::error title=affected-index-ratchet::exit=<1|2> reason=<token>` (a run that printed no marker is annotated `exit=2 reason=no-marker`, a non-success run with no annotation at all counts as exit 2);
- the job summary, which carries the fuller failure text (the log prints the first 25 entries of each class and a count);
- the jobs API, `.jobs[] | select(.name == "affected-index-ratchet")` for `conclusion`, `started_at` and `completed_at`. `continue-on-error` is meant to keep the `pull_request` and `merge_group` RUN conclusions green while the context is not required (GitHub's documented behaviour; not confirmed by the canary, whose run was red from other jobs).
  Measured on the canary (observation log below): a failing job-level `continue-on-error` job still concludes `failure` in the jobs API and shows as a red check on the PR check list, with its `::error` annotation. Read the marker line, not the conclusion alone, and do not read a red advisory check as a required-check failure.

`oracle-inputs-changed: <files>` in the output (also a `::warning` and a summary line) is a **non-blocking** notice that this diff touches the check's own oracle: `scripts/ci-pr-affected-replay.py`, `.github/workflows/ci.yml`, the baseline,
`plugins/soleur/scripts/lint-ratchet.py`, the accept file, `scripts/lib/test-affected-paths.sh` or `scripts/test-all.sh`. Review it as the oracle, and know what that review is: **no automated control checks that the suite does not read a file an accept row exempts;
this check does not verify it.** A CODEOWNERS entry routes the review, but no required review exists in this repository's ruleset (verified: only the marketplace repo's ruleset sets `required_approving_review_count`), so the review is
not an enforced control and PR3b must not claim one. For the replay script and ci.yml, compare the verdicts of the base copy (`git show HEAD^1:scripts/ci-pr-affected-replay.py`) and the PR copy on the same tree; the check does not run the base
copy of the script as the gate, because a PR that legitimately changes the ratchet logic would then be unmergeable. The helper `plugins/soleur/scripts/lint-ratchet.py` is different: it is loaded from the MERGE-BASE commit, as ADR-290 runs its own ratchet script, so one PR
cannot weaken the base-resolution helper together with the baseline; a PR that moves that helper must land the move first (a base without the file is exit 2 `internal`). Growth of the accept file is notice-only in PR3a.

| Exit | Reason token | What it means | What to do |
|---|---|---|---|
| 0 | `pass` | live equals the baseline and every other check holds | nothing |
| 1 | `new-pair` | a suite names a tracked path that is not declared, not accepted and not in the baseline | declare or accept it (below); never add a baseline line |
| 1 | `baseline-deleted` | the baseline file was deleted while pairs are still live | confirm the file really was deleted on your branch (a run that exited 2 or printed partial selector output proves nothing), then restore it: `git checkout origin/main -- scripts/ci-pr-affected-audit.baseline.tsv`; only the strict-zero end state (nothing live) may delete it |
| 1 | `stale-line` | a baseline line is no longer live (the suite or the path changed), or the file is malformed or holds conflict markers | first confirm the pair is really gone on a clean checkout; if the selector output was partial or this run exited 2, do not prune: rerun. Then delete the line the output prints; see the baseline-conflict recipe |
| 1 | `baseline-dup`, `baseline-order` | a duplicate line, or the file is not C-locale sorted with a final newline | take main's copy, then the recipe below |
| 1 | `grown` | the head baseline has a line the base does not (a new suite, or one pair swapped for another) | remove it: a baseline can only lose lines against its base |
| 1 | `unaudited` | the audit could not read the suite in full | fix the selector row or make its inputs readable |
| 1 | `star-row`, `stale-accept` | an accept row for a readable suite as a whole, or an accept row the tree no longer backs, or a malformed accept file | delete or correct the accept row |
| 2 | `floor-*`, `selector-failed`, `selector-timeout` | infrastructure: the selector failed, hung, fell back, printed a short, extra or inconsistent output, or the census read nothing | re-run the job; a reproduction on the same SHA is a defect: report it on #10448 |
| 2 | `floor-bad-row` | an `AFFECTED_SELECTED` row fails the selector grammar: the selected flag is not `0` or `1`, or the reason is not one of the `_AC_CLASS` literals derived at run time from `scripts/test-all.sh` | a defect in the selector output or in the derivation: report it on #10448; never prune the baseline on this run |
| 2 | `floor-unreadable` | a tracked input could not be read for a reason other than being absent (a permission or I/O fault) | re-run on a clean checkout; a reproduction is a defect |
| 2 | `timeout`, `no-marker` | `timeout`: the job was cancelled at its time limit (the observation probe's classification); `no-marker`: the script died before printing a marker line (the workflow annotation only) | re-run; a reproduction on the same SHA is a defect |
| 2 | `base-unresolved` | `HEAD^1` does not resolve (a root commit or a shallow clone) | fetch more history (the job uses `fetch-depth: 2`) |
| 2 | `baseline-unreadable`, `accept-unreadable`, `internal` | the baseline file (`baseline-unreadable`) or the accept file (`accept-unreadable`) could not be read, or the helper `plugins/soleur/scripts/lint-ratchet.py` at the merge base is missing, does not compile or raised | re-run; a reproduction is a defect |

A re-run of a failed `pull_request` job reuses the old merge SHA, so after a push or a rebase let the new run decide; a PR with a merge conflict has no run at all (resolve the conflict first).

### Ratchet red on a PR or queue entry

The failure text names the suite, the path and the referencing `file:line`, then one of three causes: your change **added the file** the suite names; your change **edited the suite** (or a file it
reads); or it touched **neither** (main moved, or an edge or accept row that covered the pair was removed: rebase, then declare or accept). Then there are exactly two remedies, and the decision between them is the point:

1. **Declare the path** in `AFFECTED_<LABEL>_PATHS` in `scripts/lib/test-affected-paths.sh`, only when the suite really reads or executes the file (that is what the selector must know to select the suite). Editing that file is a runner trigger and runs the full battery once.
2. **Add an anchor-keyed accept row** to `scripts/ci-pr-affected-audit.accept.tsv` (`suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>`; the anchor and ordinal are on the `ref` line of the failure text and in `audit --all-refs`) only when the suite merely names the file: a message, a fixture it writes into a scratch tree, a negative-test string. The reason names the line kind. **An accept row on a file the suite really reads is a false negative that becomes live once the lever flips**, and no automated control checks that the suite does not read the file: this check does not verify it. A CODEOWNERS entry routes the review, but no required review exists in this repository's ruleset, so the author and the reviewer must check the claim by reading the suite.

A baseline row cannot be added: the failure text offers no way to, `ratchet --print-baseline` only removes pairs once a baseline exists, and the growth rule refuses any line the base does not have. PR4 (#10860) drained the code-extension pairs
it could prove are real reads; the pairs that remain in the file (`wc -l` is the count) are mentions, non-code pairs, and the real reads whose edge was held back because declaring it reveals more mentions (PR4b and PR4c take them first, PR5 the rest). Until they are drained or accepted,
**a PR that adds a new path mention to a suite fails the ratchet and must declare an edge** (or add an accept row for a mention) in the same PR.

A rename or move of a path a baselined suite names reads as a new pair (growth, exit 1): a rename of a baselined path or suite is a **drain-class PR**. Declare or accept the renamed pairs first, then rename, or rename in the same PR with every renamed pair declared or accepted.
While the job is advisory a red on such a rename is expected and is noted in the PR; rename-carry (an exact one-to-one rename of a pair already in the base baseline) is a PR3b entry condition, not built.

A PR that **widens the audit's reach** (the REACH section of the script) may land only in the same PR that drains every pair it reveals: zero baseline pairs added, nothing undeclared revealed. A baseline re-base is forbidden (it would turn the ratchet into a ledger that can be reset).
If the reveal is too large the widening lands dark (code present behind an off-by-default option the ratchet job does not pass) and the PR that drains the revealed pairs turns the option on in the same commit. Every reach change needs a reach-differential receipt like PR1b's. A widening PR with a non-empty reveal is red by design.

### Ratchet red because main moved

A new pair that landed on main (another PR's suite, merged while this one was open) turns later runs red with nobody forced to repair it. The repair owner is the **author who introduced the pair**; the owner of #10448 is the fallback
when the author is a bot or unreachable. The fix-forward is a declare, accept or prune PR that never adds a baseline line, due within **one working day**. While the job has no push run, "main is red" means the latest `merge_group` conclusion of the job on the main tip.
`ratchet --print-baseline` is prune-only: it removes lines that are no longer live and never adds one. Use it only after a full, clean `ratchet` run (it must reach a verdict; a run that exited 2 or printed partial selector output measured nothing, and pruning from it would delete real pairs that a shrink-only baseline can never get back). In PR3a, where the base has no baseline, deleting the baseline file first and regenerating is legitimate (adoption absorbs it); after PR3a merges it is not.
The adoption arm (base has no baseline, HEAD has one) is a PR3a bootstrap path and an open hole once a baseline has been retired: PR5 (#10861), in the commit that deletes the baseline, also removes the adoption arm from the state table, with a row proving that a re-added baseline exits 1.

### The baseline-conflict recipe

When the baseline file conflicts on a rebase (or holds conflict markers, a duplicate, or an order problem), never hand-resolve it by taking either side. Take main's copy of the file, then prune it with the tool and re-check (only when a plain `ratchet --base origin/main` run reached a verdict first, see above). Do not redirect straight onto the file (the shell truncates it before the tool reads it):

```bash
git fetch origin main                      # a stale origin/main is the wrong base
# resolve scripts/lib/test-affected-paths.sh first, then regenerate on the FINAL tree (HEAD committed, tree clean), and again after any later edit to the index
git checkout origin/main -- scripts/ci-pr-affected-audit.baseline.tsv
python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > scripts/ci-pr-affected-audit.baseline.tsv.new \
  && mv scripts/ci-pr-affected-audit.baseline.tsv.new scripts/ci-pr-affected-audit.baseline.tsv
python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main     # on a developer checkout pass the base: HEAD^1 is only the previous local commit
```

The baseline must be tracked on the tree the tool runs on (a worktree of `HEAD`), or the suites that name the baseline's own path gain a pair. If the pruned file is still not equal to the live set, the difference is a new pair: declare it or accept it (above). In a drain PR a new pair from main is declared when the suite really reads the file; if it is a mention, an accept row is allowed in PR4b and PR4c under the four limits of the drain rubric (mentions only; hold the whole edge on doubt; hold an edge that needs more than 10 accept rows, or any accept row anchored on a file with more than 8 commits in 90 days; zero stale or unused accept rows at the end), otherwise hold the pair for PR5 and say so in the PR body.

### The drain claim

PR4 (#10860), its continuations PR4b and PR4c (both tracked on #10959) and PR5 (#10861) shrink the baseline in the same commit as the edge or accept edit, so the live set and the baseline move together. Only one drain PR is open at a time: the claim is the label `s4-drain` on one open DRAFT PR plus a mirror
comment on #10448 (`gh pr list --label s4-drain --state open` must be empty before a second is started). A second PR rebases and regenerates with the prune-only `--print-baseline` until the diff to main is empty, never by hand. A drain PR merged inside the PR3b observation window
changes the baseline, the live set and the runner oracle, so it restarts the window count: the probe enforces that itself (#10949), counting only runs created after the LATER of the PR3a merge and the latest merged `s4-drain` PR, so the restart needs no hand-recorded SHA (recording the merge SHA on #10865 stays good practice, and the status line's `window opened=` and `floor=pr3a|s4-drain` name the floor in use). The floor follows the LABEL: an oracle change merged without the `s4-drain` claim does not move it (a PR touching an oracle input is still excluded from the counts), and a page of 100 labelled items is refused rather than trusted. The default order was PR3a, the window, PR3b, PR4; PR4 was not delayed, which is the owner's schedule call.

### The drain rubric

One home for the bar PR4 applied, so PR4b, PR5 and later authors apply the same one (evidence for each pair: `knowledge-base/project/specs/archive/20261025-151757-feat-one-shot-s4-affected-index-pr4-code-edge-drain/pairs-decisions.tsv`).

- **Declare an exact-file edge** in `AFFECTED_<LABEL>_PATHS` only when, at run time, the suite or a library or script it runs (a) executes or sources the file (a computed path and a best-effort `source ... || true` count), (b) opens its content (cat, grep, jq, readFileSync, import, hash, diff, or copy-then-assert on a copy), (c) asserts its existence or mode where the verdict depends on it, or (d) the path is a data-table row that a quoted loop feeds to a read, exec or stat. No quoted loop means no declaration.
- **A mention is not declared.** Messages, docstrings and comments, test-vector arguments to a predicate that never opens the path, fixture rows, files the suite writes into a scratch tree, allow-list, classification and relevance rows (a text-scanned data library is not a read), negative strings. A mention is accepted with an anchor-keyed accept row in the same commit as the edge that reveals it (PR4b and PR4c, under the four limits below); a mention that breaks a limit holds its edge and goes to PR4c or PR5.
- **Shared helper reads** go through an underscore-prefixed shared array (`_CLOSURE_LEAF_*`, defined above the first label that spreads it, commented with the sourcing `file:line`), spread only into labels whose suite really sources the helper.
- **Breadth.** Exact file by default; a directory prefix only for a real walker (loop line quoted, at least 3 segments, at most 25 tracked files); `glob:` only for extension-aware walks; no `ALWAYS_ON_SUITES` entry in a drain PR, except the one PR5's measured verdict allows (#10861; procedure below). A whole-tree walker is decided by that measured verdict, not by hand.
- **Reveal and hold-back.** Declaring a file makes the audit read it, and every path it names becomes a pair for that suite. Count the `new-pair` entries of the first report (`ratchet --report <file>`). A revealed real read is declared next round; a revealed mention gets an accept row (reason `false-positive: <line kind>: <file:line>: <evidence>`, one row per boundary line, taken from `audit --all-refs`, because the ratchet report prints at most 3 lines per pair) or, on doubt or past a limit, the revealing edge is held back (its original pair stays baselined). The first report is counted with the round's edges declared and no accept rows for them; round 1 summed over all chains is at most 130; a single edge that alone reveals 60 or more pairs is never declared in a drain PR. A suite whose read recorder (`scripts/audit-suite-reads.sh record --mode check`) shows the named path opened in both recordings is a real read; opened in one is a hold; unreliable recordings (rc != 0), bulk readers (more than 1000 files opened) and edges whose declared file was never opened are held. Accept reasons name the line kind from this list: `message`, `JSDoc/comment`, `PR-body string`, `help/menu text`, `data row not fed to a read loop`, `code line in a file read only as text` (the last needs the recorder to show the file opened and the named path not opened in both recordings, and the suite text to use the file only as an argument to a text tool). Before accepting any pair, grep the declared file for the path's basename and its parent directory as separate string literals: an audit boundary line is the literal path, and a computed construction (`Path(".claude") / "x"`, `os.path.join`, a `$ROOT/...` concatenation) reads the file without producing one. Recorder verdict `uncovered` (reads outside the argv cover) and `unresolved=` (static operands it could not resolve) are information in `--mode check`, not holds; a row of the new kind stays valid only while the suite uses the file as text, so a suite edit that adds `bash`, `source` or `exec` of that file reopens the row. Expect accept-row churn: editing an accepted line turns its row stale and the pair new on the editing PR, which is the intended signal, not an incident. Stop line (CTO ruling of 2026-10-23, plan `plans/archive/20261025-151757-2026-10-23-ci-s4-affected-index-pr4-code-edge-drain-plan.md` Technical Rulings 5 and 7): round 1 under 60 new pairs PER CHAIN (and at most 130 summed over all chains, CTO amendment of 2026-10-25), later rounds under 30, at most 4 rounds, strictly shrinking, cumulative at most 150 with accepted mentions counted and a shared-array reveal multiplied by the number of labels that spread it; over a cap, hold back and continue in a follow-up PR under the same `s4-drain` claim.
- **Ambiguous pairs and big files.** A pair a 20-minute read cannot settle is declared as one exact file only if the edge adds at most about one suite run per 20 PRs (`git log --since=90.days --oneline -- <path>` count times suites declaring it); otherwise leave it for PR5 (#10861). An edge that needs more than 10 accept rows, or any accept row anchored on a file with more than 8 commits in 90 days (`git log --since=90.days --oneline -- <file> | wc -l`, evaluated on the file that holds the mention line), is held back.
- **A whole-tree or glob reader (PR5, #10861).** Take both measurements at work time on a recorded `origin/main` SHA, never from an earlier PR. First record the SHA (`git fetch origin main && git rev-parse origin/main`) and save the edge set BEFORE any index edit: `bash scripts/test-all.sh --print-selection --paths=README.md > rows.txt`. Then run `python3 -I scripts/ci-pr-affected-replay.py glob-rate --candidates <file> --list rows.txt --pairs <file> --commits 200 --base <sha> --spot-check 3 --out <dir>`. The candidates file is `suite<TAB>entry` per line: a blank entry lists the suite on its existing edges alone, a `glob:head/**.ext` or `dir/` or file entry adds a candidate, and `suite<TAB>@tree` demands that the glob entries cover every tracked file of their extensions (a `glob` verdict needs either an `@tree` cover or at least one pair in `--pairs`, else it is `baselined` as `no-coverage-proof`). The pairs file is `suite<TAB>path` for the baselined pairs the glob must cover. Exit 0 means every row got a verdict, not that anything qualified: read the `verdict` column or the `SOLEUR_PR_AFFECTED_GLOB_RATE` marker counts; 2 is a refused input, 3 a failed read, 4 the model disagreeing with the real selector. It is read-only; per suite it prints the duration with its `src` column, the selection rate over the last 200 first-parent commits (existing edges OR the candidate entries, in a conservative and an excluded reading that must agree) and a verdict with inclusive bounds: `glob` (a `measured` duration of at most 60 s and at most 25% of the units), `always_on` (a `measured` duration of at most 30 s by the policy, in practice at most 10 s because `scripts/test-all-fast-tier-budget.test.sh` rejects any always-on label above `LOCAL_FAST_CAP_MS`, and more than 25%), otherwise `baselined` with a reason code (`always-on-over-fast-tier-cap` for the 10 s to 30 s case; raising the always-on ceiling means changing the fast-tier cap in `scripts/test-all-fast-tier-budget.test.sh` first, in a separate PR). A `floor` or missing duration row never qualifies. The spot-check runs the real selector on evenly spaced diffs and a divergence stops the work. An `always_on` entry also raises `_MIN_ALWAYS_ON_DECLARED` and its `f1` pin, and deletes the suite's accept rows and `test-affected-kb-consumers.baseline.txt` rows. The hot-file budget does not apply to a `glob:` edge: the replayed rate already shows a hot file's churn. Never an accept row for a real whole-tree reader.
- **Never in a drain PR:** hand-edit the baseline (`--print-baseline` is prune-only and cannot re-add a line; start from main's file), add an accept row for a real read or for a mention that breaks a limit, add an `ALWAYS_ON_SUITES` entry (except PR5's measured verdict, #10861), set `CI_PR_AFFECTED`, or remove the activation lock. (An accept row for a revealed mention is allowed in PR4b and PR4c under the four limits; the accept file exists.)
- **The PR4b worklist.** In the decision table, section-2 rows of kind `held-back` are the real-read edges PR4b takes first (`awk -F'\t' '$1=="held-back"{print $2"\t"$3}' pairs-decisions.tsv`); rows of kind `deferred-sweep` are whole-tree or glob reads, a selection-policy call, not PR4b. After the PR4 branch merges the spec directory is archived, so look under `knowledge-base/project/specs/archive/<timestamp>-feat-one-shot-s4-affected-index-pr4-code-edge-drain/`. PR4b's own outcome per worklist edge (declare, or a hold with a reason code `recorder-unreliable`, `bulk-reader`, `declared-F-never-opened`, `held-hot`, `held-brittle`, `kept-for-census`, `already-undrained`, `out-of-slice`) is `receipts/edges-decisions.tsv` under `knowledge-base/project/specs/archive/<timestamp>-feat-one-shot-s4-affected-index-pr4b-held-back-edges/`; PR4c starts from its `out-of-slice` and `held-*` rows. Handed on, not done in PR4b: the single 152-pair edge `tests/scripts/git-data-birth-readiness-gate` (PR5) and the 43 whole-tree reads, for which the CTO ruled the policy only: a `glob:` edge when the suite runs in 60 s or less and the edge selects at most 25% of 200 merged PRs, an `ALWAYS_ON_SUITES` entry when it runs in 30 s or less and is selected more often, otherwise baselined, and never an accept row for a real whole-tree reader. A drain PR edits `scripts/lib/test-affected-paths.sh`, which counts as a runner change, so `test-all.sh --affected` degrades to the full battery (`AFFECTED_FALLBACK reason=runner-changed`): the local gate then queues behind sibling runs for hours and CI's required `test` context is the merge gate. Run the ratchet, the audit, `test-affected-kb-consumers.test.sh`, `scripts/lib/inngest-probe-row.test.sh` and the replay suite locally and let the full gate run detached. The recorder is evidence and never a gate: the static line kind decides, and `not opened in both recordings` alone never licenses an accept row. The line kind in accept reasons is written `code line in a file read only as text` (the ruled name `code line in a file the suite reads only as text`, shortened). PR4c's outcome per worklist edge is `receipts/edges-decisions.tsv` under `knowledge-base/project/specs/archive/<timestamp>-feat-one-shot-s4-affected-index-pr4c-held-back-edges/receipts/` after the ship step archives it (until then under `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4c-held-back-edges/receipts/`). Column 3 is the outcome (`declare`, `held-pr5`, `held-unsure`, `held-hot`, `held-brittle`, `kept-for-census`, `already-undrained`) and column 4 the reason, whose prefix is the reason code: `recorder-unreliable-2`, `declared-F-never-opened-2` and `real-read-unproven` mean a second look stayed unproven. PR5 inherits what PR4c did not declare with `awk -F'\t' 'NR>1 && $3!="declare"' receipts/edges-decisions.tsv`. PR4c declared 8 worklist edges (baseline lines drained; the 3 round-2 real-read files are index entries, not worklist edges), fewer than the 10 that CTO row 3 requires, so there is no PR4d: the drain series ends with PR4c and everything still held goes to PR5 by name, together with the `tests/scripts/git-data-birth-readiness-gate` edge (151 pairs in the PR4c trial), `.claude/hooks/grep-q-pipe-guard.test.sh`'s 31 edges, the bulk readers and the 43 whole-tree reads (`receipts/handoff-pr5-deferred-sweep.tsv`; the policy above is unchanged and PR5 takes both measurements at its own work time). Also for PR5, in `receipts/handoff-pr5-notes.md`: `plugins/soleur/test/boundary-prefix.test.sh` is a directory-glob scanner (four globs, about 164 files) that PR4c expresses with exact files only, and the accept rows that rest on a suite's text-only use of a file are re-read against that suite before any flip. A hot file (more than 8 commits in 90 days) may be declared as F with zero accept rows only if every pair it reveals is a real read, every other real read the chain reveals passes the same test, and its 90-day commit count times the number of suites declaring it (counting the baselined consumers PR5 will add) is at most about 72 (a cost heuristic for the editor of that file, not a correctness bound); a later suite is added to such an F only if the budget and zero accept rows hold for every consumer. PR4c used no such exception: the one candidate, the rung2 suite's own script, reveals a file the suite never reads.
- **A revert is not a clean rollback.** It re-adds the drained baseline lines, which the growth rule reads as `grown` on the revert PR itself, because those lines are absent from its base, so that PR is red; once it merges, main is consistent again (the edges and the baseline lines come back together) and later PRs compare clean. Correct forward instead: keep the edge, or remove it together with its accept rows.

### The observation log

The window that PR3b waits for is enforced by the follow-through probe `scripts/followthroughs/ratchet-observation-window-10865.sh` (tracker #10865). Its rules:

- **Criteria.** At least 3 `pull_request` runs from 3 distinct PRs (one touching `scripts/` or a suite file) and 3 `merge_group` runs on distinct SHAs, every one `exit=0 reason=pass`; p95 wall at most 210 s and maximum at most 270 s; one docs-only PR, one draft PR and one bot PR when one occurs (when none occurs by the 30-day trigger the committed synthetic-green unit test substitutes and the substitution is recorded). The p95 and maximum are computed over every unit that ran and is not an excluded incident, red and timed-out units included, so a ceiling sees the tail.
- **Exit codes.** An unmet criterion is exit 2 with a `NOT YET:` first token, the convention the sweeper and the sibling closing probes use; exit 1 is not used by this probe. Exit 3 means it could not establish the answer (a read failed, or a successful job carried no marker), 78 refusal under xtrace, 0 the window passed.
- **Pause and restart.** A genuine `exit=1` pauses nothing by itself and restarts nothing; a red latest `merge_group` run pauses the window until it is repaired (a pause is `NOT YET`, not a restart). An exit 2 is classified by a same-SHA rerun with no code change (passes: an incident, excluded; reproduces: a defect, the window restarts at that run); an exit 2 never rerun is unclassified and `NOT YET`. A job cancelled or timed out with a wall of 290 s or more is a unit with exit 2 reason `timeout`; a shorter cancellation (a superseded push) is not a unit, and a run whose own conclusion is `cancelled` is skipped before any job read.
- **Reads are bounded and oldest-first.** The probe lists runs created after the PR3a merge (up to 40 pages of 100 per event), reads jobs and logs for at most 250 runs per sweep oldest-first plus always the newest 10 `merge_group` runs, and prints `runs_listed=N units_read=M truncated=0|1`. A PASS certifies the earliest prefix of the LISTED runs plus the newest queue state. GitHub caps a run listing that carries a `created` or `event` filter at 1,000 results (measured 2026-10-28: exactly 1,000 `pull_request` runs, 551 of them `cancelled`, the oldest listed run created 2026-10-24T21:23Z although the window opened 2026-10-23T15:41Z), so beyond 1,000 runs the listing is the NEWEST 1,000 and the oldest-250 prefix MOVES forward as runs accumulate: evidence does not latch across sweeps, and the one sweep that sees every criterion is what closes the tracker. The probe is read-only and writes no tracker comment. Reads run four at a time (`SOAK_PARALLEL`, at most 8) inside a 300 s read budget (`SOAK_BUDGET_S`, at most 600; the per-PR facts loop has its own `SOAK_FACTS_BUDGET_S` allowance): the newest 10 `merge_group` runs are read first and are exempt, and past the budget the remaining oldest-first runs wait for the next sweep (`truncated=1`, `NOT YET`, never `CANNOT ESTABLISH`). The probe reads `rate_limit` first and exits 3 with `API quota (remaining, need, resets at)` when the planned reads do not fit the sweeper token's hourly allowance (about 1,000 requests per repository, shared): `need = ceil(1.5 x runs to read) + ceil(runs needing a commit lookup / 2) + 3 x PRs + 100`, which is about 856 for a shape of 260 runs and 81 PRs (the 2026-10-28 operator-token run of 156 units and 24 PRs planned 716 and spent 321) (the earlier 2 per run, 5 per PR and 200 reserve was calibrated to 4 PRs and would exceed the whole hourly allowance at about 80, a permanent exit 3); the weights rest on two days of measurements and the `planned=` figure on the `quota:` line is how they are shown wrong. A 403 or 429 stops further reads. A read that fails with a timeout or a 5xx is retried once after 2 s; a 403, 429, 404 or 422 is never retried, and nothing is retried while a 403 or 429 has been seen. Time arithmetic against the sweeper's 15 minute job limit (shared by every tracker, no per-probe timeout; a probe that overruns takes the whole night's sweep with it): the listing is about 25 s and is inside the 300 s read budget, which is a launch gate (reads already in flight finish, and a unit makes up to 4 serial reads); the per-PR facts phase has its own 180 s allowance (`SOAK_FACTS_BUDGET_S`) checked before each PR, and a PR's facts are a pull, up to 3 files pages and a timeline, i.e. up to 5 serial reads at about 2.4 s each (24 PRs took 58 s on 2026-10-28, so about 75 PRs fill the allowance); the baseline reads are about 3 s. Typical: roughly 300 s of reads plus up to 180 s of facts, about 480 s. A retry is skipped once the read and facts budgets are spent (`SECONDS - T0 >= SOAK_BUDGET_S + SOAK_FACTS_BUDGET_S`), but a read that hangs still costs up to 2 x 60 s + 2 s, so the worst case is the sum of those budgets plus the hung tail of the reads in flight, which is why a pathological GitHub outage can still run the job into its 15 minute limit. Progress is three `soak-progress:` phase lines on stderr (plus a heartbeat per 25 reads with `SOAK_PROGRESS=1`); stdout ends with a `quota: used_delta=N limit=N remaining=N planned=N` line, which is the real figure to read after the first nightly run (a `used_delta` above `planned`, or within 10% of it, means the weights are wrong). No API payload goes on a jq argument (one argument is capped at 131072 bytes; a files page with patch bodies is up to 1.1 MB): pages go to jq on stdin.
- **Forgery bound.** A `pull_request` run whose own `pull_requests` is empty (GitHub empties it once the PR merges, so for a merged PR it is empty on every run) is attributed to its PR by `commits/<sha>/pulls?per_page=2`, and only when exactly one PR of this repository comes back whose head ref is the run's branch (the PR's own `head.sha` is usually a later push and is not compared); an empty answer, HTTP 404 or 422, two PRs, a foreign repository or another head ref leaves the run unattributed, excluded and counted in `pr_unattributed_runs` on the status line, and any other failed lookup is exit 3. Only green plain units of this repository that are not canary branches spend a lookup. A fork PR (head repository not this repository) and a PR whose file list touches an oracle input never count towards the distinct-PR or composition criteria; the file list is read up to 3 pages and a longer one counts as oracle-touching and not docs-only. The exclusions and the docs-only, scripts, draft and bot facts are judged on the resolved PR's FINAL state (its file list and author), not on the tree a given run built, so a PR that reverted an oracle edit before merging is still counted: the same residual open PRs always had, now the common path. The evidence is still the PR job's own log, which its author controls, so closing #10865 does not authorize PR3b.
- **Cumulative shrink-only check.** The baseline is read through the contents API at the PR3a merge commit and at the main tip; every line present at the tip and absent at the merge commit is cumulative growth, and any growth is `NOT YET: baseline grew by <n> line(s) since the PR3a merge`. The baseline absent at the tip is the end state and fine; absent at the merge commit or an unreadable one is exit 3. Lines are compared as sets, so a moved line is not growth. Per-diff `grown` cannot see a PR that adds a pair and its baseline line and merges while the job is advisory: this check can.
- **Ceilings are PROVISIONAL.** 210 s and 270 s are the ruled numbers, but the only prior figures are a local mean of 203 s and one hosted run of 162 s (see the observation log above), so the series is a single point. The probe's failure text for the wall criterion ends "ceiling re-rule owed: bring the measured series to the CTO agent". The CTO agent re-rules the two constants (a dated row with the series and a code change of the two constants, nothing else) at the close of the window or at the 30-day trigger, whichever is first; the budget owner is involved only if the new ceiling raises spend beyond the stated 4,400 minutes a week.

Closing #10865 records that the window passed; it does **not** authorize PR3b (#10859), which waits for the budget owner and for the PR3b entry conditions of the ADR-276 amendment (item 9): a real oracle control (a code-owner-review ruleset, an `infra/github` change that is a hold for the budget owner, or the budget owner's written acceptance of the residual), a ruled accept-row growth design, the cumulative baseline check evaluated at PR3b merge time (`git diff <PR3a-merge-sha> origin/main -- scripts/ci-pr-affected-audit.baseline.tsv` has no added line), a ruled rename-carry design and the re-ruled ceilings. Record here, per PR3a: the first real run's marker line, its wall time, and the jobs-API result of the canary (a throwaway DRAFT PR with one deliberate unbaselined pair, closed with its branch deleted afterwards, excluded from the distinct-PR count), including the canary job duration (`completed_at` minus `started_at`, with the run URL), under the line "ceilings provisional; the only prior figure is local mean 203 s".

Observation log entries:


- 2026-10-23, first hosted run (PR #10851 head `9838619695`, run 39936463461, job 120357109670): `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=1886 baseline=1886`, job wall 162 s (10:04:45Z to 10:07:27Z; the ratchet step took 146 s), conclusion `success`. One datapoint, so the ceilings stay provisional.
- 2026-10-23, canary (throwaway DRAFT PR #10899, one deliberate unbaselined pair, closed with its branch deleted; run 39937846319, job 120361674562): the job concluded `failure` after 110 s wall (10:17:39Z to 10:19:29Z) with annotations `exit=1 reason=new-pair` and the `oracle-inputs-changed` warning; `gh pr checks` reported it as `fail`. The workflow run concluded `failure` too, but not because of this job alone: the draft-light `test` leg is red by design on a draft (ADR-276 Option R) and `e2e` failed on an unrelated `ERR_CONNECTION_REFUSED`, so the run-level effect of `continue-on-error` was not isolated. The canary is excluded from the distinct-PR count.
- 2026-10-28, probe fix (no evidence run was re-collected): the probe read each run's PR from the run's own `pull_requests` and dropped runs where it is empty as fork runs. GitHub empties it once the PR merges, so of the 151 successful `pull_request` runs in the 1,000 listed since the PR3a merge 135 named no PR (none were fork runs), and the oldest-250 prefix the probe reads was all merged PRs: the distinct-green-PR count was 0 by construction and the window could not certify. The probe now attributes such a run by its head commit (see the forgery bound), re-derives the planned-reads accounting and widens the facts allowance to 180 s, retries a transient read once, and no longer aborts on a sweep with no PR unit (`${#PR_EXCLUDED[@]}` of an empty associative array under bash 5.3). The same change enforces the drain restart in the probe (#10949): a first read of the `s4-drain` label list put the floor at the PR5 merge (2026-10-26T21:59:35Z), and the 30-day triggers stay on the PR3a merge.

### Rolling the ratchet back

Triggers: a defect verdict (a false red or false green), p95 wall over the ceiling after the first window, or a cost the owner of #10448 rejects; the decider is the owner of #10448. The repository squash-merges, so PR3a is ONE commit on main and the recipe is squash-shaped. Until PR4 lands PR3a is independently revertible:

1. First remove the `follow-through` label and the directive from #10865 (or close it with a withdrawal comment), so the sweeper never runs a probe whose file is gone.
2. `git revert <squash-sha>` (single parent, no `-m`) on a branch. It removes the job, the pins (`ALWAYS_RUN_JOBS`, `UNGATED_PINNED`, `LIGHT_PINNED`), the fan-out ledger row (28 back to 27), the subcommand, the follow-through probe and its rows, the baseline and this section, and also the ADR-276 amendment.
3. `git checkout <squash-sha> -- knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`, then append a dated one-line withdrawal note (ADR-276 is append-only; the revert would otherwise delete the amendment and the record of the decision).
4. Update the bodies of #10859 and #10861.

Receipt: the revert was simulated on 2026-10-22 in a scratch detached worktree in the PER-COMMIT shape (`git revert --no-commit` of the five PR3a code commits), and the replay suite, `scripts/ci-push-dedupe.test.sh` and `scripts/ci-draft-light.test.sh` all passed on the reverted tree. It was NOT simulated in the squash shape above, and the per-commit simulation omitted the follow-through probe; repeat the check in the squash shape (squash the branch onto main, `git revert` it, restore the ADR file as in step 3, run the same three suites) before relying on this recipe, and record the date, tree and results here as "simulated in the squash shape". After PR4 lands, withdrawal is a forward PR that deletes the job, the subcommand and the baseline together (a revert would be a modify/delete conflict on the baseline file). After PR3b it is a ruleset event, covered by PR3b's own plan, including a break-glass path for a required check that no longer reports.

## Rollback

The receipts and tooling can be deleted with no effect on any workflow. The lever's off switch is deleting the repository
variable; while the variable is absent the dark job is skipped and costs 0 billed minutes.
