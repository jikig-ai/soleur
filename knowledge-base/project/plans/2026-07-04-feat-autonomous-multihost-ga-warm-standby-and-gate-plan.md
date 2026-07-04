---
title: "Autonomous multi-host GA warm-standby apply + programmatic §(c) LB-weight gate + de-manualization (ADR-068)"
date: 2026-07-04
type: feat
branch: feat-one-shot-autonomous-multihost-ga-cutover
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: []
refs: [5887, 5877, 5274, 5966, 5967, 5968, 5933]
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- lint-infra-ignore start
     Everything this plan quotes about operator-run terraform / remote-shell / private-net
     verify is a LINT SENTINEL definition (Phase 4) or a de-manualization TARGET being REMOVED
     (Phase 3) — never a prescribed manual step. The whole point is to ELIMINATE human infra
     steps; the `## Infrastructure (IaC)` section routes the only real apply through the
     R2-serialized dispatch workflow. This region marker is the same carve-out mechanism
     Phase 4's lint honors, demonstrated on the file that introduces it. -->

# Autonomous multi-host GA warm-standby + programmatic §(c) gate

## Enhancement Summary

**Deepened on:** 2026-07-04. **Review panel:** CTO + spec-flow-analyzer + DHH + Kieran +
code-simplicity (5 agents, all code-verified against `main`), fully incorporated before this pass.
**Deepen gates:** 4.6 User-Brand (PASS), 4.7 Observability (PASS, no-SSH), 4.8 PAT-shaped (none),
4.9 UI-wireframe (N/A), 4.55 Downtime & Cutover (section added). All cited rule IDs active, all
cited learning paths + `[hook-enforced:]` tag format verified.

### Key improvements folded from review
1. **readyz reconciliation (P0):** dropped the off-host `readyz==200` / `workspaces_writable` design
   — `workspaces_writable` passes on the host-root fallback dir so it does NOT prove the volume
   attach. Attach proof = the terraform apply's own created-resources output; readyz serve-readiness
   moved to the deferred orchestrator's on-host (docker-exec) gate.
2. **topology (P0):** off-host `/hooks/deploy-status` reaches web-1 only (no peer aggregation) —
   verify web-2 via web-1's deploy-status `reason` (`ok` vs `ok_peer_fanout_degraded`) + a pre-trigger
   `:9000` probe; the dispatch fails on the degraded reason.
3. **doc-lint (P0):** actor+imperative CO-OCCURRENCE model (not bare `terraform apply`/`reboot`) +
   `<!-- lint-infra-ignore -->` regions + broadened scan dirs, so it doesn't red-line this plan or
   the retained deferred-orchestrator prose; tag is `[hook-enforced:]` not `[skill-enforced:]`.
4. **§(c) gate:** SHAPE-ONLY with a machine-readable `requires_runtime_bind_probe=true`; roster
   parser-parity + web-2-in-roster + allowlist⊆roster; malformed/future/soak-floor timestamp cases;
   dropped the tautological source-grep; two files (Doppler wrapper deferred to the orchestrator).
5. **AGENTS:** strengthen one rule in place (24 B headroom); the lint is the enforcement teeth.

### New considerations discovered
- The deploy trigger **re-swaps the live origin (web-1)** — acknowledged as an existing
  canary-gated zero-downtime path (SE-3), not a new downtime source (Downtime & Cutover §).
- apply+deploy are **non-transactional** → an ingress-safe partial (attached-but-undeployed) is
  possible; recovery = idempotent re-dispatch (Phase 2 recovery contract).

## Overview

ADR-068's multi-host GA line was designed with **human-in-the-loop ops steps** — an operator
maintenance-window terraform apply, a private-net remote-shell verify, and a "book a window /
decide before the window" human decision — carried in the multi-host blue-green plan
(`2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md` Phase 2 + Post-merge) and the
`moved-block-wedge-cutover-5887.md` runbook (Scope B). **Soleur users are non-technical and act
only through the web app / CI.** Each such step is an automation bug to close, not a valid step
(`hr-exhaust-all-automated-options-before`, `hr-fresh-host-provisioning-reachable-from-terraform-apply`,
`hr-no-ssh-fallback-in-runbooks`).

The automation substrate already exists on `main` — Inngest-dispatches-GHA off-host with
cloud-admin creds; the `apply-web-platform-infra.yml` R2-backend **concurrency serializer**;
`ci-deploy.sh fan_out_to_peers` host-side over the `10.0.1.0/24` private net; the
`/internal/readyz` deep-readiness endpoint (#5966). **This plan wires it together** and closes the
human-step class so it cannot ship again.

**Scope (safe foundations + workflow fix; the live web-1 reboot orchestration is a tracked
follow-up gated on these landing + soak):**

1. **Programmatic §(c) gate** — a tested, **fail-closed, SHAPE-ONLY** check (script + unit tests)
   over injected inputs, verifying the *config-shape* of BOTH ADR-068 §(c) conditions and emitting
   a machine-readable `requires_runtime_bind_probe=true` so no consumer mistakes it for weight-flip
   authorization. Consumable by CI and the future orchestrator.
2. **Dispatchable warm-standby apply** — a `workflow_dispatch` path in `apply-web-platform-infra.yml`
   that runs the additive 6-resource `-target` apply through the **existing R2 concurrency
   serializer** (never operator-local), triggers the host-side deploy fan-out to web-2, and verifies
   web-2 came up **off-host with no SSH** using the two reachable signals (the apply's own
   created-resources output + web-1's deploy-status `reason`).
3. **De-manualize the plan + runbook** — replace every operator-run apply / private-net verify /
   maintenance-window human decision in the multi-host blue-green plan and the runbook Scope B with
   the dispatch/orchestration path + the programmatic §(c) gate.
4. **Improve our own workflow** — strengthen the hard rules + add a **CI lint** that FAILS when a
   plan/spec/runbook prescribes a *human-run* terraform / SSH / reboot / verify-on-private-net infra
   step (actor+imperative match, not bare infra nouns), so this class can't ship again; plus a
   learning file.

**Deferred (tracked follow-up issue, gated on 1–4 + soak):** the live cutover orchestrator — an
Inngest-dispatched GHA maintenance-window workflow that runs the §(c) gate + its on-host runtime
gate → shift web-2 LB weight 0→1 → drain web-1 → remove `ignore_changes=[placement_group_id]` →
placement-group reboot on the **drained** host → restore, with automatic rollback. It reboots the
sole live origin and MUST NOT be built before the warm-standby + gate land and soak-verify.

## Research Reconciliation — Feature framing vs. Codebase reality

All cited context (ADR-068, server.tf §(c), session-proxy/router, git-data flag + D2 sentinel,
network.tf, variables.tf `web_hosts`, expenses, the apply workflow) was **verified present on this
branch** (Phase 0.6 premise validation). Five framing claims are falsified by the code and reshape
the design (all confirmed by the 5-agent plan-review panel against `main`):

| Feature-description claim | Reality (verified 2026-07-04, file:line) | Plan response |
|---|---|---|
| "assert `GET /internal/readyz` on web-2 **private IP (10.0.1.11)** == 200" | **Triply false.** (a) `readiness.ts:113` dual-gates on `isLoopbackPeer(remoteAddress)` (`loopback.ts:30-34` accepts only 127.0.0.1/::1) + loopback Host → off-host/private-net caller = **403**. (b) web-2 `/workspaces` is empty at warm-standby (git-data OFF) → `populated=false` → **503 by design**. (c) `workspaces_writable` (`readiness.ts:54-69` write+unlink probe) **passes on the host root fs too** — docker auto-creates the bind dir (module comment :30-35), so it does NOT prove the Hetzner volume attached. | **Drop the readyz probe from this PR.** Prove the attach with the **terraform apply's own created-resources output** (in-job); prove web-2 liveness/acceptance with web-1's deploy-status `reason`. The readyz serve-readiness gate (docker-exec in-container, writable+populated+N≥2) is the **deferred orchestrator's on-host pre-pool** check — exactly ADR-068's model. See SE-1. |
| off-host `/hooks/deploy-status` reports web-2's state | **False (topology).** `deploy.soleur.ai/hooks/deploy-status` resolves via the CF tunnel to the **serving host only (web-1)**; `cat-deploy-state.sh` does **no** peer aggregation; web-2 has zero LB weight + no public ingress. An off-host runner cannot read web-2 directly. | Verify web-2 via web-1's deploy-status **`reason`** field: `fan_out_to_peers` (`ci-deploy.sh:161`) POSTs `peer:9000/hooks/deploy-peer`; on non-202 it sets `reason="ok_peer_fanout_degraded"` (`:1325-1330`). With one peer (web-2) that reason IS the web-2-accepted signal. Full web-2 serve-verification is the deferred orchestrator. Resolves Open Question 1 as a **topology** decision. |
| "the deploy fan-out asserts readyz" | `fan_out_to_peers` is fire-and-forget (checks HTTP **202 accept**, not deploy success); does NOT call readyz. | The dispatch **fails on `reason=~_peer_fanout_degraded`**; a pre-trigger web-2 `:9000` reachability probe avoids firing at an unbound listener (SE-2). |
| "add an AGENTS.md hard rule" (net-new) | `B_ALWAYS` = `AGENTS.md`(5840)+`AGENTS.core.md`(17136) = **22976/23000** — 24 B headroom. A net-new core rule can't land. Enforcement teeth are the CI lint, not the prose. | **Strengthen `hr-no-ssh-fallback-in-runbooks` in place** (clause owner) with a `[hook-enforced: lefthook lint-infra-no-human-steps.py]` tag; the other two get a short cross-ref. Re-measure ≤23000. SE-6. |
| the 6-target set / "OPERATOR_APPLIED_EXCLUSIONS" | The 6 additive resources are enumerated in `terraform-target-parity.test.ts` `OPERATOR_APPLIED_EXCLUSIONS` (:374) — excluded from BOTH auto-apply target sets. `hcloud_server.web["web-2"]` already exists in state (running). | Dispatch `-targets` exactly the 6 (`hcloud_network.private`, `hcloud_network_subnet.private`, `hcloud_server_network.web["web-1"]` online attach, `…["web-2"]`, `hcloud_volume.workspaces["web-2"]`, `hcloud_volume_attachment.workspaces["web-2"]`). No server create. |

## User-Brand Impact

**If this lands broken, the user experiences:** foundations are inert on merge — no LB weight, no
reboot, no ingress change. The real blast radius is *latent*: a **§(c) gate false-PASS** would let
the future orchestrator flip web-2's LB weight 0→1 before the relay + git-data are live → a live
request lands on web-2's **empty `/workspaces`** → fresh-session greeting, repo/conversation state
gone (#5240-class workspace-gone incident). Secondarily, a warm-standby `-target` set that dragged
in web-1's placement reboot would power-off the sole live origin.

**If this leaks, the user's workflow is exposed via:** N/A for this PR — no new data-processing
path is activated (git-data OFF, `isGitDataStoreEnabled()==false`; web-2 `/workspaces` empty). The
Article-30 / git-data processing lockstep lands with the deferred GA orchestrator.

**Brand-survival threshold:** single-user incident → `requires_cpo_signoff: true`;
`user-impact-reviewer` runs at review. The gate's value IS this threshold: fail-closed (any
missing/empty/malformed input → non-zero) AND explicitly SHAPE-ONLY (`requires_runtime_bind_probe`),
so a false-PASS cannot authorize the weight flip.

## Implementation Phases

> **Phase ordering (Kieran P2-C):** land Phase 4 (the lint + its carve-out mechanism) **before**
> Phase 3's "docs PASS the lint" is evaluated — the lint is the producer, the de-manualized docs +
> this plan file are its consumers.

### Phase 0 — Preconditions (grep/read, no mutation; record in PR body)

- **P0.1 — 6-target plan is additive & the apply output is the attach proof.** Read-only
  `terraform plan` limited to the 6 targets; confirm `6 to add, 0 to change, 0 to destroy`, `0 to
  create` of any non-targeted resource, and **no** `placement_group_id`/reboot diff on
  `hcloud_server.web["web-1"]`. Canonical triplet (learning `2026-05-09-drift-runbook-canonical-tf-invocation`):
  raw `AWS_*` exports from Doppler `prd_terraform` (R2 backend), `terraform init -input=false`,
  `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan …`. The
  dispatch job's apply asserts `hcloud_volume_attachment.workspaces["web-2"]` +
  `hcloud_server_network.web["web-2"]` **created** — this in-job output is the attach proof
  (no reachability needed).
- **P0.2 — deploy trigger + fan-out reachability.** Read `ci-deploy.sh:134-172,1320-1330`. Confirm:
  the fan-out fires only after web-1's own successful swap (→ triggering web-2 re-swaps web-1 —
  SE-3); non-202 → `reason="ok_peer_fanout_degraded"`, exit 0; `POST /hooks/deploy` redeploys the
  current version (vs `gh workflow run web-platform-release.yml` cutting a new release). Choose the
  minimal-blast trigger and whether a web-2-only deploy path exists (Open Question 2).
- **P0.3 — runtime env source.** Confirm `SOLEUR_PROXY_BIND`, `SOLEUR_PROXY_PEER_ALLOWLIST`,
  `SOLEUR_HOST_ROSTER`, `GIT_DATA_STORE_ENABLED` are runtime env from Doppler **`prd`** (not
  `prd_terraform`). The gate's Doppler-sourcing entry point (Phase 5) reads `prd`.
- **P0.4 — reboot-guard reality.** The **primary** web-1-reboot protection is the plan-scoped jq
  `reboot_updates` counter (`destroy-guard-filter-web-platform.jq:114-127`, `actions==["update"]`
  on `hcloud_server.*` with changed `placement_group_id`/`server_type`), which the dispatch apply
  runs. `terraform-target-parity.test.ts` `MOVED_OPERATOR_CONSUMED` (:752) regex-**unions all**
  `-target=` lines in the workflow with no per-job scoping — the 6 warm-standby addresses are
  already excused there (they're in `OPERATOR_APPLIED_EXCLUSIONS`:374). **Keep that test job-aware;
  do NOT weaken its boundary** by broadening `allTargets`. `git grep -ln 'reboot_updates\|MOVED_OPERATOR_CONSUMED\|-target='`
  to enumerate every asserting suite before editing.
- **P0.5 — doc-lint corpus baseline.** Run the actor+imperative candidate patterns across the
  scanned dirs; enumerate current matches to size the changed-files scope + carve-outs (Phase 4).
- **P0.6 — AGENTS budget baseline.** `wc -c AGENTS.md AGENTS.core.md` (22976/23000) + the byte
  length of `hr-no-ssh-fallback-in-runbooks`.

### Phase 1 — Programmatic §(c) gate (fail-closed, SHAPE-ONLY; script + unit tests)

**Files to create (two files — pure + test; the Doppler-sourcing entry point ships with the
deferred orchestrator, Phase 5, its only caller):**
- `apps/web-platform/infra/lb-weight-gate.sh` — **pure, fail-closed** over injected env. Exit `0`
  ONLY if both conditions' config-shape holds; any missing/empty/malformed input → non-zero with a
  structured line naming the failed sub-condition. **On success it prints
  `requires_runtime_bind_probe=true`** and a `SHAPE-ONLY — NOT weight-flip authorization` banner, so
  a consumer that treats exit 0 as "safe to weight web-2" is contractually wrong.
  - **Condition A (owner-side relay config-shape):** `SOLEUR_PROXY_BIND` non-empty;
    `SOLEUR_PROXY_PEER_ALLOWLIST` non-empty, parsed with the **same semantics as
    `parseProxyPeerAllowlist` (`session-proxy.ts:166`)**; `SOLEUR_HOST_ROSTER` parsed with the
    **same semantics as `loadHostRoster` (`session-router.ts:57` — non-object/dup-key/whitespace →
    reject, mirroring the loader's `{}` fallback)**, and **web-2 specifically** present as a roster
    entry (not just "≥2 arbitrary"); and **allowlist peers ⊆ roster hosts** (P2-10). *Rationale:*
    `loadHostRoster` is fail-safe (silently `{}`) — the gate adds the fail-closed shape check the
    loader lacks. This proves config-shape, NOT that any listener bound (that's the runtime probe).
  - **Condition B (git-data cut-over config-shape):** `GIT_DATA_STORE_ENABLED == "true"`; a
    **LUKS-cutover soak marker** — Doppler `prd` key `GIT_DATA_LUKS_CUTOVER_AT` (ISO-8601) written
    by the deferred cutover, with `now - GIT_DATA_LUKS_CUTOVER_AT >= GIT_DATA_LUKS_SOAK_DAYS`
    (default 3, ADR-068 3.D). Absent marker (today) → **not satisfied** (correct — GA hasn't
    happened). **No source-grep sentinel** — the D2 write-boundary sentinel is a code-review/CI
    sweep concern (`hr-write-boundary-sentinel-sweep-all-write-sites`), always-true once merged, so
    it carries zero runtime signal in a weight-flip gate (dropped per DHH/CTO/code-simplicity + OQ3).
- `apps/web-platform/infra/lb-weight-gate.test.sh` — native-bash unit tests (`PASS/FAIL/TOTAL`;
  assert on **exit codes**, not summary literals). Cases: both-hold→0; each single missing/empty
  A-var→non-zero; roster missing web-2→non-zero; roster loader-rejects (dup-key/non-object/whitespace)→non-zero;
  allowlist ⊄ roster→non-zero; `GIT_DATA_STORE_ENABLED=false`→non-zero; marker absent→non-zero;
  marker **unparseable/garbage date**→non-zero; marker **future-dated**→non-zero;
  `GIT_DATA_LUKS_SOAK_DAYS<=0`→non-zero (or floor); soak not elapsed→non-zero; all-hold + elapsed→0
  AND stdout contains `requires_runtime_bind_probe=true`.

### Phase 2 — Dispatchable warm-standby apply (R2-serialized; no operator-local, no SSH)

**Files to edit/create:**
- `.github/workflows/apply-web-platform-infra.yml` — add a `workflow_dispatch` input `apply_target`
  (enum `manual-rerun` [default, current behavior] | `warm-standby`). On `warm-standby`, a
  **dedicated plan+apply job** that:
  1. Runs in the **same `concurrency: group: terraform-apply-web-platform-host`** (`:97`,
     `cancel-in-progress:false` — the sole serializer for the lock-less R2 backend; do NOT split
     into a second workflow, per CTO — that reintroduces the unserialized-second-writer hazard).
  2. Sources raw `AWS_*` from `prd_terraform` (existing steps), `plan -out=tfplan` `-target`ing the
     6 resources, runs the **existing plan-scoped destroy-guard** (`reboot_updates=0` asserted),
     then `apply tfplan`. The apply's created-resources output is the **attach proof** (P0.1).
  3. **Triggers the web-2 deploy** via the minimal-blast path chosen in P0.2 (`POST /hooks/deploy`
     current version preferred). **Between apply and trigger, probe web-2 `:9000` reachability**
     (bounded retry) so the fire-and-forget fan-out doesn't hit an unbound listener (SE-2). The
     trigger **re-swaps web-1** (fan-out fires post-web-1-swap) — an idempotent, canary-gated
     redeploy of the live origin at the current version; ingress is unchanged (SE-3).
  4. **Verify web-2 off-host, no SSH:** read web-1's `/hooks/deploy-status` (CF-Access + HMAC,
     `cat-deploy-state.sh` — "deploy-status read (no SSH)") and **fail unless `reason=="ok"`**
     (`reason=~_peer_fanout_degraded` ⇒ web-2 did not accept the deploy → red). This is the
     reachable web-2-accepted signal; full web-2 serve-readiness is the deferred orchestrator's
     on-host gate.
- **No `ci-deploy.sh` change** — the readyz probe is dropped from this PR (the attach proof is the
  apply output; web-2 serve-readiness is deferred). The fan-out already surfaces the per-peer accept
  via `reason`.
- **Guard suites (P0.4):** confirm the plan-scoped `reboot_updates` jq guard covers the dispatch
  apply; keep `terraform-target-parity.test.ts` job-aware. Add a test asserting the warm-standby
  6-target plan yields `reboot_updates=0` on `hcloud_server.web["web-1"]`.

> **Sequencing (learning `2026-04-21-workflow-dispatch-requires-default-branch`):** `apply_target=warm-standby`
> can only be dispatched AFTER merge (GitHub resolves `workflow_dispatch` against the default
> branch). Pre-merge = local `-target` dry-run (P0.1) + guard/gate unit tests + `actionlint` +
> `bash -c` on extracted `run:`. **Post-merge** = the actual `gh workflow run … -f
> apply_target=warm-standby` (operator-acknowledged **menu** trigger per
> `hr-menu-option-ack-not-prod-write-auth` — a menu ack, not a prod-write authored by a
> non-technical user).
>
> **Recovery contract (P1-5):** apply and deploy-trigger are **not transactional**. If the apply
> lands (volume attaches → billing flips) but the trigger fails, the state is *ingress-safe*
> (web-2 weight 0) but attached-but-undeployed — **not** "no partial state". Recovery = idempotent
> re-dispatch (apply = 0 changes, re-trigger). The dispatch MUST fail loudly on a partial so it
> can't read as success.

### Phase 3 — De-manualize the multi-host plan + the runbook

- `…/plans/2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md` — rewrite **Phase 2**
  (operator maintenance-window apply), its Step 1/2 (operator-local `-target` apply / private-IP
  verify), the IaC **Apply path** line, and the **Post-merge (operator)** Phase-2 bullet → the
  dispatch path `gh workflow run apply-web-platform-infra.yml -f apply_target=warm-standby`
  (R2-serialized apply + fan-out + deploy-status `reason` verify; no operator command, no SSH).
  Reference the §(c) gate for the deferred weight flip.
- `…/runbooks/moved-block-wedge-cutover-5887.md` **Scope B**: (a) Pre-flight step 1 ("maintenance
  window booked") — the *warm-standby* needs none (additive, zero ingress impact); the window
  belongs ONLY to the deferred reboot orchestrator. (b) Steps 5–6 (provision + deploy-drained +
  private-IP readyz verify) → the dispatch path. (c) Steps 7–10 (§(c) satisfy → weight 0→1 → drain →
  reboot → restore) **stay as the DEFERRED orchestrator**, wrapped in a `<!-- lint-infra-ignore -->`
  region (they describe an *orchestrator* action, not a human step), and reference
  `lb-weight-gate.sh` + its runtime-bind probe. Keep `## Resolved` / `Last-resort diagnosis` intact.
- These are deliberate, task-mandated edits to another feature's operational docs; they MUST PASS
  the Phase-4 lint after de-manualization (verified in the ACs).

### Phase 4 — Workflow improvement (AGENTS strengthen-in-place + actor+imperative CI lint + learning)

- **AGENTS (byte-budgeted — 22976/23000).** Strengthen **`hr-no-ssh-fallback-in-runbooks`**
  (AGENTS.core.md:44) in place as the clause owner: append the class ("a plan/spec/runbook that
  prescribes a *human-run* terraform / SSH / reboot / verify-on-private-net infra step fails CI")
  + a **`[hook-enforced: lefthook lint-infra-no-human-steps.py]`** tag (NOT `[skill-enforced:]` —
  there is no `plugins/soleur/skills/lint-infra-no-human-steps/`; `lint-agents-enforcement-tags.py`
  validates the tag against `lefthook.yml`, Kieran P1-B). Give `hr-exhaust-all-automated-options-before`
  (:12) + `hr-fresh-host-provisioning-reachable-from-terraform-apply` (:20) a short cross-ref only.
  Re-measure `wc -c` after each edit; keep ≤ 23000; fund the tag by tightening prose. A discrete new
  `hr-*` id lands ONLY with a named funding trim (not worth it — the lint is the enforcement, not
  the prose; SE-6).
- **`scripts/lint-infra-no-human-steps.py`** (Python, mirrors `lint-rule-ids.py`) +
  **`scripts/lint-infra-no-human-steps.test.sh`** (native bash). **Sentinel model = human-actor +
  infra-imperative CO-OCCURRENCE on a line** (P0-3/P1-8 — a bare-token denylist cannot separate
  "prescribes a *human* runs X" from "defers X to an *orchestrator*", and would red-line this plan +
  the retained deferred-orchestrator runbook steps):
  - **Actor tokens:** `operator`, `you`/`your laptop`, `SSH into`, `log into … console`, `by hand`,
    `manually`, `ask the operator`.
  - **Infra-imperative tokens:** `terraform apply`/`tofu apply`/`opentofu apply`, `reboot`/`power-cycle`,
    `attach the volume`, `verify … private … IP`, `-target … apply`.
  - Flag ONLY when an actor token and an imperative token co-occur (same line / adjacent). Honor
    **`<!-- lint-infra-ignore -->` region markers**, ignore fenced code blocks + backtick spans,
    carve out `**/archive/**` + `## Resolved` / `Last-resort diagnosis` sections. **Changed-files
    mode** (git diff vs merge base) for grandfathering. Paren-safe phrases (learning
    `2026-05-15-ci-sentinel-paren-safety`).
  - **Scan dirs:** `knowledge-base/{project/plans,project/specs,engineering/operations/runbooks,legal/runbooks,engineering/architecture/decisions}`
    — including the legal-runbooks + ADR dirs (P1-8a: the ADR-068 amendment this PR authors + legal
    runbooks would otherwise escape the class). Exit 1 listing `file:line`.
  - Wire into **`.github/workflows/ci.yml`** (a lint step joining `lint-bot-synthetic-statuses.sh`
    — the load-bearing fail-closed gate) **and** `lefthook.yml` (pre-commit parity; also what the
    `hook-enforced` tag references). `.test.sh` fixtures: a human-step line FAILS; an
    orchestrator-defers line PASSES; an ignore-region line PASSES; a paraphrase (`tofu apply` by
    operator) FAILS.
- **Learning file** `knowledge-base/project/learnings/workflow-patterns/2026-07-04-<topic>.md`
  (dir + topic; author dates it): "I designed human-in-the-loop ops steps for non-technical users;
  the fix is autonomous CI/Inngest orchestration + an actor+imperative lint that fails the class."

### Phase 5 — Defer the live cutover orchestrator (tracked issue)

`gh issue create` (milestone from `roadmap.md`, `Ref` not `Closes`): **"Live multi-host GA cutover
orchestrator (Inngest-dispatched GHA maintenance-window)"** — builds `lb-weight-gate-doppler.sh`
(the Doppler-sourcing entry point) + the **on-host runtime gate** (in-container `docker exec … curl
127.0.0.1:3000/internal/readyz -H 'Host: localhost'`, requiring `workspaces_writable && populated`
with **N≥2 consecutive** reads before draining a live origin, plus a device-identity attach check
`/dev/disk/by-id/scsi-0HC_Volume_*`) as a **distinct required condition** from the SHAPE-ONLY gate
(never fold "runtime probe" into "gate green") → shift web-2 weight 0→1 → drain web-1 → remove
`ignore_changes=[placement_group_id]` → reboot the **drained** host → restore, with auto-rollback.
**Gated on:** Phases 1–4 merged + warm-standby + gate soak-verified. Re-eval: warm-standby
dispatched clean ≥1×; gate unit-green; `GIT_DATA_LUKS_CUTOVER_AT` written + soak elapsed.
(`wg-when-deferring-a-capability-create-a`.)

## Infrastructure (IaC)

### Terraform changes
- **No new `.tf` resources authored** — the 6 warm-standby resources already exist in `network.tf` /
  `server.tf` (excluded from both auto-apply target sets; enumerated in
  `terraform-target-parity.test.ts OPERATOR_APPLIED_EXCLUSIONS`). This PR adds only the **dispatch
  path** that applies them through the serializer.
- **No new no-default TF variable** → no merge-apply blocker (learning
  `2026-06-17-operator-mint-tf-var-must-sequence`). The gate uses existing Doppler `prd` runtime
  keys + one new Doppler key `GIT_DATA_LUKS_CUTOVER_AT` (written by the deferred cutover) — a Doppler
  secret, not a `TF_VAR_*`.

### Apply path
- **Dispatch through the R2 concurrency serializer** (`apply_target=warm-standby`). Downtime **zero**
  on ingress (weight unchanged); web-1 sees an idempotent canary-gated redeploy of the current
  version (SE-3). No reboot-bearing change targeted (`reboot_updates=0`). Never operator-local; never
  remote-shell.

### Distinctness / drift safeguards
- `for_each` gate: all 6 targets key off existing addresses / `var.web_hosts`; **no NEW `for_each`
  over a `-target`-excluded map** (learning `2026-07-03-for-each-over-target-excluded-map`) → no
  premature provisioning. Assert `0 to create` of any non-targeted resource (P0.1).
- The dispatch target set is a hand-maintained allow-list → the plan-scoped `reboot_updates` jq
  guard is the reboot protection; keep the parity test job-aware (P0.4).

### Vendor-tier reality check
- **No new recurring expense in THIS PR.** web-2 20 GB volume (~€0.88/mo) already recorded
  (`expenses.md:18`, active); CF Load Balancing ($5/mo) is `approved-not-billing` + GA-deferred. The
  dispatch's first run flips the volume to billing — already tracked. No
  `wg-record-recurring-vendor-expense-before-ready` action.

## Downtime & Cutover

Zero-downtime-first (deepen Phase 4.55; Soleur is a live single-operator surface — an outage is a
`single-user incident`). Two operations in this arc *could* take the serving surface offline; both
are handled zero-downtime and the one true offline op is **deferred**:

- **Deferred placement-group reboot of web-1 (NOT this PR).** Attaching web-1 to `web_spread` is a
  Hetzner power-off. This PR does NOT do it — `ignore_changes=[placement_group_id]` (#5950) keeps it
  out of every plan; the deferred orchestrator (Phase 5) takes it **blue-green on a DRAINED host**
  after web-2 is serving. The warm-standby apply asserts `reboot_updates=0` (P0.4) so it cannot
  sneak into the dispatch path.
- **Deploy-trigger re-swap of web-1 (this PR, zero-downtime).** The dispatch triggers a deploy so
  the fan-out reaches web-2; `fan_out_to_peers` fires only after web-1's own swap, so web-1 is
  re-deployed at the **current version** through the **existing canary-gated swap** (SE-3) — the
  established zero-downtime deploy contract, not a naive drop-in. Ingress is unchanged (no LB, no
  DNS, no weight).
- **Warm-standby apply itself (this PR, zero-downtime).** The 6-target set is additive: the
  `hcloud_server_network` attach is **online** (no reboot), the web-2 volume touches a
  **non-serving** host, no reboot-bearing change is targeted (P0.1: `0 change / 0 destroy`).

**Residual downtime accepted in THIS PR: none.** No bounded maintenance window is needed for the
warm-standby; the maintenance window + operator sign-off belong ONLY to the deferred reboot
orchestrator (which reboots a drained, non-serving host).

## Observability

```yaml
liveness_signal:
  what: warm-standby dispatch run conclusion + the apply's created-resources output (attach proof) + web-1 deploy-status reason=="ok" (web-2 accepted the deploy)
  cadence: on-dispatch (Phase 2); existing web-1 public /health poll + #5933 per-host origin-absence detector
  alert_target: Better Stack (web-1 monitor + #5933 web-2 absence detector); dispatch failure = red GHA run
  configured_in: .github/workflows/apply-web-platform-infra.yml + apps/web-platform/infra/cat-deploy-state.sh
error_reporting:
  destination: Sentry (existing web-platform DSN)
  fail_loud: gate emits a structured non-zero line naming the failed sub-condition; dispatch fails on reason=~_peer_fanout_degraded or a partial apply
failure_modes:
  - mode: warm-standby -target set drags in web-1 placement reboot
    detection: plan-scoped reboot_updates jq counter + P0.1 plan shows 0 change/0 destroy
    alert_route: dispatch apply red; apply aborts before touching web-1
  - mode: gate false-PASS (would authorize a premature weight flip)
    detection: lb-weight-gate.test.sh (fail-closed default; malformed/future/soak<=0 timestamp cases; roster+allowlist shape); requires_runtime_bind_probe=true forces a separate runtime gate
    alert_route: unit suite red; the deferred orchestrator refuses to flip weight without the runtime probe
  - mode: web-2 never accepted the deploy (unbound :9000 / fan-out degraded)
    detection: web-1 deploy-status reason=="ok_peer_fanout_degraded" (no SSH); pre-trigger :9000 reachability probe
    alert_route: dispatch run red; no ingress change made
  - mode: a future plan/runbook re-introduces a human infra step (incl. a paraphrase, or in an ADR/legal runbook)
    detection: lint-infra-no-human-steps.py (ci.yml + lefthook), actor+imperative match, broadened scan dirs, changed-files mode
    alert_route: CI red on the lint job; lint-infra-no-human-steps.test.sh guards the lint itself
logs:
  where: host pino to stdout (existing); GHA run logs; Sentry breadcrumbs
  retention: existing web-platform retention
discoverability_test:
  command: "gh run list --workflow=apply-web-platform-infra.yml --event=workflow_dispatch --branch main --limit 1 --json conclusion,displayTitle && bash apps/web-platform/infra/lb-weight-gate.test.sh"
  expected_output: 'the latest workflow_dispatch run conclusion is "success" and the gate unit tests PASS (no ssh)'
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-068** (via `/soleur:architecture`) — "Autonomous warm-standby apply + programmatic §(c)
gate": (1) warm-standby provisioning is a `workflow_dispatch` **through the R2 concurrency
serializer** (never operator-local); (2) §(c) is a **fail-closed, SHAPE-ONLY** programmatic check
(`lb-weight-gate.sh`) emitting `requires_runtime_bind_probe=true`, consumable by CI + the
orchestrator, defining the `GIT_DATA_LUKS_CUTOVER_AT` soak-marker contract; (3) warm-standby verifies
attach via the terraform apply output + web-2-accepted via web-1 deploy-status `reason` — the readyz
serve-readiness gate is the **deferred orchestrator's on-host** pre-pool check (not `ready==200`
off-host, and not `workspaces_writable` as attach proof). Squarely in the ADR-068 arc — **amend, do
not create a new ADR**. (The amendment text is `<!-- lint-infra-ignore -->`-wrapped where it quotes
the deferred orchestrator's reboot/apply.)

### C4 views
Read all three model files (`model.c4` / `views.c4` / `spec.c4`). **No C4 edit this PR.** The change
adds a build/deploy-plane `workflow_dispatch` path + a gate **script** + docs — no new runtime
container/database. Enumeration checked: actors (`founder` triggers the dispatch — already modeled,
not a new access relationship; `contributor`, `emailSender`) — none new; external systems (`github`
= GHA plane, already modeled + CI is not a runtime container here, consistent with the release
pipeline; `cloudflare` LB/DNS edge — **GA-deferred**; `doppler`) — none new; containers/data-stores
(`hetzner` = web-1/web-2 compute already covers both; `tunnel`; `coordinator`; `gitDataStore` OFF) —
none new; access relationships — none changed (web-2 gets zero LB weight; no cross-host serving).

### Sequencing
ADR amendment authored now (ADR-068 stays `status: adopting`); the weight flip / reboot is the
deferred orchestrator (Phase 5).

## Domain Review

**Domains relevant:** Engineering (CTO — reviewed, findings folded below). Finance/Ops: no new
expense this PR (already recorded). Legal: deferred to GA (no new data processing). Product/UX: none.

### Engineering (CTO)
**Status:** reviewed. **Assessment:** safe-additive (no LB weight / reboot / ingress change on
merge); the gate is fail-closed + SHAPE-ONLY + inert until the orchestrator consumes it. Folded
CTO findings: gate emits `requires_runtime_bind_probe` (config-shape ≠ runtime truth); roster
parser-parity with `loadHostRoster` + web-2-in-roster + allowlist⊆roster; malformed/future/soak-floor
timestamp cases; dropped the tautological source-grep; keep the parity test job-aware (plan-scoped
jq is the real reboot guard); substrate = dispatch branch of the same workflow (shared serializer),
NOT a second workflow. `workspaces_writable` corrected to NOT be the attach proof (code-simplicity +
spec-flow: it passes on the host root fs) — the apply output is.

### Product/UX Gate
**Tier:** none. No user-facing surface (workflow + script + docs only).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `lb-weight-gate.sh` is fail-closed + SHAPE-ONLY: `lb-weight-gate.test.sh` PASSES every case in
      Phase 1 (both-hold→0 incl. `requires_runtime_bind_probe=true` on stdout; every missing/empty/
      malformed/roster-missing-web-2/allowlist⊄roster/unparseable-or-future-timestamp/soak≤0 →
      non-zero; assert exit codes).
- [ ] `apply-web-platform-infra.yml` has `workflow_dispatch apply_target`; the `warm-standby` branch
      `-targets` exactly the 6 resources in the `terraform-apply-web-platform-host` concurrency
      group, runs the plan-scoped destroy-guard (`reboot_updates=0`) before apply, probes web-2
      `:9000` before the trigger, and fails on `reason=~_peer_fanout_degraded`. `actionlint` clean;
      extracted `run:` snippets pass `bash -c`.
- [ ] The plan-scoped `reboot_updates` jq guard covers the warm-standby apply; the parity test stays
      job-aware (P0.4 evidence in PR body: the 6 addresses already in `OPERATOR_APPLIED_EXCLUSIONS`).
- [ ] The multi-host plan Phase 2 + Post-merge + runbook Scope B pre-flight/steps 5–6 are
      de-manualized to the dispatch path; steps 7–10 reference the gate, wrapped in
      `<!-- lint-infra-ignore -->`. **All three files (both docs + THIS plan) PASS
      `lint-infra-no-human-steps.py`** in changed-files mode.
- [ ] `lint-infra-no-human-steps.py` + `.test.sh` exist, wired into `ci.yml` + `lefthook.yml`;
      actor+imperative co-occurrence model; ignore-region + fenced/backtick carve-outs; scan dirs
      include legal/runbooks + decisions; `.test.sh` asserts human-step FAILS, orchestrator-defer
      PASSES, ignore-region PASSES, `tofu apply`-by-operator paraphrase FAILS.
- [ ] `hr-no-ssh-fallback-in-runbooks` strengthened in place with the class clause + a valid
      `[hook-enforced: lefthook lint-infra-no-human-steps.py]` tag; the other two get a cross-ref;
      `wc -c AGENTS.md AGENTS.core.md` ≤ 23000 (before/after in PR body); `lint-agents-enforcement-tags.py`,
      `lint-agents-rule-budget.py`, `lint-rule-ids.py` all green.
- [ ] ADR-068 amendment committed, recording the SHAPE-ONLY gate + the readyz/attach reconciliation
      (assert the amendment TEXT names `requires_runtime_bind_probe` + "apply output = attach proof",
      not just that a commit exists).
- [ ] Learning file written (dir + topic). Deferred orchestrator issue filed (`Ref`, re-eval
      criteria naming the SHAPE-ONLY gate + the separate runtime gate as distinct conditions).
- [ ] PR body uses `Ref #5887 / #5274` (NOT `Closes`).

### Post-merge (dispatch — operator-acknowledged menu trigger, not authored)
- [ ] `gh workflow run apply-web-platform-infra.yml -f apply_target=warm-standby` runs green: apply
      output shows `hcloud_volume_attachment.workspaces["web-2"]` + `hcloud_server_network.web["web-2"]`
      created, `0 change / 0 destroy`, no web-1 reboot; web-1 deploy-status `reason=="ok"` (web-2
      accepted). Pulled via `gh run view` + a `curl` to deploy-status — no dashboard, no SSH.

## Sharp Edges

- **SE-1 — readyz is NOT the warm-standby verification.** Off-host = 403 (`loopback.ts:30-34`),
  empty `/workspaces` = 503, and `workspaces_writable` passes on the host root fallback dir
  (`readiness.ts:30-35`) so it does NOT prove the volume attached. Attach proof = the terraform
  apply's created-resources output; web-2 serve-readiness (docker-exec in-container readyz, N≥2
  consecutive, device-identity) is the deferred orchestrator's on-host pre-pool gate.
- **SE-2 — fan-out is fire-and-forget; probe web-2 `:9000` first.** A fresh
  `hcloud_server_network.web["web-2"]` attach means web-2's private interface + `:9000` may be
  unbound when the fan-out fires → `reason=ok_peer_fanout_degraded`, exit 0. Probe reachability
  before the trigger AND fail the dispatch on the degraded reason.
- **SE-3 — triggering web-2's deploy re-swaps web-1.** `fan_out_to_peers` fires only after web-1's
  own successful swap (`ci-deploy.sh:1320-1325`). Prefer `POST /hooks/deploy` (current version, not
  a new release). Ingress-unchanged and canary-gated, but the "safe additive" claim must acknowledge
  a live-origin redeploy.
- **SE-4 — the doc-lint must not red-line itself or the deferred-orchestrator prose.** Actor+imperative
  co-occurrence (not bare `terraform apply`/`reboot`) + ignore-region markers; this plan + the
  retained runbook steps 7–10 are wrapped. Verify all three files PASS before claiming the AC.
- **SE-5 — the enforcement tag is `hook-enforced`, not `skill-enforced`** (no matching SKILL.md;
  `lint-agents-enforcement-tags.py` validates against `lefthook.yml`). Re-run the budget after the
  tag lands.
- **SE-6 — AGENTS at 22976/23000 (24 B).** Strengthen one rule in place; the lint is the
  enforcement, not the prose. A new id needs a named funding trim (not worth it). Re-measure per edit.
- **SE-7 — the §(c) gate is SHAPE-ONLY.** Exit 0 proves config-shape in Doppler, NOT that a listener
  bound or the container env is live. It emits `requires_runtime_bind_probe=true`; the deferred
  orchestrator MUST satisfy a separate on-host runtime gate before any weight flip. The soak marker's
  writer is deferred — "not satisfied" today is the correct fail-closed default.
- **SE-8 — `## User-Brand Impact` empty/`TBD`/threshold-less fails deepen-plan Phase 4.6.** Filled;
  keep it filled.

## Open Questions
1. **RESOLVED (topology, spec-flow P0-1):** web-2 is verified off-host via web-1's deploy-status
   `reason` (web-2-accepted) + the apply's attach output — NOT a dedicated verify-status endpoint
   (would need a web-2 CF-Access hostname; deferred if stronger in-PR web-2 verification is later
   wanted). No off-host reachability to `10.0.1.11`.
2. Minimal-blast deploy trigger: `POST /hooks/deploy` (current version, re-swaps web-1) — is there a
   web-2-only deploy path that avoids the web-1 re-swap? Decide at /work after reading the webhook
   payload contract (P0.2).
3. **RESOLVED:** §(c) Condition B drops the source-grep sentinel (tautology); keeps
   `GIT_DATA_STORE_ENABLED` + the soak marker. AGENTS Phase 4 strengthens one rule in place.
