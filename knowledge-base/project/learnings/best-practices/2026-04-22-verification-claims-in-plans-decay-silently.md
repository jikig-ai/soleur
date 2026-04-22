---
title: Verification claims in plans decay silently -- re-verify at plan-read time
date: 2026-04-22
category: best-practices
module: plan-skill, doppler, ci
tags: [planning, verification-decay, doppler, config-drift, ci-guards]
source_session: one-shot fix for Sentry 595bebdc6ef943c39e90ecf7ac139b73 (PR #2767)
---

# Verification claims in plans decay silently

## Problem

Production fired Sentry issue `595bebdc6ef943c39e90ecf7ac139b73` on every `POST /api/repo/setup`:

> `NEXT_PUBLIC_APP_URL unset; agent share URLs will point at https://app.soleur.ai`

The `reportSilentFallback` guard in `apps/web-platform/server/agent-runner.ts` fired because the env var was undefined. Root cause: the secret was **absent from all four Doppler configs** (`dev`, `prd`, `ci`, `prd_terraform`).

The interesting part: a prior plan (`knowledge-base/project/plans/2026-04-17-feat-agent-user-parity-kb-share-plan.md:443`) stated:

> "`NEXT_PUBLIC_APP_URL` is already configured in Doppler `dev`/`prd`; verified via `doppler secrets get NEXT_PUBLIC_APP_URL -p soleur -c dev --plain`"

That claim was either stale at write-time or the secret was deleted between 2026-04-17 and 2026-04-22 (five days). No commit record exists of the deletion. The claim rotted silently.

This extends the existing reconciliation learning
(`2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`) from **spec-vs-codebase**
(static) to **plan-vs-environment** (dynamic).

## Solution

Two complementary guards:

1. **At plan-read time (procedural):** Whenever a plan cites "verified via `<command>`", re-run the command before quoting the result. Verification claims about mutable environment state (Doppler, DNS, feature flags, infrastructure) have a shelf life measured in days. The plan skill's Research Reconciliation section (per 2026-04-15 learning) must treat **verification claims in prior plans** as decay-prone spec claims: reconcile them against current reality.

2. **At CI-gate time (mechanical):** File a CI smoke check that asserts every required `NEXT_PUBLIC_*` secret is present in Doppler `prd` before the web-platform release workflow deploys (filed as issue #2769). The list should be auto-derived from `Dockerfile` ARG lines + grep `process.env.NEXT_PUBLIC_*` across `apps/web-platform/{app,server,lib}/` — a drift between code and the check is itself a bug.

## Key Insight

**Verification is a read, not a write.** A plan that says "I verified X" is an assertion about environment state at write-time, not a guarantee it stays true. The verification's value decays the moment the author stops looking. Any plan re-read days or weeks later must re-verify before citing the prior verification as load-bearing.

A secondary insight: **Doppler secret absence is a silent failure mode across the SDLC.** The Next.js runtime logs a Sentry error, but the CI deploy pipeline does not. The operational cost of the missing check is every production request emitting a false-positive error until someone notices in Sentry. Gate the class at deploy-time, not at runtime.

## Prevention

1. **Plan skill:** Extend the Research Reconciliation requirement to cover verification claims from prior plans (not just specs). Any "verified via X" statement older than 72 hours re-runs the verification.
2. **CI guard (issue #2769):** Add a pre-deploy job that asserts required `NEXT_PUBLIC_*` secrets exist in Doppler `prd`. Fail the deploy on absence. Auto-derive the required set from code, don't hand-maintain it.
3. **Comment pattern:** When a fallback literal coincidentally matches a production URL (as with `https://app.soleur.ai` here), add a symbol-anchored comment above the guard documenting that the match is coincidental and a Sentry hit means a config regression. Shipped in this PR at `agent-runner.ts` above the `reportSilentFallback` call.

## Session Errors

- **Bash CWD non-persistence (minor, recovered).** After `cd apps/web-platform && npx tsc --noEmit`, a subsequent `git commit` failed with `fatal: pathspec ... did not match` because the Bash tool runs each command in a fresh shell. Recovered by re-chaining `cd <worktree-abs-path> && <cmd>` in a single call. **Prevention:** Already covered by `hr-the-bash-tool-runs-in-a-non-interactive` + `cq-for-local-verification-of-apps-doppler`; no new rule needed. Internalize the single-call-chain pattern for any command requiring CWD context.

## Cross-references

- Builds on: `knowledge-base/project/learnings/best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`
- Related rules: `hr-menu-option-ack-not-prod-write-auth`, `cq-silent-fallback-must-mirror-to-sentry`, `cq-for-production-debugging-use`
- Follow-up issues: #2768 (URL consolidation), #2769 (CI guard), #2770 (mirror silent fallbacks)
- PR: #2767
