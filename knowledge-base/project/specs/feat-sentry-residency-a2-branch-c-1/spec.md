---
feature: sentry-residency-a2-branch-c
date: 2026-05-16
status: ready-for-plan
owner: jean.deruelle@jikigai.com
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
triad: [cpo, clo, cto]
parent_issue: "#3861"
related_issues:
  - "#3861"  # umbrella
  - "#3863"  # A1 (merged 2026-05-15)
  - "#3904"  # PR-α draft (this worktree)
brainstorm: knowledge-base/project/brainstorms/2026-05-16-sentry-residency-a2-branch-c-brainstorm.md
worktrees_planned:
  - feat-sentry-residency-a2-branch-c-1  # PR-α (legal+docs)
  - feat-sentry-residency-a2-branch-c-2  # PR-β (runtime+IaC+audit-gate)
  - feat-sentry-residency-a2-branch-c-3  # PR-γ (cleanup+vendor)
art_33_deadline: "2026-05-19T12:50:00Z"
---

# Spec: Sentry Residency A2 — Branch C (new DE org from scratch)

## Problem Statement

A2's original framing (align tfstate to existing DE org, rotate token, re-apply) was invalidated by a 3-premise cascade on 2026-05-16: (1) `de.sentry.io` is INGEST-ONLY; the dashboard host is `sentry.io` / `jikigai.sentry.io` / `eu.sentry.io`; (2) there is NO controllable jikigai org on EU/DE — region-router 302→401 confirms; (3) A1's audit script greenlit a phantom destination because cluster-substring check ≠ admin-controllability check. The runtime `SENTRY_DSN` POSTed user-telemetry-shaped events to an unowned org ID `4511123328466944` on `o4511...ingest.de.sentry.io` for a 49-day window (2026-03-28 → 2026-05-16) documented in `knowledge-base/engineering/ops/runbooks/sentry-phantom-ingest-destination-unreachable-postmortem.md`.

Branch C creates a new DE jikigai org from scratch on `eu.sentry.io`, atomically migrates the runtime DSN + 7+ secret surfaces, drops + re-imports tfstate, and extends the audit script with a destination-controllability gate so the failure mode cannot silently recur.

## Goals

- G1. Provision a new Jikigai-controllable Sentry org on `eu.sentry.io` (DE residency).
- G2. Atomic-swap all runtime DSN, auth-token, cron-checkin, and CSP-report-uri secrets from phantom org to new DE org across 7+ surfaces (Doppler `prd`, GH repo secrets, Vercel envs, .env.example, Dockerfile build-args, 11 scheduled GH workflows, sentry-cli build path).
- G3. Drop existing tfstate entirely + manifest-capture-then-serial-reimport against new DE org.
- G4. Extend `apps/web-platform/scripts/sentry-monitors-audit.sh` with `audit_destination_admin_controllable` triple-gate (reachability + project-scope + write-probe) running both at deploy and in CI on Sentry-touching diffs.
- G5. Update PA8 §5(2) (Article 30 Register) with CLO-signed positive disclosure of the phantom-ingest window.
- G6. Update ADR-031 — replace stale 404 URL + add ingest/dashboard/API host glossary.
- G7. Tear down US shadow org (Team subscription already cancelled effective 2026-06-14; alive on free plan for forensics + refund) + 2 separate Sentry support tickets (billing-only + forensics-only).
- G8. Flip PIR `status: open → resolved` once C2 + C5 ship + Sentry-support-response-OR-T+14d-timeout.

## Non-Goals

- NG1. C9 (Sentry Relocation tooling) — ruled out by 30-min-capped probe this brainstorm. Self-hosted→SaaS only; doesn't preserve DSNs; doesn't migrate from unowned orgs.
- NG2. Cross-cluster event-history migration — historical events on phantom org are unrecoverable; new org starts with empty event stream.
- NG3. Source-map re-upload to new org for pre-swap releases — orphan window self-closes when phantom-org 49-day retention expires ~2026-07-04.
- NG4. Dual-DSN feature-flag rollout — CTO ruled out as half-state surface.
- NG5. Single bundled PR — CPO ruled out as deadline-coupling risk.
- NG6. Aggressive forensics-language refund posture — CPO ruled out as vendor-relationship risk.

## Functional Requirements

**PR-α (legal+docs, this worktree, ships 2026-05-17/18):**

- FR1. Append CLO-signed phantom-ingest disclosure paragraph to PA8 §5(2) recipient cell in `knowledge-base/legal/article-30-register.md`. Use `<pending C2 merge>` placeholder for the post-swap DE-org reference; backfilled in PR-γ.
- FR2. Update ADR-031 (`knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`): replace stale URL `de.sentry.io/settings/account/api/auth-tokens/` (returns 404), add glossary distinguishing ingest hosts (`*.ingest.{de,us}.sentry.io`), dashboard hosts (`sentry.io`, `jikigai.sentry.io`, `eu.sentry.io`), and API hosts (`{eu,us}.sentry.io/api/0/...`).
- FR3. Add one-line cross-reference in `knowledge-base/legal/compliance-posture.md` under "Active Compliance Items" pointing to the PIR (creates auditable Art 34 self-subject disclosure trail).

**PR-β (runtime+IaC+audit-gate, sibling `-2`, ships next week):**

- FR4. **C1.** Operator creates new DE jikigai org under `jean.deruelle@jikigai.com` via `eu.sentry.io` signup. Playwright drives nav; operator types credentials. Headed-config enforced; pre-flight `pgrep --headless` probe per cascade learning W1.
- FR5. **C2.** Atomic-swap across all surfaces (write-new-everywhere-then-revoke-old with 2h observation window):
    - Doppler `prd`: `SENTRY_DSN`, `NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_CSP_REPORT_URI`, `SENTRY_AUTH_TOKEN`, `SENTRY_API_TOKEN` (3rd namespace per `2026-05-15-token-namespace-divergence`), `SENTRY_ORG`, `SENTRY_PROJECT`.
    - GH repo secrets: `NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`, `SENTRY_API_HOST` (set to `eu.sentry.io`).
    - Vercel envs (matching Doppler `prd` shape).
    - `apps/web-platform/.env.example` (commented templates).
    - `apps/web-platform/Dockerfile` build-args (`NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`).
    - `apps/web-platform/next.config.ts` Sentry block (`SENTRY_URL` injection if absent).
    - `.github/workflows/reusable-release.yml` (lines ~283-330 audit-script env block; ~513-518 Docker build-args; inject `SENTRY_URL=https://eu.sentry.io/`).
    - 11 scheduled GH workflows consuming cron-checkin triple (`scheduled-terraform-drift.yml`, `scheduled-github-app-drift-guard.yml`, `scheduled-daily-triage.yml`, `scheduled-community-monitor.yml`, `scheduled-oauth-probe.yml`, `scheduled-realtime-probe.yml`, `scheduled-content-vendor-drift.yml`, `scheduled-skill-freshness.yml`, `scheduled-followthrough-sweeper.yml`, and 2 additional flagged in repo-research inventory).
    - Cloudflare edge cache purge for CSP `report-uri` header after Doppler/Vercel propagation.
- FR6. **C3.** Mint new DE-scoped `SENTRY_AUTH_TOKEN` (scopes: `project:read`, `project:releases`, `project:write`, `org:read`). Verify probe MUST target `https://eu.sentry.io/api/0/users/me/` (NOT de.sentry.io — cascade learning §"Solution 1").
- FR7. **C4.** `terraform state rm` × all (13 resources: 8 cron monitors + 4 issue alerts + 1 data lookup). Pre-flight manifest capture via existing audit script. Update `var.sentry_project` default if new DE-org project slug differs. Sequence imports strictly serial (R2 backend has `use_lockfile = false` — concurrent imports race silently per `2026-03-21-terraform-state-r2-migration.md`).
- FR8. **C5.** Extend `apps/web-platform/scripts/sentry-monitors-audit.sh` with three new gates slotted between region-probe success (L58) and DSN-cluster check (L60):
    - `audit_destination_admin_controllable`: `curl -H "Bearer $TOKEN" https://eu.sentry.io/api/0/organizations/$SENTRY_ORG/ → 2xx`.
    - `audit_project_scope`: `curl … /api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/ → 2xx`.
    - `audit_write_probe`: POST synthetic release to `/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/releases/`, DELETE it. Proves `project:releases` scope end-to-end.
    - Wire CI to run on diffs touching `sentry.*.config.ts | next.config.ts | infra/sentry/**/*.tf | .github/workflows/*sentry*` paths.
- FR9. Extend audit-script region-probe loop at L43-58 to include `eu.sentry.io` (currently iterates `de.sentry.io, sentry.io` only).

**PR-γ (cleanup+vendor, sibling `-3`, ships when refund processes):**

- FR10. **C8a.** Tear down US shadow org `jikigai` on `sentry.io` (already cancelled effective 2026-06-14; keep on free plan during forensics window).
- FR11. **C8b.** Submit 2 separate Sentry support tickets:
    - Ticket 1 (billing-only): "Team trial activated in error during IaC misconfiguration, requesting prorated refund of $5.46 PAYG + unused Team prorate. Happy to provide our EU org slug once provisioned."
    - Ticket 2 (forensics-only, separate routing): "Requesting owner-history confirmation for org ID 4511123328466944 to close an internal Article 30 sub-processor audit."
- FR12. Backfill `<pending C2 merge>` placeholder in PA8 §5(2) (PR-α's C6) with actual PR-β commit SHA / merge ref.
- FR13. File W1/W2/W4/W5 as 4 atomic GH issues (W3 absorbed into C5).
- FR14. Flip PIR `status: open → resolved` once C2 + C5 ship AND (Sentry-support-response-received OR T+14d-timeout-elapsed). Document residual evidence ceiling.

## Technical Requirements

- TR1. **Half-state guard mechanic** (C2): write-new-everywhere → deploy → 2h observation window → audit-script-C5 green against new org → revoke old token. Hard-gate revoke on audit green.
- TR2. **Playwright posture** (C1): headed via `--config` flag + persistent profile `--user-data-dir=/home/jean/.cache/playwright-mcp-profile`. Pre-flight `pgrep -fa chromium | grep -- --headless` MUST return empty before driving any credential flow. Reconcile against `@playwright/mcp@0.0.75` headless-default regression — verify .mcp.json config takes effect at C1 start.
- TR3. **DE org name collision check** (C1): Playwright probe whether `jikigai` org slug is available on `eu.sentry.io`. If not, document chosen alternative (`jikigai-eu` / `jikigai-de`) and propagate to all 11+ secret surfaces + Terraform `var.sentry_org` default.
- TR4. **PIR Phase 8 gate criteria** (FR14): explicitly enumerate in PIR frontmatter — DSN substring matches new DE org orgInternalId, controllability probe 2xx, all secret stores rotated, old token revoked, Sentry-support T+14d-or-response. Becomes institutional precedent for future Phase-8 closures.
- TR5. **CSP report-uri Cloudflare cache purge mechanic** (FR5): determine per-zone vs per-URL purge for Cloudflare plan; document chosen approach in C2 runbook.
- TR6. **Source-map orphan disclosure** (NG3): PIR documents that pre-swap prod errors cannot be symbolicated post-swap; orphan window auto-closes at phantom-org 49-day retention expiry (~2026-07-04).
- TR7. **All Branch C PRs frontmatter** carries `brand_survival_threshold: single-user incident` and triggers user-impact-reviewer at review time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Acceptance Criteria

**PR-α:**

- AC1. PA8 §5(2) recipient cell contains phantom-ingest disclosure paragraph (verifiable via `grep "Phantom-ingest disclosure" knowledge-base/legal/article-30-register.md`).
- AC2. CLO sign-off on §5(2) wording captured in PR-α body.
- AC3. ADR-031 no longer references the 404 URL (`grep -c "de.sentry.io/settings" knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` returns 0); glossary section present.
- AC4. compliance-posture.md cross-references PIR.
- AC5. PR-α merged by 2026-05-19 (Art 33 procedural gate).

**PR-β:**

- AC6. New DE org provisioned + DSN substring matches `o<new-id>.ingest.de.sentry.io` AND `<new-id> ≠ 4511123328466944`.
- AC7. Audit-script C5 triple-gate runs green against new org + audit script CI workflow added/extended.
- AC8. All 7+ secret surfaces enumerated in FR5 contain new DSN/token values (verified per-surface independently).
- AC9. Old token revoked AFTER audit green; phantom DSN not referenced in any current deployment env.
- AC10. tfstate contains 13 resources imported against new DE org; pre/post manifest diff captured in PR body.
- AC11. 11 scheduled GH workflows successfully post beacons to new DE org (verified via first scheduled run post-merge).

**PR-γ:**

- AC12. US shadow org status documented (free-plan retention until refund processes).
- AC13. Both Sentry support tickets opened with ticket IDs captured in PR body.
- AC14. PA8 §5(2) `<pending C2 merge>` placeholder backfilled with PR-β ref.
- AC15. PIR status flipped to `resolved` with explicit gate-criteria block.
- AC16. W1/W2/W4/W5 follow-up issues filed (W3 marked complete in C5).

## Constraints

- C-1. Art 33 CNIL deadline 2026-05-19T12:50:00Z gates PR-α. Brand_survival_threshold `single-user incident` gates all Branch C PRs at review.
- C-2. R2 backend `use_lockfile = false` — terraform import operations strictly serial (no concurrent runs).
- C-3. `@playwright/mcp@0.0.75` headless-default regression — config-driven headed mode must be verified at C1 start, not assumed.
- C-4. Vendor-relationship preservation: refund posture is amicable-with-receipts; aggressive forensics language confined to Ticket 2 (separate routing).
- C-5. PIR Phase 8 flip is the institutional precedent — gate criteria over-documented in TR4.

## Open Questions (carry-forward to plan time)

See brainstorm "Open Questions" section. Five items: Sentry support response timing, DE org slug availability, source-map orphan, Playwright headed-vs-headless reconciliation, Cloudflare cache purge mechanic.

## Domain Review (carry-forward to plan)

Triad: CPO + CLO + CTO. Brainstorm captures full leader assessments. Plan skill's Phase 2.6 carries forward verbatim.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-16-sentry-residency-a2-branch-c-brainstorm.md`
- PIR: `knowledge-base/engineering/ops/runbooks/sentry-phantom-ingest-destination-unreachable-postmortem.md`
- Cascade learning: `knowledge-base/project/learnings/2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md`
- A1 plan: `knowledge-base/project/plans/2026-05-15-feat-sentry-residency-cleanup-plan.md`
- A1 PR: #3863
- Umbrella: #3861
