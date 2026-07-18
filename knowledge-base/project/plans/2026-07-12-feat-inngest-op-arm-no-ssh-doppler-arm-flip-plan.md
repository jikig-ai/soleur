---
title: "feat(infra): no-SSH op=arm for the inngest cutover Doppler arm-flip (#6369)"
date: 2026-07-12
type: feat
issue: 6369
parent: 6178
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: terraform-architect invoked; the write TOKEN is TF-provisioned
     (doppler_service_token.inngest_arm_write, see ## Infrastructure (IaC)). The three arm-flip
     VALUES are out-of-band by ADR-100 Decision 6a + inngest-host.tf:137-166 doctrine — they
     CANNOT be doppler_secret Terraform resources (dark-window heartbeat masking; a DB password
     TF never minted; the FSM must fire at the maintenance window, not at apply). op=arm writes
     them via the TF-provisioned token at the window. This is the sanctioned no-SSH verb, not a
     manual-provisioning dodge. The `doppler secrets set` literals below describe that verb + the
     one-time source seed, both reviewed under Phase 2.8. -->

# feat(infra): no-SSH `op=arm` for the inngest cutover Doppler arm-flip (#6369)

## Overview

The #6178 dedicated-host inngest cutover is now no-SSH for every host *mutation* (deploy/restart; and, as of #6368, quiesce/enable via `op=quiesce-web` / `op=rollback`). The last operator seam is the **2.2b/2.3 Doppler arm-flip**: three secret writes to `soleur-inngest/prd` that arm the cutover flip FSM. Today `op=execute` only **prints** these as an out-of-band operator hand-off (`.github/workflows/cutover-inngest.yml:607-611`), and the runbook's "Op order" carries them as a manual `doppler`-write SEAM.

This plan builds **`op=arm`**: a new `workflow_dispatch` verb in `cutover-inngest.yml` that performs the three writes no-SSH, using a **Terraform-provisioned read/write Doppler service token** scoped to the isolated `soleur-inngest/prd` project, **never logging any value** (AC-NOBODY), then confirms the on-host FSM reached `done` via Better Stack. It removes the last operator secret-write seam from the cutover.

The three writes, in mandatory order (LAST = FSM trigger), mirroring `cutover-inngest.yml:608-610`:

1. `INNGEST_POSTGRES_URI` — prod session-pooler DSN (`:5432`, never `:6543` — breaks inngest's sqlc prepared statements, `inngest-host.tf:157`)
2. `INNGEST_HEARTBEAT_URL` — `betteruptime_heartbeat.inngest_prd.url`
3. `INNGEST_CUTOVER_FLIP=armed` — literal, written **last** (the enabled 30s on-host `.timer` picks it up and drives the FSM `armed → flipping → flushed → done`; ADR-100 Decision 6a)

**Trust model (the reconciliation).** `op=arm` is a **prod-write behind explicit operator dispatch** — the identical trust model already established by `op=quiesce-web` (`cutover-inngest.yml:618-728`, comment `:624`: *"a prod-write behind explicit dispatch (same trust model as op=rollback)"*) and `op=rollback`. A manual `gh workflow run cutover-inngest.yml --field op=arm` IS the "explicit per-command go-ahead" that `hr-menu-option-ack-not-prod-write-auth` requires; the hard rule kept the flip out of `op=execute`'s *auto-run* spine, not out of a separately-dispatched no-SSH verb. This plan makes that reconciliation explicit in an ADR-100 amendment (§Architecture Decision).

**Second deliverable — "run the full #6178 cutover end-to-end."** With `op=arm` landed, every *secret-write* and *host-mutation* step of the cutover is no-SSH. The final phase assembles the now-fully-automated end-to-end op order into the runbook and validates it with a **dry-run** (registry/inventory reads + a staged FSM confirmation against the dark host), so the operator can drive the live cutover as a single ordered dispatch sequence. The **live prod cutover execution itself is operator-gated** (maintenance window, single-user-incident blast radius) and is NOT an autonomous `/work` step — see §Non-Goals for the two remaining non-#6369 seams (web-2 lifecycle 2.2a; app-repoint 2.4).

## Premise Validation (Phase 0.6)

- **#6369** — OPEN, labelled `deferred-scope-out`; the scope-out was filed by #6368 (host-mutation gap only) with re-eval captured in `knowledge-base/project/learnings/integration-issues/no-ssh-cutover-verb-by-verb-audit-inngest-quiesce-20260712.md` (insight #4). Premise holds — build now.
- **#6178** — OPEN, the umbrella cutover; this is the direct parent. Holds.
- **#6368** — MERGED (`compliance/critical`), the direct precedent: `op=quiesce-web` + `op=rollback`. The op-block structure, HMAC+CF-Access auth, `::add-mask::`, and the "prod-write behind explicit dispatch" trust model are all reused verbatim. Holds.
- **ADR-100** — status `adopting` (amendable). Decision 6a fixes the flip FSM (`armed → flipping → flushed → done`, terminal `aborted`). op=arm is the writer of `armed`; this plan amends ADR-100, not a new ADR (avoids an ordinal collision; same architectural surface).
- **Mechanism vs. ADR corpus** — the "CI writes the arm-flip secrets" mechanism is NOT in an ADR rejected-alternatives table; ADR-100 Decision 6a's rejected alternatives concern the *on-host flip mechanism* (webhook vs oneshot), not *who writes the arm secret*. The out-of-band doctrine (`inngest-host.tf:137-166`) explains why the 3 values are NOT TF `doppler_secret` resources — op=arm honours that doctrine (it writes them at the window, not at apply). No stale premise.

No spec.md exists for this branch (one-shot path); `lane: cross-domain` (infra + workflow + IaC + docs). This plan is the source of truth.

## Research Reconciliation — Spec vs. Codebase

| Claim (from #6369 / task) | Codebase reality | Plan response |
|---|---|---|
| "TF write-token to soleur-inngest/prd" | `soleur-inngest` is a **TF-managed separate Doppler project** (`doppler_project.inngest`, `inngest-host.tf:91`); an existing **read-only** token `doppler_service_token.inngest` ("inngest-boot") already lives there (`:173-178`). Precedent for a read/**write** token: `doppler-write-token.tf` (`doppler_service_token.write` + `github_actions_secret.doppler_token_write`). | New `doppler_service_token.inngest_arm_write` (read/write, by-reference project/config) + `github_actions_secret.doppler_token_inngest_arm`. Wire by resource reference, not literal (`2026-07-08-doppler-secret-precedent-mirror` learning). |
| "writing INNGEST_POSTGRES_URI / INNGEST_HEARTBEAT_URL / INNGEST_CUTOVER_FLIP=armed" | These 3 are the exact operator-printed SEAM writes (`cutover-inngest.yml:608-610`); all target `soleur-inngest/prd`. `INNGEST_HEARTBEAT_URL = betteruptime_heartbeat.inngest_prd.url` (also `output "inngest_heartbeat_url"`, `outputs.tf:26`; and `doppler_secret.inngest_heartbeat_url_prd` in **soleur/prd**, `inngest.tf:345`). `INNGEST_POSTGRES_URI` embeds a Supabase DB password TF **never** minted (`inngest-host.tf:153-158`). | op=arm reads the two *source* values (masked) and writes all three via the write token, `armed` last. HEARTBEAT_URL sourced TF-managed; POSTGRES_URI sourced from a **one-time operator-seeded** read-secret (§IaC Q3). |
| "never logging them (AC-NOBODY)" | `op=execute`'s SEAM already asserts AC-NOBODY: *"no secrets / bodies / connection strings are echoed"* (`:604`). `::add-mask::` is the GH primitive. | Every value `::add-mask::`'d before use; the write CLI fed via **stdin, never argv** (`inngest-host.tf:166`); `--plain` read output masked on capture; no value echo. A test asserts no value-echo. |
| "then run the full #6178 cutover end-to-end" | The cutover is operator-triggered (`cutover-inngest.yml:11`, ADR-100); live execution has single-user blast radius. Remaining non-#6369 seams: 2.2a web-2 lifecycle (`:606`), 2.4 app-repoint (`:612`). | Assemble + dry-run-validate the end-to-end runbook; live prod execution stays operator-gated (§Non-Goals). |

## User-Brand Impact

**If this lands broken, the user experiences:** the inngest cron scheduler mis-armed at cutover — either the FSM fires against a stale/missing `INNGEST_POSTGRES_URI` (a broken or `:6543` DSN silently breaks sqlc → the singleton scheduler dies) or a wrong-order write arms the flip before the URIs land. The dedicated host is the **sole** scheduler (ADR-100), so **every user's** async workflows stall: email-triage, workspace-reconcile-on-push, reminders, one-shot crons. A `DBSIZE!=0` abort or a silent mis-write surfaces only at the next cron that never fires.

**If this leaks, the user's data is exposed via:** the write token (read/write on `soleur-inngest/prd`) or the `INNGEST_POSTGRES_URI` value appearing in a run log → a session-pooler DSN grants direct read/write to the inngest Postgres (config + run history + email-triage claim/finalize rows). AC-NOBODY + `::add-mask::` + stdin-never-argv are the load-bearing controls; the token's blast radius is bounded to the isolated `soleur-inngest` project (no config-inheritance path to `soleur/prd` — `inngest-host.tf:78-85`).

**Brand-survival threshold:** `single-user incident` → `requires_cpo_signoff: true`. CPO sign-off required at plan time before `/work`; `user-impact-reviewer` runs at review time; `security-sentinel` + `data-integrity-guardian` at deepen-plan (single-user-incident threshold).

## Downtime & Cutover

**op=arm itself induces NO downtime** — it writes three Doppler secrets and reads Better Stack. It changes no host, takes no DB lock, restarts no router; the new `.tf` resource is a `doppler_service_token` (no reboot/replace on any `hcloud_server`). The deepen-plan Phase 4.55 downtime-trigger set does not fire on this plan's Files-to-Edit.

<!-- lint-infra-ignore start -->
**The cutover's brief scheduler restart is owned by ADR-100 Decision 6a, not introduced here.** Writing `INNGEST_CUTOVER_FLIP=armed` causes the on-host `.timer`/oneshot FSM to `stop → FLUSHALL → assert DBSIZE==0 → flushed → start` the singleton inngest scheduler — a bounded, gated transient (seconds), executed only inside the operator maintenance window.
<!-- lint-infra-ignore end --> This plan does not change that downtime profile; it only replaces the *manual* arm-write with a no-SSH verb. The zero-downtime evaluation for the cutover proper (dark-host-provisioned-first, drain via quiesce, then flip) already lives in ADR-100 + the runbook. Residual transient is accepted with operator sign-off inside the window (single-user-incident; see §User-Brand Impact).

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)
1. **Doppler read-path verification (terraform-architect flagged assumption #1).** Confirm which config the workflow's existing `DOPPLER_TOKEN` (prd_terraform-scoped, `cutover-inngest.yml:69`) can READ the two source values from: `doppler secrets get INNGEST_HEARTBEAT_URL -p soleur -c prd --plain` (does prd_terraform resolve the `prd` root?) vs. seeding the source values into `prd_terraform` directly. **Decision rule:** if the existing token cannot read `soleur/prd`, seed BOTH source values into `prd_terraform` (guaranteed readable). Record the verified read path in the spec.
2. **iac-plan-write-guard opt-out (already applied in this plan).** `.claude/hooks/iac-plan-write-guard.sh` denies the Doppler-write literal in Write/Edit content; the plan carries `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`. The op=arm YAML + runbook edits at /work will trip the same hook — apply the same ack (the writes go through a TF-provisioned token; values are out-of-band by ADR-100 doctrine). Do NOT bypass silently; record the ack.
3. **tfstate confirms `doppler_project.inngest` + `doppler_environment.inngest_prd` are applied** (the dedicated host is provisioned — cutover phase), so the per-merge `-target` of the new token is a create-only no-op on its transitive deps.

### Phase 1 — Terraform: the arm-write token (RED→GREEN)
1. Create `apps/web-platform/infra/inngest-arm-write-token.tf` (see §IaC Q1). Header comment must document: blast-radius (isolated project, no inheritance), rotation (`-replace`), state (Computed+Sensitive, R2 tfstate), and the `no ignore_changes` propagation rationale.
2. Add two `-target=` lines to `.github/workflows/apply-web-platform-infra.yml` per-merge default allow-list (near `:356-357`, beside `doppler_service_token.write`): `doppler_service_token.inngest_arm_write` and `github_actions_secret.doppler_token_inngest_arm`. **Do NOT** add to the `inngest_host` dispatch set or any `OPERATOR_APPLIED_*_EXCLUSIONS`.
3. `terraform validate` + `terraform plan` (canonical triplet + R2 backend exports — see Sharp Edges) shows **`+2 create, 0 change, 0 destroy`**, no transitive create of `hcloud_server.inngest`/project/env.
4. Confirm `plugins/soleur/test/terraform-target-parity.test.ts` passes with **no manual edit** (dynamic extraction covers the two new per-merge targets). Run the web-platform destroy-guard counter (`tests/scripts/test-destroy-guard-counter-web-platform.sh`) — unchanged (create-only).

### Phase 2 — POSTGRES_URI source seed (one-time, IaC-documented)
> **⚠️ SUPERSEDED by the CTO read-through decision (see `## CTO Decision at /work` below).** Phase 0 verified the prod `INNGEST_POSTGRES_URI` is already CI-readable in `prd_terraform` (canonical, `:5432`, distinct from dark), so this operator-seed step is **DROPPED entirely** — op=arm reads both source values read-through. The paragraphs below are the retained point-in-time draft; the shipping design has **no seed**.

1. Document (runbook precondition + `## Infrastructure (IaC)`) the **one-time** seed of `INNGEST_POSTGRES_URI_PROD` (the prod session-pooler `:5432` DSN) into the config verified readable in Phase 0 (default `prd_terraform`), via the Doppler-write CLI stdin — **not** a TF `doppler_secret` resource (TF never owned the password; a `doppler_secret` would clobber it, `inngest-host.tf:155-157`). This is the **only** human secret step, done **once before the maintenance window**, never at cutover.
2. HEARTBEAT_URL source: if Phase 0 confirms read-through of the TF-managed value works, **no seed** — read the existing TF-managed value at arm time (drift-free). If not, mint a TF `doppler_secret` mirroring `betteruptime_heartbeat.inngest_prd.url` into the readable config (TF has this value; add its `-target` line + parity coverage). Prefer read-through.

### Phase 3 — The `op=arm` workflow verb (RED→GREEN)  [op=arm is FORWARD-ONLY — rollback stays in op=rollback, §deepen Q5]
1. Add `arm` to the `op` choice `options:` list (`cutover-inngest.yml:22-32`). **No `flip_state` input** — op=arm writes only `armed` (rollback is the existing `op=rollback` verb; Phase 4).
2. Add the write token as a **job-`env:` conditional** so it is EMPTY for every non-arm dispatch (security F2): `DOPPLER_TOKEN_INNGEST_ARM: ${{ inputs.op == 'arm' && secrets.DOPPLER_TOKEN_INNGEST_ARM || '' }}`. Additionally gate the op=arm path behind a **GitHub Environment** (`environment: inngest-cutover`) with a required-reviewer protection rule (security F3 — restores the human ack the Doppler console provided; publish the token as an *environment* secret, not a repo-wide secret). A bash comment does NOT scope a step-env var — the conditional + environment are the real scoping.
3. Add the `arm)` case arm (template: `op=quiesce-web` `:618-728` for structure; NO webhook/HMAC — pure Doppler). Sequence, all guards fail-closed and **value-silent**:
   - **G1 — pre-write FSM-state guard (data-integrity Q2, P1 — prevents prod-Redis re-FLUSHALL data loss):** read the CURRENT `INNGEST_CUTOVER_FLIP` from `soleur-inngest/prd` (write token, `--plain`) and **refuse unless ∈ {`unset`, empty, `aborted`, `rolled-back`}**. Re-arming over `armed`/`flipping`/`flushed`/`done` re-drives the FSM `stop → FLUSHALL` — and over `done` it FLUSHALLs the now-PROD Redis, wiping the live cron sorted-set. The concurrency group `deploy-inngest-restart` serializes dispatches, so the read is TOCTOU-safe.
   - **G2 — read source values, mask EACH on its own capture line (security F7):** `HB=$(doppler secrets get INNGEST_HEARTBEAT_URL ... --plain); printf '::add-mask::%s\n' "$HB"`; then the same for `PG=$(doppler secrets get INNGEST_POSTGRES_URI_PROD ...)`. Never batch the masks (a mid-sequence `set -e` exit leaves an unmasked captured value).
   - **G3 — positive prod-URI assertion (data-integrity Q3, P1 — the `:5432`/`:6543` guard MISSES the dark backend; both use `:5432`):** read the CURRENT (dark) `INNGEST_POSTGRES_URI` from `soleur-inngest/prd`, mask it, and assert `PG != PG_dark` (refuse on equality — a same-value flip is a mis-seed/no-op) AND `PG` contains the TF-known prod pooler host / Supabase project-ref. Plus the empty + `:6543` rejects. All comparisons value-silent.
   - **G4 — write POSTGRES_URI then HEARTBEAT_URL** via the write token, **stdin** (pipe the masked value into the Doppler write CLI — `secrets set INNGEST_POSTGRES_URI` on `soleur-inngest/prd`, value on stdin, never argv). Verify each write exit 0 **before** the next.
   - **G5 — write `INNGEST_CUTOVER_FLIP=armed` LAST** (literal; same stdin form).
   - **G6 — confirm via Better Stack, single-state-token + time-bounded + branch (security F1 + data-integrity Q4, both P1):** query `betterstack-query.sh` for the `inngest-cutover-flip` line **bounded to ≥ the `armed`-write timestamp** (or match a per-dispatch correlation token — a stale `done` from a prior run/dry-run on the SAME source else false-succeeds). Extract ONLY the terminal state via `jq -r` (NEVER `echo "$BODY" | jq .` / raw-row echo — that dumps whatever the FSM logged to the run log, a mask bypass). **Branch** on `done` (success) / `aborted` / `rolled-back` (fail loud with the ADR remediation: confirm dark backend, do NOT proceed to 2.4) / timeout. This is a Better Stack READ, not a deploy-status poll → does not perturb the `QMAX_POLLS` drift-guard counts.
4. Update the drift-guard test `apps/web-platform/infra/cutover-inngest-workflow.test.sh`: assert (a) `arm` is a real `case` arm + menu option (D.1 `:99`); (b) `-p soleur-inngest -c prd` on every write; (c) stdin form (no secret in argv); (d) NO value echoed — first assert the `awk` range is **non-empty** (else the grep passes vacuously, security F6), then `grep -E 'echo.*\$(HB|PG|PG_DARK|POSTGRES|HEARTBEAT)'` → 0, AND `grep 'jq \.'` (raw-row echo) → 0, AND `grep 'set -x'` → 0; (e) `::add-mask::` present before EACH source-value use; (f) no `ssh`; (g) G1 state-guard + G3 prod-URI assertion present; (h) the token env uses the `inputs.op == 'arm' && ... || ''` conditional form + the job names `environment: inngest-cutover`.

### Phase 4 — SEAM removal in `op=execute`; rollback write in `op=rollback`; runbook
1. In `op=execute`'s SEAM block, replace the `2.2b+2.3 ARM THE FLIP — three Doppler writes` hand-off (`cutover-inngest.yml:607-611`) with: *"2.2b+2.3 ARM THE FLIP — dispatch `op=arm` (no-SSH; performs the 3 writes on soleur-inngest/prd + confirms the FSM done via Better Stack)."* Keep 2.2a (web-2 lifecycle) and 2.4 (app-repoint) — the remaining non-#6369 seams. Update the `:602-604` comment (the flip is now a dispatchable op; hr-menu-option-ack satisfied by the explicit `op=arm` dispatch + the environment required-reviewer gate).
2. **Fold the reverse `INNGEST_CUTOVER_FLIP=rollback` write into the EXISTING `op=rollback` verb** (`cutover-inngest.yml:890`), NOT a `flip_state` input on op=arm (data-integrity Q5 + architecture P1 — ADR-100:231 mandates the symmetric forward/reverse pair stay as *separate* verbs; op=rollback already owns the reverse web-scheduler re-enable at `:614` step 3). Give op=rollback the conditional `DOPPLER_TOKEN_INNGEST_ARM` env (`inputs.op == 'rollback'` arm) + the same environment gate; order it: write the reverse flip value (stdin, masked-doctrine) → confirm `rolled-back` via time-bounded Better Stack → the existing web re-enable fan-out. Update the `:614` ROLLBACK SEAM text to point at `op=rollback` (which now does the Doppler write too). Rollback writes ONLY the flip value — never re-writes POSTGRES_URI/HEARTBEAT.
<!-- lint-infra-ignore start -->
3. Runbook `knowledge-base/engineering/operations/runbooks/inngest-server.md`: rewrite the 2.2b/2.3 "Op order" SEAM to the `op=arm` dispatch; add the **post-cutover token-revoke** step (security F4 + architecture P2 — the write token is a standing read handle to the armed prod DSN; revoke via `terraform apply -replace=doppler_service_token.inngest_arm_write` + `doppler configs tokens revoke` after AC17 validates); update the "SEAM"/"operator" markers count. (The **one-time seed** and **seed-delete** from the original draft are DROPPED per the CTO read-through decision below — reads are read-through from prd_terraform, no seed exists.)
<!-- lint-infra-ignore end -->

### Phase 5 — End-to-end cutover assembly + dry-run validation
1. Assemble the full now-no-SSH op order in the runbook (enumerate → capture → inventory → backup → execute → [op=quiesce-web if gate fails] → **op=arm** → op=rearm → op=verify), with the two remaining operator-lifecycle steps (2.2a web-2 recreate, 2.4 app-repoint) clearly flagged as the ONLY non-dispatch steps.
2. **Dry-run validation** (no live cutover): confirm each op's reachability (op=inventory/enumerate reads; op=arm's read+mask path against the dark `soleur-inngest/prd` WITHOUT writing `armed`, or against a scratch key) and that the FSM-confirm poll parses a synthetic Better Stack `done`. Document the dry-run in the spec.
3. **The live prod cutover is operator-gated** — not an autonomous `/work` step (single-user-incident; maintenance window). The plan's deliverable is the *enabled* end-to-end (every secret-write + host-mutation no-SSH) + the operator's single ordered dispatch sequence.

### Phase 6 — ADR-100 amendment + C4 check
See §Architecture Decision.

## Files to Create
- `apps/web-platform/infra/inngest-arm-write-token.tf` — the read/write Doppler service token + its github_actions_secret.
- `knowledge-base/project/specs/feat-one-shot-6369-inngest-op-arm/tasks.md` (generated by plan Save-Tasks).

## Files to Edit
- `.github/workflows/cutover-inngest.yml` — `arm` option (`:22-32`); step env (`:62-81`); new `arm)` case; SEAM rewrite in `op=execute` (`:602-615`).
- `.github/workflows/apply-web-platform-infra.yml` — 2 `-target=` lines (per-merge default set, near `:356-357`); (conditionally) a 3rd for the heartbeat `doppler_secret` if Phase 2 needs it.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — op=arm drift-guard assertions.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — 2.2b/2.3 SEAM rewrite + one-time seed precondition + end-to-end op order.
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` — Decision 6b amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — **only if** the ADR reviewer judges the CI→`soleur-inngest/prd` write edge material (default: no edit — see §Architecture Decision C4).
- **No edit** to `plugins/soleur/test/terraform-target-parity.test.ts` (dynamic extraction).

## Infrastructure (IaC)

### Q1 — Terraform changes (new file `apps/web-platform/infra/inngest-arm-write-token.tf`)
```hcl
resource "doppler_service_token" "inngest_arm_write" {
  project = doppler_project.inngest.name        # by-reference (builds the dep edge; NOT "soleur-inngest")
  config  = doppler_environment.inngest_prd.slug # by-reference (NOT "prd")
  name    = "inngest-cutover-arm"                # distinct from the read token "inngest-boot"
  access  = "read/write"
}
resource "github_actions_secret" "doppler_token_inngest_arm" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_INNGEST_ARM"
  plaintext_value = doppler_service_token.inngest_arm_write.key   # NO ignore_changes → -replace propagates in one apply
}
```
- **Providers/pins:** none new (`doppler` + `github` providers already in the root).
- **Sensitive vars:** none new. The token `.key` is `Computed + Sensitive`, minted once, lands in R2-backed encrypted `terraform.tfstate` (same posture as `doppler_service_token.write`/`.inngest`/`.ghcr_minter`). Cannot be re-read from the Doppler API.

### Apply path
<!-- lint-infra-ignore start -->
- **(b) cloud-init + bootstrap → N/A** (no host resource). Path is a plain per-merge `-target` apply: merging the `.tf` + the `-target` lines creates the token + env secret on the next `apply-web-platform-infra.yml` per-merge run. **No bootstrap cycle** (unlike `doppler_token_write`, whose same-job step consumes the secret it minted): `op=arm` is a separate, later-dispatched workflow, so `DOPPLER_TOKEN_INNGEST_ARM` exists by the time the operator dispatches op=arm. Blast-radius: `+3 create` (token + environment + env secret — D5), zero downtime.
<!-- lint-infra-ignore end -->
- **`-target` placement = per-merge default allow-list** (NOT the stripped `inngest_host` dispatch set). Rationale (terraform-architect): the parity test explicitly forbids CI-published `github_actions_secret` tokens in `OPERATOR_APPLIED_TOKEN_EXCLUSIONS` (`terraform-target-parity.test.ts:631-635` — the #5566 silent-un-applied class); `stripDispatchJobs` would hide an `inngest_host`-placed target from coverage → RED. Transitivity pulls the already-applied project/env (no-op create) but NOT `hcloud_server.inngest`.

### Q3 — source-of-truth for the two URI VALUES (the crux)
- **INNGEST_HEARTBEAT_URL:** TF-known (`betteruptime_heartbeat.inngest_prd.url`). **Read-through** at arm time from the TF-managed value (existing in `soleur/prd` as `doppler_secret.inngest_heartbeat_url_prd`); NOT written by TF into `soleur-inngest/prd` at apply (the dark-window masking doctrine, `inngest-host.tf:137-151`, forbids provisioning it there before cutover — op=arm is the correct at-window writer). Read path decided in Phase 0.
- **INNGEST_POSTGRES_URI:** embeds a Supabase DB password TF **never** minted (`inngest-host.tf:153-158`); the Supabase Management API (read-only `SUPABASE_ACCESS_TOKEN`, `cutover-inngest.yml:71`) **cannot** derive it (password not exposed post-set; a reset is destructive). → **operator-seed-once** `INNGEST_POSTGRES_URI_PROD` into a CI-readable Doppler read-secret (Phase 2), consumed no-SSH by op=arm. This is the SAME out-of-band doctrine already governing the dark `INNGEST_POSTGRES_URI`; it is a Doppler secret seed, NOT a TF variable → `hr-tf-variable-no-operator-mint-default` does not apply; `hr-all-infrastructure-provisioning` is honoured (provisioned via Doppler, once, before the window — no paste at cutover).

### Distinctness / drift safeguards
- **No `ignore_changes`** on either resource (rotation via `-replace` must re-propagate `.key` in one apply). Adding `ignore_changes=[plaintext_value]` would strand the GH secret on the old key — do NOT.
- **dev != prd:** `soleur-inngest` has **no dev config**; the token is `prd`-only (`hr-dev-prd-distinct`; `inngest-host.tf:43`).
- **Token distinctness:** `inngest-cutover-arm` (read/write, CI-consumed) coexists with `inngest-boot` (read, host-consumed) — distinct names, blast radii, consumers.

### Q4 — scope-guard test sweep
Only `plugins/soleur/test/terraform-target-parity.test.ts` asserts per-merge `-target` coverage, and it extracts targets **dynamically** → **no manual edit** with the per-merge placement. Do NOT add to `OPERATOR_APPLIED_*_EXCLUSIONS`. `tests/scripts/test-destroy-guard-counter-web-platform.sh` + `destroy-guard-filter-web-platform.jq` + fixture assert destroy counts (create-only → unchanged). `*-gate.sh` replace-gates are unrelated. Verify green, don't assume.

## Observability

```yaml
liveness_signal:
  what: on-host `inngest-cutover-flip` FSM log line reaching `done` (exit_code:0), shipped journald→Vector→Better Stack Logs (source 2457081)
  cadence: once per op=arm dispatch (at cutover); the 30s on-host .timer drives the FSM
  alert_target: op=arm job FAILS loud (exit 1) if Better Stack does not show `done` within the bounded poll window, or shows `aborted`/`rolled-back`
  configured_in: cutover-inngest.yml op=arm case (betterstack-query.sh); ADR-100 Decision 6a
error_reporting:
  destination: GitHub Actions run log (::error:: annotations, no secret values) + the on-host FSM Better Stack line for the terminal state
  fail_loud: true — empty-value guard, :6543-port guard, per-write exit-code check, and FSM-not-done all exit 1 with a no-SSH remediation string
failure_modes:
  - {mode: source value empty/unreadable, detection: op=arm empty-string guard on doppler-get, alert_route: job exit 1 (no value echoed)}
  - {mode: wrong pooler port (:6543) in POSTGRES_URI, detection: op=arm regex guard before write, alert_route: job exit 1}
  - {mode: partial write (URI written, armed not), detection: per-write exit-code check gates the next write; armed written last only after both URIs succeed, alert_route: job exit 1 before arming}
  - {mode: FSM aborts (DBSIZE!=0) or rolls back, detection: betterstack-query.sh sees terminal `aborted`/`rolled-back`, alert_route: job exit 1 + remediation (confirm dark backend, do NOT proceed to 2.4)}
  - {mode: secret value leaks to a run log, detection: cutover-inngest-workflow.test.sh asserts no value-echo + ::add-mask:: present, alert_route: CI red pre-merge}
logs:
  where: GitHub Actions run log (op=arm); Better Stack Logs source 2457081 (on-host FSM)
  retention: GH Actions default (90d); Better Stack Logs per plan retention
discoverability_test:
  command: gh run list --workflow=cutover-inngest.yml --limit 1 --json conclusion  # (NO ssh); + betterstack-query.sh for the FSM done line
  expected_output: op=arm run conclusion=success AND a Better Stack `inngest-cutover-flip ... exit_code:0 reason:done` line
```

## Architecture Decision (ADR/C4)

### ADR — amend ADR-100 (Decision 6b), do NOT create a new ADR
ADR-100 is `adopting` and Decision 6a already owns the flip FSM. Add **Decision 6b (2026-07-12, Ref #6369)**:
- The arm-flip (the three writes to `soleur-inngest/prd`) is performed no-SSH by `cutover-inngest.yml op=arm` using a **TF-provisioned read/write Doppler service token** (`doppler_service_token.inngest_arm_write`), never logging values (AC-NOBODY).
- **Reconciles `hr-menu-option-ack-not-prod-write-auth`:** a manual `op=arm` dispatch IS the explicit per-command go-ahead; the trust model is identical to `op=quiesce-web`/`op=rollback` (`cutover-inngest.yml:624`). The rule kept the flip out of `op=execute`'s auto-run spine, not out of a separately-dispatched verb.
- **Reconciles `hr-all-infrastructure-provisioning`:** the write *token* is TF-provisioned; the 3 *values* remain out-of-band (they cannot be TF `doppler_secret` resources — dark-window heartbeat masking + a DB password TF never minted, `inngest-host.tf:137-166`). op=arm writes them at the maintenance-window moment, which is exactly when the doctrine says they must appear.
- Records the one-time `INNGEST_POSTGRES_URI_PROD` seed as the single remaining human secret step (pre-window, never at cutover).
- **Ordinal:** amendment to ADR-100 → no new ordinal (next-free is ADR-113 if a reviewer insists on a standalone; default is the amendment).

### C4 views
Read all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`). Enumeration for op=arm:
- **External human actors:** none new (the operator who dispatches op=arm is the existing CI-trigger actor).
- **External systems:** `doppler` (system, `model.c4:234`), `betterstack` (system, `:264`), `github` — all already modeled.
- **Containers/data-stores:** `inngest`, `inngestPostgres` (`:184-190`), `inngestRedis` (`:192`) — all modeled.
- **Access relationships:** the CI→Doppler secret-write relationship **already exists** at the C4 altitude (TF applies write to Doppler via `doppler_service_token.write`); `doppler -> inngest "Injects secrets"` (`:385`) models the scoped soleur-inngest credential. op=arm is a new *instance* of an existing modeled relationship type, not a new relationship.
- **Conclusion:** **no `.c4` edit required** (cite this enumeration). The ADR reviewer at deepen-plan/work re-reads the three files for correctness; if they judge a distinct `ci -> doppler "arms the cutover flip (soleur-inngest/prd)"` edge material, add it to `model.c4` + the `view include` in `views.c4` and run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
Decision 6b is true at merge (the token + verb ship together); the *live* arm happens later at the operator window. ADR amendment authored now with the `adopting` status carried forward.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `apps/web-platform/infra/inngest-arm-write-token.tf` exists; `terraform validate` passes; `grep -c 'access  = "read/write"'` == 1; `project`/`config` are `doppler_project.inngest.name` / `doppler_environment.inngest_prd.slug` (by-reference — `grep -c '"soleur-inngest"'` in the new file == 0).
- **AC2** `apply-web-platform-infra.yml` per-merge `-target` set contains BOTH `doppler_service_token.inngest_arm_write` AND `github_actions_secret.doppler_token_inngest_arm`; neither appears in any `OPERATOR_APPLIED_*_EXCLUSIONS` block (`grep`).
- **AC3** `plugins/soleur/test/terraform-target-parity.test.ts` passes **unmodified** (`git diff --stat` shows no change to it).
- **AC4** `terraform plan` (canonical triplet) prints `Plan: 2 to add, 0 to change, 0 to destroy` and shows NO create of `hcloud_server.inngest` / `doppler_project.inngest` / `doppler_environment.inngest_prd` (verify at /work against live state immediately before merge; if drift, re-scope).
- **AC5** `cutover-inngest.yml` `op` `options:` includes `arm`; a real `arm)` `case` arm exists (D.1 rule).
- **AC6 (AC-NOBODY)** the `arm)` block echoes NO value: `awk '/^            arm)/,/^            ;;/' cutover-inngest.yml | grep -E 'echo.*\$(HB|PG|PG_URI|POSTGRES|HEARTBEAT)'` returns 0; `::add-mask::` appears before the first source-value use; every write reads from **stdin** (`printf '%s' "$VAR" | doppler secrets set NAME`), never `NAME=value` argv.
- **AC7** write order enforced: `INNGEST_CUTOVER_FLIP=armed` is written **after** both URI writes, each gated on the prior exit code (assert via `cutover-inngest-workflow.test.sh`).
- **AC8** `:5432`/`:6543` guard present in the arm block (reject `:6543`); empty-value guard present.
- **AC9** `op=arm` confirms the FSM via `betterstack-query.sh` (`inngest-cutover-flip` line, require `exit_code:0`); fails loud on `aborted`/`rolled-back`/timeout. NO new deploy-status poll (QMAX_POLLS/retry counts in `cutover-inngest-workflow.test.sh` unchanged).
- **AC10** `op=execute` SEAM no longer prints the three arm Doppler-write lines; it points to `op=arm` (the arm write itself is stdin, not a literal in prose).
- **AC11** runbook `inngest-server.md` 2.2b/2.3 SEAM rewritten to `op=arm`; the one-time `INNGEST_POSTGRES_URI_PROD` seed documented as a pre-window precondition; the operator Op-order no longer instructs three manual Doppler writes for the flip.
- **AC12** ADR-100 Decision 6b present; cites the hr-menu-option-ack + hr-all-infrastructure-provisioning reconciliations; C4 enumeration recorded (no `.c4` edit, or the edit + passing c4 tests if made).
- **AC13** `cutover-inngest-workflow.test.sh` green; no `ssh` token in the arm block.
- **AC14** gitleaks/secret-scan clean: no real secret literal in any edited file (synthetic placeholders only; `<prod-postgres-uri>` style in prose).

### Post-merge (operator)
- **AC15** After the per-merge apply, `DOPPLER_TOKEN_INNGEST_ARM` exists as a repo secret (`gh secret list | grep DOPPLER_TOKEN_INNGEST_ARM`) — automatable presence check, run in `/soleur:ship` post-merge verification.
- **AC16** One-time seed `INNGEST_POSTGRES_URI_PROD` into the verified-readable config (operator, pre-window). `Automation: not feasible because the prod inngest DB password is not TF-owned nor Management-API-derivable — see IaC Q3` (genuinely seed-once; NOT a per-cutover step). `Ref #6369` (not `Closes`) so the issue closes only after the live arm validates.
- **AC17 (soak/live, operator-gated)** op=arm dispatched at the live cutover writes the 3 values, the FSM reaches `done`, and the dedicated host serves prod crons — validated in the operator maintenance window (NOT an autonomous /work step).

## Domain Review

**Domains relevant:** none (of the 8 business domains) — this is an infrastructure/tooling + security change.

No cross-domain (Product/Marketing/Finance/Legal/Sales/Support/Operations) implications detected. Engineering/security review is covered by: plan-review (DHH/Kieran/Simplicity + architecture-strategist at single-user-incident threshold) and deepen-plan (security-sentinel + data-integrity-guardian + architecture-strategist). `user-impact-reviewer` runs at PR review (threshold `single-user incident`). **CPO sign-off required at plan time** (`requires_cpo_signoff: true`) — the technical approach (a TF-provisioned prod write token + a CI verb that writes prod secrets) is the product-owner ack per the §User-Brand Impact threshold.

### Product/UX Gate
**Tier:** none — no UI surface (no file under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). Skipped.

## Open Code-Review Overlap
None. (Re-run at /work once `## Files to Edit` is frozen: `gh issue list --label code-review --state open --json number,title,body` then `jq contains($path)` per edited path; record matches or `None`.)

## Test Scenarios
- **T1** op=arm happy path (dry-run against dark/scratch key): reads both source values masked, writes 3 values stdin, `armed` last, FSM-confirm parses `done`.
- **T2** Empty source value → exit 1, no value echoed.
- **T3** POSTGRES_URI with `:6543` → exit 1 before any write.
- **T4** First URI write fails → `armed` never written; job exit 1.
- **T5** FSM returns `aborted` (synthetic Better Stack) → exit 1 + remediation string; NO advance to 2.4.
- **T6** Drift-guard: `cutover-inngest-workflow.test.sh` asserts no value-echo, `::add-mask::`, stdin form, `-p soleur-inngest -c prd`, no ssh, guards present.
- **T7** `terraform-target-parity.test.ts` green unmodified; destroy-guard counter unchanged.

## Sharp Edges
- **iac-plan-write-guard blocks the edits.** `.claude/hooks/iac-plan-write-guard.sh` denies the Doppler-write literal in Write/Edit content. This plan carries the `iac-routing-ack` opt-out; /work MUST apply the same ack for the op=arm YAML + runbook edits (writes go through a TF-provisioned token; values out-of-band by ADR-100 doctrine). Do NOT bypass silently; record the ack.
- **Canonical TF invocation.** `terraform plan/apply` against `apps/web-platform/infra/` needs the triplet: export raw `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (R2 backend, NOT via tf-var), `terraform init -input=false`, then `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan`. Missing `--name-transformer tf-var` → ~13 `No value for required variable` errors (`2026-05-09-drift-runbook-canonical-tf-invocation`).
- **Re-run `terraform plan` against LIVE state immediately before merge** (AC4). The `+2 create` claim depends on the dark host being provisioned; a stale assumption drags project/env into a create. Verify, don't trust.
- **`-target` scope-guard sweep** (`2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites`): only `terraform-target-parity.test.ts` asserts per-merge coverage and it is dynamic (no edit). The destroy-guard counter + `*-gate.sh` suites are create-only-unaffected — confirm, don't assume.
- **AC-NOBODY is the load-bearing control.** `doppler secrets get --plain` output MUST be `::add-mask::`'d on the SAME line it is captured, before any use; the write CLI MUST read stdin (never `NAME=value` argv, which is process-listing-visible and log-echoable). A value in a run log at `single-user incident` threshold is a brand-survival event.
- **Write order is a correctness invariant.** `armed` last, each URI write exit-code-gated. Arming before the URIs land fires the FSM against a stale/missing DSN → scheduler death. The FSM's `flipping`/`flushed` checkpoints (ADR-100 6a) protect the on-host transient, NOT a mis-ordered arm write.
- **Doppler read-path is unverified (terraform-architect flag #1).** Whether the existing prd_terraform `DOPPLER_TOKEN` can read `soleur/prd` source values is unconfirmed; Phase 0 decides read-through vs. seed-into-prd_terraform. Do NOT assume read-through in the op=arm code before Phase 0.
- **`gh secret list` cannot read values** — AC15 verifies presence only; the value is write-once in tfstate.
- **Better Stack confirm is a READ, not a deploy-status poll** — keep it out of the `QMAX_POLLS`/retry-count grep space so `cutover-inngest-workflow.test.sh`'s poll-budget drift-guard stays unambiguous.
- **A `## User-Brand Impact` section that is empty/placeholder/omits the threshold fails deepen-plan Phase 4.6.** It is filled above (threshold `single-user incident`).

## Non-Goals / Alternative Approaches Considered
- **Live prod cutover execution** — operator-gated maintenance-window action, single-user blast radius; NOT an autonomous /work step. The plan *enables* the fully-no-SSH end-to-end + provides the ordered dispatch sequence.
- **2.2a web-2 lifecycle freeze/recreate** (`cutover-inngest.yml:606`) — a host-lifecycle step outside #6369 (tracked toward #6227's per-host fan-out). Remains operator/dispatch.
- **2.4 app-repoint** (merge `ci-deploy.sh INNGEST_BASE_URL → 10.0.1.40:8288` + redeploy, `:612`) — a code merge outside #6369.
- **TF `doppler_secret` for the 3 arm values** — REJECTED: violates the out-of-band doctrine (dark-window heartbeat masking; DB password TF never minted; FSM must fire at the window, not at apply). `inngest-host.tf:137-166`.
- **Deriving POSTGRES_URI via Supabase Management API** — REJECTED: read-only token cannot fetch the DB password; a reset is destructive. → one-time seed.
- **New standalone ADR (ADR-113)** — deferred to reviewer preference; default is the ADR-100 amendment (same architectural surface, avoids ordinal churn).
- **Placing the token in the `inngest_host` dispatch `-target` set** — REJECTED: parity test forbids CI-published tokens in exclusions; `stripDispatchJobs` would hide it from coverage.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Deepen-Plan Findings & Required Changes (2026-07-12 — SUPERSEDES the sections above where noted)

Reviewed by security-sentinel, data-integrity-guardian, architecture-strategist, and a verify-negative/precedent Explore. The verify-negative pass **confirmed all 8** load-bearing facts (token shape at `doppler-write-token.tf:44-50`; parity-test forbids CI-published tokens in exclusions at `terraform-target-parity.test.ts:631-635` and extracts targets dynamically; `-target` neighbours `:356-357`; op structure `:22-32`/`:62-81`, op=quiesce-web `:618`, op=rollback `:890`, SEAM `:607-611`; stdin/`--plain` doctrine `inngest-host.tf:165-166`; `cutover-inngest.yml` has ZERO `::add-mask::` today — the drift-guard is load-bearing; FSM states `ADR-100:160-162`; no-inheritance `inngest-host.tf:78-85`). The following changes are authoritative and OVERRIDE the earlier phases/ACs where they conflict.

### D1 (P1) — op=arm is FORWARD-ONLY; rollback stays in the EXISTING `op=rollback` verb
**Supersedes Phase 4.2's `flip_state` idea.** Do NOT add a `flip_state` input to op=arm and do NOT default any prod-mutating input (data-integrity Q5 + architecture P1; ADR-100:231 keeps the symmetric forward/reverse pair as *separate* verbs). op=arm writes only `armed`. Fold the reverse `INNGEST_CUTOVER_FLIP=rollback` write into the existing `op=rollback` (`:890`): give it the conditional `DOPPLER_TOKEN_INNGEST_ARM` env + the environment gate; order it **G1' guard (refuse unless the forward flip progressed, ∈ {flipping,flushed,done}) → write `rollback` (stdin) → confirm `rolled-back` (time-bounded) → the existing web re-enable fan-out**. Rollback writes ONLY the flip value.

### D2 (P1) — pre-write FSM-state guard (prevents PROD-Redis re-FLUSHALL data loss)
**New G1 step in the `arm)` case, before any write.** Read the CURRENT `INNGEST_CUTOVER_FLIP` from `soleur-inngest/prd` (write token) and **refuse unless ∈ {`unset`, empty, `aborted`, `rolled-back`}**. Re-arming over `done` re-drives `stop → FLUSHALL` against the now-PROD Redis → wipes the live cron sorted-set + in-flight jobs (data-integrity Q2). The `deploy-inngest-restart` concurrency group (`:52-54`, `cancel-in-progress:false`) serializes dispatches → TOCTOU-safe. **Add AC:** op=arm refuses over `{armed,flipping,flushed,done}`.

### D3 (P1) — positive prod-URI assertion (the `:5432`/`:6543` guard MISSES the dark backend)
**New G3 step.** Both dark and prod DSNs use `:5432`, so an empty/`:6543` guard does NOT stop arming the DARK backend (data-integrity Q3 — the exact §User-Brand Impact failure). Read the CURRENT (dark) `INNGEST_POSTGRES_URI` from `soleur-inngest/prd`, mask it, and assert `PG != PG_dark` (refuse on equality) AND `PG` contains the TF-known prod pooler host / Supabase project-ref. All comparisons value-silent. **Add AC + T-case** (mis-seed == dark → exit 1 before any write).

### D4 (P1) — AC-NOBODY hardening (three concrete leak vectors)
- **G6 Better Stack confirm** (security F1 + data-integrity Q4): `betterstack-query.sh` emits whole rows — extract ONLY a single state token via `jq -r`, NEVER `echo "$BODY" | jq .`; and **time-bound the query to ≥ the `armed`-write timestamp** (or a per-dispatch correlation token) — a stale `done` from a prior run or the Phase-5 dry-run on the SAME source else false-succeeds. Branch on `done`/`aborted`/`rolled-back`/timeout.
- **G2 masking** (security F7): mask EACH source value on its OWN capture line (`printf '::add-mask::%s\n' "$HB"` immediately after `HB=$(...)`, then PG) — never batch (a mid-sequence `set -e` exit leaves an unmasked value).
- **Drift-guard test** (security F6): assert the `awk '/arm)/,/;;/'` range is **non-empty** BEFORE grepping (else the no-value-echo grep passes vacuously); add `grep 'jq \.'` == 0 (no raw-row echo) and `grep 'set -x'` == 0.

### D5 (P1) — GitHub Environment secret + required reviewer (real human ack)
**Supersedes IaC Q1's plain `github_actions_secret`.** A `workflow_dispatch` is only repo `actions:write` — weaker than the Doppler console credentials the manual write required, and a repo-wide `github_actions_secret` is readable by every workflow (security F2/F3). Change the IaC to:
```hcl
resource "github_repository_environment" "inngest_cutover" {
  repository  = "soleur"
  environment = "inngest-cutover"
  reviewers { users = [/* operator user id */] }
}
resource "github_actions_environment_secret" "doppler_token_inngest_arm" {
  repository      = "soleur"
  environment     = github_repository_environment.inngest_cutover.environment
  secret_name     = "DOPPLER_TOKEN_INNGEST_ARM"
  plaintext_value = doppler_service_token.inngest_arm_write.key   # NO ignore_changes
}
```
The op=arm job declares `environment: inngest-cutover` (required-reviewer gate fires on dispatch) AND scopes the token conditionally: `DOPPLER_TOKEN_INNGEST_ARM: ${{ inputs.op == 'arm' && secrets.DOPPLER_TOKEN_INNGEST_ARM || '' }}` (empty for non-arm ops). Add both `-target` entries (token + env secret) to the per-merge set; `terraform validate` must confirm `github_repository_environment`/`github_actions_environment_secret` exist in the pinned github provider. **Update AC15** to `gh api repos/.../environments/inngest-cutover/secrets`. The ADR-100 6b reconciliation now rests on this gate, not the dispatch alone.

### D6 (P1) — token/seed lifecycle (the token is a standing read handle to the armed prod DSN)
- **Post-cutover revoke** (security F4): after AC17 validates the live cutover, revoke the write token (`terraform apply -replace=doppler_service_token.inngest_arm_write` + `doppler configs tokens revoke` the old key) — it can READ the prod DSN it wrote into `soleur-inngest/prd`. Add to the runbook + AC17. Correct §User-Brand Impact: blast radius = the isolated project *including* the armed prod DSN.
- **Seed into a NARROW config, not `prd_terraform`** (security F5): `prd_terraform` is the broadest CI-read surface. Seed `INNGEST_POSTGRES_URI_PROD` into a narrow config read only by op=arm; add a **rotation co-update** (the `inngest-host.tf:165` password-rotation step must also re-seed) + a pre-window **freshness assertion** (value-silent) that seed and target agree; **delete the seed** after AC17. Update Phase 2 + AC16/AC17.

### D7 (P2) — documentation/hygiene tightenings
<!-- lint-infra-ignore start -->
- **Transitivity precedent** = `doppler_service_token.inngest` (by-reference, `inngest-host.tf:171`), NOT `.write` (string-literal, zero edges). The by-reference wiring makes the `-target` a **standing** transitive path onto the excluded project/env — document in the `.tf` header that a teardown/re-provision of `doppler_project.inngest` must be operator-applied first, else CI recreates the isolated project unattended (architecture P2).
<!-- lint-infra-ignore end -->
- **ADR-100 6b boundary delta:** state that this is the FIRST CI-consumed read/write token into the isolated `soleur-inngest` project (prior tokens are read-only host-boot, `inngest-host.tf:173`) — CI can now WRITE `soleur-inngest/prd`. State plainly: *the dispatch + environment approval IS the ack; there is no interactive pre-write value confirmation, by design (AC-NOBODY forbids echoing the values).*
- **Source-of-truth principle:** "read-through where TF owns the value (HEARTBEAT_URL), seed-once where TF cannot (POSTGRES_URI)." The Phase-0 heartbeat fallback mirror lands in the CI-readable config, NOT `soleur-inngest/prd` — so it does NOT breach the dark-window masking doctrine (architecture P2).
- **On-host flip-guard (data-integrity P2 edge, cross-ref, NOT built in #6369):** the on-host oneshot's ExecStartPre should positively require `URI==prod` at flip-time (defend a transient dark-URI resolution). That lives on the ADR-100/#6178 on-host surface — raise with the ADR-100 owner; flagged, not built here.

### Updated Test Scenarios (add to §Test Scenarios)
- **T-D2** pre-write state == `done`/`flipping` → G1 exit 1 (data-loss prevention).
- **T-D3** POSTGRES_URI == current dark URI (mis-seed) → G3 exit 1 before any write. Fixtures use unmistakably synthetic non-matching DSNs (`cq-test-fixtures-synthesized-only`, security F9) + AC14 extended to fixtures.
- **T-D4** stale prior-run `done` before the arm timestamp → NOT matched (time-bound holds); confirm continues/times out.
- **T-D5** op=rollback writes only `INNGEST_CUTOVER_FLIP=rollback` behind G1'; confirms `rolled-back`.

### Enhancement Summary
Deepened 2026-07-12. Structurally sound plan; the `-target` placement and ADR-amendment calls were confirmed correct. Seven load-bearing changes fold in above (D1-D6 are P1). The single sharpest catch: **D2** — without the pre-write FSM-state guard, a second op=arm dispatch over `done` re-FLUSHALLs the live PROD Redis. No blocking principle deviation (AP-001/002/007/008 aligned).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Deepen-Plan Findings — Required Changes (SUPERSEDES the sections above where they conflict)

`<!-- iac-routing-ack: plan-phase-2-8-reviewed — the Doppler-write literals below describe the op=arm verb + one-time seed reviewed under Phase 2.8; the write TOKEN is TF-provisioned; the 3 values are out-of-band by ADR-100 Decision 6a. -->`

**Deepened 2026-07-12** — agents: security-sentinel, data-integrity-guardian, architecture-strategist, verify-negative/precedent Explore, terraform-architect. The following corrections are load-bearing and OVERRIDE the earlier draft where they differ. All 8 precedent/verify claims above were confirmed against source.

### C1 (P1, data-integrity Q5 + architecture P1) — op=arm is FORWARD-ONLY; rollback stays in `op=rollback`
DROP the `flip_state` input idea. ADR-100:231 rules the symmetric forward/reverse verb pair must stay **separate** (the same reason `op=quiesce-web`/`op=rollback` are distinct). Fold the reverse `INNGEST_CUTOVER_FLIP=rollback` write into the EXISTING `op=rollback` verb (`cutover-inngest.yml:890`, which already owns the reverse web-scheduler re-enable at `:614` step 3): give it the conditional arm-write token env + the same environment gate; order **G1'** (refuse unless the forward flip progressed, ∈ {`flipping`,`flushed`,`done`}) → write `rollback` (stdin) → confirm `rolled-back` (time-bounded) → existing web re-enable. Rollback writes ONLY the flip value. No prod-mutating default on any input.

### C2 (P1, data-integrity Q2) — pre-write FSM-state guard (prevents PROD-Redis re-FLUSHALL data loss)
Before ANY write, op=arm MUST read the current `INNGEST_CUTOVER_FLIP` from `soleur-inngest/prd` and **refuse unless ∈ {`unset`, empty, `aborted`, `rolled-back`}**. Re-arming over `done` re-drives the FSM `stop → FLUSHALL` against the now-PROD Redis, wiping the live cron sorted-set + in-flight jobs. The `deploy-inngest-restart` concurrency group (`:52-54`, `cancel-in-progress:false`) serializes dispatches → TOCTOU-safe. Add as AC7 and T5.

### C3 (P1, data-integrity Q3) — positive prod-URI assertion (the `:5432`/`:6543` guard MISSES the dark backend)
Both dark and prod DSNs use `:5432`, so the port guard does NOT catch arming the DARK backend (which FLUSHALLs the host Redis and flips onto the wrong Postgres → every user's crons silently stall, queue already wiped). op=arm MUST read the current (dark) `INNGEST_POSTGRES_URI` from `soleur-inngest/prd`, mask it, and assert the value it is about to write `!= dark` AND contains the TF-known prod pooler host/Supabase project-ref (plus empty + `:6543` rejects). All value-silent. Add as AC8 and T3.

### C4 (P1, security F3) — GitHub Environment secret + required reviewer (real human ack)
A `workflow_dispatch` is only repo `actions:write` — weaker than the Doppler console credentials it replaces. Publish `DOPPLER_TOKEN_INNGEST_ARM` as a **GitHub Environment secret** (`github_actions_environment_secret` under `github_repository_environment "inngest-cutover"` with a required-reviewer rule), NOT a repo-wide `github_actions_secret`; add `environment: inngest-cutover` to the op=arm (and op=rollback-write) job. This restores the human ack and is the real basis of the `hr-menu-option-ack` reconciliation. IaC Q1 changes accordingly. Add to AC1/AC15.

### C5 (P1, security F2) — conditional token env (not step-comment scoping)
A bash comment does not scope a step-`env:` var. Inject the token EMPTY for non-arm dispatches: `DOPPLER_TOKEN_INNGEST_ARM: ${{ inputs.op == 'arm' && secrets.DOPPLER_TOKEN_INNGEST_ARM || '' }}` (and the `rollback` arm for the reverse write). Assert the conditional form in the drift-guard (AC13).

### C6 (P1, security F1 + data-integrity Q4) — Better Stack confirm: single-token + time-bounded
`betterstack-query.sh` emits whole matched rows. op=arm MUST (a) bound the query to logs `≥` the `armed`-write timestamp (or a per-dispatch correlation token) — a stale `done` from a prior run/dry-run on the SAME source else false-succeeds and the operator proceeds to 2.4 on an unarmed host; and (b) extract ONLY the terminal state via `jq -r '...|.state'`, NEVER `echo "$BODY" | jq .` (raw-row echo = mask bypass). Branch on `done`/`aborted`/`rolled-back`/timeout. Add to AC9 and T8.

### C7 (P1/P2, security F4/F5 + architecture P2) — token/seed lifecycle
- The write token is a **standing read handle to the armed prod DSN** once op=arm writes it into `soleur-inngest/prd`. Runbook adds a **post-cutover revoke** (`terraform apply -replace=doppler_service_token.inngest_arm_write` + `doppler configs tokens revoke` of the orphan) after AC17.
- Seed `INNGEST_POSTGRES_URI_PROD` into a **narrow** CI-readable config, NOT `prd_terraform` (broadest CI-read surface + rotation-drift trap). Add a rotation co-update note (rotating the DB password must update the seed too) + a pre-window value-silent freshness assertion; **delete the seed** after AC17. Principle: *read-through where TF owns the value (HEARTBEAT_URL), seed-once where TF cannot (POSTGRES_URI).*

### C8 (P2) — AC-NOBODY hardening + drift-guard non-vacuity
- Mask EACH source value on its own capture line (security F7 — a batched mask leaves an unmasked window under `set -e`).
- The drift-guard test MUST first assert the `arm)` awk range is **non-empty** (security F6 — else `grep … == 0` passes vacuously), then assert: no value-echo, no `jq .` raw-row echo, no `set -x`, `::add-mask::` before each use, stdin-form writes, `-p soleur-inngest -c prd`, no `ssh`, the conditional env + `environment:`.
- Test fixtures use unmistakably synthetic non-matching DSNs (security F9, `cq-test-fixtures-synthesized-only`); extend AC14 to fixtures, not just prose.

### C9 (P2) — ADR-100 Decision 6b precision
Record the **boundary delta** (first CI-consumed read/write token into the isolated `soleur-inngest` project — previously operator-only writes). State plainly: *the dispatch + environment approval is the ack; there is no interactive pre-write value confirmation, by design (AC-NOBODY forbids echoing values).* Cite the transitivity precedent as `doppler_service_token.inngest` (by-reference), NOT `.write` (string-literal, zero edges). Heartbeat fallback mirror lands in the CI-readable config, NOT `soleur-inngest/prd` → no masking-doctrine breach.

### C10 (P2, cross-ref, NOT built in #6369) — on-host flip-guard positive prod assertion
Data-integrity Q1 P2 edge: the on-host oneshot's ExecStartPre guard should positively require `URI==prod` at flip-time (not merely reject prod pre-arm) to defend a transient dark-URI resolution. That guard lives on the #6178/ADR-100 on-host surface — flagged for the ADR-100 owner, out of #6369 scope.

**Net:** the ordering (Q1) is sound; the four data-integrity P1s (C1/C2/C3/C6) + the four security P1s (C4/C5/C6/C7) are the pre-`/work` must-fixes. `/work` should treat the Phases/ACs above as amended by C1-C9 (C10 is a cross-ref, not in-scope).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## CTO Decision at /work (2026-07-12 — SUPERSEDES D6/C7 + Phase 2 + AC16 where they conflict)

**Fork:** deepen D6/C7 assumed the prod `INNGEST_POSTGRES_URI` is NOT CI-readable and must be operator-seeded (`INNGEST_POSTGRES_URI_PROD`) into a narrow config. **Live Doppler (value-silent probes at /work Phase 0) contradicts this:** `prd_terraform.INNGEST_POSTGRES_URI` is directly readable by the workflow's existing config-scoped `DOPPLER_TOKEN`, is SHA-identical to canonical `prd.INNGEST_POSTGRES_URI`, uses `:5432`, and is DIFFERENT from the dark `soleur-inngest/prd` value. `INNGEST_POSTGRES_URI_PROD` is absent everywhere.

**Routed to `soleur:engineering:cto` (architecture/security fork — not operator, not unilateral).** **DECISION: Option B — read-through from `prd_terraform`.** op=arm reads BOTH source values (`INNGEST_POSTGRES_URI`, `INNGEST_HEARTBEAT_URL`) from `soleur/prd_terraform` via the existing read-only `DOPPLER_TOKEN` (config-scoped, no `--project/--config` — mirrors `op=backup`'s `HCLOUD_TOKEN` read at `cutover-inngest.yml:304`). Writes unchanged (three to `soleur-inngest/prd` via `DOPPLER_TOKEN_INNGEST_ARM`, `armed` last).

**Supersedes (DROP from D6/C7 + Phase 2 + AC16):**
- The operator seed `INNGEST_POSTGRES_URI_PROD` — **dropped entirely** (no new secret name; the value is already the live canonical source).
- The narrow read config `prd_inngest_arm` + narrow read token / any `DOPPLER_TOKEN` re-scoping — **not created**.
- The post-cutover seed DELETE + seed rotation co-update note — **moot** (no copy to rot/delete).
- The value-silent freshness assertion (a stale-seed catch) — **replaced** by the G3 positive prod-URI assertion (freshness is now structural: live canonical source).

**RETAINED (unchanged):** the write token `DOPPLER_TOKEN_INNGEST_ARM` + its post-cutover **revoke** (D6/C7 F4 — the token holds standing read+write to the armed prod DSN, independent of read-source); G3 positive prod-URI assertion (prod != dark, contains prod host/ref, `:5432` not `:6543`); AC-NOBODY per-value `::add-mask::` + stdin-only writes; write order (`armed` last, exit-gated); G1 pre-write FSM-state guard; time-bounded single-state Better Stack confirm; the GitHub Environment secret + required-reviewer gate (D5/C4); op=arm FORWARD-ONLY + reverse write in op=rollback (D1/C1).

**Rationale (CTO):** A's "narrow read surface" removes no existing exposure (the value already sits in `prd_terraform`, readable by every prd_terraform-scoped CI job) while ADDING a forbidden human pre-window seed step (`hr-menu-option-ack`, "never defer operator actions") and a stale-copy rotation-drift trap — a seeded DSN that goes stale before the window arms a dead DSN → the sole scheduler cannot connect → every user's crons stall (the single-user incident). Reading the live source at arm-time eliminates that window → B STRENGTHENS the single-user-incident posture; G3 + FSM/quiesce guards remain the defense against writing a wrong/dark value. **Rejected:** (A) seed-once narrow config — removes no exposure, adds human step + drift trap; (C) workflow copies prd_terraform→narrow — machinery to relocate an already-readable value, inherits A's drift risk. Recorded in ADR-100 Decision 6b.

**AC16 revised:** the one-time operator seed is DROPPED. Post-merge operator step reduces to: after the per-merge apply, `DOPPLER_TOKEN_INNGEST_ARM` exists as a **repo** secret (`gh secret list | grep DOPPLER_TOKEN_INNGEST_ARM`) — no seed. Phase 2 collapses to a runbook note: "op=arm reads the two source values read-through from `prd_terraform`; no seed."

> **Fix-forward (post-#6369-merge):** D5/C4's `github_actions_environment_secret` FAILED at the first per-merge apply with a 403 — the TF GitHub App cannot write environment secrets (repo secrets work; that is how `doppler_token_write` ships). Changed to a repo-level `github_actions_secret`; the required-reviewer HUMAN-ACK is preserved because the op=arm/op=rollback **job** still declares `environment: inngest-cutover` (the gate is on the job, not the secret). AC15 verifies `gh secret list`, not the environments API. See ADR-100 Decision 6b.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
