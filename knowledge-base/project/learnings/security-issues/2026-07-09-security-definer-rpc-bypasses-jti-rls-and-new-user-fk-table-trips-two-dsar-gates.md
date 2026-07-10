---
title: "A SECURITY DEFINER read RPC bypasses the RESTRICTIVE jti-deny RLS policy; a new user-FK table trips TWO DSAR gates"
date: 2026-07-09
category: security-issues
module: apps/web-platform/supabase + server/dsar-export
pr: 6239
issue: 6172
tags: [security-definer, jti-deny, rls-bypass, dsar, migration, precedent-mirror]
---

# SECURITY DEFINER RPC jti-bypass + new-user-FK-table DSAR two-gate

Two recurring, independently-generalizable patterns surfaced while shipping the
read-only beta-CRM UI (PR #6239, migration 127: `beta_contact_access_log` +
the atomic `crm_get_contact_detail` read+audit RPC).

## Pattern 1 (security) — a SECURITY DEFINER RPC does NOT inherit the RESTRICTIVE jti-deny RLS policy

### Problem
Migration 126/127 tables carry the `068/076/077`-shape RESTRICTIVE policy
`<table>_jti_not_denied AS RESTRICTIVE FOR ALL TO authenticated USING (NOT
public.is_jti_denied_from_jwt())`, whose stated purpose is "a revoked/stolen
founder JWT used directly against PostgREST is rejected at the policy boundary."

That guarantee holds **only for direct table access**. A `SECURITY DEFINER`
function (`crm_get_contact_detail`, granted to `authenticated`) is reachable at
`POST /rest/v1/rpc/<fn>` with a raw bearer token, and SECURITY DEFINER
**bypasses RLS** — so the RESTRICTIVE jti policy on the underlying tables never
runs on the RPC path. The RPC gated only on `auth.uid() IS NULL`. A
denylisted-but-unexpired JWT (mig-068 revocation window, ~1h) could therefore
still read verbatim third-party note bodies via the RPC.

The migration's own header **claimed** jti protection — a documented-but-false
security assertion. The gap was faithfully **mirrored from mig-126** (whose
write RPCs `crm_contact_upsert`/`crm_note_append`/`crm_contact_set_stage` share
the identical `auth.uid()`-only gate — a pre-existing WRITE-path analogue, now
tracked in #6249).

### Solution
Re-assert the denylist **in the function body**, right after the `auth.uid()`
null-check, so it runs on the SECURITY DEFINER path too:

```sql
IF public.is_jti_denied_from_jwt() THEN
  RAISE EXCEPTION '<fn>: token denied' USING ERRCODE = '42501';
END IF;
```

`42501` keeps any uniform-404 route mapping intact. `is_jti_denied_from_jwt()`
reads `request.jwt.claims` (a GUC), which is available inside a definer
function. Place the guard **before** any PII-loading SELECT (fail fast).

### Key insight
**A RESTRICTIVE RLS policy protects rows, not RPCs.** Any SECURITY DEFINER
function granted to `authenticated` is an independent PostgREST entry point that
bypasses RLS — every RLS-boundary security property (jti-deny, tenant scoping,
row filters) must be **re-asserted in the function body**, not assumed inherited
from a policy. When mirroring a precedent RPC for a new role, enumerate the
precedent's RLS-boundary guarantees and confirm each is re-encoded in the body
(the precedent-mirror-breaks-invariant class).

## Pattern 2 (workflow/test) — a new user-FK table trips TWO DSAR registration gates

### Problem
Adding `beta_contact_access_log` (FK chain to `public.users`) turned the
full-suite exit gate red on `dsar-allowlist-completeness.test.ts` (every user-FK
table must be in `DSAR_TABLE_ALLOWLIST` or `DSAR_TABLE_EXCLUSIONS`). Registering
it in the allowlist then surfaced a **second** gate:
`dsar-worker-per-row-where.test.ts` asserts the export WORKER (`dsar-export.ts`)
has a `service.from("<table>")` owner-scoped read block for every allowlisted
table. So one new user-FK table requires **two** coordinated edits.

### Solution
For any new table with a (possibly transitive) FK to `public.users`, in the
SAME PR:
1. Add it to `DSAR_TABLE_ALLOWLIST` (`ownerField` + `article`) — or
   `DSAR_TABLE_EXCLUSIONS` with a >20-char reason.
2. Add a `service.from("<table>").select("*").eq("<ownerField>", expectedUserId)`
   + `assertReadScope(...)` block to `server/dsar-export.ts`, mirroring a sibling.
3. Confirm Art. 17 erasure reaches it (a composite-FK `ON DELETE CASCADE` from
   the parent means the existing erase RPC sweeps it — no independent step).

### Key insight
The **touched-file test loop is not the DSAR gate** — both DSAR completeness
tests live in `test/**/*.test.ts` and only fire in the full-suite exit gate
(`vitest run` / `test-all.sh`), never when you run just the migration's own
touched tests. Run the full suite before trusting a migration that adds a
user-FK table. "Allowlist registered" is only half; the worker query block is
the other gate.

## Session Errors

- **New user-FK table failed the full suite (1 test), not the touched-file loop** — Recovery: register in allowlist + worker. Prevention: run `test-all.sh`/full `vitest run` as the exit gate on any migration adding a user-FK table (Pattern 2).
- **SECURITY DEFINER RPC shipped with a documented-but-false jti claim** — Recovery: in-body `is_jti_denied_from_jwt()` guard + shape-test assertion. Prevention: Pattern 1 (re-assert RLS-boundary props in every definer body).
- **`computeFunnel` nearly exported from `route.ts`** (violates `cq-nextjs-route-files-http-only-exports`) — Recovery: extracted to sibling `compute.ts`. Prevention: rule already exists; applied correctly.
- **Plan overclaimed an import-only Sentry `.tf` as apply-on-merge** — Recovery: corrected plan Observability/Infrastructure to DEFERRED + tracker #6250. Prevention: verify `infra/sentry/issue-alerts.tf` is import-only before a plan asserts a new alert as in-PR IaC.
- **Bash CWD persisted at `apps/web-platform`** causing a doubled Edit path — Recovery: absolute path. Prevention: use absolute paths for Edit/Write in worktrees.
- **Playwright structural gate blocked on Ubuntu 26.04** (pinned headless-shell 1208 unsupported) — Recovery: deferred to CI's containerized `playwright:v1.58.2-jammy` e2e (authoritative). Prevention: machine-specific; not a repo defect — CI is the authoritative structural gate.

## Related
- ADR-102 (beta-CRM) UI-phase amendment.
- Follow-ups: #6249 (mig-126 write-RPC jti + agent-read audit), #6250 (v2 UI features).
- Precedent-mirror class: `knowledge-base/project/learnings/best-practices/2026-06-30-precedent-mirror-for-new-role-breaks-fencing-token-monotonicity.md`.
