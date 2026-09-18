---
title: "scheduled-marketplace-drift's Sentry check-in never delivered — the plugin's only distribution alarm was dark from the day it shipped"
date: 2026-08-13
incident_pr: 7504
incident_window: "2026-08-12 (workflow created in #7473, 790dd8227) → 2026-09-18 (PR #8313: the composite resolves through a self-repository reference)"
recovery_at: "2026-09-18T15:33:26Z"  # measured: Sentry cron monitor check-in id a2e141b4-03d7-4f83-8801-3669ddee2f71 via GET /monitors/scheduled-marketplace-drift/checkins/ (status ok, environment production; the first row the monitor ever recorded)
suspected_change: "#7473 (790dd8227) created .github/workflows/scheduled-marketplace-drift.yml with a sentry-heartbeat step that omitted all three of the composite's `required: true` ingest inputs"
brand_survival_threshold: single-user incident
status: resolved  # amended 2026-09-18 — the 2026-08-13 repair did not recover the monitor; see the AMENDED banner
triggers:
  - discovered incidentally while planning #7493 (recorded as plan correction C9)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

> **AMENDED 2026-09-18.** The recovery this document claimed did not happen. `recovery_at` was
> written as an expectation ("first live check-in expected at the next 06:37 UTC tick") with no
> probe behind it, and the expectation was false for 36 more days.
>
> **Claimed:** forwarding the three composite inputs (PR #7504) restored the check-in.
> **Measured (2026-09-18):** all 36 scheduled runs after that repair — run 31782063181 on
> 2026-08-14 through run 35341073667 on 2026-09-18 — carry the runner line `Can't find
> 'action.yml', 'action.yaml' or 'Dockerfile' under '…/.github/actions/sentry-heartbeat'. Did you
> forget to run actions/checkout before running your local action?` in the `drift-check` job;
> 33 of 36 concluded `success`. `GET /monitors/scheduled-marketplace-drift/checkins/` returned
> `[]` at 2026-09-18T14:54:55Z while the monitor itself existed (`status: active`, created
> 2026-08-12T17:40:50Z). The monitor had never recorded a check-in.
>
> **Mechanism:** `drift-check` is deliberately checkout-free, and a `uses: ./…` action resolves
> from the runner's workspace, which that job never populates. The step was
> `continue-on-error: true`, so the resolution error became a green step. The 2026-08-13 repair
> fixed the FIRST cause (inputs not forwarded) and could not see the second: its verification
> read the step and run conclusion, which `continue-on-error` guarantees green regardless.
>
> **Dark window, restated:** 2026-08-12 (monitor created) → 2026-09-18T15:33:26Z — 37 days, of
> which 36 followed a PIR that recorded the incident as resolved.
>
> **Fix (PR #8313):** the step references the composite through GitHub's self-repository form
> `$/.github/actions/sentry-heartbeat`, which the runner downloads from this repository at the
> running commit during `Set up job` — no checkout, and a resolution failure now fails the job
> loudly instead of being swallowed. The first branch dispatch also surfaced that the archive
> extraction that form depends on failed on two committed dangling-symlink fixtures
> (`test/fixtures/orphan-proc-dangling/4242/{cwd,fd/255}`); they were removed in the same PR.
> The composite's curl now prints `sentry-heartbeat: http_code=<n>` so a step log evidences
> delivery. **Guard:** `scripts/lint-workflow-local-action-checkout.py` (unit + live pair in
> `scripts/test-all.sh`) refuses any `./` step with no preceding `actions/checkout` in its job.
>
> **What `recovery_at` now records:** the first check-in row, produced by a `workflow_dispatch`
> of PR #8313's branch (run 35361236920, `drift-check` log: 0 resolution errors,
> `sentry-heartbeat: http_code=202`), read back from the monitors API — measured, not expected.
> `main` stayed dark until that PR merged; the `main`-ref check-in is evidenced by AC16's row in
> the PR body, not here.

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

**Second gap (added 2026-09-18).** Nothing asserted that a `uses: ./…` step is preceded by an
`actions/checkout` in the same job — the property the AMENDED banner's mechanism violates. That
gap is now closed, not proposed: `scripts/lint-workflow-local-action-checkout.py` walks every
job of every workflow and every composite's `runs.steps`, and its `-live` arm runs in the
`scripts` shard on every PR. A third gap is the one this amendment itself corrects: a PIR
`recovery_at` written as a future expectation is not a measurement. Recovery is evidenced by
the affected path's own telemetry — here, a row from the monitors API — or it is not recorded.

## Action Items & Follow-ups

*No action items — incident fully resolved by PR #8313 (2026-09-18; the source PR #7504 did not recover the monitor — see the AMENDED banner); no residual work.*

## Related

- #7473 (790dd8227) — created the workflow with the omission
- #7504 / #7493 — forwarded the inputs, alongside the marketplace protection work (did not
  recover the monitor — see the AMENDED banner)
- PR #8313 (2026-09-18) — the actual recovery: self-repository reference, composite `-w` line,
  the local-action-checkout lint, the dangling-fixture removal, and this amendment
- The 2026-09-18 devin-docs-drift repair — the same class in a sibling workflow, repaired by
  adding a checkout; its learning:
  `knowledge-base/project/learnings/2026-09-18-local-composite-action-needs-checkout-continue-on-error-masks-it.md`
- #8282 — the sibling `scheduled-devin-docs-drift` monitor does not exist in Sentry (infra apply
  failed), so that repair's ingest 2xx proved nothing: an ingest 2xx is necessary, not sufficient
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — same failure class (a control that reports success while asserting nothing), found four more
  times in the same PR's review
