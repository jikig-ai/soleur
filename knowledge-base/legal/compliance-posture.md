---
last_updated: 2026-05-12
---
<!-- 2026-05-11: Compound Promotion Loop (#2720) registered as Active Item with DPIA candidacy note (Art. 35; defer formal assessment 4 weeks). -->

<!-- 2026-05-11: R15 mitigation for #2719 landed via #3543 (ruleset PUT to #14145388) -->
<!-- 2026-05-11: R15 follow-up D1 (#3544) landed — daily bypass_actors audit closes the audit-log-only blind spot in #3543 -->
<!-- 2026-05-11: R15 follow-up D2 (#3545) landed — empirical audit confirmed CodeQL coverage on bot PRs is satisfied (neutral conclusion). No remediation needed. Runbook: knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md -->


# Legal Compliance Posture

Living status document for vendor DPAs, legal documents, and compliance action items. Domain leaders read this during assessment to avoid asserting stale or incorrect status.

## Legal Documents

| Document | Location | Last Updated | Status |
|----------|----------|-------------|--------|
| Terms & Conditions | `docs/legal/terms-and-conditions.md` | 2026-03-20 | Active |
| Privacy Policy | `docs/legal/privacy-policy.md` | 2026-05-12 | Active |
| Cookie Policy | `docs/legal/cookie-policy.md` | 2026-03-20 | Active |
| GDPR Policy | `docs/legal/gdpr-policy.md` | 2026-05-12 | Active |
| Acceptable Use Policy | `docs/legal/acceptable-use-policy.md` | 2026-03-20 | Active |
| Data Protection Disclosure | `docs/legal/data-protection-disclosure.md` | 2026-05-12 | Active |
| Disclaimer | `docs/legal/disclaimer.md` | 2026-03-20 | Active |
| Individual CLA | `docs/legal/individual-cla.md` | 2026-03-20 | Active |
| Corporate CLA | `docs/legal/corporate-cla.md` | 2026-03-20 | Active |

## Vendor DPA Status

Source: `knowledge-base/project/specs/feat-vendor-ops-legal/dpa-verification-memo.md`

| Vendor | DPA Status | Signed/Verified | Transfer Mechanism | Data Region | Notes |
|--------|-----------|----------------|-------------------|-------------|-------|
| Hetzner Online GmbH | SIGNED | 2026-03-19 | N/A (EU-only) | hel1 (Finland) | Covers CX33 (web platform) |
| Supabase Inc | SIGNED | 2026-03-19 | N/A (EU-only) | eu-west-1 (Ireland) | DPA version: August 5, 2025. SCCs Module 2+3. Governing law: Irish. `usage` jsonb column added to `messages` table 2026-05-12 (PR #3648); processing-activity-bound DPA scope covers column-level extensions without re-signing |
| Stripe Inc | AUTO | 2026-03-19 | EU-US DPF + SCCs | US-based | Automatic via Services Agreement. SAQ-A eligible (PCI) |
| Cloudflare Inc | AUTO | 2026-03-19 | DPF + SCCs + CBPR | Global CDN | Self-executing via Self-Serve Agreement |
| Resend Inc | AUTO | 2026-04-13 | DPF + SCCs | US-based | Automatic DPA via Terms of Service (Section 7: Data Processing). Transactional email for review gate notifications |
| Doppler Inc | AUTO (MSA + DPA addendum — verification pending) | 2026-05-05 | EU-US Data Privacy Framework | US-based | Holds GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 (brand-survival credential — single-user incident threshold). RBAC review tracked in #3228. PR #3224 introduces the drift-guard secret; Doppler→GH Actions sync is the documented bootstrap path |
| Google LLC (osv.dev) | AUTO | 2026-05-10 | SCC-equivalent (Google Cloud DPA) | US-based | OSV.dev queried by `skill-security-scan` for supply-chain advisory checks (#2719). Package metadata only (name, ecosystem, version) — never operator-identifying data — is sent. Per gdpr-gate `GDPR-ChapterV-1`. |
| Anthropic PBC | AUTO | 2026-05-11 | SCCs M2+3 + UK IDTA + Swiss Addendum | US-based | DPA effective 2025-02-24 (`https://www.anthropic.com/legal/data-processing-addendum`), auto-incorporated via Commercial Terms § C ("Data Privacy") effective 2025-06-17. SCCs Modules 2+3 per § I.1 (Art. 46 GDPR). Governing law: Irish (DPA § A.1.c). Sub-processors: `https://trust.anthropic.com/subprocessors`. **Scope: Jikigai-keyed Anthropic API surface only** — `claude-code-action` workflows in this repo's CI and the compound-promotion-loop (#2720) clustering job. Plugin/skill invocations under the user's own Anthropic API key are covered by `docs/legal/gdpr-policy.md` § 2.2 (Anthropic acts as independent controller/processor — Soleur does not intermediate). Single-user-incident threshold dependency for #2720 (per #2720 plan AC23/AC26). |

## Vendored Code Provenance

Source: `knowledge-base/engineering/policies/content-vendoring.md`

The `gdpr-gate` skill incorporates upstream-vendored detection rules under permissive license. Each lifted bundle is governed by the content-vendoring policy: pinned to a commit, integrity-checked at pre-commit, drift-detected weekly, and runtime-monitored for staleness (>30d STDOUT banner, >90d POSTURE_FAIL line).

| Upstream | License | Pinned Commit | Lifted Files | Last Verified | Status |
|---|---|---|---|---|---|
| github.com/goSprinto/compliance-skills | MIT | `7b58d68` | 5 (gdpr-gate `references/`) | 2026-05-10 | active |

NOTICE-of-record: `plugins/soleur/skills/gdpr-gate/NOTICE` (YAML frontmatter is the canonical machine-readable form). Drift-detection workflow: `.github/workflows/scheduled-content-vendor-drift.yml`. Operator runbook: `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md`.

## Active Compliance Items

<!--
Row schema (canonical for gdpr-gate critical-finding handshake — operator-acknowledged write only; the gate NEVER writes here directly):

| Item                       | Issue        | Status              | Deadline | Notes                                                            |
|----------------------------|--------------|---------------------|----------|------------------------------------------------------------------|
| <one-line summary>         | #<number>    | OPEN | IN-PROGRESS | <date>   | <check_id from gdpr-gate, e.g. GDPR-Art-9; remediation context>  |

Contract (mirrors plugins/soleur/skills/gdpr-gate/SKILL.md §"Critical-finding escalation flow"):
- The `clo` agent reads this section during legal posture assessments.
- `/soleur:gdpr-gate` Critical findings prompt the operator to (1) `gh issue create --label compliance/critical`, (2) append a row here referencing the issue number + check_id, (3) commit with `compliance: register Art. 9 finding for #<issue>`.
- `/soleur:ship` Phase 5.5 gdpr-gate critical-finding-acknowledgment gate verifies every PR-referenced `compliance/critical` issue has a row here before merge.
- Status moves OPEN → IN-PROGRESS → resolved (move to Completed Compliance Work).
-->

| Item | Issue | Status | Deadline | Notes |
|------|-------|--------|----------|-------|
| T&C blanket statement contradictions | #736 | OPEN | - | Identified during #670 review |
| Skill-install advisory gate | #2719 | OPEN | - | Single-user-incident threshold; EU jurisdiction. Verdict naming `LOW-RISK \| REVIEW \| HIGH-RISK` with mandatory advisory disclaimer (CLO requirement). Override = structured artifact under `knowledge-base/security/skill-overrides/` (GDPR Art. 32 evidence; retention = repo lifetime). PII redaction (email/IPv4/IBAN) at scan time per `GDPR-DataMin-1`. Self-defense: SHA-pinned rule pack, OSV untrusted-input handling, fail-loud self-test. R15 mitigation landed via #3543 on 2026-05-11 — `skill-security-scan PR gate` is a required check on the `CI Required` ruleset (#14145388); admin-merge bypass auto-files a `compliance/critical` issue via post-merge audit. R15 follow-up D1 landed via #3544 on 2026-05-11 — daily audit compares live `bypass_actors` to `scripts/ci-required-ruleset-canonical-bypass-actors.json` (24h worst-case detection window) and files a `compliance/critical` issue routed to CLO + CPO on drift. Runbook: `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`. |
| Compound Promotion Loop (Layer 2 self-healing) | #2720 | OPEN | - | Single-user-incident threshold. Default OFF; opt-in via `knowledge-base/project/promotion-config.yml`. Plan-time gdpr-gate findings folded as AC23/AC26/AC27 (Anthropic DPA row required pre-merge — tracked in #3594; DPIA candidacy LC-04; synthesized-PII fixtures). **DPIA candidate (Art. 35)** — defer formal assessment until first 4 weeks of operation generate empirical data (cluster count, false-positive rate, operator merge ratio). Re-evaluate at week-4 review. Append-only audit log: `knowledge-base/project/learnings/promotion-log.md`. Runbook: `knowledge-base/engineering/ops/runbooks/compound-promote-runbook.md`. |
| Anthropic processor DPA row missing from Vendor DPAs | #3594 | OPEN | - | Pre-existing systemic gap (applies to every `claude-code-action` workflow, gdpr-gate skill, compound-promotion-loop). Blocks #2720 ship (AC23). Operator-action: verify DPA at Anthropic Console, add row to Vendor DPA Status table, open PR citing #3594 + #2720. |

## Completed Compliance Work

| Item | Issue/PR | Completed | Notes |
|------|----------|-----------|-------|
| W7 DSAR cohort audit (cc-soleur-go disclosure-asymmetry window) | #3603 / PR #3662 | 2026-05-12 | Backward-looking Art. 15 cohort audit for window 2026-05-05 → 2026-05-11 (PR #3286 first ship through PR-A1 AC11 verification). Four channels: GitHub `label:legal` (programmatic), `legal@jikigai.com` inbox + Linear `Art. 15 OR DSAR` + Discord support (operator-manual completeness flags). **Result: zero Art. 15 / DSAR requests in window.** No supplementary disclosure required. Evidence: `knowledge-base/legal/audits/2026-05-12-w7-dsar-cohort-audit.md` (load-bearing per CLO Q4 — null result is the audit answer). Operator-amendment posture documented for post-merge discovery. |
| `CC_PERSIST_USAGE=true` operator decision + PR-C disclosure-side close | #3603 / PR #3662 | 2026-05-12 | Operator confirmed at PR-C plan-time that the flip to `CC_PERSIST_USAGE=true` in both `prd` and `prd_scheduled` Doppler configs was a **deliberate decision** taken with PR-C disclosure in flight — not a flag-flip-by-mistake. PR-C #3662 closes the disclosure side: Privacy Policy §4.7, DPD §2.3(i), GDPR Policy §3.7 + §10 #10 each carry the `usage` jsonb disclosure. SIGKILL persistence-limitation transparency sentence added to Privacy §4.7 (and Notes in GDPR §10 #10) with cross-reference from Privacy §8.1. Not an Art. 33-notifiable incident; planned-and-known operator-decision audit trail. Re-evaluation deferred to post-OP3 (after umbrella close). |
| Supabase DPA update (Braintrust sub-processor) | #1056 / PR #1298 | 2026-04-07 | Supabase confirmed (Tracy Lane, 2026-04-07): Braintrust tracing disabled for EU-hosted projects (eu-west-1). No cross-border transfer. No data sent to Braintrust. No re-signing required — existing DPA (signed 2026-03-19) remains in effect. Sub-processor accepted via Section 6.5 notification mechanism. |
| Web platform vendor DPA review | #670 / PR #732 | 2026-03-18 | All 4 vendor DPAs signed/verified. Expense ledger updated. Legal docs updated |
| Vendor checklist gate added | #670 / PR #732 | 2026-03-18 | PR template and constitution updated with vendor compliance section |

## How to Update This Document

- When a DPA is signed, updated, or revoked: update the Vendor DPA Status table
- When a new compliance item arises: add to Active Compliance Items with issue reference
- When a compliance item is resolved: move from Active to Completed
- Update `last_updated` frontmatter date on every change
