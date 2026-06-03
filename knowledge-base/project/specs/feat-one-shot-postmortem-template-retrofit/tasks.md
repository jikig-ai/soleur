---
title: "Tasks: Merge richer PIR template structure and retrofit existing post-mortems"
plan: knowledge-base/project/plans/2026-06-03-feat-pir-template-merge-and-retrofit-plan.md
branch: feat-one-shot-postmortem-template-retrofit
lane: cross-domain
---

# Tasks — PIR template merge + retrofit

Derived from `2026-06-03-feat-pir-template-merge-and-retrofit-plan.md`. Phase
order is load-bearing (see plan "Phase Order"). Token set lives in THREE places
(template / SKILL.md Phase 4 table / dry-run heredoc) — move all three together.

## Phase 1 — Template (declares the token contract)

- 1.1 Edit `plugins/soleur/skills/incident/templates/pir.md`: merge the new
  sections per the plan "Merged Template Design" (sections 4-20), preserving
  ALL existing machinery (GDPR frontmatter, Actor key, `{{SECRET_LEAK_PREAMBLE}}`,
  triage hypothesis table, Recovery verification, 6 role-impact rows).
- 1.2 Add the new `{{TOKEN}}`s: `{{INCIDENT_OVERVIEW}}`, `{{RECOVERY_AT}}`,
  `{{MTTR}}`, `{{MTTD}}`, `{{PARTICIPANTS}}`, `{{DETECTION_METHOD}}`,
  `{{TRIGGERED_BY}}`, `{{RESOLUTION}}`, `{{ROOT_CAUSE_5WHYS}}`,
  `{{VERSION_TRIGGERED}}`, `{{VERSION_RESTORED}}`, `{{SERVICES_IMPACTED}}`,
  `{{REVENUE_IMPACT}}`, `{{TEAM_IMPACT}}`, `{{LUCKY}}`, `{{WENT_WELL}}`,
  `{{WENT_WRONG}}`, `{{ACTION_ITEMS}}`.
- 1.3 Rename "Who was affected (by role)" → "Customer Impact (by role)" (keep
  the 6 role rows; do NOT add a second free-text Customer Impact block).
- 1.4 Status section reads from frontmatter `status:` — no new token.

## Phase 2 — SKILL.md (consumes the token set)

- 2.1 Edit `plugins/soleur/skills/incident/SKILL.md` Phase 4 table: add one row
  per new token (plan "New substitution tokens" table).
- 2.2 Phase 0 capture: add operator-supplied fields (`incident_overview`,
  `participants`, `detection_method`, `triggered_by`, `resolution`,
  `services_impacted`, `revenue_impact`, `team_impact`, `version_triggered`,
  `version_restored`) + ISO-8601-validated `recovery_at` / `monitoring_detected_at`.
- 2.3 Phase 0 "Compute locally" block: add MTTR/MTTD `date -u -d` epoch
  subtraction (FR7), with the empty-`recovery_at` → `TBD` guard and the
  external/manual → `Unknown` guard.
- 2.4 LLM-trust-boundary section: add the new operator-prose tokens to the
  sed-escape + first-pass-sentinel enumeration.
- 2.5 Do NOT edit `description:` (verify word budget unaffected).

## Phase 3 — Fixtures + dry-run heredoc (consumes both)

- 3.1 Add the new fields to `test/fixtures/dry-run-incident.json` (synthetic).
- 3.2 Add the new fields to `test/fixtures/dry-run-secret-leak.json` (synthetic).
- 3.3 Edit `scripts/dry-run.sh`: parse new fixture fields; compute MTTR/MTTD;
  emit the new template sections in the Phase 4 here-doc so the draft mirrors
  the new template shape.
- 3.4 Fix the stale `runbooks/${slug}-postmortem.md` → `post-mortems/` string
  at `dry-run.sh:282`.
- 3.5 Run both dry-runs; iterate until exit 0 with no raw `{{` in output (AC5/AC7).

## Phase 4 — Retrofit the 3 non-baseline PIRs

- 4.1 Retrofit `chat-rls-workspace-id-outage-postmortem.md` (plan §B).
- 4.2 Retrofit `soleur-ai-marketing-site-cloudflare-526-...-postmortem.md` (plan §D).
- 4.3 Retrofit `sentry-phantom-ingest-...-postmortem.md` LIGHT (plan §C —
  preserve Phase 8/9 + existing tables verbatim).
- 4.4 Per file: preserve every existing frontmatter field; fill gaps with
  `Unknown`/`N/A` + one-line reason; never fabricate.

## Phase 5 — Retrofit the baseline LAST + verify

- 5.1 Retrofit `dashboard-error-postmortem.md` (plan §A) — the anchor + sentinel
  negative-baseline. Do NOT introduce any email/UUID/IPv4/real-token shape.
- 5.2 Run `redact-sentinel.sh` against the file → confirm exit 0.
- 5.3 Run `redact-sentinel.test.sh` → `Total: N pass, 0 fail` (AC4).

## Phase 6 — Final verification (Acceptance Criteria)

- 6.1 AC1/AC2 grep checks on `pir.md` (existing machinery + new headings present).
- 6.2 AC3 bidirectional `comm` diff (template tokens ↔ SKILL.md Phase 4 table)
  returns empty.
- 6.3 AC5/AC6/AC7 dry-run checks (both fixtures, headings present, no raw `{{`,
  secret-leak preamble still fires).
- 6.4 AC8 per-PIR frontmatter preservation diff.
- 6.5 AC9 anchor reference in `SKILL.md:20` unchanged.
- 6.6 AC10 `bun test plugins/soleur/test/components.test.ts` passes.
- 6.7 AC11 no `runbooks/.*postmortem` string remains in `dry-run.sh`.
- 6.8 Run `code-review` skill on the diff before PR.
