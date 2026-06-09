---
title: "{{TITLE}}"
date: {{DATE}}
incident_pr: {{INCIDENT_PR}}
incident_window: "{{INCIDENT_WINDOW}}"
recovery_at: "{{RECOVERY_AT}}"
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

# Incident Overview

{{INCIDENT_OVERVIEW}}

## Status

{{STATUS}} — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

{{SYMPTOM}}

## Incident Timeline

- **Start time (detected):** {{DETECTED_AT}}
- **End time (recovered):** {{RECOVERY_AT}}
- **Duration (MTTR):** {{MTTR}}

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| human | {{DETECTED_AT}} | Incident detected. |

## Participants and Systems Involved

{{PARTICIPANTS}}

## Detection (+ MTTD)

- **How detected:** {{DETECTION_METHOD}} — monitoring system vs. external/manual report.
- **MTTD (mean time to detect):** {{MTTD}}

## Triggered by

{{TRIGGERED_BY}} — one of user / system / market movement / provider.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| {{ROOT_CAUSE_HYPOTHESIS}} | TBD | TBD | TBD |

## Resolution

{{RESOLUTION}}

## Recovery verification

TBD — describe the artifact or probe proving recovery. Cite a green workflow run, dashboard screenshot, or query result.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

{{ROOT_CAUSE_5WHYS}}

## Versions of Components

- **Version(s) that triggered the outage:** {{VERSION_TRIGGERED}}
- **Version(s) that restored the service:** {{VERSION_RESTORED}}

## Impact details

### Services Impacted

{{SERVICES_IMPACTED}}

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: TBD
- Authenticated app user: TBD
- Legal-document signer: TBD
- Admin via Access: TBD
- Billing customer: TBD
- OAuth installation owner: TBD

### Revenue Impact

{{REVENUE_IMPACT}}

### Team Impact

{{TEAM_IMPACT}}

## Lessons Learned

### Where we got lucky

{{LUCKY}}

### What went well

{{WENT_WELL}}

### What went wrong

{{WENT_WRONG}}

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `_No action items — incident fully resolved in the source PR with no residual work._` (the only permitted no-item form).

| Issue | Action | Status |
|---|---|---|
| #{{ACTION_ITEM_ISSUE}} | {{ACTION_ITEM_DESC}} | open |
