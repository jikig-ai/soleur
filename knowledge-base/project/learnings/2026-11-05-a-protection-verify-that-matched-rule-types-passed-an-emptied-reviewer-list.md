# Learning: presence-of-type is not content verify — a `protection_rules` check that matched rule types passed an emptied reviewer list and a non-main branch policy

## Problem

PR #12153 (#11923). `scripts/key-rotate.sh`'s `kk_chk_approval` is the live verify of the `key-rotate-approval` environment's protection, run on every rotate because a referenced-but-absent or drifted environment auto-creates UNPROTECTED and the workflow `environment:` binding alone is not proof of protection. The first version asserted only that `protection_rules` contained the types `required_reviewers` and `branch_policy`. Review found the type-presence shape passes a drifted environment: a `required_reviewers` rule whose reviewer list was emptied, and a branch policy that admits a non-`main` ref, both carry the right types with the wrong contents — the gate would certify an approval environment that gates nothing.

## Solution

Verify the contents each type must hold, and read the paginated policy list in full (commits d7f9da2552, 5ef3082cd8; `kk_chk_approval` at `scripts/key-rotate.sh:444`, mirrored inline in the inngest workflow's `envverify` step because that job runs no checkout):

```bash
# 1. types present (necessary, not sufficient):
jq -e '[.protection_rules[]? | .type] | index("required_reviewers") and index("branch_policy")'
# 2. the required_reviewers rule actually lists a reviewer:
jq -e '[.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]?] | length > 0'
# 3. deployment-branch-policies, read with --paginate, is non-empty and main-only:
gh api --paginate "repos/${GITHUB_REPOSITORY}/environments/key-rotate-approval/deployment-branch-policies" \
  | jq -e '.branch_policies as $p | ($p | length) > 0 and all($p[]; .type == "branch" and .name == "main")'
```

Every arm fails closed to `approval_environment_unprotected` — including an unreadable read, which is treated as an unprotected environment, not a retry.

## Key Insight

A protection verify that asks "does a rule of this type exist" certifies the schema, not the protection. For each protection type the check depends on, name the content property that makes it protective (non-empty reviewer list, main-only policy set, non-empty policy collection) and assert THAT — and use `--paginate` on list endpoints so a second page cannot hide the drifted row. Same shape as `2026-11-04-an-absence-pin-measures-its-scan-window-not-the-property-it-names.md`: the predicate must cover the property the prose claims.

## Session Errors

1. **The first cut of the verify asserted type-presence only** — the content properties were added under review. **Prevention:** for any "X is protected/enabled" check, write the drift case first ("X present but emptied/widened") and assert the content property, per the verify's own comment block at `scripts/key-rotate.sh:437`.
2. **The first envverify comment claimed the script "cannot carry" the check because it is sha256-pinned** — wrong reason; the approve job runs no checkout and `scripts/inngest-key-rotate.sh` does not source `kk_chk_approval`. Recovery: comment corrected in the round-2 fix. **Prevention:** name the mechanism that actually prevents reuse (no checkout + unsourced script), not a plausible-sounding one.

## Tags
category: security-issues
module: scripts/key-rotate.sh, .github/workflows/inngest-key-rotate.yml, apps/web-platform/infra/key-rotate-approval-environment.tf
