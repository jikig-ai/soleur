---
title: "{{TITLE}}"
date: {{DATE}}
incident_pr: {{INCIDENT_PR}}
incident_window: "{{INCIDENT_WINDOW}}"
suspected_change: "{{SUSPECTED_CHANGE}}"
brand_survival_threshold: {{BRAND_SURVIVAL_THRESHOLD}}
status: {{STATUS}}
triggers:
{{TRIGGERS_LIST}}
art_33_triggered: {{ART_33_TRIGGERED}}
art_34_triggered: {{ART_34_TRIGGERED}}
art_33_deadline: "{{ART_33_DEADLINE}}"
{{CLASSIFICATION_OVERRIDE_BLOCK}}
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

{{SECRET_LEAK_PREAMBLE}}

## Symptom

{{SYMPTOM}}

## Root-cause hypothesis

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| {{ROOT_CAUSE_HYPOTHESIS}} | TBD | TBD | TBD |

## Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| human | {{DETECTED_AT}} | Incident detected. |

## Recovery verification

TBD — describe the artifact or probe proving recovery. Cite a green workflow run, dashboard screenshot, or query result.

## Follow-ups

- [ ] TBD

## Who was affected (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface:

- Prospect: TBD
- Authenticated app user: TBD
- Legal-document signer: TBD
- Admin via Access: TBD
- Billing customer: TBD
- OAuth installation owner: TBD
