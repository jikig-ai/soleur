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

## Addendum — 2026-09-09 (#5806)

**The mechanism this learning documents no longer exists. Do not act on the
"verify three things and move on" checklist above.**

`await-ci` was DELETED from `web-platform-release.yml` by #5806 (ADR-217,
ADR-072 option 3). It was a job that held an idle GitHub-hosted runner for up to
72 minutes polling the REST API for CI's verdict on a SHA, and it failed CLOSED
when CI outran its ceiling — a fixed bound on an unbounded, growing quantity.
The #7902 symptom (a healthy build that could not deploy) is the same defect
class as the admin-merge red run recorded above; both are `await-ci` fail-closing
on a CI verdict that had not arrived in time.

**What replaced it.** The workflow is now split across two triggers, so every
merge produces TWO runs of `web-platform-release.yml`:

| arm | trigger | jobs |
|---|---|---|
| push arm | `on: push` to `main` (path-filtered) | `release` only — build + publish |
| deploy arm | `on: workflow_run` — `CI` **completed**, `branches: [main]` | `resolve-target`, `migrate`, `verify-migrations`, `verify-doppler-secrets`, `deploy`, `live-verify`, `notify-gated`, `release-outcome` |

`resolve-target` is the direct successor to `await-ci`: instead of polling for a
verdict, it reads the verdict off the `workflow_run` event that carries it, and
recovers the release's values from an artifact the push-arm run uploaded. There
is no ceiling to outrun and no runner held while waiting.

**How the admin-merge case INVERTS.** An admin-merge bypasses branch protection,
not CI. The squash commit still lands on `main`, `ci.yml` still runs on it, and
when that run completes the `workflow_run` trigger fires — so **the deploy DOES
happen**. It is not skipped and the run is not expected to be red. Under the new
topology:

- merge-commit CI `success` → the deploy arm deploys this commit for real.
  Verify it like any other deploy under `wg-after-a-pr-merges-to-main-verify-all`.
  A red deploy arm is now a **genuine deploy failure**, not an expected artifact.
- merge-commit CI `failure` → the deploy arm still fires (`types: [completed]`),
  and `resolve-target` clean-skips with `skip_reason=ci_not_green`, concluding
  **green** having deployed nothing. A green release run is no longer proof that
  prod moved.

**The `deploy: skipped` reading is also now ambiguous** and must not be treated
as benign on sight: on a push-arm run the `deploy` job does not exist at all, so
any consumer that selects "the latest `web-platform-release` run" without
`--event workflow_run` lands on a run with no deploy job roughly half the time.

**What is still true.** The scoping rule survives: the admin-merge hatch remains
restricted to zero-conflict-surface changes. Only its justification changed —
from "the deploy never happens, so nothing can be stranded" to "CI verifies the
squash commit before the deploy arm fires".

Superseding refs: #5806, ADR-217, `plugins/soleur/skills/ship/SKILL.md`
§settle-then-admin-merge escape hatch (rewritten in the same change).

## Tags
category: best-practices
module: ship
