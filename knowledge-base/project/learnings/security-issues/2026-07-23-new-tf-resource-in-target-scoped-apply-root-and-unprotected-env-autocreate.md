---
title: A new *.tf resource in a -target-scoped apply root is never applied — and a referenced GitHub environment auto-creates WITHOUT protection, shipping a vacuous required-reviewer gate
category: security-issues
module: apps/web-platform/infra
tags: [terraform, github-actions, -target, required-reviewer, environment, apply-pipeline, keyless-cosign, promotion-pointer]
issue: 6780
pr: 6839
date: 2026-07-23
---

# Learning: a new `.tf` resource in a `-target`-scoped apply root ships un-applied, and a referenced GitHub environment auto-creates unprotected

## Problem

PR #6839 (ADR-135 config-refresh channel foundations) added a HARD-7 human-ack gate: a
`github_repository_environment.inngest_config_signing` with `reviewers.users = [54279]`, referenced
by the signing workflow as `environment: inngest-config-signing`. The intent — a compromised/rogue
CI actor who dispatches the keyless-signing workflow is held in "Waiting" for operator approval
before any bundle is signed. This is the ADR's *named top residual RCE path* mitigation.

It shipped **vacuous**. Two independent infra facts, each invisible to `terraform validate`, `tsc`,
and the green PR branch:

1. **`apply-web-platform-infra.yml` is a `-target=`-scoped apply, not a full-root apply.** Terraform
   prunes every resource NOT named in the explicit `-target=<addr>` allow-list. A bare new `*.tf`
   file is therefore *never created* — the workflow's own header (line ~288) states the convention
   verbatim: "a new `apps/web-platform/infra/*.tf` resource MUST get a matching `-target=<addr>`."
   The new environment was not added, so no push/manual apply would ever create it.

2. **A referenced-but-nonexistent GitHub `environment:` is auto-created WITHOUT protection rules on
   first use.** So the first `workflow_dispatch` does NOT wait for a reviewer — it runs immediately,
   keyless-signs with the workflow's trusted OIDC identity, and pushes. The human gate the entire
   threat model rests on is silently absent. (`workflow_dispatch` can even run from a feature branch
   before merge.)

The TF file's own header comment *asserted the opposite* — "Applies via the normal
apply-web-platform-infra.yml path" — a false self-claim that read as reassurance.

A **second, adjacent** trap on the same PR: `var.inngest_config_digest` (the promoted digest
pointer) was declared with **no default**, mirroring the sibling `betterstack_logs_token`. But
Terraform resolves ALL root variables *before* `-target` pruning, and the apply pipeline runs
`doppler run --name-transformer tf-var -- terraform plan` over the whole root. So a no-default var
with no provisioned `TF_VAR_*` value breaks EVERY apply (including unrelated ones) between merge and
the cutover that finally sets it — a self-inflicted apply-pipeline outage.

## Root cause

Both are the same shape: **a new resource/variable in a whole-root-resolved, `-target`-scoped apply
pipeline has cross-cutting obligations that are not local to its `.tf` file.** The `.tf` compiles,
`validate` passes, the feature's own tests pass — but the resource's *reachability* (will it ever
apply?) and the variable's *resolvability* (does the whole-root plan still resolve?) live in the
apply-workflow YAML, not the resource file. Mirroring a sibling `.tf` copies the resource shape but
NOT the sibling's apply-pipeline wiring or its provisioning preconditions.

The security sharpener: for a `github_repository_environment` used as a required-reviewer gate, "not
applied" does not fail closed — GitHub's auto-create-on-reference makes it fail **open** (a gate with
no rules). A guard that is never installed is worse than no guard, because the workflow *declares*
`environment:` and everyone reads that as "gated."

## Solution

1. **Wire the new resource into the apply allow-list in the same PR.** Append
   `-target=github_repository_environment.inngest_config_signing` next to the sibling
   `-target=github_repository_environment.inngest_cutover` in `apply-web-platform-infra.yml`. Correct
   the `.tf` header to state the `-target=` requirement instead of the false "applies via the normal
   path" claim.
2. **For a required-reviewer environment gate, treat "the environment exists WITH reviewers" as a
   precondition of the workflow being considered live** — never rely on auto-create. Apply the env
   TF before (or with) the workflow that references it.
3. **For a promotion-output / dark-state TF var** (a pointer whose legitimate initial value is
   "nothing promoted yet"), give it `default = ""` — the honest empty sentinel. This is NOT a
   `hr-tf-variable-no-operator-mint-default` violation: that rule targets *secrets* a default would
   let an operator skip minting; a CI promotion output whose absence is a valid state is different,
   and the empty default keeps unrelated whole-root applies from failing var-resolution. Exclude the
   consuming resource from the `-target` list until it is meant to apply, so the empty never
   propagates.

## Key insight

When adding **any** new `.tf` resource to a `-target`-scoped apply root, ask two questions the
resource file cannot answer:

- **Reachability:** is it in the apply workflow's `-target=` allow-list? (`grep -n '<resource-addr>'
  apply-*.yml`). If not, it never applies — and for a `github_repository_environment` gate that means
  it fails OPEN (auto-created unprotected), not merely absent.
- **Resolvability:** if it introduces a `variable` with no default, does the whole-root
  `terraform plan` still resolve for EVERY (even unrelated) apply between now and when its value is
  provisioned? A promotion-output/dark-state var wants `default = ""`.

Mechanical review gate: for a PR adding a `github_repository_environment` (or any resource whose
*absence fails open*), the reviewer must `grep` the apply workflow's `-target=` set and confirm the
new address is present; a green feature branch proves neither reachability nor the auto-create-open
behavior. security-sentinel caught this here; a work-time self-check would catch it earlier.

## Session Errors

- **New `github_repository_environment` `.tf` not wired into the apply `-target=` allow-list (P1).**
  Recovery: added the `-target=` + corrected the false `.tf` header. Prevention: work-time/review
  grep of the apply workflow's `-target=` set for every new `.tf` resource address; the
  auto-create-unprotected behavior makes this security-relevant, not cosmetic.
- **Promotion-pointer var declared with no default → whole-root apply-resolution outage (P2).**
  Recovery: `default = ""`. Prevention: dark-state/promotion-output vars take an empty default;
  no-default is for secrets an operator must consciously mint.
- **Packager SORT assertion coincidental + false "sorted by basename" claim (P2).** Recovery:
  `sort -k2` + a coincidence-breaking fixture (assign the alphabetically-first basename to the
  larger-hashing content so sha-order and basename-order are opposite). Prevention: an ordering test
  is vacuous unless the fixture's sort-keys are deliberately made to disagree.
- **`new-scheduled-cron-prefer-inngest` hook denied a `scheduled-*.yml` write twice on `cron:` inside
  DOCSTRING prose (`{ cron: }`), not a real schedule trigger.** Recovery: renamed to
  `inngest-config-drift.yml` (dropped the `scheduled-` prefix; the file is Inngest-dispatched, so the
  prefix was a misnomer anyway). Prevention: a workflow that is Inngest-dispatched (not
  `schedule:`-triggered) should not carry the `scheduled-` prefix; if it must, avoid the literal
  `cron:`/`schedule:` token in comments, or use the documented gate-override marker.
- **Test negative anchors (`not.toContain("betterstack-query")`) false-failed on the SUT docstring
  that legitimately names those files.** Recovery: switched to execution-construct anchors
  (`spawn(`, `execFile`, `readFileSync`). Prevention: re-hit the documented "anchor on syntax not a
  bare token; a body/source negative false-matches the file's own comments" class — never anchor a
  negative on a token the file also documents in prose.
- **routine-metadata description exceeded the 160-char parity limit.** One-off; parity test caught it.
- **Explore agent died mid-stream (transient API stall); initial `ls` ran at the bare-repo root;
  force-push needed after the start-of-session rebase rewrote pre-existing SHAs.** One-offs.
