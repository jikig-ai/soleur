# Learning: "channel nobody reads" is a claim to root-cause, not a framing to accept

## Problem

Issue #6769 reported that `action-required` — the agent pipeline's operator
escalation label — had a ~0% resolution rate on its oldest items (30 open, oldest
131 days) and hypothesized it was a **write-only sink** whose harvesting digest
(`operator-digest` Section 4) had probably never run. The framing invited two wrong
responses: file a 30th escalation, or sweep-close the 29 — both "treat the symptom."

## Solution

Root-cause the delivery chain before accepting the sink framing. The cheap check
(does the harvesting component actually RUN?) **disproved the premise** and relocated
the failure to four downstream layers:

1. **Delivery** — the weekly digest was filed into the OWNING (separate, private)
   repo `jikig-ai/operator-digest` with `assignees=[]` on issues #1–#7, so the
   operator was never notified. Verified: `gh issue list -R <repo> --json assignees`.
   A dedicated `--assignee` delivery probe (#8) had already been filed and **failed**.
2. **Presentation** — Section 4's harvest was `gh issue list --label action-required
   --json title,url`: no sort, no age, no priority, no cap. A 131-day chore rendered
   identical to a P0. Age was invisible.
3. **Routing** — items that already had their own labels (`decision-challenge`,
   `content*`) were ALSO stamped `action-required`, so 19 of 30 open items were noise
   that trained the reader to skim the whole list.
4. **Lifecycle** — no SLA / escalation / auto-expiry; structurally-dead chores (manual
   social posting a non-technical operator will never do) never aged out.

Design chosen: a four-layer staleness contract (delivery fix → triage render →
de-pollute → SLA lifecycle with auto-expiry of dead classes only), NOT a
replace-the-label refactor — the label is load-bearing (`scheduled-inngest-health.yml:853`
picks it *because* the digest harvests only it) and partially drains (57 closed).

## Key Insight

When an issue names a component as "the likely single point of failure" for a
channel "nobody reads," check whether it actually **runs** — pull workflow-run
history from the **owning** repo (which may be a separate, private repo the public
repo only references) — BEFORE designing around the assumed failure. A channel that
**delivers-but-is-ignored** has a completely different fix (triage + delivery +
de-pollute) than one that **never fires**. Two high-signal, low-cost probes:

- `gh run list -R <owning-repo>` — is the harvester actually green on a cadence?
- `gh issue list -R <repo> --json assignees` — `assignees=[]` on notification-style
  issues is a silent delivery failure: the artifact exists, nobody is pinged.

Also: a partially-draining backlog (many closed, oldest rotting) is not a dead
channel — it is an **untriaged** one. The rot concentrates in structurally-dead
classes (chores the actor cannot/will not do) mixed into the same undifferentiated
list as genuine emergencies.

## Session Errors

- **Assumed #6769 was OPEN when linking artifacts; it was CLOSED (COMPLETED by the
  operator 2 days prior, during the delivery-probe cleanup).** Recovery: the
  brainstorm's closed-`#N` path — created a superseding tracking issue (#6836) with
  "Supersedes closed #6769" and cross-commented the closed issue. Prevention: already
  covered by brainstorm Phase 3.6 (validate each `#N` via `gh issue view --json state`
  before use); no workflow change needed. One-off.

## Tags
category: workflow-patterns
module: brainstorm, operator-digest, action-required
issue: 6769, 6836
