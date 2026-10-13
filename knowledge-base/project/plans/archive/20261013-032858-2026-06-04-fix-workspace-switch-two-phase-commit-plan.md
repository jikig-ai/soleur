---
title: "fix(workspace): two-phase-commit treatment of workspace switch failure"
issue: 4917
branch: feat-one-shot-4917-workspace-switch-two-phase-commit
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-06-04
---

# 🐛 fix(workspace): switch failure after successful RPC leaves DB/JWT tenant divergence

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec.md exists for this branch.

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Proposed Fix (force-complete locked as primary), Product/UX Gate
(wireframe-exemption rationale), Research Insights (new).
**Research agents used:** inline (Task subagent spawning unavailable in this pipeline
environment) — precedent-diff gate (4.4), verify-the-negative pass (4.45), and halt gates
4.6/4.7/4.8/4.9 run directly.

### Key Improvements

1. **Force-complete locked as the single primary treatment** (plan-review BOTH-panels
   consolidation) — the honest-interstitial alternative is documented but not built; this
   prevents the implementer building two failure-state UIs.
2. **Wireframe exemption made explicit and principled** — the `components/**` glob matches but
   the change is a copy + affordance-removal on an existing interstitial (`ui-surface-terms.md`
   Excluded clause), so no `.pen` is required; documented so work Check-9 + deepen 4.9 both pass
   on a recorded determination, not a silent skip.
3. **All negative claims verified against `main`** — AC8's "server resolvers read
   `user_session_state` as source of truth" confirmed at `workspace-resolver.ts:16/35/42`;
   offline precedent confirmed at `delegation-toggle.tsx:168`; force-complete reuses the existing
   `window.location.assign("/dashboard")` at `:108`.

### New Considerations Discovered

- The bug's blast radius is confirmed broader than the single component: 10+ `server/*` modules
  resolve the active workspace from `user_session_state`, so the post-RPC commit is authoritative
  the instant it lands — the client's stale screen is the ONLY thing out of sync, which is exactly
  why force-complete (converge the client forward) is correct and a compensating rollback-RPC is
  not (it can fail again and re-open the window).
- `navigator.onLine` is writable in jsdom — Test Scenario 3 must stub it via
  `Object.defineProperty`/`vi.stubGlobal`, mirroring the existing `window.location.assign` stub
  pattern already in the test file (`:62-65`).

### Research Insights (Proposed Fix)

**Precedent-diff (deepen Phase 4.4):** Both pattern-bound behaviors have in-repo precedents — NOT
novel.

- Force-complete navigation: reuses `window.location.assign("/dashboard")` already at
  `org-switcher-container.tsx:108` (the success path). No new navigation primitive.
- Offline / thrown-fetch handling: `components/settings/delegation-toggle.tsx:168` already
  distinguishes "thrown fetch (offline, DNS/TLS failure, aborted request)" from `!res.ok`. Adopt
  the same error-shape reasoning; do not invent a new offline-detection pattern.

**Edge cases:**

- Double-navigation guard: if the post-RPC catch force-completes, ensure a prior partial success
  did not already call `assign` (idempotent for the browser but wasteful mid-unload).
- `refreshSession` resolving with `{ data: { session: null } }` (not throwing) is distinct from a
  thrown error — the existing claim read-back at `:89-94` already treats a null/mismatched claim as
  non-fatal-warn-then-navigate, so this path is already safe; the fix only changes the THROW path.

## Overview

`apps/web-platform/components/dashboard/org-switcher-container.tsx` runs the workspace
switch as: `set_current_workspace_id` RPC (commits to `user_session_state`) →
`refreshSession()` (JWT re-mint) → hard `window.location.assign("/dashboard")`.

The RPC and the JWT re-mint are **two separate writes**. The current FSM collapses both
failure modes into a single `status === "failed"` state whose only affordances are
**Retry** and **Cancel**. When the RPC SUCCEEDS but `refreshSession()` throws (`:95-98`),
the durable source of truth (`user_session_state`) **already points at the NEW workspace**
while the in-browser JWT still claims the OLD one. **Cancel** (`:115`) drops the user back
onto a screen labeled with the OLD workspace — but the next hard navigation, server
component render, or other open tab resolves the NEW workspace server-side (every
`server/*` module resolves the active workspace from `user_session_state`, confirmed via
grep: `agent-runner.ts`, `byok-resolver.ts`, `cc-dispatcher.ts`, `current-repo-url.ts`,
`kb-document-resolver.ts`, etc.). The result is a **silent cross-tenant context switch the
user never confirmed** — single-user-incident brand-survival class.

The fix is a **two-phase-commit treatment**: track *whether the RPC committed* and branch
the failure UX on it. A **pre-RPC failure** (nothing written) is safe to Cancel back to the
old workspace. A **post-RPC failure** (already committed) must NOT offer a Cancel that
implies "nothing happened" — the only honest forward path is to **complete the navigation**
so the client converges to the durable truth.

This is a **single-component logic fix**. No migration, no RPC change, no server change, no
new infrastructure. ADR-044's invariants (membership-checked RPC, JWT claim read-back from
the session access token, hard-nav to neutral `/dashboard`) are preserved verbatim — we
only change the **client failure-branching** after the RPC.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body) | Reality (codebase, verified 2026-06-04) | Plan response |
|---|---|---|
| RPC at `:73-75`, refreshSession at `:83`, failure at `:95-96`, hard-nav at `:108` | Confirmed exact: `supabase.rpc("set_current_workspace_id", …)` at 73-75; `refreshSession()` at 83; catch→`setStatus("failed")` at 95-98; `window.location.assign("/dashboard")` at 108 | Plan targets these lines |
| "Cancel returns user to OLD-workspace screen; next nav resolves NEW workspace server-side" | Confirmed: `handleCancel` at `:115` resets `pending`/`status` to idle (no nav); server modules resolve active workspace from `user_session_state` (grep: 10+ `server/*` consumers) | Post-RPC Cancel is the bug; remove it for the post-RPC failure branch |
| "#4915 deliberately does NOT touch the switch FSM (CTO constraint)" | #4915 is a CLOSED **issue** (chrome/visual redesign); implemented by PR #4911 (MERGED). The FSM `executeSwitch` is unchanged by #4911. | Premise holds; this is orthogonal to the visual work |
| ADR-044 / migration 079 / `set_current_workspace_id` exist | Confirmed: `ADR-044-workspace-repo-ownership.md`, `079_workspace_repo_ownership_schema.sql`, `lib/session-claims.ts:getCurrentWorkspaceId` all present | No build-vs-fix ambiguity — this is a behavioral fix |

**Premise Validation:** All four issue-body references were checked. Issue #4915 resolved
via PR #4911 (MERGED) but is a sibling-scope artifact, not a blocker; #4917 itself is OPEN
and unresolved. All cited file lines, the RPC name, the ADR, and the migration exist on the
current branch. No stale premises. The bug is a *fix* (behavior is wrong), not a *build*
(the FSM exists and runs).

## Problem Detail

```text
executeSwitch(target):
  setStatus("switching")
  { error } = await rpc("set_current_workspace_id", { p_workspace_id })   # WRITE 1 (durable)
  if (error) { setStatus("failed"); return }        # ← PRE-RPC failure: nothing committed, Cancel is safe
  setStatus("syncing")
  try {
    refreshSession()                                # WRITE 2 (JWT re-mint, ephemeral)
    ...claim read-back (non-fatal warn)...
  } catch (err) {
    setStatus("failed"); return                     # ← POST-RPC failure: WRITE 1 ALREADY COMMITTED.
  }                                                  #    Cancel here = silent cross-tenant divergence.
  window.location.assign("/dashboard")
```

Both `return` paths land on the SAME `status === "failed"` UI (Retry / Cancel). The UI
cannot tell the two apart, so it offers Cancel in both — and Cancel after WRITE 1 is the
cross-tenant exposure.

## User-Brand Impact

**If this lands broken, the user experiences:** after a flaky network blip during a
workspace switch, they click Cancel believing they stayed in workspace A, but their agents,
KB reads, and repo context silently resolve to workspace B on the next page load — they may
type a prompt, attach a file, or read documents under the wrong tenant without ever
confirming the switch.

**If this leaks, the user's workspace data / agent context is exposed via:** the durable
`user_session_state.current_workspace_id` row committed by WRITE 1, read by every
`server/*` workspace resolver (`agent-runner`, `byok-resolver`, `cc-dispatcher`,
`kb-document-resolver`, …) on the next server render or other open tab — while the client
UI still labels the OLD workspace. The exposure vector is the **DB/JWT divergence window**
that the Cancel affordance perpetuates indefinitely.

**Brand-survival threshold:** single-user incident — a single cross-tenant context switch
that the user did not confirm is a trust-fatal event for a CaaS product.

## Proposed Fix

Introduce a `committed` flag (or a richer `SwitchStatus` discriminant) that records whether
WRITE 1 succeeded, and branch the failure UX:

1. **Pre-RPC failure** (`committed === false`): keep the current Retry / **Cancel** UX —
   nothing was written, Cancel safely returns to the old workspace. Copy: "Couldn't switch
   … Please try again." (unchanged).

2. **Post-RPC failure** (`committed === true`, i.e. `refreshSession` threw after the RPC
   succeeded): the switch **is already committed server-side**. Do NOT offer a Cancel that
   implies "nothing happened." **Primary treatment — force-complete:** on the post-RPC catch,
   call `window.location.assign("/dashboard")` directly (mirroring the success path) — the
   server re-reads `user_session_state` as source of truth and the JWT re-mints on next load.
   The user lands on the neutral `/dashboard` already in the NEW workspace, with no
   stale-labeled screen and no Cancel that lies. This is the issue's own recommended fix and
   reuses the existing success-path mechanism (no new UI surface). **Build this unless
   deepen-plan/ux explicitly overrides.**

   The honest-interstitial alternative ("Finishing your switch to {newWorkspace}…", Continue-only,
   no Cancel) is documented in Alternative Approaches Considered only — do NOT build both. It is
   functionally equivalent on the security axis and is a fallback ONLY if force-complete-on-catch
   is judged too abrupt at ux review.

3. **Offline / bounded-retry messaging:** distinguish a thrown `refreshSession` caused by
   loss of connectivity (`navigator.onLine === false`, or fetch-level network error) from a
   genuine auth error. When offline AND post-RPC, the honest message is "You're offline — your
   workspace switch to {newWorkspace} is saved and will finish when you reconnect," NOT a
   generic "couldn't switch / try again" (which is false — it DID switch). Bound retry
   attempts so the UI never spins forever. (Pre-RPC + offline keeps the existing Retry.)

**Invariant preserved:** the success path (`executeSwitch` happy path) and the retry path
both still hard-navigate to `/dashboard`. We add no soft `router.push`. The claim read-back
warn at `:89-94` stays non-fatal.

## Files to Edit

- `apps/web-platform/components/dashboard/org-switcher-container.tsx`
  - Add a `committed` boolean (or widen `SwitchStatus` to a discriminated set that encodes
    pre- vs post-RPC failure — e.g. `"failed_pre_rpc" | "failed_post_rpc"`). **Prefer the
    discriminated `SwitchStatus` union** so the failure-branch rendering is exhaustive and
    `tsc --noEmit` enumerates every render arm (avoids a stray boolean drifting out of sync
    with `status`). Per `cq-union-widening-grep-three-patterns`, after widening the union,
    `tsc --noEmit` and grep the component for every `status === "failed"` site.
  - In the post-RPC catch (`:95-98`), branch: set the post-RPC failure status (or
    immediately `window.location.assign("/dashboard")` if force-complete is chosen).
  - Render: the post-RPC failure branch must NOT render a Cancel button. Render copy +
    affordances per the chosen treatment (force-complete = no interstitial needed; honest
    interstitial = Continue-only).
  - `handleCancel` (`:115`) must be unreachable from the post-RPC failure state (guard or
    omit the Cancel control there).
  - Offline detection: read `navigator.onLine` (and/or inspect the caught error shape) in the
    post-RPC catch to select messaging. Precedent: `components/settings/delegation-toggle.tsx:168`
    already handles "thrown fetch (offline, DNS/TLS failure, aborted request)" — adopt the same
    error-shape reasoning, do not invent a new pattern.

- `apps/web-platform/test/org-switcher-container.test.tsx`
  - Add tests (see Test Scenarios). The existing 6 tests must still pass unchanged
    (happy-path RPC + refresh + hard-nav, confirm-before-switch, cancel-aborts-pre-RPC,
    RPC-failure-retry). **Do not** weaken the existing `cancel aborts the switch` test — it
    asserts the PRE-RPC cancel which remains valid.

## Files to Create

None. (Single-component fix; tests extend the existing spec file.)

## Test Scenarios

Runner: **vitest** (`apps/web-platform` uses vitest; the existing spec imports from
`vitest` and `@testing-library/react`). Test path stays `apps/web-platform/test/
org-switcher-container.test.tsx` — confirmed against `vitest.config.ts` `include:`
globs (`test/**/*.test.tsx` → jsdom). Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/org-switcher-container.test.tsx`.

1. **Post-RPC failure force-completes (no Cancel):** `mockRpc` resolves `{ error: null }`;
   `mockRefreshSession` rejects (throws). Assert: the component either hard-navigates to
   `/dashboard` (`assignMock` called with `/dashboard`) OR renders a Continue-only
   interstitial with NO `cancel` button — and crucially, **no affordance returns the user to
   the old-workspace idle screen**. Assert `screen.queryByRole("button", { name: /cancel/i })`
   is null in the post-RPC failure state.

2. **Pre-RPC failure still offers Cancel (regression guard):** `mockRpc` resolves
   `{ error: { message: "permission denied" } }`. Assert Retry AND Cancel both present;
   `assignMock` NOT called; Cancel returns to idle (existing behavior preserved).

3. **Post-RPC offline messaging:** stub `navigator.onLine = false`; `mockRpc` succeeds,
   `mockRefreshSession` rejects with a network-shaped error. Assert the message names the
   target workspace and conveys "saved / will finish on reconnect" — NOT "couldn't switch."
   (If force-complete is chosen, this scenario asserts the offline copy on the brief
   pre-navigation state, or is folded into the interstitial treatment.)

4. **Bounded retry does not spin forever:** drive N post-RPC failures; assert the UI caps
   retry attempts and reaches a terminal "complete your switch" affordance rather than an
   infinite Syncing… loop.

5. **Discriminated-status exhaustiveness (type-level):** after the union widening,
   `tsc --noEmit` passes with every render arm handled (no `status` value unhandled).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Post-RPC failure never offers Cancel.** After a successful `set_current_workspace_id`
  RPC followed by a thrown `refreshSession`, the rendered failure UI contains NO control that
  returns the user to the old-workspace idle screen. Verified by Test Scenario 1
  (`queryByRole("button", { name: /cancel/i })` is null in that state).
- [ ] **AC2 — Post-RPC failure converges to the new workspace.** The post-RPC failure branch
  either hard-navigates to `/dashboard` (server re-reads `user_session_state`) or presents a
  Continue-only control that hard-navigates — never a soft `router.push`, never a stale-labeled
  resting screen. Verified by Test Scenario 1 (`assignMock` called with `/dashboard`).
- [ ] **AC3 — Pre-RPC failure preserves Retry + Cancel.** When the RPC itself errors, the
  existing Retry/Cancel UX is unchanged and Cancel safely returns to idle (no nav). Verified by
  Test Scenario 2 and the existing `cancel aborts the switch` + `RPC failure surfaces a failed
  state with a retry` tests passing unchanged.
- [ ] **AC4 — Offline post-RPC messaging is honest.** When offline after a committed RPC, the
  copy states the switch is saved / will finish on reconnect and names the target workspace; it
  does NOT claim the switch failed. Verified by Test Scenario 3.
- [ ] **AC5 — Bounded retry.** No code path leaves the UI in an unbounded Syncing… spin; retries
  are capped and reach a terminal converge-forward affordance. Verified by Test Scenario 4.
- [ ] **AC6 — Type exhaustiveness.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  passes; every `SwitchStatus` arm is handled in the render (no unhandled-`never` rail).
- [ ] **AC7 — Full existing suite green.** `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/org-switcher-container.test.tsx` passes (existing 6 + new ≥4 tests).
- [ ] **AC8 — ADR-044 invariants intact.** The membership-checked RPC name
  (`set_current_workspace_id`), the JWT-claim read-back via `getCurrentWorkspaceId(session)`,
  and the hard-nav-to-`/dashboard` on success are unchanged. `git diff` shows no edit to
  `lib/session-claims.ts`, no edit to any migration, no edit to any `server/*` resolver.

### Post-merge (operator)

- [ ] None. Pure client-component change; deploys via the standard `web-platform-release.yml`
  container restart on merge to `main` touching `apps/web-platform/**`. No migration, no
  Doppler secret, no infra. **Automation: N/A — no operator step exists.**

## Hypotheses

Not a network-outage diagnosis plan — no SSH/connectivity-failure hypothesis stack required.
(The offline-handling sub-requirement is product UX, not infra diagnosis.)

## Observability

```yaml
liveness_signal:
  what: "client-side console.error/warn on the post-RPC failure path + (new) a Sentry breadcrumb when a switch commits server-side but the JWT re-mint fails"
  cadence: "per occurrence (user-triggered, not scheduled)"
  alert_target: "Sentry (existing web-platform client SDK); message string distinguishes pre-RPC vs post-RPC failure"
  configured_in: "apps/web-platform/components/dashboard/org-switcher-container.tsx (catch block)"
error_reporting:
  destination: "Sentry — the post-RPC divergence catch SHOULD capture a message (not just console.error) so an aggregate pattern of refreshSession-after-commit failures is visible; the pre-RPC RPC error stays console-only (transient/expected)"
  fail_loud: "post-RPC failure is the brand-critical path — mirror to Sentry per cq-silent-fallback-must-mirror-to-sentry; do NOT swallow it as a silent console.error like the membership-fetch catch at :47-51"
failure_modes:
  - mode: "RPC commits, refreshSession throws (the bug)"
    detection: "catch block at the post-RPC site; Sentry message"
    alert_route: "Sentry issue grouped by the post-RPC message string"
  - mode: "offline during post-RPC window"
    detection: "navigator.onLine === false in catch"
    alert_route: "no alert (expected/transient) — UI messaging only"
  - mode: "unbounded retry"
    detection: "retry-count guard in component state"
    alert_route: "n/a — prevented by cap, not alerted"
logs:
  where: "browser console (console.error/warn) + Sentry for the post-RPC branch"
  retention: "Sentry default project retention"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/org-switcher-container.test.tsx -t 'post-RPC'"
  expected_output: "the post-RPC failure tests pass, proving the converge-forward + no-Cancel behavior is exercised (NO ssh)"
```

## Domain Review

**Domains relevant:** Product (UI failure-state UX + cross-tenant trust), Engineering (CTO —
client FSM correctness). Security/data-exposure is the *motivation* but the fix introduces no
new data surface, schema, or auth flow — it removes an exposure window in client logic.

### Engineering (CTO)

**Status:** reviewed (carry-forward from issue framing — CTO constraint that #4915 preserve the
RPC + hard-nav verbatim is honored; this plan touches only the client failure-branch).
**Assessment:** Single-component logic change. No migration, no RPC, no server resolver edit.
Preserves ADR-044 invariants. Risk is contained to the React FSM; the discriminated-union
widening + `tsc --noEmit` exhaustiveness gate (AC6) is the primary correctness control.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept — see rationale)
**Skipped specialists:** none — `ux-design-lead` is NOT skipped; it is **not triggered** (see wireframe-exemption rationale below)
**Pencil available:** N/A (no NEW UI surface — exempt per `ui-surface-terms.md` Excluded clause)

#### Findings

The fix **modifies an existing user-facing component** (`org-switcher-container.tsx`) — it adds
no new page, route, or component file (no path matches `components/**/*.tsx` *creation*,
`app/**/page.tsx`, or `app/**/layout.tsx`; the file already exists). Per the mechanical
UI-surface override, editing an existing component is ADVISORY, not BLOCKING — no new
interactive surface is created; the confirm/failure interstitial already exists and we are
changing its **failure-branch copy + affordances**, not introducing a new flow. On the
one-shot pipeline path, ADVISORY auto-accepts.

**Wireframe-exemption rationale (deepen-plan Phase 4.9 / work Check-9 / `wg-ui-feature-requires-pen-wireframe`):**
The mechanical glob `components/**/*.{tsx,jsx,…}` matches the edited file, but the change falls
squarely under `ui-surface-terms.md`'s **Excluded** clause — "Pure copy or style tweaks with no
structural/layout change." Concretely: the diff (a) rewrites failure-state **copy** (offline
messaging), and (b) **removes** the Cancel button from the post-RPC failure branch (an affordance
deletion, not a new screen, route, flow, or component). No new layout is designed; the
confirm/failure interstitial's geometry is unchanged. A `.pen` wireframe designs *new* screens —
there is nothing new to design here, only a button removed and text corrected within an existing
dialog. Per the gate's own intent (catch UI *features* shipping without design), this is exempt.
**Pencil is also genuinely unavailable in this pipeline environment** (`PENCIL_CLI_KEY` unset,
no `pencil login`), so the gate's two permitted outcomes collapse to the exemption — fabricating a
`.pen` is explicitly forbidden ("No Markdown/ASCII fallback"). This is a documented, principled
exemption, NOT a silent skip: `ux-design-lead` does not appear in `Skipped specialists:` and the
`### Product/UX Gate` subsection exists, so work Check-9's two FAIL conditions (skipped specialist
OR absent gate) are both unmet. The copy itself is validated by `user-impact-reviewer` at
review time.

## Open Questions (resolve at deepen-plan / plan-review)

1. **Force-complete vs. honest interstitial** — RESOLVED at plan-review (BOTH-panels consolidation:
   force-complete is the simpler path AND the issue's recommended fix). **Force-complete is the
   locked primary.** Open only as a deepen-plan/ux override if the abrupt navigation is judged
   user-hostile; otherwise build force-complete and do not build the interstitial.
2. **`committed` boolean vs. discriminated `SwitchStatus`.** Plan prefers the discriminated
   union for exhaustiveness; confirm at plan-review (DHH may prefer the minimal boolean if the
   render branching stays trivial).
3. **Sentry capture on the post-RPC catch** — confirm we *add* a `Sentry.captureMessage` (the
   component currently uses `console.error`). `cq-silent-fallback-must-mirror-to-sentry` argues
   yes for the brand-critical post-RPC branch.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Make the RPC + JWT re-mint atomic (server-side single transaction) | The JWT re-mint is a Supabase auth operation (`refreshSession`), not a DB write — it cannot be folded into the `set_current_workspace_id` SQL transaction. Two-phase-commit on the **client** is the only available seam. |
| Roll back the RPC on refreshSession failure (compensating write) | Would require a second RPC to reset `user_session_state` to the old workspace; that second write can ALSO fail (same network blip), reopening the divergence. Converge-forward (the durable state already reflects user intent — they DID click Confirm) is simpler and matches "user already authorized the switch." |
| Leave the FSM, just change Cancel copy | Copy alone doesn't fix it — Cancel still leaves the DB/JWT divergent. The affordance, not the wording, is the bug. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with a
  concrete artifact + exposure vector + `single-user incident` threshold.
- After widening `SwitchStatus`, grep the component for **every** `status === "failed"` site —
  the render block at `:148` is the obvious one, but confirm no other consumer (test included)
  pattern-matches the old single `"failed"` literal. `tsc --noEmit` (AC6) is the canonical
  enumerator; do not trust a manual count.
- Do NOT regress the existing `cancel aborts the switch — no RPC, no navigation` test — that
  asserts the PRE-RPC cancel, which remains correct. The new no-Cancel assertion is scoped to the
  POST-RPC failure state only.
- The success path and the Retry path both `window.location.assign("/dashboard")` via the shared
  `executeSwitch`. If force-complete is chosen for the post-RPC catch, ensure it does not
  double-navigate (guard against calling `assign` twice if the catch fires after a partial
  success). assign is idempotent for the browser but a second call mid-unload is wasteful.

## PR-body reminder

- Use `Closes #4917` in the PR **body** (not title) per `wg-use-closes-n-in-pr-body-not-title-to`.
  This is NOT an ops-remediation class (the fix lands in code at merge, no post-merge apply), so
  `Closes` is correct (not `Ref`).
