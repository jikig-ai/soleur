---
title: "fix: gated -replace path for the CI-SSH Cloudflare Access service token"
date: 2026-07-31
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-ci-ssh-token-replace
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  ACK JUSTIFICATION (auditable, not a silent bypass):
  The `iac-plan-write-guard` matched the literal `doppler secrets set`. Every
  occurrence in this plan DESCRIBES pre-existing workflow code —
  `apply-web-platform-infra.yml:840-843`, the already-merged "Sync CF Access
  CI-SSH service token to Doppler" step. This plan prescribes NO new manual
  Doppler write, NO operator SSH, and NO vendor-dashboard click-path. It in fact
  REMOVES a would-be manual path: the whole point is to replace a local
  `terraform apply` / dashboard regeneration with a gated Terraform-driven
  workflow. Phase 2.8 was reviewed; see the `## Infrastructure (IaC)` section.
-->

# fix: gated `-replace` path for the CI-SSH Cloudflare Access service token

## Overview

`CI_SSH_ACCESS_TOKEN_ID/_SECRET` in Doppler `prd_terraform` holds a
`client_secret` Cloudflare no longer accepts. The CF Tunnel SSH bridge (CI → prod
SSH) is therefore broken, and `scheduled-terraform-drift.yml` has been RED on it
since 2026-07-30T18:00.

`terraform apply` **cannot** self-heal this. Cloudflare returns a service token's
`client_secret` **only at creation**, so the correct value is unreadable from any
API — including from Terraform state, which holds whatever was captured at the
last create. The token must be **recreated**.

This plan adds one gated `apply_target` to `apply-web-platform-infra.yml` that
performs a scoped `-target` + `-replace` of the token, lets the existing sync step
write both new values to Doppler, and **verifies the result** before reporting
success. It also closes the silent-success hole that let a mismatched credential
pair persist undetected.

**Scope boundary:** this plan does NOT dispatch the new target. Building the
mechanism and executing it in production are separate acts; execution is an
operator dispatch after merge.

## Hypotheses

Phase 1.4 fired (`SSH`, `403`). Per `hr-ssh-diagnosis-verify-firewall`, L3→L7 is
verified **before** any service-layer hypothesis.

### L3 — Firewall allow-list — VERIFIED (not causal)

Hetzner firewall `soleur-web-platform` (id 10708450): 8 rules, applied to 2
servers, port 22 restricted to 5 `/32`s. Operator egress rotated
`82.67.29.121 → 37.166.251.228` mid-session; `ADMIN_IPS` was refreshed and applied
2026-07-31, and SSH to `soleur-web-platform` now **succeeds** from the current
egress (host echoed back `37.166.251.228`). Firewall is not the cause.

### L3 — DNS / routing — VERIFIED (not causal)

`dig +short ssh.soleur.ai` → `188.114.97.2`, `188.114.96.2` (Cloudflare anycast,
expected for a tunnel-fronted hostname). Resolution is correct.

### L7 — TLS / proxy — VERIFIED, and this is where the failure lives

`curl -sI https://ssh.soleur.ai` → `HTTP/2 403`, `server: cloudflare`,
`cf-ray: a23cd12cbe779a80-CDG`. The `cf-ray` + `server: cloudflare` pair proves
Cloudflare **Access rejects at the edge** — the request never reaches origin. This
is an authorization rejection, not an sshd/origin fault.

### Service layer — the credential itself

Established by elimination (each measured, not inferred):

| Check | Result |
|---|---|
| Token exists | ✅ `github-actions-ci-ssh`, token_id `20d8c846-bf18-42af-bf35-fce42988326b` |
| Expired? | ✅ No — valid to 2027-05-20 |
| Doppler `client_id` | ✅ `15c3d51c019f9ceb7640eaefd3dc431a.access` — exact match to the live token |
| Access policy binds it | ✅ "Allow GitHub Actions CI SSH", `include.service_token.token_id = 20d8c846…`, `decision=non_identity` |
| Access app present | ✅ `ssh.soleur.ai`, 1 policy |
| Detector verdict | ✅ `31 live, 1 dead, 0 unverifiable` (the **0 unverifiable** is what makes the verdict trustworthy) |
| `client_secret` in Doppler | ❌ **only untested element — therefore the fault** |

### Root cause of the DIVERGENCE — **UNKNOWN**, deliberately

| # | Hypothesis | Verdict | Deciding datum |
|---|---|---|---|
| H1 | Cloudflare-side secret rotation (a rotate preserves `client_id`, changes `client_secret`) — would explain ID-matches-secret-doesn't exactly, and the 07-30 timing coincides with operator Cloudflare rotation during incident remediation | **UNKNOWN** | Cloudflare audit log. Probed: `CF_API_TOKEN` returns `Authentication error` on `/audit_logs` — **not readable with available credentials** |
| H3 | Partial sync write — `CI_SSH_ACCESS_TOKEN_ID` written, `_SECRET` write failed, `set -e` aborted mid-step | **REFUTED** | All 16 `apply-web-platform-infra` runs 07-28→07-31 concluded `success`; an aborted step would have failed the job |
| H5 | Detector false-positive | **REFUTED** | Independent `curl` with real header values reproduces the 403; 31 sibling tokens pass the same detector |

**H1 is NOT marked confirmed.** Its deciding datum is unavailable, and a
plausible-and-well-fitting story is not evidence. This is deliberate: the plan
does not need the root cause, because **every** hypothesis consistent with the
measured state has the same remediation — regenerate and re-sync. Recording H1 as
CONFIRMED would buy nothing and would falsify the record.

**Caveat carried into the fix:** if H1 is true, the divergence can recur at any
time from outside Terraform. That is precisely why Phase 3 (post-sync
verification) is in scope and not deferred — it converts a silent recurrence into
a loud one.

## Research Reconciliation — brief vs. codebase

Three of the constraints in the invoking brief were wrong or incomplete. Each was
checked against the file rather than taken on trust.

| Brief claim | Reality | Plan response |
|---|---|---|
| "Verify whether the sync step writes both ID and SECRET" | It **does** — `apply-web-platform-infra.yml:840-843` writes `CI_SSH_ACCESS_TOKEN_ID` then `CI_SSH_ACCESS_TOKEN_SECRET`, both `--silent`, both from `terraform output -raw` | No new sync logic needed. Reuse verbatim in the new job. |
| "`terraform-target-parity.test.ts` asserts target sets — register the new job or the test fails" | **False.** That suite only asserts SSH-provisioned `terraform_data` resources are covered by the target union (`MIN_SSH_PROVISIONED = 10`, `EXCLUSION_ALLOWLIST = {root_authorized_keys}`). Cloudflare targets are additive and unconstrained. | No registration needed. AC asserts the suite still passes. |
| "Choose an `environment:`; confirm reviewers non-empty" | `web-platform-infra-apply` **has** a non-empty required-reviewer set (1 reviewer, `deruelle`) — a real gate, not auto-approve | See Authorization below. |
| (not in brief) | `cloudflare_zero_trust_access_service_token.ci_ssh` carries `lifecycle { create_before_destroy = true }` (`tunnel.tf:199-208`) | Load-bearing: `-replace` **creates first**, then the policy update re-points to the new token, then the old is destroyed. The destroy-guard must expect exactly this shape. |
| (not in brief) | The sync step's empty-output branch (`:829-832`) emits `::warning::` then **`exit 0`** | This is the silent-success hole. Phase 3 fixes it. |

## User-Brand Impact

**If this lands broken, the user experiences:** a dispatched `ci-ssh-token-replace`
that applies drift outside its intended scope. The pending drift on this root is
35-add / 3-change / 4-destroy and **includes `hcloud_server.registry must be
replaced`** — a mis-scoped `-replace` destroys-before-creates the registry host,
and with no DC stock the fleet strands with no rollback and production cannot pull
images.

**If this leaks, the user's workflow is exposed via:** the job handles a live
Cloudflare Access service token. An unmasked `terraform output` or an echoed
Doppler write would put a credential granting CI→prod SSH reach into a public
Actions log.

**Brand-survival threshold:** `single-user incident`

## Authorization posture (decided, not deferred)

**No `environment:` gate; `confirm` typo-guard with its own distinct literal.**

Rationale: this matches the four sibling dispatch-only jobs (`inngest_host`,
`registry_host_replace`, `registry_region_migrate`, `git_data_host_replace`),
whose authorization is the dispatch itself. The action is **repair, not
destruction** — it regenerates a credential that is already dead, is self-healing
via the sync step, and destroys no data. Adding a reviewer click to a repair path
adds friction without adding safety.

`hr-menu-option-ack-not-prod-write-auth` is satisfied by the `confirm` literal
plus the scoped destroy-guard, not by the menu selection alone.

**Recorded alternative:** `environment: web-platform-infra-apply` is available and
its reviewer set is **verified non-empty** (1 reviewer). If the operator prefers a
click-gate on any production credential write, that is a one-line change with a
real gate behind it — the DP-11 F8 zero-reviewer trap does not apply here.

## Implementation Phases

Phase order is dependency-directed: the guard exists before the job that sources
it, and verification exists before the path that relies on it.

### Phase 1 — Scoped destroy-guard (RED first)

Create `tests/scripts/lib/ci-ssh-token-replace-gate.sh` exposing
`ci_ssh_token_replace_gate <tfplan.json>`, modelled on
`tests/scripts/lib/registry-host-replace-gate.sh`.

It must PASS only on the exact expected shape and FAIL otherwise:
- exactly one `create` + one `delete` for
  `cloudflare_zero_trust_access_service_token.ci_ssh` (the
  `create_before_destroy` replace pair)
- at most one `update` for `cloudflare_zero_trust_access_policy.ci_ssh_service_token`
- **zero** actions of any kind on any other address — explicitly assert
  `hcloud_server.registry`, `hcloud_server_network.registry`,
  `hcloud_volume_attachment.registry` and `doppler_secret.zot_heartbeat_url_prd`
  are absent, since those are the live pending-drift destroys
- no `delete` on any `hcloud_*` address (belt-and-braces)

Companion `tests/scripts/test-ci-ssh-token-replace-gate.sh` exercising the SAME
bytes, with fixtures for: expected shape (pass), registry-replace smuggled in
(fail), extra unrelated create (fail), empty plan (fail).

### Phase 2 — The `ci-ssh-token-replace` job

Add the enum value to the existing `apply_target` input (**zero new inputs** — the
10-input cap and the file's own "next per-target input pair → dedicated workflow"
note are both respected).

Job shape, mirroring `inngest_host` + `registry_host_replace`:
- `if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'ci-ssh-token-replace'`
- `confirm` literal check (distinct from every other target's literal)
- plan with `-replace` **and** `-target`, scoping load-bearing:
  ```
  -replace=cloudflare_zero_trust_access_service_token.ci_ssh \
  -target=cloudflare_zero_trust_access_service_token.ci_ssh \
  -target=cloudflare_zero_trust_access_policy.ci_ssh_service_token
  ```
- `terraform show -json tfplan > tfplan.json`; source the Phase 1 gate; abort on fail
- apply
- reuse the existing sync step verbatim (it already writes both values)

### Phase 3 — Close the silent-success hole + verify

Two changes, both in the sync path:

1. **The empty-output branch must not silently succeed on this path.** The
   existing `::warning:: … exit 0` is correct for the *bootstrap* case it was
   written for (first apply, tokens absent). In the replace job the outputs are
   guaranteed present, so an empty output there is a real failure — fail loud.

2. **Post-sync verification.** After the writes, probe the new credential against
   `ssh.soleur.ai` and require a non-403. Then run
   `scripts/check-cloudflare-token-drift.sh` and require **`dead == 0` AND
   `unverifiable == 0`**. A zero dead-count with nonzero unverifiable means the
   sweep could not check — the detector's own error text says exactly this — so
   asserting `dead == 0` alone would accept an unchecked fleet as a clean one.

This is the durable half of the plan: it is what converts a future recurrence
(H1) from a two-day silent breakage into an immediate red job.

## Files to Create

- `tests/scripts/lib/ci-ssh-token-replace-gate.sh`
- `tests/scripts/test-ci-ssh-token-replace-gate.sh`

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — enum value + new job + sync hardening

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` against the two paths
above. **None.**

## Observability

```yaml
liveness_signal:
  what: scheduled-terraform-drift.yml token-drift step
  cadence: 2x/day (Inngest-dispatched)
  alert_target: infra-drift issue + email notification (already wired)
  configured_in: .github/workflows/scheduled-terraform-drift.yml
error_reporting:
  destination: GitHub Actions job log + the drift workflow's existing email step
  fail_loud: true - the gate aborts with ::error:: and a non-zero exit; the new
    post-sync verification fails the job rather than warning
failure_modes:
  - mode: plan shape is not the exact scoped replace (drift smuggled in)
    detection: ci_ssh_token_replace_gate returns non-zero, prints the offending plan lines
    alert_route: job fails; ::error:: annotation names the unexpected address
  - mode: sync produced a pair Cloudflare still rejects
    detection: post-sync probe against ssh.soleur.ai returns 403
    alert_route: job fails before reporting success
  - mode: detector cannot verify (coverage gap)
    detection: unverifiable != 0
    alert_route: job fails - an unchecked fleet is not a clean one
logs:
  where: GitHub Actions run log for apply-web-platform-infra.yml
  retention: 90 days (repo default)
discoverability_test:
  command: bash scripts/check-cloudflare-token-drift.sh
  expected_output: "dead entries: 0" AND "unverifiable: 0"
```

The discoverability test contains no SSH invocation — it runs from any checkout
with Doppler read access.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — see deviation note)
**Assessment:** CI/infra tooling change. The architectural risk is entirely in
`-target` scoping: this root carries a pending registry-host replace, so an
unscoped or mis-scoped apply is a fleet-strand event. That risk is mitigated
structurally (the sourced gate asserts the exact shape and is exercised by its own
test suite), not procedurally. No data model, no user-facing surface, no new
dependency.

> **Deviation recorded:** this session carries a standing instruction not to spawn
> agents unless the operator requests them, so domain-leader agents, the 5-agent
> `plan-review` panel, the Step 4.5 strong-model advisor consult, and the
> `spec-flow-analyzer` were **not** invoked. At `single-user incident` threshold
> the skill would normally mandate that panel, and it reliably catches a class of
> substance-level findings (guard scoping, proxy-vs-invariant ACs) that inline
> authoring does not. Treat this plan as un-panelled: the review phase should
> weight the destroy-guard scoping and the AC/invariant alignment more heavily
> than usual.

### Product/UX Gate

Not applicable — no UI surface. `Files to Create`/`Files to Edit` contain no path
matching the UI-surface glob set (no `components/**`, no `app/**/page.tsx`, no
`.njk`). The mechanical override does not fire.

## Architecture Decision (ADR/C4)

**Skip — no architectural decision.** This extends an existing, ADR-covered
mechanism (the gated `apply_target` dispatch pattern) with one more target. It
introduces no ownership/tenancy boundary, no new substrate, no trust-boundary
change, and reverses no existing ADR. A competent engineer reading the current
ADRs + C4 would not be misled about the system after this ships.

C4 completeness check: read `model.c4`, `views.c4`, `spec.c4`. The external actors
and systems this touches — Cloudflare (Access/Tunnel), GitHub Actions, Doppler —
are already modelled; no new external actor, system, container, or access
relationship is introduced. No `.c4` edit required.

## Infrastructure (IaC)

**No new infrastructure.** The change is CI-side only and routes the credential
regeneration **through Terraform**, which is the compliant path under
`hr-all-infrastructure-provisioning-servers` — it replaces a would-be local
`terraform apply` (or a vendor-dashboard regeneration) with a gated workflow.

### Terraform changes

None. No `.tf` file is added or edited. The plan operates existing resources
(`cloudflare_zero_trust_access_service_token.ci_ssh` and its policy) via a new
`-target`/`-replace` invocation.

### Apply path

Gated `workflow_dispatch` on the existing auto-apply root. No cloud-init, no
bootstrap script, no host mutation, no `-replace` of any server.

### Distinctness / drift safeguards

The sourced destroy-guard asserts the plan touches **only** the two Cloudflare
addresses. The `doppler_secret` resources carrying token values keep their
existing `lifecycle.ignore_changes = [value]`; the value transfer happens via the
already-merged sync step, not via a new Terraform write.

### Vendor-tier reality check

Cloudflare Zero Trust service tokens are available on the current plan (three
already exist and 31 credential entries verify live). No tier gate needed.

## Encryption Posture

**Skip** — introduces no persistent store and no new cross-component connection.
The credential in flight is masked (`::add-mask::`) and written via a stdin-piped,
`--silent` Doppler write, matching the existing step byte-for-byte.

## GDPR / Compliance Gate

**Skip** — no regulated-data surface. No schema, migration, auth flow, API route,
or `.sql` file. None of the (a)–(d) expansion triggers fire: no LLM processing of
operator data, no new cron reading `knowledge-base/`, no new artifact
distribution surface.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash tests/scripts/test-ci-ssh-token-replace-gate.sh` exits 0, and its output
   shows the **fail** fixtures actually failing (a guard whose negative cases pass
   is not a guard).
2. The gate rejects a fixture containing `hcloud_server.registry` with action
   `delete` — asserted explicitly, since that is the live pending-drift hazard.
3. `actionlint .github/workflows/apply-web-platform-infra.yml` is clean
   (`actionlint`, NOT `bash -n` — the file is a workflow, not a shell script).
4. Every embedded `run:` block added by this PR passes `bash -c` extraction.
5. `bun test plugins/soleur/test/terraform-target-parity.test.ts` still passes
   (asserting the Research Reconciliation finding that no registration is needed).
6. The `apply_target` enum contains `ci-ssh-token-replace` and the
   `workflow_dispatch` `inputs:` block still declares **7** inputs (no new input
   was added).
7. The new job's `confirm` literal differs from every other target's literal —
   verified by extracting all literals and asserting uniqueness.
8. The `-replace`/`-target` argument set appears in the job **exactly** as the
   three flags specified in Phase 2, verified by an anchored grep on the job body
   (not a bare token grep — `cq-assert-anchor-not-bare-token`).

### Post-merge (operator dispatch)

9. Operator dispatches `apply_target=ci-ssh-token-replace` with the confirm
   literal. The plan step's gate PASSES and the applied plan shows exactly: 1
   create + 1 delete of the token, ≤1 update of the policy, **0** other actions.
10. Post-sync probe against `ssh.soleur.ai` returns non-403.
11. `bash scripts/check-cloudflare-token-drift.sh` reports `dead entries: 0` **and**
    `unverifiable: 0`.
12. `scheduled-terraform-drift.yml` next run concludes `success`.

## Test Scenarios

1. **Gate accepts the expected shape** — fixture tfplan.json with the
   create/delete pair + policy update → `ci_ssh_token_replace_gate` exits 0.
2. **Gate rejects smuggled registry replace** — same fixture plus an
   `hcloud_server.registry` delete → exits non-zero, message names the address.
3. **Gate rejects an empty plan** — a no-op plan is not a successful replace.
4. **Gate rejects a create-only plan** — a create with no matching delete means
   `create_before_destroy` did not complete as expected.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `-replace` drags in pending drift (registry strand) | `-target` scoping + sourced gate asserting zero other actions, with an explicit registry-address assertion; gate is exercised by its own test suite |
| Sync writes a pair Cloudflare still rejects | Phase 3 post-sync probe fails the job before it reports success |
| Detector reports `dead: 0` because it could not check | AC requires `unverifiable: 0` alongside |
| Credential leaks into the Actions log | Reuse the existing `::add-mask::` + `--silent` stdin-pipe pattern verbatim; no new echo path |
| H1 recurs (external rotation) | Not preventable from this repo; Phase 3 makes it loud, and the drift detector already catches it within 12h |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This one is filled.
- The root cause is recorded as **UNKNOWN**, not confirmed. Do not let a
  downstream phase promote H1 to fact — its deciding datum (Cloudflare audit log)
  was probed and is unreadable with the available token.
- `bash -n` on a workflow YAML parses the YAML header as bash and is meaningless.
  Use `actionlint` for the workflow and `bash -c` on extracted `run:` snippets.
- The existing sync step's `exit 0` on empty outputs is **correct** for the
  bootstrap case it was written for. Phase 3 must not break that path — harden it
  only for the replace job, where outputs are guaranteed present.
