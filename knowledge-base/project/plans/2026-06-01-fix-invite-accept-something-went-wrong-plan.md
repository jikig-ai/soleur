---
title: "fix: invite-accept Join screen shows generic \"Something went wrong\""
type: fix
date: 2026-06-01
branch: feat-one-shot-invite-accept-something-went-wrong
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# 🐛 fix: invite-accept "Something went wrong. Please try again." regression

## Enhancement Summary

**Deepened on:** 2026-06-01

### Key Improvements (folded into the plan body)

1. **Pass the RPC `error` object to `reportSilentFallback`, not `null`** (Phase 1). Verified
   against `server/observability.ts:185` — `sqlStateFromError(err)` emits the SQLSTATE as a
   queryable `pg_code` Sentry tag (#4695). All four existing sibling calls pass `null` and
   lose it; passing `error` is what turns this 42703/grant-drift class into a one-grep
   diagnosis. Highest-value line in the fix.
2. **Test harness pinned to the verified mock pattern** (Phase 4): `vi.mock` of
   `@/lib/supabase/service` + `@/server/observability` + `@/server/logger`, helpers at
   `apps/web-platform/test/helpers/mock-supabase.ts`, runner `./node_modules/.bin/vitest run`.
3. **Precedent-diff for the SECURITY DEFINER RPC + Sentry-mirror pattern** recorded below.

### New Considerations Discovered

- The bug is almost certainly NOT in the migration source (verified consistent end-to-end);
  it is live prod schema/grant drift OR the dark-error masking. The fix is mostly
  observability + copy + a live-DB-confirmed migration apply — not an RPC rewrite.
- Gates 4.6 (User-Brand Impact, threshold `single-user incident`), 4.7 (Observability,
  no-ssh), 4.8 (no PAT-shaped vars) all PASS. 4.5 network-outage: no triggers (the only
  "ssh" token is the literal "NO ssh" in the discoverability command).

### Precedent-Diff (Phase 4.4)

| Pattern | Precedent (verified) | This plan |
| --- | --- | --- |
| Sentry-mirror on RPC failure | `revokeWorkspaceInvitation` `:281-289` — `reportSilentFallback(null, {feature, op:"revoke", message})` | Same shape for `op:"accept"` **but first arg = `error`** (improves on precedent — emits `pg_code`) |
| `accept_workspace_invitation` SECURITY DEFINER RPC | `085_revoke_workspace_invitation.sql:190` — `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `REVOKE ALL … FROM authenticated` + `GRANT EXECUTE … TO service_role` | No RPC change unless Phase 0 proves drift; if so, a NEW forward `086_…` migration with the same pinned shape (never edit `085` in place) |
| Arg-capture vitest unit + opt-in dev integration | `workspace-invitations-pending-select.test.ts` + `workspace-invitations-pending.integration.test.ts` (bb5eee90) | Same two-file pattern, same `TENANT_INTEGRATION_TEST=1` gate, dev-only |

## Overview

When `jean.deruelle@gmail.com` opens the workspace invite from `ops@jikigai.com`, the
`/invite/[token]` **Join screen** renders correctly ("Join {workspace}", "… invited you to
join as a **member**", expires 6/8/2026). Clicking **Accept invitation** then shows the red
error box **"Something went wrong. Please try again."** and the user is not joined.

The cited commit `bb5eee90` ("fix(invite): pending-invite query drops auth-only
raw_user_meta_data (42703)") fixed the **read/display** path (`getPendingInvitesForUser`,
the dashboard recovery banner). It did **not** touch the **write** path behind the Accept
button. So this is a sibling failure in the acceptance path, of the same 42703 *class*
(an RPC failing in prod against a schema that the migration source no longer matches), but
in a different surface.

### What the investigation established (static source is correct end-to-end)

The Accept click runs this chain:

```
invite-actions.tsx handleAccept()                         (client)
  → POST /api/workspace/accept-invite/route.ts            (route)
    → acceptWorkspaceInvitation(invitationId, user.id)    (server/workspace-invitations.ts)
      → supabase.rpc("accept_workspace_invitation", …)    (Postgres SECURITY DEFINER RPC)
```

The **migration source** for `accept_workspace_invitation` (latest definition in
`085_revoke_workspace_invitation.sql:190-270`, superseding `076` and `075`) is internally
consistent: the happy path INSERTs into `workspace_member_attestations` then
`workspace_members`, all FK/CHECK/NOT-NULL constraints are satisfied, the
`workspace_members_audit` trigger (`063:160`) tolerates a NULL actor GUC, and the BYOK
member-delete trigger (`064:856`) is `AFTER DELETE` only. **No static defect in the write
path produces this error.**

Two real defects WERE found that this plan fixes, and one root-cause hypothesis that can
only be confirmed against live prod:

1. **Observability gap (confirmed, `cq-silent-fallback-must-mirror-to-sentry`).**
   `acceptWorkspaceInvitation` (`server/workspace-invitations.ts:208-211`) returns
   `reason: "rpc_failed"` on RPC error but only `log.error(...)` to pino — it does **NOT**
   call `reportSilentFallback`. Its sibling `revokeWorkspaceInvitation` (`:281-289`) DOES
   mirror to Sentry. This asymmetry is why the actual prod failure is invisible in Sentry
   and the bug is undiagnosable from logs alone.

2. **Reason-code → copy mapping gap (confirmed).** The client `reasonToMessage`
   (`invite-actions.tsx:24-40`) has **no case** for `rpc_failed` or `revoked`, so both fall
   through to the default `"Something went wrong. Please try again."`. The exact user-facing
   string in the report is this default branch. A genuine `rpc_failed` and a genuine
   `revoked` are indistinguishable to the user (and `revoked` even has a friendly meaning —
   "the owner cancelled this invite").

3. **Root-cause hypothesis (requires live-DB confirmation, like bb5eee90 was "confirmed
   against the live prod DB").** Because the source is correct, the live `rpc_failed` is
   most likely **prod schema/grant drift**: e.g. migration `085` not applied to prod (so
   the `revoked_at`/`revoked_by` columns or the revoked-aware RPC body are missing, and the
   RPC errors on `v_inv.revoked_at`), or the `GRANT EXECUTE … TO service_role` was lost, or
   a divergent live RPC body referencing a dropped/renamed column. This MUST be confirmed at
   /work time via the Supabase MCP against the **dev** project first, then **prod** (read
   only) — never assume from source.

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report) | Reality (verified) | Plan response |
| --- | --- | --- |
| "after the recent invite fixes (bb5eee90)" caused the Accept failure | bb5eee90 only changed `getPendingInvitesForUser` (read path); the Accept write path (`accept_workspace_invitation` RPC) was untouched by it | Treat as a *sibling* failure of the same 42703 class, not a direct regression from bb5eee90. Investigate the write path + live prod state. |
| "Clicking Accept invitation fails" with "Something went wrong" | Confirmed: that exact string is the default branch of `reasonToMessage` (`invite-actions.tsx:38`), reached when `data.error ∈ {rpc_failed, revoked, …}` — codes the switch does not map | Add `rpc_failed`/`revoked` (and any other emitted-but-unmapped code) handling; surface a distinguishable message. |
| The Join screen renders (title, inviter, role, expiry) | `lookup_invitation_by_token` RPC succeeded → row is NOT revoked/expired/declined/accepted at *lookup* time | The failure is in the *mutation* RPC or its live prod definition, not lookup. |
| Member, expires 6/8/2026 | Not expired (today 2026-06-01); `role='member'` is valid | Rules out `expired` and invalid-role as the reason. |

## User-Brand Impact

**If this lands broken, the user experiences:** a workspace invitation that can never be
accepted — the single most important first-touch flow for a multi-user workspace. The
invitee sees a dead-end "Something went wrong" with no recovery and no signal to the inviter.

**If this leaks, the user's data / workflow / money is exposed via:** no new data exposure
(this is a fix that makes a *blocked* write succeed and improves error copy). The change must
NOT widen who can accept — the existing identity binding (`076`/`085` RPC `not_intended_invitee`
check + route 403 + page email gate) is the security floor and must be preserved verbatim.

**Brand-survival threshold:** single-user incident — a broken invite-accept is a first-touch
brand failure for every invited collaborator; one stuck invitee is a brand incident.

> CPO sign-off required at plan time before `/work` begins (carried from the single-user-incident
> threshold). The `user-impact-reviewer` agent runs at review time.

## Premise Validation

Checked: cited commit `bb5eee90` exists and is real (read its diff — it edits only
`getPendingInvitesForUser`'s embedded select, dropping `raw_user_meta_data`). The Accept
button path (`invite-actions.tsx` → `/api/workspace/accept-invite/route.ts` →
`acceptWorkspaceInvitation` → `accept_workspace_invitation` RPC) all exist on the branch.
Open issues #4530 (accept-invite should require raw token) and #4636 (resend invite) are
separate enhancements, not this regression. No open `code-review` issues touch the
accept-invite or workspace-invitations files. The premise holds with one refinement: this is
a *sibling* of bb5eee90, not a direct consequence of it.

## Root-Cause Hypotheses (resolve at /work Phase 0, live-DB-first)

Ordered most→least likely. The error reaching the client is `rpc_failed` (the only
emitted-but-unmapped code that fits an authenticated, intended, non-expired invitee).

- **H1 — Prod migration drift: `085` not applied.** If prod is at `076`, the live
  `accept_workspace_invitation` body has no `revoked_at` reference and the
  `workspace_invitations` table lacks `revoked_at`/`revoked_by`. But the route + lib
  reference no revoked columns directly, so a `076`-era RPC would *succeed*. More precisely:
  if `085` was applied **partially** (RPC redefined to reference `v_inv.revoked_at` but the
  `ADD COLUMN` did not run, or vice-versa) the RPC errors at runtime → `rpc_failed`.
  **Verify:** Supabase MCP — read live `accept_workspace_invitation` body + confirm
  `workspace_invitations.revoked_at`/`revoked_by` columns exist on dev AND prod.
- **H2 — Lost `GRANT EXECUTE … TO service_role`.** If a `CREATE OR REPLACE FUNCTION`
  redefinition in prod dropped the grant, the service-role call gets a permission error →
  `rpc_failed`. **Verify:** `has_function_privilege('service_role', 'public.accept_workspace_invitation(uuid,uuid)', 'EXECUTE')`.
- **H3 — Divergent live RPC referencing a dropped/renamed column** (the literal 42703 class).
  **Verify:** read the live function source; grep for any column not in the live table shape.
- **H4 — `workspaces!inner(name)` embed in the route pre-check (`route.ts:32-36`) erroring**
  and `invRow` swallowed as null — but this only skips the `isInvitee` gate; it does not
  cause `rpc_failed`. Low likelihood; rule out by inspection.

If H1–H3 confirm drift, the fix is **the migration apply** (idempotent re-run of `085` on
prod via the canonical Doppler `prd_terraform`/migration pipeline) PLUS the two code-side
hardening fixes below (which make the next occurrence diagnosable). If the live RPC source
matches `085` exactly and the grant is present, escalate: capture the live `rpc_failed`
Postgres error text (now possible because of fix #1) and re-triage.

## Implementation Phases

### Phase 0 — Live-DB confirmation (RED evidence, no code yet)

1. Use the Supabase MCP (dev project first). Read the live `accept_workspace_invitation`
   function source; compare against `085`. Confirm `workspace_invitations` has
   `revoked_at`/`revoked_by`. Check `has_function_privilege('service_role', …)`.
2. Repeat read-only against prod (per `hr-dev-prd-distinct-supabase-projects`, dev and prod
   are distinct projects — never run integration writes against prod, per the AC-discipline
   rule). Capture the divergence (if any) into the plan's Research Insights / PR body.
3. Reproduce the `rpc_failed` (or the actual Postgres error) by calling the RPC with the
   real invitation id + accepter user id as `service_role` on **dev** inside
   `BEGIN; … ROLLBACK;`. Record the SQLSTATE + message.

### Phase 1 — Observability fix (mirror RPC failure to Sentry)

File: `apps/web-platform/server/workspace-invitations.ts:208-211`
(`acceptWorkspaceInvitation`). Mirror the sibling `revokeWorkspaceInvitation` pattern
(`:281-289`) but **pass the RPC `error` object as the FIRST arg** (NOT `null`): on RPC
`error`, call `reportSilentFallback(error, { feature: "workspace-invitations", op: "accept",
message: \`accept_workspace_invitation RPC failed: ${error.message}\` })` BEFORE returning
`{ ok:false, reason:"rpc_failed" }`. Also mirror the reasonless `ok=false` ("unknown") branch
(`:214-215`) the same way the revoke fn does (`:296-303`) — for that branch there is no error
object, so pass `null`. Preserve the existing pino `log.error`. This carries the Postgres
error message into Sentry so the next occurrence is diagnosable instead of dark.

> **Deepen finding (load-bearing — improve on the precedent, do not blindly copy it).**
> `reportSilentFallback(err, options)` runs `sqlStateFromError(err)` (`server/observability.ts:185`,
> #4695) and, when `err` is a Postgres/PostgREST error, emits the SQLSTATE as a **queryable
> `pg_code` Sentry tag** (e.g. `pg_code:42703`, `pg_code:42501`). EVERY existing
> `reportSilentFallback` call in `workspace-invitations.ts` (`:98, :106, :283, :298`) passes
> `null` and therefore loses this tag. Passing the real `error` here is exactly the signal
> that turns this class of bug (the 42703 / grant-drift family) from "Something went wrong"
> into a one-grep Sentry diagnosis. This is the highest-value line in the fix.

> Carry-forward the original log message string verbatim: the existing
> `"accept_workspace_invitation RPC failed"` pino literal must remain (a helper/Sentry
> migration that changes the operator-facing message string silently darkens any dashboard
> keyed on the original literal).

### Phase 2 — Reason-code → copy mapping fix (no more silent generic error)

File: `apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx:24-40`
(`reasonToMessage`). Add cases for **every** code the route/RPC can emit that is currently
unmapped:

- `revoked` → "This invitation has been cancelled. Ask the workspace owner to send a new one."
- `rpc_failed` (and `caller_not_authenticated`, `unauthorized`) → keep a *generic-but-honest*
  fallback, but distinguish a transient backend error from a terminal state. Recommended:
  `rpc_failed` → "Something went wrong on our end. Please try again in a moment." (signals
  retry is meaningful), while genuinely-terminal unmapped codes keep the existing default.

Enumerate the full emitted set (route `route.ts` + lib + RPC) and classify each as
mapped/terminal/transient — do not leave any emitted code falling through unintentionally.
Emitted codes to classify: `invitation_not_found, already_accepted, already_declined,
revoked, expired, already_member, not_intended_invitee, rpc_failed, caller_not_authenticated,
unauthorized, invalid_body, invalid_json`.

### Phase 3 — Root-cause remediation (driven by Phase 0 outcome)

- **If prod migration drift (H1/H2/H3):** route the apply through the existing migration
  pipeline (`web-platform-release.yml#migrate` — verify the exact workflow/job name at
  /work via `ls .github/workflows/` per the named-artifact-verification rule; do NOT
  prescribe a fabricated workflow file). `085` is written idempotently
  (`ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, re-`GRANT`), so a re-apply is
  safe. Confirm post-apply with the Phase 0 read-only checks. This is the actual unblock.
- **If the live RPC matches source and the grant is present:** the regression is elsewhere
  (re-triage using the now-captured Sentry error). Do NOT ship a speculative RPC change.

### Phase 4 — Regression test (deterministic, no LLM, runner-correct path)

- **Unit (route reason mapping):** add `apps/web-platform/test/server/` … a `.test.ts`
  asserting `reasonToMessage` returns a non-default, distinguishable string for `revoked`
  and a transient-flavored string for `rpc_failed` (guards Phase 2). Place under
  `test/**/*.test.ts` (vitest node project) — NOT co-located, NOT `bun test`
  (`bunfig.toml` blocks bun discovery; runner is vitest).
- **Unit (observability):** assert `acceptWorkspaceInvitation` calls `reportSilentFallback`
  when the mocked supabase `.rpc()` returns `{ error }`, AND that it passes the `error`
  object as the FIRST arg (so `pg_code` is emitted), not `null` (guards Phase 1). Mirror the
  existing `workspace-invitations-pending-select.test.ts` mock style added by bb5eee90:
  `vi.mock("@/lib/supabase/service", () => ({ createServiceClient: vi.fn(() => ({ rpc:
  mockRpc })) }))` + `vi.mock("@/server/observability", () => ({ reportSilentFallback:
  vi.fn() }))` + `vi.mock("@/server/logger", …)`; assert
  `expect(reportSilentFallback).toHaveBeenCalledWith(mockError, expect.objectContaining({
  feature: "workspace-invitations", op: "accept" }))`. Helpers live at
  `apps/web-platform/test/helpers/mock-supabase.ts`.
- **Opt-in integration (`TENANT_INTEGRATION_TEST=1`, DEV only):** exercise the real
  `accept_workspace_invitation` RPC against dev Supabase end-to-end (create invite → accept →
  assert `workspace_members` row + `accepted_at` set), mirroring
  `workspace-invitations-pending.integration.test.ts`. This is the durable guard that catches
  schema/grant drift the unit mocks cannot — the exact gap bb5eee90 documented. **Never run
  integration writes against prod.**

## Files to Edit

- `apps/web-platform/server/workspace-invitations.ts` — Phase 1 (Sentry mirror on
  `accept_workspace_invitation` RPC failure + reasonless ok=false).
- `apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx` — Phase 2
  (`reasonToMessage` cases for `revoked`, `rpc_failed`, and audit of all emitted codes).
- `apps/web-platform/supabase/migrations/085_revoke_workspace_invitation.sql` — **only if**
  Phase 0 proves the live RPC body diverges from intended (e.g., add the missing column ref
  in a NEW migration `086_…`; never edit an applied migration in place — add a forward
  migration).

## Files to Create

- `apps/web-platform/test/server/workspace-invitations-accept.test.ts` — unit guards
  (reason mapping + Sentry mirror).
- `apps/web-platform/test/server/workspace-invitations-accept.integration.test.ts` — opt-in
  dev integration guard (gated on `TENANT_INTEGRATION_TEST=1`).
- (Conditional) `apps/web-platform/supabase/migrations/086_<topic>.sql` + `.down.sql` — only
  if Phase 0 proves a forward DDL/RPC repair is needed.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issues whose body
references `accept-invite` or `workspace-invitations`.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `acceptWorkspaceInvitation` mirrors the RPC-failure path to Sentry via
  `reportSilentFallback` (passes the RPC `error` object as the first arg for the `pg_code`
  tag), matching the `revokeWorkspaceInvitation` sibling shape.
- [x] `reasonToMessage` returns a string distinct from the default for `revoked` and a
  transient-flavored string for `rpc_failed`; a test asserts both (and that no
  route/RPC-emitted code in the enumerated set silently hits the unintended default).
- [x] Unit tests pass under `./node_modules/.bin/vitest run
  test/server/workspace-invitations-accept.test.ts test/invite-reason-messages.test.ts` (10 tests).
- [x] No change to the identity-binding security floor: the route 403 path, the page email
  gate, and the RPC `not_intended_invitee` checks are unchanged (the diff does not touch them).
- [x] `tsc --noEmit` clean for the package.
- [x] **ROOT CAUSE found + fixed (migration 090):** the failure was NOT drift — it was a
  self-contradiction in 075 (create sets `attestation_id`; trigger makes it immutable; accept
  tried to overwrite it → P0001). Reproduced against prod; 090 verified to unblock the real
  invite (rolled back); dev integration test green.

### Post-merge (operator / automatable)

- [x] **Live-DB confirmation (read-only, prod):** prod `accept_workspace_invitation` source
  matches `085`, `revoked_at`/`revoked_by` exist, `has_function_privilege('service_role', …)`
  is true. → All confirmed; NO drift. Root cause was instead a logic self-contradiction (see
  pre-merge AC). Applied via node-pg + Doppler `DATABASE_URL_POOLER` (Supabase MCP OAuth-gated).
- [x] **No drift to repair.** Migration 090 (the logic fix) applied to dev with `_schema_migrations`
  tracking row; will reach prod via the standard deploy/migrate pipeline on merge.
- [x] A real accept against dev (opt-in integration test) returns `ok:true` and creates the
  `workspace_members` row. Also verified against prod's real failing invite in a rolled-back
  transaction. (Writes were DEV only / prod rolled-back — never persisted to prod.)

## Domain Review

**Domains relevant:** Engineering, Product, Legal/Compliance (invite = GDPR Art. 6(1)(b)/(f)
processing; the RPC writes attestation + membership PII).

### Engineering

**Status:** reviewed
**Assessment:** Fix is two small code-side hardenings (Sentry mirror + reason-copy mapping)
plus a live-DB-confirmed root-cause remediation that is most likely a prod migration apply,
not a code change. The DB write path source is correct; the durable risk is mock-only unit
coverage hiding schema/grant drift (the exact bb5eee90 lesson) — addressed by the opt-in
integration test. No new infrastructure; pure code + (conditional) forward migration on an
already-provisioned Supabase project.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

Modifies existing invite-accept error copy on an existing screen; no new pages/flows/
components. The copy change (distinguish "cancelled invite" and transient backend error from
a generic dead-end) is a strict UX improvement. CPO sign-off is still required at the
single-user-incident threshold (frontmatter `requires_cpo_signoff: true`).

### Legal/Compliance

**Status:** reviewed
**Assessment:** No new data category, no new processing purpose, no new retention. The fix
unblocks an existing, already-lawful processing activity (workspace invite acceptance,
LAWFUL_BASIS Art. 6(1)(b)/(f) per `075`). The Sentry mirror adds an RPC error *message* to
Sentry — ensure it does not include invitee PII (the message is the Postgres error text +
the literal "accept_workspace_invitation RPC failed", not invitee email/id; verify at /work).
Run `/soleur:gdpr-gate` against the diff at /work since the path touches auth/membership
write surfaces.

## Observability

```yaml
liveness_signal:
  what: Sentry events for "accept_workspace_invitation RPC failed" (op=accept)
  cadence: on-failure (event-driven)
  alert_target: Sentry web-platform project
  configured_in: apps/web-platform/server/workspace-invitations.ts (reportSilentFallback)
error_reporting:
  destination: Sentry via reportSilentFallback + pino log.error
  fail_loud: true (RPC failure now mirrored, not pino-only)
failure_modes:
  - mode: accept_workspace_invitation RPC errors (drift/grant/column)
    detection: Sentry event op=accept (after this fix); previously dark
    alert_route: Sentry
  - mode: route returns unmapped reason code
    detection: vitest reasonToMessage test asserts no unintended default
    alert_route: CI (pre-merge)
  - mode: prod schema/grant drift vs migration source
    detection: opt-in integration test (dev) + post-merge Supabase MCP privilege/source check
    alert_route: CI (dev) + post-merge operator/MCP gate
logs:
  where: pino (server) + Sentry (web-platform project)
  retention: per existing Sentry/log retention
discoverability_test:
  command: "./node_modules/.bin/vitest run test/server/workspace-invitations-accept.test.ts (run from apps/web-platform; NO ssh)"
  expected_output: "tests pass; assert reportSilentFallback called on RPC error and revoked/rpc_failed map to distinct copy"
```

## Sharp Edges

- The DB write path SOURCE is correct end-to-end — do NOT speculatively rewrite the RPC.
  The root cause is most likely live prod drift; confirm with the Supabase MCP (dev then
  prod, read-only) BEFORE touching any migration. Mirrors how bb5eee90 was "confirmed against
  the live prod DB."
- `/invite` is in `PUBLIC_PATHS` (`lib/routes.ts:40`), so `middleware.ts` returns early and
  the T&C gate never fires there. This is NOT the cause of this bug (the route only checks
  `getUser`), but do not "fix" it by routing accept through a gated path without re-checking
  the security floor (a public-path prefix short-circuits the gate; cf.
  `knowledge-base/project/learnings/2026-03-20-middleware-prefix-matching-bypass.md`).
- Test runner is **vitest**, not bun (`bunfig.toml` blocks bun test discovery). New tests
  MUST land under `test/**/*.test.ts` (node) — co-located or `bun test` paths are silently
  never run. Run with `./node_modules/.bin/vitest run <path>`.
- Never edit an applied migration in place; if Phase 0 proves a DDL/RPC repair is needed,
  add a forward `086_…` migration (idempotent), and add its `.down.sql`.
- Never run the integration test (which creates synthetic auth.users / membership rows)
  against prod — DEV only, per `hr-dev-prd-distinct-supabase-projects`.
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
