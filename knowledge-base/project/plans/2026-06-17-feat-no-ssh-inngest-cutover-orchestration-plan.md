---
date: 2026-06-17
type: feat
issue: 5450
branch: feat-one-shot-inngest-cutover-no-ssh-5450
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed. This plan ROUTES THROUGH the no-SSH webhook-hook + infra-config
  push surface (## Infrastructure (IaC) section below) — it does NOT prescribe operator
  SSH. The `ssh ` / `ssh root@host` strings appear ONLY in prose that (a) describes the
  CURRENT SSH-requiring runbook steps being REPLACED, and (b) the AC6 no-`ssh ` grep that
  asserts their removal. The `systemctl stop/start` strings are the legitimate BODY of the
  committed host script (inngest-wiped-volume-verify.sh), delivered no-SSH via infra-config
  push and executed via an HMAC-gated webhook hook — not an operator manual step. No new
  TF secret (reuses WEBHOOK_DEPLOY_SECRET + CF-Access). hooks.json.tmpl is TF-rendered.
-->

# feat: No-SSH cutover orchestration for the Inngest durable-backend Phase 2 cutover (#5450)

## Enhancement Summary

**Deepened on:** 2026-06-17
**Sections enhanced:** Files to Edit (host-script delivery lockstep), Research Reconciliation, Risks, Implementation Phases, Network-Outage Deep-Dive added.

### Key Improvements (deepen pass, grounded against `main`)
1. **Host-script delivery is a multi-file lockstep per script, not a 2-file edit (load-bearing correction).** Shipping a NEW host script (`/usr/local/bin/<name>`) via the no-SSH `infra-config` push path requires editing FOUR files in lockstep + their tests: (a) `push-infra-config.sh` JSON payload builder (`<name>_b64`), (b) `hooks.json.tmpl` `infra-config` hook `pass-environment` block (`<NAME>_B64` envname), (c) `infra-config-apply.sh` `FILE_MAP` (`<NAME>_B64|/usr/local/bin/<name>|755|root:root`), (d) `infra-config-install.sh` `DEST_SPEC` allowlist (`["/usr/local/bin/<name>"]="755 root:root"` — **absent → rc=3 `install_rejected`**, the script silently never lands). Applies per script — the dedicated verify-status responder `cat-inngest-verify-state.sh` (P1a) ALSO rides this push, so the cutover ships ~3-4 new host scripts each needing the lockstep. This mirrors `2026-06-05-new-inngest-cron-requires-five-registry-lockstep`. Verified at `infra-config-install.sh:59-67`, `infra-config-apply.sh:33-41`, `push-infra-config.sh:32-42`. PLUS a root-managed sudoers grant (B3) that is NOT on this push path. The `## Files to Edit` list and Phases are corrected below.
2. **`(b) is structurally impossible for step 5` — confirmed.** A containerized Next.js route has no host `systemctl`/`rm -rf /var/lib/inngest` capability; only `infra-config-install.sh`-style root-escalation via the webhook handler can. Approach (a) for both steps stands.
3. **`no new secret` claim — confirmed.** The chosen path reuses `WEBHOOK_DEPLOY_SECRET` (HMAC) + CF-Access (used by `restart-inngest-server.yml`). No `INNGEST_MANUAL_TRIGGER_SECRET`, no new TF random/doppler resource.
4. **inngest bind confirmed `0.0.0.0:8288`** (`inngest-bootstrap.sh:12,180`) — the host-side scripts curl `127.0.0.1:8288` directly; no firewall change needed (loopback intent preserved by host firewall).

### Verify-the-Negative pass (single-user-incident threshold)
- "no client-env exposure": **not-applicable** — no `NEXT_PUBLIC_*` in scope; the orchestration is host scripts + a GHA workflow + runbook/ADR, zero app-client surface.
- "(b) structurally impossible for step 5": **confirms** — `infra-config-install.sh` is the ONLY root-escalation path; a route cannot wipe `/var/lib/inngest`.
- "no new secret needed": **confirms** — `push-infra-config.sh`/`restart-inngest-server.yml` both auth via `WEBHOOK_DEPLOY_SECRET` + CF-Access only.

## Deepen-Plan Review Findings (4-agent panel — RESOLVE BEFORE /work)

A 4-agent panel (architecture-strategist, security-sentinel, user-impact-reviewer, code-simplicity-reviewer) reviewed the deepened plan. Findings are folded in below; the load-bearing ones reshape scope.

### BLOCKING (single-user-incident keystone)

- **B1 — The durable-backend precondition guard (AC2/R3) is the WRONG invariant (security CRITICAL, confirmed at `inngest-bootstrap.sh:180`).** The `--postgres-uri` flag is *unconditionally* in the prod unit `ExecStart` post-#5459, so "refuse if `--postgres-uri` absent" ALWAYS passes — it never fires, and "durable backend present" does NOT mean "no real reminders armed." The verify could wipe a backend holding the operator's #5432 reminder. **Fix:** the destructive verify's real safety gate is **"no non-throwaway armed reminders present right now"** — it MUST call the enumeration first and abort loudly unless the armed set is empty (or contains only its own throwaway marker). AC1 (enumerate) and AC2 (verify) become *sequenced*, not independent. Keep the postgres-uri check only as a secondary "is this a durable host" sanity assert. **The test must assert the verify ABORTS when a real future reminder is present** (that is the test mapping to the failure mode).
- **B2 — The re-arm executor is missing entirely; re-arm has 3 silent-drop vectors (user-impact CRITICAL).** The plan builds enumerate + verify but ships NO re-arm path — yet re-arm is the half that actually makes a dropped reminder fire. Three uncovered drops: (i) the re-arm record `{reminder_id, fire_at, action}` omits the Inngest dedup keys `id`(=reminder_id) and `ts`(=`Date.parse(fire_at)`) — a re-arm without them double-fires a non-idempotent comment (`route.ts:128-133`); (ii) it omits `actor:"platform"` — the re-arm POST is 400-rejected (`route.ts:106-108`), reminder silently never re-arms; (iii) re-arm routes through the quiesce-gated `schedule-reminder` endpoint — if attempted before the operator clears `INNGEST_CUTOVER_QUIESCE` it gets 503 and is lost (`route.ts:74-79`). **Fix:** AC1's enumeration record MUST carry the full re-armable payload (`id`/`ts`/`actor`/`action`); add a re-arm executor (or AC asserting the enumeration output pipes directly to `schedule-reminder` post-quiesce-clear) with an ordering guard so re-arm cannot 503 silently. Also: the enumerate→re-arm WINDOW race (a reminder fires between enumerate and re-arm) needs the dedup `id`/`ts` to be safe — the `runs` cross-ref at enumerate time alone does not cover it.
- **B3 — Missing service stop/start sudoers grant (security HIGH, `deploy-inngest-bootstrap.sudoers:28`).** Only the `restart inngest-server.service` command is granted; the verify is stop→wipe→start (can't be a restart — the wipe happens while down). As specified the stop fails (no grant) OR an over-broad grant is added mid-`/work`. Sudoers is NOT webhook-deliverable (root-managed via cloud-init + handler-bootstrap bridge per `infra-config-install.sh:48-51`). **Fix:** add two pinned `Cmnd_Alias` entries (a service-stop and a service-start alias for `inngest-server.service`, no wildcard) with their root-managed delivery path as an explicit (automated) lockstep item. NOTE: the wipe itself (`rm -rf /var/lib/inngest/*`) needs NO root — the dir is `deploy:deploy` 0750 (`inngest-bootstrap.sh:103-105`).

### SCOPE FORK (code-simplicity dissent vs. the task's named deliverables) — RESOLVED: drain-first

- **F1 — The runbook's OWN "dual-run-drain" fallback (`inngest-server.md:250`) is simpler than enumerate+re-arm for N=1.** Simplicity argues: at one armed reminder, draining (run the old SQLite server until its armed reminders fire; new arming already quiesced via the shipped flag) is a wait, not an engineering deliverable — and it dissolves B1/B2 (no re-arm → no double-fire, no payload-completeness, no missing executor). Architecture/security/user-impact all noted the re-arm path is the risk concentrator. **Resolution (plan author):** the task directive explicitly scopes "a no-SSH enumeration + re-arm path" — do NOT silently delete it. BUT restructure so **dual-run-drain is the documented DEFAULT cutover path** (simplest, no re-arm risk), and the **enumerate+re-arm path is the no-SSH FALLBACK** for when drain is not viable (e.g., many armed reminders, or old+new server collision on already-armed events). This satisfies the directive (the no-SSH enumerate+re-arm capability IS built + tested) while honoring the simpler default. Phase 0 MUST verify drain viability (can the old SQLite server keep firing already-armed reminders post-cutover without colliding with the new backend?) — if drain is viable, it is step 2's primary instruction.
- **F2 — The destructive wiped-volume verify is largely redundant with the existing `verify_inngest_health` HARD gate (`ci-deploy.sh:233-308`)** which already asserts the durable flags + redis-active + `/health` + `/v1/functions` cron on every deploy, and spike 0.2 ALREADY ran the wiped-volume test (durable Redis: survived). **Resolution:** downgrade — the no-SSH verify SHOULD prefer the existing non-destructive `verify_inngest_health` (already runs in step 4's deploy) + spike 0.2 evidence. The destructive wiped-volume verify is retained ONLY as an explicit, opt-in, emptiness-gated (B1) operation for the operator who wants the end-to-end proof — NOT a default cutover step. This shrinks the destructive blast radius and the permanent-hook footprint. The task's "no-SSH wiped-volume verify equivalent" is satisfied by the gated opt-in script; its DEFAULT recommendation in the runbook is the non-destructive health gate.

### P1/P2 (architecture + security, fold into /work)

- **P1a — Wiped-volume verify cannot reuse `/hooks/deploy-status`** (it reads only `ci-deploy.state`, written only by `ci-deploy.sh`). Needs a DEDICATED status responder (`cat-inngest-verify-state.sh` + `/hooks/inngest-verify-status` GET) mirroring the `infra-config-status` triple → the delivery lockstep is **6 files**, not 5 (the responder itself rides the push). Also: put `cutover-inngest.yml` in the SAME concurrency group as deploy/restart (they share the state slot).
- **P1b — The keystone `eventsV2` payload field + `runs` cross-ref shape is UNVERIFIED** against the self-hosted Inngest `v0/gql` surface. Make Phase 0.2/0.3 a BLOCKING gate with a written fallback (reconstruct from SDK-side ledger, or block loudly), and pin the verified field name + `runs` status enum into the plan/spec BEFORE writing the script (the test fixture needs the real shape).
- **P2-sec-a — Enumeration GET leaks issue numbers + comment bodies into CI logs.** The workflow should emit counts + reminder_ids to the log, fetch full bodies only at re-arm; or `::add-mask::`. Note in Legal/Observability that comment bodies transit CI logs. Build the GraphQL body with `jq -n --arg` (NOT shell string interpolation) — injection-safe, mirrors `cat-deploy-state.sh`.
- **P2-sec-b — The throwaway verify reminder must NOT post to a real user issue.** Both allowlisted action types (`issue-comment`, `named-check`) target a real issue. Constrain the throwaway action to a dedicated sentinel issue or an assert-via-`runs`-only path that posts no comment; test asserts zero comments on any real issue.
- **P2-sec-c — Specify post-cutover removal/disarm** of the destructive hook (a permanent root-escalating wipe hook is a standing liability) — file a follow-up or fence behind `INNGEST_CUTOVER_QUIESCE`.
- **P2-arch — Corrections:** ADR-030 frontmatter is `status: accepted` (not `adopting` — the `adopting` behavior is prose; the amend keeps `accepted`); name the full filename `ADR-030-inngest-as-durable-trigger-layer.md` (there are TWO ADR-030 files). The container reaches inngest via `host.docker.internal`, NOT `127.0.0.1` (the `0.0.0.0` bind exists because `127.0.0.1` blocked the container, #4017) — host-side `127.0.0.1:8288` is correct, the (b)-rationale wording at the decision table is not. Re-anchor all `## Files to Edit` line numbers against `main` at /work. Add the `push: paths:[<self>]` registration trigger to `cutover-inngest.yml` (mirrors `restart-inngest-server.yml:20-23`) so the new workflow registers in the Actions UI (R4).
- **P2-workflow — `workflow_dispatch` op input must be `type: choice` (`options: [enumerate, verify-wiped-volume]`)**, not a free-string regex; keep any `fire_at`/window input OFF `date -d` (validate ISO-instant regex).

## Overview

The durable-backend implementation (Supabase Postgres `--postgres-uri` + self-hosted AOF Redis `--redis-uri`, image `vinngest-v1.1.14`) **merged 2026-06-17** (PR #5459). The production host is still on the old bundled **SQLite + in-memory Redis** backend; the live cutover has not run. Issue **#5450 is OPEN** (verified `gh issue view 5450 --json state` → `OPEN`).

The cutover runbook (`knowledge-base/engineering/operations/runbooks/inngest-server.md` §"Cutover procedure (Phase 2 …)", lines 270–330) has **two host-side steps that require SSH**, which violates `hr-no-ssh-fallback-in-runbooks` and means the cutover **cannot be executed autonomously today**:

- **Step 2 — enumerate armed-but-unfired reminders.** Written as on-host `curl http://127.0.0.1:8288/v0/gql` (loopback GraphQL `eventsV2`) → requires a remote shell on the Hetzner box.
- **Step 5 — wiped-volume verify.** Written as "arm a throwaway future reminder, **recreate the inngest container with a wiped local volume**, confirm it still fires + `/health` 200 + `/v1/functions` ≥1 cron" → requires a remote shell (host `systemctl` + `rm -rf /var/lib/inngest` + container recreate).

This plan **builds and tests** the no-SSH orchestration so the operator can trigger the cutover via CI afterward. **It does NOT execute the live prod cutover.**

**Time-sensitivity:** at least one armed future reminder exists (the #5432 otel-rebase reminder armed for 2026-06-18 — issue #5432 confirmed OPEN). A naive fresh-Postgres cutover silently drops it. Armed reminders live **ONLY** in Inngest state — there is no app-side reminder ledger (`schedule-reminder/route.ts` only emits `reminder.scheduled`; verdict 0.4 in the runbook confirms no `scheduled_reminders` migration). The enumeration → re-arm path is the keystone that prevents the single-user-incident-class silent loss.

### Pre-flight facts (verified read-only this session)
- Step 0 done: `INNGEST_REDIS_PASSWORD` (48-char) + `INNGEST_POSTGRES_URI` present in Doppler prd; `INNGEST_CUTOVER_QUIESCE` clear (arming open). `vinngest-v1.1.14` OCI image built OK, not deployed.
- PR #5459 MERGED `2026-06-17T14:37:13Z`. No dedicated inngest deploy/restart since 2026-06-12.
- `INNGEST_CUTOVER_QUIESCE` gate already wired in `schedule-reminder/route.ts:40-79` (503 + `Retry-After: 120` when set) — the arming-pause half of the cutover is shipped; only the no-SSH **host-side** halves remain.

## Architectural Decision — approach (a) vs (b), and the chosen shape

The task offered two candidate mechanisms. The decision is **NOT a clean binary**; the two steps have different host-capability requirements:

| Step | Operation | Can a Next.js internal route do it? | Verdict |
|---|---|---|---|
| 2 — enumerate + re-arm | curl loopback `127.0.0.1:8288/v0/gql` + `inngest.send` re-arm | **Yes** — the `soleur-web-platform` container reaches inngest via `host.docker.internal` (P2-arch: NOT `127.0.0.1` from the container — the `0.0.0.0` bind exists *because* `127.0.0.1` blocked the container, #4017; host-side scripts curl `127.0.0.1:8288` correctly); the app already holds the wired Inngest client | feasible via (b), but see below |
| 5 — wiped-volume verify | host `systemctl stop inngest-server` + wipe `/var/lib/inngest` + restart + assert `/health`/`/v1/functions` | **No** — a containerized route has no host service-manager / host-FS capability over `/var/lib/inngest` | **(b) is structurally impossible**; only the host-exec webhook path (a) works |

**Step 5 forces approach (a)** (host-side script via the deploy webhook). Splitting step 2 onto a *different* mechanism (b — a new internal endpoint with a second auth primitive + second test surface) to save one curl is a net complexity loss at `single-user incident` threshold. **Decision: approach (a) for BOTH steps**, using the established **new-webhook-hook** shape (NOT the `ci-deploy.sh` 4-field parser):

- The webhook surface (`hooks.json.tmpl`) already has **four hooks**, each a dedicated `execute-command` host script. The `infra-config` hook (`hooks.json.tmpl:29-57` → `infra-config-apply.sh`) proves new hooks are first-class; the `deploy-status` / `infra-config-status` GET hooks (`include-command-output-in-response: true`) prove the **read-only-output-via-GET** pattern that step 2's enumeration result needs.
- This avoids the repo-research agent's stated blocker ("`ci-deploy.sh` hard 4-field validation"): we do **not** touch `ci-deploy.sh`'s parser. We add a new HMAC-gated hook + a new idempotent host script, mirroring `cat-deploy-state.sh` (read-only GET) for enumeration and an `infra-config`-style POST hook for the destructive wiped-volume verify.

**Why not (b) for step 2 anyway?** (b) keeps Inngest business logic in the app (code locality), but: (i) it still leaves step 5 on (a), so we'd ship two mechanisms; (ii) the enumeration is a one-time cutover op, not an ongoing app feature — it belongs in the host-ops surface alongside `restart-inngest-server.yml`, not as a permanent prod-write route; (iii) a permanent `/api/internal/inngest/*` route widens the always-deployed attack surface for a one-shot migration. The webhook hooks are HMAC-gated and the scripts can be **removed post-cutover** (or gated behind the quiesce flag) — a smaller permanent footprint.

The **GitHub Action** is a `workflow_dispatch` workflow mirroring `.github/workflows/restart-inngest-server.yml` (HMAC-signed POST to `deploy.soleur.ai/hooks/<hook>` + CF-Access headers + poll). Two dispatch inputs select the operation (`enumerate` | `verify-wiped-volume`), or two sibling workflows — decided in Phase 2 (see Sharp Edges on `workflow_dispatch`-default-branch).

## Research Reconciliation — Spec vs. Codebase

| Spec / runbook claim | Codebase reality | Plan response |
|---|---|---|
| Runbook step 2 `eventsV2` query selects `id name receivedAt` and says "re-send it to the NEW server" | That query returns **no payload** — `data`/`raw` (reminder_id, fire_at, action) is NOT selected. You cannot reconstruct `inngest.send({name, id, ts, data})` from `id/name/receivedAt` alone. | The new enumeration script MUST select the full event payload (`raw`/`data`) AND cross-ref `runs` to drop already-fired events. Captured as R1 + Sharp Edge. The current runbook query is **incomplete** and would silently produce un-re-armable output. |
| "approach (a) requires hardcoding a 4-field command in `ci-deploy.sh`" (repo-research agent) | `hooks.json.tmpl` shows new hooks (`infra-config`) are first-class dedicated scripts; `ci-deploy.sh`'s parser is untouched by adding a hook. | Add new hooks, not new `ci-deploy.sh` actions. The 4-field constraint is irrelevant. |
| Step 5 "recreate the inngest container with a wiped local volume" | Inngest runs as a **systemd unit** (`inngest-server.service`, `inngest-bootstrap.sh:40`), not a docker container in the usual sense; the "local volume" is `/var/lib/inngest` (SQLite + version file). | Host script does service-stop → wipe `/var/lib/inngest` → service-start → assert. "Container recreate" in the runbook prose is loose; the real op is unit-restart-with-wiped-state. |
| inngest is "loopback-only" (feature description / ADR-030 framing) | Binds `0.0.0.0:8288`; loopback intent preserved via host firewall (`inngest-bootstrap.sh:12-20`). | Enumeration script curls `127.0.0.1:8288` on the host (fine); the route-based (b) path was also feasible but rejected per the decision above. |
| `INNGEST_MANUAL_TRIGGER_SECRET` would auth a new endpoint | TF-generated random in `inngest.tf`; already in Doppler prd. | Only relevant if (b) were chosen; (a) uses the existing `WEBHOOK_DEPLOY_SECRET` HMAC + CF-Access. No new secret needed for the chosen path. |

## User-Brand Impact

**If this lands broken, the user experiences:** a future-dated reminder they set (e.g., the #5432 otel-rebase reminder armed for 2026-06-18) **silently never fires** after the cutover — the action they scheduled simply does not happen, with no error surfaced. The orchestration's whole job is to enumerate-and-re-arm those reminders; if the enumeration returns un-re-armable output (missing payload) or the re-arm double-fires a non-idempotent comment, the user sees either a dropped action or a duplicate spam comment on their issue.

**If this leaks, the user's workflow is exposed via:** the enumeration output contains armed `reminder.scheduled` payloads (issue numbers, comment bodies, check params). Reminders are operator/platform-scoped (`actor: "platform"`), but the HMAC + CF-Access gate is the trust boundary; an unauthenticated leak of the enumeration would expose pending operator actions. The destructive wiped-volume verify, if mis-triggered against the live post-cutover server with real armed reminders, would **destroy** them (the rollback tripwire, Phase 2 step 7).

**Brand-survival threshold:** single-user incident (a dropped armed reminder is a silent user-facing miss).

> **CPO sign-off required at plan time before `/work` begins.** Invoke CPO domain leader if not already covered by Phase 2.5 carry-forward, or confirm CPO has reviewed the #5450 brainstorm framing. `user-impact-reviewer` will be invoked at review-time (review/SKILL.md conditional-agent block).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 — enumeration script exists + is payload-complete + paginates to exhaustion (B2, P1b, P2-sec-a).** A new host script (e.g. `apps/web-platform/infra/inngest-enumerate-reminders.sh`) queries `127.0.0.1:8288/v0/gql` `eventsV2(filter:{from, eventNames:["reminder.scheduled"]})` selecting the **full re-armable payload** — the Inngest `id` (=reminder_id), `ts` (=`Date.parse(fire_at)`), and the event `data` (`reminder_id`, `fire_at`, `actor:"platform"`, `action`) — cross-refs `runs` to drop already-fired events, **paginates the cursor to exhaustion** (NOT a single `first:N` page — a far-future reminder beyond page 1 must still be captured), and emits JSON re-arm records carrying `{id, ts, reminder_id, fire_at, actor, action}` to stdout. The GraphQL body is built with `jq -n --arg` (no shell string interpolation). Verify via shellcheck + a unit test (`*.test.sh`): already-fired excluded; future-dated included WITH the full payload AND dedup keys; a page-2 event still captured. **Phase 0.2/0.3 is a BLOCKING gate** that pins the verified `eventsV2` payload field name + `runs` status enum before the script is written (P1b).
- **AC2 — re-arm executor (B2 — the missing keystone half).** A no-SSH re-arm path consumes AC1's records and re-emits each via `inngest.send` carrying the original `id` + `ts` (so Inngest dedups against any survivor — no double-fire) and the full `data` including `actor:"platform"` (so the `schedule-reminder` route does not 400-reject). It runs AFTER the operator clears `INNGEST_CUTOVER_QUIESCE` (an ordering guard refuses-loud, not silent-503, if quiesce is still set). Verify: a test round-trips an AC1 record through `validateReminderAction` + the route's `actor` check + asserts the dedup `id`/`ts` are preserved.
- **AC3 — wiped-volume verify script: opt-in, emptiness-gated, non-default (B1, F2, P2-sec-b).** A new host script (e.g. `apps/web-platform/infra/inngest-wiped-volume-verify.sh`) is an **explicit opt-in** end-to-end durability proof — NOT a default cutover step (the default verify is the existing non-destructive `verify_inngest_health` HARD gate, F2). Its safety gate is **"no non-throwaway armed reminders present"**: it calls AC1's enumeration first and **aborts loudly unless the armed set is empty (or only its own throwaway marker)** — the `--postgres-uri` check is only a secondary sanity assert (B1: that check ALWAYS passes post-#5459 and protects nothing). The throwaway reminder targets a **dedicated sentinel issue or an assert-via-`runs`-only sink that posts NO comment** (P2-sec-b). It then service-stops inngest (via the pinned sudoers alias, B3), wipes `/var/lib/inngest`, service-starts, and asserts: (a) the throwaway fired (via `runs`), (b) `/health` 200, (c) `/v1/functions` ≥1 cron. Verify via shellcheck + `*.test.sh`: **the verify ABORTS when a real future reminder is present** (the test mapping to the failure mode); the throwaway posts zero comments on any real issue; marker-id uniqueness.
- **AC4 — webhook hooks + dedicated verify status responder (P1a).** `hooks.json.tmpl` gains an `inngest-enumerate-reminders` GET hook (`include-command-output-in-response: true`, `cat-deploy-state.sh`-style) and an `inngest-wiped-volume-verify` POST hook (HMAC-gated, async 202). The destructive verify reports terminal status via a **DEDICATED** `cat-inngest-verify-state.sh` + `/hooks/inngest-verify-status` GET responder + its own state file (it CANNOT reuse `/hooks/deploy-status`, which reads only `ci-deploy.state` — P1a), mirroring the `infra-config-status` triple. Verify: `jq . hooks.json.tmpl` parses; a test asserts all three new hook ids exist with HMAC `trigger-rule`.
- **AC5 — workflow_dispatch driver exists.** `.github/workflows/cutover-inngest.yml` mirrors `restart-inngest-server.yml`: HMAC-signs the payload with `WEBHOOK_DEPLOY_SECRET`, sends CF-Access headers, with `timeout-minutes` ≥ poll budget, `permissions: contents: read`, `--max-time` on every curl, AND a `push: branches:[main] paths:[<self>]` registration trigger (so the new workflow appears in the Actions UI, mirroring `restart-inngest-server.yml:20-23`). The op input is `type: choice` (`options: [enumerate, verify-wiped-volume]`) — NOT a free-string (P2-workflow). It is in the **SAME `concurrency.group` as deploy/restart** (they share the state slot — P1a). For the destructive verify it polls `/hooks/inngest-verify-status` (NOT deploy-status) for terminal state with the `start_ts ≥ TRIGGER_TS - 60` freshness guard.
- **AC6 — runbook rewritten drain-first, tripwire intact (F1, F2).** Runbook §"Cutover procedure": step 2 documents **dual-run-drain as the DEFAULT** (run old SQLite until armed reminders fire; new arming already quiesced) with `gh workflow run cutover-inngest.yml --field op=enumerate` as the no-SSH **fallback** to enumerate + re-arm when drain is not viable; step 5's DEFAULT verify is the existing non-destructive `verify_inngest_health` (runs in step 4's deploy), with `op=verify-wiped-volume` as the opt-in destructive proof. The **rollback tripwire** (step 7) is preserved verbatim: revert-to-SQLite is data-safe ONLY before any real reminder is armed against Postgres; forward-fix-only after; wipe old `/var/lib/inngest` on a committed cutover. Verify: `grep -c 'ssh ' <step-2-and-5-region>` returns 0 (with `--exclude` of THIS plan + spec); the tripwire paragraph byte-preserved.
- **AC7 — no-SSH discoverability.** `grep` over the rewritten cutover §steps 2 and 5 contains no `ssh ` (trailing space) verb. The new scripts' failure paths are reachable from the workflow run log + the verify-status JSON (no remote shell to diagnose).
- **AC8 — observability.** New host scripts emit structured `logger -t` lines (mirroring `ci-deploy.sh`/`cat-deploy-state.sh`) AND surface terminal status in the dedicated verify-state JSON so a failed enumeration/verify is visible in the workflow log without a remote shell. The destructive verify reports a non-zero terminal `exit_code` on failure that the workflow `::error::`-annotates. The enumeration workflow emits **counts + reminder_ids** to the run log (not full comment bodies — P2-sec-a).
- **AC9 — typecheck/lint clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (if any TS touched); `shellcheck` clean on the new `.sh`; the relevant `*.test.sh` pass (including the FILE_MAP↔DEST_SPEC parity guards for the 6-file delivery lockstep).

### Post-merge (operator) — the live cutover (OUT OF SCOPE for THIS PR; runs after)

- **AC10 — (Ref only, not a deliverable of this PR)** Operator triggers `cutover-inngest.yml` per the rewritten runbook to execute the actual cutover. Tracked under #5450; **this PR uses `Ref #5450`, not `Closes #5450`** (the issue closes only after the live cutover succeeds — ops-remediation `Closes`-vs-`Ref`). Automation feasibility: the cutover trigger IS automatable via `gh workflow run` post-merge, but executing the live prod cutover is explicitly OUT OF SCOPE of this task per the directive.

## Files to Create

- `apps/web-platform/infra/inngest-enumerate-reminders.sh` — host-side read-only enumeration (payload-complete + dedup-key-complete eventsV2 + runs cross-ref + cursor pagination, `jq --arg` body). Model: `cat-deploy-state.sh`.
- `apps/web-platform/infra/inngest-enumerate-reminders.test.sh` — mocked-GraphQL unit test (already-fired excluded; future-dated included w/ full payload + `id`/`ts`; page-2 captured).
- **Re-arm executor (AC2 — the missing keystone half).** Either a host script `apps/web-platform/infra/inngest-rearm-reminders.sh` (re-emits AC1 records via the host's inngest event endpoint preserving `id`/`ts`/`actor`) + test, OR an AC asserting the enumeration JSON pipes directly into `POST /api/internal/schedule-reminder` post-quiesce-clear. Decide in Phase 1 (the route already validates `actor` + dedups on `id`/`ts`).
- `apps/web-platform/infra/inngest-wiped-volume-verify.sh` — host-side OPT-IN destructive verify (emptiness gate via AC1 enumeration + sentinel-issue/runs-only throwaway + service-stop-via-pinned-sudoers + wipe + service-start + assert).
- `apps/web-platform/infra/inngest-wiped-volume-verify.test.sh` — ABORT-when-real-reminder-present test + zero-comment-on-real-issue + marker-uniqueness.
- `apps/web-platform/infra/cat-inngest-verify-state.sh` (+ `.test.sh`) — DEDICATED verify status responder for `/hooks/inngest-verify-status` (P1a — cannot reuse deploy-status). Model: `cat-infra-config-state.sh`.
- `.github/workflows/cutover-inngest.yml` — `workflow_dispatch` driver (`type: choice` op input) + self-path `push` registration trigger, mirroring `restart-inngest-server.yml`.

## Files to Edit

- `apps/web-platform/infra/hooks.json.tmpl` — TWO edits: (i) add `inngest-enumerate-reminders` (GET, output-in-response) + `inngest-wiped-volume-verify` (POST, async 202) hooks, both HMAC-gated; (ii) add the two new scripts' `<NAME>_B64` envnames to the EXISTING `infra-config` hook's `pass-environment` block (so they ride the infra-config push that delivers them to the host).
- **Host-script delivery lockstep (per new `/usr/local/bin/<name>.sh`, deepen-corrected — see Enhancement Summary #1; re-anchor line refs against `main` at /work, P2-arch).** To land each new host script (enumerate, re-arm-if-host-script, wiped-volume-verify, AND the dedicated `cat-inngest-verify-state.sh` responder) via the no-SSH `infra-config` push, edit in lockstep:
  - `apps/web-platform/infra/push-infra-config.sh` (payload builder ~L32-42) — add `"<name>_b64": "$(base64 -w0 < "${INFRA_DIR}/<name>.sh")"`.
  - `apps/web-platform/infra/hooks.json.tmpl` (`infra-config` hook `pass-environment` ~L38-45) — add the `<NAME>_B64` envname.
  - `apps/web-platform/infra/infra-config-apply.sh` (`FILE_MAP` ~L33-41) — add `"<NAME>_B64|/usr/local/bin/<name>.sh|755|root:root"`.
  - `apps/web-platform/infra/infra-config-install.sh` (`DEST_SPEC` ~L59-67) — add `["/usr/local/bin/<name>.sh"]="755 root:root"` (**absent → rc=3 `install_rejected`; the script silently never lands**).
  - Their `*.test.sh` lockstep guards — bump/extend so the FILE_MAP↔DEST_SPEC parity assertion passes (the maps MUST stay in lockstep per `infra-config-install.sh:56-58`).
- **Sudoers grant for the destructive verify (B3 — root-managed, NOT webhook-deliverable).** `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` — add two pinned, wildcard-free `Cmnd_Alias` entries (a service-stop + a service-start alias for `inngest-server.service`; only `restart` exists today at L28). Delivery is via cloud-init `write_files` + the handler-bootstrap bridge (mirrors #4827) — specify the automated path; test asserts no wildcard. (The wipe itself needs no root.)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — rewrite §"Cutover procedure" steps 2 & 5 (drain-first default per F1/F2); preserve step 7 rollback tripwire verbatim.
- `apps/web-platform/infra/cat-deploy-state.sh` (+ its test) — IF the wiped-volume verify reports terminal status through the existing deploy-state slot (AC7), extend the state schema; otherwise add a dedicated status responder. Decide in Phase 2.
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` — see Architecture Decision section below.

## Open Code-Review Overlap

To be populated at /work after the Files lists are frozen (run the `gh issue list --label code-review` two-stage `jq --arg` sweep over each path). Initial scan: None known at plan time.

## Architecture Decision (ADR/C4)

This plan does **not** make a *new* architectural decision — it implements the cutover mechanism for a decision already recorded in **`ADR-030-inngest-as-durable-trigger-layer.md`** (P2-arch: full filename — there are TWO ADR-030 files; frontmatter `status: accepted`, with prose describing `adopting`-until-verified behavior; the amend KEEPS frontmatter `accepted`). The **no-SSH host-operation surface** (a new webhook hook class for one-time-migration host ops, distinct from `deploy`/`restart`/`infra-config`) is a small extension worth recording.

- **### ADR** — Amend **`ADR-030-inngest-as-durable-trigger-layer.md`** (the durable-backend ADR) with a short `## Cutover orchestration` note: the cutover's host-side enumeration + wiped-volume verify run through **HMAC-gated webhook hooks** (not SSH, not the `ci-deploy.sh` 4-field parser), mirroring `infra-config` + `cat-deploy-state.sh`. No new standalone ADR — this is the execution mechanism for ADR-030's adopted decision. Author via `/soleur:architecture` as an in-scope task of THIS feature (not a deferred issue).
- **### C4 views** — Likely no C4 model change: the Inngest container/component already exists in the Container view; the webhook hook surface is an existing edge (`deploy.soleur.ai` → host). If a Component-view `.c4` enumerates the webhook hooks, add the two new hooks; otherwise skip. Confirm at /work via `git grep -l 'deploy.soleur.ai\|hooks/deploy' knowledge-base/**/*.c4` — edit `.c4` directly if a hook list exists.
- **### Sequencing** — The ADR amendment is authored in THIS PR (mechanism is real at merge); the "cutover executed" state is post-merge (operator-triggered), noted as `status: adopting` until the live cutover lands.

## Implementation Phases

### Phase 0 — Preconditions (verify, no writes)
1. Re-read `ci-deploy.sh` (command dispatch + `verify_inngest_health`), `cat-deploy-state.sh`, `hooks.json.tmpl`, `restart-inngest-server.yml`, `push-infra-config.sh` + `infra-config-install.sh` (the host-script delivery path).
2. Confirm the `eventsV2` payload field name (`data` vs `raw`) against inngest v1.19.4 GraphQL — probe the schema (the runbook's query omits it; this is the load-bearing reconstruction field). Pin the verified field name in the spec.
3. Confirm the `runs` cross-ref shape to detect a fired reminder (status `Completed`/`Cancelled`).
4. Decide GET-vs-POST per step (enumerate = GET read-only; verify = POST destructive async) and single-vs-two workflows.

### Phase 1 — Enumeration path (no-SSH step 2)
1. Write the RED test for `inngest-enumerate-reminders.sh` first (`cq-write-failing-tests-before`), then the script (payload-complete eventsV2 + runs cross-ref → JSON re-arm records).
2. Register the `inngest-enumerate-reminders` GET hook in `hooks.json.tmpl`.
3. Thread host-script delivery (infra-config push payload OR deploy bundle — per Phase 0.1).

### Phase 2 — Wiped-volume verify path (no-SSH step 5)
1. Write the RED test, then `inngest-wiped-volume-verify.sh` with the **durable-backend precondition guard** (refuse if `--postgres-uri` absent — never wipe a SQLite-only backend with real reminders).
2. Register the `inngest-wiped-volume-verify` POST hook (async 202 + status). Decide status-slot reuse vs dedicated responder.
3. Idempotent throwaway-marker arming (unique id, `fire_at` T+90s) + assert-fired-via-runs + `/health` + `/v1/functions`.

### Phase 3 — Workflow_dispatch driver
1. `.github/workflows/cutover-inngest.yml` mirroring `restart-inngest-server.yml` (HMAC + CF-Access + freshness-guarded poll + `timeout-minutes` ≥ poll budget + enum input validation + `--max-time` on every curl).

### Phase 4 — Runbook rewrite + ADR amend
1. Rewrite §"Cutover procedure" steps 2 & 5 to the `gh workflow run cutover-inngest.yml` triggers; preserve step 7 tripwire verbatim.
2. Amend ADR-030 (`## Cutover orchestration` note) via `/soleur:architecture`.

### Phase 5 — Verify + ship
1. shellcheck, `*.test.sh`, `tsc --noEmit` (if TS touched), runbook no-`ssh ` grep over the rewritten region.
2. PR body uses `Ref #5450` (NOT `Closes`).

## Risks & Mitigations

- **R1 — `eventsV2` does not return the payload (KEYSTONE).** The runbook's current query selects only `id name receivedAt`; re-arm needs `reminder_id/fire_at/action`. Mitigation: enumeration script selects `data`/`raw`; Phase 0.2 pins the field name against the live schema; AC1 test asserts payload presence.
- **R2 — re-arm double-fires a non-idempotent reminder.** The reminder `post-comment`/`run-check` steps are not idempotent on replay (runbook step 3). Mitigation: enumeration cross-refs `runs` to exclude already-fired events; re-arm only future-dated, never-run events. Document in runbook.
- **R3 — wiped-volume verify destroys real reminders if mis-targeted.** Mitigation: the verify script refuses unless `--postgres-uri` is configured (durable backend present), uses a unique throwaway marker, and is the only destructive op — gated behind its own POST hook + HMAC. The rollback tripwire (step 7) is preserved.
- **R4 — `workflow_dispatch` cannot be pre-merge-verified from the feature branch.** A NEW workflow returns 404 on `gh workflow run --ref <feature-branch>` (it must exist on the default branch first). Mitigation: do NOT plan pre-merge `gh workflow run`; the scripts are unit-tested locally (`*.test.sh`) and the workflow's curl/poll logic is extracted/asserted via shell test; live verification of the workflow is post-merge against main (the cutover itself). See Sharp Edges.
- **R5 — host-script delivery without a remote shell (deepen-corrected).** New `.sh` files reach `/usr/local/bin` via the no-SSH `infra-config` push, but this is a **5-file lockstep** (Enhancement Summary #1): `push-infra-config.sh` (payload) + `hooks.json.tmpl` (envname) + `infra-config-apply.sh` `FILE_MAP` + `infra-config-install.sh` `DEST_SPEC` (allowlist — absent → rc=3) + tests. Missing the `DEST_SPEC` entry is the silent-failure mode: the push returns but the script is rejected and never installed. Mitigation: the corrected `## Files to Edit` lockstep + the FILE_MAP↔DEST_SPEC parity test.
- **R6 — availability coupling (permanent).** Post-cutover inngest can't boot without Supabase+Redis; the wiped-volume verify exercises exactly this. Mitigation: the verify's durable-backend precondition + the existing `verify_inngest_health` HARD gate already assert this; document the coupling (already in runbook §"Availability coupling").

## Infrastructure (IaC)

### Terraform changes
- **`hooks.json.tmpl`** is rendered by Terraform (`${jsonencode(webhook_deploy_secret)}`) — adding two hooks is a template edit applied via the infra apply path. No new providers, no new provider version pins.
- **No new secret** for the chosen approach (a): reuses `WEBHOOK_DEPLOY_SECRET` (HMAC) + `CF_ACCESS_CLIENT_ID/SECRET` (already GH secrets, used by `restart-inngest-server.yml`). This avoids the `hr-tf-variable-no-operator-mint-default` + no-default-var-fails-merge-apply class entirely. Sensitive variable list: unchanged.
- **New host scripts** (`inngest-enumerate-reminders.sh`, `inngest-wiped-volume-verify.sh`) ship to `/usr/local/bin` via the established **no-SSH `infra-config` push** path (Phase 0.1 / R5) — NOT via a remote shell. If they ship via the deploy bundle instead, that is equally no-SSH. Confirm + document the chosen path.

### Apply path
- (b) cloud-init + idempotent infra-config push: the `hooks.json` re-render + new scripts land via `push-infra-config.sh` → `/hooks/infra-config` (HMAC-gated, no SSH). Blast radius: re-renders `hooks.json` + installs scripts; the webhook service reloads. No inngest downtime from the hook addition itself. Expected downtime: none for the orchestration build (the destructive verify causes a brief inngest restart only when the operator triggers it during the live cutover).

### Distinctness / drift safeguards
- `dev != prd`: the cutover workflow targets prod `deploy.soleur.ai`; no dev equivalent (inngest durable backend is a prod concern). The destructive verify's durable-backend precondition prevents accidental SQLite-state destruction. No `lifecycle.ignore_changes` needed (no new TF resource). State storage: unchanged (no new secret in `terraform.tfstate`).

### Vendor-tier reality check
- N/A — no new vendor resource; Supabase + self-hosted Redis already provisioned (#5459).

## Network-Outage Deep-Dive (Phase 4.5)

This plan's whole purpose is to REMOVE SSH from the cutover; the deep-dive confirms the no-SSH path's network reachability per the L3→L7 checklist (`plan-network-outage-checklist.md`). There is **no outage to diagnose** — the gate fires only because the plan body mentions `ssh`. Layer status:

- **L3 firewall allow-list:** the GHA driver reaches the host via `deploy.soleur.ai` (Cloudflare Tunnel + CF-Access), NOT a raw SSH port — so the operator-egress-IP-drift class (`hr-ssh-diagnosis-verify-firewall`, #3061) does NOT apply. The existing `restart-inngest-server.yml` already uses this exact path in production. **Verified** (no new firewall rule; reuses the tunnel ingress).
- **L3 DNS/routing:** `deploy.soleur.ai` resolves via the existing Cloudflare Tunnel ingress (unchanged). **Verified** (no new DNS record).
- **L7 TLS/proxy:** HTTPS to `deploy.soleur.ai` terminates at Cloudflare; the async-202-then-poll pattern (`2026-03-21-async-webhook-deploy-cloudflare-timeout.md`) avoids the CF 120s edge timeout — the destructive wiped-volume verify MUST be async (202 + `/hooks/deploy-status` poll), NOT a synchronous response, because the inngest stop/wipe/restart/assert exceeds 120s. **Captured in AC4** (poll budget) — load-bearing.
- **L7 application:** the enumeration curls `127.0.0.1:8288` on the host (inngest bound `0.0.0.0:8288`, firewall-scoped to loopback intent). **Verified** (`inngest-bootstrap.sh:12,180`).

No firewall/DNS/TLS change is required; the no-SSH path is a superset-reuse of the proven `restart-inngest-server.yml` ingress. The only new L7 surfaces are the two webhook hooks (HMAC-gated, same secret).

## Observability

```yaml
liveness_signal:
  what: cutover-inngest.yml workflow run terminal status (success/failure) + the DEDICATED /hooks/inngest-verify-status JSON terminal exit_code for the wiped-volume verify (NOT /hooks/deploy-status — that slot is ci-deploy.state only; P1a)
  cadence: on-demand (operator-triggered cutover, one-time)
  alert_target: workflow run log (GitHub Actions) + the run's ::error:: annotation on failure
  configured_in: .github/workflows/cutover-inngest.yml + apps/web-platform/infra/cat-inngest-verify-state.sh (dedicated verify-state slot)
error_reporting:
  destination: host syslog via logger -t (mirrors ci-deploy.sh/cat-deploy-state.sh) surfaced in the inngest-verify-status JSON; workflow ::error:: annotation. Re-arm/enumerate failures surface their loud abort body in the run log (hooks set include-command-output-in-response-on-error)
  fail_loud: yes — the wiped-volume verify returns non-zero terminal exit_code; the enumeration returns its records or a non-200; re-arm exits non-zero (the webhook returns 500 with the abort body); the workflow fails the run (no silent green)
failure_modes:
  - mode: enumeration returns no payload (eventsV2 schema drift)
    detection: AC1 test asserts payload presence; workflow run shows empty/invalid re-arm records
    alert_route: workflow run log
  - mode: re-arm runs before quiesce-clear (would 503 and silently drop)
    detection: inngest-rearm-reminders.sh aborts loud on 503; the rearm hook returns 500 with the abort body (include-command-output-in-response-on-error)
    alert_route: workflow ::error:: + run log body + Layer-3 journald
  - mode: wiped-volume verify destroys state with a real reminder armed
    detection: the emptiness gate (B1) calls enumerate first and aborts (exit non-zero) unless the armed set is empty; the --postgres-uri check is only a secondary sanity
    alert_route: workflow ::error:: + inngest-verify-status JSON exit_code
  - mode: throwaway reminder did not fire post-wipe (durability regression)
    detection: verify script re-enumerates for the marker; presence then non-zero exit
    alert_route: workflow ::error:: + inngest-verify-status JSON
logs:
  where: host syslog (journalctl -t inngest-enumerate-reminders / -rearm-reminders / -wiped-volume-verify) — surfaced via /hooks/inngest-verify-status + the run log without a remote shell
  retention: host journald default (existing)
discoverability_test:
  command: gh run view --log <run-id>   # plus an HMAC+CF-Access GET to /hooks/inngest-verify-status for the verify terminal state
  expected_output: workflow run shows enumerate records / verify PASS|FAIL; inngest-verify-status JSON shows terminal exit_code — no remote shell required
```

## Domain Review

**Domains relevant:** Engineering (CTO), Operations, Legal — carried forward from the #5450 brainstorm `## Domain Assessments`.

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward + this session's code research)
**Assessment:** The host-rebuild gap is real and narrow (HTTP-armed reminders). The no-SSH orchestration must (1) enumerate payload-complete events (the runbook query is incomplete), (2) cross-ref runs to avoid double-fire, (3) gate the destructive verify behind a durable-backend precondition. Approach (a) via new webhook hooks is the coherent shape; step 5 cannot run from a containerized route.

### Operations
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** New host scripts must reach the host without a remote shell (infra-config push). The destructive verify must be safe-by-default (refuse on non-durable backend). One-time op; trigger on a low-traffic window.

### Legal
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** No new sub-processor (#5459 already adopted Supabase Postgres + self-hosted Redis). Enumeration output is operator/platform-scoped (`actor: "platform"`) — no new personal-data category in the cutover orchestration itself. The HMAC + CF-Access gate is the trust boundary for the enumeration output.

### Product/UX Gate
**Tier:** none — pure infra/ops orchestration, no UI surface in `## Files to Create`/`## Files to Edit` (scripts, workflow YAML, runbook, ADR). Product NONE.

## Test Scenarios

1. `inngest-enumerate-reminders.test.sh`: mocked GraphQL → already-fired event excluded; future-dated event included WITH payload `{reminder_id, fire_at, action}`.
2. `inngest-wiped-volume-verify.test.sh`: precondition guard refuses (exit ≠ 0) when ExecStart lacks `--postgres-uri`; throwaway marker is unique per run.
3. `hooks.json.tmpl`: `jq .` parses; both new hook ids present with HMAC `trigger-rule`.
4. Runbook: `grep -c 'ssh ' <steps-2-and-5-region>` == 0; tripwire paragraph (step 7) byte-preserved.
5. Workflow: extracted curl/poll logic asserts `--max-time` present, freshness guard present, enum input validated.

## Sharp Edges

- **`## User-Brand Impact` is load-bearing.** A plan whose section is empty/`TBD`/placeholder fails `deepen-plan` Phase 4.6. (Filled above; threshold = single-user incident → `requires_cpo_signoff: true`.)
- **`workflow_dispatch` cannot be pre-merge-verified.** A NEW workflow 404s on `gh workflow run --ref <feature-branch>` — it must exist on the default branch first. Do NOT plan a pre-merge `gh workflow run`; unit-test the scripts + extract-and-assert the workflow shell. Live workflow verification is post-merge (the cutover itself). (R4.)
- **The runbook's step-2 `eventsV2` query is incomplete.** It selects `id name receivedAt` — no payload — so its output is un-re-armable as written. The new script MUST select `data`/`raw`. (R1.)
- **The wiped-volume verify is destructive.** It must refuse on a non-durable (SQLite-only) backend; mis-targeting destroys real reminders. (R3.)
- **`Ref #5450`, not `Closes #5450`.** This PR builds the orchestration; the issue closes only after the operator runs the live cutover (ops-remediation Closes-vs-Ref).
- **Host-script delivery is itself a no-SSH question.** New `.sh` reach the host via `infra-config` push, not a remote shell copy. (R5.)
