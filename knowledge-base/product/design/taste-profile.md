---
last_updated: 2026-10-05
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
{"schema":1,"entries":[{"context":"dashboard","axis":"aesthetic-direction","value":"instrumented-spec","last_reinforced":"2026-09-26","reinforce_count":1},{"context":"app-ui","axis":"aesthetic-direction","value":"single-status-box-fading-trail","last_reinforced":"2026-10-05","reinforce_count":1}],"contradictions":[{"context":"dashboard","axis":"aesthetic-direction","old_value":"workstream-sibling-kanban","new_value":"workstream-inline-crud-optimistic","old_count":1,"date":"2026-07-10"},{"context":"dashboard","axis":"aesthetic-direction","old_value":"workstream-inline-crud-optimistic","new_value":"evidence-before-request-two-zone","old_count":1,"date":"2026-08-06"},{"context":"dashboard","axis":"aesthetic-direction","old_value":"evidence-before-request-two-zone","new_value":"instrumented-spec","old_count":1,"date":"2026-09-26"},{"context":"app-ui","axis":"aesthetic-direction","old_value":"kb-mobile-drill-in","new_value":"reuse-existing-warning-surface-dark","old_count":1,"date":"2026-09-26"},{"context":"app-ui","axis":"aesthetic-direction","old_value":"reuse-existing-warning-surface-dark","new_value":"dark-minimal-existing-chrome","old_count":1,"date":"2026-09-30"},{"context":"app-ui","axis":"aesthetic-direction","old_value":"dark-minimal-existing-chrome","new_value":"single-status-box-fading-trail","old_count":1,"date":"2026-10-05"}]}
```
<!-- taste-profile:data:end -->

## Reinforced Aesthetics

| context | axis | value | last_reinforced | reinforced |
|---|---|---|---|---|
| app-ui | aesthetic-direction | single-status-box-fading-trail | 2026-10-05 | 1 |
| dashboard | aesthetic-direction | instrumented-spec | 2026-09-26 | 1 |

## Contradiction Flags

- 2026-10-05 — `app-ui`/`aesthetic-direction`: `dark-minimal-existing-chrome` (reinforced 1×) superseded by `single-status-box-fading-trail`
- 2026-09-30 — `app-ui`/`aesthetic-direction`: `reuse-existing-warning-surface-dark` (reinforced 1×) superseded by `dark-minimal-existing-chrome`
- 2026-09-26 — `app-ui`/`aesthetic-direction`: `kb-mobile-drill-in` (reinforced 1×) superseded by `reuse-existing-warning-surface-dark`
- 2026-09-26 — `dashboard`/`aesthetic-direction`: `evidence-before-request-two-zone` (reinforced 1×) superseded by `instrumented-spec`
- 2026-08-06 — `dashboard`/`aesthetic-direction`: `workstream-inline-crud-optimistic` (reinforced 1×) superseded by `evidence-before-request-two-zone`
- 2026-07-10 — `dashboard`/`aesthetic-direction`: `workstream-sibling-kanban` (reinforced 1×) superseded by `workstream-inline-crud-optimistic`
