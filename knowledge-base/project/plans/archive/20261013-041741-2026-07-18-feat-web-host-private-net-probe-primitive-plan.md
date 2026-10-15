---
title: "Web-host private-net probe primitive (off-host L3 §1 + git-data + §3 NIC guard)"
type: feat
issues: [6438, 6548]
parent_vehicle: 5274
branch: feat-off-host-l3-probe-6438
pr: 6654
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-18-off-host-l3-probe-brainstorm.md
spec: knowledge-base/project/specs/feat-off-host-l3-probe-6438/spec.md
date: 2026-07-18
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# Plan: Web-host private-net probe primitive

## Overview

Build the web-host private-net probe primitive (the `#5274 PR C` vehicle) that closes three tracked gaps sharing one delivery substrate:

- **#6438 §1** — a consumer-perspective ("L3") probe: the web host verifies it can actually **serve an image** from the zot registry (`10.0.1.30`) over the private NIC, then pings a heartbeat so absence alarms. Closes the gap that L1/L2 (#6415/ADR-115) + #6540 (registry self-ping) structurally cannot see: "the private net is broken from a *consumer's* perspective while the registry thinks its own NIC is fine."
- **#6548** — the same, for git-data (`10.0.1.20`, SSH), a fail-soft overlay.
- **#6438 §3** — the ADR-115 on-host private-NIC self-convergence guard extended to the web host(s).

The whole point is honesty: the failure this class prevents (#6400) is a silent-for-14-days degradation where every health signal stayed green. A probe that ships GREEN-but-inert is that failure, reproduced. ADR-117's executable-`feeder` CI guard is the no-green-AC gate, and this plan's acceptance is a **measured real beat**, never a passing unit test.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| Web hosts **plural** (web-1 `10.0.1.10` + web-2 `10.0.1.11`); per-host heartbeats to avoid masking | **web-2 retired 2026-07-17 (#6538/#6463); fleet is single-host.** `var.web_hosts` defaults to `web-1` only (`variables.tf:108-110`, "Do NOT re-add a key here"); commit `6aa3afe75` removed web-2 ledger rows post-destroy | Use **`for_each = var.web_hosts`** for the heartbeat + URL secret — one live beat today, anti-masking preserved *by construction* for future active-active-N (#6459). No hardcoded web-2 resource (would be a dead feeder → parity-test RED). |
| Blocker #2 (arming) = "replay #6540/ADR-117" | The **decision** (measure-then-arm, fail-loud on timeout) is already **ADR-117** (its "Corrected 2026-07-16" section documents the exact PATCH→poll→fail-loud sequence). Only the *runtime call site* is absent — the apply workflow's Better Stack lookup is read-only/non-gating. A write-token-in-CI precedent already exists: `inngest-arm-write-token.tf` (injected only under `op=='arm'`). | The arm gate is **ADR-117 automated**, not net-new: move the PATCH into the apply workflow, **op/state-gated** (act only when `paused==true` / on `triggers_replace`), via a **dedicated Doppler service token** over the existing global Better Stack provider token. **Amend ADR-117**, don't author a sibling ADR. |
| Delivery = bake + `ci-deploy.sh` re-seed | `ci-deploy.sh` re-seed copies plugin **files** into a bind mount (`:2331-2355`); it installs **no** host systemd units. Bake-only never reaches web-1 (cx33 unrebuildable, `ignore_changes=[user_data]` `server.tf:266`; C4 `model.c4:182` "the bake reaches no live host") | web-1 arming = a **new SSH `terraform_data` provisioner** modeled on `terraform_data.disk_monitor_install` (`server.tf:278-310`) that heredocs `.service`+`.timer` → `/etc/systemd/system` → `systemctl enable --now`. |
| §3 = ADR-115 guard incl. reboot | ADR-115 reboot was for the single-active registry + lease coordinator; the apply workflow states a web-1 reboot **"would power-off the sole live origin"** (`apply-web-platform-infra.yml:878`) | §3 on web hosts = **detect + emit + alarm, NO auto-reboot** (documented divergence from ADR-115; amend the ADR). |
| Probe `/v2/` 200/401 = alive | Proves the auth gate answers, **not** that the store serves. A zot with a detached/empty store (region-migrate) returns 401 while real pulls 404 → silent GHCR fallback = #6400 *inside* the probe | Probe a **real repository path** (HEAD a known manifest / `GET /v2/<repo>/tags/list` → 200), not the bare auth gate. |

## User-Brand Impact

**If this lands broken, the user experiences:** the web host silently loses its private-net path to zot, image pulls fall back to GHCR (or fail), deploys degrade, and every health signal stays green — the operator's product silently rots for days (the #6400 shape).

**If this leaks, the user's workflow is exposed via:** N/A — the beat payload is fleet metadata (up/down, timestamp, monitor id) to Better Stack, an existing sub-processor. CLO cleared: no PII in the beat or escalation webhook, no new data-residency/DPA surface.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true` — CPO reviewed the approach at brainstorm (carry-forward); `user-impact-reviewer` runs at PR review.

**Self-referential risk:** the primitive is itself a monitor that can go inert (web-1 dark behind a GREEN manifest). The measured-beat arm gate is the brand-critical AC — a half-armed probe reads as coverage while providing none (ADR-117), worse than none.

## Implementation Phases

### Phase A — Delivery substrate + §3 NIC guard (proves the rail)

Front-loaded per CPO ("prove the rail is read before speculative consumer beats arm") — and, per P2-14, **A must exercise the exact web-1 re-seed + measured-beat + unpause path** or the de-risking is hollow.

- **A1. §3 NIC self-convergence guard (detect + emit, NO reboot on web hosts).** Port `soleur-private-nic-guard.sh` (`cloud-init-registry.yml:412-651`) into web `cloud-init.yml` (Terraform-baked) with per-host `EXPECTED_IP='${private_ip}'` (from `var.web_hosts[each.key].private_ip`, never a literal). **Disable the auto-reboot *action* on web hosts** (P0-4) — emit `SOLEUR_PRIVATE_NIC` + alarm; do not power-cycle the sole origin (`apply.yml:878`). Doppler context `--project soleur --config prd`. Baked in cloud-init = future fresh hosts self-report at boot.
- **A2. §3 liveness heartbeat (created explicitly) + web-1 delivery via the SSH `terraform_data` provisioner.** Create a **dedicated** `betteruptime_heartbeat.web_nic_guard` (`for_each = var.web_hosts`) + its `doppler_secret` URL — the §3 guard pings it every healthy run so the fault-emitter is observable-when-healthy (architecture P2-F: a `SOLEUR_PRIVATE_NIC` emit that never fires is indistinguishable from "guard dead"; **permanent, not scaffolding**; NOT subsumed by the zot beat — independent unit/failure-domain, folding would re-introduce OR-masking). New `terraform_data.private_nic_guard_install` (mirror `disk_monitor_install` `server.tf:278-310`, hardcoded `web["web-1"]`) ships the guard + the systemd unit-activation via the provisioner's `remote-exec` onto running web-1 (which cloud-init can never reach), exercising the whole delivery+arm rail before any consumer probe.
- **A3. The arm gate (ADR-117 automated — build once, reuse in B/C).** A step the apply workflow invokes that: reads a **dedicated Doppler service token** (`doppler_service_token`, mirroring `inngest-arm-write-token.tf`) exposing only the arm secret over the existing global Better Stack provider token (P2-E: Better Stack tokens are account-wide R+W — the *only* scoping axis is Doppler; record the account-wide blast radius in the ADR). **Op/state-gated, NOT every-apply** (P1-B): run the measure→PATCH cycle only when the target monitor is live-`paused==true` (`GET /heartbeats/<id>`) or its feeder `terraform_data` was replaced this apply (`triggers_replace`) — so routine re-applies are a true no-op and don't flake on Better Stack blips. Sequence (P0-3 + Kieran freshness): **capture pre-install baseline `T0`** → poll the monitor (resolved by its tfstate `id`/`url`, not a name-regex) for `last_ping_at > T0` within deadline `period+grace` → `PATCH paused=false` **only** on a fresh beat → on timeout **leave paused and fail the apply loud** (no "unavailable"-and-continue). Never gate unpause on the provisioner's exit code (P0-1).
- **A4. Manifest + parity.** Add §3's `web_nic_guard` heartbeat row to `heartbeat-manifest.ts` with `arming:"web-host-cron"`, `paused:true` (matching source), `feeder:{kind:"timer", evidence:{file:"apps/web-platform/infra/server.tf", pattern:"<the provisioner's literal unit-activation line>"}}`. Add its parity-manifest row — do not touch `registry_prd`'s 60/30.
- **A5. Future-host coupling (P1-C, tracked not "by construction").** Bake the consumer-probe scripts (B/C) into `cloud-init.yml` too, so a future fresh host (#6459 active-active-N) self-arms them at boot (the SSH provisioner is the web-1-unrebuildable *exception*, not the only path). Make the arm gate iterate `var.web_hosts`. Note the `apply.yml:456` new-host-HALT coupling: adding a host to `var.web_hosts` needs a create-dispatch + arm-gate coverage, or every subsequent merge halts. Tracked as a #6459 dependency.

### Phase B — zot consumer probe (#6438 §1)

- **B1. Probe script (AUTHENTICATED serviceability, Kieran P1 + P1-7).** zot runs `defaultPolicy:[]` — an **anonymous** request gets `401` on *every* path including a real repo path (auth is enforced before the repo lookup, `cloud-init-registry.yml:341-345`). So the probe MUST present the zot htpasswd Basic auth (`ZUSER`/`ZTOK`, already on-host for `docker login` at `cloud-init.yml:513`): `curl -s -u "$ZUSER:$ZTOK" -o /dev/null -w '%{http_code}' -m 10` HEAD a **known manifest** (`http://10.0.1.30:5000/v2/<repo>/manifests/<tag>`). Classify: `200` = servable (ping), `404` = store empty/detached = the #6400-inside-the-probe case (suppress ping → alarm), `401` = **auth broke, HARD failure** (not "alive"), `5xx` wedged, `000` unreachable. **No `curl -f`.** Add `ZUSER`/`ZTOK` to the probe unit env + the secrets list.
- **B2. Per-host heartbeat + URL secret (`for_each = var.web_hosts`).** New `betteruptime_heartbeat.web_zot_consumer` (`period=180`, `grace=60`, `email=true`, `policy_id = var.betterstack_paid_tier ? …[0].id : null`, `paused=true`, `ignore_changes=[paused]`) + `doppler_secret.web_zot_consumer_url` (masked). Mirror `git_data_prd` shape (`git-data.tf:243-286`).
- **B3. Delete the reserved secret (Q3/TR5).** Remove `doppler_secret.zot_heartbeat_url_prd` (`zot-registry.tf:511-517`) + its stale reservation comment (`:498-510`) — the comment itself prescribes deletion. Lands here (the phase that mints the replacement), never stranded.
- **B4. Deliver + arm (atomic with the manifest row, P1-13).** New `terraform_data.zot_consumer_probe_install` (SSH provisioner) heredocs the timer (`OnUnitActiveSec=60s`, `AccuracySec=1s`) + script reading `$WEB_ZOT_PROBE_URL_*`; add the manifest row **with its feeder evidence in the same phase**; run the A3 arm gate against web-1's monitor.

### Phase C — git-data consumer probe (#6548)

- **C1. Probe (SSH reachability, Q2/P2-11).** Connect-and-close to `10.0.1.20:22` (bounded `nc -z` / `ssh -o BatchMode -o ConnectTimeout` no-auth), ping on success. git transport is ED25519 SSH (`git-data.tf:29-40`).
- **C1b. Serviceability asymmetry (Kieran P2 — named, not hidden).** A TCP connect proves the port is open, not that git transport serves — the same reachability-vs-serviceability gap the plan rejects for zot. The existing `git-data.tf:270-273` TODO prescribes `git ls-remote` (a real transport check). Because git-data is fail-soft, connect-and-close is an **accepted** tradeoff for v1 — but state it explicitly; upgrade to `git ls-remote` if a port-open-but-wedged git-data is observed.
- **C2. Arm the existing `git_data_prd`, page only on a *sustained* break (P1-6).** git-data is fail-soft (`ensure-workspace-repo.ts:332` "an OVERLAY, not a hard dependency"). Relax grace (`git-data.tf:246` `30 → 180`) so a single transient blip does not page; the beat pings via `$GIT_DATA_HEARTBEAT_URL`. Flip the `git_data_prd` manifest row (`heartbeat-manifest.ts:152-153` feeder block) from `feeder:{kind:"none",…}` to `{kind:"timer",evidence:{…}}` and reconcile the "still unfed by BOTH routes" tripwire (`heartbeat-reprovision-parity.test.ts:413`) in the same phase.
- **C3. Cardinality note.** Single-host makes git-data's shared beat masking-moot; if a future host lands, give git-data `for_each` too for consistency (tracked, not built now).

## Files to Edit

- `apps/web-platform/infra/server.tf` — new `terraform_data` SSH provisioners (§3 guard install, zot probe install, git-data probe install); `-target` inclusion in `apply-web-platform-infra.yml`.
- `apps/web-platform/infra/cloud-init.yml` — §3 NIC guard (detect+emit, no reboot), baked for future hosts.
- `apps/web-platform/infra/zot-registry.tf` — delete `zot_heartbeat_url_prd` + stale comment; new `web_zot_consumer` + `web_nic_guard` (§3) heartbeats + URL secrets (`for_each = var.web_hosts`) (or a new `web-probe.tf`).
- `apps/web-platform/infra/git-data.tf` — relax `git_data_prd` grace (`:246`); the probe reads existing `GIT_DATA_HEARTBEAT_URL`.
- `apps/web-platform/infra/<new> web-arm-write-token.tf` — a `doppler_service_token` exposing only the arm secret over the existing Better Stack provider token (mirror `inngest-arm-write-token.tf`). No new operator-mint var (`hr-tf-variable-no-operator-mint-default`) — reuses the existing global BS token.
- `.github/workflows/apply-web-platform-infra.yml` — the arm gate (measure→PATCH unpause, write-scoped token, fail-loud); `-target` list additions.
- `plugins/soleur/lib/heartbeat-manifest.ts` — new §3 + zot rows; flip `git_data_prd` row.
- `plugins/soleur/test/heartbeat-reprovision-parity.test.ts` — new parity rows; reconcile the `git_data_prd` "unfed" tripwire.
- `knowledge-base/engineering/architecture/decisions/ADR-115-*.md` (amend) + a new ADR (arm-gate pattern); `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4}`.

## Files to Create

- `apps/web-platform/infra/web-probe.tf` (optional grouping) · probe/guard scripts if not inline-heredoc'd · a new ADR file.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

(Full terraform-architect output — reconciled to single-host.) All delivery is IaC/CI; no manual operator step. The `systemctl enable --now` reference below is the literal line the `terraform_data` SSH provisioner runs in CI (parity-test evidence anchor), not a human step.

<!-- lint-infra-ignore start: IaC delivery description — the terraform_data/SSH provisioner + no-reboot apply path run in CI, not by a human; prescribes no human step -->
- **Terraform changes:** delete `zot_heartbeat_url_prd`; new `betteruptime_heartbeat.web_zot_consumer` + `doppler_secret.web_zot_consumer_url` (both `for_each = var.web_hosts`, free-tier shape, `paused=true`, `ignore_changes=[paused]`, `policy_id` ternary); relax `git_data_prd` grace; new `terraform_data.*_install` SSH provisioners for web-1; §3 guard in `cloud-init.yml`. Providers `betteruptime`/`doppler` already present — no new credential except an optional write-scoped Better Stack token (Doppler `prd_terraform`, no operator-mint default).
- **Apply path:** cloud-init bake (§3 for future hosts) **+** SSH `terraform_data` provisioner (the sole path that arms running web-1 — `ci-deploy.sh` re-seed installs no host units, verified `:2331-2355`). Pure `+ create` provisioners → no reboot; ride the `-target` list (`server.tf:640-644`).
- **Distinctness / drift:** `ignore_changes=[user_data]` (`server.tf:266`) is why cloud-init can't arm web-1; heartbeat URL is a masked routing token in tfstate (same class as existing beats); every new heartbeat REQUIRES a matching manifest row (parity test line 365) with `paused` matching source + executable feeder; interpolate `EXPECTED_IP` per-host.
- **Vendor-tier reality check:** free-tier heartbeats are creatable (unconditional in-repo; only `betteruptime_policy`/`_monitor` are `count`-gated); free-tier monitor cap = 10, heartbeats don't count. `betterstack_paid_tier` stays `false` (email-only; #6549 item 1 owns paid-tier). Verify current pricing at the provider page before budget decisions.
- **Highest-risk item:** web-1 arming delivery (P0) — the SSH `terraform_data` provisioner is the only path; the manifest `feeder.evidence.pattern` must point at its literal `systemctl enable --now` line so the parity guard proves the beat is real.

<!-- lint-infra-ignore end -->

## Observability

```yaml
liveness_signal:
  what: per-host zot-consumer heartbeat (serviceability probe) + §3 NIC-guard liveness beat + git_data_prd
  cadence: systemd timer OnUnitActiveSec=60s; heartbeat period 180 / grace 60 (git-data grace relaxed to 180)
  alert_target: Better Stack heartbeat absence → email (paid-tier escalation deferred to #6549 item 1)
  configured_in: apps/web-platform/infra/{zot-registry,git-data,server}.tf + heartbeat-manifest.ts
error_reporting:
  destination: Better Stack Logs (SOLEUR_PRIVATE_NIC event via the §3 guard) + heartbeat absence
  fail_loud: yes — the arm gate PATCHes unpause only on a fresh measured beat; on timeout it leaves paused and FAILS the apply (no swallow)
failure_modes:
  - {mode: "web-1 loses private route to zot (steady-state)", detection: "web-1 zot-consumer heartbeat absence (in-surface: the probe runs ON web-1)", alert_route: "Better Stack email"}
  - {mode: "zot up but store empty/detached (serviceability)", detection: "probe HEADs a real manifest, not bare /v2/ — 404 on the repo path suppresses the ping", alert_route: "heartbeat absence"}
  - {mode: "web-1 probe unit never installed (inert-monitor trap)", detection: "arm gate polls web-1's specific monitor for a FRESH beat; no beat → apply fails loud, monitor stays paused (never green-but-inert)", alert_route: "CI apply failure"}
  - {mode: "web host boots NIC-less (future fresh host)", detection: "§3 guard SOLEUR_PRIVATE_NIC emit at boot (no auto-reboot on web hosts)", alert_route: "Better Stack Logs alarm"}
  - {mode: "git-data unreachable (fail-soft)", detection: "git_data_prd absence, paged only on a sustained (multi-window) break", alert_route: "Better Stack email"}
logs:
  where: Better Stack Logs source 2457081 — SOLEUR_PRIVATE_NIC (direct curl) AND each probe unit's fault-classification stderr, shipped via Vector Source 4 host_scripts_journald under per-unit SyslogIdentifier= (web-zot-consumer-probe / web-git-data-probe / web-nic-guard; #6556 off-box lesson, hr-no-ssh-fallback)
  retention: per existing Better Stack Logs retention
discoverability_test:
  command: "curl -sS -H 'Authorization: Bearer $TOKEN' https://uptime.betterstack.com/api/v2/heartbeats | jq '.data[] | select(.attributes.name|test(\"zot-consumer|private-nic\"))'"
  expected_output: "the web-1 heartbeats present with status up/paused as expected — NO ssh"
```

**2.9.2 affected-surface (web-1 is a semi-blind host):** the probe emits FROM web-1 (in-surface), and the §3 `SOLEUR_PRIVATE_NIC` event carries structured fields discriminating NIC-absent vs path-broken vs serviceability — not a single boolean.

**2.9.1 soak follow-through:** the "monitor stays armed and green after the measured beat" is a post-deploy soak close-criterion → enroll a follow-through probe (`scripts/followthroughs/l3-probe-armed-6438.sh`, exit 0 while the beat holds; `<!-- soleur:followthrough … -->` directive + `follow-through` label) so the closure is automated, not left to memory.

## Architecture Decision (ADR/C4)

- **### ADR (new — §3, do NOT amend ADR-115):** a **new** ADR "web-host private-NIC self-report (no self-converge)" (architecture P2-D). ADR-115 is deliberately REGISTRY-only and its two normative reboot-blockers *earn* self-reboot authority for one host; the web-host variant makes a *structurally different* decision (detect + emit + alarm, **no reboot** — the registry's reboot would power-off the sole live origin, `apply.yml:878`). A new ADR **cites** ADR-115's reboot-blockers as the *reason* web hosts don't reboot, rather than diluting ADR-115's narrow scope. Provisional ordinal — `/ship` re-verifies against `origin/main`.
- **### ADR (amend ADR-117, NOT a new pattern ADR):** ADR-117 already owns the measure-then-arm decision (its "Corrected 2026-07-16" section has the exact PATCH→poll→fail-loud sequence). Amend it to record the **automation** delta only: the PATCH moves into the apply workflow, **op/state-gated** (P1-B), via a **dedicated Doppler service token** over the account-wide Better Stack provider token — and record that token's account-wide blast radius honestly in the risk section (P2-E). A sibling arm-gate ADR would fragment the invariant across two docs (architecture P1-A + simplicity).
- **### C4 views:** Container — add the **web-host → zot / git-data private-net consumer-probe edges** and the new heartbeats to the Better Stack element description (`model.c4:268` currently says git-data's beat is unfed and registry-liveness paused — update both). The `SOLEUR_PRIVATE_NIC` edge exists (`model.c4:423`); extend it to the web-host source. Run `c4-code-syntax.test.ts` + `c4-render.test.ts` after editing. (Checked all three `.c4` files: the external systems — Better Stack, zot, git-data — are already modeled; the new elements are the *edges* + heartbeat descriptions, which are in-scope tasks here.)

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`).

### Engineering (CTO + platform-strategist)
**Status:** reviewed. **Assessment:** L3 closes a real residual gap over #6540; caught the reused-heartbeat masking trap; delivery via SSH `terraform_data` provisioner is the sole web-1 path; email-only escalation; small–medium once single-host simplifies cardinality.

### Product (CPO)
**Status:** reviewed. **Assessment:** flagged L3's inert-monitor risk + that it does not close #6400's literal shape; reconciled by front-loading §3/substrate (Phase A proves the rail) and deferring the speculative consumer beats behind it. Single-host further reduces §3's immediate value (web-1 already booted/unrebuildable) → §3 is mostly future-host value.

### Legal (CLO)
**Status:** reviewed. **Assessment:** no legal threshold — internal telemetry, existing sub-processor, no PII. A future paid-tier move is a `hr-record-recurring-vendor-expense` finance/ops item.

### Product/UX Gate
**Tier:** none — no UI surface (all Files to Edit are `.tf`/`.sh`/`.ts`/`.yml`/`.c4`; mechanical UI-surface override does not fire).

## Acceptance Criteria

### Pre-merge (PR)
- **AC1.** The zot probe presents Basic auth (`ZUSER:ZTOK`) and HEADs a **known manifest** (not bare `/v2/`); a unit/integration test proves it pings on `200`, suppresses on `404`/`5xx`/`000`, and treats `401` as a **hard failure** (models `-u`/`-w`/`-m`; re-introducing `-f` or dropping `-u` fails behaviorally).
- **AC2.** `heartbeat-manifest.ts` + parity test are green **because** every new row is honestly fed (executable `feeder` evidence pointing at the provisioner's literal unit-activation line) — never `feeder:none` deferred to a later phase; the row and its feeder evidence land in the **same** phase (P1-13). The `git_data_prd` "still unfed" tripwire is reconciled in Phase C's commit.
- **AC3.** The arm gate is **gating and freshness-correct**: capture `T0`, PATCH `paused=false` only when a beat with `last_ping_at > T0` arrives within `period+grace`; on timeout leave paused and **fail the apply**. Grep is **scoped to the arm-step block** (the read-only "Best-effort heartbeat status" steps at `apply.yml:1967,2181` legitimately contain "unavailable" — a whole-file grep can't distinguish).
- **AC4.** §3 on web hosts performs **no reboot action** — assert the reboot *invocation path* (`reboot`/`$REBOOT_BIN` / `CONVERGED_BY=reboot` execution) is absent, NOT a bare `grep reboot == 0` (the `SOLEUR_PRIVATE_NIC` emit carries `reboot_count=` and comments mention reboot; a token grep false-fails a correct detect-only port). The new §3 ADR documents the divergence.
- **AC5.** `terraform plan` shows the new resources as `+ create`, **exactly 1 to destroy** (the reserved `zot_heartbeat_url_prd`, expected — B3) plus the `git_data_prd` in-place grace update, and **no `hcloud_server.web` replacement/reboot**; the new provisioners ride the `-target` list.
- **AC6.** New §3 ADR authored + ADR-117 amended + `.c4` edited (web-host consumer + §3 edges; `model.c4:268` git-data-unfed / registry-paused descriptions updated); `c4-code-syntax.test.ts` + `c4-render.test.ts` green.

### Post-merge (operator / automated)
- **AC7.** After apply, `betterstack-query.sh` (self-pulled, no dashboard) shows web-1's zot-consumer + §3 heartbeats `up` (a real measured beat), git_data_prd `up`. The follow-through probe is enrolled and green over the soak window.

## Open Questions (resolved — recorded for review)

Q1 → `for_each var.web_hosts` (single beat now, anti-masking by construction later). Q2 → SSH connect-and-close to `:22`. Q3 → delete reserved secret. Q4 → `web-host-cron`. Q5 → SSH `terraform_data` provisioner (NOT ci-deploy re-seed — corrected). Q6 → detect+emit+alarm, **no reboot** on web hosts. Q7 → A (substrate+§3, proves rail) → B (zot) → C (git-data).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty/placeholder or omits the threshold fails `deepen-plan` Phase 4.6 — this one is filled (single-user incident).
- The arm gate's decision is **ADR-117's** (amend it), but its **runtime call site is new** — do not "reuse" the read-only status lookup at `apply-web-platform-infra.yml` (it swallows errors, returns "unavailable"); build the op/state-gated write path + `T0` fresh-beat poll + fail-loud (P0-3, P1-B).
- Do not replay the luks install precedent's `2>/dev/null || true` on the web-1 provisioner — a swallowed enable-failure during the *paused* window is fully silent (P0-1).
