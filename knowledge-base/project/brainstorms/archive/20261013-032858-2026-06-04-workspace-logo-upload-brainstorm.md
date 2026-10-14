---
date: 2026-06-04
topic: workspace-logo-upload
issue: 4916
branch: feat-workspace-logo-upload
pr: 4930
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Workspace Logo Upload — Brainstorm

## What We're Building

A user-uploaded **custom workspace logo** that replaces the name-initial monogram
in the dashboard chrome. Scope is the deferred upload slice from #4915 (chrome
redesign, PR #4911 merged) — the monogram fallback is already live, so this is a
pure upgrade, not a fix.

**Chosen scope (operator-selected): "Upload, raster-only, minimal."**

- Upload pipeline: Supabase **private** storage bucket + server upload route + `sharp` validation.
- **Raster only: PNG / WebP. No SVG, no JPG.** Square, max ~1MB.
- `logo_url` column on the `workspaces` record (workspace-grain, ADR-044).
- **Single render mount:** the workspace identity tile only (not context band, not favicon).
- Serving: **private bucket + short-lived signed URL**, minted server-side and folded
  into the existing `org-memberships-resolver.ts` (one round-trip with the rest of chrome).

## Why This Approach

**Approach 1 (selected): server-minted signed URL + `sharp` decode-and-re-encode.**
The org-memberships resolver already feeds the chrome (it's the source of
`organizationName`). Adding `logoSignedUrl` to `OrgMembershipSummary` means the
logo arrives in the same round-trip — no extra client fetch, refreshes naturally
on membership refetch. The upload route **decodes and re-encodes** to a clean
PNG/WebP, which strips EXIF/GPS metadata (a GDPR nicety) and neutralizes any
polyglot/payload bytes — strictly stronger than metadata-only sniffing. Rare
alignment: fewer moving parts *and* the better security posture.

Rejected: Approach 2 (dedicated on-demand `/api/workspace/logo-url` route + client
fetch + metadata-only validation) — extra render round-trip and weaker validation
(no re-encode → EXIF/polyglot bytes survive).

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Scope | Full upload, raster-only, minimal | Monogram fallback already live; threshold is single-user-incident, so trim surfaces aggressively |
| Formats | **PNG / WebP only — drop SVG and JPG** | SVG is an active document (script/onload/foreignObject); sanitization is a perpetual-CVE arms race. **Contradicts the issue's "PNG/SVG" wording — deliberately overridden by CTO security review.** |
| Bucket access | **Private bucket + signed URL** | Zero path-enumeration risk (CTO defense-in-depth); operator chose this over public+getPublicUrl |
| Signed-URL delivery | Server-minted, folded into `org-memberships-resolver.ts` | One round-trip; signed-URL lifecycle hidden from client; TTL tuned to membership-refetch cadence |
| Validation | `sharp` decode-and-re-encode (already a dependency) | Strips EXIF + neutralizes polyglots; enforces square + size cap; no magic-byte-sniff lib needed |
| RLS template | Clone migration **068** (workspace-grain) with **F3 write-split** | `is_workspace_member` helper already exists (mig 053); owner-only INSERT/UPDATE/DELETE, widened SELECT; **never `FOR ALL USING`** |
| Write path | Server route only (never client SDK) | `logo_url` on `workspaces` would inherit the permissive UPDATE policy → column-takeover risk |
| Render mount | Identity tile only (`workspace-identity-tile.tsx` TODO(#4916)) | Single mount per ADR-047; context band / favicon = scope creep |
| Render fallback | `img` + `onError`→monogram, modeled on `leader-avatar.tsx` | Broken/expired signed URL falls back to monogram, never a broken-image glyph |
| Path coherence | Assert storage-path `workspace_id` == resolved active workspace before write | Mismatch is the cross-tenant overwrite bug (`hr-write-boundary-sentinel-sweep-all-write-sites`) |
| Silent-failure | Sentry on upload reject, persist-after-storage failure, and render onError | `cq-silent-fallback-must-mirror-to-sentry`; the no-logo monogram path stays silent (legitimate) |
| Visual design | `.pen` + screenshots 25–28 (see below) | Wireframes authored by ux-design-lead |

**Visual design:** `knowledge-base/product/design/navigation/workspace-logo-upload.pen`
plus screenshots `25-workspace-logo-settings-control.png`,
`26-workspace-logo-validation-error.png`, `27-workspace-logo-uploading-success.png`,
`28-identity-tile-render-states.png` (all under `.../navigation/screenshots/`).

## User-Brand Impact

- **Artifact:** user-uploaded workspace logo image (raster), stored in a private
  Supabase bucket, rendered in dashboard chrome.
- **Vectors (operator confirmed "all of them"):** (1) stored XSS via malicious
  SVG `<script>` → **eliminated by dropping SVG + raster re-encode**; (2) cross-tenant
  read/overwrite via storage RLS/path misconfig → **mitigated by private bucket +
  068 F3 owner-only write-split + path==row assertion**; (3) silent upload failure →
  **mitigated by explicit UI error states + Sentry on every failure arm**; (4)
  storage/billing abuse via unbounded size/count → **mitigated by ~1MB cap +
  single logo per workspace + bucket `file_size_limit`**.
- **Threshold:** `single-user incident` (inherited by the plan).

## Open Questions

1. **Signed-URL TTL vs. chrome cache:** what TTL balances "logo doesn't vanish
   mid-session" against "leaked URL expires fast"? Tune to the membership-refetch
   cadence; decide at plan time.
2. **Square enforcement UX:** reject non-square outright, or offer a center-crop?
   v1 leans reject-with-clear-error (no crop tool — out of scope).
3. **Orphaned-object cleanup:** if the DB `logo_url` UPDATE fails after a successful
   storage write, do we delete-then-fail or leave a reaper? Plan-time call.
4. **CSP `img-src`:** signed Supabase Storage origin must be added to `img-src` in
   `lib/security-headers.ts` or the `<img>` is CSP-blocked (learnings #6).

## Domain Assessments

**Assessed:** Engineering, Product, Legal

### Engineering (CTO)
**Summary:** Drop SVG, accept raster only (decisive on the XSS vector). Clone migration
068 for workspace-grain RLS with the F3 write-split (owner-only writes); never
`FOR ALL USING`. Upload route must resolve the active `workspace_id` server-side and
assert the storage path matches the row updated. Sentry on all three silent-failure
arms. Complexity ~medium (2–3 days); no capability gaps. Suggests an ADR for the new
bucket + RLS shape.

### Product (CPO)
**Summary:** Monogram is already a decent fallback and this is p3-low, so the smallest
viable slice was paste-a-URL `logo_url`; operator chose the fuller raster-upload path
instead. Single mount (identity tile), logo→monogram precedence, logo control beside
Rename in the existing Workspace settings pane — not a new section. Out of scope:
animated logos, dark/light variants, favicon, crop tool, context-band logo.

### Legal (CLO)
**Summary:** Founder-grade handleable inline — **no external-counsel routing needed.**
But this is a new processing activity requiring a **lockstep 3-doc update** (Privacy
Policy + Data-Protection-Disclosure + GDPR/Article-30 register) and wiring the
`workspace-logos` bucket into the **DSAR export archiver** and the **workspace-deletion
cascade** — NOT the per-user `account-delete` purge (logo is workspace-grain, shared
property; deleting one member must not delete the workspace logo). One-line AUP scope
extension recommended. CLO agent is the PR-time attestation authority.

## Capability Gaps

None blocking. One **net-new** implementation need (not a missing capability):

- **Server-side content validation:** no magic-byte sniffing exists today
  (`rg "fileTypeFrom|from \"file-type\"|import sharp" apps/web-platform --glob '*.ts'`
  → zero source hits; `file-type` is not a dependency). **Resolved by using `sharp`**
  (already at `apps/web-platform/package.json:84`, `^0.34.5`) for decode-and-re-encode,
  which validates format + dimensions and strips payloads — no new dependency required.

## Reuse Map (for the plan)

| Need | Reuse | Path |
|------|-------|------|
| Bucket + RLS | migration 068 (F3 write-split) + `is_workspace_member` (mig 053) | `apps/web-platform/supabase/migrations/068_attachments_workspace_shared.sql` |
| Migration test | 068 test (add cross-tenant overwrite-denial case) | `apps/web-platform/test/supabase-migrations/068-attachments-workspace-shared.test.ts` |
| Client upload UI | custom-icon upload (file input, preview, reset) | `apps/web-platform/components/settings/conversation-names-settings.tsx` |
| Settings mutation pattern | per-workspace rename action | `apps/web-platform/components/settings/rename-workspace-action.tsx` |
| Upload API route shape | CSRF/origin/auth/size-precheck/Sentry taxonomy | `apps/web-platform/app/api/kb/upload/route.ts` |
| Signed URL mint | `createSignedUrl` + `is_workspace_member` gate | `apps/web-platform/app/api/attachments/url/route.ts` |
| Render fallback | `setImgError` onError → fallback | `apps/web-platform/components/leader-avatar.tsx` |
| Render mount | TODO(#4916) img branch | `apps/web-platform/components/dashboard/workspace-identity-tile.tsx` |
| Chrome data source | thread `logoSignedUrl` into `OrgMembershipSummary` | `apps/web-platform/server/org-memberships-resolver.ts` |
| Column add | `ALTER TABLE workspaces ADD COLUMN IF NOT EXISTS logo_url text` (nullable) | new migration; table at `053_organizations_and_workspace_members.sql` |
| Legal lockstep | Privacy Policy + DPD + GDPR/Art.30 + AUP one-liner | `docs/legal/*`, `knowledge-base/legal/article-30-register.md` |
| DSAR / deletion wiring | DSAR export archiver + workspace-deletion cascade (NOT account-delete) | `apps/web-platform/server/dsar-export.ts`, workspace-deletion path |

## Session Errors

- Issue body specifies "PNG/SVG" but the security review (CTO) overrides to
  **PNG/WebP, no SVG**. The issue wording is stale relative to the brand-survival
  threshold; the spec and PR body must state the SVG drop explicitly so a reviewer
  doesn't "restore" SVG per the issue text.
