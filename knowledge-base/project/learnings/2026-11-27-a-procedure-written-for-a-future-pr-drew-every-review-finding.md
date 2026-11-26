---
title: A procedure written for a future PR drew every review finding until it was cut to facts and constraints
date: 2026-11-27
category: workflow-issues
tags: [review, runbook, fix-round, cloudflare, token-revoke]
issue: 12931
pr: 13080
---

# A procedure written for a future PR drew every review finding until it was cut to facts and constraints

## Problem

PR #13080 aligned the cf-token-scope test mock with the live grant codes (1006 and 10400). The review panel also found that the runbook's Phase 5 told the agent to overwrite `<KEY>` and then revoke through a recipe that reads `<KEY>`. That order revoked the NEW token (P1). The first fix made things worse: it wrote a full token-replacement procedure into Phase 5, to be run by a cleanup PR that does not exist yet. Fix round 1 then put every new finding from the seven seats on that procedure:

- A names-only holder check cannot see an old value.
- The Origin CA token's holder lives in `soleur-infra-privileged/prd`, a project the holder search never covered.
- The analytics token is an owner mint (`origin-tls-strict-flip.md`).
- The value copy had no command.

## Solution

Phase 5 no longer prescribes a procedure. It records what was measured, what was not located, and the constraints the cleanup PR's procedure must meet:

- Stage the old value as `<KEY>_PREV` before overwriting `<KEY>`.
- Check by digest or verify id, never by key name.
- Treat the analytics token as an owner mint.
- Run the page-rules read on the new zone first; a scope error there means "unknown", not "no page rules".

The cleanup PR writes its own steps under its own review.

Two other fixes held:

- **Revoke read-back.** Step 4 deletes the key only on a line that starts `success=false`. Any other output means stop and keep the key. The verifier found that my own fix had split the outcomes into "true" and "everything else", which deleted the only copy of a possibly live token on an empty or `null` read-back.
- **Test pins.** The M2 pins use whole-line `grep -cxF`. The M5e pin requires the displayed code fragment (`, err 1000`, or none for two documents). Each was proven by a sandbox mutant diffed against a control.

## Key Insight

When a fix round's new findings all land on prose that prescribes work for a later PR, the defect is the prescription, not its details. Each fixed detail is one more claim about a system this PR does not change and cannot test. Replace the procedure with measured facts plus the constraints that procedure must meet.

The same holds for a negative claim: "no holder found" is true only for the search that produced it. Name that search's scope in the sentence.

## Session Errors

1. **The gate monitor's `grep -c` fallback printed `0\n0` and broke its arithmetic.** Recovery: re-armed with a file-existence until-loop. **Prevention:** a monitor's exit condition tests one file's existence, never a computed count.
2. **Mutant B did not land twice.** Its anchor matched lines 700 and 921, and the heredoc escaping broke. Recovery: a line-numbered `sed` guarded on line 698 being `mig_errcode() {`. **Prevention:** count anchor matches before mutating, and require exactly one (the landed-assert caught both misses).
3. **markdownlint MD022/MD032 (session-state.md) and MD038 (plan).** Recovery: fixed. **Prevention:** run markdownlint on every edited `.md` before committing.
4. **A Phase 5 replacement procedure for a future PR drew a P1, then three P2s.** Recovery: cut to facts plus constraints. **Prevention:** the bullet routed to `review/references/risk-tier-and-fix-rounds.md`.
5. **The fix brief said "script header wrap is fixed" when the long line had only moved (137 chars).** Recovery: rewrapped and checked with `awk 'length>82'`. **Prevention:** each claim in a fix brief comes from a command run at the fix SHA, never from memory of the edit.
6. **My step-4 fix deleted the key on any read-back other than `success=true`.** Recovery: delete only on `success=false`; on any other output, stop. **Prevention:** a destructive branch keys on the one confirmed outcome, and every other output (including empty and `null`) takes the safe arm.
7. **Runbook test R6 broke when step 4 was reworded.** Recovery: kept the pinned phrase. **Prevention:** grep the runbook test for a phrase before rewording it.
8. **The local affected gate was killed by an external SIGTERM in `.github/scripts/test/run-all.sh`.** Recovery: recorded as unresolved; CI `test-bun` passed at the head. **Prevention:** never read a killed gate as a pass. Name the CI leg that substitutes for it.
9. **The hook blocked a `pgrep -f`.** Recovery: used `proc.sh`. **Prevention:** already hook-enforced.
10. **Local #12850 failure ("seam can only RAISE the floor").** Recovery: matched to #12850, which is open, needs terraform installed, and CI skips. **Prevention:** tracked by #12850.
11. **I posted "no Doppler holder found" for the Origin CA token on public epic comment 7205049710 after searching only project `soleur`.** Recovery: edited the comment to state the search's scope and name the documented holder. **Prevention:** a negative finding names its search scope in the same sentence.
12. **The revoke needed the login that owns the token.** Several sign-in round trips with the operator passed before the right account was found. Recovery: the recipe now names the owning login, and the agent asks the operator to sign in rather than switching logins itself. **Prevention:** the recipe's step 3 text.
13. **An in-page `fetch` DELETE got an HTML 403 from the dashboard edge.** Recovery: a Node-side `page.request.delete` with an absolute URL. **Prevention:** the recipe's step 3.3 text.

## Tags

category: workflow-issues
module: plugins/soleur/skills/cf-token-scope, knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md
