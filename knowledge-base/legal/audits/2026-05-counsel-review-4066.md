---
title: "Counsel review audit — #4066 (PR-H Article 30 PA-17 + DPD/Privacy/AUP amendments)"
type: counsel-review
date: 2026-05-19
issue: 3244
pr: 4066
status: SIGNED-OFF (operator-attested)
signed_off_at: 2026-05-19
signed_off_by: "Jean Deruelle (Jikigai SARL gérant)"
re_evaluation_triggers: "First non-Soleur tenant onboarding OR first founder installing the GitHub App with regulated-data repositories"
---

# Counsel review audit — #4066 (PR-H Article 30 PA-17 + legal doc amendments)

This audit file is the load-bearing evidence for the counsel-review gate on PR #4066 (PR-H, draft 2026-05-19). The five artifacts below were touched by the multi-source priority signals work; each row is operator-attested in lieu of external counsel review for v1 (Soleur-as-tenant-zero posture) per the precedent established by PR #4081 / #4051 (`2026-05-counsel-review-4051.md`).

The PR was held in draft state until all rows below were signed off.

---

## Artifact 1 — Article 30 Register (PA-17 addition, PA-15 LinkedIn restoration)

**File:** `knowledge-base/legal/article-30-register.md`

**Scope of review:**
- New Processing Activity 17 — "GitHub-sourced multi-source priority signals (PR-H #3244)". Nine-limb Art. 30(1) shape covering founder-operators, GitHub installation_id + webhook delivery_id + repository content rendered display-only, Art. 6(1)(f) legitimate-interest basis, GitHub Inc. as source (not recipient), Supabase eu-west-1 + Hetzner eu-central residency, 12 TOMs.
- PA-15 collision fix: the LinkedIn PA-15 from PR #4081 (merged 2026-05-19) was restored verbatim from origin/main and the GitHub block shifted to PA-17 (review F3).

**Particular attention requested on:**
1. Lawful-basis three-part test for Art. 6(1)(f): is the "founder benefits from priority signals on their own dashboard from their own installation" framing sufficiently narrow?
2. PA-17 TOM-#10 caveat — `record_github_token_use` ships as schema-only in PR-H; per-Octokit-call writer wires in PR-H+1 (#4098). Is the unpopulated-ledger disclosure language adequate?
3. Render-time `redactGithubSourcedText` is the load-bearing Art. 14 minimization gate. INSERT-time redaction is belt-and-suspenders. CVE / secret-scan rows additionally have `draft_preview` summary-body stripped server-side (review P2 fix). Is the layered-minimisation framing accurately characterized?

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1 — Soleur-as-tenant-zero posture; external counsel re-review trigger: first non-Soleur tenant onboarding OR first founder installing the GitHub App with regulated-data repositories) | 2026-05-19 | Operator attestation via PR #4066 review | ☑ | Approved. PA-17 framing accurate; layered redaction is documented at three sites (INSERT-time, render-time, on-wire CVE strip). Re-evaluation triggers in place. |

---

## Artifact 2 — Data Protection Disclosure (DPD)

**File:** `docs/legal/data-protection-disclosure.md`

**Scope of review:** the diff in PR #4066 covering the GitHub Inc. (Microsoft Corporation) sub-processor reaffirmation comment for the new GitHub App webhook ingress, SCCs Module 2 + DPF as the transfer mechanism, and the cross-reference update from `Processing Activity 15` to `Processing Activity 17` (review F3 collision fix).

**Particular attention requested on:**
1. Sub-processor characterization: GitHub Inc. as source (not recipient) of the data, with the data egress flowing FROM GitHub TO Soleur via the signed webhook. Does this framing correctly distinguish source-vs-recipient under Art. 28 / Art. 13(1)(e)?
2. Per-founder bilaterality: the App is installable on the founder's own account/orgs only — is this sufficient to scope the DPA disclosure as bilaterally per-founder rather than as a universal Soleur-side sub-processor row?

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1) | 2026-05-19 | Operator attestation via PR #4066 review | ☑ | Approved. Source-vs-recipient framing matches the bilaterally-per-founder install topology. |

---

## Artifact 3 — Privacy Policy

**File:** `docs/legal/privacy-policy.md`

**Scope of review:** the diff in PR #4066 covering the Web Platform agent runtime's ingestion of GitHub repository activity, the render-time `redactGithubSourcedText` Art. 14 minimization gate disclosure, `Cache-Control: private, max-age=60` on the Today endpoint, the founder-revoke-at-/dashboard/settings/scope-grants affordance (Art. 22(3) + PR-G ADR-033), and the cross-reference update to `Processing Activity 17` (review F3 collision fix).

**Particular attention requested on:**
1. Art. 14(1)(d) "categories of personal data concerned" disclosure: are PR titles/bodies, issue titles/bodies, CI run names+URLs, CVE / secret-scanning metadata correctly enumerated for indirect-collection scenarios (the third-party content was authored by repo contributors, not the founder)?
2. Render-time vs INSERT-time redaction framing — clarity on which is the load-bearing gate (render-time per plan TR6 amendment).

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1) | 2026-05-19 | Operator attestation via PR #4066 review | ☑ | Approved. Art. 14 indirect-collection enumeration is accurate; minimization gate is correctly framed as render-time-load-bearing with INSERT-time belt-and-suspenders. |

---

## Artifact 4 — Acceptable Use Policy

**File:** `docs/legal/acceptable-use-policy.md`

**Scope of review:** the diff in PR #4066 adds the card-screenshot-redaction clause. GitHub-sourced Today cards render with `redactGithubSourcedText` applied at the render layer; founders are advised not to capture or share screenshots of cards containing third-party repository content beyond what Soleur presents. CVE / secret-scanning cards render ID + severity only by default. KB-drift cards are internal-infrastructure signal and render unredacted by design.

**Particular attention requested on:**
1. Operator-advisory framing: is "advised not to capture or share screenshots" the right register, or should it be a contractual prohibition?
2. KB-drift unredacted-by-design disclosure: clarity that internal-infrastructure rows (link health, anchor health) are not third-party content.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1) | 2026-05-19 | Operator attestation via PR #4066 review | ☑ | Approved. Advisory register is appropriate for v1; contractual escalation deferred to first non-Soleur tenant onboarding. |

---

## Artifact 5 — Audit ledger Art. 17 cascade (post-review P1 fix)

**File:** `apps/web-platform/supabase/migrations/052_multi_source_dedup.sql` (anonymise function + WORM trigger) + `apps/web-platform/server/account-delete.ts` (cascade wiring).

**Scope of review:** post-review P1 finding F6 (data-migration-expert, data-integrity-guardian) surfaced that `audit_github_token_use.founder_id` has `ON DELETE RESTRICT` without an Art. 17 cascade hook. Migration 051 was amended to add `anonymise_audit_github_token_use(p_founder_id)` SECURITY DEFINER RPC + WORM trigger (`audit_github_token_use_no_mutate`) + replica-mode bypass for the anonymise path. Account-delete now invokes the RPC BEFORE `auth.admin.deleteUser()`.

**Particular attention requested on:**
1. Art. 17 cascade discipline: does the anonymise path (NULL founder_id + NULL repo_full_name; keep installation_id + endpoint + ts + response_status as accountability metadata) correctly satisfy the right-to-erasure obligation while preserving Art. 5(2) accountability evidence?
2. WORM-bypass narrowness: `SET LOCAL session_replication_role = 'replica'` scopes the trigger short-circuit to the RPC body only. Is this sufficient under Art. 32 design principles?

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1) | 2026-05-19 | Operator attestation via PR #4066 review | ☑ | Approved. Art. 17 cascade preserves accountability metadata while erasing founder-linked PII; WORM-bypass is correctly scoped to the SECURITY DEFINER RPC body. |

---

## Post-sign-off operator actions

After all five rows above are signed off:

1. Move the `#4066 | IN-PROGRESS` row in `knowledge-base/legal/compliance-posture.md` from Active Compliance Items to Completed Compliance Work with the merge-day completion date.
2. Mark PR ready: `gh pr ready 4066`.
3. Verify CI green; auto-merge: `gh pr merge --squash --auto 4066`.

Post-merge operator runbook (NOT part of this counsel review — captured separately in the PR body):
- `terraform apply` for `apps/web-platform/infra/github-app.tf` + `kb-drift.tf` + `alerts-github-webhook.tf` (operator holds Doppler `prd_terraform` + Cloudflare zone access + GitHub App creation UI access).
- Doppler `prd_kb_drift_walker` config bootstrap.
- GitHub App creation in https://github.com/settings/apps (operator), webhook URL pointed at production endpoint, secret rotated in via Doppler.
- BetterUptime monitor verification for the new webhook endpoint.
- PR-H+1 (#4098) feature work follows on its own track.
