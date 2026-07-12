---
title: "feat(infra): no-SSH web-host inngest QUIESCE (stop+disable) + symmetric no-SSH re-enable — close the #6178 2.2 cutover gap"
date: 2026-07-12
type: feature
branch: feat-one-shot-6178-nosSH-inngest-quiesce-web
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues:
  - "#6178 (OPEN — cutover umbrella this unblocks)"
status: draft
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- NOTE: the pinned `systemctl` argv strings below are (a) the exact sudoers-pinned commands the
     deploy user is granted and (b) the operator host-shell steps this plan REMOVES, replacing them
     with no-SSH webhook verbs. There is NO new manual provisioning: the apply path is the EXISTING
     terraform_data.deploy_pipeline_fix auto-apply (see ## Infrastructure (IaC)). Phase 2.8
     reviewed — no new .tf resource is warranted. -->

# feat(infra): no-SSH web-host inngest QUIESCE + symmetric no-SSH re-enable

## Overview

The #6178 dedicated-host inngest cutover has ONE remaining no-SSH gap. The `op=execute`
pre-flip orchestrator runs a **2.2 QUIESCE HARD GATE** that only *checks* (inventory HTTP 200 →
fail-closed); it has no path to actually *stop* the co-located `inngest-server.service` on the
LB-reachable web host. Both the workflow remediation text
(`.github/workflows/cutover-inngest.yml:561,596`) and the runbook fall back to an operator
host-shell stop-and-disable step — an SSH action Soleur operators cannot perform (no SSH
access), violating `hr-no-ssh-fallback-in-runbooks`. This was hit live on `op=execute`
run 29188751276 (`2.2 QUIESCE HARD GATE FAILED: web-1 inngest STILL RUNNING`). With the #6090
webhook 226/NAMESPACE deadlock fix already merged + verified (v0.212.5), this is the **last
blocker** for the cutover.

This plan adds a no-SSH `op=quiesce-web` capability that mirrors the existing no-SSH
`INNGEST_RESTART` precedent (`deploy-inngest-bootstrap.sudoers` + `ci-deploy.sh` `restart`
handler + `restart-inngest-server.yml` webhook POST), fanning the stop-and-disable out over the
private net (HMAC + CF-Access, no SSH) to every host in `CUTOVER_HOSTS`. It also closes the
**inverse** gap the feature request implicitly requires: `op=rollback` currently prints an
operator re-enable SEAM (workflow `:800-802`) because a `restart` cannot restore the `[Install]`
symlink a disable removed — leaving rollback blocked on an SSH step too. This plan makes
re-enable no-SSH via a symmetric `enable` verb, so the *whole* dedicated-host cutover (forward
quiesce AND rollback re-enable) is genuinely no-SSH end to end.

## Premise Validation (Phase 0.6)

Checked every artifact the request cites by reference. Three premise corrections were found —
all confirmed by reading the current code on this branch, NOT paraphrased.

1. **CORRECTION — the `stop` grant ALREADY exists; only `disable` is genuinely new.** The request
   states "There is no stop/disable grant." False for stop:
   `deploy-inngest-bootstrap.sudoers` already grants
   `Cmnd_Alias INNGEST_STOP = /usr/bin/systemctl stop inngest-server.service` (from #5450, for
   the wiped-volume durability proof). Only the disable verb is genuinely ungranted. The plan
   follows the request's explicit shape — a self-documenting combined `INNGEST_QUIESCE` alias
   covering both verbs — and treats the stop overlap with `INNGEST_STOP` as a harmless,
   intentional mirror (sudo matches a command against any alias; no conflict). Noted so review
   does not flag the duplication as an error.

2. **CORRECTION (load-bearing) — "the existing op=rollback restart path for re-enable" is
   FACTUALLY WRONG; a restart does not re-enable.** The request's 4th bullet assumes
   `op=rollback`'s `restart inngest _ latest` re-enables the unit. The workflow's OWN comments
   contradict this (`cutover-inngest.yml:803-806`: the restart action *does NOT itself re-enable
   it — a restart never touches the [Install] symlink*), which is why `op=rollback` prints an
   operator re-enable SEAM at `:800-802`. Because the 2.2 quiesce *disables* the unit (removes the
   `[Install]` `WantedBy` symlink so a mid-window reboot cannot auto-restart the old scheduler —
   the exact double-fire the quiesce prevents), a bare restart on rollback brings the unit UP but
   DISABLED → it silently drops on the next reboot. **To satisfy the request's stated GOAL
   ("genuinely no-SSH end to end") while preserving the safety-load-bearing disable, re-enable
   MUST also be no-SSH.** This plan adds a symmetric `enable` verb rather than deleting the
   re-enable step and hoping restart covers it. This is a **User-Challenge** against the request's
   stated mechanism (see Decision Challenges below).

3. **Folding the enable verb into the shared `restart` handler is UNSAFE (rejected
   alternative).** The tempting minimal fix — make `ci-deploy.sh`'s shared `restart` handler also
   re-enable so `op=rollback`'s existing restart re-enables "for free" — is **rejected**:
   post-cutover the web hosts' inngest is *intentionally* disabled (10.0.1.40 is now the sole
   scheduler). A routine `restart-inngest-server.yml` restart (LB-routed to a web host) with a
   re-enable folded in would RE-ENABLE the deliberately-disabled web scheduler → a second live
   scheduler on prod Postgres → double-fire. `restart` must stay pure; only the *deliberate*
   `op=rollback` reverse re-enables, via a distinct `enable` verb.

4. **`#6178` is OPEN** (`arch: extract inngest to its own HA host …`) — the cutover umbrella this
   plan unblocks. Premise holds; this is a *build*, not a re-scope.

5. **`#6090` MERGED + verified** (webhook 226/NAMESPACE deadlock; multiple follow-up PRs
   reference it, e.g. #6119). Premise holds — this really is the last blocker.

6. **`#6227` is CLOSED** (`review: real per-host web→web inventory/capture fan-out …`), yet the
   workflow + runbook still cite it as an OPEN deferral ("tracked #6227"). The per-host
   **inventory** (web→web:8288 verify) fan-out it tracked is still absent — the 2.2 inventory
   probe still resolves over the LB. The plan preserves the honest DI-C3 VERIFY limitation but
   does NOT introduce a fresh "tracked #6227" claim; where the new `op=quiesce-web` needs the
   deferred-verify caveat it references the DI-C3 limitation directly (a follow-up issue to
   re-open/replace #6227 is filed — see Deferrals).

7. **Repo-capability confirmed, not assumed (`hr-verify-repo-capability-claim-before-assert`):**
   the per-host **ACT** fan-out DOES exist and is live — `ci-deploy.sh:173 fan_out_to_peers`
   forwards `{command:…}` to each peer's `http://<ip>:9000/hooks/deploy-peer` over the private
   net (#5274/ADR-068), driven by the `peers` payload field (`hooks.json.tmpl:19-20` →
   `SOLEUR_DEPLOY_PEERS`). `op=rollback` already uses it for a genuine per-host restart fan-out
   (`cutover-inngest.yml:808`). So `op=quiesce-web` can ACT on BOTH hosts (incl. weight-0 web-2)
   — a real improvement over today's operator-only web-2 handling — while VERIFY stays
   LB-scoped. Firewall for web→web:9000 is already proven live by the deploy fan-out (L3-first
   per `hr-ssh-diagnosis-verify-firewall`); no new firewall rule is needed.

## Research Reconciliation — Spec vs. Codebase

| Request claim | Codebase reality | Plan response |
|---|---|---|
| "no stop/disable grant" | `INNGEST_STOP` (stop) already granted (#5450); only disable new | Add combined `INNGEST_QUIESCE` alias per request shape; note the harmless stop overlap |
| "the existing op=rollback restart path for re-enable" | restart never touches the `[Install]` symlink (`:803-806`); rollback prints an operator re-enable SEAM (`:800-802`) | Add a distinct no-SSH `enable` verb + `INNGEST_ENABLE` grant; `op=rollback` runs enable-fanout THEN restart-fanout; delete the operator SEAM |
| op=quiesce-web "verify each host non-serving afterward" | inventory probe resolves over the LB → can only positively confirm the LB-reachable host (DI-C3) | Mirror the 2.2 gate EXACTLY: LB-reachable inventory-non-200 = quiesced; per-host ACT via fan-out, per-host VERIFY honestly deferred (surfaced via each host's deploy-status reason + fan-out rc) |
| "fans out … to every host in CUTOVER_HOSTS" | fan-out is `deploy`-action-scoped; `restart`/new handlers exit BEFORE the `:1640` fan-out call | quiesce + enable handlers call `fan_out_to_peers` themselves (mirror deploy); peers receive on `/hooks/deploy-peer` (no re-fan) |
| ci-deploy.sh + sudoers "auto-applies via apply-deploy-pipeline-fix.yml" | Both already in the DPF trigger list (`server.tf:17`, `:680`/`:738`; `apply-deploy-pipeline-fix.yml:66,72`) | NO new trigger file → NO DPF gate/test change (confirmed) |
| "#6227 tracks the deferred per-host fan-out" | #6227 is CLOSED | Preserve the DI-C3 VERIFY caveat; file a fresh follow-up for auto-verify rather than citing a closed issue |

## User-Brand Impact

**If this lands broken, the user experiences:** the #6178 cutover stays blocked (the operator
cannot quiesce the old web scheduler no-SSH, exactly as on run 29188751276) — a progress/
availability failure. The higher-severity failure: a `op=quiesce-web` that reports `quiesced`
while `inngest-server` is still serving would (if trusted without the independent 2.2 re-check)
leave a second live scheduler on prod Postgres → a user receives a **duplicate
`event-scheduled-reminder`** (double-fire of a real user-facing action). Defence-in-depth: the
`op=execute` 2.2 HARD GATE runs its OWN independent, fail-closed inventory probe before the SEAM
is ever printed, so a wrong quiesce-verify cannot by itself arm a double-fire — but the plan
treats the duplicate-user-action vector as real.

**If this leaks, the user's data is exposed via:** N/A — no user data is read, written, or
logged. The webhook carries only the fixed 4-token command (`quiesce inngest _ _`); no bodies,
reminders, or connection strings are echoed (AC-NOBODY holds).

**Brand-survival threshold:** single-user incident. → `requires_cpo_signoff: true` (frontmatter).
CPO sign-off required at plan time before `/work`; `user-impact-reviewer` runs at review time
(review skill conditional-agent block). Deepen-plan triad (data-integrity-guardian +
security-sentinel + architecture-strategist) runs next — appropriate at this threshold.

## Decision Challenges (headless — persisted for `ship`)

- **User-Challenge (mechanism):** the request says re-enable is handled by "the existing
  op=rollback restart path." The codebase proves a restart does not re-enable, so honoring the
  request's GOAL requires a small scope addition the request did not enumerate: a no-SSH `enable`
  verb + `INNGEST_ENABLE` sudoers grant + `op=rollback` wiring. The operator's stated direction
  (reuse restart) is the default; this challenge is surfaced (not silently applied). Recorded to
  `knowledge-base/project/specs/feat-one-shot-6178-nosSH-inngest-quiesce-web/decision-challenges.md`
  for `ship` to render into the PR body + an `action-required` issue.

## Implementation Phases

> TDD: write the failing test first for each shell/behavioral change
> (`cq-write-failing-tests-before`). Phase order is contract-before-consumer
> (`ci-deploy.sh` verbs + sudoers grants land before the workflow/runbook consume them).

### Phase 0 — Preconditions
- **CONFIRMED (deepen):** `/hooks/deploy-peer` (`hooks.json.tmpl:44-49`) passes only
  `command → SSH_ORIGINAL_COMMAND` and DELIBERATELY does NOT pass `peers` (its `__comment` at
  `:43` states the loop-prevention: `SOLEUR_DEPLOY_PEERS` unset → `ci-deploy.sh` does NOT re-fan).
  Both `/hooks/deploy` and `/hooks/deploy-peer` route to `/usr/local/bin/ci-deploy-wrapper.sh` →
  `ci-deploy.sh`. So a `quiesce inngest _ _` forwarded to a peer runs locally with no re-fan —
  loop-safe by construction. No code change needed here; the quiesce/enable verbs ride the SAME
  peer hook the deploy fan-out already uses.
- Confirm both trigger files are already in the DPF `paths:` filter (they are:
  `apply-deploy-pipeline-fix.yml:66,72`) → **no DPF gate/test change** this PR.
- Re-read `deploy-inngest-bootstrap.sudoers` `INNGEST_STOP`/`INNGEST_RESTART` blocks to mirror
  the exact pinned form (sudo-rs: no wildcards, resolved `/usr/bin/systemctl` path).

### Phase 1 — sudoers grants (`apps/web-platform/infra/deploy-inngest-bootstrap.sudoers`)
**Files to Edit:** `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers`
- Add, mirroring the `INNGEST_RESTART` block exactly (comment cites #6178 + this PR): a
  `Cmnd_Alias INNGEST_QUIESCE` pinning the exact `/usr/bin/systemctl stop inngest-server.service`
  and `/usr/bin/systemctl disable inngest-server.service` argv, and a
  `Cmnd_Alias INNGEST_ENABLE` pinning `/usr/bin/systemctl enable inngest-server.service`; grant
  each NOPASSWD to the `deploy` user. Each invocation is exact/pinned (no wildcards — sudo-rs
  safe). `INNGEST_ENABLE` is required by Premise Correction #2 (no-SSH rollback re-enable).
  Comment notes the intentional stop overlap with the pre-existing `INNGEST_STOP` alias.
  **No start grant is added** — the `enable` handler's start step reuses the EXISTING
  `INNGEST_START` alias (the pinned start argv, granted by #5450). So this file adds exactly two
  new pinned verbs: disable (via `INNGEST_QUIESCE`) and enable (via `INNGEST_ENABLE`).

### Phase 2 — `ci-deploy.sh` `quiesce` + `enable` handlers
**Files to Edit:** `apps/web-platform/infra/ci-deploy.sh`
- Extend the ACTION validation (`:1081`) allowlist to accept `quiesce` and `enable` alongside
  `deploy`/`restart` (keep the 4-field `read -r ACTION COMPONENT IMAGE TAG` contract; command is
  `quiesce inngest _ _` / `enable inngest _ _`, 4 fields). Reject non-`inngest` component
  (mirror `:1091` `component_not_restartable` → `component_not_quiescible` / `_not_enableable`).
- Add a `verify_inngest_quiesced()` helper. The goal state is **not-serving AND not-enabled** —
  verifying only not-serving is a proxy that defeats the disable's purpose (data-integrity review
  P1-A). Two assertions:
  1. **Not serving (PESSIMISTIC poll) + unit inactive.** Poll
     `curl -sf --max-time 5 http://127.0.0.1:8288/health` and require **ALL** N attempts to fail
     before declaring not-serving (return-on-first-failure is WRONG — a briefly-busy live
     scheduler, e.g. a GC pause, would false-read as quiesced). This is the mirror-image polarity
     of `verify_inngest_health` (which breaks on the FIRST success); the inverse must break only
     when EVERY probe fails. Reuse the health poll budget/constants (drift-guard coherence) with
     the 2.2 gate's stable-failure discipline (`CUTOVER_QUIESCE_PROBES`-style). ALSO assert the
     unit is not active via an `is-active` query (read-only, no sudo) — the double-fire risk is
     the scheduler *executing queued jobs*, which can outlive `/health` in a shutdown/crash-loop
     window (architecture review P2-3); `/health`-down AND unit-inactive together prove
     not-running.
  2. **Not enabled.** Read the unit's enabled-state (an `is-enabled` query — a read-only,
     un-granted probe, no sudo needed). Treat `static` / no-`[Install]` / `masked` as benign
     (the unit cannot auto-start on boot) → OK; treat `enabled` as FAIL → `inngest_still_enabled`,
     fail-closed. This is what makes a tolerated disable-non-zero safe: a genuine disable failure
     on a unit that HAS an `[Install]` section is caught here (the `/health` probe alone is blind
     to enabled-state, so a mid-window reboot would otherwise re-arm the old scheduler → the exact
     double-fire the disable prevents — Premise #2). Neither this nor the 2.2 inventory gate (also
     serving-only) backstops this without the enabled-state assertion.
- **`quiesce` handler** (place AFTER the `restart` handler block, before the disk-space check;
  mirror `:1161-1181`):
  1. stop the unit via the pinned sudo argv — tolerate non-zero (log advisory; an already-stopped
     or absent unit is fine — the verify is the real gate).
  2. disable the unit via the pinned sudo argv — tolerate non-zero (a unit with no `[Install]`
     section or already-disabled must NOT fail the op; log advisory).
  3. `verify_inngest_quiesced` — if still serving → `final_write_state 1 "inngest_still_serving"`;
     exit 1 (fail-closed — the goal state is not-serving).
  4. `fan_out_to_peers` — if any peer forward was not **accepted** →
     `final_write_state 1 "quiesced_peer_fanout_unaccepted"`; exit 1. **Honesty (data-integrity
     P1-B / arch P1-2):** a peer 202 is **spawn-acceptance only** (the webhook returns 202 the
     moment the peer's `ci-deploy.sh` is spawned, `ci-deploy.sh:266-270`), NOT proof the peer
     quiesced — the peer's own not-serving verdict lands on the PEER's deploy-status slot, which
     this op cannot read (DI-C3). So this reason detects an **unreachable/rejected** peer, not an
     **un-quiesced** one; do NOT name it or describe it as "peer not quiesced". On full local
     success + all peers accepted → `final_write_state 0 "quiesced"`; exit 0.
     (Single-host default: `SOLEUR_DEPLOY_PEERS` unset → `fan_out_to_peers` returns 0 immediately;
     dormant, byte-identical to pre-change for non-cutover callers.)
- **`enable` handler = enable + start + verify-serving (the TRUE inverse of quiesce; single verb,
  single flock hold — fixes the two-POST race, data-integrity P2-C / arch P1-1).**
  1. enable the unit via the pinned `INNGEST_ENABLE` sudo argv — idempotent; tolerate the
     already-enabled note (exit 0). Hard-fail only on a genuine error →
     `final_write_state 1 "inngest_enable_failed"`.
  2. start the unit via the **pre-existing `INNGEST_START` sudo grant** (from #5450 — no new grant
     needed for start; a `restart` is not required because the unit was stopped by quiesce).
     Hard-fail → `final_write_state 1 "inngest_start_failed"`.
  3. `verify_inngest_health` (reuse the existing helper) — confirm serving AND, symmetric to the
     quiesce verify, confirm the unit is now `enabled` (is-enabled query). Not-enabled after an
     enable is a failure → `inngest_reenable_unverified`.
  4. `fan_out_to_peers` (rc → `enabled_peer_fanout_unaccepted` on non-acceptance — same
     spawn-acceptance honesty as quiesce). On success → `final_write_state 0 "enabled"`; exit 0.
  Rationale for enable+start in ONE verb (vs. an `enable` POST then a separate `restart` POST):
  the two-POST form races the `flock -n` (`:1146`) — the restart POST arrives while the enable
  invocation still holds FD-200 → restart loser writes `lock_contention`, exits 1, the webhook
  already returned 202 → rollback silently ends **enabled-but-stopped** (non-durable). One verb,
  one flock hold, one fan-out eliminates the race. `restart` STAYS PURE (Premise #3); only this
  deliberate `enable` verb re-enables + starts.
- **`set -e` safety (security-review advisory).** The handlers run under `set -euo pipefail`. A
  "tolerated non-zero" sudo call MUST be guarded with `if ! sudo …; then log; fi` (or
  `sudo … || true`) — an UNGUARDED tolerated call that returns non-zero would abort the script
  under `set -e` BEFORE `final_write_state`, leaving a stale `running` state and NO fail-loud
  reason off-host (an `hr-observability-as-plan-quality-gate` regression). Wrap
  `verify_inngest_quiesced` in `set +e`/`set -e` exactly as the restart handler wraps
  `verify_inngest_health` (`:1169-1172`). This is the load-bearing pattern to copy verbatim.
- Canonical reason enum (single source of truth — keep these EXACT strings consistent across the
  handlers, the workflow poll, the Observability block, the ACs, and the reason-taxonomy doc):
  quiesce path → `quiesced` (success), `inngest_still_serving`, `inngest_still_enabled`,
  `quiesced_peer_fanout_unaccepted`; enable path → `enabled` (success), `inngest_enable_failed`,
  `inngest_start_failed`, `inngest_reenable_unverified`, `enabled_peer_fanout_unaccepted`. Each is
  a **named off-host result** surfaced via the deploy-status webhook (`/hooks/deploy-status`,
  `cat-deploy-state.sh`) AND `logger -t ci-deploy` (Vector Source 4 allowlist → Better Stack).
  No SSH. Add all of them to the reason-taxonomy doc
  `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` (arch P2-6 — docs
  completeness; `cat-deploy-state.sh` echoes the field verbatim, no parser change).

### Phase 3 — `cutover-inngest.yml`: `op=quiesce-web` + rollback re-enable + remediation rewire
**Files to Edit:** `.github/workflows/cutover-inngest.yml`
- Add `quiesce-web` to the `op:` choice `options:` list (`:22-31`).
- Add a `quiesce-web)` case arm (mirror `op=rollback`'s POST-to-`/hooks/deploy` shape,
  `:808-822`): guard `CUTOVER_HOSTS` non-empty; POST
  `{"command":"quiesce inngest _ _","peers":"<CUTOVER_HOSTS>"}` to `$BASE/deploy` (HMAC +
  CF-Access; expect 202); capture `TRIGGER_TS`.
- **Verification is a POLL, not a probe (deepen correction — `TimeoutStopSec=180`).**
  The `inngest-server.service` unit sets `TimeoutStopSec=180` (`inngest-bootstrap.sh:433`), so the
  webhook's async stop of the unit can take up to 180s AFTER the 202. An immediate inventory probe
  right after the 202 would RACE the stop and false-report STILL RUNNING. Instead mirror
  `restart-inngest-server.yml`'s verify step: **poll `/hooks/deploy-status`** for a terminal
  `component=="inngest"` state whose `start_ts >= FRESH_FLOOR` (`TRIGGER_TS - 60` clock-skew), with
  a poll budget that COVERS the host-side quiesce worst case (`verify_inngest_quiesced` attempts ×
  (interval+5) + TimeoutStopSec 180 + margin). The host writes `quiesced` only AFTER its own
  `verify_inngest_quiesced` passes → `exit_code==0 reason==quiesced` is the authoritative
  not-serving proof; `inngest_still_serving` / `inngest_still_enabled` /
  `quiesced_peer_fanout_unaccepted` → fail. (Retain an inventory-non-200 check as a SECONDARY
  confirm mirroring the 2.2 gate's classification, but the deploy-status `quiesced` reason is the
  primary gate — it is the host-side synchronous verify, stronger than the LB-routed inventory
  read.)
  **Honesty-scope (DI-C3):** the fan-out ACT is per-host; both the deploy-status poll AND the
  inventory confirm read only the LB-reachable host's slot — carry the identical caveat block the
  2.2 gate uses (`:586-599`). Per-host peer quiesce SUCCESS is surfaced only via the fan-out rc
  folded into the receiving host's reason (`quiesced_peer_fanout_unaccepted` on a non-accepted
  202) — the peer's OWN verify is the DI-C3 deferred gap (peers are fire-and-forget 202, same as
  the deploy fan-out's AC5 soak-verify pattern). No `#6227` open-claim.
- Rewire the 2.2 remediation text: `:561` and the `:596` `::error::2.2 QUIESCE HARD GATE FAILED`
  message (currently instructing an operator host-shell stop-and-disable on the LB-reachable
  host) → point at **`gh workflow run cutover-inngest.yml --field op=quiesce-web`** as the no-SSH
  remediation, then re-run `op=execute`.
- **op=quiesce-web's OWN failure branches need a no-SSH escalation (spec-flow Finding 2) — else
  the loop dead-ends at the removed SSH step.** For `inngest_still_serving`/`inngest_still_enabled`
  (persistent across a re-run), emit a diagnosis-and-forward message, NOT an SSH fallback:
  "a persistent still-serving/still-enabled means the unit is being RESURRECTED — pull
  `reason=` from `/hooks/deploy-status` / Better Stack (`logger -t ci-deploy`) and investigate
  what restarts it (e.g. a stray deploy re-enabling the unit); do NOT SSH the host." For UNKNOWN
  (000) → "the webhook was unreachable — check CF-Access/HMAC + the run log, re-dispatch". No
  branch may resolve to an operator host-shell step.
- **web-2 coherence (spec-flow Finding 4) — op=quiesce-web now ACTs on web-2 but freeze/recreate
  STAYS mandatory.** The fan-out stop+disables web-2's scheduler (an ACT), but (a) CI still cannot
  VERIFY web-2 (DI-C3, LB-scoped), and (b) web-2's LOCAL-Redis reminders were NEVER captured (2.1
  capture is also LB-scoped) — a fan-out stop does not capture/re-arm them. So the operator web-2
  **freeze/recreate lifecycle (2.2a) remains MANDATORY**. Edit the 2.2-PASSED scope notice
  (`:599`) and the 2.2a WEB-2 QUIESCE SEAM (`:605`) to state: "op=quiesce-web (when run) now
  stop+disables web-2's scheduler, but CI cannot VERIFY web-2 AND web-2's local reminders were
  never captured — freeze/recreate remains mandatory; do NOT read a green op=quiesce-web as
  'web-2 handled'." Keep `op=execute`'s 2.2a emission LOUD and UNCONDITIONAL.
- `op=rollback` re-enable (no-SSH, SINGLE POST — fixes the flock race, arch P1-1 / DI P2-C):
  REPLACE the existing `restart inngest _ latest` POST (`:808`) with a SINGLE
  `enable inngest _ _` fan-out POST (the enable verb does enable+start+verify in one flock-held
  handler — see Phase 2). Do NOT issue two POSTs (an `enable` POST then a `restart` POST) — the
  second races `flock -n` and can leave the unit enabled-but-stopped, reported as success. Then
  **poll `/hooks/deploy-status`** for terminal `component=="inngest"` `reason==enabled`
  (`start_ts >= FRESH_FLOOR`) — mirror the op=quiesce-web poll so the receiving host's
  `inngest_enable_failed` / `inngest_start_failed` / `enabled_peer_fanout_unaccepted` verdict is
  reachable from the run (not a fire-and-forget 202). DELETE the operator re-enable SEAM
  (`:800-802`); update the surrounding comments (`:796-807`) to state the reverse is now a single
  no-SSH `enable` verb (enable+start), per-host via the peer fan-out. web-2 is ACTed by the
  fan-out but its verdict is acceptance-only (DI-C3, same honesty as quiesce) — keep the web-2
  VERIFY caveat.

### Phase 4 — runbook + reason-taxonomy doc
**Files to Edit:** `knowledge-base/engineering/operations/runbooks/inngest-server.md`,
`plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`
- Document `op=quiesce-web` in the `op=…` legend at the top of the cutover section + as the
  no-SSH remediation when the 2.2 gate reports STILL RUNNING (replace any operator host-shell
  stop-and-disable prose — the `hr-no-ssh-fallback-in-runbooks` violation). Include the no-SSH
  escalation text for op=quiesce-web's own failure verdicts (spec-flow Finding 2).
- **Runbook step 1a (`:584-590`) + the op=execute SEAM notice (spec-flow Finding 4):** update to
  state that `op=quiesce-web` now stop+disables web-2's SCHEDULER (ACT) but the freeze/recreate
  lifecycle **remains MANDATORY** (CI still cannot VERIFY web-2, and web-2's local reminders were
  never captured). Do not let the fan-out read as "web-2 handled."
- Rollback step 3 (`:687-691`): the existing runbook text already claims op=rollback
  "re-enables + restarts" — a doc-ahead-of-code drift the single `enable` verb (enable+start) now
  makes TRUE. Confirm it, delete any operator re-enable reminder, keep the DI-C3 web-2 VERIFY
  caveat.
- `deploy-status-debugging.md`: add the new quiesce/enable reason strings (arch P2-6).
- Leave the SQLite-retention host-shell cleanup at `:314` OUT OF SCOPE (a separate section /
  distinct procedure) — note it in Deferrals as a pre-existing follow-up, do not expand scope
  (`wg-when-an-audit-identifies-pre-existing`).

### Phase 5 — tests
**Files to Edit:** `apps/web-platform/infra/ci-deploy.test.sh`,
`apps/web-platform/infra/cutover-inngest-workflow.test.sh`, and the sudoers test surface
(the existing `deploy-inngest-bootstrap.sudoers` visudo/pin assertion — locate via
`grep -rn 'deploy-inngest-bootstrap.sudoers\|INNGEST_RESTART' apps/web-platform/infra/*.test.sh`).
- `ci-deploy.test.sh` (mirror the `Restart action` block `:2320-2392`):
  - `quiesce inngest _ _` succeeds → reason `quiesced`, exit 0 (arm `MOCK_CURL_INNGEST_HEALTH_FAIL=1`
    so verify sees not-serving = quiesced).
  - **already-stopped idempotency:** unit already down (health unreachable) → `quiesced`, exit 0
    regardless of stop exit code.
  - **BENIGN disable tolerance:** disable exits non-zero on a unit with NO `[Install]` section
    (is-enabled → `static`) → op → `quiesced` exit 0 (tolerated). Mock: `MOCK_SYSTEMCTL_DISABLE_FAIL=1`
    + is-enabled mock returning `static`.
  - **GENUINE disable failure fail-closed (data-integrity P1-A):** disable fails AND is-enabled
    still returns `enabled` → `inngest_still_enabled`, exit 1. This is the case serving-only
    verify would have MISSED.
  - **still-serving fail-closed:** default mock (health 200) → `inngest_still_serving`, exit 1.
  - **pessimistic not-serving:** verify must require ALL probes to fail (add a mock that returns
    200 on probe 1 then fails — must NOT read as quiesced).
  - `quiesce web-platform _ _` rejected (`component_not_quiescible`, exit 1).
  - `enable inngest _ _` → enable + start + verify-serving-and-enabled → `enabled`, exit 0;
    idempotent already-enabled → `enabled`; start failure → `inngest_start_failed`.
- sudoers pin test: assert the `INNGEST_QUIESCE`/`INNGEST_ENABLE` aliases pin the EXACT
  fully-resolved `/usr/bin/systemctl <verb> inngest-server.service` argv (no wildcards) and grant
  NOPASSWD to `deploy`; keep the existing `visudo -cf` syntax gate green.
- **#5145-style poll drift-guard (new):** add a sibling of the existing restart drift-guard
  (`ci-deploy.test.sh:2569-2640`) asserting the `op=quiesce-web` deploy-status poll window ≥ the
  host-side quiesce worst case (`verify_inngest_quiesced` attempts × (interval+5) + TimeoutStopSec
  180 + margin). Extract by shape (not pinned literals) like the restart guard.
- `cutover-inngest-workflow.test.sh`: `quiesce-web` present in BOTH the `options:` list and a
  `quiesce-web)` case arm; the arm POSTs `quiesce inngest _ _` with `peers` to `/hooks/deploy` and
  POLLS deploy-status (not a bare inventory probe); the 2.2 remediation strings reference
  `op=quiesce-web` (not an operator host-shell step); `op=rollback` issues a SINGLE
  `enable inngest _ _` POST (NO separate `restart` POST) and no longer prints an operator re-enable
  SEAM.

## Infrastructure (IaC)

### Terraform changes
None (no new resource, variable, secret, vendor, or persistent process). `ci-deploy.sh` and
`deploy-inngest-bootstrap.sudoers` are existing content-carrier files.

### Apply path
(b) idempotent auto-apply on merge via the EXISTING
`terraform_data.deploy_pipeline_fix` mechanism — `apply-deploy-pipeline-fix.yml` fires on any PR
touching `apps/web-platform/infra/ci-deploy.sh` or `.../deploy-inngest-bootstrap.sudoers` (both
already in its `paths:` filter). Fresh hosts get the same sudoers via cloud-init `write_files`.
No new trigger file → no DPF gate/test change. `.github/workflows/cutover-inngest.yml` +
the runbook take effect at merge (workflow) / on read (docs). Blast radius: the sudoers install
is a `visudo -cf`-gated atomic replace (`server.tf:760-762`); the ci-deploy.sh change is dormant
for all non-cutover callers (new verbs only run when explicitly POSTed).

### Distinctness / drift safeguards
No secrets land in state (no TF var). `op=quiesce-web` and the `restart`-vs-`enable` split are
prod-write ops behind explicit `gh workflow run --field op=…` dispatch (same trust model as the
existing `op=rollback` prod-write), not a merge-time apply.

### Vendor-tier reality check
N/A — no vendor resource.

## Observability

```yaml
liveness_signal:
  what: "op=quiesce-web / op=rollback run status + each host's ci-deploy deploy-status reason"
  cadence: "on-demand (operator gh workflow run, cutover maintenance window)"
  alert_target: "GitHub Actions run conclusion (fail-loud) + Better Stack Logs (tag ci-deploy)"
  configured_in: ".github/workflows/cutover-inngest.yml + apps/web-platform/infra/ci-deploy.sh (write_state)"
error_reporting:
  destination: "deploy-status webhook reason field (/hooks/deploy-status, cat-deploy-state.sh) + logger -t ci-deploy -> Vector Source 4 -> Better Stack"
  fail_loud: true   # all failure reasons exit non-zero AND are reachable from the run via the deploy-status POLL (not fire-and-forget 202)
failure_modes:
  - mode: "stop+disable ran but inngest still SERVING on LB-reachable host"
    detection: "verify_inngest_quiesced (in-host curl /health, all-probes-fail) -> host writes reason; op=quiesce-web POLLS deploy-status"
    alert_route: "reason=inngest_still_serving (deploy-status poll) + workflow fail-closed"
  - mode: "stop succeeded but unit still ENABLED (disable failed on a unit WITH [Install]) -> reboot re-arms"
    detection: "verify_inngest_quiesced is-enabled check (in-host, no sudo)"
    alert_route: "reason=inngest_still_enabled (deploy-status poll) + workflow fail-closed"
  - mode: "peer (web-2) fan-out NOT ACCEPTED (webhook unreachable / HMAC-rejected)"
    detection: "fan_out_to_peers rc != 0 on receiving host — NOTE: this detects non-ACCEPTANCE (missing 202), NOT peer-not-quiesced; the peer's own quiesce verdict lands on the PEER's deploy-status slot (DI-C3 deferred, unreadable here)"
    alert_route: "reason=quiesced_peer_fanout_unaccepted (deploy-status poll) + workflow non-zero exit"
  - mode: "rollback re-enable failed on a host (enable, start, or re-enable-verify)"
    detection: "enable handler non-zero exit OR fan-out non-acceptance; op=rollback POLLS deploy-status"
    alert_route: "reason=inngest_enable_failed / inngest_start_failed / inngest_reenable_unverified / enabled_peer_fanout_unaccepted (deploy-status poll)"
logs:
  where: "Better Stack Logs (tag=ci-deploy, Vector Source 4 allowlist) + GitHub Actions run log"
  retention: "Better Stack default retention; run logs 90d"
discoverability_test:
  command: "curl -s -H 'X-Signature-256: sha256=$SIG' -H 'CF-Access-Client-Id: ...' https://deploy.soleur.ai/hooks/deploy-status | jq '{component,reason,exit_code}'"
  expected_output: "{component: inngest, reason: quiesced, exit_code: 0} after op=quiesce-web (NO ssh)"
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-100** (`ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`, status
`adopting`) — add a note under `## Decision` (and an entry in its alternatives) that the web-host
scheduler quiesce/re-enable during cutover is performed **no-SSH** via the deploy webhook +
pinned sudoers verbs (`INNGEST_QUIESCE` stop+disable via `op=quiesce-web`; `INNGEST_ENABLE`
re-enable via `op=rollback`), mirroring `INNGEST_RESTART` (#4538) + the deploy fan-out
(ADR-068). Record the rejected alternative (fold enable into shared `restart` — unsafe
post-cutover, Premise #3). Note the **security blast-radius expansion** (security review P2): the
single shared webhook deploy secret now authorizes a scheduler-disable (and, via `enable`, a
re-arm) fleet-wide, not just deploy/restart — inside the existing "deploy secret == prod-write"
boundary, but the secret-rotation cadence should reflect it; and the peer fan-out path
(`http://<ip>:9000/hooks/deploy-peer`) is HMAC + L3-firewall only (no CF-Access), so confirm the
web→web:9000 firewall restricts source to peer hosts. No NEW ADR ordinal (this is an extension of
ADR-100's decision, not a new architecture).

### C4 views
No C4 impact — verified by reading all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) at /work time.
Enumeration checked: (a) external human actor — the operator dispatching `gh workflow run` is
already the modeled operator; no new actor. (b) external system/vendor — none (deploy webhook,
`ci-deploy.sh`, `inngest-server.service` are already-modeled internal containers). (c)
data-store — none touched. (d) access relationship — the deploy-webhook → ci-deploy →
inngest-server control edge already exists (restart/deploy); `quiesce`/`enable` are additional
verbs on the SAME edge, not a new relationship. A "no C4 impact" conclusion cites this
enumeration; deepen-plan re-verifies against the `.c4` files.

### Sequencing
Immediate — the ADR-100 amendment ships in THIS PR (it is a deliverable, not a follow-up).

## Acceptance Criteria

### Pre-merge (PR)
- [x] `deploy-inngest-bootstrap.sudoers` grants `INNGEST_QUIESCE` (pinned stop+disable) and
      `INNGEST_ENABLE` (pinned enable) NOPASSWD to `deploy`; `visudo -cf` passes; each argv is
      wildcard-free (grep asserts the exact `/usr/bin/systemctl … inngest-server.service`).
- [x] `verify_inngest_quiesced` asserts **not-serving (ALL /health probes fail, PESSIMISTIC) AND
      unit-inactive AND not-`enabled`** — a disable-failure on a unit WITH an `[Install]` section
      fails closed as `inngest_still_enabled` (benign `static`/no-`[Install]` tolerated). Verifying
      serving-only would defeat the disable (data-integrity P1-A).
- [x] `ci-deploy.sh` accepts `quiesce inngest _ _` → reason `quiesced` exit 0 on not-serving-and-
      not-enabled; `inngest_still_serving` / `inngest_still_enabled` exit 1 otherwise; tolerates
      already-stopped + a disable non-zero (verify is the gate); rejects non-inngest component.
- [x] `ci-deploy.sh` accepts `enable inngest _ _` = enable + start + verify-serving-and-enabled in
      ONE flock-held handler (reuses the pre-existing `INNGEST_START` grant); reason `enabled` exit
      0. `restart` semantics UNCHANGED (no re-enable folded in — a security + correctness
      regression guard).
- [x] `cutover-inngest.yml` `op:` options include `quiesce-web`; the `quiesce-web)` arm POSTs
      `quiesce inngest _ _`+`peers` and **POLLS `/hooks/deploy-status`** for terminal
      `reason==quiesced` (FRESH_FLOOR-anchored, budget ≥ TimeoutStopSec 180 + verify) as the
      primary gate, with an inventory-non-200 SECONDARY confirm (LB-scoped, DI-C3 caveat). It does
      NOT probe immediately after the 202 (races the async stop).
- [x] `op=quiesce-web` failure verdicts (`inngest_still_serving`/`inngest_still_enabled`/
      `quiesced_peer_fanout_unaccepted`/UNKNOWN) each print a no-SSH forward action (spec-flow
      Finding 2) — no branch resolves to an operator host-shell step.
- [x] `op=execute` 2.2 remediation (`:561`,`:596`) references `op=quiesce-web`, not an operator
      host-shell step; the 2.2-PASSED notice (`:599`) + 2.2a SEAM (`:605`) state web-2 is ACTed by
      the fan-out but freeze/recreate remains MANDATORY (spec-flow Finding 4).
- [x] `op=rollback` issues a SINGLE `enable inngest _ _` POST (enable+start) and POLLS
      deploy-status for `reason==enabled` — NOT a two-POST enable+restart (flock race, arch P1-1);
      the operator re-enable SEAM (`:800-802`) is removed.
- [x] Runbook documents `op=quiesce-web`; the 2.2 + rollback steps contain no operator host-shell
      step (`hr-no-ssh-fallback-in-runbooks` satisfied for the cutover flow).
- [x] ADR-100 amended (no-SSH quiesce/re-enable verbs + rejected fold-into-restart).
- [x] `ci-deploy.test.sh` + `cutover-inngest-workflow.test.sh` + sudoers pin test green.
- [x] `decision-challenges.md` written (the restart≠enable User-Challenge) for `ship`.

### Post-merge (operator/CI)
- [ ] DPF auto-apply (`apply-deploy-pipeline-fix.yml`) lands the new sudoers + ci-deploy.sh on
      running web hosts (CI-verified via the workflow run + deploy-status; no operator action).
- [ ] Re-run the live cutover: `op=execute` → if `2.2 STILL RUNNING`, `op=quiesce-web` → re-run
      `op=execute` reaches the SEAM (unblocks #6178). Close #6178's 2.2 criterion.

## Test Scenarios
Covered above (Phase 5). Deterministic shell tests only — no LLM/network in the assertion path;
mocks drive `systemctl`/`curl` exit codes so the quiesce verify + disable tolerance are exercised
by construction.

## Domain Review

**Domains relevant:** none (infrastructure/tooling change).

No cross-domain (marketing/finance/legal/sales/support/product) implications — a no-SSH
deploy-webhook control verb + runbook/ADR update. No UI surface (no `components/**`,
`app/**/page.tsx`) → Product/UX Gate does not fire. Engineering scrutiny is delivered by
plan-review (DHH/Kieran/simplicity + architecture-strategist/spec-flow at the single-user-incident
threshold) and the deepen-plan triad (data-integrity-guardian, security-sentinel,
architecture-strategist).

## Deferrals (tracking)
- Pre-existing SQLite-retention host-shell cleanup at `inngest-server.md:314` (separate section,
  its own deferred-automation note) — file a follow-up to make that cleanup no-SSH; NOT in scope.
- Per-host **inventory** auto-verify (web→web:8288) so `op=quiesce-web`/`op=execute` positively
  confirm web-2 without an operator step — #6227 (its original tracker) is CLOSED; file a fresh
  issue to re-open/replace it. `op=quiesce-web`'s per-host ACT (fan-out) already narrows the gap.

## Open Code-Review Overlap
None — checked open `code-review`-labelled issues against the Files to Edit
(`deploy-inngest-bootstrap.sudoers`, `ci-deploy.sh`, `cutover-inngest.yml`, `inngest-server.md`,
the test files, ADR-100); no overlap found. (Re-run `gh issue list --label code-review --state
open` at /work if the backlog changed.)

## Deepen-Plan Review Findings & Resolutions

**Deepened 2026-07-12.** Mandatory gates: User-Brand Impact (4.6) PASS, Observability (4.7) PASS,
PAT-shaped (4.8) PASS (none), UI-wireframe (4.9) N/A (no UI surface), Network-outage (4.5) —
web→web:9000 firewall already proven live by the deploy fan-out, no new rule. Review panel
(single-user-incident threshold): security-sentinel, data-integrity-guardian,
architecture-strategist, spec-flow-analyzer.

| # | Src | Finding | Resolution |
|---|-----|---------|------------|
| P1-A | data-integrity | `verify_inngest_quiesced` checked SERVING only → a tolerated disable-failure on a unit WITH `[Install]` passes as `quiesced` while still enabled → reboot re-arms → double-fire | Verify now asserts not-serving (all-probes) AND not-`enabled` (`inngest_still_enabled` fail-closed; benign `static`/no-`[Install]` tolerated). Phase 2 + AC + tests updated. |
| P1-1 / P2-C | arch + data-integrity | Two-POST rollback (enable POST then restart POST) races `flock -n` → unit ends enabled-but-stopped, reported success | Collapsed to ONE `enable inngest _ _` verb = enable+start+verify in one flock hold (reuses the existing `INNGEST_START` #5450 grant); op=rollback POSTs it once + polls deploy-status. |
| F1 (HIGH) | spec-flow | op=quiesce-web POST is async 202 → handler verdict never reaches the workflow; a `fail_loud` claim the wiring didn't deliver | op=quiesce-web (and op=rollback) now POLL `/hooks/deploy-status` for the terminal reason (FRESH_FLOOR-anchored). Also fixes the TimeoutStopSec=180 async-stop race (P2-5/F3). |
| F2 (HIGH) | spec-flow | op=quiesce-web's own failure verdicts had no defined no-SSH remediation → loop dead-ends at the removed SSH step | Added no-SSH diagnosis-and-forward text per verdict (Phase 3 + runbook). |
| F4 (HIGH) | spec-flow | op=quiesce-web now ACTs on web-2 via fan-out, but `:599`/`:605`/runbook 1a still say web-2 is unverified & mandate freeze/recreate — operator could skip it | Reconciled: web-2 scheduler is ACTed but freeze/recreate STAYS mandatory (CI can't verify web-2 + local reminders never captured); path-dependency stated. |
| P1-B / P1-2 | data-integrity + arch | `quiesced_peer_unreached` overstated — a 202 is spawn-acceptance, not quiescence | Renamed `quiesced_peer_fanout_unaccepted`; reworded everywhere to "non-acceptance, not peer-not-quiesced". |
| P2-3 | arch | inverse `/health` alone is a weak quiesce signal (jobs can outlive /health) | Added a unit-`is-active` check to the not-serving assertion. |
| P2-4 | arch | `restart` being pure ≠ safe post-cutover — a routine restart-inngest-server.yml on a web host re-starts the disabled unit (transient double-fire; ExecStartPre guard is dedicated-host-only) | Added Sharp Edge + runbook/ADR note. |
| Sec P2 | security | shared deploy secret now authorizes scheduler-disable/re-arm fleet-wide; peer path is HMAC + L3 only (no CF-Access) | ADR-100 amendment records the blast-radius + rotation cadence + firewall-source-scope confirmation. |
| Sec advisory | security | `set -e` + tolerated-non-zero could exit before `final_write_state` → stale `running`, no reason | Handlers copy the restart handler's `if ! sudo…; then` + `set +e/-e`-around-verify pattern verbatim. |
| P2-6 | arch | new reason strings absent from the taxonomy doc | Added `deploy-status-debugging.md` to Phase 4 Files-to-Edit. |

**Confirmations (no change):** sudoers pins are argv-exact / sudo-rs safe (no injection; service name is a hardcoded literal, `COMPONENT` never reaches the sudo argv); `/hooks/deploy-peer` omits `peers` → no re-fan (loop-safe); `fan_out_to_peers` self-skip means each host acts exactly once; the op=execute 2.2 HARD GATE is genuine independent defence-in-depth before arming; the existing `INNGEST_STOP` (#5450) makes only `disable` genuinely new.

## Deepen-Plan Review Findings & Resolutions

**Deepened:** 2026-07-12. **Mandatory gates (all PASS):** User-Brand Impact present (threshold
single-user incident); Observability 5-field schema present, `discoverability_test` has no `ssh`;
no PAT-shaped variables; no UI surface (no `.pen` required); IaC routing acked (apply path is the
existing DPF auto-apply). **Network-Outage (4.5, SSH keyword):** L3 firewall for web→web:9000 is
already proven live by the deploy fan-out (#5274) — no new firewall rule; the only firewall action
is a security-review CONFIRM that web→web:9000 source-restricts to peer hosts. **Downtime (4.55):**
`op=quiesce-web` stops only the co-located inngest SCHEDULER (loopback :8288), not the Concierge/web
serving surface; the scheduler-silent window is the intended cutover gap already covered by the
runbook's Better Stack heartbeat-suppression window (P2-14). No new downtime section warranted.

**Review agents:** architecture-strategist, security-sentinel, data-integrity-guardian,
spec-flow-analyzer (the single-user-incident triad + flow analysis).

| # | Sev | Finding | Resolution (applied to plan) |
|---|-----|---------|------------------------------|
| DI P1-A | P1 | `verify_inngest_quiesced` checked SERVING only; a tolerated disable-failure on a unit WITH `[Install]` passes as `quiesced` while still enabled → reboot re-arms → double-fire | verify now asserts not-serving (pessimistic, ALL probes) AND unit-inactive AND not-`enabled`; `inngest_still_enabled` fail-closed; benign `static`/no-`[Install]` tolerated. AC + tests updated |
| DI P1-B / arch P1-2 | P1 | `quiesced_peer_unreached` proves 202 ACCEPTANCE (spawn), not quiescence — overstated as "peer not quiesced" | renamed `quiesced_peer_fanout_unaccepted`; Observability table + prose corrected to "non-acceptance, NOT peer-verified"; peer verdict is DI-C3 deferred |
| arch P1-1 / DI P2-C | P1 | rollback's two-POST (enable then restart) races `flock -n` → enabled-but-stopped reported as success | `enable` is now a SINGLE verb (enable+start+verify, one flock hold, reuses `INNGEST_START`); `op=rollback` issues one POST + polls deploy-status |
| spec-flow F1 | HIGH | async 202 means the handler verdict is invisible to the run; `fail_loud` unreachable | `op=quiesce-web` + `op=rollback` now POLL `/hooks/deploy-status` (FRESH_FLOOR, budget ≥ TimeoutStopSec 180) — verdict reachable from the run |
| spec-flow F2 | HIGH | op=quiesce-web's own failure branches had no no-SSH escalation → loop dead-ends at the removed SSH step | each verdict prints a no-SSH forward action (diagnose-what-resurrects-it via deploy-status/Better Stack); emitted in run output + runbook |
| spec-flow F4 | MED | op=quiesce-web now ACTs on web-2 (fan-out) but `:599`/`:605`/runbook 1a still say web-2 unhandled → operator may skip mandatory freeze/recreate | Phase 3/4 add explicit edits: web-2 scheduler is stop+disabled (ACT) but freeze/recreate STAYS mandatory (CI can't verify + local reminders never captured); path-dependency stated |
| arch P2-3 | P2 | inverse `/health` weaker than for restart (scheduler can outlive `/health`) | verify also asserts unit-inactive (is-active) |
| arch P2-4 | P2 | `restart` pure ≠ safe: a routine `restart-inngest-server.yml` post-cutover starts a web host's disabled unit → transient double-fire (flip-guard blocks only the dedicated host) | Sharp Edge + runbook/ADR note added |
| sec P2 (×2) | P2 | shared deploy secret now authorizes scheduler-disable/re-arm fleet-wide; peer path is HMAC+L3 only (no CF-Access) | ADR-100 amendment notes blast-radius + rotation cadence + web→web:9000 firewall source-scope confirm |
| arch P2-6 | P2 | new reason strings not in the reason-taxonomy doc | Phase 4 adds `deploy-status-debugging.md` update |
| sec advisory | — | unguarded tolerated-non-zero sudo aborts before `final_write_state` under `set -e` | Phase 2 mandates the `if ! sudo …; then` + `set +e/-e` pattern copied from the restart handler |

**Confirmed sound (no change):** separate `enable` verb (not folding into restart); inverting the
health check as the success criterion; loop/re-fan safety (`/hooks/deploy-peer` omits `peers`);
`fan_out_to_peers` self-skip; sudoers pin form + the `INNGEST_STOP`/`INNGEST_START` reuse. AC-NOBODY
holds (fixed reason enum; no bodies/reminders/connection strings logged). Defence-in-depth is real:
`op=execute`'s independent fail-closed 2.2 gate remains the arming guard, so a wrong quiesce-verify
cannot by itself arm a double-fire.

## Sharp Edges
- The `## User-Brand Impact` section is filled (threshold single-user incident); do not blank it —
  deepen-plan Phase 4.6 halts on an empty/TBD section.
- `restart` MUST stay pure (never re-enable) — folding enable in would re-arm the deliberately
  disabled post-cutover web scheduler on any routine `restart-inngest-server.yml` run
  (double-fire). Only the deliberate `op=rollback` re-enables, via the distinct `enable` verb.
- **`restart` being pure ≠ `restart` being SAFE post-cutover (arch P2-4).** A routine
  `restart-inngest-server.yml` (LB-routed to a web host) post-cutover ALREADY starts the
  stopped+disabled unit → a TRANSIENT second scheduler on prod Postgres, independent of any
  enable-folding, because the `ExecStartPre` flip-guard blocks only the DEDICATED host, not web
  hosts. Document in the runbook/ADR that `restart-inngest-server.yml` should not target web hosts
  after the cutover completes; the web verb to touch post-cutover is `op=quiesce-web`, never
  restart.
- **The `enable` verb is a re-arm footgun (security review P2).** It enable+starts a deliberately-
  disabled web scheduler; an `enable` invoked outside `op=rollback` re-arms a second scheduler →
  duplicate user reminder. Keep it reachable ONLY via `op=rollback`, and keep the "restart stays
  pure" + "enable does not fire on quiesce" invariants as SECURITY regression guards, not just
  correctness.
- `op=quiesce-web` verify is LB-scoped (DI-C3): the fan-out ACTS per-host but the inventory probe
  confirms only the LB-reachable host — carry the exact 2.2-gate caveat; do NOT claim per-host
  VERIFY (that infra is deferred; original tracker #6227 is closed).
- The two "quiesce" meanings differ: `INNGEST_CUTOVER_QUIESCE` (Doppler arming-quiesce, blocks
  new reminders into old SQLite) vs `op=quiesce-web` (stop-and-disable the scheduler process).
  Keep runbook prose disambiguated.
- sudo-rs rejects wildcards — every new alias pins the fully-resolved
  `/usr/bin/systemctl <verb> inngest-server.service` argv; the pin test guards it.
