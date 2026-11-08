---
title: "feat(infra): SOLEUR_HOST_KERNEL marker + stale-kernel alert on every prod host"
type: feat
date: 2026-11-08
slug: host-kernel-marker-stale-kernel-alert
branch: feat-one-shot-12007-host-kernel-marker
issue: 12007
closes: 12007
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat(infra): SOLEUR_HOST_KERNEL marker + stale-kernel alert on every prod host

## Enhancement Summary

**Deepened on:** 2026-11-08. **Passes:** repo research, learnings research, two CTO ruling rounds (18 forks), terraform-architect review of the IaC section, plan-review panel (DHH, Kieran, code-simplicity, CTO devex), deepen-plan gates 4.5, 4.55, 4.6, 4.7, 4.10-4.13.

### Key improvements
1. The alert is a per-host dead-man heartbeat with a literal 36 h beat window, not a native alert (the 900 s `query_period` ceiling makes a native alert blind to this cadence).
2. Merge-time behavior is stated, not implied: a merge creates the four heartbeats paused and re-delivers `vector.toml` through the standing provisioners, but the web installers are held via the exclusion list by default; the inngest and registry hosts are never in a per-merge target.
3. Verified defects fixed from review: the feeder's `$`-refusal, the existing loop-equals-`TARGETS` pin, the heartbeat `-target` and `want_res` wiring pins, the image-bake `.dockerignore`/Dockerfile sites, the `W2_ALLOWED` parity set, the vacuous Guard 1 reorder row, the circular arming prerequisite, and the "kernel blanked unless observed" rule in `classify_host`.
4. Plain unit files replaced the systemd template.

### New considerations discovered
- Pending ForceNew drift on the registry and inngest hosts shows in untargeted plans and the drift detector until rollout; the two held `terraform_data` installer creates (`host_kernel_marker_install`, `host_kernel_marker_install_web2`) also stand as drift on the twice-daily plan until #12386.
- Planned replaces of those hosts go dark for up to the 36 h window, so the runbook pauses their heartbeat first.

Spec lacks a valid `lane:` (no spec.md exists for this branch): defaulted to `cross-domain` (fail-closed).

## Overview

The `soleur:cve-exposure` skill (#12006, ADR-322) answers "are we subject to CVE-X" from Terraform and Better Stack telemetry.
Today every host kernel resolves to `unknown`: the only kernel row is the failed-deploy diagnostic, and the other hosts report
nothing, so `Affected=no` can never be grounded. This change gives each running prod host a periodic kernel report, ships it
through the log path each host already has, adds a dead-man alert that fires when a host stops reporting, and teaches
`host-state.sh` to call a kernel `observed` only from a periodic report at most 48 hours old.

Hosts in scope: web-1, web-2, the inngest host and the registry. The git-data host (own Logs source) is tracked in #12385;
grok-dogfood is default-off with no shipper and is an explicit census exemption. Delivery to running hosts, the host
re-provision and arming the heartbeats are held steps (#12386); this run changes nothing in production and opens no host connection.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured on this branch) | Plan response |
|---|---|---|
| "ships through the Vector allowlist" for every host | Vector runs only on web-1, web-2 and the inngest host. The registry and git-data run no Vector (`cloud-init-registry.yml`, `cloud-init-git-data.yml` say so); grok-dogfood has no shipper. The allowlist is exact-value `SYSLOG_IDENTIFIER` in `vector.toml` `[sources.host_scripts_journald]`. | Journald + allowlist entry for the three Vector hosts; the registry reuses its existing direct-POST path; git-data deferred (#12385); grok-dogfood exempt. |
| "Better Stack alert: kernel age or uptime above N days, or reboot-required set for more than N days" | That is a patching-cadence alert (#12008, out of scope). The brief asks for a staleness alert: last report older than the freshness window. | Staleness only; the marker carries `uptime_s` and `reboot_required` so #12008 can alert on them later. |
| "Alert fires in a rehearsal with a lowered threshold" | A native logs alert cannot see sparse rows: `logs-alert-query-period-ceiling.test.sh` caps `query_period` at 900 s (incident 1023423999). The sanctioned pattern is an archive-fed dead-man heartbeat (`scripts/deadman-heartbeat-feeder.sh`). | Feeder targets with a literal 36 h window; the rehearsal is an offline fixture suite (fresh row beats, old row withholds, empty window withholds). The window is never an env knob. |
| "One marker per host per day" | A daily marker leaves one missed run as the only slack inside the 48 h trust window. | Every 6 h (at least one per day holds) plus one row per boot. |
| `host_name` identifies a host | `host_name` is stamped by Vector for journald hosts only. Registry rows have no `host_name` and no `SYSLOG_IDENTIFIER`; identity there is in-message (`host=` mirrors `SOLEUR_ZOT_DISK`). | Two identity rules, pinned in `host-state.sh` and the feeder predicates (Guard 1, Guard 2). |
| web-1 can be re-provisioned like the others | `heartbeat-manifest.ts` records web-1 as unrebuildable (never re-runs cloud-init); only a `terraform_data` provisioner reaches it. | A web-1 provisioner plus web-2 twin (fleet parity rule), applied only on the operator's go-ahead. |
| Editing a host's cloud-init is harmless | `hcloud_server.registry` and `hcloud_server.inngest` carry no `ignore_changes = [user_data]`: a `user_data` edit is ForceNew on the next apply. | Work phase confirms the apply path does not replace either host on a routine merge apply (pre-merge AC) and states the gate in the PR. |

## Research Insights

**Premise validation (Phase 0.6).** #12007 is OPEN; #12006 CLOSED (skill live); #12008 and #12348 OPEN and out of scope. `SOLEUR_HOST_KERNEL`
appears on `origin/main` only in the 2026-11-03 learning and the archived cve-exposure plan (no emitter exists). PR #12379 is this
branch's own draft; the foreign `test-all.sh` processes belong to an unrelated worktree. The ADR corpus (ADR-322 decisions 5 and 6,
ADR-286, ADR-197, ADR-192) was read: nothing there rejects a periodic marker; ADR-322 decision 6 explicitly waits for it.

**Property List (Phase 0.6b).**

1. While it is up, every running prod host that can ship logs reports its running kernel to Better Stack about every 6 hours and shortly after each boot (the registry's report is cron-driven and does not replay a missed slot).
2. A report is readable without SSH (`scripts/betterstack-query.sh --grep SOLEUR_HOST_KERNEL`).
3. A host that stops reporting is detected before the 48 h trust window ends.
4. `host-state.sh` prints `kernel_state=observed` only for a valid periodic report at most 48 h old, attributed to the right host.
5. No durable or public artifact carries a version, host, kernel string or "not affected" wording.
6. Fresh hosts get the emitter from `terraform apply`; running hosts only by a held, separately approved step.

**Cut List (Phase 0.6b).** Native `logtail_exploration_alert` -> property 3 -> covered by the dead-man feeder pattern (the ceiling sentinel forbids it). Uptime /
reboot-age / kernel-age alert -> patching cadence -> #12008. Per-class emitters -> property 1 -> one shared collector covers it. One aggregate heartbeat ->
property 3 per host -> an aggregate hides a dead host behind a live one. New ADR -> property 4 -> an amendment to ADR-322 decision 6 covers it. A `--sink post` mode
in the collector -> registry property 1 -> the registry's existing `post()` covers it (no fifth copy of the hand-pinned token judge).

**Institutional learnings applied.** Judge liveness from the timer and the marker row, never from a oneshot service's active state
(2026-06-03 oneshot-inactive learning). Set an explicit `PATH` in the collector (2026-07-15 blind-host learning: `/usr/sbin` is absent under cron). Three states for an
empty read, not one (2026-08-17). Field-isolate on `SYSLOG_IDENTIFIER`, never a bare substring grep (2026-07-18). Pick a new marker name, do not reuse a monitored one
(2026-08-12). A cloud-init edit on a booted host is inert (`ignore_changes`) and `-replace` needs dependent `-target`s (2026-07-07 immutable-redeploy; 2026-07-26).
User-data stays under the Hetzner cap (2026-07-06). Estimate quota for the new allowlist entry (2026-06-10).

**Repo-global ratchets this change touches** (each has an AC below):
`scripts/lib/inngest-probe-row.test.sh` (census allowlists `host-state.sh`; dropping its probe marker makes the entry STALE; a new file naming the probe marker is UNCLASSIFIED),
`scripts/test-affected-kb-consumers.baseline.txt` (a suite that reads a `knowledge-base/` path needs a covering edge or a baseline row; `host-state.test.sh` already has one row),
`scripts/guard-vacuity-floor.test.sh` (derives every `*.test.sh` floor of shape `[[ n -lt N ]]`; `host-state.test.sh` ends with `REAL -lt MIN_CASES`),
`scripts/image-cve-public-claim-guard.test.sh` (tripwire for public-copy claims), `apps/web-platform/test/git-lock-marker-telemetry.test.ts` (walks `SOLEUR_*` sentinels that `skills/*/scripts/*.sh` emit),
`plugins/soleur/lib/heartbeat-manifest.ts` + `heartbeat-reprovision-parity.test.ts` (one row per heartbeat), `apps/web-platform/infra/web-host-provisioner-parity.test.sh` (twin rule),
`plugins/soleur/test/cloud-init-user-data-size.test.ts` and the registry / inngest user-data budget scripts, `betterstack-alert-structure.test.sh`, `lint-orphan-test-suites.sh`.

## Open Code-Review Overlap

2 open scope-outs mention files this plan edits; neither concerns this change.

- #2197 (billing: SubscriptionStatus type) names `server.tf` only incidentally. **Acknowledge:** unrelated concern.
- #10462 (rename the zot fill-rate probe) names `cloud-init-registry.yml`. **Acknowledge:** the registry edit here is additive and does not touch that probe's name; the issue stays open. Its re-evaluation trigger (a commit touching `zot-registry.tf` or `cloud-init-registry.yml` after #10444) fires at this PR; the rename stays deferred because it is orthogonal to the marker.

## Hypotheses

The network-outage gate fired on the word "SSH" and on the new `terraform_data` provisioners (a provisioner makes SSH an apply-time dependency). This plan addresses no
connectivity symptom, so there is nothing to diagnose; the checklist is recorded for the held apply step.

- L3 firewall allow-list vs the applying runner's egress IP: **not verified in this run** (needs a live `hcloud` read and credentials; production reads are out of scope here). The apply workflow's existing pre-apply admin-IP step owns it; the held apply item in #12386 must cite its output.
- L3 DNS / routing: **not verified in this run**, same reason; the provisioners dial by `hcloud_server` address, not by name.
- L7 TLS / proxy: not applicable (SSH, not HTTPS).
- L7 service layer (`sshd`, `fail2ban`): not hypothesized before L3 is verified, per `hr-ssh-diagnosis-verify-firewall`.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

Trigger: the plan adds `terraform_data` resources with `file` / `remote-exec` provisioners (SSH is a hard apply-time dependency). Status by layer, in L3 to L7 order, for the HELD installer apply only (nothing is dialed in this run):

| Layer | Status | Artifact to cite at apply time |
|---|---|---|
| L3 firewall allow-list vs the runner egress IP | not verified here (live read out of scope) | the apply workflow's pre-apply admin-IP step output, pasted into #12386 before the dispatch |
| L3 DNS / routing | not verified here | provisioners dial `hcloud_server` addresses; web-2 goes through the web-1 bastion forward, so a web-1 failure also blocks web-2: apply web-1 first |
| L7 TLS / proxy | not applicable (SSH) | none |
| L7 service (`sshd`, `fail2ban`) | only after L3 is verified | `journalctl` is not used; the Better Stack `sshd` rows (already allowlisted) are the no-SSH read |

## Downtime & Cutover

Trigger: the held rollout replaces `hcloud_server.inngest` (the sole scheduler) and `hcloud_server.registry` (the sole pull path). This PR replaces neither; the section records the default so the owner's window decision starts from the zero-downtime-first answer.

<!-- lint-infra-ignore start: records the held, owner-scheduled replace and its zero-downtime-first default; prescribes no step to run now -->
- **Offline-inducing operations.** Inngest replace: the scheduler is offline for the replace window (exactly-one-scheduler, ADR-100, forbids a parallel second host, so blue-green is unavailable by design). Registry replace: the sole pull path is offline from destroy to a healthy create, with no rollback if the create fails.
- **Zero-downtime evaluation, default first.** (1) Do not schedule a dedicated replace: the emitter is in each host's cloud-init / bootstrap image, so it lands the next time the host is replaced for any other reason; until then that host stays `unknown` in the skill, which is the honest state. (2) Web hosts need no replace at all (provisioner install, no reboot). (3) The ADR-135 signed config-refresh channel delivers host scripts to the inngest host in place, but its refresh set is scripts only and its membership rules exclude units and timers, so it can carry the collector but not the timer that runs it: rejected as a sole path. (4) Registry blue-green is not available (single private-IP host behind a tunnel ingress).
- **Residual downtime** is accepted only if a dedicated window is chosen for either host, which is a schedule decision (operator-only) tracked in #12386 with host-class checkboxes (web first, inngest next, registry last), a stock check beforehand, and the heartbeat paused before the window opens.
- **Per-stage verification and rollback.** Web: first row visible by query, rollback = remove the timer through the same twin installer. Inngest / registry: first row after the replace, NIC check, rollback = the existing replace dispatch's own preflight; no new rollback is introduced by this plan.
<!-- lint-infra-ignore end -->

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A periodic SOLEUR_HOST_KERNEL marker emitted on every prod host (all hosts, not just web)" [brief] | Phase 1 (collector + units), Phase 3 (per-host delivery), Guard 3 census | mapped (git-data -> #12385, grok-dogfood exempt, both with tracked reason) |
| 2 | "shipped through the Vector allowlist" [brief] | Phase 2 (`vector.toml` entry + mirror + tests) | mapped for the three Vector hosts; the registry uses its existing post path |
| 3 | "the marker must be queryable via scripts/betterstack-query.sh" [brief] | Phase 4 runbook section; Observability `discoverability_test`; post-merge query AC | mapped |
| 4 | "A stale-kernel alert: fires when a host's last SOLEUR_HOST_KERNEL report is older than the freshness window" [brief] | Phase 4 (feeder targets, heartbeats, manifest) | mapped |
| 5 | "kernel_state is `observed` only from a periodic report at most 48 h old; anything else stays `unknown`" [brief] | Phase 5 (`host-state.sh`) | mapped; CTO ruling G1 adds `stale` for old evidence, which never grounds `no` |
| 6 | "Keep the producer-contract tests in host-state.test.sh in step with the producer" [brief] | Phase 0 and Phase 5 (producer-contract rows) | mapped |
| 7 | "Mind the repo-global ratchets: kb-consumers baseline, guard-vacuity floors, inngest-probe-row census, and the public-claim guard" [brief] | Phase 6 | mapped |
| 8 | "Fresh-host provisioning must reach the new emitter from terraform apply" [brief] | Phase 3 (cloud-init bake per host class) | mapped |
| 9 | "host config changes follow immutable redeploy" [brief] | Infrastructure (IaC) section, holds list | mapped |
| 10 | "Do NOT apply, reboot or otherwise mutate production in this run" [brief] | Holds list, post-merge ACs | mapped |
| 11 | "Document the query in the betterstack-log-query runbook." [issue #12007] | Phase 4 | mapped |
| 12 | "Alert fires in a rehearsal with a lowered threshold." [issue #12007] | Phase 0 feeder fixture suite | mapped (offline; no production knob) |
| 13 | "Better Stack alert: kernel age or uptime above N days, or reboot-required set for more than N days, per host." [issue #12007] | — | descoped — justification: patching-cadence alert; the brief's out-of-scope list names #12008; the fields are emitted for it |
| 14 | "Out of scope (do not start): kernel patch and reboot cadence (#12008), CVE-id/safe-status lint (#12348), and the dogfood run of the cve-exposure skill." [brief] | — | descoped — justification: stated out of scope |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `apps/web-platform/infra/host-kernel-marker.sh` + plain service and timer | "A periodic SOLEUR_HOST_KERNEL marker emitted on every prod host" | asked |
| Marker fields `uptime_s`, `reboot_required`, `sec_updates` | "`uname -r`, uptime days, `/var/run/reboot-required` present, count of pending security updates, hostname role" [issue #12007] | asked (plan review proposed cutting them; the issue lists them, so they stay: see decision-challenges.md) |
| `vector.toml` allowlist entry and mirror, journald/admission/pii-scrub tests | "shipped through the Vector allowlist" | asked |
| bootstrap bake list, image bake files, cloud-init timer enable | "Fresh-host provisioning must reach the new emitter from terraform apply" | asked |
| web-1 provisioner + web-2 twin | "emitted on every prod host (all hosts, not just web)" and "host config changes follow immutable redeploy" | asked (running hosts; web-1 cannot be re-provisioned) |
| `model.c4` SSH-provisioner count and edge clauses; ADR-322 amendment | "Update host-state.sh (cve-exposure skill helper) to consume the marker" | inferred — justification: the plan skill's Phase 2.10 mandates the ADR and C4 update in the same plan for a decision that changes what ADR-322 decision 6 says, and the derived provisioner count goes stale when two installers are added |
| inngest + registry delivery | "emitted on every prod host (all hosts, not just web)" | asked |
| feeder targets, four paused heartbeats, manifest rows | "A stale-kernel alert: fires when a host's last SOLEUR_HOST_KERNEL report is older than the freshness window" | asked |
| `host-state.sh` marker class, precedence, identity rules | "kernel_state is `observed` only from a periodic report at most 48 h old" | asked |
| `host-state.test.sh` producer-contract rows | "Keep the producer-contract tests in host-state.test.sh in step with the producer" | asked |
| SKILL.md, component-map.md, ADR-322 amendment | "Update host-state.sh (cve-exposure skill helper) to consume the marker" | inferred — justification: the skill text and ADR decision 6 say "which no marker supplies until #12007 ships" and become false the moment this lands |
| `stale` third `kernel_state` value | "anything else stays `unknown`" | inferred — justification: CTO ruling G1; dropping stale evidence to `unknown` makes SKILL.md Step 5's observed-stale branch unreachable and conflates "never seen" with "seen but too old" |
| Guard 3 host census (emitter or tracked exemption per `hcloud_server`) | "emitted on every prod host (all hosts, not just web)" | asked |
| Follow-up issues #12385 (git-data) and #12386 (rollout and arming) | "Do NOT apply, reboot or otherwise mutate production in this run" | inferred — justification: wg-when-deferring-a-capability-create-a requires a tracking issue for each deferral, and `arming_pending` needs an existing issue number |
| Runbook section and arming-runbook edit | "Document the query in the betterstack-log-query runbook." | asked |
| Ratchet updates (baseline, floors, census, shard tsv) | "Mind the repo-global ratchets" | asked |

### Split Assessment

- Subsystems touched: 6 — `apps/web-platform`, `plugins/soleur`, `scripts`, `.github`, `knowledge-base`, `tests`
- Planned files: 41 (4 created, 37 edited) | Estimated changed lines: 1,700 (about 700 of them tests and fixtures)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the pieces are coupled by contracts that a split would leave red: the collector's line format is read by the helper, the feeder predicates and the producer-contract tests, so shipping the emitter without the reader (or the reader without the emitter) leaves the helper's tests asserting a producer that does not exist. Every file is additive or a one-row edit to a census the new rows must join, and no step applies anything. If review wants a seam, the only clean one is "emitter + Vector + delivery" vs "helper + alert + docs", at the cost of the producer-contract rows landing one PR late.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; the operator-facing cve-exposure session output could print a kernel as `observed` that was not, which would make an operator treat a host as patched when it is not (a false all-clear on a security question). The design guards exactly that: stale, forged, mislabeled or missing rows must read `unknown` or `stale`, never `observed`.
- **If this leaks, the user's workflow is exposed via:** a kernel string, uptime and host role in a durable or public artifact (an issue, PR body, commit message, KB page or CI log), which would be a targeting list for an unpatched host. The marker itself lives only in the private Better Stack source; the plan adds no durable artifact that names a version, host or kernel, and the tests use synthesized kernel strings.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** no single user's data is touched and nothing here reaches a customer surface; the exposure is a fleet-wide false all-clear, a pattern across hosts rather than one user's incident. A reviewer who reads a forged-row all-clear as single-user-incident class can raise it; the cost is a CPO sign-off line.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-322 (via `soleur:architecture`), not a new ADR: decision 6 currently says a periodic report "no marker supplies until #12007 ships". The amendment records:
the marker is now supplied by `SOLEUR_HOST_KERNEL v=1` (every 6 h plus per boot) on web-1, web-2, inngest and registry; identity rules (journald hosts by Vector-stamped `host_name` + exact
`SYSLOG_IDENTIFIER`, registry by `role=registry` + `host=<registry host id>`; a journald-path row carrying `host=` is rejected); the third `kernel_state` value `stale` (never grounds `no`); the staleness alert is a
dead-man heartbeat per host with a 36 h literal beat window (about 40 h worst case) rather than a native alert, because the 900 s `query_period` ceiling makes a native alert blind; git-data and grok-dogfood remain `unknown`
by design and by census exemption. Add the rejected alternatives (native alert; aggregate heartbeat; per-class emitters; `--sink post` in the collector) to `## Alternatives Considered`. No new ordinal, so no collision check applies.

### C4 views

Read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. External actors and systems checked, all already modeled: `founder` (reads host state, edge `founder -> betterstack` carries the cve-exposure read),
`betterstack` (shared Logs source), `hetzner`, `inngest`, `zotRegistry`, `gitDataStore`, `github` (the dead-man feeder edge `github -> betterstack`). No new element, no new relationship, no `views.c4` change.
Edge prose to extend with the new marker: `hetzner -> betterstack` (web markers via Vector), `inngest -> betterstack`, `zotRegistry -> betterstack` (adds `SOLEUR_HOST_KERNEL` to the posted markers),
`github -> betterstack` (the four `host-kernel-*` feeder targets, once armed), `founder -> betterstack` (the helper now also reads the periodic kernel marker). The `github -> tunnel` edge states "the 25 terraform_data SSH provisioners"
for web-1; adding two `terraform_data` installers changes that derived count, so correct it with a regeneration in the same edit. `gitDataStore -> betterstack` is deliberately unchanged (#12385).
Run `plugins/soleur/test/c4-count-parity.test.sh` (green on this branch at plan time: 13 pass) and `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit.

### Sequencing

The ADR amendment describes the target state (a `status: adopting` note for the rollout) and lands in this PR; it is not a follow-up issue.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf`: add the three new files to the web bootstrap bake list (the `file()` list beside the other timer scripts), plus two `terraform_data` installers modeled on `web_bash_synthetic_install` / `_install_web2` and the recent `nonlocal_bind_sysctl` pair (#12234): `host_kernel_marker_install` (web-1) and `host_kernel_marker_install_web2` (twin), each `triggers_replace` = sha256 of the three files, with a `remote-exec` stage that installs the files, reloads systemd, enables and starts the web timer, and starts the service once (OnBootSec does not refire on an already-booted host).
- `apps/web-platform/infra/uptime-alerts.tf`: four `betteruptime_heartbeat` resources (`soleur-host-kernel-web-1-prd`, `-web-2-`, `-inngest-`, `-registry-`), period 3600, grace 7200, `paused = true`, `lifecycle.ignore_changes = [paused]`, `policy_id` gated on `var.betterstack_paid_tier` exactly as the luks sibling. No `doppler_secret`: the feeder resolves the URL through the read-only API by exact name.
- Providers and pins: unchanged (`BetterStackHQ/better-uptime`, `hcloud`). No new variable, no new secret, no `TF_VAR_*`.
- `cloud-init.yml` (timer enable), `inngest-bootstrap.sh` (write and enable, like `inngest-server-probe`; the inngest host's `user_data` changes only if the bootstrap image pin it carries changes, so `cloud-init-inngest.yml` is edited only if that pin moves), `cloud-init-registry.yml` (write the collector; `zot-disk-heartbeat.sh` gains the once-per-6h call; the registry's `user_data` does change).

### Apply path

(a) cloud-init-only for a host not yet provisioned. For a RUNNING host, per `hr-prod-host-config-change-immutable-redeploy`: web-1 is unrebuildable, so its path is the `terraform_data` installer the fleet already uses for every timer (applied by the apply workflow); web-2 gets the twin; inngest and registry by `terraform apply -replace` of the server with its dependent attachments `-target`ed (net, volume, firewall) and a post-replace NIC check. **The inngest and registry replaces are held steps awaiting separate approval (#12386); the web installers are held by default via the exclusion list (see Merge-time behavior).** Neither `hcloud_server.inngest` nor `hcloud_server.registry` is in any per-merge `-target` list (only the `inngest_host_replace` / `registry_host_replace` dispatch jobs target them), and the `host_creates` HALT counts create-or-replace and cannot be bypassed by `[ack-destroy]`, so a merge cannot replace them; after merge they show as a pending ForceNew in untargeted plans and in the drift detector (the registry already carries one), which is expected until the rollout. Blast radius: the registry is the sole pull path and has no rollback if the create fails after the destroy; verify target-type stock in the target location first, as the rule says.

### Host fan-out

`terraform_data` SSH provisioners under `apps/web-platform/infra/` classify fleet siblings per `plan-host-fanout.md`:

| Artifact | web-1 | web-2 | Class |
|---|---|---|---|
| collector, service and timer | provisioner `host_kernel_marker_install` | provisioner `host_kernel_marker_install_web2` | `twin` (no credential material on either; the marker needs none) |

Installer shape (copy the sibling pair, do not invent): web-1 `depends_on = [terraform_data.journald_persistent]`, `host_key = local.web_1_ssh_host_key`, `%RAND%` in `script_path`; web-2 `depends_on = [terraform_data.journald_persistent_web2]`, `host_key = local.web_2_ssh_host_key`, `%RAND%`, `timeout = "5m"`, and no credential material (`W2_CRED_RE` rejects it). Update `web-host-provisioner-parity.test.sh` (`W2_ALLOWED` is an exact-equality set: name `host_kernel_marker_install_web2`) and `-mutation.test.sh`, plus the `egress_gateway_web2` delivery-census comment in `server.tf`. The three new files also go through the image bake: `apps/web-platform/.dockerignore` (`!infra/...` allow lines) and the `Dockerfile` COPY block, or a fresh host's baked-file coherence check fails. Plain unit names (no systemd template): the parity loops, `fresh-boot-parity.test.sh`, `.dockerignore` and the COPY block all key on `<name>.timer` / literal filenames, and `cron-egress-alarm@.service` is the only template in the tree.

<!-- lint-infra-ignore start: describes what the merge-triggered CI apply does; prescribes no human infra step -->
**Merge-time behavior, stated plainly.** `apply-web-platform-infra.yml` fires on a push to main. (1) The four heartbeats get `-target` lines in the main apply list beside `betteruptime_heartbeat.luks_monitor_host_timer` (else `terraform-target-parity.test.ts` reds), so the merge creates them PAUSED; that pages nothing. (2) `vector.toml` is hashed into the existing `journald_persistent` provisioners' `triggers_replace`, so the merge re-delivers it to web-1 and web-2 through the standing path every `vector.toml` edit uses; the new allowlist entry is inert until a unit emits. (3) The two installers are the production-mutating step: by default they go into `OPERATOR_APPLIED_EXCLUSIONS` (the mechanism the sibling operator-applied writers use) and are not in the SSH-stage `-target` list, so a merge does NOT install the emitter on a running web host; a dispatched workflow run does that later (#12386). Moving them into the SSH-stage list (beside `terraform_data.web_bash_synthetic_install_web2` / `nonlocal_bind_sysctl_web2`, the block ending in `-target=terraform_data.egress_gateway_web2`) is the one-line change that makes merge deliver them; which of the two happens is a decision for the owner (decision-challenges.md, last row).
<!-- lint-infra-ignore end -->

### Distinctness / drift safeguards

No `dev != prd` surface is introduced. Heartbeats carry `ignore_changes = [paused]` so a later apply cannot revert the owner's unpause. The collector's role is an allowlisted instance argument, so a mis-set unit cannot claim another role. State holds the heartbeat URLs (bearer capabilities) in `terraform.tfstate`, as for every sibling heartbeat.

### Vendor-tier reality check

The heartbeats follow the existing paid-tier gate (`var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null`). The hot window is about 40 minutes, so the feeder reads hot UNION archive (it already does); nothing here relies on the hot arm alone.

## Encryption Posture

```yaml
at_rest:
  - store:             Better Stack Logs shared source (existing; no new store)
    mechanism:         provider-managed:betterstack-encrypted-at-rest (the existing ledger row for store `betterstack.logs` in scripts/encryption-posture-ledger.json; source 2457081)
    evidence:          Better Stack security documentation, attestation_url https://betterstack.com/security, as recorded in that ledger row; this plan adds one marker to the source, not a store
    defends_against:   a seized disk at the vendor; a casual vendor-side read of unrelated tenants' data
    does_not_defend:   a holder of the Logs ingest token forging a marker row; a holder of the read credential reading it; a compromise of the vendor account
    disclosed_as:      not-publicly-claimed
    live_verification: unavailable:named SOC 2 attestation formalization pending; tracked #6911 (same reason as the ledger row)
in_transit:
  - connection:        registry host -> Better Stack Logs ingest (existing curl POST in zot-disk-heartbeat.sh, now also carrying one more marker line)
    enforced_at:       apps/web-platform/infra/cloud-init-registry.yml (https URL pinned from zot-registry.tf; existing)
    tls:               https, curl default minimum
    cert_verification: on
    does_not_defend:   a compromised registry host (it holds the ingest token); a vendor-side compromise
    disclosed_as:      not-publicly-claimed
  - connection:        web-1, web-2, inngest -> Better Stack Logs via Vector (existing sink; one new journald tag only)
    enforced_at:       apps/web-platform/infra/vector.toml [sinks.betterstack]
    tls:               https
    cert_verification: on
    does_not_defend:   a compromised host (it holds the Vector token)
    disclosed_as:      not-publicly-claimed
```

No new store and no new network connection is introduced; the rows above restate the existing paths this plan adds one marker to.

## Observability

```yaml
liveness_signal:
  what: Four Better Stack heartbeats (soleur-host-kernel-<role>-prd), each fed hourly by scripts/deadman-heartbeat-feeder.sh only while that host's own valid SOLEUR_HOST_KERNEL row exists inside a literal 36 h window (hot UNION archive); absence of the beat pages after period 3600 + grace 7200.
  cadence: emitter every 6 h plus once per boot; feeder hourly
  alert_target: operator email and push through the existing paid-tier policy (born paused; armed by the owner, #12386)
  configured_in: apps/web-platform/infra/uptime-alerts.tf; scripts/deadman-heartbeat-feeder.sh; plugins/soleur/lib/heartbeat-manifest.ts
error_reporting:
  destination: the feeder's Sentry cron check-in (monitor scheduled-deadman-heartbeat-feeder) and its value-free deadman-feeder marker lines in the workflow log
  fail_loud: verdict=no_qualifying_row (exit 3) names the dark host's target; a marker line outside the feeder's shapes is counted, not printed
failure_modes:
  - mode: a host stops emitting (timer dead, unit failed, Vector or allowlist broken on one host)
    detection: layer 3 (vector journald shipper) row absent from the Logs warehouse; registry: direct POST absent. No qualifying row for that host in 36 h -> the feeder withholds the beat -> the heartbeat times out
    alert_route: Better Stack heartbeat incident to the operator policy
  - mode: the marker ships but its kernel is unreadable or the role/host is wrong
    detection: layer 3 (vector journald shipper) row in the Logs warehouse, or the registry's direct POST row; the predicate requires the anchored kernel shape and the exact identity (journald: host_name, SYSLOG_IDENTIFIER and the systemd unit), so the row does not qualify and the beat is withheld; host-state.sh prints unknown (or stale when an older valid periodic row exists)
    alert_route: same heartbeat
  - mode: the warehouse read itself fails (credentials, transport, unparseable answer)
    detection: workflow run log (layer: the GitHub Actions run of scheduled-deadman-heartbeat-feeder.yml) and the Sentry cron check-in; the feeder exits 3 or 4 with query_failed or beat_failed, distinct from no_qualifying_row; the Sentry check-in goes error
    alert_route: Sentry monitor scheduled-deadman-heartbeat-feeder
  - mode: a forged row from a holder of the ingest token keeps a heartbeat fed
    detection: not detected (residual accepted in the ADR-322 addendum of 2026-11-08: root on the host for the journald path, the shared ingest-token holder for the registry)
    alert_route: none (documented residual)
logs:
  where: Better Stack Logs shared source; journald on the host (SyslogIdentifier=host-kernel-marker); the registry row is posted directly
  retention: the source's retention; the 7-day helper window reads hot UNION archive
interim_state: until the arming change no alert is armed (the four targets are outside the feeder loop and the four heartbeats are paused); the only read is the credentialed query below
discoverability_test:
  command: bash scripts/deadman-heartbeat-feeder.sh --selftest
  expected_output: selftest=ok
```

The credentialed read of the marker itself is `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 12h --grep SOLEUR_HOST_KERNEL --limit 20` (one grep per term; it needs the Logs read credential and has no unauthenticated substitute), documented in the runbook section Phase 4 adds. The selftest above runs offline in under a second and fails if any of the four targets is missing from the feeder table.

## Task Design

```yaml
tasks:
  - task: host-kernel-marker timer (host-kernel-marker.timer on web-1 and web-2, an equivalent pair written by inngest-bootstrap.sh on the inngest host; a once-per-6h call inside the registry's existing 5-minute zot-disk-heartbeat cron)
    trigger: systemd timer — OnBootSec=2min plus a 6-hourly OnCalendar with Persistent=true and a randomized delay; the registry call is gated by a stamp file inside an existing cron
    services: reads uname, /proc/uptime, /var/run/reboot-required and the local apt package lists; writes one journald line (or, on the registry, one POST to the existing Better Stack Logs ingest URL)
    next: nothing further on the host; downstream the Vector journald source ships the line, the deadman feeder reads it, and host-state.sh decodes it
    human_reentry: stop it by disabling the timer, which applies only through the held re-provision path and never ad hoc; the heartbeats are born paused and only the owner arms them
    dedupe: a oneshot unit (systemd refuses a second start while one is active) plus the Persistent stamp, so a missed slot replays once; rows are append-only facts keyed by host_name and dt and every reader takes the newest valid row, so a duplicate row is harmless
    source_dedupe: not a ticket source
  - task: dead-man feeder targets host-kernel-web-1, host-kernel-web-2, host-kernel-inngest, host-kernel-registry (added to the existing feeder script; workflow loop membership deferred to the arming change)
    trigger: the existing scheduled-deadman-heartbeat-feeder.yml hourly dispatch — the four names are NOT in its loop in this PR (CTO ruling H1)
    services: reads the Better Stack Logs warehouse (hot UNION archive) and the uptime API (read-only token); beats one heartbeat per target
    next: nothing — a beat or a withheld beat is the whole output
    human_reentry: the owner arms each heartbeat after two consecutive qualifying_row_heartbeat_paused runs (runbook), then the arming change adds the four names to the workflow loop
    dedupe: one target per invocation and one beat call site (beat_once); the heartbeat itself collapses repeated beats into one period; the workflow concurrency group serializes runs, and the exact-name heartbeat lookup refuses a non-unique match
    source_dedupe: not a ticket source
```

## Implementation Phases

Write the failing tests first (`cq-write-failing-tests-before`): Phase 0 lands RED, each later phase turns rows green. All shell suites are `*.test.sh`
(the repo's convention; no new framework). Commit with `LEFTHOOK_EXCLUDE=bun-test` and `git commit -F <file>`; batch commits before pushing; CI is the merge gate.

### Phase 0 — Failing tests first

- `plugins/soleur/skills/cve-exposure/test/host-state.test.sh`: new fixtures for web-1, web-2, inngest and registry kernel rows (synthesized kernels such as `9.9.9-1-generic`); rows for every Guard 1 mutation below; producer-contract rows for the collector (the `SOLEUR_HOST_KERNEL v=1 role=` literal, the fixed `SyslogIdentifier`, the allowlisted instance names), for the vector allowlist entry, and for the registry post call. The existing canary-kernel cases change from `observed` to `stale` (CTO G1). Raise `MIN_CASES` to the new real count.
- `apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh`: rehearsal rows for the four targets (fresh row beats; row older than the window withholds; empty window withholds; a web-1 row does not feed the web-2 target; an unreadable kernel withholds); the window pinned at 129600 and never read from the environment.
- `apps/web-platform/infra/host-kernel-marker.test.sh` (new): drives the collector against stubbed `uname`, `/proc/uptime`, a reboot-required file and a stub `apt-get`; asserts the exact line grammar, `unknown` on a failing or timing-out apt, `kernel=unreadable` on an odd `uname -r`, and exit 64 on a bad role.
- Pins that WILL go red and must be rewritten in the same change: `deadman-heartbeat-feeder.test.sh` asserts the workflow loop equals the script's `TARGETS` exactly (`loop-targets-differ-from-script-table`) and treats a target outside the loop as an orphan: replace it with "loop = `TARGETS` minus a `DEFERRED_TARGETS` set" where the set is exactly the four host-kernel names until the arming change empties it; its wiring pin (`want_res` / `EXPECT_TARGETS`) gains the four `betteruptime_heartbeat` `-target` lines; `host-state.test.sh` SQL pins (the `multiIf` class tag and the marker-predicate `OR` count, which today is 6 clauses over four predicates) gain the new class. The stub reader routes by SQL substring and never executes the SQL, so these pins, not the fixtures, are what make a deleted clause RED.
- Wire the new suite into the infra runner (`run-registered-suites.sh` population, `suite-durations.tsv`, `suite-shard-legs.tsv`) the way #12234 did; run `scripts/lint-orphan-test-suites.sh` once the file is tracked.

### Phase 1 — Collector and units

- `apps/web-platform/infra/host-kernel-marker.sh`: prints exactly one line, `SOLEUR_HOST_KERNEL v=1 role=<web|inngest|registry> kernel=<uname -r|unreadable> uptime_s=<uint|unknown> reboot_required=<0|1|unknown> sec_updates=<uint|unknown>`, plus ` host=<hostname>` only for `--role registry`. Explicit `PATH` including `/usr/sbin`; `LC_ALL=C`; the role argument checked against an allowlist; `sec_updates` = count of `^Inst .*-security` from `timeout 20 apt-get -s upgrade` over the local lists only (reuse `lib/apt-bounded.sh` only if its interface fits an on-host call), `unknown` on any failure, display only (a stale list undercounts); a measurement failure never makes the script exit non-zero.
- `host-kernel-marker.service` (Type=oneshot, `SyslogIdentifier=host-kernel-marker`, ExecStart `--role web`) and `host-kernel-marker.timer` (`OnBootSec=2min`, 6-hourly `OnCalendar`, `Persistent=true`, `RandomizedDelaySec`, `AccuracySec`). The inngest host does not use these files: `inngest-bootstrap.sh` writes its own pair (same `SyslogIdentifier`, `--role inngest`) exactly as it does for `inngest-server-probe`.
- Line grammar detail that other files rely on: the `kernel=` value is always followed by a single space and `uptime_s=`, so readers can delimit it without a `$` anchor (the feeder's `build_sql` refuses any `$` except its two table tokens; use that delimiter, or RE2 `\z` escaped for a SQL literal, never a bare `$`).

### Phase 2 — Vector allowlist

- `apps/web-platform/infra/vector.toml`: add `"host-kernel-marker"` to `[sources.host_scripts_journald]` `include_matches.SYSLOG_IDENTIFIER` with the quota note (about 4 rows per day per host plus one per boot, a fresh quota decision per the file header) AND to the mirrored `exclude_matches.SYSLOG_IDENTIFIER` on `[sources.inngest_journald]` (the two must stay set-equal). Do not add `systemd`.
- Update `journald-config.test.sh`, `apps/web-platform/test/infra/vector-admission.test.sh` (mirror equality) and `vector-pii-scrub.test.sh` (add a fixture proving the marker line passes the scrub unchanged; any derived-tag test is located by grep, see Guard 3).
- Hot delivery of `vector.toml` to web hosts rides the existing `journald_persistent` provisioners (their `triggers_replace` hashes the file), so the edit changes the next apply's plan: state it in the PR as part of the held apply.

### Phase 3 — Delivery per host class (nothing applied)

- Web: `server.tf` bake list + the two installers + `OPERATOR_APPLIED_EXCLUSIONS` entries (and the four heartbeat `-target` lines in `apply-web-platform-infra.yml`); `.dockerignore` + `Dockerfile` COPY lines; `soleur-host-bootstrap.sh` install loop; `cloud-init.yml` timer enable (the bake is a bundle, not inline, so the user-data render barely moves; re-run the size test); parity tests (`web-host-provisioner-parity*.test.sh`, `terraform-target-parity.test.ts`, `fresh-boot-parity.test.sh` (a new `PROBE_UNITS` row for the plain timer)).
- Inngest: `inngest-bootstrap.sh` writes and enables the units as it does for `inngest-server-probe`; the bootstrap image build must carry the collector (`build-inngest-bootstrap-image.yml` copies `inngest-bootstrap.sh` and `vector.toml` into the build dir: add the collector and units the same way, and read how `cloud-init-inngest.yml` consumes the image dir before choosing). A byte-parity test ties every baked copy to `host-kernel-marker.sh` (single source of truth). Re-run `inngest-userdata-budget.sh`.
- Registry: `cloud-init-registry.yml` writes the collector (templatefile var from `file()`; `registry-userdata-budget.sh` hand-restates the var map, so update it in lockstep or it fails closed) and `zot-disk-heartbeat.sh` calls it once per 6 h, AFTER its existing post so a slow apt call cannot delay the disk row, under a stamp file in `/run` (tmpfs, so the first cron tick after every boot also reports), `timeout`-bounded, failure swallowed, reusing the existing `post()` with `LINE` set to the collector output. The collector's `host=` for `--role registry` is the registry host id constant the helper pins (`REGISTRY_HOST_ID`), asserted equal by a test, not whatever `hostname` happens to print. Re-run the registry budget and the sweep battery that pins the four copies of the token judge (this adds no fifth copy).
- Falsifiable apply-path check (plan-graded, no live read): `terraform-target-parity.test.ts` plus a small assertion in the new census suite that neither `hcloud_server.registry` nor `hcloud_server.inngest` appears in any per-merge `-target` list of `apply-web-platform-infra.yml` (only their dispatch jobs may name them). The PR cites the `host_creates` HALT and those dispatch jobs by name.

### Phase 4 — Alert and runbooks

- `scripts/deadman-heartbeat-feeder.sh`: four targets in `TARGETS` / `select_target`, window `129600`, names `soleur-host-kernel-<role>-prd`, one-physical-line predicates (journald hosts: exact `SYSLOG_IDENTIFIER`, exact `host_name` as a literal cross-pinned to the helper's `ROLE_TABLE` by a test (the feeder runs in CI and the helper runs from an upstream-verified operator checkout, so neither can source the other), `startsWith(message,'SOLEUR_HOST_KERNEL v=1 role=<web|inngest> ')`, the kernel shape delimited by its trailing space (no `$`), and no ` host=`; registry: empty `SYSLOG_IDENTIFIER` and `host_name`, `role=registry` and `host=<registry host id>`, the kernel shape). `--selftest` covers them. The `withhold_no_row` text for the new targets names a dark host or source.
- `uptime-alerts.tf` heartbeats and four `heartbeat-manifest.ts` rows: `arming: "external-probe"`, `paused: true`, `feeder: { kind: "none", url_secret: null, tracking_issue: 12386 }` until the arming change flips them to the cron form (workflow loop membership is deferred by ruling H1), `exempt_reason` stating the archive-reading feeder. Do NOT add the four names to the workflow loop in this PR; add a comment there and the rewritten loop pin from Phase 0. Arming is staged so no step is circular: (1) after the owner's rollout shows a first row per host, a small change adds the names to the loop while the heartbeats are still paused (the feeder then reports `qualifying_row_heartbeat_paused`, no red); (2) after two consecutive such runs the owner arms, and the manifest `feeder` rows flip to the cron form in the same change. One batched change per stage, not per host.
- `betterstack-log-query.md`: a "Querying SOLEUR_HOST_KERNEL" section (the query, the decode, the three empty-read states, the identity rules, the 36 h window, how a page is read); `workspaces-luks-cutover-6604.md` arming section: add the four targets, the two-stage order above, a note that a planned replace of the inngest or registry host goes dark for up to the 36 h window so its heartbeat is paused first, and a note that registry and inngest `unknown` in the skill output is the expected rollout state, not a bug.

### Phase 5 — Helper and skill text

- `host-state.sh` (header contract, `classify_host`, marker SQL, jq decode): add class `kern` (an explicit `multiIf` arm before the `zot` default); decode journald rows by Vector-stamped `host_name` + exact `SYSLOG_IDENTIFIER` + `startsWith` on the v=1 token with a `role=` cross-check and `host=` rejection; decode registry rows by `role=registry` + `host=<registry id>`; a mismatched or unknown-v row is `unmapped` or ignored, never attributed. The `kernel_state` enum becomes `observed|stale|unknown`: `observed` = valid kernel shape and newest periodic row at most 48 h old; `stale` = an older periodic row or only a failed-deploy row (kernel and age visible; this means changing `classify_host`'s rule that blanks `kernel` and `kernel_age_hours` unless `observed`, with a row for it); else `unknown`. A newest periodic row with an unreadable kernel does not shadow an older valid one: the newest VALID row wins. Precedence and `source_marker` as ruled in G1. `marker_state` counts `kern` as a periodic marker. Keep every existing probe / NIC / ZOT clause intact (the probe-row census allowlist must not go STALE) and keep the probe marker and the reader invocation off one line (the census flags a raw reader line that names the probe marker).
- `SKILL.md` Steps 3, 5, 6 (remove the "most hosts report no kernel today; #12007 adds one" and "no marker supplies yet" clauses; `observed` may ground `no`, `stale` never does) and `references/component-map.md` host discriminators table. Neither edit touches the `description:` frontmatter (no description-budget cost). No version, host or kernel string appears in either file.
- ADR-322 amendment (see above); extend the `model.c4` edge prose and the SSH-provisioner count.

### Phase 6 — Ratchet sweep

`scripts/test-affected-kb-consumers.baseline.txt` (new suites must not name `knowledge-base/` paths; if one must, regenerate with the script's `--write-baseline` and commit the delta), `scripts/guard-vacuity-floor.test.sh` (run it; the new suites use the `[[ n -lt N ]]` floor shape it derives), `scripts/lib/inngest-probe-row.test.sh` (must stay green with no allowlist edit), `scripts/image-cve-public-claim-guard.test.sh`, `apps/web-platform/test/git-lock-marker-telemetry.test.ts` (the marker name is read, not emitted, by the skill script; confirm), `betterstack-alert-structure.test.sh` (no native alert added, floors unchanged), `heartbeat-reprovision-parity.test.ts`, `tests/scripts/test-infra-privileged-tier-census.sh`, `lint-orphan-test-suites.sh`, `c4-count-parity.test.sh`. Final sweep for durable text: `git grep` the diff for kernel-shaped strings (`[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-z]+`) and host literals outside synthesized fixtures.

### Phase 7 — PR

PR body: `Closes #12007`, `Ref #12385`, `Ref #12386`; a Holds block naming the operator-reserved steps; the decision-challenges rows via `ship`. Ends with the Claude Code attribution line. Plugin edits are a `semver:patch`.

## Guard Contract

### Guard 1 — host-state kernel grounding (host-state.sh)

**Property.** `kernel_state=observed` is printed for a role only when a periodic `SOLEUR_HOST_KERNEL v=1` row, attributed to that role by transport-stamped identity (journald: Vector `host_name` + exact `SYSLOG_IDENTIFIER`; registry: `role=registry` and `host=` equal to the registry id), carries a kernel matching the anchored shape and is at most 48 hours old; everything else prints `stale` or `unknown`, never `observed`.

**Assembly.** The single chokepoint is `classify_host` (every printed host line, including `unmapped`, flows through it and re-validates against anchored shapes). The members that feed it: the marker SQL predicate for the new class (hot arm AND archive arm, 7-day window, `LIMIT ... BY` per class and host), the jq decode branches (journald branch, registry branch, role cross-check, `host=` rejection, unknown-`v` ignore), the precedence between fresh periodic / older periodic / failed-deploy row, the `FRESH_HOURS` constant, and the role table (`ROLE_TABLE` host names, shared with the feeder predicates). Two decode branches exist by design (journald hosts and the registry); a check that covers one is the defect.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make a fresh kern row for web-2 arrive with web-1's `host_name`; the helper must not print web-2 `observed` | RED (attribution) |
| 2 | Raise `FRESH_HOURS` from 48 to 72, then feed a 60-hour-old valid row | RED (must print `stale`) |
| 3 | Feed a registry row with `role=registry` but a different `host=`; then one with the right `host=` and `role=web` | RED for both (second member after a compliant first) |
| 4 | Feed a journald row that carries ` host=` equal to the registry id for the registry role | RED (rejected) |
| 5 | Feed `v=2` and `v=` (missing) rows | RED (ignored, role stays `unknown`) |
| 6 | Feed a failed-deploy kernel row 3 hours old and nothing periodic | RED if printed `observed` (must be `stale`) |
| 7 | Delete the new class from the marker SQL `OR` chain (the helper's own dispatch) so zero kern rows are fetched | RED through the SQL pins (the `multiIf` class tag and the `OR`-clause count), because the stub reader never executes SQL; a helper that fetches nothing and exits 0 is vacuous |
| 8 | Precedence: a newest row with an unreadable kernel above an older valid row within 48 h | RED unless the older valid row wins (`observed` from the valid row, never `observed` with an unreadable kernel) |
| 9 | Feed a row dated two minutes in the future, then one dated two days ahead | RED for the second (clock skew mints no fresh; the first clamps to age 0) |

**Harness rows.** Edit the SUITE: stub `fail`/`check` to a no-op copy (through the `HOST_STATE_SUT_OVERRIDE`-style seam) and require the floor and the accounting-conservation check to catch it. Must-PASS input that is NOT the canonical fixture: a different permitted kernel build and a different ABI on a second web host, and a valid row whose message carries extra trailing fields (`sec_updates=unknown`); all must print `observed`, so a guard that rejects everything fails these.

**Anchor.** The 48 h bound lives in `FRESH_HOURS` and in the skill text; a weakening edit must move both the constant and the producer-contract rows that pin it in `host-state.test.sh`, and the ADR-322 amendment names the number, so one diff cannot loosen it without touching three reviewed places. The registry id is pinned to the same `REGISTRY_HOST_ID` the existing `SOLEUR_ZOT_DISK` path uses.

### Guard 2 — dead-man feeder targets (deadman-heartbeat-feeder.sh)

**Property.** A heartbeat for host X is beaten only while X's own valid `SOLEUR_HOST_KERNEL` row, under X's identity predicate, exists inside the 129600 s window; a different host's row, an unreadable kernel or an empty window never beats it.

**Assembly.** `TARGETS`, `select_target` (literal equality, constants only), `build_sql` (window in both arms, archive arm `_row_type = 1`), the four predicates, `--selftest`, the exact heartbeat names (`uptime-alerts.tf`), the manifest rows, and the workflow loop (deliberately without the four names until arming). Names must agree across five places: feeder table, `.tf`, manifest, runbook, test.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `host_name` from the web-2 predicate; a web-1 row must then feed web-2 | RED |
| 2 | Widen `W` to 200000 (past the 48 h trust bound) | RED (a test derives `W + 3600 + period + grace < 48 h` from the table) |
| 3 | Remove one of the four targets from `TARGETS`; `--selftest` must go non-zero | RED (dispatch) |
| 4 | Add a fifth host-kernel heartbeat in `.tf` without a manifest row or feeder target | RED (parity) |
| 5 | Feed a row with an unreadable kernel to a target that was compliant a minute earlier | RED (must withhold) |
| 6 | Add the four names to the workflow loop while they are still in `DEFERRED_TARGETS` or their manifest rows still say `feeder: none` | RED (loop = `TARGETS` minus the deferred set) |

**Harness rows.** Edit the suite: replace the beat transport stub with one that always succeeds and require a withheld-beat case to still fail the suite. Must-PASS non-canonical: a row for the target host 35 hours and 59 minutes old with extra trailing fields beats.

**Anchor.** The window is a literal in the SQL text (no env override, asserted), the 40 h worst case is derived in a test from `W`, period and grace, and the 48 h skill bound lives outside this file (Guard 1), so loosening the alert requires editing both.

### Guard 3 — emitter census and allowlist (collector, units, vector.toml, cloud-init)

**Property.** Every `hcloud_server` resource in the infra root is classified as emitting `SOLEUR_HOST_KERNEL` or carries a tracked exemption, and every emitting class has its collector copy byte-equal to `host-kernel-marker.sh`, a shipped identifier, and a fresh-host enable line.

**Assembly.** The population is DERIVED by extending the existing host census in `host-state.test.sh` (every `hcloud_server` block outside a rehearsal root: web by `for_each`, inngest, registry, git_data, grok_dogfood), not by a second parser; each role row gains an `emits` or `exempt:<tracking>` class; the members per emitting class are the baked copy (bootstrap bake list, inngest bootstrap, registry cloud-init), the unit `SyslogIdentifier`, the `vector.toml` include AND its inngest-source exclude mirror, and the enable line. Exemptions: git_data (#12385) and grok_dogfood (`count = var.enable_grok_dogfood`, default false, no shipper; remove the exemption when the variable flips).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a new `hcloud_server` block with no class | RED (UNCLASSIFIED bucket) |
| 2 | Delete `"host-kernel-marker"` from the `vector.toml` include (keep the unit) | RED |
| 3 | Delete it from the inngest-source exclude mirror only | RED (set-equality) |
| 4 | Alter one byte in the inngest-baked collector copy after a compliant web copy | RED (second member) |
| 5 | Change the unit's `SyslogIdentifier` | RED (the census suite's own unit-to-allowlist join: it reads the unit's `SyslogIdentifier=` and requires the value in the `vector.toml` include; `journald-config.test.sh`-style anchored `^SyslogIdentifier=host-kernel-marker$` pins back it. The `vector.toml` header cites an "AC3" derived-tag test; `vector-pii-scrub.test.sh` has none, so locate it by grep in Phase 0 and use it if it exists) |
| 6 | Remove the exemption row for grok_dogfood | RED (UNCLASSIFIED) |
| 7 | Make the census enumerate zero `hcloud_server` blocks | RED (floor on population count; a census that sees nothing is vacuous) |

**Harness rows.** Edit the suite: make the census helper always print "clean" and require row 1 to still fail the run. Must-PASS non-canonical: a fixture tree with an extra `hcloud_server` that carries a valid exemption stays green.

**Anchor.** Exemption rows are keyed to a tracking issue or a variable name and the test reads the variable's default from `variables.tf`; flipping `enable_grok_dogfood` or closing #12385 without removing the row reds the suite.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `host-state.test.sh`, the feeder rehearsal suite, `host-kernel-marker.test.sh`, `journald-config.test.sh`, `vector-admission.test.sh`, `vector-pii-scrub.test.sh`, `web-host-provisioner-parity*.test.sh` and the new census pass in CI, and every Guard 1-3 mutation row is committed and goes RED when applied.
- [ ] `host-state.sh` prints `observed` only for a valid periodic row at most 48 hours old attributed under the identity rules; the canary-only and over-48-hour cases print `stale`; the old canary `observed` assertions are rewritten, not deleted.
- [ ] `bash scripts/deadman-heartbeat-feeder.sh --selftest` prints `deadman-feeder: selftest=ok` and fails when a target is removed; the window constant is a literal in the SQL text.
- [ ] Four heartbeats exist in `uptime-alerts.tf`, born paused with `ignore_changes = [paused]`, and four `heartbeat-manifest.ts` rows agree with them; `heartbeat-reprovision-parity.test.ts` is green; the workflow loop contains none of the four names.
- [ ] The `vector.toml` allowlist entry and its inngest-source mirror are set-equal; `systemd` is not added anywhere; the quota note names the expected row rate.
- [ ] Ratchets green: `inngest-probe-row.test.sh` with no allowlist edit, `guard-vacuity-floor.test.sh`, `image-cve-public-claim-guard.test.sh`, `test-affected-kb-consumers.test.sh` (any baseline delta is a deliberate, explained row), `git-lock-marker-telemetry.test.ts`, `betterstack-alert-structure.test.sh`, `c4-count-parity.test.sh`, `lint-orphan-test-suites.sh`, and the user-data size and budget checks (web, inngest, registry).
- [ ] `git grep` over the diff finds no kernel-shaped string or host literal outside synthesized fixtures, and neither SKILL.md nor the runbook carries a version, host, kernel or "not affected" wording (the runbook uses placeholders).
- [ ] The ADR-322 amendment, the `model.c4` edge prose (including the corrected SSH-provisioner count), `SKILL.md`, `component-map.md` and the runbook section are in the diff; `c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
- [ ] A routine merge apply does not replace the registry or inngest host (a read-only check recorded in the PR), and the PR states the gate.
- [ ] The PR body has `Closes #12007`, `Ref #12385`, `Ref #12386`, the Holds block, and ends with the Claude Code attribution line; this run applied, rebooted and connected to nothing.

### Post-merge (operator)

All held; each needs the operator's explicit per-command go-ahead. Tracked in #12386. Automation: not feasible in this run because each step mutates production or arms a paging surface.

- [ ] Web first (cheapest, no re-provision): the dispatch that applies the two installers to web-1 and web-2.
- [ ] Then the `-replace` of the inngest host and, last, the registry host (no rollback if its create fails), each with its dependent targets and a post-replace NIC check, in the order the operator chooses.
- [ ] A first row per host is visible: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 12h --grep SOLEUR_HOST_KERNEL --limit 20`, and the helper prints `observed` for each rolled host.
- [ ] Stage 1 change: add the four names to the workflow loop (heartbeats still paused). Stage 2, after two consecutive `qualifying_row_heartbeat_paused` runs per target: arm each heartbeat (runbook), flip the manifest `feeder` rows to the cron form and drop `arming_pending`, in one batched change.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled all technical forks (F1-F5, G1-G3, H1-H5; recorded in `knowledge-base/project/specs/feat-one-shot-12007-host-kernel-marker/decision-challenges.md`): one collector with per-class sinks, a 6-hourly cadence, a dead-man heartbeat per host with a 36 h window instead of a native alert, git-data deferred and grok-dogfood exempt, identity by transport-stamped `host_name` with a registry in-message rule, a third `stale` kernel state, and the feeder-loop membership deferred to the arming change. No other domain has a stake: no UI, no copy, no pricing, no customer data, no legal surface (the marker is host telemetry in a private source; the public artifacts carry no exposure data by construction).

GDPR gate: skipped. The marker carries host kernel, uptime and role, no personal data, no new processing activity and no new artifact distribution surface (the helper is operator tooling gated by a repo-identity guard); none of the (a)-(d) triggers fire.

## Test Strategy

Shell `*.test.sh` suites, synthesized fixtures only (`cq-test-fixtures-synthesized-only`: kernels like `9.9.9-1-generic`). No new framework. The stubbed reader and curl shims in `host-state.test.sh` are reused for the new decode branches; the feeder rehearsal uses the existing stub query and beat transports. Mutation rows are committed in the suites, not described in prose.

## Risks

- **Interim state.** Until the held apply, the four heartbeats are paused and the feeder loop excludes them, so nothing pages and the helper prints `silent` or `unknown` for hosts not yet rolled: correct, but the skill's answers stay mostly `unknown` until the operator rolls out. Tracked in #12386.
- **User-data replace.** Editing the registry or inngest cloud-init is ForceNew on those hosts. The pre-merge AC makes the replace gate explicit before merge.
- **Forged rows.** A holder of the ingest token can forge a marker and keep a heartbeat fed; accepted in ADR-322 and restated in the amendment.
- **Pending ForceNew drift.** After merge the registry and inngest hosts show a pending replace in untargeted plans and the drift detector until the owner rolls out (the registry already carried one). The two held `terraform_data` installer creates (`host_kernel_marker_install` and `host_kernel_marker_install_web2`) are standing drift on the twice-daily plan until #12386 releases or applies them. Review correction (2026-11-08, appended): the inngest host is delivered through the digest-pinned bootstrap OCI image, so its marker arrives with a pin bump rather than a ForceNew from this change; the delivery matrix in `workspaces-luks-cutover-6604.md` is the reference. The `host_creates` HALT and the dispatch-only targets keep a merge from replacing them; the rollout issue carries an expiry for the interim.
- **Quota.** About 4 rows per day per host plus one per boot across four hosts: negligible against the 2026-06 host-metrics finding; the measured number is recorded after rollout, not before.
- **Reboot recovery.** This change names no reboot as a recovery step; the report refreshes within minutes of any future boot (`OnBootSec`), which #12008 will rely on.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- Do not add the four feeder names to `scheduled-deadman-heartbeat-feeder.yml` in this PR (ruling H1); the arming change does it.
- Do not rewrite or drop the probe-marker clauses in `host-state.sh`: the probe-row census allowlist would go STALE, and a line naming both the reader and the probe marker flips it to ALLOWLISTED-READER.
- The `multiIf` in the marker SQL defaults to `zot`; the new class needs an explicit arm before the default or its rows are mislabeled.
- The canary-kernel assertions in `host-state.test.sh` change meaning (observed -> stale); rewrite them, do not delete them.
- Write the Guard mutation tables directly under the bold `**Mutation matrix.**` line, as this plan does, or `lint-guard-contract.py` counts zero rows.
- This run opens no host connection and arms nothing; each such step is a hold that needs its own explicit per-command go-ahead.

## Files to Create

- `apps/web-platform/infra/host-kernel-marker.sh`
- `apps/web-platform/infra/host-kernel-marker.service`
- `apps/web-platform/infra/host-kernel-marker.timer`
- `apps/web-platform/infra/host-kernel-marker.test.sh`

## Files to Edit

- `plugins/soleur/skills/cve-exposure/scripts/host-state.sh`
- `plugins/soleur/skills/cve-exposure/test/host-state.test.sh`
- `plugins/soleur/skills/cve-exposure/SKILL.md`
- `plugins/soleur/skills/cve-exposure/references/component-map.md`
- `scripts/deadman-heartbeat-feeder.sh`
- `apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh`
- `apps/web-platform/infra/vector.toml`
- `apps/web-platform/infra/journald-config.test.sh`
- `apps/web-platform/test/infra/vector-admission.test.sh`
- `apps/web-platform/test/infra/vector-pii-scrub.test.sh`
- `apps/web-platform/infra/server.tf`
- `apps/web-platform/infra/uptime-alerts.tf`
- `apps/web-platform/infra/soleur-host-bootstrap.sh`
- `apps/web-platform/infra/cloud-init.yml`
- `apps/web-platform/infra/inngest-bootstrap.sh`
- `apps/web-platform/infra/cloud-init-registry.yml`
- `apps/web-platform/infra/registry-userdata-budget.sh`
- `.github/workflows/apply-web-platform-infra.yml`
- `.github/workflows/build-inngest-bootstrap-image.yml`
- `.github/workflows/scheduled-deadman-heartbeat-feeder.yml` (comment only in this PR)
- `apps/web-platform/.dockerignore`
- `apps/web-platform/Dockerfile`
- `tests/scripts/test-infra-privileged-tier-census.sh` (only if the exclusion entries require a census row)
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh`
- `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
- `apps/web-platform/infra/fresh-boot-parity.test.sh`
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `plugins/soleur/test/cloud-init-user-data-size.test.ts`
- `plugins/soleur/lib/heartbeat-manifest.ts`
- `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`
- `apps/web-platform/infra/suite-durations.tsv`
- `apps/web-platform/infra/suite-shard-legs.tsv`
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`
- `knowledge-base/engineering/architecture/decisions/ADR-322-exposure-answers-are-unknown-by-default-and-session-only-in-a-public-repo.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `scripts/test-affected-kb-consumers.baseline.txt` (only if a new suite must name a `knowledge-base/` path)

The pipeline also writes `knowledge-base/project/specs/feat-one-shot-12007-host-kernel-marker/{tasks.md,decision-challenges.md,session-state.md}` and this plan; the diff-scope AC allows them.

## Follow-ups filed (deferral tracking)

- #12385 — SOLEUR_HOST_KERNEL marker for the git-data host (separate Logs source). Re-evaluate after two weeks of rows from the other four hosts.
- #12386 — roll out the emitter to running hosts and arm the four heartbeats (operator-reserved holds).
