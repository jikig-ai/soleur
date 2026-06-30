---
title: "Reusing a two-phase-commit pattern drops the precedent's post-commit observability; reusing a code string across a new transport channel drifts the payload"
category: best-practices
module: web-platform / repo-connect, workspace-switch
tags: [two-phase-commit, observability, sentry, refreshSession, cross-channel-contract, multi-agent-review, mirrors-x-drift]
related_pr: 5671
related_issue: 5673
---

# Learning: a reused multi-step pattern silently sheds its precedent's *observability*, and a reused code string across a new channel sheds its *payload contract*

## Problem

`feat-repo-connect-block-offer-join` (PR #5671) added a client-side "switch to your
existing workspace" CTA that reuses the canonical two-phase commit from
`org-switcher-container.tsx` (#4917): `set_current_workspace_id` RPC (durable write)
→ `auth.refreshSession()` (JWT re-mint) → `window.location.assign("/dashboard")`
(hard nav). The `handleSwitch` header comment explicitly claimed it "mirrors the
canonical two-phase commit in org-switcher-container.tsx."

It mirrored the **happy path** faithfully but dropped the precedent's
**post-RPC observability**: org-switcher wraps the `refreshSession()` failure in
`reportSilentFallback({op:"refresh-session-post-rpc"})` precisely so an aggregate
pattern of post-commit DB/JWT divergence stays visible. The reused copy had an
**empty `catch {}`** — the RPC has already committed the durable pointer, so a
refresh failure is the identical brand-critical divergence, silently swallowed.
`tsc` and the happy-path test both passed green.

Separately, the feature reused the existing `workspace_switch_required` code string
(already emitted by the WS dispatch path as `{errorCode, switchToWorkspaceId}`) on a
NEW HTTP-409 channel as `{code, existingWorkspaceId}`. Same semantic concept, two
divergent payload shapes — the id field name AND the key name both drift across
channels. A single source of truth for the code *literal* does nothing to prevent
the *companion-field* drift.

## Solution

- Added `reportSilentFallback(err, {feature:"repo-connect-switch", op:"refresh-session-post-rpc", ...})`
  to the `catch`, matching the precedent exactly while keeping converge-forward
  (hard nav still fires — the durable pointer is already committed). Same fix for
  the sibling swallowed `repo_status` readiness read in the guard.
- Added a test that forces `refreshSession` to reject and asserts both `assign("/dashboard")`
  AND the Sentry mirror fire; tightened the switch test to assert the load-bearing
  call **order** (`rpc < refreshSession < assign`), not just that each was called.
- Documented the cross-channel divergence in the new shared `lib/repo-connect-codes.ts`
  header (and noted the deferred agent-callable switch primitive) rather than a
  premature 7-file rename — the divergence is latent (no agent drives connect yet).

## Key Insight

1. **When you reuse a multi-step pattern (two-phase commit, saga, retry envelope,
   optimistic-lock-then-write) from a named precedent, the precedent's *observability*
   on the failure arms is PART of the pattern — and it is the most commonly dropped
   part**, because the happy path is what gets copied. A `// mirrors X` claim is the
   cheapest detection hook: grep the precedent for `reportSilentFallback` / Sentry /
   log calls on its catch/error arms and confirm each survived the copy. The
   happy-path test passes either way, so only a failure-arm test (force the throw,
   assert the mirror) catches the drop.

2. **Reusing an existing code/enum string on a NEW transport channel re-opens
   payload-shape drift even when the literal is single-sourced.** The literal is one
   field; the companion fields (id field name, key name, status) are the contract.
   Either align the new channel to the established field names, or document the
   divergence at the shared-constant site so the next reader does not assume the
   payloads are interchangeable.

3. **Multi-agent review at `single-user incident` threshold catches the
   observability drop where a single reviewer would not** — here code-quality,
   user-impact, and data-integrity *independently* converged on the same empty-catch
   by comparing against the cited precedent. The convergence is the signal; the
   "mirrors X" comment is what each agent anchored on.

## Session Errors

- **Stale `/soleur:plan continue` fallback wakeup fired after the work was already
  complete.** Recovery: recognized as stale, did not re-run; rescheduled with a
  corrected prompt reflecting true state. Prevention: when a `/loop`/ScheduleWakeup
  fallback outlives its task, replace the carried prompt with current state rather
  than re-firing the original (one-off; no rule warranted).
- **`git push` rejected (non-fast-forward) after an intentional rebase onto
  origin/main.** Recovery: `git push --force-with-lease`. Prevention: expected after
  a deliberate rebase; `--force-with-lease` is the safe form (one-off).
- **Existing setup-route tests broke when the new extracted guard ran its REAL
  resolver query against their single-`.eq()` mock chains.** Recovery: `vi.mock`
  the extracted guard module (default `{outcome:"ok"}`) in those files, keeping
  branch logic in the dedicated guard unit test. Prevention: when extracting a
  helper that a route already-tested now calls, mock the helper in the route's
  existing tests so they stay focused — recurring pattern, already captured here.
