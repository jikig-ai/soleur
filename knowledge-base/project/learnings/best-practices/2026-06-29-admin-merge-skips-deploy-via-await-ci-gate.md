# Learning: the admin-merge escape hatch makes the release run go RED (deploy skipped) — harmless for the changes it's scoped to

category: best-practices
module: ship / web-platform-release
date: 2026-06-29
refs: PR #5707, plugins/soleur/skills/ship/SKILL.md (settle-then-admin-merge escape hatch)

## Problem

`/ship`'s **settle-then-admin-merge escape hatch** (for a zero-conflict-surface
change livelocking on a fast-moving `main`) is `gh pr merge --squash --admin`,
which bypasses *only* the "branch up to date with base" gate, not the checks.
After using it on PR #5707 (a single test-file change), the post-merge
`web-platform-release` workflow concluded **`failure`** — alarming at a glance,
since `wg-after-a-pr-merges-to-main-verify-all` treats a failed release as a
silent-outage class.

## Root cause

`web-platform-release.yml` has an `await-ci` job that **polls for the CI
workflow's `test` to go green on the exact merge-commit SHA**, and the prod
`deploy` job is gated on it:

```yaml
deploy:
  needs: [release, migrate, verify-migrations, verify-doppler-secrets, await-ci]
  if: always() && ... && (needs.await-ci.result == 'success' || ...)
```

An admin-merge lands the squash commit on `main` *before* that merge-commit CI
can start (on a busy runner pool CI sits `queued`). `await-ci` polls, times out
waiting for a CI run that hasn't begun, and concludes **`failure`** → the
`deploy` job's `if` is false → `deploy` is **skipped** → with one job failed and
the cutover skipped, the release run concludes `failure`.

The build (`release / release`) and `migrate` jobs still succeed — the "failure"
is purely the `await-ci` gate, not a build or deploy fault.

## Key Insight

**An admin-merge red release run is expected, not a regression — for exactly the
change classes the hatch permits.** The hatch is scoped to *zero-conflict-surface*
changes (test / docs / skill / additive), and that set is precisely the set with
**nothing runtime to cut over**: prod keeps running the prior commit, which is
byte-identical at runtime to the new HEAD. So a skipped deploy is *correct*. A
runtime change would never qualify for the hatch in the first place, so the
deploy-skip can never strand a real change undeployed.

When you admin-merge, verify three things and move on — do NOT re-run or "fix"
the red release:
1. the merge-commit **`CI`** workflow concludes `success` (main HEAD verified green),
2. the skipped job is **`deploy`** (not a failed `release`/`migrate` build),
3. **`/health` is 200** (prod still healthy on the prior, runtime-identical commit).

## Session Errors

- **Briefly read the `await-ci` `completed/failure` as a real release failure.**
  Recovery: traced the release workflow's `deploy` `if:` condition + confirmed
  build/migrate succeeded, CI-on-merge-commit went green, and `/health`=200.
  Prevention: the ship escape-hatch section now documents this expected
  side effect (this learning's companion edit).

## Tags
category: best-practices
module: ship
