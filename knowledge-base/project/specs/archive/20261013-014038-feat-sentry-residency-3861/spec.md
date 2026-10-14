---
feature: sentry-residency-3861
status: spec
brand_survival_threshold: single-user incident
lane: cross-domain
triggering_issue: "#3861"
brainstorm: knowledge-base/project/brainstorms/2026-05-15-sentry-residency-cleanup-brainstorm.md
related_plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
related_adr: knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md
---

# Spec — Sentry Residency Cleanup

## Problem Statement

Article 30 register PA8 (§(d), §(e), Vendor DPAs table L208) asserts Sentry is processed in DE region (Functional Software GmbH, intra-EU, no third-country transfer). The committed AC14 migration-audit artifact at `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` records `API host: sentry.io` and lists 8 cron monitors — supposedly serving as Article 30 §5(2) accountability evidence. The two claims contradict on their face.

Live probe results:

- Production DSN: `o4511123328466944.ingest.de.sentry.io` — region-bound org-id. All user-event ingest is on DE.
- AC14 audit artifact captured a US-side `jikigai` *shadow org* where IaC accidentally provisioned monitors, because `reusable-release.yml:308` defaults `SENTRY_API_HOST: ${{ secrets.SENTRY_API_HOST || 'sentry.io' }}`.

No personal data was transferred to US. Article 33 clock does NOT trigger. The register's factual DE claim is correct; its supporting accountability evidence is wrong-shape and regenerates incorrectly each release.

## Goals

- G1: Stop wrong-shape §5(2) accountability evidence from regenerating on each release.
- G2: Align IaC tfstate at `apps/web-platform/infra/sentry/` with the canonical DE cluster.
- G3: Produce a corrected §5(2) accountability artifact from the DE cluster.
- G4: Preserve the existing AC14 artifact for audit-trail integrity (append a timestamped correcting note; do NOT rewrite or delete).
- G5: Keep all public-facing legal corpus (Privacy Policy, DPD, GDPR Policy, Eleventy mirrors, Article 30 register §(d) and §(e)) factually unchanged — they are already correct.
- G6: Catch this class of bug at preflight/ship in the future via a productized DSN-vs-register residency check (filed as a separate follow-up issue).

## Non-Goals

- Public-facing legal corpus edits.
- Article 33 notification to a supervisory authority.
- Counsel review.
- Modifying ADR-031 prose (executes ADR-031; does not amend it).
- Generalized residency-vs-runtime check in `gdpr-gate` (defer to a second concrete instance).
- Re-architecting IaC root layout (single shared root vs per-region).
- Cleaning up the `SENTRY_API_TOKEN` (Doppler postmerge) vs `SENTRY_AUTH_TOKEN` (GitHub IaC) name divergence — separate housekeeping.
- Adding a code-side throw on DSN cluster mismatch (config-driven log+skip only).

## Functional Requirements

- **FR1 (Phase A1):** `reusable-release.yml:308` default flips `'sentry.io'` → `'de.sentry.io'`. GitHub repo secret `SENTRY_API_HOST` retains override semantics for any future legitimate migration.
- **FR2 (Phase A1):** `apps/web-platform/scripts/sentry-monitors-audit.sh:45` probe order reverses to `for candidate in de.sentry.io sentry.io`.
- **FR3 (Phase A1):** Audit-script frontmatter emits `**Region URL:** <links.regionUrl from /organizations/{org}/>` alongside the existing `**API host:**` line — authoritative residency signal independent of host used.
- **FR4 (Phase A1):** `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` gains a timestamped correcting note explaining the wrong-cluster shadow IaC capture. The original content remains intact for audit-trail integrity.
- **FR5 (Phase A1):** `knowledge-base/legal/compliance-posture.md` gains an entry under Completed Work documenting probe + reframing + remediation outcome.
- **FR6 (Phase A1):** Article 30 register PA8 §(c)(iv) gains a clarifying parenthetical: cron check-ins as "workflow slug + status + ISO timestamp — operational metadata, not Art. 4 personal data".
- **FR7 (Phase A2 prereq, operator-only):** Operator adds a payment method to `jikigai` org on `de.sentry.io`, enables PAYG with ≥ 8 cron seats. Verified via `GET https://de.sentry.io/api/0/customers/jikigai/`.
- **FR8 (Phase A2 prereq, operator-only):** Operator mints a fresh DE-scoped `SENTRY_AUTH_TOKEN` (internal-integration token from `de.sentry.io`).
- **FR9 (Phase A2):** `terraform state rm` removes the 12 US-side resources (4 `sentry_issue_alert.*` + 8 `sentry_cron_monitor.*`) from tfstate. State-rm only — no API delete.
- **FR10 (Phase A2):** ACK-gated direct-API delete of US shadow-org monitors and alerts using a separate US-scoped token (not persisted to Doppler).
- **FR11 (Phase A2):** Doppler `prd` `SENTRY_AUTH_TOKEN` + GitHub repo secret `SENTRY_AUTH_TOKEN` rotate to the DE token from FR8.
- **FR12 (Phase A2):** `apply-sentry-infra` workflow run against DE imports/creates the 12 resources cleanly.
- **FR13 (Phase A2):** A new audit artifact `knowledge-base/legal/audits/sentry-migration-audit-<post-fix-date>.md` is regenerated against DE and committed as the live §5(2) evidence.
- **FR14 (Phase A2, optional, < 20 LOC budget):** Config-driven residency guard in `apps/web-platform/sentry.{client,server}.config.ts` gated on `SENTRY_RESIDENCY_EXPECTED=de` env; on DSN cluster mismatch, log to stderr and skip init (do NOT throw). If LOC budget exceeded, defer to a separate follow-up.

## Technical Requirements

- **TR1 — Ordering invariant:** FR1 lands in the merge BEFORE FR9–FR12. A state-rm + apply against the stale workflow default would re-bind to US.
- **TR2 — Ordering invariant:** FR9 lands BEFORE FR10. Reverse order means the next terraform plan sees drift and recreates US resources.
- **TR3 — Operator-gate sentinel:** FR7 + FR8 + FR10 are operator-only per `hr-never-label-any-step-as-manual-without` case (d) (payment) and `hr-menu-option-ack-not-prod-write-auth` (destructive API). Plan must surface these as explicit ACK gates, not CI automation.
- **TR4 — Reversibility:** FR9 (state-rm) is reversible via `terraform import`. FR10 (API delete) is irreversible; place it AFTER explicit ACK and AFTER state-rm.
- **TR5 — GDPR-gate:** PR touches the §5(2) accountability artifact path named in Article 30 PA8's last line. `/soleur:gdpr-gate` runs at PR time per `hr-gdpr-gate-on-regulated-data-surfaces`.
- **TR6 — Env-wiring verification (FR14):** Before merging FR14, verify `SENTRY_RESIDENCY_EXPECTED` reaches the container at boot via `apps/web-platform/Dockerfile` ARG + Doppler injection, or the guard silently no-ops.
- **TR7 — Audit-script tolerance:** Between FR9 and FR12, an interim audit run against DE returns zero monitors. Confirm `sentry-monitors-audit.sh` fail-closed posture per the `2026-05-04` learning is the desired behavior in that window, or scope a temporary skip.

## Sharp Edges (carry from brainstorm)

- Workflow default flip BEFORE state surgery. State-rm BEFORE API delete.
- `links.regionUrl` is region-bound — frontmatter records BOTH host queried AND claimed `regionUrl`.
- Token namespace divergence (Doppler `prd` `SENTRY_AUTH_TOKEN` ≠ GH repo secret `SENTRY_AUTH_TOKEN` ≠ Doppler `SENTRY_API_TOKEN`) — Phase A2 rotates two; third is housekeeping.
- Pre-existing internal split: `oauth-probe-failure.md` already defaults DE; only the workflow flips in this PR.

## Acceptance Criteria

- **AC1:** `reusable-release.yml` default for `SENTRY_API_HOST` is `'de.sentry.io'` post-merge.
- **AC2:** `sentry-monitors-audit.sh` probes DE-first; frontmatter includes both `**API host:**` and `**Region URL:**` fields.
- **AC3:** `audits/sentry-migration-audit-2026-05-15.md` is preserved unchanged BELOW a new appended `## Correction (YYYY-MM-DD)` section.
- **AC4:** Article 30 register PA8 §(c)(iv) carries the clarifying parenthetical; §(d) + §(e) + Vendor DPAs table unchanged.
- **AC5:** `compliance-posture.md` Completed Work entry exists; references this brainstorm + #3861.
- **AC6 (Phase A2):** `terraform plan` against `apps/web-platform/infra/sentry/` shows zero drift on DE post-cutover.
- **AC7 (Phase A2):** New audit artifact `audits/sentry-migration-audit-<post-fix-date>.md` exists with `**Region URL:** https://de.sentry.io` and an 8-monitor inventory matching `cron-monitors.tf`.
- **AC8 (Phase A2, optional FR14):** Boot of the web-platform with intentionally-misaligned DSN logs a stderr warning and skips Sentry init, gated on `SENTRY_RESIDENCY_EXPECTED=de`.
- **AC9:** `/soleur:gdpr-gate` runs against the PR diff and surfaces no critical findings.

## Open Questions (carry from brainstorm)

- Are US shadow-org monitors currently billed (active) or stuck disabled? Affects teardown cost.
- GitHub repo secret rotation lag — same PR or operator-prereq?
- Audit-script behavior between FR9 state-rm and FR12 apply (zero monitors on DE) — fail-closed or temporary-skip?
