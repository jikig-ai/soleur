---
title: "scheduled-marketplace-drift's Sentry check-in never delivered — the plugin's only distribution alarm was dark from the day it shipped"
date: 2026-08-13
incident_pr: 7504
incident_window: "2026-08-12 (workflow created in #7473, 790dd8227) → 2026-08-13 (fix shipped in #7504)"
recovery_at: "2026-08-13 — the three composite inputs are forwarded; first live check-in expected at the next 06:37 UTC tick"
suspected_change: "#7473 (790dd8227) created .github/workflows/scheduled-marketplace-drift.yml with a sentry-heartbeat step that omitted all three of the composite's `required: true` ingest inputs"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - discovered incidentally while planning #7493 (recorded as plan correction C9)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Why this is filed at all

No user was harmed and no data was exposed. It is filed because the operator's standing rule is
that **any detected incident gets a PIR, including one found incidentally while doing other
work** — and because the failure class is the one this repo keeps paying for: a control that
reports success while doing nothing.

Art. 33/34 are both `false`: this is an availability-of-monitoring defect on a public manifest
watcher. No personal data is processed by the workflow, which reads two public URLs
unauthenticated.

## What happened

`.github/workflows/scheduled-marketplace-drift.yml` is the daily watcher on
`jikig-ai/soleur-marketplace` — the plugin's sole distribution channel. Its final step calls the
`sentry-heartbeat` composite, which is what detects **the job not running at all**: GitHub
disables schedules on repository inactivity and silently drops ticks under load, and a missed
tick leaves no red run to notice.

The composite declares three inputs `required: true` — `sentry-ingest-domain`,
`sentry-project-id`, `sentry-public-key`. The workflow forwarded **none** of them.

Measured on `origin/main` at the time of the fix:

```
git show origin/main:.github/workflows/scheduled-marketplace-drift.yml \
  | grep -c 'sentry-ingest-domain\|sentry-project-id\|sentry-public-key'
0
```

## Root cause

**GitHub Actions does not enforce `required: true` on composite-action inputs.** It is
documentation, not a contract. The composite hit its own empty-guard, printed a `::warning::`,
and exited 0 — so the calling workflow stayed green while the check-in was never delivered.

The workflow's own comment asserted that this step "is also the only mechanism that detects the
job NOT RUNNING AT ALL". That sentence was true of the design and false of the deployment, for
the entire life of the workflow (~1 day).

## Blast radius

Bounded, and smaller than it first looked. The other nine callers of the composite were checked
and **all nine forward all three inputs correctly**:

```
for f in $(grep -rln 'sentry-heartbeat' .github/workflows/); do
  printf '%-52s %s\n' "$(basename $f)" \
    "$(grep -c 'sentry-ingest-domain\|sentry-project-id\|sentry-public-key' "$f")"
done
```

→ every workflow reports 3 (`scheduled-terraform-drift.yml` reports 6: two heartbeat call sites).
So this was a single-caller omission, not a systemic pattern.

What was actually at risk during the window: had the daily drift check silently stopped firing,
nothing would have reported it. The manifest itself was never wrong — verified at fix time,
published is byte-identical to source (`MANIFEST_IN_SYNC`).

## Detection

Not detected by any gate. Found by reading the composite's interface while planning #7493, and
recorded as plan correction C9 before implementation began. No alarm fired, because the alarm was
the thing that was broken — which is the whole point of the failure class.

## Fix

Forward the three values from secrets, mirroring the sibling `scheduled-terraform-drift.yml`
(#7504). Sentry ingest values are public-by-design write-only beacon components, not product
secrets, which is why forwarding them does not change the workflow's gate-override justification
about consuming no product secrets — that clause was reworded in the same PR to say so.

## What would have caught it

Nothing in the repo today asserts that a workflow calling a composite supplies the composite's
`required: true` inputs. That is a mechanically checkable property: parse
`.github/actions/*/action.yml` for `required: true` inputs, then assert every `uses:` call site
passes them. It is the same shape as the unbound-variable lint added in #7504 — a contract the
runtime does not enforce, so a linter must.

This is **not** filed as an action item because it is a *new gate proposal*, not residual work
from this incident, and the repo is under an explicit gate-moratorium posture (see the
net-issue-flow rationale). It is recorded here so the next person to hit this class finds the
analysis rather than re-deriving it.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._

## Related

- #7473 (790dd8227) — created the workflow with the omission
- #7504 / #7493 — repaired it, alongside the marketplace protection work
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — same failure class (a control that reports success while asserting nothing), found four more
  times in the same PR's review
