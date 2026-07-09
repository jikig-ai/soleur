---
title: "fix(infra): zot registry disk full — grow volume 30→60 GB + tighten retention keep-set (capacity-vs-retention)"
date: 2026-07-09
type: ops-remediation
classification: ops-only-prod-write
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
ref_issue: 6247
incident: "zot registry /var/lib/zot ext4 volume 100% full, zot crash-looping on ENOSPC (recurrence of 2026-07-08 #6240/#6246)"
apply_path: "registry-host-replace workflow_dispatch (dispatch-only, OPERATOR_APPLIED_EXCLUSION — NOT per-PR CI -target)"
---

# fix(infra): zot registry disk full — capacity-vs-retention resolution

🐛 **LIVE INCIDENT.** The self-hosted zot OCI registry host (Hetzner, deny-all ingress, no SSH)
has its 30 GB ext4 volume at `/var/lib/zot` **100% full** and zot is **crash-looping on ENOSPC**.

Live telemetry (`SOLEUR_ZOT_DISK`, Better Stack Logs, pulled 2026-07-09 ~15:35 UTC):
`pcent=100 fs_size_gb=30 block_size_gb=30 resize_ok=true zot_restarts=908 ping_rc=0
host=soleur-registry`, `zot_restarts` climbing ~20 per 5 min; the `soleur-registry-disk-prd`
heartbeat is down.

## Overview

This is a **recurrence** of the disk-full incident whose primary remediation merged 2026-07-08
(#6246: fail-loud `resize2fs` + `SOLEUR_ZOT_DISK` telemetry + gc 24h→1h / retention 24h→2h).
**That fix HELD.** `resize_ok=true` and `fs_size_gb=30=block_size_gb` prove the ext4 filesystem
is fully grown to the block device — this is **NOT** a resize regression. The 30 GB is genuinely
full of retention-KEEP blobs. This is exactly the telemetry-gated **grow-the-volume contingency**
the 2026-07-08 postmortem pre-registered as issue #6247; its trigger condition
(`resize_ok=true` AND fs≈full AND `pcent≥85` after the tightened gc has already run) is now met.

**Root cause of the refill.** The zot `storage.retention` keep-set in
`apps/web-platform/infra/cloud-init-registry.yml` keeps, **per repo across 2 platform-image repos**
(`soleur-web-platform` + `soleur-inngest-bootstrap`): `latest` + **unbounded** `sha256-.*` cosign
sig referrers + the **10** most-recently-pushed `v*` tags + the **10** most-recent commit-sha tags.
Each platform image is ~1.5–2 GB and dedupe shares little across versions. Up to ~20 multi-GB image
manifests per repo × 2 repos legitimately exceeds 30 GB, so gc/retention (working correctly) still
keep more than the volume holds. gc cannot reclaim a blob the retention policy says to KEEP.

**Durable fix — both levers, one PR, one dispatch:**

1. **Stop the bleed (headroom now).** Grow `var.registry_volume_size` 30 → **60 GB** in
   `apps/web-platform/infra/variables.tf`. The Hetzner volume resizes the block device **in place**
   (data survives) and the existing fail-loud `resize2fs` on the next boot grows the ext4 to fill
   it, dropping `pcent` well below 85 and ending the crash-loop.
2. **Stop the refill (bound growth).** Tighten the keep-set in `cloud-init-registry.yml` so gc
   reclaims below capacity: lower `mostRecentlyPushedCount` **10 → 5** (rollback-sufficient) for
   both the `v*` and commit-sha patterns, and **bound the currently-unbounded `sha256-.*`**
   sig-referrer pattern with a conservative `mostRecentlyPushedCount` so signatures are dropped
   roughly alongside their subject image rather than kept forever.

**Apply path (load-bearing).** This host is an `OPERATOR_APPLIED_EXCLUSION` / dispatch-only surface.
Apply via the sanctioned **`registry-host-replace` `workflow_dispatch`** (scoped, destroy-guarded
`terraform apply -replace='hcloud_server.registry'` that PRESERVES `hcloud_volume.registry` and
applies the pending volume resize), **NOT** the per-PR CI `-target` path. The dispatch already
`-target`s `hcloud_volume.registry`, and its destroy-guard (`registry-host-replace-gate.sh`) already
PERMITS a size `["update"]` on the volume — so **no workflow or gate change is required** (verified:
`registry_host_replace_gate` counts any volume action that is not `["update"]`/`["no-op"]` as
`volume_bad_update`, and a size grow is an `["update"]`; the gate's own Test 1 exercises the
volume-size-update PASS path). Re-derive the live volume size via a scoped `terraform plan` at
implementation time (do not quote it from a stale plan).

## Premise Validation (Phase 0.6)

| Cited premise | Check | Result |
|---|---|---|
| `SOLEUR_ZOT_DISK` telemetry fields exist and mean what the incident says | Read `cloud-init-registry.yml:137-173` | HOLDS — the reporter emits `pcent/fs_size_gb/block_size_gb/resize_ok/zot_restarts/ping_rc`; the incident reading is consistent with a genuinely-full, grown fs. |
| The 2026-07-08 fix is the fail-loud resize + gc/retention tighten | Read postmortem + ADR-096 amendment (#6240/#6244) | HOLDS — keep-set was explicitly left UNCHANGED by #6246; this PR is the follow-on capacity+keep-set change. |
| `registry-host-replace` dispatch preserves the volume and permits a size update | Read `apply-web-platform-infra.yml:1649-1770` + `tests/scripts/lib/registry-host-replace-gate.sh` + `test-registry-host-replace-gate.sh` Test 1 | HOLDS — volume is `-target`ed and in the allow-set; gate permits `["update"]`. No gate/workflow change needed. |
| Issue #6247 tracks this contingency and is OPEN (per postmortem line 265) | `gh issue view 6247` | **STALE** — #6247 is **CLOSED (COMPLETED, 2026-07-08 21:52 UTC)**, closed prematurely as "not-yet-needed". Its trigger is now met. Plan response: **reopen #6247** as the tracking issue and reference it `Ref #6247` in the PR body (ops-remediation: NOT `Closes` — closure follows the post-dispatch verification, per the ops-remediation `Closes`-vs-`Ref` sharp edge). |
| The `sha256-.*` keep-set is intended to be kept forever (ADR-087) | Read ADR-087 + `cloud-init-registry.yml:52-55` | HOLDS but is exactly what this PR revises — see Sharp Edge #1. Bounding it is a deliberate contract change (ADR-096 amendment), sized to never prune a *kept* image's sig. |

No other external premises to validate.

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Codebase reality | Plan response |
|---|---|---|
| "grow `var.registry_volume_size` beyond 30 GB (e.g. 60 GB)" | `variables.tf:126-130` default `= 30`; description hard-codes "30 GB holds the storage.retention keep-set (10 v* + 10 sha + latest + sigs) with headroom" — this description is now falsified. | Set default `= 60`; rewrite the description (drop the falsified "with headroom" and "10 v* + 10 sha" phrasing; state the keep-set is now 5+5 and the recurrence drove the grow). |
| "bound the unbounded `sha256-.*` sig-referrer retention" | `cloud-init-registry.yml:92` `{ "patterns": ["sha256-.*"] }` — no `mostRecentlyPushedCount` (kept forever); comment at `:52-55` says "ALWAYS keep every `sha256-*` tag". | Add a conservative `mostRecentlyPushedCount`; rewrite the `:52-65` comment block to explain the bound + the cosign-verify coupling risk (Sharp Edge #1). |
| "lower `mostRecentlyPushedCount` from 10 to a smaller count" | `cloud-init-registry.yml:93-94` both `v.*` and `[0-9a-f]{7,64}` at `mostRecentlyPushedCount: 10`. | Lower both to 5. |
| (implicit) tests will still pass | `registry-boot-guard.test.sh:106` asserts `cosign referrer keep-set (sha256-.*) UNCHANGED` via `grep -qF 'sha256-.*'`. Adding a count to the SAME line keeps the literal present → the grep still passes, but the test's semantics ("UNCHANGED") become false. No test currently pins the value `10`, so lowering counts breaks no assertion. | Update this test: re-word the sha256-* assertion to assert the now-BOUNDED keep-set, and add positive assertions for the new v*/commit-sha/sha256 counts. |
| stale "30 GB" / "10 GB" references in comments | `cloud-init-registry.yml:21,48,62,189,192`; `zot-registry.tf:375`; `tests/scripts/lib/registry-host-replace-gate.sh:17` ("10->30 GB resize", now doubly stale — gate logic is size-agnostic so functionally inert). | Sweep and update the ones this change falsifies (the keep-set/size narrative + the gate `:17` comment); leave the historical `:189-192` root-cause comment intact (it describes the #6240 past, not the current size). |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly — the registry is an
internal deploy-pipeline / image-mirror surface. The concrete failure artifact is a **stuck deploy
pipeline** (zot-mirror step keeps 500-ing on ENOSPC) and a **persistently-open Better Stack disk
incident**. Image serving to running hosts is **GHCR-fallback-covered** (ADR-096 dark-launch
fallback), so no authenticated app user sees downtime.

**If this leaks, the user's data is exposed via:** N/A — the zot host holds only OCI image blobs
(no customer PII, no auth material, no schema). The one secret involved (`BETTERSTACK_LOGS_TOKEN`) is
a write-only logs-ingest token in an isolated Doppler config, untouched by this change.

**Brand-survival threshold:** `aggregate pattern` — availability degradation of the deploy/registry-
mirror layer (GHCR-fallback-covered), not a single named user. Matches the 2026-07-08 postmortem's
classification. No CPO sign-off required; `user-impact-reviewer` not required at review time.

*Sensitive-path note:* this diff touches `apps/web-platform/infra/*` but the threshold is not `none`,
so no `threshold: none` scope-out bullet is needed.

## Hypotheses (Network-outage gate — false-positive acknowledgment)

The Phase 1.4 gate matches on the `SSH` substring ("no SSH" in the incident description). **This is
not a connectivity incident.** The root cause is **ENOSPC** (disk full), positively confirmed by
in-surface telemetry (`resize_ok=true`, `fs_size_gb=30=block_size_gb`, `pcent=100`). This PR proposes
**no** sshd/fail2ban/firewall change; `hcloud_server.registry` has **no** `provisioner "remote-exec"`
/ `connection { type = ssh }` block (cloud-init-only), so the provisioner-SSH trigger does not fire.
The L3→L7 firewall-first diagnostic ordering is **N/A** here — there is no network hypothesis to rank.

## Downtime & Cutover

**Trigger:** infra reboot/replace class — the fix is applied via `-replace='hcloud_server.registry'`
(a `must be replaced` on a serving `hcloud_server`). Gate 4.55 fires.

**Offline-inducing operation + surface.** The `registry-host-replace` dispatch destroys and re-creates
the **singleton** registry host, taking zot (`10.0.1.30:5000`) unreachable for a fresh-boot window
(~minutes). The affected surface is the **zot pull/mirror path only**.

**Zero-downtime path evaluation (defaulted to the least-downtime sanctioned mechanism):**

- **The zot store volume is PRESERVED** across the `-replace` (destroy-guard `store_destroyed==0`,
  `volume_bad_update==0`) — no data cutover, no rebuild. This is the expand-in-place path for the
  data (size `["update"]`, not a replace).
- **Serving is GHCR-fallback-covered.** Per ADR-096 dark-launch (`model.c4:377` `hetzner -> ghcr`
  atomic fallback), a running host that cannot reach zot pulls the SAME `@sha256` digest from GHCR.
  So authenticated app users see **no serving interruption** during the boot window — only the
  zot-mirror *push* step is briefly unavailable, and it is already failing (ENOSPC) pre-fix.
- **Full blue-green (a second parallel registry host) is rejected as over-engineering** for a
  singleton mirror surface that is GHCR-fallback-covered: it would double the host cost and add a
  store-sync problem for a ~minutes boot gap that causes no user-facing outage. The
  `registry-host-replace` dispatch IS the sanctioned least-downtime path (a naive full
  `terraform apply` would be strictly worse — it is why the scoped dispatch exists).

**Residual downtime:** the ~minutes fresh-boot window on the push/mirror path, **bounded** by the
dispatch (not an open-ended apply) and **justified** by (a) GHCR fallback covering serving and (b)
the store volume persisting. Brand-survival threshold is `aggregate pattern` (not `single-user
incident`), and no named user is served off zot today — so residual bounded downtime on the mirror
path is acceptable. Authorization is the `workflow_dispatch` menu-ack (`hr-menu-option-ack-not-prod-write-auth`);
no additional maintenance-window sign-off required. Post-dispatch, verify NIC reachability from a
peer web host (learning `2026-07-07-immutable-redeploy.md`) before declaring recovery. **Per-stage
rollback:** if the `-replace` apply fails mid-flight the store volume is intact; re-dispatch
`registry-host-replace` recovers from the preserved volume (the workflow's own error path documents this).

## Network-Outage Deep-Dive (deepen-plan Phase 4.5 — false-positive)

The gate fires on the `SSH` substring ("no SSH" in the incident). **This is not a connectivity
incident and no firewall/DNS/TLS/service-layer hypothesis applies.** L3 firewall allow-list: N/A —
no firewall rule changes; `hcloud_firewall.registry` stays deny-all-public (the destroy-guard asserts
it is re-attached, `firewall_ok>=1`). L3 DNS/routing: N/A — private-net `10.0.1.30`, unchanged. L7
TLS/proxy: N/A — plain-HTTP private net, unchanged. L7 application: the root cause is **ENOSPC**
(positively confirmed by `SOLEUR_ZOT_DISK`: `resize_ok=true`, `fs_size_gb=30=block_size_gb`,
`pcent=100`), not a reachability failure. `hcloud_server.registry` has **no** `provisioner
"remote-exec"` / `connection { type = ssh }` block (cloud-init-only), so the terraform-apply SSH
dependency does not exist. The only post-`-replace` reachability check is the private-NIC-up
verification (Research Insights → `2026-07-07-immutable-redeploy.md`), already in Phase 4 step 16.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/variables.tf` — `variable "registry_volume_size"` default `30 → 60`;
  rewrite the description. (No new variable; `hr-tf-variable-no-operator-mint-default` N/A — this is
  an existing no-secret sizing var with a default.)
- `apps/web-platform/infra/zot-registry.tf` — no resource-shape change; the `size =
  var.registry_volume_size` reference at `:296` picks up the new default. Update the stale `30 GB`
  comment at `:375`.
- `apps/web-platform/infra/cloud-init-registry.yml` — the `storage.retention.keepTags` policy
  (`:90-95`) + its explanatory comment block (`:48-65`, `:21`). This YAML is `base64gzip`-
  `templatefile`'d into Hetzner `user_data`; the change is a JSON-value edit inside the rendered
  `config.json`, well under the 32,768-byte `user_data` cap (verify byte-exact size at first plan).
- **No provider/version-pin change.** No new sensitive variable enters `terraform.tfstate`.

### Apply path

**(c) taint + `terraform apply -replace` — via the sanctioned `registry-host-replace`
`workflow_dispatch`** (NOT an operator SSH step, NOT the per-PR CI `-target` path). The dispatch does
a scoped `-replace='hcloud_server.registry'` that re-runs cloud-init (ships the new `config.json`
keep-set) and applies the pending `hcloud_volume.registry` **size update** (30→60 GB, data
preserved). Expected blast radius: a fresh registry-host boot (~minutes); image serving is GHCR-
fallback-covered during the gap. **No gate/workflow edit** — the existing 6-target scope + destroy-
guard already cover a volume size `["update"]`.

### Distinctness / drift safeguards

`dev != prd`: N/A (single prod registry host). `hcloud_volume.registry` is preserved by the destroy-
guard (`store_destroyed==0`, `volume_bad_update==0`). No `lifecycle.ignore_changes` change. The 12h
drift detector will show the `registry_volume_size` diff **AND** an `hcloud_server.registry` "must be
replaced" (the `cloud-init-registry.yml` change forces `user_data`; there is deliberately no
`ignore_changes=[user_data]`, `zot-registry.tf:274-276`) plus its ForceNew dependents — until the
dispatch applies. **CAUTION (terraform-review P2):** `scheduled-terraform-drift.yml` is detect-only,
but the auto-filed drift issue body emits generic *"run `terraform apply` locally to update state"* —
an **untargeted** apply would replace the prod registry host **OUTSIDE** the destroy-guard. This
transient drift MUST be reconciled ONLY via the `registry-host-replace` dispatch, **never** the drift
issue's generic apply text.

### Vendor-tier reality check

Hetzner block volumes: **grow-only, in-place** (cannot shrink; 60 GB is within limits). No paid-tier
gate. Cost delta: +30 GB × Hetzner volume rate (~€0.044/GB/mo ≈ **+€1.32/mo**); record via ops-advisor
(see Domain Review — Operations). Better Stack free-tier logs source is unchanged.

## Observability

The change edits an infra surface but adds **no new code path**; verification rides the **existing**
`SOLEUR_ZOT_DISK` in-surface telemetry (the blind-host probe #6244). Schema:

```yaml
liveness_signal:
  what: "soleur-registry-disk-prd Better Stack heartbeat (pings only while /var/lib/zot < 85%) + the SOLEUR_ZOT_DISK log event every 5 min"
  cadence: "heartbeat period 900s / grace 600s; SOLEUR_ZOT_DISK every 5 min"
  alert_target: "Better Stack (email via inngest escalation policy)"
  configured_in: "zot-registry.tf betteruptime_heartbeat.registry_disk_prd + cloud-init-registry.yml /etc/cron.d/zot-disk-heartbeat"
error_reporting:
  destination: "Better Stack Logs (SOLEUR_ZOT_DISK); zot container logs → journald"
  fail_loud: "resize2fs is fail-loud (resize_ok=false on failure); egress failure carried in ping_rc; heartbeat absence alerts"
failure_modes:
  - mode: "fs still full after redeploy (grow/gc did not reclaim)"
    detection: "SOLEUR_ZOT_DISK pcent stays >=85 with resize_ok=true, fs_size_gb≈57-58"
    alert_route: "soleur-registry-disk-prd heartbeat stays down → Better Stack"
  - mode: "resize did not apply (volume still 30 GB)"
    detection: "SOLEUR_ZOT_DISK fs_size_gb≈28 (30 GB device) instead of ≈57-58 (60 GB device); block_size_gb=30"
    alert_route: "in-session betterstack-query.sh read of the first post-redeploy event"
  - mode: "cosign verify fails on a kept image (sha256-* bound pruned a needed sig)"
    detection: "cosign_verify_event on the deploy host (ci-deploy.sh, WARN mode — non-blocking today)"
    alert_route: "Sentry cosign_verify_event; deploy-log WARN"
logs:
  where: "Better Stack Logs source 2457081 (SOLEUR_ZOT_DISK grep marker); journald on-host (not shipped)"
  retention: "Better Stack free-tier retention"
discoverability_test:
  command: "scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK   # NO ssh"
  expected_output: "first post-redeploy event shows pcent<85, resize_ok=true, fs_size_gb≈57-58, block_size_gb=60, zot_restarts stops climbing"
```

**Affected-surface (2.9.2):** the registry host is a deny-all/no-SSH blind surface; the existing
`SOLEUR_ZOT_DISK` event is the required in-surface probe and its fields already discriminate the
competing post-fix hypotheses in ONE event (grow-applied vs not; gc-reclaimed vs not; crash-looping
vs stable). No new probe needed.

## Architecture Decision (ADR/C4)

This PR changes two recorded contracts: the registry **volume-sizing policy** and the zot **retention
keep-set** (specifically the previously-absolute "ALWAYS keep every `sha256-*`" rule). Both are
amendments to **ADR-096**, which already carries the #6240/#6244 disk-full amendment.

### ADR

- **Amend ADR-096** (`ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`) with a new dated
  amendment **"Capacity-vs-retention recurrence (2026-07-09, #6247)"**: records that the keep-set
  legitimately exceeded 30 GB (the residual cause #6246's gc/retention tightening did not cover), the
  resolution (volume 30→60 GB + `mostRecentlyPushedCount` 10→5 for v*/commit-sha + a **bounded**
  `sha256-.*`), and the cosign-verify coupling constraint (the sig bound must never prune a *kept*
  image's signature). This is an in-scope plan task, not a follow-up.
- **ADR-087** (cosign deploy-verify) gets a one-line **consequence note** cross-referencing the new
  ADR-096 amendment: bounding `sha256-.*` retention means a mis-sized bound could prune a kept image's
  `.sig` → deploy-time `cosign verify` `UNAUTHORIZED`/fail (WARN-mode, non-blocking today; becomes
  blocking at the future WARN→ENFORCE soak flip #5933-follow-up). No topology change to ADR-087's
  decision.

### C4 views

**No C4 impact.** This is a parameter/policy change (volume GB, retention counts) — zero new external
actor, external system, container/data-store, or access relationship. Enumeration checked against all
three model files: `model.c4:258` (`zotRegistry` system) + `:376` (`hetzner -> zotRegistry` pull =
image + baked bootstrap + cosign `.sig` at boot/deploy) already model the store and the cosign-verify
edge; `views.c4:14,36` include `zotRegistry`; `spec.c4:52` (zot not muted). No external human actor is
involved in a disk resize. No zotRegistry element **description** is falsified by the change (the
descriptions carry no volume-size or keep-count literal). **Implementer task:** read all three `.c4`
files to confirm and cite before writing the "no C4 impact" line; if any description is found to carry
a now-false literal, fix it + run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing

Single atomic PR; the ADR amendments describe the target state that the same PR's dispatch realizes.
No soak-gated status flip.

## Files to Edit

- `apps/web-platform/infra/variables.tf` — `registry_volume_size` default `30 → 60`; rewrite description.
- `apps/web-platform/infra/zot-registry.tf` — update the stale `30 GB` comment at `:375`.
- `apps/web-platform/infra/cloud-init-registry.yml` — keepTags policy (`:90-95`: v* 10→5, commit-sha
  10→5, add bounded `sha256-.*` count); rewrite the `:48-65` + `:21` comment narrative.
- `apps/web-platform/infra/registry-boot-guard.test.sh` — re-word the `sha256-.*) UNCHANGED`
  assertion (`:106`) to assert the now-BOUNDED keep-set; add positive assertions for the new
  v*/commit-sha/sha256 counts (keep all resize2fs/gc/delay assertions).
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — 2026-07-09 amendment.
- `knowledge-base/engineering/architecture/decisions/ADR-087-cosign-deploy-verify-host-net-ephemeral-verifier-over-private-ghcr.md` — one-line consequence note.
- `knowledge-base/engineering/operations/post-mortems/zot-registry-disk-full-postmortem.md` — **ship deliverable**: record the 2026-07-09 recurrence + capacity-vs-retention resolution; update the #6247 action-item row (reopened / this PR).
- (conditional) `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4` — only if a description literal is found falsified (none expected).

## Files to Create

None.

## Files explicitly NOT edited (verified no change needed)

- `.github/workflows/apply-web-platform-infra.yml` (`registry_host_replace` job) — already `-target`s
  `hcloud_volume.registry`; a size update rides the existing scope.
- `tests/scripts/lib/registry-host-replace-gate.sh` + `tests/scripts/test-registry-host-replace-gate.sh`
  — the gate already permits a volume `["update"]` (Test 1 PASS path). No new fixture needed.

## Open Code-Review Overlap

None. (No open `code-review`-labelled issue touches `cloud-init-registry.yml`, `zot-registry.tf`,
`variables.tf`, or `registry-boot-guard.test.sh` — implementer to confirm via the Phase 1.7.5 grep
against the finalized file list before /work.)

## Implementation Phases

### Phase 0 — Preconditions (read-only, in-session)

1. Read the current `SOLEUR_ZOT_DISK` state: `scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK`
   (confirm `resize_ok=true`, `fs_size_gb≈block_size_gb`, `pcent≥85` — the #6247 trigger). If
   `resize_ok=false` or `fs_size_gb << block_size_gb`, **STOP** — that is a resize regression, not a
   capacity problem, and the grow is the wrong fix.
2. Reopen #6247 (`gh issue reopen 6247`) as the tracking issue for this recurrence.
3. Re-derive the live `hcloud_volume.registry` size via a **scoped** `terraform plan` (do not quote a
   stale number). Confirm the current size is 30 GB and the grow target 60 GB.
4. Read all three `.c4` files to confirm "no C4 impact" (ADR gate C4 completeness mandate).
5. Phase 1.7.5 code-review overlap grep on the finalized Files-to-Edit list.

### Phase 1 — Grow the volume (stop the bleed)

6. `variables.tf`: `registry_volume_size` default `30 → 60`; rewrite the description (drop the
   falsified "30 GB … with headroom" / "10 v* + 10 sha").
7. `zot-registry.tf`: update the `:375` stale `30 GB` comment.

### Phase 2 — Tighten the keep-set (stop the refill)

8. `cloud-init-registry.yml` `keepTags`: `v.*` `mostRecentlyPushedCount` 10→5; `[0-9a-f]{7,64}`
   10→5; `sha256-.*` add a conservative `mostRecentlyPushedCount` **50** (NOT 20 — see Sharp Edge #1:
   true keep requirement is ~12–18 sig tags/repo, and backfill/re-sign can evict out of order; 50
   never prunes a kept image at current scale). Rewrite the `:48-65` + `:21` comment narrative to
   explain the bound + the cosign-verify coupling. **If the operator resolves the persisted
   decision-challenge to DROP the sha256-* bound, skip this sub-step's sha256-* edit** (keep only the
   v*/commit-sha 10→5) and drop the ADR-087 note + the `registry-boot-guard.test.sh` sha256-* reword.
9. Verify the rendered `user_data` stays under 32,768 bytes (byte-exact at first `terraform plan`).

### Phase 3 — Tests + docs

10. `registry-boot-guard.test.sh`: re-word the sha256-* assertion; add the new-count assertions.
11. ADR-096 amendment + ADR-087 consequence note.
12. Postmortem: record the 2026-07-09 recurrence + resolution; update the #6247 row.
13. Run the registry test surface: `apps/web-platform/infra/registry-boot-guard.test.sh`,
    `tests/scripts/test-registry-host-replace-gate.sh`, and the C4 tests. Run the full suite exit
    gate (`test-all.sh` / the repo's canonical runner — do not assume a framework).

### Phase 4 — Ship + dispatch + verify (post-merge, in-session)

14. Ship the PR (`Ref #6247`, NOT `Closes`).
15. **Post-merge:** dispatch `registry-host-replace` (`gh workflow run apply-web-platform-infra.yml
    -f apply_target=registry-host-replace -f reason="#6247 grow 30→60 + tighten keep-set"`).
16. **Verify (no SSH):** poll `SOLEUR_ZOT_DISK` — first post-redeploy event shows `pcent<85`,
    `resize_ok=true`, `fs_size_gb≈57-58`, `block_size_gb=60`, `zot_restarts` stops climbing; the
    `soleur-registry-disk-prd` heartbeat returns to `status==up`; the Better Stack disk incident
    auto-resolves. Use `Monitor` (not run-in-background) for the poll per `hr-monitor-not-run-in-background-for-polling`.
    Also confirm the **private NIC came up** after the `-replace` (learning
    `2026-07-07-immutable-redeploy.md` — the NIC can miss on first boot): a peer web host's zot-mirror
    push succeeds from `10.0.1.30:5000` (no connection-refused). A fresh `SOLEUR_ZOT_DISK` event + a
    successful mirror push is the no-SSH proof it is reachable; soft-reboot via a re-dispatch only if
    the NIC did not bind.
17. `gh issue close 6247` after verification succeeds.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `variables.tf` `registry_volume_size` default is `60`; description no longer contains the
      falsified "30 GB" / "10 v* + 10 sha" phrasing (`grep -c '30 GB' variables.tf` on that block == 0).
- [ ] `cloud-init-registry.yml` `config.json` keepTags: `v.*` and `[0-9a-f]{7,64}` each carry
      `"mostRecentlyPushedCount": 5`; the `sha256-.*` pattern carries a `"mostRecentlyPushedCount"`
      (bounded — no longer count-less).
- [ ] `gcInterval:"1h"`, `delay:"2h"`, `gcDelay:"1h"`, `deleteReferrers:false` all UNCHANGED
      (verify the #6246 tightening is preserved).
- [ ] `registry-boot-guard.test.sh` passes and its sha256-* assertion now asserts a BOUNDED keep-set
      (not "UNCHANGED"); new count assertions present.
- [ ] `terraform validate` + `terraform plan` (scoped) show `hcloud_volume.registry` as an in-place
      `["update"]` (size 30→60), NOT delete/replace; rendered `user_data` < 32,768 bytes.
- [ ] `test-registry-host-replace-gate.sh` still green (the size-update PASS path is Test 1 —
      unchanged, confirming no gate edit needed).
- [ ] ADR-096 amendment + ADR-087 consequence note present; postmortem records the 2026-07-09 recurrence.
- [ ] All three `.c4` files read; "no C4 impact" line cites the checked actors/systems/relationships;
      C4 tests green.
- [ ] PR body uses `Ref #6247` (NOT `Closes`).

### Post-merge (operator/agent, in-session — automated, not a manual checklist)

- [ ] `registry-host-replace` dispatch applied (destroy-guard PASS: store + logs-token preserved,
      volume size-update permitted).
- [ ] First post-redeploy `SOLEUR_ZOT_DISK` event: `pcent<85`, `resize_ok=true`, `fs_size_gb≈57-58`,
      `block_size_gb=60`, `zot_restarts` no longer climbing (read via `betterstack-query.sh`, no SSH).
- [ ] `soleur-registry-disk-prd` heartbeat `status==up`; Better Stack disk incident auto-resolved.
- [ ] `#6247` closed after verification.

## Domain Review

**Domains relevant:** Engineering (infra), Operations (recurring vendor cost).

### Engineering (infra)

**Status:** reviewed (self, inline)
**Assessment:** Pure infra remediation on an already-provisioned host via the sanctioned dispatch. No
new resource, no new secret, no SSH step. The sharpest technical risk is the `sha256-.*` bound vs
cosign verify (Sharp Edge #1) — flagged for deepen-plan + plan-review (architecture-strategist).

### Operations

**Status:** reviewed (self, inline)
**Assessment:** +30 GB Hetzner volume ≈ **+€1.32/mo** recurring. Record via `ops-advisor` before
PR-ready (`wg-record-recurring-vendor-expense-before-ready`). Below any material budget threshold.

### Product/UX Gate

Not relevant — no UI surface in Files-to-Edit (mechanical UI-surface override did not fire). NONE.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Grow the volume ONLY (no keep-set change) | Stops the bleed but not the refill — the 2-repo keep-set keeps growing each deploy; 60 GB buys time, not a bound. Deferring the keep-set change re-queues the same incident. |
| Tighten the keep-set ONLY (no grow) | The tightened set (5+5 per repo × 2 repos × ~1.5-2 GB) *might* fit under 30 GB, but with near-zero headroom and no margin for a large image or a transient dual-push spike — fragile. Both levers give a durable margin. |
| Bound `sha256-.*` aggressively (small count) | Higher risk of pruning a *kept* image's `.sig` → cosign verify fails (no GHCR rescue, ADR-096 atomic-move). Conservative count (**50**) sized well above the ~12–18 sig-tags/repo true requirement. **User-Challenge — all 3 reviewers recommend dropping this lever entirely; persisted to decision-challenges.md** (see Sharp Edge #1). |
| Use `deleteReferrers:true` to tie sigs to subjects | Does not apply — cosign here uses **TAG-based** sigs (`sha256-<digest>.sig`), not OCI Subject-field referrers (`cloud-init-registry.yml:54-55`); `deleteReferrers` governs only Subject-field referrers. The only lever is a `keepTags` policy. |

## Sharp Edges

1. **`sha256-.*` bound vs cosign deploy-verify (top risk — all 3 deepen-plan reviewers said DROP it).**
   The current config keeps every `sha256-*` sig tag **forever by design** (ADR-087 /
   `cloud-init-registry.yml:52-55`) because deploy-time `cosign verify` fetches the signature **by tag
   from the same registry** it pulls the image. zot's `mostRecentlyPushedCount` on `sha256-.*` keeps
   the N most-recently-**pushed** sig tags — it does NOT correlate a tag's embedded digest with a
   still-present manifest. Four hard facts the deepen-plan review surfaced:
   - **The disk benefit is ~zero.** Sigs/attestations are KB–MB; the 60 GB volume is filled by
     multi-GB IMAGES. The grow + v*/commit-sha 10→5 already solve the disk with margin. Bounding
     "keep forever" → "keep N" saves single-digit MB.
   - **GHCR fallback does NOT rescue a zot-pruned sig on a KEPT image.** Under ADR-096's atomic-move
     design (`ADR-096:45-47,88-91`), cosign fetches the `.sig` from **whichever registry serves the
     pull** — a kept image served from zot fetches its `.sig` from **zot**, so a zot-pruned sig
     hard-fails verify with **no GHCR rescue**. Sharper than "GHCR covers serving".
   - **`mostRecentlyPushedCount` is heuristic-only and BREAKS under backfill.** "push-order of sigs ≈
     push-order of images" holds only under strict monotonic lockstep push; ADR-096's own mirror/
     `crane copy` backfill + re-sign path (`ADR-096:90-93`) re-pushes a sig for an OLD image out of
     order, so the "N most-recently-pushed sigs" window can evict a KEPT image's sig. No zot mechanism
     ties a tag-based sig to its subject manifest (`deleteReferrers` governs only OCI Subject-field
     referrers — not these).
   - **Count 20 is a THIN margin, not generous.** True keep requirement ≈ (~5–6 kept releases/repo) ×
     (2–3 referrer types: `.sig`+`.att`) ≈ **12–18 sig tags/repo** — 20 is only ~1.1–1.6×. If the bound
     is retained at all, use **50** (disk cost of a larger count is negligible; 50 never prunes a kept
     image at current scale yet still caps forever-growth).
   Blast radius **today** is WARN-mode (`ci-deploy.sh`, ADR-087) → a mis-size emits a
   `cosign_verify_event`, non-blocking; it becomes **blocking** at the WARN→ENFORCE flip (#5933-follow-up).
   **User-Challenge (ADR-084) — RECORDED.** All three deepen-plan reviewers (architecture-strategist,
   code-simplicity, + the IaC pass raised no objection to dropping it) recommend **dropping the
   `sha256-.*` bound from this PR** (keep only the volume grow + v*/commit-sha 10→5). The operator's
   stated direction is "both levers, bound sha256-*", which is the **default** — so the plan RETAINS
   the bound but at the safe count **50** (bounded-but-inert-now: honors the direction without risking
   a kept-image sig). The drop-vs-keep challenge is persisted to
   `knowledge-base/project/specs/feat-one-shot-zot-disk-full-capacity-retention/decision-challenges.md`
   for `ship` to render into the PR body + file as an `action-required` issue. `/work` MAY drop the
   bound if the operator resolves the challenge that way before implementation.
2. **Do NOT quote a stale volume size.** Re-derive via a scoped `terraform plan` at implementation
   (learning: drift snapshots go stale; the plan is the reconciliation).
3. **"UNCHANGED" test trap.** `registry-boot-guard.test.sh:106` `grep -qF 'sha256-.*'` still passes
   after the bound (the literal stays present), so a green test would falsely imply the keep-set is
   unchanged. Update the assertion to assert the **bound** explicitly, or the test silently rots.
4. **Ops-remediation `Ref` not `Closes`.** #6247 closes only AFTER the post-dispatch verification —
   use `Ref #6247` in the PR body (`Closes` would auto-close at merge, before the fix runs).
5. **base64gzip user_data cap.** The keepTags edit is tiny, but re-verify the rendered `user_data`
   stays under Hetzner's 32,768-byte cap at first `terraform plan`.
6. **Preserve the #6246 tightening.** Do not regress `gcInterval:1h` / `delay:2h` / `gcDelay:1h` /
   `deleteReferrers:false` while editing the keep-set — they are load-bearing from the prior fix.

## Research Insights (institutional learnings)

- `2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md` — triangulate
  disk-fullness from telemetry, not heartbeat/last-push alone; `SOLEUR_ZOT_DISK` via
  `betterstack-query.sh --grep` is the sanctioned no-SSH read. (Applied: Phase 0 precondition +
  Phase 4 verify.)
- `best-practices/2026-07-08-disk-full-reads-as-not-full-when-you-check-block-device-not-filesystem.md`
  — block-device size ≠ fs size; the #6247 trigger (`resize_ok=true`, fs≈block) is the discriminator.
- `best-practices/2026-07-09-nonblocking-copy-then-sign-publish-sign-failure-is-not-a-clean-miss.md`
  — a pruned/absent sig for a *kept* image = present-but-unsigned → deploy `verify_image_signature`
  fails (WARN-mode non-block today). Reinforces **Sharp Edge #1** — the `sha256-.*` bound must never
  prune a kept image's sig.
- `best-practices/2026-07-07-cloud-init-user-data-cap-is-measured-on-the-gzipped-render.md` — the
  32,768-byte cap is on `base64(gzip(render))`; **measure with**
  `gzip -9 -c apps/web-platform/infra/cloud-init-registry.yml | base64 -w0 | wc -c`. Real headroom is
  ~15 KB (comments count); the keepTags edit is tiny — ample room.
- `2026-07-07-immutable-redeploy.md` — after `-replace`, the **private NIC may not come up on first
  boot**; verify private-net reachability from a peer host and soft-reboot if needed. (Added to Phase 4.)
- `best-practices/2026-07-07-refactoring-a-shape-a-drift-guard-greps-breaks-the-guard.md` — when
  editing `registry-boot-guard.test.sh`, re-anchor the sha256-* assertion on the **invariant** (the
  bound is present), not the old literal; avoid matching comment prose.
- `best-practices/2026-07-03-destroy-guard-blind-to-reboot-forcing-in-place-update.md` +
  `2026-05-16-...-destroy-guard-empty-string-bypass.md` — the registry gate already validates counters
  with `^[0-9]+$` and permits only a volume `["update"]`; no gate edit here, but confirm the scoped
  plan shows **no reboot-forcing `hcloud_server.registry` update beyond the intended `-replace`**.

## Test Scenarios

- `registry-boot-guard.test.sh` — bounded sha256-* + new counts + preserved gc/retention/resize
  assertions all pass.
- `test-registry-host-replace-gate.sh` — Test 1 (volume size-update + logs-token) still PASS; Tests
  2/3 (volume delete/replace) still ABORT (proves the grow is size-update-only, not a data-losing
  replace).
- `terraform validate` + scoped `plan` — `hcloud_volume.registry` `["update"]`, not delete/replace.
- C4 syntax + render tests green.
- Full-suite exit gate green.
