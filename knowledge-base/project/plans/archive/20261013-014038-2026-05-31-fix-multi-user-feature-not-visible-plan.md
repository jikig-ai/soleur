---
title: "fix: Multi-user (Members) feature not visible for ops@jikigai.com"
type: fix
date: 2026-05-31
branch: feat-one-shot-multi-user-feature-not-visible
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: diagnose-then-fix
related_specs:
  - knowledge-base/project/specs/feat-team-workspace-multi-user/spec.md
related_brainstorms:
  - knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md
  - knowledge-base/project/brainstorms/2026-05-29-flag-org-scoping-brainstorm.md
related_learnings:
  - knowledge-base/project/learnings/2026-05-27-supabase-getuser-app-metadata-does-not-include-jwt-hook-claims.md
  - knowledge-base/project/learnings/best-practices/2026-05-27-flagsmith-segment-rule-structure-verify-before-implementing.md
  - knowledge-base/project/learnings/2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md
---

# 🐛 fix: Multi-user (Members) feature not visible for ops@jikigai.com

## Overview

The "Members" tab (the multi-user / team-workspace invite feature) has disappeared from
**Settings** for `ops@jikigai.com`. The screenshot shows the settings sub-nav as
`General · Conversation names · Integrations · Scope Grants · Billing` — no **Members** tab
and no **Team Activity** tab. The user reports it was visible before.

The feature itself is **not removed from code** — every artifact in the visibility chain
exists on the current branch (premise validated in Phase 0.6 below). This is therefore a
**live-state regression**, not a code-deletion regression. The plan is a *diagnose-then-fix*:
the diagnosis MUST read live Flagsmith + Supabase state (the bug is invisible to code-grep),
then the fix is applied to whichever of the three failure modes is the actual cause, plus a
guard/observability addition so a silent disappearance surfaces next time instead of being
reported by the user.

### The visibility chain (verified in code — all present)

The Members tab is rendered only when **every** gate below passes. Any single failure hides
it with no error surfaced to the user:

| # | Gate | Location | Failure → tab hidden when |
|---|------|----------|---------------------------|
| 1 | Authenticated user | `app/(dashboard)/dashboard/settings/layout.tsx:11-15` (`resolveMembersTab`) | `getUser()` returns no user |
| 2 | `orgId` resolves non-null | `layout.tsx:17-18` → `resolveCurrentOrganizationId(user.id, supabase)` (`server/workspace-resolver.ts:44-73`) | `user_session_state.current_organization_id` is `NULL` for the user (read is source-of-truth, RLS `auth.uid()=user_id`) |
| 3 | Flag evaluates ON | `layout.tsx:20-21` → `isTeamWorkspaceInviteEnabled(orgId, identity)` → `getRuntimeFlag("team-workspace-invite", {userId, role:"prd", orgId})` (`lib/feature-flags/server.ts:144-165`) | Flagsmith `team-workspace-invite-orgs` segment lacks an `EQUAL orgId` condition for jikigai's org **AND** env fallback `FLAG_TEAM_WORKSPACE_INVITE` is `0`/unset in the live env |
| 4 | `membersTab` prop threaded to nav | `components/settings/settings-shell.tsx:24-37` | (cosmetic; only fires if 1–3 pass but prop is dropped — not the suspected cause) |

`activityTab` (the **Team Activity** sub-nav entry) is gated on `membersTab` being non-null
(`layout.tsx:31-33`), so it disappears together with Members — consistent with the screenshot.

### Why this is live-state, not code

- The route `/dashboard/settings/team/page.tsx` **exists** and itself re-gates via
  `resolveTeamMembershipPageData` (org + flag) → `notFound()` on `no-org`/`no-membership`.
- `resolveMembersTab` and `resolveCurrentOrganizationId` exist and were last touched by
  **#4516** (`fix(auth): query user_session_state directly for org resolution`) whose own
  commit message documents the *prior occurrence of this exact symptom*: "This caused the
  Members tab and all org-gated features to silently fail for every user."
- The flag was **migrated off the legacy shared `org-targeted` segment onto a per-feature
  `team-workspace-invite-orgs` segment** in **#4617** (commits `a17995cf` flip.sh
  `--detach-shared`, `4c3c5a25` retirement-complete). Decision #7 of the flag-org-scoping
  brainstorm explicitly warned: *"Cutover must not drop `team-workspace-invite` for either
  org."* A dropped `EQUAL orgId` condition during that cutover is the leading hypothesis.

## User-Brand Impact

(Carry-forward from `feat-team-workspace-multi-user` brainstorm `USER_BRAND_CRITICAL=true`.)

**If this lands broken, the user experiences:** the multi-user feature they paid for / were
promised silently absent with no error and no way to self-diagnose — the operator (Jean)
cannot invite or manage workspace members, defeating the internal dogfood and the external
team prospect signal (#2972). A *fix* that mis-targets the flag could over-expose the feature
to a **non-opted-in org**, exposing another org's spend/key-delegation surface.

**If this leaks, the user's data / workflow / money is exposed via:** enabling
`team-workspace-invite` for the wrong org (a flag mis-flip during the fix) would surface the
invite/membership UI — and the cross-tenant boundary it governs — to a tenant that never
opted in. The fix's re-verify read MUST prove the flag is ON for jikigai's org **and OFF for
a control org** (the proxy-vs-invariant trap, see Research Reconciliation).

**Brand-survival threshold:** `single-user incident`. One mis-targeted flag flip that enables
the multi-user surface for a non-opted-in org is brand-survival territory (CLO: GDPR Art. 33
72h clock triggers only if a non-opted-in org actually accesses personal data; design for
detectability).

`requires_cpo_signoff: true` — CPO sign-off required at plan time before `/work`. CPO already
framed the parent feature (Domain Review carry-forward, spec lines 157-160); this fix inherits
that framing. `user-impact-reviewer` will be invoked at review-time per the conditional-agent
block.

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report / sibling docs) | Reality (verified on branch) | Plan response |
|---|---|---|
| "Code regression removed the multi-user UI" | All visibility-chain artifacts exist (`layout.tsx`, `settings-shell.tsx`, `workspace-resolver.ts`, `feature-flags/server.ts`, `team/page.tsx`). No deletion in `git log`. | **Reject** code-deletion hypothesis. Treat as live-state regression. |
| Flag is "per-user / per-role targeted" | Flag is **per-org** via `team-workspace-invite-orgs` Flagsmith segment with `EQUAL orgId` conditions (`feature-flags/server.ts:24-31`); `role` hardcoded `"prd"` in `layout.tsx:20`. Identifier `org:${orgId}:${role}`. | Diagnosis must probe the **segment's `EQUAL orgId` conditions**, not a per-user trait. |
| "Just flip the flag back on" | A bare flip risks enabling the flag for the wrong org (shared-segment blast radius is exactly what #4617 removed). | Re-verify read MUST be `count==1` for jikigai **AND** OFF for a control org. Assert flag **evaluation** (identity+orgId), not segment **membership** alone (proxy-vs-invariant, learning `2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`). |
| `current_organization_id` always populated for solo users | Migration 060 backfilled it once; the column is `ON DELETE SET NULL` (migration 060 line 34) and writes route through `set_current_organization_id` RPC. It **can** become NULL (org/membership change, RPC write, cascade). | Diagnosis must **live-read** `user_session_state.current_organization_id` for ops@jikigai before assuming the flag is the cause. |
| The 200ms Flagsmith timeout could be the cause | On timeout, `getRuntimeSnapshot` falls back to `runtimeEnvFallback()` which reads `FLAG_TEAM_WORKSPACE_INVITE` env (`feature-flags/server.ts:90-96,139`). If env is `0` in the live env, a Flagsmith slowdown silently hides the tab. | Diagnosis must record the **live env value** of `FLAG_TEAM_WORKSPACE_INVITE` and whether Flagsmith is reachable (Sentry warn-debounce `flagsmith:getidentityflags-timeout`, #4571). |

## Hypotheses (ranked, each with a live probe)

**Diagnosis order is load-bearing: probe in this order, stop at the first confirmed cause,
but record all four readings in the PR body (cheap, and rules out compound causes).**

### H1 (leading) — Flagsmith segment dropped jikigai's org during the #4617 cutover
The `--detach-shared` migration (PR #4617) moved `team-workspace-invite` from the shared
`org-targeted` segment to `team-workspace-invite-orgs`. If jikigai's `EQUAL orgId` condition
was not carried over, the flag evaluates OFF for jikigai while `enabled=true` on the segment.
- **Probe:** GET the `team-workspace-invite-orgs` segment via the Flagsmith Admin API and list
  its `rules[].rules[].conditions[]` where `operator=EQUAL property=orgId`. Confirm jikigai's
  org UUID is present. (Structure per learning `2026-05-27-flagsmith-segment-rule-structure-verify-before-implementing.md`: `ALL → ANY → [EQUAL/orgId per org]`, NOT an `IN`.)
- **Probe (evaluation, not membership):** call `getIdentityFlags("org:<jikigai-org>:prd", {role:"prd", orgId:"<jikigai-org>"})` and assert `isFeatureEnabled("team-workspace-invite") === true`; repeat for a control org and assert `=== false`.
- **Fix:** re-add jikigai's `EQUAL orgId` condition via the sanctioned tool
  `plugins/soleur/skills/flag-set-role/scripts/flip.sh team-workspace-invite prd on --org <jikigai-org-uuid> [--control-org <real-sibling-uuid>] --confirmed`.
  Verified precedent (Phase 4.4 deepen): the plain `on --org` path (NOT `--detach-shared`)
  targets the feature's own `team-workspace-invite-orgs` segment, adds the org's `EQUAL orgId`
  condition, writes the WORM `flag_flip_audit` row (migration 071), then **re-verifies by
  EVALUATING the flag for the target org (must be enabled) and a control org (must be disabled)**
  — `flip.sh:6-9,116-121` ("re-verify reads the EVALUATED flag, not the membership set",
  `flip.sh:24,342-343`). **Do NOT mirror to Doppler for the per-org edit** — the `--org` path is
  segment-membership only and explicitly does "No Doppler" (`flip.sh:8-9`); Doppler
  `FLAG_TEAM_WORKSPACE_INVITE` mirrors the prd-**role**-segment state (role-grain fallback), not
  the per-org override. See corrected H1 fix note in Phase 1 and AC5.

### H2 — `user_session_state.current_organization_id` is NULL for ops@jikigai
If the org/membership state changed since migration 060's backfill (RPC write, org delete
cascade `ON DELETE SET NULL`, or never-set), `resolveCurrentOrganizationId` returns null →
`resolveMembersTab` returns null at gate #2, *before* the flag is even consulted.
- **Probe:** `SELECT current_organization_id FROM public.user_session_state WHERE user_id = (SELECT id FROM auth.users WHERE email='ops@jikigai.com')` against the correct project (PRD — never DEV, `hr-dev-prd-distinct-supabase-projects`). Cross-check `workspace_members` + `organizations` for ops@jikigai to confirm the *correct* org id.
- **Fix:** if NULL/wrong, write the correct org via the `set_current_organization_id` RPC
  (NOT a raw UPDATE — preserves the SECURITY DEFINER write boundary and re-checks
  `workspace_members`). Confirm the JWT hook (migration 060) then injects it on next token mint.
- **Guard:** `resolveCurrentOrganizationId` currently returns `null` on `!result.data`
  *silently* (no Sentry). If the row is simply missing for a user who *should* have one, that
  is an integrity surface that goes dark. Consider a `reportSilentFallback` on the
  `!result.data` branch for users with ≥1 `workspace_members` row (see Phase 3 / Observability).

### H3 — env-fallback OFF masks a Flagsmith outage
If `FLAGSMITH_ENVIRONMENT_KEY` is set but Flagsmith is timing out (200ms ceiling) and
`FLAG_TEAM_WORKSPACE_INVITE` is `0` in the live env, the tab disappears intermittently for
*all* orgs, not just jikigai.
- **Probe:** check live Doppler `FLAG_TEAM_WORKSPACE_INVITE` + `FLAGSMITH_ENVIRONMENT_KEY`
  presence; check Sentry for `flagsmith:getidentityflags-timeout` warn-debounce events
  (`feature-flags/server.ts:121-130`, #4571) in the reported window.
- **Fix:** if this is the cause, it is an availability incident, not a config bug — record it;
  the env-fallback mirror is role-grain, not org-grain (flag-org-scoping brainstorm CTO note —
  a per-org flag *correctly* falls back OFF during a Flagsmith outage, the safe direction). So
  the remediation here is Flagsmith availability + alerting, NOT flipping `FLAG_TEAM_WORKSPACE_INVITE`
  (which would enable the flag for every org).

### H4 (lowest) — `role: "prd"` hardcode / identity mismatch
`layout.tsx:20` hardcodes `role: "prd"`. If the live segment was provisioned with a `dev`
override only, prd-role identities miss it. Unlikely given the identifier is `org:<id>:prd`,
but record the role the segment override targets during the H1 probe.

## Implementation Phases

### Phase 0 — Live diagnosis (READ-ONLY; no prod writes)

> Per `hr-no-dashboard-eyeball-pull-data-yourself` and `hr-menu-option-ack-not-prod-write-auth`:
> pull the data via API, do not eyeball a dashboard; menu-option acknowledgement is not
> prod-write authorization. All Phase 0 steps are read-only.

0.1 Resolve jikigai's org UUID and ops@jikigai's user id from PRD Supabase
   (`mcp__plugin_supabase_supabase__*` or service-role REST; `hr-dev-prd-distinct-supabase-projects`).
0.2 **H2 probe:** read `user_session_state.current_organization_id` for ops@jikigai; cross-check
   `workspace_members` / `organizations`. Record the value (or NULL).
0.3 **H1 probe:** GET the `team-workspace-invite-orgs` Flagsmith segment; dump its
   `EQUAL/orgId` conditions; confirm presence/absence of jikigai's org UUID. Record the live
   structure (per the segment-structure learning — verify shape, do not assume `IN`).
0.4 **H1 evaluation probe (invariant, not proxy):** evaluate the flag via `getIdentityFlags`
   for jikigai (`expect ON`) and a control org (`expect OFF`). Record both.
0.5 **H3 probe:** read live `FLAG_TEAM_WORKSPACE_INVITE` (Doppler), `FLAGSMITH_ENVIRONMENT_KEY`
   presence; grep Sentry for `flagsmith:getidentityflags-timeout` in the reported window.
0.6 Write a one-paragraph **Diagnosis** into the PR body naming the confirmed failing gate(s)
   and the readings for all four probes. This is the load-bearing artifact — the fix branch
   chosen in Phase 1 is determined entirely by it.

### Phase 1 — Apply the targeted fix (the ONE confirmed cause)

Branch on the Phase 0 diagnosis. **Do exactly one** of the following (or the minimal set the
diagnosis proves are jointly the cause):

- **If H1:** run `flag-set-role` `flip.sh team-workspace-invite prd on --org <jikigai>
  --control-org <real-sibling> --confirmed` to re-add jikigai's `EQUAL orgId` condition on the
  `team-workspace-invite-orgs` segment; the skill writes the WORM audit row and does the
  EVALUATION re-verify (jikigai ON + control OFF) internally. **No Doppler mirror for the per-org
  edit** (the `--org` path is segment-only; Doppler is role-grain — `flip.sh:8-9`). **No code change.**
  Automation: `flag-set-role` skill (sanctioned tooling) — NOT a manual dashboard click.
- **If H2:** call `set_current_organization_id` RPC for ops@jikigai with the correct org id
  (via Supabase MCP / service-role REST). **No code change** to the resolver.
  Automation: Supabase MCP / `gh`/curl RPC call — not an operator dashboard step.
- **If H3:** file/record the Flagsmith availability incident; add alerting (Phase 3). No flag flip.
- **If H4:** correct the segment's role targeting via `flip.sh` (prd). No code change.

### Phase 2 — Regression guard (test + behavioral)

Add a **deterministic** regression test that fails if the visibility chain silently breaks
again, removing the live-state dependency from the assertion path:

- Unit test `resolveMembersTab` logic (extract a pure `shouldShowMembersTab(orgId, flagOn)`
  helper if needed, OR test the existing function with a mocked supabase + mocked
  `isTeamWorkspaceInviteEnabled`) asserting: (a) `orgId != null && flagOn` → tab shown;
  (b) `orgId == null` → hidden; (c) `flagOn == false` → hidden. Test FILE path MUST land under
  the runner's discovery glob — `apps/web-platform/test/...` per `vitest.config.ts` `include:`
  (NOT co-located, per Sharp Edge / #4634). Verify the runner is **vitest** via
  `apps/web-platform/package.json scripts.test` + `apps/web-platform/bunfig.toml`
  (`pathIgnorePatterns` blocks `bun test`).
- If the chosen cause is H1 (flag/segment), add the `flag-set-role` dry-run / re-verify
  assertion to the PR body output, NOT a new prod-touching test (per
  `hr-dev-prd-distinct-supabase-projects` — no synthetic users / no prod integration suite).

### Phase 3 — Close the observability gap (so the next disappearance is not user-reported)

The root failure class is **silent**: a tab vanishes with no error. Add detection at the gate
that went dark (per `## Observability`):

- If H2: add `reportSilentFallback`/`mirrorWarn` to `resolveCurrentOrganizationId` (or the
  layout) when a user with ≥1 `workspace_members` row resolves `orgId == null` — that is an
  integrity surface, not a normal solo-user case. Debounced, keyed on a non-PII shape
  (mirror the existing `feature-flags/server.ts:121-130` debounce pattern; NEVER emit userId).
- If H1/H3: ensure the `flagsmith:getidentityflags-timeout` warn-debounce is wired to an alert
  route (it currently mirrors to Sentry at WARNING; confirm an alert exists, else add one) so a
  Flagsmith outage that hides org-gated UI surfaces in observability, not via the user.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 (Diagnosis recorded):** PR body contains the Phase 0 Diagnosis paragraph with all
      four probe readings (H1 segment conditions, H1 evaluation jikigai=ON/control=OFF, H2
      `current_organization_id` value, H3 env + Sentry-timeout reading) and names the confirmed
      failing gate(s).
- [ ] **AC2 (Fix is targeted):** exactly the gate(s) the diagnosis proved broken are changed;
      no speculative edits to the other gates.
- [ ] **AC3 (Invariant, not proxy):** if the flag was touched, the PR shows the
      post-fix **evaluation** read: `team-workspace-invite` evaluates `true` for jikigai's org
      identity AND `false` for a named control org. Segment-membership-only evidence is
      insufficient (learning `2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`).
- [ ] **AC4 (No wrong-org exposure):** the control-org-OFF read in AC3 is present and OFF.
- [ ] **AC5 (Env-fallback fidelity):** the PR explicitly notes that the per-org `--org` flip does
      NOT change the role-grain Doppler `FLAG_TEAM_WORKSPACE_INVITE` mirror (`flip.sh:8-9` "No
      Doppler"; the env var mirrors the prd-**role**-segment, not per-org overrides —
      `feature-flags/server.ts:14-16`). Only a prd-role-segment state change reconciles Doppler.
- [ ] **AC6 (Regression test):** new deterministic test asserts the three visibility-chain
      branches (orgId+flag, orgId-null, flag-off), lands under the vitest discovery glob, and
      passes via `apps/web-platform`'s actual runner.
- [ ] **AC7 (Observability):** the gate that went dark now emits a debounced Sentry/alert
      signal on the silent-failure path; no userId is emitted.
- [ ] **AC8 (No prod synthetic residue):** no test or AC creates synthetic auth.users / runs an
      integration suite against PRD (`hr-dev-prd-distinct-supabase-projects`). Live PRD touch is
      limited to the read-only Phase 0 probes + the single sanctioned write in Phase 1.

### Post-merge (operator)
- [ ] **AC9 (User-visible confirmation):** the Members tab + Team Activity tab are visible in
      Settings for `ops@jikigai.com`. **Automation:** Playwright MCP (`mcp__playwright__*`) —
      sign in as the dogfood account (up to any OAuth/consent gate) and assert the
      `/dashboard/settings/team` link renders in the settings sub-nav; this is NOT a manual
      "operator checks the browser" step.
- [ ] **AC10 (Issue closure):** if this fix executes a prod write post-merge (flag flip / RPC),
      use `Ref #N` in the PR body and close the tracking issue in a post-merge step after the
      write + AC9 succeed (`Closes` would auto-close before the remediation runs — ops-remediation
      class Sharp Edge).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from
`feat-team-workspace-multi-user` spec Domain Review, lines 155-160).

### Engineering (CTO)
**Status:** carry-forward
**Assessment:** Approved architecture for the parent feature (organizations + workspaces +
workspace_members + `is_workspace_member` + per-feature Flagsmith segments per amended ADR-043).
This fix touches no schema and no RLS predicate — it diagnoses live flag/session state and
applies a sanctioned-tool flip or RPC write. The only code change is a regression test + a
debounced observability signal. No new architectural surface.

### Product (CPO)
**Status:** carry-forward (sign-off required — `requires_cpo_signoff: true`)
**Assessment:** CPO framed the parent feature with the override caveat (flagged UI; flag stays
OFF until legal scaffolding lands). The legal scaffolding has since merged (ToS/AUP/DPD/Side
Letter references present in `plugins/soleur/docs/pages/legal/*`). Restoring visibility for
jikigai (the day-one allowlisted org) is in-scope of the approved rollout. **CPO sign-off
required at plan time before `/work`** — confirm CPO has reviewed (or invoke CPO domain leader)
that re-enabling for jikigai does not change the OFF-for-all-other-orgs posture.

### Legal (CLO)
**Status:** carry-forward
**Assessment:** CLO's load-bearing gate is *cross-org scoping must be proven via a post-write
re-verify read* (flag-org-scoping brainstorm CLO note). AC3/AC4 encode exactly this
(jikigai=ON, control=OFF). No new regulated-data surface is added; the WORM `flag_flip_audit`
row (migration 071) is written by the `flag-set-role` tool if a flip occurs. GDPR Art. 33 72h
clock is not triggered unless a non-opted-in org actually accessed personal data — the
control-OFF assertion is the detectability gate.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (no new UI; restores an existing tab), copywriter (no copy)
**Pencil available:** N/A
#### Findings
This fix restores an existing, already-designed nav tab. It adds no new user-facing surface,
modal, or copy. No wireframes required.

## Infrastructure (IaC)

Skip — no new infrastructure. No server, service, cron, vendor account, DNS, TLS, secret, or
firewall rule is introduced. The fix mutates **existing** runtime state: a Flagsmith segment
condition (via the sanctioned `flag-set-role` skill, which already wraps the Flagsmith Admin
API + WORM audit) and/or a `user_session_state` row (via the existing
`set_current_organization_id` RPC). The per-org `--org` flip does NOT touch Doppler
(`flip.sh:8-9` "No Doppler"); the existing `FLAG_TEAM_WORKSPACE_INVITE` secret mirrors the
prd-role-segment fallback only and is not provisioned or reconciled by this fix.

## Observability

```yaml
liveness_signal:
  what: "Members tab renders for an org-enabled identity; flag evaluates true for jikigai"
  cadence: "per settings-page render (request-time) + AC9 post-merge Playwright assertion"
  alert_target: "Sentry (existing project) — feature-flags + workspace-resolver scopes"
  configured_in: "apps/web-platform/lib/feature-flags/server.ts (mirrorWarnWithDebounce); apps/web-platform/server/workspace-resolver.ts (reportSilentFallback)"
error_reporting:
  destination: "Sentry via reportSilentFallback / mirrorWarnWithDebounce"
  fail_loud: "false for the recovered (env-fallback) path by design; the NEW signal in Phase 3 fires when a user WITH workspace_members resolves orgId=null — that is an integrity surface and is reported"
failure_modes:
  - mode: "Flagsmith timeout (200ms ceiling) -> silent env fallback"
    detection: "Sentry warn-debounce key flagsmith:getidentityflags-timeout (server.ts:121-130, #4571)"
    alert_route: "Sentry WARNING — Phase 3 confirms/adds an alert rule routing it"
  - mode: "current_organization_id NULL for a multi-membership user"
    detection: "NEW Phase 3 reportSilentFallback on resolveCurrentOrganizationId !result.data when user has >=1 workspace_members row"
    alert_route: "Sentry — debounced, no userId emitted"
  - mode: "Flag segment lost jikigai org during a future migration"
    detection: "flag-set-role re-verify read (count==1 jikigai, OFF control) at flip time + WORM flag_flip_audit row"
    alert_route: "exit-non-2xx hard-block in flip.sh + WORM audit trail (migration 071)"
logs:
  where: "Sentry (errors/warns); pino structured logs (server); flag_flip_audit WORM table (migration 071, 7-yr)"
  retention: "Sentry default; WORM 7 years"
discoverability_test:
  command: grep -nE settings-members-tab apps/web-platform/server/members-tab.ts
  expected_output: "settings-members-tab"
```

## Open Code-Review Overlap

None (check ran: no open `code-review`-labelled issue names the visibility-chain files;
verify with `gh issue list --label code-review --state open` at /work time per Phase 1.7.5).

## Files to Edit

- `apps/web-platform/server/workspace-resolver.ts` — **(conditional on H2)** add debounced
  `reportSilentFallback` on the `!result.data` branch of `resolveCurrentOrganizationId` when
  the user has ≥1 `workspace_members` row (Phase 3 observability). No behavioral change to the
  return value.
- `apps/web-platform/app/(dashboard)/dashboard/settings/layout.tsx` — **(optional)** if a pure
  `shouldShowMembersTab` helper is extracted for testability; otherwise unchanged.

## Files to Create

- `apps/web-platform/test/<members-tab-visibility>.test.ts` — deterministic regression test for
  the three visibility-chain branches (Phase 2 / AC6). Path under the vitest `include:` glob.

## Files to Read (diagnosis, no edit)

- Live Flagsmith `team-workspace-invite-orgs` segment (Admin API).
- PRD Supabase `user_session_state`, `workspace_members`, `organizations` for ops@jikigai.
- Doppler `FLAG_TEAM_WORKSPACE_INVITE`, `FLAGSMITH_ENVIRONMENT_KEY` (presence only).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled.)
- **Do not flip the flag before reading live state.** The bug may be H2 (NULL org), in which
  case flipping the flag changes nothing and leaves a misleading WORM audit row. Phase 0 read
  is load-bearing and gates Phase 1.
- **Segment structure is `ALL → ANY → [EQUAL/orgId]`, NOT `IN`** (learning
  `2026-05-27-flagsmith-segment-rule-structure-verify-before-implementing.md`). A probe that
  assumes a comma-separated `IN` value will misread the live segment.
- **Membership ≠ evaluation.** Asserting jikigai's `EQUAL orgId` condition exists on the segment
  proves *membership*, not that the flag *evaluates* ON for jikigai's identity (the feature-state
  override must also be present). Always assert via `getIdentityFlags`, with a control-org-OFF
  negative (learning `2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`).
- **Env fallback is role-grain, not org-grain.** A per-org flag *correctly* falls back OFF
  during a Flagsmith outage (flag-org-scoping brainstorm CTO note). Do NOT "fix" an outage by
  setting `FLAG_TEAM_WORKSPACE_INVITE=1` — that would enable it for *every* org. Outage
  remediation is availability/alerting, not an env flip.
- **PRD vs DEV Supabase** (`hr-dev-prd-distinct-supabase-projects`): ops@jikigai is a PRD
  account. All probes and the single write target the PRD project.
- **ops-remediation issue closure:** if the fix is a post-merge prod write, use `Ref #N` not
  `Closes #N`; close the issue in a post-merge step after the write + AC9 succeed.
- **Test runner:** `apps/web-platform` uses **vitest**, not `bun test` (`bunfig.toml`
  `pathIgnorePatterns` blocks bun test discovery). Test file MUST match the vitest `include:`
  glob (`test/**/*.test.ts[x]`), not a co-located `components/**` path (#4634).

## Test Scenarios

1. `orgId` resolves + flag ON → Members tab + Team Activity tab present.
2. `orgId` resolves null (no `user_session_state` row / null column) → both tabs hidden, no crash.
3. flag OFF for the org → both tabs hidden.
4. Flagsmith timeout + env fallback ON → tab shown (recovered path); + env fallback OFF → hidden.
5. (Post-fix, live) jikigai identity evaluates `team-workspace-invite=true`; control org `=false`.

## Research Insights (deepen-plan)

### Precedent-Diff Gate (Phase 4.4) — verified against repo

All three remediation primitives the plan prescribes have an in-repo sanctioned precedent;
each was read at deepen time (no novel pattern):

| Primitive | Precedent (verified) | Confirms |
|---|---|---|
| Flag re-enable for an org | `plugins/soleur/skills/flag-set-role/scripts/flip.sh` usage line 7: `flip.sh <flag> <prd\|dev> <on\|off> [--confirmed] [--org <orgId>] [--dry-run]`. The plain `on --org` path (≠ `--detach-shared`) targets the feature's own `<flag>-orgs` segment, adds the `EQUAL orgId` condition, and **EVALUATION-re-verifies** (target ON + control OFF) at `flip.sh:6-9,116-121`. | H1 fix invocation is exact; AC3/AC4 (evaluation not membership) map to the script's load-bearing FR8 re-verify. |
| Org session-state write | `set_current_organization_id` RPC, migration `060_current_organization_jwt_hook.sql:29,45` — "INSERT/UPDATE routed through `set_current_organization_id` RPC; no [raw write]". | H2 fix path uses the SECURITY DEFINER RPC, not a raw UPDATE — preserves the write boundary. |
| WORM audit of the flip | `flag_flip_audit` table, migration `071_flag_flip_audit.sql` (7-yr retention). | Observability `failure_modes[2]` + AC3 audit trail are real, not aspirational. |

### Verify-the-Negative Pass (Phase 4.45) — negative claims confirmed

- **"All visibility-chain artifacts exist (no code deletion)"** → CONFIRMED: `layout.tsx`,
  `settings-shell.tsx`, `workspace-resolver.ts`, `feature-flags/server.ts`,
  `app/(dashboard)/dashboard/settings/team/page.tsx` all present on branch.
- **"Members + Team Activity are the only dynamic tabs; the 5 static tabs match the screenshot"**
  → CONFIRMED: `settings-shell.tsx:13-19` static list = `General · Conversation names ·
  Integrations · Scope Grants · Billing` (exactly the screenshot); `membersTab`/`activityTab`
  are appended conditionally (`:33-37`). The screenshot's missing tabs are precisely the two
  flag-gated ones.
- **"Env fallback is role-grain, not org-grain — a per-org flag falls back OFF on Flagsmith
  outage"** → CONFIRMED: `runtimeEnvFallback()` reads `FLAG_TEAM_WORKSPACE_INVITE` with no orgId
  dimension (`feature-flags/server.ts:90-96`); `flip.sh:8-9` "No Doppler" for the `--org` path.
  The plan's H3 "do not flip env to fix an outage" guard is therefore correct.

### Live Citation Verification (Quality Checks)

| Ref | Live state (gh) | Role in plan |
|---|---|---|
| #4516 | CLOSED issue "feat: build team workspace Members tab UI and invite flow" (closed by #4518 `fix(auth): query user_session_state directly`) | prior occurrence of this exact symptom; source-of-truth read |
| #4617 | CLOSED issue "migrate team-workspace-invite off shared org-targeted to twi-orgs" | the segment cutover — H1's regression window |
| #4629 | MERGED PR "docs(adr-043): mark org-targeted retirement complete (#4617)" | retirement-complete |
| #2972 | CLOSED issue "validate small-team expansion" | the prospect/dogfood signal motivating the feature |
| #4581 / #4582 | CLOSED issue / MERGED PR — per-feature segment scoping | the per-org segment model H1 probes |

### Round-1 Self-Audit (Phase 4.45) — corrections applied this pass

- Removed an inaccurate "mirror to Doppler `FLAG_TEAM_WORKSPACE_INVITE`" instruction from H1 +
  Phase 1 + AC5 + Infrastructure: the `flip.sh --org` path is segment-membership only and does
  "No Doppler" (`flip.sh:8-9`). Doppler mirrors the prd-**role**-segment, not per-org overrides.
  Leaving the instruction in would have produced a spurious env-var write that re-enables the
  flag for **every** org — the exact wrong-org-exposure the User-Brand Impact section guards.

## Enhancement Summary

**Deepened on:** 2026-05-31
**Sections enhanced:** Hypotheses (H1 fix), Phase 1, Acceptance Criteria (AC5), Infrastructure,
plus new Research Insights.
**Hard gates passed:** 4.6 User-Brand Impact (present, threshold `single-user incident`),
4.7 Observability (5/5 fields, no SSH in discoverability_test), 4.8 PAT-shaped (no matches).

### Key Improvements
1. **Corrected the Doppler-mirror error** — the leading-hypothesis fix (`flip.sh --org`) does
   NOT write Doppler; the prior wording risked re-enabling the flag for every org.
2. **Verified all three remediation precedents in-repo** (flip.sh re-verify, `set_current_organization_id`
   RPC, `flag_flip_audit` migration 071) — no novel pattern; the plan's fix instructions are exact.
3. **Confirmed the negative claims** (no code deletion; static vs dynamic tab split matches the
   screenshot; env fallback is role-grain) against the actual source.

### New Considerations Discovered
- The `flip.sh` `--org` path already performs the AC3/AC4 evaluation re-verify (target ON +
  control OFF) internally — the plan should rely on the script's output, not re-implement it.
- ops@jikigai is a **PRD** account; every probe and the single write target the PRD Supabase
  project + the prd Flagsmith environment (`hr-dev-prd-distinct-supabase-projects`).
