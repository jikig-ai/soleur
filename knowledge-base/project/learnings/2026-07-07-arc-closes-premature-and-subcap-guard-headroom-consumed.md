---
title: "Partial-fix arc PRs must not Closes the tracking issue; sub-cap drift-guards need re-baselining when a multi-PR arc eats their headroom"
date: 2026-07-07
category: workflow-patterns
tags: [one-shot, collision-gate, closes-vs-ref, drift-guard, size-budget, cloud-init, templatefile, infra]
issue: 6090
branch: feat-one-shot-6090-ghcr-login-bake-creds
---

# Learning: arc PRs, premature `Closes`, and drift-guard headroom exhaustion

## Problem

Resuming #6090 (web-2 cold-boot never binds `:9000`) surfaced three recurring traps, all
downstream of the same root shape: **a multi-PR "observability arc" that peeled a silent
failure down to a named root cause across several merged PRs, then shipped the actual fix
last.**

1. **The tracking issue was already CLOSED before the fix landed.** A sibling arc PR (#6125,
   "move package install into instrumented runcmd apt — name the config-phase hang") used
   `Closes #6090` in its body. #6125 *diagnosed* the hang; it did NOT implement the
   ghcr_login root-cause fix (#6090's actual deliverable). GitHub auto-closed #6090 anyway.
   When `/soleur:one-shot` resumed the work, its Step 0a.5 collision gate saw `state=CLOSED`
   and hard-aborted — correctly, per its own rule, but on a false premise (the work was
   genuinely undone; verified: `cloud-init.yml` still ran the un-hardened
   `timeout 15 doppler secrets get GHCR_READ_*` with no baked fallback).

2. **A sub-cap "budget with headroom" drift-guard had its headroom silently consumed by the
   arc.** `cloud-init-user-data-size.test.ts`'s `WEB_GZIP_BUDGET = 18_000` was set over a
   then-measured ~15,064 B with "~2.9 KB headroom." Across the arc's merged PRs the modeled
   web `user_data` grew organically to ~17,844 B (measured at HEAD before this PR). A
   legitimate ~272 B fix (the bake + retry loop) tipped it to 18,116 — a red test on a
   change that is *correct*. Trimming the load-bearing retry logic to claw back 116 B would
   have left the guard at zero headroom, re-triggering on the very next infra PR.

3. **`${var}` inside a comment of a `templatefile()`'d file still interpolates.** The first
   draft of the cloud-init comment read `mirrors the ${sentry_dsn} bake above`. Terraform's
   `templatefile()` substitutes every `${...}` regardless of shell-comment context, so that
   comment would have rendered the real DSN value into `user_data` (a needless second
   occurrence of a semi-public secret + wasted bytes on a capped surface).

## Solution

1. **Re-open the prematurely-closed issue and proceed** (operator-confirmed). The one-shot
   abort message names this exact remedy ("re-open the issue first"). Ship the fix as
   `Ref #6090` (never `Closes` — the real closure is the operator's post-merge web-2
   recreate binding `:9000`).

2. **Re-baseline the drift-guard, don't gut it and don't trim the legit change to zero
   headroom.** Bumped `WEB_GZIP_BUDGET` 18,000 → 20,000: restores ~1.9 KB working headroom,
   stays ~12.8 KB under the 32,768 B Hetzner hard cap, and still trips on any ≥1.9 KB
   re-inlining regression (the failure mode the guard actually protects). Updated the stale
   "Measured ~15,064 B" comment to the real ~18,116 B so the next reader isn't misled.

3. **Drop the braces on `${var}` refs inside comments** of any file that flows through
   `templatefile()` (`sentry_dsn`, not `${sentry_dsn}`), so the comment documents without
   interpolating.

## Key Insight

- **A partial-fix PR in a multi-PR arc must use `Ref #N`, not `Closes #N`.** `Closes` belongs
  ONLY on the PR that actually lands the tracked deliverable. A diagnosis/instrumentation PR
  that moves the arc forward without fixing the root cause auto-closes the tracker, which
  then trips the next session's one-shot collision gate (a hard abort) on a false "already
  done" signal. This is the deeper form of `wg-use-closes-n-in-pr-body-not-title`: the
  hazard is not only title-vs-body, it's `Closes`-before-the-fix-exists.

- **A sub-cap "budget + headroom" guard on a high-churn surface is a consumable, not a
  constant.** When a multi-PR arc grows the guarded artifact, the guard's headroom is spent
  by *already-merged* work, so the final small PR inherits a near-exhausted budget and fails
  on a correct change. The fix is to re-baseline (preserve the guard's real purpose — catch
  KB-scale re-inlining — while restoring headroom) and correct the stale measurement comment
  — NOT to trim a load-bearing change down to zero-headroom, which just defers the wall one PR.

- **`templatefile()` interpolates `${...}` everywhere, including comments.** Bare-`$` forms
  (`$(...)`, `$((n+1))`, `$VAR`) pass through untouched; braced `${...}` always substitutes.
  A `${secret_var}` in a comment silently renders the secret value into the output artifact.

## Session Errors

1. **Two subagents crashed on the Anthropic session limit** (planning subagent + an earlier
   verify child). Recovery: partial-artifact recovery — the plan skill had already committed
   the plan (`0e2007a58`) before the crash, so the one-shot fallback path loaded it and the
   implementation ran inline (no re-plan). **Prevention:** already covered by one-shot's
   "Partial-artifact recovery check"; when subagents are rate-limited, do the remaining
   pipeline phases (implement/review-fix/compound) inline rather than re-spawning into the
   same limit.

2. **Orphan duplicate plan file** — the crashed planning subagent had run `/plan` twice,
   leaving `...web-host-cloud-init-plan.md` (untracked) beside the committed
   `...cold-boot-plan.md` (referenced by tasks.md). Recovery: removed the orphan; kept the
   tasks.md-referenced canonical. **Prevention:** on partial-artifact recovery, reconcile
   plan files against `tasks.md`'s `Plan:` pointer and delete any un-referenced sibling.

3. **#6090 already CLOSED by a sibling arc PR's `Closes`** (see Key Insight). Recovery:
   verified fix undone in `main`, re-opened, proceeded. **Prevention:** the `Ref`-not-`Closes`
   discipline above.

4. **Size-budget test red on a correct change** (arc consumed the headroom). Recovery:
   re-baseline (see Solution 2). **Prevention:** the "budget is a consumable" insight;
   compound/ship should flag when a merged arc leaves a guard within one PR of its cap.

5. **`terraform validate` failed (providers not cached)** in the fresh worktree. Recovery:
   `terraform init -backend=false -input=false` then validate = Success. **Prevention:**
   one-off/expected — init before validate in a fresh checkout.

6. **`${sentry_dsn}` in a cloud-init comment would interpolate** (see Key Insight). Recovery:
   changed to bare `sentry_dsn` pre-commit. **Prevention:** the templatefile-comment insight.

7. **Plan claimed a `ghcr_login_ok` success detail tag** that the cleared detail file never
   surfaces (a successful `docker pull` runs `: > /run/soleur-stage-detail` before any emit
   reads it). Recovery: observability-coverage-reviewer caught it; corrected the plan's
   success signal to `cloud_init_complete` + `:9000` bind. **Prevention:** verify a claimed
   positive observability signal against the actual write/clear ordering, not just that the
   value is written somewhere.
