---
module: System
date: 2026-11-01
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "The CLA merge-queue verifier refused candidates as 'tampered pairing' because merge_group.head_ref's embedded oid != the candidate's head_sha — ejecting healthy rebuilt and multi-member entries (#11688, #11739, #11734 among them)"
  - "Every post-#11681 rejection in merge-queue-cla-synthetics.yml was a false positive: the embedded oid is minted at group (re)creation and legitimately diverges from head_sha on rebuilds"
root_cause: wrong_assumption
resolution_type: workflow_improvement
severity: medium
tags: [merge-queue, graphql, adr-270, clarify-binding-vs-provenance, hotfix-11753]
---

# Learning: a mint-time embedded identifier is provenance — the per-entry record is the binding

## Problem

`scripts/merge-queue-cla-verify.sh` bound `merge_group.head_ref`'s embedded oid
(the `<sha>` in `gh-readonly-queue/main/pr-<N>-<sha>`) to the candidate's
`head_sha` and refused the pair as tampered when they differed. That equality
is only true at mint time: GitHub mints the ref at group creation, and on
rebuilt or multi-member candidates the embedded oid records the group's
integrated head at that mint — which legitimately diverges from the candidate
build's `head_sha` being verified now. The strict check ejected real PRs
(#11688, #11739, #11734 in a single window; hotfix #11753 demoted the check
to provenance-only and pinned the regression row).

## Solution

Two identifiers can name the same object at different times: the oid embedded
in the queue ref is provenance — an audit trail of what the group looked like
when minted — while the *binding* is each entry's own `headCommit.oid ==
HEAD_SHA`, read live from `mergeQueue.entries` at verify time. When a system
carries both a mint-time identifier and a per-entry record, bind on the
per-entry record, treat the minted one as audit context (log it; never gate on
it), and write the regression row that exercises legitimate divergence
(rebuild, multi-member group) before trusting the check — the verifier had a
tamper-fixture row but no divergence fixture, so the false-positive arm was
the only one ever exercised. Measured after the hotfix: nine consecutive
synthetics runs green, `anchor=headCommit` on every grouped landing
(ADR-270 addendum 2026-11-01).
