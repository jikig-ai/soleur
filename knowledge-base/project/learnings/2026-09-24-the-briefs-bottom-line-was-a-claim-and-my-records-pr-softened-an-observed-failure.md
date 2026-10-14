---
title: The brief's bottom line was a claim, and my records PR softened an observed failure
date: 2026-09-24
category: workflow-patterns
tags: [records, adr-096, zot, verification, inherited-claims, correction-sweep]
refs: ["#6122", "#8036", "#8651", "#7077", "#6073", "PR #8666"]
---

# The brief's bottom line was a claim, and my records PR softened an observed failure

## Problem

PR #8666 corrected stale records of the GHCR-to-zot migration (ADR-096's Status block, the
registry-oidc `tasks.md`, six issues). A records PR changes no code, so every defect it can ship
is a false sentence. Review found two P1s, and both were sentences I had not measured:

1. **The operator brief's conclusion** ("the gap to migration complete is not engineering; it is
   one authorization act on #6122") was posted verbatim to #6122. It is false as stated:
   `zot-soak-6122.sh` carries a `WEB_BLOCKER=8651` arm and needs `app_zot` evidence, so the soak
   cannot pass until the #8651 fix (PR #8660) lands and a fresh web boot is observed, and the
   recorded FAIL needs a re-armed window.
2. **"A zot-served fresh web boot has not yet been observed"** in the new Status block. #8651
   records an observed FAILURE (the 2026-09-23 web-2 replace booted dark). "Not observed" reads
   as an evidence gap, and together with "zot is the sole pull path" it tells a reader a web-host
   replace is safe.

## Solution

- Rewrote the #6122 comment in place with the real chain (#8651 closes → soak re-armed →
  operator authorizes #6500 and #6122 → option chosen → engineering), plus an explicit reply
  format and an Option 0 (do nothing).
- Status block: "a fresh web boot currently fails … do not replace a web host until #8651
  closes"; "sole pull path" scoped to rolling deploys.
- The claim-indexed sweep the first pass skipped: the revert runbook's "On page … run the
  Immediate revert" (which would remove the only working pull path) and its soak-table advice to
  recreate a web host; `model.c4`'s "registry heartbeat paused" and "2/3 admitted secrets"; ADR
  body lines — each with a dated superseded marker.
- Measured instead of inherited: the plan's "heartbeat still paused" (source `paused = true`,
  decoupled from live by `ignore_changes`) was refuted by one read-only Better Stack call
  (`status=up paused=false`); the plan's "isolation gate never ran" was refuted by listing the
  registry config's secret names (exactly the 4 the boot self-check admits).

## Key Insight

A brief's CONCLUSION sentence is the least-checked sentence in a session: it arrives as the
requester's framing, often next to a block labelled "context you can trust", and it reads as the
thing to deliver rather than a thing to test. When the brief says "state plainly X", X is a claim
about gates that exist in the repo — name the gate that would falsify it and read it before
posting. And a records PR that SOFTENS a finding ("not observed" for "observed to fail") is as
wrong as one that inflates it; the softened form is worse because it licenses the unsafe action.

## Session Errors

1. **`cleanup-merged` could not pull main** (main checkout on detached HEAD). Recovery: non-fatal, proceeded on `origin/main`. **Prevention:** none needed; one-off environment state.
2. **`cd`'d into the sibling #8651 worktree** to read its diff, moving the session's primary dir. Recovery: read-only, left immediately. **Prevention:** inspect sibling worktrees with `git -C <path>` or `gh pr diff`, never `cd`.
3. **Plan asserted the registry heartbeat was paused** from source `paused = true`. Recovery: live Better Stack read showed up/unpaused; 1.8 ticked `[x]`. **Prevention:** before recording a Terraform attribute as live state, grep the resource for `ignore_changes` covering it; if present, read live.
4. **Plan's #6073 text carried an unsourced "reproduced live 2026-07-05".** Recovery: reworded to what the learning records. **Prevention:** every date in paste-ready prose names its source.
5. **Plan paraphrased #6126's multi-writer warning too broadly.** Recovery: reworded to "multi-writer zot over shared R2". **Prevention:** quote, do not paraphrase, a cited issue's constraint.
6. **#7077 comment dated 2026-09-24 (local) though posted 2026-09-23 UTC.** Recovery: patched. **Prevention:** date GitHub artifacts in UTC (`date -u`).
7. **Brief's "one authorization act" bottom line posted unmeasured (review P1).** Recovery: comment rewritten with the real chain; plan paragraph marked superseded. **Prevention:** plan sharp-edges bullet (routed in this PR).
8. **Status block said "not yet observed" for an observed failure (review P1).** Recovery: rewritten. **Prevention:** when citing an issue as evidence of absence, read its body; if it records a failure, say so.
9. **Correction swept by file, not by claim** — runbook, `model.c4`, ADR body kept the retired claims. Recovery: claim-indexed sweep in the review round. **Prevention:** existing compound/work rule (grep the claim's subject repo-wide); applied late here.
10. **`test-all.sh` refused (sibling full-gate run in flight).** Recovery: ran the consumer suites (kb-index, kb-drift, c4 freshness) plus lints. **Prevention:** existing `--capacity` probe; ask first.
11. **Ran `markdownlint-cli2` directly** instead of `scripts/markdown-lint.sh`, surfacing pre-existing errors in the excluded `knowledge-base/project/`. **Prevention:** lint through the repo invoker, which honours `.markdownlintignore`.
12. **Searched for the C4 freshness suite with a wrong glob.** Recovery: `git ls-files | grep`. **Prevention:** locate suites with `git ls-files`, not `ls` globs.
13. **`grep -c 'START=2026-…'` returned 0** because the literal is `START="${ZOT_SOAK_START:-…}"`. Recovery: re-grepped the value. **Prevention:** grep the value, not an assumed assignment shape.
14. **Stop hook fired on a first-person commitment while waiting on agents.** Recovery: emitted an explicit `<stop>BLOCKED:` line. **Prevention:** when waiting on background work, end with the stop marker, not a promise.

## Addendum 2026-09-24 (PR #8684)

15. **Recorded task 5.5 (revoke the leaked PAT) as done from the operator's empty token lists, without checking WHICH account held the PAT.** ADR-096's own 2026-07-30 correction and `variables.tf` say it was a fine-grained PAT on a machine account, and the new amendment even misquoted that correction as "user-account". Caught by the security reviewer, whose correction was itself inherited: the "machine account" came from an unmeasured `variables.tf` description. Recovery: measured the owner (`GHCR_READ_USER` equals the operator's own login), so the operator's screenshots did cover it and 5.5 closed on evidence. **Prevention:** before closing a credential-revocation task on evidence, grep the repo for the credential's owner (`variables.tf` description, the ADR's credential section) and confirm the evidence was taken on THAT principal — and measure the owner (compare the stored login against the account the evidence came from) rather than trusting a description of it.
