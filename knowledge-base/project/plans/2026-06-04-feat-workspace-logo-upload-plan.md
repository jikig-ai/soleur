---
plan: workspace-logo-upload
issue: 4916
branch: feat-workspace-logo-upload
pr: 4930
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-04
brainstorm: knowledge-base/project/brainstorms/2026-06-04-workspace-logo-upload-brainstorm.md
spec: knowledge-base/project/specs/feat-workspace-logo-upload/spec.md
---

# Plan: Workspace Logo Upload ✨

Implements the deferred upload slice from #4915 (monogram fallback shipped via PR #4911).
A workspace **owner** uploads a custom logo (PNG/WebP, square, ≤1 MB); it renders in the
chrome wherever `WorkspaceIdentityTile` mounts, falling back to the monogram on any failure.
Private Supabase bucket + server-minted signed URL; `sharp` decode-and-re-encode validation.

## Overview

- **Data:** add `logo_path text` (nullable) to `public.workspaces`; new private `workspace-logos` bucket.
- **Write:** server route only (owner-gated); `sharp` re-encode; path↔row `workspace_id` coherence assertion.
- **Read:** signed URL minted in `org-memberships-resolver.ts`, threaded to every `WorkspaceIdentityTile` mount.
- **Render:** `img` + `onError`→monogram, modeled on `leader-avatar.tsx`.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Column named `logo_url` | Private bucket → a stored URL would expire; we mint signed URLs on read | **Rename to `logo_path`** (stores the object key, e.g. `<workspace_id>/logo.png`). Reconciled; documented. |
| "Add Supabase origin to `img-src` (TR4)" | `csp.ts:97` ALREADY has `img-src 'self' blob: data: <supabase-origin>` | **Drop TR4 edit.** Replace with a verification AC that the signed-URL host equals the CSP-allowed Supabase origin. |
| "Wire logo into DSAR export (LR2)" | `dsar-export.ts` archiver is **user-keyed** (`<userId>/` prefix); logo is workspace-keyed shared property | **Exclude from automated per-user DSAR v1** — GDPR-gate ruling: defensible under Art. 15(4) rights-of-others (shared asset, no uploader-attribution in v1). Document rationale; manual Art. 15 path covers edge cases. |
| "Wire logo into workspace-deletion cascade (LR2)" | No workspace-row-deletion DB flow exists. `workspace.ts:236 deleteWorkspace()` removes only **local clone dirs**; `organization_id` is `ON DELETE RESTRICT` | **Add reusable `purgeWorkspaceLogoObjects(workspaceId)` helper**; GDPR-gate ruling: call from the **sole-owned-workspace teardown branch** of `account-delete.ts` (NOT on shared-workspace member removal — that would delete a shared asset). Verify sole-vs-shared teardown semantics at /work Phase 0. Follow-up to wire into any future explicit workspace-delete flow. Retention = workspace lifetime (Art. 5(1)(e)). |
| `is_workspace_owner` helper exists | **Does not exist** (grep empty); only inline `EXISTS(...role='owner')` at 068:311 | **Create `is_workspace_owner(p_workspace_id, p_user_id)`** in migration 098, mirroring `is_attachment_path_workspace_member` DEFINER/REVOKE/GRANT + `SET search_path = public, pg_temp`. |
| Single mount / "no context band" (spec Non-Goal) | `WorkspaceIdentityTile` renders in org-switcher rows AND `workspace-context-band.tsx:96`. Band sources name from client hook `useActiveWorkspaceName` (layout:133) which already fetches `/api/workspace/list-memberships` and reads `current.organizationName` | **Reconciled (spec-flow P0-3):** the band is NOT a separate surface — it's the same tile component. Surface `logoSignedUrl` through `useActiveWorkspaceName` (SAME fetch, one extra field) into the band tile. **Correct the spec Non-Goal** to "no favicon / no NEW surfaces beyond the `WorkspaceIdentityTile` component." Cheap full payoff (band + switcher). |
| Fold signed-URL mint into resolver (brainstorm Approach 1) | Resolver is storage-free; client-side signed URLs cause (a) re-download thrash — `useActiveWorkspaceName` re-polls on every window-focus, each mint = a new signature in `src` = cache-miss = re-download of always-visible chrome; (b) logo-drift between the band and switcher (two disjoint fetches); (c) N+1 mint; (d) resolver↔storage coupling | **Review-driven revision (architecture P1-A/P1-B/P2-A):** introduce a **stable proxy route** `GET /api/workspace/[id]/logo` that membership-gates then 302-redirects to a freshly-minted **short-TTL (300s) signed URL** with `Cache-Control: private, max-age=300`. The `<img src>` is the stable proxy path (no signature) → browser cache survives focus re-polls; the signed target rotates invisibly. Storage model UNCHANGED (still private bucket + signed URL — honors the user's choice; the signed URL is just minted lazily server-side per cache-miss, not client-exposed long-term). Resolver/hook return only `hasLogo: boolean` (no mint, no storage import). Eliminates N+1, thrash, drift, and coupling in one move. |
| Single deterministic object key | Two owners could upload png vs webp → two objects, `logo_path` points at one (code-simplicity) | **Re-encode ALL logos to a single canonical format (WebP), key `<workspace_id>/logo.webp`.** Accept PNG/WebP input, always output WebP. Eliminates extension-collision; single deterministic key. Bucket `allowed_mime_types=['image/webp']` (only the canonical output is ever written). |
| TR6 `file.stream()` (spec) | Phase 2 uses `sharp(buf)` (buffered) | **Reconciled:** 1 MB `file_size_limit` cap + `sharp` `limitInputPixels` make a single buffered decode acceptable; `sharp` requires a Buffer. Documented override (not a silent drop). |

## User-Brand Impact

(Carried forward from brainstorm Phase 0.1 — `USER_BRAND_CRITICAL=true`.)

- **If this lands broken, the user experiences:** a broken-image glyph in their always-visible
  workspace chrome, or (worse) another workspace's logo shown on theirs.
- **If this leaks, the user's data/workflow is exposed via:** (1) stored XSS — **eliminated**
  by dropping SVG + raster re-encode; (2) cross-tenant logo read/overwrite — **mitigated** by
  private bucket + 068-style owner-only write-split + path↔row `workspace_id` assertion;
  (3) storage/billing abuse — **mitigated** by 1 MB `file_size_limit` + single object per workspace.
- **Brand-survival threshold:** `single-user incident`. → `requires_cpo_signoff: true` (carry-forward
  from brainstorm CPO assessment); `user-impact-reviewer` runs at PR review.

## Implementation Phases

### Phase 0 — Preconditions (verify at /work start)
- `grep` the mount site of `rename-workspace-action.tsx` to locate the Workspace settings pane the logo control co-locates into (do NOT freeze a path — verify).
- Confirm `createSignedUrls` (plural) is available on the installed `@supabase/supabase-js`; else loop `createSignedUrl`.
- Read migrations 095–097 for any DDL-runner constraints before authoring 098.

### Phase 1 — Migration 098 (data + storage + RLS)
- `ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS logo_path text;` (nullable, no backfill).
- `INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('workspace-logos','workspace-logos', false, 1048576, ARRAY['image/webp']) ON CONFLICT (id) DO NOTHING;` (canonical output is WebP).
- `CREATE FUNCTION public.is_workspace_owner(p_workspace_id uuid, p_user_id uuid) RETURNS boolean ... SECURITY DEFINER SET search_path = public, pg_temp;` — body: `IF p_workspace_id IS NULL OR p_user_id IS NULL THEN RETURN false; END IF; RETURN EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id=p_workspace_id AND user_id=p_user_id AND role='owner');` (parameterized, NO dynamic SQL). `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ... TO authenticated;` — REVOKE list must include **all four** (mirror 053:139 exactly; data-integrity P1 caught `service_role` omission in the v1 paraphrase).
- `storage.objects` RLS for `bucket_id='workspace-logos'`, path `<workspace_id>/logo.webp`. **Every policy AND-guards the UUID shape BEFORE the cast** (068:124 lesson — an unguarded `::uuid` on a malformed `name` raises 22P02 and aborts the statement, surfacing as a 500 on the read path): `(storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$' AND <helper>((storage.foldername(name))[1]::uuid, auth.uid())`.
  - `FOR SELECT` (USING): `is_workspace_member(...)`.
  - `FOR INSERT` (**WITH CHECK only**): `is_workspace_owner(...)`.
  - `FOR UPDATE` (**USING AND WITH CHECK** — data-integrity P0: USING gates the OLD row, WITH CHECK gates the NEW row; USING-only lets an owner of A move/rename an object INTO B's prefix): `is_workspace_owner(...)` on both clauses.
  - `FOR DELETE` (USING only): `is_workspace_owner(...)`.
  - **Never** `FOR ALL USING` (068 F3). No `COMMENT ON POLICY` on `storage.objects` (068:158 prd-fails).
- `098_..._workspace_logos.down.sql` — drop in **reverse order**: policies → function → `DELETE FROM storage.objects WHERE bucket_id='workspace-logos'` (dropping the bucket row does NOT cascade objects — data-integrity P2) → bucket row → column. Migration test mirroring `068-attachments-workspace-shared.test.ts` + a **cross-tenant overwrite-denial** case + a **cross-tenant move (UPDATE into other prefix) denial** case + a **malformed-path clean-deny** case.

### Phase 2 — Upload/remove API route (`app/api/workspace/logo/route.ts`)
- `POST`: `validateOrigin`/`rejectCsrf` → **rate-limit** (per-user/workspace; mirror the KB-upload route's limiter — security P1-1, guards pixel-bomb amplification) → content-length precheck (1 MB + slack → 413) → `auth.getUser()` (401) → resolve **active** `workspace_id` **server-side** from the `current_organization_id` claim via `server/workspace-resolver.ts` (NOT client-supplied) → `rpc("is_workspace_owner", …)` gate (403) → `formData` parse → **`sharp(buf, { limitInputPixels: 16_000_000, failOn: 'error' })`** (security P0-1: 1 MB input ≠ bounded decoded pixels — a crafted PNG decodes to GB and OOMs without this) → read `meta = await img.metadata()`; **assert `meta.format ∈ {png, webp}` from the DECODED metadata, not the client Content-Type** (security P0-2 — closes polyglot/MIME-spoof); reject non-square (422); **flatten APNG to single frame** (code-simplicity: `image/png` MIME passes but APNG renders animated — `.png({...})`/no-`animated` re-encode drops extra frames) → **re-encode to canonical WebP** (`.webp()`) → assert storage path `workspace_id` == resolved → `serviceClient.storage.from("workspace-logos").upload("<wid>/logo.webp", out, {contentType:'image/webp', upsert:true})` → `UPDATE workspaces SET logo_path='<wid>/logo.webp' WHERE id=<wid>`. On DB-persist failure after storage write: delete the orphan object + `reportSilentFallback` + 500.
- **Ordering invariant (spec-flow P0-2):** upload object FIRST (deterministic key `<wid>/logo.<ext>`, `upsert:true`) → THEN `UPDATE logo_path`. On DB-write failure: attempt object cleanup. **The cleanup-delete can ITSELF fail** — that arm gets a distinct `reportSilentFallback` breadcrumb (`logo-orphan-cleanup-failed`, the TRUE orphan) + 500. A stale row never points at a missing object because `logo_path` only ever stores the deterministic key and a missing object renders → `onError` → monogram (P0-1 covers it).
- `DELETE`: owner-gate → `UPDATE workspaces SET logo_path=NULL` **FIRST**, then remove object (so a stale row never outlives the object). **The object-removal arm can itself fail** → distinct `logo-orphan-cleanup-failed` `reportSilentFallback` breadcrumb (data-integrity: DELETE-path orphan, symmetric to the upload path). Concurrent two-owner upload = last-writer-wins on the single canonical key `logo.webp` (no extension-collision now; documented-acceptable).
- `Sentry.captureMessage` on every reject/failure arm; HTTP-only exports (`cq-nextjs-route-files-http-only-exports`).
- _Orphan-sweep follow-up CUT (code-simplicity):_ a single deterministic key + `upsert:true` + missing-object→monogram means there is no accumulating orphan population to reconcile. No follow-up issue.

### Phase 3 — Read path (stable proxy route)
- **New route `GET /api/workspace/[id]/logo`:** `auth.getUser()` → `rpc("is_workspace_member", {p_workspace_id:id, p_user_id})` gate (403) → read `logo_path` for `id` (404 if null) → `serviceClient.storage.from("workspace-logos").createSignedUrl(logo_path, 300)` → **302 redirect** to it with `Cache-Control: private, max-age=300` and `X-Content-Type-Options: nosniff` (security P0-3/P2-2 — short TTL, stable cacheable src, signed URL never persisted client-side). `reportSilentFallback` on mint failure → 502 (tile falls back to monogram via onError).
- **Resolver stays storage-thin (architecture P2-A):** `org-memberships-resolver.ts` adds `logo_path` to the `workspaces.select(...)` (:97) and exposes `hasLogo: boolean` on `OrgMembershipSummary` (:8) — **no mint, no storage import** in the resolver. The tile builds the stable `src` from `workspaceId` when `hasLogo`.

### Phase 4 — Render (`WorkspaceIdentityTile` + mounts)
- Add `workspaceId?: string` + `hasLogo?: boolean` props. When `hasLogo`, render `<img src={`/api/workspace/${workspaceId}/logo`}>` (the **stable proxy path** — same string across mounts and focus re-polls → browser-cacheable, closes thrash + drift P1-A/P1-B) + `onError`→monogram (model `leader-avatar.tsx` `setImgError`, reset on id change). `onError` → `Sentry.captureMessage` (a set-but-broken logo is a defect; the no-logo monogram path stays silent).
- Thread `workspaceId`+`hasLogo` through `org-switcher-container.tsx` → `org-switcher.tsx` (:86,:114,:153).
- **Band (spec-flow P0-3):** extend `hooks/use-active-workspace-name.ts` to also return `current.hasLogo` + `current.workspaceId` (same `/api/workspace/list-memberships` fetch — extra fields, no new data path); thread into `workspace-context-band.tsx:96`'s tile. Rename hook to `useActiveWorkspace` returning `{name, workspaceId, hasLogo}`.

### Phase 5 — Settings UI (`workspace-logo-settings.tsx`)
- Client component modeled on `conversation-names-settings.tsx` (file input, `ACCEPTED=['image/png','image/webp']`, `MAX=1 MB`, `checkDimensions` square, FormData POST to `/api/workspace/logo`, optimistic preview, Remove→DELETE→monogram). Co-locate beside `rename-workspace-action.tsx`. Inline error states (wireframes 25–27). **Reject copy must name "SVG and JPG aren't accepted"** (issue says PNG/SVG — overridden).
- **Non-owner gating (spec-flow P1-1):** the settings page server component loads the viewer's `workspace_members.role`; the logo control renders **disabled-with-tooltip** ("Only workspace owners can change the logo") for non-owners — never a visible control that 403s on click (dead-end).
- **State (spec-flow P2-1):** the component status is a **4-value union** (`idle｜uploading｜success｜error`), not a boolean (`cq-union-widening` rails apply). The tile itself stays a 3-branch render (logo / onError→monogram / null).

### Phase 6 — Legal lockstep (mandatory; CLO attests at PR)
- Privacy Policy + Data-Protection-Disclosure + GDPR Policy/Article-30 register: new processing activity (workspace logo image, retention = workspace lifetime, eu-west-1, no new sub-processor). One-line AUP scope extension naming the logo surface. **DSAR export + workspace-deletion wiring per GDPR-gate ruling** (see Research Reconciliation — expected: exclude-from-DSAR + purge-helper, not user-keyed account-delete).

## Files to Create
- `apps/web-platform/supabase/migrations/098_workspace_logos.sql` + `.down.sql`
- `apps/web-platform/test/supabase-migrations/098-workspace-logos.test.ts`
- `apps/web-platform/app/api/workspace/logo/route.ts` (POST upload + DELETE remove)
- `apps/web-platform/app/api/workspace/[id]/logo/route.ts` (GET stable proxy → 302 signed URL)
- `apps/web-platform/components/settings/workspace-logo-settings.tsx`
- (maybe) `apps/web-platform/app/(dashboard)/dashboard/settings/workspace/page.tsx` — only if no existing pane; verify Phase 0.

## Files to Edit
- `apps/web-platform/server/org-memberships-resolver.ts` (add `logo_path` to select + expose `hasLogo` — NO mint, NO storage import)
- `apps/web-platform/components/dashboard/workspace-identity-tile.tsx` (img branch using the proxy `src` — resolves TODO(#4916))
- `apps/web-platform/components/dashboard/org-switcher.tsx` + `org-switcher-container.tsx` (thread `workspaceId`+`hasLogo`)
- `apps/web-platform/components/dashboard/workspace-context-band.tsx` (thread logo into the band tile)
- `apps/web-platform/hooks/use-active-workspace-name.ts` (surface `hasLogo`+`workspaceId` from the same fetch — P0-3)
- `apps/web-platform/server/account-delete.ts` (call `purgeWorkspaceLogoObjects` in the **sole-owned-workspace** teardown branch only)
- the Workspace settings page server component (load viewer `role` for non-owner gating — locate at Phase 0)
- `apps/web-platform/server/workspace.ts` (add `purgeWorkspaceLogoObjects(workspaceId)` helper)
- `docs/legal/{privacy-policy,data-protection-disclosure,gdpr-policy,acceptable-use-policy}.md` + `knowledge-base/legal/article-30-register.md`
- `apps/web-platform/test/csp.test.ts` (assert signed-URL host ∈ img-src) — if a focused AC is added

## Acceptance Criteria

### Pre-merge (PR)
- [x] AC1 — Migration 098 applies + `.down.sql` reverts cleanly (DEV, live-verified); `logo_path` nullable; bucket `public=false`, `allowed_mime_types=['image/webp']` (canonical re-encode is always WebP — the AC's earlier `['image/png','image/webp']` was a pre-canonical-WebP-decision remnant; the route always uploads `image/webp`), `file_size_limit=1048576`. **`.down.sql` reverts policies+function+column only — Supabase `protect_delete` trigger blocks direct `DELETE FROM storage.{objects,buckets}` (the plan's object-then-bucket delete is infeasible; 019/042 precedent ship no SQL bucket teardown). See migration-checklist.md.**
- [x] AC2 — `pg_policy` shows 1 SELECT (member) + 3 narrow INSERT/UPDATE/DELETE (owner) on `workspace-logos`; **no `FOR ALL`**; the **UPDATE policy has BOTH `qual` (USING) AND `with_check` non-null** (data-integrity P0 cross-tenant-move guard); every policy AND-guards the `^[0-9a-f-]{36}$` path shape before the `::uuid` cast; `is_workspace_owner` is `SECURITY DEFINER` with `search_path=public, pg_temp`, REVOKE covers `PUBLIC, anon, authenticated, service_role`, GRANT only `authenticated`, body has the NULL-args guard.
- [x] AC3 — Live DEV behavioral verification (`SET LOCAL ROLE authenticated`, savepoint-isolated, ROLLBACK-wrapped) proves: owner writes own path; co-member reads; **non-member cannot read; non-owner member cannot overwrite; owner-of-A cannot UPDATE/move an object into B's prefix; malformed path denies cleanly (no 22P02 abort).** 32/32 PASS (migration-checklist.md). Offline-shape test (24) is the committed CI gate.
- [x] AC4 — Upload route rejects SVG, JPG, >1 MB, non-square, **a 1 MB pixel-bomb (decoded-pixel flood, not OOM — `limitInputPixels`)**, and **APNG renders single-frame**; format asserted from **decoded `sharp` metadata**, not client Content-Type; output is canonical WebP at `<wid>/logo.webp` with EXIF stripped.
- [x] AC5 — Upload asserts storage-path `workspace_id` == server-resolved active workspace before write (unit test on the assertion); active workspace resolved from the `current_organization_id` claim, never client-supplied.
- [ ] AC5b — **Column-takeover is DB-enforced (data-integrity P2 / security P1-2):** assert `public.workspaces` has NO client-facing INSERT/UPDATE/DELETE policy (only `workspaces_select_for_members`), so no authenticated client SDK path can set `logo_path` to another workspace's key (the read proxy trusts `logo_path`). `pg_policy` count assertion + the route writes via service-role only.
- [x] AC6 — Proxy route `GET /api/workspace/[id]/logo`: 403 for non-member, 404 when `logo_path` null, 302→signed URL (TTL=300s) with `Cache-Control: private, max-age=300` + `X-Content-Type-Options: nosniff` for a member; resolver exposes `hasLogo` (boolean) with NO mint and NO storage import (no N+1).
- [x] AC6b — Rate-limit on `POST /api/workspace/logo` (security P1-1) — test that rapid repeats are throttled.
- [x] AC7 — **(spec-flow P0-1) Integration test, not just RTL:** upload a real PNG → reload chrome → assert the rendered `img` (src=`/api/workspace/<id>/logo`) resolves (`naturalWidth > 0`); a SECOND case (non-member / deleted logo) gets 403/404 from the proxy → asserts the **monogram is visible**. RTL additionally covers the 3-branch state machine (hasLogo→img / onError / no-logo). RTL alone is NOT sufficient (jsdom never fires real `onError`).
- [x] AC7c — **(architecture P1-A/B) Stable src:** the tile's `img src` is byte-identical across two consecutive membership fetches and across a window-focus re-poll (no signature in the URL) — both mounts (switcher + band) render the same `/api/workspace/<id>/logo` string (no drift).
- [x] AC7b — **(spec-flow P0-2)** the cleanup-delete-failure arm emits a distinct `logo-orphan-cleanup-failed` Sentry breadcrumb (unit test on the failure path); `DELETE` sets `logo_path=NULL` before object removal (assertion test).
- [ ] AC8 — **(unconditional, spec-flow P2-3)** Signed-URL host equals a CSP `img-src`-allowed origin (`csp.test.ts`); **no CSP edit shipped** (TR4 confirmed no-op — `csp.ts:97` already allows the Supabase origin).
- [ ] AC8b — **(spec-flow P1-1)** non-owner member sees the logo control disabled-with-tooltip (RTL test with member-role fixture); the server route still 403s a non-owner (defense in depth).
- [ ] AC9 — Legal lockstep: Privacy Policy + DPD + Art-30 + AUP updated; migration 098 carries `-- LAWFUL_BASIS:` annotation (GDPR-Art-6); Art-30 row states retention=workspace lifetime and uses the next free PA number (verify via `grep "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail`).
- [ ] AC10 — `tsc --noEmit` clean (union-widening rails — settings 4-state union); test runner = package's actual runner (vitest; verify path matches `vitest.config.ts` include globs — `test/**`, not co-located).

### Post-merge (operator)
- _Note (not an AC — code-simplicity demotion):_ Migration 098 applies to prd automatically via `web-platform-release.yml#migrate` on merge touching `apps/web-platform/**`. No operator action; the merge IS the apply.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward + plan-time seam verification + **substance triad ran**: data-integrity-guardian, security-sentinel, architecture-strategist, code-simplicity — the single-user-incident deepen-equivalent pass). **Assessment:** Drop SVG; clone 068 F3 write-split; create `is_workspace_owner`; assert path↔row `workspace_id`; Sentry on all arms. **Triad findings folded:** UPDATE policy needs USING+WITH CHECK (cross-tenant move); regex-guard before `::uuid` cast; `sharp` `limitInputPixels` + format-from-metadata + APNG flatten; column-takeover is DB-enforced (no client write policy — strengthens posture); read-path switched to stable proxy route (kills thrash/drift/N+1); canonical WebP single key; orphan-sweep follow-up cut. CSP edit confirmed no-op.

### Product (CPO)
**Status:** reviewed (carry-forward). **Assessment:** Single mount (tile), logo→monogram precedence, control beside Rename. Out of scope: animated/dark-light/favicon/crop/context-band-as-separate-surface. **`requires_cpo_signoff: true`** — CPO reviewed the brainstorm; sign-off carried forward.

### Legal (CLO)
**Status:** reviewed (carry-forward) — **re-reconciliation required** (see below). **Assessment:** founder-grade inline, no external counsel. Lockstep 3-doc + AUP mandatory. **Open reconciliation:** brainstorm LR2 mandated DSAR-export + workspace-deletion wiring, but codebase has no workspace-deletion DB flow and DSAR/account-delete are user-keyed. GDPR-gate (Phase 2.7) ruling drives the final v1 posture; CLO attests at PR.

### Product/UX Gate
**Tier:** blocking (UI-surface override: new `components/**/*.tsx` + settings page). **Decision:** reviewed — wireframes already produced in brainstorm Phase 3.55. **Agents invoked:** ux-design-lead (brainstorm), spec-flow-analyzer (this plan). **Skipped specialists:** none. **Pencil available:** yes (`.pen` committed: `knowledge-base/product/design/navigation/workspace-logo-upload.pen` + screenshots 25–28).

## Observability

```yaml
liveness_signal:
  what: workspace-logo upload success/failure events (Sentry breadcrumb + count)
  cadence: per-upload (user-triggered, not scheduled)
  alert_target: Sentry issue alert on reportSilentFallback rate for the logo route
  configured_in: infra/sentry/*.tf (issue alert) + route Sentry.captureMessage
error_reporting:
  destination: Sentry (captureMessage on every reject/failure arm)
  fail_loud: true (UI error toast + Sentry; no silent no-op)
failure_modes:
  - mode: upload rejected (bad MIME/size/dimensions)
    detection: 4xx + Sentry.captureMessage
    alert_route: Sentry (rate alert)
  - mode: DB persist fails after storage write (orphan object)
    detection: reportSilentFallback + object cleanup + 500
    alert_route: Sentry (reportSilentFallback rate alert)
  - mode: signed-URL mint fails in resolver
    detection: reportSilentFallback → null → monogram
    alert_route: Sentry
  - mode: render onError (set-but-broken logo)
    detection: Sentry.captureMessage in tile onError (distinct from no-logo silent path)
    alert_route: Sentry
logs:
  where: pino structured logs (route) + Sentry
  retention: per existing Sentry/log retention (no new store)
discoverability_test:
  command: "curl -s -X POST $APP/api/workspace/logo (bad file) → observe 4xx + Sentry event; NO ssh"
  expected_output: "4xx JSON error body + Sentry issue created"
```

## Infrastructure (IaC)
**No Terraform change.** The `workspace-logos` bucket + RLS are provisioned by the Supabase
**migration runner** (`web-platform-release.yml#migrate`) — the repo's IaC path for DB/storage,
same as buckets 019/042/045/068/071. No new server, vendor, secret, DNS, or operator
dashboard/SSH step. The only post-merge action (AC11) is the automatic migration apply.
The Sentry issue-alert rule (Observability) lands in `infra/sentry/*.tf` via the existing
`apply-sentry-infra.yml` `-target=` path.

## Open Code-Review Overlap
**None.** 71 open `code-review` issues queried (2026-06-04); zero reference any planned file path
(`org-memberships-resolver.ts`, `workspace-identity-tile.tsx`, `org-switcher.tsx`,
`workspace-context-band.tsx`, `account-delete.ts`, `workspace.ts`). Check ran; no overlap.

## Risks & Mitigations
- **Cross-tenant overwrite** (highest): owner-only write-split + path↔row assertion + migration test denial case.
- **N+1 signed-URL mint:** null-skip + batch `createSignedUrls`; common case (no logo) = zero mints.
- **Orphaned storage object** on DB-persist failure: delete-then-fail in the route; `reportSilentFallback`.
- **SVG/polyglot XSS:** raster-only + format-asserted-from-decoded-metadata + `sharp` re-encode to WebP; proxy response carries `image/webp` + `nosniff`. No inline `<img>` of SVG.
- **Decompression bomb (security P0-1):** `sharp(buf, { limitInputPixels: 16_000_000, failOn:'error' })` — input byte cap ≠ decoded-pixel cap.
- **`logo_path` column-takeover — DB-ENFORCED, not convention (data-integrity P2 / security P1-2):** `public.workspaces` has ONLY `workspaces_select_for_members` and NO client INSERT/UPDATE/DELETE policy, so RLS denies every authenticated client-SDK write at the DB layer; the route writes via service-role (like `workspace/rename`). The read proxy can safely trust `logo_path`. Verified by AC5b. **(This strengthens the CPO single-user-incident sign-off basis.)**
- **Read-path thrash/drift (architecture P1):** closed by the stable proxy `src` + 300s `Cache-Control` (no signature in URL).

## Non-Goals (v1)
SVG/JPG, animated/dark-light/per-theme logos, favicon, crop tool, public-URL serving,
context-band as a *separate* logo surface beyond the shared tile, per-user DSAR export of the logo.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails deepen-plan Phase 4.6 — filled above.
- Issue body says "PNG/SVG"; this plan ships **PNG/WebP only**. Reviewers must not "restore" SVG.
