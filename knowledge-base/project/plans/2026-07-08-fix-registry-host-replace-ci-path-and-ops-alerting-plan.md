---
title: "fix: registry-host-replace CI path + Better Stack ops@ recipient IaC"
date: 2026-07-08
type: fix
classification: ops-remediation
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
issue_refs: ["#6122 (ADR-096)", "#6178/#6197 (ADR-100)"]
incident: "Better Stack — soleur-registry-disk-prd | Missed heartbeat (2026-07-08 15:30 CEST, unacknowledged)"
---

# 🐛 fix: registry-host-replace CI path + Better Stack ops@ recipient IaC

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Note: systemctl/resize2fs/docker-run mentions in prose QUOTE the existing cloud-init-registry.yml (host first-boot config already routed through Terraform user_data); this plan prescribes NO manual host step. All apply is via Terraform + a dispatch workflow. See the Infrastructure (IaC) section. -->

## Overview

A Better Stack incident fired at 2026-07-08 15:30 CEST — **`soleur-registry-disk-prd | Missed heartbeat`** — and stayed unacknowledged. This is **not a genuine disk-full event**. It is a **deploy-sequencing false positive**: the 2026-07-08 zot capacity-management merge created a NEW disk-full heartbeat resource (`betteruptime_heartbeat.registry_disk_prd`, `paused=false`) in Better Stack, but the registry **host was never redeployed** with the cloud-init that installs the `zot-disk-heartbeat.sh` self-ping cron. The heartbeat has therefore **never received a ping** (its Better Stack `status` is `pending`/`down`) — Better Stack alerts on the absence. The same missing redeploy means the merge's actual disk-full mitigations — `storage.retention` pruning and the 10→30 GB volume grow — are **also not live**, so the original registry disk-full risk (#6122: 100 % → all pushes `500 no space left on device`) remains unmitigated.

Two structural gaps produced this:

1. **No CI reprovision path for the registry host.** `apps/web-platform/infra/zot-registry.tf` resources are, by a CTO ruling (Research Reconciliation), `OPERATOR_APPLIED_EXCLUSION`s — deliberately NOT in the per-PR `-target=` allow-list of `.github/workflows/apply-web-platform-infra.yml`, which bridges over SSH to the *existing* web host and cannot provision a brand-new host. The dedicated **inngest** host (same posture) has an `inngest-host-replace` `workflow_dispatch` escape hatch to re-run its cloud-init; the **registry** host has none. So there is no non-SSH mechanism to reprovision it. (The framing "the allow-list is missing the registry" is *incomplete* — the exclusion is intentional; the real gap is the missing **dispatch-replace** path, exactly the shape inngest already has.)
2. **No IaC-managed alert recipient.** `betterstack_paid_tier` defaults `false`, so every heartbeat runs `policy_id = null` (email-only, no escalation policy). ops@jikigai.com is not a Better Stack team member and recipients are not managed in Terraform at all — so only the account owner (jean.deruelle@jikigai.com) was emailed.

**FIX A** — add a `registry-host-replace` `workflow_dispatch` path mirroring `inngest-host-replace`: a scoped `terraform apply -replace='hcloud_server.registry'` over a **5-target** set (server + its 3 id-referencing dependents + the storage volume) with a sourced destroy-guard that **preserves** `hcloud_volume.registry` (permits only a size-increasing resize, forbids delete/replace) and positively asserts the new host is re-attached to its private NIC + deny-all firewall. This single dispatch activates all three merged-but-un-live mitigations at once (new cloud-init installs the disk-heartbeat cron + `storage.retention`; the 10→30 GB volume resize rides in as a dependency update).

**FIX B** — add `betteruptime_team_member.ops` (email = ops@jikigai.com) as the free-tier IaC recipient path, so future heartbeat/monitor alerts reach ops@ without a manual UI step. (Inert until ops@ accepts the one-time invite — see FIX B framing.)

**After merge** — trigger the new dispatch path and verify from the observability layer (self-pull) that the disk heartbeat `status` transitions to `up` and the incident auto-resolves; this also confirms retention + the 30 GB volume are now live.

## Research Reconciliation — Spec vs. Codebase

| Diagnosis / draft claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "the `-target` allow-list does NOT include `hcloud_server.registry`… so there is no CI mechanism to reprovision" | **TRUE but by design.** `zot-registry.tf:15-21` records a CTO ruling (2026-07-06): every registry resource is an `OPERATOR_APPLIED_EXCLUSION`; the per-PR path bridges over SSH to the existing web host and cannot provision a fresh host. `terraform-target-parity.test.ts:536-570` lists the registry resources as exclusions. | Do NOT add registry to the per-PR allow-list. Add a **dispatch-only** `registry-host-replace` job. Correct the PR-body framing. |
| Replace scope = server + volume + heartbeat | The server is at `zot-registry.tf:183`. Its id-referencing **dependents** (ForceNew/update on replace) are `hcloud_server_network.registry` (**network.tf:57**), `hcloud_volume_attachment.registry` (`:251`), `hcloud_firewall_attachment.registry` (`:270`). **`hcloud_volume.registry` (`:240`) is ALSO in-graph** — the server `user_data` interpolates `hcloud_volume.registry.id` (`:208`), so `-target=hcloud_server.registry` pulls it in, and its live size is **10 GB vs the config default 30 GB** (`variables.tf:126`) → a pending in-place `["update"]` resize. | **5-target** scoped plan: `-replace='hcloud_server.registry'` + `-target=` for server, server_network, volume_attachment, firewall_attachment, **and `hcloud_volume.registry`**. The gate PERMITS the volume's size `["update"]` (this is *how* the 30 GB grow goes live) but forbids delete/forget/replace. Without the volume in-scope the guard would abort the very fix the incident needs (caught by 3 independent reviewers). |
| "mirror `inngest-host-replace` exactly" (implying 3 targets, no firewall) | `inngest_host_replace` targets **3** (server + server_network + volume_attachment) and **deliberately omits** `hcloud_firewall_attachment.inngest` (`inngest-host.tf:286-292`: `server_ids` is update-in-place, not ForceNew, so a scoped replace does not re-plan it). | **Intentional deviation, not mirroring:** the registry has a real deny-all-public firewall to preserve (`zot-registry.tf:262-273`); a `-target`ed dependent that isn't listed is *not* re-planned, so the new host would boot **without** the firewall on its public IP. We add `hcloud_firewall_attachment.registry` as the 4th dependent (update-in-place) so the new host is protected immediately. Labelled a deviation so a reviewer doesn't "correct" it back to 3. |
| draft: "`stripDispatchJobs()` explicitly accommodates the replace path" | `stripDispatchJobs()` (`terraform-target-parity.test.ts:412-420`) strips `warm_standby`, `web_2_recreate`, **`inngest_host`** (the net-new job) — NOT `inngest_host_replace`. `stripJob` matches the header exactly (`^ {2}<id>:`), so the *replace* job's `-target`s currently fold into the coverage anchor (benign only because they are exclusions). | Do NOT assert the strip is "Required" a priori. **Empirically validate** (Phase 3.3): run parity with `registry_host_replace` present-but-unstripped; add the strip only if it goes RED; if green, note it as belt-and-suspenders. Use the exact literal `"registry_host_replace"` (copying `"inngest_host"`→`"registry_host"` would strip nothing). |
| "add ops@ as a managed recipient (works on the free tier)" | Provider `BetterStackHQ/better-uptime ~> 0.20` (main.tf:41-44). `betteruptime_policy` (escalation) is paid-only, gated `count = var.betterstack_paid_tier ? 1 : 0`. `betteruptime_team_member` exists (`email` required; `role` optional default `responder`; `team_name` optional "used to specify the team when using global tokens"), confirmed absent today. Whether free-tier unassigned-incident email reaches a **non-owner** member is not doc-confirmed; a **pending (un-accepted) invite receives no alerts**. | FIX B = `betteruptime_team_member.ops` (the IaC path to exhaust). Ship it; Phase 0 confirms the resource, the `team_name`-for-global-token need, the free-tier seat limit, and a valid `role`. Reframe: FIX B *provisions* the recipient in IaC; *activation* is the one-time invite accept (ops@'s own inbox). Document the webhook/paid-tier fallback. |
| draft Better Stack verify via `last_event_at` | The heartbeat API (`GET https://uptime.betterstack.com/api/v2/heartbeats`) exposes `attributes.status ∈ {paused,pending,up,down}` + `created_at`/`updated_at` — **there is NO `last_event_at`/ping-timestamp field** (Kieran verified against 3 Better Stack docs). | Verify via the **`status` transition**: a never-pinged heartbeat is `pending`/`down`; a successful redeploy ping flips it to `up`. Poll `.data[] \| select(.attributes.name=="soleur-registry-disk-prd") \| .attributes.status=="up"`. Drop `last_event_at`/`APPLY_START` epoch-compare entirely (unimplementable). |

**Premise Validation note.** Cited precedents (#6122/ADR-096 registry, #6178/#6197/ADR-100 inngest) are verified live on this branch (files, resources, the parity test, the `inngest_host_replace` job all exist). The incident is the driver; no cited *blocker* issue is already-resolved. The stale sub-premises (allow-list-oversight; 3-target mirror; `last_event_at`) are corrected above.

## User-Brand Impact

**If this lands broken, the user experiences:** a registry `-replace` that either fails to boot the new host or (worst case) destroys `hcloud_volume.registry` — the OCI store — breaking cold-boot image pulls. Mitigated: zot is **dark-launch-gated with an atomic GHCR fallback** (ADR-096), so running web hosts keep serving and deploys fall back to GHCR; the blast radius is the deploy pipeline, not user-facing serving. A broken FIX B leaves ops@ off the alert path (status quo).

**If this leaks, the user's data is exposed via:** N/A — this touches infra CI, a Terraform-generated host, and an operator-email recipient. No customer PII, schema, auth, or API surface. `ops@jikigai.com` is the operator's own contact address.

**Brand-survival threshold:** aggregate pattern. A registry disk-full degrades the **deploy pipeline** (aggregate reliability), not a single-user data incident; the GHCR dark-launch fallback further bounds it. No CPO sign-off required. This diff touches no preflight Check-6 sensitive-path surface, so no `threshold: none` scope-out bullet is needed.

## Hypotheses (redeploy correctness)

- **H1 — the redeploy activates all three mitigations in one apply, and the disk heartbeat goes `up`.** The new cloud-init grows the fs (`cloud-init-registry.yml:146`), starts zot with the new `storage.retention` config (`:208`), and emits an immediate first `zot-disk-heartbeat.sh` ping on boot (`:225-226`). Causal chain: 30 GB resize + retention pruning bring `/var/lib/zot` usage well under the 85 % ping gate → the boot ping fires → heartbeat `status` flips `pending/down → up` → the incident auto-resolves. Heartbeat `period=900s / grace=600s` gives a ~25-min tolerance window.
- **H2 — the disk heartbeat is a disk-gated signal (arch-strategist MEDIUM).** `zot-disk-heartbeat.sh` pings ONLY when `/var/lib/zot < 85 %` — including the boot ping. A non-fire therefore does NOT distinguish "redeploy failed" from "disk still ≥85 %." Mitigation: the **authoritative** redeploy-success signal is the deterministic `terraform apply` (host replaced, volume 30 GB in state — verifiable from the applied plan); the heartbeat `status==up` is the observability confirmation and, post-resize+prune, is expected to fire. A non-fire after a successful apply is itself diagnostic (genuine disk-full), not a false negative.
- **H3 — private NIC may be down after `-replace` (learning `knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md`).** The disk heartbeat pings over the PUBLIC egress interface, so it proves boot+egress, not the private NIC (`10.0.1.30:5000`) for web-host pulls. The gate positively asserts the NIC is re-attached; private-net `/v2/` reachability is covered by the separate paused liveness heartbeat (Phase-3, out of scope) + GHCR fallback.
- **H4 — no SSH provisioner in scope.** zot-registry.tf is cloud-init-only (`:19`); network.tf's server_network has no provisioner. The replace scope contains no `remote-exec`/`file`/`connection` block → the network-outage checklist's provisioner trigger does not fire; verification stays heartbeat-visible per `hr-no-ssh-fallback-in-runbooks`.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)

0.1. **`betteruptime_team_member` schema + args, against the pinned provider.** In `apps/web-platform/infra`, `terraform init -lockfile=readonly` then `terraform providers schema -json | jq '.provider_schemas | to_entries[] | select(.key|test("better-uptime")) | .value.resource_schemas.betteruptime_team_member.block.attributes | keys'`. Confirm `email`, `role`, and whether `team_name` is REQUIRED when the provider uses a **global** token (`main.tf:66` `api_token = var.betterstack_api_token`; the tf comment calls it "global Read & write"). If existing team-scoped `betteruptime_*` resources omit `team_name` and apply cleanly, the token is effectively team-scoped and `team_name` may be omittable — verify, don't assume. Confirm a free-tier-valid `role` (`responder` is the provider default) and the **free-tier team-seat limit** (does adding a member fail or need a paid seat?).
0.2. Confirm the Doppler `soleur/prd_terraform` key `BETTERSTACK_API_TOKEN` maps (via `--name-transformer tf-var`) to `var.betterstack_api_token`, the **Uptime** API bearer (distinct from `scripts/betterstack-query.sh`'s `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` Telemetry/ClickHouse creds). Kieran verified the wiring; re-confirm at build time.
0.3. Read `tests/scripts/lib/inngest-host-replace-gate.sh` + `tests/scripts/test-inngest-host-replace-gate.sh` in full — the byte-precise template. **Copy its positive-action `out_of_scope` filter verbatim** (`select(.change.actions? | any(.=="create" or .=="update" or .=="delete" or .=="forget"))`), which excludes `no-op` AND `read` (a "≠ no-op" filter would false-abort on `data.*` reads — Kieran P1).
0.4. Confirm the pending volume delta: read state / `terraform plan -target=hcloud_volume.registry` → establish `hcloud_volume.registry.size` is live-10 / desired-30 (pending `["update"]`). This is the resize that must ride in the scoped plan.
0.5. **Dry-run the scoped plan** (`terraform plan` with the 5 `-target`s + ephemeral ssh key) to (a) capture the EXACT `resource_changes` shape the gate will see (which addresses/actions actually appear — incl. any `read` or benign dependency drift), and (b) confirm no *other* plan-time evaluation in the root (`file()`, `data`, `templatefile()`) errors under this `-target` set. Seed the gate fixtures from this real plan JSON.
0.6. Determine whether `terraform-target-parity.test.ts` enumerates the resource universe from `.tf` (auto-balances FIX B) or a hardcoded list (needs an explicit `betteruptime_team_member.ops` edit). `git grep -ln 'registry\|dispatch\|-target=\|parity' -- tests/ apps/web-platform/infra/*.test.sh plugins/soleur/test/` to inventory EVERY guard/parity suite (`web-hosts-fanout-parity.test.sh`, `ci-deploy-wrapper.test.sh`, `destroy-guard-filter-web-platform.jq`, `terraform-target-parity.test.ts`).

### Phase 1 — FIX A: `registry-host-replace` dispatch path

1.1. **`.github/workflows/apply-web-platform-infra.yml` — dispatch input.** Add `registry-host-replace` to the `apply_target` `choice` `options:` (after `inngest-host-replace`) and extend the input `description:` (mirror the per-option phrasing: "scoped `-replace` of the registry host to re-run cloud-init + activate the 30 GB volume resize; preserves the zot storage volume").
1.2. **New job `registry_host_replace`**, `if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'registry-host-replace'`, `timeout-minutes: 20`, in the SAME workflow (so it shares `concurrency.group: terraform-apply-web-platform-host`, `cancel-in-progress: false` — the sole R2-state serializer, since `main.tf:19` `use_lockfile = false`). Mirror `inngest_host_replace` (`:1485-1616`): checkout (pinned SHA) → setup-terraform (pinned) → Install Doppler CLI → generate ephemeral SSH pubkey for `var.ssh_key_path` (HCL evaluates `file()` at plan time; throwaway key, never consumed) → verify `DOPPLER_TOKEN` present → extract R2 creds (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` raw via `doppler secrets get --plain`, masked) → `terraform init -input=false -lockfile=readonly`.
1.3. **Plan + destroy-guard step.** `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -no-color -input=false -out=tfplan` with:
   ```
   -replace='hcloud_server.registry'
   -target='hcloud_server.registry'
   -target='hcloud_server_network.registry'      # network.tf:57 — server_id ForceNew; else new host has no private NIC
   -target='hcloud_volume_attachment.registry'    # zot-registry.tf:251 — server_id ForceNew
   -target='hcloud_firewall_attachment.registry'  # :270 server_ids update-in-place; INTENTIONAL deviation from inngest — else new host loses deny-all firewall
   -target='hcloud_volume.registry'               # :240 — activates the pending 10→30 GB resize (rides in as a dependency); gate permits size-update only
   -var="ssh_key_path=${CI_SSH_PUB}"
   ```
   Then `terraform show -json tfplan > tfplan.json`, `source tests/scripts/lib/registry-host-replace-gate.sh`, abort (`::error::` naming the store + NIC + firewall + volume specifically, plus `grep -E 'will be destroyed|must be replaced|Plan:'`) unless the gate passes. **No `[ack-destroy]` bypass** (`hr-menu-option-ack-not-prod-write-auth`).
1.4. **Apply + preservation asserts.** `terraform apply -no-color -input=false tfplan`; then jq backstops from the saved `tfplan.json`: `hcloud_volume.registry` shows **0** delete/forget actions (store preserved; a size `["update"]` is allowed), and `hcloud_server_network.registry` shows a `create` (NIC re-attached).
1.5. **Best-effort heartbeat status line in the summary (non-gating).** After apply, `doppler secrets get BETTERSTACK_API_TOKEN --plain` (guard non-empty) and a single `curl -fsS --max-time 10` of the Uptime heartbeats endpoint → emit the `soleur-registry-disk-prd` `status` into `$GITHUB_STEP_SUMMARY`. **Informational, not a job gate** — Better-Stack ingestion latency must not fail a prod apply; the deterministic gates (1.3/1.4) gate the job, and Phase 5.3 is the authoritative heartbeat assert. (Reconciles the ARGUMENTS' "post-apply assert" with the reviewers' flakiness concern by relocating the authoritative assert to the pipeline layer where retries are natural.)
1.6. **Dispatch summary** step (`if: always()`) — reason, status, run URL, the best-effort heartbeat line.

### Phase 2 — FIX B: Better Stack `betteruptime_team_member.ops`

2.1. **In `apps/web-platform/infra/uptime-alerts.tf`** (the account-level alerting file — holds the apex/app monitors + the uptime escalation policy; cohesive home, no new file) add:
   ```hcl
   # ops@jikigai.com as a managed Better Stack team member so free-tier heartbeat/monitor email
   # alerts reach ops@ (not just the account owner). No new no-default var — the betteruptime
   # provider authenticates via the existing var.betterstack_api_token. ops@ is the operator's own
   # address, not a secret. INERT until ops@ accepts the one-time invite (its own inbox).
   resource "betteruptime_team_member" "ops" {
     email = "ops@jikigai.com"
     role  = "responder"          # confirm free-tier-valid role in Phase 0.1
     # team_name = "Your team"     # ADD ONLY IF Phase 0.1 shows a global token requires it
   }
   ```
2.2. **`.github/workflows/apply-web-platform-infra.yml` — per-merge `-target` list.** Append `-target=betteruptime_team_member.ops` to the `manual-rerun` (per-merge) apply target list (alongside the other `betteruptime_*` targets ~`:294-297`) so the resource **auto-applies on merge** (additive/safe).
2.3. **Parity edit for FIX B** — per Phase 0.6: if the parity test uses a hardcoded universe, add `betteruptime_team_member.ops` to the covered set; if it parses `.tf`, the resource + its `-target` self-balance (verify green). Do NOT add it to `OPERATOR_APPLIED_EXCLUSIONS` (it is auto-appliable).

### Phase 3 — Destroy-guard gate file + tests + guard-suite sweep

3.1. **Create `tests/scripts/lib/registry-host-replace-gate.sh`** — `registry_host_replace_gate <tfplan.json>` mirroring `inngest_host_replace_gate`, using the **positive-action** filter (Phase 0.3). 5-member allow-set: `hcloud_server.registry`, `hcloud_server_network.registry`, `hcloud_volume_attachment.registry`, `hcloud_firewall_attachment.registry`, `hcloud_volume.registry`. Counters (jq, `IN(.address; allow[])` exact-equality):
   - `out_of_scope` = positive-action changes whose address ∉ allow-set → **0**.
   - `store_destroyed` = `hcloud_volume.registry` with `delete`, `forget`, OR a replace (`index("delete") and index("create")`) → **0** (named backstop: "zot store would be destroyed/recreated").
   - `volume_bad_update` = `hcloud_volume.registry` whose actions ⊄ `{["update"],["no-op"]}` → **0** (only an in-place size update is allowed).
   - `server_replaced` = `hcloud_server.registry` with `delete` AND `create` → **1** (a true replace).
   - `nic_recreated` = `hcloud_server_network.registry` with `create` → **1** (positive NIC-attached assertion — spec-flow 1b; else a "server replaced but NIC stripped" plan would PASS and boot a private-NIC-less host invisible to the egress heartbeat).
   - `firewall_ok` = `hcloud_firewall_attachment.registry` actions ∈ `{["update"],["create"]}`, NOT a bare `["delete"]`.
   - **PASS iff** `out_of_scope==0 && store_destroyed==0 && volume_bad_update==0 && server_replaced==1 && nic_recreated==1 && firewall_ok`.
3.2. **Create `tests/scripts/test-registry-host-replace-gate.sh`** — synthesized `tfplan.json` fixtures (`cq-test-fixtures-synthesized-only`), seeded from the Phase 0.5 real plan: (a) exact scoped replace WITH the volume size `["update"]` → **PASS**; (b) `delete` on `hcloud_volume.registry` → ABORT (store_destroyed); (c) *replace* of the volume (delete+create) → ABORT; (d) out-of-scope address (`hcloud_server.web`) → ABORT; (e) no-op (`server_replaced==0`) → ABORT; (f) server replaced but `hcloud_server_network.registry` shows only `delete` (NIC stripped) → ABORT (nic_recreated). Register per the repo's shell-test-runner convention (match sibling `test-inngest-host-replace-gate.sh`; verify runner in Phase 0 — do NOT add a framework).
3.3. **Parity — empirical strip validation** (Kieran P1). Add `registry_host_replace` to the workflow, run the parity suite **without** stripping it; if RED, add `stripJob(..., "registry_host_replace")` to `stripDispatchJobs()` (`:412-420`) using the exact literal, re-run green; if GREEN, record the strip is belt-and-suspenders and add it anyway (harmless). Add a unit assertion that the registry job's `-target`s are absent from the stripped text, and confirm none of the 5 registry addresses appear in `MOVED_OPERATOR_CONSUMED`.
3.4. **Guard-suite sweep** (Phase 0.6 inventory) — run each affected suite locally and confirm green. Add any suite that mechanically fails to Files to Edit.

### Phase 4 — Docs / ADR / C4

4.1. **Amend `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`** — a short "Reprovisioning / apply-path" note: the registry host now has a sanctioned **dispatch-only** `registry-host-replace` path (mirroring ADR-100's `inngest-host-replace`) to re-run cloud-init + apply the volume resize without SSH; the per-PR exclusion is unchanged. Record the FIX B recipient decision (`betteruptime_team_member.ops`, free-tier).
4.2. **Update `apps/web-platform/infra/zot-registry.tf` header** (`:15-21`) — one line noting the dispatch-replace path exists, without contradicting the "NONE in the per-PR `-target=` list" invariant.

### Phase 5 — After merge (do NOT stop at a merged PR)

5.1. **Sequencing.** The merge (touching `apps/web-platform/infra/**`) triggers the per-merge auto-apply, which now also creates `betteruptime_team_member.ops`. The Phase 5.1 dispatch shares the `terraform-apply-web-platform-host` concurrency group (`cancel-in-progress: false`) → it will **queue behind** the merge apply and start when that releases (not a hang). Wait for the merge apply to complete, then: `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=registry-host-replace -f reason="reprovision registry: install disk-heartbeat cron + activate storage.retention + 30GB volume resize (incident soleur-registry-disk-prd)"` — **must run against `main`** (learning `knowledge-base/project/learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`: `gh workflow run` finds the workflow only on the default branch; the `reason` input is declared at `.github/workflows/apply-web-platform-infra.yml:78`).
5.2. `gh run watch`; confirm the destroy-guard passed, apply succeeded, volume preserved (0 delete/forget) AND resized to 30 GB in the applied plan, NIC re-attached.
5.3. **Authoritative observability self-pull** (do NOT ask the operator): bounded poll (aligned to the ~25-min boot+cloud-init+grace window, e.g. up to ~20 min with `curl --max-time 10`, distinguishing non-2xx → fail-fast-with-status from status-not-yet-`up` → keep-polling) of the Uptime API with `BETTERSTACK_API_TOKEN` for `soleur-registry-disk-prd` until `attributes.status == "up"`. This confirms the redeploy ran the new cloud-init → retention + 30 GB volume live. Then bounded-poll `GET /api/v2/incidents` until the incident **auto-resolves** (resolution lags the first ping by up to one period — do not single-shot check).
5.4. **Failure branch.** If the guard passes but `terraform apply` fails mid-replace (old server destroyed, new create fails — quota/image/boot), the registry is DOWN but serving is covered by the GHCR dark-launch fallback; recovery = **re-dispatch** `registry-host-replace` (re-creates the host from the preserved volume) after fixing the cause. Do NOT auto-re-dispatch on a mere verification *lag* (a 5.3 timeout ≠ an apply failure; investigate first — a destructive re-replace is the wrong reflex).
5.5. `gh issue comment`/`close` the incident-tracking artifact only after 5.3 is green — use **`Ref`** (not `Closes`) in the PR body (`wg-use-closes-n-in-pr-body-not-title-to` — the fix executes post-merge).

## Files to Create

- `tests/scripts/lib/registry-host-replace-gate.sh` — sourced destroy-guard gate (positive-action filter, 5-member allow-set, positive NIC/firewall/volume-update assertions).
- `tests/scripts/test-registry-host-replace-gate.sh` — synthesized-fixture unit test (6 fixtures).

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — dispatch `choice` option + description; new `registry_host_replace` job (5 `-target`s); append `-target=betteruptime_team_member.ops` to the per-merge apply list.
- `apps/web-platform/infra/uptime-alerts.tf` — `betteruptime_team_member.ops`.
- `plugins/soleur/test/terraform-target-parity.test.ts` — (empirically) `registry_host_replace` in `stripDispatchJobs()` + unit assertion; (conditional) `betteruptime_team_member.ops` in the covered set per Phase 0.6.
- `apps/web-platform/infra/zot-registry.tf` — header note on the dispatch-replace path.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — reprovision + recipient amendment.
- (conditional, Phase 3.4) `web-hosts-fanout-parity.test.sh` / `ci-deploy-wrapper.test.sh` — only if the sweep shows a mechanical failure.

## Infrastructure (IaC)

### Terraform changes
- New resource `betteruptime_team_member.ops` in `apps/web-platform/infra/uptime-alerts.tf`. Provider `BetterStackHQ/better-uptime ~> 0.20` (already required, main.tf:41-44). **No new no-default variable** — auth is the existing `var.betterstack_api_token`; the ops email is a non-secret literal.
- No `.tf` change for FIX A (the workflow orchestrates a scoped `-replace` of existing resources).

### Apply path
- **FIX B:** path (a)/(b) — auto-applies per-merge via the workflow's `-target=betteruptime_team_member.ops` (safe additive create; sends an invite).
- **FIX A:** path (c) `-replace` — dispatch-only. Bounded downtime = one Hetzner host recreate (~2–5 min); the store volume is preserved + resized (guarded). Deploy-serving blast radius bounded by the ADR-096 GHCR dark-launch fallback.

### Distinctness / drift safeguards
- Registry resources stay `OPERATOR_APPLIED_EXCLUSION`s; the dispatch job is (empirically) stripped from the per-merge coverage anchor. `hcloud_volume.registry` preserved by `store_destroyed==0` + size-update-only. `betteruptime_heartbeat.*` keep `lifecycle.ignore_changes = [paused]`.
- **Cross-workflow drift race (latent, pre-existing):** `scheduled-terraform-drift.yml` uses a *different* concurrency group (`terraform-drift`), so a 12 h drift run can race any dispatch against unlocked R2 state (`use_lockfile=false`). Not worsened here (every dispatch job, incl. `inngest_host_replace`, shares this exposure) — documented, not fixed in this plan.

### Vendor-tier reality check
- Better Stack **free tier**: `betteruptime_policy` (escalation) stays paid-gated (`count = var.betterstack_paid_tier ? 1 : 0`, unchanged). `betteruptime_team_member` is not documented as paid-gated but the **seat limit + global-token `team_name` requirement + `role` validity are Phase-0 gates**. No recurring vendor expense (no tier upgrade); a Responder-tier upgrade (fallback) would trigger `wg-record-recurring-vendor-expense-before-ready` and is out of scope.

## Observability

```yaml
liveness_signal:
  what: "betteruptime_heartbeat.registry_disk_prd — self-ping from the registry host while /var/lib/zot < 85% used; verified via Better Stack status transition to up"
  cadence: "every 5 min (cron */5) + one immediate ping in cloud-init runcmd on boot; heartbeat period 900s / grace 600s (~25-min window)"
  alert_target: "Better Stack incident (email) → account owner + ops@ (FIX B, once invite accepted)"
  configured_in: "apps/web-platform/infra/zot-registry.tf:324 + cloud-init-registry.yml:116-131,146,223-226"
error_reporting:
  destination: "Better Stack missed-heartbeat incident (email). CI dispatch-job failures → GitHub Actions ::error:: + run summary."
  fail_loud: "yes — the dispatch job aborts hard on destroy-guard failure, volume delete/replace, or NIC-stripped plan. Heartbeat status is best-effort in the summary (non-gating); Phase 5.3 is the authoritative bounded-poll assert."
failure_modes:
  - mode: "registry host down / never booted after -replace"
    detection: "disk heartbeat stops pinging (in-surface probe emitted FROM the host) → Better Stack status down/pending → missed-heartbeat incident"
    alert_route: "Better Stack email → owner + ops@"
  - mode: "/var/lib/zot >= 85% (disk filling — the #6122 failure)"
    detection: "zot-disk-heartbeat.sh skips the ping when USE>=85 → same absence alert BEFORE the disk is full"
    alert_route: "Better Stack email → owner + ops@"
  - mode: "private NIC down after replace (host boots, egress works, private-net /v2/ dead)"
    detection: "NOT covered by the egress-based disk heartbeat; the gate positively asserts NIC re-attach at apply time; runtime private-net coverage = the separate paused liveness heartbeat (Phase-3) + GHCR pull fallback"
    alert_route: "deferred — documented limitation; GHCR fallback prevents deploy breakage"
logs:
  where: "GitHub Actions run logs (dispatch job); Better Stack incident timeline. Registry host journald ships nowhere yet (Phase-3 Vector wiring, out of scope)."
  retention: "GitHub Actions default; Better Stack incident history."
discoverability_test:
  command: "TOKEN=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain); curl -fsS --max-time 10 -H \"Authorization: Bearer $TOKEN\" https://uptime.betterstack.com/api/v2/heartbeats | jq -r '.data[] | select(.attributes.name==\"soleur-registry-disk-prd\") | .attributes.status'"
  expected_output: "up  (a never-pinged heartbeat reads pending/down; only up proves the redeploy's first ping arrived — paused/pending/down must NOT pass the redeploy gate)"
```

**Affected-surface note (Phase 2.9.2).** The registry host is a blind surface (deny-all-public, no SSH). The disk heartbeat is an **in-surface** probe (emitted from the host). Discrimination limit (H2): a single presence/absence signal does not, alone, separate host-down vs cron-broken vs disk->=85%; the deterministic terraform apply is the authoritative redeploy-success signal, and the paused liveness heartbeat adds host-reachability discrimination. Acceptable for this plan's scope; noted, not silently accepted.

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-096** (not a new ADR — extends an accepted pattern; parity with how `inngest-host-replace` folds into ADR-100): record the sanctioned dispatch-only `registry-host-replace` reprovision path and the `betteruptime_team_member.ops` recipient decision. In-scope task (Phase 4.1), not a deferred follow-up.

### C4 views
- **No C4 impact.** Verified against all three model files: `model.c4:258` (`zotRegistry`), `model.c4:262` (`betterstack`), `model.c4:8` (`Founder / Operator` actor), `model.c4:371` (`hetzner -> zotRegistry` pull edge) are all already modeled. This adds (a) a CI *apply path* for an existing host and (b) a *notification recipient* on the existing Better Stack system — no new external actor, external system, container/data-store, or actor↔surface access relationship at C4 Container granularity. Enumeration checked: external human actors (operator/ops → `Founder / Operator`), external systems (Better Stack, Hetzner — modeled), data stores (zot volume — host-internal, below granularity), access relationships (unchanged). No `.c4` edit; `c4-code-syntax.test.ts` / `c4-render.test.ts` unaffected.

### Sequencing
- The ADR amendment describes the target state and ships in this PR. FIX A's dispatch path is live at merge; FIX B auto-applies at merge; the redeploy (Phase 5) executes post-merge against `main`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `.github/workflows/apply-web-platform-infra.yml` `apply_target` `choice` `options:` contains `registry-host-replace`; the input `description:` documents it. (`grep -c "registry-host-replace" <file>` ≥ 2.)
- [ ] A `registry_host_replace` job exists, guarded on `inputs.apply_target == 'registry-host-replace'`, with plan+guard, apply+preservation-assert, and a non-gating heartbeat-status summary line. Its plan step contains `-replace='hcloud_server.registry'` and exactly the **5** `-target=` addresses (server + server_network + volume_attachment + firewall_attachment + volume). Verify by extracting the job block with a **header-skipping** awk (`awk '/^  registry_host_replace:/{f=1;next} f&&/^ {2}[A-Za-z0-9_-]+:/{exit} f'`, NOT a `/start/,/next-header/` range that self-matches the header) and asserting each `-target` line present.
- [ ] `tests/scripts/lib/registry-host-replace-gate.sh` exists; `tests/scripts/test-registry-host-replace-gate.sh` passes all 6 fixtures (PASS-with-volume-update / volume-delete-ABORT / volume-replace-ABORT / out-of-scope-ABORT / no-op-ABORT / NIC-stripped-ABORT). The gate's `out_of_scope` uses the positive-action filter (grep the gate for `any(.=="create"`), NOT "≠ no-op".
- [ ] `plugins/soleur/test/terraform-target-parity.test.ts` parity suite is green with `registry_host_replace` present; if the empirical check (Phase 3.3) showed RED, `stripDispatchJobs()` strips `registry_host_replace` (`grep -c 'registry_host_replace' <test>` ≥ 1). No registry address in `MOVED_OPERATOR_CONSUMED`.
- [ ] `apps/web-platform/infra/uptime-alerts.tf` defines `betteruptime_team_member.ops` with `email = "ops@jikigai.com"` (and `team_name` iff Phase 0.1 required it); `-target=betteruptime_team_member.ops` is in the per-merge apply list; `terraform validate` succeeds with the pinned provider.
- [ ] All guard suites in the Phase 0.6 inventory are green.
- [ ] ADR-096 amended; `zot-registry.tf` header updated. Every `knowledge-base/` citation resolves (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} test -f {}`).
- [ ] PR body uses **`Ref`** (not `Closes`) for the incident artifact and corrects the framing (deploy-sequencing false positive; the same gap left disk mitigations un-live).

### Post-merge (operator/agent — automated, not deferred to a human)
- [ ] Phase 5.1 `gh workflow run … -f apply_target=registry-host-replace` dispatched against `main` (after the merge apply drains the concurrency group); run succeeds; destroy-guard passed; `hcloud_volume.registry` preserved (0 delete/forget) AND resized to 30 GB in the applied plan; NIC re-attached.
- [ ] Uptime API self-pull (Phase 5.3): `soleur-registry-disk-prd` `attributes.status == "up"` (bounded poll) → confirms retention + 30 GB volume live.
- [ ] Better Stack incident `soleur-registry-disk-prd | Missed heartbeat` auto-resolved (bounded-poll `/api/v2/incidents`).
- [ ] FIX B: `betteruptime_team_member.ops` created + invite **sent** (API-verifiable: `terraform state show` / Uptime team list shows the pending member). NOTE: **inert until ops@ accepts the invite** — end-to-end "ops@ receives an alert" is a best-effort soft check (needs a triggered incident + inbox access); if free-tier routing proves owner-only, escalate to the documented fallback rather than silently closing.
- [ ] `Automation: not feasible because <X>` — the single genuinely-human step is ops@ **accepting the Better Stack invite** (a click in ops@'s own inbox; analogous to OAuth consent). `automation-status: UNVERIFIED — /work MUST attempt a Playwright/inbox path before operator handoff`; all other steps agent-automated.

## Test Scenarios
- **Gate unit test** (`test-registry-host-replace-gate.sh`): 6 synthesized `tfplan.json` fixtures (Phase 3.2), seeded from the Phase 0.5 real plan.
- **Parity regression**: `terraform-target-parity.test.ts` green with the new dispatch job (stripped iff empirically required) and the new team_member covered.
- **Dispatch dry validation**: `actionlint` on the workflow YAML + `bash -c` on the extracted `run:` snippets of the new job (NOT `bash -n` the YAML).
- **Live redeploy** (post-merge): Phase 5 dispatch is the end-to-end test — `status→up` + incident auto-resolve is the pass signal.

## Domain Review

**Domains relevant:** Operations (observability / alerting / recipient routing), Engineering (CI, IaC, destroy-guard). Product: NONE (no UI-surface file — mechanical override does not fire). Legal/Finance/Sales/Marketing/Support: NONE.

### Operations
**Status:** assessed inline (headless infra-remediation; the on-call/recipient decision is fully researched — `betteruptime_team_member` is the free-tier IaC path, escalation policies paid-only, residual free-tier-routing + invite-acceptance uncertainties carried as Risks with verification gates).
**Assessment:** The alerting gap (recipients not in IaC; only owner emailed) is the operational root cause of the unacknowledged incident. FIX B addresses it within IaC on the free tier; fallback (webhook forward / Responder-tier) documented, not shipped. No SSH/manual runbook step.

### Engineering
**Status:** assessed inline; CTO lens covered by the plan-review eng panel.
**Assessment:** FIX A mirrors an accepted, parity-accommodated pattern with a deliberate, justified firewall-target deviation; the load-bearing risks (volume-resize-in-scope, positive NIC/firewall assertions, positive-action filter, parity strip, status-not-timestamp verify) are enumerated with guard coverage — all surfaced by the 5-agent plan review and folded in.

### Product/UX Gate
Not applicable — Product not relevant; no UI-surface file. Skipped.

## Open Code-Review Overlap
None — no open `code-review`-labeled issue touches `.github/workflows/apply-web-platform-infra.yml`, `apps/web-platform/infra/`, `tests/scripts/`, or `plugins/soleur/test/terraform-target-parity.test.ts` for this scope. (Confirm with the two-stage `gh issue list --label code-review --json` + standalone `jq --arg` sweep at /work time.)

## Risks & Mitigations
- **Pending volume resize aborts the guard (CRITICAL — caught by 3 reviewers):** `hcloud_volume.registry` rides into the scoped plan as a `["update"]` (10→30 GB). Mitigation: it is the 5th `-target` and an allow-set member permitting size-update-only; `store_destroyed`/`volume_bad_update` forbid delete/forget/replace. This IS the mechanism that makes the 30 GB grow live.
- **Heartbeat verify via a nonexistent field (P0):** the API has no `last_event_at`. Mitigation: verify via `status == "up"`; drop epoch-compare.
- **Disk-gated verification deadlock (H2):** a non-ping conflates redeploy-failure with disk->=85%. Mitigation: the deterministic apply is authoritative; post-resize+prune usage is <85% so the ping fires; a non-fire is diagnostic.
- **NIC/firewall stripped but guard passes (spec-flow 1b):** positive `nic_recreated==1` + `firewall_ok` assertions in the predicate.
- **`out_of_scope` false-abort on data-source reads (Kieran P1):** positive-action filter (excludes `read`).
- **FIX B inert until invite acceptance + free-tier routing unverified:** ship the IaC recipient; ACs assert API-verifiable state; "ops@ actually alerted" is best-effort; documented fallback = `betteruptime_outgoing_webhook`→forward or Responder-tier (expense-gated).
- **`team_name` required for a global token:** Phase 0.1 gate before writing the `.tf`.
- **Mid-apply failure leaves registry DOWN:** GHCR fallback covers serving; recovery = re-dispatch (re-creates from preserved volume); never auto-re-replace on a verification lag.
- **Cross-workflow drift race (pre-existing):** documented; not worsened.
- **Drift on a targeted dependency aborts a safe replace (fail-loud):** runbook says reconcile drift, do NOT widen the guard.

## Sharp Edges
- `## User-Brand Impact` filled (threshold: aggregate pattern) — passes deepen-plan Phase 4.6.
- `gh workflow run` for the new dispatch path works ONLY after the file is on `main` (post-merge) — Phase 5.1 is explicitly post-merge.
- Extending the per-merge `-target=` list (FIX B) and adding a dispatch job (FIX A) each touch a hand-maintained allow-list + its parity guard — Phase 0.6 + 3.3/3.4 sweep every guard suite.
- The gate is copied from inngest but has a LARGER allow-set (5 vs 3) and MORE positive assertions — do not "simplify" it back to the inngest shape; the volume + firewall + NIC assertions are load-bearing.

## Alternative Approaches Considered
| Approach | Rejected because |
|---|---|
| Add registry to the per-PR `-target=` allow-list | Violates the CTO ruling (`OPERATOR_APPLIED_EXCLUSION`); the per-PR path SSH-bridges to the existing web host and cannot provision a fresh host. |
| Mirror inngest exactly (3 targets, no firewall/volume) | Would leave the new host without its deny-all firewall AND never apply the 30 GB resize — the two things the fix needs. |
| Operator applies the change out-of-band by hand | Violates `hr-no-ssh-fallback-in-runbooks`, `hr-all-infrastructure-provisioning-servers`, non-technical-operator principle. |
| In-CI heartbeat poll as a hard job gate | Couples a prod apply to Better Stack ingestion latency (flaky); the inngest precedent omits it. Relocated: deterministic gates in-CI, best-effort status line in the summary, authoritative bounded-poll in Phase 5.3. |
| Verify `last_event_at ≥ APPLY_START` | The heartbeat API has no ping-timestamp field; unimplementable. `status==up` is the correct proof from a never-pinged start. |
| Upgrade to Responder tier now for an escalation policy to ops@ | Out of scope (free-tier requested; recurring expense gate). Documented fallback if free-tier team-member routing proves insufficient. |
