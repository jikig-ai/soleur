<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan edits NO .tf and provisions NO new resource. The only
     "operator runs terraform" step is the ADR-068 Phase-3 maintenance-window cutover, which is
     genuinely human-gated (a supervised production web-host power-off reboot = risk-acceptance
     judgment, not an automatable tooling gap). It is documented as a runbook with the canonical
     Doppler tf-var invocation triplet, gated on a 0-destroy dry-run, and tracked via follow-through.
     A ## Infrastructure (IaC) section is present below. -->
---
title: "fix(infra): unblock apply-web-platform-infra — sequence #5877 moved-block migration + add moved/-target guard"
issue: 5887
branch: feat-one-shot-5887-moved-target-allowlist
type: ops-remediation
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-02
---

# 🐛 fix(infra): unblock apply-web-platform-infra — sequence the #5877 moved-block migration + add a moved/`-target` parity guard

> Spec lacks a `lane:` (no spec.md authored for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`.github/workflows/apply-web-platform-infra.yml` auto-applies `apps/web-platform/infra/*.tf` on every merge to `main`, using a **target-scoped** `terraform plan -target=<addr>` allow-list (one `-target=` line per resource that is *intended* to be applied per-PR). It has been **red on every run since 2026-07-01 18:03** (#5877, Phase 3 Sub-PR 3.A), which added four `moved {}` blocks to `apps/web-platform/infra/placement-group.tf`. Terraform rejects a targeted plan when a pending `moved` source/target base address is excluded from the `-target` set:

```
Error: Moved resource instances excluded by targeting
  … hcloud_server.web, hcloud_volume.workspaces, hcloud_volume_attachment.workspaces …
```

The issue proposes: extend the `-target=` allow-list with the three reported bases (mirroring the #5566 un-targeted-resource fix), and extend `terraform-target-parity.test.ts` to catch `moved`-block endpoints missing from the `-target` set.

**Research + CTO review rejects the literal `-target` extension as unsafe** and reframes the fix. `hcloud_server.web` now carries `placement_group_id = hcloud_placement_group.web_spread.id` (server.tf:40) and `for_each = var.web_hosts`. Its own comment (server.tf:37-39) states attaching the placement group to the running web-1 **"forces a power-off → maintenance-window apply."** Adding `hcloud_server.web` to the *routine* per-PR `-target` list would, on the next arbitrary infra-PR merge, **reboot the production web host unattended** (and transitively create `hcloud_placement_group.web_spread`, and — via `for_each` — potentially provision web-2). The existing destroy-guard would NOT catch it (it is an in-place update, 0 destroy; the guard filter is Cloudflare-scoped). This is a `single-user incident` brand-survival regression, not a benign allow-list line.

**The root cause is operator-action-pending sequencing, not a forgotten allow-list entry.** The four `moved` blocks are transient migration scaffolding for the singleton→`for_each` cutover that ADR-068 Phase 3 GA always implied but never executed. The correct unblock is the **operator's Phase-3 maintenance-window full `terraform apply`**, which consumes all four moves (state re-address to `["web-1"]`), creates `web_spread`, and performs the planned power-off attach in a supervised window. Afterward there are **no pending moves in state** and the targeted CI plan self-heals with **zero workflow change**. One operator apply also unwedges the sibling `apply-deploy-pipeline-fix.yml`, which is failing on the identical error against the same R2 state.

This plan therefore delivers two independent, safe workstreams:

1. **A recurrence guard (ships now, code/test/docs-only, safe to merge independently):** extend `terraform-target-parity.test.ts` with a `moved`-block dimension so a future singleton→`for_each` migration that re-addresses an operator-excluded resource FAILS at plan-review time instead of silently wedging every targeted CI apply. Record the sequencing rule as an ADR-068 amendment + a learning.
2. **The operator cutover (post-merge, maintenance-window, operator-supervised):** a documented, gated runbook for the Phase-3 migration apply that actually clears the wedge. This is genuinely human-gated (a supervised production reboot / new-host provisioning = risk-acceptance judgment), not a tooling gap.

**We do NOT extend the per-PR `-target` allow-list with the host/volume bases** — doing so is rejected (Risks §R1).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #5887) | Reality (verified) | Plan response |
|---|---|---|
| Add 3 moved bases to the per-PR `-target` allow-list, mirroring #5566 | `hcloud_server.web` carries `placement_group_id` (server.tf:40) + `for_each = var.web_hosts`; targeting it reboots prod web-1 unattended and creates `web_spread`/web-2. #5566 was a genuinely per-PR secret; these are deliberately `OPERATOR_APPLIED_EXCLUSIONS`. | **Reject** the `-target` extension. Unblock via operator maintenance-window apply (§Phase 3). |
| Three resources are moved-implicated (`hcloud_server.web`, `hcloud_volume.workspaces`, `hcloud_volume_attachment.workspaces`) | **Four** `moved` blocks exist (placement-group.tf:23-41); the 4th is `hcloud_server_network.web`. Runtime error reports only 3 because `hcloud_server_network.web` is a Phase-2 resource **not yet in state** → its move is a no-op with nothing to move. | Guard covers **all four** moved bases via `MOVED_OPERATOR_CONSUMED`, not the runtime-reported subset. |
| Impact: `apps/web-platform/infra/**` changes do not auto-apply | Confirmed, **plus** `apply-deploy-pipeline-fix.yml` (lines 239/254, same R2 state) is also wedged; this workflow's own SSH-apply step (525-536) would fail too (moot — plan step aborts first). `scheduled-terraform-drift.yml` (full plan, no `-target`, line 100) is **not** wedged and correctly surfaces the moves as drift — the 12h backstop works. | Note blast radius; one operator apply unwedges all targeted workflows at once. |
| Extend the parity guard so moved endpoints must be in the `-target` set | Encoding "moved endpoint ⟹ must be in `-target`" would hard-code the *unsafe* fix as the required state. | Guard asserts each moved base ∈ (`allTargets` ∪ documented `MOVED_OPERATOR_CONSUMED`), failing only on an **unaccounted** moved block. |

## User-Brand Impact

**If this lands broken, the user experiences:** a production web-host reboot (or, worst case, a host replacement / a surprise web-2 provisioning) triggered by an *unrelated* infra PR merge — i.e. a mid-session outage of the Concierge/web-platform surface with no maintenance-window warning. This is exactly the failure mode the "reject the `-target` extension" decision prevents.

**If this leaks, the user's workflow is exposed via:** N/A — no data surface; the exposure vector is availability (unattended reboot), not confidentiality.

**Brand-survival threshold:** single-user incident — one operator whose live session dies on an unexpected host power-cycle is a brand-survival event. `requires_cpo_signoff: true`. CPO sign-off required at plan time before `/work` begins (Engineering/CTO review is complete; the product-owner ack is on the technical approach — reject the reboot-bearing `-target` edit). `user-impact-reviewer` runs at review time.

## Hypotheses

**Network-outage / SSH gate (plan Phase 1.4):** evaluated and **does not fire**. The failure is a Terraform *plan-time move-targeting* error, not an SSH/connectivity/handshake failure. The moved resources (`hcloud_server.web`, `hcloud_volume.workspaces`, `hcloud_volume_attachment.workspaces`) have no `provisioner`/`connection { ssh }` block in their own definitions (the SSH-provisioned `terraform_data.*` siblings are separate resources applied over the CF Tunnel bridge in a later, separate step). No L3→L7 firewall/egress diagnosis is in scope; the `hr-ssh-diagnosis-verify-firewall` checklist is not required here.

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)
1. `grep -n '^moved' apps/web-platform/infra/*.tf` — confirm the four `moved` bases and that they are the complete set (a future 5th block is exactly what the guard must catch).
2. Confirm each of the four moved bases is present in `OPERATOR_APPLIED_EXCLUSIONS` in `plugins/soleur/test/terraform-target-parity.test.ts` (lines 370-423) — they are (`hcloud_server.web`, `hcloud_volume.workspaces`, `hcloud_volume_attachment.workspaces`, `hcloud_server_network.web`).
3. Confirm the test runner: `plugins/soleur/test/*.ts` is `bun:test` (header line 48). Run the current suite green as a baseline: `bun test plugins/soleur/test/terraform-target-parity.test.ts`.
4. Do NOT run `terraform plan/apply` from the agent (no prd_terraform creds / R2 state in-session). The migration dry-run/apply is an operator maintenance-window step (Phase 3).

### Phase 1 — Extend the `moved`/`-target` parity guard (the recurrence fix)
Edit `plugins/soleur/test/terraform-target-parity.test.ts` (add a new `describe` block; do not disturb the existing SSH and #5566 blocks):
- Add a `parseMovedBlocks(stripped)` helper: match `moved\s*\{ … from = <addr> … to = <addr> … \}`, extract both endpoints, reduce each to its **base address** (strip a trailing `["…"]` index).
- Add a documented `MOVED_OPERATOR_CONSUMED` set — the four #5877 bases, each with a one-line rationale mirroring `OPERATOR_APPLIED_EXCLUSIONS` discipline: *"consumed by the ADR-068 Phase-3 maintenance-window apply; a routine per-PR `-target` add would reboot/replace the running host — see #5887."*
- Assert: every moved base ∈ (`allTargets` ∪ `MOVED_OPERATOR_CONSUMED`). Uncovered ⟹ fail.
- Add a **non-vacuity / synthetic-forgotten-moved-block** test mirroring the existing `synthetic_untargeted_ssh` pattern (lines 278-333): a synthetic `moved` block whose base is in neither set must be flagged uncovered (proves the guard bites).
- Add a **regression anchor**: assert the four #5877 bases are each in `MOVED_OPERATOR_CONSUMED` (so a later un-accounting fails loudly).
- Comment the WHY: the existing #5566 test treats "in `OPERATOR_APPLIED_EXCLUSIONS`" as sufficient coverage, which is **orthogonal** to Terraform's plan-time move-processing requirement — hence a new `moved`-keyed dimension, not a tweak to the existing check.

### Phase 2 — ADR-068 amendment + learning (capture the sequencing rule)
- Amend `knowledge-base/engineering/architecture/decisions/ADR-068-*.md` (append an `> **Amendment (2026-07-02, #5887)**` note under the existing Phase-3 amendment section): record that a `moved` block re-addressing a resource in `OPERATOR_APPLIED_EXCLUSIONS` **wedges every targeted CI apply** until an operator full apply consumes it; such migrations must ship **with** the operator cutover, never as a routine `-target` allow-list edit. Do NOT change the ADR's `status:` (still `adopting`).
- Write a learning `knowledge-base/project/learnings/<topic>.md` (author picks date at write-time; directory = `knowledge-base/project/learnings/` root or `bug-fixes/`): "a singleton→`for_each` `moved` migration on an operator-excluded resource red-lines target-scoped CI applies; unblock via operator cutover + a moved/`-target` guard, not an allow-list edit."

### Phase 3 — Operator cutover runbook (post-merge, maintenance window)
Author a `### Post-merge (operator)` runbook (below) for the Phase-3 migration apply. This clears the wedge. It is operator-gated (supervised prod reboot). Provide the canonical Doppler `tf-var` invocation triplet verbatim (per the drift-runbook Sharp Edge). Enroll a `follow-through` tracker so issue closure is gated on the apply succeeding (not on merge).

## Files to Edit

- `plugins/soleur/test/terraform-target-parity.test.ts` — add the `moved`/`-target` parity `describe` block + `MOVED_OPERATOR_CONSUMED` set + non-vacuity test (Phase 1).
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — append the #5887 sequencing amendment (Phase 2).

## Files to Create

- `knowledge-base/project/learnings/<topic>.md` — the sequencing-rule learning (Phase 2).
- `knowledge-base/project/specs/feat-one-shot-5887-moved-target-allowlist/tasks.md` — task breakdown (generated by plan skill).
- (operator, post-merge) no repo file — the migration is applied against live state; the runbook lives in this plan + the PR body.

**Deliberately NOT edited:** `.github/workflows/apply-web-platform-infra.yml` — the `-target` allow-list is intentionally left unchanged (Risks §R1). The workflow self-heals once the operator cutover lands.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes with the new `moved`/`-target` block.
- [ ] The new guard **fails** on a synthetic forgotten `moved` block (non-vacuity test asserts the uncovered base is flagged).
- [ ] The four #5877 moved bases are each asserted present in `MOVED_OPERATOR_CONSUMED` (regression anchor).
- [ ] `.github/workflows/apply-web-platform-infra.yml` diff is empty (no `-target` line added/removed) — verified by `git diff --stat` in the PR.
- [ ] ADR-068 amendment present; `git grep -n '5887' knowledge-base/engineering/architecture/decisions/ADR-068-*.md` returns ≥1.
- [ ] Learning file exists under `knowledge-base/project/learnings/`; `grep -rl 'moved' knowledge-base/project/learnings/ | head` includes it.
- [ ] Full suite green: `bun test plugins/soleur/test/` (sweeps the sibling destroy-guard / parity suites the `-target` allow-list is asserted on — no other suite regresses).
- [ ] PR body uses **`Ref #5887`** (NOT `Closes`) — the remediation completes in the post-merge operator apply, so auto-close on merge would produce a false-resolved state (`ops-remediation` class).

### Post-merge (operator) — maintenance window
- [ ] Operator runs a **dry-run** `terraform plan` (canonical invocation below) and confirms the plan is the expected Phase-3 cutover (`0 to destroy`; the only in-place change on `hcloud_server.web["web-1"]` is the placement-group attach; web-2 create iff `var.web_hosts` includes it). `Automation:` supervised prod reboot = human risk-acceptance judgment; the plan/apply itself is scriptable and provided as a copy-paste runbook (not a tooling gap).
- [ ] Operator runs `terraform apply` in the maintenance window; confirms web-1 power-cycles and returns healthy; confirms `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` next runs are **green** (no pending moves).
- [ ] `gh issue close 5887` after the apply succeeds (not before).
- [ ] `follow-through` tracker verifies the two workflows are green post-apply.

**Canonical operator invocation** (drift-runbook Sharp Edge — verbatim):
```bash
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
cd apps/web-platform/infra && terraform init -input=false
# DRY-RUN first — confirm 0-destroy + expected cutover scope:
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -var="ssh_key_path=<pubkey>"
# APPLY in the maintenance window (expect web-1 reboot):
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply -var="ssh_key_path=<pubkey>"
```

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (61 open) — no open scope-out references `apply-web-platform-infra.yml`, `terraform-target-parity.test.ts`, or `placement-group.tf`.

## Domain Review

**Domains relevant:** Engineering (infra/CI). Product NONE (no UI-surface file in Files-to-Edit/Create — mechanical override does not fire). Legal/Finance/Sales/Marketing/Support/Ops: none.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO assessment obtained and folded into this plan. Verdict table:

| Option | Action | Verdict |
|---|---|---|
| 1 (recommended) | Operator Phase-3 maintenance-window full `terraform apply` consumes moves + PG attach; CI self-heals; no workflow edit | **Do** |
| 2 | Add the (3 → transitively 4) bases to routine per-PR `-target` | **Reject** — unattended prod reboot, ADR-068 violation |
| 3 (parallel) | `moved`-block guard in `terraform-target-parity.test.ts` (`MOVED_OPERATOR_CONSUMED` shape) | **Do** — prevents recurrence |

Key CTO findings folded in: (a) Terraform move coverage is all-or-nothing (can't add the 2 safe bases and omit the reboot-bearing server); (b) targeting the server transitively drags in `hcloud_placement_group.web_spread`; (c) blast radius includes `apply-deploy-pipeline-fix.yml`; (d) guard must key on a new `moved` dimension (the #5566 exclusion check is orthogonal to plan-time move processing). No capability gaps.

## Infrastructure (IaC)

### Terraform changes
No `.tf` files are edited. This plan changes **who applies** the Phase-3 moved migration (operator maintenance window) and adds a CI **guard** — it introduces no new resource, provider, or `TF_VAR_*`.

### Apply path
(c-variant: taint/replace-class → here, an operator maintenance-window apply) The singleton→`for_each` migration + placement-group attach is an **operator maintenance-window `terraform apply`** (supervised, expected web-1 power-off reboot; possible web-2 create per `var.web_hosts`). It is NOT routed through the per-PR auto-apply `-target` path, because that path is unattended and this change reboots the running host. Expected downtime: one web-1 reboot cycle within the operator's window. After the apply, no pending moves remain → the per-PR target-scoped plan self-heals with no workflow change.

### Distinctness / drift safeguards
`dev != prd`: this is prd (`prd_terraform`). The `moved` migration is 0-destroy **only if** web-1's `name`/`server_type`/`location` in `var.web_hosts` match current state (a location change force-REPLACES the live host — server.tf comment). The dry-run `terraform plan` MUST show `0 to destroy` before apply. `scheduled-terraform-drift.yml` (full plan) is the 12h backstop and is already surfacing this as drift (working as designed). State lands in the encrypted R2 backend (`use_lockfile = false` — the shared GHA concurrency group is the serializer, not relevant to an operator-local apply).

### Vendor-tier reality check
N/A — Hetzner placement groups are free (max 10 servers/group; ADR-068 Cost Impacts).

## Observability

```yaml
liveness_signal:
  what: apply-web-platform-infra.yml + apply-deploy-pipeline-fix.yml run conclusion (green after operator cutover)
  cadence: on every merge to main touching apps/web-platform/infra/** ; 12h drift cron backstop
  alert_target: GitHub Actions run status (visible via `gh run list --workflow=apply-web-platform-infra.yml`); scheduled-terraform-drift.yml files an infra-drift issue
  configured_in: .github/workflows/apply-web-platform-infra.yml, apply-deploy-pipeline-fix.yml, scheduled-terraform-drift.yml
error_reporting:
  destination: GitHub Actions job annotations (::error::) — the plan step already surfaces the terraform error loudly
  fail_loud: true
failure_modes:
  - mode: a future singleton to for_each moved block re-addresses an operator-excluded resource and re-wedges targeted CI
    detection: bun test plugins/soleur/test/terraform-target-parity.test.ts (new moved/-target block) FAILS at plan-review time
    alert_route: CI required check on the PR (pre-merge, before the wedge reaches main)
  - mode: operator cutover not yet run so workflows stay red
    detection: gh run list shows failure; scheduled-terraform-drift.yml infra-drift issue
    alert_route: follow-through tracker + infra-drift label
logs:
  where: GitHub Actions run logs (plan step); operator-local terraform plan/apply output during cutover
  retention: GitHub default (90d)
discoverability_test:
  command: gh run list --workflow=apply-web-platform-infra.yml --limit 3
  expected_output: post-cutover runs show success (pre-cutover show failure with the moved-targeting error)
```

### Soak follow-through enrollment
Post-cutover close criterion (both workflows green) is time/action-gated on an operator apply → enroll a `follow-through` tracker with the `follow-through` label and a directive so #5887 closes only after the two workflows are observed green post-apply. Verification script (`scripts/followthroughs/<name>-5887.sh`): assert the most-recent `apply-web-platform-infra.yml` AND `apply-deploy-pipeline-fix.yml` runs on `main` are `success`.

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-068** (do not create a new ADR; do not change `status: adopting`). Append `> **Amendment (2026-07-02, #5887)**`: a `moved` block that re-addresses a resource in `OPERATOR_APPLIED_EXCLUSIONS` wedges every target-scoped CI apply (`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`) until an operator full apply consumes the pending move; singleton→`for_each` migrations on operator-excluded hosts must ship **with** the operator cutover, never as a routine `-target` allow-list edit. This is an in-scope task of THIS plan (Phase 2), not a deferred follow-up.

### C4 views
**No C4 impact.** Checked all three model files (`model.c4`, `views.c4`, `spec.c4`). Enumeration:
- **External human actors:** none added/changed (this is a CI-plumbing + operator-runbook change).
- **External systems / vendors:** none added — Hetzner Cloud is already modeled (`model.c4:164` `hetzner = container "Compute"`, description already reads "Cluster of Hetzner Cloud hosts … spread placement (ADR-068)").
- **Containers / data stores:** none added — the web-host cluster + placement spread is already in the `hetzner` container description; this change alters *which workflow applies* the hosts, not the topology.
- **Access relationships:** none changed — no new actor↔surface edge.
ADR-068 already recorded the multi-host C4 impact (its `## C4 impact` section, ADR-068:501). This fix does not add or move any C4 element.

## Test Scenarios

1. **Guard passes on current tree:** the four #5877 moved bases are covered by `MOVED_OPERATOR_CONSUMED` → suite green.
2. **Guard fails on a forgotten moved block:** synthetic `moved { from = hcloud_foo.bar; to = hcloud_foo.bar["k"] }` with base in neither set → flagged uncovered (non-vacuity).
3. **Guard permits a genuinely per-PR-targeted move:** a synthetic moved base that IS in `allTargets` → covered (does not false-fail).
4. **No workflow drift:** `git diff .github/workflows/apply-web-platform-infra.yml` is empty.
5. **Full suite:** `bun test plugins/soleur/test/` green (destroy-guard/parity siblings unaffected).

## Risks & Mitigations

- **R1 — Extending the per-PR `-target` allow-list (issue's literal ask) reboots prod.** `hcloud_server.web` carries `placement_group_id` (reboot on attach) + `for_each` (web-2 create); targeting it transitively creates `hcloud_placement_group.web_spread`. Destroy-guard does NOT catch an in-place reboot. **Mitigation:** reject the `-target` edit; unblock via operator cutover. This is the central decision.
- **R2 — Operator cutover not run → workflows stay red.** Drift accumulates (issue's stated impact); the 12h drift cron is the backstop and is already surfacing it. **Mitigation:** `follow-through` tracker + `Ref #5887` (close only after apply).
- **R3 — Cutover apply shows unexpected destroy/replace.** A `var.web_hosts` web-1 attribute drift (location/server_type) would force-replace the live host. **Mitigation:** mandatory dry-run showing `0 to destroy` before apply (server.tf comment + ADR-068 NFR-016).
- **R4 — 4th moved block (`hcloud_server_network.web`) joins the pending set later.** When the operator provisions the Phase-2 private network, its move becomes pending. **Mitigation:** the operator full apply consumes it in the same cutover; the guard already accounts for it via `MOVED_OPERATOR_CONSUMED`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this one is filled (threshold `single-user incident`, `requires_cpo_signoff: true`).
- Terraform `-target` move coverage is **all-or-nothing** — you cannot add the two safe bases (volume/attachment) and omit the reboot-bearing server; the error demands all three together. This is *why* the naive fix is unsafe (the server target is mandatory if you go that route).
- The guard must NOT encode "moved endpoint ⟹ must be in `-target`" — that hard-codes the rejected fix as the required state. Key it on `allTargets ∪ MOVED_OPERATOR_CONSUMED`.
- The learning filename must be date-picked at write-time (do not pin a date in tasks.md).

## Deferral Tracking

- The operator maintenance-window cutover is tracked via `Ref #5887` (stays open until applied) + a `follow-through` tracker — not a separate deferral issue (it IS the remediation, not out-of-scope).
- No "Alternative Approaches / Non-Goals" items are deferred beyond the operator apply.
