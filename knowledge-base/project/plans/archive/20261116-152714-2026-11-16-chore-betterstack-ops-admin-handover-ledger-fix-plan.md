---
title: "chore(infra): hand the Better Stack ops@ team member to the vendor web app and correct the Better Stack cost record"
type: chore
date: 2026-11-16
slug: chore-betterstack-ops-admin-handover-ledger-fix
branch: feat-one-shot-betterstack-ops-admin-handover
issue: none
closes: none
priority: p2
domain: engineering, operations, finance
brand_survival_threshold: none
pr: 12813
lane: cross-domain
# lane: no spec.md exists for this one-shot branch, so the lane fails closed to cross-domain.
---

# chore(infra): hand the Better Stack ops@ team member to the vendor web app and correct the Better Stack cost record

## Enhancement Summary

**Deepened on:** 2026-11-16
**Sections enhanced:** 5 (Research Insights, Files to Edit 2, Infrastructure (IaC), Guard Contract, Sharp Edges)
**Research agents used:**

- soleur:engineering:infra:terraform-architect, which ran a scratch-root `fmt` and a forget-plan experiment on TF 1.9.8 and ran the census read-only;
- a verify-the-negative and post-edit self-audit grep pass (general-purpose);
- the deepen halt gates 4.6–4.13, run mechanically.

### Key Improvements

1. Ran a forget plan on a scratch root. With the address targeted it plans `["forget"]` and `0 to destroy`. Without it in `-target`, the state entry stays. This confirms the kept `-target`.
2. Ran census Guard 4 read-only: 422 passed, G4a at 9 blocks. The 9 → 10 expectation holds.
3. All nine content anchors the plan quotes match exactly once. The P4 sweep now excludes post-mortems, matching the prose.

### New Considerations Discovered

- The provider's `Read` still runs on the forgotten address during the plan. A 404 drops the entry (no change). *(Superseded: see the 2026-11-16 Addendum at the end of this plan.)* Any other error, such as a 5xx or a 401/403, fails the whole per-merge plan. AC13 covers the token. A 5xx is transient, and a re-run recovers.
- Census G4b only reads steps containing a literal `terraform apply`. The saved-plan step qualifies only because of an `::error::` echo line. G4b also merges the target lists across steps, so mutation row 6 rests on FIX B (c) alone.
- Between the merge and the forget applying, the scheduled drift job (a full plan with no `-target`) would show the forget and exit 2. The per-merge apply on the same push closes that window.

## Overview

On 2026-11-16 the Better Stack org was changed through the vendor's web app. `ops@jikigai.com` is now
the org's only **Admin**. `jean.deruelle@jikigai.com` is **Billing admin**, a role that is not billed.
`harry@soleur.ai`, a free Member, was removed. The responder usage page reads "1 out of 2 licenses
used". Cutting the license count from 2 to 1 is a pending billing decision for the operator, and it
is not part of this PR.

Two records are now wrong:

1. **Terraform.** `apps/web-platform/infra/uptime-alerts.tf` still declares
   `resource "betteruptime_team_member" "ops"` with `role = "responder"`. The per-merge apply job
   targets it through `-target=betteruptime_team_member.ops`. The provider,
   BetterStackHQ/better-uptime 0.20.17, manages **non-admin** members only.
2. **Expense ledger.** `knowledge-base/operations/expenses.md` books the $68.00 on the "Better
   Stack" row as an unverified paid logs plan, and the "Better Stack Responder (DEFERRED)" row says
   the seat was declined. The 2026-11-14 invoice shows that the $68.00 is two Responder licenses.

The plan makes four changes:

- Replace the resource with a `removed { lifecycle { destroy = false } }` block, so that Terraform
  forgets the member and never deletes it.
- Rewrite the one test that pins the old resource.
- Split the two Better Stack ledger rows to match the invoice lines.
- Add short dated notes to the docs whose statements are now false. No ADR decision is rewritten.

This PR touches no Better Stack live state. On the vendor side, the merge's only effect is the forget
that the per-merge apply plans, and a forget changes Terraform state only.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified 2026-11-16) | Plan response |
|---|---|---|
| "the next apply of this root would fail or try to revert ops@ to Responder" | **Partly wrong.** In provider source v0.20.17 (`internal/provider/resource_team_member.go`), `role` has a `DiffSuppressFunc` that returns `true` whenever the resource has an ID, and the resource has **no `UpdateContext`**. A role revert is therefore never planned. The real hazards are two. **(a)** `Read` does `GET /api/v2/team-members?email=…` and calls `SetId("")` on a 404. That forces a CREATE: a `POST` invite with `role = responder` sent for the Admin's email. **(b)** Deleting the block **without** a `removed` block plans `DELETE /api/v2/team-members?email=ops@jikigai.com`, which removes the org's only Admin. | The `removed { destroy = false }` block closes both hazards. Its comment names the DELETE hazard, so nobody later "simplifies" the block away. |
| "verify … TF >= 1.7" | The root sets `required_version = ">= 1.7"` (`main.tf`). CI pins `TERRAFORM_VERSION: "1.10.5"` in `apply-web-platform-infra.yml`, `infra-validation.yml` and `scheduled-terraform-drift.yml`. | Use `removed`. No state-rm fallback is needed. |
| "Check whether any test … asserts on this resource" | Exactly one test does: the describe `"betteruptime_team_member.ops is a per-merge -targeted managed resource (FIX B)"` in `plugins/soleur/test/terraform-target-parity.test.ts`. It asserts that the resource exists, that a per-merge job targets it, and that it is not an `OPERATOR_APPLIED_EXCLUSION`. A second, existing guard will police the new block: Guard 4 of `tests/scripts/test-infra-privileged-tier-census.sh`. Its G4a check requires every `removed` block to have a `from` and `destroy = false`. G4b requires the address to be in the root's `-target` list. G4c flags a resource that exists at the merge-base but was deleted with no `removed` block. Kieran's read-only run was green: "9 blocks over 69 .tf files". | Rewrite the FIX B describe, and rely on census Guard 4 for the shape of the `removed` block. See the Guard Contract. |
| (implied) the workflow's `-target` line goes away along with the resource | The repo's precedent is to **keep** it: `doppler-write-token.tf`, `github-app.tf`, `inngest-host.tf` (the #8754 attachment forget), `tunnel.tf` and `web-host-birth-environment.tf`. Under `-target`, a `removed` block is planned only when its address is targeted. Once the forget has applied, the line is an inert tombstone. | Keep `-target=betteruptime_team_member.ops` in the `apply` job's saved-plan command. |
| "$68 … logs tier" | The invoice puts the $68.00 on the line "Responders" (PAYG) for 2 licenses. Logs are a separate $0.60 PAYG line. | Split the rows by invoice line (CTO ruling, below). |

## Research Insights

**Premise validation.** No GitHub issue is cited. Every path the brief cites exists on `origin/main`
in this worktree:

- `uptime-alerts.tf`: the `resource "betteruptime_team_member" "ops"` block, plus its detached
  comment header `# ── Better Stack managed alert recipient: ops@jikigai.com`.
- `expenses.md`: both Better Stack rows.
- ADR-260, ADR-298 and `cost-model.md`.

The collision check came back clean. `gh pr list --state open --search "betteruptime_team_member"`
and `"Better Stack expenses"` both return nothing, and draft PR #12813 is this branch.

**Property list (Phase 0.6b).**

- P1: Terraform no longer claims to manage ops@, and the next apply can neither delete nor re-invite it.
- P2: CI goes red before merge if a later edit brings back a managed ops@ member or drops the forget.
- P3: The ledger states what Better Stack bills today, line by line, and the overdue estimate marker
  is resolved.
- P4: Every doc found by the sweep below gets a dated correction:
  - docs that call the Responder seat "declined" or "not purchased";
  - docs that call ops@ a Terraform-managed responder.

  Sweep command, re-run at work time:
  `git grep -n -i 'betteruptime_team_member\|responder seat\|responder tier\|responder-tier' -- knowledge-base apps/web-platform/infra ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings' ':!knowledge-base/project/brainstorms' ':!**/archive/**' ':!**/post-mortems/**'`.
  At deepen time (2026-11-16), every hit mapped to Files to Edit 1, 3 or 5–11. `cost-model.md`
  (item 6) is found by `still declined` rather than by the sweep terms.

  The sweep excludes post-mortems on purpose, because they are point-in-time records.

**Cut list.**

- **`terraform state rm`**, the brief's fallback. `removed` works on TF 1.10.5 and is the repo's
  reviewed route. A state-rm happens outside PR review, and the block, still declared, would
  re-create the member.
- **`lifecycle { ignore_changes }`.** It keeps the 404-then-CREATE path open. The provider's
  `DiffSuppressFunc` already suppresses role drift.
- **A new estimate marker for the pending license cut.** A marker means "this figure is unverified"
  (see the header of `scripts/expenses-verify-by-check.sh`). 68.00 is verified from the invoice, and
  34.00 has not happened yet. The cut becomes an operator action item instead.
- **A post-merge `GET team-members?email=…` probe** (plan-review, 2026-11-16). Its 200 and 404
  outcomes are both safe, and how it behaves for Admin members is unverified, so its result cannot
  change any decision.

**Value proposition (0.6c).** Not applicable: this is not a cost-saving mechanism. The ledger
correction moves Better Stack from $68.00 booked to $88.60 billed (+$20.60/mo), taken from the
2026-11-14 invoice (number withheld: public repo).

**Relevant files and anchors.**

- `apps/web-platform/infra/uptime-alerts.tf`: the header
  `# ── Better Stack managed alert recipient: ops@jikigai.com` is **detached** from its resource.
  - Heartbeat blocks were later inserted between them, so the header now sits directly above the
    `#6604 — the DAILY /workspaces LUKS` heartbeat comment.
  - The resource block sits just before
    `# ── Cloudflare zone-level origin-5xx notification policy: NOT shipped`.
- `.github/workflows/apply-web-platform-infra.yml`:
  - `-target=betteruptime_team_member.ops` is part of the `apply` job's saved-plan command,
    `terraform plan -no-color -input=false -out=tfplan`. Doppler is run with
    `--name-transformer tf-var`.
  - The workflow triggers on `push` to `main` with `paths: apps/web-platform/infra/**`, so the
    `uptime-alerts.tf` edit itself triggers the forget.
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq`, comment `SHARP EDGE: ["forget"] actions`:
  - A forget is excluded from `resource_deletes`. It trips `nested_deletes` only for Cloudflare
    types, so a `betteruptime_team_member` forget trips no counter and needs no `[ack-destroy]`.
  - The comment's inventory of `removed` blocks is **already stale**: it leaves out `tunnel.tf`'s
    `cloudflare_zero_trust_access_service_token.deploy` forget, which is a Cloudflare type. It
    therefore claims "non-Cloudflare types" incorrectly. Files to Edit 4 fixes this.
- `plugins/soleur/test/terraform-target-parity.test.ts`:
  - Model the new describe on `#8754 inngest firewall attachment forget rides the per-merge saved plan`
    (`commandIn(applyJob, /^\s*terraform plan\b.*-out=tfplan/)`, plus the post-bridge negative).
  - `g2eStrip()` is hoisted and strips `/* */` as well as `#`.
  - The brace-matched `block` helper is a closure local to one describe, so it cannot be reused.
  - `escapeRe` is a `const` (TDZ). Use only hoisted `function` helpers in a describe body.
  - `TEST_FLOOR = 376` is a `>=` floor; there are 395 tests today.
- `scripts/encryption-posture-ledger.json` lists `"betteruptime_team_member"` in `non_store_types`.
  `scripts/lint-encryption-posture.py` only checks that declared types are classified, so the unused
  entry is harmless. Leave it.
- `scripts/expenses-verify-by-check.sh` is the ledger lint. Its rules:
  - A row is an estimate iff it carries `<!-- estimate verify_by=… owner=… source="…" -->`.
  - Verifying a figure removes its marker.
  - One marker per row, and no `|` inside a marker.
  - It accepts a `LEDGER_PATH` argument.
  - It exits 1 while any marker is expired. Today 31 of 34 are expired, including "Better Stack"
    (verify_by=2026-11-12).
- `knowledge-base/engineering/architecture/diagrams/model.c4`: model.c4 has two stale statements.
  - The comment at the two lines
    `// paging primitive of its own (email only until the Responder seat is bought — the` and
    `// deferral trigger fired twice and the seat stays declined), so the wake path is the`.
  - The `betterstack -> founder` relationship description, at its clause
    `(the expenses.md deferral trigger fired twice; declined — revisit if Slack proves insufficient)`.
    This description is rendered into `model.likec4.json`, and `c4-model-freshness.test.sh`
    byte-diffs that file, so the edit needs `bash scripts/regenerate-c4-model.sh`.
- `knowledge-base/engineering/architecture/decisions/ADR-276-…md`, bullet
  `` **Named responder for `SOLEUR_FULL_BATTERY_ESCAPE`.** ``: it names
  `betteruptime_team_member.ops` and says "no Responder-tier seat is purchased". The sweep found
  this one.
- `.github/workflows/infra-validation.yml`: the PR-time live-state plan runs with
  `-refresh=false`, so it never exercises the Better Stack API token. This is why AC13 adds a
  read-only token probe.

**Institutional learnings applied.**

- `2026-09-21-a-removed-vendor-api-is-a-migration-with-a-backlog-not-a-brownout-to-retry.md`:
  `removed { destroy = false }` forgets an address without reading the old object.
- `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`: under a
  `-target` allowlist, a deletion or a forget needs the `-target` line kept.
- `2026-08-19-i-proposed-deleting-a-control-because-terraform-appeared-to-own-it.md`: "not in
  Terraform" means drift, not dead. The new comment names ops@'s Admin role as drift held only by
  the vendor.
- `2026-07-17-hetzner-cloud-api-catalog-not-billed-and-one-marker-per-row.md`: one marker per row,
  and only figures sourced from an invoice go unmarked.
- `2026-06-16-recurring-vendor-expense-ledger-gate-and-cost-model-refresh.md`: append a dated note
  rather than rewriting earlier dated notes.

**Conventions.**

- `cq-cite-content-anchor-not-line-number`: cite content anchors, not line numbers.
- Bump the ledger's `last_updated` whenever it changes (per the ops-advisor agent).
- `hr-tf-variable-no-operator-mint-default`: no new variable.
- `wg-when-deferring-a-capability-create-a`: the deferred escalation-policy question is filed as #12817.
- Dollar figures live in `expenses.md` and `cost-model.md` only. ADR and C4 notes state the fact
  and point to the ledger, so the pending license cut stays a two-file update (CTO devex review).

## Decisions (persisted to `knowledge-base/project/specs/feat-one-shot-betterstack-ops-admin-handover/decision-challenges.md`)

- **IaC mechanism.** Ruled by CTO agent, 2026-11-16:
  - Delete the resource block and its detached header.
  - Put `removed { from = betteruptime_team_member.ops lifecycle { destroy = false } }` where the
    resource was.
  - Keep the `-target`.
- **Ledger shape.** Ruled by CTO agent, 2026-11-16: split by invoice line.
  - "Better Stack Responder": active, 68.00, verified, no marker.
  - "Better Stack": active, 20.60 (the $20.00 heartbeat pack plus $0.60 of logs), with the overdue
    marker removed.
  - The pending 2→1 cut is a dated note plus an operator action item, not a marker.
- **Renewal Date.** Ruled by CTO agent, 2026-11-16, after the CFO raised it: **2026-12-14** on both
  rows. That is the next charge date after the 2026-11-14 to 2026-12-13 period, which is written in
  Notes. It replaces the CTO's first answer, 2026-12-13, which was the period end.
- **`var.betterstack_paid_tier`.** Ruled by CTO agent, 2026-11-16: not flipped here, because it
  changes fleet-wide paging. Deferred to #12817.
- **License cut 2→1.** Operator decision (money), recorded in decision-challenges.md. `ship` files it
  as an action-required issue.
- **ops@ Admin credential recovery.** Operator decision (irreversible). ops@ is now the only Admin,
  and it sits behind a forwarding mailbox, so a lost login cannot be recovered without vendor support
  (COO finding).
- **Plan-review dissents.** Recorded as `taste` rows in decision-challenges.md, with the reason each
  was or was not applied.

## Files to Edit

1. **`apps/web-platform/infra/uptime-alerts.tf`**
   - Delete the detached comment header. It runs from
     `# ── Better Stack managed alert recipient: ops@jikigai.com ──…` through the line
     `# betteruptime_outgoing_webhook forward or a Responder-tier upgrade (expense-gated).` and
     stops there. The next line, `# #6604 — the DAILY /workspaces LUKS…`, stays.
   - Replace `resource "betteruptime_team_member" "ops" { … }` with:

     ```hcl
     # ── Better Stack alert recipient ops@jikigai.com: managed by the vendor, not Terraform ──
     #
     # FORGOTTEN, NOT DESTROYED (2026-11-16). ops@jikigai.com is now the org's sole Admin, set
     # through the Better Stack web app; the account owner was moved to Billing admin, so only one
     # Responder seat is used. ops@ forwards to the Soleur inbox. BetterStackHQ/better-uptime
     # manages NON-ADMIN members only, and its Delete calls DELETE /api/v2/team-members?email=… —
     # deleting the resource block WITHOUT this removed block would delete the org's only Admin.
     # ops@'s Admin membership is drift outside IaC, recorded only by the vendor.
     #
     # Under -target a removed block is planned only when its address is targeted, so keep
     # `-target=betteruptime_team_member.ops` in the apply job's saved plan. Once the forget has
     # applied, both are inert tombstones (the inngest-host.tf #8754 precedent keeps them).
     removed {
       from = betteruptime_team_member.ops

       lifecycle {
         destroy = false
       }
     }
     ```

2. **`plugins/soleur/test/terraform-target-parity.test.ts`.** Delete the FIX B describe. Add
   `"betteruptime_team_member.ops is forgotten, never destroyed (FIX B handed to the vendor, 2026-11-16)"`
   **right after** the `#8754 inngest firewall attachment forget rides the per-merge saved plan`
   describe. Its body uses only hoisted `function` helpers (no TDZ). Each `.tf` file's text is run
   through `g2eStrip()` before matching. The describe asserts:
   - **(a)** No `resource "betteruptime_team_member"` block in any `listInfraTfFiles()` file has the
     label `ops`, or a body containing `ops@jikigai.com`. Match the block opener plus its
     brace-matched body with a small local `function`.
   - **(b)** At least one top-level `removed` block has `from = betteruptime_team_member.ops`. Its
     `destroy = false` is enforced by census G4a, so it is not re-asserted here.
   - **(c)** The address is in `extractAllTargets(savedPlan)` and is not in the post-bridge
     `terraform apply -auto-approve -input=false`. Build `savedPlan` and `postBridge` exactly as the
     #8754 describe does.
   - **Non-vacuity**, anchored on this root itself: `listInfraTfFiles().length > 0`, the resource
     scan sees at least one `betteruptime_heartbeat` in `uptime-alerts.tf`, and `savedPlan` targets
     `hcloud_firewall_attachment.web`.
   - Add one `<before> -> <after> (this PR, <delta>)` line to the history comment above
     `const TEST_FLOOR`, re-deriving both counts with
     `grep -cE '^\s*test\(' plugins/soleur/test/terraform-target-parity.test.ts` (395 today). The
     constant stays 376, because the final describe asserts
     `expect(declared).toBeGreaterThanOrEqual(TEST_FLOOR)`.
3. **`apps/web-platform/infra/betterstack-logs-alerts.tf`.** In the ROUTING comment, replace
   `(account owner + betteruptime_team_member.ops)` with
   `(the team's responder ops@jikigai.com, the org Admin managed by the vendor since 2026-11-16)`.
4. **`tests/scripts/lib/destroy-guard-filter-web-platform.jq`.** In the SHARP EDGE comment, replace
   the hand-kept inventory of `removed` blocks and its "non-Cloudflare types" claim with a recipe
   that cannot go stale, for example:
   `# list them with: grep -n '^removed' apps/web-platform/infra/*.tf, and check each "from" type`
   `# against the nested_deletes clauses below. tunnel.tf's cloudflare_zero_trust_access_service_token`
   `# forget is a Cloudflare type (already applied); betteruptime_team_member.ops (uptime-alerts.tf) is not.`

   This is a comment-only change, and it also corrects a claim that is already false on `main`.
5. **`knowledge-base/operations/expenses.md`.** Bump `last_updated: 2026-11-16`.
   - **The "Better Stack Responder (DEFERRED)" row** becomes
     `| Better Stack Responder | Better Stack | observability | 68.00 | active | 2026-12-14 | … |`.
     Its Notes cell, in order:
     - The billed fact: "Responders (PAYG), 2 licenses × $34.00, the 2026-11-14 invoice,
       paid 2026-11-14, period 2026-11-14 to 2026-12-13."
     - A dated note headed **[2026-11-16 — supersedes the DEFERRED status and the 2026-09-28 "STILL
       DECLINED" line]**:
       - The seat has been billing, at $34 a license rather than the $29 this row assumed.
       - Since 2026-11-16, `ops@jikigai.com` has been the only org Admin and holds the one seat
         needed. The owner is Billing admin, which is not billed.
       - Usage reads 1 of 2 licenses.
       - The 2→1 license cut is a pending operator billing decision. It is expected to bring this
         row to 34.00 and the vendor total to about $54.60/mo.
       - The cut is tracked as an action-required issue, and the next invoice verifies it
         (proration or a credit is possible).
     - One condensed dated sentence of history: the #3960 deferral, the trigger that fired on
       2026-09-28, and the seat declined in favor of the $0 Slack path (ADR-260).
     - The hedged clause: the $68.00 the "Better Stack" row has carried since 2026-08-16 equals this
       2-license line. Whether the 2026-08-16 charge was this same line is **not verified**.
     - The pricing source: betterstack.com/pricing (Responder $34/mo monthly; Team member $0).
   - **The "Better Stack" row** becomes
     `| Better Stack | Better Stack | observability | 20.60 | active | 2026-12-14 | … |`.
     - Rewrite the stale lead sentence ("Free tier: 10 monitors… email alerts") to state the billed
       lines, from the same invoice:
       - Heartbeats: 17 active (10 included, 7 extra), billed as one $20.00 pack of 10.
       - Logs Europe PAYG: 4 GB (3 included, 1 extra), 90-day retention, $0.60. This line is
         usage-based and varies from month to month.
     - A dated note headed **[2026-11-16 — invoice read]**:
       - The 68.00 moved to "Better Stack Responder" per the 2026-11-14 invoice. It is a
         move, not a saving. The vendor total is 88.60.
       - The invoice has no logs-plan line, because logs bill PAYG. #7577's "Nano ($30 EU)
         downgrade" therefore has no plan to downgrade from.
     - One line on the paused heartbeats: 4 `soleur-host-kernel-*` heartbeats are paused and unbilled.
       Unpausing them takes active heartbeats from 17 to 21, which adds a second $20.00 pack. The
       break-even consequence is in cost-model.md. Pricing: betterstack.com/pricing, where each
       additional 10 heartbeats costs $20/mo.
     - **Remove** the `<!-- estimate verify_by=2026-11-12 … -->` marker. The invoice it asked for has
       been read. Its other question, the 2026-08-14 quota exhaustion, is answered by the row's own
       **[2026-08-17]** note (the HTTP 402 ingest refusal, see the PIR).
     - Leave every earlier dated note unchanged.
     - **Fold the stray 8th cell** into the Notes cell so the row has the table's 7 columns. That is
       the text starting `**[2026-08-17 — supersedes the 'stay free tier' decision above]**`, which
       now sits in a cell after Notes. Join it with a space, and keep any `|` out of the moved text.
6. **`knowledge-base/finance/cost-model.md`.** Bump `last_updated: 2026-11-16`.
   - Add a dated blockquote note right after the Product COGS table, beside the Proton and Sentry
     notes, titled **2026-11-16 Better Stack correction**. It says:
     - `expenses.md` now splits Better Stack into Responder 68.00 and Better Stack 20.60. The vendor
       total is **88.60**, or about **54.60** after the pending license cut.
     - Both §4.1 line-and-anchor conditions hold, so the next monthly review re-derives the subtotals
       rather than this note:
       - (i) The subtotal moves less than 10%: +$20.60 on 359.47 of Product COGS is about 5.7%.
       - (ii) No `⌈burn ÷ price⌉` boundary is crossed. COGS of 380.07 stays at **8** users at both
         $49 and $48. The all-in floor of ≥1,319.92 stays at **27** users at $49 and **28** at $48.
     - Unpausing the 4 paused heartbeats (+$20) **would** cross boundaries: COGS 400.07 means 9 users
       at both prices, and the all-in ≥1,339.92 goes from 27 to 28 users at $49. That change requires
       a full re-derivation.
     - It supersedes two earlier statements:
       - the 2026-09-29 note's "the seat was **still declined** … the deferred row stands";
       - the earlier review note's "Better Stack's paid observability plan (**+$68/month**, active
         since 2026-08-16)", which was the Responder licenses, not a plan.
   - In the Product COGS row `Better Stack | 68.00 [expenses.md@2026-08-16]`, change only the Source
     cell, to `expenses.md@2026-11-16 (see the 2026-11-16 note)`. The amount cell changes at the
     next review.
   - In the upgrade-exposure row `Better Stack | $68.00 … (active; exact paid tier unverified)`,
     replace the stale "tier unverified / delta unknown" cells with the next steps that are now
     known: +$20/mo for each 10 extra active heartbeats, and about $0.60 for each extra GB of logs.
     This change is CFO-required.
7. **`knowledge-base/engineering/architecture/decisions/ADR-260-db-outage-paging-and-bounded-auto-restart.md`.**
   Append a dated note at the end of `### 1. Paging: Slack native integration over the Responder seat`.
   **The decision itself is unchanged.** The note reads: "2026-11-16: the 2026-11-14 invoice shows
   Responder licenses are billed, and ops@ holds the one needed seat as org Admin (figures:
   expenses.md 'Better Stack Responder'). The Slack path remains the paging route, and escalation
   policies stay gated off (#12817). 'Not purchased' no longer describes billing."
8. **`knowledge-base/engineering/architecture/decisions/ADR-298-betterstack-incident-mirror-github-issues.md`.**
   Add **one** dated note after decision item 4 ("Responder-tier escalation stays deferred"). It
   covers both item 4 and the Alternatives row "Paid-tier escalation policy". It says that a
   Responder seat is now billed (see expenses.md), so the premise "the seat the operator declined at
   ADR-260" no longer holds. The `betteruptime_policy` arm stays deferred as a scope decision (#12817).
9. **`knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`.**
   After the paragraph `**Alert recipient (free-tier IaC path).**`, add: *2026-11-16:
   `betteruptime_team_member.ops` is forgotten (`removed { destroy = false }`). ops@ is now the
   org Admin, managed by the vendor, because the provider manages non-admin members only. The
   `-target` stays as a tombstone.*
10. **`knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`.**
    After the bullet `` **Named responder for `SOLEUR_FULL_BATTERY_ESCAPE`.** ``, add a dated note:
    "2026-11-16: `ops@jikigai.com` is now the org Admin, managed by the vendor and no longer a
    Terraform resource. A Responder seat is billed (see expenses.md). Escalation policies stay off
    (#12817), and the Slack and email wake path is unchanged."
11. **`knowledge-base/engineering/architecture/diagrams/model.c4`** and the regenerated
    **`knowledge-base/engineering/architecture/diagrams/model.likec4.json`.**
    - **Comment.** After the line ending `the seat stays declined), so the wake path is the` and its
      sentence, insert one new `//` line: `// 2026-11-16: a Responder seat is billed (expenses.md);
      the Slack wake path below is unchanged (ADR-260, #12817).`
    - **Relationship string.** In the `betterstack -> founder` description, after `revisit if Slack
      proves insufficient)`, append `(2026-11-16: a Responder seat is now billed, see expenses.md;
      escalation stays gated, #12817)`. Do not add any "<n> <noun>" phrase, which would move a
      c4-count-parity cardinality.
    - Then run `bash scripts/regenerate-c4-model.sh` and commit the regenerated JSON.

**Not edited (acknowledged).**

- `.github/workflows/apply-web-platform-infra.yml`: the `-target` stays on purpose, and the file
  forbids comments inside its run block.
- Post-mortems: they are point-in-time records.
- `scripts/encryption-posture-ledger.json`: see Research Insights.
- The `betterstack_paid_tier` description in `variables.tf`: deferred to #12817.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-betterstack-ops-admin-handover/decision-challenges.md`
  (created at plan time).
- `knowledge-base/project/specs/feat-one-shot-betterstack-ops-admin-handover/tasks.md`.

## Open Code-Review Overlap

Two open scope-outs touch these files:

- **#12784** (anchor the `inngest_luks_wrong_volume` needles, `betterstack-logs-alerts.tf`):
  **Acknowledge.** It concerns a different block. This plan changes one routing comment.
- **#10464** (the zot fill-rate blind window, which cites ADR-096): **Acknowledge.** It concerns a
  different section. This plan appends one dated note.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/uptime-alerts.tf`: the resource block is replaced by a `removed` block.
There is no new provider, version pin or variable. The sensitive variables are unchanged:
`TF_VAR_betterstack_api_token`, from Doppler `prd_terraform` via `--name-transformer tf-var`.

### Apply path

The forget rides the per-merge `apply` job's saved plan (`terraform plan … -out=tfplan`). The
workflow fires on the merge push.

- The plan shows either `betteruptime_team_member.ops will no longer be managed by Terraform` (a
  `forget` action) or, if a refresh had already dropped the entry, no change for that address. Both
  outcomes show `0 to destroy`.
- No API write reaches Better Stack. There is no downtime and no host is touched.
- The blast radius is one state entry.
- Lookup during the plan: the provider's `Read` (`GET /api/v2/team-members?email=…`) still runs on the forgotten address. A 404 drops the entry, giving no change. *(Superseded: see the 2026-11-16 Addendum at the end of this plan.)* A non-404 error, such as a 5xx or a 401/403, fails the per-merge plan loudly. AC13 pre-checks the token, and a 5xx is re-run (terraform-architect, deepen 2026-11-16).

### Host fan-out

None. No `terraform_data` SSH provisioner is touched.

### Distinctness / drift safeguards

- `destroy = false` is the safeguard that keeps the Admin from being deleted. Census G4a enforces it
  on every `removed` block.
- The destroy guard's `resource_deletes` counter aborts any future plain DELETE that lacks
  `[ack-destroy]`.
- After the forget, ops@'s Admin role is drift held only by the vendor. The `removed` comment and
  ADR-096 both say so.

### Vendor-tier reality check

The provider resource manages non-admin members only, as its description says: "Allows managing
**non-admin team members**". Escalation policies stay behind `var.betterstack_paid_tier = false`
(#12817).

## Architecture Decision (ADR/C4)

### ADR

No new ADR is needed. The change extends **ADR-096**, whose FIX B alert-recipient paragraph described
an IaC-managed responder. That paragraph gets a dated amendment note (Files to Edit 9).

ADR-260, ADR-298 and ADR-276 get dated factual notes (Files to Edit 7, 8 and 10). Their decisions
are unchanged. What the notes correct is the billing premise those ADRs cite.

### C4 views

All three model files were read: `knowledge-base/engineering/architecture/diagrams/model.c4`,
`views.c4` and `spec.c4`.

- **External actors.** The operator, who receives alerts, is already modelled as `founder`. ops@ is
  one of the operator's addresses, not a new actor.
- **External systems.** `betterstack` and `slack` are already modelled.
- **Containers and data stores.** None touched.
- **Access relationships.** `betterstack -> founder` keeps its edge. Only its description text gets a
  dated correction.

There are no element, relationship or `view include` changes. Run
`plugins/soleur/test/c4-count-parity.test.sh`, `plugins/soleur/test/c4-model-freshness.test.sh`,
`apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`. All four green is the
evidence that no count moved and the JSON is fresh.

### Sequencing

None needed. The notes describe the state at merge.

## Encryption Posture

Detection fires only on the `.tf` path. This plan adds no persistent store and no cross-component
connection, and it changes no existing one. The edit removes a team-member declaration from state.
Per plan Phase 2.11, no posture rows are required.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The worst case is internal:
  - If the `removed` block were dropped and the plain deletion applied (which takes an
    `[ack-destroy]`), Better Stack's only Admin, ops@, would be deleted.
  - Better Stack's incident emails to the operator would then stop, so a user-visible app.soleur.ai
    outage could go unnoticed for longer.
  - The Slack integration (ADR-260) and the GitHub incident mirror (ADR-298) would still post.
- **If this leaks, the user's data is exposed via:** no vector. The change touches no user data,
  credential or secret. It forgets a vendor team-member state entry and edits ledger prose.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the only failure path is degraded alert delivery to the
  operator, and it sits behind two independent channels plus two guards. No user-data or money path
  is involved.
- `threshold: none, reason: the infra edit forgets one Better Stack team-member state entry with destroy = false and touches no user-data, auth or secret surface.`

## Observability

```yaml
liveness_signal:
  what: the per-merge apply-web-platform-infra.yml apply job on main, whose saved plan carries the betteruptime_team_member.ops forget
  cadence: per push to main touching apps/web-platform/infra/**
  alert_target: GitHub Actions failed-run notification to the operator, plus the job's ::error:: annotations
  configured_in: .github/workflows/apply-web-platform-infra.yml (apply job, saved-plan command `terraform plan -no-color -input=false -out=tfplan`)

error_reporting:
  destination: GitHub Actions job log and annotations for apply-web-platform-infra.yml
  fail_loud: "::error::terraform plan failed (exit N)" or a destroy-guard abort naming resource_deletes > 0

failure_modes:
  - mode: the removed block is dropped while the resource block stays deleted, so the plan carries a DELETE of the sole Admin
    detection: census Guard 4 G4c (orphaned vs the merge-base) and the FIX B describe assertion (b) fail pre-merge; post-merge, the destroy guard's resource_deletes >= 1 aborts the apply without [ack-destroy]
    alert_route: PR CI red check / failed apply run notification
  - mode: destroy = true is set on the removed block
    detection: census Guard 4 G4a fails pre-merge
    alert_route: PR CI red check
  - mode: a later edit re-declares a betteruptime_team_member for ops@jikigai.com (404-then-POST re-invite of the Admin)
    detection: FIX B assertion (a) fails pre-merge; for the same address, terraform plan also refuses ("Removed resource still exists")
    alert_route: PR CI red check
  - mode: the forget is never planned because the -target line left the saved plan
    detection: FIX B assertion (c) and census G4b fail pre-merge
    alert_route: PR CI red check
  - mode: the Better Stack API token stops authenticating after the owner's demotion to Billing admin, so the per-merge plan errors
    detection: AC13 read-only token probe pre-merge; post-merge, "::error::terraform plan failed" in the apply job
    alert_route: PR check / failed apply run notification
  - mode: ops@ loses Admin or stops receiving alerts through a vendor-side change (now drift outside IaC)
    detection: not IaC-detectable by design; the Better Stack to Slack integration (ADR-260) and the GitHub incident mirror (ADR-298) remain independent delivery channels
    alert_route: Slack incident channel and GitHub incident-mirror issues

logs:
  where: GitHub Actions run logs for apply-web-platform-infra.yml (public repo jikig-ai/soleur)
  retention: 90 days (GitHub Actions default log retention)

discoverability_test:
  command: curl -s https://api.github.com/repos/jikig-ai/soleur/actions/workflows/apply-web-platform-infra.yml/runs?per_page=1
  expected_output: "success"
```

## Guard Contract

### Guard 1 — ops@ forget pin (FIX B describe + census Guard 4)

**Property.** Terraform never again manages `ops@jikigai.com` as a Better Stack team member, and the
per-merge saved plan forgets the old address rather than deleting it.

**Assembly.** The property runs through three chokepoints:

- **(1) Every `*.tf` file that Terraform loads in the root.** That is `listInfraTfFiles()`, plus the
  existing `*.tf.json` absence assertion in the #8754 PR-B describe, with text read through
  `g2eStrip()`. This chokepoint is where any `resource "betteruptime_team_member"` would appear.
- **(2) Every top-level `removed` block in those files.** Census Guard 4 owns their shape (G4a), their
  targeting (G4b) and the orphan check against the merge-base (G4c). FIX B adds that an ops block
  exists.
- **(3) The `apply` job's saved-plan command** `terraform plan … -out=tfplan` in
  `apply-web-platform-infra.yml`. A `-target`ed forget is planned only here. The negative side is
  the post-bridge `terraform apply`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `removed { from = betteruptime_team_member.ops … }` block | RED: FIX B (b), and census G4c against the merge-base |
| 2 | Change `destroy = false` to `destroy = true` | RED: census G4a |
| 3 | Re-add `resource "betteruptime_team_member" "ops" { email = "ops@jikigai.com" }` in `uptime-alerts.tf` | RED: FIX B (a). `terraform plan` also refuses ("Removed resource still exists"); the test gives earlier feedback |
| 4 | Starting from a compliant tree, add a second member, `resource "betteruptime_team_member" "ops_admin" { email = "ops@jikigai.com" }`, in `inngest.tf` | RED: FIX B (a). Terraform cannot catch a new label pointing at the Admin's email |
| 5 | Remove `-target=betteruptime_team_member.ops` from the saved-plan command | RED: FIX B (c), and census G4b |
| 6 | Move that `-target` out of the saved plan and into the post-bridge `terraform apply` only | RED: FIX B (c) |
| 7 | Point the describe's own dispatch at an empty file list (`listInfraTfFiles()` returns `[]`) | RED: the non-vacuity anchor (`betteruptime_heartbeat` not found in `uptime-alerts.tf`) |

**Harness rows:**

| # | Edit / input | Expected |
|---|---|---|
| H1 | Suite input: the `removed` block exists only inside a `/* … */` comment | RED: FIX B (b), because `g2eStrip()` removes block comments |
| H2 | Must-PASS non-canonical input: `resource "betteruptime_team_member" "oncall" { email = "oncall@example.com" }`, a different non-admin member | PASS: the contract forbids only ops@ and `.ops` |

**Anchor.** None: no stored value is compared.

**Known weakness (deepen 2026-11-16).** Census G4b reads only steps that contain a literal `terraform apply`. The saved-plan step qualifies today only because of an `::error::` echo line. G4b also merges every apply step's `-target` list, so row 6 (saved plan versus post-bridge) rests on FIX B (c) alone. Rewording that echo turns G4b red, which is loud, not silent. Hardening G4b is out of scope here.

The work phase runs rows 1–7 and H1–H2 as throwaway local mutations, reverts them, and records a
one-line tally in the PR body. Only the final assertions are committed.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "stop managing that member in Terraform WITHOUT destroying it — delete the resource block and add a Terraform `removed { from = betteruptime_team_member.ops  lifecycle { destroy = false } }` block" | Files to Edit 1 | mapped |
| 2 | "verify the root's required_version / the CI Terraform version supports `removed`, TF >= 1.7" | Research Reconciliation row 2 | mapped |
| 3 | "Rewrite the long comment above the resource to say ops@ is now the org Admin managed in the UI (owner downgraded to Billing admin so only one responder seat is used) and that ops@ forwards to the Soleur inbox" | Files to Edit 1 (new comment) | mapped |
| 4 | "Check whether any test (e.g. infra *.test.sh) asserts on this resource and update it" | Files to Edit 2; census Guard 4 is named | mapped |
| 5 | "The \"Better Stack\" row ($68.00 active) misattributes the $68 to a logs tier." | Files to Edit 5 ("Better Stack" row) | mapped |
| 6 | "Also reconcile the \"Better Stack Responder (DEFERRED)\" row … reconcile the two rows without inventing figures" | Files to Edit 5 (Responder row) | mapped |
| 7 | "4 heartbeats (soleur-host-kernel-*) are paused and unbilled; unpausing them takes active heartbeats 17 → 21 → a second $20 pack" | Files to Edit 5 (fact) and 6 (break-even) | mapped |
| 8 | "Resolve the overdue `verify_by=2026-11-12` estimate marker on that row since the invoice is now read" | Files to Edit 5 (marker removed) | mapped |
| 9 | "Respect whatever ledger lint/format rules exist" | AC6, AC7 | mapped |
| 10 | "Check other docs that assert the ops@ member's role or the Responder deferral … add a short dated note where a statement is now false; do not rewrite ADR decisions" | Files to Edit 3, 6–11 | mapped |
| 11 | "Do not touch Better Stack live state; infra-only change plus ledger/docs." | Apply path (forget only); AC13 is a read-only GET | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit 1 (`uptime-alerts.tf`) | asks 1, 3 | asked |
| Files to Edit 2 (parity test) | ask 4 | asked |
| Files to Edit 3 (`betterstack-logs-alerts.tf` comment) | ask 10: "Check other docs that assert the ops@ member's role" | asked |
| Files to Edit 4 (`destroy-guard-filter-web-platform.jq` comment) | — | inferred — justification: the comment is the root's forget-safety argument; its inventory is already false on main (tunnel.tf's Cloudflare forget is missing), and this PR adds a forget it would also omit; the recipe form stops the drift (`wg-when-an-audit-identifies-pre-existing`) |
| Files to Edit 5 (`expenses.md`) | asks 5–9 | asked |
| Files to Edit 6–11 (cost-model, ADR-260/298/096/276, model.c4 + JSON) | ask 10 | asked |
| Keep the workflow `-target` (no edit) | — | inferred — justification: a `removed` block is planned only when its address is targeted (#8754 precedent); dropping it orphans the state entry |
| AC13 read-only token probe | — | inferred — justification: COO flagged that the owner's demotion may revoke a user-created token; the PR-time plan runs `-refresh=false` and cannot see it, so the merge's apply would be the first to fail, blocking every per-merge target |
| Deferral issue #12817 | — | inferred — justification: `wg-when-deferring-a-capability-create-a`; the CTO ruled the paid-tier flip out of this PR's scope |
| Operator action items (license 2→1; ops@ Admin credential recovery) in decision-challenges.md | "reducing the license count 2→1 is a pending operator billing action" | asked (license); inferred — justification: COO single-Admin bus-factor finding, operator category irreversible (credential recovery) |

### Split Assessment

- Subsystems touched: 3:
  - `apps/web-platform/infra/`, with its test pins in `plugins/soleur/test/` and `tests/scripts/lib/`;
  - `knowledge-base/operations` and `finance`;
  - `knowledge-base/engineering/architecture`.
- Planned files: 15. That is 12 edits counting the regenerated `model.likec4.json`, 2 creates and
  the plan itself, plus any pipeline-written `specs/<branch>/session-state.md`.
- Estimated changed lines: about 150.
- Thresholds: >= 4 subsystem roots, OR > 25 planned files, OR > 800 estimated lines.
- Recommendation: single PR.

## Acceptance Criteria

- [x] **AC1.** No team-member resource remains, and exactly one `removed` block with
  `destroy = false` names the address:
  - `grep -hcE '^[[:space:]]*resource[[:space:]]+"betteruptime_team_member"' apps/web-platform/infra/*.tf | awk '{s+=$1} END{print s+0}'`
    prints `0`.
  - `awk '/^removed[[:space:]]*\{/{f=1} f{print} f&&/^\}/{f=0}' apps/web-platform/infra/uptime-alerts.tf | grep -cE 'from = betteruptime_team_member\.ops|destroy = false'`
    prints `2`.
- [x] **AC2.** `git diff --quiet origin/main...HEAD -- .github/workflows/apply-web-platform-infra.yml`
  exits 0, and `grep -c -- '-target=betteruptime_team_member.ops' .github/workflows/apply-web-platform-infra.yml`
  prints `1`.
- [x] **AC3.** The old header is gone and the new comment carries the required facts:
  - `grep -c 'Better Stack managed alert recipient' apps/web-platform/infra/uptime-alerts.tf`
    prints `0`.
  - The new comment contains "sole Admin", "Billing admin", "forwards to the Soleur inbox", the
    DELETE hazard and the `-target` tombstone.
- [x] **AC4.** On TF 1.10.5, `terraform -chdir=apps/web-platform/infra fmt -check` passes, and
  `terraform validate` passes after `init -backend=false`.
- [x] **AC5.** The ops forget is pinned by both guards:
  - `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes, with assertions (a), (b),
    (c) and the non-vacuity anchors.
  - `bash tests/scripts/test-infra-privileged-tier-census.sh` passes, and its G4a line counts one
    more `removed` block than on the merge-base (9 → 10 today).
  - Mutation rows 1–7 and harness rows H1–H2 are each observed as tabled, and a one-line tally is
    recorded in the PR body.
- [x] **AC6.** Run the ledger lint on the merge-base copy and on the HEAD copy:

  ```sh
  T=$(mktemp -d)
  git show "$(git merge-base origin/main HEAD)":knowledge-base/operations/expenses.md > "$T/base.md"
  bash scripts/expenses-verify-by-check.sh "$T/base.md"
  bash scripts/expenses-verify-by-check.sh
  ```

  - Exit 1 is expected from both runs while other rows' markers are expired.
  - On HEAD, `candidates` and `parsed_ok` are each exactly 1 lower than on base.
  - On HEAD, `anomalies=0`.
  - No EXPIRED line names "Better Stack" or "Better Stack Responder".
- [x] **AC7.** Both rows are rewritten:
  - In `expenses.md` the two rows read `Better Stack Responder | … | 68.00 | active | 2026-12-14`
    and `Better Stack | … | 20.60 | active | 2026-12-14`.
  - `awk -F'|' '/^\| Better Stack/{n++; if(NF!=9)b++} END{print n, b+0}' knowledge-base/operations/expenses.md`
    prints `2 0`. Today it prints `2 1`.
  - 68.00 + 20.60 = 88.60, which equals the invoice total.
  - Neither row carries an estimate marker.
  - `last_updated: 2026-11-16`.
- [x] **AC8.** In `git diff origin/main...HEAD -- knowledge-base/operations/expenses.md knowledge-base/finance/cost-model.md`,
  every new dollar figure is one of these:
  - from the invoice: $68.00, $20.00, $0.60, $88.60;
  - from the pricing page: $34, $20;
  - derived: ~$54.60, 380.07, 400.07, 1,319.92 and 1,339.92, plus the break-even counts.
- [x] **AC9.** The ADR notes add text and remove nothing:
  - `git diff -U0 origin/main...HEAD -- <ADR-260> <ADR-096> <ADR-276> <ADR-298> | grep -c '^-[^-]'`
    prints `0`, because every ADR note is additive.
  - `grep -c '2026-11-16'` is at least 1 in each of ADR-260, ADR-298, ADR-096, ADR-276,
    `cost-model.md` and `model.c4`.
- [x] **AC10.** `grep -c 'account owner + betteruptime_team_member.ops' apps/web-platform/infra/betterstack-logs-alerts.tf`
  prints `0`, and the destroy-guard jq comment no longer claims that every `removed` block is a
  non-Cloudflare type.
- [x] **AC11.** Local gates pass before push, to save CI cycles:
  - `bash plugins/soleur/test/c4-count-parity.test.sh`
  - `bash plugins/soleur/test/c4-model-freshness.test.sh`
  - `cd apps/web-platform && npx vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`
  - `python3 scripts/lint-encryption-posture.py --repo-sweep`
- [x] **AC12.** `decision-challenges.md` holds two operator rows:
  - `operator (money)`: cut Better Stack Responder licenses 2 → 1, then verify 34.00 on the next
    invoice and update only `expenses.md` and `cost-model.md`.
  - `operator (irreversible)`: record where ops@'s Better Stack credentials and 2FA recovery codes
    live.

  `ship` files both as action-required issues.
- [x] **AC13.** Before the PR is marked ready, this read-only probe prints `200`:

  ```sh
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- bash -c 'curl -s --max-time 15 -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TF_VAR_betterstack_api_token" "https://uptime.betterstack.com/api/v2/monitors?per_page=1"'
  ```

  A `401` or `403` means the token needs replacing. Route that to the CTO before merge.

## Domain Review

**Domains relevant:** Engineering, Operations, Finance

### Engineering

**Status:** reviewed (CTO agent, 2026-11-16; CTO devex lens at plan review)
**Assessment:**

- Use option (a): a `removed { destroy = false }` block plus the kept `-target` and a FIX B rewrite.
  - Rejected: `state rm`, which leaves no review trail and re-creates the member.
  - Rejected: `ignore_changes`, which leaves the 404-then-CREATE path and the DELETE-on-removal
    hazard in place.
- Name the drift outside IaC in the `removed` comment and in ADR-096.
- Split the ledger by invoice line.
- Leave `betterstack_paid_tier` alone (#12817).
- Devex review findings, applied:
  - The jq inventory was already stale; it is now a recipe.
  - Dollar figures appear only in the ledger and cost-model.
  - The tombstone gets an exit condition.
  - Non-vacuity is anchored on this root.
  - The `TEST_FLOOR` comment is updated.

### Operations

**Status:** reviewed (COO agent, 2026-11-16)
**Assessment:**

- The single-Admin bus factor is high. Folded in as an `operator (irreversible)` item (AC12).
- The API token must still work after the owner's demotion. Folded in as AC13.
- The DEFERRED row contradicted the invoice. It is now reconciled.
- The logs line is marked usage-based, and the renewal date is set.
- The license item verifies 34.00 against the next invoice. The operator can weigh whether any seat
  is needed, given ADR-260.
- The stale "INERT until ops@ accepts" header is deleted.
- The removed free Member was not a recipient declared in IaC. `git grep "harry@" -- apps .github scripts`
  finds only test fixtures.

### Finance

**Status:** reviewed (CFO agent, 2026-11-16)
**Assessment:**

- The split is correct, and Responder seats are Product COGS.
- A note is enough instead of a re-derivation, but it has to cite both §4.1 conditions. All folded
  in, with break-even unchanged.
- Unpausing the heartbeats crosses boundaries, so it requires a full re-derivation (folded in).
- The stale cost-model cells are updated.
- The Nano downgrade premise is void.
- The renewal date is the next charge date.

### Product/UX Gate

Not applicable. No file in Files to Edit or Files to Create matches the UI-surface terms. This is an
infra, ledger and docs change, so the tier is NONE.

## Test Scenarios

- **(unit)** Given the edited tree, `bun test plugins/soleur/test/terraform-target-parity.test.ts`
  and `bash tests/scripts/test-infra-privileged-tier-census.sh` both pass. Each mutation row turns
  them red as tabled.
- **(unit)** Given the edited ledger, AC6's base-vs-HEAD lint comparison holds.
- **(integration)** `terraform init -backend=false && terraform validate` on TF 1.10.5 accepts the
  `removed` block.
- **(integration, post-merge)** Select the merge commit's push run:
  `gh run list --workflow apply-web-platform-infra.yml --commit <merge-sha> --json databaseId,conclusion`.
  It concludes `success`. *(Superseded: see the 2026-11-16 Addendum at the end of this plan.)* Its `apply` job log shows `0 to destroy`, and for
  `betteruptime_team_member.ops` it shows either `will no longer be managed by Terraform` or no
  change.

## Sharp Edges

- Keep `-target=betteruptime_team_member.ops` and the `removed` block at least until the forget has
  applied. After that both are inert tombstones, and repo precedent keeps them. Removing them is
  safe only once a read-only `terraform state list` on prd shows no such address.
- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6.
- The ledger's "Better Stack" row is about 6 kB on one table line, with an 8th cell. Use an
  exact-string Edit anchored on unique substrings, not `sed` over `|`. Re-run AC7's `awk` after the
  edit.
- `expenses-verify-by-check.sh` extracts one marker per row, greedily. Leave no `<!-- estimate`
  fragment in the moved 8th-cell text.
- Put the new parity describe after the #8754 describe, and use only hoisted `function` helpers in
  its body. A `const` helper declared later in the file, such as `escapeRe`, throws a TDZ
  ReferenceError when the module loads.
- The pre-commit hook `c4-model-regenerate` may regenerate `model.likec4.json` by itself. Either
  way, commit the regenerated file, and confirm `c4-model-freshness.test.sh` is green.
- Until the forget applies, `scheduled-terraform-drift.yml` (a full plan with no `-target`) shows the forget and exits 2. The per-merge apply on the merge push closes that window, so a drift issue opened in between can be closed as expected.

## Addendum — 2026-11-16 (ship, #12813)

> **Superseded 2026-11-16 (#12813):** two predictions above were wrong. "A 404 drops the entry (no change)" is false: apply run 43870657893 shows the provider Read still succeeds for ops@ as Admin, so the merge plans a `["forget"]`. The post-merge check's "It concludes `success`" is also false while #12823 is open. In that run, the `Terraform apply` step (non-SSH resources, which includes this forget) succeeded, and the run then failed later at `SSH forward to web-2 through the web-1 bastion`. Verify the forget from the `Terraform apply` step log (`will no longer be managed by Terraform`, `0 to destroy`), not from the run's conclusion.
