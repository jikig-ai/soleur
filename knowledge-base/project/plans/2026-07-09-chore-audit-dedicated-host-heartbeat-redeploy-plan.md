---
title: "chore: audit dedicated-host heartbeats for shipped-without-redeploy gap (git-data) + recurrence guard"
type: chore
date: 2026-07-09
issue: 6242
branch: feat-one-shot-6242-heartbeat-redeploy-audit
lane: procedural
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore: audit dedicated-host heartbeats for shipped-without-redeploy gap (git-data) + recurrence guard

## Overview

Recurrence-prevention follow-up to PR #6238 (the `soleur-registry-disk-prd` missed-heartbeat
false-positive). Root cause of that incident: a **non-paused, host-cloud-init-armed heartbeat**
(`betteruptime_heartbeat.registry_disk_prd`) shipped in the same PR as the host cron that pings it,
but `terraform apply` creating the heartbeat does **not** redeploy the host, and the registry host
had **no non-SSH reprovision path** — so the ping cron was never installed and the orphaned
heartbeat fired an absence alert. PR #6238 fixed the registry host specifically by adding a
`registry-host-replace` scoped-`-replace` dispatch path.

This issue audits **every other dedicated host** for the same failure class and prevents recurrence.
The audit is **complete** (see the matrix below). The honest finding: **no host currently sits in
the live bug-class state** (non-paused + on-host cloud-init cron + no reprovision path). But two
genuine gaps remain, both squarely inside the issue's "recurrence-prevention" framing:

1. **git-data has NO non-SSH reprovision path at all** — unlike inngest (`inngest-host-replace`,
   ADR-100) and registry (`registry-host-replace`, #6238). Its host resources are
   `OPERATOR_APPLIED_EXCLUSIONS` (`plugins/soleur/test/terraform-target-parity.test.ts:484-499`) —
   a one-time operator maintenance-window apply with no dispatch path. Its heartbeat
   (`git_data_prd`) is `paused = true` today (safe), so this is a **latent** gap: the moment
   #5274 PR C arms the web-host probe cron and unpauses it, *or* git-data's cloud-init needs a
   <!-- lint-infra-ignore start -->
   config change, there is no sanctioned non-SSH way to reprovision — forcing an operator-local
   `terraform apply -replace`, which violates `hr-all-infrastructure-provisioning-servers` /
   `hr-prod-host-config-change-immutable-redeploy` (describes the anti-pattern the plan closes).
   <!-- lint-infra-ignore end -->
2. **Nothing mechanically enforces the invariant.** The #6238 bug was caught by a human *after* a
   false-positive incident. A future PR can re-introduce the class (add a non-paused,
   host-cron-armed heartbeat with no reprovision path) and no CI gate would stop it.

**Deliverables:** (A) codify the audit matrix; (B) add a mechanical recurrence guard that fails CI
if a non-paused, on-host-cloud-init-armed heartbeat lacks a `<host>-host-replace` reprovision path;
(C) add the `git-data-host-replace` dispatch path so git-data reaches parity with its two siblings,
mirroring the destroy-guarded registry/inngest jobs exactly.

> **Decision point (CTO-adjudicated: GO, re-justified):** Deliverable C adds a destroy-capable
> `-replace` dispatch to a data-bearing LUKS host (single-user-incident threshold). Its
> justification is **NOT** heartbeat recurrence-prevention — `git_data_prd` is web-host-pinged and
> paused, so the false-positive class cannot fire and the Deliverable-B guard does not require C.
> The load-bearing reason is that **git-data currently has ZERO non-SSH reprovision capability** — a
> standing violation of `hr-prod-host-config-change-immutable-redeploy` / `hr-no-ssh-fallback-in-runbooks`
> for the fleet's most irreplaceable data store. Any future git-data cloud-init/bootstrap change (a
> LUKS keyscript fix, a Vector wiring change à la inngest #6197) would today have no sanctioned path.
> CTO recommendation: **GO** — build it now while the #6238/ADR-096 pattern is fresh and mirror-able
> (Medium complexity, mostly mirroring). The defer-to-PR-C path is recorded as Alternative 2 for
> plan-review, but leaves the immutable-redeploy gap open on git-data. Primary = ship A+B+C+D.

## Problem Statement / Motivation

A dedicated Hetzner host behind a deny-all-public firewall (git-data, inngest, registry) cannot be
probed externally by Better Stack, so its liveness/health uses a **PUSH heartbeat**: something pings
a heartbeat URL on a cadence, and *absence of ping* alerts. The pinger is installed either (a) on
the host itself by cloud-init (registry disk cron, inngest systemd timer), or (b) by a separate
web-host cron over the private net (git-data + registry *liveness* — both unshipped follow-ups).

For class (a), the heartbeat and its cron ship together; if the host has no non-SSH reprovision
path, the cron is never installed and the heartbeat is a guaranteed false-positive — the #6238
incident. The correct guard already in the codebase is twofold: heartbeats whose cron is not yet
shipped are `paused = true` with `lifecycle { ignore_changes = [paused] }` (so an operator UI
unpause survives applies); heartbeats whose cron IS host-cloud-init-armed at boot must have a
`<host>-host-replace` dispatch path so the cron can be (re)installed without SSH.

Nothing mechanically ties these two facts together. This plan makes the pattern enforceable.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6242 body) | Codebase reality | Plan response |
|---|---|---|
| "audit dedicated hosts … starting with git-data" for the shipped-without-redeploy gap | git-data's heartbeat is a PUSH heartbeat armed by an **unshipped web-host cron** (TODO #5274 PR C, `git-data.tf:257-260`), *not* a git-data-cloud-init cron. So reprovisioning git-data would not even arm it. | Audit reframed: git-data's gap is "no `-replace` path at all," not "orphaned firing heartbeat." Matrix records the nuance. |
| "confirm a non-SSH reprovision path exists … so a heartbeat shipped in the same PR as its cron can actually be armed" | inngest ✓ (`inngest-host-replace`, `apply-web-platform-infra.yml:1487`), registry ✓ (`registry-host-replace`, `:1648`). git-data ✗ (no dispatch path; resources are `OPERATOR_APPLIED_EXCLUSIONS`). web = external probe, no host cron. | Add `git-data-host-replace` (Deliverable C); record parity in the guard manifest (Deliverable B). |
| "Where a host has a heartbeat but no reprovision path, add one (or file per-host follow-ups)" | Only git-data qualifies. It is currently paused/safe, so "add one" is pre-positioning + IaC-rule compliance, not fixing an active fire. | Ship C (add one), with a documented defer-to-follow-up alternative. |
| The one non-paused host-cron heartbeat class (`registry_disk_prd`) | Already fixed by #6238 (`registry-host-replace`, re-runs cloud-init → installs `zot-disk-heartbeat` cron). | No further host work; used as the guard's "must-have-path" positive fixture. |

## Audit Matrix (Deliverable A — the census)

Six `betteruptime_heartbeat` resources exist in `apps/web-platform/infra/`; the census below is
exhaustive (verified via `grep -rnE 'resource "betteruptime_heartbeat"'`). External probes
(`betteruptime_monitor.soleur_apex`/`.app`, `uptime-alerts.tf:53,93`; the `sentry_uptime_monitor.*`
family) need no host cron and are out of scope.

| # | Heartbeat (file:line) | Host / surface | `paused` | Arming mechanism | Reprovision path | Verdict |
|---|---|---|---|---|---|---|
| 1 | `inngest_prd` (inngest.tf:264) | inngest host | `true`→UI | **on-host** systemd timer (`inngest-bootstrap.sh:482`, from `cloud-init-inngest.yml:227`) | `inngest-host-replace` `-replace='hcloud_server.inngest'` (`apply-web-platform-infra.yml:1562`) | **OK** |
| 2 | `registry_prd` (zot-registry.tf:337) | registry liveness | `true` | web-host probe cron (Phase-3, **unshipped**, `zot-registry.tf:330-336`) | host `-replace` exists; pinger is web-host | **N/A (deferred, paused-safe)** |
| 3 | `registry_disk_prd` (zot-registry.tf:378) | registry disk-health | **`false`** | **on-host** cron `/etc/cron.d/zot-disk-heartbeat` (`cloud-init-registry.yml:180`) | `registry-host-replace` `-replace='hcloud_server.registry'` (`apply-web-platform-infra.yml:1721`, #6238) | **OK (the fixed exemplar)** |
| 4 | `github_webhook_sig_failures` (alerts-github-webhook.tf:56) | web app route (PR-H #3244) | `true` | **app/container emit** (webhook route pings on sig-failure) | container redeploy via ci-deploy (path exists) | **N/A (app-level)** |
| 5 | `github_api_429_sustained` (alerts-github-webhook.tf:73) | web app route | `true` | **app/container emit** | container redeploy via ci-deploy | **N/A (app-level)** |
| 6 | `git_data_prd` (git-data.tf:230) | git-data liveness | `true` | web-host probe cron (**unshipped** TODO #5274 PR C, `git-data.tf:257-260`) | **NONE for `hcloud_server.git_data`** | **latent gap → Deliverable C** |

**Conclusion:** State (b) GAP count = 0 today. The two on-host-cron heartbeats (#1 timer, #3 disk
cron) both have reprovision paths; the paused liveness/app heartbeats (#2, #4, #5, #6) are
false-positive-safe. git-data (#6) is the only dedicated host with *no* `-replace` path at all.

## Proposed Solution

### Deliverable A — Audit documentation
Codify the matrix above. Primary home: this plan + the `## Decision` of the new ADR (Deliverable D)
+ inline comments in the guard test's manifest (Deliverable B). No separate KB doc — the guard
manifest IS the living, enforced version of the matrix. Add a one-line pointer from the registry
post-mortem's follow-up section to this audit.

### Deliverable B — Mechanical recurrence guard (the core recurrence-prevention piece)
A CI test that parses `apps/web-platform/infra/*.tf` for every `betteruptime_heartbeat` block and
enforces the invariant against an in-test manifest that classifies each heartbeat by arming
mechanism. The guard is a **static-analysis test** — zero live infra, no secrets.

Invariant enforced (worded per CTO — keyed on **the monitored host's remediation**, NOT the cron's
location, so it correctly covers inngest's systemd timer and does not misclassify git-data's
web-host ping):

> Every non-paused `betteruptime_heartbeat` whose arming/remediation depends on a **dedicated
> Hetzner host's boot-time provisioning** (an on-host cloud-init cron OR a cloud-init-installed
> systemd timer) MUST have that host's `<host>-host-replace` dispatch path (a choice option in
> `apply-web-platform-infra.yml` + a `-replace='hcloud_server.<host>'` line in its job).

- Every `betteruptime_heartbeat` discovered in the `.tf` files MUST appear in the manifest (a new
  heartbeat with no classification **fails** the test → forces the author to declare arming +
  reprovision, closing the silent-add hole).
- `arming = dedicated-host-boot` **and** `paused = false` → the declared `<host>-host-replace` path
  MUST exist. `paused = true` heartbeats and `arming ∈ {web-host-cron, app-emit, external-probe}`
  are exempt (recorded with exemption reason) — their remediation is a web-host/container ci-deploy
  (which always exists) or an external probe, not a dedicated-host reprovision.

Run today, the guard PASSES: only `registry_disk_prd` is `dedicated-host-boot` + `paused=false`, and
`registry-host-replace` exists. It is forward-looking and is the mechanical gate that would have
caught #6238: unpausing `inngest_prd` without `inngest-host-replace`, or adding a new non-paused
dedicated-host-boot heartbeat with no path, turns it RED. (Note: `git_data_prd` is `web-host-cron`
armed → exempt even when unpaused — so this guard does NOT by itself require Deliverable C; C is
justified independently below.)

The `paused` value is read from the `.tf` source (the guard asserts the *declared* value); this is a
source-drift guard, not a live-state probe — matching the codebase's other `terraform-*.test.ts`
guards.

### Deliverable C — `git-data-host-replace` dispatch path
Mirror `registry_host_replace` / `inngest_host_replace` exactly:
1. Add `git-data-host-replace` to the `apply_target` choice enum + description
   (`apply-web-platform-infra.yml:92,96-102`).
2. New job `git_data_host_replace` (`if: workflow_dispatch && inputs.apply_target ==
   'git-data-host-replace'`) running a scoped `terraform apply -replace='hcloud_server.git_data'`
   with the exact `-target=` set (below), reusing the top-level
   `concurrency: terraform-apply-web-platform-host` group.
3. New sourced destroy-guard `tests/scripts/lib/git-data-host-replace-gate.sh` — a **5-member**
   allow-set (server + network + both volume attachments + firewall attachment) that preserves
   **both** git-data volumes + the LUKS passphrase BY OMISSION (they are OUTSIDE the allow-set).
   (Reconciled at /work: the detailed Technical Approach §"exact -target= set" and §"destroy-guard
   contract" both specify 5; the earlier "7" here conflated 5 targets + 2 omitted volumes.)
4. New test `tests/scripts/test-git-data-host-replace-gate.sh`; register in `scripts/test-all.sh`
   (mirror `:159-160`).
5. Add `git_data_host_replace` to `stripDispatchJobs()` in
   `plugins/soleur/test/terraform-target-parity.test.ts:425-431` (belt-and-suspenders per the
   established best-practice comment at `:416-424`).
6. Add a REPROVISION-PATH note to `git-data.tf` (mirror the note #6238 added at
   `zot-registry.tf:24-28`).

### Deliverable D — ADR (Deliverable of this plan, not deferred)
Two distinct decisions (CTO ruling), so two ADR actions:
- **ADR-100 amendment** — adding `git-data-host-replace` is the **third application** of the
  established host-replace mechanism (ADR-096 registry, ADR-100 inngest), not a novel decision. Amend
  ADR-100 (or add a short cross-referencing note to ADR-068 git-data) recording git-data as the third
  host to adopt the scoped `-replace` dispatch. No new ordinal for this.
- **New short ADR-103** (provisional ordinal — re-verify next-free at ship): *"Dedicated-host
  boot-armed push heartbeats require a mechanically-guarded non-SSH reprovision path."* This is the
  genuinely new cross-cutting rule (the invariant the Deliverable-B guard enforces), generalizing the
  ad-hoc registry #6238 fix. Cross-references #6238, ADR-096, ADR-100, ADR-068. Names the guard as
  its enforcement. No C4 model edit (see Architecture Decision section).

> CTO also suggested surfacing the invariant as an AGENTS.md `wg-*` gate for plan-time loading.
> **Deferred as optional:** `AGENTS.md` always-loaded budget is near-cap (a recent PR descoped a
> planned rule at 22994/23000 bytes). The CI guard (Deliverable B) IS the enforcement; the ADR is the
> record. `/work` should attempt the AGENTS pointer only if `B_ALWAYS` headroom permits (measure per
> `2026-06-15-agents-budget-at-cap` learning); otherwise ADR-103 + the CI guard stand alone.

## Technical Approach

### The exact `-target=` set for `git-data-host-replace` (5 targets — volumes preserved by OMISSION)
Per learning `2026-07-07-immutable-redeploy.md`: `-replace` is transitive on **dependencies**, not
**dependents** — a bare `-replace=hcloud_server.git_data` drops the NIC, firewall attachment, and
volume attachments unless each is explicitly `-target`ed. The two data volumes are **deliberately
NOT `-target`ed** (mirrors inngest's `hcloud_volume.inngest_redis` omission, not registry's in-scope
volume): an untargeted resource cannot be planned for destroy, so omission is simpler *and* strictly
safer than including them. git-data has no pending resize (registry included its volume only to ride
a 10→30 GB resize — N/A here). Set (5 `-target=`):

```text
-replace='hcloud_server.git_data'
-target='hcloud_server.git_data'                    # host (ForceNew server recreate)
-target='hcloud_server_network.git_data'            # network.tf:48 — private NIC 10.0.1.20 (server_id ForceNew); ONLY transport path
-target='hcloud_volume_attachment.git_data'         # git-data.tf:194 — plaintext bare-repo volume (ForceNew); else /mnt/git-data unmounted
-target='hcloud_volume_attachment.git_data_luks'    # git-data-luks.tf:90 — LUKS volume (ForceNew); else /mnt/git-data-luks unmounted
-target='hcloud_firewall_attachment.git_data'       # git-data.tf:215 — deny-all-public firewall (registry-style INCLUDE, NOT inngest omission: fresh host has public IPv4/IPv6, would boot NAKED without it)
# NO -target for hcloud_volume.git_data (git-data.tf:183) or hcloud_volume.git_data_luks (git-data-luks.tf:79) — preserved by omission.
# NO -target for random_password.git_data_luks / doppler_secret.git_data_luks_key — a rotated passphrase would fail to open the existing LUKS header.
```

Keep the ephemeral-SSH-key step (`file()` evaluates at plan time regardless of `-target` filtering —
same as the sibling jobs, `apply-web-platform-infra.yml:1503,1664`).

### The destroy-guard (`git-data-host-replace-gate.sh`) contract
Mirror `registry-host-replace-gate.sh` but with a **5-member allow-set** (volumes NOT in the set —
so any volume change leaking in is caught by `out_of_scope` directly; registry needed its
`store_destroyed` named backstop only because its volume WAS in the allow-set). PASS (rc=0) iff:

```text
out_of_scope==0                    # no create/update/delete/forget outside the 5-member allow-set
server_replaced==1                 # hcloud_server.git_data shows BOTH delete and create
nic_recreated>=1                   # hcloud_server_network.git_data shows create (else no private-net transport)
plaintext_attachment_recreated>=1  # hcloud_volume_attachment.git_data shows create (else /mnt/git-data unmounted)
luks_attachment_recreated>=1       # hcloud_volume_attachment.git_data_luks shows create — SEPARATE counter (else LUKS at-rest store unmounted)
firewall_ok>=1                     # hcloud_firewall_attachment.git_data update|create
```

Allow-set (exact-equality `IN(.address; allow[])`, 5 members): `hcloud_server.git_data`,
`hcloud_server_network.git_data`, `hcloud_volume_attachment.git_data`,
`hcloud_volume_attachment.git_data_luks`, `hcloud_firewall_attachment.git_data`.

**Named "must be preserved" backstops** (operator-legible + GDPR-relevant; redundant with
`out_of_scope` since the volumes/passphrase are outside the allow-set, but high-value error text):
```text
git_data_volume_destroyed==0   # hcloud_volume.git_data no delete/forget
luks_volume_destroyed==0       # hcloud_volume.git_data_luks no delete/forget (Art.17 at-rest store + rollback backstop)
luks_passphrase_untouched==0   # random_password.git_data_luks AND doppler_secret.git_data_luks_key show ZERO actions —
                               # a rotated passphrase opens a NEW header, stranding the old LUKS data (CTO High-if-mis-scoped risk)
```

No `[ack-destroy]` bypass — authorized only by the menu-ack `workflow_dispatch`
(`hr-menu-option-ack-not-prod-write-auth`). Belt-and-suspenders post-apply jq assert mirrors
`apply-web-platform-infra.yml:1748-1777`, plus the mid-replace-failure annotation (registry
`:1757-1765`): old host destroyed + new create fails leaves git-data DOWN with the writer-side CAS
fence offline — but both volumes are preserved, so re-dispatch recovers from them.

### LUKS re-open safety on fresh boot (CTO-verified)
`cloud-init-git-data.yml:142-163` is idempotent: `if ! cryptsetup isLuks "$DEV"; then luksFormat ...`
— on a `-replace` the existing LUKS volume re-attaches, `isLuks` returns true → **luksFormat is
skipped** (no header wipe), `luksOpen --key-file -` runs with the unchanged passphrase. Data is
preserved and auto-unlocked with NO SSH. This safety holds **only if** the replace scope excludes
`random_password.git_data_luks` / `doppler_secret.git_data_luks_key` (guarded by
`luks_passphrase_untouched`) AND both `hcloud_volume.*` (guarded by omission + the named backstops).

### The recurrence guard (`heartbeat-reprovision-parity.test.ts`) shape
New test under `plugins/soleur/test/` (sibling to `terraform-target-parity.test.ts`). Reads the
`.tf` files with the same comment-strip + block-scan helpers, builds the discovered heartbeat set,
and diffs against the manifest. Manifest rows (one per heartbeat) declare `{ name, arming, paused,
replace_target | exempt_reason }` where `arming ∈ {dedicated-host-boot, web-host-cron, app-emit,
external-probe}`. Assertions: (1) discovered ⊆ manifest and manifest ⊆ discovered (no orphan either
way); (2) for `arming == dedicated-host-boot && !paused`, `replace_target` resolves to a real choice
option + `-replace='hcloud_server.<host>'` line in the workflow.

## Architecture Decision (ADR/C4)

### ADR
Two actions (CTO split — the git-data path is a re-application; the invariant is the new decision):
- **Amend ADR-100** (inngest host-replace) / cross-ref ADR-068: record git-data as the third host to
  adopt the scoped `-replace` dispatch mechanism. No new ordinal.
- **Create ADR-103** (provisional ordinal per `wg-architecture-decision-is-a-plan-deliverable`;
  ship's ADR-Ordinal Collision Gate re-verifies next-free against `origin/main`; if renumbered, sweep
  this plan + `tasks.md` + any AC naming the ordinal in the same edit). Decision: *a non-paused
  `betteruptime_heartbeat` armed by a dedicated Hetzner host's boot-time provisioning MUST have a
  mechanically-guarded non-SSH `<host>-host-replace` reprovision path; the
  `heartbeat-reprovision-parity` test is that guard.* Generalizes the registry #6238 fix; references
  #6238 / ADR-096 / ADR-100 / ADR-068. `## Alternatives Considered` records "keep it ad-hoc per host"
  (rejected — that IS what let #6238 happen) and "fold the invariant into ADR-100" (rejected —
  ADR-100 is inngest-scoped; the invariant is cross-host).

### C4 views
**No C4 model edit.** All relevant elements are already modeled — verified by reading all three
`.c4` files:
- **External actors:** the operator dispatching a maintenance-window `workflow_dispatch` — an
  operational action, not a C4 actor; no new human actor.
- **External systems:** Hetzner Cloud (`model.c4:180 hetzner`), Better Stack
  (`model.c4:262-264 betterstack` — already names "Apex + inngest/git-data heartbeats"), GitHub
  Actions (the dispatch runner) — all modeled.
- **Containers / stores:** the git-data host + its store (`model.c4:210 gitDataStore`), inngest
  (`:184`), zot registry (`:258`) — modeled.
- **Access relationships:** adding a reprovision *dispatch workflow* changes no modeled edge (it is
  a CI operation on an existing host, not a new data-flow between elements).
This is a "no C4 impact" conclusion backed by the external-actor / external-system / store /
relationship enumeration the C4 completeness mandate requires — not an unsupported "None". No
`views.c4` include line changes; no `.c4` validation-test run needed (no model delta).

## Infrastructure (IaC)

<!-- lint-infra-ignore start -->
This plan routes the new reprovision capability through IaC (a destroy-guarded `workflow_dispatch`
job running scoped `terraform apply -replace`), NOT operator SSH — satisfying
`hr-all-infrastructure-provisioning-servers` and `hr-prod-host-config-change-immutable-redeploy`.
<!-- lint-infra-ignore end -->

### Terraform changes
- **No new `.tf` resources.** The `-replace` targets the existing `hcloud_server.git_data` and its
  dependents. Only a doc-comment REPROVISION-PATH note is added to `git-data.tf`.
- Providers/pins: unchanged (`hcloud`, `betteruptime` already declared in `main.tf`).
- Sensitive vars: unchanged — the git-data cloud-init already consumes `doppler_service_token.git_data`
  (scoped `prd_git_data`, `git-data.tf:166`); no new `TF_VAR_*`, no operator mint.

### Apply path
**(c) taint + `terraform apply -replace`** via the `git-data-host-replace` dispatch — a
maintenance-window, menu-ack, destroy-guarded run. git-data is cloud-init-only (NO remote-exec
provisioner, `git-data.tf:9`), so the `-replace` re-runs cloud-init cleanly (no SSH provisioner to
hang the apply). Downtime/blast-radius: git-data is the single-writer workspace-git store at
replicas=1 — a `-replace` causes a git push/pull outage window for the duration of host recreate +
cloud-init + LUKS re-open. This is a deliberate, operator-initiated maintenance action (same class
as the registry/inngest paths). It never auto-applies (dispatch-only, not merge-triggered).

### Distinctness / drift safeguards
- git-data resources are `OPERATOR_APPLIED_EXCLUSIONS` (`terraform-target-parity.test.ts:484-499`),
  so a routine per-PR merge does NOT touch them and cannot fight the `-replace`. The new dispatch
  job's `-target`s are all exclusions → per-PR coverage anchor unaffected (guaranteed by adding it
  to `stripDispatchJobs`).
- Destroy-guard preserves BOTH volumes; the belt-and-suspenders post-apply assert is the second
  brake. Per `2026-07-07-immutable-redeploy.md`, a fresh Hetzner host may boot with the private NIC
  down even when the control plane shows it attached — the plan adds a post-replace reachability
  verification step (web-host `git ls-remote` over the private net) BEFORE the run is declared
  successful, and the diagnosis path must NOT depend on SSH to the deny-all host.

### Vendor-tier reality check
Better Stack paid-tier features (`policy_id`) are already `var.betterstack_paid_tier`-gated on
`git_data_prd` (`git-data.tf:242`); no tier change. No new vendor account.

## User-Brand Impact

- **If this lands broken, the user experiences:** a botched `git-data-host-replace` dispatch —
  a destroy-guard that wrongly permits a plan (a) destroying `hcloud_volume.git_data` /
  `hcloud_volume.git_data_luks`, (b) **rotating the LUKS passphrase** (`random_password.git_data_luks`
  / `doppler_secret.git_data_luks_key` in scope → the fresh boot luksOpens a NEW header, stranding
  the existing at-rest data — the R2 vector, guarded by `luks_passphrase_touched`), or (c) a
  `-replace` that boots git-data with the private NIC down / a store attachment unmounted — makes a
  user's workspace bare-git repository (their entire commit history for that workspace) inaccessible
  or lost.
- **If this leaks, the user's workflow/data is exposed via:** n/a for the *guard* deliverables (A/B
  are static tests). For C, the `-replace` re-runs the same cloud-init that already luksOpens the
  at-rest-encrypted volume; the change adds no new exposure vector — the LUKS key stays in the
  scoped `prd_git_data` token, never in user_data.
- **Brand-survival threshold:** `single-user incident` — git-data holds irreplaceable per-user
  workspace git history (ADR-068); a mis-scoped destructive `-replace` is a per-user data-loss event.

CPO sign-off required at plan time before `/work` begins (carried via Domain Review). `user-impact-
reviewer` runs at review-time (review/SKILL.md conditional-agent block) against the diff, enumerating
the destroy-guard's failure modes.

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions run status of the git_data_host_replace dispatch job (its ::error:: on gate ABORT); and, once #5274 PR C ships, the betteruptime_heartbeat.git_data_prd absence alert."
  cadence: "per-dispatch (on-demand maintenance run); git_data_prd period=60s once unpaused."
  alert_target: "GitHub Actions run UI + ops@jikigai.com (betteruptime_team_member.ops, uptime-alerts.tf:156) for the heartbeat."
  configured_in: ".github/workflows/apply-web-platform-infra.yml (git_data_host_replace job); apps/web-platform/infra/git-data.tf:230 (heartbeat)."
error_reporting:
  destination: "GitHub Actions job log (::error:: annotations from the destroy-guard); the parity/gate tests fail the CI run in scripts/test-all.sh."
  fail_loud: "git_data_host_replace_gate ABORT prints the failing counter line and returns 1 (job fails, no apply); heartbeat-reprovision-parity.test.ts fails the build with the un-classified/un-pathed heartbeat named."
failure_modes:
  - mode: "A future non-paused host-cron heartbeat ships with no <host>-host-replace path (the #6238 class recurs)."
    detection: "heartbeat-reprovision-parity.test.ts fails in CI (static analysis of *.tf + the workflow)."
    alert_route: "CI red on the PR; blocks merge."
  - mode: "git-data-host-replace plan would destroy a git-data volume or strip the NIC/firewall."
    detection: "git_data_host_replace_gate.sh reads the structured plan JSON, counters != PASS set, returns 1."
    alert_route: "dispatch job fails with ::error::; no terraform apply runs."
  - mode: "git-data boots after -replace with private NIC down (immutable-redeploy risk)."
    detection: "post-replace web-host `git ls-remote` reachability step fails the job."
    alert_route: "dispatch job fails; operator re-runs / investigates via control-plane (never SSH to deny-all host)."
logs:
  where: "GitHub Actions run logs (retained per repo policy); test output in the CI run."
  retention: "GitHub Actions default (90 days)."
discoverability_test:
  command: bash tests/scripts/test-git-data-host-replace-gate.sh
  expected_output: "16 passed, 0 failed"
  # Single, no-SSH, non-shell-active command (runnable under preflight Check 10's env -i sandbox);
  # exit 0 + the summary line proves the destroy-guard's 16 fixtures all PASS/ABORT as specified.
  # Option-presence is separately locked by the terraform-target-parity job<->gate parity block
  # (grep -c 'git-data-host-replace' .github/workflows/apply-web-platform-infra.yml >= 2, AC4).
```

Affected-surface note (2.9.2): git-data is a blind host (deny-all, no SSH), but these deliverables
add CI/dispatch surfaces, not code that runs ON git-data. The dispatch's telemetry is the structured
terraform-plan JSON the destroy-guard reads (a discriminating in-plan signal: which resource shows
which action) + the post-apply reachability probe — the root-cause of an ABORT is decided from the
counter line in one job log, no SSH.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (audit):** This plan's Audit Matrix enumerates all 6 `betteruptime_heartbeat` resources
      with file:line, `paused` value, arming mechanism, and reprovision-path verdict; count matches
      `grep -rcE 'resource "betteruptime_heartbeat"' apps/web-platform/infra/*.tf | awk -F: '{s+=$2} END{print s}'` == 6.
- [x] **AC2 (guard exists + passes today):** `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`
      exists, is registered in the bun test surface, and PASSES against current `main` (only
      `registry_disk_prd` is on-host-cloud-init+non-paused, and `registry-host-replace` exists).
- [x] **AC3 (guard is load-bearing):** a synthetic fixture (an un-manifested heartbeat, AND a
      non-paused on-host-cron heartbeat whose `<host>-host-replace` option is absent) makes the guard
      FAIL — proving it is not vacuous.
- [x] **AC4 (git-data dispatch option):** `apply-web-platform-infra.yml` `apply_target` choice enum
      contains `git-data-host-replace`; `grep -c "git-data-host-replace" .github/workflows/apply-web-platform-infra.yml >= 2` (option + job `if:`).
- [x] **AC5 (git-data replace targets):** the `git_data_host_replace` job contains
      `-replace='hcloud_server.git_data'` and all **5** `-target=` lines above (server + network +
      both volume attachments + firewall attachment; the "7" in an earlier draft conflated 5
      targets with the 2 omitted volumes — reconciled at /work); a `bun test`/parity assertion
      confirms the target set includes both volume attachments.
- [x] **AC6 (destroy-guard):** `tests/scripts/lib/git-data-host-replace-gate.sh` +
      `tests/scripts/test-git-data-host-replace-gate.sh` exist; the test exercises fixtures for
      PASS (scoped recreate, both volumes preserved), ABORT-on-bare-repo-volume-destroy,
      ABORT-on-luks-volume-destroy, ABORT-on-stripped-NIC, ABORT-on-out-of-scope; suite exits 0.
- [x] **AC7 (test-all registration):** `scripts/test-all.sh` runs the git-data gate suite (grep for
      `git-data-host-replace-gate` returns a `run_suite` line).
- [x] **AC8 (parity strip):** `stripDispatchJobs()` in `terraform-target-parity.test.ts` includes
      `git_data_host_replace`; the full `plugins/soleur/test/terraform-target-parity.test.ts` suite
      passes.
- [x] **AC9 (tf note):** `git-data.tf` carries a REPROVISION-PATH doc note referencing
      `git-data-host-replace` (mirror `zot-registry.tf:24-28`).
- [x] **AC10 (ADR):** `ADR-103-*.md` exists under `knowledge-base/engineering/architecture/decisions/`
      with `## Decision` + `## Alternatives Considered`; ordinal re-verified next-free at ship.
- [x] **AC11 (whole suite green):** `bash scripts/test-all.sh` exits 0; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

### Post-merge (operator)
<!-- lint-infra-ignore start -->
- None. No terraform apply is required by this change — the `git-data-host-replace` path is a
  *capability* added to the dispatch menu, exercised only when an operator later needs to reprovision
  git-data. Its correctness is proven pre-merge by the destroy-guard fixtures (no live apply).
  `Automation: N/A` — nothing to run at merge.
<!-- lint-infra-ignore end -->

## Test Scenarios

- Given the current `main` tree, when `heartbeat-reprovision-parity.test.ts` runs, then it PASSES
  (all 6 heartbeats classified; the sole non-paused on-host-cron one has its path).
- Given a synthetic `.tf` fixture adding `betteruptime_heartbeat.rogue` with `paused = false` and no
  manifest entry, when the guard runs, then it FAILS naming `rogue`.
- Given a synthetic terraform plan JSON that deletes `hcloud_volume.git_data_luks`, when
  `git_data_host_replace_gate` runs, then it ABORTs with `luks_volume_destroyed=1`.
- Given a plan JSON that replaces the server but omits `hcloud_server_network.git_data`, when the
  gate runs, then it ABORTs with `nic_recreated=0`.
- Given the scoped git-data recreate plan (server + NIC + both attachments create, both volumes
  no-op/update), when the gate runs, then it PASSES.

## Dependencies & Risks

- **R1 — data-loss on mis-scoped replace (single-user incident, HIGH):** mitigated by the 5-member
  destroy-guard (both volumes preserved by omission + named `git_data_volume_destroyed` /
  `luks_volume_destroyed` backstops) + post-apply jq assert; no `[ack-destroy]` bypass; dispatch-only
  (never auto-applies). Load-bearing risk; the guard fixtures (AC6) are its proof.
- **R2 — LUKS passphrase in replace scope → header won't open (HIGH-if-mis-scoped):** a
  `random_password.git_data_luks` / `doppler_secret.git_data_luks_key` rotation in the plan would
  luksOpen a NEW header, stranding the old at-rest data. Mitigated by the `luks_passphrase_untouched`
  gate assertion (zero actions on both). The idempotent `isLuks` skip (`cloud-init-git-data.yml:142-163`)
  only preserves data when the passphrase is unchanged.
- **R3 — mid-replace apply failure → git-data DOWN (HIGH, single-writer no-fallback):** if the old
  host is destroyed and the new create fails (quota/image/boot), git-data is down with the writer-side
  CAS fence offline — unlike registry (GHCR fallback) / inngest (paused reminders), git-data has NO
  fallback. Both volumes are preserved so re-dispatch recovers; the write-outage window (~10 min fresh
  boot + LUKS open) is real and inherent to any host replace. Runbook states: writes **fail, not
  corrupt**; single-writer → no split-brain. Mirror registry's mid-replace-failure `::error::`
  annotation.
- **R4 — private-NIC-down / firewall-not-attached on fresh boot** (`2026-07-07-immutable-redeploy.md`):
  the gate asserts `hcloud_server_network.git_data` re-created AND `hcloud_firewall_attachment.git_data`
  re-attached; a post-replace web-host `git ls-remote` readiness probe is the authoritative liveness
  gate; diagnosis never SSHes the deny-all host.
- **R5 — scope judgment on Deliverable C** (CTO ruled GO; Overview decision point): if plan-review
  overrides, ship A+B+D and file the per-host follow-up (Alternative 2).
- **R6 — ADR ordinal collision:** provisional ADR-103; re-verify next-free at ship; if renumbered,
  sweep plan + tasks.md + ACs in the same edit.

## Alternative Approaches Considered

| Alternative | Description | Disposition |
|---|---|---|
| **1 (primary): A+B+C+D** | Audit + recurrence guard + git-data-host-replace + ADR. | **Chosen** — closes git-data's real (if latent) reprovision-path gap now, matches the issue's "add one" for the named host, and mirrors two shipped siblings (low novelty). |
| **2: A+B+D, defer C** | Ship audit + guard + ADR; file a per-host follow-up to add `git-data-host-replace` alongside #5274 PR C when the probe cron actually arms `git_data_prd`. | **Deferred-fallback** — if CTO/plan-review judges adding a destroy-capable path to a data-bearing host premature (YAGNI: C doesn't arm the paused heartbeat). Requires a tracking issue with re-eval criteria = "#5274 PR C lands / git_data_prd unpaused." |
| **3: guard only (B)** | Just the mechanical guard; no git-data path, no ADR. | **Rejected** — leaves git-data with zero non-SSH reprovision path (IaC-rule gap) and under-delivers on the issue's git-data focus. |
| **4: unpause + build the probe cron here** | Actually arm `git_data_prd` (build the web-host probe cron + systemd timer + unpause). | **Rejected** — that IS #5274 PR C, a distinct larger work-stream (web-host ci-deploy wiring); out of scope for this audit chore. |

## Domain Review

**Domains relevant:** Engineering (CTO). Product = NONE (no `components/**`, `app/**/page.tsx`,
or any UI-surface path; files are `.yml`/`.tf`/`.sh`/`.test.ts`). Legal/GDPR — see Compliance note.

### Engineering (CTO + terraform-architect)

**Status:** reviewed.

**CTO assessment:**
- **Deliverable C: GO, re-justified.** Not heartbeat-recurrence (paused heartbeat can't fire) — the
  driver is git-data's ZERO non-SSH reprovision capability, a standing `hr-prod-host-config-change-immutable-redeploy`
  violation on the fleet's most irreplaceable data store. Medium complexity (mirror + gate + test +
  parity-strip). Defer-to-PR-C defensible on YAGNI but leaves the gap open.
- **Deliverable B: GO, reshape the invariant** (applied above) — key on the monitored host's
  remediation, not "on-host cloud-init cron" (which would miss git-data's web-host ping and read
  inngest's systemd timer wrong). Cheap CI test; correct forward shape; not overkill for a p2.
- **LUKS re-open is SAFE conditionally** (`cloud-init-git-data.yml:142-163` idempotent `isLuks`
  skip) — ONLY if the replace scope excludes `random_password.git_data_luks` /
  `doppler_secret.git_data_luks_key` (a rotated passphrase strands the old header). → new gate
  assertion `luks_passphrase_untouched` (applied above).
- **ADR:** split into ADR-100 amendment (git-data = 3rd application) + new ADR-103 (the parity
  invariant). Consider an AGENTS.md `wg-*` gate — deferred on budget (applied above).
- **Highest risk:** mid-replace apply failure → git-data DOWN (single-writer, NO fallback unlike
  registry/inngest). Volumes preserved → re-dispatch recovers; write-outage window is real
  (~10 min fresh boot + LUKS open). Writes FAIL, not corrupt; single-writer → no split-brain.

**terraform-architect assessment:**
- **`-target` set = 5, volumes preserved by OMISSION** (applied above) — simpler + strictly safer
  than including them (registry included its volume only for a pending resize; git-data has none).
- **Gate = 5-member allow-set** (volumes OUT → `out_of_scope` catches leaks directly) + separate
  `luks_attachment_recreated` counter + named volume/passphrase backstops (applied above).
- **Post-replace verification differs from registry:** git-data's heartbeat is paused + probe cron
  unbuilt, so a "best-effort heartbeat status" step is useless → **OMIT it**. Verify via (i) in-job
  jq NIC/attachment/volume assertions from the saved plan (load-bearing — no runtime fallback if the
  NIC is stripped), and (ii) the out-of-job web-host private-net `git ls-remote` readiness probe
  (`git-data.tf:12-14`) as the authoritative liveness gate. Never imply a Better Stack pull
  (deny-all makes pull impossible). Satisfies `hr-fresh-host-provisioning-reachable-from-terraform-apply`
  / `hr-no-ssh-fallback-in-runbooks`.
- **Parity/concurrency (mechanical):** all 5 targets + both volumes are ALREADY
  `OPERATOR_APPLIED_EXCLUSIONS` (`terraform-target-parity.test.ts:484-535`) → no per-PR fight; must
  add `git_data_host_replace` to `stripDispatchJobs`. Inherit the workflow-level
  `concurrency: terraform-apply-web-platform-host` (`:104-119`), add NO per-job block;
  `cancel-in-progress: false` mandatory (a cancelled half-replace is the worse split-state).

### Product/UX Gate

Not applicable — no user-facing surface. NONE.

## Compliance (GDPR gate — Phase 2.7)

Trigger (b) fires: `brand-survival threshold = single-user incident` on a host that stores personal
data (workspace repos may contain PII). Assessment: this change adds **no new processing activity** —
it adds a reprovision *dispatch path* + static CI guards. The load-bearing compliance requirement is
**data preservation** (the destroy-guard MUST NOT permit a git-data volume destroy), already the
central AC6 assertion. The existing Art. 17 erasure path (`git-data-remove.sh` forced command) is
untouched. No Art. 30 register change. `/soleur:gdpr-gate` may run in deepen-plan for confirmation;
no Critical finding anticipated (no new lawful-basis question, no special-category processing added).

## References & Research

### Internal references
- Incident post-mortem: `knowledge-base/engineering/operations/post-mortems/registry-disk-heartbeat-false-positive-postmortem.md`
- Immutable-redeploy sharp edges: `knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md`
- Canonical TF invocation triplet: `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`
- Better Stack free-tier / heartbeat quirks: `knowledge-base/project/learnings/2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md`
- Exemplar jobs: `.github/workflows/apply-web-platform-infra.yml` (`registry_host_replace` :1648-1830, `inngest_host_replace` :1487-1620)
- Exemplar gates: `tests/scripts/lib/registry-host-replace-gate.sh`, `tests/scripts/lib/inngest-host-replace-gate.sh`
- Target-parity guard: `plugins/soleur/test/terraform-target-parity.test.ts` (git-data exclusions :484-499; `stripDispatchJobs` :412-432)
- git-data resources: `apps/web-platform/infra/git-data.tf`, `git-data-luks.tf`, `network.tf:48`
- ADRs: ADR-068 (git-data / multi-host), ADR-096 (zot registry), ADR-100 (inngest host-replace), ADR-082 (fresh-host observability)

### Related work
- Fixes-forward: #6238 (registry-host-replace), #6246 (registry disk root-cause)
- Related epic: #5274 Phase 2/3 (git-data host; PR C = web-host probe cron that arms `git_data_prd`)
- This issue: #6242
