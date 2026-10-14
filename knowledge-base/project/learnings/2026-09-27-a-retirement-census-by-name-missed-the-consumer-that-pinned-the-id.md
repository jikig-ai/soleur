---
title: A retirement census by name missed the consumer that pinned the ID
date: 2026-09-27
category: integration-issues
module: apps/web-platform/infra
tags: [retirement, census, inngest, follow-through, doppler, destroy-guard, terraform]
issue: 8714
pr: 9071
---

# Learning: retiring something is a search over every way it is REFERENCED, and a name is only one of them

## Problem

ADR-096 task 5.4 retired the disabled GHCR token minter (an Inngest function), its read/write Doppler service token, and the revoked GHCR read credential. The plan ran a whole-repo consumer census: case-insensitive grep over every spelling of the names (`ghcr_read`, `GHCR_MINTER`, `cron-ghcr-token-minter`, …), with a disposition per hit. The census was thorough and it was still incomplete in three ways that surfaced only at review and in CI:

1. **A consumer pinned the function by UUID.** `scripts/followthroughs/inngest-soak-6178.function-ids.txt` lists the 52 cron function IDs the #6178 soak probe scans. It is UUIDs only, so no name-grep can find it. The probe's registry gate refuses (`registry_drift`, exit 3) when any pinned ID leaves the Inngest registry, so once the deployed app stopped serving the minter the live soak (which posts a daily verdict on #6178) would have been unreadable every sweep until its stale date.
2. **A guard had no route for an intended destroy.** `tests/scripts/test-infra-privileged-tier-census.sh` G4c refuses any resource block the base declares and HEAD deletes without a `removed` block, and G4a refuses `removed` blocks without `destroy = false`. Both are right for the App identity they protect, and together they made every intentional Terraform destroy impossible. The #9062 precedent never hit it because that resource block had been deleted long before G4c existed.
3. **Identical value hashes were read as inheritance.** The four GHCR keys showed the same value hash in `prd`, `prd_terraform`, `prd_ghcr` and `prd_scheduled`, and the plan called them inherited. Doppler's activity log shows `prd_terraform` holds its OWN `GHCR_READ_USER`/`GHCR_READ_TOKEN` entries, written an hour before `prd` root had them. A root delete likely leaves them.

## Solution

- The soak probe got a `RETIRED_IDS` list: a retired ID stays in the population (its in-window runs are still scanned) but may be absent from the registry, and the unmeasured-function count subtracts it. Rows C0e/C0f pin both halves; mutants removing either go RED.
- The census got an `INTENDED_DESTROYS` allowance. An address is honoured only when its root's per-merge apply still targets it bare, and never for the App identity pair (new row G4f). M-g4-6 (accept) and M-g4-7 (untargeted, RED) pin it.
- The branch-config copies moved to the post-merge verification (names per config) and the #9080 follow-up.

## Key Insight

A retirement census must enumerate every IDENTIFIER the retired thing has, not only its names: function UUIDs, resource IDs, token slugs, monitor slugs. Then run the repo's own destroy/census guards against the planned deletion before calling the census complete. "Nothing references it" is a claim about a search, and a search keyed on names is structurally blind to ID-pinned consumers. The same shape one level down: two stores agreeing on a value says nothing about whether one derives from the other. Read the store's own provenance (Doppler's log) before asserting inheritance.

## Session Errors

1. **The census missed the UUID-pinned soak population.** Recovery: review P1, fixed with `RETIRED_IDS`. **Prevention:** grep opaque identifiers too (routed to `plan-sharp-edges.md`).
2. **Inheritance was asserted from matching hashes.** Recovery: the structural seat read the Doppler log; the post-merge check reads names per config. **Prevention:** same Sharp Edges bullet.
3. **A new comment cited `github-app.tf` as the operator-minted `ignore_changes` precedent,** a shape #8209 had removed. Recovery: re-cited `resend.tf`. **Prevention:** grep the cited file for the claimed construct before writing "mirrors X".
4. **CodeQL `js/incomplete-sanitization`** from `a.replace(/\./g, "\\.")` in a new test row. Recovery: used the file's `escapeRe`. **Prevention:** reuse the file's escaper; CodeQL catches it.
5. **The Guard Contract mutation matrix was a numbered list;** `lint-guard-contract.py` counts table rows only, so `lint-guard-contract-live` failed in CI. Recovery: rewrote as tables. **Prevention:** plan SKILL.md 2.12 now says "a markdown TABLE".
6. **The plan did not run the census guard against the planned destroy.** Recovery: `INTENDED_DESTROYS` plus rows. **Prevention:** Sharp Edges bullet (run the destroy/census guards before calling the census complete).
7. **A non-vacuity anchor named a resource that is only targeted, never declared** (`doppler_secret.github_app_id`), so the new test was red on first run. Recovery: anchored on `zot_pull_token`. **Prevention:** grep the anchor in the searched corpus before using it.
8. **`git add -N .` intent-added the borrowed `node_modules` symlink.** Recovery: `git rm --cached`. **Prevention:** stage explicit paths, or use a `':!apps/web-platform/node_modules'` pathspec.
9. **A foreground preview exceeded 120 s, and `sleep` and a background poll were both hook-blocked.** Recovery: Monitor and a bounded `timeout` wait. **Prevention:** use Monitor for waits from the start (already hook-enforced).
10. **The borrowed stale `node_modules` broke the local typecheck hook and three unrelated vitest files.** Recovery: excluded the hook for the commit; CI ran tsc. **Prevention:** known worktree limitation; treat env-only local failures as unverified, never as passes.
11. **`gh api …/actions/jobs/<id>/logs` printed nothing without `--allow-escape-sequences`.** Recovery: added the flag. **Prevention:** use `gh api --allow-escape-sequences` for job logs, or ask the API which step failed first.

## Tags

category: integration-issues
module: apps/web-platform/infra
