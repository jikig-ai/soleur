---
title: "infra: web-1 retirement step 2b — bastion replace route (ADR-327)"
date: 2026-11-28
slug: feat-bastion-host-replace-route
branch: feat-one-shot-12879-bastion-host-replace-route
issue: 12879
refs: [12879, 9421, 12008]
type: feat
lane: cross-domain
priority: p3-low
domain: engineering
brand_survival_threshold: none
---

# infra: web-1 retirement step 2b — bastion replace route (ADR-327)

## Enhancement Summary

**Deepened on:** 2026-11-28
**Sections enhanced:** Proposed Solution, Implementation Phases, Guard Contract (Guards 1-3), Observability,
User-Brand Impact, Encryption Posture, Architecture Decision, Files to Edit, Acceptance Criteria. New
sections: Downtime & Cutover, Network-Outage Deep-Dive, and Deepen-Plan Research Insights.
**Agents used:** security-sentinel, architecture-strategist, spec-flow-analyzer, test-design-reviewer,
observability-coverage-reviewer, framework-docs-researcher, and a verify-the-negative sweep. The CTO
re-ruled Q4b and R3b.

### Key Improvements

1. The id pin now covers every bastion record a replace deletes or updates: the NIC's
   `before.server_id` and the attachment's `before.server_ids`. Allowed actions are a per-address
   table, so a future list member is no-op-only by default.
2. Boot-verify and `_bbv_poweroff` refuse any server id that existed before the apply, on both
   routes. This closes two holes: a healthy bastion powered off after a failed or cancelled replace,
   and a birth dispatched into a lost-state project.
3. The plan JSON now carries the host private key in clear text on a replace. The route writes it
   under `umask 077` in `$RUNNER_TEMP`, masks it, never prints values, and deletes it on `always()`.
4. Hetzner reads go through one `bc_curl` helper (ADR-280). The TOCTOU step re-checks identity
   rather than comparing documents.
5. Q4b: this PR is #8385's first slice. ADR-231 gets an addendum. The relocation keeps first lines,
   and its byte math is measured (3,375 B freed, net about 487,100).
6. The plan-JSON shapes behind H1 are confirmed from Terraform v1.10.5 and hcloud v1.63.0 source.
   The limit of 25 `workflow_dispatch` inputs is confirmed.

### New Considerations Discovered

- R3b: extracting the shared checks needs a harness change in the birth suite (the `gmut` target
  file and `scratch_gate`). The CTO ruled that allowed, with two conditions.
- **Operator item:** schedule #8385 (split the apply workflow) before the next route that adds to it.
  Its own trigger has fired.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Step 2b of the web-1 retirement epic (#9421, ADR-327). Step 2a (PR #12873) gave the dedicated
bastion a gated birth route. This plan adds its sibling: a gated destroy-and-recreate route,
selected by a new `apply_target` value on the apply workflow, with a sourced plan gate under
`tests/scripts/lib/` and its test suite registered in `scripts/test-all.sh`.

## Research Insights

### Premise Validation (Phase 0.6, 2026-11-28)

- **#12879** is OPEN (the target). **#12873** (step 2a) MERGED 2026-11-19 at `0d09246a05`.
  **#12866**, **#9421**, **#12942**, **#12867**, **#12008**, **#12937** are all OPEN. **#12958** is
  OPEN, CONFLICTING, and edits `apply-web-platform-infra.yml` in hunks at lines 310-1635 and
  6295-6410. It nets -757 bytes from its merge-base `916fee0ec7`, which equals today's file size.
- **The bastion is not born.** The last `workflow_dispatch` of `apply-web-platform-infra.yml` was
  2026-11-16, before the birth route merged. The runbook's "Pre-birth boot evidence" step and #12942
  gate the birth. The issue's second done-when bullet (a `plan_only` run against the real bastion)
  therefore cannot run inside this PR. It runs after a birth, on the owner's typed go.
- **Collision pre-check** (`collision-precheck.sh 12879`): one hit, this session's own draft PR
  #13111. There is no foreign run and no sibling worktree on the defect noun.
- **Byte budget (measured).** `wc -c` of `.github/workflows/apply-web-platform-infra.yml` is 489,485 bytes on `main`
  (the GitHub contents API agrees). `plugins/soleur/test/workflow-file-size.test.ts` gates it at
  `WORKFLOW_FILE_GATE_BYTES = 490_000`, so the headroom is **515 bytes**. The 2a caller job
  `bastion_host_create` alone is 573 bytes. A replace caller cannot land without freeing bytes in the
  same PR.
- **Scope signal the issue body omits.** The ADR-327 addendum (2026-11-18) says "#12879 (2b) adds the
  replace route **and heartbeat**". The archived 2a plan records a CTO re-rule (2026-11-17) that moved
  the Better Stack heartbeat, its timer, its manifest row, its egress row and its ping proof to #12879.
  The issue body lists only the route. The CTO ruling below settles which one this PR delivers.

### Property List (Phase 0.6b)

- P1. An operator can destroy and recreate `soleur-bastion` from `main` by one dispatch, without SSH.
- P2. The dispatch can destroy only the bastion server that exists now (the physical id), never
  another server that some state corruption maps to the address.
- P3. The plan the apply consumes changes only `hcloud_server.bastion` and its attachments. Every
  other address, the bastion's own firewall and the host key included, is left unchanged.
- P4. The SSH host key never changes on this route. The replacement boots with the same key.
- P5. When a prior replace destroyed the server and failed to create it, the same route recovers by
  a create. It recovers only when no `soleur-bastion` exists in the Hetzner project, so there are
  never two bastions.
- P6. The destroy never runs unless Hetzner stock for `cx23` in the location is proven first.
- P7. A replace never runs concurrently with any other apply of the web-platform state.
- P8. A replaced bastion that does not report `fresh_boot_ready` is powered off and reported, as at birth.
- P9. A `plan_only` run grades the real plan and stops before any destroy, apply or host contact.
- P10. The apply workflow still starts. Its file stays under GitHub's 512,000-byte refusal and the
  repo's 490,000-byte gate, with headroom left for the next sibling.

### Cut List (Phase 0.6b)

- A new `workflow_dispatch` input for the job body → P1 → the reusable-workflow pattern of 2a already
  carries the body. Only a thin caller is added to the apply file.
- A new concurrency group → P7 → the caller workflow's top-level `terraform-apply-web-platform-host`
  group already covers a reusable callee, which runs inside the caller's run
  (`bastion-host-create.yml` header; `terraform-target-parity.test.ts` asserts the callee declares none).
- A new boot-verify or power-off implementation → P8 → `scripts/lib/bastion-boot-verify.sh` already
  takes a `dispatch-label` argument whose documented value is `bastion-host-replace`.
- A new stock-check implementation → P6 → `stock_preflight_gate` counts a `["delete","create"]` as a
  create (`_stock_plan_creates` selects `index("create")`).
- A new address list → P3 → `tests/scripts/lib/bastion-resources.txt` is the one list; the
  replace gate reads it, as the birth gate does.

### Repo anchors

- `.github/workflows/apply-web-platform-infra.yml`: the `apply_target` `options:` list and its
  `description:` (`terraform-target-parity.test.ts` checks enum-to-description parity, and its
  options regex needs the list to stay followed by a blank line and `concurrency:`); the `plan_only`
  and `confirm` input descriptions name the targets they apply to; the `bastion_host_create` caller job
  is the template.
- `.github/workflows/bastion-host-create.yml`: the birth body, used here as the template. It covers
  the credential tiering, the Tier-B check, the DSN assertion, the scoped plan, the gate plus the stock
  gate, the boot anchor, the apply, boot-verify, the power-off on cancel, the pin read-back and the
  summary.
- `tests/scripts/lib/bastion-host-birth-gate.sh`: the arm idioms the replace gate reuses. These are
  the firewall content, the label binding, the attachment binding read from configuration references,
  the NIC IP pin and the allow-set drift check.
- `tests/scripts/lib/plan-gate-preamble.sh`: `plan_gate_assert_readable`,
  `plan_gate_assert_classifiable`, `plan_gate_assert_numeric`.
- `tests/scripts/lib/stock-preflight-gate.sh`: `stock_preflight_gate <plan>`,
  `stock_abort_closing <label> [tail]`, `stock_recovery_report <label> <plan> [--probe-state]`.
- `scripts/lib/bastion-boot-verify.sh`: `bastion_boot_verify <since> <apply-outcome> [label]` and
  `_bbv_poweroff`. Its recovery line still says "#12879, not yet available", and it comments on #12879.
- `apps/web-platform/infra/bastion.tf`: no `prevent_destroy` and no `create_before_destroy` (so a
  replace destroys first); `ignore_changes = [ssh_keys]`; the NIC's `server_id` is ForceNew; the
  firewall attachment's id is the firewall's, so a server replace plans it as an in-place `update`.
- Census suites that name the bastion routes (from repo research):
  `plugins/soleur/test/terraform-target-parity.test.ts` (`stripDispatchJobs`, `MAIN_ROOT_TF_WORKFLOWS`,
  the bastion describe block); `plugins/soleur/test/stock-preflight-coverage.test.ts` (follows a
  caller's `uses:` into "the one job that applies"); `tests/scripts/test-infra-privileged-tier-census.sh`
  (`PLAN_ONLY_JOBS`, the reusable-caller Tier-B clause);
  `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` (the `prov_job` loop and the
  AC8e reusable-file block); `apps/web-platform/infra/kernel-currency.test.sh` (the `job_timeout`
  budget rows); `apps/web-platform/infra/lib/bastion-lint.py` (`BASTION_FILES`);
  `plugins/soleur/test/heartbeat-reprovision-parity.test.ts` (whose `hasReplaceLine` greps only the apply
  file's text); `scripts/test-all.sh` (the `run_suite` lines for the bastion suites);
  `scripts/lib/test-affected-paths.sh`; `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv`.

### Institutional learnings applied

- `2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-...`: measure the file
  at `main`'s tip right before any dispatch. A kept comment line counts as anchored only after deleting
  it reds its cited consumer.
- `2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm.md`: pin the
  destroy to `before.id`; accept the bare-create recovery shape.
- `2026-09-03-the-gate-cleared-the-destroy-and-never-graded-the-create.md`: grade the replacement's
  `after` values (the NIC IP, the firewall binding, the host-key wiring), not only the destroy.
- `2026-11-17-a-split-pr-cannot-ship-a-boot-armed-heartbeat-before-its-replace-route.md`: the
  heartbeat parity test needs a literal `-replace='hcloud_server.bastion'` that its reader can see.
- `2026-11-19-a-reusable-workflow-hides-its-steps-from-every-suite-that-reads-the-caller.md`: every suite
  that parses the caller must follow `uses:`.
- `2026-11-25-i-fixed-the-gate-instead-of-the-workflow-and-shipped-an-empty-token.md`: pass every
  environment secret by name; never fix a gate by deleting the line it flags.
- `2026-11-08-a-merge-that-edits-registry-cloud-init-auto-replaces-...`: the reusable body has only
  `workflow_call`, never a `push` trigger.
- `2026-11-23-a-new-workflow-job-moved-other-suites-anchors-...`: grep the neighbours' names before
  inserting a job.
- `2026-11-09-testall-run-suite-registration-window.md`: the `run_suite` line goes inside the
  `want_scripts` block. Check it with `bash scripts/test-all.sh --enumerate scripts | grep bastion-host-replace`.
- `2026-07-15-replace-shaped-ops-are-net-zero-on-the-resource-they-exhaust.md`: the stock gate must
  not count the replaced server as a new quota slot. It checks stock, not quota, so this holds.

### Functional overlap

`soleur:engineering:discovery:functional-discovery` queried three registries and found no overlap
worth installing (the HashiCorp Terraform MCP plugin does general Terraform automation, not plan
gating). Community discovery: no uncovered stack.

### CLAUDE.md conventions

Sourced gates live under `tests/scripts/lib/` and are the same bytes CI runs. Fixtures are
synthesized (`cq-test-fixtures-synthesized-only`, ADR-322). Tests come first
(`cq-write-failing-tests-before`). Citations use content anchors, never line numbers
(`cq-cite-content-anchor-not-line-number`).

## CTO Rulings (2026-11-28, binding)

The full table is in `knowledge-base/project/specs/feat-one-shot-12879-bastion-host-replace-route/decision-challenges.md`.
In short (R1-R5 came after plan review and amend the earlier rows where they say so):

- **Q1, narrowed by R2.** The route only. The heartbeat is **#13113**, filed at plan time and blocked
  by #12879. This PR fixes one thing in `heartbeat-reprovision-parity.test.ts`: `hasReplaceLine`
  strips comments before matching. That hardens today's registry and inngest rows. Following a
  caller's `uses:` into the callee moved to #13113 with its fixtures, because nothing in this PR
  consumes it. Deferring is safe: if it is missed, the parity test goes red. Guard 2 pins the
  callee's real `-replace='hcloud_server.bastion'` array line.
- **Q2.** The body goes in a new reusable `.github/workflows/bastion-host-replace.yml` with its own
  thin caller job `bastion_host_replace`. `calledApplyingSteps` needs one applying job per called
  file. The ADR-327 "joins it there" wording is amended, and #12942 was commented.
- **Q3.** The id pin needs three-way agreement: the `expected_bastion_server_id` input, the live
  Hetzner API (exactly one `soleur-bastion` with label `role=bastion`), and the plan's `before.id`.
  The values are compared as strings (`tostring`), because the API id is a number and the other two
  are strings. The recovery arm requires the literal `none`. The job re-reads the API before the apply.
- **Q4, amended by Q4b.** `apply-web-platform-infra.yml` is at most **488,000** bytes, measured with
  `wc -c` after the rebase. This PR is **#8385's first slice**. The bastion routes are per-target
  callees with thin callers. The relocation frees only what the caller needs, in ADR-231's format:
  each block keeps its first line, its test-anchored lines and the `# Rationale:` pointer. It is its
  own commit.

  An ADR-231 addendum records four things: the routes are the first slice; the relocation is the
  minimum and is not a substitute for the split; the counter has tripped (489,485 ≥ 485,000); and the
  next PR that adds caller bytes must take the split. A comment on #8385 records the trip. The plan
  does not count on #12958.
- **Q5.** The arms are Guard 1. Plan review added one accepted shape: on the replace arm, the NIC may
  be `["create"]` (with the 10.0.1.70 pin), because a re-dispatch after a partial replace plans it that
  way. There is still no third arm.
- **Q6, amended by R4.** The PR body says **`Ref #12879`**. Boot-verify's `gh issue comment` moves to
  the open epic **#9421** in this PR. A comment on #9421 records that this target must move again
  before the epic closes.
- **Q7.** `confirm=REPLACE-bastion`, `environment: web-platform-infra-apply`, boot-verify with label
  `bastion-host-replace`, the cancel power-off, and stock preflight after the gate and before the apply.
- **F1.** The birth-readiness interlock moves to `scripts/lib/bastion-birth-readiness.sh`. The function
  is `bastion_birth_readiness <label>`, called from a step still named "Birth-readiness interlock".
- **F2.** The gate signature is `bastion_host_replace_gate <plan-json> <expected-id|none> <hetzner-servers-json-file>`,
  and the gate grades the raw API document.
- **F3, withdrawn by R1.** There is no before-and-after fingerprint compare. Both reads would come
  from state, so the compare could never fail. The existing "Record the bastion pin" read-back stays.
  The runtime proof of the key is a dialer that pins it, in step 3 (#12880).
- **F4.** `-replace='hcloud_server.bastion'` is passed only on the replace arm, on a real array line.
- **F5.** `bastion_host_replace` joins `PLAN_ONLY_JOBS`, and the plan-only notice comes from the summary step.
- **R3.** The create-side checks both gates need move into `tests/scripts/lib/bastion-gate-common.sh`.
  That is the firewall content, the label bindings, the attachment binding from configuration
  references, the NIC IP pin, inline `firewall_ids`, and the allow-set load and drift check. The
  extraction is its own commit, before the replace gate lands. `tests/scripts/test-bastion-host-birth-gate.sh`
  must pass with **no assertion changed**; only how it sources the gate may change. If any assertion
  has to change, stop and copy the checks instead.
- **R5.** Two cases stay out of scope, and the runbook says the route refuses them, quoting the ABORT
  text:
  - lost state while Hetzner still holds `soleur-bastion` is **#13117**. It depends on #13116, because
    losing state loses the host key.
  - a deliberate host-key rotation is **#13116**.

## Research Reconciliation — Spec vs. Codebase

| Spec / brief claim | Codebase reality | Plan response |
|---|---|---|
| "new apply_target value and job in apply-web-platform-infra.yml" [issue] | The file has 515 bytes of headroom. 2a moved its body into a reusable file for this reason. | A thin caller job lives in the apply file. The body goes in `bastion-host-replace.yml` (Q2). The file nets at most 488,000 bytes (Q4). |
| "pinned to the live server's physical id" [issue] | No sibling host-replace gate pins a physical id. Only `registry-luks-recut` pins one, by a dispatch input. | New input, API read and `before.id` agreement (Q3). This is new work, not a copy. |
| "accepts a create-only recovery arm only when state has no bastion server and the live Hetzner API shows no server named soleur-bastion" [issue] | `bastion-host-birth-gate.sh` passes a create on empty state but never asks the API. | The recovery arm lives in the replace gate. It requires pin `none`, zero API servers, and no server in `prior_state` (Q5). |
| "uses the shared terraform-apply-web-platform-host concurrency group" [issue] | A reusable callee runs inside the caller's run, and the caller holds that group at workflow level. `terraform-target-parity.test.ts` asserts the callee declares none. | No `concurrency:` in the callee or on the caller job. Pinned by the new parity block (Guard 2). |
| "#12879 (2b) adds the replace route and heartbeat" [ADR-327 addendum] | The issue body omits the heartbeat. | Heartbeat deferred to #13113 (Q1). The ADR addendum is amended. |
| "2b's replace job joins it there" [ADR-327]; "#12879 grows the same file" [#12942] | `calledApplyingSteps` reads one applying job per called file. | Separate callee file (Q2). The ADR is amended; #12942 was commented. |
| "A plan_only run against the real bastion passes the gate" [issue, done-when] | The bastion is not born. | Post-merge Operator Hold. The PR says `Ref #12879` (Q6). |

## Hypotheses

- **H1. What a `-replace` of `hcloud_server.bastion` plans** in the scoped target set:
  - `hcloud_server.bastion`: `["delete","create"]`.
  - `hcloud_server_network.bastion`: `["delete","create"]` (`server_id` is ForceNew).
  - `hcloud_firewall_attachment.bastion`: `["update"]`, whose `server_ids` holds one unknown element.
    Plan JSON renders that as `after.server_ids = [null]` and `after_unknown.server_ids = [true]`.
    This is confirmed from Terraform v1.10.5 source (see the Verified facts table). A wholly unknown
    set, `true` with `after` omitted, is unreachable for this configuration. The fixtures cover both
    renderings anyway.
  - `hcloud_firewall.bastion` and `tls_private_key.bastion_host_ssh`: `["no-op"]`.

  `before.id` is a string in plan JSON, and the Hetzner API's `.servers[].id` is a number. The fixtures
  use those real types. None of this can be confirmed against a real plan until a bastion exists, so
  the post-merge `plan_only` run is the confirmation (Operator Hold). A wrong guess fails closed: the
  gate refuses and nothing is destroyed. The fix is then a follow-up PR that widens one arm and adds a
  fixture.
- **H2. The recovery arm plans without `-replace`** (F4), so it never relies on how Terraform treats a
  `-replace` address that is absent from state.
- **H3. Partial failures, and how each one recovers.**
  - The server create returned an id and a later resource failed (the NIC create, or the attachment
    update). The new server is in state. A replace dispatch pinned to the **new** id plans the server
    `["delete","create"]` again, and plans the NIC as `["create"]`, which the replace arm accepts (Q5).
  - The destroy landed and the create never returned an id. State and the API both hold no server, so
    the recovery arm (`none`) applies.
  - Lost state while the API still shows a server is refused (#13117).

## Proposed Solution

One new dispatch route with the same shape as the birth route:

```text
gh workflow run apply-web-platform-infra.yml -f apply_target=bastion-host-replace \
  -f confirm=REPLACE-bastion -f expected_bastion_server_id=<id|none> -f plan_only=true \
  -f reason='...'
```

Flow inside `bastion-host-replace.yml`, job `bastion_host_replace` (environment
`web-platform-infra-apply`):

1. Checkout and setup-terraform. Tiered credentials, with Tier-B required: the power-off and the API
   read need the read/write `HCLOUD_TOKEN`.
2. **Validate dispatch inputs.** `confirm` must equal `REPLACE-bastion`, and
   `expected_bastion_server_id` must match `^([1-9][0-9]{0,11}|none)$`. Both come in through `env:`
   and never appear in `run:` bodies.
3. **Birth-readiness interlock** (F1): `bastion_birth_readiness bastion-host-replace`.
4. The ephemeral SSH public key, the required secrets, the R2 backend credentials, and the
   `SENTRY_DSN` assertion, as in the birth body.
5. `terraform init -lockfile=readonly`.
6. **Read the live bastion from Hetzner.** `GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion`.
   The bearer token goes in through `-H @-` from `printf`, never in argv. The response is saved to
   `hetzner-servers.json`. Any curl error, non-2xx status or non-JSON body fails the step before any
   plan. The step then prints every returned `id name labels.role status` to the step summary. Server
   ids are not secret, so a `plan_only` run also tells the reader the live id.
7. **Plan:** `terraform plan -out=tfplan` over exactly the five `bastion-resources.txt` `-target`
   lines. On the replace arm only, `"${replace_args[@]}"` carries `-replace='hcloud_server.bastion'` (F4).
8. **Gate, then stock preflight.** `bastion_host_replace_gate tfplan.json "$EXPECTED_ID" hetzner-servers.json`
   runs first. Every ABORT prints the pin, every API id and `before.id`, then the counter vector. Then
   `stock_preflight_gate tfplan.json`, aborting with `stock_abort_closing bastion-host-replace ...`.
9. **Summary** (`if: always()`). It lists the commit, the pin, the live API ids, the arm the gate took
   or the arm that refused, and the planned (action, address) list. It also emits the `plan_only`
   notice (F5). Running on `always()` means a refused rehearsal still shows the reader why.
10. Every step from here on carries `if: inputs.plan_only != true`:
    - **TOCTOU re-pin.** Re-read the API and compare `[.servers[] | {id: (.id|tostring), role: .labels.role}]`
      with the saved document. Abort before the apply if they differ.
    - The boot-trail anchor.
    - `terraform apply tfplan`. On failure, `stock_recovery_report bastion-host-replace tfplan.json --probe-state`
      runs. The step then re-reads the API and state and prints one ready-to-run `gh workflow run ...`
      line, with `expected_bastion_server_id=none` when no server exists and `=<new id>` when a new
      server exists (H3).
11. **Boot verify.** `bastion_boot_verify "$since" "$apply_outcome" bastion-host-replace "$OLD_ID"`.
    The new optional fourth argument is the pinned old id (`none` on the recovery arm). Boot-verify
    refuses to read or power off a server whose id equals it. It decides only when the API shows a
    `soleur-bastion` whose id differs from the old pin. If the apply failed before the old server was
    deleted, the old server is never touched. A server that is not ready is powered off with its disk
    kept, and the run URL is commented on #9421 (R4). The cancel power-off step copies the birth body's
    `if:`, adds the `plan_only` guard, and passes the same old id.
12. **Record the bastion pin.** The fingerprint and private IP read-back, unchanged from the birth body.
13. **Dispatch summary**, using the outcome-pair logic copied from the birth body. For a not-ready
    replacement it prints the powered-off server's id and the ready-to-run replace dispatch line. The
    old server is already gone, so the next step is another `bastion-host-replace` with that id (Q7).

## Implementation Phases

### Phase 0 — Measure, then free bytes (Q4). This phase is its own commit.

1. `git fetch origin main` and rebase. Record `wc -c .github/workflows/apply-web-platform-infra.yml`.
   If #12958 has merged, rebase onto it first. Its hunks sit at the `apply` job and the
   `ci_ssh_token_replace` region, away from the inputs block and from the insertion point after
   `bastion_host_create`.
2. Move comment blocks verbatim, largest first and only as many as the ceiling needs, into
   `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`. Each block
   gets a `## <input name>` section, and the workflow keeps one
   `# Rationale: knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md §<name>`
   line in its place.

   The candidates, measured 2026-11-28, all sit in the `workflow_dispatch.inputs` block:

   | Block | Bytes |
   |---|---|
   | `manual-rerun` | 1,338 |
   | `expected_registry_store_volume_id` | 964 |
   | `web_host_key` | 782 |
   | `apply_target` "FIELD LABEL" | 647 |
   | `expected_luks_volume_id` | 562 |
   | `image_tag` | 436 |
   | **Sum** | **4,729** |

   **Measured on 2026-11-28, keeping each block's first line plus a full-path pointer line (Q4b):**

   | Block | Freed |
   |---|---|
   | `manual-rerun` | 1,127 |
   | `expected_registry_store_volume_id` | 721 |
   | `web_host_key` | 567 |
   | `apply_target` field label | 409 |
   | `expected_luks_volume_id` | 328 |
   | `image_tag` | 223 |
   | **Total** | **3,375** |

   The additions cost about 990 B: the caller (about 600 B), the input (about 250 B), the option (33 B)
   and three description entries (about 70 B together). The net is 489,485 - 3,375 + 990, which is about
   487,100 B, about 900 B under the 488,000 ceiling. This is an estimate until `wc -c` measures it, and
   AC1 is the measurement. If the measured net misses the ceiling, the PR stops and reports. It does
   not open a further relocation round (Q4b). Any anchored line that must stay reduces the freed bytes
   by its length.

   For each block, grep `plugins/ tests/ apps/ scripts/` for its distinctive phrases first. A phrase
   that a suite anchors on stays in the workflow. Confirm each anchor by deleting the phrase and
   running the cited consumer (learning 2026-09-19).
3. The relocation commit changes comments only. Prove it: `yaml.safe_load` of the file at that commit
   is **exactly equal** to the parse of its parent, and the `actionlint` findings are unchanged.

### Phase 1 — Extract the shared gate checks (R3). This phase is its own commit.

1. Move the birth gate's create-side checks, word for word, into `tests/scripts/lib/bastion-gate-common.sh`.
   That covers the allow-set load and drift check, the firewall content and unreadable checks, the
   `apply_to` and `label_selectors` checks, the attachment binding from configuration references, the
   NIC IP pin, inline `firewall_ids`, and `_BHBG_JQ_UNKNOWN`. `bastion-host-birth-gate.sh` sources the
   common file and calls it.
2. `bash tests/scripts/test-bastion-host-birth-gate.sh` passes with no assertion changed. The diff of
   the suite touches only how it sources the gate. If an assertion has to change, stop and copy the
   checks into the replace gate instead (R3).

### Phase 2 — Tests first (`cq-write-failing-tests-before`)

1. `tests/scripts/test-bastion-host-replace-gate.sh`: the full Guard 1 matrix, including the H rows,
   on synthesized plan and API documents (ADR-322). The fixtures use the real types: a string
   `before.id` and a numeric API id. Model it on `test-bastion-host-birth-gate.sh`: the instrument
   self-test, the `NOT IMPLEMENTED` stub, the H1 `return 0` flip, and the floor printed by `printf`
   plus `exit 1`.
2. `plugins/soleur/test/terraform-target-parity.test.ts`:
   - Add `bastion-host-replace.yml` to `MAIN_ROOT_TF_WORKFLOWS`, and add `bastion_host_replace` to
     `stripDispatchJobs`.
   - Run the existing bastion describe block's caller, secret, env, `-target` and exclusion tests over
     both `[bastion_host_create, bastion_host_replace]`.
   - Add the Guard 2 rows that only the replace route needs.
3. `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`: `hasReplaceLine` strips comments
   before it matches (Guard 3), with a fixture showing that a commented-out literal no longer counts.
   Its pure-over-inputs signature stays as it is.
4. `tests/scripts/test-bastion-boot-verify.sh` gets new rows:
   - The `bastion-host-replace` label's recovery text. It never says "not yet available" and never
     says "Do not re-run bastion-host-create".
   - The comment target is #9421.
   - The fourth-argument old id. A server with that id is never powered off, and with `none` the
     behaviour is unchanged.
   - `bastion_birth_readiness` (F1): each label's HELD message, a missing emitter literal, an unbound
     token, and a malformed token.

### Phase 3 — Gate and libraries

1. `tests/scripts/lib/bastion-host-replace-gate.sh`. It sources `plan-gate-preamble.sh` and
   `bastion-gate-common.sh`. It adds what only a replace needs: the three-way pin with `tostring`, the
   API-document checks, the replace and recovery arms, the exact no-op of the key and the firewall,
   and the replacement's `after` values. Each arm has one counter, and every counter goes through
   `plan_gate_assert_numeric`.
2. `scripts/lib/bastion-birth-readiness.sh` (F1). The function is `bastion_birth_readiness <label>`.
   Its body moves word for word from the birth step, with `bastion-host-create` replaced by `${label}`.
   `bastion-host-create.yml`'s step keeps its name and becomes a source-and-call.
3. `scripts/lib/bastion-boot-verify.sh` changes:
   - Replace the "#12879, not yet available — escalate to the owner" recovery text with the live route
     (`bastion-host-replace`, `confirm=REPLACE-bastion`, `expected_bastion_server_id`).
   - Add the replace-label clause, which prints the ready-to-run replace dispatch for the powered-off
     server.
   - Add the optional fourth argument, the old id (step 11).
   - Point `gh issue comment` at #9421 (R4).
   - Point the "no heartbeat until #12879" header line at #13113.

### Phase 4 — Workflows

1. `.github/workflows/bastion-host-replace.yml`, following the Proposed Solution flow. It has
   `on: workflow_call` only:
   - inputs `confirm`, `plan_only`, `reason`, `expected_bastion_server_id`;
   - secrets by name, with `DOPPLER_TOKEN_INFRA_PRIVILEGED` `required: true`;
   - workflow-level `permissions: contents: read`;
   - redeclared `TERRAFORM_VERSION`, `TF_VAR_terraform_version` and `INFRA_DIR`;
   - no `concurrency:`.

   `timeout-minutes` is the birth's plus one destroy minute, which `kernel-currency.test.sh` checks.
2. `.github/workflows/apply-web-platform-infra.yml`:
   - Add the `expected_bastion_server_id` input, with a one-line description and no comment block.
     Check GitHub's documented `workflow_dispatch` input limit first, since this is the 10th input.
   - Add the `- bastion-host-replace` option after `- bastion-host-create`.
   - Add `bastion-host-replace` to the `apply_target` description list, with one clause:
     "bastion-host-replace DESTROYS AND RECREATES soleur-bastion (host key kept); needs
     `confirm=REPLACE-bastion` + `expected_bastion_server_id` (`none` to recover a lost server)".
   - Add it to the `plan_only` target list and to the reviewer-gated list in the `confirm` description.
   - Add the thin `bastion_host_replace` caller job immediately after `bastion_host_create`. It passes
     the four inputs and the three secrets by name, with `permissions: contents: read, issues: write`.
3. `.github/workflows/bastion-host-create.yml` gets four edits:
   - The interlock step becomes a source-and-call (F1).
   - The pre-apply id set is passed to boot-verify and the cancel power-off.
   - The summary branches on `comment_result` and names #9421 and #13113.
   - The pin read-back prints the server id.

   These follow Deepen-Plan Research Insights.

### Phase 5 — Census, registration and records

1. Find every suite that reads the caller's jobs:
   `git grep -l 'apply-web-platform-infra.yml' -- ':!knowledge-base' ':!.github' ':!*.md' | xargs grep -lE 'bastion_host_create|\.jobs\b|\.steps\b|jobs\[|\bsteps:'`.
   Do the same for `bastion-host-create.yml` (sharp edge "a job body in a reusable workflow"). Read
   each hit. Then run the census suites and edit the ones that go red, plus those the rulings
   require. The expected edits are:
   - `PLAN_ONLY_JOBS` in `tests/scripts/test-infra-privileged-tier-census.sh` (F5);
   - the `prov_job` loop and an AC8e-shaped block in `soleur-host-bootstrap-observability.test.sh`;
   - a `job_timeout bastion_host_replace "$BRWF"` row in `kernel-currency.test.sh`;
   - `bastion-runcmd-rehearsal.test.sh`, whose `for lit in ...` anchor on the interlock moves to
     `scripts/lib/bastion-birth-readiness.sh` with F1;
   - `tests/scripts/test-argv-bearer-sweep.sh`, whose S4 count of `_bearer_ok` definitions changes
     when the library gains one;
   - `BASTION_FILES` in `lib/bastion-lint.py`, if it reds.
2. `scripts/test-all.sh`: add
   `run_suite "tests/scripts/bastion-host-replace-gate" bash tests/scripts/test-bastion-host-replace-gate.sh`
   beside the bastion lines, inside the `want_scripts` block. In `scripts/lib/test-affected-paths.sh`,
   add the new gate, the common file and the readiness library to the bastion edges. Add rows to
   `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` only if the registration gates
   ask for them. The proof is `--enumerate scripts` together with `bash scripts/lint-orphan-test-suites.sh`
   once the file is tracked.
3. Records:
   - **ADR-327:** add a 2026-11-28 addendum (#12879, step 2b) covering:
     - the route and its three-way id pin;
     - the recovery arm;
     - the separate callee, which amends "joins it there";
     - the heartbeat moving to #13113;
     - the two refused cases (#13116, #13117);
     - the shared libraries (F1, R3);
     - `Ref #12879` until the post-birth proof.

     It also says that "its own replace route bounds that risk" holds only once a bastion exists, and
     that step 3 (#12867) must revisit replace downtime and draining its consumer.
   - **`bastion-host.md`** (R4, R5):
     - line 7: the replace route is live;
     - line 12: "no heartbeat until #12879" becomes #13113;
     - line 48: names the route with its exact inputs;
     - lines 57 and 61: the comment target becomes #9421;
     - line 67: the replace job reads the trail;
     - line 71: lost state with a live server is **refused**, quoting the ABORT text and pointing at #13117;
     - line 84: rotation is refused by both routes and lives at #13116.

     Add two new sections:
     - "Replacing the bastion": `plan_only` first; reading the live id from that run's summary (or the
       read-only Hetzner recipe in `git-data-luks-cutover-5274.md` where reading the read-only token
       is permitted); `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch -L1 --json databaseId,url`
       and `gh run watch <id>`, noting that "waiting" means the run is waiting for the environment
       reviewer; and each failure's next dispatch.
     - "Recovering a failed replace", covering the H3 cases.
   - **`model.c4`:** the bastion container's description, the `github -> bastion` edge description, and
     the `bastion -> sentry` heartbeat clause (now #13113). Run `c4-code-syntax.test.ts`,
     `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 6 — Verify locally

1. Run every suite named in Files to Edit, plus `bun test plugins/soleur/test/workflow-file-size.test.ts`,
   `terraform-target-parity`, `stock-preflight-coverage` and `heartbeat-reprovision-parity`.
2. Run `bash scripts/test-all.sh --enumerate scripts | grep bastion-host-replace`, `actionlint` on
   both workflows, `shellcheck` on the new libraries, and `lint-infra-no-human-steps.py --changed`.
3. Measure `wc -c` against the 488,000 ceiling.

### Phase 7 — After merge (Operator Holds, never in this PR)

- The bastion birth, on the owner's go, after #12942 and the runbook's pre-birth evidence.
- A `plan_only` dispatch of `bastion-host-replace`, pinned to the born id, against the real bastion.
  It needs the owner's typed go naming the exact command. Its PASS satisfies #12879's done-when 2, and
  #12879 closes then.

## Deepen-Plan Research Insights (2026-11-28)

These amend the sections above. Where they conflict, this section wins. `tasks.md` carries the same
amendments.

### Boot-verify never touches a server that existed before the apply (spec-flow row 1, Kieran #5)

- The old-id argument becomes a **pre-apply id set**. Before the apply, the job records every
  `soleur-bastion` id from the API. Boot-verify (`bastion_boot_verify <since> <outcome> <label> <pre-ids>`)
  refuses to read or power off any server whose id is in that set. It decides only on a server whose
  id is not in it. If no such server exists, it records the new result `poweroff_result=old_untouched`
  (or `absent`). The summary prints a re-dispatch line that keeps the same pin.
- **Both routes pass the set.** The birth body passes it too (the F1 edit already touches that
  file). If state is lost while the bastion is live, the birth route's create fails on the duplicate
  name. Without the set, birth boot-verify would power off the healthy live server. With the set, it
  touches nothing.
- The runbook's "Lost state" section says not to use the birth route either. Until #13117 lands,
  there is no safe in-repo action, so the ABORT text says exactly that.
- Rows in `test-bastion-boot-verify.sh`:
  - a pre-apply id is never powered off (the curl fake asserts the id in the POST URL);
  - a positive control: a different id that is not ready IS powered off;
  - an empty set behaves exactly as today;
  - `old_untouched` produces its own summary and comment text.

### Every exit prints its next action (spec-flow rows 2-4, 6-7, 9; CTO devex #3)

- **The next dispatch is computed in the always-run summary.** It comes from a fresh API read and
  `terraform state list`, so it is not limited to the apply-failure branch. It is one ready-to-run
  `gh workflow run ...` line. The pin is chosen like this:

  | State after the run | Pin printed |
  |---|---|
  | no server | `none` |
  | only a new id exists | the new id |
  | only the pre-apply id exists (apply failed before the destroy, or only the NIC was deleted) | the same pin |

  If the read itself fails, the summary prints `next dispatch: unread (API read failed); no line to
  copy`, never a guessed line.
- **TOCTOU mismatch:** "the live bastion changed since the plan: re-run `plan_only` and read the id
  from its summary". The comparison also includes `status`.
- **Not ready:** the recovery line reads "read the boot-trail stage above, fix `bastion-cloud-init.yml`
  if it is a template fault, then replace (this destroys the kept disk)".
- **Server id in the summary:** the "Record the bastion pin" step prints the server id beside the
  fingerprint and IP, in both bodies. A first rehearsal against a born bastion can then read the id
  from the last birth's summary. The API listing in step 6 gives it on any `plan_only` run, refused
  or not.
- **Same-SHA rehearsal:** the runbook says to dispatch the `plan_only` run and the real run at the
  same commit, and to compare the two summaries' commit lines. #12942 adds the mechanical check for
  this.
- **Waiting for approval:** the runbook says the run holds the shared concurrency group while it waits
  for the reviewer, so approve or cancel promptly. It also says to confirm a re-dispatch was not
  superseded with `gh run list --workflow apply-web-platform-infra.yml -L 3 --json databaseId,status,conclusion`.

### Boot-verify reports truthfully (observability #2-#4)

- `bastion_boot_verify` records `comment_result=posted|failed|no_token`, and both summaries branch on
  it. The summaries never claim a comment that did not post. The birth summary's "#12879" and "no
  heartbeat until #12879" become #9421 and #13113. `bastion-host-create.yml`'s dispatch-summary step is
  therefore also edited.
- New failure modes, each with its own `::error::` literal. The response body is never printed, only
  the HTTP code and `.error.code`:
  - `bastion-host-replace: Hetzner server read FAILED (http=<code>)`, at step 6, before any plan;
  - `bastion-host-replace: TOCTOU re-read FAILED (http=<code>); nothing applied`;
  - `bastion-host-replace: post-failure state read FAILED; no next dispatch`;
  - `bastion-boot-verify: the comment on #9421 FAILED`. This changes `::warning::` to `::error::` on
    the replace label only. Birth keeps its `::warning::`, because its suite pins that string.
- The not-ready failure mode's alert route names its layer. It is the workflow run log line
  `::error::bastion-boot-verify: soleur-bastion is NOT ready` (layer 6), plus the power-off and the
  #9421 comment.

### Guard 1 matrix additions (test-design #2-#6; R3b)

- **Split row 1** into rows 1, 1b and 1c in the Guard 1 table:
  - `[null]`/`[true]` is canonical and PASS;
  - `true` with `after` omitted is PASS;
  - `[true]` with `after` omitted is RED.

  The common attachment check is extracted word for word. The replace gate adds its stricter
  `["update"]` requirement on top of it, and the common check is not edited.
- **Fixture type self-check.** Beside the base-fixture check, assert the
  `prior_state ... hcloud_server.bastion` `values.id` type is `string`, the `.servers[0].id` type is
  `number`, and the attachment's `before.server_ids` is `[<number>]`.
- **Three-way pin rows, one mismatch each.**
  - pin≠API, with API = `before.id`
  - pin = API, with API ≠ `before.id`
  - pin = `before.id`, with API ≠ the others
- **More RED rows.**
  - an attachment `["update"]` whose known `after.server_ids` is still the old id;
  - the server `["delete"]` with no create;
  - the NIC `["delete"]` with no create;
  - the server `["create","delete"]` (no `create_before_destroy` is declared);
  - each "or" in rows 8, 14, 16 and 21 split into its own row.
- **Message substrings.** Every RED row names its ABORT message substring, as the birth suite does.
- **Gate-mutation rows** (`gmut`-style exact-once replacements on the replace gate):
  - drop `tostring`;
  - drop the API count check;
  - drop the role check;
  - drop the recovery arm's `prior_state` check;
  - drop the attachment update-binding check;
  - drop each `after`-value check;
  - delete the call into `bastion-gate-common.sh` (R3b's call-site row).
- **Behaviour rows (R3b).** One synthesized plan per shared check, each going RED with the common
  message.
- **H2 is dropped.** The PASS rows already need exit 0. H3 keeps a literal `MIN_CASES` floor and a
  literal minimum RED count, as the birth suite does, not a count derived from the table.
- **R3b harness change in the birth suite.** The `gmut` helper takes a target file, and
  `scratch_gate` also copies `bastion-gate-common.sh`. Both gates source the common file from their own
  directory (the `_BHBG_DIR` pattern). `GMUT` stays at 11.

### Guard 2 additions (test-design #7-#8)

- **Order rows**, one for each adjacent swap. Each one must red:
  - interlock after the plan;
  - stock preflight before the gate;
  - TOCTOU before the preflight;
  - TOCTOU after the apply.
- **Wiring rows:**
  - the birth suite's "no `terraform plan` after the gate" row, with its re-plan mutation;
  - the gate call missing `hetzner-servers.json`;
  - the `replace_args` assignment outside the `!= none` block.
- **Placement.** The plan-chain rows (apply consumes `tfplan`, the order rows, the re-plan row) live
  in `test-bastion-host-replace-gate.sh`, as the birth suite's do. The parity-shaped rows (the `on`
  keys, the confirm literal, the caller secrets) stay in `terraform-target-parity.test.ts`.

### Guard 3 additions (test-design #8)

- A trailing comment (`foo # -replace='hcloud_server.x'`) is RED.
- `[[ ${#a[@]} -gt 0 ]] && x=(-replace='hcloud_server.x')` is PASS. The `#` inside `${#` must not
  start a comment.

### The pin covers every bastion record a replace deletes or updates (security #1, architecture #1)

- On the replace arm, the NIC delete requires `before.server_id|tostring == pin` and
  `before.ip == "10.0.1.70"`. The attachment update requires `before.server_ids|map(tostring) == [pin]`.
  Without these two checks, a state that maps the NIC or the attachment onto web-1 would detach web-1
  from the private network, or strip its firewall binding, while the server pin passes.
- The allow-set becomes **a per-address table of allowed actions**, inside the replace gate:

  | Address | Allowed actions |
  |---|---|
  | `hcloud_server.bastion` | replace arm: `["delete","create"]`; recovery arm: `["create"]` |
  | `hcloud_server_network.bastion` | replace arm: `["delete","create"]` or `["create"]`; recovery arm: `["create"]` |
  | `hcloud_firewall_attachment.bastion` | replace arm: `["update"]`; recovery arm: `["update"]` or `["create"]` |
  | `tls_private_key.bastion_host_ssh`, `hcloud_firewall.bastion` | `["no-op"]` |
  | any other `bastion-resources.txt` member | `["no-op"]` |

  An address that step 3 (#12867) or #13113 adds to the list is therefore never destroy-eligible by
  default. Matrix rows:
  - a new list member planned `["update"]` is RED;
  - `tls_private_key` planned `["create"]` (a key regenerated after lost state) is RED;
  - the NIC `before.server_id` ≠ pin is RED;
  - the attachment `before.server_ids` ≠ `[pin]` is RED;
  - an API server whose `name` ≠ `soleur-bastion` is RED (the name is checked exactly, not trusted to
    the `?name=` filter).

### One Hetzner reader, through `bc_curl` (security #4-#5, architecture #5)

- Add one helper, `_bbv_servers_doc <out-file>`, in `scripts/lib/bastion-boot-verify.sh`, next to
  `_bbv_lookup`. It calls `bc_curl bastion 'Authorization:Bearer :HCLOUD_TOKEN' -- -sS --max-time 20 -o "$out" -w '%{http_code}' "https://api.hetzner.cloud/v1/servers?name=soleur-bastion"`
  (ADR-280's `scripts/lib/bearer-curl.sh`). It requires HTTP 200 exactly and a `.servers|arrays`
  body. Any other result returns non-zero, with `http=<code>` and `.error.code` only.
- The step-6 read, the TOCTOU re-read and the post-failure next-dispatch read all use it.
  `_bbv_lookup` keeps its own call, because the birth suite pins it.
- **The TOCTOU re-read re-checks identity; it does not compare documents.** The fresh document goes
  back through the gate's identity function, which is exported as
  `bastion_replace_identity <pin> <doc> <before-id>` from the replace gate. The check is count 1,
  name exact, role `bastion`, and `id == pin == before.id`, or count 0 for `none`. Any read error
  fails closed.
- The pin is re-validated under `LC_ALL=C` inside the gate and inside the boot-verify library. It
  reaches jq only through `--arg`, never inside the program text. API ids must match `^[0-9]+$`
  before they are printed into a summary or a `gh workflow run` line. API string fields are printed
  through `@json`, so they cannot inject `::` workflow commands.
- F1 moves the interlock's inline `_bearer_ok` into the library. The repo-wide count of definitions
  stays the same, because one leaves the workflow and one enters the library. Re-run
  `test-argv-bearer-sweep.sh` anyway.

### Power-off refuses pre-apply ids at the lowest level (security #2, architecture #7)

- The guard lives in `_bbv_poweroff [pre-ids]`, not only in `bastion_boot_verify`. Both the cancel
  step (which calls `_bbv_poweroff` directly) and the failed-apply path go through it.
- For the label `bastion-host-replace`, a missing or malformed pre-id set fails closed: nothing is
  powered off, and the result is `poweroff_result=refused_no_preids`. Rows cover:
  - the cancel path with a pre-apply id;
  - the failed-apply path with a pre-apply id;
  - a missing set on the replace label.

### The plan JSON now carries the host private key (security #3)

- On a replace the key is a no-op, so the plan JSON's `prior_state` and the key's `change.before` and
  `change.after` hold `private_key_openssh` in clear text. At birth it was unknown at plan time. This
  is a **new** exposure, and the User-Brand Impact section is amended to say so.
- Mitigations in the replace body:
  - write `tfplan`, `tfplan.json` and `hetzner-servers.json` under `umask 077` into a `mktemp -d`
    under `$RUNNER_TEMP`;
  - mask each line of the key before any step can print it: read
    `jq -r '..|.private_key_openssh? // empty'` and `::add-mask::` each line;
  - the gate and the summaries print only addresses, actions, ids and attribute names, never values;
  - an `if: always()` final step deletes the directory.
- Matrix row: a fixture whose key fields hold a synthetic marker (`SYNTHETIC-KEY-MARKER`) must not
  appear in any gate output, ABORT line or summary text the suite captures.
- `tfplan.txt` (from `terraform show -no-color`) renders sensitive values as `(sensitive value)`, so
  the existing `grep` excerpt on ABORT stays safe.

### Branch and push cannot reach the destroy (security #7)

- Guard 2 adds two rows. One asserts both clauses of the caller's `if:` (`github.event_name == 'workflow_dispatch'`
  and the `apply_target` match). The other asserts a callee job-level
  `if: github.ref == 'refs/heads/main'`. That second check is defence in depth behind the
  environment's main-only branch policy (`web-host-birth-environment.tf`). The callee has no byte
  limit, so the check is free.
- The reviewer gate on `web-platform-infra-apply` is the owner's own approval (one required reviewer,
  user 54279), not a second person. The ADR-327 addendum states this, as the 2a addendum did for
  birth.

### Precedent departures, now named (architecture #2, #8)

- **The recovery arm admits a bare create.** `web-host-replace-gate.sh` refuses one and routes it to
  the birth route. The bastion admits it here because the issue requires it, and because only this
  gate checks the API for zero servers. The ADR-327 addendum names the departure.
- **ABORT lines follow the sibling convention.** Each ends "NOTHING HAS BEEN DESTROYED — this gate runs
  before the apply." followed by the specific next action, which comes from the summary's
  next-dispatch line.
- **`git_data_host_post_apply_assert`** (#10137) is a post-apply backstop. It is not adopted here,
  because boot-verify's strict verdict plus the pin read-back covers this host's post-apply truth.
- **The shared checks** follow the `git-data-root-key-arm-gate.sh` sourced-sub-gate precedent: a
  `declare -F` idempotent guard, a 127-on-failed-source note, and functions that take a gate label so
  messages name the calling gate. The birth gate's `creates`, `destroys` and `key_touched` arms stay in
  the birth gate.

### Verified facts (framework-docs research, pinned Terraform 1.10.5 and hcloud provider 1.63.0)

| Claim | Verdict | Source |
|---|---|---|
| `server_ids = [hcloud_server.bastion.id]` on a replace is a known one-element set with an unknown element: `after.server_ids = [null]`, `after_unknown.server_ids = [true]` (a wholly unknown set would be `true` and omitted from `after`) | confirmed (source) | terraform `internal/command/jsonplan/plan.go` `unknownAsBool`, `omitUnknowns` at v1.10.5 |
| `hcloud_server` `before.id` is a string | confirmed | hcloud `internal/server/resource.go` v1.63.0 (`d.SetId(util.FormatID(...))`) |
| Hetzner `servers[].id` is an integer, and `name` is an exact filter | confirmed | Hetzner Cloud OpenAPI spec |
| `hcloud_server_network.server_id` is RequiresReplace; `hcloud_firewall_attachment.server_ids` updates in place (only `firewall_id` is ForceNew) | confirmed | hcloud `internal/server/resource_network.go`, `internal/firewall/attachment_resource.go` v1.63.0 |
| `prior_state` under `-target` is complete, and is the refreshed state | confirmed | terraform `internal/command/jsonplan/values.go` |
| `workflow_dispatch` allows 25 inputs (was 10) | confirmed | <https://github.blog/changelog/2025-12-04-actions-workflow-dispatch-workflows-now-support-25-inputs/> |
| `-replace` naming an address absent from state is silent: the plan just creates it | confirmed (source) | terraform `internal/terraform/node_resource_plan_instance.go` v1.10.5. F4 stays for clarity, not necessity. |
| The empty-result shape is `{"servers": [], "meta": {...}}` | unverified | The gate requires only `.servers|arrays`, which holds either way. |

H1 is therefore confirmed by source, not only assumed. The canonical replace fixture uses
`after.server_ids=[null]` and `after_unknown.server_ids=[true]`. The birth gate's word-for-word
`att_ok` passes it through `(.change.after.server_ids|length)==1`, so the extraction needs no new arm
for this shape. The `[true]`-with-`after`-absent row (1c) is kept as a RED row, because that shape is
unreachable for this configuration.

## Files to Create

- `.github/workflows/bastion-host-replace.yml`
- `tests/scripts/lib/bastion-host-replace-gate.sh`
- `tests/scripts/lib/bastion-gate-common.sh` (R3)
- `tests/scripts/test-bastion-host-replace-gate.sh`
- `scripts/lib/bastion-birth-readiness.sh` (F1)

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml`: the input, the option, three descriptions, the
  caller, and the comment relocations.
- `.github/workflows/bastion-host-create.yml`: four edits.
  - The interlock becomes a source-and-call (F1).
  - The pre-apply id set is passed to boot-verify and the cancel power-off.
  - The summary branches on `comment_result` and names #9421 and #13113.
  - The pin read-back prints the server id.
- `tests/scripts/lib/bastion-host-birth-gate.sh`: sources the common checks (R3).
- `tests/scripts/test-bastion-host-birth-gate.sh`: only if sourcing changes; no assertion changes (R3).
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
- `knowledge-base/engineering/operations/runbooks/bastion-host.md`
- `knowledge-base/engineering/architecture/decisions/ADR-327-dedicated-bastion-web-hosts-are-identical-cattle.md`
- `knowledge-base/engineering/architecture/decisions/ADR-231-workflow-files-are-byte-budgeted-and-rationale-relocates-to-a-runbook.md` (Q4b addendum)
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `scripts/lib/bastion-boot-verify.sh`
- `scripts/test-all.sh`
- `scripts/lib/test-affected-paths.sh`. Also `scripts/suite-shard-legs.tsv` and
  `scripts/suite-durations.tsv`, but only if a registration gate asks for rows.
- `tests/scripts/test-bastion-boot-verify.sh`
- `tests/scripts/test-infra-privileged-tier-census.sh` (`PLAN_ONLY_JOBS`)
- `tests/scripts/test-argv-bearer-sweep.sh`: verify the S4 count, and edit it if it reds.
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`: comment stripping only (R2).
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`
- `apps/web-platform/infra/kernel-currency.test.sh`
- `apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh`: the interlock anchor moves to the library.
- `apps/web-platform/infra/lib/bastion-lint.py`: only if it reds.
- `plugins/soleur/test/stock-preflight-coverage.test.ts`: verify only. `calledApplyingSteps` already
  follows `uses:`.

`apps/web-platform/infra/bastion.tf` and `bastion-cloud-init.yml` are **not** edited. A cloud-init edit
plans a bastion replace, and the heartbeat is #13113.

## Open Code-Review Overlap

2 open scope-outs touch these files:

- **#7098** (audit the `run:` bodies whose `set` omits `-e`), on `apply-web-platform-infra.yml`.
  **Acknowledge.** This PR adds a `uses:` caller with no `run:` body, and its relocations are comment-only.
- **#7942** (two `*.mutation.sh` batteries run in no gate), on `scripts/test-all.sh`. **Acknowledge.**
  This PR registers its suite under a `test-*.sh` name, so it does not repeat that defect.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly. The bastion has no consumer until
step 3 (#12867), which this PR blocks. A broken route surfaces later, when the owner cannot
recover a dead bastion. Once step 3 lands, that means no SSH management plane for deploys and host
repair, and a delayed fix for the next user-facing incident.

**If this leaks, the user's data / workflow is exposed via:** a mis-scoped destroy. A gate that admits
a plan whose `hcloud_server.bastion` address maps onto another physical server, for example web-1,
would destroy a production host that serves every user's workspace. The three-way id pin and the
out-of-scope arm exist for this. A second exposure is the bastion host key's private half. It sits in
Terraform state and in the runner-local plan file (the ADR-327 residual). This route never changes the
key and never uploads the plan file as an artifact. A replace adds a **new** exposure that birth did
not have: the key is a no-op, so the plan JSON's `prior_state` holds `private_key_openssh` in clear
text. Deepen-Plan Research Insights prescribes the mitigation: `umask 077` in `$RUNNER_TEMP`, a mask
for every line, no value printing, and an `always()` delete.

**Brand-survival threshold:** none

- threshold: none, reason: the route mutates only the never-yet-born, consumer-less bastion, and its
gate refuses any plan that touches another address or another physical server, so no user data or
user-facing surface is within its reach in this PR.

## Observability

```yaml
liveness_signal:
  what: "the run itself: the dispatch summary (gated plan, pinned id, outcome pair) and boot-verify's strict Sentry boot-trail verdict for host_name=soleur-bastion; no standing heartbeat (deferred to #13113)"
  cadence: "per dispatch"
  alert_target: "GitHub run summary and ::error:: annotations; a not-ready replacement is commented on #9421 by bastion-boot-verify.sh (R4)"
  configured_in: ".github/workflows/bastion-host-replace.yml (job bastion_host_replace) and scripts/lib/bastion-boot-verify.sh"
error_reporting:
  destination: "GitHub Actions run log plus the #9421 issue comment; the host reports fresh_boot_ready or fresh_boot_not_ready_<stage> to Sentry web-platform via the SENTRY_DSN baked at birth"
  fail_loud: "::error:: lines naming the refusing gate arm (bastion_host_replace_gate: ABORT ...), the stock-preflight ABORT, and the TOCTOU mismatch, each with a non-zero job exit"
failure_modes:
  - mode: "the gate refuses (id mismatch, API count not 0 or 1, key or firewall touched, out-of-scope change)"
    detection: "the gate's ABORT line with its counter vector, in the plan step's log"
    alert_route: "the run's ::error:: annotation; nothing was destroyed"
  - mode: "stock miss for cx23 before the destroy"
    detection: "stock_preflight_gate plus stock_abort_closing bastion-host-replace"
    alert_route: "the run's ::error:: annotation; nothing was destroyed"
  - mode: "the live server changed between plan and apply"
    detection: "the TOCTOU re-pin step diffs the API document against the saved one"
    alert_route: "the run's ::error:: annotation; nothing was applied"
  - mode: "the destroy landed and the create failed"
    detection: "the apply step's failure plus stock_recovery_report --probe-state naming absent or tainted"
    alert_route: "the run's ::error:: text names the recovery dispatch (none, or the new id)"
  - mode: "the replacement booted not-ready"
    detection: "bastion_boot_verify strict verdict from the Sentry boot trail"
    alert_route: "workflow run log ::error::bastion-boot-verify: soleur-bastion is NOT ready (layer 6), plus power-off (disk kept), the #9421 comment and the summary next-dispatch line"
  - mode: "the Hetzner server read fails (step 6, the TOCTOU re-read, or the post-failure read)"
    detection: "_bbv_servers_doc returns non-zero; the step prints http=<code> and .error.code only"
    alert_route: "workflow run log ::error:: (layer 6); nothing is planned or applied, and the summary prints next dispatch: unread"
  - mode: "boot-verify's comment on #9421 fails"
    detection: "comment_result=failed recorded by bastion_boot_verify"
    alert_route: "workflow run log ::error:: on the replace label (layer 6), and the summary says the comment did not post"
  - mode: "the apply failed before the old server was deleted"
    detection: "boot-verify's old-id argument: the API still shows only the pinned old id"
    alert_route: "the run's ::error:: line; the old bastion is never powered off"
logs:
  where: "GitHub Actions run logs of apply-web-platform-infra.yml (the caller run contains the called job); Sentry web-platform events tagged host_name=soleur-bastion"
  retention: "GitHub Actions default log retention (90 days); Sentry per plan retention"
discoverability_test:
  command: "grep -c -e '^bastion_host_replace_gate() {' tests/scripts/lib/bastion-host-replace-gate.sh"
  expected_output: "1"
```

## Downtime & Cutover

- **Operation.** `terraform apply` of a `-replace='hcloud_server.bastion'` plan. Hetzner destroys
  `soleur-bastion` and then creates it. The bastion has no `create_before_destroy`, so its fixed name
  and its fixed private IP (10.0.1.70) are freed first.
- **Surface affected.** The management-plane bastion only. In step 2 it serves nothing: sshd is
  masked, nothing dials it, and no user request crosses it. No user-facing or serving surface goes
  offline.
- **Zero-downtime path evaluated:**
  - *Blue-green* (birth a second bastion, cut over, retire the old one) is not available here. The
    name `soleur-bastion` and the IP 10.0.1.70 are literals in `bastion.tf`, and the bastion's own gate
    and boot-verify both refuse two servers with that name.
  - *Rolling* has one member.
  - *A state-only re-address* does not deliver a new boot.

  So the residual downtime is the bastion's own boot: about 2 minutes for create plus the
  cloud-init settle, bounded by the job's `timeout-minutes`.
- **Justification and sign-off.** The downtime is accepted because no consumer exists until step 3
  (#12867), which this route blocks. The window is the job's run. The owner's typed go on the real
  dispatch is the sign-off.
- **Revisit.** Step 3 (#12867) gives the bastion consumers and must re-evaluate this. That means
  either a blue-green design with a second name and IP, or a drain-then-replace with a bounded window.
  The ADR-327 addendum records that obligation.

## Network-Outage Deep-Dive

This is not a connectivity fix. The words "firewall" and "timeout" appear here only as resource
and step names. The layers are:

- **L3 firewall allow-list.** CI never connects to the bastion, so no SSH and no allow-list are
  involved. The bastion's Hetzner firewall stays zero-rule, and the gate enforces it.
- **L3 DNS/routing.** Only `api.hetzner.cloud` is reached, over HTTPS from a GitHub-hosted runner.
  `stock-preflight-gate.sh` and the birth route's power-off already use the same path.
- **L7 TLS.** curl with default certificate verification. The Encryption Posture `in_transit` row
  covers it.
- **L7 application.** A non-2xx response or a non-JSON body from the API fails the read step closed
  before any plan.

There is no `terraform_data` SSH provisioner in the `-target` set, so the resource-shape trigger does
not apply.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file changes. The route drives the existing `apps/web-platform/infra/bastion.tf`
resources through `-target` and `-replace`. It reads the existing outputs
`bastion_ssh_host_key_fingerprint` and `bastion_private_ip`. The sensitive inputs are unchanged:
`TF_VAR_*` comes from Doppler `prd_terraform` through `doppler run --name-transformer tf-var`, and
`HCLOUD_TOKEN` comes from the Tier-B loader.

### Apply path

(b) `terraform apply` of a plan made with `-replace='hcloud_server.bastion'`, scoped to the five
bastion addresses. The bastion has no persistent volume and holds no state; cloud-init rebuilds it
whole. The downtime is the bastion's own boot. It has no consumer in this step, so the blast radius
is zero users. The recovery arm is (a), a create on empty state.

### Host fan-out

Not applicable. No `terraform_data` SSH provisioner is added or edited, and CI never connects to
the bastion.

### Distinctness / drift safeguards

- The bastion addresses stay in `OPERATOR_APPLIED_EXCLUSIONS`, so the per-merge apply never reaches
  them. The new parity block asserts that the replace job's `-target` multiset equals
  `bastion-resources.txt`.
- `ignore_changes = [ssh_keys]` on the server is unchanged.
- State is the R2 backend with no lock. Serialization is the caller's workflow-level
  `terraform-apply-web-platform-host` group, and the callee declares none.
- The plan file holds the host key's private half (ADR-327 residual). It stays runner-local and is
  never uploaded (G6e in the tier census).

### Vendor-tier reality check

Hetzner `cx23` stock is checked by `stock_preflight_gate` before the destroy. The cost is unchanged:
a replace does not add a second recurring server, because the old one is destroyed first.

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_server.bastion local disk (no attached volume)"
    mechanism: "plaintext-exception"
    evidence: "apps/web-platform/infra/bastion.tf declares no hcloud_volume; the host keeps no data beyond cloud-init output"
    defends_against: "nothing at rest; the disk carries no user data, only the OS, the egress rules and the host key"
    does_not_defend: "a Hetzner-side read of the disk or of the metadata endpoint exposes the bastion host key's private half (ADR-327 residual); nor the replace run's runner-local plan JSON, which holds the key in clear text until the always() delete step removes it"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: the bastion is not born"
in_transit:
  - connection: "GitHub Actions runner -> api.hetzner.cloud (server lookup by name and power-off)"
    enforced_at: ".github/workflows/bastion-host-replace.yml step 'Read the live bastion from Hetzner' (curl to an https:// URL with no -k or --insecure)"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a leaked HCLOUD_TOKEN, which authorizes the same reads and power actions from anywhere"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "the bastion's disk is unencrypted by design: it holds no user data, and its only secret, the host key, already sits in Terraform state and the metadata endpoint, which disk encryption would not cover"
  tracking_issue: "#12866"
  reevaluate_when: "step 3 (#12867) puts any credential other than the host key on the bastion"
  expires_on: "2027-02-25"
```

## Task Design

```yaml
tasks:
  - task: "bastion-host-replace (reusable workflow bastion-host-replace.yml, job bastion_host_replace)"
    trigger: "workflow_call from the bastion_host_replace caller job, which runs only on a workflow_dispatch of apply-web-platform-infra.yml with apply_target=bastion-host-replace"
    services: "reads Doppler prd_terraform, the R2 Terraform state, the Hetzner API and the Sentry boot trail; writes the R2 Terraform state, the Hetzner server, and a comment on #9421"
    next: "nothing; step 3 (#12867), the heartbeat (#13113), key rotation (#13116) and lost-state recovery (#13117) are separate changes"
    human_reentry: "the web-platform-infra-apply environment's required reviewer approves or rejects the job before it starts; plan_only=true stops before any destroy; cancelling the run triggers the cancel power-off step"
    dedupe: "the three-way id pin: a second dispatch after a successful replace carries a stale expected_bastion_server_id, which no longer matches the API or before.id, so the gate refuses it; the TOCTOU re-pin refuses a change between plan and apply"
    source_dedupe: "not a ticket source"
```

## Guard Contract

### Guard 1 — bastion replace gate

**Property.** An apply on this route runs only on a plan that matches one of two arms:

- **Replace arm.** The plan destroys exactly the one live `soleur-bastion` whose id the dispatch, the
  Hetzner API and the plan's `before.id` all agree on, compared as strings. It recreates that server,
  creates its NIC at 10.0.1.70, and updates its zero-rule firewall attachment so it binds by id to the
  new server.
- **Recovery arm (pin `none`).** The plan creates the server only when neither state nor the API holds
  any `soleur-bastion`.

In both arms the host key and the firewall are exactly no-op, and nothing outside
`bastion-resources.txt` changes.

**Assembly.** The chokepoint is `bastion_host_replace_gate` in
`tests/scripts/lib/bastion-host-replace-gate.sh`, plus the shared checks it calls in
`tests/scripts/lib/bastion-gate-common.sh` (R3). The gate is called from one place only,
`bastion-host-replace.yml`'s plan step. Its inputs are:

- the plan JSON's `resource_changes[]`, `prior_state` and `configuration.root_module.resources[]`;
- the pin argument;
- the API document's `.servers[]`.

The allow-set is `bastion-resources.txt`, read at call time with no override. One member of the
assembly sits outside the function: the apply step must consume the same `tfplan` that the gate
graded. Guard 2 pins that.

**Mutation matrix.** The fixtures are synthesized, and each row is one `jq` edit of the canonical
replace plan, the recovery plan or the API document. Each row must drive the gate RED unless it is
marked PASS. The fixtures use a string `before.id` and a numeric API id.

| # | Mutation | Expected |
|---|---|---|
| 1 | canonical replace plan with the attachment's `after.server_ids` `[null]` and `after_unknown.server_ids` `[true]`, and API 1 server (id = pin, role=bastion) | PASS |
| 1b | row 1 with `after_unknown.server_ids` as `true` and `after.server_ids` omitted (wholly unknown; tolerated by the word-for-word common check) | PASS |
| 1c | row 1 with `after_unknown.server_ids` `[true]` and `after.server_ids` omitted (inconsistent shape) | RED |
| 2 | canonical recovery plan, pin `none`, API 0 servers | PASS |
| 3 | canonical replace plan with `resource_changes[]` in reverse order (a permitted variant) | PASS |
| 3a | replace arm with the NIC `["create"]` at 10.0.1.70, the partial-replace re-dispatch (H3) | PASS |
| 3b | replace arm with the attachment `["no-op"]` (still bound to the deleted id) | RED |
| 4 | pin ≠ API id | RED (identity mismatch; the line prints pin, API ids, `before.id`) |
| 5 | pin = API id ≠ `before.id` | RED |
| 6 | API 2 servers | RED (never guess) |
| 7 | API 1 server with `labels.role` ≠ bastion | RED |
| 8 | API document with no `.servers` key, or `.servers` not an array | RED (unreadable is not zero) |
| 9 | pin `none` + API 1 server | RED (#13117 is the lost-state case) |
| 10 | pin `none` + `prior_state` holds `hcloud_server.bastion` | RED |
| 11 | pin = id + server `["create"]` only (before null) | RED |
| 12 | `tls_private_key.bastion_host_ssh` `["update"]`; then `["delete","create"]` | RED, each (#13116) |
| 13 | `hcloud_firewall.bastion` `["update"]` (a rule added) | RED |
| 14 | NIC with `after.ip` ≠ 10.0.1.70, or unknown | RED |
| 15 | attachment binding references another server (configuration references) | RED |
| 16 | attachment `label_selectors` non-empty, or firewall `apply_to` non-empty | RED |
| 17 | `hcloud_server.web["web-1"]` `["delete","create"]` added | RED |
| 18 | a compliant extra no-op entry, then a SECOND, out-of-scope change after it | RED |
| 19 | any address `["forget"]` | RED |
| 20 | a `bastion-resources.txt` copy missing one graded address (common loader, sourced from a scratch dir) | RED |
| 21 | the replacement's `after.server_type` ≠ cx23, `after.name` ≠ soleur-bastion, or `after.labels.role` ≠ bastion | RED, each |
| 22 | inline `firewall_ids` on the server | RED |
| 23 | pin argument malformed (`0`, `12a`, empty) | RED |
| 24 | a plan with no `resource_changes` (preamble) | RED |

**Harness rows.**

- **H1.** Replace the gate with `return 0`. Every RED row must flip.
- **H2.** Replace the gate with `return 1`. Every PASS row must flip. This shows the must-PASS rows can
  see a gate that rejects everything.
- **H3.** `cases == passes + fails`, and `cases` equals the row count derived from the suite's own row
  table. Both are reported with `printf` and `exit 1`, never through `fail()`.
- **H4.** The instrument self-test.

Rows 3 and 3a are the must-PASS inputs that differ from the canonical plan in a way the contract
permits. R3 adds one more check on top of the matrix: the unchanged birth suite must pass against the
extracted common checks.

**Anchor.** The owner reads the `plan_only` summary before giving the typed go for the real replace.
The summary shows the commit, the pin, the live API ids and the planned (action, address) list. The
pin value comes from the Hetzner API, which does not depend on the state the gate guards.

### Guard 2 — replace route wiring

**Property.** The replace job applies only the plan file that the gate passed. It runs only after the
interlock, the gate, the stock preflight and the TOCTOU re-pin, in that order. Every step that mutates
or powers off is skipped on `plan_only`. The job runs in the reviewer-gated environment and inside the
caller's concurrency group.

**Assembly.** Two job blocks are the chokepoints: the `bastion_host_replace` caller in
`apply-web-platform-infra.yml`, and the `bastion_host_replace` job in `bastion-host-replace.yml`. The
caller's `secrets:`, the callee's env and `-target` lines, the exclusions, the absent `concurrency:`
and `secrets: inherit` are all covered by the existing bastion describe block, now run over both
routes. The new rows read each step's `if:` and `run:` text and its position, and the callee's
parsed `on` keys and `environment:`.

**Mutation matrix.** The rows live in the `terraform-target-parity.test.ts` bastion block, and the F5
row lives in `test-infra-privileged-tier-census.sh`.

| # | Mutation | Expected |
|---|---|---|
| 1 | `terraform apply` consumes anything other than `tfplan` | RED |
| 2 | the stock-preflight call moves after the apply step | RED |
| 3 | the TOCTOU re-pin step moves after the apply | RED |
| 4 | the `-replace='hcloud_server.bastion'` line is commented out, or moves out of the replace-arm branch | RED (F4, R2) |
| 5 | the cancel power-off, the boot-verify or the TOCTOU step loses `inputs.plan_only != true` | RED, each (the census cannot see a Hetzner `curl POST`) |
| 6 | the apply step loses `inputs.plan_only != true` | RED (F5 census) |
| 7 | the summary step loses `if: always()` | RED |
| 8 | the callee's parsed `on` keys are anything other than `["workflow_call"]` (including the inline `on: [workflow_call, push]` form) | RED |
| 9 | the confirm literal becomes `BIRTH-bastion` | RED (the tokens must stay distinct) |
| 10 | the boot-verify call drops the old-id fourth argument | RED |
| 11 | the existing block's caller tests, run over both routes: `secrets: inherit` on the replace caller, or one declared secret not passed | RED |

**Harness rows.**

- Each row first asserts that the callee job it extracted is non-empty and that every named step it
  reads is present. A renamed job or step therefore reds and never passes vacuously.
- One must-PASS row reorders two independent steps (the ephemeral-key step and the required-secrets
  step), and the block stays green.

**Anchor.** None stored. The guard compares live files only.

### Guard 3 — heartbeat parity ignores comments

**Property.** A `dedicated-host-boot` heartbeat's replace path counts only when the
`-replace='hcloud_server.<host>'` literal sits on a non-comment line.

**Assembly.** `hasReplaceLine` in `heartbeat-reprovision-parity.test.ts`. It now runs on the
comment-stripped text of the apply workflow, and stays pure over its input. Following `uses:` into a
callee is #13113's work (R2).

**Mutation matrix.** The fixtures are synthesized workflow texts.

| # | Mutation | Expected |
|---|---|---|
| 1 | the literal on a real line | PASS |
| 2 | the literal only in a `#` comment | RED |
| 3 | the literal inside a quoted string after a `#` that is itself inside quotes (`"a#b" -replace='hcloud_server.x'`) | PASS (the quote-aware strip keeps it) |
| 4 | the existing registry and inngest rows against the real file | PASS, unchanged |

**Harness rows.**

- The existing `paused_boot_prd` and `newhost_boot_prd` fixtures still red.
- An empty workflow text matches nothing.

**Anchor.** None stored.

`plugins/soleur/test/workflow-file-size.test.ts` is the existing guard for the byte ceiling. AC1 and
AC2 hold it to this PR's numbers, and the PR adds no new guard there.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-327** with an addendum dated 2026-11-28 (#12879, step 2b). It covers:

- the replace route and its three-way id pin;
- the recovery arm;
- the separate reusable callee, which amends 2a's "2b's replace job joins it there" with the
  `calledApplyingSteps` reason;
- the heartbeat moved to #13113, which amends "2b adds the replace route and heartbeat";
- `Ref #12879` until the post-birth `plan_only` proof;
- the shared readiness library (F1).

- the two refused cases (#13116, #13117);
- the shared libraries (F1, R3);
- the pre-apply id set that boot-verify honours on both routes;
- the reviewer gate, which is the owner's own approval;
- that step 3 (#12867) must revisit the replace downtime and draining its consumer.

Amend **ADR-231** with an addendum dated 2026-11-28 (Q4b). It covers:

- the bastion routes as #8385-shape callees, the first slice of the split;
- this PR's relocation as the minimum the thin caller needs, not a substitute for the split;
- the #8385 counter, which has tripped (489,485 ≥ 485,000);
- the next PR that adds caller bytes to `apply-web-platform-infra.yml`, which must take the split
  with no further relocation round.

Both are amendments to existing ADRs, so no new ADR is created.

### C4 views

All three model files were read. `model.c4` already models the `bastion` container, the external
`github` actor edge `github -> bastion` (Terraform via Hetzner API), and `bastion -> sentry`. The
route adds no new actor, external system, container or access relationship. CI reaching the bastion
through the Hetzner API is already the `github -> bastion` edge. Edits:

- the bastion container's description ("Its replace route and heartbeat are #12879" becomes the
  replace route as built, with the heartbeat at #13113);
- the `github -> bastion` description ("Replace route pending #12879" becomes the
  `bastion-host-replace` dispatch);
- the `bastion -> sentry` heartbeat clause (re-pointed to #13113).

`views.c4` and `spec.c4` need no change; the bastion is already included in its view. Run
`c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

The addendum describes the route as built. Its "bounds that risk" claim becomes true only once a
bastion exists, and the addendum says so.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings Q1-Q7 and F1-F5 (2026-11-28) are recorded above and in
`decision-challenges.md`. The main risks are the byte budget (Q4), a gate that cannot see a
mis-mapped physical id (Q3), and a parity test that a comment could satisfy (Q1, F4). Each one has a
guard with a mutation matrix.

No Product, Marketing, Legal, Finance, Sales, Support or Operations implications. There is no user
surface. The cost is unchanged, because a replace destroys before it creates. No new vendor or data
processing is added.

## Operator Holds

- **No production dispatch from this PR.** That includes the issue's `plan_only` run against the real
  bastion. It needs a born bastion, and the owner's typed go naming the exact command.
- **Operator item (priority/schedule):** schedule #8385 (split the apply workflow) before the next
  route that adds to it. Its own trigger has fired (489,485 ≥ 485,000). This PR is its first slice (Q4b).
- The PR body says `Ref #12879`, `Ref #9421` and `Ref #12008`. It never says `Closes` for #9421 or #12008.
- **What the merge triggers.** This was derived from every workflow whose `on.push.paths` matches the
  planned files (measured 2026-11-28):
  - `apply-web-platform-infra.yml` runs its per-merge apply. Its own file and `apps/web-platform/infra/**`
    are both in its paths. The bastion addresses are in `OPERATOR_APPLIED_EXCLUSIONS`, so that apply never
    reaches the bastion. Every push apply since 2026-11-25 has failed at "Load infra credentials
    (tiered)" before any plan (run 45824746387).
  - `web-platform-release.yml` runs because of `apps/web-platform/**`. The infra census test files
    match it. Production release is blocked at the zot mirror (#12937), so this run is expected to fail
    there as the others have.
  - `infra-validation.yml` and `validate-vector-config.yml` run validation only (`apps/web-platform/infra/*.sh`).
  - `version-bump-and-release.yml` runs because of `plugins/soleur/**`.
  - `registry-host-replace-dispatch.yml`, `apply-deploy-pipeline-fix.yml` and `mint-inngest-bootstrap-tag.yml`
    do not match any planned file. The work phase re-runs this derivation on the final diff.

  Before merge, the work phase reads the latest failed push-apply and release runs' `::error::` lines,
  and the PR body states what each triggered workflow will do.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Add the `bastion-host-replace` route: a new `apply_target` value and job in `.github/workflows/apply-web-platform-infra.yml`" [issue #12879] | Phase 3.2; the caller job plus the callee (Q2) | mapped |
| 2 | "with a sourced gate `tests/scripts/lib/bastion-host-replace-gate.sh`" [issue #12879] | Phase 2.1; Guard 1 | mapped |
| 3 | "and its test registered in `scripts/test-all.sh`" [issue #12879] | Phase 1.1; Phase 4.2 | mapped |
| 4 | "is pinned to the live server's physical id" [issue #12879] | Q3; Guard 1 rows 4-5 | mapped |
| 5 | "allows only a delete-and-create of `hcloud_server.bastion` and its attachments" [issue #12879] | Guard 1 rows 1, 3, 11, 17-19 | mapped |
| 6 | "refuses any action on `tls_private_key.bastion_host_ssh`" [issue #12879] | Guard 1 row 12 | mapped |
| 7 | "accepts a create-only recovery arm only when state has no bastion server and the live Hetzner API shows no server named `soleur-bastion`" [issue #12879] | Guard 1 rows 2, 9, 10 | mapped |
| 8 | "runs `stock-preflight-gate.sh` before the destroy and uses the shared `terraform-apply-web-platform-host` concurrency group" [issue #12879] | Proposed Solution step 9; Guard 2 rows 2, 6 | mapped |
| 9 | "The route exists, with its gate tested on synthesized plans." [issue #12879, done when] | Phase 1-4 | mapped |
| 10 | "A `plan_only` run against the real bastion passes the gate." [issue #12879, done when] | Phase 6 Operator Hold | descoped — justification: the bastion is not born; the dispatch needs the owner's typed go (brief) |
| 11 | "This session covers #12879 ONLY (one PR)." [brief] | Single PR; heartbeat split to #13113 (Q1) | mapped |
| 12 | "plan for a rebase if it lands first, and mind GitHub's workflow-file byte limit" [brief] | Phase 0; Q4; Guard 3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `bastion-host-replace.yml` callee | "new apply_target value and job" | asked |
| `expected_bastion_server_id` input | "pinned to the live server's physical id" | asked |
| Comment relocations | "mind GitHub's workflow-file byte limit" | asked |
| `scripts/lib/bastion-birth-readiness.sh` (F1) | — | inferred — justification: the replace job needs the same readiness check, and the CTO ruled a library over a copy |
| `hasReplaceLine` strips comments (Q1/R2) | — | inferred — justification: a commented literal satisfies the parity test today; the CTO ruled the fix into this PR and the `uses:` follow into #13113 |
| `bastion-gate-common.sh` (R3) | — | inferred — justification: the replace gate needs the birth gate's create-side checks; the CTO ruled a shared helper over a copy |
| Old-id argument to boot-verify | — | inferred — justification: plan review (Kieran) showed a failed apply before the destroy would otherwise power off the healthy old bastion |
| Boot-verify text, runbook, ADR-327, `model.c4` | — | inferred — justification: each states that #12879's route does not exist yet, and would lie after merge (`wg-architecture-decision-is-a-plan-deliverable`) |
| TOCTOU re-pin | "pinned to the live server's physical id" | asked |

### Split Assessment

- Subsystems touched: 4. They are `.github/workflows/`, `tests/scripts/` plus `scripts/`,
  `plugins/soleur/test/`, and `knowledge-base/engineering/`. The edits under
  `apps/web-platform/infra/` are census test files only.
- Planned files: 5 to create and about 22 to edit, 27 in total. Estimated changed lines: about 1,500.
  Most of them are the gate (~300), its matrix (~450), the callee (~380) and the relocated prose
  (moved, not written).
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines.
- Recommendation: a single PR. The thresholds trip on file and line count, and most of the edited files
  are one-line census entries, but the brief fixes this session at
  one PR. The heartbeat, the largest separable unit, is already split out (#13113). A further split
  would land the gate without the route that sources it.

## Acceptance Criteria

### Pre-merge

- [ ] AC1. After the final rebase on `origin/main`, `wc -c .github/workflows/apply-web-platform-infra.yml`
  is at most 488,000, and `bun test plugins/soleur/test/workflow-file-size.test.ts` passes.
- [ ] AC2. The relocation is its own commit, and the parsed YAML on both sides of it is exactly equal:
  `python3 -c 'import yaml,sys; print(yaml.safe_load(open(sys.argv[1]))==yaml.safe_load(open(sys.argv[2])))' <before> <after>`
  prints `True` for the file at that commit and at its parent. Every relocated block appears word for
  word in the job-rationale runbook.
- [ ] AC3. The R3 extraction is its own commit. At that commit `bash tests/scripts/test-bastion-host-birth-gate.sh`
  passes, and `git diff <parent> -- tests/scripts/test-bastion-host-birth-gate.sh` changes no
  assertion line.
- [ ] AC4. `bash tests/scripts/test-bastion-host-replace-gate.sh` passes. Its case count equals its row
  table, and the H1 and H2 flips are reported.
- [ ] AC5. `bash scripts/test-all.sh --enumerate scripts | grep -c bastion-host-replace-gate` prints `1`.
- [ ] AC6. These all pass:
  - `terraform-target-parity`
  - `stock-preflight-coverage`
  - `heartbeat-reprovision-parity`
  - `test-infra-privileged-tier-census.sh`
  - `soleur-host-bootstrap-observability.test.sh`
  - `kernel-currency.test.sh`
  - `bastion-runcmd-rehearsal.test.sh`, whose static rows run locally, while its boots run in its
    dedicated job
  - `test-argv-bearer-sweep.sh`
  - `test-bastion-boot-verify.sh`, including its readiness and old-id rows
- [ ] AC7. `git grep -n "not yet available" scripts/lib/bastion-boot-verify.sh` returns nothing.
  `grep -c -e 'gh issue comment 9421' scripts/lib/bastion-boot-verify.sh` prints `1`.
- [ ] AC8. `actionlint` is clean on `bastion-host-replace.yml` and `bastion-host-create.yml`, and
  `shellcheck` is clean on the new libraries and the gate.
- [ ] AC9. `python3 scripts/lint-infra-no-human-steps.py --changed` exits 0.
- [ ] AC10. The callee's parsed `on` keys are exactly `["workflow_call"]` (Guard 2 row 8), and
  `grep -c "uses: ./.github/workflows/bastion-host-replace.yml" .github/workflows/apply-web-platform-infra.yml`
  prints `1`.
- [ ] AC11. The ADR-327 addendum, `bastion-host.md` and `model.c4` no longer describe the replace route
  as pending. `bastion-host.md` names #13116 and #13117 for the two refused cases, and the C4 suites
  pass.
- [ ] AC11b. The ADR-231 addendum (Q4b) exists and states the four points.
- [ ] AC11c. `test-bastion-host-replace-gate.sh` runs a fixture whose key fields hold
  `SYNTHETIC-KEY-MARKER`, and that string appears in none of the gate output it captures.
  `test-bastion-boot-verify.sh` shows that a pre-apply id is never powered off, on the cancel path
  and on the failed-apply path.
- [ ] AC12. The PR body says `Ref #12879`, `Ref #9421` and `Ref #12008`. It carries the done-when
  checklist with item 2 unchecked as an Operator Hold, and it lists each workflow the merge triggers
  and what that workflow will do.

### Post-merge (Operator Holds, each needs the owner's typed go)

- [ ] AC13. After a bastion birth, a `plan_only` dispatch of `bastion-host-replace` with the born id
  passes the gate. Its summary lists the delete and create of the server and the NIC, and the
  attachment update. #12879 closes on that evidence.

## Test Scenarios

- Given the canonical replace plan and an API document holding one `soleur-bastion` with
  `role=bastion` and the pinned id, the gate passes and prints its counter vector.
- Given pin `none`, an empty API document and a plan with no server in `prior_state`, the recovery arm
  passes.
- Given the API returns the server but the pin is a different id, the gate aborts with "identity
  mismatch" and nothing is destroyed.
- Given an API document with `.servers` missing, the gate aborts. An unreadable answer is never read as
  zero servers.
- Given a plan that also replaces `hcloud_server.web["web-1"]`, the gate aborts on out-of-scope.
- Given `boot-verify` with label `bastion-host-replace` and a not-ready verdict, the recovery line names
  another replace dispatch and never says "not yet available".
- Given the caller's `-replace=` literal only in a comment, `heartbeat-reprovision-parity` reds.
- Given an apply that failed before the old server was deleted, boot-verify (old id passed) finds only
  the old id in the API and powers nothing off.
- Given a re-dispatch after a partial replace (new server in state, NIC absent), the replace arm passes
  with the NIC `["create"]` pinned at 10.0.1.70.

## Dependencies & Risks

- **#12958** may land first. Rebase; its hunks do not overlap the inputs block or the insertion point.
  Re-measure AC1 after every rebase, because a sibling merge can take the file over the gate
  (learning 2026-09-19).
- **workflow_dispatch input count.** The new input is the 10th. Check GitHub's documented limit in Phase 3.2.
- **H1 is unproven against a real plan** until a bastion exists. A wrong guess fails closed: the gate
  refuses and nothing is destroyed.
- **F1 and R3 edit 2a's birth body and birth gate.** The interlock step keeps its name, so the suites
  anchored on it keep binding, except `bastion-runcmd-rehearsal.test.sh`, whose `for lit in` anchor moves
  to the library. R3's extraction must leave the birth suite's assertions untouched (AC3), or it is
  abandoned for a copy.
- **The two refused cases are real gaps until #13116 and #13117 land.** The bastion has no consumer
  before step 3, so neither case can reach a user. Both block #12867 in practice.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- `hasReplaceLine` reads raw text. A comment holding the `-replace=` literal would satisfy it. Strip
  comments (Guard 3), and pin the real callee line (F4, Guard 2 row 4).
- An API read that fails must never become the recovery arm's "zero servers". Fail the step on curl
  or HTTP errors, and have the gate refuse a document with no `.servers` array (Guard 1 row 8).
- The `apply_target` options regex in `terraform-target-parity.test.ts` needs the option list to stay
  followed by a blank line and `concurrency:`. Insert the option inside the list, not at its end.
- The `run_suite` line goes inside the `want_scripts` block, never at the file's end (learning 2026-11-09).
