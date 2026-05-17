---
date: 2026-05-16
topic: sentry-residency-a2-branch-c
status: complete
worktree: .worktrees/feat-sentry-residency-a2-branch-c-1
branch: feat-sentry-residency-a2-branch-c-1
draft_pr: "#3904"
parent_issue: "#3861"
related_issues:
  - "#3861"  # umbrella
  - "#3863"  # A1 (merged 2026-05-15)
  - "#3904"  # this draft PR
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
triad: [cpo, clo, cto]
---

# Brainstorm: Sentry Residency Cleanup A2 — Branch C (new DE org from scratch)

A2's original framing ("align tfstate to existing DE org, rotate token, re-apply") was invalidated by a 3-premise cascade documented in `knowledge-base/project/learnings/2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md`. Branch C restarts with the correct premise: **there is no controllable jikigai org on EU/DE; one must be created from scratch on `eu.sentry.io`** and the runtime DSN + 7+ secret surfaces must be atomically migrated to it. A 49-day phantom-ingest window (PIR `sentry-phantom-ingest-destination-unreachable-postmortem.md`) is the active driver.

## User-Brand Impact

**Artifact:** Sentry destination cluster — runtime `SENTRY_DSN` + `NEXT_PUBLIC_SENTRY_DSN` + `SENTRY_CSP_REPORT_URI` + `SENTRY_AUTH_TOKEN` + cron-checkin secrets triple + PA8 §5(2) sub-processor entry.

**Vector (all 4 operator-selected at Phase 0.1):**
- Phantom-ingest reopen: new DE org's DSN written but events never arrive (gate failure).
- Half-state DSN split during atomic swap: prod surfaces split-emit (web client → old, server → new) fragmenting traces of a live prod incident.
- Audit gate misconfigured: gate green but admin-controllability not actually verified, masking next residency drift identically to the original failure mode.
- Atomic-swap data loss: prod error fires into a now-revoked DSN before propagation completes; single user hits the bug; the supporting telemetry is gone.

**Threshold:** `single-user incident`. Forward-looking — the PIR's `brand_survival_threshold: none` downgrade applies only to the historical window (10 operator-adjacent accounts existed 2026-03-28 → 2026-05-16, all under operator instruction or contractual relationship per PR-α SQL-count + operator categorization on 2026-05-17; zero arms-length external signups). Every Branch C PR is the remediation that determines whether the **next** arms-length signup hits a clean DE residency story or a half-state. All Branch C PRs carry this threshold in frontmatter and trigger user-impact-reviewer at review time.

## Lane

`cross-domain`. CPO + CLO + CTO triad required (CLO load-bearing for PA8 §5(2) disclosure + PIR Phase 8 closure; CTO for cluster surgery + audit-gate mechanic; CPO for sequencing under Art 33 deadline). USER_BRAND_CRITICAL=true forces this lane independent of keyword inference.

## What We're Building

A 3-PR series under sibling worktrees `feat-sentry-residency-a2-branch-c-{1,2,3}`:

- **PR-α (this worktree, draft #3904) — legal+docs deadline gate.** C6 PA8 §5(2) phantom-ingest disclosure (CLO-signed, with `<pending C2 merge>` placeholder) + C7 ADR-031 stale-URL fix (`de.sentry.io/settings/account/api/auth-tokens/` → 404; ingest cluster has no settings UI) + ingest/dashboard/API host glossary. Ships Sun 2026-05-17 or Mon 2026-05-18. **Satisfies the Art 33 procedural gate (deadline 2026-05-19).**

- **PR-β (new sibling `-2`) — runtime atomic swap + IaC + audit-gate extension.** C1 Playwright-driven DE org provision (operator at keyboard for credentials; headed-config enforced via persistent profile per `2026-05-15-playwright-mcp-headed-and-persistent-profile.md` reconciled with today's `--headless` default regression) + C2 expanded atomic swap across all 7+ secret surfaces (see "Key Decisions" Q3 for full inventory) + C3 token mint (verify probe targets `eu.sentry.io/api/0/users/me/`, NOT de.sentry.io) + C4 tfstate drop + manifest-capture-then-reimport + C5 audit-gate triple-expansion. Ships next week, no deadline pressure.

- **PR-γ (new sibling `-3`) — cleanup + vendor relationship.** C8 US shadow org teardown + 2 separate Sentry support tickets (per CLO: ticket 1 billing-only refund "Team trial activated in error"; ticket 2 forensics-only org-ID owner-history) + C2-backfill of C6's `<pending C2 merge>` placeholder with actual PR-β ref + W1-W5 workflow improvements filed as issues. Ships when refund processes.

## Why This Approach

Three load-bearing reasons the dialogue converged here:

1. **C9 ruled out by probe (~5 min this session, well under the 30-min cap).** Sentry Relocation is real but doesn't apply: covers self-hosted→SaaS only, requires owner access on source install (we don't have it on phantom org 4511…), regenerates DSNs anyway, no cross-region SaaS migration documented. All 5 candidate API endpoints returned 404 on both eu and us edges. No `sentry-cli relocation` subcommand. The US cancellation page's "migrate to another existing account" prompt is — as CTO predicted with 85% confidence — billing/subscription-transfer theater (sales-assisted plan move between same-cluster orgs), not cross-cluster destination migration.

2. **C6 is the deadline-driven artifact, not C2 (CPO).** Art 33 obligation is disclosure-of-known-facts, not remediation-complete. CLO can sign off an interim PA8 §5(2) update with `<pending C2 merge>` placeholder by Sun-Mon, satisfying the procedural CNIL gate independently of runtime swap risk. Bundling forces same-day legal review of a 4-secret-store atomic-swap PR — strongly not advisable given today's cascade-learning context.

3. **Write-new-everywhere-then-revoke-old with 2-hour observation window is the right half-state mechanic (CTO).** Dual-DSN feature-flag rollout requires `sentry.{client,server}.config.ts` code changes + deploy = exactly the half-state surface A1's guard was designed to prevent. Atomic-Doppler-only swap is brittle because Vercel envs propagate per-deploy not per-push — they will drift. Write-new-then-revoke gives a verification window where the new org receives events and audit-script-C5 can run green before the old token dies; 2h is enough for one synthetic + one real event without burning PAYG meaningfully. Hard-gate revoke behind audit-script green against new org.

## Key Decisions

| # | Decision | Why | When |
|---|---|---|---|
| 1 | **3-PR series, PR-α (legal+docs) ships first by 2026-05-18** | Art 33 deadline is procedural-disclosure-driven, not remediation-driven. Decouples CLO sign-off from runtime risk. CPO recommendation; CLO concurs. | PR-α: 2026-05-17/18. PR-β: next week. PR-γ: when refund processes. |
| 2 | **C9 (Sentry Relocation) ruled out** | Probed this session — self-hosted→SaaS only, no cross-region SaaS, no API endpoints exist, doesn't preserve DSNs anyway. Manual swap is the only path. | Closed within brainstorm; no follow-up issue needed. |
| 3 | **C2 scope expanded to 7+ secret surfaces (vs original 4)** | Repo-research uncovered 4 surfaces missing from original feature description: (a) cron-checkin secrets triple `SENTRY_INGEST_DOMAIN`+`SENTRY_PROJECT_ID`+`SENTRY_PUBLIC_KEY` consumed by 11 scheduled GH workflows (each posts beacons to the org — today they post to phantom); (b) `SENTRY_URL`/`SENTRY_API_HOST` env for sentry-cli in `reusable-release.yml` + Dockerfile build-args (currently absent, defaults US, will silently target wrong region on new DE org); (c) CSP `report-uri` swap requires Cloudflare edge cache purge after Doppler/Vercel propagation; (d) source-map artifacts on phantom org are orphaned debug evidence — PIR notes pre-swap errors cannot be symbolicated post-swap. All 4 mechanically required for atomic swap. | All in PR-β. |
| 4 | **Half-state guard: write-new-then-revoke with 2h observation window** | NOT dual-DSN feature flag (deploy half-state surface). NOT atomic-Doppler-only (Vercel envs drift). NOT 24h window (excessive). 2h = one synthetic + one real event observation without meaningful PAYG burn. Revoke hard-gated on audit-script-C5 green against new org. | C2 mechanic; CTO recommendation. |
| 5 | **C5 audit-gate expanded to 3 sub-gates** | Org-reachability (`/api/0/organizations/$SENTRY_ORG/ → 2xx`) proves admin reachability but NOT write authority. Add project-scope probe (`/projects/$ORG/$PROJECT/ → 2xx`) and write-probe (POST release create + DELETE) to prove `project:releases` scope works end-to-end. CI on every diff touching `sentry.*.config.ts | next.config.ts (Sentry block) | infra/sentry/**/*.tf | .github/workflows/*sentry*` paths-filtered. CTO recommendation. | C5 in PR-β. |
| 6 | **Brand-survival threshold `single-user incident` for all Branch C PRs** | Forward-looking — PIR's `none` is backward-looking only. The four operator-selected failure modes all describe forward harms to future users (the next signup hits the swap-window state). All Branch C PRs carry this threshold and trigger user-impact-reviewer. CPO recommendation. | All 3 PRs frontmatter. |
| 7 | **PIR Phase 8 (status: open → resolved) flip gate: C2 + C5 + Sentry-support-response-OR-T+14d-timeout** | Three conditions must all hold: (a) C2 lands (no further phantom emission), (b) C5 lands (audit gate prevents recurrence), (c) Sentry support responded on org 4511… OR 14 calendar days elapsed since ticket open. Submit-and-accept, not submit-and-pray — residual documented as "unknown — Sentry support response of `<date>`: `<verbatim>`" if they decline. CLO recommendation. | PIR update lives in PR-γ alongside C8. |
| 8 | **PA8 §5(2) disclosure wording (CLO drafted)** | Paragraph appended to recipient cell (does NOT replace it). Acknowledges the window without misrepresenting blast radius (no external subjects). References new DE org via `<pending C2 merge>` placeholder pre-C2, backfilled in PR-γ. Describes audit gate as drift-detection control, not continuous-controllability guarantee. Full text in PR-α commit. | C6 in PR-α. |
| 9 | **Refund posture: 2 tickets, amicable-with-receipts (CPO+CLO converged)** | Ticket 1 (billing-only, no compliance language): "Team trial activated in error during IaC misconfiguration, requesting prorated refund of $5.46 PAYG + unused Team prorate." Ticket 2 (forensics-only, separate routing): "Requesting owner-history confirmation for org ID 4511123328466944 to close an internal Article 30 sub-processor audit." Asymmetry resolved by not asking same Sentry support agent to weigh both. Vendor-relationship-preserving (we'll continue using `eu.sentry.io` post-Branch-C). | PR-γ + operator-driven ticket submission. |
| 10 | **Art 33 CNIL filing: defer, file only if Sentry support confirms org 4511… is third-party-owned OR by 2026-05-18T12:50:00Z (T-24h buffer)** | Breach-element under Art 4(12) is unconfirmed pending forensics. WP29 Guidelines 250 require "reasonable degree of certainty" of unauthorized access for the awareness clock; we have certainty of mis-routing only. File-with-recovery-in-flight is the correct sequence if filing is warranted. CLO recommendation. | Operator-driven, gated on Sentry support T-24h. |
| 11 | **Internal disclosure to operator-as-data-subject: PIR is disclosure of record, plus one Article 30 §5(2) cross-reference** | Under self-controller-self-processor framing, PIR (committed, dated, signed via git authorship) satisfies Art 34 "clear and plain language" communication. No separate notification. Add one-line cross-reference in `knowledge-base/legal/compliance-posture.md` under "Active Compliance Items" — creates auditable trail without parallel document drift. CLO recommendation. | PR-α. |
| 12 | **tfstate strategy: drop entirely + manifest-capture + serial re-import** | Pre-flight manifest captured via existing audit script. With `use_lockfile = false` on R2 backend, two concurrent `terraform import` runs would race silently — sequence strictly serial. Cross-org-address translation as plan-time state mv is more failure surface than clean drop+re-import. Loss risk: monitor `slug` references in alert filters (capture in pre-drop manifest, post-import diff). CTO + repo-research consensus. | C4 in PR-β. |

## Open Questions (resolved at plan time)

- **Sentry support response timing.** Ticket 2 (forensics) might never get an authoritative answer. T+14d documented timeout is the practical ceiling.
- **DE org name collision.** New org slug on `eu.sentry.io` — is `jikigai` available, or do we need `jikigai-eu` / `jikigai-de`? Plan-time check via Playwright. Cascading rename through 11 scheduled workflows + Terraform `var.sentry_org` default if not `jikigai`.
- **Source-map artifact orphan window.** Pre-swap prod errors symbolication is lost when phantom-org 49-day retention expires (~2026-07-04 by today + 49d). Acceptable risk per CTO and CPO; PIR documents.
- **Playwright headed-vs-headless reconciliation.** `2026-05-15-playwright-mcp-headed-and-persistent-profile.md` assumes headed via `--user-data-dir`; today's session proved `@playwright/mcp@0.0.75` ignores that and spawns `--headless`. PR-β plan-time TR: verify `.mcp.json --config` flag + persistent-profile path actually take effect at C1 start.
- **Cloudflare cache purge mechanic.** Per-zone vs per-URL purge for CSP `report-uri` header — verify which the operator's Cloudflare plan supports. Plan-time TR.

## Domain Assessments

**Assessed:** Engineering (CTO), Legal (CLO), Product (CPO). Operations + Marketing + Sales + Finance + Support not assessed (cross-domain lane scoped to triad per USER_BRAND_CRITICAL + feature description requirement).

### Engineering (CTO)

**Summary:** Manual swap is the only viable shape (C9 ruled out by probe). Half-state guard: write-new-everywhere → 2h observation → audit-script-green → revoke old. Audit gate must expand to 3 sub-gates (reachability + project-scope + write-probe) running in CI on Sentry-touching paths AND at deploy. tfstate drop+reimport with pre-flight manifest. Five engineering gaps in C1-C9: sentry-cli `SENTRY_URL` injection, audit-script region-probe loop, CSP edge-cache purge, source-map orphan disclosure, project-slug default in Terraform.

### Legal (CLO)

**Summary:** Art 33 filing deferred pending Sentry support response (T-24h buffer 2026-05-18T12:50Z). PA8 §5(2) disclosure drafted (appended to recipient cell, `<pending C2 merge>` placeholder). PIR Phase 8 gate = C2 + C5 + Sentry-response-OR-T+14d. PIR satisfies Art 34 self-subject disclosure; cross-ref only. Refund split into 2 tickets (billing-only + forensics-only) to isolate decision surfaces.

### Product (CPO)

**Summary:** 3-PR series with PR-α (legal+docs) shipping first as deadline gate. C6 not C2 is the Art-33-driven critical path. `single-user incident` threshold load-bearing for forward-looking Branch C (PIR's `none` is backward-looking only). Amicable-with-receipts refund posture preserves vendor relationship on the org we're about to depend on. C9 probe first 30-min capped (already executed: ruled out).

## Capability Gaps

Each gap below cites evidence (specific grep / find / API probe). Bare assertions are research misses, not gaps.

1. **No prior PIR Phase 8 precedent.** Evidence: `grep -r "art_33_triggered: true" knowledge-base/engineering/ops/runbooks/` returns only today's PIR; `grep -r "status: resolved" knowledge-base/engineering/ops/runbooks/` returns no incident with the recovery-completeness flow. The PIR Phase 8 recovery-completeness gate is being defined for the first time by Branch C (per learnings-researcher finding 6). **Implication:** Branch C's flip-criteria block becomes the institutional precedent — over-document, not under-document.

2. **No prior wording precedent for after-the-fact residency-drift §5(2) disclosure.** Evidence: `grep -rn "after-the-fact\|drift\|phantom" knowledge-base/legal/article-30-register.md` returns no matches; closest adjacent is `2026-03-18-dpd-sub-processor-contradiction-fix.md` (audit-all-sections-for-contradictions pattern, not drift wording). CLO's drafted text in Decision #8 is first-of-its-kind. **Implication:** CLO sign-off in PR-α is load-bearing for both this PR and the wording precedent inherited by every future drift disclosure.

3. **No prior atomic cross-store secret-rotation playbook.** Evidence: `find knowledge-base/project/learnings -iname "*rotation*"` returns none direct; adjacents are `2026-05-15-token-namespace-divergence-across-secret-stores.md` (namespace drift only, not rotation playbook) and `2026-03-25-doppler-secret-audit-before-creation.md` (pre-creation audit only). C2's 7-surface atomic swap with write-new-then-revoke + 2h-observation is also first-of-its-kind. **Implication:** plan-time C2 TR section must include explicit sequencing-and-rollback playbook that becomes the precedent for future cross-store rotations.

## Productize Candidates

None identified. Branch C is a one-shot residency-cleanup remediation. The W1-W5 workflow improvements from the cascade learning are deferred follow-up issues, not productize candidates.

## Workflow Improvements Deferred (W1-W5 from cascade learning)

To be filed as 4 atomic GH issues in PR-γ:

1. **W1** — new hard rule `hr-prereq-playwright-first-then-credential-handoff` (AGENTS.core.md).
2. **W2** — extend `soleur:brainstorm` Phase 1.0.5 premise check to named URL substrings (not just numerical claims).
3. **W3** — extend `apps/web-platform/scripts/sentry-monitors-audit.sh` with `audit_destination_admin_controllable` gate. **Absorbed into Branch C as C5** — no separate issue needed.
4. **W4** — `worktree-manager.sh feature` optionally copies `--config=playwright-headed.json` into worktree `.mcp.json` under `SOLEUR_PLAYWRIGHT_HEADED=1` env gate.
5. **W5** — `/soleur:compound` fail-friendly when on main (offer to create worktree rather than hard-abort).

## References

- **PIR:** `knowledge-base/engineering/ops/runbooks/sentry-phantom-ingest-destination-unreachable-postmortem.md`
- **Today's cascade learning (load-bearing):** `knowledge-base/project/learnings/2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md`
- **A1 plan:** `knowledge-base/project/plans/2026-05-15-feat-sentry-residency-cleanup-plan.md`
- **A1 PR:** #3863 (merged v3.94.8 / web-v0.87.9 on 2026-05-15)
- **Umbrella:** #3861
- **ADR-031 (target of C7):** `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`
- **Authoritative learnings:**
  - `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`
  - `2026-05-15-token-namespace-divergence-across-secret-stores.md`
  - `2026-05-15-sentry-iac-billing-and-quirks.md`
  - `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`
  - `2026-05-15-playwright-mcp-headed-and-persistent-profile.md`
  - `2026-05-12-playwright-mcp-isolated-flag-wipes-oauth-sessions.md`
