---
title: "The one defect lived in the only code path with no test, and my stub answered every question"
date: 2026-09-19
category: test-failures
module: registry-host-replace dispatcher / registry-delivery-change helper / review
issue: 8279
pr: 8355
problem_type: test_failure
component: testing_framework
symptoms:
  - "verdict step said the host's bytes were 'unchanged since the watermark' on an unattributed direct push that HAD changed the config"
  - "five URL-construction mutants (reversed compare range, listing from the wrong SHA/path) survived a 98-assertion suite"
  - "`${arr[*]}` with IFS='; ' joined on ';' — the header and plan promised '; ' and no row could see it"
  - "one-line anti-vacuity floors with exit 2 were unconstructible for guard-vacuity-floor.test.sh"
root_cause: test_isolation
resolution_type: test_fix
severity: high
tags: [review, mutation-testing, stub-fidelity, workflow-yaml, vacuity, github-actions, registry]
synced_to: [work]
---

# Learning: the one defect lived in the only code path with no test, and my stub answered every question

## Problem

PR #8355 replaced the hard-coded `#7555/#7556` in `registry-host-replace-dispatch.yml` with a
derivation helper (`scripts/registry-delivery-change.sh`: watermark range ∩ path-touching commits →
PR attribution) and a single `verdict` step that posts each delivery's outcome on the delivering
PR(s). The helper shipped with a 96-row suite, 16 mutation rows all killed, and every plan AC
green. An eleven-agent review then found ~45 findings, one P1 and the P1 was not in the helper.

**The P1 was in the YAML.** The verdict step decided between "the bytes are unchanged since the
watermark" and "the change(s) are NOT live" by testing `prs=` empty on a proven range. `prs=` is
also empty for an **unattributed direct push** (`soleur-ai[bot]` pushes to `main` with no `(#N)`
suffix — the T8 fixture the suite already carried), which DID change the config. On every failing
arm the verdict would have created an owned issue saying "this run was not applied" while the
dispatch reason on the same run said "Delivering: commit abc1234". The helper's contract for
"nothing touched the config" was `commits=`, and the `change` step had forwarded that key to
`$GITHUB_OUTPUT` all along; nothing read it. The verdict composition was the one code path with
no test — it lived in a `run:` block, and the plan's ACs pinned its *spelling* (greps for
`are NOT live`, `unchanged since the delivery watermark`) rather than its *decision*.

**The stub answered any request.** The suite's `gh` stub keyed `/pulls` fixtures per SHA (good)
but returned `STUB_COMPARE_JSON` for any `*/compare/*` argv and `STUB_PATH_JSON` for any argv
carrying `-f path=`. The two calls the helper string-builds a URL for were therefore
unobservable: `compare/${AFTER}...${BEFORE}` (every range `behind`), `-f sha="$BEFORE"` (listing
from the watermark, intersection always empty) and three siblings each passed 98/98. The battery
had 16 rows on the SUT's *logic* and none on the *request shape*.

Smaller instances of the same "asserted, not measured" class rode along: the header promised a
`; `-joined summary while `${arr[*]}` joins on the first IFS character only (no multi-part
fixture existed); `--help` printed `sed -n '1,50p'` of a 57-line header; the plan's mutation list
was uniformly "make the SUT wronger" and never "ask the stub what was requested".

## Solution

1. **A workflow-body harness** — `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh`
   extracts the `change` and `verdict` `run:` bodies with PyYAML, executes them under the runner's
   own shell (`bash --noprofile --norc -eo pipefail`) with a stubbed `gh`, and pins what each arm
   DECIDES (31 rows: every `kind`, the `commits`-keyed sentence, the owner-issue dedupe, the raw
   tracker normalisation, marker last). Mutation-checked: `COMMITS`→`PRS` reds V2; deleting the
   `gate-failed` arm reds V11.
2. **A request-checking stub** — the compare branch requires
   `repos/<repo>/compare/${STUB_EXPECT_BEFORE}...${STUB_EXPECT_AFTER}` and the listing branch
   requires `-f sha=${STUB_EXPECT_AFTER} -f path=${STUB_EXPECT_PATH}`; anything else is a miss
   (exit 64). `run_sut` derives the expectations from the `--before`/`--after` it passes, so every
   row is protected without naming the URL. `assert_shape` additionally reds on any `stub:` line in
   stderr, because the SUT swallows the stub's stderr and a forgotten fixture reads as the no-PR arm.
3. **A registered battery** — `tests/scripts/test-registry-delivery-change-mutation-battery.sh`
   (21 rows across request-shape / arm / cardinality / direction; sandbox copies; `cmp` asserts
   each mutation landed; a red control voids the run) in `scripts/test-all.sh`, so the kills
   protect something tomorrow.
4. The helper: `join_semi` loop; rc-vs-empty split on `/pulls` (a FAILED lookup leaves the commit
   unattributed — the trailing `(#N)` is contributor text and must not pick the write target on an
   API error); `merged_at != null` preference; `sed -n '1,/^# Usage:/p'`.

## Key Insight

**The defect lands where the assertion count is lowest, and a self-run battery cannot see it,
because every row mutates the thing the author was already testing.** Two readings, both cheap:

- **List the code paths the diff adds and ask which has ZERO behavioural rows.** A `run:` block
  in a workflow is the modal answer — its ACs are greps, and a grep pins bytes, not a branch.
  Extracting the body and executing it costs one PyYAML call; the harness here took ~120 lines
  and found the P1 on its second row.
- **Ask the stub what it CHECKS, not what it RETURNS.** A stub that dispatches on one axis (which
  SHA) and ignores the others (which range, which path) makes every wrong request look like the
  right one. The fix is not more fixtures; it is a stub that refuses a request it did not expect.

## Session Errors

1. **Committed a docs/bookkeeping commit while the Phase 2 exit gate was running.** The runner's
   write-boundary guard reported HEAD moving `3284cb942 → bbafda23a` as the run's one failure.
   Recovery: read the guard's report, confirmed the move was my own commit, re-ran the one suite
   the delta touched in isolation. **Prevention:** the work skill's "confirm clean, then do not
   edit under it" rule already exists; treat a launched gate as a lock on the tree — queue the
   bookkeeping commit behind the rc file, or kill the run before committing.
2. **`pr="$(resolve_pr_for_sha "$sha")"` discarded `BY_SUBJECT`** — the documented subshell trap,
   reproduced in a function written the same day the rule was read. Recovery: the suite's first
   GREEN attempt failed on `BY_SUBJECT: unbound variable`; the function now sets `PR_OUT` and is
   called directly. **Prevention:** a function that sets a global is never called as `$(...)`;
   return the value through a named variable when there is more than one output.
3. **`@tsv` over a `tojson` field re-escaped its backslashes** so any subject with `"` failed
   `jq -r .`; and a `sed` byte-range bracket for U+2028 never matched under a UTF-8 locale.
   Recovery: base64 transport for the listing (`"\(.sha) \(.commit.message|@base64)"`) and
   `LC_ALL=C` on the byte-level `tr`/`sed`; later replaced by `scripts/lib/strip-log-injection.sh`
   which already existed for exactly this. **Prevention:** grep `scripts/lib/` for a strip/
   sanitise helper before writing one (the work skill's "grep lib before writing a helper" rule);
   move multi-line text between jq and bash as base64, never `@tsv`.
4. **Plan-asserted properties carried into the code unmeasured:** the `prs=`-keyed "unchanged"
   predicate (the P1), the `; ` join, the `1,50p` help range, the `run 35352234356` citation for
   `continue-on-error` behaviour (that run had no such step). Recovery: the review panel measured
   each. **Prevention:** for every sentence a plan asserts about a SET or a SHAPE ("empty ⇔ no
   touch", "joined with `; `", "measured on run N"), name the fixture that instantiates the
   other member and run it before the sentence reaches code.
5. **My own verdict simulation stub returned raw JSON where the SUT applies `--jq`**, so the
   "existing owner issue" path read as broken for one iteration. Recovery: made the stub answer
   `4100`; the harness row V4 now pins it. **Prevention:** verify the instrument against a
   known-positive before reading its verdict — a stub that cannot satisfy the SUT's parse is not a
   control.
6. **One-line anti-vacuity floors with `exit 2` were unconstructible** for
   `scripts/guard-vacuity-floor.test.sh` (it slices from the floor's `if` to a standalone `fi` and
   treats rc=2 as CONSTRUCTION), so the ratchet reddened 15 → 16. Recovery: multi-line
   `if … fi` + `printf` + `exit 1`. **Prevention:** run the repo-global ratchet lints after every
   commit that adds a `.test.sh` (work skill §6.6 names them); write floors in the covered shape
   from the start.
7. **First `gh issue create` for the deferral was denied** by the filing hook (a machinery
   finding needs `--label meta/machinery`). Recovery: re-filed with the label (#8365). **Prevention:** read the filing hook's three exits before composing a review-origin filing; a CI-machinery refactor is exit (1).
8. **Tooling friction:** a foreground `sleep` was blocked, a background rc-file waiter was killed
   by the memory reaper, two Monitors overlapped on one file; `grep -c -- '-f tracker='` and a
   `sed` range expression were each mis-typed once. **Prevention:** one Monitor per rc file (TaskStop the
   prior one before re-arming) and `grep -c -- '<pattern>'` for any pattern starting with `-`; one-offs otherwise.

## Related

- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `knowledge-base/project/learnings/test-failures/2026-09-02-my-fake-curl-put-the-seam-above-everything-the-vendor-validates.md`
- `knowledge-base/project/learnings/2026-08-17-the-artifact-that-proves-a-refusal-happened-could-not-be-written.md`
- `knowledge-base/project/learnings/2026-07-27-the-subshell-bug-i-was-fixing-bit-me-three-more-times.md`
- Runbook: `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`
- Deferral: #8365 (shared merge-SHA→PR resolver extraction, counter-triggered)
