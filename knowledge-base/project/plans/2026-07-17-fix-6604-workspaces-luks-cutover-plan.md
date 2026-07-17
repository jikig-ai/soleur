---
title: "fix(security): #6604 — the /workspaces LUKS cutover (PR 2 — the half that moves sole-copy user data)"
issue: 6604
parent_issue: 6588
date: 2026-07-17
lane: cross-domain
type: security-remediation
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-119 (EXISTS on main, status:adopting → accepted on soak-pass — this PR does NOT mint a new ADR)
supersedes_sections_of: knowledge-base/project/plans/2026-07-17-fix-6588-luks-encrypt-workspaces-volume-plan.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Ack rationale: Phase 2.8 ran. Every host command named below is a step INSIDE a
  workflow-orchestrated script (`workspaces-cutover.sh`), executed by a `workflow_dispatch`
  job/workflow with credentials held off-host over the sanctioned CF-Tunnel SSH bridge — the
  `git-data-cutover.yml` / `git_data_host_replace` precedent. This plan authors ZERO commands
  for a human to run at a keyboard. The only human act is a risk-acceptance authorization to
  engage the freeze (see §Automation feasibility).
-->

# 🔒 fix(security): the `/workspaces` LUKS cutover (#6604 — PR 2 of #6588)

> ## ⚠️ Enhancement Summary — Deepen Pass (2026-07-17)
>
> **Four review lenses ran** (terraform-architect, spec-flow-analyzer, observability-coverage-reviewer,
> code-simplicity-reviewer) plus mechanical gates (4.5–4.9 pass) and a verify-the-negative sweep. **The
> plan does NOT survive intact — two P1s would have made it un-buildable. `/work` MUST apply
> §Deepen Pass Corrections (DP-1…DP-11).**
>
> ### The corrections that matter (all fixed in-body + captured in §Deepen Pass Corrections)
> 1. **DP-1 (P1) — the cutover gate would ABORT its own first apply.** All FIVE `workspaces_luks` resources
>    are excluded-not-yet-applied, so the create is a `+create` of all five; the `luks_passphrase_touched==0`
>    counter (copied from git-data's host-*replace* gate) counted those creates. Fixed: count `update`/`delete`/`forget`
>    only; `-target` all five; allow-set = five.
> 2. **DP-2 (P1) — Phase-5 "retire the old block" is fatal for a `for_each` volume** (re-creates the
>    plaintext volume, or destroys web-2's volume, or destroys the web-1 server). Fixed: narrow the
>    `for_each` key-set, not delete the block.
> 3. **DP-4 (P1) — the soak's "fold remediation before exit 0" is structurally impossible** (the sweeper
>    runs `env -i`, no `GH_TOKEN`/`DOPPLER_TOKEN`, `contents:read`+`issues:write` only). Fixed: read-only
>    verify-completion soak + a separate environment-gated destructive dispatch.
> 4. **DP-6 (P1) — three C19-class no-exit states survive** (mid-freeze SSH loss, reboot destroying the
>    trap + stale `CANARY_OK`, the Phase-5 canary_ok provenance). Fixed: host-side EXIT trap + persisted
>    freeze state + a host-local dead-man rollback.
>
> **Verdict: the design (additive volume, freeze, filesystem verify, retain-then-wipe, two-artifact split)
> survives — validated by terraform-architect F5 and simplicity KEEPs. The gate/convergence/soak/state
> INSTRUMENTATION did not, and is corrected below.**


> **This is the cutover — the half that actually moves sole-copy user data onto the encrypted
> volume.** PR 1 (#6593) declared the additive volume; it encrypts nothing until the job in THIS PR
> runs. The parent plan
> (`knowledge-base/project/plans/2026-07-17-fix-6588-luks-encrypt-workspaces-volume-plan.md`) and its
> `## Deepen Pass Corrections — BINDING on /work` (C1–C19) are **binding, not advisory**. This plan
> re-scopes that parent to the #6604 infra deliverable, re-verifies every premise against `origin/main`
> as of 2026-07-17 (#6593 has since merged, moving the ground), and carries C1–C19 forward as tasks and
> ACs. **The coupled legal PR (AC1–AC10 + the present-tense LUKS flip) is OUT OF SCOPE — PR 3, opened
> only after the cutover canary passes (AC30).**

## Overview

`hcloud_volume.workspaces` (web-1's `/mnt/data`) holds every user's checked-out source code as
**plaintext ext4**, while three published legal documents tell data subjects it is LUKS-encrypted. The
data is **sole-copy**: `refs/checkpoints/*` is pushed by no refspec, `session-sync.ts` autocommits only
`knowledge-base/**`, and signup-provisioned workspaces have **no git remote at all** — so ADR-068 §1's
*"GitHub remains the durable rehydration source"* does not hold and there is no second copy anywhere.
This fix also **creates a terminal failure mode that does not exist today**: passphrase or LUKS-header
loss ⇒ unreadable forever. Today's worst case is that someone else reads the user's code; post-LUKS it
is that the user cannot.

**The adopted design (ADR-119, status `adopting`): additive volume + freeze + two-pass rsync +
filesystem-level verify + repoint the mapper — never replace the host** (`cx33` is `available=false` in
all 3 EU DCs, so a `-replace` destroys the sole prod host and strands the fleet unrebuildable). PR 1
(#6593) already shipped the additive volume, its drift guard, ADR-119, the C4 model corrections, and the
`OPERATOR_APPLIED_EXCLUSIONS`. **This PR builds the cutover mechanism on top of that:** pin the mount,
deliver a fail-closed mount gate to the live host via the cutover channel, the dispatch apply + gate,
the freeze/rsync/repoint/canary orchestration, the observability that lets the operator verify without
SSH, and the soak enrollment that automates the post-soak converge/wipe.

> No `spec.md` exists for this branch (one-shot; no brainstorm ran) — **lane defaulted to `cross-domain`
> (TR2 fail-closed)**. The parent effort's four domain leaders (CTO, CLO, COO, CPO) are carried forward
> (see §Domain Review).

---

## Premise Validation (Phase 0.6)

Every premise the issue and the parent plan cite by reference was re-checked against `origin/main` at
`/work`-open (2026-07-17, after #6593 merged as `2c763c423`). Several moved.

| # | Claim (issue / parent plan) | Verified reality on main | Response |
|---|---|---|---|
| Q1 | Issue body: *"`Ref #6588` · **ADR-118** (`status: adopting`)"* | **Mis-cited.** `ADR-118-*.md` on main is *"A shared cert's SANs are the cluster roster"* (#6598). The LUKS ADR is **`ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`, `status: adopting`**. The parent plan's provisional "ADR-119" is what shipped. | **This plan cites ADR-119 everywhere.** Do NOT propagate "ADR-118". |
| Q2 | Parent Files-to-Create: `workspaces-luks.tf`, `workspaces-luks.test.sh`, ADR | **Already shipped by #6593** (`2c763c423`). `workspaces-luks.tf` (10.7 KB), `workspaces-luks.test.sh` (A1–A11, registered `infra-validation.yml:571`), ADR-119, and `model.c4` corrections are ALL on main. | **Remove them from #6604's Files-to-Create.** #6604 does NOT re-create them; it must keep them green (regression ACs). |
| Q3 | Parent: *"`lifecycle { prevent_destroy = true }` on the OLD volume (CPO G7)"* | **NOT shipped, deliberately.** `workspaces-luks.tf` carries no `lifecycle` block; the issue records *"`prevent_destroy` … applies to every `for_each` instance and fails the whole plan … **Deliberately NOT in PR 1.**"* `grep prevent_destroy apps/web-platform/infra/*.tf` → 0 workspaces hits. | **The old plaintext volume is protected by the cutover GATE (`old_volume_touched==0` + `resource_deletes==0`), NOT `prevent_destroy`.** Rewrite AC20 accordingly. |
| Q4 | C19 P1: *"the infra PR CANNOT MERGE — add the LUKS resources to `OPERATOR_APPLIED_EXCLUSIONS`"* | **Already done by #6593.** `terraform-target-parity.test.ts` (the canonical machine-readable set) lists all five (`random_password.workspaces_luks`, `doppler_secret.workspaces_luks_key`, `hcloud_volume.workspaces_luks`, `hcloud_volume_attachment.workspaces_luks`, `doppler_service_token.workspaces_luks`) + the token exclusion, "ride the operator's `workspaces-luks-cutover` dispatch apply." Old `hcloud_volume.workspaces` + attachment already excluded. | **#6604 adds NO new merge-path hcloud resource** (only scripts/workflows/gate). Keep the exclusion parity green (AC). The C19-P1 "cannot merge" hazard is discharged. |
| Q5 | Parent: *"pin the mount — cloud-init.yml:568-569 glob; sweep `git-data-bootstrap.sh`"* | **Still live.** `cloud-init.yml` still `mount /dev/disk/by-id/scsi-0HC_Volume_* /mnt/data \|\| true` + fstab echo with the glob, no `nofail`, no `grep -q`. `git-data-bootstrap.sh` uses the glob at its re-mount (`:46`) and LUKS-discovery loop (`:71`). | **Phase 1 of #6604.** Pin by volume ID; sweep both; edit the C10 guard test (see Q6). |
| Q6 | C10: a currently-passing guard requires the exact `\|\| true` glob string | **Confirmed.** `soleur-host-bootstrap-observability.test.sh` (AC6b) asserts `grep -qE 'mount /dev/disk/by-id/scsi-0HC_Volume_\* /mnt/data \|\| true'` with the message *"do not invert survivable→fatal."* | **Add this file to Files-to-Edit; argue the reversal; re-point the guard at the new volume-ID+`nofail`+`grep -q` invariant** — do NOT silently delete the assertion. |
| Q7 | C2: `--restart unless-stopped` defeats a pre-`docker run` gate on reboot | **Confirmed live** at cloud-init.yml `docker run … --restart unless-stopped … -v /mnt/data/workspaces:/workspaces`. There is **no** fail-closed mount gate before it; `soleur-host-bootstrap.sh` has **no** LUKS block, no `findmnt` gate, no `RequiresMountsFor`, no `/etc/crypttab`, no `chattr`. | **The fail-closed gate must be STRUCTURAL** (systemd `RequiresMountsFor=/mnt/data` + `/etc/crypttab` + `chattr +i`) so it survives the dockerd reboot resurrection, AND delivered to the LIVE host via the cutover channel (ADR-119 §(e)) because the bake has no consumer. |
| Q8 | C14 P0-2: persist the Sentry DSN | **Confirmed.** `/etc/default/webhook-deploy` carries only `DOPPLER_TOKEN`, `DOPPLER_CONFIG_DIR`, `DOPPLER_ENABLE_VERSION_CHECK` — **no `SOLEUR_SENTRY_DSN`.** `soleur-boot-emit` (baked in `soleur-host-bootstrap.sh`) hardcodes **3 tags** (`stage`,`host_id`,`region`) and cannot carry `reason=`. | **Persist the DSN to a boot-written env file** the standing `luks-monitor` unit sources (baked, not Doppler-fetched — else the "Doppler unreachable ⇒ MUST page" mode has its DSN fail by the same cause). A new emit script (mirror `cron-egress-enforce-probe.sh`), not `soleur-boot-emit`. |
| Q9 | C14 P1-3: `luks-monitor` Vector tag | **Confirmed absent.** `vector.toml` `include_matches.SYSLOG_IDENTIFIER` is a 14-tag exact-match allowlist; `luks-monitor` is not in it (comment: *"a tag typo silently matches nothing"*). `vector-pii-scrub.test.sh` pins the exact set. | **Add `luks-monitor` to the allowlist AND update the pinning test fixture** in the same PR. |
| Q10 | C19: soak secret names `SENTRY_API_TOKEN,BETTERSTACK_API_TOKEN` | **Both wrong.** The wired names are `SENTRY_AUTH_TOKEN` (GH secret `SENTRY_IAC_AUTH_TOKEN`) + `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` — **already present** in `scheduled-followthrough-sweeper.yml`. `reconcile-ff-only-sentry-4977.sh` checks HTTP status FIRST (non-200 ⇒ TRANSIENT exit 2, never false-PASS). | **Soak script uses `SENTRY_AUTH_TOKEN` + `BETTERSTACK_QUERY_*` (no new secret wiring needed).** Copy the status-first fail-safe. |
| Q11 | Scope: `workspaces-luks-cutover` dispatch job + `apply_target` choice + `web-1-swap` | **Confirmed shape.** `apply_target` is a `type: choice` (8 options today, `git-data-host-replace` last); `git_data_host_replace` (`:2158`) is the template. `warm_standby` + `web_2_recreate` each declare **job-level `concurrency: group: web-1-swap`** because they mutate web-1; `git_data_host_replace` inherits `terraform-apply-web-platform-host` because it mutates the git-data host. | The cutover mutates **web-1** ⇒ **`web-1-swap` is correct** (matches warm_standby/web_2_recreate). Add the choice option + description. |
| Q12 | C5: `blkdiscard` + verified-read-back wipe precedent | **No code precedent** — `inngest-wiped-volume-verify.sh` uses `rm -rf` + a service-health read-back (gate→destroy→read-back→state-file is the STRUCTURAL shape). The blkdiscard technique is net-new. | Specify the full sequence in `workspaces-cutover.sh`'s wipe path; mirror inngest-wiped-volume-verify's structure. |
| Q13 | C4/C11: C4 model state | **`workspacesVolume` element + `doppler → hetzner` boot-credential edge already shipped** by #6593; description currently says *"PLAINTEXT AT REST as of 2026-07-17 … the gap #6588/ADR-119 closes"*. | **No new C4 element/edge.** The only C4 edit is flipping that description PLAINTEXT→LUKS post-canary (Phase 4/5), sequenced with the ADR status flip. |

**Own-capability claims** (`hr-verify-repo-capability-claim-before-assert`): I asserted the cutover is "a
new apply_target job in apply-web-platform-infra.yml" AND "a git-data-cutover.yml-style orchestration
workflow" — **both precedents exist and are distinct**; the split below is deliberate, not assumed (see
§Infrastructure). I asserted `stock-preflight-gate.sh` "does not fire on a volume create" — **verified**
(`select(.type == "hcloud_server")`; a volume-only plan hits its legitimate-empty out-of-scope branch).

---

## Research Reconciliation — Spec vs. Codebase

| # | Parent-plan / issue claim | Reality on main (post-#6593) | #6604 response |
|---|---|---|---|
| R1 | Files-to-Create: ADR-119, `workspaces-luks.tf`, `workspaces-luks.test.sh` | **Shipped in #6593.** | Removed from #6604 Files-to-Create; regression ACs only. |
| R2 | AC11 (ADR exists), AC12 (C4 edge), AC13 (drift guard), AC17 (target-parity), AC19 (no TF_VAR) | **Satisfied by #6593.** ADR-119 has `## Decision` + `## Alternatives Considered` (blue-green/reencrypt/fscrypt/drain/snapshot); `model.c4` has the Doppler→web-host edge; `workspaces-luks.test.sh` A1–A11 green; exclusion parity green; no `variable "workspaces_luks*"`. | **Assert they stay green (regression) — do NOT re-implement.** AC12's C4 *content flip* (PLAINTEXT→LUKS) is #6604's, sequenced post-canary. |
| R3 | `git-data-cutover.sh` is a reusable asset | **A shape to copy, never invokable** — it calls `soleur-drain.service` + `soleur-web.service`, defined nowhere. | `workspaces-cutover.sh` copies its structure; never sources or invokes it. |
| R4 | `verify_set_identity` reuse (`git rev-list … sha256sum`) | **Does not port** — `/workspaces` holds working trees + `refs/checkpoints/*`; a rev-list identity passes while dropping the sole-copy data. | **Filesystem-level itemized rsync verify (C1)**, not rev-list. |
| R5 | AC20: "old volume carries `prevent_destroy`" | **False — not shipped** (Q3). | Rewrite AC20: old volume protected by the gate's `old_volume_touched==0` + `resource_deletes==0`. |
| R6 | Parent: fail-closed gate in the baked `soleur-host-bootstrap.sh` "in this PR" | **The bake has no consumer** (ADR-119 §(e); cx33 unorderable ⇒ web-1 never re-creates ⇒ `ignore_changes=[user_data]` ⇒ cloud-init never re-runs). The bake ships for future fresh hosts but reaches no live host. | **Deliver the gate to web-1 via the CUTOVER channel** (C19). The bake is authored too, acknowledged as dead-on-web-1. |
| R7 | Escrow proof placement (parent Phase 3) | Ran **before** `prepare_luks_target` (couldn't test the real volume) and proved the CI read path, not the host's token path (C19). | **Re-order: `prepare_luks_target` → escrow proof against the real device via the host's `prd_workspaces_luks` token path.** |
| R8 | Soak has ≥3 false-green paths (C14 P0/P1, C19) | Monitor authored-but-never-delivered; auth-failure⇒zero-events⇒PASS; `earliest=` placeholder ⇒ opens day 0; wrong secret names (Q10). | Full C19 soak rewrite (§Observability, §Phase 5). |
| R9 | Reading the passphrase | `workspaces-luks.tf:112` pins it: `doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks`. **Never** `doppler run`/`download --config prd_workspaces_luks` (branch inherits root ⇒ drags ~116 `prd` secrets into env — the CWE-522 hole this design closes). | The cutover script reads the key with the pinned `secrets get` form; a runtime assert `docker exec … env` contains no `WORKSPACES_LUKS_KEY`. |

---

## Hypotheses

**Gate fired** (Phase 1.4): the cutover orchestrates over **SSH from CI** (the CF-Tunnel bridge), and the
`apply_target` job runs `terraform` against `hcloud_server.web` whose definition carries `remote-exec` +
`connection { type = "ssh" }`. Per `hr-ssh-diagnosis-verify-firewall`, L3→L7 order is mandatory before
any service-layer step. **This is not an outage diagnosis** — each layer is a **pre-flight gate inside
the workflow**; an L3 failure that strands the cutover mid-freeze (container stopped, site down) is the
exact class the ordering prevents.

1. **L3 — host reachability.** `[gate]` The runner egress is not in `var.admin_ips`; it reaches web-1
   via the **CF-Tunnel SSH bridge** (`./.github/actions/cf-tunnel-ssh-bridge`, as `git-data-cutover.yml`
   does — creds off-host, script holds no key). **Verify pre-freeze:** assert SSH reachability + the
   resolved endpoint; abort before any `docker stop` if absent. *Skipped ⇒ freeze engages, delta rsync
   cannot connect, site down with no orchestrator.*
2. **L3 — DNS / routing.** `[gate]` `app.soleur.ai` is a proxied singleton A record to
   `hcloud_server.web["web-1"]`. **Verify:** `dig +short +time=5 +tries=2 app.soleur.ai` resolves to CF
   edge **and** the private `10.0.1.10` answers, **before** the freeze.
3. **L7 — TLS / proxy.** `[opt-out with artifact]` No cert/SNI change; the tunnel connector is untouched.
   *Artifact:* the canary's `curl -sS -o /dev/null -w '%{http_code}' https://app.soleur.ai/api/health` →
   200 post-restart exercises the full HTTPS path.
4. **L7 — application layer.** `[gate]` The freeze's straggler assert (`lsof +D /mnt/data` /
   `fuser -vm /mnt/data`) returning **empty** is the intended signal that the service is not touching the
   mount. *Skipped ⇒ rsync a live tree, silently lose the delta.*

> **Ordering discipline:** L3 gates run pre-freeze (Phase 3/4, zero downtime). Only after both pass does
> the freeze engage. **A cutover that cannot reach the host must fail before it stops the container.**

---

## Architecture Decision (ADR/C4)

**No new ADR.** ADR-119 (`status: adopting`) already governs and already carries the #6604-binding
rulings — §(e) (the fail-closed gate reaches web-1 via the cutover channel, not the bake; structural
`RequiresMountsFor` + `chattr +i`). **#6604 IMPLEMENTS ADR-119; it does not mint or amend a decision.**

### ADR edit (sequenced, not now)
- ADR-119 `status: adopting → accepted` on **soak-pass** (Phase 5, executed by the soak followthrough
  actor). Re-verify the ordinal is still ADR-119 on `origin/main` at ship; if the status-flip lands in
  THIS PR's diff, it stays `adopting` (the flip is a Phase-5 post-canary action, not a merge-time edit).

### C4 views
**All three model files re-read** — `model.c4`, `views.c4`, `spec.c4`. **The `workspacesVolume` element
and the `doppler → hetzner` boot-credential edge already exist** (shipped #6593). Enumerated for
completeness (C4 mandate):
- **External human actors:** none added.
- **External systems / vendors:** Hetzner + Doppler — already modelled (the `doppler → hetzner` edge
  names `WORKSPACES_LUKS_KEY`/`prd_workspaces_luks`). No new vendor, no new sub-processor.
- **Containers / data stores:** `workspacesVolume` — the ONLY C4 edit is flipping its description from
  *"PLAINTEXT AT REST as of 2026-07-17"* to **LUKS-encrypted at rest**, sequenced with Phase 4/5 (after
  the canary proves it). Not now — the description must not lie ahead of the fact.
- **Access relationships:** the Doppler→web-host boot-time-passphrase dependency edge already renders.

**Verdict:** C4 impact is a single description flip, post-canary. No `views.c4` `include` change (both
elements already included ⇒ LikeC4 renders the edge). Run `c4-code-syntax.test.ts` + `c4-render.test.ts`
after the flip.

---

## User-Brand Impact

**If this lands broken, the user experiences:** their workspace is gone or truncated — uncommitted edits,
untracked files, and `refs/checkpoints/*` are **unrecoverable** (sole-copy; no remote). Or — the mode the
fix itself creates (CPO F4) — the volume is intact and encrypted and the passphrase/header is gone: their
code is **unreadable forever**. A botched host mutation is worse: **web-1 cannot be rebuilt** (cx33
stock), so the failure mode is "the product is gone," not "a workspace is gone."

**If this leaks, the user's source code is exposed via:** a Hetzner volume snapshot, a mis-scoped detach,
or physical-media recovery of the retained plaintext volume — until it is `blkdiscard -z`'d and detached
(Phase 5). The compounding harm is the published contradiction: under **Art. 34(3)(a)** encryption
exempts breach-notification to data subjects; plaintext means no exemption, so an Art. 33 filing would
state "plaintext" while the live privacy policy says "LUKS-encrypted."

**Brand-survival threshold:** `single-user incident` ⇒ `requires_cpo_signoff: true` — **carried forward
APPROVE-WITH-CONDITIONS from the parent** (§Domain Review). `user-impact-reviewer` runs at review time.
> **Scope note (P8):** with **0 beta users**, today's "single user" is the operator himself. The
> threshold is met on data-criticality, not population.

---

## Observability

The full 5-field schema below is the #6604 deliverable. The rewrite from the parent's cargo-culted
5-min `luks-monitor` poll stands: the mount state is boot-immutable, so the standing check is a **daily**
escrow+header probe (C3/C15), NOT a 5-min heartbeat; and the transition-time signal lives **in the
pre-`docker run` fail-closed gate** delivered via the cutover channel (§(e)). C14's emit-path defects are
all fixed here: persisted DSN (Q8), discriminating fields (P1-1), `feature:`/`op:` tags + a matching
`sentry_issue_alert` (P1-5), the `luks-monitor` Vector tag (Q9), and a heartbeat so a **dead probe
FAILS** (P1-4).

```yaml
liveness_signal:
  what: "The STRUCTURAL fail-closed mapper gate delivered via the cutover channel — a systemd dependency (RequiresMountsFor=/mnt/data ordered after the /etc/crypttab mapper-open) + chattr +i on the root-disk /mnt/data inode, so 'container running ⇒ /mnt/data == /dev/mapper/workspaces' holds by construction ACROSS the dockerd --restart unless-stopped reboot resurrection (C2). On a failed unlock the container never starts ⇒ HTTP outage, not a silent plaintext write. Plus a DAILY luks-monitor probe (escrow --test-passphrase + header-UUID match) pushing a Better Stack heartbeat."
  cadence: "every boot + every container (re)start (structural gate); once daily (the escrow/header probe)"
  alert_target: "Sentry op:workspaces-luks-drift (feature:workspaces-luks) via a persisted-DSN emit + a NEW sentry_issue_alert rule; the EXISTING betteruptime_monitor.app (a refused container is a hard down); a NEW betteruptime_heartbeat.workspaces_luks (the daily probe — a missed push pages)"
  configured_in: "apps/web-platform/infra/workspaces-cutover.sh (delivers the gate + crypttab + chattr); apps/web-platform/infra/luks-monitor.{sh,service,timer} (daily probe); apps/web-platform/infra/vector.toml (luks-monitor tag); apps/web-platform/infra/sentry/issue-alerts.tf (+ configure-sentry-alerts.sh mirror); apps/web-platform/infra/uptime-alerts.tf (heartbeat); .github/workflows/workspaces-luks-verify.yml (read-only re-assert)"
error_reporting:
  destination: "Sentry — op:workspaces-luks-drift, feature:workspaces-luks"
  fail_loud: true   # NEVER an unencrypted fallback (NFR-026; mirrors cloud-init-git-data.yml empty-key fail-loud)
failure_modes:
  - mode: "Volume plaintext ext4 (LUKS never applied / a future volume born plaintext)"
    detection: "blkid -s TYPE != crypto_LUKS — emitted FROM the host, in-surface; device selected by volume ID"
    alert_route: "Sentry P1 + Better Stack heartbeat miss"
  - mode: "/mnt/data mounted from the raw device, bypassing the mapper (#5274 data-stranding)"
    detection: "findmnt -no SOURCE /mnt/data != /dev/mapper/workspaces; cryptsetup status workspaces missing the mapper→device link"
    alert_route: "Sentry P1 — the silent-plaintext-writes mode"
  - mode: "/mnt/data not mounted at all ⇒ container writes workspaces to the ROOT DISK (the live R5 bug)"
    detection: "mountpoint -q /mnt/data fails AND the chattr +i root-disk inode makes Docker's implicit mkdir EPERM ⇒ container refuses to start"
    alert_route: "Sentry P1 + disk-monitor's existing root-disk fill alarm as a second signal"
  - mode: "Doppler unreachable at boot ⇒ passphrase absent ⇒ mapper never opens"
    detection: "distinct doppler_reachable=false field on the boot emit; nofail keeps /mnt/data unmounted (degraded, pageable — not a hang) and the structural gate refuses the container"
    alert_route: "Sentry P1 — MUST page; DSN is PERSISTED (baked), so it survives the Doppler outage (C14 P0-2)"
  - mode: "Passphrase/header lost or unescrowed ⇒ volume unreadable forever (CPO F4 — the mode the fix creates)"
    detection: "escrow proof (luksOpen --test-passphrase via the host token path, AFTER prepare_luks_target) is a BLOCKING pre-cutover gate; luksHeaderBackup UUID match; the daily probe re-tests both"
    alert_route: "Sentry P1 + cutover aborts before the freeze"
  - mode: "Cutover aborts mid-freeze (container stopped, site down)"
    detection: "betteruptime_monitor.app on app.soleur.ai + the workflow's non-zero exit + the EXIT-trap auto-rollback (C19)"
    alert_route: "Better Stack alert + workflow failure annotation"
logs:
  where: "journald (SYSLOG_IDENTIFIER=luks-monitor, ADDED to vector.toml include_matches) -> Vector -> Better Stack Logs; host_name=soleur-web-platform"
  retention: "per existing Better Stack plan; no change"
discoverability_test:
  command: "gh workflow run workspaces-luks-verify.yml && gh run watch   # read-only re-assert, NO ssh; the runbook artifact"
  expected_output: "workflow conclusion=success (blkid=crypto_LUKS, findmnt=/dev/mapper/workspaces, cryptsetup status link present, mountpoint ok); heartbeat status up"
```

**Discriminating fields (§2.9.2 — blind-surface).** Every `luks-monitor` / cutover event carries
**`{device_type, mount_source, mapper_present, luks_open_result, header_uuid_match, cryptsetup_unit_result,
doppler_reachable, mountpoint_ok, host, reason}`** so the competing failure modes are discriminated **in
one event** (C14 P1-1: the parent's 5 fields collapsed FM3/FM4/FM5 to an identical tuple). The emit is a
new script mirroring `cron-egress-enforce-probe.sh` (which reads the DSN and carries a `probe_result`
discriminator) — NOT `soleur-boot-emit` (hardcoded 3 tags, cannot carry `reason=`).

> `hr-no-ssh-fallback-in-runbooks` does not bar the SSH-orchestrated cutover (the `git-data-cutover.yml`
> precedent is sanctioned). It bars the **runbook** from saying "log in and check." Hence the standing
> probe + `workspaces-luks-verify.yml`: verification is a workflow + an API read, never a login.

### Soak Follow-Through Enrollment (§2.9.1)

Phase 5 gates on a soak before the plaintext volume is wiped and ADR-119 flips `adopting → accepted` — a
time-gated close criterion ⇒ enrollment is **mandatory**. The parent's C19 defects are all corrected:

- **Script:** `scripts/followthroughs/workspaces-luks-soak-6604.sh` — exit 0 **iff**, over the full soak
  window: (a) **zero** `op:workspaces-luks-drift` Sentry events (query gated on `SENTRY_AUTH_TOKEN`,
  status-checked FIRST so an auth failure is `TRANSIENT exit 2`, never a false PASS — copy
  `reconcile-ff-only-sentry-4977.sh`), **AND** (b) the daily `luks-monitor` heartbeat/OK line is
  **present** in Better Stack Telemetry (`BETTERSTACK_QUERY_*`) — a **positive control** so a probe that
  never ran **FAILS the gate** (C19: the parent soak could never go RED). `start=` is pinned **strictly
  after** the Phase-4 canary timestamp (no `earliest=` placeholder — the literal-placeholder→epoch-0 bug
  opened the gate on day 0).
- **AC30 actor (DP-4, F1/F2, P1 — the first draft was structurally impossible).** The sweeper runs the
  script under `env -i` with **only** the directive's declared secrets (no `GH_TOKEN`, no `DOPPLER_TOKEN`)
  and grants only `contents:read` + `issues:write` (`scheduled-followthrough-sweeper.yml:43-46`,
  `sweep-followthroughs.sh:186-208`). So the soak script **cannot** `gh workflow run` the wipe,
  `doppler secrets get` creds, `state rm`, or open PR 3 — the cited `web2-tunnel-depool-6425.sh` runs in a
  **full-env post-merge** context, not under the sweeper (a category error). And authorizing an
  irreversible `blkdiscard -z` of the sole rollback copy from an unattended cron contradicts the plan's own
  `environment:`-gated + `canary_ok && confirm_wipe` control model. **Corrected — the two-phase
  verify-completion pattern (`inngest-rls-drop-6488.sh`):**
  1. **Read-only soak (sweeper-run):** PASSes when zero drift + heartbeat-present + **elapsed ≥7d** hold
     AND it OBSERVES that the destructive work already happened (retained plaintext volume detached+gone
     via a read-only Hetzner API probe, PR 3 exists, ADR-119 `accepted`). It comments and closes **only on
     observed completion**. Before that, it comments *"SOAK PASSED — wipe authorized"* and leaves the
     tracker **open**.
  2. **Destructive dispatch (human/environment-gated):** the wipe + converge + ADR-flip + open-PR-3 ride a
     **separate `environment: workspaces-luks-cutover` `workflow_dispatch`** with its own `actions`/
     `pull-requests` perms + required reviewer, authorized by a human who saw the soak pass. This is the
     only actor with the creds + the sign-off to do the irreversible step.
  Never let soak-pass auto-close the tracker before the wipe + PR 3 are *observed* done (SF-F9).
- **Retention:** **7 days** carried from CPO C7 (blocking; overrides COO's 72h). *(C15 argued a
  `reboot-once + re-canary` in Phase 4 tests the boot path in 90s where 7 uptime-days test it zero times —
  KEEP that reboot test in Phase 4 as the real boot-path proof, and keep the 7d retention as the rollback
  window. They are complementary, not alternatives.)*
- **Wiring:** `SENTRY_AUTH_TOKEN` + `BETTERSTACK_QUERY_*` are **already** in
  `scheduled-followthrough-sweeper.yml` (Q10) — no new secret. Add the tracker directive
  `<!-- soleur:followthrough script=scripts/followthroughs/workspaces-luks-soak-6604.sh earliest=<canary+7d> secrets=SENTRY_AUTH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` + the `follow-through` label.

Enforced fail-closed by `/ship` Phase 5.5 + `ship-soak-followthrough-gate.sh`.

---

## Infrastructure (IaC)

### Terraform changes

| File | Change |
|---|---|
| `.github/workflows/apply-web-platform-infra.yml` | **New `apply_target=workspaces-luks-cutover` job** on the `git_data_host_replace` template shape (ephemeral SSH keygen for `var.ssh_key_path`'s plan-time `file()`; `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan`; sources the new gate lib; **no `environment:`, no `[ack-destroy]`**). Add the value to the `apply_target` `options:` + the `description:`. **Job-level `concurrency: group: web-1-swap`** (matches warm_standby/web_2_recreate — this job mutates web-1). The plan is a **pure `+create`** of `hcloud_volume.workspaces_luks` + attachment (already excluded from the per-PR path). |
| `.github/workflows/workspaces-luks-cutover.yml` **(new)** | The freeze orchestration, mirroring `git-data-cutover.yml`: `workflow_dispatch`-only; typed `confirm` input; `dry_run`(default true)/`rollback`/`confirm_wipe` booleans; CF-Tunnel SSH bridge (creds off-host); job-level `concurrency: group: web-1-swap`; runs `workspaces-cutover.sh`. **Sign-off mechanism (C19):** a GitHub **`environment: workspaces-luks-cutover`** with a required reviewer gates the freeze/wipe steps — with an explicit #4220 counter-argument in a comment (the #4220 env removal was for MERGE-path 13h waits under CODEOWNERS; a `workflow_dispatch` cutover has NO merge/CODEOWNERS gate, so the environment is the ONLY human control on a sole-copy-data freeze). The typed `confirm` token remains a typo-guard, not the authorization. |
| `.github/workflows/workspaces-luks-verify.yml` **(new)** | Read-only `workflow_dispatch` re-assert (the no-SSH runbook artifact + `discoverability_test`): over the SSH bridge, `blkid`/`findmnt`/`cryptsetup status`/`mountpoint` + an app-level workspace read + `/api/health` 200; emits the discriminating fields. **No mutation.** |
| `apps/web-platform/infra/cloud-init.yml` | **Phase 1:** replace the `scsi-0HC_Volume_*` glob (mount + fstab) with an explicit **volume-ID** device (from the TF output) + `nofail` + a `grep -q` fstab-dedupe guard; a boot emit on mount failure. **Persist the Sentry DSN** to a boot-written env file the `luks-monitor` unit sources (Q8/C14 P0-2). |
| `apps/web-platform/infra/soleur-host-bootstrap.sh` | The baked LUKS block + structural mount dependency (for the future **fresh-host** path — acknowledged dead on web-1, ADR-119 §(e)). |
| `apps/web-platform/infra/git-data-bootstrap.sh` | **Sweep (Q5, `hr-write-boundary-sentinel-sweep-all-write-sites`):** pin its `scsi-0HC_Volume_*` sites (`:46`,`:71`) by volume ID, or document why the git-data host's 2-volume set is unambiguous (it runs on a DIFFERENT host than web-1; the ambiguity bites web-1). |
| `apps/web-platform/infra/vector.toml` (+ `apps/web-platform/test/infra/vector-pii-scrub.test.sh` fixture) | Add `luks-monitor` to the `include_matches.SYSLOG_IDENTIFIER` allowlist + update the pinning test (Q9). *(Path verified: the fixture is under `test/infra/`, not `infra/`.)* |
| `apps/web-platform/infra/sentry/issue-alerts.tf` (+ `configure-sentry-alerts.sh` mirror) | New `sentry_issue_alert` filtering `feature=workspaces-luks` / `op IS_IN workspaces-luks-drift`, `notify_email IssueOwners/ActiveMembers` (C14 P1-5). |
| `apps/web-platform/infra/uptime-alerts.tf` | New `betteruptime_heartbeat.workspaces_luks` (the daily-probe positive control). |
| `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` | **Edit the AC6b assertion (Q6/C10):** it currently requires the exact `\|\| true` glob string. Re-point it at the new volume-ID + `nofail` + `grep -q` invariant; argue the reversal in-file. |
| `apps/web-platform/infra/server.tf` | **Phase 5 only, and NOT a rename (C12):** keep `hcloud_volume.workspaces_luks` as the permanent address; retire the old `hcloud_volume.workspaces` block after API-detach → API-delete → `state rm`. No `moved`, no rename, no divergence window. |

**Provider pins:** `hcloud ~> 1.49` (lock `1.63.0`), `doppler`, `random`, `jianyuan/sentry`,
`betteruptime` — all existing. **No new providers, no new `TF_VAR_*`** (the passphrase is
`random_password`; #5468 sequencing trap does not apply).

> **Doppler-config precondition** (`prd_workspaces_luks`) was an operator precondition for #6593's apply
> and, per `workspaces-luks.tf:95`, is already required to exist. **Re-verify it exists at /work**
> (`doppler configs --project soleur | grep prd_workspaces_luks`); `automation-status: UNVERIFIED — /work
> MUST attempt in-band creation (doppler_config resource) before any handoff` if absent.

### Apply path

**(b) cloud-init + idempotent cutover scripts**, via the two dispatch workflows above — never the
merge-triggered allow-list. The volume create/attach is a **pure `+create`** ⇒ it does not trip the
destroy-guard, but the per-PR `apply` path's **`host_creates` TRIPWIRE fires on any `hcloud_volume`
create** (unbypassable, `[skip-web-platform-apply]`-only) — which is precisely why the create must ride
the dedicated `apply_target=workspaces-luks-cutover` dispatch, not a PR merge. `stock-preflight-gate.sh`
does not fire (servers only). **Blast radius:** Phases 1–3 = zero downtime; Phase 4 freeze = ≤20 min
budget (~10 target), ≤2h hard abort.

### The cutover gate (CAP-COUPLING)

`tests/scripts/lib/workspaces-luks-cutover-gate.sh` + `tests/scripts/test-workspaces-luks-cutover-gate.sh`
— **sourced-not-copied**, synthesized fixtures, mirroring the `git_data_host_replace_gate` pair. It reads
the structured `terraform show -json` and PASSES **iff** (exact-equality `IN(.address; allow[])`, never
`contains`; every "touched"/delete/out-of-scope counter uses the git-data **4-verb** positive-action
filter `create`/`update`/`delete`/`forget` — a `removed{}`/`state rm` manifests as `forget`, not `delete`):

```
# ⚠️ DP-1 CORRECTION (terraform-architect F1): this is a FIRST PROVISION, not a host -replace.
# All FIVE workspaces_luks resources are OPERATOR_APPLIED_EXCLUSIONS not yet in state, so the
# create job's plan is a +create of ALL FIVE. The gate MUST PERMIT those creates.
allow-set = { random_password.workspaces_luks, doppler_secret.workspaces_luks_key,
              doppler_service_token.workspaces_luks, hcloud_volume.workspaces_luks,
              hcloud_volume_attachment.workspaces_luks }   # all five — the create job -targets exactly these

luks_volume_created     >= 1  # hcloud_volume.workspaces_luks "create" — anti-no-op
luks_attachment_created >= 1  # hcloud_volume_attachment.workspaces_luks "create"
luks_secret_created     >= 1  # doppler_secret.workspaces_luks_key "create" — REQUIRED: escrow reads via prd_workspaces_luks
old_volume_touched      == 0  # 4-verb action on hcloud_volume.workspaces["web-1"] — AC20's STOP (replaces prevent_destroy)
old_attachment_touched  == 0  # 4-verb action on hcloud_volume_attachment.workspaces["web-1"] — detaching live /mnt/data is catastrophic (F3)
web1_server_touched     == 0  # 4-verb action on hcloud_server.web["web-1"] — highest-value: a destroyed web-1 is unrecoverable
luks_volume_destroyed   == 0  # delete OR forget of hcloud_volume.workspaces_luks
luks_passphrase_touched == 0  # update/delete/forget (NEVER create) on random_password.workspaces_luks OR doppler_secret.workspaces_luks_key — the C19 re-key catastrophe; a FIRST create is legal, a later re-mint is F4
resource_deletes        == 0  # delete OR forget of anything
out_of_scope            == 0  # any 4-verb action on an address not in allow-set
```

> **DP-1 (F1, P1) — the gate as first-drafted would ABORT its own first apply.** `luks_passphrase_touched`
> was copied verbatim from `git-data-host-replace-gate.sh`, which guards a host **-replace** where the
> passphrase already exists in state (a no-op is expected). The workspaces cutover is a **first provision**:
> `random_password` + `doppler_secret` + `doppler_service_token` are all excluded-not-yet-applied
> (`terraform-target-parity.test.ts:568-572`), so the create plan is a `+create` of **all five**. Counting
> those creates as a "touch" aborts the provision the gate exists to authorize. Fix (above): the create job
> `-target`s **exactly those five** (precedent: `warm-standby` `-target`s exactly its 6 excluded resources,
> `apply-web-platform-infra.yml:795-796` — never untargeted, which pulls unrelated drift); `luks_passphrase_touched`
> counts `update`/`delete`/`forget` only; the escrow proof (AC22) can only run **after** this create (the
> `doppler_secret` must exist for the `prd_workspaces_luks` key-read). The §Infra table row "pure +create of
> the volume + attachment" is superseded: it is a `+create` of all five.

Fixture mutation cases (each differs from PASS by ONE mutation; each MUST flip RED): old-volume touch
(any verb); old-**attachment** touch; web-1 server replace; luks-volume delete **or forget**; passphrase
**re-mint** (`random_password` update — NOT a first create); doppler_secret **update**; any out-of-scope
positive action; a no-op plan (anti-vacuity → RED on `luks_volume_created==0`). Use bracketed indexed
addresses (`hcloud_volume.workspaces["web-1"]`), exact-equality `IN`.

### Distinctness / drift safeguards

- `lifecycle.ignore_changes = [user_data, ssh_keys, image, placement_group_id]` on `hcloud_server.web`
  **stays** (`terraform-target-parity.test.ts:1188` asserts `user_data` present — dropping it reds AC17).
- **Convergence (Phase 5) does NOT rename (C12), and is NOT a block deletion (DP-2, F2, P1).** Keep
  `hcloud_volume.workspaces_luks` as the permanent address. But `hcloud_volume.workspaces` is
  **`for_each = var.web_hosts`** (`server.tf:1241`), with live `["web-1"]` and `["web-2"]` instances, and
  its attachment is likewise `for_each` (`:1253`). **"Remove the old block" is fatal three ways:** (a)
  `state rm 'hcloud_volume.workspaces["web-1"]'` while the config still `for_each`es web-1 ⇒ next plan
  **re-creates the plaintext volume**; (b) deleting the whole `resource` block while web-2 is still in
  `var.web_hosts` ⇒ **destroys web-2's live volume**; (c) narrowing `var.web_hosts` to drop web-1 ⇒
  **destroys `hcloud_server.web["web-1"]`** (`server.tf:107` is also `for_each = var.web_hosts`) — the
  cx33-unrebuildable catastrophe. The git-data precedent ports only because its volume is a **singleton**.
  **Corrected convergence:** in ONE PR, narrow the `for_each` key-set to exclude web-1 on **both** the
  volume and its attachment (`for_each = { for k,v in var.web_hosts : k=>v if k != "web-1" }`) **together
  with** `removed {}`/`state rm` of the two `["web-1"]` instances, after API-detach → API-delete (delete
  BEFORE `state rm`, else an orphan billed volume). Then plan is clean (web-1 absent from state AND
  for_each; web-2 untouched). **Or** sequence the whole convergence after #6538 (web-2 teardown), which
  removes web-2 from the map and lets the block retire wholesale. No `moved`, no rename — but a real
  `for_each` config edit, not "no config change."
- **Secrets land in `terraform.tfstate`** — R2 backend encrypted; `use_lockfile = false`. **The R2
  serializer is the INHERITED workflow-level `terraform-apply-web-platform-host` group** (which gates the
  whole workflow RUN regardless of any job-level group) — this is what protects the lockless backend
  against every apply path (inngest-host, registry, plain push). The cutover job **additionally** declares
  job-level `concurrency: group: web-1-swap`, which **COEXISTS** (does not replace) as the cross-workflow
  web-1 mutex against the separate release-deploy pipeline (DP-3, F4 — the first draft's "but the cutover
  job is on web-1-swap" wrongly implied a substitution). Both apply; the job stays **in
  `apply-web-platform-infra.yml`** — splitting the create into a second workflow reintroduces the
  unserialized second-writer hazard (`apply-web-platform-infra.yml:681`). Precedent-exact: `warm_standby`
  (`:688-699`) + `web_2_recreate` (`:925-935`) both do exactly this.

---

## Downtime & Cutover

**Justification (#5887 norm; CPO C8).** Zero-downtime is rejected on four grounds: (1) zero external
users — availability nobody consumes; (2) downtime buys data integrity — a quiesced volume is copied at
rest, no live `refs/checkpoints/*` mutation mid-rsync (a zero-downtime design has strictly more ways to
lose sole-copy data); (3) zero-downtime is impossible anyway — it needs a host create and cx33 is
unorderable; (4) #5887's precedent was won for a reboot/wedge (availability, no data-integrity dimension).

**Window:** ≤20 min budget, ~10 target, **≤2h hard abort** (CPO ceiling). **Authorization** to engage the
freeze is the single human decision (the `environment:` required-reviewer gate, §Infrastructure).

**Rollback (C13 — corrected):** run the **host-level canary** (`blkid`/`findmnt`/`cryptsetup status`/
`mountpoint` — no container needed) **BEFORE `docker start`**; resume `webhook.service` only after
canary-pass. Inside the freeze, rollback is unmount-mapper → remount-plaintext → restart (seconds,
byte-identical). Post-canary the retained LUKS volume physically **retains** every write, so rollback is
**reconcilable, not a one-way door** — remount the retained plaintext read-only at a distinct path (a
byte-exact T0) and the door becomes "restore T0 + replay from LUKS." The runbook states this precisely
(never "one-way door" — that makes an operator refuse a rollback they should take). **EXIT trap
(C19):** `trap cleanup EXIT` + `FREEZE_HELD`/`FLIP_DONE`/`CANARY_OK` state so any non-zero exit
auto-rolls-back — without it the ≤2h abort IS the stranded state, not the escape.

---

## Implementation Phases

> **Phase order is load-bearing.** Mount-pin precedes the cutover because the glob is what makes a second
> volume ambiguous. Escrow proof precedes the freeze because F4 is terminal. The gate + observability
> precede the apply because a create you cannot verify is a create you cannot trust.

### Phase 0 — Read-only preconditions (no code, NOT blocked)
- [ ] **Highest-value check:** verify the LIVE host's actual `/etc/fstab` + mount state over the SSH
      bridge (read-only). **If web-1 rebooted since first boot and `/mnt/data` is unmounted, the data is
      not where this plan assumes and the sequencing is invalid** — STOP and re-scope (this is the R5
      "emergency mode on a headless cx33-unrebuildable host" risk; it has a real response, not a dead end:
      remediate the mount first, then proceed).
- [ ] `du --apparent-size -sh /mnt/data/workspaces` (read-only) — confirm near-empty at 0 users ⇒
      single-pass rsync into the empty target needs no `--delete` on the critical path (C15).
- [ ] Confirm `prd_workspaces_luks` exists (Q of §Infra); confirm the exclusion parity + drift guard are
      still green on main (regression baseline).

### Phase 1 — Pin the mount, fail-closed (ships independently; a live latent-bug fix)
- [ ] `cloud-init.yml`: glob → explicit volume-ID device + `nofail` + `grep -q` fstab guard; boot emit on
      mount failure. Persist the Sentry DSN to a boot env file (Q8).
- [ ] Sweep `git-data-bootstrap.sh` (`:46`,`:71`) per Q5.
- [ ] **Edit `soleur-host-bootstrap-observability.test.sh` AC6b** (Q6/C10) — re-point at the new
      invariant; argue the reversal in-file.
- [ ] Re-run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` (budget 21,900) + the
      observability test.

### Phase 2 — The cutover gate + observability plumbing (mergeable, inert until dispatched)
- [ ] `tests/scripts/lib/workspaces-luks-cutover-gate.sh` + `test-...-gate.sh` (CAP-COUPLING, the counters
      above, no `[ack-destroy]`). Register the test in `tests/scripts/test-all.sh`'s discovery.
- [ ] Vector `luks-monitor` tag + fixture (Q9); `sentry_issue_alert` + `configure-sentry-alerts.sh`
      mirror (C14 P1-5); `betteruptime_heartbeat.workspaces_luks` (C14 P1-4); the emit script mirroring
      `cron-egress-enforce-probe.sh` with the discriminating fields + persisted DSN.
- [ ] `luks-monitor.{sh,service,timer}` — **daily** escrow(`--test-passphrase`)+header-UUID probe pushing
      the heartbeat (NOT a 5-min poll of a boot-immutable state).
- [ ] The baked LUKS block + structural `RequiresMountsFor`/`crypttab`/`chattr +i` into
      `soleur-host-bootstrap.sh` (fresh-host path; acknowledged dead on web-1).
- [ ] `workspaces-luks-verify.yml` (read-only re-assert).

### Phase 3 — Additive volume dispatch apply + escrow + rollback rehearsal + bulk rsync (ZERO downtime)
- [ ] New `apply_target=workspaces-luks-cutover` job (create+attach, gate-lib-guarded, `web-1-swap`,
      ephemeral keygen). Add the choice option + description.
- [ ] **L3 gates (Hypotheses 1-2)** — abort before any freeze if either fails.
- [ ] `prepare_luks_target`: select the FRESH device **by volume ID** (never glob); `blkid` raw-signature
      discriminator (raw ⇒ luksFormat; crypto_LUKS ⇒ no-op; anything else ⇒ FATAL). Open mapper at a
      staging path.
- [ ] **Escrow proof (BLOCKING, C3/C19 — AFTER `prepare_luks_target`):** `printf '%s' "$KEY" | cryptsetup
      luksOpen --test-passphrase --key-file - "$REAL_DEV"` against the **real** device, key read via the
      host's `prd_workspaces_luks` token path (the `secrets get` form, R9). Wrong passphrase MUST fail
      (Test Scenario). Then **`luksHeaderBackup` off-host to a bucket distinct from the tfstate bucket
      (C4)**; assert the backup's `luksDump` UUID matches.
- [ ] **G2 manifest** — enumerate workspaces; `git rev-parse` every ref incl. `refs/checkpoints/*`;
      `git status --porcelain` dirty inventory → counts + SHAs. Derive a **`count > 0` floor** (C19).
- [ ] **Rollback rehearsal (C15 caveat):** prove the retained plaintext volume remounts read-only at a
      distinct path — do NOT restart the container (that contradicts zero-downtime); the rehearsal is the
      read-only remount, not "and serves."
- [ ] Bulk `rsync -aHAX` (no `--delete`) into the empty LUKS target against the LIVE tree. No user impact.

### Phase 4 — The freeze (≤20 min budget, ≤2h hard abort, environment-gated)
- [ ] Halt `webhook.service` (so a CI deploy cannot restart the container mid-rsync).
- [ ] `docker stop -t 120 soleur-web-platform` (C8 — drain lets in-flight `write()` finish; a 10s SIGKILL
      truncates a file that is then faithfully rsynced and certified). Post-stop **interrupted-write
      asserts:** no `.git/index.lock`, no `objects/pack/tmp_pack_*`, no `gc.pid` ⇒ abort rather than copy
      wreckage. `lsof +D /mnt/data` empty (G4).
- [ ] **G3 manifest AFTER the freeze on SRC**, compared to DST — same instant, opposite volumes (C9; the
      parent compared across the dogfooding window ⇒ false-RED). `refs/checkpoints/*` asserted as its own
      named check (highest-probability silent loss).
- [ ] Pass-2 delta `rsync -aHAX --delete --checksum` (C1: pass-2 carries `--checksum` — it is the only
      backstop). **Drop caches** (`sync && echo 3 > /proc/sys/vm/drop_caches`) before the verify (else you
      verify rsync's page cache, not that bytes round-tripped through dm-crypt).
- [ ] **Itemized verify (C1 — the false-green fix):**
      `rsync -aHAXi --numeric-ids --checksum --delete --dry-run --out-format='%i %n' SRC/ DST/ | wc -l`
      MUST be **0** (hardcode `--dry-run`; one typo from wiping live data). Byte assert with
      `du --apparent-size -sb` (never `df`/`du -sb` — LUKS steals a header, geometry differs). **`git fsck
      --full` per DST workspace.** `df` AND `df -i` capacity preflight (inode exhaustion with free bytes is
      the realistic ENOSPC inside the freeze). NO post-verify `chown` re-assert (any mutation after the
      verify voids it; `rsync -a --numeric-ids` preserves uid/gid).
- [ ] `repoint_luks_mount`: mapper → `/mnt/data` (backup fstab first; `findmnt` assert). The `#5274`
      data-stranding trap is sharp here — `/mnt/data/workspaces` is hardcoded into the bind mount.
- [ ] **Host-level canary BEFORE `docker start` (C13):** `blkid TYPE=crypto_LUKS` **AND** `findmnt -no
      SOURCE /mnt/data == /dev/mapper/workspaces` **AND `cryptsetup status workspaces`** (the mapper→device
      link — the missing chain link, C19 P1) **AND `mountpoint -q`**. Emit the discriminating fields.
- [ ] `docker start`; resume `webhook.service`; app-level canary (`/api/health` 200 + a workspace read).
- [ ] **Reboot-once + re-canary (C15)** — the realistic failure is the boot path; a deliberate reboot
      tests the structural gate + `--restart` resurrection in 90s, inside the window, plaintext volume
      still attached.
- [ ] **Any failed assert ⇒ EXIT-trap rollback** to the plaintext mount.

### Phase 5 — Soak → converge → wipe → open PR 3 (executed by the soak followthrough actor)
- [ ] Plaintext volume stays **attached-unmounted, un-wiped** for **7 days** (protected by the gate, not
      `prevent_destroy`).
- [ ] Soak-pass ⇒ the soak script (§Observability) fires the remediation: **wipe** (`lsblk -D` discard
      capability → `blkdiscard -z` → **verified read-back at random offsets + offset 0** → Hetzner API
      delete; **DETACH** the retained volume — unmounted is hygiene, `dd | strings` still recovers; C5) →
      **converge** (API-detach → API-delete → `state rm` + **`for_each` key-set narrowing to exclude
      web-1 on both the old volume AND its attachment** — DP-2, NOT a block delete; or sequence after
      #6538) → **ADR-119 `accepted`** → **open PR 3** (the legal flip, AC1–AC10 + present-tense LUKS + SHA
      re-pin). All of this rides the **separate `environment:`-gated dispatch** (DP-4), never the sweeper.
- [ ] `canary_ok` for the double-gated wipe is sourced from the **persisted Phase-4 canary artifact** (the
      wipe is a separate dispatch 7 days later, not the same process — C19 P1).

---

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| 1 | Live `/etc/fstab` + mount state unverified — if web-1 rebooted, data is not where assumed. | Phase 0 gate (read-only, highest-value); has a real STOP+remediate response. |
| 2 | F4 — passphrase/header loss ⇒ unreadable forever (a mode the fix creates). | Escrow proof (blocking, AFTER prepare_luks_target, host-token path) + `luksHeaderBackup` to a distinct bucket + daily probe. Rotation is `luksChangeKey`, never `-replace`; gate asserts `luks_passphrase_touched==0`. |
| 3 | Rollback authority expires at canary-pass. | Reconcilable (retained LUKS retains writes) + read-only T0 remount + 7d retention + EXIT-trap. Stated precisely in the runbook. Residual risk accepted. |
| 4 | web-1 cannot be rebuilt (cx33). Mid-cutover host death = product gone. | Destroy nothing; no server create/replace; gate `web1_server_touched==0`; plaintext retained. |
| 5 | Cutover edits an already-malformed fstab on a host with no LB/peer. | Phase 1 fixes fstab first, standalone; backup before rewrite; `findmnt` assert; `nofail` ⇒ degraded boot not a hang. |
| 6 | Doppler unreachable at boot ⇒ mapper never opens. | `nofail` + **persisted-DSN** paging emit `doppler_reachable=false` + structural fail-closed gate. |
| 7 | Retained plaintext volume is the exposure for 7 days. | Attached-**unmounted**, then Phase-5 `blkdiscard -z` + verified read-back + **detach** + API-delete. Not a snapshot (no indefinite copy). |
| 8 | Frozen-and-unreachable / soak-red / SSH-drops-mid-freeze. | EXIT-trap auto-rollback; SSH reachability re-asserted as a lease-like pre-freeze gate; every C19 no-exit state gets an explicit exit. |
| 9 | `host_creates` TRIPWIRE would halt a PR that creates the volume. | The create rides the dedicated `apply_target` dispatch, never a merge (design, not accident). |
| 10 | The apply job on `web-1-swap` is not on the R2 serializer group. | `web-1-swap` serializes ALL web-1-mutating pipelines ⇒ no overlapping web-1 apply. Flagged for plan-review. |

---

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Operations (COO), Product (CPO) — **carried forward
from the parent effort** (`2026-07-17-fix-6588-...-plan.md` §Domain Review). No re-spawn: #6604 implements
the already-reviewed ADR-119; the approach is unchanged.

### Product/UX Gate
**Tier:** none. No path in Files-to-Create/Edit matches the UI-surface term list (`components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`); the mechanical override does not fire. User-facing impact is data
integrity + published legal text, not an interface. **CPO threshold sign-off:** APPROVE-WITH-CONDITIONS
(carried forward — all ten conditions are folded as plan structure). `ux-design-lead` is N/A (no UI),
not skipped. **Pencil available:** N/A.

---

## GDPR / Compliance Gate (Phase 2.7)

**Invoked** — triggers (a) regulated-data surface (encryption of personal data at rest) and (b)
brand-survival `single-user incident` both fire. The CLO advisory from the parent is the compliance
output. **Its Critical findings (Art. 30 PA gap, `compliance-posture.md:78` CAX11, the mirror hole)
land in PR 3 (the legal PR), which is OUT OF SCOPE here** — #6604 carries **zero doc changes**. The
Art. 25(1) systemic root-cause (no gate reconciles Art. 32 claims against the Art. 30 register) remains a
filed deferral. **Advisory only — all legal output is draft material requiring professional review.**

---

## Open Code-Review Overlap

Checked via `gh issue list --label code-review --state open` + per-path `jq --arg` containment across
`apply-web-platform-infra.yml`, `cloud-init.yml`, `soleur-host-bootstrap.sh`, `vector.toml`,
`server.tf`, `workspaces-luks.tf`. **Re-run at /work** (the label set moves). Record `None` if clean;
for any match, choose fold-in / acknowledge / defer explicitly.

---

## Files to Create

- `.github/workflows/workspaces-luks-cutover.yml` *(the freeze orchestration; environment-gated; SSH bridge)*
- `.github/workflows/workspaces-luks-verify.yml` *(read-only no-SSH re-assert — the runbook artifact)*
- `apps/web-platform/infra/workspaces-cutover.sh` *(copy git-data-cutover.sh's SHAPE; never invoke it)*
- `apps/web-platform/infra/luks-monitor.{sh,service,timer}` *(daily escrow+header probe → heartbeat)*
- `apps/web-platform/infra/workspaces-luks-emit.sh` *(the discriminating-field emit; mirror cron-egress-enforce-probe.sh; persisted DSN)*
- `tests/scripts/lib/workspaces-luks-cutover-gate.sh` + `tests/scripts/test-workspaces-luks-cutover-gate.sh` *(CAP-COUPLING gate + synthesized-fixture test)*
- `scripts/followthroughs/workspaces-luks-soak-6604.sh` *(soak; positive-control heartbeat; folds the converge/wipe/PR-3 remediation)*
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` *(runbook — verification is workflow + API read, never a login)*

> **NOT created (already on main via #6593 — parent Files-to-Create is stale):** `workspaces-luks.tf`,
> `workspaces-luks.test.sh`, `ADR-119-*.md`. **NO** `plugins/soleur/skills/*/SKILL.md description:` edit
> ⇒ §1.8 budget check skipped. **NO** new AGENTS.md rule ⇒ always-loaded byte budget untouched.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` *(new `workspaces-luks-cutover` job + choice option + description + `web-1-swap`)*
- `apps/web-platform/infra/cloud-init.yml` *(Phase 1 mount-pin + DSN persistence)*
- `apps/web-platform/infra/soleur-host-bootstrap.sh` *(baked LUKS + structural gate — fresh-host path)*
- `apps/web-platform/infra/git-data-bootstrap.sh` *(glob sweep, Q5)*
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` *(AC6b re-point, C10)*
- `apps/web-platform/infra/vector.toml` + `apps/web-platform/infra/vector-pii-scrub.test.sh` *(luks-monitor tag + fixture)*
- `apps/web-platform/infra/sentry/issue-alerts.tf` + `apps/web-platform/scripts/configure-sentry-alerts.sh` *(the paging rule)*
- `apps/web-platform/infra/uptime-alerts.tf` *(betteruptime_heartbeat)*
- `apps/web-platform/infra/server.tf` *(Phase 5 only — retire the old block; NO rename)*
- `knowledge-base/engineering/architecture/diagrams/model.c4` *(Phase 4/5 — description PLAINTEXT→LUKS)*
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` *(Phase 5 — status adopting→accepted)*

---

## Deferrals (tracking issues required)

| Item | Why deferred | Re-evaluation | Label |
|---|---|---|---|
| **PR 3 — the legal flip** (AC1–AC10 + present-tense LUKS + SHA re-pin + Art. 30 PA + compliance-posture) | Coupled by operator decision; lands only after the canary passes (AC30). **Re-derive the clause-site count at that PR** — #6568 proliferated the claim; the parent's "20 sites" is stale. | On canary-pass | `type/security` |
| Art. 25(1) gate: reconcile Art. 32 claims vs the Art. 30 register | Systemic root cause; own design | After PR 3 | `type/security`, `compliance/critical` |
| Expense-ledger rate correction (`~0.044` → `0.0572 EUR/GB/mo`, 5 rows) | Distinct concern/owner | Next invoice | `domain/engineering`, `priority/p3-low` |
| web-2's plaintext workspaces volume | Slated for teardown (#6538); empty; never served | With #6538 | `deferred-scope-out` |
| Fleet-wide backup posture (no snapshot/backup IaC) | Out of scope; retained volume is this cutover's backstop | Post-GA | `domain/engineering` |

---

## Acceptance Criteria

> **AC1–AC10 (the legal PR) are OUT OF SCOPE this run** — they ship in PR 3 after the canary. `/work`
> must satisfy none of them and must not treat them as unmet gates.

### Pre-merge (the infra PR) — THIS RUN's gates
- [ ] **AC13 (regression)** `workspaces-luks.test.sh` (A1–A11) still green; exclusion parity
      (`terraform-target-parity.test.ts`) still green — #6604 adds no new merge-path hcloud resource.
- [ ] **AC14** `cloud-init.yml` contains **no** `scsi-0HC_Volume_*` glob on the `/mnt/data` mount/fstab;
      the fstab line carries an explicit volume ID + `nofail` + a `grep -q` guard;
      `git grep -c 'scsi-0HC_Volume_\*' apps/web-platform/infra/cloud-init.yml` → `0`; the sweep also
      covers `git-data-bootstrap.sh` (Q5).
- [ ] **AC15** The STRUCTURAL fail-closed mount gate (RequiresMountsFor + crypttab + chattr +i) is
      authored AND delivered via the cutover channel (not the inert bake); mutation-tested — mounting
      `/mnt/data` from the raw device ⇒ container start refuses. **The reboot test (Phase 4) proves it
      survives `--restart unless-stopped` resurrection** (C2).
- [ ] **AC16** `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` green (budget 21,900).
- [ ] **AC17 (regression)** `terraform-target-parity.test.ts` green (`user_data` still in `ignore_changes`).
- [ ] **AC18** `bash tests/scripts/test-all.sh` — read the **`N/N suites passed`** summary (orphan-suite
      class); the new gate test is registered and green.
- [ ] **AC19 (regression)** No `TF_VAR_*`/`sensitive` variable added for the passphrase.
- [ ] **AC20** The `workspaces-luks-cutover` gate PASSES a create+attach plan and **ABORTS** (fixtures)
      on: old-volume touch, web-1 server touch, luks-volume destroy, passphrase touch, any out-of-scope
      positive action, or a no-op. **No `[ack-destroy]` bypass.** *(The old volume is protected by
      `old_volume_touched==0` + `resource_deletes==0` — NOT `prevent_destroy`, which #6593 deliberately
      omitted.)*
- [ ] **AC20a** `luks-monitor` is in `vector.toml`'s `include_matches.SYSLOG_IDENTIFIER` and the pinning
      fixture asserts it; the `sentry_issue_alert` (feature:workspaces-luks / op:workspaces-luks-drift)
      exists and is mirrored in `configure-sentry-alerts.sh`; `betteruptime_heartbeat.workspaces_luks`
      exists; the emit script carries the 9 discriminating fields and reads a **persisted** DSN.
- [ ] **AC20b** `workspaces-luks-verify.yml` exists (read-only, reusing the `luks-monitor.sh` probe logic —
      DP-11); `workspaces-luks-cutover.yml` is `environment:`-gated on the freeze/wipe steps with the #4220
      counter-argument **AND the `workspaces-luks-cutover` environment has a non-empty required-reviewer set**
      (DP-11 — a zero-reviewer environment auto-approves); the soak followthrough is enrolled
      (`follow-through` label + directive; a real ISO `earliest=`; secrets `SENTRY_AUTH_TOKEN` +
      `BETTERSTACK_QUERY_*`).

### Post-merge (automated — dispatch)
- [ ] **AC21** Cutover workflow conclusion `success`.
- [ ] **AC22 (blocking pre-freeze)** Escrow proof recorded: passphrase read via the host `prd_workspaces_luks`
      token path **unlocked the REAL device with `luksOpen --test-passphrase`** AFTER `prepare_luks_target`;
      `luksHeaderBackup` stored off-host (distinct bucket), `luksDump` UUID matches.
- [ ] **AC23 (verified live, not by inspection)** From the host, in-surface: `blkid -s TYPE -o value <dev-by-ID>`
      == `crypto_LUKS` **AND** `findmnt -no SOURCE /mnt/data` == `/dev/mapper/workspaces` **AND**
      `cryptsetup status workspaces` shows the mapper→device link **AND** `mountpoint -q /mnt/data`.
      Emitted with the discriminating fields.
- [ ] **AC24 (G2/G3 — the data gate)** Post-freeze SRC manifest == DST manifest, with `refs/checkpoints/*`
      as its **own** named check + the dirty-file inventory + a `count > 0` floor. *(The canary is
      structurally blind to partial data loss — G3, not the canary, is the data gate.)*
- [ ] **AC25 (G4)** Straggler assert (`lsof +D /mnt/data` empty) + interrupted-write asserts (no
      `index.lock`/`tmp_pack_*`/`gc.pid`) recorded before the delta pass.
- [ ] **AC26 (the false-green fix)** Itemized verify `rsync -aHAXi --numeric-ids --checksum --delete
      --dry-run --out-format='%i %n' | wc -l` == **0**, mutation-proven (touch/chmod/truncate/chown each
      flip RED); caches dropped first; `du --apparent-size` byte match; `git fsck --full` per workspace
      clean; `df` + `df -i` preflight passed.
- [ ] **AC27** `curl … https://app.soleur.ai/api/health` == `200` post-restart; `betteruptime_monitor.app`
      status == `up`; the reboot-once re-canary passed (C15).
- [ ] **AC28** Downtime ≤ **20 min** (workflow-emitted freeze-start/end timestamps); hard abort at 2h; the
      EXIT-trap auto-rollback is exercised in a dry-run.
- [ ] **AC29** Rollback rehearsal (read-only remount of the retained plaintext) recorded green in Phase 3.
- [ ] **AC30** 7d soak enrolled (positive-control heartbeat, correct secret names `SENTRY_AUTH_TOKEN` +
      `BETTERSTACK_QUERY_*`, a **real ISO `earliest=` timestamp** not the literal placeholder, and an
      internal **elapsed-window floor** ≥7d so a day-0 sweep cannot PASS — DP-5). The **read-only** soak
      script (sweeper-run) PASSes only on **observed completion** (drift=0 ∧ heartbeat present ∧ retained
      volume detached+gone ∧ PR 3 open ∧ ADR-119 `accepted`) and closes the tracker only then. The
      irreversible wipe (`blkdiscard -z` + read-back + detach + API-delete), the `for_each`-narrowing
      convergence (DP-2), the ADR flip, and opening **PR 3** ride a **separate `environment:`-gated
      dispatch** (DP-4) — never the unattended cron.

---

## Test Scenarios

Runners: `bash tests/scripts/test-workspaces-luks-cutover-gate.sh` (synthesized plan JSON, sourced lib);
`bash apps/web-platform/infra/*.test.sh` for infra guards; `bun test plugins/soleur/test/**`;
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (not `npm run -w` — no root `workspaces`).

1. Gate PASSES a pure create+attach plan; FAILS (each) old-volume-touch, web-1-server-touch,
   luks-volume-destroy, passphrase-rotate, doppler-secret-update, out-of-scope action, no-op.
2. AC14 grep: `scsi-0HC_Volume_*` count == 0 on the `/mnt/data` mount; fstab has volume ID + `nofail` + `grep -q`.
3. AC6b observability test re-pointed and green on the new invariant.
4. `luks-monitor` present in vector allowlist + fixture; a tag typo would red the fixture.
5. Container-start gate RED when `/mnt/data` is mounted from the raw device; survives a reboot (structural).
6. Escrow proof: a WRONG passphrase fails the `--test-passphrase` unlock (proves RED).
7. Itemized rsync verify: touch/chmod/truncate/chown each flip the `wc -l` from 0 to non-zero.
8. Soak: an auth failure returns TRANSIENT (exit 2), never PASS; a probe that never emitted a heartbeat FAILS.
9. Cutover script `DRY_RUN` exercises every phase with no writes; the EXIT trap rolls back a forced failure.
10. `cloud-init-user-data-size` under budget; `terraform-target-parity` still asserts `user_data`.

---

## Sharp Edges

- **The issue cites "ADR-118"; the LUKS ADR is ADR-119.** ADR-118 is the proxy-cert-SANs ADR. Never
  propagate ADR-118 into this work.
- **The old plaintext volume has NO `prevent_destroy`** (deliberately, #6593). Its only protection is the
  cutover gate's `old_volume_touched==0` + `resource_deletes==0`. Do NOT write an AC that asserts
  `prevent_destroy` on it.
- **Read the passphrase ONLY as `doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks`.**
  `doppler run`/`download --config prd_workspaces_luks` drags the root's ~116 `prd` secrets into env — the
  CWE-522 hole the dedicated config exists to close.
- **Select the LUKS device by volume ID, never by glob.** The glob now matches two devices; the inverse
  "which one is LUKS" predicate matches the LIVE PLAINTEXT volume during the transition.
- **`--restart unless-stopped` resurrects the container on reboot with no `docker run`** — a pre-`docker
  run` gate catches nothing. The gate MUST be structural (RequiresMountsFor + crypttab + chattr +i).
- **The escrow proof is vacuous unless it runs AFTER `prepare_luks_target` against the REAL device via the
  host token path.** A throwaway-format test passes for any string.
- **The LUKS header is an independent terminal limb** — `luksHeaderBackup` to a bucket distinct from
  tfstate, else the "different blast radius" property evaporates.
- **`blkdiscard` silently no-ops without discard support** — gate on `lsblk -D`; then verified read-back;
  then delete; then DETACH (unmounted is hygiene, not a control).
- **The soak could never go RED in the parent** (query matches zero unconditionally, no positive control,
  `earliest=` placeholder). Gate on heartbeat-present AND zero-drift; status-check first; real actor before
  `exit 0`.
- **`web-1-swap`, not `terraform-apply-web-platform-host`, for the cutover job** — it mutates web-1 (matches
  warm_standby/web_2_recreate). Flagged for plan-review.
- **A plan whose `## User-Brand Impact` is empty/`TBD` fails deepen-plan Phase 4.6.** It is filled.
- **`Ref #6588`, never `Closes`** — `type: security-remediation`; the remediation executes post-merge.

---

## Binding corrections — reference

C1–C19 in the parent plan's `## Deepen Pass Corrections — BINDING on /work` are binding. Their #6604
manifestations are folded above: **C1**→AC26/Phase 4; **C2**→AC15/Phase 2 (structural gate); **C3/C19**→
AC22/Phase 3 (escrow after prepare, host token path); **C4**→AC22 (header backup); **C5**→AC30/Phase 5
(blkdiscard+read-back+detach); **C6**→R9 (key-read form); **C7**→Phase 3 (blkid discriminator, no
`format`); **C8**→Phase 4 (`docker stop -t 120` + interrupted-write asserts); **C9**→AC24/Phase 4
(post-freeze SRC manifest); **C10**→AC14/Q6 (AC6b re-point); **C11/C13**→Downtime & Cutover (host-canary
before `docker start`, reconcilable rollback); **C12**→§Infra (no rename); **C14**→§Observability
(persisted DSN, discriminating fields, feature/op tags, Vector tag, heartbeat); **C15**→Phase 4
(reboot-once) + soak retention; **C18**→§Infra gate (counters, `web-1-swap`, choice option, ephemeral
keygen, no `[ack-destroy]`); **C19**→AC30/§Observability (soak actor, positive control, EXIT trap,
`cryptsetup status`, count floor, environment sign-off).

---

## Deepen Pass Corrections (#6604) — BINDING on `/work`

These supersede the sections they name. Each is evidence-backed against `origin/main`; none is taste.
DP-1/DP-2/DP-3/DP-4 are applied in-body above; DP-5…DP-11 are captured here.

- **DP-1 (terraform-architect F1, P1) — gate must permit the first-provision creates.** Applied in
  §Infrastructure "The cutover gate." The create is a `+create` of all five `workspaces_luks` resources;
  `-target` exactly those five; `luks_passphrase_touched` = `update`/`delete`/`forget` only.
- **DP-2 (terraform-architect F2, P1) — Phase-5 convergence is a `for_each` key-set narrowing, not a block
  delete.** Applied in §Infrastructure "Distinctness." Also update Phase 5.3 + Files-to-Edit `server.tf`
  note: the convergence PR edits the `for_each` on both `hcloud_volume.workspaces` and its attachment.
- **DP-3 (terraform-architect F4, P2) — concurrency rationale.** Applied. The R2 serializer is the
  inherited workflow-level group; `web-1-swap` coexists; keep the create job in `apply-web-platform-infra.yml`.
- **DP-4 (observability F1/F2 + spec-flow F9, P1) — soak is read-only verify-completion + separate
  environment-gated destructive dispatch.** Applied in §Soak Enrollment + AC30.
- **DP-5 (observability F3 + spec-flow F10, P2) — the soak needs a real elapsed-window floor.**
  `sweep-followthroughs.sh:74-79` maps an empty/unparseable `earliest=` to epoch 0 ⇒ day-0 open; the
  directive ships the literal `earliest=<canary+7d>`. Fix: substitute a **real ISO timestamp** at
  enrollment AND enforce an internal floor (canary timestamp ≥7d old, or heartbeat rows spanning ≥7d) so
  a day-0 sweep cannot PASS even if the directive is mis-filled. Include the archive arm (not `--no-archive`)
  for a real 7-day Telemetry span.
- **DP-6 (spec-flow F3/F5, P1) — three no-exit states from the C19 class survive; the root cause is
  rollback authority living in ephemeral process/shell state while the machine spans reboots + a 7-day gap
  + a fragile SSH bridge.** Fix, precedent `git-data-cutover.sh` (EXIT trap + `ROLLBACK` mode + recovery
  state, all HOST-SIDE): (a) `workspaces-cutover.sh` runs **on web-1** via the bridge, so `trap cleanup EXIT`
  is **host-local** and rolls back (unmount-mapper → remount-plaintext → restart) **without needing CI SSH**
  — closing "frozen-and-SSH-unreachable" (F3); (b) persist freeze state to a **host file** (`/var/lib/…`),
  not shell vars, so a deliberate reboot does not destroy the trap or the state; (c) the post-reboot
  re-canary is its **own gated step** that reads the persisted state and remounts plaintext on failure —
  the pre-reboot `CANARY_OK=true` must **never** satisfy the post-reboot gate (F5); (d) add a host-local
  **dead-man timer** that auto-remounts plaintext + restarts if no orchestrator heartbeat within N minutes;
  make the pre-freeze SSH-reachability gate a **renewing lease**, not a one-shot.
- **DP-7 (spec-flow F7, P2) — the Phase-5 `canary_ok` wipe-gate needs a durable, run-keyed, staleness-guarded
  source.** The wipe is a separate dispatch 7 days after the canary. Store the canary artifact in a **durable
  bucket** (R2, not an ephemeral GH artifact), **keyed to the run ID + the LUKS header UUID**, written only
  on canary-pass; the wipe dispatch **re-verifies the artifact's header-UUID against the live mapper**
  immediately before `blkdiscard`. A bare "a canary artifact exists" could green-light a wipe on a stale or
  prior-aborted run.
- **DP-8 (spec-flow F1, P2) — Phase 0's "STOP + remediate" needs a concrete, reachable procedure.** If web-1
  is in emergency mode (fstab already failed), the SSH bridge may be down and cloud-init never re-runs on
  web-1 (R6) — so even the read-only Phase 0 check cannot run. Make **SSH-bridge reachability an explicit
  precondition of Phase 0 itself**; if the host is in emergency mode the branch routes to **Hetzner
  rescue-system crypttab+fstab repair**, not "proceed."
- **DP-9 (observability F4, P2) — the persisted-DSN emit must be BAKED-first, not Doppler-first.**
  `cron-egress-enforce-probe.sh` reads the DSN via `doppler secrets get SENTRY_DSN` — copying it verbatim
  reintroduces the exact circular dependency (the "Doppler unreachable ⇒ MUST page" mode loses its DSN by
  the same cause). Fix: `workspaces-luks-emit.sh` reads the **baked** DSN first (the
  `soleur-host-bootstrap.sh:263-276` `@@SOLEUR_SENTRY_DSN@@` sed-splice shape, or an `EnvironmentFile`
  `/etc/default/luks-monitor` written root:root 0600 by cloud-init — same one-liner as `cloud-init.yml:409`),
  Doppler only as last resort. Prefer the dedicated env file over appending to the `deploy:deploy`-owned
  `webhook-deploy`.
- **DP-10 (observability F5, P2) — the Sentry emit envelope must carry BOTH `feature` AND `op` tags.** The
  `sentry_issue_alert` filters `feature=workspaces-luks` / `op IS_IN workspaces-luks-drift`, but Vector is
  Better-Stack-only (does not reach Sentry), so the drift PAGE depends entirely on the direct-curl envelope
  matching the filter. Model the emit tag-set on the **ghcr envelope at `soleur-host-bootstrap.sh:185`**
  (which sets `feature`/`op`), NOT the egress probe (which sets only `stage`/`host_id`/`probe_result`).
  Assert in the gate test that the emitted body carries both tags.
- **DP-11 (spec-flow F8 + simplicity, P2) — assertions + simplicity KEEPs.** (a) A GitHub environment with
  **zero configured reviewers auto-approves** — AC20b must assert the required-reviewer set is **non-empty**,
  not just that the environment exists. (b) **Simplicity KEEPs** (code-simplicity-reviewer): the two-workflow
  split, the daily escrow/header probe (load-bearing — catches steady-state drift before a reboot makes it
  terminal), the `betteruptime_heartbeat`, and the 7d soak are all KEEP. **SIMPLIFY:** `workspaces-luks-verify.yml`
  should invoke the **same probe logic** as `luks-monitor.sh` (DRY, not a bespoke reimplementation) — its
  only delta is the app-level workspace read; and keep the baked `soleur-host-bootstrap.sh` LUKS block
  **minimal** (it is dead on web-1; the live delivery is the cutover channel).
- **CONFIRMED (no change):** terraform-architect F5 (the two-artifact split is precedent-exact); observability
  Q1 (persisted DSN achievable), Q3/F6 (secret names + Telemetry-log gating), Q5 (all three page-legs exist,
  `betteruptime_heartbeat` is a real resource type); the exclusion parity + drift guard regression baseline.

---

## Deepen Pass Corrections (#6604) — BINDING on `/work`

Evidence-backed findings from the four review lenses. DP-1…DP-4 are already applied in-body (§Infra gate,
§Distinctness, §Soak, AC30); DP-5…DP-11 are captured here and supersede the sections they name.

### DP-1 (P1, terraform-architect F1) — gate must permit the FIRST-provision creates 🔴
Applied in §Infra "The cutover gate." The create is a `+create` of all five `workspaces_luks` resources;
`luks_passphrase_touched` counts `update`/`delete`/`forget` only; `-target` exactly the five; escrow runs
after the create.

### DP-2 (P1, terraform-architect F2) — Phase-5 convergence is a `for_each` narrowing, not a block delete 🔴
Applied in §Distinctness. `hcloud_volume.workspaces` is `for_each = var.web_hosts` (`server.tf:1241`);
retiring it requires narrowing the key-set to exclude web-1 on volume+attachment **in the same PR** as the
`state rm` of the two `["web-1"]` instances — or sequencing after #6538. Never delete the block or narrow
`var.web_hosts` (which destroys the web-1 server).

### DP-3 (P2, terraform-architect F3/F4) — gate `forget` arm + old-attachment backstop; concurrency rationale
Applied in §Infra gate (4-verb filter, `old_attachment_touched==0`) and §Distinctness (R2 serialization is
the inherited workflow-level group; `web-1-swap` coexists; keep the create job in `apply-web-platform-infra.yml`).
The two-artifact split is validated (F5, CONFIRM).

### DP-4 (P1, observability F1/F2 + spec-flow F9) — soak is read-only verify-completion, wipe is a separate gated dispatch 🔴
Applied in §Soak + AC30. The sweeper cannot run destructive/authed work (`env -i`, `contents:read`+`issues:write`).

### DP-5 (P2, observability F3 + spec-flow) — soak elapsed-window floor + real `earliest=`
The directive's `earliest=<canary+7d>` **literal placeholder** parses to epoch 0 (`sweep-followthroughs.sh:74-79`)
⇒ the gate opens on day 0; and "≥1 heartbeat ∧ zero drift" can PASS on day 1. **Fix:** substitute a real ISO
timestamp at enrollment, AND the script enforces an internal floor — require the canary timestamp ≥7d old (or
heartbeat rows spanning ≥7d via the archive arm, not `--no-archive`). The status-first + positive-control legs
(`reconcile-ff-only-sentry-4977.sh:58-72`) already close auth-zero-events + dead-probe.

### DP-6 (P1, spec-flow F3/F5/F7) — rollback authority must be host-side + durable, not ephemeral shell state 🔴
Three C19-class no-exit states survive because rollback state lives in the orchestrator's process/shell vars
while the machine spans a reboot, a 7-day gap, and a fragile SSH bridge:
- **F3 (mid-freeze SSH loss):** the EXIT trap, if it runs runner-side, cannot reach a dead host. **Fix:** the
  `workspaces-cutover.sh` runs **on web-1** (via the bridge), so `trap cleanup EXIT` is **host-local** and
  rolls back without CI SSH (precedent: `git-data-cutover.sh:85-101` — recovery state + host-side trap). Add
  a **host-local dead-man timer** (systemd `OnBootSec`/watchdog) that auto-remounts plaintext + restarts if no
  orchestrator heartbeat within N minutes; make the pre-freeze L3 gate a **renewing lease**, not one-shot.
- **F5 (reboot-once destroys the trap + stales `CANARY_OK`):** the deliberate reboot (Phase 4.8) kills the
  in-process trap and its shell vars, and `CANARY_OK=true` was set pre-reboot. **Fix:** persist freeze state
  to a **host file** (not shell vars); the post-reboot re-canary is its **own gated step** that remounts
  plaintext from the persisted state on failure — a pre-reboot `CANARY_OK=true` MUST NOT satisfy the
  post-reboot gate.
- **F7 (Phase-5 `canary_ok` provenance):** the wipe (7d later, separate dispatch) reads `canary_ok` from a
  persisted artifact — **Fix:** store it in a **durable bucket (R2), not an ephemeral GH artifact**, keyed to
  THIS run ID + the LUKS **header UUID**, written only on canary-pass, and re-verified against the live mapper
  header UUID immediately before `blkdiscard`.

### DP-7 (P2, observability F4) — the luks-monitor emit reads the BAKED DSN first, Doppler last
`cron-egress-enforce-probe.sh` reads the DSN via `doppler secrets get` — copying it verbatim reintroduces the
exact circular trap (the "Doppler unreachable ⇒ MUST page" mode loses its DSN by the same cause). **Fix:**
`workspaces-luks-emit.sh` reads a **baked** DSN first — a dedicated `/etc/default/luks-monitor` (root:root
0600) written by cloud-init (same one-liner as `cloud-init.yml:409-411`), or the `soleur-boot-emit`
`@@SOLEUR_SENTRY_DSN@@` sed-splice shape (`soleur-host-bootstrap.sh:263-276`) — Doppler only as last resort.
Persisted-DSN feasibility CONFIRMED (`${sentry_dsn}` is already a rendered cloud-init var).

### DP-8 (P2, observability F5) — the Sentry emit envelope MUST carry BOTH `feature` AND `op` tags
The `sentry_issue_alert` filters `feature=workspaces-luks` ∧ `op IS_IN workspaces-luks-drift`, but
`cron-egress-enforce-probe.sh` sets only `stage`/`host_id`/`probe_result`. Vector is Better-Stack-only
(doesn't reach Sentry), so the drift PAGE depends **entirely** on the direct-curl envelope matching the
filter. **Fix:** model the emit tag-set on the ghcr envelope (`soleur-host-bootstrap.sh:185`, which sets
`feature`/`op`); the gate test asserts the emitted body carries both. (`luks-monitor` Vector tag path + the
`betteruptime_heartbeat` resource are both confirmed achievable; include the archive arm for a real 7d span.)

### DP-9 (P1/P2, spec-flow F1/F8/F10) — close the remaining partial exits
- **F1 — Phase-0 mount-repair (P1):** if web-1 is in emergency mode (fstab already failed), the SSH bridge may
  be down and Phase 1's `nofail` fix never reaches the host (cloud-init never re-runs). **Fix:** make SSH-bridge
  reachability an explicit **precondition** of Phase 0; the "unmounted /mnt/data" branch routes to a named
  **Hetzner rescue-system crypttab+fstab repair** runbook, not "proceed."
- **F8 — environment reviewer non-empty (P2):** a GitHub environment with **zero** configured reviewers
  auto-approves. AC20b must assert the required-reviewer set is **non-empty**, not merely that the environment
  exists.
- **F10 — G3 count floor (P2):** the literal `count > 0` floor collides with Phase 0's "near-empty at 0 users"
  (0 workspaces ⇒ false-RED or vacuous). **Fix:** derive the floor from the **observed G2 count** (assert
  `DST_count == G2_count`), not a hardcoded `>0`.

### DP-10 (simplicity — KEEP/SIMPLIFY) — no safety controls cut on sole-copy data
KEEP: the two-artifact split (F5); the **daily** escrow/header probe (catches steady-state drift before a
reboot makes it terminal); the 7d soak + reboot-once (complementary, not redundant). SIMPLIFY: `workspaces-luks-verify.yml`
**reuses the daily probe's logic** (DRY — a dispatchable trigger of the same assert + the app-level workspace
read), not a bespoke reimplementation; the `betteruptime_heartbeat` is justified as the **steady-state
dead-probe switch** (distinct from the soak's log-line query); keep the baked `soleur-host-bootstrap.sh` LUKS
block **minimal** (crypttab + `RequiresMountsFor` + `chattr +i`, no gold-plating) since it is dead on web-1 —
or defer its full authoring to the next fresh-host provision (tracking note), delivering only the live-host
gate via the cutover channel now.

### DP-11 (path correction) — `vector-pii-scrub.test.sh` lives under `test/infra/`
The pinning fixture is `apps/web-platform/test/infra/vector-pii-scrub.test.sh`, not `apps/web-platform/infra/`
(applied in §Infra + Files-to-Edit).

---

## Decision Challenges (ADR-084)

Carried forward from `knowledge-base/project/specs/feat-one-shot-6588-luks-workspaces-volume/decision-challenges.md`.
**DC-A (couple the legal PR) was RESOLVED interactively 2026-07-17 — operator DECLINED the decouple; the
coupling stands.** Consequence for #6604: **the infra PR carries ZERO doc changes**; PR 3 (the legal flip,
AC1–AC10 + present-tense LUKS) lands only after the canary passes and is opened by the soak actor (AC30).
DC-B/DC-C are legal-track concerns resolved in the parent; nothing in #6604 relitigates them.
