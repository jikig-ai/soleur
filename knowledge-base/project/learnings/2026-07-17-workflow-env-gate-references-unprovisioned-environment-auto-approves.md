---
title: A workflow_dispatch job that declares `environment: X` but never provisions X in Terraform is a silent auto-approve hole
date: 2026-07-17
category: security-issues
module: infra/github-environments
tags: [github-environments, terraform, workflow_dispatch, auto-approve, luks-cutover, dp-11]
issue: 6604
pr: 6638
---

# Learning: an unprovisioned `environment:` gate auto-approves the run it was meant to gate

## Problem

The `/workspaces` LUKS live-cutover mechanism (merged 2026-07-17) shipped
`.github/workflows/workspaces-luks-cutover.yml`, whose freeze job declares
`environment: workspaces-luks-cutover` and documents it, in its own header, as *"the
ONLY human authorization"* on an irreversible freeze of sole-copy user data
(passphrase/header loss ⇒ unreadable forever). The intent was a required-reviewer gate.

But the environment was **never provisioned**: `gh api
repos/<org>/<repo>/environments/workspaces-luks-cutover` returned **404**, and no
Terraform resource defined it — while the sibling `inngest-cutover` gate WAS
Terraform-provisioned (`github_repository_environment.inngest_cutover`). CI stayed green
because a missing environment is not a build error; it is a **runtime** hole.

GitHub **auto-creates an environment on first reference with zero protection rules**, so
the first `workflow_dispatch` of the freeze would have manufactured a zero-reviewer
environment and **auto-approved the irreversible freeze with no human ack** — the exact
DP-11 F8 failure the workflow header warned about.

## Solution

Provision the gate in Terraform, mirroring the approved `inngest_cutover` precedent 1:1
(only the resource name + `environment` string differ), and wire its `-target` into the
DEFAULT (push / `manual-rerun`) allow-list apply block — NOT the scoped cutover apply,
whose sourced gate asserts an exact create-set and would abort on a sixth create. Then
correct the runbook, which had mis-framed the environment as a manual "operator
precondition" (that framing was itself the bug vs `hr-all-infrastructure-provisioning-servers`).

Added a fail-closed CI guard (`terraform-target-parity.test.ts`): every
`github_repository_environment` in the infra root must declare a non-empty
`reviewers.users`, with a non-vacuity assertion that the extractor actually saw the known
env gates. Mutation-verified (emptying `users` → RED).

## Key Insight

**When a `workflow_dispatch` job declares `environment: X` as a safety gate, `X` being
declared in the workflow is NOT the same as `X` existing with reviewers.** A missing or
zero-reviewer environment does not fail CI — GitHub silently auto-creates it and
auto-approves. Two independent checks are load-bearing:

1. The environment must be **Terraform-provisioned** (`github_repository_environment`
   with a non-empty `reviewers.users`), reachable from `terraform apply` — not a manual
   operator precondition. Verify with `gh api .../environments/<name>` returning 200 +
   non-empty `protection_rules[].reviewers`.
2. A **pre-merge assertion** should guard reviewer non-emptiness; Terraform state alone
   self-heals drift only on the next apply, and a code edit emptying the reviewer literal
   otherwise ships silently.

Routing corollary (`/go`): "run the cutover" against a shipped-but-ungated mechanism is a
premise to verify, not an instruction to execute. Pulling the live state (env 404, no run
history) reframed the ask from *dispatch the freeze* to *the freeze cannot be dispatched
safely until its authorization gate exists* — and the freeze itself stays operator-dispatched.

## Session Errors

1. **Ran `./node_modules/.bin/vitest` at the repo root** for `plugins/soleur/test/*.test.ts`
   → exit 127 (no root vitest binary). **Recovery:** the plugin `.ts` suite runs via `bun
   test plugins/soleur/` (see `scripts/test-all.sh` — the `bun` shard). **Prevention:**
   for a `plugins/soleur/test/*.ts` file, invoke `bun test <path>`, not vitest; vitest is
   the `apps/web-platform` runner.

## Tags
category: security-issues
module: infra/github-environments
