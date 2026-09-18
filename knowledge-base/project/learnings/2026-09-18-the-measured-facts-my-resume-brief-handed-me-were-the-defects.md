---
title: "The measured facts my resume brief handed me were the defects"
date: 2026-09-18
category: workflow-issues
module: git-data boot poll / follow-through probes / review
issue: 8178
pr: 8262
tags: [resume, inherited-claims, follow-through, log-attribution, errexit, review]
---

# Learning: the measured facts my resume brief handed me were the defects

## Problem

PR #8262 fixes #8178: the git-data birth/replace boot poll had never read a row, because it
bound repository secrets that the Better Stack query endpoint rejected, and it discarded
stderr. The session resumed from a detailed brief that listed Phases 0-4 and 6 as "DONE and
verified" and two "measured" facts to keep in the PR body. A twelve-agent review panel then
found that:

- One "measured" fact was false. The brief said the 10-minute poll budget was too short
  because run 34836141887's `boot_complete` landed `15:27:24`, 2m37s after the poll gave up.
  That row came from the NEXT host: replace run 34861860722 finished its apply at `15:27:06`.
  The birth host had died at `gitdata_doppler_dl`; with working credentials it would correctly
  have read `silent`. The false fact had already raised the budget 20 -> 30 polls, which ate
  the job's 20-minute timeout, and it sat in the plan, ADR-149, two workflow comments and a
  test fixture.
- I had re-affirmed a retracted diagnosis myself. I wrote an ADR-192 addendum saying its
  "the git-data source has never stored a row" reading of `CLUSTER_DOESNT_EXIST` was "true
  when written", and kept a `table-missing` class blaming the producer. #7867, closed nine days
  earlier, established the opposite: a Better Stack SQL API connection does not cover sources
  created after it, the data was stored all along, and the error names the READER's connection
  scope. That is #8178's actual cause.
- "DONE" was not done. I bulk-ticked tasks.md 0-4 on the brief's word. Four items (FR9 table
  pin from the registry, FR10 replace-job outcome backstop, FR11 no re-dispatch remediation,
  task 4.6 readiness note) were unmet; two Phase 6 items were absent from the diff entirely.

Then the fix round shipped the defect classes review exists to catch, in its own guards:

- The follow-through probe attributed `VERDICT=` lines to the poll step by a 1-second clock
  window. The next step's env block echoes the operator's `reason` input in the same second
  the poll step completes, so a crafted dispatch could close #8178 without the poll ever
  reading. A tab inside echoed text could also place an attacker-chosen timestamp.
- The suite drove `git_data_boot_verify` at top level in a `bash -e` shell. The workflow calls
  it as `rc=0; git_data_boot_verify … || rc=$?`, and that `||` switches errexit off inside the
  function. Deleting `|| return 1` after the invariant check left the suite 108/108 green while
  a real replace with `luks_mounted=no` would go green.
- Wiring checks grepped the whole job block, so a `DOPPLER_TOKEN:` line in another step, a
  commented-out `if:`, or `id: poll_v2` all satisfied them.

## Solution

- Re-measured every inherited number against run logs (`gh run view --json jobs` step
  timestamps) before keeping it; kept the budget at 20 x 30 s, capped each read at 45 s around
  the whole `doppler run`, and raised `timeout-minutes` to 40 so the poll always prints a
  verdict.
- Rewrote the ADR-192 addendum and the classifier from #7867's resolution:
  `CLUSTER_DOESNT_EXIST` -> `source-not-in-connection`, a read-path fault.
- Diffed every "DONE" item against the branch diff; implemented the unmet ones by moving the
  step logic into one library function (`git_data_boot_verify`) that both jobs call.
- Bounded the probe's evidence by the RUNNER's structure, not the clock: only lines between the
  poll step's `##[group]Run` header and the next step's header count, each reduced to gh's third
  field, and the summary's `answered=N` must equal the step's own `poll k/M: answered` lines.
- Ran S17 in the workflow's exact call shape, and scoped every wiring check to the named step
  with comments stripped and exact-line matches; executed the Dispatch summary body over an
  apply/poll outcome-pair table. Two mutation batteries: 31/32 then 25/25 killed.

## Key Insight

A resume brief is written by the session that did the work, so its "measured" facts and its
"DONE" markers carry exactly that session's blind spots, in the most authoritative-looking
form a claim can take. Treat every number, verdict and DONE in it as a precondition to
re-measure, the same as a plan-quoted number or an issue comment. And before interpreting a
vendor error string, grep closed issues for the literal: the reading you are about to write
may already have been retracted.

For log-based verdicts: attribute lines by the producer's structural delimiters
(`##[group]Run` headers), never by timestamps, and never by a pattern that can match anywhere
in a line. For step logic: test it in the exact call shape production uses, because `|| rc=$?`
turns errexit off and hides a missing explicit `return`.

## Session Errors

1. **Inherited a false "measured" budget fact from the resume brief** (2m37s) and nearly shipped it in the PR body. Recovery: the user-impact seat flagged it; `gh run view --json jobs` step timestamps showed the row landed 18 s after replace run 34861860722's apply. **Prevention:** re-derive every number a resume brief marks "measured" from the run log before writing it anywhere (work SKILL.md bullet routed in this session).
2. **Re-affirmed #7867's retracted `CLUSTER_DOESNT_EXIST` reading** in an ADR-192 addendum. Recovery: architecture seat H1; rewrote the addendum and renamed the class. **Prevention:** before interpreting a vendor error string, `gh issue list --state all -L 200 --search "<literal error>"` and read the resolution (same routed bullet).
3. **Bulk-ticked tasks.md 0-4** on the brief's "DONE"; FR9/FR10/FR11/4.6 were unmet. Recovery: simplicity and user-impact seats; implemented them. **Prevention:** existing work-skill rule ("An acceptance checkbox is a CLAIM — never bulk-toggle"); I violated it. Diff each DONE item against `git diff origin/main...HEAD` before ticking.
4. **The brief overstated Phase 6** (6.2 ADR-192 addendum and 6.3 AP-027 absent). Recovery: caught at resume by diffing the file list. **Prevention:** same as 1.
5. **Plan claimed "no `secrets=` wiring is required"** for a `gh`-based probe. Recovery: read `scripts/sweep-followthroughs.sh`'s `env -i` allowlist; declared `secrets=GH_TOKEN`. **Prevention:** a follow-through probe's credential posture is verified against the sweeper's env construction, not assumed.
6. **Clock-window log attribution was forgeable** (next step's `REASON` echo in the same second; tab-embedded timestamps). Recovery: bound by `##[group]Run` headers plus third-field anchoring plus an answered-count cross-check. **Prevention:** review SKILL.md defect-class bullet routed in this session.
7. **Suite exercised `git_data_boot_verify` at top level under errexit**, masking a missing `|| return 1`. Recovery: S17 now calls it as `rc=0; … || rc=$?`. **Prevention:** same routed review bullet (test in the production call shape).
8. **Whole-job grep wiring checks** were satisfied by other steps and comments. Recovery: per-step extraction, comments stripped, exact lines, plus a `chk` canary. **Prevention:** same routed review bullet.
9. **First probe draft said "the poll step never ran"** for pre-fix jobs whose old inline poll did run. Recovery: the live end-to-end run showed it; reworded. **Prevention:** run a probe once against real data before trusting its messages.
10. **`gh api repos/.../jobs/<id>/logs` exits 1** on logs containing terminal escape sequences (gh 2.101.0). Recovery: `gh run view --job <id> --log`. **Prevention:** recorded in the probe header.
11. **The trace-refusal lint counted `DOPPLER_TOKEN` named in a comment and a message.** Recovery: reworded both. **Prevention:** in credential-bearing scripts, name tokens generically in prose.
12. **P1b fixture ratchet +1** from an unguarded `run_arm` redirect. Recovery: `assert_fixture_dir "$d"`. **Prevention:** existing work-skill 6.6 (run the fixture ratchets on every new `.test.sh`), which caught it.
13. **Guard hook denied `rm -rf "$D"`** (misparsed as the worktree root). Recovery: fresh `mktemp -d` path. **Prevention:** create scratch dirs with `mktemp` rather than clearing a fixed path.
14. **Stop hook fired twice** on "fixes land when the agents report" closings. Recovery: explicit `<stop>BLOCKED: …</stop>`. **Prevention:** when waiting on background agents, end with the stop tag, not a first-person promise.
15. **shellcheck SC2034** on two variables the rewrite left unused. Recovery: removed. **Prevention:** shellcheck after every rewrite, not only once.
16. **The first per-read timeout sat inside `doppler run`** and could not cover Doppler's own fetch. Recovery: `timeout -k 5 45 doppler run …`, pinned by a timeout argv shim. **Prevention:** put a cap around the whole external call chain, and assert its placement.
17. **Remediation cited a web-host `git ls-remote` check that does not exist** (it is `TODO(#5274 PR C)`); propagated from a pre-existing readiness note. Recovery: removed and replaced with the truth. **Prevention:** hr-verify-repo-capability-claim-before-assert applies to remediation text too.
18. **(earlier phase) A sourced library toggled `set +e`/`set -e`**, leaving errexit armed in the caller. Recovery: `rc=0; … || rc=$?`. **Prevention:** a sourced function never changes the caller's shell options; S16 asserts it.
19. **(earlier phase) A client-side anchor re-check** parsed `dt` assuming UTC and truncated fractions, disagreeing with the server at the anchor second. Recovery: deleted; the server predicate plus `LIMIT 1` does the job. **Prevention:** do not re-implement a server-side predicate client-side with weaker parsing.

## Tags

category: workflow-issues
module: git-data boot poll, follow-through probes, review
