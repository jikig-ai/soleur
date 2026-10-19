---
title: Provision the workspaces-luks-cutover GitHub environment authorization gate
type: fix
issue: 6604 (Ref, do NOT close)
adr: ADR-119 (workspaces LUKS cutover); precedent ADR-100 (inngest cutover env gate)
branch: feat-one-shot-6604-luks-cutover-env-gate
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
date: 2026-07-17
---

# 🐛 Provision the missing `workspaces-luks-cutover` GitHub environment authorization gate

## Enhancement Summary

**Deepened on:** 2026-07-17
**Scope decision:** This is a 3-file, precedent-mirror IaC change (mirrors
`github_repository_environment.inngest_cutover` 1:1). Deepen ran the mandatory
always-on halt gates + a live precedent-diff / citation-verification pass rather than a
disproportionate 40-agent fan-out — appropriate for a mechanical infra-wiring change at
this altitude. The heavy review lens (architecture-strategist + spec-flow-analyzer +
`user-impact-reviewer`) lands at the review phase, which the single-user-incident
threshold already escalates.

**Halt gates (all PASS):** 4.6 User-Brand Impact present, threshold `single-user
incident`. 4.7 Observability present, 5 fields, `discoverability_test.command` is
`gh api` (no ssh). 4.8 no PAT-shaped variable. 4.9 no UI surface (skip). 4.5
network-outage / 4.55 downtime — no trigger (creates a GitHub environment; no SSH
provisioner, no serving-surface offline op).

**Live-verified citations (deepen pass):**
- Precedent resource `github_repository_environment.inngest_cutover` at
  `apps/web-platform/infra/inngest-arm-write-token.tf:70-77` — `reviewers { users = [54279] }`. ✓
- Default-block wiring `-target=github_repository_environment.inngest_cutover` at
  `apply-web-platform-infra.yml:360`. ✓
- `integrations/github` provider IS required by the infra root
  (`apps/web-platform/infra/main.tf:49`, App-auth). ✓ (IaC "already required" claim holds.)
- Reviewer id `54279` = @deruelle — confirmed in the precedent (only in-repo occurrence). ✓
- `ADR-100` and `ADR-119` both exist under `knowledge-base/engineering/architecture/decisions/`. ✓
- ADR-119 records the freeze needs operator sign-off (ADR-119 §(c)) but does NOT name
  the environment mechanism → ADR attribution tightened; no ADR amend needed. ✓

**Precedent diff (inngest_cutover → workspaces_luks_cutover), the ONLY delta:**
`resource "..." "inngest_cutover"` → `"workspaces_luks_cutover"`; `environment =
"inngest-cutover"` → `"workspaces-luks-cutover"`. `repository`, the `reviewers { users =
[54279] }` block, and the absence of `lifecycle.ignore_changes` are byte-identical.
This is the intended verbatim mirror.

## Overview

The `/workspaces` LUKS live-cutover mechanism merged 2026-07-17 shipped
`.github/workflows/workspaces-luks-cutover.yml`, whose freeze job declares
`environment: workspaces-luks-cutover` (line 58) as — per its own sign-off comment
(lines 9–16) — the **SOLE human authorization** on an *irreversible* freeze of
**sole-copy user data** (passphrase/header loss ⇒ unreadable forever).

That environment is **not provisioned**: `gh api
repos/jikig-ai/soleur/environments/workspaces-luks-cutover` returns **404**
(verified 2026-07-17), and no Terraform resource defines it. GitHub **auto-creates an
environment on first reference with zero protection rules**, so the first freeze
dispatch would silently manufacture a **zero-reviewer environment that
auto-approves** the irreversible freeze — the exact **DP-11 F8 /
zero-reviewer-auto-approve** failure the workflow header warns about.

The fix mirrors the existing, already-approved `inngest-cutover` precedent
(`github_repository_environment.inngest_cutover`, ADR-100) exactly: declare the
environment in Terraform with a non-empty required-reviewer set and wire it into the
default allow-list apply so a merge provisions it. This PR **only provisions the
gate**. It references #6604 but does **NOT** close it — the live freeze (AC21–AC30),
the 7-day soak, and the volume wipe all remain operator-dispatched,
environment-gated steps.

## User-Brand Impact

**If this lands broken, the user experiences:** an operator dispatches the freeze;
GitHub auto-creates a zero-reviewer `workspaces-luks-cutover` environment and
auto-approves; the freeze runs with no human ack; a passphrase/header-loss edge (the
terminal C19/F4 failure mode the environment gate exists to hold behind a human)
strands **every user's sole-copy checked-out source code, unreadable forever**.

**If this leaks, the user's data is exposed via:** N/A — this change adds no data
path. Its failure mode is *loss of a safety gate*, not data exposure. (The escrow
token/passphrase surfaces are pre-existing in `workspaces-luks.tf`, unchanged here.)

**Brand-survival threshold:** single-user incident. A single unattended freeze that
hits the terminal failure mode is unrecoverable and brand-fatal — the gate being
present-and-non-empty is the difference between "a human said go" and "GitHub
silently said go". `requires_cpo_signoff: true`; `user-impact-reviewer` runs at
review time.

## Research Reconciliation — Spec vs. Codebase

<!-- lint-infra-ignore start: PRE-EXISTING prose (unchanged by this PR, which only re-anchored two stale ADR-119 line citations to a section anchor). Retrospective premise-vs-codebase validation table describing the CI-driven apply MECHANISM, not a step a Soleur user performs -->

| Claim (from the task) | Reality (verified) | Plan response |
|---|---|---|
| `gh api .../environments/workspaces-luks-cutover` returns 404 | **Confirmed** 404 (2026-07-17) | Provision via Terraform |
| Precedent is `github_repository_environment.inngest_cutover` | **Confirmed** at `apps/web-platform/infra/inngest-arm-write-token.tf:70-77` — `repository="soleur"`, `environment="inngest-cutover"`, `reviewers { users = [54279] }` | Mirror it verbatim (env name = `workspaces-luks-cutover`) |
| inngest_cutover is wired into the DEFAULT allow-list apply | **Confirmed** at `apply-web-platform-infra.yml:360` (`-target=github_repository_environment.inngest_cutover`), inside the push/`manual-rerun` block | Add the new env `-target` immediately after it |
| Scoped `apply_target=workspaces-luks-cutover` -targets EXACTLY 5 resources | **Confirmed** at `apply-web-platform-infra.yml:2526-2530` (passphrase/secret/token/volume/attachment) | Do NOT touch the scoped block — a 6th create aborts the gate |
| The scoped gate asserts exactly-5 and aborts a 6th | **Confirmed** — `tests/scripts/lib/workspaces-luks-cutover-gate.sh` `out_of_scope` clause + `test-workspaces-luks-cutover-gate.sh` T8 (an out-of-scope positive action ⇒ ABORT) | Keep invariant intact; env is created by the DEFAULT apply |
| Runbook frames the env as an "operator precondition" | **Confirmed** at `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md:19-21` | Reframe to Terraform-provisioned by the default apply |
| `#6604` is still open | **Confirmed** OPEN (labels: `follow-through`, `type/security`) | `Ref #6604`, never `Closes` |

**Premise Validation:** All external premises verified as holding. #6604 OPEN. The
env 404s. The precedent resource, its default-block wiring, the scoped 5-target set,
the gate's `out_of_scope` clause, and the runbook's mis-framed precondition all exist
exactly as the task describes. Nothing stale.

**Key discovered coupling (not in the task, load-bearing):** the fix is
*mechanically enforced* by `plugins/soleur/test/terraform-target-parity.test.ts:735`
("every managed resource has a `-target` line, an operator-applied exclusion, or a
pending-audit snapshot"). That test reads every `resource` from the infra `.tf` files
and requires each to appear in the workflow's non-stripped `-target` set (or an
exclusion set). Adding `github_repository_environment.workspaces_luks_cutover` to
`workspaces-luks.tf` **without** the default-block `-target` line makes this test go
RED (`uncovered = [github_repository_environment.workspaces_luks_cutover]`). This is
the built-in test-first loop for the change — the precedent env `inngest_cutover` is
green today only because it is in that allow-list.

<!-- lint-infra-ignore end -->

## Implementation Phases

### Phase 1 — Declare the environment resource (contract-declaring; TDD RED anchor)

**File to edit:** `apps/web-platform/infra/workspaces-luks.tf` (append at end of file).

Add, modeled verbatim on `github_repository_environment.inngest_cutover`:

```hcl
# GitHub Environment with a required-reviewer protection rule — the SOLE human
# authorization on the irreversible /workspaces LUKS freeze (C19 / AC20b; DP-11 F8).
# The freeze job in .github/workflows/workspaces-luks-cutover.yml declares
# `environment: workspaces-luks-cutover`, so the run is held in "Waiting" for reviewer
# approval BEFORE any step executes — that approval IS the human ack. A zero-reviewer
# environment auto-approves, so reviewers.users MUST stay non-empty. reviewers.users
# takes numeric GitHub user IDs — 54279 = @deruelle (the operator/founder). Mirrors
# github_repository_environment.inngest_cutover (inngest-arm-write-token.tf).
#
# Provisioned by the DEFAULT allow-list apply (apply-web-platform-infra.yml push /
# apply_target=manual-rerun), NOT the scoped apply_target=workspaces-luks-cutover job:
# that job's sourced workspaces_luks_cutover_gate asserts the plan is EXACTLY the five
# volume/attachment/passphrase/secret/token creates, so a sixth create there aborts it.
resource "github_repository_environment" "workspaces_luks_cutover" {
  repository  = "soleur"
  environment = "workspaces-luks-cutover"

  reviewers {
    users = [54279]
  }
}
```

At the end of Phase 1 (before Phase 2), `terraform-target-parity.test.ts:735` is
expected RED (`github_repository_environment.workspaces_luks_cutover` uncovered) —
this is the intended failing test. Do not "fix" it by adding to an exclusion set;
Phase 2 covers it via the default `-target`.

### Phase 2 — Wire the default-allow-list `-target` (GREEN)

**File to edit:** `.github/workflows/apply-web-platform-infra.yml`.

Immediately after line 360 (`-target=github_repository_environment.inngest_cutover \`),
inside the **DEFAULT** allow-list `terraform plan` block (the push / `manual-rerun`
block, guarded `github.event_name == 'push' || inputs.apply_target == 'manual-rerun'`),
add:

```yaml
              -target=github_repository_environment.workspaces_luks_cutover \
```

**Do NOT** add this `-target` to the scoped `workspaces_luks_cutover` job
(lines 2448–2600). That job must keep `-target`-ing exactly the five workspaces_luks
resources. After Phase 2, `terraform-target-parity.test.ts:735` returns GREEN.

### Phase 3 — Correct the runbook precondition framing

**File to edit:** `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`.

Replace the current precondition bullet (lines 19–21) that frames the environment as a
manual "operator precondition" with a Terraform-provisioned framing, e.g.:

> - The `workspaces-luks-cutover` GitHub **environment** is **provisioned by the
>   default allow-list apply** (`github_repository_environment.workspaces_luks_cutover`
>   in `workspaces-luks.tf`, `-target`-ed in the push/`manual-rerun` block of
>   `apply-web-platform-infra.yml`) — **not** a manual operator step
>   (`hr-all-infrastructure-provisioning-servers`,
>   `hr-fresh-host-provisioning-reachable-from-terraform-apply`; same class as
>   `inngest-cutover`). Its required-reviewer set **must remain non-empty** — a
>   zero-reviewer environment auto-approves (DP-11 F8). Verify post-apply with `gh api
>   repos/jikig-ai/soleur/environments/workspaces-luks-cutover` (200 + non-empty
>   `protection_rules[].reviewers`).

Keep the `prd_workspaces_luks` Doppler-config bullet (lines 17–18) as a genuine
operator precondition — the Doppler provider will not create a bare config, so that
one *is* operator-seeded (unchanged by this PR).

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/workspaces-luks.tf` — add
  `github_repository_environment.workspaces_luks_cutover`. Provider: `integrations/github`
  (already required by the root — it manages `github_repository_environment.inngest_cutover`).
  No new `TF_VAR_*` (numeric reviewer id `54279` is a literal, matching the precedent).
  No new secrets; nothing lands in `terraform.tfstate` beyond the environment metadata.

### Apply path

<!-- lint-infra-ignore start: PRE-EXISTING prose (unchanged by this PR). Describes the CI-driven default-apply path — the line flagged literally reads 'Zero operator ...', i.e. it documents the ABSENCE of a human step -->
- **(a) cloud-init-only? No. (b) idempotent bootstrap? No. Chosen: default per-merge
  apply.** Merging this PR touches `apps/web-platform/infra/*.tf`, which fires
  `apply-web-platform-infra.yml` on push; the default allow-list block (now including
  the new `-target`) runs `terraform apply` and creates the environment. Zero operator
  steps, zero SSH, zero dashboard. Blast radius: creation of one GitHub environment +
  its reviewer rule; no host, no data path, no downtime.

<!-- lint-infra-ignore end -->

### Distinctness / drift safeguards
- No `lifecycle.ignore_changes` (matches `inngest_cutover`) — a reviewer-set change is
  meant to propagate on the next apply. `dev != prd` N/A (GitHub repo-level resource,
  single repo `soleur`). The `-target` is transitive only onto the repo; no excluded
  sibling is dragged in (unlike the Doppler-token by-reference edges in this root).

### Vendor-tier reality check
- N/A — GitHub `Environments` with required reviewers are available on the repo's plan
  (the `inngest-cutover` environment is already provisioned this way).

## Observability

```yaml
liveness_signal:
  what: "gh api repos/jikig-ai/soleur/environments/workspaces-luks-cutover returns 200 with non-empty protection_rules[].reviewers"
  cadence: "on-demand (pre-dispatch check) + verified by the merge-triggered apply"
  alert_target: "the apply-web-platform-infra.yml run (fails loud on plan/apply error)"
  configured_in: "apps/web-platform/infra/workspaces-luks.tf + .github/workflows/apply-web-platform-infra.yml"
error_reporting:
  destination: "GitHub Actions run log (::error:: annotations) on apply-web-platform-infra.yml"
  fail_loud: true   # terraform plan/apply non-zero exits the job with ::error::
failure_modes:
  - mode: "env resource added but default -target omitted → env never created by apply"
    detection: "plugins/soleur/test/terraform-target-parity.test.ts:735 RED in CI pre-merge"
    alert_route: "CI test failure blocks the PR"
  - mode: "env accidentally added to the scoped 5-target block → 6th create aborts the freeze provision"
    detection: "tests/scripts/lib/workspaces-luks-cutover-gate.sh out_of_scope=1 (test-workspaces-luks-cutover-gate.sh T8)"
    alert_route: "gate ABORT at dispatch + CI gate-test failure"
  - mode: "reviewer set drifts empty (zero-reviewer auto-approve, DP-11 F8)"
    detection: "gh api .../environments/workspaces-luks-cutover shows empty protection_rules[].reviewers"
    alert_route: "post-merge operator verification (Terraform sets users=[54279]; drift would show on next apply)"
logs:
  where: "GitHub Actions run logs for apply-web-platform-infra.yml"
  retention: "GitHub default workflow-log retention"
discoverability_test:
  command: "gh api repos/jikig-ai/soleur/environments/workspaces-luks-cutover --jq '.protection_rules[].reviewers'"
  expected_output: "non-empty reviewers array containing user id 54279 (post-merge, post-apply)"
```

## Architecture Decision (ADR/C4)

**No new ADR; no C4 change.** ADR-119 already records the *decision* that the freeze
requires **operator sign-off / human authorization** with a bounded window
(ADR-119 §(c) — "explicit justification + a bounded window + sign-off"); it does not
name the *mechanism*. The GitHub `github_repository_environment` required-reviewer gate
is the **established mechanism precedent** for exactly that sign-off, set by
`github_repository_environment.inngest_cutover` (`inngest-arm-write-token.tf:70-77`,
under ADR-100 Decision 6b) — that env addition introduced neither a new ADR nor a C4
edit. This PR is the *provisioning implementation* that makes ADR-119's already-decided
sign-off real, using the ADR-100 mechanism verbatim; it closes an implementation gap,
not an architectural question. (Verified: ADR-119 does NOT specify the
`workspaces-luks-cutover` environment by name — the gate mechanism is a workflow-level
implementation choice, so there is nothing in the ADR corpus for this PR to amend.)

**C4 completeness check (all three `.c4` files considered):** external human actor =
the operator/reviewer @deruelle (already modeled); external system = GitHub Actions /
environments (already the CI substrate, already modeled); container/data-store touched
= none; access relationship changed = none (the reviewer↔freeze approval relationship
is a pre-existing dispatch-time gate, not a new modeled edge). No new actor, system,
store, or access relationship ⇒ no `.c4` edit required.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `apps/web-platform/infra/workspaces-luks.tf` declares
  `github_repository_environment.workspaces_luks_cutover` with `repository = "soleur"`,
  `environment = "workspaces-luks-cutover"`, and a non-empty `reviewers { users = [54279] }`.
- [ ] `terraform plan` (via `doppler run -p soleur -c prd_terraform --name-transformer
  tf-var -- terraform plan`, per the drift-runbook canonical invocation) shows the new
  `github_repository_environment.workspaces_luks_cutover` as a **`+create`** with a
  **non-empty** `reviewers.users`.
- [ ] `.github/workflows/apply-web-platform-infra.yml` contains
  `-target=github_repository_environment.workspaces_luks_cutover` inside the DEFAULT
  (push/`manual-rerun`) allow-list block, adjacent to the `inngest_cutover` target
  (line ~361). It is **absent** from the scoped `workspaces_luks_cutover` job's
  `-target` set (that job still `-target`s exactly the five workspaces_luks resources).
- [ ] `plugins/soleur/test/terraform-target-parity.test.ts` passes
  (`github_repository_environment.workspaces_luks_cutover` now covered by a `-target`).
- [ ] `tests/scripts/test-workspaces-luks-cutover-gate.sh` still passes — the scoped
  gate still permits **exactly** the five creates and aborts anything out-of-scope
  (T1 PASS, T8 out_of_scope ABORT), unchanged.
- [ ] The runbook precondition (`workspaces-luks-cutover-6604.md:19-21`) is reframed:
  the environment is **provisioned by the default allow-list apply** (not a manual
  operator step), with a note that the reviewer set must remain non-empty.
- [ ] PR body uses `Ref #6604` (NOT `Closes #6604`) — #6604 remains OPEN
  (`wg-use-closes-n-in-pr-body-not-title-to`; ops-remediation `Ref` variant).
- [ ] No cutover/freeze workflow is dispatched by this PR.

### Post-merge (operator / automated)
- [ ] The merge-triggered `apply-web-platform-infra.yml` default apply runs and
  creates the environment (automated — no operator step). **Automation:** feasible
  (default per-merge apply).
- [ ] Verify: `gh api repos/jikig-ai/soleur/environments/workspaces-luks-cutover`
  returns **200** with a **non-empty** required-reviewer set (verified by the apply +
  a `gh api` read, per `hr-no-dashboard-eyeball-pull-data-yourself`). **Automation:**
  feasible (`gh` CLI). This can ride `/soleur:ship` post-merge verification.

## Test Scenarios

1. **RED anchor:** With Phase 1 applied and Phase 2 not yet applied, run
   `terraform-target-parity.test.ts` → the "every managed resource has a -target line"
   test fails, listing `github_repository_environment.workspaces_luks_cutover`.
2. **GREEN:** With Phase 2 applied, the same test passes.
3. **Scoped-gate invariant preserved:** `test-workspaces-luks-cutover-gate.sh` T1
   (five-create PASS) and T8 (out-of-scope ABORT) unchanged.
4. **Plan shape:** `terraform plan` in the infra root shows exactly one added
   `github_repository_environment.workspaces_luks_cutover` `+create` with
   `reviewers.users = [54279]`.

## Non-Goals / Out of Scope

- Dispatching any cutover/freeze workflow (freeze AC21–AC30, 7-day soak, volume wipe)
  — all remain operator-dispatched, environment-gated steps under #6604.
- Closing #6604 (it stays OPEN as a follow-through).
- Adding `workspaces_luks_cutover` to `stripDispatchJobs` in the parity test, or adding
  a dedicated workspaces job↔gate exact-5 parity `describe` block mirroring git-data's
  (lines 1378–1413). The scoped exact-5 invariant is already enforced at dispatch by
  the gate's `out_of_scope` clause + `test-workspaces-luks-cutover-gate.sh` T8. This is
  a **candidate follow-up hardening**, not required by this fix. *(Optional; file a
  tracking issue only if deepen-plan/review deems it worth the coupling.)*
- Any change to the scoped `workspaces_luks_cutover` apply job or the five-resource
  allow-set.

## Domain Review

**Domains relevant:** Engineering (infra/security). Operations (runbook).

### Engineering
**Status:** reviewed (self-assessment; deepen-plan will run the precedent-diff + domain triad).
**Assessment:** Pure IaC wiring that mirrors an approved precedent
(`inngest_cutover`/ADR-100) 1:1. The load-bearing risk is placement (default block vs
scoped block); both the parity test (default coverage) and the gate `out_of_scope`
clause (scoped exactness) mechanically enforce correct placement. No new data path, no
host, no downtime.

### Operations
**Status:** reviewed.
**Assessment:** Runbook correction removes a false "manual operator precondition",
aligning with `hr-all-infrastructure-provisioning-servers`. No new operator burden;
the post-merge verification is a single `gh api` read, already how the runbook verifies
(dashboard-free).

### Product/UX Gate
Not relevant — no UI surface. NONE.

## GDPR / Compliance

No regulated-data surface touched (no schema, migration, auth flow, API route, or
`.sql`). The change adds a *safety gate protecting* sole-copy user data; it moves no
data and creates no processing activity. `gdpr-gate` skip — but note the underlying
data class is user source code, so `user-impact-reviewer` (already required by the
single-user-incident threshold) is the correct review-time lens.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, is `TBD`, or omits the
  threshold fails `deepen-plan` Phase 4.6.** This plan fills it (threshold =
  single-user incident).
- **Do not add the env `-target` to the scoped `workspaces_luks_cutover` job.** The
  sourced `workspaces_luks_cutover_gate` asserts the plan is EXACTLY the five
  volume/attachment/passphrase/secret/token creates; a sixth create makes
  `out_of_scope = 1` and ABORTS the freeze provision (proven by
  `test-workspaces-luks-cutover-gate.sh` T8). The env is created by the DEFAULT apply.
- **`stripDispatchJobs` does not strip `workspaces_luks_cutover`** — the scoped job's
  five `-target`s currently feed `allTargets` in the parity test, but they are all
  `OPERATOR_APPLIED_EXCLUSIONS`, so coverage holds either way. This is why the env's
  `-target` must live in the DEFAULT (non-stripped, push/`manual-rerun`) block: that
  block is the coverage anchor, and putting the env there both provisions it and
  satisfies `terraform-target-parity.test.ts:735`.
- **`Ref #6604`, never `Closes #6604`.** The remediation (environment provisioning)
  completes at the post-merge apply, and the freeze/soak/wipe stay open; auto-closing
  at merge would produce a false-resolved state (`wg-use-closes-n-in-pr-body-not-title`
  ops-remediation `Ref` variant).
- **The reviewer set must stay non-empty forever.** A future edit that empties
  `reviewers.users` silently re-opens DP-11 F8 (auto-approve). Terraform pins it to
  `[54279]`; the post-merge `gh api` read is the standing check.

## Files to Edit
- `apps/web-platform/infra/workspaces-luks.tf` — add `github_repository_environment.workspaces_luks_cutover`.
- `.github/workflows/apply-web-platform-infra.yml` — add the default-block `-target` (after line 360).
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` — reframe the precondition (lines 19–21).

## Files to Create
- None. (No new test file: the coupling is enforced by the existing generic
  `terraform-target-parity.test.ts` and `test-workspaces-luks-cutover-gate.sh`.)

## Open Code-Review Overlap
None checked at plan-write time (infra wiring, 3 files, no open code-review issues
identified for these paths). Deepen-plan may re-run the overlap query.
