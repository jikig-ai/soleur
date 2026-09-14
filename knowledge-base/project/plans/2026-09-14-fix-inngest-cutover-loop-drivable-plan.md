---
title: "fix(inngest cutover): make the execute → quiesce-web → execute → arm loop drivable end to end"
date: 2026-09-14
slug: fix-inngest-cutover-loop-drivable
branch: feat-one-shot-6921-cutover-loop-drivable
issue: 6921
closes: [6921, 8077]
type: fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(inngest cutover): make the execute → quiesce-web → execute → arm loop drivable end to end

## Enhancement Summary

**Deepened on:** 2026-09-14
**Sections enhanced:** Proposed Solution (predicate), Phase 2c/3 (in place), Guard Contract (Guards 1/2/4 rows), Acceptance Criteria (FR10/FR13/FR16), User-Brand Impact (CPO C1 resolved), Observability (probe), plus a new `## Deepen-Plan Corrections` section (C1–C13) that supersedes conflicting earlier text.
**Research agents used:** 4 read-only verifier/research subagents (ci-deploy.sh + mocks; rearm/inventory/classifier/workflow; cutover-inngest.sh/runbook/ADR/C4; systemd + Inngest source + GNU timeout + learnings). Gates run inline: 4.5 network-outage (Hypotheses already layer-verified), 4.6 User-Brand Impact (pass), 4.7 Observability (fixed), 4.8 PAT sweep (no hits), 4.9 UI (n/a), 4.10 Encryption Posture (n/a — no new store/connection), 4.11 Guard Contract lint (pass), 4.55 Downtime (n/a — no reboot/DDL/container swap).

### Key Improvements

1. **P1 — quiesced shape widened to `is-active ∈ {inactive, failed}` ∧ `disabled`.** A stop that ends in SIGKILL at `TimeoutStopSec` leaves `failed`+`disabled`; `verify_inngest_quiesced` already calls that `quiesced`, and the strict predicate would have let the watchdog restart it.
2. **P1 — the `SECRET=` relocation's hidden blast radius:** ~25 assertions in `webhook-doppler-token-reread.test.sh` (#8135) use capture mode as the Doppler-read vehicle; they are re-pointed to `rearm-from-capture` + `[]`, keeping every credential assertion's producer.
3. **A fifth start writer** (the `workspaces-cutover.sh` dead-man `sh -c` string) contradicted the plan's "starts nothing — verified"; gated + Guard 2 #6d, and the 6c assembly row gets a named allowlist so it is not RED on day one.
4. **Full-inventory QUIESCED needs the `/health` read hoisted** out of the `LIVENESS_ONLY` block — 2.2 calls the full-mode hook.
5. **FR13 resolved from Inngest v1.19.4 source:** a past event `ts` fires immediately (late), never dropped; the conditional clamp follow-up is not needed.

### New Considerations Discovered

- Stateful `systemctl` mock must be opt-in (default would flip AC-Q5/AC-Q6); AC-Q6 now reaches capture and needs a default mock rearm.
- Capture invocation: `timeout --kill-after=5 … 200>&-`, stderr tail via existing `_cred_err_tail` (200 chars); escape hatch for an active-but-GQL-dead unit is restart then re-quiesce.
- New deploy-status reasons belong in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` (the runbook has no reason table).
- Numerous line citations corrected (rearm `SECRET=` :161-166; workflow :71/:93/:104/:115-138/:141/:390; FR10 token lines; runbook §1 :862; `model.c4` :205/:206/:210).

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The dedicated-host Inngest cutover is driven by `scripts/cutover-inngest.sh` through `cutover-inngest.yml`. Today the documented loop — `op=execute` → `op=quiesce-web` → `op=execute` → `op=arm` — cannot be driven end to end from CI: the second `op=execute` re-runs its 2.1 reminder capture against the web scheduler that `op=quiesce-web` just stopped and fails there (#6921), and the 15-minute watchdog `scheduled-inngest-health.yml` reads the deliberately quiesced scheduler as `inngest_down` and dispatches a restart that starts the disabled unit again (#8077). This plan closes both defects with ONE measurable on-host signal — the quiesced unit shape, `systemctl is-active` = `inactive` AND `systemctl is-enabled` = `disabled`, which only `op=quiesce-web`'s `quiesce inngest` handler writes and only `op=rollback`'s `enable inngest` handler clears — consumed at four points: the capture script (resume from the persisted capture), the liveness probe (a distinct `QUIESCED` verdict the watchdog never remediates), and the two actuators that can start the unit — the `restart` handler and the `deploy inngest` bootstrap arm — which both refuse a quiesced unit. The `quiesce` handler itself captures the still-armed reminders BEFORE it stops the scheduler, so the persisted capture a second `op=execute` resumes from is taken at the quiesce boundary, not minutes earlier. The 2.2 hard gate is upgraded to certify that same shape instead of the "any stable non-200" proxy it accepts today.

The third item in the brief — that `CUTOVER_HOSTS` pins a destroyed web-2 and the peer fan-out would report failure after mutating web-1 — was **measured false this session** (see Research Reconciliation): `soleur-web-2` (hcloud id 155786558, 10.0.1.11, cpx22) has been running since 2026-07-27, ci-deploy's `FANOUT: peer 10.0.1.11 accepted deploy (HTTP 202)` appears 21× in the last 72 h of Better Stack, and an existing parity test pins `CUTOVER_HOSTS` to `variables.tf`. No host-set change ships; the stale prose that describes web-2 as retired (or as a warm standby running its own scheduler) is corrected instead.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Phase 2.8 reviewed: this plan provisions **no** new server, unit, cron, secret, vendor, DNS record, firewall rule or webhook. Every unit-state verb it names (`stop`/`disable`/`enable`/`start`/`restart` on `inngest-server.service`) is EXISTING code inside `apps/web-platform/infra/ci-deploy.sh`'s webhook-executed handlers, already pinned by the Terraform-rendered sudoers aliases (`INNGEST_QUIESCE`, `INNGEST_ENABLE`, `INNGEST_START`, `INNGEST_RESTART` in `cloud-init.yml`) and already delivered to hosts by the Terraform-provisioned infra-config push (`apply-deploy-pipeline-fix.yml` → `push-infra-config.sh` → `infra-config-apply.sh` FILE_MAP rows :220/:228/:231). The change edits the handlers' logic and lands by the same automated push on merge; no `.tf`, cloud-init, sudoers or bootstrap-script change is needed and no human runs anything on a host.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (measured 2026-09-14, read-only) | Plan response |
|---|---|---|
| "web-2 (10.0.1.11) was retired and destroyed on 2026-07-17; `CUTOVER_HOSTS: "10.0.1.10,10.0.1.11"` is stale" | The **fsn1** web-2 was destroyed 2026-07-17 (#6538). A **fresh hel1 cattle web-2** was born 2026-07-27T11:00:53Z as hcloud `155786558` at private IP 10.0.1.11 (#6969, ADR-143): `GET /v1/servers` via `doppler run -p soleur -c prd_terraform` lists `soleur-web-2 running cpx22 private=10.0.1.11`. `variables.tf` `web_hosts` default carries `"web-2" = { private_ip = "10.0.1.11" }`. | No pin change. `cutover-inngest-workflow.test.sh` H1 already asserts `CUTOVER_HOSTS == variables.tf private_ip set == WEB_HOST_PRIVATE_IPS`; the brief's "one-line pin fix" would have reddened it. |
| "an unreachable peer yields `quiesced_peer_fanout_unaccepted` / `enabled_peer_fanout_unaccepted` → op=quiesce-web and op=rollback report failure AFTER mutating the host" | `bash scripts/betterstack-query.sh --since 72h --grep FANOUT` → 21 rows, every one `ci-deploy FANOUT: peer 10.0.1.11 accepted deploy (HTTP 202)`; zero `NOT accepted`. The peer webhook is reachable and HMAC-accepting. | The local-then-fan-out ordering stays as documented risk R4: a transient peer non-202 leaves web-1 mutated with a red verdict, but `quiesce` (stop/disable tolerated) and `enable` (AC-E2 idempotent) both converge on re-dispatch, so the loop remains drivable. No mechanism added (Cut List). |
| (implicit in the 2.2 SEAM text) "the weight-0 warm-standby web-2 self-arms oneshots into its OWN Redis … the web-2 freeze/recreate lifecycle REMAINS MANDATORY" | The cattle web-2 was born with `web_colocate_inngest = false` (variables.tf default; no `TF_VAR_web_colocate*` in `prd_terraform`, no workflow override) → cloud-init never authors `inngest-server.service` on it. web-2 runs **no scheduler and holds no local reminders**. The quiesce/enable fan-out to it is a tolerated no-op on an absent unit. | Correct the SEAM 2.2a line, the 2.2 PASSED notice, the quiesce-web completion notice and runbook §1a/§"HISTORICAL — web-2 retired" to the measured state (Phase 4). |
| "#6921: second op=execute re-runs 2.1 against the stopped scheduler" | Confirmed by code: `inngest-rearm-reminders.sh` `capture` mode unconditionally runs `inngest-enumerate-reminders.sh` (GQL on `127.0.0.1:8288`) → exit 1 → hook HTTP 500 → `cutover-inngest.sh:1456` `exit 1`. | Phase 1. |
| "#8077: the watchdog has no quiesce awareness" | Confirmed: `grep -i quiesce scheduled-inngest-health.yml` → nothing; the liveness body for a stopped unit is `inngest-inventory: FATAL …` → `classify_liveness_mode` → `inngest_down` → restart dispatch. `ci-deploy.sh`'s `restart` handler runs the unit restart unconditionally (a restart STARTS a disabled unit). | Phases 2 and 3. |
| "#6921 also: runbook §3b `doppler configs tokens revoke … --yes` is rejected" | `doppler configs tokens revoke --help` (CLI v3.75.3, run this session) lists `-c/--config -p/--project --slug` only — no `--yes`. | Phase 4 drops `--yes` and notes `-replace` already revoked the slug. |

## Hypotheses (network-outage checklist, `hr-ssh-diagnosis-verify-firewall`)

The brief's "unreachable peer" hypothesis is L3→L7 refuted, in order:

- **L3 firewall / private net** — `hcloud_server_network` attaches web-2 at 10.0.1.11 (hcloud API `private_net[].ip` above); the deploy fan-out traverses web-1 → 10.0.1.11:9000 over the private subnet and returns 202 (Better Stack `FANOUT` rows) — the packet path is open. **Verified.**
- **L3 DNS / routing** — not in the path: the peer is addressed by private IP, no name resolution. **Verified (not in path).**
- **L7 TLS / proxy** — not in the path: peer fan-out is plain HTTP + HMAC on the private net (ADR-100 amendment 2026-07-12). **Verified (not in path).**
- **L7 application** — `adnanh/webhook` on web-2 validated the HMAC and answered 202 for 21 consecutive deploys. **Verified.**

Hypothesis disposition: **REFUTED** for the peer-unreachable claim. No SSH was used or is prescribed.

## Problem Statement

1. **The recovery loop is broken at 2.1 (#6921).** `op=execute` 2.1 is a single `POST /hooks/inngest-rearm-reminders {"mode":"capture"}`. The on-host script self-enumerates the loopback GQL. After `op=quiesce-web` the scheduler is stopped, the enumeration fails, the hook returns HTTP 500, and `cutover-inngest.sh` exits 1 with `2.1 capture returned HTTP 500` — the operator is told to re-run the very step that fails. Run `34865196148` reached 2.2 `STILL RUNNING` (the designed first stop); the next dispatch in the documented sequence is the one that breaks.
2. **The watchdog un-quiesces the window (#8077).** `scheduled-inngest-health.yml` probes `/hooks/inngest-liveness` every 15 min. A quiesced unit yields the `FATAL` sentinel → `inngest_down` → `restart-inngest-server.yml` → `ci-deploy.sh restart` → the handler's unit-restart call (sudoers `INNGEST_RESTART`) starts the disabled unit. Three verbs, a 15-minute fuse, invisible to the operator.
3. **The 2.2 hard gate certifies a proxy.** It passes on ANY stable non-200 from `/hooks/inngest-inventory`. A crash-looping (`activating`) but still-enabled unit, or a broken inventory script, passes as "quiesced" today — and a crash-looping enabled scheduler can come back mid-flip (the double-fire the gate exists to prevent).
4. **The operator-facing text lies about the host set** (Reconciliation rows 1–3) and the runbook's revoke command does not run.

## Proposed Solution

One signal, three consumers, one strengthened gate:

- **Quiesced shape predicate** (on-host, read-only, no sudo): `systemctl is-active inngest-server.service` prints `inactive` **or `failed`** AND `systemctl is-enabled inngest-server.service` prints `disabled`. *(Deepen correction — see "Deepen-Plan Corrections" C1: a `systemctl stop` that ends in SIGKILL at `TimeoutStopSec=180` or a non-zero exit of the `doppler run -- … exec inngest` wrapper leaves the unit `failed`+`disabled`, and `verify_inngest_quiesced` (`! is-active --quiet`) already accepts that as `quiesced`; a strict `inactive`-only predicate would let the watchdog restart exactly that unit. `disabled` stays the sole discriminator — `Restart=on-failure`/`RestartSec=5` with default StartLimit means a crashed ENABLED unit loops in `activating`, never settles `failed`+`disabled`. Every "`inactive` AND `disabled`" below reads as this two-state form; the QUIESCED body prints the observed state as `unit=$active_state`.)* Only the `quiesce` handler produces this shape (stop + disable on a unit that carries `[Install]`); only the `enable` handler clears it. It survives a mid-window reboot (disabled units do not start) and is not overwritten by deploys (the deploy path never touches `is-enabled`). It is the same tuple `verify_inngest_quiesced` already asserts on the way in.
- **D1 — capture resumes from the persisted file when quiesced** (`inngest-rearm-reminders.sh` `capture` mode): if the unit is in the quiesced shape AND `/var/lib/inngest/cutover-capture.json` is a valid JSON array → respond `{captured, reminder_ids, capture_file, source:"persisted", captured_at}` (exit 0, journald `resumed persisted capture …`); if quiesced AND no valid file → exit 1 with `ERROR: capture: scheduler quiesced and no persisted capture at … — nothing to resume from; dispatch op=rollback to reopen scheduling, then re-run op=execute`; otherwise (unit not in the quiesced shape) → today's live enumeration, response unchanged (CI reads `.source // "live"`, so the absent field IS the live marker). A serving host whose enumeration fails still FAILS (never a silent fallback to a stale file). `cutover-inngest.sh` 2.1 prints `source` and, on `persisted`, `captured_at`.
- **D1b — capture at the quiesce boundary** (`ci-deploy.sh` `quiesce` handler + `inngest-rearm-reminders.sh`): the `capture` branch of the rearm script needs no Bearer secret (it only enumerates loopback GQL and writes a file; `inngest-enumerate-reminders.sh` has no doppler/secret reference), so the `SECRET="$(read_secret)"` fail-closed block (`:167-172`) moves DOWN to just before the records-source section (`:221`) — capture exits before it, the two re-arm modes still hit it, and `ENUMERATE_CMD`/`MODE`/`CAPTURE_FILE` (`:172-196`) stay where they are (no `set -u` unbound read). The `quiesce` handler then runs `timeout 120 env INNGEST_REARM_MODE=capture /usr/local/bin/inngest-rearm-reminders.sh >/dev/null 2>"$cap_err"` BEFORE its stop verb whenever `systemctl is-active inngest-server.service` prints `active` (an active scheduler MUST be captured — `/health` alone is the return-on-first-failure proxy `verify_inngest_quiesced`'s own comment rejects); a capture failure or timeout is fail-closed — `logger -t ci-deploy "INNGEST_QUIESCE_CAPTURE_FAILED rc=$rc stderr_tail=<_cred_err_tail: last 200 chars, redacted — deepen C5>"`, `final_write_state 1 "quiesce_capture_failed"`, exit 1, nothing stopped — because stopping a scheduler whose reminders were not captured is the exact loss this feature prevents. When the unit is not `active` (already stopped, a re-dispatch after a transient peer failure, `failed`/`activating`, or the cattle web-2 with no unit) the capture is skipped and the existing file is left in place. The handler then runs `disable` BEFORE `stop` (the final shape is order-independent; disabling first shrinks the `deactivating`+`enabled` window a watchdog tick can land in — R8). `webhook.service` runs `User=deploy` with `/var/lib/inngest` (owned `deploy:deploy`, `inngest-bootstrap.sh:142-143`) in `ReadWritePaths` (`cloud-init.yml:267`), so the handler can write the file the webhook path already writes. No new `quiesce-web)` case arm: the existing `*)` arm already fast-fails any unknown terminal reason and points at deploy-status + Better Stack (`logger -t ci-deploy`), where the `INNGEST_QUIESCE_CAPTURE_FAILED` line carries the cause; the runbook reason table names both. This closes the [capture, quiesce] loss window that the brief's "resume from the persisted capture" left open (Property P7).
- **D1c — `op=rearm` with Σ=0 must not dead-end** (spec-flow P1): today the rearm script's `count == 0` branch prints `nothing to re-arm`, deletes the capture file and exits 0; CI's P2-b parser then fails (`could not parse 're-armed=N … total=K'`) and its remedy ("re-run op=rearm — the capture is retained") is false because the file is gone, chaining to `op=rollback`. Fix: the `count == 0` branch emits the canonical `inngest-rearm-reminders: re-armed=0 failed=0 total=0` line BEFORE the `rm -f`; test row `test_rearm_empty_capture_emits_canonical_line`. Run 34865196148 captured exactly Σ=0, so this is the path the next window will take.
- **D2 — a distinct QUIESCED liveness verdict** (`inngest-inventory.sh`): in the functions-query failure branch, before the DEGRADED/FATAL corroboration, if `/health` != 200 AND the quiesced shape holds → emit `inngest-inventory: QUIESCED host_id=… unit=inactive enabled=disabled — deliberate stop+disable (op=quiesce-web); no restart` to stdout (exit 1, so the hook returns non-200 with the body) in BOTH liveness-only and full-inventory modes, plus a journald `SOLEUR_INNGEST_LIVENESS_VERDICT mode=quiesced …` marker. `scripts/inngest-liveness-classify.sh` maps `^inngest-inventory: QUIESCED` → `inngest_quiesced`; `is_restart_family` stays `inngest_down|inngest_unhealthy` only. In `scheduled-inngest-health.yml` the probe step's `case "$MODE"` gains an `inngest_quiesced)` arm that records **no failure** (`failure_mode` stays empty so the pool probe still runs and the Sentry check-in stays `ok`), and prints a `::notice::` naming the state (mirrors the `stopped-by-brake` run-log-only precedent at the dedicated-host arm; prefixed "expected after cutover" so the permanent post-cutover notice is not read as a warning). Nothing else in the workflow changes: no new step output, no auto-close gating. A deliberate stop+disable RESOLVES a "web scheduler down" issue — there is nothing left to remediate on that host — so the existing healthy auto-close running on a quiesced tick is correct (and closes the one `[ci/inngest-down]` a stop-window tick can file, R8). Plan-review rejected both the whole-step gate (pool issues never auto-close post-cutover) and the narrowed in-body gate (the liveness-derived issues never auto-close post-cutover; a second separately-read output beside the workflow's single-source `failure_mode` re-emit contract is a fail-open hazard for future consumers). No issue class is filed for the quiesced state: post-cutover the web unit stays disabled permanently and a per-cycle issue comment would be noise.
- **D3 — both start actuators refuse a quiesced unit** (`ci-deploy.sh`): one helper `inngest_unit_quiesced()` beside `inngest_unit_enabled()` (`:2406`) — exact strings `inactive` AND `disabled`, with a one-line comment on why it is STRICTER than `verify_inngest_quiesced`'s not-enabled test (`static`/`masked`/empty are benign there; here only the shape `quiesce` writes counts, so an absent unit is never mis-read as quiesced) — called from (i) the `restart` handler before the unit-restart call → `final_write_state 1 "inngest_quiesced_restart_refused"` + journald `INNGEST_RESTART_REFUSED: unit inactive+disabled (quiesced) — only op=rollback re-arms`, exit 1; (ii) the `deploy inngest <image>` arm (`case "$COMPONENT" in inngest)` at :3362) before the extract/bootstrap block → `inngest_quiesced_deploy_refused`, because `inngest-bootstrap.sh:1662/:1679` enables and then restarts the unit (reachable from the hand-dispatched `deploy-inngest-image.yml` — CTO risk 1). Two further `start` writers found by architecture review are gated with the same two-string predicate inline (they are separate scripts, no shared lib): (iii) `apps/web-platform/infra/inngest-wiped-volume-verify.sh:236-240` (`/hooks/inngest-wiped-volume-verify`, opt-in destructive proof) refuses with `abort "quiesced_refused" …` before its stop/wipe/start; (iv) `apps/web-platform/infra/workspaces-cutover.sh:633-636` (the luks-cutover resume reconcile, root over the SSH bridge) skips its `start` + logs `SOLEUR_WORKSPACES_LUKS inngest_start_skipped reason=quiesced` when `is-enabled` prints `disabled` (deepen C6 CONTRADICTS the original "`:818` starts nothing": the dead-man `systemd-run … /bin/sh -c` string's remount-success arm runs `${starts}` then `systemctl start inngest-server.service` UNCONDITIONALLY — it is a fifth start writer and is gated too, inline in the `sh -c` string with the escaped two-state predicate, e.g. `[ \"\$(systemctl is-enabled inngest-server.service 2>/dev/null)\" = disabled ] || systemctl start inngest-server.service`). Together these close the mechanism ("a restart on a disabled unit STARTS it") for every start path on the web host; only the deliberate `enable` verb (op=rollback) re-arms. The two pollers gain a legible arm: `restart-inngest-server.yml`'s `terminal_fail` print and `deploy-inngest-image.yml:120`'s hardcoded "likely inngest-redis-bootstrap…" line both get `case "$REASON" in inngest_quiesced_*_refused) ::error:: the web unit is quiesced by op=quiesce-web — deliberate; only op=rollback re-arms ;;`.
- **D4 — 2.2 certifies the invariant**: the gate's probe loop additionally records whether any non-200 body carries `^inngest-inventory: QUIESCED`. Verdicts: any 200 → STILL RUNNING; every probe non-200 AND ≥1 QUIESCED body → quiesced; every probe non-200 without the sentinel → `UNKNOWN` fail-closed. The remedy is ONE sentence chosen by the same run's 2.1 `source` (spec-flow P1): `source=persisted` proves the rearm script — delivered by the same push and FILE_MAP as the inventory script — saw `inactive+disabled` seconds earlier, so the remedy reads "the on-host inngest-inventory.sh predates the QUIESCED verdict; confirm the config push for the merge landed, then re-dispatch op=execute (do NOT re-run quiesce-web)"; `source=live` reads "the unit is not in the quiesced shape — dispatch op=quiesce-web". The first 120 chars of the last body are printed CR/LF-stripped so the run log shows what the host said. `op=quiesce-web`'s secondary inventory confirm prints whether the sentinel was present.
- **D5 — text and runbook**: the 2.2 `::warning::`, the quiesce-web `::warning::`, the SEAM 2.2a/2.2 PASSED/quiesce-web-complete lines and runbook §"op=quiesce-web"/§1/§1a/§3b are rewritten to the measured state: the loop is drivable, the watchdog does not un-quiesce, web-2 is a scheduler-less cattle standby, `--yes` is dropped.

## Technical Approach

### Architecture

No new component, secret, store or connection. Three existing on-host scripts read two `systemctl` query verbs they already have permission for (`is-active`/`is-enabled` are read-only; `verify_inngest_quiesced` uses both today). One existing classifier gains one token. One existing workflow gains one `case` arm, one step output and one `if:` conjunct. Delivery of the on-host scripts is the existing `apply-deploy-pipeline-fix.yml` push (`paths:` already lists `ci-deploy.sh`, `inngest-rearm-reminders.sh`, `inngest-inventory.sh` — verified `.github/workflows/apply-deploy-pipeline-fix.yml:66,86,89`), so the merge IS the delivery; the workflow and classifier land on the same merge.

Sequencing note (contract-before-consumer): the on-host emitter (D2 sentinel) and the classifier/workflow consumer land in the same PR, but the classifier is written first (Phase 2a) so its tests are RED against the current emitter body until Phase 2b adds the emitter. Until the infra-config push delivers the new `inngest-inventory.sh`, a stopped web unit still yields FATAL → `inngest_down` — i.e. today's behaviour, no regression window that is worse than current.

### Implementation Phases

**Phase 0 — Preconditions (measured, no writes)**

- `grep -n 'is-active\|is-enabled' apps/web-platform/infra/ci-deploy.sh` shows both verbs already used without `sudo` (`verify_inngest_quiesced`, `inngest_unit_enabled`) — no sudoers change.
- `grep -n 'include-command-output-in-response-on-error' apps/web-platform/infra/hooks.json.tmpl` — both `inngest-inventory` and `inngest-liveness` hooks pass the body through on error (lines 161, 181).
- `grep -nE 'inngest-inventory|inngest-rearm-reminders|ci-deploy' apps/web-platform/infra/vector.toml` — all three journald tags are in the Source 4 allowlist (the new log lines reuse existing tags; no vector.toml change).
- Confirm the mock `systemctl` default state in `ci-deploy.test.sh:125-160` is `is-active → inactive` + `is-enabled → disabled` (the quiesced shape) — so every existing `restart … succeeds` row must arm `MOCK_SYSTEMCTL_ENABLED_STATE=enabled` (or `MOCK_SYSTEMCTL_ACTIVE=1`) once D3 lands (Phase 3).

**Phase 1 — D1: capture resumes from the persisted file (RED → GREEN)**

Files: `apps/web-platform/infra/inngest-rearm-reminders.sh`, `apps/web-platform/infra/inngest-rearm-reminders.test.sh`, `apps/web-platform/infra/ci-deploy.sh` (quiesce handler, D1b), `apps/web-platform/infra/ci-deploy.test.sh`, `scripts/cutover-inngest.sh` (2.1 notice; `quiesce-web)` new arm), `apps/web-platform/infra/cutover-inngest-workflow.test.sh`.

1. Tests first (`inngest-rearm-reminders.test.sh`), reusing `setup_mock_curl`, the `enum_stub` pattern and `INNGEST_CUTOVER_CAPTURE_FILE`. Add a mock `systemctl` on `MOCKBIN` driven by `MOCK_SYSTEMCTL_ACTIVE` / `MOCK_SYSTEMCTL_ENABLED_STATE` (same env names as `ci-deploy.test.sh`):
   - `test_capture_resumes_persisted_when_quiesced`: active=inactive, enabled=disabled, capture file holds 2 records, enum stub exits 99 → rc 0, stdout has `"source":"persisted"`, `"captured":2`, `captured_at` matches `^[0-9]{4}-` , enum stub NOT invoked (stub touches a marker file; assert absent), file unchanged (sha256 before == after).
   - `test_capture_quiesced_without_file_fails_with_remedy`: quiesced, no file → rc 1, stderr contains `nothing to resume from` and `op=rollback`.
   - `test_capture_quiesced_corrupt_file_fails`: quiesced, file = `{}` → rc 1 (never returns a non-array as a capture).
   - `test_capture_serving_enumerates_live`: active, enabled, file present with a DIFFERENT record → rc 0, `"source":"live"`, file now holds the enumerated record (overwritten), enum stub invoked.
   - `test_capture_health_down_but_enabled_does_not_resume`: active=inactive, enabled=**enabled** (stopped-but-armed / crash loop), file present, enum stub exits 99 → rc 1 with `enumeration failed` (no stale-file resume outside the quiesced shape).
   - Harness must-FAIL row: temporarily flip the expected `source` in the first test to `live` and confirm the suite reds (recorded in the PR body as the RED evidence), then restore.
2. Implement in the `capture` branch: a `unit_quiesced()` predicate (exact strings `inactive` and `disabled`; `systemctl` resolved from `PATH` so the test mock applies), `captured_at` from `date -u -d "@$(stat -c %Y "$CAPTURE_FILE")" +%FT%TZ`, `source` field in the `jq -nc` status object, journald line `resumed persisted capture: $n reminder(s) captured_at=$ts (scheduler quiesced)`. The capture branch precedes the secret read after D1b (step 4); the predicate writes only to stderr/journald (constitution: nothing that writes stdout inside `$(read_secret)` — the helper block `:53-54` pinned by `webhook-doppler-token-reread.test.sh` is NOT moved).
3. `scripts/cutover-inngest.sh` 2.1: read `.source // "live"` and `.captured_at // ""`; notice becomes `2.1 capture: Σcaptured=N source=<live|persisted> [captured_at=<ts>] …`; no second notice (the `captured_at` in the line is the whole signal; runtime strings carry no plan-deliverable labels). Keep `SOURCE` in a variable for 2.2's remedy (D4). Pin with two grep rows in `cutover-inngest-workflow.test.sh` on the notice format (`Σcaptured=\$SIGMA_CAPTURED source=\$SOURCE`) and on `SOURCE=$(… '.source // "live"')` — no `render_2_1` harness (a one-line jq read does not earn a region driver).
4. **D1b — capture at quiesce (RED → GREEN).** Tests first: in `inngest-rearm-reminders.test.sh`, `test_capture_needs_no_secret` (no `INNGEST_MANUAL_TRIGGER_SECRET`, no `doppler` on the mock PATH, `INNGEST_REARM_SKIP_DOPPLER` unset, serving mock → rc 0, file written — the stronger form; the flag only gates `read_secret`, which capture no longer reaches) and `test_rearm_still_fails_closed_without_secret` (mode `rearm-from-capture`, no secret → rc 1, `INNGEST_MANUAL_TRIGGER_SECRET unavailable`). In `ci-deploy.test.sh`, a mock rearm script on the mock PATH (`INNGEST_REARM_CMD` seam, pattern of `INNGEST_ENUMERATE_CMD`) that appends `capture` to the systemctl verb log and honours `MOCK_REARM_CAPTURE_FAIL=1`; the mock `systemctl` becomes STATEFUL (Kieran P1): its `stop` arm touches `$MOCK_STATE_DIR/stopped`, `is-active` prints `inactive` once that marker exists, and the mock curl's `/health` arm returns non-200 when it exists — otherwise `verify_inngest_quiesced` re-probes a statically-200 `/health` after the stop and writes `inngest_still_serving` (exactly what existing row AC-Q5 pins). Rows: `quiesce captures BEFORE stop when the unit is active` (`MOCK_SYSTEMCTL_ACTIVE=1` → verb log order `capture,disable,stop`; reason `quiesced`), `quiesce fails closed when the capture fails (quiesce_capture_failed) and stops NOTHING` (`MOCK_REARM_CAPTURE_FAIL=1` → reason `quiesce_capture_failed`, exit 1, no `stop`/`disable` in the verb log, `INNGEST_QUIESCE_CAPTURE_FAILED` in the mock logger log), `quiesce skips the capture when the unit is not active` (default mock inactive → no `capture` in the log, reason `quiesced`), `quiesce capture is bounded` (mock rearm sleeps past a test-shrunk `QUIESCE_CAPTURE_TIMEOUT` → `quiesce_capture_failed`). Implement: move the `SECRET=` block down in the rearm script (D1b); in the `quiesce` handler add the `is-active` gate + bounded capture call + `quiesce_capture_failed` write before the disable/stop verbs, and swap the verb order to disable-then-stop. Extend the `QMAX_POLLS×QPOLL_INTERVAL` drift-guard row in `ci-deploy.test.sh` by the 120 s capture bound (spec-flow P2) and the `#6178` poll-window comment in `scripts/cutover-inngest.sh` `quiesce-web)` to match.
5. **D1c — Σ=0 re-arm emits the canonical line (RED → GREEN).** Test `test_rearm_empty_capture_emits_canonical_line` in `inngest-rearm-reminders.test.sh` (mode `rearm-from-capture`, file `[]` → rc 0, stderr contains `re-armed=0 failed=0 total=0`, file removed). Implement in the `count == 0` branch before the `rm -f`. Add a `cutover-inngest-workflow.test.sh` row feeding the `rearm)` arm's P2-b parser the Σ=0 body and asserting it reconciles `0 == 0` instead of `could not parse`.

**Phase 2 — D2: QUIESCED verdict, classifier, watchdog (RED → GREEN)**

Files: `scripts/inngest-liveness-classify.sh`, `scripts/inngest-liveness-classify.test.sh`, `apps/web-platform/infra/inngest-inventory.sh`, `apps/web-platform/infra/inngest-inventory.test.sh`, `.github/workflows/scheduled-inngest-health.yml`, `apps/web-platform/infra/inngest-dedicated-host-classify.test.sh` (workflow drift rows), `scripts/inngest-restart-age-gate.test.sh` (one row: `resolve_effective_failure_mode inngest_quiesced …` passes through unchanged).

- **2a classifier**: test rows `"500 + QUIESCED sentinel → inngest_quiesced (no restart)"`, `"FATAL line whose errors payload embeds QUIESCED → inngest_down (anchored)"`, `"QUIESCED with trailing diagnostic text → inngest_quiesced"` (must-PASS non-canonical), `is_restart_family inngest_quiesced → no`. Implement: `elif printf '%s' "$body" | grep -qE '^inngest-inventory: QUIESCED'; then echo inngest_quiesced` placed BEFORE the FATAL arm (the QUIESCED body is its own line; ordering row in Guard 1).
- **2b emitter**: `inngest-inventory.sh` — add test seams `INVENTORY_UNIT_ACTIVE` / `INVENTORY_UNIT_ENABLED` (pattern of `INVENTORY_REDIS_ACTIVE`), predicate `unit_quiesced()`; in the non-array branch after `_pf_timeout_marker gql_error` and the `ERROR:` logger, evaluate `health_code` (existing seam `INVENTORY_INNGEST_HEALTH_CODE`) and the predicate in BOTH modes; on quiesced emit the marker `SOLEUR_INNGEST_LIVENESS_VERDICT mode=quiesced health_code=… functions=0 durability=… host_id=…` and the stdout line `inngest-inventory: QUIESCED host_id=$HOST_ID unit=inactive enabled=disabled — deliberate stop+disable (op=quiesce-web); no restart` then `exit 1`. host_id stays before any variable-length payload (the #6425 400-char truncation lesson at `inngest-inventory.test.sh:481`). Tests: liveness-only quiesced → QUIESCED body, exit 1, no FATAL; liveness-only `health=500 active=inactive enabled=enabled` → FATAL (unchanged); full-inventory quiesced → QUIESCED (not FATAL); `health=200` with quiesced shape → DEGRADED still wins (serving beats shape).
- **2c workflow**: in the probe step's `case "$MODE"`, add `inngest_quiesced) web_quiesced="yes"; echo "::notice::web scheduler QUIESCED (unit inactive+disabled — op=quiesce-web, #8077): deliberate, no restart dispatched, no [ci/inngest-down] filed; only op=rollback re-arms it"; break ;;` (the notice text starts "expected after cutover:"). Declare `web_quiesced="no"` on the SAME line as `fail_mode=""; fail_detail=""; dstate=""` (workflow `:71` — deepen C8, OUTSIDE the `if [[ -z "$fail_mode" ]]` block — `healthy="no"` at `:90` is inside it, and an unbound read on the `secret_unset` path under `set -uo pipefail` would kill the step before it writes `failure_mode`). Change the post-loop line to `[[ "$healthy" == "no" && "$web_quiesced" == "no" ]] && record_failure …`. No new `$GITHUB_OUTPUT` key; leave agegate/dispatch/file-issue/auto-close/check-in untouched (their allowlists exclude the new mode by construction; the check-in stays `ok` and the healthy auto-close runs because `failure_mode` is empty). Drift rows in `inngest-dedicated-host-classify.test.sh` (it already reads the workflow), every grep over `grep -v '^[[:space:]]*#'`: (ii) the dispatch `if:` line does NOT contain `quiesced` AND carries exactly one `||` (the existing `:99-109` row only checks the line exists, so this negative row is the SOLE producer — Kieran); (v) every mode `classify_liveness_mode` can print (derive by `grep -oE 'echo "[a-z_]+"' scripts/inngest-liveness-classify.sh`, assert ≥ 6 derived after excluding `healthy` (deepen C9: today `grep -oE` yields 6 tokens incl. `healthy`; adding `inngest_quiesced` makes 7 incl. / 6 excl.), EXCLUDE `healthy` which is handled by the `if [[ "$MODE" == "healthy" ]]` branch at `:95` — assert that branch exists instead) has a `case` arm in the probe step AND the `*)` default arm still exists and still maps to `probe_unavailable` (the #6374 trap lives in the default, not the enumerated arms) — the cross-file union guard that did not exist before (repo research §5). Source-shape rows that merely re-assert the diff ("the case has an `inngest_quiesced)` arm", "`record_failure` is guarded") are NOT added — (v) already reddens when the arm is missing.

**Phase 3 — D3: `restart` refuses a quiesced unit (RED → GREEN)**

Files: `apps/web-platform/infra/ci-deploy.sh`, `apps/web-platform/infra/ci-deploy.test.sh`, `knowledge-base/engineering/operations/runbooks/inngest-server.md` (reason row).

- Tests first: arm `MOCK_SYSTEMCTL_ENABLED_STATE=enabled` on the four existing `restart inngest …` rows (`succeeds`, `systemctl failure`, `health failure`, `cron plan de-planned`) — the default mock state is the quiesced shape. Add: `restart refuses a quiesced unit (inactive+disabled)` → reason `inngest_quiesced_restart_refused`, exit 1, AND the mock systemctl verb log has no `restart` entry (extend the mock to append each verb to `$MOCK_SYSTEMCTL_LOG`); `restart proceeds on an inactive-but-ENABLED unit` (a crashed unit is exactly what restart is for) → `success`; `restart proceeds on an ACTIVE disabled unit` → `success` (not the quiesced shape).
- Also: `deploy inngest _ <tag>` with the quiesced shape → `inngest_quiesced_deploy_refused`, exit 1, no `docker create`/bootstrap (extend the existing deploy-inngest rows' mocks with `MOCK_SYSTEMCTL_ENABLED_STATE=enabled` where they expect the bootstrap to run).
- Implement `inngest_unit_quiesced()` beside `inngest_unit_enabled()` (`:2406`): `local a e; a="$(systemctl is-active inngest-server.service 2>/dev/null || true)"; e="$(systemctl is-enabled inngest-server.service 2>/dev/null || true)"; [[ ( "$a" == inactive || "$a" == failed ) && "$e" == disabled ]]` (deepen C1; `|| true` is load-bearing — `is-active` exits 3 on `inactive`, `is-enabled` exits 1 on `disabled` and 4 with stdout `not-found` on systemd ≥ 253, prod is ubuntu-24.04/systemd 255), with the stricter-than-verify comment. Call it in the `restart` handler after `write_state "$EXIT_RUNNING" "running"` (→ `INNGEST_RESTART_REFUSED` logger + `inngest_quiesced_restart_refused`) and at the top of `case "$COMPONENT" in inngest)` before `INNGEST_EXTRACT_DIR` handling (→ `inngest_quiesced_deploy_refused`). Gate `inngest-wiped-volume-verify.sh:236` (`abort "quiesced_refused"`; row in `inngest-wiped-volume-verify.test.sh`) and `workspaces-cutover.sh:633-636` (skip start + `SOLEUR_WORKSPACES_LUKS inngest_start_skipped reason=quiesced` logger; a grep row in `tests/scripts/test-workspaces-luks-cutover-gate.sh` that the start is preceded by the `disabled` check). Add the pollers' `case "$REASON"` arm (`restart-inngest-server.yml`, `deploy-inngest-image.yml:120`) with one grep row each in `apps/web-platform/infra/restart-inngest-workflow-guard.test.sh` / the deploy-inngest workflow test. Add `inngest_quiesced_restart_refused`, `inngest_quiesced_deploy_refused` and `quiesce_capture_failed` to the runbook's deploy-status reason table with remedies (`op=rollback` re-arms; neither a restart nor a bootstrap deploy does — ADR-100 amendment).

**Phase 4 — D4 + D5: 2.2 certifies the shape; text and runbook (RED → GREEN)**

Files: `scripts/cutover-inngest.sh` (2.2 loop + notices, quiesce-web notices, SEAM 2.2a, the `verify)` arm's web-2 caveats at `:874`/`:2131`, and the 2.1/2.2 COMMENT blocks at `:1438-1440`/`:1470-1476`/`:1491`), `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (`render_2_2` region harness + text pins), `knowledge-base/engineering/operations/runbooks/inngest-server.md`, `knowledge-base/engineering/architecture/diagrams/model.c4` (one clause, see ADR/C4 section).

- `render_2_2`: region = `awk '/# ---- 2\.2 QUIESCE HARD GATE/{f=1} f&&/# ---- SEAM: operator maintenance-window steps/{exit} f' "$BODY_SH"` (the same `# ---- ` comment anchors `render_2_0` uses at `cutover-inngest-workflow.test.sh:1925`), non-vacuity floor ≥ 35 non-comment lines (38 today — deepen C7; stub needs a file-backed call counter); curl stub answers a per-call sequence (`STUB_SEQ="500:QUIESCED_BODY,500:QUIESCED_BODY,500:QUIESCED_BODY"`). The driver exports `SOURCE` (the 2.1 variable the remedy branches on). Rows: 3× QUIESCED → rc 0, `PASSED`; 3× FATAL with `SOURCE=live` → rc 1, `UNKNOWN` naming `op=quiesce-web`; 3× FATAL with `SOURCE=persisted` → rc 1, `UNKNOWN` naming "predates the QUIESCED verdict" and NOT `op=quiesce-web`; `QUIESCED,200,QUIESCED` → rc 1 `STILL RUNNING`; 3× `000` → rc 1 UNREADABLE; body `FATAL … not QUIESCED` → UNKNOWN (anchored grep); the UNKNOWN line carries the first 120 chars of the last body. Harness must-FAIL: swap the expected verdict on the first row.
- Implement: a `quiesced_seen=false` flag set when `grep -qE '^inngest-inventory: QUIESCED' /tmp/exec-inv`; verdict tree per Proposed Solution D4; `STILL_RUNNING`/`UNKNOWN_COUNT` semantics unchanged for the SEAM withhold.
- Text: rewrite the 2.2 `::warning::` to drop "KNOWN GAP (#6921)" and the #8077 auto-restart sentence, state that a second op=execute resumes 2.1 from the persisted capture and that the watchdog leaves a quiesced unit alone; rewrite the quiesce-web `::warning::` likewise; rewrite SEAM 2.2a + the 2.2 PASSED notice + the quiesce-web completion notice: web-2 is a cattle standby born with `web_colocate_inngest=false` (no `inngest-server.service`, no local Redis reminders); the fan-out to it is a tolerated no-op; there is no web-2 freeze/recreate step. Rewrite the comment blocks too — a comment contradicting the notice three lines below it is the next maintainer's trap — and the `verify)` arm's two doublefire-probe caveats (`:874`, `:2131`) that restate the web-2 premise. Pin the new prose with grep rows and assert the old tokens (`KNOWN GAP (#6921)`, `web-2 freeze/recreate`, `self-arms oneshots`) are gone from the WHOLE file (comments included).
- Runbook: §op=quiesce-web block (drop the 15-min sentence; describe the QUIESCED verdict), §1 op=execute (2.1 resume semantics, 2.2 shape verdicts + the new UNKNOWN remedy), §1a (replace "[HISTORICAL — web-2 retired #6538]" with the cattle-web-2 statement), §3b (`doppler configs tokens revoke --project soleur-inngest --config prd --slug <slug>` — no `--yes`; note `-replace` already revoked the old slug so (b) is a confirmation), deploy-status reason table (`inngest_quiesced_restart_refused`), watchdog section (the `web scheduler QUIESCED` notice, what it means post-cutover).

**Phase 5 — ADR-100 amendment**

- Append an `### Amendment (2026-09-14, Ref #6921/#8077)` to ADR-100 (via `/soleur:architecture`): the quiesced unit shape is the cutover's measurable quiesce signal; every start writer except the deliberate `enable` verb refuses it (FIVE writers of the unit's active/enabled state on the web host: `quiesce` (writes), `enable` (clears), `restart`, the bootstrap deploy arm, `inngest-wiped-volume-verify.sh`, `workspaces-cutover.sh` — the latter four gated); the watchdog grades it as a non-remediable state; 2.2 certifies it; `quiesce` captures before it stops. Two standing notes: `inngest-bootstrap.sh:1662` tolerates a failed `enable` (`|| true`), the one way `inactive+disabled` could arise without a quiesce — a baked-image change (pin bump) outside this PR, so the Observability audit query ("QUIESCED rows with no op=quiesce-web in the prior 24 h") is the detector until then; and a REPLACED web-1 (`web_colocate_inngest=false`) has NO unit, so `is-enabled` prints empty → FATAL forever → `inngest_down` restart churn into the age gate — pre-existing, the web-liveness arm's retirement is pinned to #7674/#6178 and named in the amendment. Also correct the amendment's stale "LB-routed to a web host" clause (the tunnel is web-1-only, `server.tf:346`). Alternatives rejected: flip-flag read, repo-var/Doppler marker, deploy-status slot, auto-close gating (below). C4: one clause corrected (ADR/C4 section).
- No deferral issue: capture-at-quiesce is folded in as D1b (the scoped advisor and the CPO both flagged the [capture, quiesce] window as the plan's residual loss; the write path was verified feasible — `webhook.service` `User=deploy`, `/var/lib/inngest` deploy-owned and in `ReadWritePaths`).

## Deepen-Plan Corrections (2026-09-14)

Four read-only verifier passes (ci-deploy.sh handlers + mocks; rearm/inventory/classifier/workflow; cutover-inngest.sh + runbook/ADR/C4; systemd/Inngest/`timeout` semantics + learnings) checked the plan against the code on this branch (`origin/main` drift since branch point: one 1-line change inside `cutover-inngest.sh` 2.0 `stale_schema`, no line shift). Where an item below conflicts with text earlier in the plan, **this section wins**; `tasks.md` is updated to match.

**C1 — P1: the quiesced shape must accept `failed`.** `unit_stop()` leaves a unit `failed` when stop ends in SIGKILL at `TimeoutStopSec=180` (learning `2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md` KI5: `systemctl stop` returns 0 after the SIGKILL, `Result=timeout`) or when the `doppler run -- bash -c 'exec inngest'` wrapper exits non-zero on SIGTERM (not measured). `verify_inngest_quiesced` (`ci-deploy.sh:2451` `! is-active --quiet`) accepts that as `quiesced`, so the strict `inactive`-only predicate would leave exactly that unit restartable by the watchdog (#8077 reopened). Predicate everywhere (three delivered scripts + two inline copies): `is-active ∈ {inactive, failed}` ∧ `is-enabled == disabled`. Safety argument unchanged — `disabled` is the discriminator; `Restart=on-failure`/`RestartSec=5` with default StartLimit means a crashed enabled unit cycles `activating`. QUIESCED body prints `unit=$active_state`. New must-PASS rows: Guard 1 #9, Guard 2 #9, Guard 4 #8. The cross-file parity row (Phase 3.5) pins the three literals `inactive`, `failed`, `disabled`.

**C2 — P1: moving the `SECRET=` block breaks the #8135 suite.** `apps/web-platform/infra/webhook-doppler-token-reread.test.sh` drives the rearm script in **capture mode** as its vehicle for the Doppler read (`run_rearm_capture()` :171-182, plus the inline F and C24 invocations): sections B, C, C', C'', D, F — ~25 assertions (B2/B7/D2 `DOPPLER_TOKEN_SEEN`, the fail-closed rc=1 rows C1/C10/C17/C20/C22/C24/C26/C28/D6, and every `SOLEUR_DEPLOY_CRED_FAIL`/Sentry row) go RED once capture skips `read_secret`. The relocation is kept (capture genuinely needs no secret; a Doppler dependency on the quiesce path would block the stop on an unrelated outage), and the suite is re-pointed, not weakened: `run_rearm_capture` → `INNGEST_REARM_MODE=rearm-from-capture` with a pre-seeded `[]` capture file (the secret read at the relocated block still precedes the `count == 0` branch, so every credential assertion keeps its producer); reword B4 ("capture file written"); update its header comment; add row `capture mode never invokes doppler` (doppler mock logs → absent). This file joins Phase 1's touched set and QG1. Correct citations: `read_secret` :134-159, `SECRET=` block **:161-166** (not :167-172), `ENUMERATE_CMD` :173, `MODE`/`CAPTURE_FILE` :194-195, capture branch :197-219, records-source :221. The ":53-54 helper block pinned" claim is incomplete — that test pins helper byte-parity (A3/A3b) and refresh-before-read order (A8), both of which survive.

**C3 — D2 full-inventory mode needs the health read hoisted.** In `inngest-inventory.sh` the `/health` probe, `health_code` and `verdict_mode` locals (:482-489) exist only inside `if [[ -n "$LIVENESS_ONLY" ]]`; full mode goes straight to FATAL (:496). 2.2 calls the FULL-mode hook (`cutover-inngest.sh:1500`), so full-mode QUIESCED is load-bearing: hoist the health read + predicate above the `LIVENESS_ONLY` gate within the non-array branch (adds ≤ 5 s curl to full mode on the failure branch only). The `_pf_timeout_marker gql_error` (:466) and `ERROR: /v0/gql…` lines still fire on every quiesced tick — noise, no alert keys on them (verified no `.tf` match). Both modes reach this branch on connection refused (`fetch_functions … || echo '{"errors":[{"message":"__FETCH_FAILED__"}]…'`) — no earlier exit. Guard 1 #10.

**C4 — `ci-deploy.test.sh` mock realism.** (a) The stateful `systemctl` mock is **opt-in** (`MOCK_SYSTEMCTL_STATEFUL=1`): made default it flips AC-Q5 (:3154, expects `inngest_still_serving`) and AC-Q6 (:3160, `MOCK_SYSTEMCTL_ACTIVE=1`) to `quiesced`. The new capture rows set `MOCK_CURL_INNGEST_HEALTH_FAIL=1` (capture is mocked; it never touches curl). (b) AC-Q6 now reaches the capture (unit active) → `create_base_mocks` exports a default-success mock rearm via `INNGEST_REARM_CMD`, else the row resolves the real `/usr/local/bin/inngest-rearm-reminders.sh` and reads `quiesce_capture_failed`. (c) No verb log exists today; Phase 1 step 4 (not Phase 3) introduces `$MOCK_SYSTEMCTL_LOG`. The logger mock captures only when `MOCK_LOGGER_CAPTURE_FILE` is set (:68-76). (d) `is-enabled` for an absent unit prints `not-found` rc 4 (systemd ≥ 253; learning `2026-09-13-the-mock-that-answered-in-one-line-certified-a-constant…`). (e) At least one rearm/inventory row runs through a PATH `systemctl` stub rather than the `INVENTORY_UNIT_*` env seam (learning `2026-09-11-the-gate-i-built-for-a-dark-host-was-blind-to-the-byte-shape-of-nothing.md`: stub the process the code execs). (f) Rows depending on the default quiesce mock are ~5 (Q1–Q5), not eleven.

**C5 — D1b handler shape (precedent-diff).** Precedents in `ci-deploy.sh`: `timeout "${CRON_DRAIN_PROBE_TIMEOUT}"` (:500), `timeout "$DOPPLER_GET_TIMEOUT"` (:1385), `200>&-` on children (#5062, :1905), `_cred_err_tail` (:1307, 200-char redacting tail). Prescribed: `timeout --kill-after=5 "${QUIESCE_CAPTURE_TIMEOUT:-120}" env INNGEST_REARM_MODE=capture "$INNGEST_REARM_CMD" >/dev/null 2>"$cap_err" 200>&-; rc=$?` → non-zero ⇒ `logger -t "$LOG_TAG" "INNGEST_QUIESCE_CAPTURE_FAILED rc=$rc stderr_tail=$(_cred_err_tail "$(cat "$cap_err")")"` (**200 chars via `_cred_err_tail`, not a hand-rolled 300**). No `--foreground` (children would escape the bound); `timeout` signals its own process group so the script's `curl` dies. Test row 5b asserts non-zero, not exactly 124 (dev boxes may carry uutils `timeout`). The hook is async (`/hooks/deploy` 202 + deploy-status poll), outer bound `ci-deploy-wrapper.sh` `timeout --kill-after=20s 4800s`. Current verb order is **stop (:2686) → disable (:2689)**; D1b swaps it. CI window: `QMAX_POLLS=120 × QPOLL_INTERVAL=5` = 600 s vs host worst case 320 s today + 120 s capture = 440 s (160 s headroom). Drift guard (`ci-deploy.test.sh:3607-3636`, `QDG_RIGHT=…`) extracts the bound by shape `QUIESCE_CAPTURE_TIMEOUT:-120` (exactly one match); add no new `${1:-N}`/`${2:-N}` defaults (DG_HEALTH/DG_INTERVAL require exactly one, :3547-3556). **Escape hatch for an active-but-GQL-dead unit** (capture fails closed forever): the unit is enabled, so not quiesced → `restart-inngest-server.yml` is allowed; runbook remedy for `quiesce_capture_failed` = check Better Stack `INNGEST_QUIESCE_CAPTURE_FAILED stderr_tail`, dispatch a restart, re-dispatch `op=quiesce-web`. No override flag ships.

**C6 — a fifth start writer, and the 6c allowlist.** CONTRADICTS the plan's "`:818` starts nothing — verified": the `workspaces-cutover.sh` dead-man `systemd-run … /bin/sh -c` string's remount-success arm runs `${starts}` then `systemctl start inngest-server.service` unconditionally → gated inline (escaped predicate inside the `sh -c` string) + Guard 2 #6d. The 6c assembly grep also hits `ci-deploy.sh:2745` (enable), `inngest-bootstrap.sh:1679`, `cloud-init.yml:774` (first boot) and `cloud-init-inngest.yml:1251` (dedicated host) → named allowlist in the row. `deploy inngest` gate goes at the TOP of `inngest)` (:3362), BEFORE `pull_image_with_fallback` (~:3383), not before `INNGEST_EXTRACT_DIR` (:3393); assert no `DOCKER_TRACE:pull`; arm `MOCK_SYSTEMCTL_ENABLED_STATE=enabled` on `assert_inngest_docker_trace` rows (:1038/:1079) and #6512(c2) (:4200). `inngest-wiped-volume-verify.sh`: place the predicate after Gate 2 (:217) and before the throwaway-marker arm (:219); its Test 1 counts every mock verb (`systemctl never invoked on abort`, :126), so the row asserts "no `stop`/`start` in the log", not "before any systemctl verb". No deploy-inngest-image workflow test exists — the poller grep row lands in `restart-inngest-workflow-guard.test.sh`.

**C7 — `render_2_2` harness.** The `render_2_0` stub (`cutover-inngest-workflow.test.sh:1953`; its region awk is :1925) is one fixed code/body; 2.2 calls curl inside `$(…)`, so `STUB_SEQ` needs a **file-backed** counter under `$TMPD`. The loop `break`s on the first 200 (the third entry of `QUIESCED,200,QUIESCED` is unused — fine). The region has **38** non-comment lines today → floor "≥ 35" (or state it holds post-change). Driver pre-seeds `BASE`, `WEBHOOK_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`, `SOURCE` (optionally `CUTOVER_QUIESCE_PROBES`); needs `openssl`, `seq`, `jq`. An `UNKNOWN` verdict already exists for `000` (`:1522`), so D4 widens it; SEAM withhold reads `STILL_RUNNING`/`UNKNOWN_COUNT` (:1524). FR15's P2-b row needs a small extraction of the two `sed -n 's/.*re-armed=…'`/`total=` expressions (:964-965) — no P2-b rows exist today. The Σ=0 canonical line goes to **stderr** (matches :294); adnanh/webhook returns combined output, so the parser sees it.

**C8 — workflow citations.** `scheduled-inngest-health.yml`: `set -uo pipefail` :63, `fail_mode=""; fail_detail=""; dstate=""` **:71**, `healthy="no"` :93 (inside `if [[ -z "$fail_mode" ]]`), healthy branch :104, `case "$MODE"` :115-138 inside `for attempt in 1 2 3` (sleep 8; `break` in a case arm exits the loop), post-loop `record_failure` :141, dispatch `if:` :390 (exactly one `||` today), auto-close :594.

**C9 — drift row (v) threshold** is ≥ 6 derived modes excluding `healthy` (applied in place).

**C10 — union-widening sweep gaps.** The new reasons `quiesce_capture_failed`, `inngest_quiesced_restart_refused`, `inngest_quiesced_deploy_refused` (and `quiesced_refused`) are added to the canonical deploy-status reason table `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` (rows near `quiesced` :66 / `inngest_still_serving` :67) — the runbook has **no** reason table (prose at `inngest-server.md:838-841`), so "runbook reason table" everywhere means: the postmerge table + a one-line pointer from the runbook prose. `scripts/cutover-inngest.sh` quiesce-web `case "$REASON"` (:1905-1918) is swept: `*)` fast-fail carries them (decision unchanged). Learning `best-practices/2026-06-22-union-widening-sweep-must-include-hardcoded-op-list-contract-tests.md`.

**C11 — runbook/ADR/C4 citations.** Runbook §1 is **:862**; §op=quiesce-web (:828) has no 15-minute sentence (that text lives only in the script — drop that sub-step); the `> **SUPERSEDED (#6538, 2026-07-17)…` block at :895-900 is rewritten with §1a; §3b command is :1042; watchdog section heading :329. `model.c4` stale web-2 claims are at **:205, :206 and :210** (all three corrected). The ADR-100 amendment is a **direct append** — `/soleur:architecture` has no amend sub-command (the 2026-07-12 amendment was a direct edit too); the stale clause is ADR-100 :342 `restart (LB-routed to a web host)`.

**C12 — Observability probe.** `credentials_required` removed (Check 10 SKIP-DECLAREs any declared probe — this one needs no credentials); `expected_output` matched to the suite's real output (applied in place).

**C14 — FR16 folded inline at /work (2026-09-14).** Filing was refused by the issue gate: Fix-Size 20 lines / 2 files is inside ADR-131's inline threshold (≤100/≤4). `apps/web-platform/app/api/internal/schedule-reminder/route.ts` now answers **503 + `Retry-After: 120`** when `inngest.send` fails with a refused connection, and every other dispatch failure stays **502**. The refusal check matches `TypeError` whose `cause.code === "ECONNREFUSED"`. That shape was measured at /work against a closed loopback port with the pinned SDK (inngest 3.54.2: `TypeError: fetch failed` → cause `Error{code: ECONNREFUSED, errno: -111}`), and the route test mocks exactly that shape. Rows: `503 + Retry-After … refused` (RED before, GREEN after), `stays 502 … ENOTFOUND`, `stays 502 … message text only`. This supersedes FR16 and task 5.2, and it corrects the User-Brand Impact window bullet: the founder-visible surface is now 503 + Retry-After, not `502 Dispatch failed`. What the bullet says about persistence still holds: nothing is persisted in the window, and `op=rearm` cannot recover a reminder the caller never re-armed.

**C13 — learnings added.** `2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md` (the `--kill-after` SIGKILL fallback is the load-bearing primitive under a webhook-inherited PGID); `2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md` ("what would make this pass WITHOUT the thing under test being true?" — applied to every mock-seam row); plus the three cited in C1/C4/C10.

## Review Round 1 Corrections (2026-09-14)

PR #8173 review round 1 falsified premises this plan relied on, and the CTO ruled on the design
question they raised. The binding contract for the fix round is
[`review-fix-contract.md`](../specs/feat-one-shot-6921-cutover-loop-drivable/review-fix-contract.md).
Where it conflicts with anything above — including the Deepen-Plan Corrections — **the contract
wins**. This section records what changed and why; it does not restate the contract. The decision
record is ADR-100's 2026-09-14 amendment.

**C-R0 — CTO ruling: hybrid.** The systemd shape (`is-active` ∈ {inactive, failed} ∧ `is-enabled`
= disabled) stays the only signal that REFUSES a start. A new on-host marker
`/var/lib/inngest/quiesced-by-op`, written only by the `quiesce inngest` handler, ATTRIBUTES the
shape to a deliberate `op=quiesce-web` and binds the capture to it (`capture_sha256`). Read sites use
a byte-identical tri-state `quiesced | disabled_unattributed | not_quiesced` (contract §1–§3). A lost
marker becomes a page (`DISABLED_UNATTRIBUTED`), never a restart. This reverses the plan's
"no new state" choice (Alternative Approaches, row 2): that row rejected OFF-host markers; an
on-host file written beside the capture by the same flock-held handler, and never consulted to
permit a start, has none of the rejected properties. Rejected in the ruling: timestamps only
(no provenance), marker required at every site (fail-open on a lost marker), provenance inside the
capture file (deleted on re-arm, retired on rollback), and a loud bootstrap enable (image change,
misses a manual disable).

**C-R1 — "only the quiesce handler writes `disabled`" is false.** A failed `systemctl enable` in
`inngest-bootstrap.sh` (`|| true`) and a manual disable also produce the shape. Risk R1's mitigation
and the User-Brand Impact first bullet rested on it. Now: those read `DISABLED_UNATTRIBUTED` — a
recorded watchdog failure (Sentry `error`, `[ci/inngest-disabled-unattributed]`), not a restart,
not a suppression (contract §4, §8).

**C-R2 — capture freshness.** A persisted 2.1 resume must prove the file belongs to the current
quiesce: JSON array, sha256 == `marker.capture_sha256`, no `capture_consumed_at`. Refusals
`stale_capture`, `already re-armed`, `capture_unattributed` replace `nothing to resume from`
(contract §5). Guard 4's assembly widens from "shape" to "tri-state + sha".

**C-R3 — capture at the quiesce boundary NARROWS the loss window; it does not close it.** A reminder
armed between the capture and the stop is lost. The runbook's window procedure now sets
`INNGEST_CUTOVER_QUIESCE=1` in Doppler `soleur/prd` and redeploys web-platform BEFORE
`op=quiesce-web` (Doppler env is baked at container start), and clears it in the 2.4 redeploy before
`op=rearm`. The route answers `503` with `X-Soleur-Unavailable: cutover-quiesce` for the window
(User-Brand Impact window bullet and C14 superseded on this point).

**C-R4 — quiesce entry rules.** D1b captured only on `active` and otherwise proceeded to stop,
which could stop a scheduler with no trustworthy capture. Now four arms (active / already quiesced /
unit absent / anything else → `quiesce_capture_unavailable`, nothing stopped), a marker-write
failure reason, a post-verify tri-state check (`quiesced_shape_unrecognized`), and a scrubbed capture
stderr tail (contract §6). Guard 5's mutation matrix gains the non-active arms.

**C-R5 — rollback retires the capture and removes the marker before `enable`** (contract §6), so no
later quiesce can resume a pre-rollback capture. The web-2 rollback fan-out is not a no-op: `enable`
on its absent unit writes `inngest_enable_failed` to web-2's own slot, tolerated.

**C-R6 — re-arm held back reminders that already fired.** Records with `fire_at` ≤ `marker.epoch`
fired on the web scheduler and are not re-sent; the canonical line gains `held_back=H` with
`N+F+H == K` and the P2-b parser reconciles it (contract §5, §9). Recorded residual, not closed: a
record due between `marker.epoch` and the stop's completion (≤ 180 s) can fire on web-1 and again
after re-arm, because the dedicated host holds no event-id dedup key from web-1.

**C-R7 — two 503s.** `backend-refused` vs `cutover-quiesce` get distinct re-arm messages and remedies
(contract §5).

**C-R8 — 2.2 certification tightened.** PASSED needs EVERY answered non-200 body to carry the
anchored QUIESCED sentinel, not one; a `DISABLED_UNATTRIBUTED` body is UNKNOWN with remedy
`op=rollback` (contract §9). Guard 3 rows follow.

**C-R9 — a quiesced unit read green forever even with no scheduler anywhere.** New `nolive`
workflow step: alarm when the web unit is quiesced beyond `INNGEST_QUIESCE_GRACE_MIN` (60) and the
dedicated verdict is not `healthy` (empty, `probe-unavailable`, `stopped-by-brake` count); files
`[ci/inngest-no-live-scheduler]`, and the Sentry check-in `ok` additionally requires no alarm
(contract §8). This amends Guard 1's "Sentry check-in `ok`" property for the quiesced state.

**C-R10 — ordering and delivery.** The wiped-volume gate moves BEFORE enumeration (contract §3);
the QUIESCED/DISABLED_UNATTRIBUTED lines are evaluated before the `gql_error` marker (contract §4);
`op=quiesce-web` refuses before any stop when the on-host script sha256s differ from the checkout,
and its poller keeps polling on `lock_contention` (contract §9). R2 is now enforced, not procedural.

**C-R11 — documentation defects.** The false-suppression audit fired forever post-cutover (it
looked for a quiesce in the prior 24 h); it is replaced by an ONSET audit isolated by
`SYSLOG_IDENTIFIER` and `host_name`. "Expected once per window" appeared twice (deduplicated). The
2026-07-12 "LB-routed" correction now cites the `deploy.` ingress's web-1 target. The shared
concurrency group `deploy-inngest-restart` (restart, cutover, deploy-inngest-image) can let a
watchdog restart replace a pending cutover op. The consumer-heartbeat read got an executable
command. `## Observability` `failure_modes` now cite a layer per detection and route, and add the
modes above.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Read `INNGEST_CUTOVER_FLIP` in the watchdog and suppress while `armed/flipping/flushed` (#8077 option 1) | The flag is written by `op=arm`, which runs AFTER the quiesce→execute window. During the window the flag is still pre-arm (`aborted` today), so it cannot discriminate a deliberate quiesce from a fault. Cut. |
| `op=quiesce-web` writes a repo variable / Doppler marker honoured for a bounded window (#8077 option 2) | New mutable state, a new write from an op that has no reviewer gate, a second fuse (the marker expires while the maintenance window is still open), and a clear-on-rollback path that must be kept in sync. The systemd shape is already written by quiesce and cleared by enable, persists across boots, and needs no new state. Cut. |
| Read `/hooks/deploy-status` `reason=quiesced` in the watchdog | Single slot, overwritten by the next deploy or restart; a merge to main during the window would erase the signal and re-open the fuse. Cut. |
| Make `failure_mode=inngest_quiesced` a first-class failure mode | It would skip the pool probe (which runs only when the liveness verdict is empty) for the whole window and, post-cutover, forever — darkening the pool alert permanently; it would also need explicit arms in five consumers (issue class, age gate, dispatch, auto-close, check-in). Recording no failure + a separate `web_scheduler` output keeps the pool probe alive and touches one consumer. |
| CI-side 2.1 skip (probe first, skip capture, verify the file via a new `mode=status`) | Puts the decision where the data is not; needs a new hook mode and a reordered CI arm. The on-host script owns the file and the unit state. |
| Re-pin `CUTOVER_HOSTS` to `10.0.1.10` | Premise false (Reconciliation row 1); would redden the H1 parity test. Cut. |
| Fan out to peers BEFORE the local stop/enable | Peer acceptance is measured 202 and re-dispatch converges; reordering would make a peer-unreachable case leave web-1 UN-quiesced with a red verdict — the more dangerous inversion for a gate whose purpose is stopping the local scheduler. Cut; recorded as R4. |
| Defer capture-at-quiesce and keep the permanent 2.1 warning about the [capture, quiesce] window | Initially the plan's choice. Reversed after the scoped advisor consult (ADR-083) and the CPO advisory: the write path IS verifiable read-only (`cloud-init.yml:250` `User=deploy`, `:267` `ReadWritePaths … -/var/lib/inngest`, `inngest-bootstrap.sh:142-143` `chown deploy:deploy /var/lib/inngest`), the enumerate needs no secret (loopback GQL, `start` mode), and deferring it would have forced D1's resume semantics to be rewritten later. Folded in as D1b. |
| Gate the healthy auto-close (whole step, or only the three liveness-derived closes) on a new `web_scheduler=quiesced` step output | Whole-step: pool/pool-probe issues never auto-close post-cutover (CTO). Narrowed: the liveness-derived issues never auto-close post-cutover, and a second separately-read output beside the workflow's single-source `failure_mode` re-emit contract is fail-open for any future consumer that reads it from the wrong step (architecture-strategist). Both panels fired on the same scope → deleted (DHH): a deliberate stop+disable resolves a "web scheduler down" issue; the existing healthy auto-close is correct on a quiesced tick. |
| Treat `deactivating`+`disabled` as QUIESCED too (closes the ≤180 s stop window a watchdog tick can land in) | Two predicates (a lenient watchdog one and the strict gate one) for a window that disable-before-stop already shrinks and whose worst case is one false `inngest_down` tick (restart refused by D3, issue auto-closed on the next tick, one Sentry `error` check-in) — R8. Cut. |

## User-Brand Impact

- **If this lands broken, the user experiences:**
  - the watchdog suppression matching a REAL crash (a unit that is `inactive` because it died AND happens to be `disabled`) → no auto-restart → every user's crons and reminders stop firing until `op=rollback` is dispatched. Mitigation: the shape requires `disabled`, which only the deliberate `quiesce` handler writes; a crashed enabled unit is `failed`/`activating`, never `disabled`. Guard 1 row 1 pins this.
  - the capture resuming from a stale file on a host that is merely /health-down → reminders armed after that capture never re-arm on the dedicated host → a user's reminder silently never fires. Mitigation: resume only in the quiesced shape (Guard 4 row 1); the 2.1 warning names the `captured_at`.
  - the 2.2 gate reading UNKNOWN on a genuinely quiesced host because the inventory script was not yet delivered → the window cannot open until the push lands (a delay, not a data loss; the remedy names the push).
- **What a founder can see during the maintenance window (CPO C2):** while the web scheduler is stopped and until 2.4 (the `INNGEST_BASE_URL` repoint merges and redeploys — the step `op=rearm`'s `registry_empty == false` precondition waits on), `POST /api/internal/schedule-reminder` returns a generic `502 Dispatch failed` after `sendInngestWithRetry` exhausts its retries (NOT the designed `503 + Retry-After` — `INNGEST_CUTOVER_QUIESCE` is a different, unset flag), and no cron fires anywhere. Reminders a founder tries to arm in that window were never persisted, so `op=rearm` cannot recover them — the caller must re-arm after the window. The runbook therefore (a) requires the 2.4 PR to be pre-staged green before `op=quiesce-web` opens the window and (b) tells the operator to announce the window. Mapping the connection-refused path to `503 + Retry-After` is a separate follow-up (FR16 files it).
- **A reminder whose `fire_at` falls inside the window (CPO C1):** the re-arm re-sends the event with `ts = Date.parse(fire_at)` in the past; the intended semantic is FIRES LATE (on re-arm), never DROPPED. This is asserted, not assumed, by AC FR13 (verify the Inngest past-`ts` behaviour against the vendor reference before writing the runbook line). If the vendor semantic turns out to be DROPPED, FR13 files an issue for a clamp on the steady-state re-arm path — it does NOT bundle a behaviour change to routine re-arms into this fix (DHH). **Deepen resolution (2026-09-14): FIRES LATE, never dropped** — Inngest pinned `v1.19.4` (`apps/web-platform/infra/inngest.tf:29`), `pkg/execution/executor/executor.go` schedule: `at := e.now(); … evtTs := time.UnixMilli(req.Events[0].GetEvent().Timestamp); if evtTs.After(at) { at = evtTs }` — a past `ts` yields `at = now` (runs immediately); the only `ts` rejection (`pkg/event/event.go` `Validate`) is before 1980 / after 2100. The docs (<https://www.inngest.com/docs/reference/events/send>, retrieved 2026-09-14) state only the future case, so the runbook line cites the source file at the pinned tag. Dedup is on event `id` per function for 24 h (`runner.go` `idempotencyKey := tracked.GetEvent().ID`; <https://www.inngest.com/docs/guides/handling-idempotency>) — `ts` is NOT part of the key, and the dedicated host's fresh backend holds no keys from the web-host SQLite, so the re-arm is not deduped against old runs; a second `op=rearm` within 24 h against the same backend IS deduped (safe). The rearm script's header comment (`:12-14`, "dedup keys `id` + `ts`") is corrected in the same edit.
- **If this leaks, the user's data is exposed via:** nothing new — the capture response still surfaces reminder ids only (P2-sec-a); the QUIESCED body carries host_id + two enum words; no secret or comment body moves.
- **Brand-survival threshold:** `single-user incident` — a single lost reminder is a broken promise to one founder.

## Observability

```yaml
liveness_signal:
  what: "scheduled-inngest-health.yml Sentry cron monitor `scheduled-inngest-health` (unchanged) + the per-cycle `web scheduler QUIESCED` ::notice:: in its run log; the dedicated-host arm (#7674) keeps grading the real scheduler"
  cadence: "*/15 min"
  alert_target: "Sentry monitor-failure page on `error` check-in; the quiesced state is deliberately `ok` (run-log notice only) unless the review-round-1 no-live-scheduler alarm fires; DISABLED_UNATTRIBUTED is `error`"
  configured_in: ".github/workflows/scheduled-inngest-health.yml (probe step case arm + auto-close if:), apps/web-platform/infra/sentry/cron-monitors.tf"

error_reporting:
  destination: "Better Stack Logs source 2457081 via Vector Source 4 (journald tags inngest-inventory, inngest-rearm-reminders, ci-deploy — all pre-allowlisted); Sentry beacon path in inngest-rearm-reminders.sh unchanged"
  fail_loud: "cutover-inngest.sh ::error:: lines (2.1 `stale_capture` / `already re-armed` / `capture_unattributed` — review round 1 replaced `nothing to resume from`; 2.2 `UNKNOWN` with the verdict-specific remedy); ci-deploy deploy-status reasons `quiesce_capture_failed`, `inngest_quiesced_restart_refused`, `inngest_quiesced_deploy_refused`; journald (tag ci-deploy) `INNGEST_QUIESCE_CAPTURE_FAILED rc= stderr_tail=`, `INNGEST_RESTART_REFUSED`; (tag inngest-inventory) `SOLEUR_INNGEST_LIVENESS_VERDICT mode=quiesced`; (tag inngest-rearm-reminders) `resumed persisted capture`"

failure_modes:
  # Review round 1 (2026-09-14): every detection and alert_route names its layer — `vector` Source 4
  # (journald tag → Better Stack source 2457081), `workflow run log` (`::error::`/`::notice::`),
  # `sentry check-in` (monitor `scheduled-inngest-health`), `github issue` — or says "none".
  - mode: "watchdog reads QUIESCED from a marker that no op=quiesce-web wrote (false suppression)"
    detection: "vector Source 4 — tag inngest-inventory `SOLEUR_INNGEST_LIVENESS_VERDICT mode=quiesced` and tag ci-deploy `SUCCESS: quiesce inngest` (host_name soleur-web-platform); the runbook onset audit (§Web scheduler QUIESCED) requires the first mode=quiesced row after the last non-quiesced verdict to follow a SUCCESS row"
    alert_route: "none automatic — runbook onset audit (operator-run betterstack-query.sh). A crashed or bootstrap-disabled unit has no marker and routes to DISABLED_UNATTRIBUTED below instead"
  - mode: "stopped+disabled unit with no valid quiesce marker (DISABLED_UNATTRIBUTED: failed bootstrap enable, manual disable, lost/voided marker)"
    detection: "vector Source 4 — tag inngest-inventory `SOLEUR_INNGEST_LIVENESS_VERDICT mode=disabled_unattributed`; workflow run log — classifier `inngest_disabled_unattributed` in scheduled-inngest-health.yml"
    alert_route: "sentry check-in `error`; github issue `[ci/inngest-disabled-unattributed]` (remedy op=rollback). No restart dispatch"
  - mode: "no live scheduler: web unit quiesced longer than INNGEST_QUIESCE_GRACE_MIN (60) while the dedicated-host verdict is not healthy (incl. probe-unavailable / stopped-by-brake)"
    detection: "workflow run log — `::error::` from the `nolive` step (alarm=true)"
    alert_route: "sentry check-in `error`; github issue `[ci/inngest-no-live-scheduler]` (label action-required), auto-closed when alarm=false"
  - mode: "2.1 would resume a capture that does not belong to the current quiesce (stale, consumed, or unattributed)"
    detection: "workflow run log — op=execute `::error::` carrying `stale_capture` / `already re-armed` / `capture_unattributed`; vector Source 4 — tag inngest-rearm-reminders `FATAL: rearm-from-capture: stale_capture` / `already re-armed` on the op=rearm path"
    alert_route: "workflow run log (op=execute / op=rearm red, SEAM withheld)"
  - mode: "2.2 UNKNOWN (inngest-inventory.sh not delivered, a non-200 body without the QUIESCED sentinel, or a DISABLED_UNATTRIBUTED body)"
    detection: "workflow run log — 2.2 `::error::` with the verdict-specific remedy and a 120-char body excerpt"
    alert_route: "workflow run log (op=execute red, SEAM withheld)"
  - mode: "quiesce_capture_failed — capture failed or timed out on an active unit; nothing stopped"
    detection: "vector Source 4 — tag ci-deploy `INNGEST_QUIESCE_CAPTURE_FAILED rc= stderr_tail=` (scrubbed); workflow run log — op=quiesce-web poller `::error::` arm"
    alert_route: "workflow run log (op=quiesce-web red)"
  - mode: "quiesce_capture_unavailable — unit neither active, quiesced, nor absent; nothing stopped"
    detection: "vector Source 4 — tag ci-deploy `INNGEST_QUIESCE_CAPTURE_UNAVAILABLE unit= enabled= state=`; workflow run log — op=quiesce-web poller `::error::` arm"
    alert_route: "workflow run log (op=quiesce-web red)"
  - mode: "quiesce_marker_write_failed / quiesced_shape_unrecognized"
    detection: "workflow run log — op=quiesce-web poller `::error::` arm reading the deploy-status reason"
    alert_route: "workflow run log (op=quiesce-web red)"
  - mode: "quiesce-web dispatched before the config push landed (on-host script sha != checkout)"
    detection: "workflow run log — preflight `::error::` \"config push not landed\" before any dispatch"
    alert_route: "workflow run log (op=quiesce-web red, nothing stopped)"
  - mode: "restart or bootstrap deploy refused on a stopped+disabled unit"
    detection: "vector Source 4 — tag ci-deploy `INNGEST_RESTART_REFUSED` / `INNGEST_DEPLOY_REFUSED` with state=; workflow run log — restart-inngest-server.yml / deploy-inngest-image.yml red on the refused reason"
    alert_route: "workflow run log of the dispatching run (remedy names op=rollback); for a watchdog-dispatched restart, the watchdog's own sentry check-in and github issue"
  - mode: "re-arm aborted on a 503 (backend-refused before the 2.4 redeploy, or INNGEST_CUTOVER_QUIESCE still live)"
    detection: "workflow run log — op=rearm `::error::` naming the X-Soleur-Unavailable class; capture retained"
    alert_route: "workflow run log (op=rearm red)"

logs:
  where: "journald on web-1 (tags inngest-inventory / inngest-rearm-reminders / ci-deploy) → Vector → Better Stack source 2457081; GitHub Actions run logs for cutover-inngest.yml and scheduled-inngest-health.yml"
  retention: "Better Stack per-source retention (source 2457081); GitHub run logs 90 days"

discoverability_test:
  command: "bash scripts/inngest-liveness-classify.test.sh"
  expected_output: "inngest_quiesced (no restart)"
  # Deepen 2026-09-14: `credentials_required` REMOVED — preflight Check 10 row 4 SKIP-DECLAREs (never
  # executes) any probe carrying a non-placeholder declaration, and this probe needs no credentials.
  # The suite prints `=== Results: N passed, M failed ===` and exits non-zero on any FAIL
  # (`[[ "$FAIL" -eq 0 ]]`), so rc==0 + the new row's PASS-line substring is the proof. The live
  # read (`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h
  # --grep 'SOLEUR_INNGEST_LIVENESS_VERDICT'`) stays a /soleur:qa step, not the Check 10 probe.
```

## Guard Contract

### Guard 1 — watchdog never remediates the quiesced shape

**Property.** A liveness body carrying `^inngest-inventory: QUIESCED` (emitted only when the web unit is `inactive` AND `disabled`) never causes a `restart-inngest-server.yml` dispatch, a `[ci/inngest-down]` filing, or a Sentry `error` check-in, while every other non-200 body keeps today's classification.

**Assembly.** Emitter: the functions-query non-array branch of `apps/web-platform/infra/inngest-inventory.sh` (one branch, two callers — liveness-only and full inventory — both must reach the QUIESCED emit before the FATAL emit). Chokepoint: `classify_liveness_mode` in `scripts/inngest-liveness-classify.sh` (the only function that maps a body to a mode) and `is_restart_family`. Consumers of the mode in `.github/workflows/scheduled-inngest-health.yml`: the probe step `case "$MODE"` (the only writer of `failure_mode`), the agegate `if:`, the dispatch `if:`, the file-issue `if:`/`case "$FAIL_MODE"`, the healthy auto-close `if:`, the durability steps' `failure_mode == ''`, and the check-in `status:` expression — enumerated by `grep -nE "failure_mode" .github/workflows/scheduled-inngest-health.yml`; the quiesced arm writes NO new output, so the consumer set is unchanged.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | In `inngest-inventory.sh` drop the `enabled == disabled` conjunct (emit QUIESCED on `inactive` alone) | RED — `inngest-inventory.test.sh` row "health=500 inactive but ENABLED → FATAL" fails |
| 2 | Order: in the emitter, move the QUIESCED emit below the FATAL branch's `exit 1` | RED — the liveness-only quiesced row expects QUIESCED, gets FATAL |
| 3 | Delete the `inngest_quiesced)` arm from the workflow probe `case` (mode falls to `*) → probe_unavailable`) | RED — classifier-mode-set drift row (v) fails (a commented-out arm also fails: the rows grep over `grep -v '^[[:space:]]*#'`) |
| 4 | Own dispatch: make the classifier-mode-set drift row derive zero modes (break its `grep -oE 'echo "[a-z_]+"'`) | RED — the row asserts the derived set has ≥ 6 members (excluding `healthy`) before iterating |
| 5 | Second member: add `|| … == 'inngest_quiesced'` to the dispatch `if:` after the compliant probe arm | RED — the NEW negative row (`! grep -qE "^ *if: .*failure_mode == '[^']*quiesced"` on the dispatch line AND exactly one `||` on it) is the sole producer; the existing `inngest-dedicated-host-classify.test.sh:99-109` row only checks the line exists |
| 6 | Declare `web_quiesced` inside the `if [[ -z "$fail_mode" ]]` block instead of beside `fail_mode=""` | RED — a declaration row (comment-stripped awk over the probe step: the line carrying `fail_mode=""` also carries `web_quiesced="no"`, and no `web_quiesced=` assignment precedes it) fails. Deepen C10: `inngest-dedicated-host-classify.test.sh` only extracts/executes the dedicated-host arm (:203), never the probe step, so the row is structural, not an execution of the `secret_unset` path |
| 7 | Harness: change the classifier test's expected token for the QUIESCED body to `inngest_down` | RED — the suite must fail (non-vacuity of the test) |
| 8 | Must-PASS non-canonical: a QUIESCED body with trailing diagnostic text and a different host_id | GREEN — still `inngest_quiesced` |
| 9 | Must-PASS non-canonical (deepen C1): emitter with `INVENTORY_UNIT_ACTIVE=failed INVENTORY_UNIT_ENABLED=disabled` and health 000 | GREEN — QUIESCED body with `unit=failed` (a stop that ended SIGKILL/non-zero is still a deliberate quiesce) |
| 10 | Drop the full-mode health read (compute `health_code` only inside the `LIVENESS_ONLY` block, as today) | RED — the full-inventory quiesced row expects QUIESCED, gets FATAL (2.2 calls the FULL-mode `/hooks/inngest-inventory`, `cutover-inngest.sh:1500`) |

### Guard 2 — `restart` refuses the quiesced shape

**Property.** No start path on the web host other than the deliberate `enable` handler starts `inngest-server.service` while the unit is `inactive` AND `disabled`: `restart` writes `inngest_quiesced_restart_refused`, the bootstrap deploy arm writes `inngest_quiesced_deploy_refused`, the wiped-volume verify aborts `quiesced_refused`, the luks-cutover reconcile skips its start — and every one proceeds unchanged for every other state.

**Assembly.** Every code path on a web host that can start `inngest-server.service`, enumerated by `git grep -nE 'systemctl (restart|start) inngest-server|inngest-bootstrap.sh' apps/web-platform/infra/ scripts/`: the `restart` action handler in `apps/web-platform/infra/ci-deploy.sh` (after the flock and `write_state running`), the `deploy inngest` arm (`case "$COMPONENT" in inngest)` :3362 → `inngest-bootstrap.sh:1662` enable + `:1679` restart under `deploy-inngest-bootstrap.sudoers`), `inngest-wiped-volume-verify.sh:236-240`, `workspaces-cutover.sh:633-636`, and the deliberate `enable` handler (op=rollback, the ONLY one allowed to re-arm). The chokepoint inside `ci-deploy.sh` is the single `inngest_unit_quiesced()` helper; the two external scripts carry the identical two-string predicate, pinned by a cross-file parity row (`grep -c "== inactive" … "== disabled"` in all three delivered scripts — CTO devex). Sudoers aliases `INNGEST_RESTART`, `INNGEST_START`, `INNGEST_ENABLE`, `INNGEST_BOOTSTRAP` in `cloud-init.yml`. Exercised by the mock `systemctl` (with verb log) and a mock `docker` in `ci-deploy.test.sh`, plus `inngest-wiped-volume-verify.test.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the guard | RED — "restart refuses a quiesced unit" expects reason `inngest_quiesced_restart_refused` |
| 2 | Guard on `is-enabled == disabled` only | RED — "restart proceeds on an ACTIVE disabled unit → success" fails |
| 3 | Guard on `is-active == inactive` only | RED — "restart proceeds on an inactive-but-ENABLED unit → success" fails |
| 4 | Order: place the guard AFTER the restart call | RED — the mock verb log asserts no `restart` entry when refused |
| 5 | Own dispatch: the refused row's verb-log assertion when the log file is absent | RED — the row asserts the log file exists (the mock wrote at least the `is-active` query) before asserting `restart` is absent |
| 6 | Second member: the `deploy inngest` arm reaches `docker create`/bootstrap with the quiesced shape | RED — FR14 row expects `inngest_quiesced_deploy_refused` and no `docker create` in the mock log |
| 6b | Third member: `inngest-wiped-volume-verify.sh` reaches its `stop` with the quiesced shape | RED — its test row expects `quiesced_refused` before any `systemctl` verb in its mock log |
| 6c | A future start writer added without the guard | RED — the assembly grep (`git grep -nE 'systemctl (restart|start) inngest-server' apps/web-platform/infra/`) returns a hit whose enclosing 15 lines carry neither `inngest_unit_quiesced` nor the predicate AND whose `file:enclosing-function` is not in the NAMED allowlist carried by the row itself (deepen C6): `ci-deploy.sh` enable handler (the deliberate re-arm), `inngest-bootstrap.sh` restart (reached only through the gated `deploy inngest` arm or first boot), `cloud-init.yml` first-boot `runcmd` (unit born enabled; no quiesced shape can pre-exist), `cloud-init-inngest.yml` (dedicated host, out of scope). Without the allowlist the row is RED on day one |
| 6d | Fifth member: the `workspaces-cutover.sh` dead-man `sh -c` string starts the unit with the quiesced shape | RED — grep row in `tests/scripts/test-workspaces-luks-cutover-gate.sh`: the dead-man string's `systemctl start inngest-server.service` is preceded in the same string by the `is-enabled … = disabled ] ||` guard |
| 7 | Harness: flip the expected reason on row 1 to `success` | RED |
| 8 | Must-PASS non-canonical: `is-enabled` prints `enabled-runtime`, unit inactive | GREEN — restart proceeds (`success`) |
| 9 | Must-PASS non-canonical (deepen C1): unit `failed` + `disabled` | GREEN-as-refusal — `inngest_quiesced_restart_refused` (the post-SIGKILL quiesce shape) |
| 10 | Must-PASS non-canonical: `is-enabled` prints `not-found` rc 4 (unit absent) | GREEN — not the quiesced shape; restart proceeds to its own verb (and fails on the absent unit as today) |

### Guard 3 — 2.2 certifies the quiesced shape, not a proxy

**Property.** 2.2 prints `QUIESCE HARD GATE PASSED` only when every probe returned non-200 AND at least one non-200 body carried `^inngest-inventory: QUIESCED`; any 200 is STILL RUNNING; every-probe-non-200 without the sentinel is UNKNOWN (fail-closed, SEAM withheld).

**Assembly.** The single 2.2 probe loop in the `execute)` arm of `scripts/cutover-inngest.sh` (flags `serving`, `reached_non200`, new `quiesced_seen`) and the verdict block that follows; `op=quiesce-web`'s secondary inventory read reports the same sentinel. Exercised by the `render_2_2` region harness in `cutover-inngest-workflow.test.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the sentinel requirement (pass on `reached_non200` alone) | RED — 3× FATAL row expects UNKNOWN |
| 2 | Let a sentinel seen on probe 1 pass despite a 200 on probe 2 | RED — `QUIESCED,200,QUIESCED` row expects STILL RUNNING |
| 3 | Unanchored `grep QUIESCED` | RED — body `FATAL … not QUIESCED` row expects UNKNOWN |
| 4 | Own dispatch: `render_2_2` extracts an empty region (awk anchors drift) | RED — the harness asserts the region is ≥ 35 non-comment lines before running any row |
| 5 | Second member: a 200 on the LAST probe after two QUIESCED bodies | RED — `QUIESCED,QUIESCED,200` row expects STILL RUNNING (the loop must not stop reading at the first sentinel) |
| 5b | The UNKNOWN remedy ignores `SOURCE` | RED — the `SOURCE=persisted` FATAL row expects "predates the QUIESCED verdict" and NOT `op=quiesce-web` |
| 6 | Harness: swap the expected verdict on row 1 | RED |
| 7 | Must-PASS non-canonical: QUIESCED body with a different host_id and a `500` vs `503` code mix | GREEN — quiesced |

### Guard 4 — capture resumes only in the quiesced shape

**Property.** `mode=capture` returns the persisted file (`source:"persisted"`) only when the unit is `inactive` AND `disabled` AND the file is a JSON array; it enumerates live (`source:"live"`) whenever the unit is not in that shape; it fails (exit 1) when quiesced without a valid file or when a non-quiesced enumeration fails — never a silent stale-file fallback.

**Assembly.** The `capture` branch of `apps/web-platform/infra/inngest-rearm-reminders.sh` (one branch; the predicate, the file validation `jq -e 'type == "array"'`, and the two status objects), exercised by `inngest-rearm-reminders.test.sh` with a mock `systemctl` and the `enum_stub`; the CI reader of `.source` in the 2.1 block of `scripts/cutover-inngest.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Resume whenever enumeration fails (drop the shape predicate) | RED — "health down but ENABLED → enumeration failed" row |
| 2 | Resume without validating the file is a JSON array | RED — corrupt-file row expects exit 1 |
| 3 | Order: enumerate first, fall back to the file on failure while quiesced | RED — the quiesced-resume row asserts the enum stub's marker file is absent |
| 4 | Own dispatch: the mock `systemctl` not on PATH (predicate reads the real host) | RED — the quiesced-resume row asserts the mock's verb log exists |
| 5 | Second member: a second persisted-shape branch that returns the file when the unit is `inactive` but `is-enabled` prints `not-found` rc 4 (unit absent, systemd ≥ 253 — the mock must emit this shape, deepen C8) | RED — an `INVENTORY`-style row with `is-enabled` printing nothing expects live enumeration (which fails on the absent unit) — never the file |
| 6 | Harness: flip the expected `source` on the resume row | RED |
| 7 | Must-PASS non-canonical: a persisted file with 0 records (`[]`) while quiesced | GREEN — `captured:0 source:persisted` (an empty capture is a valid capture — run 34865196148 wrote exactly this) |
| 8 | Must-PASS non-canonical (deepen C1): unit `failed` + `disabled` + valid file | GREEN — `source:persisted` |

### Guard 5 — quiesce captures before it stops, or does not stop

**Property.** The `quiesce inngest` handler never issues the disable/stop verbs on an ACTIVE unit (`systemctl is-active` = `active`) unless a bounded capture of its still-armed reminders has just been persisted; a capture failure or timeout leaves the scheduler running, logs `INNGEST_QUIESCE_CAPTURE_FAILED` and reports `quiesce_capture_failed`; a non-active unit is disabled/stopped without a capture attempt.

**Assembly.** The `quiesce` action handler in `apps/web-platform/infra/ci-deploy.sh` (one handler; the `is-active` gate, the `timeout`-bounded capture invocation via `INNGEST_REARM_CMD` with stderr captured, the `INNGEST_QUIESCE_CAPTURE_FAILED` logger + `quiesce_capture_failed` write, then the disable/stop/verify sequence) and the `capture` branch of `inngest-rearm-reminders.sh` now ahead of the relocated secret read; exercised by `ci-deploy.test.sh` with the stateful mock `systemctl` + verb log and `inngest-rearm-reminders.test.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Order: move the capture call AFTER the disable/stop verbs | RED — verb-log order row expects `capture` before `disable` and `stop` |
| 2 | Tolerate a capture failure (`|| true`) and proceed to stop | RED — `quiesce_capture_failed … stops NOTHING` row finds `stop` in the log |
| 3 | Drop the `is-active == active` gate and always capture | RED — the inactive row expects no `capture` (a stopped scheduler cannot be enumerated; the handler must not fail a re-dispatch) |
| 4 | Own dispatch: the mock rearm script is not on the PATH the handler uses | RED — the active row asserts `capture` appears in the log (the mock is what writes it) |
| 5 | Second member: capture mode left below the secret read (so the handler's secret-less call fails) | RED — `test_capture_needs_no_secret` |
| 5b | Remove the `timeout` around the capture | RED — the bounded row's mock sleeps past the shrunk bound and expects `quiesce_capture_failed` |
| 5c | Swallow the capture's stderr (no `INNGEST_QUIESCE_CAPTURE_FAILED` logger line) | RED — the failing row asserts the marker in the mock logger log |
| 6 | Harness: flip the expected order in row 1 | RED |
| 7 | Must-PASS non-canonical: capture returns `captured:0` (nothing armed) | GREEN — quiesce proceeds to stop (an empty capture is a capture) |

## Acceptance Criteria

### Functional Requirements

- FR1 (`inngest-rearm-reminders.sh` capture branch): quiesced shape + valid file → exit 0, status object has `source:"persisted"`, `captured_at`, `captured`, `reminder_ids`, `capture_file`; file unchanged. `bash apps/web-platform/infra/inngest-rearm-reminders.test.sh` prints PASS for all new rows (five resume rows, two secret-order rows, one Σ=0 row).
- FR2 (same file): quiesced + no/invalid file → exit 1, stderr contains `nothing to resume from` and `op=rollback`.
- FR3 (same file): non-quiesced → live enumeration, response shape unchanged (no `source` field); enumeration failure still exits 1.
- FR4 (`scripts/inngest-liveness-classify.sh`): `classify_liveness_mode 500 "inngest-inventory: QUIESCED host_id=x …"` prints `inngest_quiesced`; `is_restart_family inngest_quiesced` returns 1. `bash scripts/inngest-liveness-classify.test.sh` all PASS.
- FR5 (`inngest-inventory.sh` non-array branch): quiesced shape + `/health` != 200 → stdout begins `inngest-inventory: QUIESCED host_id=`, exit 1, in BOTH `INVENTORY_LIVENESS_ONLY=1` and full mode; inactive+enabled → FATAL unchanged; `/health`=200 → DEGRADED unchanged. `bash apps/web-platform/infra/inngest-inventory.test.sh` all PASS.
- FR6 (`scheduled-inngest-health.yml` probe step): `grep -v '^[[:space:]]*#' .github/workflows/scheduled-inngest-health.yml | grep -c "inngest_quiesced)"` = 1; `grep -c "web_scheduler" .github/workflows/scheduled-inngest-health.yml` = 0 (no side-channel output); the dispatch `if:` line (the `Auto-dispatch inngest restart` step) does NOT contain `quiesced` and carries exactly one `||`; the healthy auto-close step's `if:` is byte-identical to today's; `web_quiesced="no"` is declared on the `fail_mode=""` line; `bash apps/web-platform/infra/inngest-dedicated-host-classify.test.sh` all PASS including the new drift rows (ii)/(v) and the `secret_unset`-path row.
- FR7 (`ci-deploy.sh` restart handler): quiesced shape → `final_write_state 1 "inngest_quiesced_restart_refused"` and no `restart` verb in the mock's log; inactive+enabled and active+disabled → `success`; both call sites use `inngest_unit_quiesced` (`grep -c 'inngest_unit_quiesced' apps/web-platform/infra/ci-deploy.sh` ≥ 3 — definition + two calls). `bash apps/web-platform/infra/ci-deploy.test.sh` all PASS (the four existing restart rows armed with `MOCK_SYSTEMCTL_ENABLED_STATE=enabled`).
- FR8 (`scripts/cutover-inngest.sh` 2.2): `render_2_2` rows per Guard 3 all PASS in `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`; the UNKNOWN remedy is branched on `SOURCE` (`live` → names `op=quiesce-web`; `persisted` → names the config push and NOT `op=quiesce-web`) and prints the first 120 chars of the last body.
- FR9 (`scripts/cutover-inngest.sh` 2.1): the notice line matches `2.1 capture: Σcaptured=[0-9]+ source=(live|persisted)` and, when `persisted`, carries `captured_at=<ISO>`; there is no second 2.1 notice and no `::warning::2.1:` line; `SOURCE` is read via `.source // "live"` and reused by 2.2 (grep rows in `cutover-inngest-workflow.test.sh`).
- FR10 (text): `grep -c 'KNOWN GAP (#6921)' scripts/cutover-inngest.sh` → 0 (whole file, comments included — today only `:1530`); same for `web-2 freeze/recreate` (deepen-verified hits: `:874`, `:1440`, `:1476`, `:1491`, `:1535`, `:1544`, `:1943`, `:2131` — `:1537` is the SEAM anchor and does NOT carry the token) and `self-arms oneshots` (`:1438`, `:1472`, `:1544`); AND `grep -nE 'auto-restart the web scheduler|currently fails at 2\.1' scripts/cutover-inngest.sh` → 0 (the quiesce-web `::warning::` at `:1848` names `(#6921)`/`#8077` WITHOUT "KNOWN GAP", so the first grep alone misses it); the runbook §3b command line carries no `--yes` (a one-sentence note explaining the removal may name the flag once).
- FR11 (ADR): `grep -c 'Ref #6921' knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` ≥ 1.
- FR12 (D1b, `ci-deploy.sh` quiesce handler + rearm script): `quiesce inngest _ _` with `MOCK_SYSTEMCTL_ACTIVE=1` runs the capture BEFORE the disable/stop verbs (stateful mock verb-log order `capture,disable,stop`; reason `quiesced`); a failing or timed-out capture → reason `quiesce_capture_failed`, exit 1, no `disable`/`stop` logged, `INNGEST_QUIESCE_CAPTURE_FAILED` in the mock logger log; unit not active → no `capture`, reason `quiesced`. Capture mode runs with no Bearer secret and no `doppler` on PATH (rc 0); `rearm-from-capture` without a secret still exits 1. `scripts/cutover-inngest.sh` `quiesce-web)` gains NO new case arm (the `*)` fast-fail carries the reason). The `QMAX_POLLS×QPOLL_INTERVAL` drift-guard row includes the 120 s capture bound.
- FR15 (D1c): `rearm-from-capture` on a `[]` capture emits `inngest-rearm-reminders: re-armed=0 failed=0 total=0` before deleting the file; the `rearm)` arm's P2-b parser reconciles Σ=0 (`cutover-inngest-workflow.test.sh` row).
- FR16 (follow-ups filed, not shipped): a GitHub issue exists for mapping `schedule-reminder`'s connection-refused path to `503 + Retry-After` (today `route.ts:142` returns `{ error: "Dispatch failed" }` 502 after `sendInngestWithRetry` exhausts its `ECONNREFUSED` retries); its number appears in the runbook's window section. The conditional re-arm-clamp issue is NOT filed — FR13 resolved to FIRES LATE at deepen time (labels verified to exist: `type/bug`, `priority/p2-medium`, `domain/engineering`).
- FR13 (CPO C1 — late-not-dropped): the runbook §op=rearm states the delivery semantic for a reminder whose `fire_at` fell inside the window — **FIRES LATE on re-arm, never dropped** — citing option (a): `inngest/inngest@v1.19.4` `pkg/execution/executor/executor.go` (`if evtTs.After(at) { at = evtTs }`) + `pkg/event/event.go` `Validate` (1980–2100 bound only), retrieved 2026-09-14 (resolved at deepen; see User-Brand Impact). No dev-project probe is needed and no re-arm behaviour change ships.
- FR14 (D3 other writers): `deploy inngest _ <tag>` with the quiesced shape → reason `inngest_quiesced_deploy_refused`, exit 1, no `docker create` in the mock log; `inngest-wiped-volume-verify.sh` with the shape → `quiesced_refused` before any `systemctl` verb (its test); `workspaces-cutover.sh:633-636` start is preceded by the `disabled` check (grep row in `tests/scripts/test-workspaces-luks-cutover-gate.sh`); the two pollers carry the `inngest_quiesced_*_refused` case arm (one grep row each).

### Non-Functional Requirements

- NFR1: No new sudoers alias, secret, Doppler write, repo variable, hook, or vector.toml tag. `git diff --stat` touches no `*.tf`, no `hooks.json.tmpl`, no `vector.toml`.
- NFR2: `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` reports no NEW findings for the three host scripts (baseline unchanged or reduced).
- NFR3: `actionlint .github/workflows/scheduled-inngest-health.yml` clean.
- NFR4: `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-14-fix-inngest-cutover-loop-drivable-plan.md` passes.

### Quality Gates

- QG1: The first row of each guard (Guards 1–5) and of FR12/FR14/FR15 was observed RED before the implementation and GREEN after (a one-line "red before, green after" note per row in the PR body — no transcription of assertion text).
- QG2: The Guard 1–5 harness must-FAIL rows were executed once and reverted ("suite red under the flip" noted once per guard).
- QG3: Post-merge (self-pulled, never asked of the operator): (a) the `apply-deploy-pipeline-fix.yml` run for the merge shows the three scripts delivered (`files_written` frame + `inngest-inventory.sh` sha256 equal to `sha256sum apps/web-platform/infra/inngest-inventory.sh` on main); (b) the next `scheduled-inngest-health.yml` run log carries no `web scheduler QUIESCED` notice and no liveness-derived `failure_mode` (the web scheduler is NOT quiesced yet) — stated as a read of THIS change's outputs, not as "the run is green" (pool/dedicated state is ambient); (c) no `cutover-inngest.yml` op is dispatched by this work item.
- QG4: `op=quiesce-web` is NOT dispatched in this work item (standing constraint); the loop's live verification is the operator-pinged maintenance window.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- `inngest-rearm-reminders.test.sh`: 5 resume rows + 2 secret-order rows + 1 Σ=0 row (Phase 1) — the resume row's `"source":"persisted"` assertion fails against today's script (it exits 1 with `enumeration failed`); `test_capture_needs_no_secret` fails today with `INNGEST_MANUAL_TRIGGER_SECRET unavailable`; the Σ=0 row fails today (`nothing to re-arm`, no `re-armed=` line).
- `inngest-liveness-classify.test.sh`: 4 rows (Phase 2a) — QUIESCED body classifies `inngest_down` today.
- `inngest-inventory.test.sh`: 4 rows (Phase 2b).
- `inngest-dedicated-host-classify.test.sh`: 3 drift rows (Phase 2c: dispatch-line negative + `||`-count, classifier-mode-set union, `secret_unset`-path declaration).
- `ci-deploy.test.sh`: 3 new restart rows + 1 deploy-arm row + 4 quiesce-capture rows (active/fails/inactive/bounded) + 4 armed rows + the stateful `systemctl`/curl mock (Phases 1b and 3); `inngest-wiped-volume-verify.test.sh`: 1 row.
- `cutover-inngest-workflow.test.sh`: 2.1 grep rows (2), `render_2_2` (8 rows incl. both `SOURCE` branches), Σ=0 P2-b row, text pins (Phases 1 and 4).

### Regression Tests

- All existing rows in the six suites above stay green; in particular `restart inngest succeeds` (now armed), `quiesce tolerates a benign disable non-zero (is-enabled=static)`, `500 + inventory FATAL sentinel → inngest_down`, the #8054 `render_2_0` rows, and H1 parity (`CUTOVER_HOSTS == variables.tf`).
- `scripts/inngest-restart-age-gate.test.sh`: `resolve_effective_failure_mode inngest_quiesced` passes through unchanged (it only escalates `functions_query_degraded`).

### Edge Cases

- Quiesced shape with `/health` = 200 (a unit reported inactive while something answers :8288) → DEGRADED/serving wins; never QUIESCED (serving is the stronger fact).
- `is-enabled` prints `static`/`masked`/`not-found` (no `[Install]`, or unit absent — the cattle web-2 case; systemd 255 prints `not-found` rc 4, older systemd prints empty rc 1 — both are non-`disabled`) → NOT the quiesced shape; the watchdog does not probe web-2 (tunnel is web-1-gated), and the quiesce handler's own verify already treats these as benign. A REPLACED web-1 (born with `web_colocate_inngest=false`) has no unit at all and reads FATAL → `inngest_down` forever — pre-existing, named in the ADR-100 amendment, retirement of the web-liveness arm pinned to #7674/#6178.
- `is-enabled` prints `enabled-runtime` → not quiesced; restart proceeds.
- Empty persisted capture (`[]`) while quiesced → valid resume with `captured:0` (the measured 2026-09-14 state).
- The durability advisory steps (`steps.probe.outputs.failure_mode == ''` AND `durability_state` ∈ {sqlite_only, degraded, durable}) are no-ops on a quiesced reading: the probe step only sets `durability_state` on a healthy body, so it stays empty and neither the advisory nor its auto-close fires.
- The QUIESCED body arrives truncated at 400 chars in the watchdog → host_id still precedes the variable text; classification is prefix-anchored so truncation cannot flip the mode.

### Integration Verification (for `/soleur:qa`)

- Read-only: `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep 'inngest-inventory' | jq -r '.raw|fromjson|.message'` after the delivery push shows the liveness path still reporting the live verdicts (no QUIESCED rows — the unit is not quiesced pre-window). A QUIESCED row outside a window is the audit signal for a false suppression.
- `gh run list --workflow scheduled-inngest-health.yml --limit 2` green after merge; `gh run view <id> --log | grep -c 'web scheduler QUIESCED'` → 0 pre-window.

## Success Metrics

- The next maintenance window (operator-pinged, outside this work item) runs `execute → quiesce-web → execute → arm → rearm → verify` with the second execute passing 2.1 (`source=persisted`) and 2.2 (`PASSED` on the QUIESCED sentinel), and zero `restart-inngest-server.yml` dispatches by the watchdog inside the window (`gh run list --workflow restart-inngest-server.yml` shows none in that interval).
- Zero `[ci/inngest-down]` issues filed during the window.

## Dependencies & Prerequisites

- #8135 (merged 2026-09-13/14): the 2.1 capture's Doppler read succeeds on web-1 (measured HTTP 200 in run 34865196148) — D1 builds on the working capture path.
- #8054 (merged): 2.0 dark arm passes pre-arm — the second execute reaches 2.1/2.2.
- `apply-deploy-pipeline-fix.yml` push path delivers the three scripts on merge (verified `paths:`).
- Standing constraints (verbatim from the brief, all honoured): `INNGEST_BASE_URL` stays `http://host.docker.internal:8288`; volume 106261946 is never deleted; #7674 stays OPEN; the #7695 plan/specs are not archived; `bash apps/web-platform/infra/inngest-userdata-budget.sh` (rc=0) is re-run before any destroy-capable dispatch (none in this plan); a green workflow is not verification — telemetry is self-pulled; `op=quiesce-web` is not dispatched here.

## Risk Analysis & Mitigation

- **R1 — false suppression on a real crash.** Mitigated by requiring `disabled` (only `quiesce` writes it) — Guard 1 rows 1/2; the audit query in Observability.
- **R2 — delivery race.** Workflow/classifier land at merge; host scripts land minutes later via the push. In the gap a quiesced unit reads FATAL → `inngest_down` → today's behaviour. The window is not opened until QG3(a) confirms delivery, so the race never overlaps a real quiesce.
- **R3 — existing restart tests flip.** The mock default IS the quiesced shape; Phase 3 arms the four rows explicitly (a deliberate, visible edit, not a silent default change).
- **R4 — local-then-fan-out ordering.** A transient peer non-202 leaves web-1 mutated and the verb red; re-dispatch converges (idempotent stop/disable, idempotent enable). Documented in the runbook's `*_peer_fanout_unaccepted` remedy as "re-dispatch the same op".
- **R5 — 2.2 stricter than before.** A host on the old inventory script reads UNKNOWN instead of quiesced. Correct fail-closed behaviour; the remedy names the push and the shape.
- **R6 — post-cutover permanence.** The web unit stays quiesced forever after the cutover; the watchdog prints the "expected after cutover" notice every 15 min and files nothing. The dedicated-host arm files/comments `[ci/inngest-dedicated-host]` and prints `::error::` but the Sentry check-in reads only `failure_mode`, so the TRUE post-cutover page for a dead dedicated scheduler is the ADR-117 Better Stack consumer heartbeat (~4 min) — which `op=rollback` pauses. The runbook's watchdog section states this paging path explicitly (spec-flow).
- **R7 — capture-at-quiesce fails on an active unit.** The quiesce refuses (nothing stopped), logs `INNGEST_QUIESCE_CAPTURE_FAILED rc= stderr_tail=` under the `ci-deploy` tag and returns `quiesce_capture_failed`; the capture path is the same one 2.1 exercised successfully in run 34865196148, so the residual is an enumeration-side fault the operator sees in Better Stack before any mutation — strictly safer than today's stop-without-capture. A capture slower than 120 s is refused the same way (bounded by `timeout`).
- **R8 — one watchdog tick inside the stop window.** the stop verb can take up to `TimeoutStopSec=180`; a tick landing there reads `deactivating` → FATAL → `inngest_down` → one `[ci/inngest-down]` filing, one Sentry `error` check-in and one restart dispatch that D3 refuses (or the flock defers as `lock_contention`). Disable-before-stop shrinks the `enabled` half of that window; the next quiesced tick's unchanged healthy auto-close closes the issue. Documented in the runbook as expected once per window.
- **R9 — `quiesced_peer_fanout_unaccepted` is not always transient.** `fan_out_to_peers` returns the same verdict when `hooks.json`'s `deploy-peer` secret is unreadable (`ci-deploy.sh:301`), where re-dispatch does NOT converge; the runbook remedy tells the operator to grep Better Stack for `FANOUT: webhook secret unavailable` before re-dispatching.

## Future Considerations

- Print the watchdog's QUIESCED notice only on state change if Actions log noise becomes a concern post-cutover (advisor minor; not needed for the window).
- Retire or repoint the web-host liveness arm once the dedicated host serves (post-2.4 app-repoint) — tracked under #6178/#7674, not here.

## Documentation Plan

- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: §op=quiesce-web, §1 op=execute (2.1 resume, 2.2 shape verdicts), §1a web-2 statement, §3b revoke command, deploy-status reason table, watchdog section.
- ADR-100 amendment (Phase 5).
- Learning file (via `/soleur:compound` at ship): "a brief's stale premise was the plan's third blocker — the hcloud API and a Better Stack FANOUT grep refuted it in two read-only calls".

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` with `### Amendment (2026-09-14, Ref #6921/#8077) — the quiesced unit shape is the cutover's quiesce signal`: `is-active=inactive ∧ is-enabled=disabled` is the single measurable signal; `restart` refuses it (extends the existing "restart MUST stay pure" decision — a pure restart that STARTS a disabled unit was arch P2-4's acknowledged residue and is now closed); the watchdog grades it as a deliberate, non-remediable state; 2.2 certifies it. Alternatives Considered gains the flip-flag read, the repo-var/Doppler marker and the deploy-status slot (rejected for the reasons in the table above). No new ordinal — an extension of ADR-100, same as the 2026-07-12 amendment.

### C4 views

No structural C4 change. Enumeration checked against all three files (`model.c4`, `views.c4`, `spec.c4` read this session): (a) external human actors — the operator dispatching `cutover-inngest.yml` (already the `github` actor's dispatch path); (b) external systems — GitHub Actions (`github`), Better Stack (`betterstack`), Sentry (`sentry`), Hetzner web host (`hetzner`), the deploy webhook via the tunnel (`tunnel -> hetzner` edge, which already names `/hooks/deploy`, `deploy-status`, `inngest-liveness`), the dedicated Inngest node (`inngest`) — all modeled; (c) containers/stores — `inngest-server.service` on the web host is part of `hetzner`; the capture file lives on the existing web-host volume; no new store; (d) access relationships — `quiesce`/`enable`/`restart` are verbs on the existing `deploy-webhook → ci-deploy → inngest-server` control edge (ADR-100 amendment 2026-07-12 records "additional verbs on the SAME edge, not a new relationship"); a `restart` refusal is behaviour on that edge. `plugins/soleur/test/c4-count-parity.test.sh` run this session: 10 passed, 0 failed. One pre-existing falsity noted, not caused by this change: `model.c4:206` (tunnel description) still says "web-2 was retired 2026-07-17 … var.web_hosts is now single-host" while `var.web_hosts` has two keys and `soleur-web-2` is running — folded as a one-clause correction in Phase 4 since this plan establishes that fact; `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` run after the edit.

### Sequencing

The amendment is authored in this PR (status: accepted); nothing about it is soak-gated.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` (65 open issues, 2026-09-14) matched none of the twelve planned paths (`scripts/cutover-inngest.sh`, `apps/web-platform/infra/{ci-deploy,inngest-inventory,inngest-rearm-reminders}.sh`, `scripts/inngest-liveness-classify.sh`, `.github/workflows/scheduled-inngest-health.yml`, the five test files, the runbook) via a standalone `jq --arg path … contains($path)`.

## Domain Review

**Domains relevant:** engineering, product (sign-off only — `brand_survival_threshold: single-user incident`)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Sound; premise 3 correctly refuted; guard contracts non-vacuous. Two substantive gaps, both folded: (1) HIGH — a THIRD writer of the `[Install]` symlink the plan did not name: `inngest-bootstrap.sh:1662` (`enable`) + `:1679` (`restart`) reached from `ci-deploy.sh`'s `deploy inngest` arm (hand-dispatched `deploy-inngest-image.yml`) — folded as D3(ii) `inngest_quiesced_deploy_refused` + Guard 2 assembly/rows 6/6b + FR14, and into the ADR-100 amendment ("three writers of `[Install]`: quiesce, enable, bootstrap — the latter two gated"). (2) MEDIUM — gating the whole healthy auto-close step on the quiesced output would stop pool/pool-probe issues auto-closing forever post-cutover — folded: only the three liveness-derived closes are gated. (3) LOW — drift row (v) must also assert the probe `case`'s `*)` default still exists (the #6374 trap is the default arm) — folded. Concurs with (a) the systemd shape as the signal, (b) not making `inngest_quiesced` a first-class failure mode, (c) keeping D3 — "worth it; extend to the bootstrap path or the 'every caller' claim is untrue". Complexity: medium.

### Product/UX Gate

**Tier:** none (no UI surface; `## Files to Edit` matches no UI-surface glob) — the CPO ran for the single-user-incident sign-off, not for a UX review.
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** not applicable (no UI surface)

#### Findings

CPO sign-off: **approve-with-conditions**; threshold `single-user incident` confirmed correct ("a reminder is an explicit promise a founder made to themselves; one silent non-fire is worse than a loud outage"). Conditions and their disposition: **C1** (state and assert the delivery semantic for a reminder whose `fire_at` falls inside the window — late vs dropped) → folded as the User-Brand Impact bullet + FR13 (vendor-reference or dev-probe verification, with the clamp fallback if the semantic is DROPPED); **C2** (name the founder-visible surface of the window) → folded as the User-Brand Impact bullet (reminder arming fails and crons pause while the web scheduler is stopped; the runbook keeps the window short; this plan removes the fuse that could reopen it); **C3** (the perpetual post-cutover notice must not mask a real dedicated-host outage) → R6: the dedicated-host arm (#7674) files and pages independently in its own steps; the QUIESCED notice is emitted by the web-arm probe step only. `requires_cpo_signoff: true` is satisfied at plan time by this advisory; `user-impact-reviewer` runs at review.

### Scoped advisor consult (ADR-083, Step 4.5)

Curated payload (Overview + Phases + Phase 2 as the riskiest). Guidance and disposition: **Change 1** — move the capture into the `quiesce` handler now rather than deferring it, and confirm something writes the file in this PR → ADOPTED as D1b (write path verified feasible read-only; the FIRST `op=execute`'s 2.1 already writes the file today, and D1b makes the quiesce boundary the capture point). **Change 2a** — treat the new classifier value as a union widening and grep every `failure_mode == ''` / default arm → the plan already enumerates them (Guard 1 assembly); the durability advisory reads `failure_mode == ''` AND a non-empty `durability_state`, which the quiesced path leaves empty, so it is a no-op by construction — recorded in Edge Cases. **Change 2b** — the 2.2 UNKNOWN remedy must distinguish "not in the quiesced shape" from "on-host script predates QUIESCED" → ADOPTED in D4's remedy text. **Minor** — default the `ci-deploy.test.sh` mock to active+enabled → NOT adopted: the eleven existing quiesce/enable rows depend on the current default, so the plan arms the four restart rows explicitly instead (a visible edit rather than a default flip); noted for a follow-up if the suite grows.

## Plan Review (5-agent eng panel + CTO devex, 2026-09-14)

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer (single-user-incident escalation) + cto (devex lens). Agreements first.

**Agreed by ≥ 3 reviewers and applied (mechanical):** (1) the plan contradicted itself on the auto-close gate — Phase 2c/FR6/Guard 1 pinned the whole-step `if:` the Alternatives table rejected → resolved by DELETING the `web_scheduler` side-channel altogether (both panels fired on the scope: DHH "a deliberate stop resolves a web-scheduler-down issue", CTO "whole-step gate darkens pool closes", architecture "a second output beside the single-source `failure_mode` contract is fail-open for future consumers"); (2) Phase 1 step 2 ("keep `read_secret` order") contradicted step 4 (hoist) → the `SECRET=` block moves DOWN instead (Kieran: the capture block reads `ENUMERATE_CMD`/`MODE`/`CAPTURE_FILE` defined after `:167`, so hoisting it up would leave them unbound under `set -u`); (3) `INNGEST_REARM_SKIP_DOPPLER=1` on the handler's capture call is dead once capture precedes the secret read → dropped, and `test_capture_needs_no_secret` asserts with no secret and no `doppler` on PATH; (4) `${web_quiesced/yes/quiesced}` yields `no`, not empty → moot after (1), noted; (5) FR9/Phase 5/R6-R7 carried deferral-issue residue from before the D1b fold → rewritten; (6) one `inngest_unit_quiesced()` helper beside `inngest_unit_enabled()` instead of two inline predicates, with the stricter-than-verify comment.

**Correctness findings applied (mechanical):** Kieran — the "serving" quiesce test row was unreachable with the static `/health` 200 mock (post-stop `verify_inngest_quiesced` would read `inngest_still_serving`, AC-Q5) → the mock becomes stateful; drift row (v) must exclude `healthy` (an `if`, not a `case` arm) and require ≥ 7 derived modes; `web_quiesced` must be declared beside `fail_mode=""` (`:72`), not inside the secrets-present block, or the `secret_unset` path dies under `set -u`; FR10's whole-file grep also hits `:874`/`:2131` (verify arm) and the 2.1/2.2 comment blocks → all added to Phase 4; Guard 1 row 5 overclaimed the existing `:99-109` row → the new negative + `||`-count row is the sole producer; QG1/QG2 omitted FR12/FR14/Guard 5. Architecture — two MORE start writers (`inngest-wiped-volume-verify.sh:236-240`, `workspaces-cutover.sh:633-636`) → gated with the same predicate; D1b's capture failure was unobservable under the `ci-deploy` tag the remedy named → stderr captured + `INNGEST_QUIESCE_CAPTURE_FAILED` logger line; a single `/health` probe is the return-on-first-failure proxy `verify_inngest_quiesced`'s own comment rejects → the capture gate is `systemctl is-active == active`; `inngest-bootstrap.sh:1662` `enable || true` and the unit-less replaced-web-1 case named in the ADR amendment; the amendment's stale "LB-routed" clause corrected. Spec-flow — `op=rearm` with Σ=0 dead-ends (no `re-armed=` line, file deleted, remedy chain ends at rollback) → D1c/FR15/P8; the 2.2 UNKNOWN remedy branches on the same run's 2.1 `SOURCE`; the capture is `timeout`-bounded and the poll-window drift guard grows by 120 s; both pollers get a legible `inngest_quiesced_*_refused` arm; QG3(b) restated as a read of this change's outputs, not "the run is green"; the window's founder-visible surface is `502 Dispatch failed` (not a 503), not recoverable by re-arm → User-Brand Impact + FR16 follow-up issue; the true post-cutover paging path is the Better Stack consumer heartbeat, not the Sentry check-in → runbook.

**Taste findings — applied under the both-panels-fire rule, recorded in `decision-challenges.md`:** side-channel deletion (above); `render_2_1` dropped for two grep rows (CTO devex, DHH); source-shape drift rows that only re-assert the diff dropped, Guard 3 row 5 replaced by a behavioural second-member row (DHH #7); FR13's DROPPED arm files an issue instead of shipping a re-arm clamp (DHH #2); QG1/QG2 evidence lightened to "red before, green after" (DHH #11); `captured_at` kept as a field but the explanatory second notice dropped (DHH #10, simplicity #8); the `quiesce_capture_failed)` CI case arm dropped in favour of the existing `*)` fast-fail (DHH #8, simplicity #5); disable-before-stop + R8 instead of a `deactivating` predicate (architecture #9, spec-flow #6 — the second predicate was cut).

**Taste findings NOT applied (recorded):** CTO devex — extract the 2.2 verdict tree into a pure lib function and drop `render_2_2` (kept: the curl-stub region driver tests the loop and the anchored grep, which a 3-boolean pure function would not); DHH #1's implicit corollary that the plan name an `[ci/inngest-down]` close comment for the quiesced case (no side-channel means the existing "healthy again" wording stands — accepted). Kieran #10 / DHH #6 asked for a single helper across the three DELIVERED scripts too — kept as three literal copies + a cross-file parity grep (a shared lib is a new FILE_MAP row; CTO devex concurred).

## Research Insights

### Premise Validation (Phase 0.6)

- #6921 OPEN (p2, chore), #8077 OPEN (p1, bug), #6178 OPEN (tracker), #7674 OPEN (stays open), #7695 OPEN (plan/specs not archived) — `gh issue view` this session. No cited issue is already closed by a merged PR.
- Cited paths exist on this branch: `scripts/cutover-inngest.sh`, `.github/workflows/cutover-inngest.yml:135` (`CUTOVER_HOSTS`), `.github/workflows/scheduled-inngest-health.yml`, `apps/web-platform/infra/ci-deploy.sh` (`fan_out_to_peers` at :289, `quiesce`/`enable` handlers at :2684/:2737), `apps/web-platform/infra/inngest-rearm-reminders.sh` (capture branch :198), `/var/lib/inngest/cutover-capture.json` default at :195.
- **Stale premise (brief item 3):** web-2 destroyed → FALSE today (Reconciliation). Surfaced here rather than planned against; headless run, so the re-scope is recorded in the plan and the Session Summary rather than asked.
- ADR corpus grep for the mechanism (`quiesce`, `restart`, `is-enabled`): ADR-100's 2026-07-12 amendment already decided "restart MUST stay pure" and recorded arch P2-4 (a pure restart STARTS the disabled unit) as a residue — this plan's D3 is the extension, not a rejected alternative. No ADR rejects a systemd-shape signal.

### Property List and Cut List (Phase 0.6b)

Properties: P1 second execute resumes from the persisted capture (no re-enumeration of a stopped scheduler, no stale-file resume on a crashed one); P2 the watchdog never remediates a deliberate quiesce, keeps remediating real downs, keeps the pool probe running; P3 no `restart` path starts a quiesced unit — only `enable`; P4 2.2 certifies the shape, not the proxy; P5 operator-facing text states the measured host-set reality; P6 the runbook's revoke command runs on CLI v3.75.3; P7 (added after the advisor/CPO fold) no reminder armed between the last capture and the stop is lost — the persisted capture is taken at the quiesce boundary, fail-closed; P8 (added after spec-flow) `op=rearm` on an empty capture reconciles Σ=0 instead of dead-ending.

Cut List: re-pin `CUTOVER_HOSTS` → premise false, H1 parity covers drift; flip-flag read → cannot discriminate in-window; repo-var/Doppler marker → new state + second fuse; deploy-status slot → overwritten by deploys; reorder fan-out before local mutation → measured 202, re-dispatch converges; first-class `inngest_quiesced` failure mode → darkens the pool probe.

### Relevant file paths

- `scripts/cutover-inngest.sh` — `execute)` :1154 (2.1 :1440-1459, 2.2 :1461-1533, SEAM :1535-1549), `quiesce-web)` :1833-1944, `rollback)` :2179.
- `apps/web-platform/infra/ci-deploy.sh` — `fan_out_to_peers` :289, `inngest_unit_enabled` :2406, `verify_inngest_quiesced` :2429, restart handler :2654, quiesce handler :2684, enable handler :2737.
- `apps/web-platform/infra/inngest-inventory.sh` — non-array branch :460-499 (`INVENTORY_INNGEST_HEALTH_CODE` seam :483), `derive_durability_state` :429.
- `apps/web-platform/infra/inngest-rearm-reminders.sh` — `read_secret` :133-165, capture branch :198-219.
- `scripts/inngest-liveness-classify.sh` — `classify_liveness_mode`, `is_restart_family`.
- `.github/workflows/scheduled-inngest-health.yml` — probe step :62-168 (`case "$MODE"` :113-136), poolprobe :170, effmode :324, agegate :365, dispatch :389, file-issue :400 (`case "$FAIL_MODE"` :428), auto-close :586-594, dedicated arm :725, `stopped-by-brake` notice :822-825, check-in :913-936.
- Tests: `apps/web-platform/infra/{ci-deploy,inngest-inventory,inngest-rearm-reminders,cutover-inngest-workflow,inngest-dedicated-host-classify}.test.sh`, `scripts/{inngest-liveness-classify,inngest-restart-age-gate,inngest-restart-poll-classify}.test.sh`.
- Delivery: `.github/workflows/apply-deploy-pipeline-fix.yml:66,86,89`; `apps/web-platform/infra/infra-config-apply.sh:220,228,231`.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md` — logger tags must be in the Vector allowlist (we reuse three existing tags); FSM transients split by side-effect boundary (the quiesced shape IS the post-side-effect boundary of `quiesce`).
- `knowledge-base/project/learnings/integration-issues/no-ssh-cutover-verb-by-verb-audit-inngest-quiesce-20260712.md` — `restart` never restores `[Install]`; quiesce = stop+disable; enable = enable+start; verb-by-verb sudoers pins (none added here).
- `knowledge-base/project/learnings/2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` — 2.2 today pins "non-200", not "quiesced" (D4).
- `knowledge-base/project/learnings/workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md` — the QUIESCED verdict self-reports to journald + run log before the watchdog skips remediation.
- `knowledge-base/project/learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md` — harness must-FAIL rows in every guard.
- `knowledge-base/project/learnings/best-practices/2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md` — the Observability block above.
- `knowledge-base/project/learnings/best-practices/2026-06-03-oneshot-systemd-unit-inactive-is-healthy-report-the-timer.md` — `inactive` alone is not a fault signature; the shape needs `disabled`.
- `knowledge-base/engineering/operations/post-mortems/inngest-watchdog-false-positive-unseen-6374-postmortem.md` — the `*) → down` default in the file-issue case is the union-widening trap; D2 avoids adding a failure mode at all.

### CLI verification

- `doppler configs tokens revoke --help` (v3.75.3): flags `-c/--config`, `-p/--project`, `--slug` only — verified 2026-09-14.
- `systemctl is-enabled` output vocabulary used (`enabled|enabled-runtime|disabled|static|masked`) matches `inngest_unit_enabled`'s existing case arms in `ci-deploy.sh:2407`.

### Community discovery

No uncovered stacks (bash + GitHub Actions + TypeScript); functional-discovery: no overlapping community artifacts (3/3 registries queried).

## References & Research

### Internal References

- Tracker comment (evidence): https://github.com/jikig-ai/soleur/issues/6178#issuecomment-5666841796
- #6921, #8077, #8054 (R7), #8135, #6969 (cattle web-2 birth), #6538 (fsn1 web-2 retire), #6575, ADR-100 (+ 2026-07-12 amendment), ADR-143.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` §op=quiesce-web (:828), §1 (:864), §1a (:902), §3b (:1030-1042).

### Related Work

- Run `34865196148` (op=execute, 2026-09-14 15:54 UTC): 2.0 PASSED, 2.1 HTTP 200 Σcaptured=0, 2.2 STILL RUNNING (designed stop).
- Delivery run `34862300918`: `files_written=20/20`.
