---
title: '"Merge IS authorization" rests on CODEOWNERS review a single-maintainer repo structurally cannot enforce'
date: 2026-06-03
category: best-practices
tags: [branch-protection, codeowners, authorization, terraform, ci, solo-repo, plan-ac]
issue: 4844
pr: 4845
---

# "Merge IS authorization" rests on CODEOWNERS review a solo repo cannot enforce

## Problem

#4844 generalized a CF Tunnel CI-apply bridge so that merging a PR auto-applies
on-host hardening (apparmor/seccomp/fail2ban/journald) to the single prod host
over root SSH. The plan's authorization model — adopted verbatim from #4830 and
`hr-menu-option-ack-not-prod-write-auth` — was: **"the reviewed, CODEOWNERS-gated
merge IS the human prod-write authorization."** The plan elevated this to a P1
pre-merge gate (AC11): *confirm `main` branch protection requires CODEOWNERS
review and cite the enforced ruleset in the PR body.*

At /work AC11-verification time the premise was **falsified**:

```bash
gh api repos/jikig-ai/soleur/rulesets --jq '.[] | {name, enforcement}'
# → "CI Required", "CLA Required", "Force Push Prevention" — all required-status-checks
gh api repos/jikig-ai/soleur/branches/main/protection
# → 404 "Branch not protected"
```

No ruleset carries a `pull_request` rule with `require_code_owner_review`. The
"merge IS authorization" model was resting on an enforcement layer that **does
not exist**.

## Root Cause

On a **single-maintainer** repo the CODEOWNERS-review gate is not merely missing
— it is **structurally unsatisfiable**. GitHub forbids approving your own PR, so
a `require_code_owner_review` rule with `required_approving_review_count ≥ 1`
would block *every* solo merge (there is no second person to approve). The repo
therefore cannot enforce CODEOWNERS *review* without halting all delivery. The
real, enforceable control is:

- **sole-admin merge authority** — only @deruelle can merge to `main`; the
  deliberate merge click IS the human authorization, AND
- **required-status-checks + force-push-prevention rulesets** (which now include
  the new `terraform-target-parity` test).

CODEOWNERS files still matter as **review-routing / discoverability**, but on a
solo repo they are advisory, not an enforced merge gate.

## Solution

1. **Surface, don't paper over.** When a plan AC asserts a branch-protection /
   authorization fact, *query the live ruleset* (`gh api repos/<o>/<r>/rulesets`
   + `.../branches/main/protection`) and treat the result as load-bearing. If it
   contradicts the plan, escalate to the user — the authorization model for
   prod-write is genuinely the operator's decision, especially at a
   `single-user incident` brand-survival threshold. Do **not** fabricate the AC
   citation.
2. **State the accurate posture in the PR body** instead of the assumed one:
   "Prod root-write is gated by sole-admin merge authority + active
   required-status-checks/force-push rulesets; `require_code_owner_review` is N/A
   on a single-maintainer repo (no self-approval). CODEOWNERS is advisory
   routing." `user-impact-reviewer` CONCUR was explicitly *conditional* on the PR
   body stating this accurately.
3. **The marginal-delta test for acceptability.** Generalizing prod-root-write
   from 2→9 resources was acceptable *only because the trust boundary was already
   crossed by the live #4830 bridge* — the merge principal is unchanged; only the
   payload one merge can push grew. The same control would **not** be acceptable
   for a net-new root-write path.

## Key Insight

"Merge IS authorization" is a **two-part** claim: (a) the merge is a deliberate
human act, and (b) *something enforces who can merge what*. On a multi-maintainer
repo (b) is CODEOWNERS review; on a **solo** repo CODEOWNERS review is
structurally impossible and (b) collapses to "only the admin can merge + status
checks must pass." A plan that writes "CODEOWNERS-gated merge" as a verifiable AC
on a solo repo is asserting an enforcement layer that cannot exist — verify the
live ruleset before depending on it, and weigh the change on *marginal trust-
boundary delta*, not on the absolute prod-write capability.

## Session Errors

- **Initial plan read targeted the bare-repo path, not the worktree.** The plan
  lived at `.worktrees/feat-ci-tunnel-apply-generalize/knowledge-base/...`; the
  first `Read` used the repo-root-relative path and failed `File does not exist`.
  — Recovery: re-read from the worktree path the `/work` arg supplied verbatim.
  — Prevention: in `/work` pipeline mode, resolve plan/artifact paths against the
  worktree root the arg names, never the process cwd (which starts at the bare
  repo). Mirrors `hr-when-in-a-worktree-never-read-from-bare`.
- **AC1 literal `grep -c 'secrets\.' == 0` returned 3** — the token appeared in
  `action.yml` *comments* ("composite actions cannot read `secrets.*`"), not in
  any functional `${{ secrets.* }}`. — Recovery: reworded the comments to "the
  `secrets` context" / "repository secrets". — Prevention: when an AC is a literal
  `grep <token> == 0`, avoid the literal token even in prose/comments, or the
  reviewer's own grep yields a false positive.
- **`terraform fmt` realigned `use_lockfile`** — inserting a 6-line comment above a
  single-line assignment broke `fmt`'s `=`-alignment group, so `fmt -check`
  flagged it. — Recovery: `terraform fmt`. — Prevention: expected formatter
  behavior; run `terraform fmt` (not just `-check`) after editing HCL comment
  blocks adjacent to aligned assignments. (Also: a comment that cites a line
  number like `main.tf:13` rots when you insert lines above it — cite the
  symbol, not the line.)

## Related

- `hr-menu-option-ack-not-prod-write-auth` — the rule this learning qualifies for
  the solo-repo case.
- `hr-verify-repo-capability-claim-before-assert` — same family: verify the live
  capability before asserting it.
- #4830 (the live bridge whose trust boundary this PR reused), #4840 (the
  APP_DOMAIN_BASE fallback carried into the extracted action).
