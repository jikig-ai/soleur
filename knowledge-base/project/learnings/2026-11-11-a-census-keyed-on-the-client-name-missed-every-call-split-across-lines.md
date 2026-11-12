---
title: A census keyed on the client name missed every call split across lines
date: 2026-11-11
category: test-failures
module: plugins/soleur/test/sole-copy-drift-check.test.sh
tags: [census-guard, argv-bearer, mutation-testing, unpinned-wire, review]
issues: [12616, 10274, 12697]
pr: 12645
---

# Learning: a census keyed on the client name missed every call split across lines

## Problem

PR #12645 (#12616) added row N3b, a census over every line of runbook 6894 and `postmerge/SKILL.md`. Each line that
looks like a Hetzner bearer call must equal one of two pinned stdin-header texts. The predicates were pairs of words
that had to share one physical line: `curl` with a token name or `Authorization`, a token name with `Authorization`,
and `curl` with `api.hetzner.cloud`. The PR's own mutation battery (H18) was green, and the suite reported 286/286.

Four review seats, working independently, then put the read-only token back on argv without turning the suite red:

- a curl split over `\` continuations, with the URL alone on its last line (security, architecture);
- an httpie or xh one-liner ending `# expect 404`, which N1's exemption also skips (test-design, security);
- an `-H "Authorization: Bearer …"` appended to the shared builder `RB_HDR` and to every copy at once, so the
  copies still equal the builders (test-design);
- `_n3b=""` or `_n1=""` in place of the call, because both rows passed on empty output (test-design).

## Solution

- **Anchor the predicate on the token every real call must carry, not on the client's name.** p3 became
  `index(l, "api.hetzner.cloud")` on any line. On today's files only the three pinned lines contain the host, so the
  census did not change. The literal-URL escapes all closed with that one predicate. What remains is a URL held in a
  variable together with a renamed token, and the plan's limit 5 now says exactly that.
- **Check the property, not only equality to the builder.** `n3b_builder` requires `Authorization` exactly once,
  inside the `printf` header, and no argv credential flag after `| curl`.
- **Pin the wire, not the helper.** The first H18 row for the builder check called `n3b_builder` directly. Deleting
  the call inside `n3b` still left 286/286. The row now overrides `RB_HDR` in a subshell and runs `n3b` itself.
- **Make "ran and found nothing" distinguishable from "never ran".** `n3b_census` prints a `seen <file>: D=<n> R=<n>`
  line and `n1_rb` a `set: [...]` line. Each row requires that exact positive output, and the H18 helpers filter it out.
- **Give the judge helpers an instrument control.** H-c calls each helper once on an input it must fail and once on
  an input it must pass, inside a subshell.

Each guard was checked by a mutation battery on sandbox copies. The control passed 286/286, and all ten mutants went
red. The first battery missed one (builder call removed: 286/286), which is how the unpinned wire was found.

## Key Insight

A line-local census predicate names the shapes its author expected (`curl`, `Authorization`), so any reformatting
or substitute client gets past it. Key the predicate on the one thing no real call can omit: the API host. Then a
mutation-proof is still only as good as its row. A row that calls a helper directly proves the helper works, not that
anything calls it. Drive every row through the entry point the real check uses.

## Session Errors

1. **The code-quality review seat stopped on the weekly API rate limit and produced no report.** Recovery: the panel
   proceeded with 9 of 10 seats, and the trailer records `Reviewed-Coverage: degraded 9/10`. Prevention: already covered,
   because `emit-review-trailer.sh --agents-missing` makes the gap visible.
2. **The builder check's call site was unpinned** (the builder-call-removed mutant stayed at 286/286). Recovery: g1r14
   drives `n3b` with an overridden `RB_HDR`. Prevention: review's "both endpoints can be pinned while the wire between
   them is not" rule already names this. The fix is to apply it while writing the row, not after the battery.
3. **I attributed the CI `test` red to a weight-budget shard before reading the job list, then to the wrong upstream
   job.** The shard jobs were `skipped` because the PR was a draft (they are gated on `draft-light`). The separate
   `lint-bot-statuses` red (`readme-counts`, red on main) gates nothing, yet the first correction blamed the skips on it.
   A fix-round review caught that: no job lists `lint-bot-statuses` in `needs:`. Recovery: corrected the PR comment and
   the diagnosis bullet. Prevention: the bullet in `ship/references/ci-run-diagnosis.md` now says to read each skipped
   shard's `needs:` before naming a cause.
4. **A `sed` re-enable step in the mutation harness dropped the run ids,** so the run started with shifted arguments.
   Recovery: stopped it with TaskStop and removed the sandboxes. Prevention: one-off; edit a harness with an anchored
   whole-line replacement and `grep` the result before running it.
5. **A hook blocked `pkill -f` (it matches its own wrapper).** Recovery: a `/proc/<pid>/cwd` scan. Prevention: already
   hook-enforced.
6. **A Python edit's uniqueness assert found two `rep()` definitions,** and `mk()` quoting gave a SyntaxError on two
   mutants. Recovery: re-anchored, and moved those mutants to standalone `.py` files. Prevention: one-off; for
   multi-line or quote-heavy edits, write the edit as a file rather than as a shell-quoted string.
7. **The control "mutant" was a no-op and reported DID-NOT-LAND.** Recovery: the control became a comment insert.
   Prevention: one-off.
8. **I used `$_RB6894_N` before defining it.** Recovery: a grep caught it before any run. Prevention: one-off; under
   `set -u` the suite would have aborted anyway.
9. **The GitHub job-log API returned 502s.** Recovery: reproduced `readme-counts` locally, on the branch and on
   `origin/main`. Prevention: one-off.
10. **The structural seat's transcript ended on a tool call, and `jq -s` failed on null content.** Recovery:
    line-wise `jq -rR 'fromjson? …'`, then a SendMessage asking the seat to reply. Prevention: one-off.
11. **The stop hook blocked turns that ended on a first-person commitment.** Recovery: each wait now ends on a single
    `Paused:` line. Prevention: already hook-enforced.
12. **A suite file was edited while a run was in progress** (Work phase). Recovery: re-ran clean. Prevention: already a
    standing practice; never edit while a run is in flight.
13. **Forwarded from the plan phase:**
    - markdownlint MD038;
    - `printf "$w"` failing on `%{`;
    - a stale-read Edit refusal;
    - two wrong plan claims;
    - deepen-plan ran a subset of agents (disclosed);
    - a technical-ruling-gate shape error on row 8e.

    Recovery: each was fixed in its phase. Prevention: one-off or already covered.
14. **`lint-infra-no-human-steps.py` full-scan exits 1 on findings already on main.** Recovery: used CI's `--changed`
    form. Prevention: one-off for this PR. The full-scan findings are pre-existing and outside this diff.

Errors 15 to 18 happened after this learning was first written (fix rounds, ship and post-merge of PR #12645), and
were captured on 2026-11-12.

15. **A review-fix commit (`e6b87fc971`, the night before ready) added a `producer | grep -q` row to
    `sole-copy-drift-check.test.sh`, and the ready run's CI (run 43171768988) was the first thing to fail on it** in
    `.claude/hooks/grep-q-pipe-guard.test.sh`. That guard is in the pre-ready list of `ship/references/ready-run-wait.md`,
    and an `--affected` run selects it for any changed plugin shell file, so either would have caught the row; neither
    did on that head before ready. Recovery: `4e474c89e0` rewrote the row as `grep -q . < <(…)` (process substitution,
    the form the guard itself suggests). Prevention: run the pre-ready list on the head you ready, after the last
    review-fix commit (bullet added to `ready-run-wait.md`). The guard sweeps every extension in its `SWEEP_EXTS`, not
    only test files. Related: `2026-11-11-a-deferred-battery-and-a-draft-light-ci-left-the-repo-wide-guards-for-the-ready-run.md`
    and `2026-10-01-a-grep-q-in-a-pipefail-chain-made-the-trigger-miss-its-own-bug-class.md`.
16. **Closing a just-filed follow-up on GitHub did not clear the net-issue-flow gate.** `net-issue-flow.sh` lists
    issues with `--state all`, so a filed issue counts whether it is open or closed. `CLOSING` is read only from
    `Closes #N` keywords in the PR body, and the mandated-filing exemption needs the issue OPEN, so closing a filing
    can raise `NET`. Recovery: added the `<!-- gate-override: net-issue-flow -->` marker with a one-line justification
    per filed issue. Prevention: when a filing qualifies for one of the gate's two exits, write the override and its
    justification line when you file, not at ship time (sentence added to `review/SKILL.md` §5). A review finding
    qualifies for neither; fix it inline.
17. **`ship-kb-archive-gate.sh` denied `gh pr merge <N> --match-head-commit <sha>`** with "extra operands alongside
    --match-head-commit". Recovery: re-issued as `gh pr merge --match-head-commit <sha>` (no PR number), from the PR's
    own branch checkout. Prevention: none in the skills yet; #12697 tracks the fix. Dropping the number is a recovery,
    not a rule. `pre-merge-rebase.sh` needs a bare number right after `gh pr merge`. Without it the hook cannot name the
    PR: it reads review evidence from the session's own checkout, can sync and push the session's branch, and skips its
    merge-queue checks (`main` has a merge queue). `gh` also cannot infer the PR from the detached worktree that
    `settle-then-admin-merge.md` uses. Until #12697 lands, use the unnumbered form only from the PR's own branch
    checkout, with no `cd` inside the command and the branch already current with `main`. An earlier session took the
    other exit, a bare `gh pr merge <N>` without the sha pin
    (`2026-10-31-the-rehearsal-flipped-with-its-own-safety-control-off-and-its-success-signal-never-reached-the-sink.md`).
18. **`deploy-arm.sh find --wait` ran as a foreground Bash call and was killed at the 600 s Bash timeout** (it polls
    about once a minute for up to 120 polls, so it can wait about two hours). Recovery: re-armed it under the Monitor
    tool, matching `^ARM=`. Prevention: `postmerge/SKILL.md` Phase 3 (the `deploy-arm.sh find` paragraph) already says
    Monitor; it now also says why a foreground call cannot work.

## Tags

category: test-failures
module: plugins/soleur/test/sole-copy-drift-check.test.sh
