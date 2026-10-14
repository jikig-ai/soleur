---
title: Every gate this PR added failed open on the input it could not measure
date: 2026-09-21
category: workflow-patterns
tags: [review, qa, fail-open, guards, sync-pr-behind, pir-gate, monitor-hook, git-trace]
pr: 8474
issues: [8383, 8419, 8420, 8334, 8438, 7961]
---

# Learning: every gate this PR added failed open on the input it could not measure

## Problem

PR #8474 consolidated ship Phase 7's BEHIND sync into `sync-pr-behind.sh`, freed SKILL.md
byte budget with step-gated references, widened `monitor-supersede-guard.sh`'s "ended"
detection, and taught `ship-incident-pir-gate.sh` to ignore outage tokens inside a denial.
The work phase shipped green: every suite, a self-run mutation battery, shellcheck.

An 11-seat review then found two P1s and ~60 P2/P3s, and a QA dry run of the rewritten prose
found 18 more. Almost all were one shape: **a gate that decides from an input it cannot
fully see, defaulting to the permissive answer.**

- PIR negation: a one-word window over a `[a-z]` split treated `no small outage`,
  `did not detect outage`, `no-warning outage`, `Notifications…`, `Juno…`, and any token
  after an em-dash or `rather than … and …` as a denial — 20 real outage reports silenced,
  with only a stderr note nobody reads. The same loop was cubic (38 KB line: 46 s).
- Monitor hook: "ended" was matched per JSONL *record*, so a sibling task's `completed` in a
  batched record, the monitor's own output, or a quoted id in a user prompt hid a live
  monitor. A backticked message string executed `TaskStop` from PATH.
- Hatch classifier (`settle-then-admin-merge.md`): `git diff … | grep -v … || echo
  hatch-eligible` printed **eligible** when the diff failed or origin/main was missing.
- Sentry delta: an empty `DEPLOY_TS` made `date -d ""` = today's midnight → STOPPED →
  auto-resolve PUT.
- `sync-pr-behind.sh`: `GIT_CURL_VERBOSE=0` **enables** curl verbose (git checks presence,
  not value), so a token-bearing URL could print and real result lines scrolled out of
  `tail -2`. A no-op sync reported `pushed` and burned the sync budget.

## Solution

- PIR: cue must be a whole word + whitespace + token (one article allowed); `not that` /
  `rather than` reach ≤3 words; clause boundaries include dashes, pipe, parens and
  conjunctions; per-token work is window-bounded (linear). 67 new fixtures, including every
  suppressed real report as must-FIRE, and one-rule mutation rows that each red on a
  behavioural fixture plus a no-op negative control.
- Monitor hook: judge each `<task-notification>` block by its own header, only from
  harness-written record shapes, most recent notification (enqueue order) wins, expiry
  matched against the harness's full sentence.
- Classifier: fetch first; empty or failed diff prints `NOT eligible`.
- Sentry: empty/unparseable timestamps are SKIPPED.
- sync script: `unset` the trace/verbose vars once at the top (a per-call `env -u … git`
  would bypass the test fixture's exported `git()` mock); exit 11 `kind=noop`.

Fix batch mechanics that worked: three general-purpose agents, each in its **own detached
worktree under /var/tmp**, returned patches (`git diff > …patch`); the lead applied them
from one known SHA and re-ran every suite itself. No shared-index contention, no
cross-agent contamination of the review evidence.

## Key Insight

For every gate, name the input it **cannot measure** (a failed command, an empty value, a
token it does not recognise, a record it was not written for) and check which verdict that
input produces. On this PR the answer was the permissive one five separate times, in four
files, and none of them was reachable by mutating the implementation — the self-run battery
was green throughout. Must-FIRE fixtures shaped like the real producer (a real outage
sentence, a real heartbeat event, a missing SHA) were what closed them.

## Session Errors

1. **`.claude/hooks`-named bash commands exited 1 silently (plan phase).** Recovery: read via
   the Read tool. **Prevention:** already hook-enforced by design; use Read for hook files.
2. **Plan draft claimed the old script exits 2 on unknown `--step` (it ignored it).**
   Recovery: corrected in deepen. **Prevention:** run the script with the flag before
   describing its behaviour.
3. **Plan draft used `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` (ADR-179 forbids).** Recovery:
   bare form. **Prevention:** existing ADR-179 lint/guidance.
4. **Plan draft negation window contradicted a fixture.** Recovery: narrowed. **Prevention:**
   fixture-first design for any suppression rule.
5. **PIR negation shipped fail-open and cubic.** Recovery: rules tightened, 67 fixtures,
   linear scan. **Prevention:** a suppression rule needs a must-still-FIRE fixture per cue
   and per boundary class before merge (routed to plan-sharp-edges).
6. **Monitor hook per-record terminal match + backtick command substitution in a message.**
   Recovery: per-block header parse; escaped backticks + rendered-text assertion.
   **Prevention:** assert the exact rendered text of any hook message.
7. **`GIT_CURL_VERBOSE=0` enabled curl verbose.** Recovery: `unset` at script top.
   **Prevention:** disable git trace/verbose vars by `unset`, never `=0` (routed to
   plan-sharp-edges).
8. **Handoff said the `origin/main` merge "should be clean"; it conflicted in 2 files with
   #8458.** Recovery: verified this branch was a superset, merged `-X ours`, diffed both
   files against the pre-merge commit. **Prevention:** already covered by one-shot token
   discipline item 4 (re-measure inherited claims on resume) — `git merge-tree` against a
   main that includes the sibling PR.
9. **A failed `git commit` reported exit 0 because a trailing `git log` supplied the rc.**
   Recovery: read the lefthook summary, found `🥊 bun-test`. **Prevention:** capture
   `COMMIT_RC=$?` immediately after `git commit` (routed to work skill).
10. **New fixture authored a git tag; a usage string read as a fetch without `--no-tags`;
    both tripped the ADR-207 tag-authorship census (ledger at ceiling).** Recovery: dropped
    the tag half of the test (the census already enforces `--no-tags`), reworded the string.
    **Prevention:** the census caught it as designed; none needed.
11. **`Agent` with `isolation: "worktree"` failed: session cwd `/home/jean` is not a git
    repo.** Recovery: pre-created a detached worktree under /var/tmp and pointed the agent
    at it. **Prevention:** routed to review skill Sharp Edges.
12. **#8458's required-check monitors expired twice with no verdict (100+ queued CI runs).**
    Recovery: confirmed runs existed and were queued, re-armed. **Prevention:** one-off infra
    load; the "runs exist but queued" check is the discriminator.
13. **QA dry run found 18 unfollowable or fail-unsafe sentences after an 11-seat review.**
    Recovery: fixed and each outcome driven with stubs. **Prevention:** already documented in
    qa/SKILL.md ("a skill-prose change gets a constrained DRY RUN").

## Tags

category: workflow-patterns
module: ship, merge-pr, postmerge, monitor-supersede-guard, ship-incident-pir-gate
