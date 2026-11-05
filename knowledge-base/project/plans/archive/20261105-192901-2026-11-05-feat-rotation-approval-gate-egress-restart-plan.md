---
title: "feat(infra): reviewer-gated rotate approval environment + no-SSH vector restart enabling egress token rotation (#11923, #11920)"
type: feat
date: 2026-11-05
slug: feat-rotation-approval-gate-egress-restart
branch: feat-one-shot-11923-11920-rotation-gates
issue: 11923
closes: [11923, 11920]
lane: cross-domain
priority: p2-medium
domain: engineering
requires_cpo_signoff: true
---

# feat(infra): reviewer-gated rotate approval environment + no-SSH vector restart enabling egress token rotation (#11923, #11920)

## Overview

Two capabilities deferred from the key-rotation workflow plan land in one PR:

1. **#11923 — a reviewer-gated GitHub approval environment.** A Terraform-provisioned
   `key-rotate-approval` environment (`reviewers.users = [54279]` = @deruelle, custom
   branch policy `main`, `prevent_destroy` policy) is created in the web-platform infra
   root and wired into the `-target=` allow-list of `apply-web-platform-infra.yml`. A new
   no-secret `approve` job bound to that environment sits between `guard` and the first
   production-mutating job in both `key-rotate.yml` and `inngest-key-rotate.yml` (rotate
   and converge modes only — `mode=plan` writes nothing and stays ungated).
   `KK_APPROVAL_ENV_BOUND` flips to `true` and `kk_chk_approval` is repurposed into a
   live verify of the environment's `protection_rules` (fail-closed on API error;
   verdict renamed `approval_environment_unprotected`).
2. **#11920 — no-SSH `vector.service` restart + `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS`.**
   `ci-deploy.sh`'s existing `restart` action gains component `vector`, running
   `sudo /usr/bin/systemctl try-restart vector.service` — the exact argv of the
   already-live `DROPIN_TRY_RESTART` sudoers grant — with per-component fan-out to all
   web hosts and deploy-status verification. `egress_audit_ingest_token_previous` is
   declared as a Terraform `doppler_secret` fed by a sensitive variable (default `""`,
   `ignore_changes=[value]`, written by `-replace`). With both flip criteria met, the
   `egress_rotate_unsupported_no_vector_restart_lever` refusal is removed and the
   egress rotate sequence becomes: apply-A (set PREVIOUS=old, mint new CURRENT) →
   fleet redeploy → vector restart fan-out → clear apply (PREVIOUS="") → `rotate_ok`.

Both issues were deferred by `knowledge-base/project/plans/archive/20261103-112939-2026-11-02-feat-key-rotation-workflow-plan.md`
with explicit re-evaluation criteria; both criteria are now satisfiable with existing
mechanisms extended, not new channels.

## Problem Statement

**#11923:** the typed confirm `ROTATE-<KEY>-<YYYY-MM-DD>` is derivable from public
inputs — a fat-finger guard, not an authorization. The `infra-privileged` environment
has a custom branch policy and **zero required reviewers** (re-measured 2026-11-05 via
`gh api repos/jikig-ai/soleur/environments`), so the only technical gate on a rotate
dispatch is repository write access; "agents never dispatch rotate" is policy, not a
mechanism, and a PAT-based dispatch is indistinguishable from the owner's. Three keys
(`inngest_manual_trigger_secret_prd`, `kb_drift_ingest_signing_key`,
`github_webhook_secret`) are currently *unrotatable* because the guard refuses them
with `approval_environment_missing`.

**#11920:** `mode=rotate` refuses `egress_audit_ingest_token` with
`egress_rotate_unsupported_no_vector_restart_lever` (key-rotate.sh:403-408). Vector
reads `EGRESS_AUDIT_INGEST_TOKEN` only at process start (vector.toml `auth.token`;
the unit runs `doppler run -- vector`); the lossless CURRENT+PREVIOUS scheme needs
Vector restarted on every web host before PREVIOUS can be cleared, and no restart
lever that works without SSH existed when the issue was filed (restarts lived only in
Terraform SSH provisioners and `inngest-bootstrap.sh`). `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS`
is also not declared in Terraform — only read by `server/egress-audit-ingest.ts:95`.

## Proposed Solution

- **#11923:** new `apps/web-platform/infra/key-rotate-approval-environment.tf`
  declaring `github_repository_environment.key_rotate_approval` (reviewers `[54279]`,
  `custom_branch_policies = true`, `protected_branches = false`) +
  `github_repository_environment_deployment_policy.key_rotate_approval_main`
  (`branch_pattern = "main"`, `prevent_destroy`). Add both addresses to the
  `apply-web-platform-infra.yml` `-target=` allow-list (a bare `.tf` in this root is
  never applied) and to `REVIEWERS_RATCHET` in `terraform-target-parity.test.ts`.
  Both rotate workflows get a dedicated **`approve` job** carrying `environment:
  key-rotate-approval` and no secrets, `needs`-chained so every production-mutating
  job runs only after reviewer approval. `kk_chk_approval` becomes a live read of
  `protection_rules` (the env must carry BOTH `required_reviewers` AND `branch_policy`; absent/unprotected/API-
  error refuses `approval_environment_unprotected`). The approve job emits
  `approval_epoch`; `authorization_stale` measures from it, not `guard_epoch`.
- **#11920:** `ci-deploy.sh` restart action accepts `vector` — skips the
  inngest-specific quiesce check, runs `sudo /usr/bin/systemctl try-restart
  vector.service` (exact argv the `DROPIN_TRY_RESTART` grant already permits),
  verifies `is-active` plus an `ActiveEnterTimestamp` delta, writes the same
  deploy-status frame shapes (`component=vector`), and fans out via
  `SOLEUR_DEPLOY_PEERS` exactly like the `quiesce`/`enable` arms. `egress-audit.tf`
  declares `doppler_secret.egress_audit_ingest_token_previous` fed by
  `var.egress_audit_ingest_token_previous` (sensitive, `default = ""`) with
  `lifecycle { ignore_changes = [value] }` — written only by `-replace`, never by
  routine applies. `key-rotate.sh` removes the egress refusal, feeds the pre-apply
  read of the old CURRENT value into `TF_VAR_egress_audit_ingest_token_previous` for
  the rotate apply, adds PREVIOUS gate-table rows for both applies, and adds a
  `redeploy vector` leg + `clear` job to `key-rotate.yml`.

## Technical Approach

### Architecture

**#11923 — the gate.** GitHub evaluates a job's `environment:` before any step runs;
a `required_reviewers` rule holds the job "Waiting" until a listed reviewer approves.
The new `approve` job needs exactly one step (emits `approval_epoch`); it holds no
secrets, so the environment needs no seeded values — unlike rebinding `apply`'s
`environment:` directly, which would force the `DOPPLER_TOKEN_INFRA_PRIVILEGED`
environment secret to be supplied onto a second environment — a value the TF GitHub
App cannot write (403, ADR-100 fix-forward) and Tier-B keeps outside Terraform state
entirely (ADR-241): a non-Terraform credential step this design avoids.
`infra-privileged` keeps zero reviewers (deliberate — the unattended apply-on-merge
and scheduled drift need it; infra-privileged-environment.tf:36-49).

`key-rotate.yml` order becomes: `guard` → `approve` (rotate only) → `apply` →
`redeploy` (with the new vector step for egress) → `clear` (egress only) → `notify`.
`inngest-key-rotate.yml`: `guard` → `approve` (rotate + converge) → `apply1` →
`reboot` → `apply2` → `redeploy` → `notify`. Approval waits of any length are
already anticipated by the sibling's `admit` re-check comment
(inngest-key-rotate.yml:224).

**#11920 — the lever.** The deploy webhook (`adnanh/webhook`, deploy.soleur.ai,
HMAC `X-Signature-256` + Cloudflare Access) already terminates on every web host at
`/hooks/deploy` → `ci-deploy-wrapper.sh` → `ci-deploy.sh`, and `peers` fan-out +
`/hooks/deploy-status` per-host state frames already exist. `restart` is already a
grammar verb (`restart inngest _ latest`, #4538) writing the same state schema
`cat-deploy-state.sh` merges. The vector arm adds the third restartable component
behind the exact-argv sudoers grant — no sudoers change, so nothing on this path
needs SSH delivery (the sudoers file is root-managed; infra-config-apply.sh:217).

**#11920 — the secret.** PREVIOUS mirrors the four `inngest_*` secrets'
`ignore_changes=[value]` + `-replace`-to-write pattern: routine targeted applies
never diff it (no drift noise, no early clear); the rotate apply `-replace`s it with
`TF_VAR_egress_audit_ingest_token_previous` = the pre-apply read of the old CURRENT;
the clear apply `-replace`s it with the default `""`. The empty string is the honest
cleared sentinel (route skips empty values; egress-audit-ingest.ts:95-99).

**Rotate order (lossless):** apply-A writes PREVIOUS=old AND CURRENT=new in one apply
→ fleet redeploy (app restarts, accepts both) → vector restart fan-out (vector picks
up new CURRENT) → verify all hosts restarted → clear apply removes PREVIOUS. App
redeploy strictly precedes vector restart: if vector restarted first it would send
the new token while the app still ran the old env and reject every bucket.

### Implementation Phases

#### Phase 1 — Terraform + test harness (#11923 + #11920 foundations, RED first)

- RED: extend `plugins/soleur/test/terraform-target-parity.test.ts`
  `REVIEWERS_RATCHET` with `key_rotate_approval` (RED until the resource exists);
  add the literal `-target` pins for the two new addresses (the suite owns the
  allow-list parity); extend the gate-table-vs-HCL derivation so
  `doppler_secret.egress_audit_ingest_token_previous` with `ignore_changes=[value]`
  derives flag `replace`.
- RED: `key-rotate-workflow.test.sh` — new scenario rows for the approve job, the
  live env-protection verify, the egress rotate sequence, the vector leg, and the
  clear apply (stubs: `gh`, `doppler`, `terraform`, `curl`); update TOKENS /
  PREWRITE_TOKENS literals (remove `egress_rotate_unsupported_no_vector_restart_lever`
  and `approval_environment_missing`, add `approval_environment_unprotected` and any
  new egress verdicts), B35/B35b pins (`KK_APPROVAL_ENV_BOUND` → `true`, apply env
  stays `infra-privileged`), C2.12/C2.13/C2.14, C3.4/C3.4b, C3.15b/c, and mutation
  rows D3.5a/b, D5.1, D5.5c/d, D5.16a/d, D6.11a (mutations that deleted refusals
  must be re-derived against the NEW mechanisms — see Guard Contract).
- Create `apps/web-platform/infra/key-rotate-approval-environment.tf` (env + policy
  + `prevent_destroy`, header cites the #6780 vacuous-gate learning and the
  reviewers `[54279]` convention).
- `egress-audit.tf`: add `doppler_secret.egress_audit_ingest_token_previous`
  (`project=soleur config=prd`, `visibility = "masked"`, `ignore_changes=[value]`,
  header documents the rotate/clear contract); `variables.tf` gains the sensitive
  `egress_audit_ingest_token_previous` variable (`default = ""`).
- `apply-web-platform-infra.yml`: add three `-target=` lines
  (`github_repository_environment.key_rotate_approval`,
  `github_repository_environment_deployment_policy.key_rotate_approval_main`,
  `doppler_secret.egress_audit_ingest_token_previous`).

#### Phase 2 — Workflows (#11923 binding + #11920 legs)

- `key-rotate.yml`: insert `approve` job (`environment: key-rotate-approval`,
  `if: dispatch && mode == 'rotate'`, one step emitting `approval_epoch`); extend
  `apply`'s `needs`/`if` to require it for rotate; `apply` consumes
  `EFF_GUARD_EPOCH` replaced by `needs.approve.outputs.approval_epoch` when present;
  add the vector-restart step inside `redeploy` (trio env, `key == egress` only);
  add `clear` job (egress only, `environment: infra-privileged`,
  `terraform-apply-web-platform-host` group, infra-credentials loader,
  `bash scripts/key-rotate.sh clear`); update timeouts + header narrative.
- `inngest-key-rotate.yml`: insert the same `approve` job before `apply1`
  (`mode != 'plan'`); extend `apply1`'s `needs`/`if` accordingly.

#### Phase 3 — Scripts + host handler (#11920 mechanism)

- `ci-deploy.sh`: in the `ACTION == "restart"` arm accept `vector` (skip the
  inngest quiesce check for it); capture `ActiveEnterTimestamp` before,
  `sudo /usr/bin/systemctl try-restart vector.service`, verify is-active + timestamp
  delta; reasons `vector_restart_failed` / `vector_restart_unverified` / `success`;
  call `fan_out_to_peers` on the vector arm AFTER local restart + verify pass
  (mirrors quiesce's ordering, Ruled by CTO agent 2026-11-05 — a partial fleet
  is detectable via merged deploy-status, and consistency with the proven arm
  is the safer read).
- `key-rotate.sh`: delete `kk_chk_egress`'s refusal (keep the function as a
  pass-through or remove it + its ladder call site); rewrite `kk_chk_approval` as
  the live env-protection verify; `KK_APPROVAL_ENV_BOUND=true`; verdict list and
  `--print-contract` updated; egress apply-A reads old CURRENT value-silently into
  `TF_VAR_egress_audit_ingest_token_previous`; new `redeploy vector` subcommand
  (dispatch `restart vector _ _` + peers, poll deploy-status for
  `component=vector` frames after baseline); new `clear` subcommand (plan+apply
  `-replace` of PREVIOUS with the var default); budget-table entries for the new
  legs; header comments updated.

#### Phase 4 — Docs, ADR, C4, runbook

- Amend `ADR-317-…md` `## Decision`: F2 flips (egress rotatable — record the flip
  evidence), G6/H2 updated (reviewer-gated env bound; `approval_environment_*`
  described as a live verify, not a stub). Add this PR's mechanism to its
  Alternatives Considered history lines.
- `model.c4`: add the founder↔github environment-approval relationship (see
  `## Architecture Decision (ADR/C4)`).
- `runbooks/key-rotation.md`: approval UX (the run waits "Waiting" on
  `key-rotate-approval`), the egress rotate sequence, PREVIOUS lifecycle, the
  vector-restart lever and its per-host verification, the updated verdict table.
- PR body carries `Closes #11923` + `Closes #11920`.

### Files to Create

- `apps/web-platform/infra/key-rotate-approval-environment.tf`
- `knowledge-base/project/specs/feat-one-shot-11923-11920-rotation-gates/decision-challenges.md` (done at plan time)
- `knowledge-base/project/specs/feat-one-shot-11923-11920-rotation-gates/tasks.md` (done at plan time)

### Files to Edit

- `.github/workflows/key-rotate.yml` — approve job, clear job, vector step, apply needs/if + epoch, timeouts, header
- `.github/workflows/inngest-key-rotate.yml` — approve job before apply1
- `scripts/key-rotate.sh` — see Phase 3
- `apps/web-platform/infra/ci-deploy.sh` — restart vector arm + fan-out + verify
- `apps/web-platform/infra/ci-deploy.test.sh` — restart vector rows
- `apps/web-platform/infra/egress-audit.tf` — PREVIOUS doppler_secret
- `apps/web-platform/infra/variables.tf` — `egress_audit_ingest_token_previous` sensitive var, `default = ""`
- `.github/workflows/apply-web-platform-infra.yml` — three `-target=` rows
- `plugins/soleur/test/terraform-target-parity.test.ts` — REVIEWERS_RATCHET, -target pins, gate-table HCL derivation
- `apps/web-platform/infra/key-rotate-workflow.test.sh` — see Phase 1 RED list
- `knowledge-base/engineering/architecture/decisions/ADR-317-key-rotation-second-dispatch-only-route-sourcing-the-inngest-route.md` — amendments
- `knowledge-base/engineering/architecture/diagrams/model.c4` — founder→github approval edge
- `knowledge-base/engineering/operations/runbooks/key-rotation.md` — updated procedure

**Deliberately NOT edited:** `scripts/inngest-key-rotate.sh` (the approval is a
workflow-level `environment:` binding; editing the sourced sibling would risk both
routes and key-rotate.sh's sha256 pin over sourced bodies), `hooks.json.tmpl`
(existing `/hooks/deploy`, `/hooks/deploy-peer`, `/hooks/deploy-status` suffice),
`deploy-inngest-bootstrap.sudoers` (the grant argv is reused verbatim; a comment-only
edit would force an SSH delivery cycle for no behavioral change — the second-caller
note lives in ci-deploy.sh's own comment), `apps/web-platform/server/egress-audit-ingest.ts`
(already accepts PREVIOUS), `vector.toml` (Vector reads CURRENT only).

## Research Insights

**Premise Validation (Phase 0.6).** Checked: `gh issue view 11923` and `gh issue view
11920` (both OPEN, domain/engineering + type/security); the cited plan
`knowledge-base/project/plans/2026-11-02-feat-key-rotation-workflow-plan.md` exists
only at its archived path `plans/archive/20261103-112939-2026-11-02-...` (minor
staleness, same document); every cited file exists EXCEPT `scripts/ci-deploy.sh`,
whose real path is `apps/web-platform/infra/ci-deploy.sh` (+ `ci-deploy-wrapper.sh`)
— the issue body predates the path move; live `gh api .../environments` re-confirmed
`infra-privileged` has `branch_policy` only, zero `required_reviewers`, and no
`key-rotate-approval` env exists; ADR-317 `## Decision` F2/G6/H2 and the egress
refusal at key-rotate.sh:403-416 match the issue descriptions; collision-precheck
found only this branch's own draft PR #12153 (foreign `test-all.sh` processes belong
to sibling worktrees, not this change). Held: all load-bearing premises. Stale:
ci-deploy path; plan archive path.

**Property List (Phase 0.6b).** (P1) a human authorization gate in front of
production-mutating rotate jobs, Terraform-owned and fail-closed; (P2) a no-SSH
restart of `vector.service` on every web host, invocable from the rotate workflow;
(P3) PREVIOUS as a Terraform `doppler_secret` rotated by `-replace` in the same
apply; (P4) the refusal removed and PREVIOUS rows in the gate table once P2+P3 hold.

**Cut List (Phase 0.6b).** Dedicated `/hooks/vector-restart` hook + script → P2 is
already covered by the `restart` grammar + `DROPIN_TRY_RESTART` grant + peers
fan-out + deploy-status frames — a new hook buys nothing. Rebinding `apply`'s
`environment:` to the new env → P1 needs no Tier-B secret on the approval env; the
dedicated `approve` job covers it with zero secret material (ADR-100/ADR-241
constraints make the seeding path expensive and unnecessary). A new sudoers alias
→ the existing grant's exact argv is reused; sudoers is root-managed and
SSH-delivered, so touching it would violate the no-SSH constraint this issue exists
to close.

**Relevant files:** `apps/web-platform/infra/infra-privileged-environment.tf` (the
deliberately reviewerless Tier-B carrier), `web-host-birth-environment.tf` (the
adoption + reviewers `[54279]` + branch-policy precedent), `inngest-arm-write-token.tf`
(environment-secret 403 note — env secrets are supplied outside Terraform), `hooks.json.tmpl`
(deploy/deploy-peer/deploy-status hooks), `ci-deploy.sh:4455-4687` (action grammar +
restart handler + flock), `deploy-inngest-bootstrap.sudoers:133` (DROPIN_TRY_RESTART),
`.github/actions/dispatch-web-redeploy/track.sh` (dispatch+poll template),
`.github/workflows/restart-inngest-server.yml` (restart dispatch+poll precedent),
`cat-deploy-state.sh` (peer merge), `key-rotate.sh:76-140` (gate table, verdicts,
auth posture), `apply-web-platform-infra.yml:530-575` (`-target` allow-list).

**Institutional learnings applied:**
`security-issues/2026-07-23-new-tf-resource-in-target-scoped-apply-root-and-unprotected-env-autocreate.md`
(the env must join the `-target` list in the same PR; a referenced-but-absent env
auto-creates UNPROTECTED — hence the live-verify rung; dark-state vars take
`default = ""` for whole-root resolvability), `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
(L3-before-L7 if the SSH fallback path is ever needed), the ci-deploy `restart`/
`quiesce`/`enable` handler precedents (#4538/#6178), ADR-241 (Tier-B env secrets),
ADR-288 (egress token is a same-host hop), ADR-307/ADR-317 (rotation route shape).

**External research:** skipped — every mechanism (GitHub environment semantics,
webhook fan-out, sudoers argv pinning, doppler_secret lifecycle) is already measured
and documented in-repo; nothing external would change the design.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (measured 2026-11-05) | Plan response |
|---|---|---|
| "restarts of `vector.service` live only inside Terraform SSH provisioners and `inngest-bootstrap.sh`; `ci-deploy.sh` has none" | True for the *invocable* path, but a `DROPIN_TRY_RESTART` sudoers grant (`/usr/bin/systemctl try-restart vector.service`) already exists (deploy-inngest-bootstrap.sudoers:133), exercised by `infra-config-apply.sh`'s drop-in RESTART_MAP. The *capability* is live; only the *dispatch surface* is missing. | Reuse the grant's exact argv inside `ci-deploy.sh`'s restart action — no sudoers change, so the lever ships with zero SSH-delivered artifacts. |
| "`EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` is also not declared in Terraform" | Confirmed — only `server/egress-audit-ingest.ts:95` reads it; egress-audit.tf declares CURRENT only. | Declare `doppler_secret.egress_audit_ingest_token_previous` + sensitive var; add `-target` row. |
| "the environment has a custom branch policy and zero required reviewers" (infra-privileged) | Confirmed live: `protection_rules: [branch_policy]` only. | New env carries `required_reviewers` + `main` policy; `infra-privileged` is NOT touched (its reviewerlessness is load-bearing). |
| "`ci-deploy.sh`" as a repo-root scripts path | The script lives at `apps/web-platform/infra/ci-deploy.sh`; `scripts/ci-deploy.sh` does not exist. | All references use the real path. |

## Hypotheses

The Phase 1.4 network-outage gate fired on the `SSH` token. This plan does not
diagnose a connectivity failure — SSH appears only as the mechanism being *avoided* —
so the L3→L7 enumeration is largely inapplicable; recorded per the checklist's
opt-out form:

1. **L3 firewall allowlist.** Not applicable to the primary path — the vector
   restart rides the existing HTTPS deploy webhook (no SSH anywhere). **Conditional:**
   IF a live host turns out to lack the `DROPIN_TRY_RESTART` grant (delivered
   root-only via `terraform_data.deploy_pipeline_fix`, an SSH `remote-exec`
   provisioner), the remediation is a `terraform apply` that SSHes — at which point
   the L3 check IS mandatory before any sshd hypothesis: `hcloud firewall describe`
   vs the runner egress IP, per #3061. [not yet needed — grant presence is verified
   by the first `restart vector` dispatch, which fails loudly `vector_restart_failed`
   if sudo denies]
2. **L3 DNS/routing.** `deploy.soleur.ai` already serves `/hooks/deploy*` to the
   same workflows today (track.sh polls it every redeploy) — verified by the
   existing route's green history, not re-verified here.
3. **L7 TLS/proxy.** Same deploy.soleur.ai Cloudflare-Access edge as the existing
   redeploy/restart routes — verified by daily use.
4. **L7 application.** The deploy-status frame + journald `SUCCESS: restart vector`
   markers are the service-layer evidence the plan itself produces; no incident is
   being diagnosed.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Add `reviewers` to `infra-privileged` itself | Rejected | Its zero-reviewer set is load-bearing for the unattended apply-on-merge + scheduled drift (infra-privileged-environment.tf:36-49); a reviewer would block the route it exists to serve. |
| Rebind the apply job's `environment:` to the new reviewer-gated env | Rejected | `DOPPLER_TOKEN_INFRA_PRIVILEGED` is an env-scoped secret; the new env would need it supplied outside Terraform (the TF App cannot write env secrets — 403, ADR-100 fix-forward). The dedicated `approve` job buys the same gate with zero secret material. |
| Reuse `web-platform-infra-apply` as the approval env | Rejected | Already reviewer-gated + main-only, but its pending-approval queue is the host-birth lane's; coupling rotate approvals to it makes the two indistinguishable and widens the blast radius of a reviewer-set edit. |
| Dedicated `/hooks/vector-restart` hook + `vector-restart.sh` | Rejected | Duplicates the restart grammar, state frames, flock, fan-out and status poll that `ci-deploy.sh` already provides; new FILE_MAP row + new test surface for zero new capability. |
| New `VECTOR_RESTART` sudoers alias | Rejected | The file is root-managed — SSH-delivered only. The existing `DROPIN_TRY_RESTART` argv is reused verbatim; `try-restart` semantics (never start an inactive unit) are what the rotation wants anyway. |
| `doppler_secrets` data source feeding PREVIOUS | Rejected | Cannot express "clear" (tracks CURRENT with a one-apply lag), produces drift noise every routine apply during the window, and hides the write behind data-read ordering. The `ignore_changes` + `-replace` pattern is the in-repo idiom. |
| SSH `terraform_data` provisioner to restart vector during the rotate apply | Rejected | Re-introduces the SSH dependency the issue exists to remove; CI-side SSH provisioners have the firewall-drift failure class (#3061). |
| Permanent PREVIOUS (always = previous token, never cleared) | Rejected | Leaves the old token valid indefinitely — expands the exposure window the rotation exists to shrink. |

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct user-facing artifact —
  the blast radius is operator-facing: a vacuous approval gate converts the sole
  human authorization on production credential rotation into none (the #6780 class),
  and a botched egress rotate leaves `EGRESS_AUDIT_INGEST_TOKEN` unrotatable or the
  old value valid indefinitely (a same-host-hop credential for the egress-audit
  rollup — best-effort observability, no end-user path, per the issue).
- **If this leaks, the user's [data / workflow / money] is exposed via:** the
  egress-audit ingest token forges rollup rows on a same-host hop only (ADR-288);
  a `key-rotate` regression can wedge ALL production secret rotations mid-incident
  — the workflow route is the rotation path for six other secrets.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** matches the parent key-rotation plan's
  ruled threshold — a change to the sole rotation route can silently retire the
  human-ack boundary on every production secret, which is operator-brand blast
  radius even though no end-user data path depends on the egress token itself.

CPO sign-off required at plan time before `soleur:work` begins (threshold
`single-user incident`; `requires_cpo_signoff: true` in frontmatter).
`soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what:            ci-deploy deploy-status frame (component=vector, reason=success) per web host; journald markers `SUCCESS: restart vector` / `FAILED:`/`REJECTED:` lines under tag `ci-deploy`; the workflow's own `verdict=` line per leg
  cadence:         per-dispatch (event-driven), plus the standing Vector→Better Stack pipeline
  alert_target:    `rotated_redeploy_failed` / vector-leg failure → job fails + notify job files the action-required issue; ingest-reject events mirror to Sentry (`mirrorReject`, egress-audit-ingest.ts)
  configured_in:   apps/web-platform/infra/ci-deploy.sh (restart arm), scripts/key-rotate.sh (vector leg), apps/web-platform/infra/vector.toml (Source 4 journald → Better Stack)

error_reporting:
  destination:     journald tag `ci-deploy` → Vector Source 4 → Better Stack; Sentry for app-side ingest rejects
  fail_loud:       non-zero exit + `final_write_state` failure reason (`vector_restart_failed`, `vector_restart_unverified`, `component_not_restartable`) — every failure arm stamps a deploy-status frame, never a silent exit

failure_modes:
  - mode:          vector restart denied on a host lacking the DROPIN_TRY_RESTART grant (rollout/stale sudoers)
    detection:     `sudo` rc≠0 → `vector_restart_failed` state frame + journald `sudo: … COMMAND=` denial record; the workflow's per-host poll sees no success frame
    alert_route:   workflow verdict fails the run; `rotated_redeploy_failed`-class action-required issue via notify
  - mode:          partial fleet restart (one host restarted, one not)
    detection:     merged deploy-status (fanout_peers) shows a host without a fresh component=vector success frame; the workflow refuses to clear PREVIOUS
    alert_route:   non-success verdict + filed issue
  - mode:          environment loses required_reviewers (auto-created or drifted unprotected)
    detection:     `kk_chk_approval` live read refuses `approval_environment_unprotected` at guard, before anything writes
    alert_route:   guard refusal fails the run pre-write
  - mode:          PREVIOUS never cleared (clear apply fails/skipped)
    detection:     post-clear verification reads `doppler secrets get EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` empty/absent; a stale non-empty PREVIOUS keeps the old token valid — surfaced as non-success verdict
    alert_route:   notify job files the action-required issue

logs:
  where:           journald on each web host (`ci-deploy` tag) → Better Stack via Vector; workflow run log (verdicts only, no Terraform streams)
  retention:       Better Stack retention per existing pipeline; journald persistent on host

discoverability_test:
  command:         bash scripts/key-rotate.sh --print-contract
  expected_output: rotate_ok
```

## Encryption Posture

```yaml
at_rest:
  - store:          doppler secret `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` (soleur/prd) — `doppler_secret.egress_audit_ingest_token_previous`
    mechanism:      provider-managed:Doppler encrypted secret store (masked visibility)
    evidence:       apps/web-platform/infra/egress-audit.tf (new block); Doppler encryption attestation per existing doppler_secret rows
    defends_against: at-rest disclosure of the grace-window token outside the platform
    does_not_defend: the value also lands in the web-platform `terraform.tfstate` (Tier-A `prd_terraform`-readable — the same exposure the CURRENT token already carries per egress-audit.tf's own disclosure; a same-host hop credential, ADR-288) and is readable by any holder of a prd-scoped Doppler token
    disclosed_as:   not-publicly-claimed (internal posture; the .tf header documents it)
    live_verification: available (`doppler secrets get` + `terraform state show` reads)
# Note: the `key-rotate-approval` GitHub environment is a configuration surface holding
# NO secret material (the approve job is credential-free), so it is not a data store
# and carries no at_rest row.
in_transit:
  - connection:     key-rotate workflow → deploy.soleur.ai `/hooks/deploy` + `/hooks/deploy-status` (per web host, fan-out over private net host→host)
    enforced_at:    apps/web-platform/infra/hooks.json.tmpl (payload-hmac-sha256 trigger-rule) + scripts/lib/bearer-curl.sh (CF Access + HMAC headers)
    tls:            HTTPS (public edge; private-net plain HTTP for the peer hop — existing design, webhook service binds the private interface)
    cert_verification: on (curl default verify on the public edge)
    does_not_defend: the private-net peer hop (10.0.1.x:9000) is plain HTTP — the HMAC payload signature still authenticates each hop (existing ADR-068 posture, unchanged)
    disclosed_as:   not-publicly-claimed
  - connection:     workflow runner → Terraform R2 state / Doppler API
    enforced_at:    scripts/key-rotate.sh `kr_tf` chokepoint + infra-credentials loader
    tls:            HTTPS
    cert_verification: on
    does_not_defend: state object contents readable by Tier-A backend keys (disclosed above)
    disclosed_as:   not-publicly-claimed
```

## Infrastructure (IaC)

### Terraform changes

- **New** `apps/web-platform/infra/key-rotate-approval-environment.tf`:
  `github_repository_environment.key_rotate_approval` (`reviewers { users = [54279] }`,
  `deployment_branch_policy { protected_branches = false; custom_branch_policies = true }`),
  `github_repository_environment_deployment_policy.key_rotate_approval_main`
  (`branch_pattern = "main"`, `lifecycle { prevent_destroy = true }`).
- **Edit** `apps/web-platform/infra/egress-audit.tf`:
  `doppler_secret.egress_audit_ingest_token_previous` (`visibility = "masked"`,
  `lifecycle { ignore_changes = [value] }`).
- **Edit** `apps/web-platform/infra/variables.tf`:
  `variable "egress_audit_ingest_token_previous" { type = string; sensitive = true;
  default = "" }` — the `""` default keeps whole-root plan resolution working when
  the var is not supplied (the #6780 P2 lesson: no-default vars break every
  unrelated apply under `doppler run --name-transformer tf-var`).
- **Edit** `.github/workflows/apply-web-platform-infra.yml`: three `-target=` rows —
  a bare `.tf` in this root never applies, and an un-referenced environment
  auto-creates unprotected on first use (the #6780 vacuous-gate class).
- Required providers: `integrations/github` (env resources), `doppler` — both already
  pinned in the web-platform root.
- Sensitive variables: `TF_VAR_egress_audit_ingest_token_previous` — sourced at
  runtime by `key-rotate.sh` from the value-silent Doppler read of the old CURRENT.

### Apply path

Routine merge-apply through `apply-web-platform-infra.yml` (saved-plan, `-target`
allow-list). The environment must exist BEFORE a dispatch can rely on it: it is
created by the post-merge apply; the `kk_chk_approval` live verify refuses a rotate
dispatch against an absent/unprotected env — the sequencing hazard the live read
exists for. No `terraform import` is needed (the environment does not exist today —
measured 2026-11-05); adoption-by-PUT applies if it is ever auto-created first.

### Host fan-out

The vector restart reaches every web host via the `peers` CSV
(`WEB_HOST_PRIVATE_IPS: "10.0.1.10,10.0.1.11"` — already the pinned literal in
`key-rotate.yml`'s redeploy job, parity-guarded by
`web-hosts-fanout-parity.test.sh`); `deploy-peer` on each sibling host receives the
same command and does NOT re-fan. Per-host success is read through the merged
deploy-status (`fanout_peers` persisted by `write_state`).

### Distinctness / drift safeguards

- `key-rotate-approval` ≠ `infra-privileged` (reviewer-gated vs unattended) — the
  reviewerless carrier is untouched.
- `prevent_destroy` on the deployment policy (the host-birth precedent) so the
  main-only pin cannot be acked away.
- `ignore_changes=[value]` on PREVIOUS makes routine applies diff-free on it —
  the scheduled drift check sees no noise and a merge apply cannot early-clear the
  grace token.
- The PREVIOUS value lands in `terraform.tfstate` — disclosed, same as the CURRENT
  token (egress-audit.tf comment).

### Vendor-tier reality check

GitHub Environments + deployment branch policies are free-tier features on public
repos — no paid-tier gate applies. No new vendor.

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-317-key-rotation-second-dispatch-only-route-sourcing-the-inngest-route.md`
in this PR (an extension of an existing decision, not a new ADR):

- **F2** — `egress_audit_ingest_token` flips from plan-only to fully rotatable;
  record the flip evidence (the `restart vector` no-SSH lever + the
  Terraform-declared PREVIOUS rotated by `-replace`) and the lossless ordering.
- **G6/H2** — the reviewer-gated environment `key-rotate-approval` now exists and is
  bound; `kk_chk_approval` becomes a live verify of `protection_rules`; the residual
  text ("Until #11923…", "an owner PAT still passes") is updated — the PAT residual
  is now bounded by the reviewer gate, while a PAT *approval* is still the owner's
  click by design.
- `## Consequences` gains the new failure modes (unprotected-env refusal, partial
  fleet restart, PREVIOUS-never-cleared).

### C4 views

Checked all three model files
(`diagrams/{model.c4,views.c4,spec.c4}`): the `founder` actor, `github`,
`doppler` and `hetzner` systems already exist; the `github -> doppler` edge
enumerates Tier-B environment-secret carriers — `key-rotate-approval` carries NO
secret, so that enumeration needs no row. The NEW actor↔surface relationship is the
founder approving a queued Actions job at a reviewer-gated environment — modeled by
extending the `founder -> github` edge set with an "approves a production-mutating
dispatch at the `key-rotate-approval` environment" relationship (Context view;
`views.c4` include line if the edge does not render under the existing view's
membership). Container/Component views: unchanged — no new container, data store or
runtime component (the restart lever is an existing process surface). Validation:
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` must pass.

### Sequencing

The ADR amendment describes the target state as shipped in this PR — no `adopting`
staging needed (the env + binding + refusal removals land atomically).

## Guard Contract

### Guard 1 — Environment protection cannot silently degrade (DP-11 F8 + live verify)

**Property.** Every rotate dispatch reaches a production-mutating job only behind a
GitHub environment that carries `required_reviewers` AND a `main` deployment branch
policy — in Terraform (`REVIEWERS_RATCHET`), in the workflow binding (`environment:`),
and live (`kk_chk_approval` reads `protection_rules`).

**Assembly.** `github_repository_environment.key_rotate_approval` +
`…deployment_policy.key_rotate_approval_main` in `key-rotate-approval-environment.tf`;
the `-target=` allow-list block of `apply-web-platform-infra.yml`; the `approve`
job definitions in `key-rotate.yml` and `inngest-key-rotate.yml`; `kk_chk_approval`
in `scripts/key-rotate.sh`; `REVIEWERS_RATCHET` in `terraform-target-parity.test.ts`.
Two chokepoints: the PR-time suite pin (ratchet + -target pins) and the run-time
live read.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Empty `reviewers.users` on `key_rotate_approval` | RED — REVIEWERS_RATCHET fails |
| 2 | Remove `key_rotate_approval` from `REVIEWERS_RATCHET` | RED — the ratchet asserts every named env exists in-tree AND every ratchet member has reviewers |
| 3 | Drop the `-target=github_repository_environment.key_rotate_approval` line | RED — the allow-list parity pin in terraform-target-parity.test.ts |
| 4 | `kk_chk_approval` accepts a `protection_rules` array lacking `required_reviewers` | RED — the live-verify scenario (stub `gh api` returning branch_policy-only) must stay a refusal |
| 5 | Approve job's `environment:` renamed to `infra-privileged` | RED — the suite's environment-binding pin (`.jobs.approve.environment` literal) |
| 6 | Guard reports the env check ran zero times and exits 0 | RED — a must-PASS fixture where the env IS protected must still pass, while a "0 checked" stub must fail — anti-vacuity on the live read itself |

**Anchor.** The ratchet + HCL live in the same commit as the resource — consistency,
not integrity. What must ALSO move for a weakening to pass silently: the live
`protection_rules` on GitHub (outside the commit), which the run-time verify reads —
that is the anchor covering the between-merge window.

### Guard 2 — The egress gate-table projection equals the HCL + the refusal is gone

**Property.** `mode=rotate` for `egress_audit_ingest_token` plans exactly the
declared rows (random_id delete,create; CURRENT update; PREVIOUS replace) — no more,
no fewer — and emits no `egress_rotate_unsupported_no_vector_restart_lever` anywhere.

**Assembly.** `KR_GATE_TABLE` + `KK_COPIES`/`KK_KEYS` in `scripts/key-rotate.sh`;
the HCL in `egress-audit.tf`; the Guard-5 HCL-derivation describe in
`terraform-target-parity.test.ts`; the `kk_*` refusal ladder ordering in
`key-rotate.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Re-add a `kk_chk_egress` refusal rung | RED — the suite's rotate-proceeds scenario for egress fails |
| 2 | Drop the PREVIOUS `-replace` row from the gate table | RED — the plan projection shows a replace the gate did not request (`replace_not_requested`) |
| 3 | `ignore_changes=[value]` removed from PREVIOUS | RED — the HCL-derivation flips its flag to `target` and the table/HCL parity fails |
| 4 | Clear apply skipped (PREVIOUS stays populated) | RED — the post-clear assertion on empty PREVIOUS fails |
| 5 | Second egress rotate after a clean first | must-PASS — the suite's non-canonical input: PREVIOUS already holds a value; `-replace` still writes the new old-token |

### Guard 3 — `restart vector` reaches every web host and reports per-host

**Property.** A `restart vector _ _` dispatch with `peers` restarts
`vector.service` on EVERY listed host — and a host that does not report a fresh
`component=vector` success frame makes the leg non-green.

**Assembly.** `ci-deploy.sh` restart action's component allowlist + vector arm +
`fan_out_to_peers` call; `/hooks/deploy` + `/hooks/deploy-peer` in `hooks.json.tmpl`;
`write_state`/`cat-deploy-state.sh` frame + peers merge; the `redeploy vector` leg
in `key-rotate.sh`; the `WEB_HOST_PRIVATE_IPS` roster.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | `vector` dropped from the restartable-component check | RED — `component_not_restartable` scenario regression |
| 2 | `fan_out_to_peers` call removed from the vector arm | RED — the peers-forward scenario shows a single-host restart only |
| 3 | Handler invokes `restart` instead of `try-restart` (argv drift) | RED — the sudoers-argv lockstep pin (sudo denies → `vector_restart_failed`); ci-deploy.test.sh asserts the exact argv |
| 4 | `deploy-status` poll accepts a frame with `start_ts <= baseline` | RED — the stale-frame scenario must not count as success |
| 5 | Suite harness: stub `systemctl` that always exits 0 while `is-active` reports inactive | RED — the verify step (timestamp/active check), not the sudo rc alone, must catch it |

## Downtime & Cutover

The only availability-adjacent operation is `systemctl try-restart vector.service`
on each web host — Vector is the **telemetry** pipeline, not a serving connector; the
web app keeps serving. The restart darkens host telemetry for seconds while
`doppler run` re-resolves env. **Zero-downtime path is the design:** hosts restart
independently (not a lockstep swap), the app is already redeployed accepting
CURRENT+PREVIOUS before any vector restarts, and PREVIOUS is not cleared until
every host reports a fresh success frame — an old-token send is never rejected.
**Residual:** a host whose vector was already down darkens nothing further;
`try-restart` deliberately does not start it (a deliberate unit state, not this
lever's call) and the verify reports `vector_restart_unverified`. Rollback: re-dispatch
`restart vector _ _` — it is idempotent. No bounded maintenance window is needed
because the serving surface never goes offline.

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed (inline — Task-spawn unavailable in this subagent context;
orchestrator assessed with repo evidence)
**Assessment:** Architectural change with a new trust-boundary element (a
reviewer-gated environment) riding an existing, heavily-precedented pattern
(inngest-cutover, web-platform-infra-apply). Main risks: the vacuous-gate
auto-create class (mitigated by `-target` wiring + live verify), the
approval-wait × `authorization_stale` interaction (mitigated by approval_epoch),
and partial-fleet restart semantics (mitigated by per-host frames + PREVIOUS held
until all report). Six pending-assumed technical rulings recorded in
`decision-challenges.md` — no CTO spawn available in this context.

### Operations

**Status:** reviewed (inline, same caveat)
**Assessment:** The only process change is that rotate/converge dispatches now wait
in "Waiting" for a reviewer click in the Actions UI — the intended feature. No new
vendor, tool, or procurement. Runbook updated.

No Product/UX surface — the mechanical UI-surface scan of Files to Create/Edit
finds no UI path (all files are `.tf`, `.yml`, `.sh`, `.c4`, `.md`). Legal,
marketing, sales, finance, support: no implication beyond the existing Tier-B
credential model.

## Open Code-Review Overlap

One match: **#7098** (`ci: audit the 56 run: bodies whose set omits -e…`) mentions
`apply-web-platform-infra.yml`. **Acknowledge** — that scope-out audits `run:` body
`set` flags, an orthogonal concern to this PR's `-target=` line additions; no fold
(adding targets does not create a new `run:` body), no deferral note needed.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a Terraform-provisioned GitHub environment with required reviewers as an approval gate in front of the production-mutating jobs of `key-rotate.yml` (and the sibling `inngest-key-rotate.yml`)" [issue #11923] | `key-rotate-approval-environment.tf`, `approve` jobs in both workflows, Phase 1/2 | mapped |
| 2 | "remove the refusal from `scripts/key-rotate.sh` and add the PREVIOUS rows to its gate table once both flip criteria hold" [issue #11920] | Phase 3 `kk_chk_egress` removal + gate-table PREVIOUS rows | mapped |
| 3 | "a verified no-SSH way to restart `vector.service` on every web host" [issue #11920 flip criterion 1] | `ci-deploy.sh` restart-vector arm + `fan_out_to_peers` + `redeploy vector` leg | mapped |
| 4 | "`EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` declared as a Terraform `doppler_secret` and rotated by `-replace` in the same apply" [issue #11920 flip criterion 2] | `egress-audit.tf` + `variables.tf` + gate-table rows + `-target` row | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| `key-rotate-approval-environment.tf` | ask 1 | asked |
| `approve` jobs in both workflows | ask 1 ("approval gate in front of the production-mutating jobs") | asked |
| `kk_chk_approval` → live `protection_rules` verify + `approval_environment_unprotected` | — | inferred — justification: the #6780 vacuous-gate class means structural binding alone can silently degrade between merge and apply; the live read makes the gate self-reporting (ask 1's "approval gate" must actually gate) |
| `approval_epoch` output + `authorization_stale` rebaseline | — | inferred — justification: KK_AUTH_MAX_AGE_S=3600 measures from guard; an approval queue would make every legitimate slow approval self-refuse |
| `ci-deploy.sh` restart `vector` arm | ask 3 | asked |
| `doppler_secret.egress_audit_ingest_token_previous` + var + `-target` | ask 4 | asked |
| `clear` job + `redeploy vector` subcommand | ask 3 + the egress-audit.tf rotation contract ("clear PREVIOUS once both have restarted") | asked |
| test-suite updates (key-rotate-workflow.test.sh, terraform-target-parity.test.ts, ci-deploy.test.sh) | — | inferred — justification: the suites pin the verdict list, gate-table parity, env bindings and argv lockstep; without updating them the change cannot go green and the guards rot |
| `REVIEWERS_RATCHET` + `-target` allow-list entries | — | inferred — justification: the #6780 learning requires the new env in the apply allow-list in the same PR and the ratchet holds the reviewers property |
| ADR-317 amendment + model.c4 edge + runbook update | — | inferred — justification: wg-architecture-decision-is-a-plan-deliverable (the approval gate is a trust-boundary change); the runbook must not document a refusal that no longer exists |
| `notify`/verdict plumbing for new legs | — | inferred — justification: every write leg must reach a verdict or the notify job's write-tracking contract breaks |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/infra`, `scripts`, `.github/workflows` (+ KB docs under knowledge-base)
- Planned files: 14 | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — both issues were deferred from one plan, share the same gate table / verdict contract / workflow skeleton, and the egress flow depends on the approval env being live for the `_prd`-class rotation; splitting would land a rotatable egress path gated behind an env that does not yet exist in the other half.

## Acceptance Criteria

### Functional Requirements

- [ ] FR1: `gh api repos/jikig-ai/soleur/environments/key-rotate-approval` shows `required_reviewers` including user 54279 AND a `main` deployment-branch policy, applied through `apply-web-platform-infra.yml` (the three new `-target` rows are present in the workflow and in the applied plan).
- [ ] FR2: `key-rotate.yml` `mode=rotate` for any key pauses at the `approve` job ("Waiting" on `key-rotate-approval`); after reviewer approval, `apply` proceeds. `mode=plan` never pauses.
- [ ] FR3: `inngest-key-rotate.yml` `mode=rotate` and `mode=converge` pause at `approve` before `apply1`; `mode=plan` does not.
- [ ] FR4: `kk_chk_approval` refuses `approval_environment_unprotected` when the env's `protection_rules` lack `required_reviewers` (or the read fails), at guard time, before any write.
- [ ] FR5: `POST {"command":"restart vector _ _","peers":"<roster>"}` to `/hooks/deploy` restarts `vector.service` on every peer host: each writes a `component=vector` deploy-status frame (`reason=success` iff `try-restart` + verify pass); a host failing either reports `vector_restart_failed`/`vector_restart_unverified`.
- [ ] FR6: `restart` on an inert component still refuses `component_not_restartable`; the inngest quiesce check does not apply to `vector` and still applies to `inngest`.
- [ ] FR7: `terraform plan` with `TF_VAR_egress_audit_ingest_token_previous=<old>` and `-replace=doppler_secret.egress_audit_ingest_token_previous` shows PREVIOUS delete,create; routine targeted applies show no diff on it (`ignore_changes`).
- [ ] FR8: `mode=rotate egress_audit_ingest_token` runs apply-A (PREVIOUS=old CURRENT read, new CURRENT minted) → redeploy → vector restart all hosts → clear apply (PREVIOUS="") → `rotate_ok`; it never emits `egress_rotate_unsupported_no_vector_restart_lever`.
- [ ] FR9: if any host fails the vector restart or verification, the run ends non-success and PREVIOUS is NOT cleared (the old token stays accepted — the lossless direction).
- [ ] FR10: `--print-contract` lists the updated verdict set (the two removed tokens absent; `approval_environment_unprotected` and any new egress verdicts present) and the suite's set-equality pin passes.

### Non-Functional Requirements

- [ ] No Terraform stream reaches a log, summary or artifact (kr_tf chokepoint covers the new clear apply).
- [ ] The PREVIOUS token value never reaches argv — `TF_VAR_` env only.
- [ ] Timeouts for new jobs/steps come from the script's BUDGET TABLE and the suite pins them.
- [ ] NFR register assessment: no NFR tier moved — same trust boundaries, one added human gate.

### Quality Gates

- [ ] `key-rotate-workflow.test.sh` green including: approve-job rows, live-verify rungs, full egress rotate (stubbed terraform/doppler/gh/curl), vector leg per-host verification, clear apply, and every re-derived mutation row.
- [ ] `ci-deploy.test.sh` green including restart-vector rows (argv lockstep, is-active/timestamp verify, fan-out, quiesce-check scoping).
- [ ] `terraform-target-parity.test.ts` green including REVIEWERS_RATCHET, -target pins and the PREVIOUS flag derivation.
- [ ] `bash scripts/lint-guard-contract.py` clean on this file.
- [ ] C4 tests (`c4-code-syntax.test.ts`, `c4-render.test.ts`) green.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given `mode=rotate` + any key + env protected, when the run reaches `approve`, then it waits for reviewer approval and `apply` starts only after it.
- Given the env auto-created unprotected (protection_rules `[branch_policy]` only), when a rotate is dispatched, then guard refuses `approval_environment_unprotected` and nothing is written.
- Given `mode=rotate egress_audit_ingest_token` + stubs, when apply-A runs, then the plan shows exactly random_id delete,create + CURRENT update + PREVIOUS delete,create, and PREVIOUS's value equals the pre-apply read of the old CURRENT.
- Given apply-A succeeded + redeploy ok, when `redeploy vector` runs, then every peer reports a fresh `component=vector` success frame and the clear apply empties PREVIOUS.
- Given one peer's `try-restart` fails, when the vector leg polls, then the run ends non-success and the clear apply never runs.
- Given `restart vector _ _` on a host where `is-active` reports inactive, when the handler runs, then it refuses `vector_restart_unverified` (try-restart no-op is not success).

### Regression Tests

- Given `restart inngest _ latest`, when dispatched, then the quiesce check + verify_inngest_health path is unchanged.
- Given `mode=plan` for any key (incl. egress), when the guard runs, then `plan_ok` reports `rotate_would_refuse=none` for egress.
- Given a `deploy web-platform …` command, when processed, then the deploy path is byte-identical to before (dormant peers).

### Edge Cases

- Approval wait > 60 min: `authorization_stale` measures from `approval_epoch`, not `guard_epoch` — a slow approval cannot self-refuse.
- Second consecutive egress rotate: PREVIOUS already holds a value; `-replace` still writes the new old-token (Guard 2 row 5).
- `re-run` of any job: refused as before (rerun_refused unchanged).
- Webhook `peers` empty: single-host restart (documented single-host lever behavior).

### Integration Verification

- Post-merge: `gh api repos/jikig-ai/soleur/environments/key-rotate-approval` → `protection_rules` contains `required_reviewers` + `branch_policy` (verified before first dispatch — the live-verify rung makes a premature dispatch fail closed anyway).
- First `restart vector _ _` dispatch proves the grant on live hosts; a `sudo` denial surfaces as `vector_restart_failed` (remediation: a Terraform-driven delivery through `apply-deploy-pipeline-fix.yml` — the established IaC channel, one-time, not part of the rotate loop).
- Post-clear: `doppler secrets get EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS -p soleur -c prd` returns empty; Better Stack ingest-reject rows for egress stay absent after clear.

## Success Metrics

- `mode=rotate` for `egress_audit_ingest_token` reaches `rotate_ok` end-to-end on a real dispatch (after dev shakedown).
- All three formerly-refused keys rotate behind a reviewer approval; no `approval_environment_unprotected` firing once the env is live.
- Zero SSH invocations anywhere in the rotation path (the only SSH-managed artifact, the sudoers file, is unchanged).

## Dependencies & Prerequisites

- The `DROPIN_TRY_RESTART` sudoers grant must be present on live web hosts (added #7103-era; verify on first dispatch — failure is loud, not silent).
- The new environment must be applied before the first rotate dispatch (routine merge apply; the live verify fails closed otherwise).
- No external prerequisite PRs; both issues' re-evaluation criteria are met by this change itself.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| Env referenced before applied → auto-creates unprotected (#6780) | Live verify refuses; `-target` wiring same-PR; post-merge `gh api` AC |
| Approval queue stalls → `authorization_stale` | `approval_epoch` baseline |
| Partial fleet vector restart → old token rejected after clear | Clear only after all hosts' fresh success frames; PREVIOUS retained on failure (lossless direction) |
| `try-restart` no-ops on inactive vector | Verify is-active + timestamp delta → `vector_restart_unverified` |
| Test-suite mutation rows go stale when refusals are removed | Re-derived mutation rows target the NEW mechanisms (Guard Contract §matrices) |
| PAT dispatch residual | The reviewer gate bounds it: a PAT can dispatch but the reviewer's approval is still a distinct human act — documented residual, same class as the existing gates |

## Resource Requirements

No new vendor, tier, or runner class. Existing: GitHub Actions + Environments,
Doppler, Hetzner web hosts, adnanh/webhook, Better Stack.

## Future Considerations

- `restart` could later admit other `User=deploy` units behind the same grant pattern
  (each a deliberate allow-list entry + verify arm, never a wildcard).
- If the approval queue proves noisy for dev shakedowns, a per-key approval scope
  (`_prd`-class only) is a one-line `if:` refinement — deferred unless needed.
- `sentry-infra-apply`-style reviewer-gated envs could converge onto one approval-env
  naming scheme later — out of scope.

## Documentation Plan

- `runbooks/key-rotation.md`: approval flow, egress sequence, PREVIOUS lifecycle,
  vector-restart verification, verdict table.
- ADR-317 amendment (this PR).
- model.c4 edge (this PR).
- Both issue bodies: closed by PR body (`Closes #11923`, `Closes #11920`).

## References & Research

### Internal References

- `apps/web-platform/infra/web-host-birth-environment.tf` — the reviewers+branch-policy precedent, adoption/import notes, `prevent_destroy`
- `apps/web-platform/infra/infra-privileged-environment.tf` — why `infra-privileged` must stay reviewerless
- `apps/web-platform/infra/inngest-arm-write-token.tf` — env-secret 403 fix-forward (job-level gate instead of env secret)
- `apps/web-platform/infra/hooks.json.tmpl` — deploy/deploy-peer/deploy-status hook set
- `apps/web-platform/infra/ci-deploy.sh:4455-4687` — action grammar, restart handler, flock
- `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers:133` — `DROPIN_TRY_RESTART`
- `apps/web-platform/infra/egress-audit.tf` — CURRENT secret + rotation contract comment
- `apps/web-platform/server/egress-audit-ingest.ts:95` — `configuredTokens` reads CURRENT+PREVIOUS
- `.github/actions/dispatch-web-redeploy/track.sh` — dispatch+poll mechanism
- `.github/workflows/restart-inngest-server.yml` — restart dispatch+poll precedent
- `scripts/key-rotate.sh:66-140,403-416` — verdicts, gate table, refusal rungs, auth posture
- `plugins/soleur/test/terraform-target-parity.test.ts:4152-4390` — DP-11 F8 + REVIEWERS_RATCHET
- `knowledge-base/engineering/architecture/decisions/ADR-241`, `ADR-288`, `ADR-307`, `ADR-317`
- `knowledge-base/project/plans/archive/20261103-112939-2026-11-02-feat-key-rotation-workflow-plan.md` — parent plan
- Learning: `knowledge-base/project/learnings/security-issues/2026-07-23-new-tf-resource-in-target-scoped-apply-root-and-unprotected-env-autocreate.md`

### Related Work

- Issues: #11923, #11920 (this PR), #11294, #10205 (parents), #11922, #11927, #11928, #9294 (sibling residuals), #7098 (acknowledged overlap)
- This branch's draft PR: #12153

## Enhancement Summary

**Deepened on:** 2026-11-05
**Sections enhanced:** Encryption Posture (dropped the non-store `key-rotate-approval` row — a plaintext-exception row would have required a spurious exception block); discoverability probe verified against the real `--print-contract` invocation.
**Agents used:** none — `Reviewed-Coverage: sequential-fallback` (depth-1 planning subagent, no spawn tool); every prescribed fan-out (repo/learnings research, functional-overlap, domain leaders, per-section research, review panel, scoped advisor) ran inline sequentially or is recorded as pending-assumed in `decision-challenges.md`.
**Halt gates verified inline (deepen-plan §4):** 4.5 network-outage (Hypotheses emitted; resource-shape trigger evaluated — no apply driven on a provisioner-bearing resource) · 4.55 Downtime & Cutover (section present, zero-downtime default argued) · 4.6 User-Brand Impact (`single-user incident`, `requires_cpo_signoff: true`) · 4.7 Observability (5-field schema; probe `bash scripts/key-rotate.sh --print-contract` — allowlisted verb, offline, <15s, literal `rotate_ok`) · 4.8 PAT-shaped vars (repo grep: zero hits; the new var ends `_previous`) · 4.9 UI-wireframe (no UI-surface files — skip) · 4.10 Encryption Posture (fires on `.tf`; fields filled, no `plaintext-exception`/`cert_verification: off` row) · 4.11 Guard Contract (3 guards; `lint-guard-contract.py` clean) · 4.12 Scope Check (4 asks all mapped; inferred rows justified) · 4.13 Task Design (no new workflow file, no `schedule:`/`on:` trigger added — does not fire).

### Key Improvements

- The no-SSH restart lever reuses the already-live `DROPIN_TRY_RESTART` sudoers grant (`/usr/bin/systemctl try-restart vector.service`) — no sudoers change, so nothing SSH-delivered is needed (the sudoers file is root-managed; infra-config-apply.sh:217).
- The approval gate is a dedicated no-secret `approve` job, not a rebind of `apply`'s environment — avoids the environment-secret seeding the TF App cannot perform (ADR-100 fix-forward).
- `kk_chk_approval` becomes a live `protection_rules` read rather than a removed rung, closing the #6780 auto-create-unprotected window structurally.
- PREVIOUS uses the in-repo `ignore_changes=[value]` + `-replace`-to-write idiom, so routine applies can neither drift-flag nor early-clear the grace token.

### New Considerations Discovered

- `authorization_stale` (KK_AUTH_MAX_AGE_S=3600, measured from `guard_epoch`) would self-refuse after a slow approval — `approval_epoch` emitted by the approve job re-baselines it.
- `fan_out_to_peers` is wired on `deploy`/`quiesce`/`enable` but NOT on the `restart` action today — the vector arm must add it explicitly.
- `scripts/ci-deploy.sh` (issue-cited) does not exist; the real path is `apps/web-platform/infra/ci-deploy.sh`.
- Six technical forks are pending-assumed in `specs/feat-one-shot-11923-11920-rotation-gates/decision-challenges.md` (no CTO spawn available); the work phase may upgrade them.
