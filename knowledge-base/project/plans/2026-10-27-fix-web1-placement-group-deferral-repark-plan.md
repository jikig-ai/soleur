---
title: "revert(infra): re-park web-1 placement_group_id ignore_changes deferral (ADR-068, Ref #11181, Ref #6027)"
type: fix
date: 2026-10-27
slug: web1-placement-group-deferral-repark
branch: feat-one-shot-web1-pg-deferral-repark
issue: 11181
domain: engineering/infra
priority: high
brand_survival_threshold: none
lane: cross-domain
---

# revert(infra): re-park web-1 placement_group_id ignore_changes deferral (ADR-068, Ref #11181, Ref #6027)

## Overview

Merge commit `6f530d494a` (PR #11217, "feat(infra): remove placement_group_id from web-1 ignore_changes (GA maintenance window, ADR-068 #5887)", merged 2026-10-27) dropped `placement_group_id` from `hcloud_server.web`'s `lifecycle.ignore_changes`. That exposed web-1's pending `0 -> web_spread` placement-group attach — a reboot-forcing in-place `update` on the sole live origin — to every terraform plan, where the `reboot_updates` destroy-guard now HALTs each apply. The operator has deferred that reboot until web-2 serves traffic (blue-green cutover, epic #11181 / orchestrator issue #6027, both OPEN). This plan restores the pre-removal state by reverting `6f530d494a` in full, which re-adds `placement_group_id` to the ignore list, restores the workflow error-message text naming the four-element list, flips the static parity guard back to asserting the entry is present, and restores the birth-gate comment that marks the `placement_group_id` arm unreachable while the entry is ignored.

`Reviewed-Coverage: sequential-fallback` — no plugin-defined subagents exist on this harness; every named agent role below (research, domain leaders, review panel, CTO ruling) was executed inline by this orchestrator against the same agent definitions, sequentially.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| "restore all three touched files" | `git show 6f530d494a --stat` lists **four** files: the three named plus `tests/scripts/lib/web-host-birth-gate.sh` (comment-only change flipping the `placement_group_id` arm from UNREACHABLE to LIVE) | Prescribe the full `git revert` — all four files. A partial revert would leave a comment claiming LIVE coverage terraform cannot emit. (CTO-ruled — see `decision-challenges.md`.) |
| "`git revert` of merge commit 6f530d494a" | `6f530d494a` has exactly one parent (`7ea2f503e6`) — it is a squash-merge, not a two-parent merge | Plain `git revert 6f530d494a`; no `-m 1` needed |
| "removal exposes the pending attach to every terraform plan" | Verified: `server.tf:617` currently reads `ignore_changes = [user_data, ssh_keys, image]`; `server.tf:368` still computes `placement_group_id` for web-1, so a `0 -> web_spread` attach diff is live in every plan | Revert restores the documented suppression |

## Research Insights

### Premise Validation (Phase 0.6)

- **#11181** OPEN — "Epic: ADR-068 Phase-3 GA blockers (multi-host /workspaces) — non-cutover track". Item 5 ("Placement-group reboot deferral removal … during GA maintenance window (drained host)") is an **unchecked** checkbox — the epic still expects the removal to be pending work.
- **#6027** OPEN — "feat(infra): live multi-host GA cutover orchestrator (Inngest-dispatched GHA maintenance-window)". Its step 4 is exactly the orchestrated `ignore_changes` removal on the drained host — the revert re-parks until that workflow does it.
- **`6f530d494a`** exists on first-parent history; single parent (squash merge).
- **Reverse-apply verified:** `git show 6f530d494a | git apply --check -R` passes on all four files (test hunks land at −10 line offset; the others exact).
- **ADR-068 mechanism check:** the ADR's 2026-07-03 amendment documents `ignore_changes = [placement_group_id]` as the standing deferral and names the GA-window removal trigger; its 2026-07-05 amendment (line ~843) literally asserts `ignore_changes = [user_data, ssh_keys, image, placement_group_id]` as the baseline the `web_2_recreate` dispatch depends on. The revert **re-aligns code with the ADR**; it does not reverse a recorded decision. The rejected-alternatives scan found no alternative this plan re-proposes.
- **Collision precheck:** `collision-precheck.sh 11181` and `… 6027` — no open PRs naming either issue; two foreign `test-all.sh` processes (pids 3812402, 3847006) owned by `.worktrees/feat-one-shot-10368-codeql-fs-race` — reported, unrelated to this work.
- **Cross-site sweep:** `git grep placement_group_id` outside the four reverted files shows only generic guard comments (`apply-deploy-pipeline-fix.yml:524`, `destroy-guard-filter-web-platform.jq`, `web-host-replace-gate.sh`, `git-data-host-birth-gate.sh`, destroy-guard test fixtures) — all accurate under either ignore state; `cloud-init-web-zot-seed.test.sh:276` asserts `user_data` membership only (tolerant of the four-element list); `web-host-provisioner-parity.test.sh:30` uses the wildcard `[user_data, ssh_keys, image, ...]` form. No site outside the commit pins the three-element list.

### Property List (Phase 0.6b)

- **P1** — web-1's pending `0 -> web_spread` attach is absent from every terraform plan, so the `reboot_updates` destroy-guard counter reads 0 and both apply pipelines self-heal (the #5887 unwedge mechanism, per runbook `moved-block-wedge-cutover-5887.md` and ADR-068 amendment 2026-07-03).
- **P2** — the static parity guard fails if `placement_group_id` is dropped from `ignore_changes` again before the orchestrated cutover (recurrence protection).
- **P3** — the operator-facing HALT text in `apply-web-platform-infra.yml` names the true four-element ignore list (error text must not lie about the config it describes).
- **P4** — the `web-host-birth-gate.sh` comment truthfully marks the `placement_group_id` arm unreachable while the attribute is ignored (no dead-coverage claim, no false LIVE claim).
- **P5** — no other change: the diff is exactly the inverse of `6f530d494a` (pure revert; zero new behavior).

### Cut List (Phase 0.6b)

- None. `git revert` is the minimal mechanism covering P1–P5 atomically; no mechanism on `origin/main` buys these properties today (the commit being reverted is precisely what removed them — verified by the `server.tf:617` grep of the authority). The hand-edit alternative reproduces the same bytes with strictly more error surface and no recorded revert relationship.

### Institutional Learnings

- `knowledge-base/engineering/operations/runbooks/moved-block-wedge-cutover-5887.md` — documents this exact `ignore_changes` entry (added by PR #5950) as the standing deferral that both apply pipelines depend on, and Scope B (the orchestrated cutover) as the only path that should remove it. Still accurate post-revert.
- `knowledge-base/project/learnings/2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md` — "amend the ADR when reversing a documented decision". **Evaluated:** no amendment needed here — the revert does not reverse ADR-068; it restores the exact state ADR-068 records as current (see Architecture Decision section). The removal PR was premature execution of the GA-window trigger, not a decision change.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-05-stale-branch-can-silently-revert-a-just-merged-invariant-pr.md` — stale branches silently re-reverting invariants. Mitigation: the parity test IS the invariant guard; it must be restored in the same PR, and CI runs it on the diff.
- `knowledge-base/project/learnings/best-practices/2026-07-03-destroy-guard-blind-to-reboot-forcing-in-place-update.md` — why `reboot_updates` exists; the revert is the documented way to make it read 0 (the pending change leaves the plan entirely).
- `knowledge-base/project/learnings/workflow-patterns/2026-07-03-chain-of-latent-defects-clearing-a-wedge-exposes-a-cascade.md` — clearing a wedge can expose downstream defects. Noted: post-merge, watch the next apply run rather than assuming green.

### Community Discovery / Functional Overlap

- Stack signatures scanned (no flutter/rust/elixir/go/swift/kotlin/php files) — no uncovered stacks; agent-finder not needed.
- Functional overlap: the deliverable is a `git revert` — core VCS functionality already in-repo; no community artifact could provide it. No installs.

### Network-Outage Checklist (Phase 1.4)

Not triggered. The feature description contains none of the keyword triggers (`SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `5xx`, `handshake`, `EHOSTUNREACH`, `ECONNRESET`), and the provisioner arm does not apply: `resource "hcloud_server" "web"` contains **no** `provisioner`/`connection` blocks (they live in sibling `terraform_data` resources), and the plan prescribes no fresh apply of SSH-provisioned resources — it removes a diff from plans, it does not add one.

### External Research (Phase 1.6)

Skipped — strong local context. The mechanism is `git revert`, the target state is byte-known (the pre-commit tree), the apply check already passed, and every behavioral claim is pinned by an in-repo guard or ADR. External sources would add nothing.

## Problem Statement / Motivation

PR #11217 removed `placement_group_id` from `hcloud_server.web`'s `lifecycle.ignore_changes` on the premise that the GA maintenance window had arrived. It had not: the reboot belongs to the orchestrated blue-green cutover (#6027), which removes the entry itself on the drained host. With the entry gone, web-1's pending `0 -> web_spread` attach rides every terraform plan and the `reboot_updates` destroy-guard HALTs each infra apply — blocking unrelated infra work until either the reboot is taken early (unacceptable: sole live origin) or the deferral is re-parked.

## Proposed Solution

`git revert 6f530d494a` — the atomic inverse of the premature removal, restoring all four touched files to their pre-removal bytes. The revert is the mechanism the runbook documents (the `ignore_changes` entry is the standing deferral; the orchestrator removes it for real at cutover).

## Technical Considerations

- **Squash commit:** `6f530d494a` has one parent — plain `git revert`, no `-m` flag.
- **Fourth file:** `tests/scripts/lib/web-host-birth-gate.sh` carries a comment-only change that flips the `placement_group_id` arm from UNREACHABLE to LIVE. It must revert with the rest — post-partial-revert it would claim LIVE coverage against a delta terraform can no longer emit.
- **Reboot semantics unchanged:** Hetzner still requires a stopped server for placement-group attach; the revert only removes the pending diff from plans. The attach itself still waits for #6027's drained-host window.
- **CI apply after merge:** the routine targeted apply self-heals — the pending update exits the plan, `reboot_updates` reads 0, no `[ack-destroy]` or `[skip-web-platform-apply]` needed.
- **NFR:** no performance, security, or data-model impact; the change is a lifecycle-metadata restoration on an existing resource.

## Implementation Phases

### Phase 1: Revert and verify locally

1. `git revert 6f530d494a` (no `-m`; squash commit). Edit the commit body to add one paragraph noting the re-park rationale ("reboot deferred until web-2 serves traffic — #6027 takes the reboot on the drained host; epic #11181 item 5 remains pending") — subject stays the default `Revert "…"` form.
2. Verify all four files match the pre-removal state:
   - `grep -F 'ignore_changes = [user_data, ssh_keys, image, placement_group_id]' apps/web-platform/infra/server.tf`
   - `grep -F 'ignore_changes = [user_data, ssh_keys, image, placement_group_id]' .github/workflows/apply-web-platform-infra.yml`
   - `grep -F 'placement_group_id stays in ignore_changes' plugins/soleur/test/terraform-target-parity.test.ts`
   - `grep -F 'currently UNREACHABLE' tests/scripts/lib/web-host-birth-gate.sh`
   - `git status --short` shows no residual edits beyond the revert commit.
3. `bun test plugins/soleur/test/terraform-target-parity.test.ts` — green, including the restored `lifecycle.ignore_changes includes placement_group_id` assertion.
4. `cd apps/web-platform/infra && terraform init -backend=false && terraform validate` — config parses.
5. If live creds are present, optionally run the canonical read invocation — `export AWS_ACCESS_KEY_ID=<TF_STATE_AWS_ACCESS_KEY_ID from prd_terraform>` + `export AWS_SECRET_ACCESS_KEY=<…>` then `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra plan` — and assert no `placement_group_id` on `hcloud_server.web` in the diff (read-only; the Tier-B write form from `infra-credential-tiers-8209.md` is NOT needed — no state-writing verb is prescribed). The static grep + `ignore_changes` semantics are the required arm (the identical suppression was live-verified 2026-07-03: `31 add, 2 change` → `31 add, 1 change`).

### Phase 2: PR

1. Push branch; open PR titled `revert: "feat(infra): remove placement_group_id from web-1 ignore_changes (GA maintenance window, ADR-068 #5887)"`. **The body's first line answers "does merging THIS alone mutate production?"** — "Merge triggers the routine targeted apply; the restored `ignore_changes` removes the pending `0 -> web_spread` update from the plan, so no new mutation is introduced — the change subtracts a pending reboot rather than adding anything" — then `Ref #11181` and `Ref #6027` only (never `Closes`/`Fixes` — both issues stay open; #6027 performs the real removal).
2. Set `semver:patch` label (touches `plugins/soleur/test/`).

## Files to Edit

- `apps/web-platform/infra/server.tf` — restored by revert: `lifecycle.ignore_changes` → `[user_data, ssh_keys, image, placement_group_id]` (line ~617).
- `.github/workflows/apply-web-platform-infra.yml` — restored by revert: HALT error text names the four-element list (line ~829).
- `plugins/soleur/test/terraform-target-parity.test.ts` — restored by revert: describe name `hcloud_server.web reboot deferral — placement_group_id stays in ignore_changes (#5887 zero-downtime CI unwedge)`, explanatory comment, and `expect(entries).toContain("placement_group_id")`.
- `tests/scripts/lib/web-host-birth-gate.sh` — restored by revert: `placement_group_id` arm documented as `currently UNREACHABLE` (comment-only).

## Files to Create

- None.

## Open Code-Review Overlap

- #2197 (`refactor(billing): SubscriptionStatus type + …`) mentions `apps/web-platform/infra/server.tf` — disposition: **Acknowledge.** Its concern is a `count`/`for_each` addition vs. in-memory rate limiters; the revert touches `lifecycle.ignore_changes` only. Different concern, remains open.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing new — a botched revert surfaces as a red `terraform-target-parity` suite or a still-halted apply pipeline (CI-visible), not a user-facing artifact. The change exists precisely to keep the *correct* failure mode (unplanned web-1 reboot → `app.soleur.ai` outage) from ever reaching a user.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the diff is terraform lifecycle metadata and guard text on an already-public repo surface; it writes no user data path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is a CI plan diff and static-guard text, not a runtime surface; the user-facing risk (live-origin reboot) is what this change *removes*, not what it could add.
- `threshold: none, reason: the touched sensitive paths (apps/web-platform/infra/server.tf, apply-web-platform-infra.yml per preflight SENSITIVE_PATH_RE) are infrastructure-metadata surfaces whose diff suppresses a pending reboot rather than introducing a runtime or data-path change.`

## Observability

```yaml
liveness_signal:
  what: "web-1 placement-group attach absent from terraform plan — asserted statically by terraform-target-parity.test.ts (describe 'placement_group_id stays in ignore_changes')"
  cadence: "per-PR CI run and on-demand `bun test`"
  alert_target: "PR check failure (terraform-target-parity suite red)"
  configured_in: "plugins/soleur/test/terraform-target-parity.test.ts"

error_reporting:
  destination: "CI run log + GitHub check status on the PR"
  fail_loud: "bun test assertion failure: expect(entries).toContain('placement_group_id'); or apply-web-platform-infra.yml HALT line printing reboot_updates>0"

failure_modes:
  - mode: "ignore_changes entry dropped again before cutover"
    detection: "terraform-target-parity.test.ts fails (static guard — the restored arm)"
    alert_route: "red required check on the offending PR"
  - mode: "pending attach re-surfaces in plan despite ignore entry (provider/ignore semantics change)"
    detection: "apply-web-platform-infra.yml reboot_updates counter HALT (unchanged guard)"
    alert_route: "apply job ::error:: block; no [ack-destroy] path reaches it"

logs:
  where: "GitHub Actions run logs for the parity suite and the apply workflow"
  retention: "GitHub default (90 days)"

discoverability_test:
  command: "grep -F 'ignore_changes = [user_data, ssh_keys, image, placement_group_id]' apps/web-platform/infra/server.tf"
  expected_output: "ignore_changes = [user_data, ssh_keys, image, placement_group_id]"
```

## Encryption Posture

```yaml
at_rest:
  - store: "none introduced — the change restores lifecycle metadata on existing hcloud_server.web; no volume, bucket, table, queue, cache, or log sink is created, re-keyed, or re-scoped. Existing store postures (workspaces LUKS volume per ADR-119/ADR-263, R2 state backend) are untouched."
in_transit:
  - connection: "none introduced — no new cross-component or network connection; ignore_changes alters plan-time diff computation only."
```

No `exception` block — no plaintext mechanism and no cert-verification-off row exists.

## Architecture Decision (ADR/C4)

- **Detection evaluated:** the plan makes **no architectural decision** — it restores the pre-removal state ADR-068 already records as current. ADR-068's 2026-07-03 amendment documents `ignore_changes` on `placement_group_id` as the standing deferral with the GA-window removal trigger; its 2026-07-05 amendment asserts the four-element list as the baseline `web_2_recreate` depends on; its "Deferred orchestrator" clause assigns the removal to the Inngest-dispatched cutover (#6027). The revert re-aligns code with the ADR — no new ADR, no amendment.
- **ADR:** none (see above; ruled — `decision-challenges.md`).
- **C4 views:** no impact. Enumeration checked against `model.c4`/`views.c4`/`spec.c4`: no new external human actor, no new external system/vendor, no new container or data store, no changed actor↔surface access relationship. The Hetzner compute container already models "spread placement" (model.c4 `hetzner` container); `ignore_changes` is a terraform diff-suppression attribute, below C4 abstraction.

## Guard Contract

### Guard 1 — `terraform-target-parity` web-1 deferral pin (restored)

**Property.** While the GA cutover (#6027) has not run, `hcloud_server.web`'s `lifecycle.ignore_changes` must contain `placement_group_id` — and the guard must prove it parsed the real list, not an empty or wrong block.

**Assembly.** One chokepoint: `apps/web-platform/infra/server.tf`'s `lifecycle { ignore_changes = [...] }` inside `resource "hcloud_server" "web"`, parsed by `hcloudServerWebBody()` (brace-matched body slice) + `/ignore_changes\s*=\s*\[([^\]]*)\]/` in `plugins/soleur/test/terraform-target-parity.test.ts`. A second, comment-only surface (`tests/scripts/lib/web-host-birth-gate.sh`) documents reachability but asserts nothing — the test is the sole enforcement site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete `placement_group_id` from the `ignore_changes` list in server.tf | RED (`toContain` fails) |
| 2 | Replace the test's `expect(entries).not.toBeNull()` with a tautology (guard's own dispatch never checks) | RED (vacuous harness — `toContain`/`toContain('user_data')` assertions are the teeth; removing the parse assertions leaves nothing green that proves the property) |
| 3 | Reorder the list to `[placement_group_id, user_data, ssh_keys, image]` | PASS — membership, not order, is the property |
| 4 | Strip `user_data` from the list while keeping `placement_group_id` (non-vacuity arm) | RED (`toContain("user_data")` fails — proves the real block was parsed) |
| 5 | Edit the suite to assert `not.toContain` (re-running the #11217 flip) | RED against the reverted server.tf — suite and guard travel together |

**Anchor.** The guard compares committed config (`server.tf` on the PR branch) against committed assertions in the same diff — a weakening requires both files to move in one PR, which CI + review see as one diff; the merged-state anchor is the restored assertion itself (a future silent drop fails on the next PR).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "git revert 6f530d494a — restore all three touched files" | Phase 1 step 1 + all four Files-to-Edit rows | mapped (widened: commit touches 4 files — see Research Reconciliation) |
| 2 | "apps/web-platform/infra/server.tf — ignore_changes back to [user_data, ssh_keys, image, placement_group_id]" | Files-to-Edit: server.tf | mapped |
| 3 | ".github/workflows/apply-web-platform-infra.yml — restore the error-message text naming the four-element ignore list" | Files-to-Edit: apply-web-platform-infra.yml | mapped |
| 4 | "plugins/soleur/test/terraform-target-parity.test.ts — flip the static guard back to asserting ignore_changes INCLUDES placement_group_id (restore its pre-revert describe name and explanatory comment)" | Files-to-Edit: terraform-target-parity.test.ts | mapped |
| 5 | "terraform-target-parity test suite green with the includes-assertion" | Phase 1 step 3 + AC2 | mapped |
| 6 | "terraform plan in apps/web-platform/infra no longer surfaces a placement_group_id diff for web-1 (verify statically if live creds are unavailable)" | Phase 1 steps 4–5 + AC3 | mapped |
| 7 | "PR body uses Ref #11181 and Ref #6027 only — never Closes/Fixes" | Phase 2 step 1 + AC4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `git revert` + 4-file restore | "git revert 6f530d494a — restore all three touched files" (4th file = same commit, CTO-ruled full revert) | asked |
| Commit-body re-park note | — | inferred — justification: the revert commit must record WHY the deferral returned or a future reader re-runs the same premature removal |
| `terraform init -backend=false && terraform validate` | "verify statically if live creds are unavailable" | asked |
| `semver:patch` label | — | inferred — justification: constitution requires a semver label on any PR touching plugins/soleur/ |
| `Ref #11181` / `Ref #6027` PR-body rule | "PR body uses Ref #11181 and Ref #6027 only — never Closes/Fixes" | asked |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `.github`, `plugins/soleur` (+ `tests/` → 4 first-segment roots)
- Planned files: 4 | Estimated changed lines: ~31 (exact inverse of the 14+/17- removal diff)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the four files are one atomic revert; splitting a single commit's inverse across PRs re-wedges the guard states the revert restores.

## Acceptance Criteria

- [ ] AC1: `git revert 6f530d494a` is committed on this branch; `git show <revert-sha> --stat` touches exactly the four files (`server.tf`, `apply-web-platform-infra.yml`, `terraform-target-parity.test.ts`, `web-host-birth-gate.sh`) and nothing else.
- [ ] AC2: `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes, including the restored `lifecycle.ignore_changes includes placement_group_id` test inside describe `hcloud_server.web reboot deferral — placement_group_id stays in ignore_changes (#5887 zero-downtime CI unwedge)`.
- [ ] AC3: `grep -F 'ignore_changes = [user_data, ssh_keys, image, placement_group_id]' apps/web-platform/infra/server.tf` matches, and `terraform init -backend=false && terraform validate` succeeds; if live creds are available, `terraform plan` shows no `placement_group_id` diff on `hcloud_server.web` (static verification is the required arm).
- [ ] AC4: PR body references the issues as `Ref #11181` and `Ref #6027` — no `Closes`/`Fixes`/`Resolves` anywhere in title or body; PR carries `semver:patch`.
- [ ] AC5: the restored workflow line `ignore_changes = [user_data, ssh_keys, image, placement_group_id]` is present in `apply-web-platform-infra.yml`, and `web-host-birth-gate.sh` again documents the `placement_group_id` arm as `currently UNREACHABLE`.

<!-- founder-stated check: none — headless pipeline run; no block written per plan-founder-check.md -->

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed
**Assessment:** (CTO assess interface, sequential-fallback inline) — Revert of an in-flight premature diff, not a new design. Architectural posture is ADR-068's recorded one: deferral stands until the orchestrated cutover removes the entry on the drained host. Risks: (a) partial-revert drift — mitigated by reverting the whole commit atomically; (b) the stale-branch class (`2026-07-05` learning) — mitigated by restoring the static guard in the same diff; (c) post-merge a latent downstream red may surface behind the now-green apply path (cascade learning) — mitigated by watching the next apply run. Complexity: small. No capability gaps.

### Operations

**Status:** reviewed
**Assessment:** (COO assess interface, sequential-fallback inline) — Unblocks the apply pipelines without a maintenance window, vendor change, or cost. The reboot cost/blast-radius is deferred into #6027's orchestrated envelope, which is where the authorization to power-cycle web-1 already lives. No new procurement, runbook, or on-call step; the existing `moved-block-wedge-cutover-5887.md` runbook remains the operating reference.

## Test Scenarios

- Given the revert commit is applied, when `bun test plugins/soleur/test/terraform-target-parity.test.ts` runs, then all assertions pass including `expect(entries).toContain("placement_group_id")` (unit).
- Given a hypothetical edit drops `placement_group_id` from the list, when the suite runs, then the restored describe fails — the non-vacuity `toContain("user_data")` arm still passes, proving the real block was parsed (unit — mutation check).
- Given the reverted `server.tf`, when `terraform init -backend=false && terraform validate` runs, then it exits 0 (integration — config parses).
- Given the restored workflow text, when the apply workflow's HALT arm fires (or its text is grepped), then the message names `[user_data, ssh_keys, image, placement_group_id]` (integration — text parity).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- Do NOT split the revert across PRs or hand-edit a subset: the four files are one atomic commit's inverse; a partial revert leaves the birth-gate comment claiming LIVE coverage that cannot exist.
- `6f530d494a` is a squash commit — `-m 1` is wrong and unnecessary; plain `git revert`.
- PR body must use `Ref #11181`/`Ref #6027`, never `Closes`/`Fixes` — both issues remain open; #6027 performs the real removal at cutover.
- After merge, watch the next `apply-web-platform-infra.yml` run — the wedge-clear may expose a downstream red that was masked behind the HALT (cascade learning).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Full `git revert 6f530d494a` | **Chosen** — atomic, recorded, restores all four files |
| Hand-edit the three named files only | Rejected — leaves `web-host-birth-gate.sh` claiming LIVE coverage terraform cannot emit; loses the revert relationship |
| Keep removal, take the reboot now | Rejected by operator — the reboot waits for web-2 serving traffic (#6027 drains web-1 first) |
| `[skip-web-platform-apply]` merge-commit bypass | Rejected — skips the apply, does not remove the pending diff; every later targeted plan still trips `reboot_updates` |

## Context

- The `placement_group_id` attach forces a Hetzner power-off (placement groups attach to stopped servers only); web-1 is the sole live origin behind `app.soleur.ai`.
- The deferral mechanism was added by PR #5950 (2026-07-03) and live-verified: `31 add, 2 change` → `31 add, 1 change, 0 destroy`; `reboot_updates` reads 0 while the entry is ignored.
- `web-host-birth-gate.sh`'s `placement_group_id` arm is a dormant backstop while the attribute is ignored — the reverted comment says exactly that.

## References

- Revert target: `6f530d494a` (PR #11217)
- ADR-068 (`knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`) — amendments 2026-07-02/03/05
- Runbook: `knowledge-base/engineering/operations/runbooks/moved-block-wedge-cutover-5887.md`
- Epic: #11181 (item 5 — deferral removal, pending) | Orchestrator: #6027
- Related: #5887 (original wedge), #5911 (`reboot_updates` counter), #967 (import-artifact ignore entries)
- Deferral origin: PR #5950
