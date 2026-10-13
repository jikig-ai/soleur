---
feature: action-required escalation staleness contract
lane: cross-domain
brand_survival_threshold: single-user incident
supersedes_issue: 6769
status: draft
date: 2026-07-22
---

# Spec: `action-required` Escalation Staleness Contract

## Problem Statement

The `action-required` label is the agent pipeline's escalation channel to the
non-technical operator. Its oldest items have a ~0% resolution rate (30 open, oldest
131 days). The issue (#6769) hypothesized the channel is a write-only sink and that
`operator-digest` Section 4 (which harvests it) had never run. **Investigation
disproved that hypothesis** and root-caused four independent failures — see
`knowledge-base/project/brainstorms/2026-07-22-action-required-staleness-contract-brainstorm.md`:

1. **Delivery:** weekly digests #1–#7 are filed with `assignees=[]` — the operator is
   never notified; the #8 `--assignee` delivery probe failed.
2. **Presentation:** Section 4 renders a flat, age-blind, priority-blind, uncapped list.
3. **Routing:** `decision-challenge` + content chores are double-stamped
   `action-required`, polluting the harvest until the reader skims all of it.
4. **Lifecycle:** no SLA / escalation / expiry — structurally-dead chores never age out.

The channel is **load-bearing** (`scheduled-inngest-health.yml:853`) and partially
drains (57 closed). This is a staleness-contract problem, not a replace-the-label problem.

## Goals

- **G1.** Every weekly digest reliably **reaches and notifies** the operator.
- **G2.** Section 4 makes **age and priority legible per item**; oldest/SLA-breaching
  items surface first; the tail is capped.
- **G3.** The harvest is **de-polluted** — only true only-you-can-do asks appear.
- **G4.** Aged items **escalate**; structurally-dead classes **auto-expire**; genuine
  ops/infra asks are **never auto-closed**.
- **G5.** SLA breaches **self-report** via a monitored `SOLEUR_*` marker.

## Non-Goals

- Replacing or renaming `action-required` (it is load-bearing; the finer taxonomy
  already exists).
- Auto-closing genuine ops/infra escalations (explicitly out of scope — risk knob set
  to "expire dead classes only").
- Changing what upstream watchdogs *detect* (only how their output is labeled/aged).
- Any UI surface (this is digest markdown + labels + cron only).

## Functional Requirements

- **FR1 (Delivery).** The `operator-digest` workflow assigns each digest issue to the
  operator and produces a notification. Fix the failing `--assignee` path (#8 probe);
  confirm the private-repo workflow token can assign. If assignee-notify is
  insufficient, add a push channel. *(Ships first.)*
- **FR2 (Render).** Rewrite `operator-digest/SKILL.md` §4 harvest to fetch
  `title,url,createdAt,labels`, sort by (priority, age desc), render a **"🔴 oldest /
  SLA-breaching"** block with **per-item age in days**, and cap the remainder as "+N more".
- **FR3 (De-pollute).** Define the stricter harvest predicate (e.g. `action-required
  AND NOT (decision-challenge OR content*)`). Update every producer that double-stamps
  `action-required` on those classes so the label means "only-you-can-do" again.
- **FR4 (Lifecycle cron).** A scheduled workflow that, per open `action-required` item:
  escalates its priority label as age crosses class thresholds; **auto-expires
  structurally-dead classes only** (content-publishing chores past N days → close as
  stale + re-route to a distribution backlog, mirroring `content-starvation`); leaves
  all other classes open; emits a `SOLEUR_*` stdout marker on SLA breach.
- **FR5 (Backfill).** One-time triage of the current 30: expire the 6 dead content
  chores, drop the 13 decision-challenges from the harvest, retain the ~11 genuine asks.

## Technical Requirements

- **TR1.** `operator-digest` scheduling lives in the **private** `jikig-ai/operator-digest`
  repo (`operator-digest.yml`); the public render/skill lives in `soleur`. Changes span
  both — sequence accordingly.
- **TR2.** Lifecycle cron home: default to public `soleur/.github/workflows/scheduled-*.yml`
  (co-located with the producers it must re-label and the other watchdogs). Confirm at plan.
- **TR3.** Close-authority must be **fail-safe**: the auto-expire path operates on an
  allowlist of dead classes, never a denylist — an unclassified item is never closed.
- **TR4.** SLA marker follows the `SOLEUR_*` stdout → Vector allowlist convention so it
  reaches Better Stack (`hr-no-dashboard-eyeball-pull-data-yourself`,
  `cq-silent-fallback-must-mirror-to-sentry`).

## Open Questions (carry to /plan)

- Q-A: concrete SLA day-thresholds per class (escalate/expire windows).
- Q-B: is `--assignee` + GH notification enough, or is a push channel needed?
- Q-C: exact harvest predicate + full list of double-stamping producers.
- Q-D: lifecycle cron home (public vs private repo).
- Q-E: backfill executed as part of this feature or as a follow-up.

## Acceptance Criteria

- The next weekly digest is assigned to the operator and notifies them.
- Section 4 shows per-item age; the oldest genuine ask sorts to the top; the tail is capped.
- No `decision-challenge`/content item appears in Section 4's action list.
- A content chore past threshold is auto-closed-with-reason; a genuine ops item past
  threshold is escalated but left open.
- An SLA breach appears in Better Stack via a `SOLEUR_*` marker.
