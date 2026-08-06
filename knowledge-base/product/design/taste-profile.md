---
last_updated: 2026-08-06
last_reviewed: 2026-07-05
review_cadence: quarterly
owner: CPO
---
# Design Taste Profile

Learned operator design preferences, keyed by `(context, axis)` and ordered by
recency. Loaded into design sessions via FR6 (`frontend-design` skill `context_queries`)
and a direct Read (`ux-design-lead` agent). See ADR-090.

<!-- Machine block owned by plugins/soleur/scripts/taste-profile-update.sh — do not hand-edit. -->
<!-- taste-profile:data:start -->
```json
{"schema":1,"entries":[{"context":"app-ui","axis":"aesthetic-direction","value":"kb-mobile-drill-in","last_reinforced":"2026-08-03","reinforce_count":1},{"context":"dashboard","axis":"aesthetic-direction","value":"evidence-before-request-two-zone","last_reinforced":"2026-08-06","reinforce_count":1}],"contradictions":[{"context":"dashboard","axis":"aesthetic-direction","old_value":"workstream-sibling-kanban","new_value":"workstream-inline-crud-optimistic","old_count":1,"date":"2026-07-10"},{"context":"dashboard","axis":"aesthetic-direction","old_value":"workstream-inline-crud-optimistic","new_value":"evidence-before-request-two-zone","old_count":1,"date":"2026-08-06"}]}
```
<!-- taste-profile:data:end -->

## Reinforced Aesthetics

| context | axis | value | last_reinforced | reinforced |
|---|---|---|---|---|
| dashboard | aesthetic-direction | evidence-before-request-two-zone | 2026-08-06 | 1 |
| app-ui | aesthetic-direction | kb-mobile-drill-in | 2026-08-03 | 1 |

## Contradiction Flags

- 2026-08-06 — `dashboard`/`aesthetic-direction`: `workstream-inline-crud-optimistic` (reinforced 1×) superseded by `evidence-before-request-two-zone`
- 2026-07-10 — `dashboard`/`aesthetic-direction`: `workstream-sibling-kanban` (reinforced 1×) superseded by `workstream-inline-crud-optimistic`
