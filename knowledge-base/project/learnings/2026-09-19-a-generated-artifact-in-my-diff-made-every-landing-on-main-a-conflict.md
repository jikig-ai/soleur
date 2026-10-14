---
title: "A generated artifact in my diff made every landing on main a conflict, and DIRTY is not BEHIND for the admin-merge hatch"
date: 2026-09-19
category: workflow-patterns
module: plugins/soleur/skills/ship
tags: [ship, merge-queue, dirty-vs-behind, generated-artifacts, rule-metrics, adr-ordinal-collision, sharp-edges-extraction, rename-guard, canary-sandbox, bwrap, monitor-hygiene, repo-global-guards, admin-merge]
issue: 8302
pr: 8301
---

# Learning: a PR that carries a regenerated file every sibling PR also regenerates cannot stay mergeable, and only BEHIND — never DIRTY — is admin-mergeable

## Problem

PR #8301 was ready to merge at 17:30 and merged at 02:16 — nine hours, twenty
Monitor rounds, six head changes. Two required checks were genuinely red at the
start, both in the PR's own new suites; every hour after that was spent
re-syncing `main` into the branch, and each sync restarted a CI cycle that the
hosted-runner backlog stretched to 45–60 minutes — longer than the interval
between sibling PRs landing on `main`. The operator authorised "admin merge if
BEHIND and CI green" halfway through; the PR spent the next three hours DIRTY
instead, which that authorisation cannot act on.

## What was measured, in the order it changed the work

**Both red required checks were in this PR's own surface and invisible to a
file-selected suite set** (the class `work/SKILL.md` already names). (a)
`plugins/soleur/test/fixture-dir-operand-assert.test.sh` reported 70 assertions
against a floor of 71: my three new suites each carried an inline
`assert_fixture_dir` whose body had drifted from the canonical one in
`plugins/soleur/test/test-helpers.sh`, and the guard compares every copy in the
tree byte-for-byte with comments stripped. The drifted body's extra "inside
`$TMP_ROOT`" arm was vacuous — every call site passed `$TMP_ROOT` itself — so
replacing it with canon verbatim lost nothing. (b)
`tests/scripts/test-rule-metrics-aggregate.sh` T7 asserted the pre-#8302 contract
("the try/catch on `fromdateiso8601` rescues a malformed timestamp"); the new
closed-alphabet gate on `timestamp` drops such a row, it was the fixture's ONLY
row, so the aggregator no-oped (#6042) and wrote no file. The rewrite keeps T7's
real property — one bad row must not abort the run or swallow its neighbours —
by seeding a well-formed row beside it and asserting the drop is OBSERVABLE
(`Dropped 1 malformed line(s)`), because a silent drop and a counted event are
indistinguishable in the output file alone. Neither reproduced from the
diff-derived selection; both reproduced locally in under five minutes once the
CI log named the suite. The log itself: `gh run view --log-failed` refuses while
the run is in progress, but `gh api repos/{owner}/{repo}/actions/jobs/<id>/logs
--allow-escape-sequences` serves it immediately, and
`SCRIPTS_SHARD=k/N bash scripts/test-all.sh --enumerate scripts` answers which
shard a suite lives in without leaving the shell.

**`rename-guard` fired correctly on the extraction, and the label was the right
override.** `plan/SKILL.md` is scanned by every gitleaks rule;
`skills/*/references/*.md` is allowlisted both globally and per rule, so moving
151 KB from the first to the second widens the exemption scope — not the
archive-kb subset shape the guard exempts. Before overriding I copied the
destination file OUTSIDE the repo and scanned it as a non-allowlisted path with
the repo's own `.gitleaks.toml` under the CI-pinned gitleaks 8.24.2: `no leaks
found`. The `secret-scan-allow-rename` label re-runs only the secret-scan
workflow via the `labeled` event (the runbook's operator note), leaving the ~60
green checks on the head valid; a trailer would have needed a new head and a
full re-run. The scan evidence went into a PR comment so the override is
auditable.

**The PR was DIRTY on every landing to `main` because it carried a regenerated
`knowledge-base/project/rule-metrics.json`.** Measured: 20 of the last 20 merges
to `main` touched that file — compound is its local producer (ADR-091), so every
PR that ran compound regenerates it. Each landing → DIRTY → sync → CI restart →
next landing. Three cycles in four hours before the cause was named, and the
cause was named only by asking "which file conflicts, and how often does `main`
touch it?" rather than resolving the conflict a fourth time. Remedy: take
`main`'s copy so the PR no longer diffs the generated file at all (AC21 still
held on `main`'s copy: 98 rules, 0 retirement rows) — the widened aggregator is
the deliverable, and the next compound run on `main` regenerates the aggregate
through it. After that change, `main`'s churn on the file made the PR merely
BEHIND.

**DIRTY ≠ BEHIND for the admin-merge hatch.** `gh pr merge --admin` bypasses
`required_status_checks` and the strict up-to-date rule; it does not bypass a
merge conflict. So the operator's "admin merge if BEHIND and CI green" is only
reachable once the PR's diff has no file that `main` rewrites every merge. The
poll's hatch became: on BEHIND, HOLD (do not re-sync — a sync restarts CI and
re-opens the window) until every required context is SUCCESS on the current
head, then admin-merge. A second thing was measured twice on the way: GitHub
reported `CONFLICTING`/`DIRTY` while `git merge-tree --write-tree origin/main
HEAD` was CLEAN locally, with and without rename detection. The final
`gh pr merge --squash --admin` then SUCCEEDED (the repo's pre-merge hook synced
and pushed first). The mechanism, found while shipping this learning's own PR:
both sides had touched `knowledge-base/INDEX.md`, which `.gitattributes` gives
the custom `kb-index` merge driver — local git runs it and merges cleanly,
GitHub's server-side merge cannot and reports a real conflict. Reproduced by
disabling the driver locally (`git -c merge.kb-index.driver=false merge-tree`
conflicts on exactly that file). So a DIRTY that is clean locally is cured by a
local sync and push — `gh pr merge` triggers `pre-merge-rebase.sh`, which does
that — never by a resolver.

**The ADR ordinal collided at ship exactly as the brief predicted.** #8248 landed
its ADR-225 on `main` during the merge queue, three syncs in; 226/227/228 were
claimed by open PRs #8300/#8320/#8297, so the ADR shipped as ADR-229. The sweep
was scoped to `git diff --name-only origin/main...HEAD` (43 replacements, 17
files), lines citing `main`'s ADR-225 were excluded, and the FOUR sentences that
were claims ABOUT the ordinal — plan §ADR ordinal, the plan's risk row, tasks
8.3, the learning's session-error entry — were kept at ADR-225 with an appended
superseded note instead of being rewritten (a rewritten "ADR-229 free across 90
refs" would have been a false sentence). The PR body was swept too, because the
"PR body citing files not in diff" check would fail on the old filename. Every
subsequent sync in the poll re-ran `scripts/check-adr-ordinals.sh` before
pushing.

**The extraction conflicts on every Sharp Edges addition to `main`.** Three PRs
(#8275, #8270, #8276) added bullets to the OLD location in `plan/SKILL.md` while
this PR was open. Resolution each time: keep ours in `SKILL.md`, port `main`'s
PURE ADDITIONS (every added line begins `- **`; refuse if `main` removed or
edited a line) into `references/plan-sharp-edges.md` at the same anchor.
Automated in the poll after the second occurrence; the first automation kept a
bare `+` diff line as an empty "addition" because it filtered on `l.strip()`
instead of `l[1:].strip()`, and the assertion caught it before anything was
written.

**The first deploy-arm run rolled back on the bwrap canary probe, and for the
first time the instrumentation named the class.** The journald line — read with
`scripts/betterstack-query.sh` under `prd_terraform`, the runbook's only no-SSH
path — was `rc=137 ms=79 cstate=running err_chars=0 bwrap_err="<empty>"`: the
post-mortem's H3 "signalled child", discriminable from `rc=1` + message (bwrap's
own refusal) and from `cstate=exited` (the container was gone). The three
deploys immediately before (v0.277.0, v0.277.1, v0.278.0) passed the same probe;
this PR touched nothing under `apps/web-platform`. `gh run rerun <id> --failed`
re-ran only `deploy`; it passed, `live-verify` passed, and `/health` reported
the merge SHA. Production had rolled back cleanly to v0.278.0 in between.

## Solution

1. Before the first Phase 7 sync, list the files this PR diffs that `main` has
   rewritten in most of its recent merges (`git log origin/main -20 --name-only`
   intersected with `git diff --name-only origin/main...HEAD`). A generated
   artifact on that list leaves the PR (take `main`'s copy) unless the PR's
   deliverable IS that artifact's content.
2. On BEHIND with every required context green, admin-merge (when authorised)
   instead of syncing; on DIRTY, name the conflicting file before resolving it.
3. Re-run `check-adr-ordinals.sh` after every sync, not once at ship start.
4. When a repo-global guard reds a new suite, reproduce with the guard's own
   suite locally; the diff-derived selection cannot return it.

## Key Insight

A long-lived PR is unmergeable in proportion to how many of its files `main`
rewrites per merge. A generated artifact with one producer per PR has a rewrite
rate of one per merge, so carrying it guarantees a conflict on every landing,
and a conflict is the one state the admin-merge hatch cannot cross. The fix is
not a better resolver — it is not diffing the file.

## Session Errors

1. **The first merge-poll Monitor `cd`'d into the feature worktree** despite the standing constraint. Recovery: harmless here because the poll exits on MERGED before `cleanup-merged` runs, but the constraint exists for the session that does not. **Prevention:** the poll's shell lives in the main checkout or `/var/tmp`; the sync step uses `git -C <worktree>`.
2. **`sleep 25 && gh …` was blocked by the harness.** Recovery: re-armed a Monitor. **Prevention:** a wait is a Monitor with an until-loop, never a chained `sleep`.
3. **Two required checks red in the PR's own new suites** (`assert_fixture_dir` drift; legacy T7 on a superseded contract), invisible to the file-selected suite set. Recovery: fixed both, verified all three `test-scripts` shards green on `9c09b77fb` before the next sync. **Prevention:** when a PR adds a suite, run `fixture-dir-operand-assert.test.sh` and every sibling suite of the script it touches, not only the suites that reference the diff.
4. **`rename-guard` red on the extraction.** Recovery: out-of-tree gitleaks scan of the destination as a non-allowlisted path, then the label override with the evidence in a PR comment. **Prevention:** a `git mv`/extraction into `references/` is an exemption widening by construction — scan the destination as unallowlisted before pushing and write the evidence into the PR body.
5. **Three Sharp Edges conflicts; the first automated port kept a bare `+` line.** Recovery: filter on `l[1:].strip()`; the assertion had refused the bad list. **Prevention:** when extracting a section that sibling PRs append to, expect a conflict per sibling until they rebase; port pure additions, refuse edits.
6. **A regenerated `rule-metrics.json` in the diff made every landing DIRTY** — three cycles, ~4 h, before the cause was named. Recovery: took `main`'s copy; the PR no longer diffs it. **Prevention:** the intersection check in Solution step 1, before the first sync.
7. **ADR-225 taken by #8248 during the queue.** Recovery: renumbered to ADR-229 with a diff-scoped sweep and superseded notes on the four ordinal claims. **Prevention:** `check-adr-ordinals.sh` after every sync in the poll (now in the resolver).
8. **GitHub reported CONFLICTING while local `merge-tree` was clean, twice.** Recovery: `gh pr merge --admin` succeeded — with the repo's pre-merge hook syncing `main` in and pushing first. Cause, measured on this learning's own PR: the `kb-index` custom merge driver on `knowledge-base/INDEX.md` runs locally and not on GitHub. **Prevention:** on a DIRTY that does not reproduce locally, check whether `INDEX.md` is in both diffs; if so, sync locally (the driver resolves it) and push — `gh pr merge` runs that sync through the hook.
9. **Two duplicate poll Monitors (rounds 6 and 11)** were armed while the prior one was still alive; the supersede hook also lists expired monitors as live, and `TaskStop` on those returns "No task found". Recovery: stopped the live duplicates by hand. **Prevention:** `TaskStop` the previous round before re-arming unless its expiry notice has arrived; treat the hook's list as "possibly live", not "live".
10. **The first deploy-arm run rolled back on the bwrap probe (H3, rc=137).** Recovery: `gh run rerun --failed`; deploy, live-verify and `/health` green. **Prevention:** none needed for the probe — the rerun is the documented path; read the `ci-deploy` journald line via `betterstack-query.sh` before rerunning so the class is named, not assumed.
11. **The hosted-runner backlog (26–28 pending runs repo-wide) made each CI cycle 45–60 min**, so six head changes cost about six hours of wall clock. Recovery: none available. **Prevention:** minimise head changes — items 6 and 8 above are the two that were avoidable.

## Related

- `plugins/soleur/skills/ship/SKILL.md` Phase 7 — "DIRTY exit", "ADR-ordinal collision after a sync", "Settle-then-admin-merge escape hatch"
- `knowledge-base/engineering/operations/post-mortems/bwrap-deploy-gate-undiagnosable-rollback-postmortem.md` (H3 row) and `runbooks/canary-probe-set.md`
- `knowledge-base/engineering/operations/secret-scanning.md` §Rename-laundering
- `knowledge-base/project/learnings/workflow-issues/2026-08-03-blanket-renumber-rewrote-other-work-and-a-count-certified-it.md`
- `knowledge-base/project/learnings/2026-09-18-every-p1-lived-in-a-guard-i-added-and-two-fixes-reintroduced-their-class.md` (the review round of the same PR)
- ADR-091 (compound is the local producer of `rule-metrics.json`), ADR-229
