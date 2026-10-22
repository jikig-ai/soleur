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

The audit exits 1 on `main` today (a baseline of 1,884 gap pairs over 294 suites on the tree PR3a measured), so a check that simply required the audit to pass could never
be green. `python3 -I scripts/ci-pr-affected-replay.py ratchet` is the audit as a **ratchet**: the live set of `(suite, undeclared tracked path)` pairs, after the `--accept`
exemptions, must EQUAL the committed shrink-only baseline `scripts/ci-pr-affected-audit.baseline.tsv`, and the baseline may only lose pairs against its base. Its contract
(exit codes, the order of the checks, the baseline-state table, the formats) is the RATCHET section of `python3 scripts/ci-pr-affected-replay.py --help`; this section is how to
operate it. What a green ratchet means is the one wording of section 4: literal-name completeness over what the audit reads, necessary but not sufficient.

### The dark phase

Until PR3b (#10859) the job `affected-index-ratchet` in `.github/workflows/ci.yml` is **advisory**: job-level `continue-on-error: true`, absent from `scripts/required-checks.txt`, the
canonical ruleset JSON and `infra/github`, and it runs on `pull_request` and `merge_group` only (never on push, so it cannot red the `CI` run that `web-platform-release.yml`
reads before a deploy). It costs about 3 billed minutes per PR and queue run, docs-only PRs included (ceiling 210 s p95 wall, `timeout-minutes: 5`). How to read a run:

- the **marker line** in the job log, the last line the script prints: `SOLEUR_PR_AFFECTED_RATCHET exit=<0|1|2> reason=<token> live=<n> baseline=<n>`;
- the **annotation** the workflow step emits from the exit code, `::error title=affected-index-ratchet::exit=<1|2> reason=<token>` (a non-success run with no annotation counts as exit 2);
- the job summary, which carries the full uncapped failure text (the log prints the first 25 entries of each class and a count);
- the jobs API, `.jobs[] | select(.name == "affected-index-ratchet")` for `conclusion`, `started_at` and `completed_at`. How a failing job-level `continue-on-error` job is reported there is
  settled by the throwaway canary of PR3a (record the result in the observation log below); until then read the marker line, not the conclusion alone.

`oracle-inputs-changed: <files>` in the output (also a `::warning` and a summary line) is a **non-blocking** notice that this diff touches the check's own oracle: `.github/workflows/ci.yml`,
`scripts/ci-pr-affected-replay.py` or the baseline. Review it as the oracle: run `git show HEAD^1:scripts/ci-pr-affected-replay.py` on the PR tree and compare the verdicts of the base copy and
the PR copy on the same tree (the check does not run the base copy as the gate, because a PR that legitimately changes the script would then be unmergeable).

| Exit | Reason token | What it means | What to do |
|---|---|---|---|
| 0 | `pass` | live equals the baseline and every other check holds | nothing |
| 1 | `new-pair` | a suite names a tracked path that is not declared, not accepted and not in the baseline | declare or accept it (below); never add a baseline line |
| 1 | `baseline-deleted` | the baseline file was deleted while pairs are still live | restore it from main; only the strict-zero end state (nothing live) may delete it |
| 1 | `stale-line` | a baseline line is no longer live (the suite or the path changed), or the file is malformed or holds conflict markers | delete the line the output prints; see the baseline-conflict recipe |
| 1 | `baseline-dup`, `baseline-order` | a duplicate line, or the file is not C-locale sorted with a final newline | take main's copy, then the recipe below |
| 1 | `grown` | the head baseline has a line the base does not (a new suite, or one pair swapped for another) | remove it: a baseline can only lose lines against its base |
| 1 | `unaudited` | the audit could not read the suite in full | fix the selector row or make its inputs readable |
| 1 | `star-row`, `stale-accept` | an accept row for a readable suite as a whole, or an accept row the tree no longer backs, or a malformed accept file | delete or correct the accept row |
| 2 | `floor-*`, `selector-failed`, `selector-timeout` | infrastructure: the selector failed, hung, fell back, printed a short, extra or inconsistent output, or the census read nothing | re-run the job; a reproduction on the same SHA is a defect: report it on #10448 |
| 2 | `base-unresolved` | `HEAD^1` does not resolve (a root commit or a shallow clone) | fetch more history (the job uses `fetch-depth: 2`) |
| 2 | `baseline-unreadable`, `internal` | the baseline or accept file could not be read, or a helper (`plugins/soleur/scripts/lint-ratchet.py`) is missing or raised | re-run; a reproduction is a defect |

A re-run of a failed `pull_request` job reuses the old merge SHA, so after a push or a rebase let the new run decide; a PR with a merge conflict has no run at all (resolve the conflict first).

### Ratchet red on a PR or queue entry

The failure text names the suite, the path and the referencing `file:line`, then one of three causes: your change **added the file** the suite names; your change **edited the suite** (or a file it
reads); or it touched **neither** (main moved, or an edge or accept row that covered the pair was removed: rebase, then declare or accept). Then there are exactly two remedies, and the decision between them is the point:

1. **Declare the path** in `AFFECTED_<LABEL>_PATHS` in `scripts/lib/test-affected-paths.sh`, only when the suite really reads or executes the file (that is what the selector must know to select the suite). Editing that file is a runner trigger and runs the full battery once.
2. **Add an anchor-keyed accept row** to `scripts/ci-pr-affected-audit.accept.tsv` (`suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>`; the anchor and ordinal are on the `ref` line of the failure text and in `audit --all-refs`) only when the suite merely names the file: a message, a fixture it writes into a scratch tree, a negative-test string. The reason names the line kind. **An accept row on a file the suite really reads is a false negative that becomes live once the lever flips**, so a reviewer blocks it.

A baseline row cannot be added: the failure text offers no way to, `ratchet --print-baseline` only removes pairs once a baseline exists, and the growth rule refuses any line the base does not have. Until PR4
drains the 1,884 baselined pairs, **a PR that adds a new path mention to a suite fails the ratchet and must declare an edge** (or add an accept row for a mention) in the same PR.

A rename or move of a path a baselined suite names reads as a new pair (growth, exit 1): a rename of a baselined path or suite is a **drain-class PR**. Declare or accept the renamed pairs first, then rename, or rename in the same PR with every renamed pair declared or accepted.
While the job is advisory a red on such a rename is expected and is noted in the PR; rename-carry (an exact one-to-one rename of a pair already in the base baseline) is a PR3b entry condition, not built.

A PR that **widens the audit's reach** (the REACH section of the script) may land only in the same PR that drains every pair it reveals: zero baseline pairs added, nothing undeclared revealed. A baseline re-base is forbidden (it would turn the ratchet into a ledger that can be reset).
If the reveal is too large the widening lands dark (code present behind an off-by-default option the ratchet job does not pass) and the PR that drains the revealed pairs turns the option on in the same commit. Every reach change needs a reach-differential receipt like PR1b's. A widening PR with a non-empty reveal is red by design.

### Ratchet red because main moved

A new pair that landed on main (another PR's suite, merged while this one was open) turns later runs red with nobody forced to repair it. The repair owner is the **author who introduced the pair**; the owner of #10448 is the fallback
when the author is a bot or unreachable. The fix-forward is a declare, accept or prune PR that never adds a baseline line, due within **one working day**. While the job has no push run, "main is red" means the latest `merge_group` conclusion of the job on the main tip.
`ratchet --print-baseline` is prune-only: it removes lines that are no longer live and never adds one. In PR3a, where the base has no baseline, deleting the baseline file first and regenerating is legitimate (adoption absorbs it); after PR3a merges it is not.

### The baseline-conflict recipe

When the baseline file conflicts on a rebase (or holds conflict markers, a duplicate, or an order problem), never hand-resolve it by taking either side. Take main's copy of the file, then prune it with the tool and re-check. Do not redirect straight onto the file (the shell truncates it before the tool reads it):

```bash
git checkout origin/main -- scripts/ci-pr-affected-audit.baseline.tsv
python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > scripts/ci-pr-affected-audit.baseline.tsv.new \
  && mv scripts/ci-pr-affected-audit.baseline.tsv.new scripts/ci-pr-affected-audit.baseline.tsv
python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main     # on a developer checkout pass the base: HEAD^1 is only the previous local commit
```

If the pruned file is still not equal to the live set, the difference is a new pair: declare it or accept it (above).

### The drain claim

PR4 (#10860) and PR5 (#10861) shrink the baseline in the same commit as the edge or accept edit, so the live set and the baseline move together. Only one drain PR is open at a time: the claim is the label `s4-drain` on one open DRAFT PR plus a mirror
comment on #10448 (`gh pr list --label s4-drain --state open` must be empty before a second is started). A second PR rebases and regenerates with the prune-only `--print-baseline` until the diff to main is empty, never by hand. A drain PR merged inside the PR3b observation window
restarts the window count (it changes the baseline, the live set and the runner oracle): the default order is PR3a, the window, PR3b, PR4.

### The observation log

The window that PR3b waits for is enforced by the follow-through probe `scripts/followthroughs/ratchet-observation-window-10865.sh` (tracker #10865): at least 3 `pull_request` runs from 3 distinct PRs (one touching `scripts/` or a suite file) and 3 `merge_group` runs on distinct SHAs, every one
`exit=0 reason=pass`, p95 wall at most 210 s and maximum at most 270 s; one docs-only PR, one draft PR and one bot PR when one occurs. A genuine `exit=1` pauses nothing by itself; a red latest `merge_group` run pauses the window until it is repaired; an exit 2 is classified by a same-SHA rerun with no code change
(passes: an incident, excluded; reproduces: a defect, the window restarts). Closing #10865 records that the window passed; it does **not** authorize PR3b, which waits for the budget owner. Record here, per PR3a: the first real run's marker line, its wall time, and the jobs-API result of the canary (a throwaway DRAFT PR with one deliberate unbaselined pair, closed with its branch deleted afterwards, excluded from the distinct-PR count).

### Rolling the ratchet back

Triggers: a defect verdict (a false red or false green), p95 wall over the ceiling after the first window, or a cost the owner of #10448 rejects; the decider is the owner of #10448. Until PR4 lands PR3a is independently revertible: `git revert` removes the job, the pins (`ALWAYS_RUN_JOBS`, `UNGATED_PINNED`, `LIGHT_PINNED`), the fan-out ledger row (28 back to 27), the subcommand, the baseline and this section together; simulate it first in a scratch detached worktree (`git revert --no-commit` of the PR3a commits, then the replay suite,
`scripts/ci-push-dedupe.test.sh` and `scripts/ci-draft-light.test.sh` must stay green). The ADR amendment stays (it is append-only) and gains a one-line dated note that the ratchet was withdrawn. After PR4 lands, withdrawal is a forward PR that deletes the job, the subcommand and the baseline together (a revert would be a modify/delete conflict on the baseline file). After PR3b it is a ruleset event, covered by PR3b's own plan, including a break-glass path for a required check that no longer reports.

## Rollback

The receipts and tooling can be deleted with no effect on any workflow. The lever's off switch is deleting the repository
variable; while the variable is absent the dark job is skipped and costs 0 billed minutes.
