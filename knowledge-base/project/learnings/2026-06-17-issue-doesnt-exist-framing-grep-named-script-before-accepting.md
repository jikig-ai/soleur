# Learning: An issue's "X doesn't exist" framing about tooling must be grepped against the named script/symbol before it bounds scope

**Date:** 2026-06-17
**Issue:** #5495
**Category:** workflow-patterns

## Problem

Issue #5495 asserted "there is no inline Better Stack log-query path, and Sentry
access is partial," and its scope was written as "build inline access for both
vendors." Taken at face value, that framing would have produced a spec to build
something that **already shipped**.

## Solution

Phase 1.0.5 premise validation grepped for the *named capability* before accepting
the framing:

- `ls scripts/betterstack-query.sh` + `git log --reverse` → the Better Stack inline
  read CLI **and its runbook shipped in #4751**, weeks before the issue was filed.
- `git grep` for Sentry issue-read → `apps/web-platform/lib/inngest/sentry-issue-rate.ts`
  already reads Sentry issues in app code.

Scope collapsed from "build inline access for both" to "build only the thin Sentry
read-by-id CLI + wire the *existing* runbooks into the debugging skills." The operator
confirmed the narrowed scope.

## Key Insight

Two generalizable points:

1. **An issue's "X doesn't exist" claim about *tooling* is a point-in-time assertion
   that drifts.** The author writes from the frustration moment (here: the #5492
   cutover, when they didn't reach for the tool), not from a fresh repo grep. Before
   letting a "doesn't exist / is missing / no path for" framing bound the option space,
   `ls`/`git grep` the **named script or consuming symbol** and `git log --reverse` it.
   The capability-existence direction *understates* what exists (extends the
   `hr-verify-repo-capability-claim-before-assert` family to issue bodies, not just
   your own claims).

2. **Discoverability ≠ capability.** The real #5492 root cause was that the Better Stack
   tool *existed* but no debugging skill referenced it, so the agent never reached for
   it. When an issue says "we couldn't do X inline," distinguish "the tool is missing"
   from "the tool exists but nothing wires the agent to it" — the latter is a wiring
   fix, not a build.

3. **"Not Terraform-mintable" ≠ "not automatable."** The CTO assessed a read-only Sentry
   token as an operator-mint step because the Sentry provider exposes no Terraform token
   resource. The operator corrected: "done by Soleur per our workflow rules." A script
   hitting the Sentry internal-integration **API** is automation and satisfies
   `hr-exhaust-all-automated-options-before` / never-defer-operator-actions. IaC absence
   is not automation absence — check the vendor's API before labeling a step manual.

## Session Errors

- **`gh issue create --json` — invalid flag.** `gh issue create` has no `--json`
  output flag (unlike `gh issue view`/`list`); it failed at flag-parse so nothing was
  created. Recovery: re-ran without `--json` (the command prints the new issue URL on
  stdout directly) after a dup-guard `gh issue list --search`. **Prevention:** for
  `gh issue create`, capture the printed URL from stdout; don't reach for `--json`.
  One-off (my flag error, not a workflow gap).

## Tags
category: workflow-patterns
module: brainstorm, premise-validation
related: hr-verify-repo-capability-claim-before-assert, hr-exhaust-all-automated-options-before
