---
issue: 5515
type: fix
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix(infra): order the webhook push after the handler bridge so a new FILE_MAP file lands in ONE apply (#5515)

🐛 **Bug** · `apps/web-platform/infra/server.tf` · infra resource-graph ordering

## Enhancement Summary

**Deepened on:** 2026-06-18
**Passes:** precedent-diff (Phase 4.4), network-outage deep-dive (Phase 4.5), verify-the-negative (Phase 4.45), 3 review agents (architecture-strategist, SpecFlow, plus the precedent/verify Explore agents). Halt gates 4.6/4.7/4.8/4.9 all PASS.

### Verification results (all confirmed against the live worktree)

- **`depends_on` precedent**: the only existing edge is `deploy_pipeline_fix → apparmor_bwrap_profile` (`server.tf:578`, single-element). The proposed two-element form is the idiomatic extension; matches repo HCL style.
- **No cycle**: `infra_config_handler_bootstrap` has NO `depends_on` of its own → no path back → DAG preserved. AC3 `terraform validate` is the mechanical guard.
- **Co-targeting invariant verified**: both resources are co-`-target`ed in `apply-deploy-pipeline-fix.yml`'s single `terraform apply` (plan + apply steps). The edge is inert if either target drops → Test 2 (AC7) guards this.
- **`-target` does not order**: confirmed Terraform property — `-target` selects nodes; only the graph edge orders them. Reordering `-target=` flags is NOT a valid alternative fix.
- **Old comment is "partially stale"**: architecture review confirms the `install_rejected` self-heal rationale covers helper/sudoers (NOT in FILE_MAP) but NOT webhook-written FILE_MAP files (which fail via the `#4804 missing_env` arm). The FILE_MAP class post-dates the #4829 comment. Fix corrects a decision that predates the failure class — not a reversal.
- **`inngest-inventory.sh` is the real triggering file** (#5509, `op=inventory`), registered across all 5 delivery surfaces — the bug is live, not hypothetical.
- **Restart serialization is a secondary benefit**: the edge orders the bridge's existing Terraform-managed webhook-listener restart (`server.tf:529`) before the push's `local-exec`, closing a latent restart-during-push connection-reset window.

### Deepen-pass corrections folded in

1. **[Premise]** Corrected the false "`inngest-inventory.sh` doesn't exist" claim (an earlier `ls` ran from the wrong cwd) → the file exists, is the concrete #5509 instance, registered everywhere.
2. **[SpecFlow P0-A]** Added Test 2 / AC7 — the co-targeting invariant (the load-bearing assertion the HCL-array test alone misses).
3. **[SpecFlow P1-A]** Expanded Files-to-Edit to audit BOTH workflows' concurrency-group comments for the now-two-element `depends_on`.
4. **[SpecFlow P1-B]** AC3 durability note: the standing cycle guard is the prod `terraform plan` step, not the one-time PR-author validate.
5. **[SpecFlow P1-C]** Disambiguated the test's extraction (bound the block, fresh `depends_on` regex — NOT the `triggers_replace` join extractor).
6. **[SpecFlow P2-A / arch P2-1]** Documented the restart-serialization benefit AND the new restart-on-unrelated-trigger coupling in the comment-rewrite spec.
7. **[arch P2-2]** Added optional Test 3 — cross-workflow blast-radius guard.

## Overview

`terraform_data.deploy_pipeline_fix` (the HTTPS webhook push of the 11 managed deploy-config files) and `terraform_data.infra_config_handler_bootstrap` (the root-SSH bridge that delivers the webhook handler `infra-config-apply.sh` + the rendered `hooks.json` to the running host) have **no ordering edge** in the Terraform graph. The CI workflow `apply-deploy-pipeline-fix.yml` lists BOTH as explicit `-target=`s in a single `terraform apply` (lines 238-239), but `-target` does **not** impose ordering — Terraform orders only by the declared dependency graph, and with no `depends_on` between them the two `terraform_data` resources apply in graph-parallel / arbitrary order.

On a merge that BOTH replaces the handler (adds a new entry to `infra-config-apply.sh`'s `FILE_MAP` + a new env key in `hooks.json`) AND fires the webhook push (a hashed trigger file changed), the push can run against the host's **stale** handler+`hooks.json`. The new file's env var is unset on the stale `hooks.json`, so the handler's per-file `missing_env` arm (`infra-config-apply.sh:105-112`) records a failure for it, the file does not land, and the op that reads it (e.g. a hypothetical `op=inventory`) 500s. The next unrelated apply finally delivers it — the file lands **one apply late**.

**Durable fix:** add `depends_on = [terraform_data.infra_config_handler_bootstrap]` to `terraform_data.deploy_pipeline_fix` so Terraform always recreates the bridge (current handler + current `hooks.json`) before the webhook push runs. A newly-added managed FILE_MAP file then lands in **one** apply. Rewrite the now-stale `#4827/#4829` "deliberately NO depends_on" comment, and add a regression test that asserts the edge exists.

This is a single-line HCL change plus a comment rewrite plus a guard test. No new infrastructure, no migration, no new secret, no new vendor, no runtime code.

## Premise Validation

- **Issue #5515**: OPEN, not closed by any merged PR. Premise holds — the bug is unfixed. (`gh issue view 5515`)
- **Cited mechanism vs. the existing code's deliberate decision (the key check):** `server.tf:566-577` documents a **deliberate `depends_on` omission** citing #4827/#4829, with the rationale "ordering … is handled by the handler's per-file `install_rejected` self-heal." That rationale was authored for the **helper + sudoers** files (root-managed, NOT in FILE_MAP), whose missing-on-host failure mode is `install_rejected`. It does **NOT** cover a **new webhook-written FILE_MAP file**, whose failure mode is the `#4804` `missing_env` arm — and `missing_env` self-heals only once the host's `hooks.json` (which passes the new env key) AND handler FILE_MAP are current, **both of which are delivered by `infra_config_handler_bootstrap`**. So the comment is **partially stale**: correct for helper/sudoers ordering, silent on new-FILE_MAP-file ordering. The class of "webhook-written FILE_MAP file" only appeared with the #5492 inngest cutover scripts (`server.tf:615-624`, `FILE_MAP` entries `infra-config-apply.sh:41-44`), AFTER the #4829 comment was written. The fix correctly closes the gap the comment does not cover. **The fix is NOT a reversal of a still-valid decision — it is the correction of a decision that predates the failure class.**
- **`inngest-inventory.sh` (`op=inventory`)**: **EXISTS** and is a CONCRETE instance of the bug, not hypothetical. It was added in #5509 (commit `b8850c968`, "backup + full-inventory cutover ops") and is registered across ALL delivery surfaces: push payload (`push-infra-config.sh:55` `inngest_inventory_sh_b64`), handler FILE_MAP (`infra-config-apply.sh:45` `INNGEST_INVENTORY_SH_B64`), `deploy_pipeline_fix` triggers_replace (`server.tf:625`), ship gate `TRIGGER_FILES` + `DPF_REGEX` (`ship-deploy-pipeline-fix-gate.test.ts:52`, `SKILL.md:704-706`). It is the most recent webhook-written FILE_MAP file and the exact one whose `op=inventory` 500'd, demonstrating the bug live. The fix is general (the ordering edge), but `inngest-inventory.sh` is the real triggering case. (Verified in the worktree; an earlier `ls` from the wrong cwd gave a false negative — the file is present.)
- **ADR corpus**: no ADR governs the `deploy_pipeline_fix` ↔ `infra_config_handler_bootstrap` ordering decision; it lives only in the `server.tf` comment. ADR-030 (deploy substrate / inngest) and ADR-052 (egress firewall) mention adjacent topics but not this edge. → Architecture Decision gate: this is a documented-in-code micro-decision being corrected; see `## Architecture Decision` below.
- **`op=backup`**: confirmed out of scope — a workflow-level hcloud snapshot with no host hook; unaffected by FILE_MAP / handler ordering.
- **Already-merged context (not work targets)**: the deploy-trigger registration (#5492) and the pass-environment SSH bridge are correct. Confirmed: `inngest-*` scripts are registered across `server.tf` triggers_replace, `FILE_MAP`, push payload, and the ship gate `TRIGGER_FILES`.

## Research Reconciliation — Spec vs. Codebase

| Description claim | Codebase reality | Plan response |
|---|---|---|
| "no ordering dependency between the two resources" | Confirmed: `deploy_pipeline_fix` has only `depends_on = [terraform_data.apparmor_bwrap_profile]` (`server.tf:578`); no edge to the bridge. | Add the edge. |
| "depends_on … so the webhook push always runs after the handler is current" | Correct mechanism — `-target` does not order; only graph edges do. Both targets are in one `terraform apply`. | Single-line HCL add. |
| "a newly-added FILE_MAP file then lands in ONE apply" | Failure today is the `missing_env` arm (`infra-config-apply.sh:105-112`), not `install_rejected`. The `hooks.json` env-passing is the load-bearing input — also delivered by the bridge. | Comment rewrite must name `missing_env` + `hooks.json`, not just `install_rejected`. |
| "the webhook push runs against the host's OLD infra-config-apply.sh handler" | `infra-config-apply.sh` is delivered ONLY by the bridge (`server.tf:479-482`); it is NOT in the webhook FILE_MAP / push payload (cannot deliver itself, `infra-config-apply.sh:58-59`). | Confirms the bridge is the sole handler-delivery path → ordering edge is the correct fix. |
| existing comment: "depends_on … unnecessary … over-couples the graph" | The over-coupling concern is real for the **operator-local full apply** (a `deploy_pipeline_fix` change would now also recreate the bridge). But a handler edit ALREADY re-fires both via the dual-fire `triggers_replace` (`server.tf:396-400`), and the bridge is idempotent. | Weigh in `## Architecture Decision`; the bug cost outweighs the idempotent re-apply cost. Rewrite the comment to reflect the new decision. |

## User-Brand Impact

**If this lands broken, the user experiences:** a deploy-config op that reads a newly-added managed host script (e.g. an inngest-cutover op) returns HTTP 500 until a second, unrelated `terraform apply` runs — a transient post-merge ops failure visible only to the operator/CI, not to end users of the product.
**If this leaks, the user's data is exposed via:** N/A — no data path. The change reorders two infra-provisioning resources; it adds no new read/write of user data and touches no auth/PII surface.
**Brand-survival threshold:** aggregate pattern — a one-apply-late host script is an operator-facing reliability papercut (it self-heals on the next apply), not a single-user data/brand incident. The blast radius is the deploy pipeline, gated behind CI + the operator.

## Hypotheses

(The network-outage checklist gate fires because both target resources carry `connection { type = "ssh" }` + `provisioner` blocks. This is recorded for completeness; the root cause is **not** a connectivity outage but a resource-graph ordering defect, so the L3→L7 layers are opted out with artifacts below.)

1. **Root cause — Terraform resource-graph ordering (confirmed, not a network layer).** `deploy_pipeline_fix` and `infra_config_handler_bootstrap` have no `depends_on` edge (`server.tf:578` lists only `apparmor_bwrap_profile`); `-target` flags in `apply-deploy-pipeline-fix.yml:238-239` do not impose ordering. Verification artifact: `grep -n "depends_on" server.tf` shows the single edge; the apply step lists both targets in one command. **[verified via code read]**
2. **L3 firewall allowlist drift.** Opted out — not applicable. The symptom is a `missing_env` per-file failure inside a handler that DID receive the push (HTTP 202 returned), not a `connection reset`/handshake failure. The bridge's own SSH path reaches the host over the CF Tunnel (`server.tf:417-427`); a handshake failure there is a separate, documented diagnosis (admin-IP drift or stale CI key), not this bug. Artifact: the bug is "file written one apply late," i.e. the packet reached the service. **[opt-out with artifact]**
3. **L3 DNS / routing, L7 TLS/proxy, L7 app-layer.** Opted out for the same reason — the webhook push succeeds (the handler runs and writes the OTHER files); the failure is intra-handler `missing_env` accounting on the new file, which is upstream-ordering, not network. Artifact: `infra-config-apply.sh:81-89` `#4804` comment describes exactly this `missing_env` self-heal window. **[opt-out with artifact]**

## Architecture Decision (ADR/C4)

This corrects a micro-decision currently recorded only in a `server.tf` code comment (the #4827/#4829 "deliberately NO depends_on" block), not in an ADR. The reversal is small, fully localized to one resource graph edge, and a future engineer reading the existing ADRs + C4 would NOT be misled about the system after this ships (no ADR claims the absence). Therefore:

- **### ADR**: No new ADR and no ADR amendment required. The decision and its rationale are captured in (a) the rewritten in-code comment at `server.tf:566-577` and (b) the regression test's header comment. Recording it twice (ADR + comment) would be ceremony for a one-edge graph change with no cross-cutting consumer.
- **### C4 views**: No C4 impact. Checked all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) for the actors/systems/relationships this change could touch:
  - External human actors: none added or changed (operator + CI runner already model the apply path; no new correspondent/recipient).
  - External systems/vendors: none added (Hetzner host, Cloudflare Tunnel, the webhook listener are all pre-existing; this changes only the apply *order* of two existing provisioners targeting the same host).
  - Containers/data stores: none added or changed.
  - Access relationships: unchanged — the operator and CI both already apply both resources; only the intra-apply ordering between them changes, which is below C4 Component granularity.

  The change is a resource-graph ordering edge between two already-modeled provisioning steps — sub-Component-level, no element/relationship to add. (A `grep` for `deploy.pipeline\|handler.bootstrap\|FILE_MAP` across the three `.c4` files returns zero, consistent with infra-provisioning internals not being modeled at C4 granularity.)

## Observability

```yaml
liveness_signal:
  what: apply-deploy-pipeline-fix.yml's post-apply HTTPS verify of the infra-config state record (files_written == files_total, files_failed == 0)
  cadence: on every merge to main touching a DEPLOY_PIPELINE_FIX_TRIGGERS file
  alert_target: GitHub Actions job failure (red check on the merge commit) + the existing webhook /hooks/infra-config-status state JSON
  configured_in: .github/workflows/apply-deploy-pipeline-fix.yml (post-apply verify step) — pre-existing, unchanged by this PR
error_reporting:
  destination: GitHub Actions step failure (CI) — the apply fails loud if the bridge or push provisioner errors; the handler's per-file missing_env arm surfaces a non-zero exit to the CI verify gate
  fail_loud: true
failure_modes:
  - mode: a future new FILE_MAP file still lands one apply late (regression — the depends_on edge removed)
    detection: the regression test (Phase 2) fails in the bun suite; CI red
    alert_route: PR check failure (pre-merge, never reaches prod)
  - mode: depends_on creates an unexpected cycle in the graph
    detection: terraform plan errors with "Cycle:" — CI plan step fails before apply
    alert_route: apply-deploy-pipeline-fix.yml plan step failure (red check)
logs:
  where: GitHub Actions run logs (terraform plan/apply output) + host journald (logger -t infra-config-apply) → Better Stack
  retention: GHA default (90d) + Better Stack ingest
discoverability_test:
  command: grep -n "infra_config_handler_bootstrap" apps/web-platform/infra/server.tf
  expected_output: "depends_on = [terraform_data.apparmor_bwrap_profile, terraform_data.infra_config_handler_bootstrap]"
```

## Files to Edit

- **`apps/web-platform/infra/server.tf`** — at `terraform_data.deploy_pipeline_fix` (`:563-648`):
  1. Add `terraform_data.infra_config_handler_bootstrap` to the `depends_on` list (`:578`): `depends_on = [terraform_data.apparmor_bwrap_profile, terraform_data.infra_config_handler_bootstrap]`.
  2. **Rewrite** the now-stale `#4827/#4829 — deliberately NO depends_on …` comment block (`:566-577`). The new comment MUST:
     - State that the edge now EXISTS, citing #5515.
     - Explain WHY: a newly-added webhook-written FILE_MAP file needs the host's handler (`infra-config-apply.sh`) AND `hooks.json` (the env-key passing) current BEFORE the push, or the new file's env is unset → the handler's `missing_env` arm (`infra-config-apply.sh:105-112`, the #4804 self-heal) drops it → lands one apply late.
     - Preserve the still-true facts: both targets are explicit `-target=`s on the same CI run; the bridge is idempotent; the dual-fire `triggers_replace` already re-fires both on a handler edit.
     - Note the accepted trade-off (the over-coupling the OLD comment feared): the operator-local full apply will now recreate the idempotent bridge whenever `deploy_pipeline_fix` is replaced — acceptable, because a handler edit already re-fires both via dual-fire, and the bridge's remote-exec is idempotent + assertion-gated. **[deepen P2-1]** State explicitly that this now also bounces the `webhook` listener (sub-second, idempotent) on operator-local full applies even when only an UNRELATED hashed trigger file changed (e.g. a `ci-deploy.sh` edit, one of `deploy_pipeline_fix`'s ~18 hashed triggers) — so a future reader does not rediscover this coupling as a surprise.
     - Distinguish this from the helper/sudoers ordering, which the `install_rejected` self-heal genuinely DOES cover (that part of the old rationale survives, for those root-managed files).
     - **[SpecFlow P2-A]** Note the secondary benefit: the edge also serializes the bridge's synchronous webhook-listener restart (`server.tf:529`, an existing Terraform-managed `remote-exec` line) BEFORE the push's `local-exec` (`server.tf:637`), so the push never races a mid-flight listener restart (a connection-reset window that exists today).
  3. **[SpecFlow P1-A]** Audit BOTH workflows' shared concurrency-group comments for staleness: `grep -n "depends_on" .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-web-platform-infra.yml`. The concurrency comment (`apply-deploy-pipeline-fix.yml:~84-101`, mirrored in `apply-web-platform-infra.yml:~84-101`) says apparmor is "pulled transitively via deploy_pipeline_fix's depends_on." After this change `deploy_pipeline_fix.depends_on` has TWO elements, so update the rationale to note that `deploy_pipeline_fix` now transitively pulls BOTH `apparmor_bwrap_profile` AND `infra_config_handler_bootstrap` into the apply-deploy-pipeline-fix run. Confirm (and the comment should state) that this does NOT change the other workflow's overlap surface — `apply-web-platform-infra.yml` SSH-`-target`s only `apparmor_bwrap_profile` (`:533`) and does NOT target either fix resource, so the new edge is never traversed by that workflow.

- **`plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`** — add regression `test()`s (siblings to the existing `server.tf`-read tests; reuse the `SERVER_TF` constant at `:21`, the `APPLY_DPF_WORKFLOW` constant at `:22`, and the `readFileSync` pattern):
  - **Test 1 — the `depends_on` edge.** **[SpecFlow P1-C]** Reuse the top-level-block BOUNDING regex (`:231-246`) to isolate the `resource "terraform_data" "deploy_pipeline_fix"` block, then run a FRESH `/depends_on\s*=\s*\[([\s\S]*?)\]/` match against that bounded slice and assert the array contains BOTH `terraform_data.apparmor_bwrap_profile` AND `terraform_data.infra_config_handler_bootstrap`. Do NOT reuse the `triggers_replace` join extractor — it matches a different construct (`sha256(join(...))`), not the `depends_on` list.
  - **Test 2 — the co-targeting invariant (the load-bearing one).** **[SpecFlow P0-A]** The `depends_on` edge is only load-bearing because BOTH resources are co-`-target`ed in `apply-deploy-pipeline-fix.yml`'s single `terraform apply` (if either target were dropped, the edge would be inert or silently do nothing, and Test 1 would still pass green). Read `APPLY_DPF_WORKFLOW` (`readFileSync` at `:346`) and assert the `terraform apply` step contains BOTH `-target=terraform_data.deploy_pipeline_fix` AND `-target=terraform_data.infra_config_handler_bootstrap`.
  - **Test 3 — cross-workflow blast-radius guard (optional, deepen P2-2).** Assert `apply-web-platform-infra.yml` (the OTHER infra workflow, which shares the concurrency group) contains NEITHER `-target=terraform_data.deploy_pipeline_fix` NOR `-target=terraform_data.infra_config_handler_bootstrap`. This pins the invariant that the new edge is never traversed by that workflow (it SSH-targets only `apparmor_bwrap_profile` among shared resources), so a future edit cannot silently widen its blast radius. Read the workflow path (add a sibling `const APPLY_WEBPLAT_WORKFLOW = resolve(REPO_ROOT, ".github/workflows/apply-web-platform-infra.yml")`).
  - Header comment explains the #5515 rationale (the `missing_env` / one-apply-late failure) so a future reader does not "simplify" any assertion away.
  - **Runner**: this file is in the `bun` suite of `scripts/test-all.sh` (line ~57: "plugins/soleur"); run it with `cd <repo-root> && bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`. (Verified: the file already uses `bun:test` imports; sibling tests run under bun.)

## Files to Create

None.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` queried; no open scope-out names `server.tf` or `ship-deploy-pipeline-fix-gate.test.ts`. If the one-shot author re-runs the query and finds a match against these two paths, fold-in or acknowledge per the planner contract.)

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

_Phase 2.8 reviewed: the `systemctl restart webhook` references in this plan are DESCRIPTIONS of an existing Terraform `provisioner "remote-exec"` line (`server.tf:529`, already IaC-managed inside `terraform_data.infra_config_handler_bootstrap`), NOT a new manual operator step. This plan adds zero manual-infrastructure actions._

This plan edits an existing Terraform root (`apps/web-platform/infra/server.tf`) and introduces NO new infrastructure (no new server, secret, vendor, cron, DNS, or persistent process). It only reorders two already-provisioned `terraform_data` resources. Per the Phase 2.8 skip rule (a plan that only edits an existing `*.tf` resource graph, adding no new resource), no `terraform-architect` reshape is required. The apply path is unchanged: `apply-deploy-pipeline-fix.yml` fires on merge (it already targets both resources). The new `depends_on` is consumed by the SAME apply that already runs both — it changes only their intra-apply ordering.

**Apply-path note (no operator step):** the merge to main triggers `apply-deploy-pipeline-fix.yml` automatically (path-filtered on `server.tf` per the #5505 reachability gate). The PR merge IS the remediation. No `### Post-merge (operator)` step is needed — the auto-apply workflow re-applies both resources in the now-correct order on merge.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** `grep -n "depends_on" apps/web-platform/infra/server.tf` shows `deploy_pipeline_fix`'s `depends_on` containing BOTH `terraform_data.apparmor_bwrap_profile` AND `terraform_data.infra_config_handler_bootstrap`.
- [x] **AC2** The `#4827/#4829 — deliberately NO depends_on` comment is gone; replaced by a comment that (a) cites #5515, (b) names the `missing_env` / `hooks.json` one-apply-late mechanism, (c) preserves the helper/sudoers `install_rejected` distinction. Verify: `grep -n "deliberately NO depends_on" server.tf` returns nothing; `grep -n "5515" server.tf` returns the new comment.
- [x] **AC3** `cd apps/web-platform/infra && terraform init -backend=false && terraform validate` passes (no cycle, valid HCL). (Backend-less validate avoids needing R2 creds AND lets `init` install providers so `validate` can build the graph; it still catches `Cycle:` errors and HCL syntax.) **[SpecFlow P1-B durability note]** AC3 is a one-time PR-author check; the DURABLE post-merge cycle guard is `apply-deploy-pipeline-fix.yml`'s `terraform plan` step (fails red on `Cycle:` before apply). If the infra dir is not already covered by a `pull_request`-triggered `terraform validate` CI job, accept post-merge plan-step detection as the durable guard and state so explicitly in the PR body — do NOT imply AC3 is a standing gate.
- [x] **AC4** New regression Test 1 (`depends_on` edge) in `ship-deploy-pipeline-fix-gate.test.ts` FAILS when the new `depends_on` element is removed (RED) and PASSES with it present (GREEN). Verify: `cd <repo-root> && bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` → all pass.
- [x] **AC5** The full bun gate suite still passes (no regression in the existing `TRIGGER_FILES` / regex / on.push.paths assertions): `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`.
- [x] **AC6** PR body uses `Closes #5515` (this is a code-only durable fix that takes effect via the auto-apply on merge — NOT an ops-remediation whose fix runs post-merge by hand; the `Closes` is correct here because the merge-triggered apply IS the fix).
- [x] **AC7** **[SpecFlow P0-A — the load-bearing assertion]** New regression Test 2 (co-targeting invariant) asserts `apply-deploy-pipeline-fix.yml`'s `terraform apply` step co-`-target`s BOTH `terraform_data.deploy_pipeline_fix` AND `terraform_data.infra_config_handler_bootstrap`. The `depends_on` edge is inert if either target is dropped; this AC guards that invariant. Verify: the test fails if either `-target=` is removed from the workflow.

### Post-merge (operator)

None. The merge fires `apply-deploy-pipeline-fix.yml`, which re-applies both resources in the corrected order. No manual terraform apply, no SSH, no dashboard step.

## Test Scenarios

1. **Regression guard — edge (Test 1):** assert `deploy_pipeline_fix`'s `depends_on` lists `infra_config_handler_bootstrap`. RED before the HCL edit, GREEN after.
2. **Regression guard — co-targeting invariant (Test 2):** assert `apply-deploy-pipeline-fix.yml` co-`-target`s both resources. The edge is inert without this; RED if either `-target=` is dropped.
3. **No-cycle validation:** `terraform init -backend=false && terraform validate` confirms the new edge does not create a graph cycle (verified: the bridge has NO `depends_on`, so no path back to `deploy_pipeline_fix`; the graph stays a DAG).
4. **Existing gate parity unchanged:** `TRIGGER_FILES` ↔ ship array ↔ regex ↔ `on.push.paths` assertions still pass (the `depends_on` edit does not touch `triggers_replace` file hashing).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a single Terraform resource-graph ordering edge + a guard test). No Product/UI surface (no file under `components/**`, `app/**/page.tsx`, etc.), no legal/finance/marketing/ops/sales/support implication.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled; threshold = `aggregate pattern`.)
- **Do NOT "simplify" the new `depends_on` away.** The edge looks redundant because both resources are already explicit `-target=`s in the same apply — but `-target` does NOT order; only the graph edge does. The rewritten comment + the regression test exist precisely to stop a future reader from re-deleting the edge under the old (partially-stale) "explicit targets make depends_on unnecessary" reasoning.
- **The old comment's `install_rejected` rationale is correct for helper/sudoers, wrong for FILE_MAP files.** When rewriting, keep both truths separate: helper/sudoers (root-managed, not in FILE_MAP) self-heal via `install_rejected`; webhook-written FILE_MAP files fail via `missing_env` and need the bridge-delivered `hooks.json`+handler current first. Conflating them in the rewrite re-introduces the confusion that caused this bug.
- **Block-extraction in the test must be bounded.** The existing `server.tf` has multiple `terraform_data` resources; reuse the existing bounded-extraction approach (`:227-236`) so the `depends_on` grep does not absorb a downstream resource's `depends_on`.
- **`terraform validate` needs `-backend=false`** in CI/local without R2 creds, or it will try to init the S3-compatible backend and fail on missing AWS creds (per the drift-runbook canonical-invocation learning). Use `terraform init -backend=false && terraform validate` for AC3.
