---
title: An import block breaks terraform test, and a count-based ack reaches every destroy in the plan
date: 2026-09-27
category: integration-issues
module: apps/web-platform/infra
tags: [terraform, import, terraform-test, destroy-guard, ack-destroy, parity-test, mutation-testing]
issue: 8754
pr: 9062
---

# Learning: adopting a live resource by `import` has two blast radii a green `validate` cannot see

## Problem

#8754 PR-B adopted a GitHub deployment policy that had been created outside Terraform
(`import` into a new address plus `removed { destroy = false }` for the phantom one), and in the
same merge destroyed an orphaned Doppler secret, which needs `[ack-destroy]`.

1. `terraform validate` passed, but `terraform test` (registered in infra-validation) failed every
   run block: `Invalid import request: Cannot import resources from mock providers`. The existing
   `seo-config-rules.tf` import behaves differently because it names the unmocked
   `cloudflare.rulesets` alias, so it reads the REAL API instead of erroring. The two comments in
   the same tftest file then appeared to contradict each other.
2. The destroy guard's `[ack-destroy]` is a boolean over `destroy_count`, not an address list. The
   merge that carries the ack for one intended destroy also approves a replace of the freshly
   imported policy (the main-only pin that gates host birth), should the import read differ from
   config at merge time.

## Solution

- `override_resource { target = <import target> }` inside the mocked provider in the tftest; a
  comment names why and ties its removal to the import's removal.
- `lifecycle { prevent_destroy = true }` on the adopted resource, so no ack can wave its destroy
  through; the parity test pins it.
- Confirm before merge that the live object matches config exactly (`GET …/deployment-branch-policies/<id>`
  returned `type: branch`, `name: main`), because a non-`branch` type would read back as
  `tag_pattern` and force a replace.
- Negative guards ("no workflow targets the gated resources") read the whole write surface: every
  workflow that plans the root, both `-target=X` and `-target X` spellings, no `*.tf.json`, no
  `-var`/`TF_VAR_` override of the gate variable. The first version read one workflow and one
  spelling; a test-design seat found 11 surviving one-line mutants on exactly those axes.

## Key Insight

A config-driven `import` is not a static change: it performs a read in every plan that reaches it
(mocked tests, `-refresh=false` PR plans, the untargeted drift plan). Enumerate every plan that
evaluates the root and ask what each one does with the import. And when a merge must carry a
count-based ack, anything else destructive in that plan rides on it, so make the resources you
cannot afford to lose ack-proof with `prevent_destroy`.

## Session Errors

1. **`git stash list` in a diagnostic command** — blocked by the stash hook. Recovery: re-ran without it. Prevention: already hook-enforced.
2. **A comment-only edit to `arm-heartbeats.sh` tripped `lint-shell-trace-credential-refusal.py --changed`** (the file is baselined, so any edit owes its xtrace-refusal and `curl --disable` debt). Recovery: reverted; the stale comment is on #9060. Prevention: work skill check 6.5 already says to grep the two baselines before editing; run it before a drive-by comment fix too.
3. **Unconditional `import` broke `terraform test`** — see Problem. Recovery: `override_resource`. Prevention: run `terraform test` whenever an `import` block is added (routed to the work skill's Infrastructure Validation list).
4. **`lint-infra-no-human-steps --changed` flagged a runbook sentence** that co-located "operator" and "terraform". Recovery: reworded. Prevention: run the lint in CI's `--changed` form before pushing runbook edits.
5. **Sandbox-worktree mutation control was red** (`Cannot find package 'yaml'`): this repo's worktrees have no `node_modules`; bun resolves packages from the parent repo root, which a `/var/tmp` worktree cannot reach. Recovery: symlink `<repo-root>/node_modules` into the sandbox. Prevention: run the unmutated control first and treat red as VOID (the battery did).
6. **Inline `python3 -c` mutations failed to land** on nested quoting. Recovery: wrote the battery as a script file with a landing check per row. Prevention: never build mutations through shell-quoted one-liners.
7. **The Terraform review seat returned a status line as its final message twice.** Recovery: resumed with a mandate to write the report to a file and reply `WROTE <path>`. Prevention: the review skill already says to mandate file delivery in the SPAWN prompt; do it for every long-running seat.
8. **Two false sentences:** a self-written "a destroy of the phantom would delete the live pin" (unmeasured; a DELETE of policy id 0 would 404), and the plan's inherited "ARMED and rolled-back-to-paused both leave no drift", which omitted that a no-beat rollback fails the arm step and turns every later merge apply red. Recovery: corrected both; measured the feeder live (both web hosts log `GIT_DATA_HEARTBEAT_URL unset — reachable but cannot ping` every 60 s) and amended ADR-149. Prevention: for every causal sentence a diff adds or inherits, name the falsifying command and run it.
9. **`markdownlint` fed by a two-dot `git diff --name-only origin/main`** included a file only `main` had changed. Recovery: used the merge base. Prevention: diff against `$(git merge-base origin/main HEAD)` when listing a branch's own files.

## Tags

category: integration-issues
module: apps/web-platform/infra
