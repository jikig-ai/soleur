---
title: "chore(flag-tooling): migrate team-workspace-invite off shared org-targeted to twi-orgs"
date: 2026-05-29
issue: 4617
branch: feat-one-shot-4617-twi-orgs-migration
type: ops-remediation
classification: ops-only-prod-write
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(flag-tooling): migrate `team-workspace-invite` off shared `org-targeted` to `twi-orgs` 🔧

## Overview

Scope-cut follow-up from #4581 PR-2 (#4612, MERGED). PR-2 introduced the per-feature
org-segment model (`<flag>-orgs`, ADR-043 §"Per-feature segment scoping") and moved
`byok-delegations` onto its own `byok-delegations-orgs` segment. `team-workspace-invite`
(twi) still rides the **legacy shared** `org-targeted` segment (Flagsmith segment id
`1130454`, members: jikigai `70a70ab0-…`, sibling `1a8045bf-…`).

This issue migrates twi onto its own `team-workspace-invite-orgs` segment, then drains and
retires the shared `org-targeted` segment, then flips ADR-043 from `superseded-in-part`
toward fully superseded. After this lands, **no feature references the shared segment** and
the per-(feature, org) granularity model from PR-2 is the sole per-org gate for all
org-targetable flags.

**This is an operator-execution + small-tooling chore, not a behavioral code change to the
app.** The eval-resolution path in `apps/web-platform/lib/feature-flags/server.ts` is
unchanged — twi already resolves through `getRuntimeFlag("team-workspace-invite", identity)`
with the `orgId` trait; which *segment* carries the ON override is transparent to the
consumer. The migration is observable only at the Flagsmith control plane.

## Premise Validation

- **#4581** (parent, "org-targetable runtime flags can't be cleanly provisioned/scoped"):
  `gh issue view 4581` → **CLOSED**. Held.
- **#4612 (PR-2)** ("per-feature segment org scoping (#4581 PR-2)"): `gh pr view 4612` →
  **MERGED**. Held. The per-feature-segment tooling this chore depends on is live on `main`.
- **#4616** ("eval-verify control-negative must poll until it settles"): **MERGED**. The
  control-negative settle-poll fix is in `flip.sh` `eval_until` — relevant because step 1's
  eval-verify of the control org depends on it (a freshly-created segment's non-member org
  can transiently read `enabled=true` for one edge-refresh window).
- **`flip.sh --org` path** (`plugins/soleur/skills/flag-set-role/scripts/flip.sh:382-518`):
  exists on `origin/main`, implements provision + membership-edit + eval-verify. Held.
- **`org-targeted` segment id `1130454` + org UUIDs**: cited in the issue body (sourced from
  PR-2 work). NOT verified against the live Flagsmith API at plan time (no management-API
  read from the planning sandbox). **Phase 0 re-reads live state via the management API
  before any mutation** — the plan does not freeze the membership/attachment shape from the
  issue body.

**Stale premise found:** the issue body asserts *"Tooling already supports this (the same
`flip.sh --org` path); this is operator execution + verification, not new code."* This is
**true for step 1 only**. See Research Reconciliation below — steps 2 and 3 (detach twi from
the shared `org-targeted` segment, then retire it) have **no existing tooling verb** and need
a decision (small tooling addition vs. documented one-off management-API path).

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase reality | Plan response |
|---|---|---|
| Step 1: `flip.sh team-workspace-invite prd on --org <jikigai>` provisions `team-workspace-invite-orgs` + ON override both envs + adds the org, eval-verify enabled. | **Confirmed.** `flip.sh:382-518` `--org` branch calls `provision_feature_segment` (segment-create-if-absent + ON override both envs, `:277-311`) then writes the `EQUAL orgId` condition + eval-verifies target ON / control OFF. | Step 1 is fully tooled. Run twice (once per member org), `--confirmed` after AskUserQuestion ack. |
| Step 2: "Remove twi's override from the shared `org-targeted` segment." | **No tooling verb exists.** `flip.sh --org` only mutates the per-feature `<flag>-orgs` segment's `conditions[]`; it never touches `org-targeted`. The `segment_ids_to_delete_overrides` payload field is hard-coded `[]` in both `flip_segment_in_env` branches (`:218`, `:221`) — there is no code path that detaches a feature-state override from a shared segment. | **Decision D1** (below): add a minimal, dry-run-gated detach path OR document a one-off management-API DELETE. The plan defaults to the tooling addition (idempotent, audited, eval-verified) so the operator never hand-edits Flagsmith — per `hr-exhaust-all-automated-options` and the ADR-038 "skill is the only approved mutation path" contract. |
| Step 3: "Once no feature references `org-targeted`, retire it; flip ADR-043 from `superseded-in-part` toward fully superseded." | `org-targeted` (id `1130454`) is a project-level segment; retiring = DELETE the segment via management API after confirming zero attached features in both envs. ADR-043 lines 3, 8-13 carry the `superseded-in-part` status + the "retained until twi migrated off it" caveat. | Step 3 = a guarded segment-DELETE (after a zero-attachment assertion read) + an ADR-043 doc edit. The doc edit is in-scope for this PR; the live DELETE is a post-merge operator action (Decision D2). |
| "byok got its own segment with no leak." | Confirmed — `byok-delegations-orgs` exists per PR-2; this chore does not touch byok. | No byok changes. byok is the regression-witness for "shared segment drained ≠ byok affected". |

## User-Brand Impact

**If this lands broken, the user experiences:** a member org (jikigai or the sibling) that
*should* have the team-workspace-invite feature loses it (twi evaluates OFF) because the
migration dropped the org from the new segment without the new override being live — OR a
non-member org gains twi access because the shared segment was retired while still attached.

**If this leaks, the user's workflow is exposed via:** `team-workspace-invite` gates the
multi-user workspace invite surface (co-member data category, ADR-038 / Article 30 PA-2). A
wrong-org enable exposes one org's workspace-invite surface to another org — the exact
shared-segment all-or-nothing blast radius this migration exists to eliminate.

**Brand-survival threshold:** `single-user incident` — inherited from #4581/PR-2's framing
(twi shares a tenant-boundary segment with byok; a mis-migration that re-pointed twi could
collaterally affect the org set). A single non-member org gaining twi access, or a single
member org silently losing it, is the failure this migration must make impossible to do
silently and detectable if it occurs. CPO sign-off required at plan time (see frontmatter
`requires_cpo_signoff: true`); `user-impact-reviewer` runs at review time.

## Decisions

### D1 — Step-2 detach: small tooling verb vs. one-off management-API path

The issue assumes step 2 is "operator execution, not new code"; it is not — no verb detaches
a feature from `org-targeted`. Two options:

- **D1-a (default, recommended): add `flip.sh --detach-shared` (or equivalent minimal mode).**
  An idempotent, dry-run-gated, WORM-audited path that publishes a new feature version with
  `segment_ids_to_delete_overrides: [<org-targeted-id>]` for twi in BOTH envs, then
  **eval-verifies** twi STILL resolves `enabled=true` for both member orgs (now served by
  `team-workspace-invite-orgs`) and `enabled=false` for a control org. Keeps the
  ADR-038 "skill is the only approved Flagsmith-mutation path" contract intact; no operator
  hand-edits. This is small (reuse `flip_segment_in_env`'s version-POST plumbing + the
  existing `eval_until` verify), but it IS new code — so the plan's lane is `cross-domain`
  and tests are required (RED before GREEN).
- **D1-b (fallback, only if D1-a is judged out-of-proportion at brainstorm/review):** document
  a single management-API call in a post-merge runbook with append-before audit + the same
  eval-verify as a manual checklist. Rejected as default because it reintroduces a hand-edit
  path the ADR explicitly forbids, and `hr-no-ssh-fallback-in-runbooks` / the operator-action
  automation-feasibility gate push toward the automatable path.

**This decision is the single most important brainstorm/deepen-plan input.** If D1-a, the PR
carries code + tests + docs. If D1-b, the PR is docs-only + a runbook and the live work is
all post-merge. The plan body is written for **D1-a** and flags D1-b as the documented
alternative.

### D2 — Live mutations are post-merge operator actions, gated by ordering

Steps 1→2→3 are **live prd Flagsmith mutations** and MUST run in order (provision new segment
+ verify BEFORE detaching the shared one; detach + verify zero-attachment BEFORE retiring the
shared segment). They are executed post-merge using the merged tooling, with eval-verify
between each step. The PR itself ships the tooling (D1-a) + the ADR-043 doc edit; it does not
flip live state at merge. Issue closure is post-merge (`Ref #4617` in PR body, not `Closes` —
per the ops-remediation Sharp Edge).

### D3 — Idempotency + ordering safety

Every live step is idempotent and re-runnable (provision converges; detach is a no-op if
already detached; retire is a no-op / clear error if already gone). eval-verify after each
step is the gate: a step that does not verify halts the sequence (exit 3, fail-loud).

## Implementation Phases

> Lane note: written for **D1-a** (tooling addition). If brainstorm/deepen-plan selects D1-b,
> collapse Phases 1-2 into a runbook-only deliverable and keep Phases 0, 3-4.

### Phase 0 — Live-state read (no writes)

1. Resolve and record live Flagsmith state via the management API (read-only):
   - `org-targeted` segment id (confirm `1130454`) + its current member orgIds.
   - Which features carry a feature-state override on `org-targeted` in **each** env
     (dev `90722`, prd `90721`) — confirm twi is attached and enumerate any OTHER feature
     still attached (step 3 retirement requires zero attachments; if byok or anything else is
     still attached, the issue's step-3 precondition is not yet met → scope step 3 out).
   - Confirm `team-workspace-invite-orgs` does/does not yet exist.
2. Confirm `FLAG_TEAM_WORKSPACE_INVITE` value in prd Doppler (fallback-fidelity context: a
   per-org-only flag falls back to this on a Flagsmith outage; record the value, do not change).
3. Record member org UUIDs (jikigai `70a70ab0-…`, sibling `1a8045bf-…`) from the live
   `org-targeted` rule, NOT from the issue body, for use as step-1 inputs + step-2 control.

### Phase 1 — Tooling (D1-a): add the shared-segment detach verb (RED→GREEN)

`plugins/soleur/skills/flag-set-role/scripts/flip.sh`

1. **RED:** extend `plugins/soleur/test/flag-org-scoping-pr2.test.sh` (or a sibling
   `flag-detach-shared.test.sh` if the existing file is at capacity) with stub-Flagsmith
   tests asserting: (a) `--detach-shared` builds a version-POST body with
   `segment_ids_to_delete_overrides:[<org-targeted-id>]` and empty create/update arrays;
   (b) it runs in BOTH envs; (c) it appends a WORM audit row before the mutation; (d) it
   eval-verifies twi `enabled=true` for a member org and `enabled=false` for control AFTER
   detach; (e) `--dry-run` writes nothing; (f) it is idempotent (no-op when no override
   exists). Confirm RED (verb absent).
2. **GREEN:** add the minimal `--detach-shared` mode. Reuse `fs_api`, `read_feature_segment_id`
   (to find/confirm the override row), the version-POST plumbing (publish a version with
   `segment_ids_to_delete_overrides`), `audit_append` (append-before-flip), and `eval_until`
   (the post-detach verify). The shared-segment id is resolved by name (`org-targeted`) via
   `resolve_segment_id`, not hard-coded. Honor `--dry-run` / `--confirmed`. Exit codes match
   the existing contract (0/2/3/4).
3. Run the shell-test suite via `bash scripts/test-all.sh scripts` (verified at plan time:
   CI `test-scripts` job at `.github/workflows/ci.yml:360` runs exactly this; the shell tests
   are `bash`-based `.test.sh`, no `bun`/`vitest`). This catches orphan-suite guards across
   the scripts group.

### Phase 2 — SKILL.md + cross-reference docs

`plugins/soleur/skills/flag-set-role/SKILL.md`

1. Document `--detach-shared` under Arguments + the org-targeting procedure + Exit codes +
   Sharp edges (note: detach is the migration verb, not a routine flip; eval-verify proves the
   feature is still served by its own segment after detach).
2. Run the skill-description budget check if the `description:` line changes (it likely does
   NOT — this is a new flag on an existing skill, body-only). Skip if no `description:` edit.

### Phase 3 — ADR-043 doc edit (in-PR)

`knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md`

1. Edit the doc to reflect that twi-migration tooling now exists and the shared `org-targeted`
   segment is slated for retirement post-merge. Do NOT prematurely flip the status to fully
   superseded in this PR — the live segment still exists until the post-merge DELETE succeeds.
   Use a `[Updated 2026-05-29]` marker. The status flip to fully-superseded is a one-line
   follow-up edit committed AFTER the post-merge retirement is verified (or staged as a
   post-merge doc commit gated on the DELETE).
   - **Awk/region note:** if any AC greps a doc region, verify the region markers don't
     self-match (per the awk-range Sharp Edge).
2. Sweep sibling docs that describe twi as riding `org-targeted` for accuracy: `ADR-038`
   line 139/159, `apps/web-platform/lib/feature-flags/server.ts:25` comment,
   `knowledge-base/legal/compliance-posture.md` line 69/109. Decide fold-in vs. follow-up per
   doc (most are historical/audit prose; a `[Updated]` note may suffice — do not rewrite audit
   history). Enumerate each in `Files to Edit` with an explicit disposition.

### Phase 4 — Live migration (post-merge operator, ordered, eval-verified)

Executed with the MERGED tooling. Each step gates the next on eval-verify success.

1. **Provision + add member orgs** (tooled, step 1):
   `flip.sh team-workspace-invite prd on --org 70a70ab0-… --control-org 1a8045bf-… --confirmed`
   then `flip.sh team-workspace-invite prd on --org 1a8045bf-… --control-org 70a70ab0-… --confirmed`.
   (Each run provisions `team-workspace-invite-orgs` if absent + ON override both envs + adds
   the org + eval-verifies target ON / control OFF. Use each *other* member as the control so
   the leak check is against a real sibling, not the synthetic default — per the flip.sh
   control-org warning.) After both: eval-verify BOTH orgs resolve twi `enabled=true`.
2. **Detach twi from `org-targeted`** (tooled via D1-a, step 2):
   `flip.sh team-workspace-invite prd on --detach-shared --org <member> --dry-run` (preview),
   AskUserQuestion ack, then `--confirmed`. **A single `--detach-shared` run eval-verifies only
   the one `--org` member.** twi has TWO member orgs, so run `--detach-shared --org <member>`
   **once per member**: the first run performs the (one-time, both-env) detach AND eval-verifies
   member #1; the second run (`--org <member2>`) is an idempotent no-op detach that eval-verifies
   member #2 STILL resolves `enabled=true` (now served by `team-workspace-invite-orgs`). The
   control org (synthetic non-member default — correct here, since both real orgs are members)
   must settle to `enabled=false` on every run.
3. **Retire `org-targeted`** (step 3): re-read attachments (Phase 0 read repeated); assert
   **zero** features attached to `org-targeted` in both envs; if zero → DELETE the segment via
   management API (tooled if D1-a adds a guarded retire mode, else a guarded one-off with the
   zero-attachment assertion as the gate). Then commit the ADR-043 status flip to
   fully-superseded.
4. `gh issue close 4617` after step 3 verifies.

## Acceptance Criteria

### Pre-merge (PR)

- [x] (D1-a) `flip.sh --detach-shared` exists; its version-POST body sets
      `segment_ids_to_delete_overrides:[<resolved org-targeted id>]` with empty create/update
      arrays, runs in both envs, appends a WORM audit row before mutating, and eval-verifies
      twi `enabled=true` for a member org + `enabled=false` for control AFTER detach.
      *Verify: the new test asserts the request body shape + the post-detach eval calls — not
      just "verb exists".* → `plugins/soleur/test/flag-detach-shared.test.sh` tests 2a-2e.
- [x] `--detach-shared --dry-run` writes nothing (stub records zero `secrets set` / zero
      mutating POST/PUT); `--detach-shared` is idempotent (no-op when no override present).
      → tests 5 (dry-run) + 6 (idempotent no-op).
- [x] `bash scripts/test-all.sh scripts` passes (shell-test group; orphan-suite guards
      included). *Verified at plan time: CI `test-scripts` job runs this at ci.yml:360.* → 81/81 suites.
- [x] SKILL.md documents `--detach-shared` (Arguments, Procedure, Exit codes, Sharp edges).
- [x] ADR-043 carries a `[Updated 2026-05-29]` note that twi-migration tooling exists and the
      shared segment is slated for retirement; status NOT yet flipped to fully-superseded.
- [x] Sibling-doc dispositions recorded: `server.ts:25` comment **folded in** (was already
      stale for byok); ADR-038 §139/159 + `compliance-posture.md` §69/109 **deferred** to the
      post-retirement doc-sweep (accurate today — twi still rides `org-targeted` pre-migration;
      become stale only after the post-merge live flip).
- [ ] PR body uses `Ref #4617` (NOT `Closes`) — closure is post-merge (ops-remediation class). *(ship phase)*
- [x] CPO sign-off recorded (frontmatter `requires_cpo_signoff: true`; `user-impact-reviewer`
      runs at the review phase per the `single-user incident` threshold).

### Post-merge (operator)

- [ ] `team-workspace-invite-orgs` segment exists with both member orgs; twi eval-verifies
      `enabled=true` for jikigai AND sibling (production `getIdentityFlags` path), control org
      `enabled=false`. *Automation: tooled via `flip.sh --org` eval-verify.*
- [ ] twi detached from `org-targeted` in both envs; post-detach eval-verify: both member orgs
      STILL `enabled=true`, control `enabled=false`. *Automation: tooled via `--detach-shared`.*
- [ ] `org-targeted` has zero attached features in both envs, then is DELETED.
      *Automation: zero-attachment read + DELETE via management API.*
- [ ] `byok-delegations` eval-verify unchanged: still `enabled` only for its own segment's
      orgs (regression witness that draining the shared segment did not touch byok).
      *Automation: `flip.sh`-style eval read for byok's org.*
- [ ] ADR-043 status flipped to fully-superseded (post-retirement doc commit); `gh issue
      close 4617`.

## Test Scenarios

- twi resolves `enabled=true` for both member orgs after step 1 (before detach) — proves the
  new segment is live before the shared one is touched.
- twi resolves `enabled=true` for both member orgs after step 2 (after detach) — proves the
  new segment is now the sole gate.
- A control (non-member) org resolves twi `enabled=false` at every step — no leak.
- `--detach-shared` is a no-op (clean exit, no version published) when twi has no override on
  `org-targeted` (idempotent re-run).
- byok eval unchanged across all steps.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO) — inherited from the
#4581/PR-2 user-brand-critical triad; this is the drain-the-shared-segment tail of that work.

### Engineering (CTO)
**Status:** to be assessed at brainstorm/deepen-plan (Domain Review Gate).
**Assessment (plan-author pre-read):** the central call is D1 (tooling verb vs. one-off). The
`segment_ids_to_delete_overrides` plumbing already exists in the version-POST body shape; the
detach verb is a thin reuse of existing helpers + the existing eval-verify. Ordering safety
(provision-verify → detach-verify → retire) is the load-bearing correctness property.

### Legal (CLO)
**Status:** to be assessed.
**Assessment (plan-author pre-read):** WORM audit must cover the detach (a twi enablement-shape
mutation), append-before-flip, route through the SECURITY DEFINER RPC (same `audit_append`
path). Retiring the shared segment is the elimination of the cross-tenant blast radius CLO
flagged in #4581 — net compliance improvement; no new data category.

### Product/UX Gate
**Tier:** none — no user-facing page/flow/component. The migration is control-plane only; the
twi feature surface is unchanged. (server.ts resolution path untouched.)

## Open Code-Review Overlap

None. (No open `code-review` issue body references `flip.sh` or `ADR-043`.)

## Infrastructure (IaC)

Not applicable. Flagsmith segments are managed via the Flagsmith Management API through the
existing `flag-set-role` skill, not Terraform (Flagsmith is a managed SaaS control plane; the
project has no IaC root for Flagsmith segment definitions, and the ADR-038 contract designates
the skill as the sole mutation path). No new server, secret, vendor, cron, or persistent
process is introduced.

## Observability

```yaml
liveness_signal:
  what: "twi eval-resolution for member orgs (getIdentityFlags edge path) returns enabled=true"
  cadence: "on each migration step (manual eval-verify) + the existing Inngest cron membership-health probe (apps/web-platform/server/inngest/functions/cron-membership-health.ts)"
  alert_target: "operator terminal (eval-verify exit 3 halts the sequence, fail-loud)"
  configured_in: "plugins/soleur/skills/flag-set-role/scripts/flip.sh (eval_until / eval_flag_enabled)"
error_reporting:
  destination: "operator terminal (non-zero exit) + WORM flag_flip_audit row (migration 071) via audit_flag_flip RPC"
  fail_loud: true
failure_modes:
  - mode: "member org loses twi (dropped from new segment before override live)"
    detection: "step-1 / step-2 eval-verify target org enabled=false → exit 3"
    alert_route: "operator terminal halt; no further step runs"
  - mode: "non-member org gains twi (shared segment retired while still attached)"
    detection: "Phase 0 / step-3 zero-attachment read returns non-zero attachments → retire aborted; control-org eval-verify enabled=true → exit 3"
    alert_route: "operator terminal halt"
  - mode: "audit row not written for the detach"
    detection: "audit_append non-2xx → exit 4 before any Flagsmith mutation (append-before-flip)"
    alert_route: "operator terminal; flip aborted"
logs:
  where: "flag_flip_audit table (Supabase, migration 071, 7-yr WORM retention) + operator terminal stdout"
  retention: "7 years (WORM audit); terminal ephemeral"
discoverability_test:
  command: "bash plugins/soleur/skills/flag-set-role/scripts/flip.sh team-workspace-invite prd on --org <member-uuid> --dry-run"
  expected_output: "prints current/proposed team-workspace-invite-orgs membership matrix, exits 0 with no mutation (NO ssh)"
```

## Research Insights (deepen-plan, 2026-05-29)

### Precedent-Diff Gate (4.4) — `--detach-shared` version-POST is a thin reuse, not a novel pattern

The detach mode (D1-a) is NOT novel plumbing. The `segment_ids_to_delete_overrides` field is
**already present** in every version-POST body the codebase builds today (always `[]`):

- `plugins/soleur/skills/flag-set-role/scripts/flip.sh:218` (first-time create branch)
- `plugins/soleur/skills/flag-set-role/scripts/flip.sh:221` (existing-override update branch)
- `plugins/soleur/skills/flag-create/scripts/create.sh:130`

D1-a's only change: populate that array with the resolved `org-targeted` segment id for twi,
posted to the **same** endpoint `flip.sh:225` (`POST .../environments/{env_id}/features/{feature_id}/versions/`,
`publish_immediately:true`). Reuse `read_feature_segment_id` to confirm the override row exists
(skip → no-op idempotency), `audit_append` for append-before-flip, and `eval_until` for the
post-detach verify. **Canonical precedent matches the proposed shape — no novel risk.** The
Flagsmith API contract for `segment_ids_to_delete_overrides` is NOT independently doc-verified
here; the GREEN step (Phase 1) must confirm against a live/staging Flagsmith env that publishing
a version with the override's segment id in that array actually removes the override (the
field-name is established in-repo, but its delete-by-segment-id semantic should be exercised,
not assumed — per the live-probe Sharp Edge for external query layers).

### Verify-the-Negative (4.45) — "resolution path unchanged" confirmed

The plan asserts the migration is transparent to the app consumer. Confirmed:
`isTeamWorkspaceInviteEnabled` (`apps/web-platform/lib/feature-flags/server.ts:158-160`) calls
`getRuntimeFlag("team-workspace-invite", identity)` with no segment-name reference — which
*segment* carries the ON override is invisible to the consumer. The migration changes only the
Flagsmith control plane; no app code edit is required for the eval path. (server.ts:25 carries a
*comment* naming `org-targeted` — a doc-disposition item in Files to Edit, not a behavioral
dependency.)

### Scheduled-work pattern (4.4) — no new scheduled job

This chore introduces no new recurring task. The membership-health liveness probe already exists
as an Inngest cron (`apps/web-platform/server/inngest/functions/cron-membership-health.ts`,
canonical per ADR-033) — referenced as an existing liveness signal, not added.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This section is filled.)
- **The issue body's "tooling already supports this" is true for step 1 only.** Steps 2-3 need
  the D1 decision. Do not start /work assuming a single `flip.sh --org` invocation closes the
  issue.
- **Ordering is load-bearing.** Provision + eval-verify the new segment BEFORE detaching the
  shared one; verify zero attachments BEFORE retiring the shared segment. A reordering silently
  drops twi for a member org (between detach and provision) or leaves a leak window.
- **Use a real sibling org as `--control-org`**, not the synthetic default — the flip.sh
  warning fires otherwise, and the synthetic default only proves "not globally ON", not "no
  leak to the org sharing the shared segment".
- **Do not hard-code segment ids.** Resolve `org-targeted` / `team-workspace-invite-orgs` by
  name via `resolve_segment_id`; the issue body's `1130454` is for human cross-reference, not a
  literal in code (verify against the Phase 0 live read).
- The eval-verify control-negative MUST poll until it settles (#4616) — a freshly created
  segment's non-member org can transiently read `enabled=true` for one edge-refresh window.
- ADR-043 status flip to fully-superseded happens AFTER the live retirement, not in the
  pre-merge PR — the segment still exists until the post-merge DELETE.
- `Ref #4617`, not `Closes #4617` — closure is post-merge after step 3 (ops-remediation Sharp
  Edge / `wg-use-closes-n-in-pr-body-not-title-to`).

## Files to Edit

- `plugins/soleur/skills/flag-set-role/scripts/flip.sh` — add `--detach-shared` mode (D1-a).
- `plugins/soleur/test/flag-org-scoping-pr2.test.sh` *(or new `flag-detach-shared.test.sh`)* —
  RED tests for the detach verb.
- `plugins/soleur/skills/flag-set-role/SKILL.md` — document `--detach-shared`.
- `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md` —
  `[Updated 2026-05-29]` note (pre-merge) + status flip (post-retirement).
- *(disposition TBD)* `knowledge-base/engineering/architecture/decisions/ADR-038-team-workspace-multi-user-organizations-and-workspace-members.md` (lines 139, 159 reference twi on `org-targeted`).
- *(disposition TBD)* `apps/web-platform/lib/feature-flags/server.ts:25` comment.
- *(disposition TBD)* `knowledge-base/legal/compliance-posture.md` (lines 69, 109 reference the shared segment).

## Files to Create

- *(conditional, D1-a only)* `plugins/soleur/test/flag-detach-shared.test.sh` — if the existing
  PR-2 test file is at capacity; otherwise extend in place.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| D1-b: one-off management-API DELETE for step 2 (no tooling verb) | Reintroduces a hand-edit path ADR-038 forbids; documented as the fallback only. |
| Flip ADR-043 to fully-superseded in the pre-merge PR | The live segment still exists until post-merge DELETE; status would lie. |
| Use the synthetic default `--control-org` | Only proves "not globally ON", not "no leak to the real sibling sharing the shared segment". |
| `Closes #4617` in PR body | Auto-closes at merge before the post-merge live migration runs → false-resolved. |
