---
title: "Decision challenges — #6588 legal half"
issue: 6588
date: 2026-07-24
---

# Decision Challenges — #6588 legal half

## DC-1 — The retained-plaintext disclosure: challenge raised, operator reaffirmed the HOLD

**Date:** 2026-07-24
**Classification:** User-Challenge (ADR-084) — **raised and resolved IN FAVOUR of the
operator's existing position.** This is an *acceptance* record, not a reversal record.
**Status:** CLOSED — hold reaffirmed. Residual accepted and tracked on **#6808**.

> **Why this record exists at all.** A challenge that resolves *for* the operator is the one
> nobody writes down. Without this file, a knowingly-retained live over-claim is
> indistinguishable from one nobody noticed. The point of the record is that the exposure is
> traceable to a decision, a date, and a tracking issue.

### (i) The prior decision — the UC-3 hold (PR #6918)

PR #6918 (merged 2026-07-24 17:55 CEST) ran `/soleur:legal-audit`, which found a **material
over-claim of the #6588 class**: `hcloud_volume.workspaces` (plain ext4,
`apps/web-platform/infra/server.tf:1569`) holds a full copy of every workspace as of the
2026-07-23 cutover, ATTACHED-UNMOUNTED and UN-WIPED, retained as the ADR-119 rollback backstop.
The ledger states the exposure in its own words:

> `does_not_defend: "a seized/snapshot disk exposes any workspace data still resident on this volume."`

The operator **HELD** the copy fix (UC-3), reasoning that **Path 1** (infra teardown — wipe the
volume) will cure it and is already tracked, rather than **Path 2** (qualify the published
wording). The auditor's Path-2 wording was preserved verbatim for later use. Recorded in
`knowledge-base/project/learnings/2026-07-24-holding-a-live-overclaim-pending-infra-teardown-and-drain-can-mean-keep-open.md`.

### (ii) The revisit-trigger analysis, as put to the operator (2026-07-24)

UC-3 states its own revisit condition: *"If the teardown slips materially, revisit Path 2."*
Measured this session:

- The teardown is blocked on **#6808** (OPEN) — `WORKSPACES_LUKS_HEARTBEAT_URL` is unwired, so
  `luks-monitor.sh` runs, succeeds, and pushes nothing.
- `workspaces-luks-soak-6604.sh` gates on the heartbeat being **present** with rows spanning
  **≥ 7 days**. With the URL unwired, **the ADR-119 soak clock has not started.**
- No soak ⇒ no Phase-5 plaintext wipe ⇒ the residual stays live.
- Earliest possible cure is therefore **"#6808 fix + 7 days"**, with **no committed date** for
  either leg. That is a material slip, and it was knowable on 2026-07-24.
- Secondary point put alongside it: this PR is already rewriting those exact sentences, so the
  marginal cost of the Path-2 wording would have been one clause rather than a fresh legal-doc
  edit.

### (iii) The operator's decision — REAFFIRM THE HOLD

Presented with the analysis in (ii), the operator on **2026-07-24 reaffirmed the UC-3 hold** and
directed that the **blocker be escalated instead**. No affirmative disclosure sentence about the
retained pre-cutover plaintext volume ships in this PR.

The operator did **not** decline the finding. They chose **Path 1 (cure the reality)** over
**Path 2 (qualify the words)**.

### (iv) The CLO's contrary recommendation — RECORDED AS OVERRIDDEN, NOT DELETED

The `soleur:legal:clo` domain review (blocking, invoked at plan time) **recommended** the
affirmative disclosure and **would have blocked without it** (block **B1**). Its reasoning is
preserved in full, because an accepted residual must remain visible:

- **Arts. 13/14** are *not* the source of the duty — TOMs are not an enumerated limb, and a
  transient storage-media state is operational detail outside them.
- **Art. 32(1)** is substantive, not publicational; it creates no disclosure duty.
- **Art. 5(2)** is already discharged internally by the ledger row and the Art. 30 register.
- **What decided it for the CLO was the #6588 over-claim standard itself.** *"Stored workspace
  git data sits on a LUKS-encrypted volume"* is read by any ordinary user as a statement about
  **their data**, not about **one volume**. A full un-wiped copy on a seizable disk defeats
  precisely the threat the sentence advertises — and Soleur has that admission in writing in its
  own ledger.
- The correct anchors, per that review, are **Art. 12(1) + 5(1)(a)** (not Art. 13(3), which the
  #6588 premise table already found wrong for this class) — noted so the deferred Path-2 edit
  does not propagate a loose citation.

**Disposition: B1 was OVERRIDDEN by operator decision on 2026-07-24.** This is a recorded
exception, not a re-ruling — the CLO's position above is unamended. Blocks **B2, B3 and B4
stand** and are cured in this PR.

### (v) The accepted residual, and where it is tracked

**Tracking issue: #6808.**

The re-scoped LUKS clause ships while a full un-wiped plaintext copy of every workspace remains
on `hcloud_volume.workspaces`. Its plain reading is broader than the infrastructure earns, and
**users are not told**. This is an **accepted, undisclosed residual** — accepted, not unnoticed.

What bounds it today:

- **Zero arms-length data subjects** (#3723 OPEN) — the volume holds the operator's own
  dogfooding workspaces, so no data subject has yet been misled.
- The residual is **ledgered** (`scripts/encryption-posture-ledger.json`,
  `hcloud_volume.workspaces`, `mechanism: plaintext-exception`, `tracking_issue: "#6897"`,
  `expires_on: 2026-10-22` — an **internal** commitment, never published) and named in
  `knowledge-base/legal/article-30-register.md`.
- **#6808 is escalated by this PR** to `priority/p1-high` + `type/security`, with a comment
  recording that it now gates a *live published over-claim* rather than only a monitoring gap.

**Escalation trigger, recorded now so it is not re-derived later:** if **#3723** onboards a
first arms-length user while **#6808** is still open, this becomes **p0** and the hold must be
re-raised.

### Why `p1-high` and not `p0-critical` on #6808

`p0-critical` reads *"drop everything"*, which is the opposite of the decision the operator just
made (hold and proceed), and it is not earned on the facts — zero arms-length data subjects
today. `p1-high` (*"degraded functionality, no workaround"*) is exact: there is no workaround for
a soak clock that cannot start.

### What this PR does NOT do

- It does **not** add any disclosure sentence, clause, or scope-to-live qualifier to
  `docs/legal/**` or the Eleventy mirrors. **AC4** asserts that absence mechanically, in both
  directions (absolute, and no-added-line in the diff).
- It does **not** fix #6808, run the soak, or wipe the plaintext volume — that is infra work,
  out of scope for a PR declaring `runtime_deploy_risk: none`.
- It does **not** close **#6897** (`Ref`, never `Closes`) — closing it would orphan the live
  ledger `tracking_issue: "#6897"` rows and the `model.c4` refs.

The Path-2 wording preserved for whoever writes it after #6808 clears is quoted in the plan
(§3b) **for that future edit only**. Pasting it into a legal document in this PR violates AC4.
