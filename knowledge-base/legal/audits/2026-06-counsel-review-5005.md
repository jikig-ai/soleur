---
title: "Counsel review audit — #5005 (PR #5014 DSAR workspace-files enumeration root converged off users.workspace_path onto the workspace-id resolver)"
type: counsel-review
date: 2026-06-08
issue: 5005
pr: 5014
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-06-08
signed_off_by: "Soleur CLO agent (Jikigai SARL — v1 internal counsel-review attestation authority; operator retains optional veto)"
disposition: DISCHARGED
re_evaluation_triggers: "First arms-length (non-Soleur) data subject exercising self-serve DSAR export against a SHARED (non-solo) workspace they own or are a member of; first EEA-out operator; first regulated-industry tenant (healthcare/finance/legal); OR ANY change converting resolveDsarWorkspacePath off the single-arg solo/N2 signature onto an active-/multi-workspace resolver (which would re-open the cross-tenant over-export surface this attestation relied on as structurally closed and would require re-pinning the no-over-export prose AND an Art. 30 PA-2 §(g) TOM review in lockstep); OR introduction of a non-solo workspace_id ≠ user_id minting flow (which would break the N2 identity the solo-keyed resolver assumes — see workspace-resolver.ts userIsSharedWorkspaceMember INVARIANT note / #2778)"
---

# Counsel review audit — #5005 (DSAR workspace-files enumeration root convergence)

Load-bearing evidence for the ship-time Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #5014 (`feat-one-shot-5005-workspace-path-readers`, `brand_survival_threshold: single-user incident`). PR #5014 converges five read paths off the legacy `users.workspace_path` / `users.workspace_status` columns onto the workspace-id resolver. The single DSAR-relevant change is in `apps/web-platform/server/dsar-export.ts`. Each disclosure claim below was cross-checked claim-by-claim against the IMPLEMENTING TypeScript — not trusted on prose alone — per the prose-against-code drift class recorded at PR #4353/#4558. Per the Soleur-as-tenant-zero v1 posture, the CLO agent performs this review and returns a per-artifact verdict; the operator (non-lawyer founder) retains an optional veto, and external counsel re-review is reserved for the frontmatter re-evaluation triggers.

The PR is held until this disposition is **DISCHARGED**.

## Implementation files cross-checked

- `apps/web-platform/server/dsar-export.ts`:
  - `resolveDsarWorkspacePath(subjectUserId)` (lines 94-96) — `return workspacePathForWorkspaceId(subjectUserId)`. Single-arg signature; no supabase client, no active-workspace claim.
  - `runExport` use site (line 2009) — `const workspacePath = resolveDsarWorkspacePath(expectedUserId)`, where `expectedUserId = job.user_id` (line 1989, the DSAR subject), fed into `buildArchiveToDisk(..., workspacePath, ...)`.
  - `enumerateWorkspaceFiles(workspacePath, ...)` (lines 1518-1537) — early-returns `{ included: [], skipped: [] }` when `workspacePath` is null/falsy OR not a directory; otherwise walks the tree. This is the silent-omission surface.
- `apps/web-platform/server/workspace-resolver.ts`:
  - `workspacePathForWorkspaceId(workspaceId)` (lines 668-670) — pure `join(WORKSPACES_ROOT, workspaceId)`; no DB read, no claim.
  - `resolveActiveWorkspacePath` / `resolveActiveWorkspaceIdWithMembership` (lines 286-348) — the ACTIVE-workspace resolver path; takes a supabase client, reads `user_session_state` current_workspace_id, J5 self-heals a stale non-member claim back to SOLO (fail-closed, never a sibling). Confirmed NOT used by the DSAR export. This is the resolver the DSAR change deliberately did NOT use.
- Removed prior code (commit 136ef27b5, `-` lines): `const workspacePath = typeof userRow?.workspace_path === "string" && userRow.workspace_path ? userRow.workspace_path : null;` — the legacy read of the `users.workspace_path` column with a null fallback.
- Legal artifacts: `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`, `docs/legal/data-protection-disclosure.md`; mirrors `plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`; `knowledge-base/legal/compliance-posture.md` changelog comment.

## Prose ↔ implementation fidelity (drift table — CONFIRMED CLEAN)

| Prose claim | Code evidence | Verdict |
|---|---|---|
| "converged the DSAR export's workspace-files enumeration root (`server/dsar-export.ts` `resolveDsarWorkspacePath`) off the stale `users.workspace_path` column onto the workspace-id resolver (`workspacePathForWorkspaceId(expectedUserId)`, solo/N2)" | New: `resolveDsarWorkspacePath` = `workspacePathForWorkspaceId(subjectUserId)` (lines 94-96), called with `expectedUserId = job.user_id` (line 2009). Removed: `userRow?.workspace_path` read (commit 136ef27b5). | MATCH. The named function, the named resolver, the single-arg solo/N2 keying, and the column it moved off are all literally accurate. |
| "Art. 15+20 completeness gap whereby data subjects provisioned after the ADR-044 `users → workspaces` relocation had their OWN workspace files silently omitted from the self-serve export (the legacy per-user column was empty/stale)" | Prior code resolved `workspacePath = null` whenever `users.workspace_path` was empty/absent; `enumerateWorkspaceFiles(null, ...)` returns `{ included: [], skipped: [] }` at line 1528 — NO error, NO skip-manifest entry. Post-relocation accounts have empty/stale `users.workspace_path`. Net effect: subject's own workspace files dropped from the export with no signal. | MATCH. This is a genuine Art. 15(3)/Art. 20(1) COMPLETENESS defect (incomplete provision of a copy / portable export of the subject's own data), silently truncated, now remediated. |
| "the solo-keyed resolver (single-arg, no active-workspace claim) structurally prevents the inverse over-export of a shared-workspace owner's files into a member's export" | `resolveDsarWorkspacePath(subjectUserId: string)` takes ONLY the subject id; it cannot consult `user_session_state.current_workspace_id` or any membership row, so it can NEVER resolve a shared/active workspace path. Contrast `resolveActiveWorkspacePath` (lines 339-348), which CAN resolve a shared workspace — deliberately not used here. | MATCH. The over-export path is closed by construction (type signature), not by a runtime check — the strongest form of the claim. Correct. |
| "No Article 30 amendment (read-path completeness remediation, not a new processing purpose)" / compliance-posture: "PA-2 DSAR coverage unchanged" | DSAR export of the subject's own workspace files is an existing registered activity (PA-2 / Art. 15+20 self-serve export). The change alters only the PATH SOURCE the enumerator keys on; it adds no table, bucket, recipient, purpose, or category. The `users` table is still emitted by `exportSqlTable` (line 2000); only the workspace-path *source* moved (confirmed by the line 2006-2008 comment). | MATCH. No Art. 30 register row added or amended; PA-2 anchor unchanged. Correct. |
| "No new processing activity, personal-data category, lawful basis, recipient, or sub-processor" | Diff touches one path-resolution expression + its helper. No new `service.from(...)` read, no new bucket, no new egress, no new external party. The data delivered (subject's own workspace files) is data the subject already controls and the export "always intended to" deliver. | MATCH. Under-, not over-, disclosure. Correct. |

No drift found. The prose does not over-claim: it does not assert the bug ever caused an over-export (it did not — the defect was under-export/omission), and it correctly frames the over-export as the *inverse* failure mode that the solo-keyed signature now forecloses.

## Resolution of the four attested questions

### 1. Is this an Art. 15/20 COMPLETENESS fix with NO new processing activity / category / lawful basis / recipient / sub-processor? — CONFIRMED YES

The prior implementation read `users.workspace_path` and fell back to `null`; `enumerateWorkspaceFiles(null)` silently returned an empty set. For any subject provisioned after the ADR-044 relocation moved workspace state from `users` to `workspaces`, that column is empty/stale, so the subject's own workspace files were omitted from their Art. 15 copy / Art. 20 portable export with no error and no skip-manifest entry. The fix resolves a deterministic id-keyed path (`<WORKSPACES_ROOT>/<subjectUserId>`) so the files are enumerated. This restores completeness of an existing right; it introduces no new processing activity, personal-data category, lawful basis, recipient, or sub-processor. **VERDICT: PASS.**

### 2. Is the "solo-keyed resolver structurally prevents over-export of a shared workspace owner's files into a member's export" claim accurate? — CONFIRMED YES

`resolveDsarWorkspacePath(subjectUserId: string): string` is single-arg and delegates to the pure `workspacePathForWorkspaceId`. It has no supabase client and no access to the active-workspace claim, so it cannot resolve anything other than the subject's own solo/N2 path. The alternative `resolveActiveWorkspacePath` — which COULD resolve a shared workspace the subject is a member of (and thereby pull the owner's files into a member's DSAR) — is deliberately not used. Because the guarantee is enforced at the type/signature level rather than by a runtime branch, the over-export is structurally impossible, exactly as the prose states. **VERDICT: PASS.**

### 3. Is "No Article 30 amendment" correct (PA-2 DSAR coverage unchanged)? — CONFIRMED YES

The self-serve DSAR export of a subject's own data is already the registered PA-2 activity. PR #5014 changes only the source from which the workspace-files enumeration root is derived; it adds no purpose, category, recipient, or sub-processor and narrows no registered PA-2 §(g) TOM (the membership-scoped read isolation that protects OTHER data subjects is untouched — the subject keying actually tightens, not loosens, scoping). No Art. 30 register edit is required, and none was made. The compliance-posture comment's "PA-2 DSAR coverage unchanged" is accurate. **VERDICT: PASS.**

### 4. Does this change lawful basis / consent / retention / Art. 6(1)(f) LIA? — CONFIRMED NO

No. The lawful basis for responding to a DSAR (legal obligation under GDPR Arts. 15/20, Art. 6(1)(c)) is unchanged. No consent is gathered or withdrawn. No retention period is altered (the export is ephemeral; the underlying files' retention is untouched). No Art. 6(1)(f) legitimate-interest balancing test is engaged or modified — the diff adds no new processing weighed against data-subject interests; it fixes an implementation to match an already-disclosed and already-balanced right of access. The GDPR Policy carries only a `**Last Updated:**` changelog line; no new balancing-test or processing-register section was added (diff-verified — the only non-context change in each source doc is the Last-Updated line). **VERDICT: PASS.**

## Lockstep / byte-equivalence verification

- Six legal files carry the identical June 8, 2026 `**Last Updated:** (PR #5014 (#5005) …)` lead.
- The `#5005` prose segment is **byte-identical** across `docs/legal/` canonical and `plugins/soleur/docs/pages/legal/` mirror for all three doc types — md5 `aa0b528ca8121a2652ff067abd47ff4a` for privacy-policy, gdpr-policy, and data-protection-disclosure source-vs-mirror segments alike (diff-verified). The Eleventy mirror cannot drift from canonical.
- `knowledge-base/legal/compliance-posture.md` changelog comment is consistent with the doc prose (same remediation framing, "No Article 30 amendment", "PA-2 DSAR coverage unchanged", "No migration").
- No source legal doc has any non-`Last Updated` content change (prior changelog text correctly rolled into the "Previous:" chain) — confirming no stealth processing-activity / register / LIA edit.

## Per-artifact verdict

| Artifact | Change | Verdict |
|---|---|---|
| `apps/web-platform/server/dsar-export.ts` (`resolveDsarWorkspacePath`, `runExport`, `enumerateWorkspaceFiles`) | Implementation that the prose describes; completeness fix; solo/N2-keyed | PASS — implements exactly what is disclosed |
| `docs/legal/privacy-policy.md` | Last-Updated #5005 changelog entry | PASS — accurate, no over-claim |
| `docs/legal/gdpr-policy.md` | Last-Updated #5005 changelog entry; no register/LIA edit | PASS — accurate; Art. 30/LIA correctly untouched |
| `docs/legal/data-protection-disclosure.md` | Last-Updated #5005 changelog entry; no new §2.3 activity | PASS — accurate; no new processing-activity entry |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | Eleventy mirror | PASS — byte-identical segment to canonical |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | Eleventy mirror | PASS — byte-identical segment to canonical |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Eleventy mirror | PASS — byte-identical segment to canonical |
| `knowledge-base/legal/compliance-posture.md` | Changelog comment | PASS — consistent with doc prose |

## Overall disposition: DISCHARGED

Every implementation-detail claim in the new legal prose is accurate against the actual TypeScript. The change is a genuine Art. 15/20 completeness remediation of an existing, already-disclosed right of access; it introduces no new processing activity, personal-data category, lawful basis, recipient, or sub-processor; it requires no Art. 30 amendment (PA-2 unchanged); and it does not touch consent, retention, or any Art. 6(1)(f) balancing test. The solo-keyed single-arg resolver structurally forecloses the inverse over-export risk. The legal docs and their Eleventy mirrors are byte-equivalent in the #5005 segment. No prose-vs-implementation mismatch and no weak/absent lawful basis. **No in-PR prose correction required.** The Phase 5.5 Counsel-Review CLO-Attestation Gate is **DISCHARGED**; PR #5014 may proceed to ship.
