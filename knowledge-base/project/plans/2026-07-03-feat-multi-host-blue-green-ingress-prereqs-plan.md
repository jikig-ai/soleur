---
title: "Multi-host blue-green ingress prerequisites (ADR-068 GA) — unwedge CI zero-downtime + warm web-2 standby"
date: 2026-07-03
type: feat
branch: feat-multi-host-blue-green-ingress
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: []
refs: [5887, 5877, 5274]
---

# Multi-host blue-green ingress prerequisites (ADR-068 GA)

## Overview

ADR-068's multi-host GA needs web-2 to be able to serve traffic so that the pending
web-1 placement-group reboot (and the git-data cutover) can happen **zero-downtime**.
This plan delivers the *safe, additive prerequisites* and the *design* for the GA — it
does **not** perform the ingress cutover, the git-data LUKS migration, or the web-1
reboot (all deferred to the GA maintenance window, tracked separately).

Two shippable deliverables + one design deliverable:

- **Phase 1 — Unwedge CI, zero reboot (normal PR).** Add `lifecycle { ignore_changes =
  [placement_group_id] }` to `hcloud_server.web`. **Verified today:** this drops the full
  plan from `31 add, 2 change` to `31 add, 1 change, 0 destroy` — web-1's
  `~ placement_group_id = 0 → 1739811` (the reboot-forcer, and the sole trigger of the
  `reboot_updates` destroy-guard from #5911) **disappears from every plan**. The CI
  targeted apply drags web-1 in only as a no-op → the guard passes → both apply pipelines
  go green with **zero reboot**. The follow-through sweeper (`moved-block-wedge-5887.sh`)
  then closes **#5887**. This is the true zero-downtime resolution of the CI wedge.
- **Phase 2 — Warm web-2 standby (autonomous dispatch, zero user impact).**
  Dispatch `gh workflow run apply-web-platform-infra.yml -f apply_target=warm-standby` — the
  R2-serialized workflow provisions the private network + web-2 `/workspaces` volume/attachment
  through the concurrency serializer, fans the deploy out to web-2 over the host-side private
  net, and confirms web-2 accepted the deploy off-host via web-1's deploy-status `reason` (no
  local command, no SSH, no private-IP curl). Ingress stays untouched (single proxied A record →
  web-1). web-2 becomes a warm, deploy-current standby that is **in no public serving pool**.
  Records the new recurring expense.
- **Design deliverable — ADR-068 amendment (no apply).** Capture the deferred GA ingress
  design (Cloudflare Load Balancer, health-checked, web-2 weight 0→1 gated on GA), the
  reboot-deferral invariant, and the sequencing that makes the eventual web-1 reboot
  zero-downtime. File the `/health` deep-readiness follow-up (see Sharp Edges C1).

**Why not build the load balancer now?** The domain review (CTO + spec-flow) converged:
before the in-process user-sticky router is activated **and** the git-data store is cut
over, web-2 physically cannot serve a web-1 user's session (each host has its own
`/workspaces` volume; the router that would proxy to the lease-holder is gated off by
`isGitDataStoreEnabled()`, default off). So any live traffic to web-2 = workspace-gone
**single-user incident**, and building the LB now buys no serving value while taking on the
A→LB live-record migration hazard + a paid recurring cost + a health-green-lie failover
risk. The LB therefore belongs to the GA cutover window, not to "prerequisites."

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #5887 / initial framing) | Reality (verified 2026-07-03) | Plan response |
|---|---|---|
| CI is wedged on pending `moved` blocks ("Moved resource instances excluded by targeting") | **Stale.** `moved` blocks already consumed in state (full plan shows no pending moves). CI's *current* red cause is the `reboot_updates` destroy-guard (#5911) halting on web-1's pending `placement_group_id` change. | Phase 1 defers the placement change via `ignore_changes` → guard passes → green. |
| The wedge clears only via a full apply that power-cycles web-1 | **False now.** `ignore_changes = [placement_group_id]` clears it with zero reboot (verified: `31 add, 1 change, 0 destroy`, no `placement_group_id` diff). | Phase 1 is the zero-downtime clear; the reboot is deferred to GA. |
| web-2 needs provisioning | web-2 **server already exists** in TF state (`hcloud_server.web["web-2"]`, id 147422810, running). Its `/workspaces` volume + private-net attach are pending creates. | Phase 2 creates the volume/attach only; no server create. |
| Convert `cloudflare_record.app` singleton→for_each for multi-host ingress | dns.tf comment: this is a destroy+recreate of the LIVE app record (no `moved`, no stable import id). spec-flow H2: a CF hostname is *either* a proxied A record *or* an LB — the swap has an inherent gap. | Ingress **untouched** this plan; LB/record migration deferred to GA and flagged for CF-behavior verification (Sharp Edge). |
| `/health` can gate web-2 readiness | **False.** `server/health.ts` hardcodes `status:"ok"` and only probes shared Supabase; returns 200 with an empty `/workspaces`. A routing lie. | web-2 verified on private IP only; deep-readiness endpoint filed as follow-up (Sharp Edge C1). |
| Cloudflare provider is v5 (research note) | **Repo pins `cloudflare ~> 4.0`** (`.terraform.lock.hcl` → 4.52.7). | Any deferred LB stanza uses v4 syntax; drain via origin `weight=0` (not v5 `endpoint_drain_duration`). |

**Premise validation:** #5887 OPEN; #5908 (`MOVED_OPERATOR_CONSUMED`) merged; #5911
(`reboot_updates`) live (its error text appears in the current red CI run 28648411099);
#5922 (web-2 user_data 32KB fix) merged; runbook PR #5946 open. No stale blockers.

## User-Brand Impact

**If this lands broken, the user experiences:** a web-1 reboot or a live request routed to
web-2 (empty `/workspaces`) → a fresh-session greeting with their repo/conversation state
gone (the #5240-class workspace-gone incident).

**If this leaks, the user's workflow is exposed via:** N/A for this plan — no new
data-processing path is activated (web-2 is warm-but-drained; the git-data store stays off,
`isGitDataStoreEnabled()=false`). The Article-30 / EU-residency lockstep for git-data
processing lands with the GA cutover, not here. web-2 stays EU-pinned (`hel1`).

**Brand-survival threshold:** single-user incident. → `requires_cpo_signoff: true`.
`user-impact-reviewer` runs at review time.

## Implementation Phases

### Phase 1 — Defer the web-1 placement reboot; unwedge CI (zero reboot)

**Files to edit:**
- `apps/web-platform/infra/server.tf` — extend the `hcloud_server.web` `lifecycle`
  block (currently `ignore_changes = [user_data, ssh_keys, image]`, server.tf:135-137) to
  `ignore_changes = [user_data, ssh_keys, image, placement_group_id]`. Add a comment: this
  is a **temporary GA-deferral** — web-1 stays out of the `web_spread` placement group
  until the GA window, whose first diff is removing this entry to take the reboot on a
  drained host. web-2 already carries `placement_group_id = 1739811` (born into the group),
  so this ignore only defers web-1.
- `plugins/soleur/test/terraform-target-parity.test.ts` and
  `tests/scripts/lib/destroy-guard-filter-web-platform.jq` — **verify only, likely no
  edit.** The `reboot_updates` clause keys on `placement_group_id`/`server_type` changes;
  with the attribute ignored there is nothing to detect. Add a test asserting a plan with
  the ignore present yields `reboot_updates = 0` for `hcloud_server.web` (guards against a
  future removal of the ignore silently re-wedging CI).

**Phase 0 verification gate (already run — record in the PR):**
```
# read-only, no mutation; runbook worktree, prd_terraform creds
terraform plan → BEFORE: "Plan: 31 to add, 2 to change, 0 to destroy" (web-1 ~placement_group_id 0→1739811)
terraform plan (with ignore_changes) → AFTER: "Plan: 31 to add, 1 to change, 0 to destroy" (only hcloud_firewall_attachment.web in-place; NO placement_group_id diff)
```

**Apply path:** normal PR → merge → `apply-web-platform-infra.yml` auto-applies the
`-target`-scoped set. With the reboot gone, the destroy-guard passes and the in-place
`hcloud_firewall_attachment.web` update (server_ids += web-2) applies cleanly. **Both** red
pipelines (`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`) go green →
`moved-block-wedge-5887.sh` closes #5887. Zero reboot, zero downtime, fully autonomous on
merge (no locally-run apply).

### Phase 2 — Warm web-2 standby (autonomous dispatch; deferred until expense approved)

> Dispatched through the R2 concurrency serializer, never run locally (these resources are
> `OPERATOR_APPLIED_EXCLUSIONS`, excluded from the per-PR auto-apply target sets). Zero user
> impact — web-2 is not in ingress. Gated on recurring-expense approval.

**Trigger (post-merge, acknowledged-menu, not authored).**
`gh workflow run apply-web-platform-infra.yml -f apply_target=warm-standby`. The dispatch job
runs the whole sequence inside the serializer; there is no local command, no SSH, and no
private-IP curl. (The `apply_target=warm-standby` path itself is delivered by
`2026-07-04-feat-autonomous-multihost-ga-warm-standby-and-gate-plan.md`.)

**Step 0 — State reconciliation (blocking, read-only, in-job).** The job confirms
`hcloud_server.web["web-2"]` is in state (VERIFIED: refreshes with id 147422810) and that the
plan shows `0 to destroy` and **no** `placement_group_id`/reboot diff on
`hcloud_server.web["web-1"]` before applying.

**Step 1 — Additive infra, precisely targeted (in the serializer).** The dispatch plans then
applies the 6 additive resources — `hcloud_network.private`, `hcloud_network_subnet.private`,
`hcloud_server_network.web["web-1"]` (online attach, no reboot),
`hcloud_server_network.web["web-2"]`, `hcloud_volume.workspaces["web-2"]`,
`hcloud_volume_attachment.workspaces["web-2"]` — via the canonical invocation (raw `AWS_*` for
the R2 backend + `doppler -p soleur -c prd_terraform --name-transformer tf-var`), after the
plan-scoped destroy-guard asserts `reboot_updates=0`. The apply's created-resources output is
the **attach proof** (no reachability probe needed). `hcloud_placement_group.web_spread` and the
git_data resources are never in the target set.

**Step 2 — Deploy to web-2 + confirm acceptance off-host (no SSH).** The job triggers the
host-side deploy fan-out (`ci-deploy.sh fan_out_to_peers` over the private net;
`WEB_HOST_PRIVATE_IPS` already carries `10.0.1.11`). **Gate:** read web-1's
`/hooks/deploy-status` `reason` off-host (`reason=="ok"` vs `ok_peer_fanout_degraded`) — the
reachable web-2-accepted signal — never via a public hostname/pool and never via a private-IP
curl.

**Step 3 — Confirm safe end-state (read-only).** web-1 still serves 100% via the unchanged
A record; web-2 is a warm standby in no serving pool. Records the recurring expense
(see IaC §Vendor-tier).

### Deferred to the GA maintenance window (NOT this plan — captured in the ADR)

Ingress cutover (LB or in-place CF convert), `GIT_DATA_STORE_ENABLED=true` flip, owner-side
relay env activation (`SOLEUR_PROXY_BIND`/`PEER_ALLOWLIST`/`HOST_ROSTER`), git-data LUKS
cutover, remove `ignore_changes=[placement_group_id]` → drain web-1 → reboot web-1 → restore —
all executed by the deferred cutover orchestrator (an Inngest-dispatched GHA maintenance-window
workflow), never a human step. The web-2 LB weight flip 0→1 is gated on
`apps/web-platform/infra/lb-weight-gate.sh` (the fail-closed, SHAPE-ONLY §(c) check that emits
`requires_runtime_bind_probe=true`) **plus** the orchestrator's separate on-host runtime-bind
probe — see `2026-07-04-feat-autonomous-multihost-ga-warm-standby-and-gate-plan.md`.

## Infrastructure (IaC)

### Terraform changes
- **Phase 1:** `apps/web-platform/infra/server.tf` `lifecycle.ignore_changes += placement_group_id`. No provider, variable, or resource additions. No cost.
- **Phase 2:** creates `hcloud_network.private`, `hcloud_network_subnet.private`,
  `hcloud_server_network.web[*]`, `hcloud_volume.workspaces["web-2"]` (20 GB) + attachment.
  All already defined in `network.tf`/`server.tf`; no new `.tf` authoring.
- **Deferred (ADR only, not applied):** `cloudflare_load_balancer` + `_pool` + `_monitor`
  in **v4 syntax** (repo pins `cloudflare ~> 4.0`), `count = var.cf_load_balancing_enabled
  ? 1 : 0`, a dedicated narrow `cf_api_token_load_balancing` token (default token lacks LB
  scope), monitor `path=/health expected_codes="2xx"` **reachability-only — MUST NOT parse
  the `supabase` body field** (both hosts share one Supabase; a body-coupled monitor would
  eject the sole live origin on a DB blip), pool with web-1 weight 1 / web-2 weight 0.

### Apply path
- Phase 1: CI auto-apply on merge (in-place firewall update, `0 reboot`, `0 destroy`).
- Phase 2: dispatched via `apply_target=warm-standby` through the R2 concurrency serializer
  (never run locally, never remote-shell); expected downtime **zero** (the private-net attach is
  online; the web-2 volume touches a non-serving host; no reboot-bearing change is targeted). The
  dispatch's created-resources output is the attach proof.
- Reboot-exclusion mechanism (load-bearing): the `moved` blocks force `hcloud_server.web`
  into any targeted plan, so it cannot be `-target`-excluded — `ignore_changes =
  [placement_group_id]` (Phase 1) is what makes it a 0-change no-op. Phase 1 must merge
  before the Phase 2 dispatch.

### Distinctness / drift safeguards
- `ignore_changes=[placement_group_id]` is **temporary** — the GA PR removes it to take the
  reboot. Document with the removal trigger inline.
- Any deferred LB carries `count = var.cf_load_balancing_enabled ? 1 : 0`, default `false`
  → no accidental spend in dev; fully reversible.

### Vendor-tier reality check
- **New recurring cost from Phase 2:** web-2 `/workspaces` 20 GB Hetzner volume ≈ €0.88/mo.
  (web-2 server itself already exists/accrues ~€13/mo — not created here.)
- **Deferred (GA):** Cloudflare Load Balancing paid add-on ≈ $5/mo (60s health interval at
  base tier) + git-data host (`cax11` ≈ €3.79/mo) + LUKS/git-data volumes.
- Record Phase 2's volume expense in `knowledge-base/finance/expenses.md` before PR-ready
  (`wg-record-recurring-vendor-expense-before-ready`). *Verify live pricing before budget
  decisions.*

## Observability

```yaml
liveness_signal:
  what: warm-standby dispatch conclusion + the apply's created-resources output (attach proof) + web-1 deploy-status reason=="ok" (web-2 accepted the deploy)
  cadence: on-dispatch (Phase 2) + existing web-1 public /health poll (release workflow)
  alert_target: Better Stack (existing web-1 monitor); dispatch failure = red GHA run
  configured_in: .github/workflows/apply-web-platform-infra.yml + apps/web-platform/infra/cat-deploy-state.sh
error_reporting:
  destination: Sentry (existing web-platform DSN)
  fail_loud: the warm-standby dispatch fails loudly on reason=~_peer_fanout_degraded or a partial apply
failure_modes:
  - mode: web-2 never accepted the deploy (unbound :9000 / fan-out degraded)
    detection: web-1 deploy-status reason=="ok_peer_fanout_degraded" (off-host, no SSH)
    alert_route: dispatch run red; no ingress change made
  - mode: Phase 1 ignore_changes silently re-wedges CI if later removed without the reboot
    detection: terraform-target-parity test asserting reboot_updates=0 with ignore present
    alert_route: CI red on the parity suite
  - mode: web-2 accidentally added to a public serving pool pre-GA (workspace-gone)
    detection: ADR gate — no cloudflare_load_balancer resource ships this plan; grep guard
    alert_route: review-time (user-impact-reviewer) + ADR hard gate
logs:
  where: host pino → stdout (existing); Sentry breadcrumbs
  retention: existing web-platform retention
discoverability_test:
  command: "gh run list --workflow=apply-web-platform-infra.yml --branch main --limit 1 --json conclusion  (expect success post-Phase-1)"
  expected_output: '"conclusion":"success"'
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-068** (`/soleur:architecture`) with a "Blue-green ingress prerequisites &
reboot deferral" section recording: (1) the temporary `ignore_changes=[placement_group_id]`
web-1 reboot-deferral and its GA-window removal trigger; (2) the deferred GA ingress design
— Cloudflare LB, health-checked, **monitor must be reachability-only (not supabase-body-
coupled)**, web-2 weight 0 until 3.C merged + 3.D git-data cutover soak-verified; (3) the
hard invariant: **no live LB weight to web-2 before the router owner-side relay is active
AND git-data is cut over.** This is squarely within the ADR-068 multi-host arc — amend, do
not create a new ADR.

### C4 views
Checked `model.c4`/`views.c4`/`spec.c4`: web-1/web-2 as web-host containers and the
Cloudflare ingress edge are already modeled from the Phase-3 work; this plan adds no new
external actor/system/data-store (web-2 warm standby, ingress unchanged). The LB element +
git-data replication edges land with the GA amendment, not here. **No C4 edit this plan**
(actors checked: end user, Cloudflare edge, Hetzner hosts, Supabase — all already modeled;
no new access relationship until GA activates cross-host serving).

### Sequencing
The ADR is authored now (status: adopting) describing the target GA ingress; the LB/relay/
git-data activation is the GA window, gated as above.

## Domain Review

**Domains relevant:** Engineering (CTO), Finance/Ops (expense), Legal (deferred to GA).

### Engineering (CTO)
**Status:** reviewed. **Assessment:** Ruled Candidate A's *live* form unsafe (weight-0-in-a-
live-pool still takes the A→LB migration + health-green-lie risk); confirmed the router is
gated off by `isGitDataStoreEnabled()` (default off) so round-robin to web-2 = data-loss;
zero-downtime web-1 reboot requires BOTH the owner-side relay AND git-data cutover (the GA
line). Recommended: ship the additive prereqs + defer the LB/ingress to the GA window.
Flagged the `/health` monitor-coupling hazard (adopted into Sharp Edges + the ADR).

### Finance/Ops
**Status:** deferred to COO/CFO. Phase 2 adds ~€0.88/mo (web-2 volume); GA adds the CF LB
(~$5/mo) + git-data host. Record before PR-ready.

### Product/UX Gate
**Tier:** none. No user-facing surface (infra/ingress only; no `components/**`, no
`app/**/page.tsx`).

## Acceptance Criteria

### Pre-merge (Phase 1 PR)
- [ ] `hcloud_server.web` `lifecycle.ignore_changes` includes `placement_group_id` with a temporary-deferral comment naming the GA removal trigger.
- [ ] `terraform-target-parity.test.ts` asserts a plan with the ignore present yields `reboot_updates = 0` on `hcloud_server.web`.
- [ ] PR body uses `Ref #5887` (NOT `Closes` — the follow-through sweeper closes it post-merge once both pipelines are green; ops-remediation class).
- [ ] No `cloudflare_load_balancer*` resource is added (grep-verified in review — LB is GA-deferred).
- [ ] ADR-068 amendment committed in this PR (reboot-deferral + deferred ingress design + monitor-coupling rule).

### Post-merge (autonomous dispatch)
- [ ] Both `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` latest `main` runs = `success` (pull via `gh run list`, no dashboard).
- [ ] `moved-block-wedge-5887.sh` PASS → #5887 auto-closed.
- [ ] **(Phase 2, gated on expense approval)** the `apply_target=warm-standby` dispatch provisions the private net + web-2 volume/attach; the run's plan showed `0 to destroy` + no web-1 placement reboot; web-2 accepted the deploy (web-1 deploy-status `reason=="ok"`, off-host, no SSH); expense recorded.

## Sharp Edges

- **C1 — `/health` is a routing lie → deep-readiness endpoint DELIVERED (#5966).**
  `server/health.ts` hardcodes `status:"ok"` and only probes shared Supabase → returns 200 with
  an empty `/workspaces`, so web-2 must NEVER be a monitored member of a public serving pool on
  `/health` alone. **Resolved:** `GET /internal/readyz` (`server/readiness.ts`, loopback-peer
  gated) returns non-2xx unless the responding host's `/workspaces` is **writable AND populated**
  — the pre-pool readiness gate for web-2. The GA LB pre-pool check / drain tooling MUST consult
  it before granting live weight, and MUST require **N≥2 consecutive** not-ready reads before
  draining a *live* origin (fail-closed single-shot bias applies only to the candidate/pre-pool
  decision). Still necessary-but-not-sufficient: it does NOT relax the hard invariant (relay
  active AND git-data cut over). See ADR-068 amendment (2026-07-03, #5966) and
  `knowledge-base/project/plans/2026-07-03-feat-deep-readiness-endpoint-workspaces-mount-plan.md`.
- **A→LB migration is a live-record operation (verify CF behavior before GA).** A CF hostname
  is either a proxied A record or an LB. best-practices research claims the LB takes DNS
  precedence gaplessly if both proxied; spec-flow warns of an NXDOMAIN/409 window. This is a
  load-bearing vendor-behavior claim — **verify against Cloudflare docs + a staging convert
  before the GA window** (do not assert gapless). Never do the A→LB swap under a "prereq" banner.
- **firewall_attachment for_each drag-in.** `firewall.tf` `server_ids = [for h in
  hcloud_server.web : h.id]` references the whole map; `-target`ing it pulls
  `hcloud_server.web["web-1"]` into the closure. Safe now (Phase 1's `ignore_changes` makes
  the server a no-op) — but never `[ack-destroy]` through a reboot on the unattended path.
- **`moved` blocks evaluate globally at plan time** regardless of `-target` — the operator
  must read the plan and not mistake the (already-consumed) re-address for a change.
- **Do not `[ack-destroy]` the CI wedge.** The correct fix is Phase 1's `ignore_changes`
  (zero reboot), never acking the reboot through the unattended apply (#5911's whole point).
- **`ignore_changes` removal is the GA PR's first diff** — leaving it forever means web-1
  never joins the HA spread group. Track its removal as a GA deliverable.

## Open Questions
1. Expense approval for Phase 2 (web-2 20 GB volume ~€0.88/mo) and the deferred GA CF LB (~$5/mo) — COO/CFO sign-off before Phase 2 apply.
2. GA ingress primitive: Cloudflare LB (health-checked drain, paid) vs. in-place CF convert — decide in the ADR/GA plan after verifying the CF record→LB migration behavior.
