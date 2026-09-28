---
title: "fix(infra): move the inngest host's first-boot bootstrap pull into a latched, retrying systemd unit (delivered dark)"
date: 2026-09-28
slug: fix-inngest-bootstrap-pull-retrying-unit
branch: feat-one-shot-8562-inngest-bootstrap-retrying-unit
issue: 8562
closes: none
type: bug
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 review: soleur:engineering:infra:terraform-architect confirmed every systemd artifact
     in this plan is delivered by cloud-init write_files inside cloud-init-inngest.yml (the
     templatefile source of hcloud_server.inngest.user_data) and armed from runcmd. There is no SSH
     step and no operator systemctl step. Delivery is the existing gated inngest-host-replace
     dispatch, deferred as a tracked follow-through. -->

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

# fix(infra): move the inngest host's first-boot bootstrap pull into a latched, retrying systemd unit

## Enhancement Summary

**Deepened on:** 2026-09-28.

**Sections enhanced (12):**

- Design (script + a Research Insights subsection)
- Implementation Phases 1.4, 4.3, 5.3, 6.1 and 6.3
- Observability (rewritten)
- Downtime & Cutover (new, gate 4.55)
- Guard Contract (Guard 8 added; rows 46 → 59)
- Test Scenarios (rewritten)
- Acceptance Criteria
- Architecture Decision
- Deferrals
- Risks

**Agents used:**

- `soleur:engineering:review:architecture-strategist`
- `soleur:engineering:review:observability-coverage-reviewer`
- `soleur:engineering:review:security-sentinel`
- `soleur:engineering:review:test-design-reviewer`
- `soleur:product:spec-flow-analyzer` (the plan-phase SpecFlow step had not run, so it runs here)
- `soleur:engineering:research:best-practices-researcher` (systemd 255 semantics; systemd-in-docker
  on GitHub runners)
- a verify-the-negative and attribution audit: 27 of 29 anchors confirmed, and all negative claims
  confirmed.

**Gates:** 4.6 User-Brand passes. 4.7 Observability passes: all 5 fields, the verb is on the
allowlist, credentials are declared. 4.8 found no PAT shapes. 4.9 does not apply (no UI). 4.10
Encryption Posture passes. 4.11 Guard lint passes (8 entries). 4.55 fired and is satisfied by the
new `## Downtime & Cutover`. 4.5 did not trigger. Every cited rule ID is active. All 18 cited
issue and PR numbers were verified live, and the prescribed labels exist.

### Key Improvements

1. **Cutover-FSM collision closed (architecture P1).** A retried bootstrap during an operator
   `op=resume` could abort the flip, and recovering from `aborted` needs a recut. The script now
   stops `inngest-cutover-flip.timer` and `inngest-luks-cutover.timer` and waits a bounded time
   for in-flight steps before every bootstrap run (T15, Guard 2 row 10).
2. **Mount precondition withdrawn (architecture P2).** Kieran's `mountpoint -q /mnt/data` check
   would have turned today's degraded-but-serving first boot (a failed LUKS stage leads to
   SQLite-only mode) into a dark retry loop. The existing Redis mapper-identity guard is stronger.
3. **Follow-through probe redesigned (observability P1).** The old design grouped by newest boot,
   which reads a healthy latched host as TRANSIENT forever. The probe now anchors on
   `provision-unit-armed` plus the cloud-init `iid`, has distinct TRANSIENT reasons, and prints
   its verdict to stdout.
4. **Off-host channel survives a Doppler outage.** The bs-token is re-staged per attempt, and the
   EXIT trap also emits `provision_attempt_failed` to Sentry through the baked DSN.
5. **Signal-safe children.** The pull and the bootstrap run as `& wait` with TERM forwarding, so a
   `TimeoutStartSec` kill reports before SIGKILL (research: dash defers traps until its foreground
   child exits).
6. **Tier A never skips.** It reuses the proven G4 fixture-root path-rewrite harness
   (`cloud-init-inngest-bootstrap.test.sh`) under `dash -u`. It requires exact return codes, treats
   rc 2 or 127 as an instrument fault, and adds a control row (test-design P1s).
7. **Security hardening.** An xtrace refusal (the token is piped to `docker login` and the journal
   is persistent), per-attempt clearing of the fixed `/tmp` staging names, the extract container
   addressed by the ID `docker create` returns, a counter that cannot wedge, and the retired `/run`
   sentinel forbidden (Guard 8).
8. **`TimeoutStartSec` derived from step bounds** (about 45 min), not from healthy history.

### New Considerations Discovered

- `betteruptime_heartbeat.inngest_prd` is `paused = true`. Non-pull provision failures page nobody.
  This is a pre-existing gap. Closing it needs a `sentry/**` edit, which triggers a production
  apply, so it is deferred to a new issue.
- There is no repo precedent for systemd as PID 1 in a container. Tier B is novel
  infrastructure; every row it would catch also has a static or Tier A detector.
- `ci-deploy.sh` cannot run the bootstrap on the dedicated host, which has no webhook. So no two
  bootstraps can overlap there (verified).
- A plan-provenance pin drifted: line numbers were measured on merge-base `7bc9bde2db`, not
  `f1f2336156`. Corrected.

## Overview

The dedicated Inngest host is the fleet's only scheduler. It fetches its bootstrap image, extracts
`inngest-bootstrap.sh` from it and runs it exactly once. That happens in the last item of
cloud-init `runcmd` in `apps/web-platform/infra/cloud-init-inngest.yml` (the item headed
`# --- Extract + run inngest-bootstrap.sh from the baked OCI image`).

`runcmd` runs once per instance. If that one attempt misses, nothing retries it, and a reboot does
not help either. A miss can come from a private NIC that converges after the 150 s wait, a zot
outage, or a transient docker or Doppler error. The only recovery today is another
`inngest-host-replace` dispatch plus a human-approved `cutover-inngest.yml -f op=resume`.

This plan moves three things out of `runcmd`:

- the zot login;
- the boot-credential isolation self-check;
- the pull → extract → bootstrap → health block.

They go into one script, `/usr/local/bin/soleur-inngest-provision`, run by a `Type=oneshot`
systemd unit. The unit:

- **retries on failure without limit, at a bounded rate.** Settings: `Restart=on-failure`,
  `RestartSec=120`, `StartLimitIntervalSec=0`, and a per-attempt `TimeoutStartSec`.
- **tries again on every boot until it has succeeded once.** A boot timer starts it, and a latch
  file, written only after `inngest-bootstrap.sh` exits 0, switches it off.
- **does nothing when a host that already provisioned reboots.** That matches today's behavior.

`runcmd` keeps its first-boot-only work: the LUKS stage, the NIC wait, and the env-file and user
writes. Its last items now enable the timer and start the unit without blocking. The pull moves;
it is not copied.

**Delivered dark.** Nothing in this PR reaches the live host at merge. The change re-renders
`hcloud_server.inngest`'s user_data, and that reaches the host only through the next
operator-approved `inngest-host-replace`.

The second half of #8562, the forced-race rehearsal, needs a Terraform-managed throwaway host. That
is a production-account write this session may not make, so it becomes a separate follow-up issue.
In its place, this PR carries an offline **Tier B** rehearsal: systemd 255 running as PID 1 in a
pinned Ubuntu 24.04 container. It exercises the real retry, latch, timer and `EnvironmentFile`
behavior without any production account. #8562 stays open as the follow-through for live delivery,
with a probe enrolled.

## Merge-Consequence Analysis (measured, required by the brief)

Every claim cites a file and anchor. Line numbers were measured on this branch's base (`origin/main`
as of 2026-09-28, merge-base `7bc9bde2db`; a deepen-plan audit found two drifted by a few lines
against the older `f1f2336156`). The quoted anchor is authoritative
(`cq-cite-content-anchor-not-line-number`).

**Planned diff surface (exhaustive).**

- `apps/web-platform/infra/cloud-init-inngest.yml`.
- Existing test suites under `apps/web-platform/infra/`, only when a re-point is needed. None is a
  `cp` carrier.
- One new suite, `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`.
- One new follow-through probe under `scripts/followthroughs/`.
- Knowledge-base files: the ADRs, the C4 model and its generated JSON, the runbooks, and the
  plan and spec.

**Not touched:** `inngest-host.tf`, `inngest.tf`, `inngest-bootstrap.sh`, any file `cp`-staged by
`build-inngest-bootstrap-image.yml`, `vector.toml`, `apps/web-platform/infra/sentry/**`,
`variables.tf`, `zot-registry.tf`, `cloud-init-registry.yml`, and any `.github/workflows/*` file.

### (a) Push-triggered workflows the diff wakes

| Workflow | Trigger anchor | Fires? | Consequence |
|---|---|---|---|
| `apply-web-platform-infra.yml` | `on.push.paths` `- "apps/web-platform/infra/**"` (`:98`) | **Yes** | The workflow run starts. **Kill switch:** the squash-merge commit body carries `[skip-web-platform-apply]` on its own line. The `preflight` job's `kill_switch` step (`:403-417`) then outputs `skip=true`, and `apply`'s `if: needs.preflight.outputs.skip != 'true' && (…)` (`:437-439`) skips the job. **No apply runs.** **Defense in depth, even without the kill switch:** the push `apply` job's `-target=` list (185 addresses, `:428-1525`) holds **no `hcloud_server.*`**, `hcloud_server_network.inngest` or `hcloud_volume_attachment.inngest*`. Outside comments, `hcloud_server.inngest` is referenced only as three attachment `server_id`s (`inngest-host.tf:610`, `inngest-redis-luks.tf:150`, `network.tf:85`), and none of those is targeted. `hcloud_firewall_attachment.inngest` exists only as a `removed { … destroy = false }` tombstone (`inngest-host.tf:630-645`). Every job that can reach the server is `workflow_dispatch`-gated (`inngest_host` `:1733`, `inngest_host_replace` `:1924`). |
| `web-platform-release.yml` | `on.push.paths` `- 'apps/web-platform/**'` (`:13-17`); inner `check_changed` `path_filter: "apps/web-platform/ …"` (`:128`) | **Yes (unavoidable)** | Any merge under `apps/web-platform/**` cuts a `web-v*` release, builds the image and rolls it out to the production web hosts. No commit-message kill switch exists; `skip_deploy` is dispatch-only. The template lives under that tree, so **no implementation of #8562 can avoid this**. Measured: today's infra-only merge #9071 (`3339fb01e0`) ran it as push run `36407993582` (success). What gets deployed is **unchanged app code**: a version-bump rolling deploy, not an infra apply and not a host replace. Recorded for the operator in `specs/<branch>/decision-challenges.md`. |
| `mint-inngest-bootstrap-tag.yml` (PR #9079) | `paths: 'apps/web-platform/infra/inngest*'`, `vector.*`, `cat-inngest-*` + three workflow/script paths (`:39-46`) | Only if an `inngest-*.test.sh` is edited | `cloud-init-inngest.yml` and the new `cloud-init-inngest-provision-unit.test.sh` start with `cloud-init`, so they do not match. A re-pointed `inngest-*.test.sh` wakes the workflow, but its `decide` stage mints only when one of these differs from the newest merged `vinngest-v*` tag: a `cp` carrier blob or mode (`build-inngest-bootstrap-image.yml:350-371`), a pin in `mint-inngest-bootstrap-tag.sh` `PINS=(inngest_cli_version inngest_cli_sha256 vector_version vector_sha256)` (`:380`), or the Dockerfile heredoc. A test file is none of these, so the result is `noop`. **Proven pre-merge** by `bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run` (no network, no credential), which must print `noop`. **Hard constraint:** do not modify `inngest-bootstrap.sh`, `vector.toml` or any other carrier. A one-byte comment edit mints a tag and dispatches a build. |
| `registry-host-replace-dispatch.yml` (PR #9120) | `paths:` `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, itself (`:37-50`) | **No** | Not in the diff. No registry replace. |
| `validate-vector-config.yml` | `apps/web-platform/infra/*.sh` | Yes (new `.sh` suite) | Read-only (`permissions: contents: read`). |
| `infra-validation.yml`, `main-health-monitor.yml` | CI | Yes | Tests only. The new suite registers by filesystem presence ("REGISTRATION IS NOW THE FILESYSTEM", `infra-validation.yml:534`, ADR-252), so there is **no workflow edit**. `inngest-userdata-budget` is a CI job (`infra-validation.yml:1213-1225`). |
| `apply-sentry-infra.yml` | `apps/web-platform/infra/sentry/**` | **No** | Not touched, so no Sentry rule is added. See the Cut List. |
| `build-inngest-bootstrap-image.yml` | `push: tags:` only | **No** | No tag is pushed. |
| `apply-deploy-pipeline-fix.yml`, `apply-inngest-rls.yml`, `zot-image-mirror.yml` | named single files | **No** | None is touched. |
| `scheduled-terraform-drift.yml` | `workflow_dispatch` only | **No** | Not push-triggered. If someone dispatches it before delivery, it reports `hcloud_server.inngest` user_data drift. That drift is expected. |

### (b) user_data re-render and `ignore_changes`

- `hcloud_server.inngest.user_data` is `local.inngest_user_data_b64gz` (`inngest-host.tf:475`). That
  value is `base64gzip` of a `templatefile("cloud-init-inngest.yml", …)` render with comment lines
  stripped (`local.inngest_rationale_strip`). This diff changes non-comment lines, so **the
  rendered user_data changes.**
- `lifecycle { ignore_changes = [ssh_keys] }` (`inngest-host.tf:491-493`). The comment "Deliberately
  NO lifecycle.ignore_changes=[user_data]" (`:477-481`) confirms user_data is not ignored. **Any
  plan that reaches `hcloud_server.inngest` plans a force-replace.**
- Only `workflow_dispatch` jobs reach it, per (a). So the change is **delivered dark**. It lands at
  the next operator-approved `apply_target=inngest-host-replace` (`:1922-1924`), followed by a
  human-approved `op=resume` because `INNGEST_CUTOVER_FLIP=done`.
- **Measured baseline:**
  - The live host was last replaced by run `36327637204` (2026-09-27T14:55Z, job
    `inngest_host_replace`).
  - The only later template commit is #9071, and it changed **comment lines only**. `git show
    3339fb01e0 -- …cloud-init-inngest.yml` shows zero non-comment `+/-` lines, and the render
    strips comment lines.
  - **So this PR creates the first pending delta.**
- **Side effect to disclose (not a production write).** Until delivery, any dispatch that requires
  zero actions on `hcloud_server.inngest` will refuse:
  - `inngest-volume-recut` Guard 1 (`:2487-2514`);
  - the `inngest_host` birth shape gate `server_touched` (`:1879`).

  Every inngest cloud-init PR creates this same state (#8560 did too).
- **Payload cap:** `bash apps/web-platform/infra/inngest-userdata-budget.sh` measured the stored
  payload at 16,400 B against a 32,768 B cap (headroom 16,368 B). The diff moves bytes within the
  same template and adds about 1.5 KB of raw unit text. The CI job above and the tf precondition
  (`USER_DATA CAP TRIPWIRE`) both gate it. The precondition is pruned on the `-target` push path,
  which is why the CI job is the merge-time gate.

### (c) vinngest-v* auto-mint

Covered in (a): the new files do not trigger it. It is `noop` by construction even where an
`inngest-*.test.sh` edit wakes it, and the dry-run proves that. **No `vinngest-v*` tag is minted.**

### (d) Registry replace dispatcher (#9120) and the inngest replace path

- `registry-host-replace-dispatch.yml` is registry-only and does not fire.
- **No inngest analogue exists.** `grep -l cloud-init-inngest .github/workflows/*.yml` returns only
  `apply-web-platform-infra.yml`, `build-inngest-bootstrap-image.yml` (tag trigger),
  `infra-validation.yml` and `main-health-monitor.yml`. Nothing auto-dispatches an
  `inngest-host-replace`.

**Verdict.**

- The merge runs **no infra apply**, provided `[skip-web-platform-apply]` is in the merge commit
  (the push target set could not reach the host anyway). It also runs **no host replace, no
  `vinngest-v*` mint and no registry replace**.
- The change is **delivered dark**. It takes effect at the next operator-approved
  `inngest-host-replace` plus `op=resume`, recorded as #8562's follow-through and not performed here.
- **No split is needed**, and the diff has no workflow edit.
- The one automatic production action the merge does cause is the **standard `web-v*` release**,
  which every `apps/web-platform/**` merge triggers. It is disclosed, deploys unchanged app code,
  and no path under this template can avoid it.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief / research) | Reality (measured) | Plan response |
|---|---|---|
| "#8560 fixed #8539, cited predecessor" | PR #8560 MERGED 2026-09-23. #8539 CLOSED; its probe `inngest-private-nic-8539.sh` passed after the 2026-09-27 replace | Treated as a predecessor. The NIC wait stays in `runcmd` |
| Deferral note: the restructure is "coupled to the LUKS stages and the cutover flip" | The LUKS stage is its own earlier `runcmd` item, and `inngest-luks-open.service` already reopens it on every later boot. The flip is installed **by** `inngest-bootstrap.sh`, and its latch lives on `/mnt/data`. `cutover-inngest.sh` gates on `inngest-cutover-flip` liveness rows, not boot markers | The unit orders `After=inngest-luks-open.service`. LUKS and the flip are untouched. The runbook says to run `op=resume` after `bootstrap-done` |
| Learnings agent: "inngest host has `ignore_changes=[user_data]`" | **False** (`inngest-host.tf:477`, `:493` ignores `ssh_keys` only) | Discarded |
| Learnings agent: "force a soft reboot after NIC attach" | ADR-115 rejects reboot-for-inngest | Discarded. Retry replaces reboot |
| Repo agent: "no standalone budget script" | **False.** `inngest-userdata-budget.sh` exists and runs in CI | Used as the gate |
| Brief's merge checklist (a)-(d) | It omits `web-platform-release.yml`, which fires on every `apps/web-platform/**` merge (surfaced by terraform-architect review, then measured) | Added to (a) and disclosed as a decision challenge |
| #6985 "touches the same runcmd surface" | #6985 names the **web** host's `cloud-init.yml`. The inngest file exports its token with `set -a`. **But** the moved block's `DIAG_BOOT="$(timeout 20 doppler secrets get …)"` works today only because every `runcmd` item shares ONE `/bin/sh` where the isolation item ran `set -a; . /etc/default/inngest-doppler` | **Not folded in**: different host, and its fix activates zot selection on web. **It does interact:** leaving the shared shell would re-create the #6985 class here. Guards 4 and 7 prevent that |
| `inngest-bootstrap.sh:58` SOLEUR-DEBT: "when a dedicated-host in-place re-bootstrap path is ever added … fail-close the `DOPPLER_PROJECT` default" | A retry after a failed attempt re-runs `inngest-bootstrap.sh` on the same host, with the same pinned bytes and never after success | A carrier-side fix would mint a tag, which is forbidden. The plan adds a caller-side static pin (Guard 4 row 5) and records the rest on #6780 |

## Research Insights

### Premise validation (Phase 0.6)

- #8562 is OPEN (`deferred-scope-out`, `type/chore`, `priority/p2-medium`), with no closing PR.
- #8539 is CLOSED. PR #8560 merged 2026-09-23T15:43Z.
- PR #9079 merged 2026-09-28T09:30Z. PR #9120 merged 2026-09-28T11:25Z.
- #6985 is OPEN. Its trigger #6969 is CLOSED. #6780 is OPEN. #6122 is OPEN.
- The template and every cited anchor exist on `origin/main`.
- **ADR corpus mechanism check.** ADR-115 rejects "Reboot-for-inngest" *because* `runcmd` runs once
  per instance. It does not reject a retrying unit. ADR-115's #8210 amendment accepts a
  Doppler-run oneshot with a standing retry as the reboot-safe equivalent for git-data. So there is
  precedent, and no rejected alternative is being revived.

### Property List (Phase 0.6b)

- **P1.** A failure anywhere in login → isolation → pull → extract → bootstrap during the
  first-boot window recovers on the same host without a replace.
- **P2.** A host whose provisioning never completed tries again on every boot.
- **P3.** A host whose provisioning completed is not re-provisioned by a reboot, as today.
- **P4.** Every attempt's outcome is visible off-host without SSH. Existing stage names are kept
  and gain an attempt number. Recovery reads as `bootstrap-done` after an `inngest_pull_fatal`.
  Paging is honest and bounded.
- **P5.** The merge causes no infra apply, host replace, `vinngest-v*` mint or registry replace.
- **P6.** Every `doppler` call on the moved path still receives an exported token and `HOME`, so
  the #6985 class does not recur.
- **P7.** Retrying is bounded in rate and per attempt, and a host that keeps failing keeps
  signaling.
- **P8.** Nothing the moved block used to inherit implicitly from the shared `runcmd` shell is lost.

### Cut List (Phase 0.6b)

| Cut | Property it would buy | Why it is cut |
|---|---|---|
| `OnFailure=` reporter unit (git-data precedent) | P4 | The script already emits on every failure arm, and an EXIT trap (with a TERM/INT trap feeding it) covers unnamed arms. |
| New or renamed Sentry alert rule for the new stages | P4 | Already bought by `zot_mirror_fallback_rate` (`stage == inngest_pull_fatal`). Editing `sentry/**` would also fire `apply-sentry-infra`, a production write. |
| Moving the NIC wait into the unit | P1 | Already bought by the retry. Per-attempt `private_nic_*` events would also re-page `web_private_nic_boot_gate`. |
| Start-limit ladder plus a 15-min standing timer (git-data shape) | P7 | Bought more simply by `StartLimitIntervalSec=0` and `RestartSec=120`. The ladder existed only to give the cut `OnFailure=` reporter a terminal state. |
| `RestartSteps=` / `RestartMaxDelaySec=` backoff | P7 page volume | Not needed: page volume is capped by the rule's 23-minute throttle on a single grouped issue, and a fixed `RestartSec` keeps recovery latency low. |
| Power-of-two Sentry page decay (proposed by the Phase 2.8 review, cut at plan review) | P4/P7 page volume | Duplicates the throttle already provided by `frequency_minutes = 23` on one grouped issue. |
| Dedicated `inngest_provision_recovered` event (cut at plan review) | P4 | Duplicates `bootstrap-done`, which already follows an `inngest_pull_fatal` on recovery. |
| Latch content `IREF/AT/ATTEMPT` (cut at plan review) | none | Nobody can read it on a no-SSH host, and the image is already recorded in `/etc/default/soleur-inngest-image`. The latch is an empty file. |
| Static free-variable analyzer for Guard 7 (cut at plan review) | P8 | Fragile over dash heredocs and quoting; a line scanner is not a lexer (Sharp Edges). Replaced by a runtime check: the harness runs the script under `sh -u` in a clean environment. |
| `RuntimeDirectory=` + `RuntimeDirectoryPreserve=` (cut at plan review) | P4 attempt counter | `StateDirectory=` already exists for the latch and can hold the counter too. |
| `SyslogIdentifier=` shipped via `vector.toml` | P4 | `vector.toml` is a `cp` carrier, so editing it would mint a tag. The phone-home and Sentry channels are the unit's off-host path. The default journald identifier stays host-local. |
| Editing `inngest-host.tf` | none | Not needed: no new template variable. It would also wake the mint filter. |
| Fixing the `inngest-bootstrap.sh` SOLEUR-DEBT in the carrier | P6-adjacent | Editing the carrier would mint a tag. Instead, a note on #6780 plus a caller-side pin. |
| Folding #6985 | none | Not a property of this ask. Acknowledged, not folded. |

### Relevant files (measured)

`apps/web-platform/infra/cloud-init-inngest.yml`:

- `write_files` (`:42`) already contains unit precedents: `inngest-luks-open.service` (`:123`),
  `inngest-nftables.service` (`:241`) and `inngest-bs-token-restage.service` (`:658`). The last one
  sets `TimeoutStartSec`, `RemainAfterExit` and the `SyslogIdentifier` rule, per #6536.
- Emitters: `inngest-boot-phone-home.sh` (`:271`) and `soleur-boot-emit` (`:388`).
- NIC wait: `soleur-inngest-nic-wait` (`:487`).
- `runcmd` starts at `:686`:
  - `/etc/default/inngest-doppler` written with `HOME=/root` (`:753`);
  - docker restart (`:1284`);
  - zot creds (`:1314`);
  - NIC wait (`:1320`);
  - zot login (`:1341-1356`);
  - isolation (`:1421-1440`);
  - deploy user (`:1448-1451`);
  - `/etc/default/inngest-server` (`:1464-1465`);
  - probe credential (`:1485-1497`);
  - pull, extract, bootstrap and health (`:1506-1823`, end of file).

Other files:

- `apps/web-platform/infra/inngest-bootstrap.sh`: the "Idempotent contract" (`:4`) and the
  version-match short-circuit (`:103-118`). ci-deploy re-runs it in place (`:1304`). It starts no
  background processes: no `&`, `nohup`, `setsid` or `systemd-run`.
- `apps/web-platform/infra/git-data-luks-reopen.{service,timer}` and their test: the precedent for
  measured systemd retry semantics and for `systemd-analyze verify`.
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`: the precedent for a rung-1
  container rehearsal. It uses a pinned Ubuntu 24.04 image, `--privileged`, `_skip` when docker is
  absent, and `arm_skip` for apt-archive state (ADR-188).
- `.github/scripts/bump-inngest-bootstrap-pin.sh` (`:335-341`) requires **exactly 2** well-formed
  `soleur-inngest-bootstrap:vX.Y.Z` refs per file.
- Tests coupled to the moved block (anchor-grep hit counts):
  - `cloud-init-inngest-bootstrap.test.sh` (47);
  - `cloud-init-inngest-zot-pull-mutation.test.sh` (24; its NIC-G1 and G4 guards key on `runcmd`
    list positions);
  - `inngest-host.test.sh` (25; §9/§9b isolation);
  - `inngest-redis-luks.test.sh` (13);
  - `inngest-boot-emitter.test.sh` (3);
  - `inngest-nic-wait.test.sh` (3).
- Consumers of boot markers:
  - `scripts/cutover-inngest.sh` gates on flip liveness rows, not boot stages;
  - `scripts/followthroughs/inngest-host-not-serving-7674.sh` reads `inngest_zot` +
    `bootstrap-done` (#7674 CLOSED);
  - `inngest-zot-boot-7462.sh` is retired;
  - `tests/scripts/test-sentry-alert-live-fidelity.sh` checks the literal `inngest_pull_fatal`.

**Local measurement (systemd 261, user units, non-production, 2026-09-28).** A oneshot with
`Restart=on-failure`, `RestartSec=2`, `StartLimitIntervalSec=0` and
`ConditionPathExists=!<latch>`, whose fixture fails twice and then writes the latch, converged to
`ActiveState=active SubState=exited Result=success NRestarts=2`. A timer with `OnBootSec=90s`,
activated long after boot, **fired immediately**: attempt 1 at 17:29:48, the same second the timer
started. So `enable --now` on the timer is itself a trigger. Tier B re-measures both on
production's systemd 255.

### Institutional learnings applied

- `2026-07-06-cloud-init-user-data-cap-bake-bodies-and-set-e-scope-fix-ungates-security-checks.md`.
  `runcmd` is ONE `/bin/sh`. **The inverse hazard applies here:** leaving that shell drops its
  implicit state. This drives P8, Guard 7 and the Phase 1.2 census.
- `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`. Set PATH
  explicitly under systemd.
- `2026-09-28-auto-mint-review-every-p2-was-a-tag-created-and-never-built.md` (PR #9079). This is
  the source of the rule that no carrier byte may change.
- `2026-09-22-inngest-host-replace-private-nic-race-postmortem.md`. A single missed first-boot
  window cost about 59 minutes of scheduler-dark time, which is the cost P1 removes.
- `2026-06-18-inngest-secrets-env-not-argv-and-detection-sentinel-swap.md`. Secrets go through
  env, never argv.
- `inngest-bootstrap.sh` `#7797`. No xtrace under a live credential set.

### CLAUDE.md / AGENTS conventions carried

- `hr-all-infrastructure-provisioning-servers`
- `hr-prod-host-config-change-immutable-redeploy`
- `hr-no-ssh-fallback-in-runbooks`: no latch-delete or `systemctl` recovery step appears anywhere.
- `hr-observability-as-plan-quality-gate`, `hr-observability-layer-citation`
- `cq-cite-content-anchor-not-line-number`
- `wg-block-pr-ready-on-undeferred-operator-steps`
- `hr-menu-option-ack-not-prod-write-auth`

## Design

### Where the boundary moves

| Stays in `runcmd` (first boot only, persistent side effects) | Moves into `/usr/local/bin/soleur-inngest-provision` (every attempt, until latched) |
|---|---|
| Doppler CLI install | docker-readiness wait |
| `/etc/default/inngest-doppler` write | idempotent pre-clean of a stale `soleur-inngest-bootstrap-extract` container |
| LUKS stage | **zot login** |
| bs-token stage and restage-unit enable | **isolation self-check**; the `/run/soleur-inngest-doppler.ok` sentinel becomes the check's own in-script status |
| `daemon.json` + docker restart | IREF/ZIREF resolution + the 3-try bounded pull |
| nftables enable | `/etc/default/soleur-inngest-image` record |
| zot creds bake | `docker create`/`cp` extract + asset staging |
| **NIC wait (once)** | `DIAG_BOOT` read |
| deploy user/group | `inngest-bootstrap.sh` run |
| `/etc/default/inngest-server` | **latch write** |
| probe credential | post-boot-health + net-health diagnostics, then an explicit `exit 0` |

The last `runcmd` items become:

```yaml
  - systemctl daemon-reload
  - systemctl enable soleur-inngest-provision.timer
  - systemctl start --no-block soleur-inngest-provision.service
  - /usr/local/bin/inngest-boot-phone-home.sh provision-unit-armed "timer=$(systemctl is-enabled soleur-inngest-provision.timer 2>&1)"
```

- **Timer enabled without `--now`.** An already-elapsed `OnBootSec=` fires the moment the timer is
  activated (measured above). `--now` would therefore be a hidden second first-boot trigger. The
  explicit `start --no-block` is the only first-boot trigger. The timer takes over from the next
  boot.
- **`--no-block` start.** A blocking start from `cloud-final` would hold cloud-init open for as long
  as the unit keeps retrying.

### The unit (via `write_files`; sketch, with the final directive set pinned by Guards 2–7)

```ini
# /etc/systemd/system/soleur-inngest-provision.service
[Unit]
Description=Provision the dedicated inngest host from its pinned bootstrap image, retrying until it succeeds once (#8562)
Wants=network-online.target docker.service
After=network-online.target docker.service inngest-luks-open.service inngest-bs-token-restage.service inngest-nftables.service
ConditionPathExists=!/var/lib/soleur-inngest-provision/done
StartLimitIntervalSec=0

[Service]
Type=oneshot
RemainAfterExit=yes
Restart=on-failure
RestartSec=120
TimeoutStartSec=45min
Environment=HOME=/root
EnvironmentFile=/etc/default/inngest-doppler
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
UMask=0022
StateDirectory=soleur-inngest-provision
ExecStart=/usr/local/bin/soleur-inngest-provision
# NO [Install]: the timer starts it on later boots; runcmd starts it on the first.
```

```ini
# /etc/systemd/system/soleur-inngest-provision.timer
[Timer]
OnBootSec=90s
[Install]
WantedBy=timers.target
```

Directive rationale:

- **No `[Install]` on the service.** `systemd.target(5)`: a target adds `After=` to every unit it
  `Wants=`. So `WantedBy=multi-user.target` would make boot completion wait on a oneshot that may
  retry for hours. Starting it from a timer creates no ordering against any target.
- **`StartLimitIntervalSec=0`** means unlimited restarts. There is no terminal state to reach, and
  a start limit would strand the host after N misses.
- **`RestartSec=120` and `TimeoutStartSec`** bound both the retry rate and each attempt.
  - Rates depend on how an attempt fails.
    - A fast-failing attempt (refused connection, isolation FATAL) takes seconds, so the rate is
      about 28 attempts an hour.
    - A zot-unreachable attempt takes about 10 minutes (up to 60 s login, then 3 × 180 s pulls
      plus sleeps), so the rate is about 5 an hour.
  - Each attempt makes at most two Doppler reads and emits about five or six phone-home rows.
  - `TimeoutStartSec` is **re-derived in Phase 1.4** from measured attempt durations: at least 3×
    the observed maximum, with a floor of 20 min.
  - Default `KillMode=control-group` is kept. Do not use `mixed`: sh defers a trap until its
    foreground child exits, and an unsignaled bootstrap child would stall the trap until SIGKILL.
- **`UMask=0022`** keeps `runcmd`'s umask, so files the bootstrap creates keep their modes.
- **Deliberately absent: `PrivateTmp`, `ProtectSystem`, `ProtectHome`, `NoNewPrivileges`.** The
  block stages assets through the host `/tmp`, and the bootstrap writes `/etc`, `/usr/local` and
  `/var/lib` and runs `systemctl`. The unit must behave the same as the shell it replaces. Guard 6
  pins these absences.
- **`EnvironmentFile=/etc/default/inngest-doppler`** without the `-` tolerance prefix. It supplies
  `HOME=/root`, `DOPPLER_TOKEN`, `DOPPLER_CONFIG_DIR` and `DOPPLER_ENABLE_VERSION_CHECK` in plain
  `KEY=VALUE` form (the `runcmd` `:753` write). A missing file should fail the attempt loudly.
- **`StateDirectory=`** holds the attempt counter and the latch, both on the root disk. The
  counter persists across reboots, so `attempt=N` counts every attempt since the host was born
  (plan review: one directive instead of a `RuntimeDirectory` + `Preserve` pair).
- **Default journald identifier.** The ExecStart basename gives `soleur-inngest-provision`, and the
  rows stay on the host. That is intentional: Vector is installed *by* the bootstrap, and shipping
  those rows would need a `vector.toml` edit, which is a mint. The unit's off-host channel is the
  phone-home plus Sentry emitters, per `hr-observability-layer-citation`.

### The script (the moved block; only the deltas are listed)

**Shell and traps**

- `#!/bin/sh`, keeping dash semantics. No xtrace. No bashisms or `pipefail`.
- At the top: `trap 'exit 143' TERM INT`. dash runs no EXIT trap on SIGTERM, and a
  `TimeoutStartSec` kill must still emit.
- One EXIT trap combines the existing `cleanup` with
  `[ "$rc" = 0 ] || inngest-boot-phone-home.sh provision-attempt-exit-$rc "attempt=N"`.

**Start of each attempt**

- Increment `/var/lib/soleur-inngest-provision/attempts` (under `StateDirectory=`).
- Emit `provision-attempt-start attempt=N` through the phone-home.
- Run `docker rm -f soleur-inngest-bootstrap-extract` as a pre-clean.

**Emits**

- Every existing stage name keeps its channel: `zot-login-*`, `zot-creds-EMPTY`,
  `isolation-check-*`, `pre-zot-pull`, `inngest_zot`, `inngest_pull_fatal`, `flip-assets-*`,
  `pre-bootstrap-run`, `bootstrap-exit-$rc`, `bootstrap-failure-journal`, `bootstrap-done`,
  `post-boot-health`, `net-health`.
- `inngest_pull_fatal` fires on **every** missed attempt, on both channels, exactly as a missed
  boot does today.
  - The phone-home detail becomes `zot miss ep=… rc=… tries=… attempt=N tail=…`, with `attempt=`
    placed before the free-form `tail=`.
  - The Sentry detail becomes `rc=… attempt=N`.
  - The rule's `frequency_minutes = 23` on one grouped issue caps paging at about 2.6 emails an
    hour while the host stays dark.
  - No `sentry/**` edit is needed. A power-of-two page decay was cut at plan review (see Cut List).
- **The recovery signal is `bootstrap-done` following an `inngest_pull_fatal`.** A dedicated
  recovery event was cut at plan review because it duplicated `bootstrap-done`.

**Latch**

- The latch is an **empty** file, `: > /var/lib/soleur-inngest-provision/done`. It is written
  exactly once, after `boot_rc -eq 0` and before the diagnostics. Content is deliberately empty:
  nobody can read it on a no-SSH host, and `/etc/default/soleur-inngest-image` already records the
  image.
- The script ends with an explicit `exit 0`, so a diagnostics tail cannot mark a latched attempt
  failed.
- **The latch's consumers.** It has exactly one consumer, the unit's
  `ConditionPathExists=!…/done`. That consumer only refuses a start and never resumes or replays,
  so the file needs no provenance.
  - Its only writer is the script. A replace gives a fresh root disk, which resets it.
  - The follow-through probe reads Better Stack, not the latch.

**Isolation, exits and the DOPPLER_PROJECT pin**

- The isolation check is the same `doppler run --project soleur-inngest --config prd -- bash -s`
  heredoc with the same regex. If it fails, the script exits non-zero before any pull.
- Every failure arm exits non-zero from the top-level shell, never from a subshell.
- The bootstrap `env` list keeps the literal `"DOPPLER_PROJECT=soleur-inngest"`.

**Traps: one combined EXIT trap (plan review, measured).** In dash a later `trap … EXIT` silently
replaces the earlier one, and a command that fails inside an EXIT trap under `set -e` turns an
`exit 0` into status 1. Both were measured.

- Install the single combined trap once, at the top of the script.
- **Delete** the moved block's own `trap cleanup EXIT` and `trap - EXIT` lines.
- Run `set +e` inside the trap body.

Guard 2 rows 7 and 8 pin this.

**No mount precondition. It was proposed at plan review and withdrawn at deepen-plan (architecture
P2).** A `mountpoint -q /mnt/data || exit 1` check would **reverse** today's first-boot behavior:

- **Today:** a failed LUKS stage does not stop the later `runcmd` items. `inngest-redis.service`'s
  mount guard (`RequiresMountsFor=/mnt/data`, plus the mapper-identity check in
  `inngest-redis-bootstrap.sh`) refuses Redis, and the server comes up SQLite-only
  (`INNGEST_DURABLE_DEGRADED`). The scheduler is degraded but serving.
- **With the check:** the host would fail fast and retry forever with the scheduler dark, and
  nothing re-runs the LUKS stage on that boot.

The existing guards are stronger anyway: they verify mapper identity, not just that a mountpoint
exists. They already protect the AOF on a reboot re-run. See the Cut List.

**Quiesce the cutover FSMs before each bootstrap run (architecture P1).** A retry after a late
failure or a timeout kill re-runs the bootstrap's `systemctl restart inngest-redis` and
`inngest-server` steps and re-enables the flip timer (`inngest-bootstrap.sh:1701`, `:1728`).

If that coincides with an operator's `op=resume`, the flip's `flushed` step may be inside its
`verify_serving` window. A restart there fails verification, and the FSM writes `aborted`.
`op=resume` G1 accepts only `done`, so recovering from `aborted` needs a `/mnt/data` recut.
"Resume after `bootstrap-done`" is runbook prose, not a gate.

So, immediately before invoking `inngest-bootstrap.sh`, the script:

```sh
systemctl stop inngest-cutover-flip.timer inngest-luks-cutover.timer 2>/dev/null || true
# bounded: wait (max 300 s) until neither oneshot is activating, so an in-flight FSM step finishes
for _u in inngest-cutover-flip.service inngest-luks-cutover.service; do
  _t=0; while [ "$(systemctl is-active "$_u" 2>/dev/null)" = activating ] && [ "$_t" -lt 300 ]; do sleep 5; _t=$((_t+5)); done
done
```

- The bootstrap re-enables both timers as today (`enable --now`).
- On attempt 1 of a fresh host the timers do not exist yet, so the stop is a harmless no-op.
- If the 300 s bound expires, emit `provision-fsm-busy` and exit non-zero, then retry.
- **Do not** order the provision unit with `Before=` on those services. The bootstrap restarts
  units synchronously, so that ordering would invite the deadlock Guard 5 row 5 forbids.
- Covered by T15 (Tier B) and a Guard 2 REORDER row (quiesce placed after the bootstrap call →
  RED).

#### Research Insights (deepen-plan, 2026-09-28)

**Shell safety.**

- **Refuse xtrace (security P2).** Copy the refusal from `inngest-bootstrap.sh:33-35` verbatim to
  the top of the script:

  ```sh
  case "$-" in *x*) printf '[FATAL] refusing to run under xtrace ...\n' >&2; exit 78 ;; esac
  ```

  The unit's journal is persistent (`journald-soleur.conf`, `Storage=persistent`), and every
  attempt pipes `ZOT_PULL_TOKEN` into `docker login`. One `set -x` would write the token to disk
  on every retry. Guard 6 pins this.
  - Exit 78 is **not** in `RestartPreventExitStatus`. A refusal is a code defect and should keep
    paging, not stop quietly.
- **Keep long children interruptible (research, systemd.kill(5) + dash semantics).** dash runs a
  trap only after the foreground child exits. Under `KillMode=control-group`, SIGTERM reaches the
  whole cgroup, and SIGKILL follows `TimeoutStopSec=` (default 90 s) later.
  - Run the two long children, the `docker pull` loop body and the `bash inngest-bootstrap.sh`
    invocation, as `cmd & child=$!; wait "$child"; rc=$?`.
  - Have the TERM trap `kill "$child" 2>/dev/null; exit 143`. The EXIT trap's emit then runs
    promptly, not after SIGKILL.
  - T9 asserts that the emit lands before the next attempt.
  - **A shutdown or reboot mid-attempt is the same SIGTERM path**, bounded by `TimeoutStopSec`.
    The emit may not leave the host if the network is already down during shutdown. The next
    boot's `provision-attempt-start attempt=N+1` is the durable trace (SpecFlow gaps 7 and 12).

**Per-attempt hygiene (security P2 and P3, SpecFlow).**

- **Clear stale staged files.** `rm -f` the full list of fixed `/tmp` staging paths the block
  copies to (`/tmp/inngest-redis.{conf,service}`, `/tmp/inngest-redis-bootstrap.sh`,
  `/tmp/vector.toml`, `/tmp/inngest-cutover-flip.{sh,service,timer}`,
  `/tmp/inngest-server-flip-guard.sh`, `/tmp/cat-inngest-cutover-state.sh`,
  `/tmp/inngest-luks-cutover.{sh,service,timer}`).
  - Without this, a failed `docker cp … || true` on attempt N+1 silently reuses attempt N's file.
  - The threat model relies on `fs.protected_symlinks=1` and `fs.protected_regular=2`, which are
    Ubuntu 24.04 defaults. `post-boot-health` records both values.
- **Address the extract container by the ID `docker create` returns**, not by its fixed name, and
  keep `docker create` fatal (never `|| true`). The pre-clean `docker rm -f
  soleur-inngest-bootstrap-extract` still clears a name left behind by a SIGKILLed attempt.
- **Attempt counter that cannot wedge.**
  `n=$(tr -cd 0-9 < …/attempts 2>/dev/null); n=$(( ${n:-0} + 1 ))`, followed by
  `printf '%s\n' "$n" > …/attempts || true`. A truncated or garbled counter file must never abort
  an attempt (T14).
- **The `/run/soleur-inngest-doppler.ok` sentinel is gone.** The script neither reads nor writes
  it, because `/run` survives across attempts within a boot. An earlier pass must not admit a later
  attempt after Doppler scope widened. A static row forbids the path, and the fixture at
  `cloud-init-inngest-bootstrap.test.sh:1903` is re-pointed.

**Channel re-arm (observability P1).**

- `inngest-bs-token-restage.service` makes one attempt per boot, with no retry. If it failed
  during a Doppler outage, `/run/inngest-bs-logs-token` is empty and every phone-home row is lost
  for the rest of the boot.
- So each attempt starts with:

  ```sh
  [ -s /run/inngest-bs-logs-token ] || /usr/local/bin/inngest-bs-token-restage.sh || true
  ```

  That reuses the existing script unchanged.
- The EXIT trap also sends `soleur-boot-emit provision_attempt_failed error "rc=… attempt=N"` to
  Sentry. Its DSN is baked into `/etc/default/soleur-sentry-dsn` on the root disk, so a failing
  host is visible in Sentry even when Better Stack is unreachable. This stage has no alert rule;
  see Deferrals.

**Host-life identity (observability P1, SpecFlow gap 6).** Every new stage, and the existing
`bootstrap-done` detail, carries `iid=<cloud-init instance-id>`. `soleur-boot-emit` already
derives it from `/var/lib/cloud/data/instance-id` (`cloud-init-inngest.yml:405`). Old and new
hosts share `host_name` during a replace, so the follow-through probe and the runbook key on
`iid`. A late `bootstrap-done` from a destroyed host can then never read as the new host's.

**Why no two bootstraps can overlap on this host (SpecFlow gap 5, verified).** `ci-deploy.sh`
runs `inngest-bootstrap.sh` directly (`ci-deploy.sh:3880-3946`), but it runs only on web hosts,
reached through the `deploy.` webhook that `deploy-inngest-image.yml:54` posts to. The dedicated
host has no webhook: "The dedicated host has NO /etc/default/webhook-deploy"
(`cloud-init-inngest.yml` `:1454-1456`). systemd never runs two instances of one unit, so the
unit, runcmd's single `start --no-block` and the timer serialize onto one job.

**Timer tick during a restart wait (SpecFlow gap 11).** A timer start delivered while the unit
sits in `auto-restart` merges into that pending job. It does not add a second attempt. T10
asserts `NRestarts` equals the number of failures. An early attempt caused by the merge would
be harmless.

**Latch durability (SpecFlow gap 10).** The latch write is followed by `sync -f
/var/lib/soleur-inngest-provision` (coreutils ≥ 8.24). Even without it, losing the latch to a
hard reset only re-runs an idempotent bootstrap on the next boot.

**Reboot of a host that never latched (SpecFlow gap 4).** Units a partial bootstrap already
enabled start at boot before the timer's 90 s re-run. That is exactly today's behavior after a
partial first-boot failure followed by a reboot (the units persist). The new behavior adds a
reconciling bootstrap run 90 s later. `inngest-server-flip-guard.sh` still gates the server on the
flip flag, and the bootstrap's idempotent contract (`inngest-bootstrap.sh:4`, `:103-118`)
re-installs units. No new state is reachable.

**Arming residual (SpecFlow P1, acknowledged).** The timer is enabled in the last `runcmd` items,
directly after the last prerequisite the unit needs: `/etc/default/inngest-server`, the deploy user
and the probe credential. If an earlier `runcmd` item aborts, for example on a LUKS-stage FATAL,
the unit is never armed. That host stays dark until a replace, **exactly as today**, and the
aborting item's own phone-home stage says why.

Arming earlier would let the unit run on a later reboot without prerequisites that only `runcmd`
writes (env files, deploy user). That would turn a loud stage FATAL into an endless retry loop
that can never succeed. This is recorded as a scoped residual, not a regression.

**Doppler read count (security P3, corrected).** A failed-bootstrap attempt makes about 6 Doppler
reads:

- the isolation check;
- `DIAG_BOOT`;
- one `doppler secrets download` inside each `inngest-redact.sh` call (`zot_tail`, `boot_tail`,
  `unit_journal`, `jl`).

A zot-miss attempt makes about 2. Redaction falls back to pattern-only matching when Doppler is
down. That is pre-existing behavior; the retry only makes it more frequent.

## Options Evaluated

| Option | Verdict | Why |
|---|---|---|
| **A. Unit only.** `runcmd` enables a boot timer (no `--now`) and starts the unit `--no-block`: one execution context | **Chosen** | One code path and one environment. Both retry and reboot are covered |
| B. `runcmd` runs the script synchronously for attempt 1, with a unit and timer for later runs | Rejected | Two environments (the shared shell vs `EnvironmentFile`) reproduce the #6985 class by construction. A concurrent timer tick would need `flock` |
| C. git-data shape: `StartLimitBurst=5` window, `OnFailure=` reporter, 15-min standing timer | Rejected | With a 45-min timeout, a window at least as long as the slow ladder is ≥ 3.8 h, so a 20-min zot blip would retry only after it closes. `RestartSec=120` recovers within about 2 min of the cause clearing |
| D. `cloud-init clean` and re-run on reboot | Rejected | ADR-115's three verified failure modes |
| E. Reboot for inngest | Rejected | Rejected by ADR-115; `runcmd` would not re-run anyway |
| F. Bake the retry into the bootstrap image | Impossible | The image is the thing being fetched |

## Implementation Phases

### Phase 0: guard matrices first (RED)

- 0.1 Write the `## Guard Contract` matrices into the new suite
  `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` **before** editing the
  template. Mirror the `case_mutate` helper of `cloud-init-inngest-zot-pull-mutation.test.sh`.
  Against `main`, the "unit exists" and "no pull in `runcmd`" rows must go RED.
- 0.2 Render through Terraform's own pipeline (`templatefile` → strip `replace` → `base64gzip`) in
  an empty scratch dir with the bounded stub values of `inngest-userdata-budget.sh`. Share that
  script's stub table; do not copy it. Assert the result is ≤ 32,768 B and starts with
  `#cloud-config`. This also catches a missed `$${` or `%%{` escape as a render error.

### Phase 1: pre-move inventory (measured, recorded in the PR body)

- 1.1 Classify every `runcmd` item between `:686` and `:1823` as *stays* or *moves*.
- 1.2 **Cross-item state census (P8).** For every free variable, exported env var, `/run` file and
  shell option the moved text reads, record where it used to come from and where it comes from
  now:
  - Examples: `DOPPLER_TOKEN`, `HOME`, `DOPPLER_CONFIG_DIR` (exported at `:1422`),
    `/run/soleur-inngest-doppler.ok`, `/run/inngest-bs-logs-token`, `ZOT_*`, `set -e`/`+e`.
  - Allowed replacements: in-script, `EnvironmentFile`, template variable, or an `After=`
    dependency.
  - Confirm that nothing in `runcmd` or `inngest-bootstrap.sh` deletes or rewrites
    `/etc/default/inngest-doppler` or `/etc/default/soleur-zot-read`. Retries depend on both for
    hours.

  Guards 4 and 7 are generated from this census.
- 1.3 Grep for every consumer of the moved block's side effects and stage names and confirm
  unchanged meaning under retry. Cover `/etc/default/soleur-inngest-image` (`inngest-bootstrap.sh:585`
  and `tests/scripts/lib/inngest-host-dark-gate.sh`), the two `/var/log/inngest-*.log` files,
  `scripts/followthroughs/*`, `scripts/cutover-inngest.sh`,
  `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`, and
  `tests/scripts/test-sentry-alert-live-fidelity.sh`. Any "is the host done?" reader must key on
  `bootstrap-done`, never on cloud-init completion.
- 1.4 **`TimeoutStartSec` derivation.** This was deepened by the architecture review (P2): derive
  the value from the **bounds the steps themselves carry**, not from healthy history. A value fitted
  to history can land the kill inside the post-restart tail, which is exactly the window that
  collides with the flip.
  - Sum the bounded steps:
    - docker-readiness wait (30 × 2 s);
    - zot login (`timeout 60`);
    - 3 pulls (`timeout 180` each, plus 2 × 5 s sleeps);
    - the Vector download (4 × 180 s plus sleeps, about 12.5 min, per the architecture review's
      reading of `inngest-bootstrap.sh`);
    - the FSM quiesce wait (300 s);
    - the post-boot `sleep 8`.
  - Then add the steps that have **no** bound: the inngest binary `curl` (`inngest-bootstrap.sh`
    `:150`) and the apt path in `inngest-redis-bootstrap.sh`. Record each as unbounded.
  - Set `TimeoutStartSec` to the bounded sum plus a margin of at least 10 min for the unbounded
    steps. Expect about 45 min. Cross-check against historical `pre-bootstrap-run` →
    `bootstrap-exit-0` deltas read from Better Stack (read-only `BETTERSTACK_QUERY_*`), if the
    credentials are available locally.
  - Record the arithmetic in the PR body and in the unit's comment.
  - Replace every "30min" in this plan's unit sketch with the derived value.

### Phase 2: template change (`cloud-init-inngest.yml`)

- 2.1 Add three `write_files` entries after `inngest-bs-token-restage.service`: the script (0755),
  the `.service` (0644) and the `.timer` (0644).
  - Re-indent consistently so the `CHKEOF` heredoc terminator stays valid.
  - No comment line inside a `content: |` block may be indented less than the block.
  - Keep `date +%…` and other `%` specifiers inside the script, never in unit directives, because
    `%` is a systemd specifier there.
- 2.2 Move the zot login item (`:1341-1356`), the isolation item (`:1421-1440`) and the pull item
  (`:1506-1823`) into the script, together with their load-bearing comments (CORRECTED #6617,
  DIGEST-PINNED, IREF IS THE PIN CARRIER, ZOT IS THE ONLY PULL).
  - The comment strip keeps this free of payload cost.
  - Carry `'%%{http_code}'` and every `$${…}` escape verbatim.
  - Write every new shell `${…}` as `$${…}`.
- 2.3 Apply the script deltas from Design.
- 2.4 Replace the moved `runcmd` items with the four arming items. The NIC wait (`:1320`) stays
  where it is.
- 2.5 Correct, in the same edit, prose that is now false: `:1376-1380` ("does NOT re-run it"),
  `:1607-1614` ("ENDS THE BOOT … whole runcmd", which now means *ends the attempt*), and
  `:1322-1340` (login placement). Grep for `ends the boot`, `whole runcmd` and
  `once-per-instance` and fix every hit that describes the moved path.
- 2.6 Check `bump-inngest-bootstrap-pin.sh`'s invariant: exactly 2 well-formed refs remain, and no
  new text names the ref.

### Phase 3: existing suites (re-point, never weaken)

- 3.1 `cloud-init-inngest-zot-pull-mutation.test.sh`.
  - Re-point NIC-G1 (the NIC wait comes before the first private-net use, which is now the unit
    start) and G4 (a miss ends the attempt with a non-zero status from the top level) to Guards 2
    and 5.
  - Replace every existing mutation row, never drop one.
  - Record before and after row counts.
- 3.2 `cloud-init-inngest-bootstrap.test.sh`. The pin guards (AC1–AC6, Guards A/B) must survive
  the move from 4-space to 6-space indentation. Loosen **leading-whitespace** anchors only, never
  token anchors.
- 3.3 `inngest-host.test.sh` §9/§9b: change the source location only. Keep the
  `HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)` nesting anchor.
- 3.4 Run these and fix anchors only if they go red: `inngest-redis-luks.test.sh`,
  `inngest-boot-emitter.test.sh`, `inngest-nic-wait.test.sh`,
  `inngest-bootstrap-mirror-only.test.sh`, `journald-config.test.sh`, and
  `inngest-redis-luks-loopback.test.sh` (the CI sudo leg).
- 3.5 Run `bash apps/web-platform/infra/inngest-userdata-budget.sh` and record the stored bytes
  and headroom.
- 3.6 Run `bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run` on the branch and record
  the `noop` line.

### Phase 4: new suite `cloud-init-inngest-provision-unit.test.sh`

- 4.1 **Static rows** over the rendered template: Guards 1, 5 and 6. These cover what no runtime
  run can see: where the pull lives, arming order and back-edges, and directive values.
- 4.2 **`systemd-analyze verify`** over the extracted `.service` and `.timer`, following the Y1
  precedent. Skip only when `systemd-analyze` is absent.
- 4.3 **One runtime harness file, two tiers.** Both tiers run the **Terraform-rendered, stripped**
  script, the same bytes that reach the host. Guards 2, 3, 4 and 7 are enforced here.
  - Stubs, each placed at the absolute path or PATH position the script calls:
    - `docker` stub, normalizing `image pull` and `--config` exactly like the G4 stub, with
      login, pull, create, cp and inspect outcomes scripted per scenario;
    - `doppler` stub, which records the environment it saw;
    - `timeout`, `sleep`, `systemctl` and `sync` stubs;
    - phone-home, `soleur-boot-emit` and `inngest-redact.sh` stubs, which append to a single call
      log;
    - a fake `inngest-bootstrap.sh`, extracted by the `docker cp` stub, with a scripted return
      code and sleep.
  - **No test seam is added to the production script.**
  - **Tier A: fixture root, no docker, and it never skips.** It extends the proven Guard 4
    machinery in `cloud-init-inngest-bootstrap.test.sh` (the `G4_FX` path-rewrite table
    `/usr/local/bin/`, `/etc/default/`, `/var/log/`, `/run/`, extended with `/var/lib/`, `/tmp/`
    and `/root/`).
    - Slice the script from the rendered `write_files` entry, **not** from `runcmd`.
    - **Every rewrite pair must match at least once.** A pair that matches nothing is an
      instrument fault, not a pass.
    - Run each scenario as `env -i PATH=<fx>/bin:… "$(command -v dash)" -u <fx>/script` (the G4
      invocation plus `-u`). The environment is built **only** by `set -a`-sourcing a fixture
      produced by **executing the rendered `:753` `printf`** into the path named by the unit's
      `EnvironmentFile=`, plus the unit's `Environment=` lines. The fixture is never hand-written
      (test-design P1-3).
    - Scenarios: T1–T5, T7, T8, T14.
    - **Instrument-fault discipline (test-design P1-1).**
      - Every scenario asserts its **exact** return code.
      - stderr must not contain `parameter not set`.
      - A mutation counts as caught only when the scenario fails on its **expected** rc or an
        expected-emit mismatch. rc 2 or rc 127 is an instrument fault and fails the suite loudly.
      - A **control row** runs the pristine render first: all scenarios must pass, and every
        must-PASS row must pass.
  - **Tier B: systemd 255 as PID 1 in a container.**
    - Pinned image: `ubuntu:24.04`, using the digest from `git-data-runcmd-rehearsal.test.sh`.
      Install systemd from its apt archive.
    - Boot command:

      ```sh
      docker run -d --privileged --cgroupns=private --cgroup-parent=docker.slice \
        --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw <img> /lib/systemd/systemd
      ```

    - Mask `systemd-resolved` and `getty@.service`, then poll `systemctl is-system-running` until
      it reads `running` or `degraded`, with a 60 s bound.
    - Install the rendered `.service`, `.timer` and script, the stubs, the executed-`:753` fixture,
      and test-only drop-ins:
      - `ExecStart=/bin/sh -u …`;
      - short `RestartSec=`, `TimeoutStartSec=` and `OnBootSec=` values per scenario.
    - Assert T6, T9–T12 and T15 **in one logged run**.
    - Allowed skips, each printed with a reason: docker absent, an ADR-188 apt-archive
      `arm_skip`, or an unbootable systemd container.
    - **The PR body shows one green Tier B run of all six scenarios**, from CI or a local run on
      the branch, with its log excerpt.
    - Every Tier B RED row also has a static or Tier A detector (Guard Contract), so a skipped
      Tier B loses no RED row.
    - **Precedent:** none in the repo for systemd as PID 1 in a container. This is novel
      infrastructure, flagged for review scrutiny (deepen-plan 4.4). The flags come from
      actions/runner-images discussion #10075.
  - **Harness sources:**
    - systemd.timer(5): "If a timer configured with OnBootSec= … is already in the past when the
      timer unit is activated, it will immediately elapse".
    - systemd.service(5): `TimeoutStartSec` expiry is a failure that `Restart=on-failure` restarts.
    - systemd.unit(5): no `[Install]` section means no automatic ordering against
      `multi-user.target`.
- 4.4 Keep the local systemd 261 measurement in Research Insights as supporting evidence only.
  Tier B on 255 is the gate.
- 4.5 **Ratchet.** Bump `BASELINE_DECLARED_PROBES` from 34 to 35 in
  `plugins/soleur/test/preflight-discoverability-test.test.ts`, adding a PLACEMENT/TRUTH/NO SUBSTITUTE
  comment. This plan's `credentials_required` is a one-line double-quoted scalar and the probe
  reads `BETTERSTACK_QUERY_*`; there is no unauthenticated substitute. The suite is not reached by
  file-scoped selection, so make the bump **the first commit of the work phase**. The plan commit
  already moves the count.

### Phase 5: architecture record (ADR and C4)

- 5.1 New ADR, provisionally **ADR-256** (re-verify the number at ship): "The dedicated inngest
  host provisions through a latched, retrying systemd unit, not once-per-instance `runcmd`."
  - Status `adopting`.
  - Record the decision and its consequences: delivery is by replace only; a reboot re-provisions
    only a host that never latched; recovery never uses SSH or a latch delete; paging repeats at
    the rule's 23-min throttle while the host stays dark.
  - Record the alternatives, Options B–F.
- 5.2 Add a dated note to ADR-115 under its "Reboot-for-inngest" rejected row. The once-per-instance
  premise now applies only to a host that has provisioned. The note must not read as extending
  ADR-115's acceptance, which covers the registry host only, to inngest. Reboot authority is
  still not granted.
- 5.3 Add a dated note to ADR-096's #8036-1d amendment, and a dated note to ADR-100 (new actor
  on the sole scheduler; FSM quiesce; `op=resume` after `bootstrap-done`). Cite ADR-142 in
  ADR-256. For the inngest host, the template now
  makes a zot miss end the **attempt**, and a live host keeps the old behavior until its next
  replace.
- 5.4 C4 `model.c4`: rewrite the `inngest -> sentry` edge prose (`:775`).
  - "a zot miss that ENDS the boot" becomes "a zot miss ends the attempt;
    `soleur-inngest-provision.service` retries every 120 s until one succeeds (#8562; a host
    replaced before this change still ends the boot)".
  - Regenerate `model.likec4.json` with the `architecture` skill's render step.
  - Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
    `plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 6: runbooks and follow-through enrollment

- 6.1 `knowledge-base/engineering/operations/runbooks/inngest-server.md`: add a section headed exactly
  `## Provision unit (#8562)`. It covers:
  - Stage meanings. A page carrying `attempt=N` is one missed attempt; the unit retries every
    120 s and the email repeats at most every 23 min while the host stays dark.
  - **After `inngest_pull_fatal`, wait for `bootstrap-done` (same `iid`) before deciding to
    replace**, because the host may recover on its own. Key every read on `iid`: an old host's
    late row must not be read as the new host's.
  - Run `op=resume` only after `bootstrap-done` for the new `iid`. The unit also quiesces the flip
    timers before every bootstrap run.
  - A repeating `provision-fsm-busy` means a flip or LUKS-cutover step is wedged. Read the FSM
    state with the existing read-only `scripts/inngest-host-state.sh` (locally, or via the
    `inngest-host-state.yml` one-tap wrapper, #8449 UC2), which reads journald → Vector → Better
    Stack. Do not replace blindly.
  - Replace triggers: `isolation-check-FAILED` on every attempt (credential scope, which retries
    cannot fix), or no `bootstrap-done` more than 2 h after the first attempt.
  - The change reaches a host only at its next replace.
  - A provisioned host's reboot does not re-provision it.
  - **No SSH, latch-delete or `systemctl` step.** Re-provisioning is a replace.
- 6.2 Sweep `inngest-server.md`'s `inngest_pull_fatal` paragraph and
  `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md`'s "fresh-boot zot miss
  ends the boot" callouts. Only the inngest half changes, stated as "template retries; the live
  host keeps the old behavior until its next replace."
- 6.3 Add `scripts/followthroughs/inngest-provision-unit-8562.sh`, modeled on
  `inngest-private-nic-8539.sh`: field-isolated decode of the rows for `host_name=soleur-inngest`,
  anchored on the newest `provision-unit-armed` row's `iid` (see the Probe design note under
  Observability).
  - It prints exactly one `verdict=…` line **to stdout**.
  - PASS (exit 0): a `bootstrap-done` with the same `iid` exists after the armed row.
  - FAIL (exit 1), either:
    - no `provision-attempt-start` for that `iid` within 10 min of the armed row; or
    - attempts with no `bootstrap-done` more than 2 h after the first attempt.
  - `TRANSIENT reason=not-delivered` (exit 2): no armed row in the 30-day window.
  - `TRANSIENT reason=probe-fault` (exit 3): the query failed.
  - Secrets: `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`, which the sweeper already wires, so no
    workflow edit is needed.
  - Fixture-test it the way its 8539 twin is tested.
- 6.4 At ship: add the directive
  `<!-- soleur:followthrough script=scripts/followthroughs/inngest-provision-unit-8562.sh earliest=<merge+7d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
  and the `follow-through` label to #8562. The PR body says `Ref #8562`, **not** `Closes`.

### Phase 7: ship constraints

- 7.1 The PR body includes the Merge-Consequence verdict, the pending-delta side effect, the
  `web-v*` release disclosure, and the census table.
- 7.2 **The squash-merge commit body includes a line that is exactly
  `[skip-web-platform-apply]`**, passed with `gh pr merge --squash --admin --body-file <file>`.
  After merge, check that the push run's `apply` job reads `skipped`.
- 7.3 File the three follow-up issues from Deferrals: the forced-race rehearsal, the Sentry alert
  for non-pull provision failures, and the `op=resume` `bootstrap-done` G-row. Comment the
  SOLEUR-DEBT and Vector notes on #6780.

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml`
- `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`: whitespace anchors only, if needed.
- `apps/web-platform/infra/inngest-host.test.sh`: §9/§9b source location. This wakes the mint
  filter, which returns `noop` (Phase 3.6).
- `apps/web-platform/infra/inngest-redis-luks.test.sh`, `inngest-boot-emitter.test.sh`,
  `inngest-nic-wait.test.sh`, `journald-config.test.sh`: anchors only, and only if red.
- `knowledge-base/engineering/architecture/decisions/ADR-115-dedicated-host-private-nic-boot-convergence.md`
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`
  (dated note, deepen-plan)
- `knowledge-base/engineering/architecture/diagrams/model.c4`, plus a regenerated `model.likec4.json`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md`
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: bump `BASELINE_DECLARED_PROBES`
  34 → 35 (Phase 4.5).

## Files to Create

- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`
- `scripts/followthroughs/inngest-provision-unit-8562.sh`, plus its fixture test if the 8539 twin
  has one.
- `knowledge-base/engineering/architecture/decisions/ADR-256-inngest-host-provisioning-runs-in-a-latched-retrying-unit.md`
  (the ordinal is provisional).

## Open Code-Review Overlap

One open code-review issue mentions a touched file's family: **#8487**, capability-gate corpus
follow-ups. It cites `cloud-init-inngest-bootstrap` among the suites with a widened CI predicate.

**Acknowledge.** It is a different concern: CI-predicate normalization. This plan copies the
existing `_skip` and `arm_skip` shape from its precedent and adds no new predicate. The scope-out
stays open.

## Deferrals (tracked)

| Deferred | Why | Tracking | Re-evaluate when |
|---|---|---|---|
| Live delivery: the next `inngest-host-replace` plus `op=resume` | A production write, forbidden this session. The change stays inert until then | #8562 stays open, with the probe `inngest-provision-unit-8562.sh` | Any operator-approved inngest replace. It rides along with the next one |
| Forced-race rehearsal on a throwaway host, covering both the #8539 fallback and this unit's recovery under a real late attach, real zot and real Doppler | Needs a Terraform-managed throwaway root, which is a production-account write. Tier B already covers systemd behavior offline | A **new issue**, filed at ship (Phase 7.3) | A throwaway-root session is approved. Precedent: `rung2-rehearsal/` |
| Carrier-side `DOPPLER_PROJECT` value check (SOLEUR-DEBT at `inngest-bootstrap.sh:58`) | Any change to a carrier auto-mints a tag (#9079) | A comment on **#6780** | The next PR that changes a carrier anyway |
| Shipping the unit's journald rows via Vector | A `vector.toml` edit is a mint | A comment on **#6780**, same batching reason | Same trigger |
| #6985 (bare-sourced Doppler sites on the web host) | Different host and file. The fix activates zot selection on web | #6985 (open) | Independently |
| A Sentry issue alert for non-pull provision failures (`provision_attempt_failed`, isolation FATAL, bootstrap failure, FSM busy) | Any `apps/web-platform/infra/sentry/**` edit fires `apply-sentry-infra.yml` on merge, which is a production write. Today a bootstrap failure also pages nobody, so the gap predates this PR; retries make it longer-lived | **New issue** filed at ship (Phase 7.3) | The next Sentry-rules PR, or the first `provision_attempt_failed` event in Sentry |
| An `op=resume` G-row that refuses unless the new `iid` has emitted `bootstrap-done` (architecture P2, defense in depth behind the unit-side FSM quiesce) | This changes `scripts/cutover-inngest.sh` gate semantics, a separately reviewed gate surface. The unit-side quiesce already prevents the collision | **New issue** filed at ship | The first `aborted` flip after a replace, or the next cutover-gate PR |

## User-Brand Impact

**If this lands broken, the user experiences:** every scheduled and background job stops after
the **next** inngest host replace: crons, reminders and agent follow-ups. That happens if the new
unit fails to provision the host, for example because the Doppler token does not reach the
isolation check, the latch is written too early, or the unit never starts. It shows up as missed
reminders and stalled automations until a revert, another replace and `op=resume`. That is the
same outage shape as 2026-09-22 (about 59 min). It cannot happen at merge.

**If this leaks, the user's data / workflow / money is exposed via:** no new exposure vector. The
unit reads the same `/etc/default/inngest-doppler` (mode 0600, root) that the `runcmd` shell
already read. It passes secrets through the environment, never argv. The latch it writes is
non-secret. Emits carry stage names, return codes and attempt counts, and log tails go through the
existing `inngest-redact.sh`.

- **Brand-survival threshold:** `aggregate pattern`

This is outage-shaped for every user at once, not a single user's breach. After delivery it is
strictly less likely than today, because a missed first-boot window no longer darkens the
scheduler. No per-PR CPO sign-off.

## Observability

Layers cited per `hr-observability-layer-citation`:

- **Sentry issue alert** `sentry_alert.zot_mirror_fallback_rate`: pages on the pull miss.
- **Sentry event stream** (store API via `soleur-boot-emit`): visibility only, with no alert rule
  for non-pull provision failures (Deferrals).
- **Better Stack Logs** source (the direct-curl phone-home): the per-stage trail.
- **Follow-through sweeper** (`scripts/sweep-followthroughs.sh` probe): delivery verdict.

The external heartbeat `betteruptime_heartbeat.inngest_prd` is **not** a layer here. It is
`paused = true` (`inngest.tf`, measured 2026-09-28), so it pages nobody.

```yaml
liveness_signal:
  what: >-
    Boot-stage events from host_name=soleur-inngest, keyed by iid=<cloud-init instance-id>. On the
    Better Stack Logs source (inngest-boot-phone-home.sh, direct curl): provision-unit-armed,
    provision-attempt-start attempt=N, bootstrap-done, post-boot-health. On Sentry (store API via
    soleur-boot-emit): inngest_zot (info), inngest_pull_fatal (fatal, every missed attempt) and
    provision_attempt_failed (error, every failed attempt).
  cadence: per provision attempt (one on a healthy boot; at most one per RestartSec=120 s while failing)
  alert_target: Sentry issue alert zot-mirror-fallback-rate (email to issue owners, frequency_minutes=23) on stage=inngest_pull_fatal
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (resource sentry_alert.zot_mirror_fallback_rate, unchanged)

error_reporting:
  destination: >-
    Sentry web-platform project via the baked DSN in /etc/default/soleur-sentry-dsn (soleur-boot-emit,
    root disk, survives a Doppler outage), and Better Stack Logs via /run/inngest-bs-logs-token
    (inngest-boot-phone-home.sh), re-staged at each attempt start when empty. Vector is not a
    channel for this unit: it is installed by the bootstrap this unit runs.
  fail_loud: >-
    stage=inngest_pull_fatal at level fatal with detail "rc=<n> attempt=<N>"; the EXIT trap emits
    provision-attempt-exit-<rc> (phone-home) and provision_attempt_failed (Sentry) for every failed
    attempt, including a TimeoutStartSec kill (TERM trap, child run as `& wait`); bootstrap-exit-<rc>
    with a redacted tail plus bootstrap-failure-journal for a failed bootstrap.

failure_modes:
  - mode: zot pull misses on an attempt (late NIC, zot down, transient docker error)
    detection: inngest_pull_fatal attempt=N on both channels, every missed attempt
    alert_route: Sentry issue alert zot-mirror-fallback-rate email (throttled 23 min, one grouped issue)
  - mode: attempt recovers after one or more misses
    detection: bootstrap-done iid=<same> following an inngest_pull_fatal from the same iid
    alert_route: none (informational; the runbook reads it as recovery)
  - mode: isolation self-check fails (over-scoped or unreachable Doppler)
    detection: isolation-check-FAILED (phone-home) and provision_attempt_failed (Sentry event) every attempt
    alert_route: no page (Sentry event stream + Better Stack Logs only) — pre-existing gap, Sentry rule deferred (Deferrals)
  - mode: bootstrap script fails after a successful pull
    detection: bootstrap-exit-<rc> plus bootstrap-failure-journal (phone-home), provision_attempt_failed (Sentry) every attempt
    alert_route: no page — pre-existing gap (today this also pages nobody), Sentry rule deferred (Deferrals)
  - mode: cutover FSM busy (a flip or LUKS-cutover step still activating past the 300 s quiesce bound)
    detection: provision-fsm-busy (phone-home) and provision_attempt_failed (Sentry); the attempt retries
    alert_route: no page; the runbook reads a repeating provision-fsm-busy as "an FSM step is wedged"
  - mode: Better Stack channel dead for the boot (bs-token restage failed during a Doppler outage)
    detection: per-attempt re-stage; while still empty, Sentry provision_attempt_failed carries the attempt
    alert_route: Sentry event stream (baked DSN, no Doppler dependency)
  - mode: unit never armed (an earlier runcmd item aborted) or armed but never started
    detection: no provision-unit-armed for the new iid (the aborting item's own stage names why), or provision-unit-armed with no provision-attempt-start within 10 min
    alert_route: follow-through probe inngest-provision-unit-8562.sh reads FAIL on the daily sweeper
  - mode: an attempt hangs
    detection: TimeoutStartSec SIGTERM -> TERM trap kills the child -> EXIT trap emits provision-attempt-exit-143 within seconds; the next attempt-start carries N+1 (a shutdown-time emit may not leave the host)
    alert_route: Sentry event stream (provision_attempt_failed) + Better Stack Logs
  - mode: latched host whose services later break
    detection: none new (the Condition skip emits nothing); pre-existing — the external heartbeat that would catch it is paused=true
    alert_route: out of scope for #8562; pre-existing gap, not widened by this change

logs:
  where: >-
    Better Stack Logs source (phone-home rows with redacted tails). Host-local
    /var/log/inngest-zot-pull.log and /var/log/inngest-bootstrap.log (0600), whose redacted tails
    ship in those rows. The unit's journald rows are host-local by design (below Vector's CRIT floor).
  retention: Better Stack source retention per the source plan; host-local files live until the next replace

discoverability_test:
  command: bash scripts/followthroughs/inngest-provision-unit-8562.sh
  expected_output: "verdict=PASS or verdict=TRANSIENT reason=not-delivered"
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD (read-only Better Stack query) — the boot-stage rows exist only in the Better Stack Logs source; no unauthenticated endpoint exposes a no-SSH host's boot stages"
```

**Probe design (deepen-plan, observability P1).** Newest-boot grouping cannot work. A latched
host that reboots emits no `provision-attempt-start`, so it would read TRANSIENT forever. And the
phone-home carries no boot id. So the probe anchors on host life instead:

- It selects the newest `provision-unit-armed` row. That row is emitted once per host life, from
  `runcmd`, and carries `iid`. It takes that row's `iid`.
- **PASS:** a `bootstrap-done` with the same `iid` exists after the armed row.
- **FAIL:** no `provision-attempt-start` for that `iid` within 10 min of the armed row, **or**
  attempts for that `iid` with no `bootstrap-done` more than 2 h after the first attempt.
- **TRANSIENT reason=not-delivered:** no `provision-unit-armed` row in the 30-day window.
- **TRANSIENT reason=probe-fault:** the Better Stack query failed. It is a distinct token, so a bad
  credential can never match `expected_output`.
- The single `verdict=…` line goes to **stdout**, and detail goes to stderr. Its 8539 twin prints
  verdicts to stderr, and Check 10 only matches stdout.
- Field isolation and `fromjson?` decoding mirror `inngest-private-nic-8539.sh`.

## Downtime & Cutover

(Deepen-plan gate 4.55: at delivery, this change is a `must be replaced` on `hcloud_server.inngest`.)

**Offline-inducing operation.** The next `apply_target=inngest-host-replace` dispatch destroys and
recreates `hcloud_server.inngest`, followed by a human-approved `cutover-inngest.yml -f op=resume`.
Affected surface: every scheduled and background job (crons, reminders, agent follow-ups). **This PR
performs no replace.** Its merge is inert (see Merge-Consequence Analysis). It adds no replace
event of its own: it rides the next replace that some change requires.

**Zero-downtime paths evaluated. None applies, for a structural reason, not by default.**

| Path | Verdict | Why |
|---|---|---|
| Blue-green (birth a second inngest host, drain, cut over, retire the old one) | Not available | ADR-100 enforces **exactly one scheduler by topology**. Two live scheduler hosts double-fire every cron. The cutover FSM and flush latch exist to keep a single owner, so a parallel host is the failure mode, not a mitigation. |
| Rolling | Not available | There is one host. |
| In-place redelivery (apply the new unit to the running host without a replace) | Not available | There is no in-place channel for the dedicated host, tracked in #6780. `hr-prod-host-config-change-immutable-redeploy` makes a replace the delivery path. |
| State-only re-address (`terraform state mv`) | Not applicable | The resource does change: user_data is ForceNew. |

**Residual downtime is accepted, with justification and a bounded window.**

- **Measured window of the last delivery (2026-09-27):** the `inngest_host_replace` job ran
  14:55:48Z–14:57:36Z (run `36327637204`), and the following `op=resume` run `36327875467` ran
  14:59:05Z–15:29:49Z, including its approval gate. The scheduler was therefore dark for about 34
  minutes.
- **This change shortens the worst case.** Today a missed first-boot pull extends the window
  until a second replace (the 2026-09-22 incident cost about 59 min). After delivery, the unit
  retries the pull every 120 s on the same host.
- **Operator sign-off already exists** on this path. The replace is an operator-approved dispatch,
  and `op=resume` holds in the `inngest-cutover` environment gate until a human approves it.
- **Timing guidance for the follow-through.**
  - Deliver with the next replace that another change needs, in a low-traffic window.
  - Run `op=resume` only after the new boot emits `bootstrap-done`.
  - **Rollback** is a revert plus another replace and `op=resume`, which costs the same bounded
    window.

**Per-stage verification (delivery day, all read-only and SSH-free).**

1. The replace job is green.
2. Better Stack shows `provision-unit-armed`, then `provision-attempt-start attempt=1`, then
   `bootstrap-done` and `post-boot-health` with `svc=[active,…]`.
3. `op=resume` completes.
4. `inngest-provision-unit-8562.sh` reads `verdict=PASS`.

Any `inngest_pull_fatal attempt=N` in step 2 means wait for `bootstrap-done` rather than replacing
again (runbook).

## Infrastructure (IaC)

### Terraform changes

No `.tf` file changes. The unit ships inside `cloud-init-inngest.yml`, which is already the
`templatefile` source of `hcloud_server.inngest.user_data` (`inngest-host.tf`). There are no new
variables, providers, secrets or resources.

### Apply path

**(c) Replace**, through the existing gated `apply_target=inngest-host-replace` dispatch followed by
`op=resume`. This PR does **not** perform it. Expected downtime is the standard replace window:
the scheduler is dark from destroy until `bootstrap-done`, plus the `op=resume` approval. The
blast radius is the dedicated inngest host only. The Redis AOF volume is a separate resource and
survives the replace.

### Distinctness / drift safeguards

- `ignore_changes` is unchanged. user_data stays un-ignored on purpose, because that is what makes
  a replace reprovision the host.
- After merge, `hcloud_server.inngest` shows a pending replace in any plan that reaches it (the
  side effect disclosed above).
- The payload size is gated by the budget CI job and the render assertion in Phase 0.2.
- This host has no dev/prd split.

### Vendor-tier reality check

No new vendor resource. A healthy boot sends one or two more rows to Better Stack. A failing host
sends up to about 150 phone-home rows an hour in the fast-fail case: about 28 attempts × 5–6 rows.
A zot-unreachable host sends about 30 an hour. It also sends one Sentry event per missed attempt,
collapsed into a single grouped issue.

## Encryption Posture

```yaml
at_rest:
  - store: /var/lib/soleur-inngest-provision/{done,attempts} (inngest root disk, new empty latch + attempt counter)
    mechanism: plaintext-exception
    evidence: the single latch write site (an empty file) and the counter write in /usr/local/bin/soleur-inngest-provision (write_files in apps/web-platform/infra/cloud-init-inngest.yml); Guard 3
    defends_against: nothing (non-sensitive by construction — an empty marker and an integer)
    does_not_defend: a root-disk reader learns that the host provisioned and after how many attempts
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:host-local file on a no-SSH host; its effect is observable only as the absence of provision-attempt-start rows after a reboot
in_transit:
  - connection: inngest host -> zot 10.0.1.30:5000 (moved from runcmd into the unit; not new)
    enforced_at: apps/web-platform/infra/cloud-init-inngest.yml (daemon.json insecure-registries in runcmd; docker login and pull in the provision script)
    tls: none (pre-existing ADR-096 posture, unchanged)
    cert_verification: off
    does_not_defend: an on-path attacker inside the private network, including disclosure of the zot pull credential (docker login sends it over plain HTTP). Image integrity is carried by the pinned @sha256 digest, not the transport
    disclosed_as: ADR-096 insecure-registry allowlist; model.c4 zot edges
  - connection: inngest host -> Doppler API (moved; isolation self-check and DIAG_BOOT read)
    enforced_at: doppler CLI default https endpoint, invoked from the provision script with EnvironmentFile=/etc/default/inngest-doppler
    tls: HTTPS (TLS 1.2+)
    cert_verification: on
    does_not_defend: a leaked soleur-inngest boot token (read/write on the isolated project, #6890)
    disclosed_as: not-publicly-claimed
exception:
  - store: /var/lib/soleur-inngest-provision/{done,attempts}
    justification: an empty marker and an integer; encrypting them buys nothing
    tracking_issue: "#8562"
    reevaluate_when: the latch ever gains a credential, token or user-derived value
    expires_on: 2026-12-27
  - connection: inngest host -> zot (pre-existing, moved)
    justification: pre-existing ADR-096 posture, unchanged; digest-pinned pulls
    tracking_issue: "#6122"
    reevaluate_when: zot gains TLS on the private net
    expires_on: 2026-12-27
```

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-256.** The ordinal is provisional; `soleur:ship`'s ADR-Ordinal Collision Gate
  re-verifies it. It records:
  - `soleur-inngest-provision.service`: a `Type=oneshot` unit with unlimited, rate-bounded
    restarts;
  - a latch written only after `inngest-bootstrap.sh` exits 0;
  - a boot timer;
  - `runcmd` only arms the unit;
  - one Sentry page per missed attempt, throttled by the existing rule;
  - status `adopting` until `inngest-provision-unit-8562.sh` passes.
- **Amend ADR-115** with a dated note: its once-per-instance premise now applies only to a host
  that has provisioned. It is still accepted for the registry only, and reboot authority is still
  not granted.
- **Amend ADR-096** with a dated note on the #8036-1d amendment: for inngest, the template's zot
  miss now ends the attempt, not the boot.
- **Amend ADR-100** with a dated note (architecture P2). The unit is a new actor that can restart
  `inngest-redis` and `inngest-server` on the sole scheduler, and it creates an ordering rule:
  quiesce the flip timers before any bootstrap run, and run `op=resume` only after the new host's
  `bootstrap-done`. The replace-to-reprovision delivery path itself is unchanged.
- **Cite ADR-142** (Redis AOF LUKS) in ADR-256. The unit orders `After=inngest-luks-open.service`
  and deliberately adds **no** mount precondition, so a failed LUKS stage keeps today's
  SQLite-degraded serving rather than going dark.
- **ADR-256 records two guarantees** (architecture P3):
  - **Singleton:** a self-recovered host never starts serving on its own authority. The flip guard
    refuses to serve a replaced host without a `done-owner` marker until `op=resume` runs.
  - **AOF safety under a kill:** Redis, the server and the flip each run in their own unit cgroup.
    `KillMode=control-group` on the provision unit kills only the script and its `systemctl`
    clients, and killing a client does not cancel the job in PID 1.

### C4 views

All three model files were read: `model.c4` (859 lines), `views.c4` (106), `spec.c4` (54).

- **External actors:** none added. The operator's replace and `op=resume` path is already modeled.
- **External systems:** Sentry, Better Stack, Doppler and zot are already modeled (`inngest ->
  sentry` `:775`, `inngest -> betterstack` `:649`, `doppler -> inngest` `:729`, `zotRegistry`
  `:379`). None is added.
- **Containers and stores:** none added. The latch is a host-local marker file.
- **Relationships:** no edge is added or removed.

**One description is now false and must change:** the `inngest -> sentry` edge says "a zot miss
that ENDS the boot". This is Phase 5.4. After the change, run
`plugins/soleur/test/c4-count-parity.test.sh`; the edge prose embeds no count this change moves, but
a green run is required evidence. Also run the two C4 validation tests.

### Sequencing

Write the ADR now, describing the target state with status `adopting`. Flip it to `accepted` when
the follow-through probe passes after the first replace that delivers the change.

## Guard Contract

### Guard 1 — single login and pull site, under the unit (static)

**Property.** The bootstrap image's `docker login` and `docker pull` each happen at exactly one site
in the rendered user_data. Both sites are inside the script the unit executes, never in a `runcmd`
item.

**Assembly.** Every `runcmd` list item and every `write_files[].content` of the rendered user_data.
The chokepoints are the `docker login` and `docker pull` tokens and the binding between
`ExecStart=` and the `write_files` path. A login or pull can structurally live in either place, so
the guard quantifies over both.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add a `runcmd` item `timeout 180 docker pull "$ZIREF"` | RED |
| 2 | Render an empty `runcmd` and empty `write_files` (the guard's own dispatch sees 0 items) | RED |
| 3 | Keep the compliant pull and add a SECOND `docker pull` later in the same script | RED |
| 4 | Change `ExecStart=` to `/usr/local/bin/soleur-inngest-provision2`; the `write_files` path stays | RED |
| 5 | Add a `runcmd` item `docker login "$ZOT_EP" …` after the NIC wait (a login outside the unit) | RED |
| 6 (harness) | Suite edit: `case_mutate` writes the mutated render to a file the guard does not read | RED (harness sentinel row) |
| 7 | Add a second pull spelled `docker image pull "$ZIREF"` (or `docker --config /root/.docker pull`) after the compliant one | RED (the static check normalizes spellings the way the G4 stub does) |
| 8 (must-PASS) | Compliant render with blank lines and an unrelated `write_files` entry before the script | PASS |

### Guard 2 — every failure arm retries, no arm latches, and one EXIT trap reports it (runtime + static)

**Property.** Every failure arm of an attempt ends the script with a non-zero status from the top
level, `Restart=on-failure` is set, and exactly one `trap … EXIT` exists in the script. So a failed
attempt is retried, never latched, and always reported.

**Assembly.** The script's exit sites (`exit` tokens, `set -e` regions), its `trap` statements (one
combined EXIT trap installed at the top, whose body runs `set +e`, plus `trap 'exit 143' TERM INT`),
and the unit's `Restart=`. The chokepoint is the script's top-level shell. The guard excludes
subshell exits, and a second `trap … EXIT` counts as a violation because in dash a later
`trap … EXIT` silently replaces the earlier one (measured: `trap A EXIT; trap B EXIT; exit 0` prints
only B).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `exit "$zot_rc"` → `exit 0` in the miss arm | RED (T1: latch absent AND rc≠0 fails) |
| 2 | Wrap the miss arm's exit in `( … exit "$zot_rc" )` | RED (T1) |
| 3 | Append `|| true` to the bootstrap invocation | RED (T4) |
| 4 | `Restart=on-failure` → `Restart=no` | RED (static directive row, plus T10 in Tier B) |
| 5 | A second failure arm (isolation FATAL) `exit 0`s after a compliant first | RED (T3) |
| 6 | Delete `trap 'exit 143' TERM INT` | RED (static row, plus T9 in Tier B) |
| 7 | Re-add the moved block's own `trap cleanup EXIT` after the combined trap (a second EXIT trap) | RED (static trap count, plus T7: no provision-attempt-exit emit) |
| 8 | Remove `set +e` from the EXIT trap body and make `docker rm -f` fail inside it | RED (T2: a latched attempt exits 1) |
| 9 | REORDER: install the combined EXIT trap below the zot login (a login failure exits unreported) | RED (static: the trap precedes the first fallible command; T7 variant with login failing) |
| 10 | REORDER: move the cutover-FSM quiesce below the `inngest-bootstrap.sh` invocation | RED (T4 call-order assertion, plus T15) |
| 11 (must-PASS) | Reorder unrelated `[Service]` directives; add a comment line between arms | PASS |

### Guard 3 — latch identity and position

**Property.** The unit's `ConditionPathExists=!` path is the path the script writes. It is written
at exactly one site, after `inngest-bootstrap.sh` returned 0 and before any diagnostic that could
fail, and the script then ends `exit 0`.

**Assembly.** `ConditionPathExists=` in the unit, every write under `/var/lib/soleur-inngest-provision/`
in the script, the `boot_rc` check, and the final `exit 0`. The chokepoint is the single latch
`: > …/done` site, which lives under the unit's `StateDirectory=` (root disk), so it survives a reboot.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the Condition path to `…/ok`; the write site stays | RED (static cross-artifact equality) |
| 2 | REORDER: move the latch write above the `inngest-bootstrap.sh` invocation | RED (T4: latch present after rc=1) |
| 3 | Add a second latch write inside the `boot_rc -ne 0` arm, after the compliant one | RED (static write-site count, plus T4) |
| 4 | Remove the latch write | RED (static write-site count, plus T2) |
| 5 | Delete the final `exit 0` and make the last diagnostic fail | RED (T2) |
| 6 | LIFETIME: move the latch to `/run/soleur-inngest-provision/done` in BOTH the Condition and the write (paths stay equal) | RED (static: the latch path must sit under `/var/lib/soleur-inngest-provision/`; T11 latch-present arm after a real T10 success) |
| 7 | After a compliant first write, add a second one spelled `install -m 0644 /dev/null "$LATCH"` in a failure arm | RED (static write-site census normalizes `: >`, `touch`, `install`, `cp`, `printf … >` and `$VAR` targets) |
| 8 (must-PASS) | Latch written with `touch` instead of `: >` | PASS |

### Guard 4 — every Doppler call gets an exported token (the #6985 class)

**Property.** Every `doppler` invocation in the script runs with `DOPPLER_TOKEN` and `HOME` in its
process environment, supplied by the unit and not by a shared shell. The bootstrap invocation
passes `DOPPLER_PROJECT=soleur-inngest` literally.

**Assembly.**

- every `doppler` token in the script;
- the unit's `EnvironmentFile=` and `Environment=`;
- the `runcmd` write that produces `/etc/default/inngest-doppler` (`printf 'HOME=/root\nDOPPLER_TOKEN=%s…'`);
- the bootstrap `env` list.

The chokepoint is the unit's environment. The script must not re-source the file with a bare `.`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `EnvironmentFile=/etc/default/inngest-doppler` | RED (static directive row, plus T6 in Tier B) |
| 2 | Change it to `EnvironmentFile=-/etc/default/inngest-doppler-typo` | RED (static: exact path, and the `-` prefix is itself forbidden; plus T6) |
| 3 | Add a second doppler call under `env -i`, after a compliant first | RED |
| 4 | Remove `HOME=/root` from both the unit and the file write | RED |
| 5 | `"DOPPLER_PROJECT=soleur-inngest"` → `"DOPPLER_PROJECT=soleur"` in the bootstrap env list | RED |
| 6 (must-PASS) | The unit additionally sets `Environment=DOPPLER_ENABLE_VERSION_CHECK=false` | PASS |

### Guard 5 — first-boot ordering, a single trigger, no back-edge

**Property.** On first boot:

- the NIC wait runs once, before every item that can start the unit;
- the only first-boot trigger is `systemctl start --no-block`, and the timer is enabled without
  `--now`;
- nothing in the template orders itself after, requires, or wants the provision unit, apart from
  its timer.

**Assembly.**

- the parsed `runcmd` list positions (NIC-G1 technique);
- the `soleur-inngest-nic-wait` item, the `start --no-block` item and the timer `enable` item;
- every `After=`/`Requires=`/`Wants=`/`BindsTo=` line in every `write_files` unit.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | REORDER: move the start item above the NIC-wait item | RED |
| 2 | Timer item gains `--now` (a hidden second trigger that fires on elapsed `OnBootSec`) | RED |
| 3 | Add a second `systemctl start … soleur-inngest-provision.service` item earlier | RED |
| 4 | Empty `runcmd` (the guard's own dispatch) | RED |
| 5 | Add `After=soleur-inngest-provision.service` to `inngest-bs-token-restage.service` | RED (back-edge) |
| 6 (must-PASS) | Insert two unrelated items and blank lines between the NIC wait and the arming items | PASS |

### Guard 6 — bounded rate, unbounded persistence, runcmd-equivalent environment

**Property.** The unit retries with no start limit and never faster than every 60 s. Each attempt
is time-bounded, and the script refuses to run under xtrace. The unit has no `[Install]`, the timer re-enters on boot, and no sandboxing
directive changes the environment the moved block ran in.

**Assembly.** The unit's `StartLimitIntervalSec=`, `StartLimitBurst=`, `Restart=`, `RestartSec=`,
`TimeoutStartSec=`, `UMask=` and `[Install]`, plus the timer's `OnBootSec=`/`[Install]`. It also
covers the absence of `PrivateTmp`, `ProtectSystem`, `ProtectHome`, `NoNewPrivileges` and
`KillMode=mixed`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `StartLimitIntervalSec=0` → `1h` plus `StartLimitBurst=5` | RED |
| 2 | `RestartSec=120` → `RestartSec=1` | RED |
| 3 | Delete `TimeoutStartSec=` (the oneshot default is infinity) | RED |
| 4 | Add `[Install] WantedBy=multi-user.target` to the service | RED |
| 5 | Add `PrivateTmp=yes` | RED |
| 6 | The timer loses `OnBootSec=` | RED (static directive row, plus T11 in Tier B) |
| 7 | Move `StartLimitIntervalSec=0` from `[Unit]` into `[Service]` | RED (the static parser is section-aware: in `[Service]` the key is ignored with a warning) |
| 8 | Delete the xtrace refusal `case "$-" in *x*) … exit 78` | RED (static presence, plus a Tier A run under `dash -x -u` that must exit 78 before any emit) |
| 9 | Change `ExecStart=` to `/bin/sh -x /usr/local/bin/soleur-inngest-provision` | RED (static: ExecStart must be the bare script path) |
| 10 (must-PASS) | `RestartSec=2min` (a unit-suffixed equivalent) | PASS |

### Guard 7 — no implicit shared-shell state (P8; runtime, by execution)

**Property.** Every variable the rendered script reads on any exercised path is set by one of
these sources: the script itself, a file the script loads with `.` (`/etc/default/soleur-zot-read`),
the unit's `Environment=`/`EnvironmentFile=` keys, or a Terraform template variable resolved at
render. No value may reach it from a `runcmd` item it no longer shares a shell with.

**Assembly.** Every Tier A and Tier B scenario (T1–T12, T14, T15) runs the rendered script under `sh -u`.

- **Tier A** runs it with `env -i` plus only the fixture keys of `/etc/default/inngest-doppler`
  (the `:753` format) and the unit's `Environment=` lines.
- **Tier B** runs it under real systemd, through the test-only drop-in
  `ExecStart=/bin/sh -u /usr/local/bin/soleur-inngest-provision`.
- The `/etc/default/soleur-zot-read` fixture is present in both, because `runcmd` writes it
  before the unit can start.

An unset read aborts the scenario. The chokepoint is the process environment the script starts
with, plus the files it loads.

This replaced a static free-variable parser, which a line scanner cannot do correctly over dash
heredocs and quoting (Sharp Edges). The residual is that it covers **exercised paths only**. The
scenario list is chosen so that every arm runs at least once: miss, recover, isolation FATAL,
bootstrap fail, stale container, unnamed arm, rc 124, garbled counter, timeout, and FSM busy.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Insert a read of `$ZOT_EP` before its in-script derivation from `/etc/default/soleur-zot-read` | RED (T2 aborts under `-u`) |
| 2 (own dispatch) | Harness runs the script WITHOUT `-u` (Tier A invocation drops the flag; Tier B drop-in absent). The harness asserts `-u` is in effect via a sentinel read of a guaranteed-unset name in a fixture-only probe run | RED |
| 3 | After a compliant first read of `$DOPPLER_TOKEN` (sourced from `EnvironmentFile`), add a second read of an unsourced `$DOPPLER_PROJECT_OVERRIDE` | RED (T2) |
| 4 | Remove `DOPPLER_CONFIG_DIR` from the fixture (and the `:753` write) while the script still reads it | RED |
| 5 (must-PASS) | A `${VAR:-default}` read of an unset name | PASS |

### Guard 8 — isolation is re-proven on every attempt (security P2; static + runtime)

**Property.** Every attempt runs the boot-credential isolation check before any `docker pull`, and
no state that persists across attempts can admit a pull without a fresh check.

**Assembly.** The script's isolation-check site, its first `docker pull` site, and every read or
write of any path under `/run/`, `/var/lib/soleur-inngest-provision/` or `/tmp/` that could carry
an isolation verdict between attempts. The chokepoint is the ordering of the check relative to the
first pull within one script execution. The retired `/run/soleur-inngest-doppler.ok` sentinel is
the known instance of the forbidden shape.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the isolation check with `test -f /run/soleur-inngest-doppler.ok \|\| exit 1` (the retired sentinel gate) | RED (static: any reference to the retired sentinel path) |
| 2 | REORDER: move the isolation check below the pull loop | RED (T3: exactly zero pull calls before the FATAL) |
| 3 | Empty script (the guard's own dispatch: zero isolation sites found) | RED |
| 4 | After a compliant check, cache its verdict to `/var/lib/soleur-inngest-provision/iso.ok` and skip the check when that file exists | RED (static: a verdict file written or read by the script; Tier A T3 run after a prior passing run in the same fixture must still FATAL) |
| 5 (must-PASS) | The isolation regex gains a new admitted name appended in its `INNGEST_(…)` group, keeping the `HEARTBEAT_URL)\|BETTERSTACK_LOGS_TOKEN)` anchor | PASS |

**Anchor (all eight guards).** The guards compare structure, not stored hashes, so no stored value
needs an anchor. The two-ref pin invariant is anchored by an independent consumer,
`bump-inngest-bootstrap-pin.sh`, which fails closed at the next bump.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `cloud-init-inngest.yml` has **zero** `docker pull` and **zero** `docker login` in `runcmd`,
  and exactly one of each in the `soleur-inngest-provision` script (Guard 1). The PR body cites
  the suite row IDs.
- [ ] `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts`
  equals 35 and carries the PLACEMENT/TRUTH/NO SUBSTITUTE comment for this plan. The G1 test in
  that file is green.
- [ ] The script contains exactly one `trap … EXIT` (Guard 2 row 7), the xtrace refusal (Guard 6),
  the cutover-FSM quiesce **before** the bootstrap invocation (Guard 2 REORDER row, T15), and **no**
  `mountpoint` precondition (withdrawn at deepen-plan; `grep -c 'mountpoint -q /mnt/data'` on the
  script is 0).
- [ ] The Terraform-pipeline render (Phase 0.2) is ≤ 32,768 B and starts with `#cloud-config`.
- [ ] `inngest-userdata-budget.sh` passes, with the measured stored bytes recorded in the PR body.
- [ ] Every Guard Contract RED row reddens its guard and every must-PASS row passes.
  - The suite prints its row count.
  - That count equals the matrix total: 8 guards, 59 rows, of which 51 RED and 8 must-PASS.
  - The suite reports rows **by ID** (`G<n>-r<m>`), counts only rows it actually **executed**,
    and in CI fails if any row did not execute. Tier B rows execute through their static or Tier A
    detector when Tier B is skipped.
  - This total was derived by an awk count over `## Guard Contract` at plan time. Re-derive it
    the same way if a row changes.
- [ ] Tier A scenarios C0, T1–T5, T7, T8, T14, T16 and T17 pass (Tier A never skips). Each runs the Terraform-rendered script, path-rewritten through the G4
  table (every pair asserted to match), under `dash -u` with `env -i` plus the executed-`:753` fixture.
- [ ] Tier B scenarios T6, T9–T12 and T15 pass on systemd 255 as PID 1, all six in one logged run.
  - The PR body shows one green Tier B run of all six scenarios on this branch (CI or local),
    with its log excerpt.
  - The only allowed skips are named: docker absent, an ADR-188 apt-archive `arm_skip`, or an
    unbootable systemd container. The PR body names any arm that skipped.
- [ ] `systemd-analyze verify` is clean over the extracted `.service` and `.timer`.
- [ ] Every Phase 3 suite is green with **no net loss of assertions**. The PR body gives
  before/after counts.
- [ ] Exactly 2 well-formed pinned refs remain:
  `grep -oE 'jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' apps/web-platform/infra/cloud-init-inngest.yml | wc -l` prints `2`.
- [ ] `bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run` on the branch reports a
  `noop` decision.
- [ ] `git diff --name-only origin/main...HEAD` contains none of these paths:
  - `apps/web-platform/infra/inngest-bootstrap.sh`
  - `apps/web-platform/infra/vector.toml`
  - any `cp` carrier named in `build-inngest-bootstrap-image.yml:350-371`
  - `apps/web-platform/infra/inngest.tf`
  - `apps/web-platform/infra/inngest-host.tf`
  - `apps/web-platform/infra/sentry/`
  - `apps/web-platform/infra/variables.tf`
  - `apps/web-platform/infra/zot-registry.tf`
  - `apps/web-platform/infra/cloud-init-registry.yml`
  - `.github/workflows/`
- [ ] Architecture record:
  - ADR-256 (or the re-verified ordinal) exists.
  - ADR-115 and ADR-096 carry dated notes.
  - `model.c4`'s `inngest -> sentry` prose no longer says "ENDS the boot".
  - `model.likec4.json` is regenerated.
  - The C4 syntax, render and count-parity tests are green.
- [ ] The runbook section exists: `grep -c '^## Provision unit (#8562)' knowledge-base/engineering/operations/runbooks/inngest-server.md` prints `1`, which makes the negative grep below non-vacuous. Then `grep -nE 'ssh |rm .*soleur-inngest-provision/done|systemctl (restart|start) soleur-inngest-provision' knowledge-base/engineering/operations/runbooks/inngest-server.md` returns nothing.
- [ ] `scripts/followthroughs/inngest-provision-unit-8562.sh` prints exactly one
  `verdict=` line, exits 0/1/2 per its documented verdicts, and is fixture-tested like its 8539
  twin.

### Merge (ship)

- [ ] The squash commit body contains a line that is exactly `[skip-web-platform-apply]`, and the
  push run's `apply` job reads `skipped`.
- [ ] No `mint-inngest-bootstrap-tag.yml` run on the merge SHA minted a tag: either there was no
  run, or the run's summary reads `noop`.
- [ ] No `registry-host-replace-dispatch.yml` run exists on the merge SHA.
- [ ] #8562 carries the follow-through directive and the `follow-through` label.
- [ ] The three follow-up issues exist (rehearsal, Sentry non-pull provision alert, `op=resume`
  `bootstrap-done` G-row), each with a re-evaluation trigger.
- [ ] #6780 carries the SOLEUR-DEBT and Vector notes.

### Post-delivery (follow-through, not this PR)

- [ ] After the next operator-approved `inngest-host-replace` plus `op=resume`,
  `inngest-provision-unit-8562.sh` reads `verdict=PASS`. The sweeper then closes #8562, and
  ADR-256 flips to `accepted`.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** One PR is the right scope. The unit, the script and the tests must move together,
and nothing touches `.tf` or `inngest-bootstrap.sh`. The cuts are sound.

Concerns raised, each folded in:

- **A1, implicit shared-shell state (high).** Covered by P8, Guard 7 and the Phase 1.2 census.
- **A2, the cgroup kill on retry or timeout (high).** Mitigated three ways:
  - `TimeoutStartSec` of at least 3× the measured attempt;
  - a TERM trap so a timeout still emits;
  - the default `KillMode`.

  The bootstrap's idempotency contract covers re-runs, but not a SIGKILL at an arbitrary line.
  That residual is recorded under Risks.
- **A3, nested `systemctl` deadlock (medium).** Guard 5 row 5 forbids a back-edge.
- **A4, `EnvironmentFile` parsing (medium).** T6 runs on real systemd in Tier B.
- **A5, duplicate first-boot triggers (low).** The timer is enabled without `--now`.

The riskiest aspect is that the unit's first real run happens during the sole scheduler's
replace. The CTO recommended a systemd-as-PID-1 rehearsal. It is adopted as Tier B of
Phase 4.3. The prose sweep was widened to both runbooks and ADR-096. The "template vs live host"
wording is required throughout.

### Infrastructure (terraform-architect, Phase 2.8)

**Status:** reviewed

**Assessment:** The IaC routing is correct: cloud-init `write_files` plus `runcmd` arming,
delivered by replace, with no manual step. Merge claims (a)–(c) are confirmed with independent
evidence.

The review added the following, all folded in:

- the `web-platform-release.yml` finding;
- the mint dry-run;
- the timer-`--now` hazard, since confirmed by local measurement;
- the TERM trap and T9;
- the page-flood control (proposed as decaying Sentry emits; the plan review cut the decay in
  favour of the rule's existing 23-min throttle);
- `RuntimeDirectoryPreserve=restart` (superseded at plan review by keeping the counter in
  `StateDirectory=`);
- the no-sandboxing assertions;
- the explicit `exit 0` after the latch;
- the Terraform-pipeline render assertion;
- the runbook's "wait for recovery before replacing" rule.

### Product/UX Gate

Not applicable. There is no UI surface in Files to Create or Files to Edit, and Product was not
flagged.

### Plan review dispositions (DHH, Kieran, code-simplicity; 2026-09-28)

**Applied (mechanical):**

- Kieran 1: guard row totals are derived by count (46 rows at plan review; 59 rows, 51 RED, 8
  must-PASS after deepen-plan).
- Kieran 2: one combined EXIT trap, the moved `trap` lines deleted, `set +e` in the trap body
  (measured in dash).
- Kieran 3: Guard 7 source set, recast as a runtime `sh -u` guard.
- Kieran 4: login moved into Guard 1.
- Kieran 5: the `multi-user.target` assertion moved to T11.
- Kieran 6: static detectors for rows that Tier B alone would catch; a Tier B run evidenced in the
  PR body.
- Simplicity: the recovery event is cut, the latch is content-free, and the static Guard 7 parser
  is cut.
- DHH 1: Guards 2, 3, 4 and 7 are enforced by the runtime harness.
- DHH 2: Guard 7 proven by execution.
- DHH 6: the counter lives in `StateDirectory=`.

**Applied (taste):**

- DHH 3 / simplicity: one harness file with two tiers. It is not a single systemd-only harness,
  because nothing in the repo already runs systemd as PID 1 in a container and Tier A must not
  depend on it.
- DHH 4 / simplicity: the power-of-two page decay is cut.
- Kieran 7: timing is driven through a `timeout` stub and unit drop-ins.
- Kieran 8: the `/mnt/data` mount precondition and T13. **Withdrawn at deepen-plan** (architecture
  P2): it would turn today's degraded-but-serving first boot into a dark retry loop; the existing
  Redis mount and mapper-identity guards already protect the AOF.
- Kieran 9: rate figures account for how long a failed attempt takes.

**Declined, with reasons (persisted to `decision-challenges.md`):**

- **DHH 7**, drop the own-dispatch and harness rows: the Guard Contract gate (plan Phase 2.12)
  requires both.
- **DHH 8**, fold ADR-256 into an ADR-115 amendment: the issue says the restructure "needs its own
  ADR", and ADR-115 is scoped to the registry.
- **DHH 9**, hardcode `TimeoutStartSec`: a figure that enters a budget must be measured (Sharp
  Edges). A fallback is kept.
- **DHH 5 / simplicity**, `enable --now` as the only trigger: an explicit `start --no-block`
  does not depend on elapsed-`OnBootSec` semantics. T12 pins that there is one trigger.
- **Simplicity:** keep `provision-unit-armed`, since only it separates "never armed" from "armed
  but never started". Keep the ADR-096 and ADR-115 notes, since they correct prose this change
  falsifies. Keep a dedicated probe file, following the #8539 precedent of one probe per
  tracker.

## Test Scenarios

Every scenario asserts an **exact** return code and an ordered emit sequence. It fails on any
`parameter not set` in stderr, and treats rc 2 or rc 127 as an instrument fault (Phase 4.3).
Timing is driven only by stubs and unit drop-ins in the test fixture or container, never by a
seam in the production script.

### Tier A (fixture root, `dash -u`, `env -i` + executed-`:753` fixture; never skips)

- **C0, control.** The pristine render runs every scenario below green before any mutation is
  applied.
- **T1, miss.** The pull stub returns rc 1 on all 3 tries.
  - Exit is **1**, and there is no latch.
  - **No** `docker create`/`cp` is recorded after the miss.
  - `inngest_pull_fatal … attempt=1` is emitted on both channels and is the **last** named-stage
    emit before `provision-attempt-exit-1`.
- **T2, recover.** Attempt 2: the pull returns 0 and the bootstrap returns 0.
  - Exit is **0**, the empty latch exists, and the counter reads 2.
  - `bootstrap-done iid=…` is emitted after attempt 1's `inngest_pull_fatal`.
  - No `provision-attempt-exit` is emitted.
- **T3, isolation FATAL.** The doppler stub lists a foreign name.
  - Exit is **1**, and `isolation-check-FAILED` is emitted.
  - **Zero** `docker pull` calls are recorded, and there is no latch.
- **T4, bootstrap fails.** The pull returns 0 and the bootstrap returns 1.
  - Exit is **1**, with `bootstrap-exit-1` then `bootstrap-failure-journal` emitted, and there is
    no latch.
  - The `systemctl stop inngest-cutover-flip.timer inngest-luks-cutover.timer` stub call is
    recorded **before** the bootstrap invocation.
- **T5, stale container.** Create returns a new ID after the stale-name pre-clean.
  - `rm -f soleur-inngest-bootstrap-extract` precedes `create`, and every `cp` addresses the
    **returned ID**.
  - Exit is **0**.
- **T7, unnamed arm.** The `docker cp …/inngest-bootstrap.sh` stub returns 1.
  - Exit is **1**.
  - The EXIT trap emits `provision-attempt-exit-1` on the phone-home and
    `provision_attempt_failed` via `soleur-boot-emit`.
- **T8, timeout miss.** The `timeout` stub returns 124 for the pull.
  - There is exactly **one** pull call (no inner retry after 124), and exit is **124**.
  - `inngest_pull_fatal … rc=124 attempt=1` is emitted.
- **T14, garbled counter.** The `attempts` file holds non-digits from a truncated write.
  - The attempt runs as `attempt=1` and ends with the scenario's own expected rc, never an abort
    from counter parsing.
- **T16, stale staged asset.** A planted `/tmp/inngest-cutover-flip.sh` from a prior attempt, with
  the `docker cp` of that asset stubbed to fail.
  - The planted file is **absent** when the bootstrap stub runs, because the per-attempt `rm -f`
    removed it.
- **T17, channel re-arm.** `/run/inngest-bs-logs-token` is empty at attempt start.
  - The restage script stub is invoked once, before `provision-attempt-start`.

### Tier B (systemd 255 as PID 1; rendered unit, timer and script; stubs; `sh -u` drop-in)

- **T6, token delivery.** Every doppler stub call records `DOPPLER_TOKEN` and `HOME=/root`, which
  come only from real `EnvironmentFile=` parsing.
- **T9, timeout.** A drop-in sets `TimeoutStartSec=5s`, and the bootstrap stub sleeps 60 s.
  - `provision-attempt-exit-143` is emitted **within 10 s** of the timeout, well before the 90 s
    `TimeoutStopSec` SIGKILL, because the child runs as `& wait`.
  - The next attempt's `provision-attempt-start attempt=2` follows it.
- **T10, ladder.** A drop-in sets `RestartSec=2s`. The pull fails twice, then succeeds.
  - `NRestarts=2`, the state is `active (exited)`, and the latch is present.
  - A timer start injected during the restart wait adds **no** attempt.
- **T11, reboot re-entry.** A drop-in sets the timer to `OnBootSec=2s`. Poll with a bound; do not
  sleep.
  - **Latch absent:** restart the container. The unit starts from the timer within 15 s, and
    **`multi-user.target` reaches `active` while the unit is still retrying**, which catches a
    stray `[Install]`.
  - **Latch present, set by a real T10 success rather than a pre-seeded file:** restart the
    container. The unit is condition-skipped, and **zero** `provision-attempt-start` rows appear.
    This checks that the latch survives a reboot (latch lifetime).
- **T12, single first-boot trigger.** A drop-in sets `OnBootSec=1s`, and the arming items run
  after 5 s of uptime (the timer is already elapsed).
  - Exactly **one** `provision-attempt-start attempt=1` appears within 10 s.
  - `systemctl is-active soleur-inngest-provision.timer` reads `inactive`, because the timer is
    enabled without `--now`.
- **T15, cutover FSM busy.** A stub `inngest-cutover-flip.service` sits `activating` for 20 s when
  the attempt reaches the bootstrap step.
  - The bootstrap stub starts only **after** that service leaves `activating`.
  - With the wait bound shortened to 5 s by the stub, the attempt exits **1** with
    `provision-fsm-busy` and retries.

Guards 1, 5 and 6 (static) and `systemd-analyze verify` cover structure. Every Guard 2, 3, 4 and 7
row that only Tier B would catch also has a static or Tier A detector (Guard Contract), so a Tier B
skip loses no RED row.

## Risks and Sharp Edges

- **The first live run happens on the sole scheduler.** Tier B proves the systemd behavior. It
  cannot prove real Doppler, real zot, the private NIC, or Hetzner's boot timing; the rehearsal
  follow-up issue covers those. Rollback is a revert, another replace and `op=resume`. The runbook
  says so.
- **SIGKILL mid-bootstrap, from a timeout, reboot or shutdown.** The kill reaches only the
  provision unit's cgroup: the script and its `systemctl` clients. Redis, the server and the flip
  run in their own cgroups, and PID 1 finishes a job even when its client dies (architecture P3).
  - What remains is a half-written unit file or binary, which the next attempt's idempotent
    bootstrap re-installs.
  - Mitigations: a `TimeoutStartSec` derived from step bounds, and the children run as `& wait`
    with the TERM trap so the attempt reports before SIGKILL.
- **Collision with an operator `op=resume`** is mitigated by the pre-bootstrap FSM quiesce (T15).
  The `op=resume` G-row is deferred.
- **Arming residual.** If a `runcmd` item aborts before the arming items, the host stays dark
  until a replace, exactly as today. It is not widened.
- **The pending delta blocks `inngest-volume-recut` until delivery.** Disclosed.
- **A `web-v*` release on merge is unavoidable** for any change under `apps/web-platform/**`.
  Disclosed and recorded in `decision-challenges.md`.
- **Mint trap.** One byte changed in `inngest-bootstrap.sh`, `vector.toml` or any other carrier
  auto-mints a tag and dispatches a build. The diff-scope acceptance criterion forbids it.
- **Sentry path trap.** Touching `apps/web-platform/infra/sentry/**` fires `apply-sentry-infra`.
- **Bump-bot trap.** Exactly 2 refs must remain, and no unit text or comment may name the ref.
- **Strip regex and indentation.** `local.inngest_rationale_strip` removes whole-comment lines
  everywhere, including inside the script and the units. `#!` survives. A comment line indented
  less than its `content: |` block breaks YAML before the strip ever runs.
- **Templatefile escaping.** Carry `%%{http_code}` and `$${…}` verbatim, and write new shell
  `${…}` as `$${…}`. A `%` inside a unit directive is a systemd specifier, so keep it in the
  script.
- **dash, not bash.** Keep `#!/bin/sh`. dash runs no EXIT trap on a signal without a TERM trap.
- **`OnBootSec` fires at once when already elapsed** (measured). That is why the timer is enabled
  without `--now`.
- **Page cadence changes.** A host that stays dark now pages about every 23 min (the rule's
  throttle) instead of once. The runbook explains `attempt=N`. Better Stack row volume on a
  fast-failing host is up to about 150 an hour (Vendor-tier reality check).
- **The SOLEUR-DEBT at `inngest-bootstrap.sh:58`** is arguably triggered. It is mitigated on the
  caller side (Guard 4 row 5) and recorded on #6780.
- **Deepen-plan gate.** A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. This plan's
  section is complete.
