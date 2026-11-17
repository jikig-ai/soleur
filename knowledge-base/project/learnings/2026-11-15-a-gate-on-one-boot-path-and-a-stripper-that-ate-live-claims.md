---
title: A confirm gate on one boot path, a note stripper that ate live claims, and a floor copy that lost its lib
date: 2026-11-15
category: workflow-issues
module: apply-web-platform-infra.yml, seo-config-rules rollback guard, logtail alert tests
tags: [review, fix-round, typed-confirm, user_data, mutation-test, legal-docs]
issue: 10479
pr: 12737
---

# Learning: a confirm gate on one boot path, a note stripper that ate live claims, and a floor copy that lost its lib

## Problem

PR #12737 (closes #10479 and #10538) moves the Cloudflare origin to `strict` and gives
the Inngest host a public `--sdk-url` poll. Round 1 of the review found three defects,
and the verifier found the second-order version of each.

1. **The typed-confirm gate covered one boot path.** `inngest_host_replace` got the
   `PUBLIC-SDK-URL` token. But `hcloud_server.inngest` has no `ignore_changes=[user_data]`,
   so two more paths boot the public sdk_url:
   - the `inngest_host` birth job, which had no gate;
   - an operator-local untargeted `terraform apply` (the OPERATOR_APPLIED_EXCLUSIONS
     break-glass), which no workflow gate can reach.

   `plan-sharp-edges.md` already says "enumerate EVERY workflow that can apply it"
   (#8705). The plan applied that rule to the workflows that apply the change. It did
   not apply it to the paths that boot the changed payload.
2. **The rollback-coupling guard stripped live claims.** The guard drops correction notes
   such as `*(Corrected 2026-…)*` before it counts TLS claims in the legal docs. Its regex
   stripped every `*( … )*` span. That included present-tense notes on the Last Updated
   lines, like `*(Section 11 now says …)*`, which are live claims about the current text.
   The real-tree counts moved from 26 to 36 (flexible) and from 15 to 21 (full) once only
   past-tense notes were stripped.
3. **The floor mutation lost a newly extracted lib.** The `mutate_floor_red` row copies the
   test to scratch and lowers its assertion floor. The copy resolved `REPO` from its own
   location, so after `logtail-pair-census.awk` was extracted, the copy could not find the
   lib. It failed for that reason, not because of the floor. The row asserted only a
   non-zero rc, so it stayed green while measuring nothing.

## Solution

- **Gate:** one shared script, `tests/scripts/lib/inngest-public-sdk-url-confirm.sh`. It
  runs as step 2 of both jobs, with distinct tokens (`PUBLIC-SDK-URL` and
  `PUBLIC-SDK-URL-BIRTH`). Pin test B10 checks, for each job:
  - the step position, with no `if`, `continue-on-error` or `shell` on the step;
  - no job-level `env`;
  - checkout has no `with`;
  - no later `always()` step touches secrets.

  A recipe sweep makes every documented dispatch recipe carry its token. The untargeted
  apply cannot be gated, so it is documented instead: the pinned-image full-apply echo
  and the runbooks say to abort if the plan replaces `hcloud_server.inngest` while #12742
  is open.
- **Stripper:** strip only past-tense `*(Corrected|Added|Updated|Changed|Removed …)*` notes.
  sdk_url now uses an allowlist: only loopback or 10.0.1.0/24 counts as private.
- **Floor copy:** rewrite `REPO` in the copy and pass `PAIR_CENSUS_AWK`. Assert the
  `[FATAL] assertion floor` line and the absence of any `[FAIL]` row, not just the rc.

## Key Insight

A guard is only as good as the set it ranges over, and each of these guards was built from
the path or shape I was looking at:

- the gate ranged over the job I had edited;
- the stripper ranged over the note shape I wanted gone;
- the mutation copy ranged over files that existed when it was written.

The fix in each case was to name the set first, then gate or test each member:

- every path that renders the payload;
- every tense of a note;
- every file the copy must carry.

A non-zero rc says that something failed. Only the specific line says what failed.

## Session Errors

1. **A decision-challenges row of class `record` was rejected by the ruling gate** (forwarded from plan phase). Recovery: removed the row. **Prevention:** decision-challenges rows carry CTO/CLO rulings only; records go in the plan.
2. **The ADR-321 amendment was renumbered to item 13** (forwarded). Recovery: renumbered. **Prevention:** re-read the ADR's last amendment number from fresh `origin/main` before writing one.
3. **Plan review and deepen were scaled down because the machine was saturated** (forwarded). Recovery: the review panel ran in full later. **Prevention:** one-off. Disclose the scale-down in the PR body.
4. **`lint-encryption-posture.py` was red on origin/main** (rows 6 and 7 expired 2026-11-12) until #12733 landed (forwarded). Recovery: merged origin/main after #12733 merged. **Prevention:** already tracked by #12733's expiry renewal. A pre-existing red on main is evidence to cite, not to fix in this PR.
5. **The issue-create hook blocked a heredoc and `gh issue create` in one command.** Recovery: wrote the body with the Write tool, then ran `gh issue create --body-file`. **Prevention:** already hook-enforced. Always write the body file first.
6. **The technical-ruling-gate rejected the D1 row's shape, and the drafted ruling was not the CTO's.** Recovery: asked the CTO agent to rule. It chose a full-first rollback in this PR, unlike the draft. **Prevention:** never draft a ruling's text before the agent rules. Ask first, then record its words in the "Ruled by CTO agent, <date>: <decision> - <reason>" shape.
7. **The recipe sweep false-positived on two prose lines** that name the selector in backticks. Recovery: exempted backtick prose spans and mutation-checked that real recipes still fail. **Prevention:** run a new sweep on the real tree before committing, and read every hit.
8. **The real-tree counts changed after the stripper was narrowed** (26→36, 15→21). Recovery: predicted both numbers by hand before updating the constants, and they matched. **Prevention:** a count constant changes only after an independent hand prediction.
9. **`gh run list` returned an API EOF.** Recovery: used `gh api repos/:owner/:repo/actions/runs`. **Prevention:** one-off transient.
10. **The confirm gate covered the replace path only** (Problem 1). Recovery: added the shared script to both jobs, B10 and the documented abort for the untargeted path. **Prevention:** extend the #8705 enumeration to paths that boot the changed payload: replace, birth and operator-local untargeted apply (routed to `plan-sharp-edges.md`).
11. **The correction-note stripper stripped present-tense claims** (Problem 2). Recovery: stripped past-tense notes only. **Prevention:** a stripper that removes text before a count needs one fixture per tense: the stripped shape and the shape that must survive.
12. **The floor mutation copy lost the extracted lib and stayed green on rc alone** (Problem 3). Recovery: asserted the `[FATAL] assertion floor` line and the absence of `[FAIL]`. **Prevention:** routed to `work-test-harness-sharp-edges.md`.
13. **quality-guards is red on the ubuntu-26.04 runner** because `timeout -s KILL` returns 124 there, not 137. Recovery: filed #12781 (systemic, not caused by this PR). **Prevention:** tracked by #12781.

## Tags

category: workflow-issues
module: apply-web-platform-infra.yml, seo-config-rules rollback guard, logtail alert tests
