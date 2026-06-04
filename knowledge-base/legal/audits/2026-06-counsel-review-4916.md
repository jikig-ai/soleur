---
title: "Counsel review audit — #4916 (PR #4930 workspace logo: Article 30 PA-26 + Privacy/DPD/GDPR/AUP amendments)"
type: counsel-review
date: 2026-06-04
issue: 4916
pr: 4930
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-06-04
signed_off_by: "Soleur CLO agent (Jikigai SARL — v1 internal counsel-review attestation authority; operator retains optional veto)"
disposition: DISCHARGED
re_evaluation_triggers: "First arms-length (non-Soleur) workspace member uploading or being depicted in a logo; first EEA-out data residency change for the workspace-logos bucket; first regulated-industry tenant; OR addition of an uploader-attribution column to the logo path (which would convert the asset into personal data of the uploader and require re-scoping the Art. 15(4) DSAR exclusion)"
---

# Counsel review audit — #4916 (workspace logo image)

Load-bearing evidence for the Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #4930 (`feat-workspace-logo-upload`, draft, `brand_survival_threshold: single-user incident`). The five legal artifacts below carry ADDITIVE disclosures for the owner-uploaded workspace logo feature. Each was cross-checked claim-by-claim against the implementing migration, routes, and helpers. Per the Soleur-as-tenant-zero v1 posture, the CLO agent performs this review and returns a per-artifact verdict; the operator (non-lawyer founder) retains an optional veto, and external counsel re-review is reserved for the frontmatter re-evaluation triggers.

The PR is held in draft until this disposition is **DISCHARGED**.

## Implementation files cross-checked

- `apps/web-platform/supabase/migrations/098_workspace_logos.sql` — `workspaces.logo_path text`; private bucket `workspace-logos` (`public=false`, `file_size_limit=1048576`, `allowed_mime_types=['image/webp']`); `is_workspace_owner(uuid,uuid)` SECURITY DEFINER plpgsql, search_path-pinned, REVOKE-then-GRANT-authenticated; member-read + owner-only INSERT/UPDATE/DELETE RLS on `storage.objects` (no FOR ALL; UPDATE carries USING + WITH CHECK).
- `apps/web-platform/app/api/workspace/logo/route.ts` — server-side workspace resolution (`resolveCurrentWorkspaceId`, never client-supplied), owner gate (403), `sharp` decode against real pixels (format gate → 415 for SVG/JPG; pixel-flood ceiling; square gate; WebP re-encode with no `.withMetadata()` → EXIF strip), service-role upload-then-persist with orphan cleanup, CSRF/origin check, content-length pre-check, rate limit.
- `apps/web-platform/app/api/workspace/[id]/logo/route.ts` — membership-gated stable proxy → 302 to 300 s signed URL; `Cache-Control: private, max-age=300`; `X-Content-Type-Options: nosniff`.
- `apps/web-platform/server/workspace.ts` (`purgeWorkspaceLogoObjects`) + `apps/web-platform/server/account-delete.ts` step 3.6 (sole-owned teardown; `userId === workspaces.id` N2 invariant; best-effort, never throws).

## Prose ↔ implementation fidelity (drift table — CONFIRMED CLEAN)

| Prose claim (across the 5 artifacts) | Code evidence | Verdict |
|---|---|---|
| Private bucket | mig 098:53 `false` | match |
| ≤1 MB cap | mig 098:54 `1048576`; route `MAX_BYTES`; bucket `file_size_limit` | match |
| Canonical WebP re-encode; single allowed mime | mig 098:55 `['image/webp']`; route `.webp({quality:90})` | match |
| EXIF stripped at re-encode | route — no `.withMetadata()`, no `animated` | match |
| Raster-only; SVG rejected | route format gate `meta.format !== png/webp` → 415 | match |
| Polyglot / decode-bomb neutralised | `sharp` decode of real bytes + `limitInputPixels` ceiling | match |
| Owner-only write, member-only read | mig 098 RLS via `is_workspace_owner` / `is_workspace_member` | match |
| Keyed by `workspace_id` | route key `<workspaceId>/logo.webp`; foldername UUID guard | match |
| No uploader-attribution column (v1) | mig only adds `workspaces.logo_path text`; no actor column | match |
| Short-TTL signed-URL proxy + nosniff | `[id]/logo` 300 s signed URL, `nosniff` header | match |
| Purged on sole-owned account-delete teardown | account-delete 3.6 → `purgeWorkspaceLogoObjects(userId)` | match |
| NOT purged on shared-member removal | helper doc + no member-removal call site | match |
| No new sub-processor / region | reuses Supabase eu-west-1; no new vendor/bucket region | match |

No prose claim hallucinated against the code (cf. the PR #4353/#4558 drift class). The disclosures are conservative relative to the implementation, not ahead of it.

---

## Legal questions resolved

**1. Lawful basis (Art. 6(1)(b) + 6(1)(f)) — DEFENSIBLE.** The logo is a workspace branding asset uploaded by the Owner to render in workspace chrome; storing it is necessary to perform the workspace-collaboration contract (6(1)(b)). The parallel 6(1)(f) limb (retaining a shared asset) is a belt-and-suspenders basis whose LIA holds: (i) **purpose** — legitimate workspace-identity branding; (ii) **necessity** — a stored asset is the least-intrusive way to render persistent chrome branding; (iii) **balancing** — minimal/no impact on data-subject rights because in v1 there is *no uploader-attribution column*, so the asset is not personal data about the uploader. The balancing test is only reached if a logo incidentally depicts a natural person, in which case the Owner is the controller of that content under the collaboration contract (PA-26 limb (b)). Defensible for v1.

**2. Retention (workspace lifetime; purge on sole-owned teardown, not on member removal) — COHERENT.** Art. 5(1)(e) storage-limitation is satisfied by binding retention to workspace lifetime. The asymmetry — purge on sole-owned account-delete teardown (`purgeWorkspaceLogoObjects`, gated on the `userId === workspaces.id` N2 invariant), but NOT on shared-member removal — is the correct treatment of a *shared* asset: a departing member has no erasure claim over a workspace-owned branding asset that is not their personal data. Coherent and internally consistent across Privacy §7, GDPR §8.4, DPD §2.3(z), and PA-26 limb (f).

**3. DSAR / Art. 15 exclusion — DEFENSIBLE.** Excluding the logo from the automated per-user export is defensible under Art. 15(4) (rights and freedoms of others): the asset is workspace-keyed and shared, with no uploader attribution in v1, so it is not "personal data concerning the [requesting] data subject" of any single user. The manual Art. 15 path remains available for edge cases. **This verdict is contingent on the v1 no-attribution design** — it is the load-bearing fact. The re-evaluation triggers (frontmatter) explicitly arm on the addition of any uploader-attribution column, which would convert the asset into the uploader's personal data and require the logo to enter (or be reasoned about within) the per-user export. Defensible as scoped.

**4. No new sub-processor / Chapter V transfer — CONFIRMED.** The `workspace-logos` bucket sits in the same Supabase Inc (eu-west-1, Ireland) substrate as the existing `chat-attachments` and `dsar-exports` buckets, under the SIGNED Supabase DPA (SCCs Module 2+3). No new processor is engaged and no new third-country transfer is introduced. The Vendor DPA Status table needs no new row.

**5. Prose ↔ implementation fidelity — CONFIRMED CLEAN.** See the drift table above; every implementation-detail claim matches the migration/route/helper body.

---

## Artifact verdicts

| # | Artifact | File | Verdict |
|---|----------|------|---------|
| 1 | Article 30 Register — PA-26 | `knowledge-base/legal/article-30-register.md` | ☑ APPROVED — eight-limb Art. 30(1) shape; purpose, no-attribution categories, recipients (members + Supabase, no new sub-processor), no new transfer, workspace-lifetime retention with sole-owned purge, five TOMs, Art. 15(4) DSAR exclusion. Matches code. |
| 2 | Privacy Policy | `docs/legal/privacy-policy.md` | ☑ APPROVED — new "Workspace logo" collection bullet (§ account-data list), Art. 15(4) exclusion paragraph extension, and §7 retention sentence. Accurate; no over-claim. |
| 3 | Data Protection Disclosure — §2.3(z) | `docs/legal/data-protection-disclosure.md` | ☑ APPROVED — full processing-activity entry; data processed, dual lawful basis, visibility scope, Art. 32 TOMs, retention, Art. 15(4) exclusion, no-new-sub-processor, PA-26 cross-ref. |
| 4 | GDPR Policy — §3.7 + §8.4 | `docs/legal/gdpr-policy.md` | ☑ APPROVED — §3.7 lawful-basis register entry (the most-often-missed of the three privacy/GDPR docs — present and consistent) and §8.4 Web Platform retention sentence. |
| 5 | Acceptable Use Policy — §4.2 | `docs/legal/acceptable-use-policy.md` | ☑ APPROVED — extends the prohibited-content enumeration to uploaded images including the workspace logo (IP/trademark/objectionable). Within AUP scope; no T&C version bump required (AUP incorporated by reference under T&C §9). |

All three privacy/GDPR documents (Privacy Policy, DPD §2.3(z), GDPR Policy §3.7) were updated in lockstep — the GDPR Policy register entry (the commonly-missed one) is present.

`apps/web-platform/lib/legal/legal-doc-shas.ts` SHA pins were refreshed for the four changed docs (acceptable-use-policy, data-protection-disclosure, gdpr-policy, privacy-policy) — consistent with the diff.

---

## Disposition

**DISCHARGED.** All five artifacts APPROVED. The five legal questions are confirmed/correct as analysed in PA-26. Prose↔implementation drift table is clean. gdpr-gate ran clean at plan-time, work-Phase-2 exit, and review (no Art. 9 Critical). No `[DRAFT — pending CLO]` markers remain. The PR's counsel-review gate is satisfied for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto. External counsel re-review is reserved for the frontmatter re-evaluation triggers — note especially that **adding an uploader-attribution column would invalidate the Art. 15(4) DSAR exclusion** and must re-open this review.

| Reviewer | Date | Channel | Sign-off |
|----------|------|---------|----------|
| Soleur CLO agent (Jikigai SARL — v1 internal counsel-review attestation authority; external re-review trigger per frontmatter) | 2026-06-04 | CLO-agent attestation via PR #4930 Phase 5.5 gate | ☑ |
