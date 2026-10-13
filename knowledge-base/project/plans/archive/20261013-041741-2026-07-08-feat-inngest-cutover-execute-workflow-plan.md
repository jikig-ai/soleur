---
title: "feat: Author Phase-2 op=execute cutover workflow for the dedicated Inngest host (#6178)"
date: 2026-07-08
issue: 6178
adr: ADR-100
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
pr_intent: "Ref #6178 (NOT Closes — #6178 stays open until Phase-4 soak)"
---

# feat: Author Phase-2 `op=execute` cutover workflow for the dedicated Inngest host (#6178)

> **Note (lane):** no `spec.md` exists for this branch (fresh one-shot) — `lane:`
> defaulted to `cross-domain` (fail-closed). This is really a single-domain
> infra/eng change; the default is conservative.

## Overview

Phase-1 IaC shipped and the dedicated Inngest host is **live and dark**
(`hcloud_server.inngest` = cpx22 amd64, private IP `10.0.1.40`, Redis AOF volume,
non-prod Postgres → empty function registry → zero prod crons). This deliverable
**authors** the Phase-2 cutover mechanism per §"Phase 2 — Cutover" of
`knowledge-base/project/plans/2026-07-07-feat-extract-inngest-dedicated-host-plan.md`
(the parent umbrella plan) and ADR-100. It does **not** execute the cutover — that
stays the operator's maintenance-window trigger.

**Scope of this PR (authoring only):**
1. New `op=execute` (pre-flip orchestrator) + `op=verify` (exactly-once) arms in
   `.github/workflows/cutover-inngest.yml`, chaining the **web-host-expressible**
   cutover spine (2.0 → 2.2, then 2.5 → 2.6) with the two non-expressible operator
   seams (2.2b+2.3 flip, 2.4 app-repoint) as explicit gated hand-offs.
2. New host script **`inngest-registry-probe.sh`** (web-host, webhook-delivered) —
   the 2.0 empty-registry pre-flight against `10.0.1.40:8288/v0/gql`.
3. New host script **`inngest-cutover-flip.sh`** + `inngest-cutover-flip.service` +
   `inngest-cutover-flip.timer` (**dedicated-host**, OCI-baked, Doppler-flag-armed) —
   the 2.2b Redis `FLUSHALL` + `DBSIZE==0` gate **merged with** the 2.3 prod-Postgres
   flip restart, executed **on** `10.0.1.40` because there is no other no-SSH channel.
4. `hooks.json.tmpl` + full drift-guard registration for the probe; OCI/cloud-init
   wiring for the flip oneshot; tests; expenses-ledger flip; runbook.

**Why the shape changed from the task framing — the load-bearing finding:** the task
assumed 2.2b is "just a new host script" and 2.3 is a restart "sequenced around the
workflow." Codebase reality (verified): **the dedicated host runs NO `adnanh/webhook`,
NO `hooks.json`, NO `ci-deploy.sh`** — its only no-SSH primitives are cloud-init
`runcmd` (fires on force-replace) and systemd units. The web-host webhook at
`deploy.soleur.ai/hooks/*` **cannot** reach `10.0.1.40` to `redis-cli FLUSHALL` a
loopback-bound Redis or `systemctl restart` the dedicated inngest. `restart-inngest-server.yml`
restarts the **co-located** web-host unit (`ci-deploy.sh:1162`), i.e. the wrong host
post-extraction. So 2.2b + 2.3 **require a new on-host mechanism** — authored here as a
Doppler-flag-armed OCI-baked oneshot. Honoring `hr-no-ssh-fallback-in-runbooks` (hard
rule) forbids "operator SSHes to flush Redis." See **Research Reconciliation** below.

## Research Reconciliation — Task/Plan framing vs. Codebase reality

| Framing claim | Reality (file:line) | Plan response |
|---|---|---|
| "2.2b Redis FLUSHALL + DBSIZE==0 — a NEW host script" (implies web-host webhook delivery like the other cutover scripts) | Redis is `bind 127.0.0.1 -::1` (`inngest-redis.conf:13`) on `10.0.1.40`; the web-host webhook cannot reach it; the dedicated host runs **no** webhook/hooks/ci-deploy (`cloud-init-inngest.yml` full read — only `runcmd` + systemd units) | Author `inngest-cutover-flip.sh` as a **dedicated-host** script delivered via the OCI image (`build-inngest-bootstrap-image.yml:177-199` pattern), installed by `inngest-bootstrap.sh`, triggered by an on-host `.timer` polling a Doppler flag — NOT a web-host webhook script |
| "2.3 flip = Doppler value edit + restart, sequenced around the workflow" (implies a restart channel exists) | No no-SSH restart channel reaches `10.0.1.40`; `restart-inngest-server.yml` → `ci-deploy.sh:1162` restarts the **web-host** unit; `INNGEST_POSTGRES_URI` is read only at `ExecStart` (`inngest-bootstrap.sh:359`) so the flip needs an on-host process restart | **Merge 2.2b + 2.3** into the same on-host oneshot: `FLUSHALL` → assert `DBSIZE==0` → `systemctl restart inngest-server.service` (re-reads the flipped prod URI) → disarm the flag → write a verify-state slot. Operator arms it via two out-of-band Doppler writes on `soleur-inngest/prd` |
| "Chain 2.0→2.6 in a single `op=execute` run" | The dedicated host is unreachable from a GitHub runner (deny-all-public, private-net-only); 2.2b/2.3 are operator prod-writes (kept out of CI per `inngest-host.tf` `ignore_changes`); 2.4 is a committed source change + redeploy | `op=execute` automates the contiguous web-host spine (2.0→2.2) and **gates** the two operator seams with printed instructions; `op=verify` does 2.6; existing `op=rearm` does 2.5. This is the honest "gated orchestration" — see **Decision-Challenge** |
| "2.6 verify per-`(function_id, scheduled_tick)`" (parent plan AC12 prose, still shows `scheduled_tick`) | `scheduled_tick` does not exist in v1.19.4 (ADR-100 Decision 7; `…5450/inngest-graphql-schema.md:14`) | 2.6 uses `runs(first, filter: RunsFilterV2!, orderBy)` with `{ timeField: STARTED_AT, functionIDs:[…] }`; exactly-once ⇔ every `(functionID, floor(startedAt / cron_period))` bucket has exactly one run |
| Heartbeat "set out-of-band at cutover" | `INNGEST_HEARTBEAT_URL` picked up by the on-host `inngest-heartbeat.timer` at the next 60s `ExecStart` (`inngest-bootstrap.sh:177-206`, project `soleur-inngest`); the URL is deliberately absent from `soleur-inngest/prd` during dark | Keep as an operator out-of-band Doppler `set` (clean no-SSH path); sequence it AT the flip (co-located web pusher quiesced simultaneously — one pusher per monitor) |

## User-Brand Impact

**If this lands broken, the user experiences:** every scheduled cron and armed
reminder either **double-fires** (two schedulers on prod Postgres — duplicate agent
runs, duplicate emails/notifications, duplicate GHCR-token mints) or is **silently
dropped** (a reminder created in the quiesce→register window, or a mis-reconciled
rearm) — the user's scheduled work vanishes or repeats with no error surfaced.

**If this leaks, the user's workflow is exposed via:** the cutover surfaces reminder
`reminder_id`s + counts only (P2-sec-a); reminder **bodies/actors** stay on-host and
must never reach a run log. A regression that echoes capture bodies into the Actions
log leaks user workflow content into a CI surface.

**Brand-survival threshold:** `single-user incident`. A single botched cutover
double-firing one founder-user's crons is a brand-survival event.

> **CPO sign-off (carry-forward):** the parent extraction plan
> (`2026-07-07-feat-extract-inngest-dedicated-host-plan.md`) was framed + reviewed at
> this threshold through brainstorm + deepen-plan + the data-integrity/security triad.
> This deliverable implements its Phase-2. CPO carry-forward applies; `user-impact-reviewer`
> runs at review-time (review-skill conditional-agent block).

## Downtime & Cutover

Two operations in this deliverable's blast radius could take a surface offline; both
default to the least-downtime path.

1. **Installing the flip oneshot on the dark host (Phase C.4).** A cloud-init/OCI change
   force-replaces the `hcloud_server.inngest` singleton (Op C — no `ignore_changes[user_data]`).
   **Zero prod-downtime by construction:** the host is on the **non-prod dark backend** and
   serves zero prod crons, so the replace touches no serving surface. The AOF Redis volume
   is a separate resource that survives the replace (re-attach verified — git-data
   precedent). Do this replace **during the dark window, well before the cutover** — never
   inside the maintenance window. No blue-green needed (dark host has no live traffic).
2. **The cutover window itself (2.2 → functions register after 2.4).** This is the parent
   plan's **accepted bounded residual** (Op B): a *fully* zero-downtime switchover is
   impossible under the single-writer constraint (two schedulers on prod Postgres
   double-fire every cron — strictly worse than a brief gap), so the forward path MUST
   quiesce the old scheduler before the new one takes prod Postgres. Mitigations:
   **low-traffic maintenance window**; the flip oneshot restarts inngest **in place** (no
   host recreate during the window — the oneshot is pre-installed, so the window is bounded
   by the restart + app-redeploy, target < 5 min, NOT a cold-boot OCI pull); enumerate
   crons needing manual `trigger-cron` re-fire; ticks missed in-window are not backfilled.
   **Rollback stops the DEDICATED host first** (arm the flip flag in a stop mode), then
   repoints app → loopback, then re-enables web inngest — mirroring the forward gate.
   Operator sign-off is carried by the parent plan's threshold framing.

**Why the oneshot beats the force-replace-flush for the window:** a force-replace-with-
gated-FLUSHALL would recreate the host mid-window (cold OCI pull + cosign + bootstrap =
minutes + 226/NAMESPACE risk), widening the H1 residual and adding failure surface at the
worst moment. The pre-installed Doppler-armed oneshot flips **in place** — this is the
zero-downtime-first choice for the window.

## Network-Outage / Reachability (L3-first)

The dedicated host is **deny-all-public** with a scoped `hcloud_firewall`; it is reachable
only from the private subnet. Reachability facts (verified in Phase-1 IaC, re-assert before
the window):
- **L3 firewall / subnet membership:** Hetzner cloud firewalls filter only the public
  interface; intra-subnet traffic is open by membership (SEC-H1). So a web host reaches
  `10.0.1.40:8288` over the private net — this is what the registry-probe (2.0) and the
  verify (2.6) depend on. Host-local **nftables** (AC-NFT, Phase-1) scopes `:8288/:8289`
  to web-host private IPs only. Re-assert the nftables allow-list + the app
  private-interface bind before the window (AC-FW).
- **GitHub runner → dedicated host: NO direct L3 path** (deny-all-public). Every dedicated-
  host interaction routes through a **web host** (registry-probe hook, verify hook) or an
  **on-host oneshot** (flip). No plan step curls `10.0.1.40` directly from a runner.
- Every `curl` in the new arms carries `--max-time` (no unbounded network call); the
  registry-probe / verify curls target the web-host webhook, which forwards over the
  private net.

## Flow-Review Reconciliation

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

A post-crash flow review of this plan surfaced defects that change **what gets built**
(not just notes). They are folded into the phases below; this section is the index. All
`systemctl`/host-state prose below describes behaviour **inside** the OCI-baked
`inngest-cutover-flip.sh` oneshot and the `inngest-server.service` unit (delivered via
cloud-init + `inngest-bootstrap.sh`, per §Infrastructure (IaC)) — not manual operator SSH
steps. The only operator actions are out-of-band Doppler writes on `soleur-inngest/prd`.

### Cutover-flip flag state machine (resolves P0-1, P0-3, P1-4, P1-5, #5450 re-flush trap)

`INNGEST_CUTOVER_FLIP` is a **finite state machine**, not a two-value armed/done flag.
The flip oneshot (`inngest-cutover-flip.sh`, Phase C.1) branches on it and the
`inngest-server.service` ExecStartPre guard (Phase C.3) reads it:

| Flag value | Oneshot action | Timer | Terminal? |
|---|---|---|---|
| `armed` | set `flipping` → **stop** inngest-server → `FLUSHALL` → assert `DBSIZE==0` → **start** → set `done` | stays enabled | no |
| `flipping` (seen only on a mid-flip reboot) | do **NOT** re-`FLUSHALL`; ensure inngest-server started → set `done` | stays enabled | no |
| `done` | **no-op** (never re-`FLUSHALL` the now-prod durable queue) | **stays enabled** so a later `rollback` write is observable | forward-terminal |
| `rollback` | **stop** inngest-server.service (dedicated scheduler down) → set `rolled-back` | stays enabled | no |
| `rolled-back` | no-op | stays enabled | rollback-terminal |
| `aborted` | no-op (poll halts; the DBSIZE≠0 gate already wrote `exit_code:1`) | stays enabled | fail-terminal |
| unset / other | no-op exit 0 | — | — |

Load-bearing consequences vs. the pre-review plan:
1. **P0-1 rollback reachable no-SSH:** the oneshot now has an explicit `rollback` mode
   (stop the dedicated inngest), and the forward flip **no longer disables the timer** —
   the timer stays enabled forever so an operator's later `INNGEST_CUTOVER_FLIP=rollback`
   Doppler write is picked up on the next 30s poll. The three previously-contradictory
   statements (C.2 "ship disabled", C.1 step 4 "disable after flip", C.4 "prefer ship
   enabled as sole gate") are reconciled to one rule: **the timer ships enabled and stays
   enabled for the host's whole life; the FSM flag is the sole gate; no step ever disables
   the timer.** The `done`/`rolled-back`/`aborted`/unset no-ops make a benign 30s poll safe.
2. **P0-3 DBSIZE abort no longer wedges both schedulers:** the DBSIZE≠0 gate transitions
   the flag to the terminal `aborted` (poll halts — no 30s re-attempt storm, and `aborted`
   never reads as success, which only `done` does). Recovery is documented: operator runs
   `op=rollback` to re-enable web inngest (reverse-op, D.6), fixes Redis, then re-arms.
3. **P1-4 FLUSHALL ordering:** the forward path is **stop → FLUSHALL → assert DBSIZE==0 →
   start**, not FLUSHALL-then-restart. The dark server is stopped first so it cannot write
   between the flush and the DBSIZE check.
4. **P1-5 arm atomicity:** `inngest-server.service` gains an **ExecStartPre guard** that
   refuses to start when `INNGEST_POSTGRES_URI` resolves to **prod** and the flag ∉
   `{armed, flipping, done}`. This closes the race where prod URI is written to Doppler
   before the gated flip and any non-arm restart (crash / `OnBootSec` / operator) would
   otherwise bring up a **second prod scheduler** against the still-dirty dark Redis.
5. **#5450 re-flush trap:** the transient `flipping` state means a reboot mid-flip does
   **not** re-`FLUSHALL` a queue that is already on prod Postgres.

### No-SSH read paths (resolves P0-2, P1-12, P1-13)

- **P0-2 flip-state signal:** the dedicated host is deny-all-public; the operator/CI
  cannot `cat` a state file on it. The flip oneshot therefore emits its verify-state as a
  structured `logger -t inngest-cutover-flip` JSON line. Commit `c890464ce` shipped the
  **Vector journal→Better Stack shipper on the dedicated host**, but its Source 4
  (`host_scripts_journald`) forwards journald only by EXACT SYSLOG_IDENTIFIER allowlist —
  which did **not** include the cutover tags, so the marker would never reach Better Stack.
  **THIS PR adds the `inngest-cutover-flip` / `inngest-server-flip-guard` /
  `inngest-registry-probe` / `inngest-doublefire-probe` entries to that `vector.toml`
  allowlist** (the drift-guard fixture in `vector-pii-scrub.test.sh` pins the set) so the
  marker forwards off-box with no SSH. The `op=execute` SEAM instructs confirming
  `exit_code:0` via **Better Stack** (pull, per `hr-no-dashboard-eyeball-pull-data-yourself`),
  NOT by reading a file on the host. `cat-inngest-cutover-state.sh` is retained only as an
  on-host debug aid, never the operator gate. (No new Better Stack/Terraform resource —
  reuses the live journald pipe; only the allowlist entries are added.)
- **P1-12 op=verify delivery:** the runner cannot reach `10.0.1.40:8288` directly, so
  `op=verify` runs its `RunsFilterV2` exactly-once query through a **new web-host webhook
  script** `inngest-doublefire-probe.sh` + `/hooks/inngest-doublefire-probe`, registered on
  the same six webhook surfaces as the registry probe (Phase B'). Same web-host→private-net
  indirection as the 2.0 probe; no direct runner→`10.0.1.40` curl.
- **P1-13 rollback web-inngest reverse-op:** re-enabling web inngest on rollback is now an
  authored workflow op **`op=rollback`** (D.6) — the reverse of 2.2 quiesce
  (`systemctl enable --now` + restart inngest on every web host) — not an unauthored runbook
  instruction. (The runner CAN reach web hosts; only the dedicated stop is an operator
  Doppler `rollback` write.)

### Hard gates (resolves P0-3 recovery, P1-6, P1-7, P1-8, P1-9, P1-11, P2-17)

- **P1-6:** the 2.0 ABORT (registry non-empty) now carries a documented remediation/re-entry
  ("how to empty the registry and retry") in D.2 + the runbook.
- **P1-7:** quiesce (2.2) is an **explicit hard gate** — `op=execute` withholds the SEAM and
  fails loud if the post-quiesce inventory shows inngest still running on **any** host
  (incl. weight-0 web-2).
- **P1-8:** the 2.1 capture host-set and the 2.2 quiesce host-set are computed **once** and
  asserted **identical** (Sharp Edge DI-C3) — not deferred.
- **P1-9 / P2-17:** a **post-2.4 registry-NON-empty probe** (mirror of 2.0) gates `op=rearm`
  and `op=verify`; both ops precondition-check that 2.4 (app-repoint → functions registered)
  actually happened before running.
- **P1-11:** the partial-rearm branch **loudly surfaces the `Σcaptured != rearmed` delta**
  and offers a re-arm retry — verified here, not assumed from "existing".

### P2 notes folded

- **P2-14 heartbeat gap:** both pushers quiesce during the window and the dedicated host
  only begins pinging post-flip, so a Better Stack alarm gap exists across the window. The
  runbook sets a **Better Stack maintenance/suppression window** (or relies on the monitor
  grace period) for the cutover window — documented in F.1 + Observability.
- **P2-16 missed-tick auto-enumeration:** `op=verify` **auto-generates** the in-window
  missed-tick list (crons whose ticks fell in the quiesce→register gap, derived from the
  cron schedules) for `soleur:trigger-cron`, replacing manual operator enumeration.

## Implementation Phases

Order is load-bearing. The **flip oneshot must be installed on the dark host BEFORE
the cutover window** (a cloud-init/OCI change that force-replaces the singleton — done
during dark, harmless on non-prod). The empty-registry probe + workflow arms land in
the same PR.

### Phase A — Ledger follow-up (do FIRST, tiny)

- [ ] **A.1** Flip three rows in `knowledge-base/operations/expenses.md` from
  `approved-not-billing` → `active` (billing began at provision 2026-07-08):
  - Row 21 "Hetzner CPX22 (inngest)"
  - Row 22 "Hetzner Volume (inngest, 10 GB)"
  - Row 23 "Hetzner Primary IPv4 (inngest)"
  Update the trailing "(approved-not-billing → active …)" clause to past tense; keep
  the `2026-08-01` due column and the DPA note. (`wg-record-recurring-vendor-expense-before-ready`
  is already satisfied — the rows pre-exist; this is only the status transition.)

### Phase B — 2.0 pre-flight empty-registry probe (web-host, webhook-delivered)

- [ ] **B.1** Create `apps/web-platform/infra/inngest-registry-probe.sh`. Runs **on a
  web host** (which reaches `10.0.1.40:8288` over the private net; `:8288` is
  subnet-reachable per SEC-H2). POSTs the `{ functions { id } }` query to
  `http://10.0.1.40:8288/v0/gql` (parameterize `INNGEST_REMOTE_GQL_URL` default
  `http://10.0.1.40:8288/v0/gql`; fixture seam `INNGEST_PROBE_FUNCTIONS_FIXTURE`).
  Emits a single pure-JSON object on stdout: `{ "registry_empty": <bool>,
  "function_count": <int>, "function_ids": [<id>...] }`. Model shape + purity (stdout =
  JSON only, summary to `logger -t inngest-registry-probe`, `curl --max-time`, fail-LOUD
  on non-array `.data.functions`) on `inngest-inventory.sh`'s `fetch_functions`. It does
  **not** itself decide abort — it reports; the workflow arm asserts.
- [ ] **B.2** Register the probe on **every** webhook-delivery surface (mirrors the
  existing `inngest-inventory.sh` entries — the six-way registration is drift-guarded and
  fail-closed):
  - `server.tf` `triggers_replace` join (add `file("${path.module}/inngest-registry-probe.sh"),` before `local.hooks_json`, ~`:888`)
  - `push-infra-config.sh:44-56` (`"inngest_registry_probe_sh_b64": "$(base64 -w0 < …)"` — fix the trailing comma on the prior last entry)
  - `hooks.json.tmpl` `pass-environment` (`{ "source":"payload", "name":"inngest_registry_probe_sh_b64", "envname":"INNGEST_REGISTRY_PROBE_SH_B64" }`) **and** a new GET hook block `"id": "inngest-registry-probe"` → `/usr/local/bin/inngest-registry-probe.sh` (`include-command-output-in-response(-on-error): true`, HMAC + 403 mismatch — copy the `inngest-inventory` hook block)
  - `infra-config-apply.sh:33-47` FILE_MAP (`"INNGEST_REGISTRY_PROBE_SH_B64|/usr/local/bin/inngest-registry-probe.sh|755|root:root"`)
  - `infra-config-install.sh:59-73` DEST_SPEC (`["/usr/local/bin/inngest-registry-probe.sh"]="755 root:root"`) + the local mirror list `:168-182`
  - `.github/workflows/apply-deploy-pipeline-fix.yml:65-90` `on.push.paths`
  - `plugins/soleur/skills/ship/SKILL.md` — doc list `:679-684`, `DEPLOY_PIPELINE_FIX_TRIGGERS` array `:691-708`, and the `DPF_REGEX` alternation `:710`
- [ ] **B.3** Update the parity tests that fail-close on the registration set (accounting
  for **both** new web-host scripts — the registry probe AND the double-fire probe B.4):
  - `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` `TRIGGER_FILES` `:40-58`
    (add both `inngest-registry-probe.sh` and `inngest-doublefire-probe.sh`)
  - `apps/web-platform/infra/infra-config-install.test.sh` — bump the hard-coded managed-dest
    count `13 → 15` (**two** web-host scripts; `:255-256`) and the local mirror `:168-182`
  - `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — add both
    `inngest-registry-probe` and `inngest-doublefire-probe` to the hook-id existence loop (`:70`)
  - `apps/web-platform/infra/infra-config-apply.test.sh` `test_b64_delivery_parity` is automatic (parses the three surfaces) — no literal to bump, but run it.
- [ ] **B.4** Create `apps/web-platform/infra/inngest-doublefire-probe.sh` (web-host,
  2.6 delivery — **P1-12**). POSTs the exactly-once `runs(first, filter: RunsFilterV2!,
  orderBy)` query (`{ timeField: STARTED_AT, functionIDs:[…], from, until }`) to
  `http://10.0.1.40:8288/v0/gql` over the private net, paginating `pageInfo.hasNextPage`;
  emits pure JSON on stdout (`{ runs: [{ functionID, startedAt }...] }`), summary to
  `logger -t inngest-doublefire-probe`, `curl --max-time`, fail-LOUD on a non-array
  `.data.runs`. Model shape/purity on `inngest-registry-probe.sh`. Parameterize
  `INNGEST_REMOTE_GQL_URL`; fixture seam `INNGEST_DOUBLEFIRE_RUNS_FIXTURE`. It **reports**
  runs; the `op=verify` arm does the `(functionID, floor(startedAt/cron_period))` bucketing.
  Register it on the **same six webhook-delivery surfaces** as B.2 (a new GET hook block
  `"id": "inngest-doublefire-probe"` in `hooks.json.tmpl`, plus `server.tf` triggers_replace,
  `push-infra-config.sh`, `infra-config-apply.sh` FILE_MAP, `infra-config-install.sh`
  DEST_SPEC + mirror, `apply-deploy-pipeline-fix.yml` paths, `ship/SKILL.md` DPF
  list/array/regex). This is why B.3's managed-dest count is `13 → 15`.

### Phase C — 2.2b+2.3 dedicated-host cutover-flip oneshot (OCI-baked, Doppler-armed)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- [ ] **C.1** Create `apps/web-platform/infra/inngest-cutover-flip.sh` (dedicated-host).
  Host-state prose here is behaviour **inside** the OCI-baked oneshot / systemd unit +
  operator out-of-band Doppler writes on `soleur-inngest/prd` (`ignore_changes[value]`),
  NOT manual provisioning (see §Infrastructure (IaC)). Reads the flip flag from Doppler
  (`doppler run --project soleur-inngest --config prd`) and branches on the **finite state
  machine** in §Flow-Review Reconciliation. The forward (`armed`) path is ordered
  **stop → FLUSHALL → assert → start** (P1-4 — the dark server is stopped first so it
  cannot write between the flush and the DBSIZE check):
  1. **Transition `armed` → `flipping`** (flag write on `soleur-inngest/prd`) BEFORE
     touching Redis, so a mid-flip reboot never re-`FLUSHALL`s (P1-5 / #5450 trap).
  2. `systemctl stop inngest-server.service` (kill the dark scheduler's write path).
  3. `redis-cli -a "$INNGEST_REDIS_PASSWORD" FLUSHALL` (loopback `:6379`).
  4. Assert `redis-cli -a … DBSIZE` == `0` — on non-zero, **abort loud**: write a
     verify-state slot `{exit_code: 1, reason: "dbsize-nonzero"}`, do NOT start, and
     **transition the flag to the terminal `aborted`** (P0-3 — halts the 30s poll so it
     neither re-attempts forever nor is read as success; only `done` reads as success). The
     operator sees a red gate; recovery is `op=rollback` (D.6) then re-arm.
  5. `systemctl start inngest-server.service` (re-execs `doppler run … inngest start` →
     reads the now-flipped prod `INNGEST_POSTGRES_URI`).
  6. **Transition `flipping` → `done`** (flag write on `soleur-inngest/prd`).
     **Do NOT disable the timer** (P0-1) — it stays enabled so a later `rollback` write is
     observable; the `done` no-op is what prevents a reboot re-`FLUSHALL`.
  7. `rollback` path: `systemctl stop inngest-server.service` → verify-state
     `{exit_code: 0, reason: "rolled-back"}` → transition flag to terminal `rolled-back`.
  8. `flipping` (mid-flip reboot): do **NOT** FLUSHALL; ensure inngest-server started →
     set `done`. `done`/`rolled-back`/`aborted`/unset ⇒ no-op exit 0.
  Every branch **also** emits its verify-state as a structured `logger -t inngest-cutover-flip`
  JSON line (`{exit_code, dbsize, reason, flag, start_ts}`) so the on-host Vector→Better Stack
  shipper (commit `c890464ce` shipped the shipper; **this PR adds the cutover tags to the
  `vector.toml` Source 4 SYSLOG_IDENTIFIER allowlist** so the marker is actually forwarded)
  carries it off-box no-SSH (P0-2). An ERR trap makes an unhandled failure emit an
  `unexpected-exit` marker and drive the flag to terminal `aborted` (never a silent exit). A
  host-path state slot is still written for `cat-inngest-cutover-state.sh` (on-host debug aid
  only, mirror `cat-inngest-verify-state.sh`) — it is **not** the operator gate.
  Fixture seams: `CUTOVER_FLIP_FLAG`, `CUTOVER_REDIS_DBSIZE`, `CUTOVER_FLAG_SET_CMD`
  (state transitions), `CUTOVER_SYSTEMCTL_CMD` (start/stop) (CI has no redis/systemd/doppler).
  `--requirepass` password comes from `INNGEST_REDIS_PASSWORD` (`inngest-host.tf:129-135`);
  never echoed.
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- [ ] **C.2** Create `inngest-cutover-flip.service` (Type=oneshot) + `inngest-cutover-flip.timer`
  (`OnUnitActiveSec=30s`, `OnBootSec=30s`) in `apps/web-platform/infra/`. The service
  runs `/usr/local/bin/inngest-cutover-flip.sh`. **Ship the timer ENABLED and keep it
  enabled for the host's whole life** (reconciles the P0-1 contradiction — the pre-review
  plan said "ship disabled" here, "disable after flip" in C.1, and "prefer ship enabled" in
  C.4; the one rule is: timer always enabled, the FSM flag is the sole gate, no step ever
  disables the timer). The FSM's `done`/`rolled-back`/`aborted`/unset no-ops make a benign
  30s poll on the dark/live host safe, and keeping it enabled is **what makes the no-SSH
  rollback flag observable** after a forward flip. Rationale for a poll-timer (vs a push):
  the dedicated host has no inbound control channel; a Doppler-flag poll is the only no-SSH
  pull trigger.
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- [ ] **C.3** Bake into the OCI image + install path (mirror the redis-bootstrap
  delivery exactly):
  - `build-inngest-bootstrap-image.yml` — `cp` the files into `$BUILD_DIR`
    (`:177-179` block), `COPY` them in the Dockerfile heredoc (`:191-195`), and stage
    to `/tmp` in the ENTRYPOINT (`:199`). Include the new **ExecStartPre guard**
    `inngest-server-flip-guard.sh` alongside the flip trio.
  - `inngest-bootstrap.sh` — a new install block (mirror `:260-279`) that installs
    `inngest-cutover-flip.sh` + `inngest-server-flip-guard.sh` to `/usr/local/bin` and the
    unit+timer to `/etc/systemd/system`, and **`systemctl enable inngest-cutover-flip.timer`**
    (P0-1 — ships enabled; the FSM flag gates all action).
  - **ExecStartPre guard (P1-5 arm atomicity):** add `inngest-server-flip-guard.sh` and wire
    it as an `ExecStartPre=` on `inngest-server.service` (edit the unit in
    `inngest-bootstrap.sh`). It reads `INNGEST_POSTGRES_URI` + the flip flag and **exits
    non-zero (blocking start) when the URI resolves to prod and the flag ∉
    `{armed, flipping, done}`** — so a crash / `OnBootSec` / operator restart cannot bring
    up a second prod scheduler against a dirty dark Redis before the gated flip. Fixture
    seams: `GUARD_POSTGRES_URI`, `GUARD_FLIP_FLAG`.
  - Bump the OCI image tag (`inngest.tf` locals) so the dark host pulls the new image.
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- [ ] **C.4** Install-on-dark + document the operator arm sequence (runbook, Phase F).
  Getting the oneshot onto the dark host is a cloud-init/OCI change → force-replaces the
  singleton (Op C) — **done during dark on the non-prod backend, harmless**. Because the
  timer ships **enabled** (C.2/C.3), the window arm (2.2b+2.3) is **purely Doppler writes**
  on `soleur-inngest/prd` with **no `systemctl` / no-SSH step at all** (P0-1 resolved):
  1. `INNGEST_POSTGRES_URI=<prod>`
  2. `INNGEST_HEARTBEAT_URL=<betteruptime url>`
  3. `INNGEST_CUTOVER_FLIP=armed` — the enabled timer's next 30s poll picks it up and runs
     the forward FSM path (C.1). The operator confirms `exit_code:0` via **Better Stack**
     (the on-host Vector→Better Stack journald shipper carries the `inngest-cutover-flip`
     log line; P0-2) — never by SSH-ing the deny-all host.
  **Rollback (no-SSH):** a single Doppler write `INNGEST_CUTOVER_FLIP=rollback` — the still-
  enabled timer stops the dedicated scheduler on the next poll — plus `op=rollback` (D.6) to
  re-enable web inngest. The previously-flagged "one non-Doppler step" is eliminated.

### Phase D — `op=execute` + `op=verify` workflow arms

- [ ] **D.1** Add `execute`, `verify`, and `rollback` to the `op` choice list + the
  `case "$OP"` in `.github/workflows/cutover-inngest.yml`. Keep `$OP` env-only (no
  `${{ inputs.op }}` in a run shell), `concurrency.group: deploy-inngest-restart`, every new
  `curl` carrying `--max-time`, `timeout-minutes` ≥ poll budget.
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- [ ] **D.2** `op=execute` (pre-flip orchestrator, web-host-expressible spine):
  1. **2.0** — call `/hooks/inngest-registry-probe` (GET, HMAC over empty body); parse
     `registry_empty`. If `false` → `::error::` + **exit 1 (ABORT)**, and print the
     **documented remediation/re-entry** (P1-6): the dark registry must be empty before the
     flip — un-register the stray functions (stop the dark inngest-server so no dev/test
     backend re-syncs, confirm `INNGEST_POSTGRES_URI` still points at the non-prod dark
     backend, clear the registry) then re-dispatch `op=execute`. Also run the existing
     inventory logic for the BEFORE baseline + backend re-detect (M3).
  2. **2.1** — compute the **prod-scheduling host-set ONCE** (`$CUTOVER_HOSTS`) and use the
     same list for 2.1 capture and 2.2 quiesce (P1-8 / DI-C3 — the two sets must be
     **identical**; assert equality, do not defer). Run the existing `backup` snapshot
     logic, then the existing `capture` logic (mode=capture) across **every** host in
     `$CUTOVER_HOSTS`, deduped on `reminder_id` → on-host `cutover-capture.json`. Record
     `Σcaptured` for the D.4 rearm reconciliation.
  3. **2.2** — quiesce + stop + `systemctl disable` inngest on **every** host in the same
     `$CUTOVER_HOSTS` (incl weight-0 web-2; per-host fan-out via the deploy-peer path or an
     explicit host loop — mirror `op=capture`).
  4. **QUIESCE HARD GATE (P1-7)** — re-run the inventory across `$CUTOVER_HOSTS` and assert
     **zero** inngest processes running on **any** host. If any host (incl weight-0 web-2)
     still runs inngest → `::error::` + **exit 1**; **withhold the SEAM** (do not print the
     arm instructions). The SEAM is only reachable once the old scheduler is provably down
     everywhere — otherwise the flip would create a second live scheduler on prod Postgres.
  5. **SEAM** — emit a `::notice::` block with the exact operator instructions for
     2.2b+2.3 (arm the Doppler flip; confirm `exit_code:0` via **Better Stack** — the
     Vector-shipped `inngest-cutover-flip` log line — NOT by reading `cat-inngest-cutover-state`
     on the deny-all host; P0-2) and 2.4 (merge the `ci-deploy.sh` `INNGEST_BASE_URL` →
     `10.0.1.40` change + redeploy), then exit 0. **Do NOT** attempt the prod-write from CI
     (`hr-menu-option-ack-not-prod-write-auth`; `inngest-host.tf` keeps these out of CI).
- [ ] **D.3** `op=verify` (post-flip, run after 2.2b/2.3/2.4 + `op=rearm`):
  - **Precondition (P1-9 / P2-17)** — assert **2.4 actually happened**: call
    `/hooks/inngest-registry-probe` and require `registry_empty == false` (functions are now
    registered against the dedicated host). If still empty → `::error::` + exit 1 (the
    app-repoint did not land). This is the post-2.4 non-empty mirror of the 2.0 gate.
  - **2.6** — enumerate cron runs via the **`/hooks/inngest-doublefire-probe`** web-host hook
    (B.4 — the runner cannot reach `10.0.1.40` directly; P1-12), which POSTs
    `runs(first:100, filter: RunsFilterV2!, orderBy:[…])`,
    `{ from, until, timeField: STARTED_AT, functionIDs:[<cron uuid>] }`, paginating
    `pageInfo.hasNextPage`. Assert every `(functionID, floor(startedAt / cron_period))`
    bucket has exactly one run (no group > 1). Emit AFTER baseline (inventory) diff +
    health-green. `scheduled_tick` appears nowhere.
  - **Missed-tick auto-enumeration (P2-16)** — from the cron schedules + the recorded
    quiesce→register window, **auto-generate** the list of ticks that fell in the gap and
    print it as a ready-to-run `soleur:trigger-cron` set (no manual operator enumeration).
- [ ] **D.4** Post-2.4 → 2.5 rearm gating + `op=rearm` reconciliation (P1-9, P1-11, P2-17):
  - `op=rearm` **precondition-checks 2.4 happened** (same registry-non-empty probe as D.3)
    before touching prod scheduling — refuse if the registry is still empty.
  - **Partial-rearm branch (P1-11)** — after rearm, reconcile `Σcaptured` (from D.2 step 2)
    vs `rearmed` vs `Σarmed`; on any delta **fail loud** (`::error::` with the exact
    `Σcaptured != rearmed` numbers + the missing `reminder_id`s) and **offer a re-arm
    retry** (re-dispatch with the residual set). Do not rely on "existing" op=rearm silently
    covering this — verify the delta surfaces.
- [ ] **D.5** Document the **rollback sequence** in the `op=execute` SEAM + runbook (F.1),
  ordered to mirror the forward gate: (1) **stop the DEDICATED host FIRST** — operator
  Doppler write `INNGEST_CUTOVER_FLIP=rollback` (the still-enabled timer stops
  inngest-server on the next poll; confirm `rolled-back` via Better Stack, P0-1/P0-2);
  (2) repoint app `INNGEST_BASE_URL` → loopback (code revert + redeploy); (3) **re-enable
  web inngest via `op=rollback`** (D.6, the authored reverse-op — NOT a hand-written runbook
  step; P1-13). Capture file retained for a later retry. This same sequence is the P0-3
  `aborted` recovery path (DBSIZE gate tripped → web schedulers were disabled → `op=rollback`
  brings them back).
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- [ ] **D.6** Add the **`op=rollback`** arm to `.github/workflows/cutover-inngest.yml`
  (P1-13 — the authored reverse of 2.2 quiesce). It re-enables + restarts inngest on
  **every** host in the `$CUTOVER_HOSTS` set (`systemctl enable --now` + restart, the exact
  inverse of D.2 step 3), then re-runs the inventory to confirm inngest is live again on all
  hosts. The runner reaches web hosts directly (no dedicated-host dependency). `$OP` stays
  env-only; `concurrency.group: deploy-inngest-restart`; every `curl --max-time`. The
  dedicated-host stop half of rollback is the operator's `INNGEST_CUTOVER_FLIP=rollback`
  Doppler write (D.5 step 1), not a CI prod-write.

### Phase E — Tests

- [ ] **E.1** Extend `apps/web-platform/infra/cutover-inngest-workflow.test.sh`:
  `execute` + `verify` + `rollback` in the choice list; an **execute assertion** (the
  op=execute arm exists, calls the registry-probe hook, aborts on non-empty, and has the
  **quiesce hard gate** — asserts zero inngest running before the SEAM, P1-7); `verify` arm
  calls the `inngest-doublefire-probe` hook, uses `RunsFilterV2` + `timeField: STARTED_AT`,
  and contains **no** `scheduled_tick`; a **rollback assertion** (op=rollback re-enables
  inngest on the host-set); every new `curl` has `--max-time` (the existing count-parity
  assertion `:49-52` covers it — verify it still passes with the new curls); `$OP` stays
  env-only (`:38-39`); the new `inngest-registry-probe` **and** `inngest-doublefire-probe`
  hook ids are in the hook-existence loop (`:70`).
- [ ] **E.2** New `apps/web-platform/infra/inngest-registry-probe.test.sh` — fixture-driven:
  empty registry → `registry_empty:true, function_count:0`; non-empty → `false, N`;
  malformed/non-array `.data.functions` → non-zero exit (fail-LOUD, no false-clean).
- [ ] **E.3** New `apps/web-platform/infra/inngest-cutover-flip.test.sh` — fixture seams
  cover the full **FSM** (§Flow-Review Reconciliation): flag `armed` + `DBSIZE=0` ⇒
  stop→FLUSHALL→assert→start in that **order** (P1-4), flag transitions
  `armed`→`flipping`→`done`, timer **never disabled** (P0-1), verify-state `exit_code:0`;
  flag `armed` + `DBSIZE=5` ⇒ **abort**, no start, flag → terminal `aborted` (P0-3),
  verify-state `exit_code:1`; flag `rollback` ⇒ stop inngest-server, flag → `rolled-back`,
  `exit_code:0` (P0-1); flag `flipping` (mid-flip reboot) ⇒ **no** FLUSHALL, start + set
  `done` (#5450 trap); flag `done`/`rolled-back`/`aborted`/unset ⇒ no-op exit 0. Assert the
  `logger -t inngest-cutover-flip` line is emitted on every branch (P0-2).
- [ ] **E.4** New `apps/web-platform/infra/inngest-server-flip-guard.test.sh` (P1-5) —
  fixture seams `GUARD_POSTGRES_URI`/`GUARD_FLIP_FLAG`: prod URI + flag `unset` ⇒ **exit
  non-zero** (start blocked); prod URI + flag ∈ `{armed, flipping, done}` ⇒ exit 0
  (allowed); non-prod (dark) URI + any flag ⇒ exit 0.
- [ ] **E.5** New `apps/web-platform/infra/inngest-doublefire-probe.test.sh` (P1-12) —
  fixture `INNGEST_DOUBLEFIRE_RUNS_FIXTURE`: valid runs → pure-JSON `{runs:[…]}`;
  malformed/non-array `.data.runs` → non-zero exit (fail-LOUD); `curl --max-time` present.
- [ ] **E.6** Run the parity guards green: `infra-config-apply.test.sh`,
  `infra-config-install.test.sh` (managed-dest count now `15`),
  `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`.

### Phase F — Runbook + drift-guard for the flip script class

- [ ] **F.1** Extend `knowledge-base/engineering/operations/runbooks/inngest-server.md`
  §"Cutover procedure" with the gated `op=execute` → arm-flip → `op=rearm` → `op=verify`
  sequence, the exact Doppler arm commands, and:
  - the **Better Stack** command to read the flip verify-state off-box (the Vector-shipped
    `inngest-cutover-flip` log line — P0-2), explicitly **NOT** an `ssh`/`cat` on the host;
  - the **2.0 non-empty remediation** (how to empty the dark registry and re-run, P1-6);
  - the **rollback sequence** (Doppler `INNGEST_CUTOVER_FLIP=rollback` → `op=rollback`
    re-enables web inngest → app repoint to loopback; P0-1/P1-13);
  - the **`aborted` recovery** (DBSIZE gate tripped → `op=rollback` → fix Redis → re-arm; P0-3);
  - the **heartbeat suppression window** (P2-14 — set a Better Stack maintenance window for
    the cutover so the pusher-quiesce→post-flip gap does not page);
  - the bounded-outage window note. `Ref #6178`.
- [ ] **F.2** Register `inngest-cutover-flip.sh` + `inngest-server-flip-guard.sh` on the
  **cloud-init/OCI** delivery surfaces only (NOT the web-host webhook set) — dedicated-host
  scripts like `inngest-redis-bootstrap.sh` (which appears in none of the webhook surfaces).
  Confirm they are excluded from `server.tf` triggers_replace / `push-infra-config.sh` /
  FILE_MAP / DEST_SPEC (those install to web hosts). The `cat-inngest-cutover-state.sh`
  reader is an **on-host debug aid only**; the operator-facing flip-state read path is the
  Vector→Better Stack journald shipper (P0-2 — resolved, not deferred). The two web-host
  probes (`inngest-registry-probe.sh`, `inngest-doublefire-probe.sh`) go on the webhook
  surfaces per B.2/B.4 — confirm the two script classes stay disjoint.

## Files to Create

- `apps/web-platform/infra/inngest-registry-probe.sh` (web-host, 2.0)
- `apps/web-platform/infra/inngest-registry-probe.test.sh`
- `apps/web-platform/infra/inngest-doublefire-probe.sh` (web-host, 2.6 delivery — P1-12)
- `apps/web-platform/infra/inngest-doublefire-probe.test.sh`
- `apps/web-platform/infra/inngest-cutover-flip.sh` (dedicated-host, 2.2b+2.3, FSM)
- `apps/web-platform/infra/inngest-cutover-flip.service`
- `apps/web-platform/infra/inngest-cutover-flip.timer`
- `apps/web-platform/infra/inngest-cutover-flip.test.sh`
- `apps/web-platform/infra/inngest-server-flip-guard.sh` (dedicated-host ExecStartPre guard — P1-5)
- `apps/web-platform/infra/inngest-server-flip-guard.test.sh`
- `apps/web-platform/infra/cat-inngest-cutover-state.sh` (dedicated-host, on-host debug aid only)

## Files to Edit

- `.github/workflows/cutover-inngest.yml` (op=execute + op=verify + op=rollback arms)
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (execute/verify/rollback assertions)
- `knowledge-base/operations/expenses.md` (3 rows → active)
- `apps/web-platform/infra/hooks.json.tmpl` (probe + doublefire pass-env + two new GET hook blocks)
- `apps/web-platform/infra/server.tf` (triggers_replace: probe + doublefire)
- `apps/web-platform/infra/push-infra-config.sh` (probe + doublefire b64)
- `apps/web-platform/infra/infra-config-apply.sh` (FILE_MAP: probe + doublefire)
- `apps/web-platform/infra/infra-config-install.sh` (DEST_SPEC: probe + doublefire + mirror)
- `apps/web-platform/infra/infra-config-install.test.sh` (count 13→15 + mirror)
- `.github/workflows/apply-deploy-pipeline-fix.yml` (paths: probe + doublefire)
- `plugins/soleur/skills/ship/SKILL.md` (DPF list/array/regex: probe + doublefire)
- `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` (TRIGGER_FILES: probe + doublefire)
- `.github/workflows/build-inngest-bootstrap-image.yml` (bake flip trio + flip-guard into OCI)
- `apps/web-platform/infra/inngest-bootstrap.sh` (install flip trio + flip-guard on dedicated host; timer ships ENABLED; wire ExecStartPre guard on inngest-server.service)
- `apps/web-platform/infra/inngest.tf` (OCI image tag bump)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` (cutover procedure)

## Acceptance Criteria

### Pre-merge (PR — `Ref #6178`, NOT `Closes`)
- [ ] **AC-EXEC1** `cutover-inngest.yml` has `execute` + `verify` + `rollback` in the `op`
  choice; `$OP` stays env-only (no `${{ inputs.op }}` in a run shell); concurrency group is
  `deploy-inngest-restart`; every `curl` carries `--max-time` (count-parity test green).
- [ ] **AC-EXEC2** `op=execute` calls `/hooks/inngest-registry-probe` and **exits
  non-zero when `registry_empty == false`** (asserted in the workflow test).
- [ ] **AC-QUIESCE-GATE** (P1-7) `op=execute` **withholds the SEAM and exits non-zero** if
  the post-quiesce inventory shows inngest running on any host; the 2.1 capture host-set and
  2.2 quiesce host-set are the same `$CUTOVER_HOSTS` (P1-8).
- [ ] **AC-VERIFY** `op=verify` reaches the dedicated GQL via `/hooks/inngest-doublefire-probe`
  (no direct runner→`10.0.1.40` curl; P1-12), uses `runs(… filter: RunsFilterV2 …)` with
  `timeField: STARTED_AT` + `functionIDs`, buckets by `floor(startedAt / cron_period)`,
  precondition-checks 2.4 (registry non-empty; P1-9/P2-17), and auto-emits the missed-tick
  `trigger-cron` list (P2-16); the string `scheduled_tick` appears **nowhere**.
- [ ] **AC-ROLLBACK** (P1-13) `op=rollback` re-enables + restarts inngest on every
  `$CUTOVER_HOSTS` host (reverse of 2.2) and confirms via inventory.
- [ ] **AC-PROBE** `inngest-registry-probe.sh` **and** `inngest-doublefire-probe.sh` emit
  pure JSON on stdout, fail LOUD on a non-array data field, and target `10.0.1.40:8288/v0/gql`
  with `curl --max-time`; fixture tests pass.
- [ ] **AC-FLIP** `inngest-cutover-flip.sh` implements the FSM: `armed`+`DBSIZE=0` ⇒
  **stop→FLUSHALL→assert→start** (in that order; P1-4) + `armed`→`flipping`→`done`, **timer
  never disabled** (P0-1), `exit_code:0`; `armed`+`DBSIZE≠0` ⇒ **abort, no start**, flag →
  terminal `aborted` (P0-3), `exit_code:1`; `rollback` ⇒ stop + flag `rolled-back`;
  `flipping` reboot ⇒ no re-FLUSHALL (#5450); `done`/`rolled-back`/`aborted`/unset ⇒
  idempotent no-op; every branch emits the `logger -t inngest-cutover-flip` line (P0-2).
- [ ] **AC-GUARD** (P1-5) `inngest-server-flip-guard.sh` blocks start (exit non-zero) when
  the URI is prod and the flag ∉ `{armed, flipping, done}`; wired as `ExecStartPre` on
  `inngest-server.service`.
- [ ] **AC-REGISTER** both web-host probes appear on all six webhook-delivery surfaces + the
  parity tests (`ship-deploy-pipeline-fix-gate.test.ts`, `infra-config-install.test.sh`
  count `15`) are green; the flip trio + flip-guard appear on the OCI/cloud-init surfaces and
  are **absent** from the webhook surfaces.
- [ ] **AC-LEDGER** the three inngest expenses rows read `active` with past-tense clauses.
- [ ] **AC-NOSSH** no `ssh ` (or `ssh\n`) in any new runbook/discoverability command
  (`hr-no-ssh-fallback-in-runbooks`, `AC9` of the parent plan).
- [ ] **AC-NOBODY** neither new script nor the new workflow arms echo reminder bodies /
  actors / connection strings — counts + `reminder_id`s / `function_id`s only (P2-sec-a).

### Post-merge / cutover (operator, maintenance window — deferred, not this PR)
- [ ] **AC-CUTOVER** (parent plan AC11-revised) captured on every prod-scheduling host,
  `Σcaptured == rearmed == Σarmed`; app `INNGEST_BASE_URL` = `10.0.1.40` at both
  `ci-deploy.sh` sites; web inngest quiesced+disabled on ALL web hosts before the flip.
- [ ] **AC-SOAK** (parent plan AC13) — Phase-4 7-day exactly-once soak (out of scope
  here; `inngest-double-fire-6178.sh` not written in this PR).

## Domain Review

**Domains relevant:** Engineering (infra) — primary. Product: **none** (no UI surface —
`Files to Create/Edit` contain zero `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`;
mechanical UI-surface override does not fire). Finance: advisory (ledger row status flip —
no new spend; `wg-record-recurring-vendor-expense-before-ready` pre-satisfied).

### Engineering (infra / CTO lens)
**Status:** reviewed (inline — infra-only change on an already-provisioned surface).
**Assessment:** the load-bearing risk is the newly-discovered no-SSH control-channel gap
on the dedicated host. The plan closes it with a Doppler-flag-armed OCI-baked oneshot
that keeps prod-writes out of CI (operator-gated per `hr-menu-option-ack-not-prod-write-auth`)
and keeps the FLUSHALL-then-flip atomic on-host (satisfies ADR-100 Decision 6 ordering).
Second risk: the `op=execute` cannot span the operator seams in one run — resolved by
gated multi-op orchestration (a User-Challenge to the task framing; see below).

### Product/UX Gate
Not applicable — no user-facing surface (NONE).

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

### Terraform / delivery changes
No new Terraform **resources** (host already provisioned). The flip oneshot is delivered
via the existing OCI-image → cloud-init → `inngest-bootstrap.sh` install path (same as
`inngest-redis-bootstrap.sh`); the probe via the existing infra-config webhook →
`infra-config-apply.sh` install path. One `inngest.tf` OCI image-tag bump. No manual host
steps — all provisioning is Terraform + cloud-init + baked scripts.

### Apply path
- Probe: lands on web hosts via `apply-deploy-pipeline-fix.yml` (auto-applies on merge
  once registered) — no host replace.
- Flip oneshot: OCI/cloud-init change → **force-replace of the dark singleton** during
  the dark window (Op C; non-prod backend, harmless; AOF volume survives). Not in the
  per-merge `-target` set → operator `apply_target=inngest-host` dispatch.

### Distinctness / drift safeguards
Prod-only (no dev inngest host). `INNGEST_POSTGRES_URI`, `INNGEST_HEARTBEAT_URL`,
`INNGEST_CUTOVER_FLIP` carry `ignore_changes[value]` (out-of-band Doppler writes on
`soleur-inngest/prd`, never TF-minted, never a `github_actions_secret`). The flip flag's
`armed → done` self-disarm is the drift-safety against reboot re-`FLUSHALL`.

### Vendor-tier reality check
No new vendor tier. Redis loopback-bound (`inngest-redis.conf:13`); heartbeat reuses the
free-tier `betteruptime_heartbeat.inngest_prd`.

## Observability

```yaml
liveness_signal:
  what: op=execute registry-probe result + op=verify exactly-once verdict + cutover-flip verify-state slot + heartbeat FROM 10.0.1.40 after flip
  cadence: cutover ops on-dispatch; heartbeat 60s post-flip; flip-timer 30s poll during window
  alert_target: GitHub Actions run status (::error::/::notice::) + Better Stack heartbeat (post-flip) + scheduled-inngest-health.yml
  configured_in: cutover-inngest.yml (execute/verify arms) + inngest-cutover-flip.sh (verify-state) + cloud-init-inngest.yml (heartbeat timer)
error_reporting:
  destination: Actions run log (::error:: one-line, CR/LF-stripped) + on-host journald (logger -t) → Vector → Sentry/Better Stack
  fail_loud: yes
failure_modes:
  - mode: dark host registry NON-empty at pre-flight (fresh-key sync somehow succeeded / self-armed prod crons)
    detection: op=execute 2.0 registry-probe registry_empty == false
    alert_route: op=execute ABORT (exit 1) before any prod-Postgres flip
  - mode: Redis DBSIZE != 0 at flip (stale dark queue state)
    detection: inngest-cutover-flip.sh DBSIZE assertion
    alert_route: verify-state exit_code:1; oneshot refuses restart + does not disarm; operator sees red gate
  - mode: cron DOUBLE-FIRE (two schedulers on prod Postgres)
    detection: op=verify per-(functionID, floor(startedAt/cron_period)) group count > 1
    alert_route: op=verify exit 1 + Phase-4 soak follow-through (out of scope here)
  - mode: reminder loss / partial rearm
    detection: Σcaptured != rearmed != Σarmed reconciliation in op=rearm
    alert_route: op=rearm partial-rearm branch (existing)
logs:
  where: GitHub Actions run log + on-host journald (journalctl -t inngest-registry-probe / -t inngest-cutover-flip) → Vector → Better Stack
  retention: Actions default; Better Stack per plan
discoverability_test:
  command: gh run view <op=execute run id> --log | grep -E 'registry_empty|::error::|::notice::'   # no shell access to any host
  expected_output: registry_empty:true on a clean dark host; explicit ABORT line if non-empty
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-100** (`status: adopting`) — add to `## Decision` a Decision 6a: "the
dark→live Redis `FLUSHALL` + `DBSIZE==0` gate and the prod-Postgres flip restart execute
**on the dedicated host** via a Doppler-flag-armed OCI-baked oneshot
(`inngest-cutover-flip`), because the host runs no `adnanh/webhook`/`ci-deploy` and its
loopback Redis is unreachable from the web-host webhook." Add to `## Alternatives
Considered`: **force-replace-with-gated-cloud-init-FLUSHALL** (rejected: recreates the
host mid-window → longer H1 outage + 226/NAMESPACE risk during the cutover) and
**dedicated-host webhook reached via web-host fan-out** (rejected: new inbound control
plane on the singleton = larger attack surface, SEC-H2). This is an amendment, not a new
ADR — the mechanism refines ADR-100's Phase-2 without changing its Decision 1-5.

### C4 views
Read `.../diagrams/{model.c4,views.c4,spec.c4}`. The Phase-1 PR already moved the
`inngest` container to the dedicated host (`model.c4:173`, AC5). This deliverable adds no
new external actor/system/data-store — the cutover-flip oneshot is an **internal control
mechanism on the already-modeled `inngest` node**, not a new element or edge. **No C4
impact** — verified against all three files: actors (no new human/external sender),
external systems (Hetzner/Supabase/Redis/Doppler already modeled `model.c4:166-180`),
data stores (reuses `inngestPostgres`/`inngestRedis`), access relationships (`api →
inngest` unchanged this PR). Run `c4-code-syntax.test.ts` + `c4-render.test.ts` if the
amendment touches any `.c4` prose (it does not).

### Sequencing
ADR-100 amendment authored in this PR (`status: adopting` unchanged; flips to `accepted`
only at the parent plan's Phase-4 soak). Not deferred.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` (62 open) — none of the bodies
reference `cutover-inngest.yml`, `hooks.json.tmpl`, `ci-deploy.sh`, `expenses.md`,
`inngest-redis`, or `inngest-registry-probe` (checked at plan-write time).

## Decision-Challenge (headless — for `ship` to render + file as action-required)

The task framing said "author a single `op=execute` chaining 2.0→2.6" and treated 2.2b as
"just a host script." Codebase reality forced two structural deviations the operator
should confirm:
1. **The dedicated host has no no-SSH control channel** — 2.2b+2.3 are merged into a new
   OCI-baked Doppler-armed on-host oneshot (`inngest-cutover-flip`), NOT a web-host
   webhook script. This is the only way to honor `hr-no-ssh-fallback-in-runbooks`.
   *Alternative to weigh:* force-replace-with-gated-FLUSHALL (simpler wiring, worse window).
2. **`op=execute` cannot span the operator seams in one run** — it automates 2.0→2.2 and
   gates 2.2b/2.3 (arm Doppler flip) + 2.4 (ci-deploy redeploy) as printed operator
   hand-offs; `op=verify` does 2.6. If the operator prefers a literal single run, that
   requires a GitHub Environment with required reviewers (repo-settings/IaC) + a prod-write
   credential in CI — both rejected here for blast-radius.

## Test Scenarios
- **T-PROBE:** empty registry fixture → `registry_empty:true`; non-empty → `false`;
  malformed → non-zero exit.
- **T-FLIP-CLEAN:** armed + DBSIZE 0 → restart + disarm + state exit 0.
- **T-FLIP-DIRTY:** armed + DBSIZE 5 → abort, no restart, no disarm, state exit 1.
- **T-FLIP-IDEMPOTENT:** flag `done` → no-op (reboot never re-flushes).
- **T-EXECUTE-ABORT:** op=execute against a non-empty registry → exit 1 before flip.
- **T-VERIFY:** run-history fixture with one run per `(fn, bucket)` → exit 0; a duplicate
  bucket → exit 1; assert `scheduled_tick` absent.

## Sharp Edges
- **DI-C3 web-2 capture coverage:** the existing `op=capture` self-enumerates one host's
  local Redis; web-2 self-arms oneshots into **its own** Redis independent of LB weight
  (`inngest-oneshot-and-reminder-patterns.md:121`). `op=execute` 2.1 must capture from
  **every** prod-scheduling host and dedup on `reminder_id` (Σ across hosts) or AC-CUTOVER
  reconciles blind to web-2's drop. Resolve the per-host fan-out mechanism at deepen
  (deploy-peer path vs explicit host loop) — do NOT assume single-host capture suffices.
  **P1-8:** the 2.1 capture host-set and 2.2 quiesce host-set are the same computed-once
  `$CUTOVER_HOSTS` and must be **asserted identical** (D.2 steps 2–3), not deferred.
- **Flip-flag disarm is load-bearing:** if `inngest-cutover-flip.sh` restarts but fails to
  set `INNGEST_CUTOVER_FLIP=done`, the next 30s poll (or a reboot) re-`FLUSHALL`s the now-
  **prod** durable queue = catastrophic reminder loss. The disarm must be ordered
  before the timer re-fires and be idempotent; the `done`/unset no-op is the guard.
- **Timer-enable is NOT an operator step (resolved, P0-1):** the timer ships **enabled** and
  stays enabled for the host's whole life (C.2/C.3); the FSM flag is the sole gate. The arm
  sequence (C.4) is pure Doppler writes — zero `systemctl`. A benign 30s no-op poll on the
  dark host is accepted (all non-`armed` states are no-ops).
- **`op=verify` reaches the dedicated GQL over private net from a web host (resolved, P1-12)** —
  the runner cannot reach `10.0.1.40` directly (deny-all-public), so verify runs through the
  authored web-host hook `/hooks/inngest-doublefire-probe` (`inngest-doublefire-probe.sh`,
  B.4), NOT a direct runner→`10.0.1.40` curl. No longer deferred.
- **Count-parity test after adding curls:** every new `curl` in the execute/verify arms
  MUST carry `--max-time` or `cutover-inngest-workflow.test.sh:49-52`'s
  `CURL_LINES == MAXTIME_LINES` fails.
- **`infra-config-install.test.sh` hard-coded `13`:** adding the **two** web-host scripts
  (registry probe + double-fire probe) bumps it to `15` — the flip trio + flip-guard are
  dedicated-host (OCI) scripts and do NOT touch FILE_MAP/DEST_SPEC.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan`
  Phase 4.6 — this one is filled (single-user incident, CPO carry-forward).

## Research Insights
- Dedicated host control channels (verified): NO adnanh/webhook, NO hooks.json, NO
  ci-deploy on `10.0.1.40`; only cloud-init `runcmd` + systemd units
  (`cloud-init-inngest.yml` full read). `restart-inngest-server.yml` → `ci-deploy.sh:1162`
  restarts the **web-host** unit.
- Redis: loopback `127.0.0.1:6379` (`inngest-redis.conf:13`), pw `INNGEST_REDIS_PASSWORD`
  in `soleur-inngest/prd` (`inngest-host.tf:129-135`; `inngest-redis.service:23`).
- Postgres flip: `INNGEST_POSTGRES_URI` out-of-band Doppler (`inngest-host.tf:153-167`),
  read only at `ExecStart` (`inngest-bootstrap.sh:359`) → needs on-host restart.
- Heartbeat: `betteruptime_heartbeat.inngest_prd` (`inngest.tf:264-294`);
  `INNGEST_HEARTBEAT_URL` picked up by the on-host timer at next 60s ExecStart — clean
  no-SSH path (pure Doppler write).
- Webhook-delivered script registration (6 surfaces + 3 parity tests) mapped:
  `server.tf:852-895`, `push-infra-config.sh:44-56`, `hooks.json.tmpl:72-84`,
  `infra-config-apply.sh:33-47`, `infra-config-install.sh:59-73`,
  `apply-deploy-pipeline-fix.yml:65-90`, `ship/SKILL.md:679-710`; tests
  `infra-config-apply.test.sh:535`, `infra-config-install.test.sh:244-257`,
  `ship-deploy-pipeline-fix-gate.test.ts:40-58,132,151,232,346`.
- OCI dedicated-host script delivery: `build-inngest-bootstrap-image.yml:177-199`
  (cp → COPY → ENTRYPOINT /tmp stage) + `inngest-bootstrap.sh:260-279` install block.
- ci-deploy INNGEST_BASE_URL sites: `ci-deploy.sh:1341` (canary) + `:1574` (prod).
- exactly-once query: ADR-100 Decision 7 — `runs(filter: RunsFilterV2!)`,
  `timeField: STARTED_AT`, bucket `floor(startedAt / cron_period)`; `scheduled_tick`
  removed everywhere.
- Issue #6178 is OPEN (verified) — PR is `Ref #6178`, not `Closes`.
