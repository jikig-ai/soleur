---
title: "fix(sentry): adopt the last two sentry_issue_alert rules as sentry_alert — the alert-rule API is gone (410), so plan_pr is red on main and every Sentry-infra PR"
type: fix
date: 2026-09-21
slug: fix-sentry-alert-410-removed-api-migration
branch: feat-one-shot-8451-sentry-alert-410-migration
issue: 8451
closes: [8451]
refs: [8282]  # closed by apply-sentry-infra.yml's success step with the run URL, not at merge
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(sentry): adopt the last two `sentry_issue_alert` rules as `sentry_alert` (410 "This API no longer exists")

## Overview

The spec has no valid `lane:`, so it defaulted to cross-domain (TR2 fail-closed).

`apply-sentry-infra.yml` runs a full-root `terraform plan` in two places: the required PR check
`plan_pr`, and the post-merge `apply` job. Both are red on main and on every PR that touches the
Sentry root. Two resources, `sentry_issue_alert.auth_per_user_loop` and
`sentry_issue_alert.sandbox_startup_failure` (`apps/web-platform/infra/sentry/issue-alerts.tf`),
still refresh through Sentry's legacy alert-rule endpoint `projects/{org}/{proj}/rules/{id}/`, and
it now answers `410 {"detail":"This API no longer exists."}` on every attempt.

This plan does two things:

1. It adopts both **live** rules at `sentry_alert` addresses using the in-tree adoption mechanism:
   `removed { lifecycle { destroy = false } }` plus `import {}`. Nothing is destroyed or recreated,
   and ids and history survive. The pinned provider cannot express their trigger natively, so the
   trigger rides in `legacy_trigger_conditions`, and each block carries
   `lifecycle { ignore_changes = all }`. That makes an **Update** structurally impossible. The
   other writes that could reach these rules are Create (after a UI delete, a rename, or
   `-replace`) and an Update after someone narrows `ignore_changes`. Both are refused before
   apply by the extended `sentry-issue-alert-create-tripwire.sh` (Guard 2). See
   *Why `ignore_changes = all`*.
2. It deletes the brownout retry ladder. Once no `sentry_issue_alert` remains, the ladder has no
   target. In its place, a plan failure carrying a 410 is reported on the **first** attempt. The
   report names the failing resource addresses and says the job does not retry. It states only
   what was measured: a 410 that persists across runs is a removal, and one that clears on re-run
   was a brownout.

Closes #8451. #8282 has the same root cause (verified from its run log below). It is referenced, not closed, by this PR: it is the apply-failure filer's own issue, and `apply-sentry-infra.yml`'s "Close the apply-failure tracking issue (success)" step (`:1590`) closes it with the green run's URL as proof. A `Closes` at merge would close it before the adoption apply is verified. If that apply then failed, the filer, which searches open issues only, would open a new issue and split the history (spec-flow review #6).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured) | Plan response |
|---|---|---|
| "Migrate both to `sentry_alert`" as a straight migration | The pinned `jianyuan/sentry` **v0.15.7** has no `event_unique_user_frequency_count` in `sentry_alert.trigger_conditions`. The upstream fix (PR #953, commit `0deba79`, 2026-09-09) is **unreleased**: the latest release is still v0.15.7 (`gh release list -R jianyuan/terraform-provider-sentry`, 2026-09-21). #7985 tracks this. | Adopt now through the provider's `legacy_trigger_conditions` escape hatch, with `ignore_changes = all`. Re-scope #7985 to the later native conversion. |
| "use `moved` blocks" | A cross-type `moved` (`sentry_issue_alert` → `sentry_alert`) needs the provider to implement `ResourceWithMoveState`. At v0.15.7, `grep -rn "MoveState" internal/` returns nothing; `resource_alert_gen.go:31` implements only `ResourceWithImportState`. | Use `removed{}` + `import{}`, the in-tree pattern proven by `git_data_boot_warning` (#7988). |
| The 410 body "now reads 'This API no longer exists'", which proves removal and not a brownout | `versions.tf` records the **same** body during the 2026-07-17 brownout. The body text cannot discriminate. What does discriminate is persistence: every plan since 2026-09-18 took 410 on all 3 attempts (#8282 run 35333341158: attempts 10:17:06Z, 10:18:16Z, 10:20:56Z). | Do not build a body-text classifier. Delete the ladder, which becomes unreachable, and word the first-attempt 410 message honestly. |
| #8451 quotes the body as `{"message": …}` | The run log shows `{"detail":"This API no longer exists."}` | Any fixture or grep keys on `got status 410` / `no longer exists`, never on the JSON key. |
| "29 sibling rules are `sentry_alert`" | 30 `resource "sentry_alert"` blocks; `alert-reference.json` has 30 keys, set-equal to their names | Counts after this PR: 32 `sentry_alert`, 0 `sentry_issue_alert`. The reference stays at 30 (see projection). |
| #8282 "probably the same root cause" | Its run log shows exactly the two addresses, `Unable to read, got status 410: {"detail":"This API no longer exists."}`, three attempts, `outcome=exhausted`. Plan `failure`, apply `skipped`. | Same root cause. `Ref #8282` in the PR body: the workflow's success step closes it with evidence (see Overview). |

## Why `ignore_changes = all` (the load-bearing decision)

The v0.15.7 `resource_alert_impl.go` behaves as follows:

- **Read (`Fill`, `:844`ff):** a trigger type outside the modeled set drops to `default:`, which
  appends only the **type string** to `legacy_trigger_conditions`. The
  `{interval, value}` comparison is discarded. It does **not** error, so an import succeeds.
- **Write (`getTriggerConditions`, `:737`ff; used by both `getCreateJSONRequestBody` and
  `getUpdateJSONRequestBody`):** every legacy entry is re-sent with `comparison: true`. Any Create
  or Update on these two rules would therefore replace "> 2 distinct tenants in 1h" and
  "> 3 distinct users in 5m" with a boolean. The paging threshold would be destroyed silently.
  `terraform plan` cannot show that, because the value never existed in config
  (`knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-provider-cannot-express-frequency-triggers.md`).

That write hazard is why #7650 Phase 2 treated these two rules as a hard blocker. The hazard lives
entirely in the **write** path, and each way into it is closed:

| Write path | Closed by |
|---|---|
| Update from a config edit | `ignore_changes = all`: structurally, no Update is ever planned |
| Update after someone narrows `ignore_changes` | extended tripwire (Guard 2): refuses any `sentry_alert` row with `update` whose `change.after.legacy_trigger_conditions` carries a type in the projection's `excluded` set |
| Create after a Sentry-UI delete (refresh drops it from state), a label rename (destroy+create under `[ack-destroy]`), or `-replace` / taint | the same tripwire, on `create`. `sentry-create-gate.sh` alone is **not** enough: it accepts any create whose block appears in the PR diff, and a rename adds one |
| The adoption itself | a no-op import is a read. The adoption assert's 0-change row check reds if an update ever appears on the adoption plan |

(Arch review P1-2 / DHH P1: an earlier draft of this plan called the whole write "structurally
impossible". That holds for Update only.)

The tripwire keys on the **legacy** field, not on the trigger type. After the #7985 native
conversion, the provider writes the true `{interval, value}`, so an Update there is safe. It must
not be blocked.

**Cost, stated plainly:** until a provider release carries `0deba79` **and** the #7985 conversion
lands, Terraform owns these two rules' **existence** (the address, plus the destroy gate) and
nothing else. That includes the detector binding. `monitor_ids` is ignored, and
`sentry-monitor-binding-gate.sh` reads planned values, which are now the refreshed live state, so
it cannot enforce the binding (arch P2-6). Threshold, filters, actions, `enabled` and binding are
all unowned during the freeze. Each block therefore carries an explicit
`# EDITS TO THIS BLOCK ARE INERT until #7985 (ignore_changes = all)` comment, so a future edit
that plans "0 changes" is not mistaken for an applied change. That is already true of `auth_per_user_loop` today: its `ignore_changes` covers
`conditions_v2`, `filters_v2`, `actions_v2`, `environment` and `frequency`. It is a regression for
`sandbox_startup_failure` only on paper, because today that rule cannot be read at all. #7985 is
re-scoped to remove the freeze.

## Research Insights

**Premise Validation (Phase 0.6).**

- #8451 is OPEN.
- #8282 is OPEN. Its run 35333341158 is the same failure: the two addresses, 410
  `This API no longer exists`, all 3 attempts. It closes here.
- PR #8442 is MERGED (2026-09-20). It is a predecessor, not a collision.
- #7650 is CLOSED (by #7821).
- #7985 is OPEN. It is the tracker for the provider-release block; its probe is
  `scripts/followthroughs/sentry-provider-release-7985.sh`.
- Both cited addresses exist on the branch tip (`issue-alerts.tf:137`, `:345`).
- **Stale premises:** "migrate to `sentry_alert`" as a straight migration is blocked, which
  #7985 already recorded. "The body proves removal" does not hold. Both are reshaped above.

**Live-state verification (read-only, 2026-09-21).** Command:
`GET /api/0/organizations/jikigai-eu/workflows/{566671,669246}/` using Doppler `soleur/prd_terraform`
`SENTRY_IAC_AUTH_TOKEN`, token on stdin. Both returned HTTP 200 and match the 2026-09-09 committed
capture exactly:

| id | name | enabled | env | detectorIds | frequency | trigger | action filter |
|---|---|---|---|---|---|---|---|
| 566671 | auth-per-user-loop | true | null | ["1213799"] | 30 | `event_unique_user_frequency_count` {value:3, interval:"5m"}, logicType all | all: tagged_event feature eq auth → email issue_owners / ActiveMembers |
| 669246 | sandbox-startup-failure | true | null | ["1213799"] | 22 | `event_unique_user_frequency_count` {value:2, interval:"1h"}, logicType all | all: feature eq agent-sandbox, op eq sdk-startup → email issue_owners / ActiveMembers |

The ids are **workflow** ids, not rule ids. Per `issue-alerts.tf` §"THE ID IS A WORKFLOW ID", that is
what `sentry_alert` imports. Both are members of
`knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json`,
which is the capture `sentry-adoption-plan-assert.sh` cross-checks import ids against. All 31
captured workflows bind detector 1213799, so `sentry-monitor-binding-gate.sh` holds.

**Provider / Terraform evidence (plan-time, not changelog):**

- `terraform validate` on a scratch copy of the root, with both blocks replaced by the proposed
  bodies below, reports `Success! The configuration is valid.` (Terraform 1.9.8 local; CI pins
  1.10.5; `jianyuan/sentry` 0.15.7 from the committed lockfile). This covers the sharp edge that
  config-phase validation can reject an `ignore_changes` body.
- Terraform v1.10.5 `internal/terraform/node_resource_plan_orphan.go:141` has
  `if !n.skipRefresh && !forget { … n.refresh(…) }`. A `removed{}`-forgotten orphan is **not
  refreshed**, so the forget itself never touches the 410 endpoint. This is what makes the
  adoption plan pass today.
- Import ID format: `ImportState2Part("organization", "id")` (`resource_alert_gen.go:1326`), i.e.
  `"${var.sentry_org}/<workflow-id>"`. That matches the in-tree `git_data_boot_warning` import.
- `trigger_conditions` is Optional+Computed and `legacy_trigger_conditions` is Optional
  (`resource_alert_gen.go:92`, `:1188`).

**Prior adoption still in tree.** The `git_data_boot_warning` `removed{}` + `import{}` pair
(`issue-alerts.tf:236-246`) has **already applied**: run 35333341158 refreshes
`sentry_alert.git_data_boot_warning [id=804298]`. So it contributes zero forget/import rows, and
the adoption plan carries exactly **2 + 2**.

**Relevant files:**

- `apps/web-platform/infra/sentry/issue-alerts.tf`: header (`:1-120`), the two blocks (`:137`, `:345`), the adoption precedent (`:204-295`).
- `.github/workflows/apply-sentry-infra.yml` (104,750 bytes): retry ladder at plan_pr (`plan_backoff=(60 150)` through `set -e`, ~`:305-395`) and at apply (~`:860-950`); `sentry-adoption-plan-assert.sh` call sites pass expected `1` at `:443` and `:1015`; destroy/forget gate; AC17 (`:1258`ff).
- `tests/scripts/lib/sentry-alert-projection.jq`: `excluded` (`:81`), the live-side `in_scope` (`:189`), and the TF side `project_tf`, which selects **every** `sentry_alert` and never reads `legacy_trigger_conditions`.
- `scripts/sentry-adoption-plan-assert.sh`: exactly N forgets + N imports, the bijection, 0 add/change/destroy per managed row, unique import ids, ids ∈ capture.
- `scripts/sentry-issue-alert-create-tripwire.sh`, `scripts/sentry-monitor-binding-gate.sh`, `scripts/sentry-forget-import-bijection.sh`.
- `tests/scripts/test-sentry-brownout-retry.sh`: extracts **exactly 2** ladder sites from the workflow by anchors `          plan_backoff=(` … `          set -e\n`. **It is an orphan.** `scripts/test-all.sh` does not glob `tests/scripts/test-*.sh` (its own comment near `run_suite "tests/scripts/preapply-entrypoint-gate"` says an unregistered suite "gates nothing"), and `grep -n brownout scripts/test-all.sh` returns nothing. The ladder's test never ran in CI. The replacement suite MUST be registered with a `run_suite` line next to the other `tests/scripts/sentry-*` suites.
- AC17 (`apply-sentry-infra.yml` "AC17 — terraform state list matches the declared .tf") **derives** `exp_alert`/`exp_issue` from the `.tf`, and `tests/scripts/test-sentry-ac17-derived-counts.sh` case R4 already covers "zero `sentry_issue_alert` declared and zero in state → green". No change is needed.
- `tests/scripts/test-sentry-alert-live-fidelity.sh:314` asserts `comparing 28 declared rule`. That count comes from the suite's own fixture, not from the `.tf`, so it is unaffected.
- `scripts/followthroughs/sentry-brownout-frequency-7650.sh` (the brownout frequency meter) is carried by no open follow-through tracker. I scanned every open `follow-through` issue body; only #7985's probe is enrolled. Once the ladder is gone it would read zero markers, so it is deleted in this PR, along with its `scripts/lint-shell-trace-credential-refusal.baseline.txt:65` line (DHH and CTO reviews).

**Institutional learnings applied:**

- `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`: validate the proposed body (done, green).
- `2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-…md`: the 512,000-byte hard limit; `plugins/soleur/test/workflow-file-size.test.ts` caps at 490,000. This plan **shrinks** the file.
- `integration-issues/2026-08-19-a-vendor-brownout-is-not-a-flake-…md` and the `sentry-issue-alert-410-transient-wedge` post-mortem: never infer "restored" from one clean read.
- `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`: forgets count toward the destroy gate, so the merge needs `[ack-destroy]` (both prior adoptions carried it: `a866e1f29`, `72ebe67b7`).
- `2026-09-18/specs … phase2-provider-cannot-express-frequency-triggers.md`: the write-path hazard, neutralized here by `ignore_changes = all`.

**Property List (Phase 0.6b).**

- P1: `plan_pr` and the post-merge `apply` plan succeed on the first attempt against today's Sentry. No refresh touches the removed endpoint.
- P2: the two live paging rules keep their ids, thresholds, filters, actions and detector binding through the adoption. Nothing is destroyed, recreated or rewritten.
- P3: Terraform still owns the two rules' **existence**. Deleting a block is a gated destroy, not a silent orphan. Content is explicitly not owned during the freeze.
- P4: while the provider cannot represent the trigger, no Terraform run can send `comparison: true` for these rules. That covers Update, Create and replace, and it must hold **after** the adoption as well as during it.
- P5: a plan failure caused by a 410 is reported on the first attempt, with the failing addresses and without a multi-minute retry first. The message states only what was measured.
- P6: the alert-reference gate runs again and stays consistent. The TF and live projections agree on which rules are in scope, and keep agreeing through the #7985 native conversion.
- P7: the #7985 exit cannot be skipped. Its tracker stays open until the freeze is actually removed.

**Cut List.**

- Cross-type `moved` → P2 → not implementable: no `MoveState` in v0.15.7. Replaced by `removed{}`/`import{}`.
- Body-text "removal vs brownout" classifier inside the ladder → P5 → the body is identical in both cases, and the ladder is unreachable once 0 `sentry_issue_alert` remain. The ladder is deleted instead of taught.
- A **new** "no create/update on a legacy-trigger rule" gate → P4 → the existing `sentry-issue-alert-create-tripwire.sh` already runs at both sites before apply, and its current invariant becomes trivially true after this PR. It is **extended**, not duplicated (arch P1-2).
- A new handler test file plus a `test-all.sh` registration → P5 → static assertions in the already-registered `tests/scripts/test-sentry-full-root-apply.sh` cover it; that suite already parses this workflow's `run:` blocks (simplicity review).
- A byte-delta AC → the file is 104,750 of 490,000 bytes and `workflow-file-size.test.ts` already enforces the cap. The existing size test running green is enough.
- Building the provider from upstream `main` (`0deba79`) as a filesystem mirror → P1/P2 → supply-chain cost (unsigned binary, lockfile hash churn) for a fix `legacy_trigger_conditions` already delivers.
- Retiring the `git_data_boot_warning` and new `removed{}`/`import{}` pairs → not needed for any property. It is the standard follow-up (#7826 precedent), folded into #7985.
- Deleting `apps/web-platform/scripts/configure-sentry-alerts.sh` → no property here, and it is referenced by 7 files. Folded into #7985.
- Copying the Alternatives table into ADR-031 → it would duplicate this plan. The amendment links the plan instead.
- A dated line in `versions.tf` → its brownout paragraphs are dated history that stays true. Untouched.

**Value measurement (0.6c):** the "~4 minutes per failing run" saving is not the justification.
The justification is P1 (a required check is red on main). No saving is claimed.

## Proposed Solution

### Terraform (`apps/web-platform/infra/sentry/issue-alerts.tf`)

Replace each `resource "sentry_issue_alert"` block with a `removed{}` / `import{}` / `resource "sentry_alert"`
triple. It takes the **same label** (the forget↔import bijection pairs by label) and **faithful
values** read from live. This body is validated:

```hcl
removed {
  from = sentry_issue_alert.sandbox_startup_failure
  lifecycle {
    destroy = false
  }
}

import {
  to = sentry_alert.sandbox_startup_failure
  id = "${var.sentry_org}/669246" # WORKFLOW id (GET /workflows/), not the /rules/ id
}

# EDITS TO THIS BLOCK ARE INERT until #7985 (ignore_changes = all). Terraform owns this rule's
# EXISTENCE only. Change its content in a #7985 conversion, never by editing these values.
resource "sentry_alert" "sandbox_startup_failure" {
  organization      = var.sentry_org
  name              = "sandbox-startup-failure"
  enabled           = true
  frequency_minutes = 22
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  # Live trigger: event_unique_user_frequency_count {value = 2, interval = "1h"} — STRICT `>`,
  # fires at >=3 distinct tenants (#6429). v0.15.7 cannot model it, so it is carried by TYPE only.
  trigger_conditions        = []
  legacy_trigger_conditions = ["event_unique_user_frequency_count"]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "agent-sandbox" } },
        { tagged_event = { key = "op", match = "eq", value = "sdk-startup" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  # ALL, not [environment]: any Create/Update re-sends every legacy trigger with
  # `comparison: true` (resource_alert_impl.go getTriggerConditions), destroying the threshold.
  # Create/replace are refused by scripts/sentry-issue-alert-create-tripwire.sh.
  # Remove only together with the native-trigger conversion (#7985).
  lifecycle {
    ignore_changes = all
  }
}
```

`auth_per_user_loop` uses the same shape: id `566671`, `frequency_minutes = 30`, one filter
`feature eq auth`, and the same action. Its trigger comment carries `{value = 3, interval = "5m"}`.

Two things to keep:

- Keep the existing #6429 rationale comment ("WHY value = 2 AND NOT 3"). Retarget its wording
  from the `conditions_v2` attribute to the live comparison.
- Keep the N=1 accepted-risk note on the IssueOwners→ActiveMembers fallthrough.

**Header.** Prefer deleting numeric split claims over updating them. AC17 already derives counts
from the `.tf`, so nothing needs the literal (DHH P2-6). Where a count must be stated, state it
once. The "A CLEAN PLAN IS NOT EVIDENCE THE DEPRECATION LIFTED" and "TWO remain" paragraphs get a
dated superseded note: "2026-09-21 (#8451): the family is removed (persistent 410); no resource
reads it; the last two are adopted as `sentry_alert` under an `ignore_changes = all` freeze until
#7985". This follows the file's own convention.

### Projection (`tests/scripts/lib/sentry-alert-projection.jq`)

`project_tf` must drop a `sentry_alert` whose trigger types intersect `excluded`, **in either
representation**:

- native: the keys of `trigger_conditions[]` elements carrying a non-null value;
- legacy: the strings in `legacy_trigger_conditions`.

That is the TF-side mirror of the live side's `in_scope`, which excludes by trigger **type**
whatever the representation. Keying on the legacy field alone would break the symmetry the day
#7985's provider bump makes Read populate the native field (arch P2-4).

Without the exclusion, the plan projects 32 rules against live's 30:

- `sentry-alert-reference-gate.sh` reds against the committed 30-key `alert-reference.json`.
- The post-apply probe reports the two as missing.

With it, `alert-reference.json` is **unchanged** (30 keys).

Implementation constraints:

- **Filter BEFORE `canon | map(tf_rule)`.** Under `ignore_changes = all`, planned values are the
  imported state. `tf_rule` errors if `trigger_conditions` is not an array, and a type-only rule
  may render it `null` (simplicity H1). The fixture must cover `trigger_conditions: null`.
- Use the **same `excluded` list** (one definition, not a copy) and the same `any(...)`
  membership idiom as `in_scope`. Do **not** use `list | index(.key)` inside a pipe; the file's
  comment at `:130` warns about it.
- A `legacy_trigger_conditions` type that is **not** in `excluded` is an `error("unmapped legacy
  trigger type …")`, not a silent projection with no triggers. That matches the module's
  "every floor is an error" contract (arch P2-5).
- The jq comment states that on the TF side the field comes from the provider's Read, i.e.
  refreshed state, not config.

### Tripwire (`scripts/sentry-issue-alert-create-tripwire.sh`): extended, not duplicated

It already runs at plan_pr and apply before `terraform apply`, fails closed on unreadable or
empty plans, and is unit-tested by the registered `tests/scripts/test-sentry-alert-adoption-guards.sh`.
Add one refusal next to the existing `sentry_issue_alert` create check. Refuse any
`resource_changes[]` row that meets all three conditions:

- `.type == "sentry_alert"`;
- `.change.actions` contains `create` or `update`, which includes a replace (`["delete","create"]`
  / `["create","delete"]`);
- `.change.after.legacy_trigger_conditions` shares a type with the projection's `excluded` set.

Read that set from the same jq module rather than re-listing it, e.g.
`jq -n -L tests/scripts/lib 'include "sentry-alert-projection"; excluded'` if the module is made
includable. Otherwise keep a single literal and add a parity assertion in the suite. The message
names the address and says why: the provider would re-send the trigger with `comparison: true`
and zero the paging threshold, and the remedy is #7985's native conversion. Import rows
(`["no-op"]` + `importing`) are not refused.

Update the header's "exactly TWO `sentry_issue_alert`" and the `:88` message to the new truth,
zero.

### Workflow (`.github/workflows/apply-sentry-infra.yml`), kept lean

1. **Both ladder sites.** Replace everything from `plan_backoff=(60 150)` through the handler's
   `set -e` with a single plan invocation plus a handler.
   - Keep `set +e`, `rm -f /tmp/sentry-plan.out`, `tee /tmp/sentry-plan.out`,
     `rc=${PIPESTATUS[0]}` and `exit $rc`. The `rm -f` stays: without it a failed `tee` leaves
     the previous run's 410 in place for the grep.
   - Precede the block with a fixed anchor comment, `# sentry-plan-410-handler (#8451)`, at both
     sites. Guard 3's static assertions key on it (the old `plan_backoff=(` anchor is deleted, and
     `set +e`/`set -e` occur 5 times each).
   - On `rc != 0` with `got status 410` present:
     - extract the failing addresses from the `with <addr>,` lines that follow each `Error:`
       stanza;
     - emit one `::error::` stating only what was measured: `terraform plan failed (exit $rc) on
       its only attempt: Sentry returned HTTP 410 for <addresses>. This job does not retry. A 410
       that persists across runs means the endpoint was removed (as the legacy alert-rule API was,
       #8451): move the named resource off it. One that clears on a re-run was a brownout.`
     - The message must pass `scripts/lint-diagnosis-claims.sh` (a required check): no unmeasured
       causal claim. Add a `# MEASURED-BY:` marker only if the lint asks for one.
   - Otherwise keep the existing `::error::terraform plan failed (exit $rc)`.
   - Drop the `brownout_only` function, the `SOLEUR_SENTRY_BROWNOUT` markers, and the ladder's
     comment block. Leave a ≤3-line comment citing #8451 for why no retry exists.
2. **Adoption-assert call sites (`:443`, `:1015`).** Change the expected count from `1` to `2`.
   Keep the phase34 capture argument (it contains 566671 and 669246).
3. **Prose.** Sweep only lines this change falsifies: ladder references, and "29" / "two
   survivors" counts. Named sites:
   - the apply-failure filer's `### If the failure was a Sentry 410` paragraph (`:1509-1510`),
     which says the plan step "retries for exactly this". Rewrite it to the same measured-only
     wording as the handler (spec-flow #7);
   - the apply site's "AC2/AC10 — the adoption is EXACTLY an adoption: 27 forgets" comment (~`:1010`);
   - `.github/workflows/scheduled-sentry-alert-drift.yml:15-20`;
   - `apps/web-platform/scripts/assert-byok-rules-exist.sh:48-54`, which describes
     `auth-per-user-loop`'s `sentry_issue_alert` `ignore_changes`;
   - `tests/scripts/test-sentry-alert-adoption-guards.sh`'s A7 comment ("the two are still editable"). Run `git grep -il brownout -- ':!knowledge-base'` as the census. Only
   `.github/workflows/scheduled-sentry-alert-drift.yml:18-19` ("with none of
   apply-sentry-infra.yml's brownout retry") becomes false outside this file, so fix that one.
   The others (`sentry-alert-live-fidelity.sh:164`, `assert-byok-rules-exist.sh:113-122`,
   `cron-sentry-alert-drift.ts:23`) are dated history that stays true. Leave them.

### Frozen-rule live pin (Guard 4): restores what the freeze takes away

Before the 410, a UI edit to `sandbox_startup_failure` (`ignore_changes = [environment]` only)
surfaced as a planned update. After this PR both rules are frozen **and** excluded from both
projection sides, so nothing would notice either rule being disabled, re-thresholded or stripped
of its action. The Kieran, architecture and spec-flow reviews and the CPO all flagged this, and
for `sandbox_startup_failure` it is a regression. Close it inside the existing live probe, not in
a new one:

- `scripts/sentry-alert-live-fidelity.sh` already fetches every live workflow. It runs post-apply
  in the apply job and daily in `scheduled-sentry-alert-drift.yml`.
- Add a pass for **every** live workflow whose trigger type is in `excluded` (a census, not a name
  list). Each one must be `enabled == true`, have `detectorIds == ["1213799"]`, have trigger
  comparisons equal to the committed capture's for the same name, and carry at least one `email`
  action.
- Expected values come from
  `knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json`,
  by name, never from literals in the script. An excluded-type workflow with **no** capture entry
  is an error (UNMANAGED-FROZEN): a new rule of this type must not slip past the pin.
- Report through the probe's existing verdict path, so the drift workflow files it like any other
  finding.

Add a static half in the op-contract vitest suite. For both frozen blocks, the `.tf` literals
(`name`, `frequency_minutes`, each `tagged_event` key/match/value, and the email action) must
equal the capture's entry for the same name. That catches a stale or edited frozen block, which
would otherwise plan "0 changes" and look applied (spec-flow #4). The capture is the anchor: it is
committed, immutable, and any edit to it shows in the diff.

### Follow-through and dead code

- `scripts/followthroughs/sentry-provider-release-7985.sh`: **change what PASS means** (CTO P1).
  Today it exits 0 as soon as any release carries `0deba79`. The sweeper would then close #7985
  before anyone converts. The sweeper runs probes from a repo checkout
  (`scheduled-followthrough-sweeper.yml` `actions/checkout`), so the probe can read the tree. New
  order:
  1. If `apps/web-platform/infra/sentry/issue-alerts.tf` carries **no** `legacy_trigger_conditions`
     and **no** `ignore_changes = all` on a `sentry_alert`, print `PASS: converted` and exit 0.
  2. Else, if a release carries the fix, print `FAIL: unblocked — provider vX contains 0deba79;
     bump versions.tf, convert both rules to native trigger_conditions, drop ignore_changes = all
     (plan must show 0 changes)` and exit 1.
  3. Else, the existing FAIL/TRANSIENT branches.

  The converted check comes first because `PINNED` is a literal, and after a bump the release
  comparison is no longer meaningful.
- **#7985 atomic exit checklist.** The ship phase writes it into #7985 with `gh issue edit`
  (title and body, not only a comment) and cites it from the ADR amendment. It must land as ONE
  PR (spec-flow #3):
  1. Bump `versions.tf` to a release containing `0deba79`.
  2. Convert both blocks to native `trigger_conditions = [{ event_unique_user_frequency_count = {…} }]`,
     drop `legacy_trigger_conditions` and `ignore_changes = all`, and require the plan to show 0 changes.
  3. Remove `event_unique_user_frequency_count` from the projection's `excluded`, map the kind on
     both sides with a shape-parity row, and regenerate `alert-reference.json` to 32 keys.
  4. Delete the TF-side exclusion's legacy branch, and Guard 4's pass for this type.
  5. Retire the `removed{}`/`import{}` pairs, including `git_data_boot_warning`'s.
  6. Retire `configure-sentry-alerts.sh`.
  7. Check that the new provider still ships `sentry_issue_alert` in its schema while any
     `removed{ from = sentry_issue_alert.* }` remains. If it does not, step 5 must precede the bump.
- `scripts/followthroughs/sentry-brownout-frequency-7650.sh`: `git rm`, and remove its line from
  `scripts/lint-shell-trace-credential-refusal.baseline.txt:65`. It meters the markers this PR
  deletes and is enrolled in no open tracker.
- `tests/scripts/test-sentry-brownout-retry.sh`: `git rm`. It was an **orphan**, registered in no
  runner, so it never gated CI.

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `tests/scripts/lib/sentry-alert-projection.jq`
- `tests/scripts/test-sentry-alert-reference-gate.sh`: Guard 1 rows. Its `_rule` builder hard-codes `legacy_trigger_conditions: null`, so add a parameterized variant.
- `scripts/sentry-issue-alert-create-tripwire.sh`: Guard 2, plus header and message wording.
- `tests/scripts/test-sentry-alert-adoption-guards.sh`: Guard 2 rows.
- `.github/workflows/apply-sentry-infra.yml`
- `tests/scripts/test-sentry-full-root-apply.sh`: Guard 3 static assertions over both plan sites.
- `.github/workflows/scheduled-sentry-alert-drift.yml`: the comment at `:18-19` only.
- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`: repoint the `sandbox-startup-failure` section (`:381`ff), per Kieran #3:
  - Put the #6429 "WHY value = 2" rationale **directly above** `resource "sentry_alert" "sandbox_startup_failure"`, after `import{}`. `scopeResourceWithComment` walks back only over the unbroken `#` block above the header, so rationale placed above `removed{}` (the `git_data_boot_warning` layout) reds the `BaseEventFrequencyCondition` / strict assertions.
  - Repoint the "pins the no-SSH page target" assertion from `IssueOwners` to `issue_owners` / `ActiveMembers`.
  - Assert, for **both** blocks: `legacy_trigger_conditions` carries `event_unique_user_frequency_count`, `ignore_changes = all`, and the INERT comment.
  - Add Guard 4's static half: the `.tf` literals equal the capture entry.
  - Rewrite `_scopeHeader`'s two-type comment.
  - Drop any assertion of the form "the capture's comparison is {value:2}". It checks an immutable file against itself.
- `apps/web-platform/infra/sentry/README.md`: `:5`, `:11`, `:23-24`.
- `scripts/followthroughs/sentry-provider-release-7985.sh`
- `scripts/sentry-alert-live-fidelity.sh`: Guard 4 frozen-rule pin.
- `tests/scripts/test-sentry-alert-live-fidelity.sh`: Guard 4 rows. Its `comparing 28 declared rule` literal is fixture-derived; re-check it only if fixtures change.
- `apps/web-platform/scripts/assert-byok-rules-exist.sh`: comment `:48-54` only.
- `scripts/lint-shell-trace-credential-refusal.baseline.txt`: drop the 7650 meter line.
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`: amendment.

## Files to Delete

- `tests/scripts/test-sentry-brownout-retry.sh`
- `scripts/followthroughs/sentry-brownout-frequency-7650.sh`

## Files to Create

None.

## Implementation Phases

1. **RED first.** Write the Guard 1 rows (reference-gate suite), the Guard 2 rows (adoption-guards suite), the Guard 3 static assertions (full-root suite) and the Guard 4 rows (live-fidelity suite and op-contract vitest) before touching the code under test. Confirm each is red for the right reason.
2. **Projection + tripwire + live pin.** The jq exclusion (before `tf_rule`), the tripwire refusal, and the fidelity-script pass.
3. **Terraform.** The two triples, the INERT comments, the header supersession note, and `terraform validate`.
4. **Workflow.** Both handler sites with the anchor comment, adoption-assert `1`→`2` at both sites, the filer paragraph, and the named prose sites. Run `actionlint`, `bash scripts/lint-diagnosis-claims.sh`, and `bun test plugins/soleur/test/workflow-file-size.test.ts`.
5. **Consumers and dead code.** Op-contract test, README, drift-workflow comment, assert-byok comment, the 7985 probe, and the ADR-031 amendment. `git rm` the orphan test and the 7650 meter (plus its baseline line).
6. **Verify locally:**
   - the census greps (see ACs);
   - `bash scripts/test-all.sh` for the touched suites: `sentry-alert-reference-gate`, `sentry-alert-adoption-guards`, `sentry-full-root-apply`, `sentry-alert-live-fidelity`, `sentry-create-gate`, `sentry-ac17-derived-counts`, `destroy-guard-counter-sentry`, `destroy-guard-sentry-scope-guard`;
   - `apps/web-platform` vitest for the op-contract file;
   - `bash plugins/soleur/test/c4-count-parity.test.sh`.
7. **PR.**
   - Before pushing the final commit, record the two workflows' live `dateUpdated`. Use the same read-only GET as Research Insights and put the values in the PR body.
   - A branch commit **body** (not subject) carries a line exactly `[ack-destroy]`, followed by the sentence "state-only forgets of `sentry_issue_alert.auth_per_user_loop` and `sentry_issue_alert.sandbox_startup_failure`; nothing destroyed".
   - The PR body has `Closes #8451` and `Ref #8282`.
   - `plan_pr` must pass on this branch **without admin bypass**.
8. **Tracker hygiene (ship-phase agent actions, not operator steps):**
   - `gh issue edit 7985` with the atomic exit checklist, and a new title such as "sentry: convert the 2 frozen legacy-trigger sentry_alert rules to native triggers once the provider ships 0deba79";
   - file one issue for the orphan-suite lint gap: `scripts/lint-orphan-test-suites.sh` scans `*.test.sh` only, not `tests/scripts/test-*.sh` (CTO #4). Include re-evaluation criteria and a milestone per `wg-when-deferring-a-capability-create-a`.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Cross-type `moved {}` | Rejected | Provider v0.15.7 implements no `MoveState`. Terraform refuses cross-type moves without it. |
| Wait for a provider release with `0deba79` | Rejected | Unbounded third-party timeline, while a required check is red on main. #7985 stays open for the native conversion. |
| Build provider from upstream `main` via `dev_overrides` / filesystem mirror in CI | Rejected | Unsigned binary on the prod paging path; lockfile/hash churn; a second provider-distribution mechanism in one root. |
| `removed { destroy = false }` only (stop managing the two) | Rejected (DHH P1 considered it) | It would cut the jq exclusion and the count bump, but it loses P3. The operator's ask was a migration that keeps IaC ownership. And Guard 2 plus Guard 4 would still be needed, because a later re-declaration re-enters the same Create hazard. |
| `sentry_alert` with a native lifecycle trigger + `event_frequency_count` action filter | Rejected | Semantics change: `phase2-provider-cannot-express-frequency-triggers.md` §"Can the 13 be RESTRUCTURED". No provider trigger means "every event". |
| Narrow `ignore_changes = [environment]` + the tripwire alone | Rejected | Any block edit would then plan an Update that only the tripwire stands in front of. `ignore_changes = all` removes Update structurally, and the tripwire covers Create and replace. The two together leave no single point of failure on the threshold. |
| Keep the retry ladder, teach it "no longer exists" = removal | Rejected | The body is identical during brownouts (`versions.tf`, 2026-07-17), and the ladder's arming condition (`with sentry_issue_alert.` + 410) is unreachable once 0 remain. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a fleet-wide agent-sandbox startup outage (the #5873 P0 class) or an auth redirect loop with **no page to the founder**. The adoption could zero or boolean-ize `sandbox-startup-failure`'s ">2 distinct tenants / 1h" or `auth-per-user-loop`'s ">3 distinct users / 5m" threshold, or destroy the rule outright.
- **If this leaks, the user's workflow is exposed via:** no new exposure vector. No new data leaves any boundary. Both rules' payloads stay pseudonymized (`userIdHash`) and the email fallthrough recipients are unchanged (IssueOwners → ActiveMembers).
- **Brand-survival threshold:** `single-user incident`. This is inherited from the #7650 migration lineage (these are paging rules for user-facing outages). CPO sign-off was obtained at plan time (below), and `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "apply-sentry-infra.yml plan_pr (required PR check) and the post-merge apply job, both of which run the full-root terraform plan that this change unwedges"
  cadence: "per PR touching infra/sentry and per push to main"
  alert_target: "red required check on the PR; on main, the job's if-failure filer opens a ci/apply-sentry-infra p1 issue (the #8282 channel)"
  configured_in: ".github/workflows/apply-sentry-infra.yml"
error_reporting:
  destination: "GitHub Actions ::error:: annotations on the plan step, plus the ci/apply-sentry-infra issue filer on main"
  fail_loud: "::error::terraform plan failed (exit N): Sentry answered 410 … endpoint removed — on the first attempt"
failure_modes:
  - mode: "a resource still reads a removed Sentry endpoint (410)"
    detection: "plan step greps got status 410 on first failure and emits the removal ::error::; job red"
    alert_route: "PR check red / ci/apply-sentry-infra issue on main"
  - mode: "adoption plan is not exactly 2 forgets + 2 imports with 0 add/change/destroy"
    detection: "scripts/sentry-adoption-plan-assert.sh at plan_pr and at apply (expected 2)"
    alert_route: "job red before apply; nothing written"
  - mode: "a threshold-rewriting write (create, update or replace) is planned for a legacy-trigger sentry_alert"
    detection: "scripts/sentry-issue-alert-create-tripwire.sh refuses the plan at plan_pr and at apply, before terraform apply (Guard 2); Update is also structurally absent under ignore_changes = all"
    alert_route: "PR check red / apply job red before any write; the ci/apply-sentry-infra issue filer on main"
  - mode: "a frozen rule is disabled, re-thresholded, rebound or stripped of its action in the Sentry UI"
    detection: "scripts/sentry-alert-live-fidelity.sh frozen-rule pin against the committed capture (Guard 4), post-apply and daily"
    alert_route: "post-apply probe failure / scheduled-sentry-alert-drift.yml filed issue"
  - mode: "TF and live fidelity projections disagree on rule scope"
    detection: "scripts/sentry-alert-reference-gate.sh at plan_pr; post-apply live probe"
    alert_route: "PR check red / post-apply probe failure"
logs:
  where: "GitHub Actions run logs for apply-sentry-infra.yml"
  retention: "GitHub default Actions log retention (90 days)"
discoverability_test:
  command: "gh run list --workflow apply-sentry-infra.yml --branch main --limit 1 --json conclusion --jq '.[0].conclusion'"
  expected_output: "success"
  credentials_required: "gh read token for jikig-ai/soleur Actions — the property (main's Sentry plan is green) lives only in GitHub Actions run state; no unauthenticated endpoint exposes it"
```

## Encryption Posture

This plan introduces **no** persistent store and **no** new connection. The existing Terraform
state backend (R2) and the existing runner → Sentry API connection are unchanged. The import
reads over the same provider connection every sibling `sentry_alert` refresh already uses. The
one connection the change exercises is recorded here for completeness.

```yaml
at_rest: []   # no store introduced; Terraform state (R2 backend) is unchanged by this plan
in_transit:
  - connection: "GitHub Actions runner (terraform + jianyuan/sentry provider) -> Sentry org API https://<org>.sentry.io/api/"
    enforced_at: "apps/web-platform/infra/sentry/main.tf provider block (base_url comment: org-subdomain https base URL)"
    tls: "HTTPS, TLS 1.2+ (Go net/http default client in the provider)"
    cert_verification: on
    does_not_defend: "a leaked SENTRY_IAC_AUTH_TOKEN repo secret: TLS protects the channel, not the bearer credential, which can read and write every alert rule in the org"
    disclosed_as: not-publicly-claimed
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-031** (`knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`)
with `Amendment (2026-09-21, #8451)`. Status note: "adopting until #7985". It records:

- The legacy alert-rule family is **removed**: a persistent 410 on every plan since 2026-09-18.
- The last two rules are adopted as `sentry_alert` with `legacy_trigger_conditions` +
  `ignore_changes = all`. This reverses the Phase 2 "hard blocker" reading. Terraform owns
  existence plus the destroy gate only.
- The write hazard is **enforced**, not assumed:
  - `ignore_changes = all` removes Update;
  - `scripts/sentry-issue-alert-create-tripwire.sh` refuses Create, Update and replace on
    legacy-excluded rows before apply;
  - the live pin in `scripts/sentry-alert-live-fidelity.sh` detects content drift.

  Per AP-021, prose is not the enforcement.
- The brownout retry is removed.
- The exit is #7985's atomic checklist. The amendment links it rather than copying it.

Mark the 2026-08-19 (#7590) "deprecated with brownouts" amendment and the 2026-09-04 (#7650
Phase 2) "hard blocker" amendment `> **Superseded 2026-09-21 (#8451):** …`, using the ADR's
existing convention (`:536`), so the ADR does not carry three contradictory readings (arch P2-8).
Link this plan for the rejected alternatives; do not copy the table.

### C4 views

No C4 change. I read all three model files (`model.c4`, `views.c4`, `spec.c4`) for this change's actors, systems and relationships:

- **External systems:** Sentry (`sentry`, `model.c4:407`) and GitHub Actions. Both are already modeled.
- **Human actors:** the founder, paged through `sentry`. Already modeled.
- **Containers / data stores:** none touched. Terraform state is already R2.
- **Access relationships:** unchanged. `sentry -> founder` paging and `github -> sentry` apply.

`model.c4:409` describes the Sentry-as-IaC plane without an alert-rule count, and no element
description is falsified. `plugins/soleur/test/c4-count-parity.test.sh` must still run green,
because the cardinality check is that gate's job, not reasoning about actors.

### Sequencing

The ADR amendment lands in this PR.

## Guard Contract

### Guard 1 — projection scope symmetry

**Property.** A `sentry_alert` is outside the TF-side fidelity projection exactly when the same rule is outside the live side. That is: one of its trigger types, native or legacy, is in `excluded`. A legacy type outside `excluded` is an error, never a silent under-projection.

**Assembly.** `tests/scripts/lib/sentry-alert-projection.jq` is the single chokepoint. The TF side (`project_tf`) is consumed by `scripts/sentry-alert-reference-gate.sh` at plan_pr and by the apply job's expected-reference step. The live side (`project_live` via `in_scope`) is consumed by `scripts/sentry-alert-live-fidelity.sh` post-apply and daily. Both key on the one `excluded` definition. A consumer projecting `sentry_alert` rows outside this module would be a second site; the census grep `git grep -n 'select(.type == "sentry_alert")'` finds it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the TF-side exclusion. A plan fixture with 30 normal rows + 2 legacy-`event_unique_user_frequency_count` rows then projects 32 names against the 30-key reference | RED |
| 2 | Dispatch: point the exclusion at an empty literal instead of `excluded` | RED |
| 3 | Second member / native form: a compliant legacy row **plus** a second row carrying the excluded type in **native** `trigger_conditions` (the post-#7985 shape). Both must be excluded | RED if only the legacy row is dropped |
| 4 | Precondition holds, property fails: a row whose `legacy_trigger_conditions` is `["issue_resolution_change"]` (not in `excluded`) | must ERROR (jq exit 5), RED if it projects |
| 5 | Move the exclusion after `map(tf_rule)` while the legacy fixture carries `trigger_conditions: null` | RED (jq error) |
| 6 | Harness must-PASS: the non-canonical fixture from row 1, against the 30-key reference | must PASS |

### Guard 2 — no threshold-destroying write reaches apply

**Property.** No plan that creates, updates or replaces a `sentry_alert` whose after-state carries a legacy trigger type in `excluded` passes the pre-apply gates, at either site.

**Assembly.** `scripts/sentry-issue-alert-create-tripwire.sh` is the single refusal. It is called at plan_pr and at apply, and both run before `terraform apply`. Its population is **every** `resource_changes[]` row (a census over the plan), not the two addresses. The excluded set is read from, or parity-pinned to, the projection's `excluded`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plan fixture: `sentry_alert.sandbox_startup_failure` with actions `["update"]` and after-legacy `["event_unique_user_frequency_count"]` | RED |
| 2 | Dispatch: a plan with zero `resource_changes` rows | RED (the existing floor) |
| 3 | Second member: a compliant no-op row first, then a **second** legacy row with `["create"]` | RED |
| 4 | Replace: `["delete","create"]` on a legacy row | RED |
| 5 | Precondition holds, property safe: an import row (`["no-op"]` + `importing`) carrying legacy, and an `update` on a native-trigger row (the post-#7985 shape) | must PASS both |
| 6 | Harness: a tripwire stub that always exits 0 must make rows 1, 3 and 4 RED in the suite | RED |

### Guard 3 — single-attempt 410 handler at both plan sites

**Property.** At both plan sites, `terraform plan` is invoked exactly once with no loop or sleep. The block preserves `rc` through `exit $rc`, clears the output file before the plan, and names the failing addresses in its 410 branch.

**Assembly.** The two `run:` blocks carrying the anchor `# sentry-plan-410-handler (#8451)` in `.github/workflows/apply-sentry-infra.yml`. Static assertions live in the registered `tests/scripts/test-sentry-full-root-apply.sh`, which already parses this workflow. They count anchors (exactly 2), and each slice runs from the anchor to the next `          set -e`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `exit $rc` → `exit 0` at either site | RED |
| 2 | Dispatch: delete one anchor, or add a third | RED (count ≠ 2) |
| 3 | Second member: the apply-site slice loses its `got status 410` branch while plan_pr keeps it | RED |
| 4 | Reintroduce `while`/`sleep`/a second `terraform plan` in either slice | RED |
| 5 | Remove `rm -f /tmp/sentry-plan.out` from either slice | RED |
| 6 | Harness must-PASS: the real workflow, unmodified | must PASS |

### Guard 4 — frozen-rule live pin

**Property.** Every live workflow whose trigger type is in `excluded` matches the committed capture for its name. It must be enabled, bound to the expected detector, have equal trigger comparisons, and carry an email action. An excluded-type workflow absent from the capture is a finding. The frozen `.tf` blocks' literals equal the capture.

**Assembly.** The live half is `scripts/sentry-alert-live-fidelity.sh`, over its full live fetch (a census of excluded-type workflows, not a name list), run post-apply and daily. The static half is the op-contract vitest over both frozen blocks. Both anchor on `phase34-live-workflows-capture-2026-09-09.json`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Live fixture: `sandbox-startup-failure` with `comparison: true` | RED |
| 2 | Dispatch: a live fixture with zero excluded-type workflows while the capture has two | RED ("compared nothing") |
| 3 | Second member: `auth-per-user-loop` correct, then `sandbox-startup-failure` with `enabled: false` | RED |
| 4 | An excluded-type live workflow named `new-frozen-rule`, absent from the capture | RED |
| 5 | Static half: edit `frequency_minutes = 22` → `10` in the frozen block | RED |
| 6 | Harness must-PASS: a live fixture byte-equal to the capture entries | must PASS |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/sentry/issue-alerts.tf` declares zero `resource "sentry_issue_alert"` blocks (`grep -c '^resource "sentry_issue_alert"'` → 0) and 32 `resource "sentry_alert"` blocks.
- [ ] Each new block:
  - is paired with `removed{ lifecycle{ destroy = false } }` under the same label;
  - has `import { id = "${var.sentry_org}/566671" }` or `"/669246"`;
  - sets `legacy_trigger_conditions = ["event_unique_user_frequency_count"]`;
  - sets `lifecycle { ignore_changes = all }`;
  - carries the INERT comment.

  Guard 4's static half proves the literals equal the capture, and it is green.
- [ ] `terraform validate` in `apps/web-platform/infra/sentry` is green.
- [ ] `plan_pr` on this PR is **green without admin bypass**. Its log shows both `sentry_alert` addresses "will be imported" with no attribute changes, and `adoption plan assert: PASS (2 forget(s), 2 import(s), 0 add / 0 change / 0 destroy …)`. Assert on that PASS line and the plan-JSON counts, not on the literal `Plan:` summary text.
- [ ] `sentry-alert-reference-gate.sh` runs and passes. `alert-reference.json` is unchanged (30 keys; `git diff --quiet origin/main -- apps/web-platform/infra/sentry/alert-reference.json`).
- [ ] Guards 1-4: every mutation-matrix row was demonstrated RED (or PASS where marked) during Phase 1. The suites are green on the final tree, and each runs from `scripts/test-all.sh` or the vitest `unit` project.
- [ ] `grep -nE 'plan_backoff|brownout_only|SOLEUR_SENTRY_BROWNOUT|retries for exactly this' .github/workflows/apply-sentry-infra.yml` returns nothing.
- [ ] `tests/scripts/test-sentry-brownout-retry.sh` and `scripts/followthroughs/sentry-brownout-frequency-7650.sh` are deleted, and no reference to either remains (`git grep -n 'test-sentry-brownout-retry\|sentry-brownout-frequency-7650' -- ':!knowledge-base'` returns nothing).
- [ ] `bash scripts/lint-diagnosis-claims.sh`, `actionlint`, and `plugins/soleur/test/workflow-file-size.test.ts` pass.
- [ ] Census: every hit of `git grep -n 'sentry_issue_alert\|auth_per_user_loop\|sandbox_startup_failure' -- ':!knowledge-base'` falls into one of these categories, each listed in the PR body:
  - (a) a synthetic test fixture;
  - (b) the `removed{ from = sentry_issue_alert.* }` lines;
  - (c) the tripwire's type check;
  - (d) dated history prose;
  - (e) a **gate type literal that must keep recognising the family on the adoption plan**. Do NOT touch these: `sentry-forget-import-bijection.sh` `startswith("sentry_issue_alert.")`, `tests/scripts/lib/destroy-guard-filter-sentry.jq`, `test-destroy-guard-sentry-scope-guard.sh` `COVERED_TYPES`, AC17's `sentry_(issue_)?alert` regex, and the adoption-assert messages (Kieran #4).
- [ ] ADR-031 carries `Amendment (2026-09-21, #8451)` and the two superseded markers. `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] A branch commit body carries a line exactly `[ack-destroy]` with the scope sentence, and `sentry-destroy-required` is green.
- [ ] The PR body has `Closes #8451` and `Ref #8282` on separate lines (not in the title). It also records the two live `dateUpdated` values taken before merge.

### Post-merge (automated, agent-run)

- [ ] **Merge ordering.** No other PR touching `apps/web-platform/infra/sentry/**` merges until this PR's push run of `apply-sentry-infra.yml` concludes `success`. Until the adoption applies, any other Sentry PR's `plan_pr` plans the same 2 forgets and would demand an `[ack-destroy]` that is not its own (spec-flow #2).
- [ ] The push run concludes `success`. Its apply log shows:
  - 2 imports and 2 forgets;
  - the adoption assert PASS at the apply site;
  - AC17 reporting `32 sentry_alert and 0 sentry_issue_alert`;
  - the post-apply probe green, including Guard 4's pass.

  #8282 is then closed by the workflow's success step with the run URL. Verify with `gh issue view 8282 --json state,comments`.
- [ ] Live re-read (read-only; same command as Research Insights) of workflows 566671 and 669246 returns HTTP 200, each with `dateUpdated` **equal** to the pre-merge values in the PR body. That is the evidence the apply wrote nothing to them.
- [ ] **If `dateUpdated` moved, or a comparison is no longer the captured `{3,"5m"}` / `{2,"1h"}`:**
  - file a `priority/p1-high` `action-required` issue;
  - restore through `PUT /api/0/organizations/jikigai-eu/workflows/<id>/`, with the body built from the phase34 capture entry for that id. The agent runs this with the same token; it is a scripted write, not a dashboard step;
  - re-read to confirm.

  Terraform cannot restore it while frozen.
- [ ] **If the apply fails part-way**, the rules keep paging from Sentry throughout. A forget touches Terraform state only. A re-run of the job **will red on the adoption assert** in every partial shape: `k == k < 2` takes the "resumed partial" branch; unequal counts (e.g. 0 forgets / 1 import after a forget applied without its import) take the "pair dropped" branch. Recovery:
  1. Run AC17's `terraform state list` reading.
  2. Open a reviewed follow-up PR that sets both adoption-assert call sites to the remaining count, carrying `[ack-destroy]` only if forget rows remain.

  Do not use `workflow_dispatch`, do not revert, and do not restore state (arch P1-1, spec-flow #1).
- [ ] #7985's title and body carry the atomic exit checklist, and its probe change is merged. The orphan-suite lint issue is filed.

## Test Scenarios

- **Guard 1:** given 30 normal `sentry_alert` rows plus 2 legacy-trigger rows with `trigger_conditions: null` and no `sensitive_values`, when projected `--arg side tf`, then the output equals `alert-reference.json` (30 keys). A native-form excluded row is also dropped. A legacy `issue_resolution_change` row makes jq exit 5.
- **Guard 2:** a plan with a legacy row `["update"]`, `["create"]` or `["delete","create"]` reds the tripwire, naming the address. An import no-op legacy row and a native-trigger `update` pass.
- **Guard 3:** the unmodified workflow passes. Each Guard 3 mutation, applied to a temp copy of the workflow the suite reads, reds it.
- **Guard 4:** a live fixture equal to the capture passes. `comparison: true`, `enabled: false`, a missing email action, a detector change, or an unknown excluded-type workflow each red. An edited frozen `.tf` literal reds the vitest half.
- **Adoption (existing suite):** `sentry-adoption-plan-assert.sh <plan> 2 <phase34 capture>` over a 2+2 fixture (ids 566671 and 669246) PASSes. With expected `1` it is RED.

## Domain Review

**Domains relevant:** engineering, product (brand-survival sign-off only)

### Engineering

**Status:** reviewed
**Assessment:** This is a CI/IaC repair on an existing surface. There is no new infrastructure, secret or vendor. It uses the in-tree adoption mechanism. The load-bearing technical claims were verified against the provider source (v0.15.7), Terraform source (v1.10.5 orphan planning), a local `terraform validate`, and a live read-only GET.

### Product/UX Gate

Not applicable: no UI surface. **Pencil available:** N/A (no UI surface).

### Plan review (5-agent eng panel + CTO devex lens + advisor consult)

**Decision:** reviewed. Mechanical findings were applied:

- The Create path is gated by the extended tripwire (DHH P1, Kieran P1, arch P1-2).
- Partial-apply recovery is corrected (arch P1-1, spec-flow #1).
- The 410 message is measured-only (arch P1-3, Kieran P2, CTO).
- The projection excludes both representations and filters before `tf_rule` (arch P2-4/5, Kieran P1, spec-flow #5, simplicity H1).
- The frozen-rule live pin and static pin (Kieran P2, spec-flow #4, arch P2-7, CPO).
- The #7985 probe no longer self-closes, plus the atomic exit checklist (CTO P1, spec-flow #3).
- `Ref #8282` instead of `Closes` (spec-flow #6).
- Filer and drift-workflow prose (spec-flow #7, CTO #6).
- The census do-not-touch category (Kieran #4) and the op-contract specifics (Kieran #3).
- The handler test folded into the registered full-root suite; the byte-delta AC and the ADR table copy cut (simplicity).
- The two dead scripts deleted (DHH, CTO).
- The merge-ordering AC (spec-flow #2).

**Advisor consult (Step 4.5):**

- Its point 1 ("the N=2 assert reds on every later plan") is refuted: the assert exits 0 with SKIP on zero forget and zero import rows (`sentry-adoption-plan-assert.sh`, the `n_forget -eq 0 && n_import -eq 0` branch).
- Its point 2 (fence the freeze) is adopted as Guard 2 + Guard 4.

**Not applied, and why:**

- DHH "switch to forget-only". It contradicts the operator's stated migrate-with-import direction, and it would not remove Guard 2 or Guard 4. Recorded as a decision challenge.
- DHH "collapse template sections". Observability, Encryption Posture and C4 are gate-enforced by deepen-plan.
- Spec-flow "diff-match forget addresses in the destroy gate". It replaces the ack model for one migration window. The merge-ordering AC covers that window instead.

### CPO sign-off (single-user incident)

**Status:** reviewed. **Decision:** granted-with-notes. The notes are folded in:

- Verify the live thresholds before and after apply: done at plan time, and a post-merge AC.
- Check actions as well as triggers: in the live table and the post-merge AC.
- Give the `ignore_changes` freeze an owner and an exit: the #7985 re-scope.
- Scope the `[ack-destroy]` with a sentence.
- Document partial-apply recovery: in the post-merge ACs.
- Word the 410 message in plain terms.
- No admin-bypass merge.

## Open Code-Review Overlap

None. I queried the open `code-review` issues against every planned file path and found no matches.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6.
- `[ack-destroy]` as a commit **subject** renders as `* [ack-destroy]` in the squash body and does **not** count. It must be a body line.
- Never add an ack, bypass or allowlist entry that lets a `create`/`update`/replace of these two addresses through the tripwire. Every such write sends `comparison: true` (DHH P1).
- Do not "tidy" the labels. The `sentry_alert` labels must equal the `removed{}` from-labels for the bijection. Once applied, a rename is a destroy+create of a live paging rule, and Guard 2 will (correctly) refuse the create.
- Never narrow `ignore_changes` on these two blocks outside the #7985 atomic conversion.
- The frozen blocks' HCL is documentation of live, not a lever. An edit plans "0 changes". Guard 4's static half is what catches a stale edit.
- Fixtures copy the #8282 run-log body verbatim: `{"detail": …}`, not the `{"message": …}` of #8451's quote and the old test's fixtures.
- The 410 handler message must pass `lint-diagnosis-claims.sh`. State the observation (address, single attempt, no retry), never a verdict the job did not measure.
