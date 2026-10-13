# Decision Challenges — feat-one-shot-6636-sentry-alert-migration

Recorded for `ship` to render into the PR body and file as an `action-required` issue (headless plan session — operator not attached, so surfaced here rather than via AskUserQuestion).

## User-Challenge: recommended fix inverts the issue's stated direction

**Class:** user-challenge (per ADR-084 / decision-principles.md). The operator's stated direction is the default; this records where the evidence points elsewhere so the operator can confirm or override.

**Issue #6636 stated direction:** "Full-root migration of all 23 alert resources with careful `terraform state mv` / import" to `sentry_alert`; the provider bump is listed as an "alternative to evaluate."

**Plan's recommended direction:** attempt the **provider bump first** (Option A), and treat the `sentry_alert` migration as a **fallback** (Option B) reached only if a Phase 0 measurement proves no available stable provider version clears the 410.

**Why the inversion:**
1. External research (framework-docs-researcher, 2026-07-17) + the #4610 finding (ADR-031 amendment 2026-05-29) agree that `sentry_alert` — even in the latest stable — **requires `monitor_ids` and has no `project` attribute**. The 23 rules are project-wide issue/frequency alerts bound to no monitor. Migration is therefore a semantic change (synthetic monitor-binding), not a faithful rename, and needs 23× cross-type state surgery (`state mv` is impossible; only `state rm`+`import`).
2. The provider bump is a version-only change: **no state mutation, no resource rewrite, zero risk of dropping a live paging rule** — decisively lower blast radius at the single-user-incident brand-survival threshold.
3. `terraform state mv` as the issue phrases it is mechanically impossible across the two disjoint schemas.

**What could flip it back to migration:** if Phase 0 measurement shows NO available stable `jianyuan/sentry` version reads `sentry_issue_alert` without a 410, Option A is impossible and the plan falls to Option B (fully specified). The 410 is a server-side retirement, so this is a real possibility, not a formality.

**Operator decision requested:** confirm the bump-first ordering, or direct the migration regardless. Absent an override, the plan proceeds bump-first (Option A) with the migration as the measured fallback.
