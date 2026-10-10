---
title: "chore(infra): inngest-luks-cutover + inngest-luks-open fail on first boot — EnvironmentFile staged by a later runcmd stage"
date: 2026-10-10
slug: chore-inngest-luks-first-boot-envfile-ordering
branch: feat-one-shot-9939-inngest-luks-boot-failures
issue: 9939
closes: []
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# chore(infra): inngest-luks-cutover + inngest-luks-open fail on first boot — EnvironmentFile staged by a later runcmd stage

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Enhancement Summary

**Deepened on:** 2026-10-10
**Sections enhanced:** Proposed Solution (file-staging topology), Acceptance Criteria (pre-merge/post-merge split + ratchet AC), Files to Edit (BASELINE_DECLARED_PROBES ratchet), new Downtime & Cutover + Network-Outage Deep-Dive sections
**Research agents used:** none available — no Task/subagent tool in this environment; all gates, verify-the-negative checks, and review passes ran inline with `Reviewed-Coverage: sequential-fallback` disclosure (never claimed as independent review)

### Key Improvements

1. Added the delivery-chain analysis: the trio files are image-baked carriers (`cp`-staged in `build-inngest-bootstrap-image.yml`), so the fix reaches the host via the auto-minted `vinngest-v*` tag → build/sign → `bump-cloud-init-pin` chain, and the cloud-init edit via `user_data` ForceNew replace.
2. Confirmed by journal read (not hypothesis) that the observed storm was a LUKS-stage abort cascade — no static early pull-in exists — and chose `ConditionPathExists=` over both the `-` prefix (rejected by the issue) and a bootstrap-side `[ -f ]` gate (does not self-heal, misses non-timer triggers).
3. Made the acceptance mechanical: the rehearsal capture script gains a `Failed to start inngest-luks` forbidden row so the evidence artifact carries the property on every future run.

### New Considerations Discovered

- `discoverability_test.credentials_required` moves `BASELINE_DECLARED_PROBES` (53 → 54) in `plugins/soleur/test/preflight-discoverability-test.test.ts` — same-PR bump required.
- The cloud-init edit forces a `hcloud_server.inngest` replace on the next apply → `## Downtime & Cutover` added; `closes: []` + `Ref #9939` because the acceptance evidence is post-merge (the #9175 plan's disposition for the identical shape).
- Phase 4.5 triggered on the literal `SSH` (the plan's "no-SSH" assertions) — the deep-dive resolves clean: the host has no SSH surface by design and no TF root on this path carries `provisioner`/`connection` blocks.

## Overview

On a fresh inngest provision, two LUKS-related systemd units attempt their first start before the `runcmd:` stages that write their `EnvironmentFile=` files have run — or after the LUKS stage aborts and never writes them at all. `inngest-luks-cutover.service` (fired by `inngest-luks-cutover.timer` at `OnBootSec=30s`) and `inngest-luks-open.service` each declare env files without the `-` tolerance prefix — a deliberate fail-closed contract — so a start attempted while a file is absent produces a `Failed to start` journal row (plus, on the cutover unit, an `ExecStopPost` `unit-exit` phone-home) for what is benign ordering/enablement noise. The noise trains the LUKS boot/cutover observability channel to carry false failures, masking real first-boot failures. The fix is ordering and enablement — `ConditionPathExists=` on the env files so a start attempted too early (or after a stage abort) skips instead of fails — while keeping the fail-closed `EnvironmentFile` semantics for the runs that matter.

## Problem Statement / Motivation

Issue #9939 (surfaced by the #9175 forced-race provision rehearsal). Measured against the Better Stack journal channel for rehearsal host `soleur-inngest-rehearsal-38031062344` (run adjacent to the cited 38036022367):

- `inngest-luks-open.service`: one `Failed to start` row at 06:30:46 — this is runcmd's own `systemctl enable --now` (cloud-init-inngest.yml arm item) firing after the runcmd LUKS stage FATAL'd at `stage=privilege rc=1`, so `/etc/default/inngest-luks` was never written. The `inngest-luks-reopen-ARM-FAILED is-active=failed` phone-home fired correctly.
- `inngest-luks-cutover.service`: `Failed to load environment files: No such file or directory` → `Failed with result 'resources'` → `Failed to start` every ~31 s from 06:38:53 until teardown — the bootstrap-armed poll timer ticking against `/etc/default/inngest-luks-volumes`, which never existed on that host. The `ExecStopPost` could not even spawn ("Failed to spawn 'stop-post' task").
- Collateral: `inngest-redis.service` `Failed to start` every ~5 s (mount-guard refusals — the designed loud failure for a closed mapper; out of this issue's scope but part of the same storm).

File-staging topology (verified against the render source): `/etc/default/inngest-doppler` (runcmd ~1544) and `/etc/default/inngest-server` (runcmd ~2162) are standalone runcmd items — they land even under a LUKS-stage abort. `/etc/default/inngest-luks` and `/etc/default/inngest-luks-volumes` are written *inside* the stage's `doppler run … bash -s` heredoc (~1735/~1748) — a stage FATAL at `privilege` dead-writes both. So the observed shape is exactly "doppler + server present, luks + luks-volumes absent" — which is why the conditions must cover every `EnvironmentFile=`, not just the two that were missing this time.

On the healthy run (38036022367) the same journal was clean — runcmd sequencing is write-then-enable on the happy path. The defect is therefore twofold: (1) a latent ordering hazard — anything that starts these units before the writers complete fails them; (2) a guaranteed storm under any LUKS-stage abort, where runcmd continues (no errexit between items), the `enable --now` and the bootstrap-armed timer both fire against env files that will never exist.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Measured reality | Plan response |
|---|---|---|
| "a dependency pulling `inngest-luks-open.service` before runcmd's own `enable --now`" | No static pull-in exists — no unit declares `Wants=`/`Requires=`/`BindsTo=` on it; `After=`/`Before=` are ordering-only. The observed pull-in was the `enable --now` itself, cascading a stage abort. | Fix the consequence (condition-skip) not a hypothetical puller; the condition also covers any pull-in added later. |
| "firing against a not-yet-staged `/etc/default/inngest-luks-volumes`" | On the failing host the file was *never* staged (stage abort), not merely late. On a healthy boot the write-then-arm order already holds (runcmd items ~1544/1735/1748 precede `enable --now` ~1986 and the provision `start --no-block` ~2217). | Same fix covers both arms; acceptance now holds under stage aborts too, which is where the noise actually came from. |
| "failing before recovering" | The cutover never recovered on the abort host — ~31 s failure ticks until teardown. | The condition turns unstartable ticks into skips; a host whose env files appear later self-heals on the next boot. |

## Proposed Solution

Add `ConditionPathExists=` covering **every** `EnvironmentFile=` each unit declares (the fail-closed `EnvironmentFile=` lines are kept — the issue is explicit that the contract is correct):

1. `apps/web-platform/infra/cloud-init-inngest.yml` — `inngest-luks-open.service` write_files block `[Unit]`:
   `ConditionPathExists=/etc/default/inngest-doppler` + `ConditionPathExists=/etc/default/inngest-luks`
2. `apps/web-platform/infra/inngest-luks-cutover.service` `[Unit]`:
   `ConditionPathExists=/etc/default/inngest-server` + `ConditionPathExists=/etc/default/inngest-luks-volumes`
3. `apps/web-platform/infra/inngest-luks-cutover.timer` `[Unit]`:
   the same two lines — a condition on the timer is evaluated at activation (`enable --now`, or `timers.target` on later boots), so under a stage abort the timer never arms at all: one skip notice per boot instead of a 31 s failure tick. Re-evaluated at each boot's activation, so it self-heals if the files ever appear.

Measured semantics (systemd 261, `--user` harness; the host runs 255 — condition semantics are stable since ~v210): a condition-failed start job exits `systemctl start`/`enable --now` rc 0, `is-active` reads `inactive`, and journald gets one NOTICE row "skipped, unmet condition check". Consequences verified:

- `enable --now inngest-luks-open.service` under abort → enabled, start skipped → `is-active=inactive` → the existing `inngest-luks-reopen-ARM-FAILED` phone-home still fires (its check is `= "active"`, not rc). The unit stays enabled, so a later boot with the files present reopens normally.
- `systemctl enable --now inngest-luks-cutover.timer` in `inngest-bootstrap.sh` (under `set -euo pipefail`) → rc 0 → no bootstrap abort; the timer reads `enabled`/`inactive` in the `post-boot-health` `svc=` field, which is *more* diagnostic than today.
- A skipped service never runs `ExecStopPost` → no `unit-exit` phone-home noise; a legitimately-started service that fails still emits it.

### Alternative approaches considered

| Shape | Verdict |
|---|---|
| `EnvironmentFile=-` tolerant prefix | Rejected by the issue itself — an absent key file must not let the unit proceed (git-data/workspaces reopen units chose `-` + in-script failure deliberately; inngest's contract is stricter). |
| Move the env-file writes earlier in runcmd | Impossible — `/etc/default/inngest-luks*` need the Doppler CLI/token stage (the key lives in `soleur-inngest/prd`) and the LUKS stage's measured volume ids. The healthy-path order is already write-then-enable. |
| Gate the bootstrap's `enable --now` on file presence (`[ -f ] && systemctl enable --now`) | Covers the timer storm but (a) leaves every non-timer trigger of the service unprotected, (b) permanently disarms rather than self-healing, (c) adds a second mechanism for the same property. Declined — the timer condition is strictly better; may be added later as a marker-emitting hardening if the single skip notice proves insufficient. |
| `ExecCondition=/usr/bin/test -f …` | Equivalent result; `ConditionPathExists=` is declarative and is the established repo pattern (`soleur-inngest-provision.service`'s `ConditionPathExists=!` latch, ADR-257; `scripts/tmpfs-guard.service`). |
| `.path` unit with `PathExists=` | Heavier machinery (a fourth unit) for a first-boot-once staging window — fails the minimalism ladder. |
| Ordering (`After=`/`Requires=` against a "files staged" unit) | No such unit exists and ordering cannot express "wait for file"; a refused start is the requirement, not a delayed one. |

## Implementation Phases

### Phase 1 — Unit conditions

- `apps/web-platform/infra/cloud-init-inngest.yml`: add the two `ConditionPathExists=` lines to the `inngest-luks-open.service` `[Unit]` block (after `Before=`), with a comment in the file's house style explaining skip-vs-fail and why the env files can be absent (stage abort / pre-write pull-in).
- `apps/web-platform/infra/inngest-luks-cutover.service`: add the two lines to `[Unit]` with a comment noting the timer is not the only possible trigger (`[Install] WantedBy=multi-user.target`).
- `apps/web-platform/infra/inngest-luks-cutover.timer`: add the same two lines to `[Unit]` with a comment noting the condition is evaluated at activation (not per-elapse) and that the file set mirrors the service's `EnvironmentFile=` set.

### Phase 2 — Evidence-channel guard

- `scripts/followthroughs/inngest-provision-rehearsal-capture.sh`: add a shared forbidden-row check — count `Failed to start inngest-luks` rows in the mode's host-row set (`HOST_ROWS` for phase-a/phase-b, `POST_ROWS` for post-reboot) and `viol` on `> 0`. This makes the issue's acceptance mechanical in the existing evidence artifact on every future rehearsal, including stage-abort shapes.

### Phase 3 — Suite pins

- `apps/web-platform/infra/inngest-redis-luks.test.sh`: new T1.x asserts — the `inngest-luks-open.service` block carries both `ConditionPathExists=` lines AND retains unprefixed `EnvironmentFile=`; a mutation row that drops a condition line and must RED; floor raised from 57 to the measured count.
- `apps/web-platform/infra/inngest.test.sh`: new arm asserting both committed trio files carry `ConditionPathExists=` on both env files (service + timer), and that `EnvironmentFile=` remains unprefixed.
- `scripts/followthroughs/inngest-provision-rehearsal-capture.test.sh`: new arms — a stubbed `Failed to start inngest-luks-cutover.service` row in the host-row fixture drives the `viol`/FAIL arm in the modes it applies to; a clean fixture still passes (guard not vacuous in the pass direction).

### Phase 4 — Delivery + verification

- Merge → the mint workflow auto-mints the next `vinngest-v*` tag on the carrier change → `build-inngest-bootstrap-image` publishes/signs → `bump-cloud-init-pin` rewrites the two `IREF`/`ZIREF` pins on main. The `cloud-init-inngest.yml` edit is a `user_data` carrier for `hcloud_server.inngest` (no `ignore_changes`) — it reaches the host on the next apply/replace; nothing is edited on the live host (`hr-prod-host-config-change-immutable-redeploy`).
- Dispatch `inngest-provision-rehearsal.yml` (`dry_run=false`) — phase-b and post-reboot captures carry the new forbidden rule; the evidence artifact is the acceptance proof. Same-delivery-sequence precedent: #9787 edited both trio files and shipped via this exact mint→build→pin-bump chain.
- Spot-check `deploy-script-tests` GuardA — it is advisory (not a required check) and asserts tag↔HEAD carrier byte-identity; it may red on the PR leg before the tag exists and reconciles post-merge when the pin lands. Do not "fix" a GuardA red by reverting carriers.

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml` — `inngest-luks-open.service` write_files block: +2 `ConditionPathExists=` lines + comment.
- `apps/web-platform/infra/inngest-luks-cutover.service` — `[Unit]`: +2 lines + comment.
- `apps/web-platform/infra/inngest-luks-cutover.timer` — `[Unit]`: +2 lines + comment.
- `apps/web-platform/infra/inngest-redis-luks.test.sh` — condition asserts + mutation row + floor bump.
- `apps/web-platform/infra/inngest.test.sh` — trio condition asserts arm.
- `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` — luks `Failed to start` forbidden check.
- `scripts/followthroughs/inngest-provision-rehearsal-capture.test.sh` — new fixture arms for the check.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — `BASELINE_DECLARED_PROBES` 53 → 54: this plan's `discoverability_test` declares `credentials_required`, which the G1 ratchet counts repo-wide (walk `knowledge-base/project/plans/**`). Bump in the same PR with the PLACEMENT/TRUTH/NO SUBSTITUTE comment the failure text requires — a `LEFTHOOK_EXCLUDE=bun-test` commit path would red one commit later.

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing artifact — the blast radius is an inngest host that skips a boot unit it should have run (mapper unopened → `inngest-redis` mount-guard refuses → the scheduler's durable tier is down, reported by existing markers) or a `Failed to start` row persisting (the status quo this fixes).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure — the change adds file-presence conditions to existing units; it touches no credential, data path, or network edge. The LUKS passphrase handling is unchanged.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal boot-ordering machinery on a no-SSH scheduler host; the worst outcome is observability noise or an already-loud Redis refusal, neither user-visible.
- `threshold: none, reason: the diff touches apps/web-platform/infra/ (a sensitive path per SENSITIVE_PATH_RE) but changes only systemd start conditions — no user data path, credential handling, or auth surface is altered`

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INNGEST_BOOT_STAGE phone-home markers (runcmd-entered → provision-unit-armed → provision-attempt-start → bootstrap-done) plus the `inngest-luks-cutover` unit-exit rows on every timer tick
  cadence: per boot for stage markers; ~30-90 s for the cutover poll
  alert_target: Better Stack journal channel (queried by followthrough probes + rehearsal evidence)
  configured_in: apps/web-platform/infra/cloud-init-inngest.yml (phone-home emitter + runcmd markers); apps/web-platform/infra/inngest-luks-cutover.service ExecStopPost

error_reporting:
  destination: Better Stack phone-home (`inngest-boot-phone-home.sh`, direct curl, no Vector dependency) + journald→Vector→Better Stack
  fail_loud: `inngest-luks-reopen-ARM-FAILED is-active=<state>` phone-home when the reopen unit does not read active after arming; `inngest-luks-FAILED stage=<name>` on any LUKS-stage abort

failure_modes:
  - mode: env files absent at unit start (stage abort or pre-write pull-in)
    detection: unit skips instead of fails — `is-active` reads `inactive`, the ARM-FAILED marker fires, and journald carries one "skipped, unmet condition check" notice per trigger
    alert_route: the `inngest-luks-FAILED` / `inngest-luks-reopen-ARM-FAILED` phone-home markers (Better Stack)
  - mode: LUKS stage FATAL leaves the host unprovisioned
    detection: unchanged by this plan — stage marker + provision-attempt retry reporting
    alert_route: existing markers (stage=privilege/device_wait/etc. carry the failing stage name)

logs:
  where: journald on the host → Vector → Better Stack source `soleur-inngest-vector-prd`; phone-home side channel for pre-Vector windows
  retention: Better Stack hot window ~40 min + s3 archive (queried via scripts/betterstack-query.sh union)

discoverability_test:
  command: bash scripts/betterstack-assert-absence.sh --host soleur-inngest-prd --absence 'Failed to start inngest-luks' --control SOLEUR_INNGEST_LUKS_CUTOVER --since 6h
  expected_output: SOLEUR_ABSENCE_ASSERT outcome=clean
  credentials_required: "doppler soleur/prd_terraform BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} — the journal channel is credential-gated; no unauthenticated read of it exists"
```

## Encryption Posture

No new persistent store or cross-component connection is introduced — the change is a start condition on existing units. Section emitted because the diff touches `cloud-init.*.yml`; postures below are the unchanged status quo, declared so this edit cannot launder a posture claim.

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis + hcloud_volume.inngest_redis_luks (the /mnt/data AOF store and its staging sibling)
    mechanism: luks — cryptsetup luksFormat in the runcmd LUKS stage; passphrase in Doppler soleur-inngest/prd (INNGEST_REDIS_LUKS_KEY), no escrow (ADR-142)
    evidence: apps/web-platform/infra/cloud-init-inngest.yml LUKS stage (luksFormat/luksOpen arms); /etc/default/inngest-luks staged 0600 root:root
    defends_against: a detached volume read off-host (snapshot, reattach elsewhere, RMA'd disk)
    does_not_defend: a running host whose mapper is open; a leaked Doppler token scoped to soleur-inngest/prd; plaintext copies made by Redis itself
    disclosed_as: not-publicly-claimed
    live_verification: available — blkid TYPE=crypto_LUKS asserted by the boot-reopen unit and the staging_verify stage emit
in_transit:
  - connection: inngest host -> api.doppler.com (secret reads) and -> Better Stack ingest (journal/phone-home)
    enforced_at: apps/web-platform/infra/cloud-init-inngest.yml (doppler CLI invocations; inngest-boot-phone-home.sh curl)
    tls: HTTPS (TLS 1.2+) via the Doppler CLI and curl
    cert_verification: on
    does_not_defend: a root actor on the host reading the scoped token at /etc/default/inngest-doppler
    disclosed_as: not-publicly-claimed
```

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed — no operator-run infrastructure steps; all changes are file edits delivered through cloud-init/image/apply -->

### Terraform changes

None — no `.tf` files change. All delivery is through existing IaC carriers: `apps/web-platform/infra/cloud-init-inngest.yml` renders into `hcloud_server.inngest`'s `user_data` (ForceNew, no `ignore_changes`), and the trio files flow through the `vinngest-v*` tag → `soleur-inngest-bootstrap` image → `IREF`/`ZIREF` pin chain.

### Apply path

(b) `terraform apply -replace` / next scheduled inngest-host replace — the fix is provision-time by nature; the acceptance criterion is itself "a fresh `terraform apply` provision". A dedicated replace is NOT required to merge: the change is inert on the live host until its next replace. Verification vehicle: `inngest-provision-rehearsal.yml` (`dry_run=false`, throwaway host), which exercises the real cloud-init + the new capture rule end-to-end including a reboot.

### Distinctness / drift safeguards

- Rehearsal root `apps/web-platform/infra/inngest-provision-rehearsal/` renders the same cloud-init against a non-inheriting scratch Doppler config — the forbidden rule verifies on the throwaway host without touching prod state.
- `deploy-script-tests` GuardA (advisory) binds pinned-tag↔HEAD carrier byte-identity; it reconciles when `bump-cloud-init-pin` lands post-merge.
- The `inngest-luks-FAILED`/`ARM-FAILED` phone-home markers are preserved verbatim — the conditions change the *journal* shape of the failure (skip vs start-failure), not the off-box marker path.

### Vendor-tier reality check

None — no new vendor resources (Hetzner/Doppler/Better Stack all within existing usage).

## Network-Outage Deep-Dive (Phase 4.5)

Fired on the literal `SSH` trigger (the plan's "no-SSH" assertions); resolved clean:

- **L3 firewall allow-list:** not applicable — the plan changes no firewall resources and the host has no inbound path by design (ADR-225). Verified: `inngest-host.tf`, `inngest.tf`, and the rehearsal root carry no `provisioner "file"`/`remote-exec` or `connection` blocks — `terraform apply` on this path has no SSH dependency.
- **L3 DNS/routing:** unchanged — no network resources touched; the rehearsal host exercises the same egress path.
- **L7 TLS/proxy:** unchanged — the only network calls the units make are the existing outbound HTTPS (Doppler, Better Stack ingest).
- **L7 application:** the change is unit-activation conditions; the phone-home emitter's path is untouched.

## Downtime & Cutover (Phase 4.55)

- **Offline-inducing operation:** `hcloud_server.inngest` replace — `user_data` is ForceNew and carries no `ignore_changes`, so the cloud-init edit takes the host down for one replace window on the next `terraform apply` (the same window every cloud-init change on this host takes).
- **Surface affected:** `soleur-inngest-prd` — the dedicated scheduler host. During the replace window the self-hosted Inngest scheduler is offline; Inngest jobs and Concierge work pause until the new host provisions (boot + provision minutes, per prior replace/rehearsal timings).
- **Zero-downtime path evaluated:** blue-green (a second inngest host, drain, cut over) — rejected: the host is a deliberate singleton with no blue-green machinery, and the issue's acceptance is itself "a fresh `terraform apply` provision"; building a second-host path for a chore would invert the scope. The merge itself induces **zero** downtime — the change is dormant until the next apply, whose timing is operator-chosen (replace-on-apply is the standing delivery contract for this host: in-place edits are banned by `hr-prod-host-config-change-immutable-redeploy`, and every prior cloud-init change paid the same window — #9787's parameterization shipped the identical shape the day before).
- **Residual downtime justification:** one bounded replace window, operator-timed; the `inngest-provision-rehearsal.yml` `dry_run=false` run exercises the exact cloud-init on a throwaway host first, so the replace's risk is measured before it is spent.

## Guard Contract

### Guard 1 — no-luks-failed-start evidence rule + suite pins

**Property.** No start of `inngest-luks-cutover.service`, `inngest-luks-cutover.timer`, or `inngest-luks-open.service` may be attempted while any of its declared `EnvironmentFile=` paths is absent — such starts are condition-skipped, never start-failures — and the rehearsal evidence artifact mechanically forbids `Failed to start inngest-luks` rows.

**Assembly.** Every activation path for the three units: the timer's `enable --now` (inngest-bootstrap.sh inside soleur-inngest-provision.service) and `timers.target` on later boots; the service's timer elapses plus its `[Install] WantedBy=multi-user.target` and any future `Wants=`/`Requires=` consumer; `inngest-luks-open.service`'s runcmd `enable --now` arm and its `multi-user.target.wants` pull-in on later boots. The assertion chokepoints are the three unit files themselves (each names every `EnvironmentFile=` it declares, so a partial env-file set still skips), and the capture script's `viol()` path in `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` for the journal-row half.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `ConditionPathExists=/etc/default/inngest-luks` from the luks-open write_files block | RED — the T1.x condition assert in inngest-redis-luks.test.sh fails |
| 2 | Delete `ConditionPathExists=/etc/default/inngest-luks-volumes` from inngest-luks-cutover.timer (the second env file, after a compliant first) | RED — the trio arm in inngest.test.sh names every file the service declares, not just the first |
| 3 | Drop the `Failed to start inngest-luks` forbidden check from the capture script | RED — the capture suite's new fixture arm injects such a row and expects the `viol`/FAIL exit |
| 4 | Weaken the new inngest.test.sh arm itself (presence grep on one file only) | test-strength mutation — NOT suite-observable (the floor counts assertions, not discrimination); the shipped arm satisfies the coverage intent by asserting every file's full condition set |
| 5 | Re-point a `ConditionPathExists=` at a path that always exists (e.g. `/etc`) | RED — the asserts pin the literal env-file paths, not merely the directive's presence |
| 6 | Must-PASS: a healthy rehearsal host (env files staged, both units active) | PASS — the forbidden check counts only `Failed to start` rows; normal `reopen_ok`/`unit-exit` rows are unaffected, and the capture's positive arms are untouched |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "A fresh `terraform apply` provision produces zero `Failed to start` rows for `inngest-luks-cutover` / `inngest-luks-open` (verify via the Better Stack journal channel or the rehearsal workflow's evidence artifact — no SSH)." [issue #9939] | Phase 1 unit conditions + Phase 2 capture `viol` check + AC1/AC2/AC6/AC8 | mapped |
| 2 | "the fix is ordering/enablement, not prefixing with `-` — except where a tolerant read is genuinely safe" [issue #9939] | Phase 1 keeps unprefixed `EnvironmentFile=`; suite pins assert the unprefixed form survives | mapped |
| 3 | "gate the cutover timer's enable on the env files existing (bootstrap already stages them)" [issue #9939, candidate shape] | Phase 1 `ConditionPathExists=` on `inngest-luks-cutover.timer` (the stronger form of the same idea — evaluated per activation, self-healing) | mapped |
| 4 | "add an `ExecCondition=`/`ConditionPathExists=` on the env files" [issue #9939, candidate shape] | Phase 1 `ConditionPathExists=` on all three units | mapped |
| 5 | "identify the actual early pull-in from the journal before choosing" [issue #9939, candidate shape] | Done at plan time via Better Stack (Research Reconciliation): the pull-ins are runcmd's own `enable --now` under a stage abort, and the bootstrap-armed timer against never-written files | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `ConditionPathExists=` on the three units | "add an `ExecCondition=`/`ConditionPathExists=` on the env files" | asked |
| Keep unprefixed `EnvironmentFile=` | "the fix is ordering/enablement, not prefixing with `-`" | asked |
| Rehearsal-capture `Failed to start inngest-luks` forbidden rule | "verify via the Better Stack journal channel or the rehearsal workflow's evidence artifact — no SSH" | inferred — justification: the ask names the evidence artifact as the verification vehicle; without a mechanical forbidden rule the artifact carries no opinion on the property and the acceptance reverts to a manual journal read |
| Suite asserts in inngest-redis-luks.test.sh / inngest.test.sh / capture.test.sh | — | inferred — justification: this repo's convention is that every infra behavior ships with a pinning assertion + mutation row; an unpinned condition rots on the next unit edit |
| Comment blocks on the added lines | — | inferred — justification: every unit in these files carries a dense why-comment; an uncommented directive violates the file's own convention (cq-cite-content-anchor) |
| `BASELINE_DECLARED_PROBES` bump (53→54) | — | inferred — justification: the `discoverability_test.credentials_required` field is a repo-global ratchet input (preflight Check 10 SKIP-DECLARED); the G1 test counts declaring plans and fails without the bump — omitting it leaves the PR red on the full battery |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `scripts`, `plugins`
- Planned files: 8 | Estimated changed lines: ~230 (mostly comments + test asserts)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `inngest-luks-cutover.service`, `inngest-luks-cutover.timer`, and `inngest-luks-open.service` each declare `ConditionPathExists=` for **every** path in their `EnvironmentFile=` set, and every `EnvironmentFile=` line remains unprefixed (fail-closed contract retained).
- [ ] AC2: `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` reports `viol`/FAIL when a `Failed to start inngest-luks*` row exists in the host's row set for the mode's window, in every mode the script supports.
- [ ] AC3: The `inngest-luks-reopen-armed`/`ARM-FAILED` marker logic is unchanged (`is-active` driven), the timer still polls ~30 s on a healthy host, and a legitimately-started service failure still emits the `unit-exit` ExecStopPost row.
- [ ] AC4: `inngest-redis-luks.test.sh`, `inngest.test.sh`, and `inngest-provision-rehearsal-capture.test.sh` carry the new asserts and pass, including at least one mutation row per new check that drives the suite RED when the condition or the forbidden rule is removed.
- [ ] AC5: `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` is 54 (bumped in this PR with the required PLACEMENT/TRUTH/NO SUBSTITUTE comment).

### Post-merge (evidence — issue stays open until these land; PR body says `Ref #9939`, not `Closes`)

- [ ] AC6: A fresh `terraform apply` provision produces zero `Failed to start` rows for `inngest-luks-cutover` / `inngest-luks-open`, verified via the Better Stack journal channel or the rehearsal workflow's evidence artifact — including under a LUKS-stage abort (the shape that produced the observed storm), where the arming markers (`inngest-luks-FAILED`, `inngest-luks-reopen-ARM-FAILED`) still fire.
- [ ] AC7: The mint → build → pin-bump chain delivered: `cloud-init-inngest.yml`'s `IREF`/`ZIREF` pins on main name a `vinngest-v*` tag whose carriers are byte-identical to the merged files (the advisory GuardA leg is green on main after the bump lands).
- [ ] AC8: The next `inngest-provision-rehearsal.yml` `dry_run=false` run's evidence artifact carries `REHEARSAL_PHASE_B_RECOVERY=PASS` + `REHEARSAL_POST_REBOOT_LATCH=PASS` with the new forbidden rule enforced (zero `Failed to start inngest-luks*` rows in the host's row set).

## Test Scenarios

- Given `inngest-luks-open.service` rendered in cloud-init, when `/etc/default/inngest-luks` is absent, then systemd reports a skipped start (`is-active` → `inactive`), no `Failed to start` row, and the ARM-FAILED marker still fires — `unit` (journald evidence from run 38031062344 is the fixture shape; suite asserts the directives).
- Given `inngest-luks-cutover.timer` activated while `/etc/default/inngest-luks-volumes` is absent, when `enable --now` runs, then the timer is enabled but inactive — zero service starts, zero tick-spam — and it activates normally on a later boot once the file exists — `unit`.
- Given a healthy provision (all env files staged), when the timer elapses, then `inngest-luks-cutover.service` starts normally and emits `unit-exit` with `service_result=success` — `integration` (the existing prod rows already show this shape; the suite pins the directive text).
- Given the capture script and a stubbed host-row set containing `Failed to start inngest-luks-cutover.service`, when run in phase-b/post-reboot mode, then it exits FAIL (`viol`) — `unit` (BETTERSTACK_QUERY_SH stub arm in the capture suite).
- Given the same fixture without the forbidden row, when run, then the mode's existing verdict logic is unchanged — `unit` (must-PASS control arm).
- Verification after delivery: `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-assert-absence.sh --host soleur-inngest-prd --absence 'Failed to start inngest-luks' --control SOLEUR_INNGEST_LUKS_CUTOVER --since 6h` → prints `SOLEUR_ABSENCE_ASSERT outcome=clean`; and the next rehearsal's evidence artifact carries `REHEARSAL_PHASE_B_RECOVERY=PASS` + `REHEARSAL_POST_REBOOT_LATCH=PASS` with the new forbidden rule enforced — `e2e`, pyramid-justified: the property is provision-time boot ordering on a real host; no lower layer reaches systemd-on-first-boot.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change on a no-SSH scheduler host. Mechanical UI-surface scan: no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in the file lists → Product tier is NONE by the file-driven check as well. No brainstorm-recommended specialists (no brainstorm ran).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (88 issues) contains no body reference to any planned file path.

## Research Insights

- **Issue fetch:** #9939 OPEN, `chore(infra)` title, labels `priority/p3-low`, `type/chore`, `domain/engineering`, `meta/machinery`. Cited refs #9175 (rehearsal, CLOSED), #6894 (LUKS cutover trio, CLOSED), #7695 (reopen unit, CLOSED via #8314) — all historical context, none stale.
- **Premise Validation:** all cited files exist on `origin/main` (`inngest-luks-cutover.service`, `cloud-init-inngest.yml`, `inngest-bootstrap.sh`). Proposed mechanism (`ExecCondition=`/`ConditionPathExists=`) checked against the ADR corpus: ADR-257 already established `ConditionPathExists=!` as the repo's latch idiom on `soleur-inngest-provision.service`; no ADR rejects the pattern. ADR-142 (the LUKS cutover) and ADR-279 (the rehearsal) are the domain precedents. The `-` tolerant prefix is the *deliberately rejected* shape (issue + sibling-host contrast: git-data/workspaces reopen units chose `EnvironmentFile=-` with in-script failure; inngest documents fail-closed at cloud-init-inngest.yml:113).
- **Property List (0.6b):** (1) zero `Failed to start` rows for the two units on a fresh provision; (2) fail-closed `EnvironmentFile=` retained for legitimate starts; (3) no `unit-exit` phone-home noise for units that never should have started; (4) the fix is ordering/enablement — no start attempted before the writer can have run, and none after the writer definitively cannot have run (stage abort).
- **Cut List:** none — all three candidate shapes buy the same property and none is covered by an existing mechanism.
- **Journal evidence (Better Stack, queried via scripts/betterstack-query.sh):** run 38031062344's host — `inngest-luks-FAILED stage=privilege rc=1` → `Failed to start inngest-luks-open.service` (the `enable --now` arm) → `Failed to load environment files`/`Failed with result 'resources'`/`Failed to start inngest-luks-cutover.service` every ~31 s until teardown. Run 38036022367's host — the same channel clean (write-then-enable held). The issue's hypothesized "dependency pull-in" does not exist statically; the real triggers are the runcmd arm under abort-cascade and the bootstrap-armed timer.
- **Measured systemd semantics (261, user-unit harness):** condition-failed `systemctl start`/`enable --now` → rc 0, `is-active` → `inactive`, `is-enabled` → `enabled`, one NOTICE "skipped, unmet condition check" journal row, `ExecStopPost` never runs.
- **Delivery chain:** `inngest-luks-cutover.{service,timer}` are `cp`-staged carriers in `build-inngest-bootstrap-image.yml:371-373` → image `ENTRYPOINT` copies to `/tmp` → `inngest-bootstrap.sh` installs to `/etc/systemd/system`. Carrier edits auto-mint `vinngest-v*` on merge (`mint-inngest-bootstrap-tag.yml`), the build+sign publishes, `bump-cloud-init-pin` rewrites `IREF`/`ZIREF`. `cloud-init-inngest.yml` is a `user_data` carrier for `hcloud_server.inngest` → replace-on-apply. `deploy-script-tests` GuardA is advisory and binds tag↔HEAD byte-identity (reconciles post-merge).
- **runcmd semantics:** items share one shell; a FATAL inside `doppler run … bash -s` exits the child only (later items continue — observed: `enable --now` ran after the stage abort); a bare `exit` in a plain `|` item (the two charset write-guards) aborts the remainder by design.
- **Verification vehicle:** `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` has a `viol()` forbidden-marker path and a `BETTERSTACK_QUERY_SH` test seam with fixture-driven arms — the natural home for the acceptance check. `scripts/betterstack-assert-absence.sh` is the ad-hoc probe (exit vocabulary: clean/unshipping/present/unknown; `SOLEUR_ABSENCE_ASSERT` verdict line).
- **Institutional learnings applied:** `2026-10-06-which-files-feed-user-data-…` (cloud-init edits = host replace; image-baked carriers need the tag/pin chain); the T1.1/G4.f asserts in `inngest-redis-luks.test.sh` record the 2026-09-17 `ARM-FAILED` history — the `is-active` check must remain the marker's driver.

## Context

Host: `soleur-inngest-prd` (no-SSH dedicated scheduler). systemd 255 on host; condition semantics measured identical on 261. The failing run's LUKS-stage `privilege` abort was itself a separate defect (rehearsal attempt-3, since remediated — run 38036022367 passed); this plan fixes the *downstream* contract the issue targets regardless of which stage failure produces an absent env file.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- `ConditionPathExists=` on the timer is evaluated at activation, not per-elapse — do not write asserts or prose claiming per-tick re-evaluation.
- `enable --now` on a condition-failed unit exits rc 0 — do not "harden" the runcmd/bootstrap calls with rc checks that assume otherwise; `is-active` is the verdict.
- Do not prefix the `EnvironmentFile=` lines with `-`: the fail-closed contract is the whole point of the units.
- The capture script's needles must match the systemd journal message text (`Failed to start inngest-luks`), not a `stage=` field shape — these rows are journald/systemd, not phone-home markers.
- `inngest-luks-cutover.service`'s mount-namespace contract (`PrivateMounts=no` comment block) is load-bearing and unrelated — do not touch the `[Service]` sandboxing while adding `[Unit]` conditions.
- GuardA drift is expected mid-pipeline for carrier edits; it is advisory and reconciles at the pin bump — never "fix" it by reverting carriers or by bumping the pin to an unbuilt tag.
- The `discoverability_test` carries `credentials_required`, so `BASELINE_DECLARED_PROBES` (53 → 54) must be bumped in the same PR — a `LEFTHOOK_EXCLUDE=bun-test` commit path defers the red by exactly one commit.
- Issue closes by `Ref #9939` + post-merge evidence, not `Closes`: the acceptance is a fresh provision's journal, and the close keyword at merge would falsify state before the rehearsal or next replace produces it (the #9175 plan's `closes: []` disposition for the identical evidence shape).

## References

- Issue: #9939; refs #9175, #6894, #7695, #8562
- ADRs: ADR-257 (latched provision unit / ConditionPathExists idiom), ADR-142 (inngest LUKS cutover), ADR-279 (forced-race rehearsal), ADR-225 (latched-flag control channel)
- Journal evidence: Better Stack `soleur-inngest-vector-prd`, hosts `soleur-inngest-rehearsal-38031062344` (failure shape, 2026-10-10 06:30–06:54 UTC) and `soleur-inngest-rehearsal-38036022367` (clean shape)
- Learning: `knowledge-base/project/learnings/test-failures/2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md`
