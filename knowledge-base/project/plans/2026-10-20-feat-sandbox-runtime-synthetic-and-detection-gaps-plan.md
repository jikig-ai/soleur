---
title: "feat: sandbox runtime Bash synthetic with per-host dead-man heartbeat (follow-up to #10445)"
date: 2026-10-20
slug: sandbox-runtime-synthetic-and-detection-gaps
branch: feat-sandbox-followups-triage-10455
issue: 10455
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
---

# feat: sandbox runtime Bash synthetic with per-host dead-man heartbeat (follow-up to #10445)

Ref #10455. Never `Closes`: #10455 keeps its gated items; #10548, #10549 and #10604 stay open behind their recorded triggers.

## Overview

The deploy-time SDK Bash smoke (PR #10546) only runs at deploy, so a sandbox that breaks between deploys is invisible; that is how the 2026-10-06..16 outage (#10445) lasted 10 days. **This PR (PR-A)** adds a **runtime Bash synthetic**: a timer unit on every web host that runs a real wrapped Bash call in the RUNNING container and feeds a per-host dead-man heartbeat.

**Split (plan review, CTO ruling 2026-10-20):** the brainstorm scoped three items; review split them. PR-B (separate branch, started after PR-A merges) carries the `masked-dir-precreate` routed alert and the read-only persisted-CLI-output measurement. They share no files with PR-A, and the measurement may produce a P1 compliance finding that must not wait behind roughly 25 parity files of review. PR-B is recorded as a checklist comment on #10455 when this PR opens.

Brainstorm: `knowledge-base/project/brainstorms/2026-10-20-sandbox-followups-triage-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-sandbox-followups-triage-10455/spec.md` (superseded where this plan differs; the spec is not edited, the #10455 note says so).

## Research Insights

**Premise Validation (Phase 0.6).** #10455, #10548, #10549, #10604 OPEN; PR #10546 MERGED 2026-10-20T11:43Z. `web-bash-synthetic` exists only in archived plan/tasks, so this is a build. ADR-079 (faithful canary) owns the surface and records nothing rejecting a runtime synthetic.

**Property List (Phase 0.6b).**
- P1: a sandbox Bash outage between deploys is detected within about 30 minutes without SSH.
- P2: a dead detector (stopped timer, dark host, failed unit) is itself detected.
- (PR-B) P3: a masked-directory precreate failure reaches a human. P4: whether sibling tenants can read persisted CLI output is measured, not inferred.

**Cut List.**
- Fold into the nic-guard unit: `web-probe.tf` records that beat as permanent and independent; folding re-creates OR-masking (CTO, 2026-10-19, reaffirmed).
- Own `flock` in the script: a systemd oneshot cannot overlap itself, so it buys nothing (simplicity review). Only the deploy-lock SKIP stays.
- Separate `skip` and `infra_error` verdicts: both mean "no ping"; one `no_ping` verdict with a `reason=` field (simplicity review).
- Spec corrections as a deliverable, and the `betterstack-log-query.md` edit: no requirement (simplicity review).
- `agentEnv`-derived deny set, test-hardening P3, page on >=2 users, legacy observer, SOCKS arms, peer-messaging auth, `--pids-limit`, EACCES/EINVAL: gated or cut (brainstorm triage).

**Institutional learnings applied:** `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`, `2026-07-24-followthrough-soak-must-arm-every-new-member-monitor.md`, `2026-07-18-shared-delivery-substrate-and-reused-heartbeat-url-masking.md`, `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md` (unit PATH lacks `/usr/sbin`), `2026-06-14-inline-remote-exec-body-outside-config-hash-is-a-silent-no-op.md`, `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`, `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`, `2026-10-10-the-mock-printed-a-short-path-where-docker-prints-the-whole-seccomp-profile.md`, `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`.

**Code map (verified by repo research and Kieran's review):**
- Precedent unit trios: `apps/web-platform/infra/web-private-nic-guard.{sh,service,timer,test.sh}`, `web-zot-consumer-probe.*`; heartbeats in `web-probe.tf` (`betteruptime_heartbeat.web_nic_guard` / `web_zot_consumer`, `for_each = var.web_hosts`, `paused = true`, `ignore_changes=[paused]`).
- Delivery: running hosts `server.tf` `terraform_data.private_nic_guard_install` / `zot_consumer_probe_install` (SSH provisioners that install the files and enable the timer); fresh hosts `cloud-init.yml` + `soleur-host-bootstrap.sh` + `web-probe-envwrite.sh`.
- Arming: `arm-heartbeats.sh` ~L931-939 already arms web-1 AND web-2 for the existing beats with literal `arm_one <tfstate address>` calls (it does not iterate and is not hardcoded to web-1). Each call's deadline is `period + grace - 40`.
- Registrations: `plugins/soleur/lib/heartbeat-manifest.ts`; `plugins/soleur/test/{heartbeat-live-reconcile,terraform-target-parity,heartbeat-reprovision-parity,cloud-init-user-data-size}.test.ts`; `infra/{fresh-boot-parity,web-host-provisioner-parity,journald-config,doppler-injection-bound}.test.sh` (`FLOOR_BLOCKS = 25` ~L1372); `test/infra/{vector-admission,vector-pii-scrub}.test.sh`; `infra/suite-shard-legs.tsv`; `apps/web-platform/Dockerfile` and `.dockerignore` (nic-guard files are referenced there); `web-probe-read-token.tf` (check). `vector.toml` carries the identifier in three arrays (include in `host_scripts_journald`; exclude in `inngest_journald` and `system_journald`).
- Smoke to reuse: `ci-deploy.sh` `run_sdk_bash_smoke` (rc 124 / `SDK_BASH_DISPATCHED` / nonce mapping; host cap 150 s, probe internal cap 120 s), `infra/lib/sdk-bash-probe.mjs`, deploy lock `/var/lock/ci-deploy.lock`, canary scratch config dir.

## Research Reconciliation — Spec vs. Codebase

| Spec / earlier-plan claim | Reality | Plan response |
|---|---|---|
| Spec FR1: `timeout 60` | Probe internal cap 120 s, deploy host cap 150 s; a 60 s kill after dispatch is a false `fail`. | Host cap 150 s; verdict mapping shared with the deploy smoke. |
| Plan v1: "`arm_one` hardcoded to web-1, iterate `var.web_hosts`" | `arm-heartbeats.sh` already arms web-1 and web-2 with literal calls (Kieran). | Two new literal `arm_one` lines (web-1, web-2) plus a test row that fails when any `var.web_hosts` member lacks one. |
| Plan v1: grace 900 s | A skipped run (deploy lock, restart) plus jitter exceeds 1800 s: false pages (DHH, spec-flow). | Period 900 s, grace 1800 s. `/fail` already gives immediate P1 detection; the dead-man beat only needs to be coarse. |
| Plan v1: probe "runtime mode" with env-mirror selector | The mirror is a static fallback; the production selector is the live flag read (`resolve-sandbox-unix-deny.ts`). After the #10548 flip an env-mirror probe tests the wrong artifact. | See CTO ruling below. |

## CTO rulings (plan review, 2026-10-20)

- **Selector.** Ruled by CTO agent: the probe calls the dispatcher's `resolveSandboxUnixDeny` through a thin bundled entrypoint (fails closed to base, memoised; returns base until the flag exists). Never the env mirror. Fallback only if the resolver cannot be bundled within the size budget: a host-side `--selector` argument. DHH's cut of the runtime mode was overruled by this ruling.
- **Split.** Ruled by CTO agent: split now (PR-A here; PR-B later), not at a file-count checkpoint.
- **Verdict mapping.** Ruled by CTO agent: extract the rc 124 / `SDK_BASH_DISPATCHED` / nonce mapping from `run_sdk_bash_smoke` into one sourced function used by both callers.
- **Parity sprawl.** Ruled by CTO agent: do not refactor here; file one debt issue (table-driven host-timer registry) when this PR opens.

## User-Brand Impact

**If this lands broken, the user experiences:** a repeat of #10445 with no page, or false pages that train the operator to ignore the synthetic; worse, a synthetic that harms tenants (memory or process pressure on the shared prod container) while testing it.
**If this leaks, the user's data is exposed via:** the synthetic itself carries no tenant data (random nonce, `env -i`, decoy key, scratch config dir, no writes to the shared `HOME`); the persisted-CLI-output exposure question moves to PR-B.
**Brand-survival threshold:** single-user incident

CPO and CLO assessments carried forward from the brainstorm; `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "decide which of these are actionable now vs. gated by their re-evaluation triggers/soak/operator authorization, and scope what to build" [brief] | Brainstorm triage; this plan = PR-A | mapped |
| 2 | "(b) runtime synthetic with a dead-man arm" [issue #10455] | Phases 1-2 | mapped |
| 3 | "A dedicated alert for `op=masked-dir-precreate`" [issue #10455] | PR-B | descoped from this PR — justification: shares no files, split ruled by CTO |
| 4 | "Other persisted CLI output / sockets a sibling can reach" [issue #10455] | PR-B | descoped from this PR — justification: same; may yield a P1 finding |
| 5 | "Derive the deny set from the env the CLI is actually spawned with" [issue #10455] | — | descoped — justification: buys no property here |
| 6 | "soak-gated promotion, flag creation and enable" [issue #10548] | — | descoped — justification: time-gated to 2026-10-26, operator-typed |
| 7 | "AF_UNIX deny for egress sessions needs a per-command wrapper" [issue #10549] | — | descoped — justification: trigger unfired |
| 8 | "flag cohort step, variant-EPERM signal" [issue #10604] | — | descoped — justification: trigger unfired |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Runtime synthetic + heartbeat | "runtime synthetic of the wrapped Bash command with a dead-man arm" | asked |
| Two literal `arm_one` calls + per-host test row | — | inferred — justification: a new beat is born `paused=true` and is dark until armed (learning 2026-07-24) |
| Container-safety pre-checks (memory skip, in-container `timeout -k`, start-time unchanged) | — | inferred — justification: architecture review; the synthetic execs into the shared prod container |
| Shared verdict-mapping function | — | inferred — justification: CTO ruling; two copies of the rc 124 mapping drift |
| Post-merge beat-status check | — | inferred — justification: spec-flow; a passing journal with a paused beat reads healthy |

### Split Assessment

- Subsystems touched: 3 (`apps/web-platform/infra`, `plugins/soleur/lib+test`, `.github/workflows`) plus docs
- Planned files: about 30 | Estimated changed lines: about 600
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (PR-A); the file count is parity registration, forced by repo rules. PR-B is the already-made split.

## Implementation Phases

### Phase 1 — Shared verdict mapping, probe entrypoint, synthetic script (RED tests first)

- Extract the verdict mapping from `run_sdk_bash_smoke` into a sourced function (`infra/lib/`), keeping `ci-deploy.sh` behavior byte-identical (existing smoke tests stay green).
- `infra/lib/sdk-bash-probe.mjs`: a runtime mode that resolves the selector through the bundled `resolveSandboxUnixDeny` entrypoint (see CTO ruling), prints the same `SDK_BASH_DISPATCHED` / `SDK_BASH_RESULT` markers, reports `coverage` honestly, and writes only to its scratch config dir (never the shared `HOME`, `~/.claude/projects`, or `/tmp/cc-socks*`).
- `infra/web-bash-synthetic.sh`: explicit `PATH=/usr/sbin:/usr/bin:/bin`; SKIP (no ping, journal `verdict=no_ping reason=<deploy_lock|container_down|container_restarted|memory_pressure|no_heartbeat_url|probe_absent|infra_error|host_timeout_before_dispatch>`) when `/var/lock/ci-deploy.lock` is held, when the container is not running, when container memory is above a threshold (read from `docker stats --no-stream`, threshold a named constant), or when the container ID/start time changed between start and end of the run (a deploy swap mid-run is a skip, never a `fail`). Run `docker exec soleur-web-platform /usr/bin/env -i PATH=... timeout -k 5 120 node probe` under host `timeout 150`, no `-u`, container `HOME` (same envelope as the deploy smoke ruling; a root pass does not prove uid 1001, recorded as a residual in the ADR addendum). Ping the heartbeat only on a verified pass; `/fail` on `sdk_bash_smoke_failed`; nothing on `no_ping`. Journal `SOLEUR_WEB_BASH_SYNTHETIC verdict=<pass|fail|no_ping> reason=... consecutive_no_ping=<n>` with `SyslogIdentifier=web-bash-synthetic`.
- `web-bash-synthetic.{service,timer}`: every 15 minutes, first run at timer start, small `RandomizedDelaySec`, `Persistent=false`.
- `web-bash-synthetic.test.sh`: written first; mocks copy real `docker exec` output shape and preserve exit status.

### Phase 2 — Delivery, heartbeat, arming, parity

- `web-probe.tf`: `betteruptime_heartbeat.web_bash_synthetic` (`for_each = var.web_hosts`, period 900 s, grace 1800 s, `paused = true`, `ignore_changes=[paused]`), its own URL per host (never the nic-guard or zot URL), `doppler_secret` per host.
- `server.tf`: `terraform_data.web_bash_synthetic_install` (running host) with unit content in the trigger hash, and the web-2 twin; both in the `-target` list of `.github/workflows/apply-web-platform-infra.yml`.
- `cloud-init.yml` + `soleur-host-bootstrap.sh` + `web-probe-envwrite.sh`: fresh-host path; `Dockerfile`/`.dockerignore` and the user-data size budget.
- `arm-heartbeats.sh`: two literal `arm_one` lines (web-1, web-2) for the new beat; `arm-heartbeats.test.sh` row that fails when any `var.web_hosts` member lacks a call. **Arming budget:** each call's deadline is `period + grace - 40` = 2660 s, which breaks the workflow ladder (Kieran). The work phase re-derives the ladder in `terraform-target-parity.test.ts` "ARM gate's deadlines fit its job" and the workflow `timeout-minutes`, preferring a smaller explicit per-call arming deadline (the nic-guard precedent is 440) over raising the job timeout; whichever is chosen is recorded in the ADR-079 addendum. Arming runs after the unit exists on the host, never before.
- `vector.toml` three arrays; `vector-admission`, `vector-pii-scrub`, `journald-config`, `doppler-injection-bound`, `fresh-boot-parity`, `web-host-provisioner-parity` (`FLOOR_BLOCKS`), `suite-shard-legs.tsv`, `heartbeat-manifest.ts` row, `heartbeat-live-reconcile`, `terraform-target-parity`, `heartbeat-reprovision-parity`.
- Re-measure the live Better Stack heartbeat object count before adding two beats (`SOLEUR_HEARTBEAT_RECONCILE_INVENTORY`; the model's 13 is a 2026-09-15 figure).
- C4: `model.c4` Better Stack description counts; the host-to-container exec is a host-internal call, explicitly not modeled as a new relationship; run `plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 3 — Docs

ADR-079 addendum (runtime synthetic `adopting`, selector ruling, arming-budget choice, root-uid residual) and a `canary-probe-set.md` runtime-synthetic section. One note on #10455 listing what shipped, what moved to PR-B, and that the spec is superseded.

## Files to Create

`apps/web-platform/infra/web-bash-synthetic.{sh,service,timer,test.sh}`; a sourced verdict-mapping function file under `apps/web-platform/infra/lib/`.

## Files to Edit

`apps/web-platform/infra/{web-probe.tf,server.tf,cloud-init.yml,soleur-host-bootstrap.sh,web-probe-envwrite.sh,arm-heartbeats.sh,arm-heartbeats.test.sh,vector.toml,ci-deploy.sh,fresh-boot-parity.test.sh,web-host-provisioner-parity.test.sh,journald-config.test.sh,doppler-injection-bound.test.sh,suite-shard-legs.tsv}`; `apps/web-platform/infra/lib/sdk-bash-probe.mjs`; `apps/web-platform/test/infra/{vector-admission,vector-pii-scrub}.test.sh`; `apps/web-platform/{Dockerfile,.dockerignore}`; `plugins/soleur/lib/heartbeat-manifest.ts`; `plugins/soleur/test/{heartbeat-live-reconcile,terraform-target-parity,heartbeat-reprovision-parity,cloud-init-user-data-size}.test.ts`; `.github/workflows/apply-web-platform-infra.yml`; `knowledge-base/engineering/architecture/diagrams/model.c4`; `knowledge-base/engineering/architecture/decisions/ADR-079-*.md`; `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`.

## Open Code-Review Overlap

One match, acknowledged: #2197 (billing types) names `apps/web-platform/infra/server.tf`. Different concern; stays open; this PR does not touch the billing blocks.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm)

### Engineering
**Status:** reviewed
**Assessment:** CTO classified every item and, at plan review, ruled the selector, split, verdict-mapping and debt-issue forks (above). Architecture review added the container-safety and deploy-swap requirements.

### Product
**Status:** reviewed
**Assessment:** CPO: the synthetic is the highest outage-risk reduction and must page on its own first failure; wording and outreach about the 10-day outage are operator brand calls, untouched here.

### Legal
**Status:** reviewed
**Assessment:** CLO: no Article 30 change; the synthetic carries no tenant data. The persisted-output exposure question moved to PR-B.

No Product/UX Gate: no user-facing surface.

## Infrastructure (IaC)

### Terraform changes

Existing root `apps/web-platform/infra/`: `betteruptime_heartbeat.web_bash_synthetic` (`for_each = var.web_hosts`), `doppler_secret` per-host URL, `terraform_data` install blocks (running host and web-2 twin). Providers/pins unchanged. Heartbeat URLs reach the host through Doppler into the 0600 env file written by `web-probe-envwrite.sh`; no `TF_VAR` default carries a secret.

### Apply path

Running hosts: `terraform_data` SSH provisioners via the push-apply workflow, no replace, no downtime. Fresh hosts: cloud-init plus `soleur-host-bootstrap.sh`. Blast radius: a timer that only execs into the container; a failing unit affects only its own heartbeat. **Image-ordering note:** the probe lives in the container image, so the first apply may land before the image carrying the runtime entrypoint is running; the script treats a missing entrypoint as `no_ping reason=probe_absent`, never `fail`.

### Host fan-out

`web-1`: install block. `web-2`: `web_bash_synthetic_install_web2` twin, no credential material beyond its own per-host heartbeat URL, in the `-target` list. Meaningful on both (both run the web container). `FLOOR_BLOCKS` bumped per new SSH block.

### Distinctness / drift safeguards

One URL per unit; beats born `paused=true`, armed by literal `arm_one` calls for every `var.web_hosts` member (test row enforces); unit content in the provisioner trigger hash.

### Vendor-tier reality check

Heartbeat object count re-measured in Phase 2. If the vendor rejects 900/1800, fall back to the closest accepted values and record them in the ADR addendum. The Logs-alert paid-tier question belongs to PR-B.

## Observability

```yaml
liveness_signal:
  what: per-host Better Stack heartbeat web_bash_synthetic, pinged only on a verified pass
  cadence: timer every 900 s; heartbeat period 900 s, grace 1800 s
  alert_target: Better Stack incident policy (email; Slack wake per ADR-260 where verified)
  configured_in: apps/web-platform/infra/web-probe.tf
error_reporting:
  destination: journald SyslogIdentifier=web-bash-synthetic -> Vector host_scripts_journald -> Better Stack Logs; fail also sends heartbeat /fail
  fail_loud: heartbeat /fail on sdk_bash_smoke_failed; a missing beat pages through the dead-man grace
failure_modes:
  - mode: sandbox Bash broken between deploys
    detection: nonce missing from the real tool_result (verdict=fail)
    alert_route: heartbeat /fail -> Better Stack incident
  - mode: timer stopped, host dark, unit failed, vector path broken
    detection: no heartbeat within period+grace
    alert_route: Better Stack heartbeat incident (independent of the log path)
  - mode: no_ping for many consecutive cycles (long deploy lock, drained host, probe absent)
    detection: consecutive_no_ping journaled; the beat goes dark after period+grace
    alert_route: Better Stack heartbeat incident; the journal tells a skip from a dead host
  - mode: synthetic harms the shared container (memory or process pile-up)
    detection: memory_pressure skip reason; in-container timeout -k bounds orphans
    alert_route: no_ping reason=memory_pressure in journald; web uptime monitors
logs:
  where: Better Stack source soleur-inngest-vector-prd (shared), host_name discriminates
  retention: per source configuration
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep web-bash-synthetic
  expected_output: SOLEUR_WEB_BASH_SYNTHETIC verdict=pass
  credentials_required: "Doppler soleur/prd_terraform BETTERSTACK_QUERY_* read connection — no unauthenticated probe can read the log warehouse"
```

## Encryption Posture

```yaml
at_rest:
  - store: none introduced (heartbeat URL in a 0600 env file on the root volume, precedent web-probe-envwrite.sh)
    mechanism: no new persistent store
    evidence: the unit writes only journald and its scratch dir under /run
    defends_against: n/a
    does_not_defend: the heartbeat URL on the host disk is protected by file mode and host root only
    disclosed_as: encryption-posture-ledger.json unchanged (no new store)
    live_verification: not applicable
in_transit:
  - connection: host -> Better Stack heartbeat (HTTPS)
    tls: yes
    cert_verification: on
    does_not_defend: a compromised host can ping a false green
    disclosed_as: ADR-079 addendum
  - connection: host -> container via docker exec (local unix socket, no network)
    tls: n/a (local)
    cert_verification: n/a
    does_not_defend: any local root can exec
    disclosed_as: ADR-079 addendum
```

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-079 (runtime synthetic `adopting`; selector, arming-budget and root-uid rulings). No new ordinal.

### C4 views

Better Stack is modeled in `model.c4` (system "Better Stack", per-host heartbeats). Checked against all three `.c4` files: no new external actor, external system, data store or actor-to-surface access relationship; the host-internal exec is not modeled. Derived heartbeat counts in that description move; green `plugins/soleur/test/c4-count-parity.test.sh` is required.

### Sequencing

The addendum is authored in this PR describing the adopting state.

## Guard Contract

### Guard 1 — web-bash-synthetic (no false green, no false red on a deploy)

**Property.** The heartbeat is pinged green only on a verified pass: a `no_ping` run never pings, a failed run pings `/fail`, and a run overlapped by a deploy swap is never a `fail`.
**Assembly.** Every exit path of `web-bash-synthetic.sh` (pass, fail, each `no_ping` reason, host-timeout before and after dispatch) and every `var.web_hosts` member's `arm_one`. The chokepoint is the single `ping_heartbeat` function all exits flow through, and the single shared verdict-mapping function used by both this script and `run_sdk_bash_smoke`.

**Mutation matrix.**

| # | Mutation | Must go RED |
|---|----------|-------------|
| 1 | Replace the nonce check with `true` | nonce-missing case |
| 2 | Ping on any `no_ping` path | every `no_ping` case asserts zero pings |
| 3 | Map rc 124 before dispatch to `fail` | host-timeout-before-dispatch case |
| 4 | Treat a changed container start time as `fail` | deploy-swap-mid-run case asserts `no_ping reason=container_restarted` |
| 5 | Ping before the verdict is computed | a case observing the ping inside the window (ping recorded before the verdict file) |
| 6 | Edit `ci-deploy.sh` to stop using the shared verdict function | a parity row asserts both callers source the same function |

Harness rows: (a) a mock `docker` that always exits 0 with no output must still drive the nonce-missing case RED; (b) must-PASS non-canonical input: a probe result with the nonce embedded mid-line among extra output. The `arm-heartbeats.test.sh` host-coverage row (add a member to `var.web_hosts` without an `arm_one`) lives in that suite.
**Anchor.** Period and grace in `web-probe.tf` are compared to the `heartbeat-manifest.ts` row (independent registry) and to live by `heartbeat-live-reconcile`; weakening the grace needs the manifest row to move too.

## Acceptance Criteria

- [x] AC1: `web-bash-synthetic.test.sh`, `arm-heartbeats.test.sh` and the parity suites pass, and each Guard 1 mutation row goes RED when applied.
- [x] AC2 (tflint is not installed locally; CI runs it): `terraform validate`/`tflint` pass for `apps/web-platform/infra/`; both install blocks are in the `-target` list; `terraform-target-parity.test.ts` (including the ARM-gate ladder) and `c4-count-parity.test.sh` are green.
- [x] AC3: the existing `run_sdk_bash_smoke` tests pass unchanged after the verdict-mapping extraction.
- [x] AC4: the synthetic writes nothing outside its scratch dir (asserted in `web-bash-synthetic.test.sh` against the probe's file operations).
- [ ] AC5: PR body uses `Ref #10455` and never a closing keyword for #10455, #10548, #10549 or #10604; a #10455 note lists what shipped and the PR-B items.
- [x] AC6 (#10777): one debt issue (table-driven host-timer registry) is filed with the issue-filing gate's required line.
- [ ] Post-merge verification (owned by `soleur:postmerge`, not an AC of the diff): every `var.web_hosts` beat reads not-paused through `arm-heartbeats.sh`'s read-back, and the `discoverability_test` returns `SOLEUR_WEB_BASH_SYNTHETIC verdict=pass` after the first timer run.

## Test Scenarios

Deploy lock held; container not running; container replaced mid-run; memory above threshold; nonce mismatch; host timeout before and after dispatch; heartbeat URL missing; probe entrypoint absent in the running image; web-2 twin identical; fresh-host cloud-init carries the unit; flag-OFF resolver returns the base artifact.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled.
- Merging does not arm the beat: a heartbeat born paused is dark until `arm_one` runs for every host; the post-merge check verifies it.
- The ARM-gate ladder is derived from `period + grace - 40`; do not set grace without re-deriving it.
- `FLOOR_BLOCKS`, the three `vector.toml` arrays and `suite-shard-legs.tsv` are the most-forgotten registrations.
- #10548's soak and the flag enable are untouched and must not be bundled.
