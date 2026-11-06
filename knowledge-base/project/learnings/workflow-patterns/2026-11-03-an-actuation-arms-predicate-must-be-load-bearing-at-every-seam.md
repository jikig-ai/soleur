---
title: An actuation arm's predicate must be load-bearing at every seam — five near-misses in one diff
date: 2026-11-03
category: engineering
tags: [workflow-patterns, actuation, concurrency, bash, github-actions, review]
issue: '#10033'
---

# Learning: An actuation arm's predicate must be load-bearing at every seam — five near-misses in one diff

## Problem

Adding a bounded auto-redrive arm to the apply-delivery-gap follower (a second
job holding `actions: write` that re-dispatches a production apply), a
ten-seat review found **six independent ways the arm could fire when it
shouldn't or fire dead**:

1. **`declare` inside a bash function is function-local.** `declare
   "N_INFLIGHT_${key//-/_}=$n"` inside `count_inflight` looked like a global
   update — it dies on return, so the in-flight suppression was always 0 in
   production while the self-test (which sets the global directly) passed.
   Four seats caught it independently. `printf -v` assigns in the calling
   scope; a plain global assignment does too.
2. **`gh workflow run` with no checkout has no repo.** The dispatch job was a
   bare `gh` call — no `GH_REPO`, no `--repo`, no git dir — and fails at
   runtime with "not a git repository". Sibling dispatchers all pass `--repo`
   or `GH_REPO` explicitly; the failure is loud but the arm never actuates.
3. **The gate bounded the wrong thing.** Scoping suppression to the
   `deploy-fix` key ignored that the protected resource is the *shared* apply
   group + single tfstate: an `infra` `cancelled-mid-run` row (possibly-partial
   state) or any in-flight run of either key must suppress.
4. **No failure circuit-breaker.** The arm re-fires on `cancelled` later runs
   (still storming — correct), but a redispatched run ending `failure` never
   becomes a candidate row, so the original evicted rows would re-fire the arm
   forever, re-applying over possibly-partial state. The rows' `$7`
   latest-later-run label was already in the table — one more awk counter
   closes it.
5. **The body kept telling agents to run the manual dispatch** while the arm
   was about to do it — a double-dispatch into a 1-pending-slot group evicts
   the auto-run. Compute the predicate before render and print
   "auto-redrive in flight — do NOT dispatch" instead.
6. **The test pinned the shape, not the binding.** `runs == [...]` asserted
   the dispatch line exists *somewhere*; moving it into the ungated `follow`
   job stayed green. The pin must bind the dispatch to the gated job's step
   list.

## Solution

Ship the predicate as the control and make every seam fail closed:

- `emit_redrive_output` computes `REDRIVE_DEPLOY_FIX` before `reconcile_issue`
  so the issue body can conditional-render; true iff deploy-fix rows exist AND
  every row (any key) is `evicted-before-start` AND `N_INFLIGHT == 0` (total,
  either key) AND no later non-cancelled run exists.
- `GH_REPO` env on the dispatch step; `actions: write` job-scoped to `redrive`
  only; `if:` exact-string pinned by the W suite along with the per-job step
  binding (`gh workflow run` may appear only in `rsteps`).
- `self_test` exercises the emit through `GITHUB_OUTPUT` (the production write
  path), not only the predicate function's return.

## Key Insight

The defect class is **"the gate looked right but wasn't load-bearing at the
seam that mattered"**: a local-masquerading global, a missing env, a
key-scoped guard on a shared resource, a missing terminal-outcome breaker, a
stale instruction, a shape-pin without a binding-pin. For any new actuation
arm, the review checklist is exactly those six seams: write-path coverage,
runtime resolution, resource-vs-key scoping, terminal-state breaker,
instruction-vs-action consistency, binding-not-shape pins. ADR-189's
sense/adjudicate/actuate split scopes the *permission*; these six scope the
*predicate*.

## Tags

actuation-predicate, concurrency-groups, bash-declare-local, gh-cli-no-repo,
circuit-breaker, fail-closed, review-panel-value
