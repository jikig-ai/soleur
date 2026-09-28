# Follow-up issue body — status page discoverability

Deferred from #9168 during brainstorm on 2026-09-28.

Mandated-By: wg-when-deferring-a-capability-create-a

User-Impact: a visitor hitting a down app.soleur.ai has no way to self-check
whether the outage is ours — the status page exists but nothing user-facing
links to it.
Fix-Size: ~10 lines / 2 files (a footer or error-page link).

## What was deferred

`https://soleur-ai.betteruptime.com/` is live (confirmed 2026-09-28 — it
recorded the 09-28 outage as "Down for 39 minutes") but no surface on
soleur.ai or app.soleur.ai links to it. Add a discoverable link (marketing
footer and/or the app's signed-out error state).

## Why deferred

#9168 is scoped to paging + recovery; a link change is a UI surface edit that
would pull the wireframe gate into an infra PR for near-zero coupling.

## Re-evaluation criteria

Any time the marketing footer or app error states are next touched; or
immediately if a user reports confusion during an outage.
