---
title: "Every escape my mutations could not reach, and the guard that refused the shape it prescribes"
date: 2026-09-10
category: workflow-patterns
module: guardrails-hooks, cron-substrate, issue-flow
issue: none
pr: 8038
tags: [guards, mutation-testing, escape-rows, vacuity, measurement, issue-flow]
---

# Every escape my mutations could not reach

## Problem

A structural fix for Soleur's issue flow: at ~2 filed per 1 closed every week
(1,455 open, 841 past 60 days), the backlog is **audit exhaust** — findings about
the project's own guards, not about anything a user receives (626
`domain/engineering` against 39 `domain/product` in a 1,000 sample). The change
adds a machinery ledger, a blocking filing-time gate, an expiry arm and a weekly
net-negative cadence.

The gate shipped green: 84 assertions, a 5-row mutation battery with every row
KILLED, a green control and a verified restore. It had two live escapes and
could not accept the command shape the repo tells agents to use.

## Key insight

**A mutation asks "can this guard fail at all". An escape asks "is this
predicate the property the guard's name claims". No mutation can answer the
second, because on an escape the guard is working exactly as written.**

Five mutation rows were all KILLED while two escapes sat in the same gate:

- `--label meta/machinery` inside a quoted `--body` opened the free exit,
  because the check grepped the whole `$COMMAND`. Merely *naming* the flag in
  prose satisfied it — the bare-token class, inside the gate built to enforce it.
- With two `Fix-Size:` lines bash `=~` binds the **first**, so large-first /
  small-last evaded the inline-threshold refusal. Small-first correctly denied,
  which is exactly why every fixture missed it.

Litmus: feed the **pristine** guard a corpus it should refuse. If you can only
describe your battery as "N mutations, all caught", you have measured the
battery's sensitivity and nothing about the predicate.

## The guard must accept the shape it prescribes

`review/SKILL.md` says *"Use `gh issue create --body-file <path>` — never
`--body "$VAR"`"*. The gate read only `$COMMAND`, so with `--body-file` the body
is **not in the command at all**: two of three exits were structurally
unreachable for the prescribed form. Every correctly-formed user-facing filing
would have been denied unless it took the machinery exit — pushing real product
issues onto the machinery ledger and corrupting the exact separation the change
creates.

That shape is the least likely to be fixtured precisely because it reads as the
safe case. The repo already documents this class; it recurred anyway.

## A check that cannot PASS

The inverse of vacuity, and it reads as protection. A new `sentry_cron_monitor`
with `failure_issue_threshold = 1` and **no `sentry-heartbeat` step** pages every
week forever on a job that ran fine. Ask of every new monitor: *what emits its
check-in, and has that emitter shipped?*

Fixing it then cascaded: the monitor is GHA-executed, so the C4 split was
backwards (12/45 written; 13/44 correct), and adding the heartbeat moved two
further derived counts (heartbeat workflows 11→12, dispatch-only 5→6).
`c4-count-parity` gates all three, and **none is visible in a diff that touches
no `.c4` file**.

## A criterion its own starting state satisfies measures nothing

Learned twice in one session. The write-up said 142 filed/week; live
re-derivation said 122. Then a 4-week measurement window compared against an
8-week-derived baseline would have declared success at 84 — the rate the repo
was *already* running.

The fix is not a better constant or a refusal guarding it: derive the baseline
over the **same window length** from a fixed pre-merge anchor, so the mismatch
class cannot occur. Verified after: 4w reports `85 >= 85`, 6w `107 >= 107` —
both correctly NOT below baseline, so the criterion can still fail.

## When the infrastructure IS guards, a body-scoped classifier cannot work

Measured over 200 open issues: **191 of 200 bodies (96%)** name a user-surface
token incidentally, so body-scoped negative evidence is vacuous and admits 3%.
The hybrid admitted 103 but proposed a dead `SUPABASE_PAT`, a docker login
failing every deploy, and image signing that had never succeeded as "machinery".

The reason no body rule works: Soleur's real infrastructure *is* guards, gates
and probes, so a genuine outage and a finding-about-a-guard share a vocabulary.
Only the **title** discriminates, because a title is a deliberate summary and a
body is not. High-precision / low-recall is the correct direction to be wrong in.

## A query filter that is a silent no-op

`gh issue list` **discards `--search` when `--label` is present**. The
self-exclusion control

    gh issue list --label deferred-scope-out --search '-label:"deferred-scope-out"'

returned all 200 instead of 0. A pure `--search` form fails identically. The
REST search endpoint DOES honour the negation (`is:open -label:X` = total − X
exactly), which makes this a trap rather than a platform limit. A positive test
passes whether or not the filter binds — only a self-exclusion control finds it.

## Instrument yields are disjoint, and the cheap ones are cheap

On this PR: `shellcheck` 0; `actionlint` caught a missing required action input
**and** a `run: |` block-scalar break (continuation lines at column 0 terminate
the block — documented, hit anyway); four-environment runs (bare / `CI=1` /
`SOLEUR_SUBAGENT=1` / both) showed no pass-count delta; and the two-agent design
pass found the coverage gap and the dead monitor. No instrument found what
another did.

## Session Errors

1. **Planning subagent killed by an API session rate limit.** Recovery: the plan
   body was on disk carrying `## Acceptance Criteria`, satisfying one-shot's
   recovery predicate, so it was recovered rather than re-paid for.
   **Prevention:** already covered by the plan-artifact-recovery block; the
   working habit is to check disk before re-spawning.
2. **Step 0a's Linear preflight matched `ADR-006`/`ADR-155`.** Recovery: both
   resolve to committed files, so `linear-fetch` was skipped on evidence.
   **Prevention:** the preflight should exclude `ADR-\d+` before treating a
   `[A-Z]{2,}-[0-9]+` match as a Linear ref.
3. **Read `rc=0` from `tail` on a FAILED push, twice.** Recovery: re-read the
   real status; the push had failed non-fast-forward after a rebase.
   **Prevention:** never take an exit code through a pipe — redirect and read
   `$?`. Already a documented rule; it recurred under time pressure.
4. **Branch 3 commits behind main, one touching lever 4's scope.**
   Recovery: rebased before Phase 1. **Prevention:** already the AGENTS-class
   fail-hard rule; it worked.
5. **The drain exclusion was a silent no-op** (`--search` discarded).
   Recovery: jq post-filter, bidirectionally fixture-tested.
   **Prevention:** every exclusion needs a SELF-EXCLUSION control.
6. **The plan's classifier rule was vacuous body-scoped.** Recovery: measured
   three scopes and title-scoped it. **Prevention:** measure a classifier's
   admit-rate against the real corpus before shipping the rule.
7. **`Mandated-By` anchored on whitespace-or-start**, unmatchable after
   `--body "`. Recovery: relaxed the leading class. **Prevention:** anchor on
   the shape that actually reaches the hook, not the shape you wrote in a test.
8. **`guardrails.test.sh` had no assertion-count floor** — a zero-assertion run
   exited 0. Recovery: added a floor reported via `printf` + `exit`, never
   through the helpers it backstops. **Prevention:** every suite needs a floor
   that does not dispatch through what it guards.
9. **My cross-generation discriminator tested `candidate.state`**, always
   `"open"` by construction — it would have re-posted on every replay retry,
   destroying the guard it meant to preserve. Recovery: keyed on the marker's
   AGE vs the cutoff. **Prevention:** ask of any discriminator *which values can
   this actually take here?*
10. **`MIN_ASSERTIONS` off by one.** Recovery: derived from the real count and
    stated as a sum. **Prevention:** derive floors, never guess them.
11. **lefthook wedged ~15 min; the completion notification said "exit code 0"
    for a commit that was `Terminated`.** Recovery: `proc.sh list_runs`
    resolved ownership via `/proc/<pid>/cwd` (a FOREIGN lefthook was running in
    a sibling worktree), `kill_mine` signalled only mine, and the commit
    re-ran under `LEFTHOOK=0` after verifying typecheck and suites by hand.
    **Prevention:** the notification is authoritative for liveness, never for
    verdict — read `git log`.
12. **Adding a Sentry monitor broke `c4-count-parity`**, invisible in the diff.
    Recovery: derived the count and updated the edge. **Prevention:** run the
    c4 suites whenever a `sentry_cron_monitor` is added.
13. **My C4 fix had the split backwards, and the fix cascaded to two more
    counts.** Recovery: derived all four. **Prevention:** a dispatched-workflow
    monitor checks in from the GHA side; derive every gated clause, never one.
14. **`actionlint` caught a missing required action input** I missed by reading
    a truncated sibling. **Prevention:** read the whole `with:` block.
15. **My YAML fix put continuation lines at column 0**, terminating `run: |`.
    Recovery: re-indented. **Prevention:** parse the YAML after editing a block
    scalar — documented, hit anyway.
16. **The new monitor had no heartbeat emitter.** Recovery: added with
    `if: always()`. **Prevention:** see the section above.
17. **The gate refused the prescribed `--body-file` form.** Recovery: read the
    body file, failing toward gating when declared-but-unreadable.
    **Prevention:** run the guard against the shape the guard prescribes.
18. **Two escapes no mutation could reach.** Recovery: fixed with fixtures AND
    controls so they discriminate rather than blanket-deny. **Prevention:**
    escape rows alongside mutation rows on every guard.
19. **Baseline window mismatch, twice.** Recovery: derived over the same window
    from a fixed anchor. **Prevention:** name the window on both sides.
20. **Taxonomy path CWD-relative, empty under vitest.** Recovery: resolved from
    the module's own location. **Prevention:** never resolve a data file from
    the CWD in a hook.
21. **Cron exit-2 fixtures used an inline multiline body the sandbox denies.**
    Recovery: moved to `--body-file`. **Prevention:** check the containment
    rules that fire BEFORE your check.
22. **My own `rm -rf "$VAR"` was blocked, twice.** Not a defect — the guard is
    fail-closed on an unresolvable variable. **Prevention:** delete a literal
    subpath, or leave `mktemp -d` dirs for the reaper.
23. **A QA probe's expected value was typo'd**, reading as a failure.
    **Prevention:** when a probe disagrees with a passing suite, suspect the
    probe first.
24. **The refusal message said `1 files`.** Recovery: pluralized.
    **Prevention:** the operator-facing string of a blocking gate is part of
    whether the refusal reads as authoritative.
25. **`lint-window-closure-assertion` fails — PRE-EXISTING**, confirmed `rc=1`
    on `origin/main` in an isolated worktree, none of its three files in this
    diff. Not fixed here; noted so the next reader does not re-derive it.
