---
title: "infra(inngest): own Sentry alert rule for degraded provision bootstraps"
type: feat
date: 2026-09-30
slug: feat-inngest-provision-degraded-sentry-alert
branch: feat-one-shot-9299-degraded-alert-rule
issue: 9299
closes: 9299
pr: 9302
lane: single-domain
domain: engineering
brand_survival_threshold: aggregate pattern
---

# infra(inngest): own Sentry alert rule for degraded provision bootstraps

## Enhancement Summary

**Deepened on:** 2026-09-30, kept proportionate to a two-rule change.
**Agents:** observability-coverage reviewer, test-design reviewer, and a verify-the-negative /
attribution sweep; halt gates 4.6, 4.7, 4.8, 4.10 and 4.11 all pass (`lint-guard-contract.py`
green; the discoverability probe passes `probe-verb-gate.sh`).

### Key improvements

1. The throttle premise is now sourced: Sentry's workflow engine keeps one
   `WorkflowActionGroupStatus` row per (workflow, action, group) and fires only when
   `now - date_updated > frequency` (`src/sentry/workflow_engine/processors/action.py`), so two
   workflows on one group throttle independently. The read-only probe of the live org confirms
   `sentry_alert` rules are these workflows (the live projection carries `frequency: 120`).
2. Closed a silent mutant no gate saw: an `environment = …` line on the new block would bind the
   rule to one environment at CREATE time (`ignore_changes` applies only after creation, and the
   projection omits `environment`), so it would never match a boot event. T1/T1b now pin its
   absence, and the comment strip also drops `//` lines.
3. Runbook structure fixed: the degraded read is a sibling `###` section with its own anchor, and
   the stages-table row links to it (a `####` under the failure heading would have swallowed the
   failure table and bullets).
4. Observability block cites its routes per `hr-observability-layer-citation`, and names the
   residual that remains: a degraded event whose Sentry POST fails is unpaged.

### New considerations discovered

- `depends_on` skip-on-failed-dependency is standard Terraform graph behaviour, but the official
  docs do not state it for the update-after-create case; the plan cites it as observed behaviour
  (hashicorp/terraform#32148), and a failed create reds the apply either way.
- The first real firing of the degraded rule cannot be exercised until the next
  inngest-host-replace; AC-post-2 proves the configuration, and the trigger shape is the one the
  sibling boot-stage rules already page with.

## Overview

PR #9292 (commit `404825d`) added one Sentry rule, `sentry_alert.inngest_provision_failure`
(`inngest-provision-failure`), that pages two stages the dedicated inngest host's
`soleur-inngest-provision` unit emits:

- `provision_attempt_failed`: every non-zero attempt exit, from the `on_exit` trap. It repeats
  while the unit retries.
- `bootstrap_done_degraded`: a bootstrap that exits 0 while the host serves SQLite-only. It is
  emitted once per boot and never again (no latch, no retry until the next boot).

Both stages land in the one always-hot issue group `WEB-PLATFORM-4S`, and `frequency_minutes`
throttles per rule per issue group. So when one attempt fails (page) and the next ends degraded
within 2 h (the common sequence), the degraded page is suppressed and never re-emitted. The host
then stays degraded, silently, until its next reboot.

This PR gives the degraded stage its own rule, `sentry_alert.inngest_provision_degraded`
(`inngest-provision-degraded`), with its own unused `frequency_minutes`, and narrows
`inngest-provision-failure` to `provision_attempt_failed` only. A separate rule has its own
throttle state, so the failure page can no longer consume the degraded page's window. Every
artifact that describes the single-rule arrangement moves in the same PR. Closes #9299, and
resolves DC-2 of the archived #9176 decision record.

**Production effect of merging:** `apply-sentry-infra.yml` auto-applies one create
(`sentry_alert.inngest_provision_degraded`) and one in-place update
(`sentry_alert.inngest_provision_failure`: stage filter only). The operator authorized exactly this
on 2026-09-30. Nothing else writes to production.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified on this branch, base `404825d`) | Plan response |
| --- | --- | --- |
| Emitter at `cloud-init-inngest.yml` ~766 (`on_exit`) and ~1322 (degraded) | `on_exit` emit at line 766, degraded emit at line 1322 | No emitter change. The test keeps reading the file, not line numbers. |
| README counts 38 -> 39 (T25) | README line 5: ``**38 `sentry_alert` rules** (38 alert rules total)``, "36 are fully Terraform-owned (35 in `issue-alerts.tf` …)" | All three numbers move: 39 / 39 / 37 (36 in `issue-alerts.tf`). T25 derives the first two from the root. |
| C4 "35 of the 37" -> "36 of the 38" | `model.c4` `sentry -> founder` edge says "35 of the 37 `sentry_alert` rules in issue-alerts.tf" | Edit it, then regenerate `model.likec4.json`. No gate derives this number (`c4-count-parity.test.sh` rows C1-C6 cover heartbeat/cron counts only), so review is its only check. |
| ADR-257 pointer may name the single-rule arrangement | Both `Superseded 2026-09-30 (#9176)` blockquotes (3-space and 4-space indented) end "one 2 h throttle covers both stages" | Rewrite both blockquotes' last two lines (Phase 3). |
| Learning may claim the gap is open | Its Solution section says "the PR keeps one rule … The split is recorded as DC-2" | Append a dated `## Update 2026-09-30 (#9299)` note. Do not rewrite the body. |
| Frequency must be unused | Taken on `origin/main`: 5, 10-28, 30, 31, 60-63, 120, 240, 1440-1442. Open draft #9263 adds 29 and 32 | Use **33**. |

## Research Insights

**Premise validation.** #9299 is OPEN (`gh issue view 9299`). PR #9292 is merged; its commit
`404825d` is this branch's parent. Draft PR #9302 is this branch. Every cited path exists on the
branch: `issue-alerts.tf` (rule at the `inngest_provision_failure` block), `alert-reference.json`
(key `inngest-provision-failure`), `README.md`, `sentry-monitors-audit.test.sh` T25,
`model.c4`, the op-contract test, the runbook section `### Reading an inngest-provision-failure page
(#9176)`, ADR-257, the learning, and the archived DC-2. No ADR rejects a per-signal rule split. The
new sharp-edge bullet in `plugins/soleur/skills/plan/references/plan-sharp-edges.md` ("group by
EMISSION CADENCE, not by failure class") prescribes exactly this fix.

**Property list.**

1. P1: a degraded bootstrap pages, even when a provision-failure page went out in the previous 2 h.
2. P2: a failing provision attempt still pages at most every 2 h, and a pull miss still does not
   page twice.
3. P3: every warning stage the provision script emits is paged by exactly one of the two rules
   (no stage unpaged, none double-routed into a shared throttle).
4. P4: the live rules equal the committed reference after the apply.

**Cut list.**

- The degraded rule's `detail nc why=inngest_pull_fatal` row -> P2 -> the degraded detail can never
  contain that string (built only from `.redis-inactive` / `.no-durable-execstart`); the row stays
  on the failure rule only. (DC-2.)
- A `host_name` filter on the new rule -> P3 -> op-contract T8 already proves no other infra file
  names either stage.
- A new op-contract test file -> P3 -> the partition property spans both rules, so it lives in the
  existing op-contract file, renamed to `sentry-inngest-provision-alerts-op-contract.test.ts`.
- `first_seen_event` / `regression_event` triggers -> P1 -> inert on the perpetually active group;
  `event_frequency_count > 0 / 1h` already fires on each event (DC-4).

**Relevant files.**

- `apps/web-platform/infra/sentry/issue-alerts.tf`: the `inngest_provision_failure` block and its
  comment block are the last resource in the file (after `image_freshness_mismatch`).
- `apps/web-platform/infra/sentry/alert-reference.json`: entries are keyed by rule name in sorted
  order; `inngest-provision-degraded` sorts immediately before `inngest-provision-failure`. The
  shape is produced by `tests/scripts/lib/sentry-alert-projection.jq` (`canon` sorts keys;
  conditions and actions `sort_by(tostring)`; a single-trigger rule projects
  `triggerLogicType: "single"`; `detectorIds: ["1213799"]` is the issue-stream monitor).
- `.github/workflows/apply-sentry-infra.yml`: `plan_pr` runs `scripts/sentry-alert-reference-gate.sh`
  against the committed reference, and on mismatch publishes the expected document as artifact
  `sentry-alert-reference-expected-<run>` plus a step-summary block, which is the no-credential
  recovery if the hand-written entry is off by a leaf. The CREATE gate (`scripts/sentry-create-gate.sh`)
  requires every planned create to be explained by an added `resource` block in the window since the
  last applied commit.
- `apps/web-platform/test/sentry-inngest-provision-failure-alert-op-contract.test.ts`: T1-T8 pin
  one rule; T3 derives the emitted warning-stage set from the provision block and requires the
  rule's stage set to equal it.
- `apps/web-platform/scripts/sentry-monitors-audit.test.sh` T25: greps the README for
  ``**<n> `sentry_alert` rules**`` and `(<n> alert rules total)`.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: the stages table rows for
  `provision_attempt_failed` and `bootstrap_done_degraded`, and `### Reading an
  inngest-provision-failure page (#9176)` (anchor `#reading-an-inngest-provision-failure-page-9176`,
  linked from the stages table; keep the heading text so the anchor survives).

**Vendor semantics (sourced at deepen).** Sentry's workflow engine throttles per (workflow, action,
issue group): `src/sentry/workflow_engine/processors/action.py` keeps one
`WorkflowActionGroupStatus` row keyed `(workflow_id, action_id, group_id)` and fires only if
`now - date_updated > frequency`
(<https://github.com/getsentry/sentry/blob/master/src/sentry/workflow_engine/processors/action.py>).
A read-only `GET /api/0/organizations/jikigai-eu/workflows/?per_page=100` with
`SENTRY_ISSUE_RO_TOKEN` (2026-09-30) returned 40 workflows, and the projection of the live
`inngest-provision-failure` equals its committed reference entry, so `sentry_alert` rules are these
workflows and the throttle premise applies to them.

**Institutional learnings.**

- `2026-09-30-one-throttle-over-a-repeating-and-a-once-only-signal-silences-the-once-only-one.md`:
  the root cause this PR fixes; also: pin ABSENCE in the guard (row counts, one filter, one action,
  `enabled`), strip comments before anchoring, put each mutation's restore in `try/finally`, anchor
  indentation-sensitive ADR replacements on `\n<indent>`, lint markdown blockquotes for MD027.
- The `git_data_boot_warning` comment in `issue-alerts.tf` ("NOT `first_seen_event` (V2)") records
  why boot-stage rules use `event_frequency_count`.
- The Sentry README convention: a new rule takes an unused `frequency_minutes` (POST-time dedup keyed
  on action shape + frequency).
- `2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md`: the create-time
  dedup key is action match + filter match + frequency + action shape, NOT the conditions. The two
  inngest rules share `logic_type = "all"` and an identical email action, so a distinct frequency
  is the only thing that keeps the new rule's POST from being refused as a duplicate. 33 vs 120 is
  load-bearing, not cosmetic.
- `2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md`: the
  `event_frequency_count` trigger counts the whole issue group, and filters never narrow the count.
  On the always-hot `WEB-PLATFORM-4S`, `value = 0` passes on every event, and the stage filter is
  what selects. Same reasoning as the sibling rule.
- `2026-09-11-a-post-write-probe-cannot-be-referenced-to-a-capture-taken-before-the-write.md`: the
  post-apply probe uses the plan-projected reference, so the new rule is "managed" on the merge
  that creates it (the #8050 fix). No manual post-apply capture is needed.

**Related issues/PRs.** #9176 / PR #9292 (the single rule), #9299 (this), draft #9263 (claims
frequencies 29 and 32 and edits `issue-alerts.tf`, `alert-reference.json`; see Risks), #8562 (the
delivery probe that reads degraded as `FAIL reason=degraded`, unchanged).

**CLAUDE.md / AGENTS.md conventions applied.** `hr-menu-option-ack-not-prod-write-auth` (the apply is
explicitly operator-authorized), `hr-no-dashboard-eyeball-pull-data-yourself` (post-merge read-back
via API), `cq-assert-anchor-not-bare-token`, `cq-cite-content-anchor-not-line-number`,
`wg-use-closes-n-in-pr-body-not-title-to`.

## Proposed Solution

### The two rules (in `issue-alerts.tf`)

The existing block keeps its resource label, name, frequency (120), trigger, `logic_type = "all"`,
action and the `detail nc` row. Only the stage row changes:

```hcl
# apps/web-platform/infra/sentry/issue-alerts.tf — sentry_alert.inngest_provision_failure
{ tagged_event = { key = "stage", match = "eq", value = "provision_attempt_failed" } },
{ tagged_event = { key = "detail", match = "nc", value = "why=inngest_pull_fatal" } },
```

The existing block also gains one meta-argument, so Terraform orders the in-place narrowing after
the create and skips it if the create fails (without it the two run in parallel, and a failed
create beside a successful narrowing would leave the degraded stage paged by nothing, which is worse
than the bug being fixed):

```hcl
# apps/web-platform/infra/sentry/issue-alerts.tf — sentry_alert.inngest_provision_failure
  # Apply-order only (#9299): narrow this rule after the degraded rule exists, never before.
  # Safe to drop once both rules are live.
  depends_on = [sentry_alert.inngest_provision_degraded]
```

The inline comment is required: it is the first `depends_on` in this root and no test pins it
(a transient apply-order concern, recorded as a known gap). Terraform walks a node only after its
dependencies, and a failed dependency stops the dependent (graph internals:
<https://developer.hashicorp.com/terraform/internals/graph>; observed behaviour discussed in
hashicorp/terraform#32148); a failed create reds the apply run either way.
Meta-arguments do not appear in the plan JSON's resource values, so the projection and the gates
are unaffected.

The new block goes directly after it (the end of the file):

```hcl
# apps/web-platform/infra/sentry/issue-alerts.tf — new
resource "sentry_alert" "inngest_provision_degraded" {
  organization      = var.sentry_org
  name              = "inngest-provision-degraded"
  enabled           = true
  frequency_minutes = 33
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 0 } },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "stage", match = "eq", value = "bootstrap_done_degraded" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}
```

**Comment blocks.** Rewrite the existing block's comment so it describes `provision_attempt_failed`
only: drop "it is paged too" and the sentence "The throttle is per issue group and shared by both
stages: a once-per-boot degraded event … is suppressed and never re-emitted (runbook covers the
read)". Replace it with one line: the degraded stage has its own rule below, because a throttle is
per rule per group and a once-per-boot signal cannot share a window with a repeating one (#9299).
The new block's comment states, in this root's voice:

- what it pages (`stage=bootstrap_done_degraded`, warning, once per boot; `why=` names
  `.redis-inactive` / `.no-durable-execstart`; no latch, so the next boot retries);
- why it is a separate rule (per-rule-per-group throttle; the #9176 bundle let a failure page
  swallow it);
- why no `detail nc` row (the detail cannot contain `why=inngest_pull_fatal`);
- why `logic_type = "all"` is still written (uniform with the sibling, and it keeps the rule safe if
  a second row is ever added: under `any` a lone `nc`-style row would page every boot stage);
- the trigger (`value = 0`, first event; not `first_seen_event`, see `git_data_boot_warning`);
- `frequency_minutes = 33`: distinct from every other rule in the root (the op-contract test
  enforces it); short because the signal does not repeat, which bounds how long a forged degraded
  event from the semi-public DSN can mask a real one;
- "Arms dark until the next inngest-host-replace delivers the unit (ADR-257 §Status)"; runbook
  pointer.

Stage match is `eq` on both rules (DC-1).

### The reference entries (`alert-reference.json`)

Change the existing entry's stage condition to
`{"comparison": {"key": "stage", "match": "eq", "value": "provision_attempt_failed"}, "type": "tagged_event"}`
(it stays second after the `detail` condition under `sort_by(tostring)`: `{"comparison":{"key":"d…`
sorts before `{"comparison":{"key":"s…`). Add a new key `inngest-provision-degraded` immediately
before `inngest-provision-failure`, same shape as the sibling with one condition, `frequency: 33`,
`name: "inngest-provision-degraded"`. Keep the file's 2-space `jq -S` formatting. Build the new entry by copying the sibling entry (itself
projected from a real plan, so it already carries the provider's normalization for every shared
field) and changing only `name`, `frequency` and the conditions; `"match": "eq"` already projects as
`eq` in 62 existing conditions. A local `terraform plan` is not an option (it needs prd provider
credentials). If the entry still differs by any leaf, `plan_pr` prints the expected document and
uploads it as an artifact; copy it verbatim.

## Implementation Phases

### Phase 1: Contract test first (RED)

`git mv apps/web-platform/test/sentry-inngest-provision-failure-alert-op-contract.test.ts
apps/web-platform/test/sentry-inngest-provision-alerts-op-contract.test.ts` (it now guards both
rules; only archived plans/specs reference the old name), then extend it. Widen the header comment
and the describe title to both rules. Extend `stripComments` to drop `//` comment lines as well as
`#` ones (HCL accepts both). Parse both blocks with the existing `tfBlockFor` and `taggedEvents`;
read each rule's stage row directly (no helper: both rules use `eq`, DC-1).

| Row | Asserts |
| --- | --- |
| T1 (failure) | unchanged (one resource, name, `enabled = true`, monitor binding, one provision script, `on_exit`), plus no `environment =` line in the block. |
| T1b (degraded) | `count(tf, 'resource "sentry_alert" "inngest_provision_degraded"') === 1`; `name = "inngest-provision-degraded"`; `enabled = true`; same monitor binding; no `environment =` line (an environment set at CREATE binds the rule before `ignore_changes` applies, and the projection omits the field, so no other gate sees it). |
| T2 (failure) | unchanged: one `logic_type`, `"all"`, exactly 2 rows, one email action with the issue_owners/ActiveMembers shape. |
| T2b (degraded) | one `logic_type`, `"all"`, exactly **1** row, one email action with the same shape. |
| T3 (partition, replaces the old T3) | every provision-block emit is attributable (unchanged); the failure block's `stage` rows `toEqual([{key: "stage", match: "eq", value: "provision_attempt_failed"}])`; the degraded block's `toEqual([{key: "stage", match: "eq", value: "bootstrap_done_degraded"}])`; `[failureValue, degradedValue].sort()` equals `[...emittedWarningStages].sort()`. That one equality also proves the emitted set is non-empty and the two rules are disjoint. |
| T4 (failure) | unchanged: `detail` rows equal `[{key: detail, match: nc, value: why=inngest_pull_fatal}]`. (The degraded rule's lack of a `detail` row follows from T2b's one-row count plus T3.) |
| T4b (failure) | full `toEqual` of the reference entry, stage condition now `eq` / `provision_attempt_failed`. |
| T4c (degraded) | full `toEqual` of the `inngest-provision-degraded` reference entry. |
| T5, T6 | unchanged. |
| T7 (failure) | unchanged (120, unique in the root). |
| T7b (degraded) | `value = 0` trigger; `frequency_minutes = 33`; exactly one `frequency_minutes = 33` across every `.tf` in the root. |
| T8 | iterate the **union** of both rules' stage sets (not one rule's `value.split(",")`). |

Run `cd apps/web-platform && npx vitest run test/sentry-inngest-provision-alerts-op-contract.test.ts`
and confirm T1b (and every degraded-scoped row) is RED on the unmodified `.tf`, and T3 is RED
because the failure rule's stage row is still a two-member `in`.

### Phase 2: The rules and registries (GREEN)

1. `issue-alerts.tf`: narrow the stage row, rewrite the old comment block, append the new
   resource and its comment (Proposed Solution).
2. `alert-reference.json`: edit the existing condition, add the new entry.
3. `apps/web-platform/infra/sentry/README.md` lines 5-6 (the sentence wraps, so use separate
   anchored edits): line 5 ``**38 `sentry_alert` rules** (38 alert rules total)`` -> 39 / 39,
   append `#9299` after `#9176` in the PR list, and the line-final `36 are` -> `37 are`; line 6
   ``(35 in `issue-alerts.tf` `` -> ``(36 in `issue-alerts.tf` ``. In the historical paragraph, after "#9176 added
   `inngest_provision_failure`, taking it to 38" add "; #9299 added `inngest_provision_degraded`,
   taking it to 39".
4. Re-run the op-contract vitest (GREEN), T25 (`bash apps/web-platform/scripts/sentry-monitors-audit.test.sh`,
   T25 block), and `terraform fmt -check` + `terraform init -backend=false && terraform validate` in
   `apps/web-platform/infra/sentry`.

### Phase 3: Docs the change makes false

1. **Runbook** `knowledge-base/engineering/operations/runbooks/inngest-server.md`:
   - Stages table: the `provision_attempt_failed` row stays "paged by `inngest-provision-failure`".
     The `bootstrap_done_degraded` row becomes "**paged** by `inngest-provision-degraded` (#9299)"
     and links to the new section's anchor (`#reading-an-inngest-provision-degraded-page-9299`)
     instead of the throttle note.
   - `### Reading an inngest-provision-failure page (#9176)`: keep the heading (anchor). Its opening
     paragraph gains: both rules page the same issue with the same subject, so **a second email
     minutes after a failure page is not a duplicate**; read the rule name or the `stage` tag. Move
     the `stage=bootstrap_done_degraded` table row out to the new section.
   - Add a sibling `### Reading an inngest-provision-degraded page (#9299)` right after the failure
     section's bullets (before `### Replace triggers`), so a search for the rule name lands on it:
     the `why=` read (`.redis-inactive`, `.no-durable-execstart`), "emitted once per boot, never
     re-emitted: treat it as open until `bootstrap-done` appears for the same `iid`", and the
     forged-event and POST-failure residuals below.
   - Replace the first bullet (the shared-throttle caveat) with: each rule throttles on its own
     (`inngest-provision-failure` at most every 2 h, `inngest-provision-degraded` at most every
     33 min), so a failure page no longer suppresses a degraded page. Keep the read "treat a
     degraded page as open until `bootstrap-done` appears for the same `iid`" (still true: it is
     never re-emitted).
   - The "benign or forged page" bullet: the windows become up to 2 h for a retrying failure and
     up to 33 min for a degraded page; a real degraded event inside a forged one's window is still
     silent until the next boot. Keep "corroborate with Better Stack".
   - "To quiet it": name both resources (`sentry_alert.inngest_provision_failure`,
     `sentry_alert.inngest_provision_degraded`).
   - "Not paged by any rule": name "a degraded event whose Sentry POST failed
     (`sentry-emit-FAILED stage=bootstrap_done_degraded` in Better Stack)" explicitly; the degraded
     state has no second paging path.
2. **ADR-257** (both `Superseded 2026-09-30 (#9176)` blockquotes, one indented 3 spaces, one 4;
   the 3-space copy also carries "the deferral is closed.", and the phrases to replace wrap across
   several `>`-prefixed lines, so write out each multi-line old string exactly, per indentation):
   replace "now pages `provision_attempt_failed` and `bootstrap_done_degraded`, excluding attempts
   whose detail carries `why=inngest_pull_fatal`" and "and one 2 h throttle covers both stages" so
   the note reads: `inngest-provision-failure` pages `provision_attempt_failed` (excluding
   `why=inngest_pull_fatal`); since #9299 `bootstrap_done_degraded` pages through its own rule,
   `sentry_alert.inngest_provision_degraded` (`inngest-provision-degraded`), so each stage has its
   own throttle. Anchor each replacement on a leading newline plus the exact indent and `>` so the 3-space copy cannot match inside
   the 4-space one. Single space after `>` (MD027). Status stays `adopting`.
   **As shipped:** the #9299 wording was appended as a `Superseded 2026-09-30 (#9299)` pointer
   under each #9176 blockquote instead of replacing it (dated records are append-only); see AC8.
3. **C4** `knowledge-base/engineering/architecture/diagrams/model.c4`, `sentry -> founder` edge:
   "35 of the 37" -> "36 of the 38". Then `bash scripts/regenerate-c4-model.sh` to refresh
   `model.likec4.json`.
4. **Learning** `knowledge-base/project/learnings/2026-09-30-one-throttle-over-a-repeating-and-a-once-only-signal-silences-the-once-only-one.md`:
   append `## Update 2026-09-30 (#9299)`: the split landed; `bootstrap_done_degraded` now pages
   through `inngest-provision-degraded` (33-min throttle) and the runbook's shared-throttle caveat
   is removed. Leave the original body unchanged.
5. **Archived DC-2**: leave the archived file unchanged (archives are point-in-time). The PR body
   and `decision-challenges.md` state that this PR resolves it; `Closes #9299` closes the tracker.

### Phase 4: Ship

`soleur:ship` with the PR body's first line: "Merging auto-applies one new Sentry alert rule
(`inngest-provision-degraded`) and one in-place update to `inngest-provision-failure`
(`apply-sentry-infra.yml`); nothing else." Body carries `Closes #9299`, "arms dark until the next
inngest-host-replace (ADR-257)", the decision challenges, and the apply-path note below. CI is the
test gate (operator instruction: no local full battery); the targeted ratchets in Phases 1-2 run
locally. Admin merge is authorized once CI is green; the diff touches no workflow file.

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `apps/web-platform/infra/sentry/alert-reference.json`
- `apps/web-platform/infra/sentry/README.md`
- `apps/web-platform/test/sentry-inngest-provision-failure-alert-op-contract.test.ts` -> renamed to `sentry-inngest-provision-alerts-op-contract.test.ts` (`git mv`, then edited)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- `knowledge-base/engineering/architecture/decisions/ADR-257-inngest-host-provisioning-runs-in-a-latched-retrying-unit.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated, not hand-edited)
- `knowledge-base/project/learnings/2026-09-30-one-throttle-over-a-repeating-and-a-once-only-signal-silences-the-once-only-one.md` (appended note only)

## Files to Create

- None in the product tree. Planning artifacts: this plan,
  `knowledge-base/project/specs/archive/20260930-190358-feat-one-shot-9299-degraded-alert-rule/{tasks.md,decision-challenges.md}`.

## Open Code-Review Overlap

None. Open `code-review` issues were checked against every path above (and `ADR-257`,
`cloud-init-inngest.yml`); no body names them.

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) silence: the degraded rule never fires,
  and a scheduler host serving jobs and reminders from a non-durable store stays that way with no
  page until the next reboot, so a restart can drop users' scheduled work (today's state in the
  failure-then-degraded sequence, so no regression); or (b) a page storm: a filter that matched the
  whole shared boot-stage group would email on every boot of every host, and the operator would
  mute it, burying real pages.
- **If this leaks, the user's data is exposed via:** nothing new. The rule reads existing events
  whose tags carry a stage name, the degraded reason, an attempt counter and a cloud instance id.
  No user content. The email goes to the existing issue-owner/ActiveMembers route.
- **Brand-survival threshold:** `aggregate pattern`. A degraded scheduler affects all users'
  scheduled work, not one user's data. Mode (b) is guarded by T2b/T3 (one exact stage row, AND
  logic) and the post-merge read-back.

## Observability

```yaml
liveness_signal:
  what: "the live Sentry workflows inngest-provision-degraded (enabled, frequency 33, stage eq bootstrap_done_degraded) and inngest-provision-failure (enabled, frequency 120, stage eq provision_attempt_failed AND detail nc why=inngest_pull_fatal)"
  cadence: "checked after every apply-sentry-infra.yml run (post-apply fidelity) and daily by the scheduled Sentry alert drift job against alert-reference.json"
  alert_target: "drift, a missing rule or a disabled rule -> the drift/apply workflow's issue filing (existing); each rule emails issue owners -> ActiveMembers"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (sentry_alert.inngest_provision_degraded, sentry_alert.inngest_provision_failure) + alert-reference.json"
error_reporting:
  destination: "Sentry issue WEB-PLATFORM-4S (shared soleur-cloud-init boot-stage group) -> email via inngest-provision-degraded or inngest-provision-failure; Better Stack phone-home rows bootstrap-done-DEGRADED / provision-attempt-exit-<rc> carry the same states"
  fail_loud: "yes: the degraded branch emits bootstrap_done_degraded (Sentry) and the phone-home row before continuing; a failed attempt's on_exit emits provision_attempt_failed"
failure_modes:
  - mode: "degraded bootstrap (SQLite-only, no latch) after a provision-failure page within 2 h (the #9299 gap)"
    detection: "stage=bootstrap_done_degraded, detail why=.redis-inactive and/or .no-durable-execstart"
    alert_route: "Sentry monitor: issue alert inngest-provision-degraded (own throttle, 33 min), fed by the host's direct soleur-boot-emit store-API POST -> email issue_owners/ActiveMembers; corroborated by the direct Better Stack phone-home row bootstrap-done-DEGRADED (not paged)"
  - mode: "non-pull provision attempt failure"
    detection: "stage=provision_attempt_failed with detail why=<last_stage> (not inngest_pull_fatal)"
    alert_route: "Sentry monitor: issue alert inngest-provision-failure (unchanged, throttle 120), fed by the direct soleur-boot-emit store-API POST -> email issue_owners/ActiveMembers; corroborated by the Better Stack row provision-attempt-exit-<rc> (not paged)"
  - mode: "forged degraded event from the semi-public DSN masks a real one"
    detection: "none that pages: a real degraded event inside the 33-min window after a forged one is suppressed and not re-emitted; the Better Stack bootstrap-done-DEGRADED row (Doppler-held token) is corroboration, not detection"
    alert_route: "residual, documented in the runbook degraded section (pre-existing class for every tag-keyed rule on the semi-public DSN; narrowed from 2 h to 33 min by this change)"
  - mode: "degraded event's Sentry POST fails"
    detection: "soleur-boot-emit phones home sentry-emit-FAILED stage=bootstrap_done_degraded to Better Stack; nothing pages on it"
    alert_route: "residual, listed under the runbook's 'Not paged by any rule' (pre-existing: soleur-boot-emit has no retry, the same for every boot-stage rule); the #8562 delivery probe reads the state as FAIL reason=degraded while that follow-through is open"
  - mode: "apply fails to create the new rule or to update the old one"
    detection: "red apply-sentry-infra.yml run for the merge SHA (its failure issue filer fires); post-apply fidelity and the daily drift job report a reference name missing live or a mismatched leaf; AC-post-2 projection diff"
    alert_route: "layer 6 (workflow run log) + the filed GitHub issue"
  - mode: "either rule drifts, is disabled, or loses its filter in Sentry"
    detection: "daily drift job compares live /workflows/ to alert-reference.json (DISABLED reported as a live fault)"
    alert_route: "layer 6 (workflow run log) + the drift workflow's filed issue"
logs:
  where: "Sentry events (tags stage/detail/host_id/host_name) in project web-platform; Better Stack inngest boot-trace source"
  retention: "Sentry plan event retention (90 days); Better Stack source retention"
discoverability_test:
  command: "grep -c inngest-provision-degraded apps/web-platform/infra/sentry/alert-reference.json"
  expected_output: "2"
```

The probe proves the new rule is declared in the live-bound reference (its key line and its
`name` line). `enabled`, `frequency` and the conditions are covered by the reference gate, the daily
drift job and AC-post-2.

## Guard Contract

### Guard 1 — inngest provision rules op-contract (`sentry-inngest-provision-alerts-op-contract.test.ts`)

**Property.** Every warning-level stage the inngest provision script emits is paged by exactly one
of the two rules; `inngest-provision-failure` matches only `provision_attempt_failed` minus pull
misses, and `inngest-provision-degraded` matches only `bootstrap_done_degraded` with no other
AND-ed condition, each at a frequency no other rule in the root uses.

**Assembly.** Emitter chokepoint: the `soleur-boot-emit <stage> <level>` calls inside the
`path: /usr/local/bin/soleur-inngest-provision` block of `cloud-init-inngest.yml`; a non-literal
call is itself a red (T3 attributability), so the literal scan cannot silently miss a member. Rule
chokepoint: the two `sentry_alert` blocks, found by resource label via `tfBlockFor`, with comments
stripped. Stored copy: the two `alert-reference.json` entries. The frequency row reads every `.tf`
in the root (directory-derived list).

**Mutation matrix** (run locally during work, each restore in `try/finally`; the tally goes in the
PR body's test notes).

| # | Mutation | Must go RED |
| --- | --- | --- |
| M1 | rename the new resource label (own dispatch: `tfBlockFor` returns "") | T1b and every degraded-scoped row |
| M2 | re-bundle: failure rule stage row back to `in` / `bootstrap_done_degraded,provision_attempt_failed` (the precondition "every stage is paged" still holds; the partition fails) | T3 |
| M3 | degraded rule stage value typo `bootstrap_done_degradd` | T3 |
| M5 | add a second warning emit `soleur-boot-emit foo_failed warning` in the provision block after the compliant ones | T3 |
| M6 | degraded `frequency_minutes = 120` | T7 (two `= 120` lines), T7b (no `= 33` line) |
| M10 | add the string `bootstrap_done_degraded` to `cloud-init.yml` | T8 |
| M11 | add `environment = "development"` to the degraded block | T1b |

**Harness rows.** H1 (must RED): turn the degraded rule's stage row into a `#` comment line; the
comment strip removes it and T2b/T3 go red, so a comment cannot satisfy a code anchor. H1b (must
RED): the same with a `//` comment. H2 (must
PASS, not the canonical): move the degraded resource block above the failure block and swap the
field order inside its `tagged_event` (`value`, `key`, `match`); the rows locate blocks by label
and parse fields order-insensitively.

**Anchor.** Not a self-certifying stored value: `alert-reference.json` is held equal to the
Terraform plan projection by the `plan_pr` reference gate and to live Sentry by the daily drift job
and post-apply fidelity, all outside this test and this diff.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/sentry/issue-alerts.tf` in the existing Sentry root (R2 backend, provider
`jianyuan/sentry` unchanged): one new `sentry_alert`, one in-place change to an existing one. No
new variables, secrets or providers.

### Apply path

- `apply-sentry-infra.yml` applies the full root on push to `main` (path filter
  `apps/web-platform/infra/sentry/**`). Expected plan: **1 to add, 1 to change, 0 to destroy**. The
  CREATE gate must list exactly `sentry_alert.inngest_provision_degraded`, explained by the added
  block. No host impact, no downtime. Operator-authorized (2026-09-30); the kill switch
  `[skip-sentry-apply]` is not used.
- `apply-web-platform-infra.yml` also fires, because `infra/sentry/**` sits under its
  `apps/web-platform/infra/**` path filter. Its root does not include the Sentry `.tf` files, so it
  is expected to plan no change; on the #9292 merge it was a no-op. Post-merge, confirm its run for
  the merge SHA concludes `success` with no resource change, and do not dispatch or re-run anything.
- No tag pushes, workflow dispatches or other terraform applies.

### Distinctness / drift safeguards

The PR-time reference gate, post-apply fidelity and the daily drift probe;
`lifecycle.ignore_changes = [environment]` like its siblings. This root targets the single prd Sentry
org `jikigai-eu`; there is no dev counterpart (unchanged).

### Vendor-tier reality check

The org runs 38 `sentry_alert` rules today; this makes 39. Issue alerts are not tier-gated.

## Encryption Posture

```yaml
at_rest:
  - store: "none new; the change adds one alert rule definition in Sentry and edits another"
    mechanism: "no store introduced; rule definitions live in Sentry's existing config and in the existing R2 Terraform state"
    evidence: "Files to Edit: sentry_alert blocks, a JSON reference entry, docs, one vitest"
    defends_against: "no new data-at-rest exposure is created by this change"
    does_not_defend: "the existing Terraform state in R2 and Sentry's own storage are unchanged; their postures are outside this change"
    disclosed_as: "no new disclosure; existing Sentry processing is unchanged"
    live_verification: "GET /api/0/organizations/jikigai-eu/workflows/ after apply (AC-post-2)"
in_transit:
  - connection: "existing edges only: inngest host -> Sentry store API (soleur-boot-emit, HTTPS) and Sentry -> operator email"
    tls: "HTTPS to the DSN host; email via Sentry's mail provider"
    cert_verification: "on"
    does_not_defend: "a holder of the public DSN can forge a degraded event, trigger a page, and start the 33-min throttle that masks a real degraded event in that window (true of every tag-keyed rule in this root; corroborate against the Better Stack phone-home row)"
    disclosed_as: "existing Sentry processing, unchanged"
```

## Architecture Decision (ADR/C4)

### ADR

No new ADR: splitting one paging rule into two is an alerting-configuration change inside the
decision ADR-257 already records. Amend ADR-257's two `Superseded 2026-09-30 (#9176)` pointers
(Phase 3.2), because they state the single-rule, shared-throttle arrangement this PR removes.

### C4 views

All three model files were read for this check (`model.c4`, `views.c4`, `spec.c4`). Actors, systems
and relationships involved are already modeled: the operator (`founder`), `sentry`, the inngest host
(`inngest`), `betterstack`, the `inngest -> sentry` boot-emitter edge (describes emission only, no
rule names) and the `sentry -> founder` paging edge. No element, relationship or `view include`
changes. One description becomes false: the `sentry -> founder` count ("35 of the 37" -> "36 of
the 38", Phase 3.3). No gate derives that count; `c4-count-parity.test.sh` (C1-C6: heartbeat and
cron counts) and `c4-model-freshness`, `c4-code-syntax`, `c4-render` must stay green after
regeneration.

### Sequencing

ADR-257 stays `adopting`; its flip belongs to the #8562 delivery probe, unchanged. Both rules arm
dark until the next inngest-host-replace delivers the provision unit.

## Plan Review Revisions (2026-09-30)

Panel: DHH, Kieran, code-simplicity (eng) and the CTO (devex lens), plus the Step 4.5 advisor
consult. Applied (mechanical):

- `depends_on` on the narrowed rule so a failed create cannot leave the degraded stage unpaged
  (advisor), with a required inline comment (Kieran, DHH, CTO, simplicity).
- Dropped the `stageSet` helper, H3/H4 and the T4-degraded row; T3 is one partition equality
  (simplicity, DHH).
- Mutation matrix trimmed to M1, M2, M3, M5, M6, M10, H1, H2; M6's expected rows corrected to
  T7/T7b (Kieran: T4c reads the JSON, not the `.tf`); the tally is recorded in the PR body so AC2
  is auditable (DHH).
- AC5 reduced to the open-PR check (T7b already enforces uniqueness on the branch).
- Test file renamed to `sentry-inngest-provision-alerts-op-contract.test.ts` (Kieran).
- README edit split across its wrapped lines; ADR-257 edit instructions corrected (Kieran).
- Runbook: an explicit "a second email is not a duplicate" read and a searchable
  `inngest-provision-degraded` section (CTO; made a sibling `###` at deepen, see the Enhancement
  Summary).
- AC-post-2 now uses the fidelity script's `?per_page=100` URL and a null check; the RO token's
  access to `/workflows/` was probed read-only at plan time (HTTP 200, live projection equals the
  committed entry).

Not applied, and why:

- Drop AC-post-2 in favour of the workflow's fidelity step (DHH, Kieran, CTO): the operator asked
  for this independent read-back, so it stays; it is proven to work.
- Remove the count from the C4 `sentry -> founder` edge instead of bumping it (DHH, simplicity,
  CTO): the brief names the bump. Recorded as a User-Challenge (DC-5).
- Make the PR purely additive (advisor): the brief says narrow in this PR; `depends_on` closes the
  gap the advisor raised.
- Drop T4c (DHH): kept as the in-test stand-in for P4 (simplicity agreed).
- Trim the Observability and Encryption Posture blocks (DHH): both are required plan sections
  (plan Phases 2.9 and 2.11 fire on `issue-alerts.tf`).

## Acceptance Criteria

### Pre-merge

- [x] AC1: the extended op-contract vitest is RED on the base `.tf` (T1b: resource absent; T3:
  failure stage row is a two-member `in`) and GREEN after Phase 2
  (`cd apps/web-platform && npx vitest run test/sentry-inngest-provision-alerts-op-contract.test.ts`).
- [x] AC2: the PR body's test notes record the mutation tally: M1, M2, M3, M5, M6, M10, M11, H1 and
  H1b each reddened the named row, and H2 stayed green.
- [x] AC3: T25 green: `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` passes its T25
  block with README ``**39 `sentry_alert` rules**`` and `(39 alert rules total)`.
- [x] AC4: `terraform fmt -check` clean and `terraform validate` (`init -backend=false`) green on
  `apps/web-platform/infra/sentry`.
- [ ] AC5: no open PR other than this one adds `frequency_minutes = 33` at ship time (root-wide
  uniqueness on the branch is T7b).
- [ ] AC6: CI `plan_pr` in `apply-sentry-infra.yml` green: reference gate passes, the CREATE gate
  lists exactly `sentry_alert.inngest_provision_degraded`, the plan shows 1 add / 1 change /
  0 destroy.
- [x] AC7: C4 tests green after regeneration (`c4-model-freshness`, `c4-count-parity`,
  `c4-code-syntax`, `c4-render`), and `grep -c "36 of the 38" knowledge-base/engineering/architecture/diagrams/model.c4` prints `1`.
- [x] AC8: no stale single-rule prose remains:
  `git grep -n "shared by both stages\|one 2 h throttle covers both stages\|it is paged too" -- apps/web-platform/infra/sentry knowledge-base/engineering` prints only the two
  ADR-257 lines inside the dated `Superseded 2026-09-30 (#9176)` pointers, each followed by a
  `Superseded 2026-09-30 (#9299)` pointer. **Amended at work (2026-09-30):** a dated record is
  append-only (work skill rule, #7309), so Phase 3.2 appends the #9299 pointer under each #9176
  blockquote instead of rewriting it.
- [ ] AC9: the PR body's first line states the production effect (one create + one in-place update
  via `apply-sentry-infra.yml`, nothing else); the body has `Closes #9299`, says it resolves the
  archived #9176 DC-2, and carries this PR's decision challenges. The diff touches no workflow file:
  `git diff --quiet origin/main...HEAD -- .github/workflows/` exits 0.

### Post-merge (operator-authorized apply; no other production write)

- [ ] AC-post-1: the `apply-sentry-infra.yml` run for the merge SHA concludes `success`, with
  post-apply fidelity green
  (`gh run list --workflow apply-sentry-infra.yml --branch main -L 3 --json headSha,conclusion`).
  The `apply-web-platform-infra.yml` run for the same SHA concludes `success` with no resource
  change (read its plan summary; do not re-run or dispatch).
- [ ] AC-post-2: both live rules equal the committed reference, read with the operator-named
  read-only `SENTRY_ISSUE_RO_TOKEN` (Doppler `soleur/prd`, never printed) and the same URL shape as
  `scripts/sentry-alert-live-fidelity.sh`. Verified at plan time (2026-09-30): this call returns
  HTTP 200 with 40 workflows, and the projection of the live `inngest-provision-failure` equals the
  committed entry, so the command works and can fail.
  `doppler run -p soleur -c prd -- sh -c 'curl -s --max-time 30 -o "$0" -w "%{http_code}\n" -H "Authorization: Bearer $SENTRY_ISSUE_RO_TOKEN" "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/workflows/?per_page=100"' "$SCRATCH/wf.json"`
  prints `200`; then `jq -S --arg side live -f tests/scripts/lib/sentry-alert-projection.jq "$SCRATCH/wf.json" > "$SCRATCH/live.json"`,
  and for each of `inngest-provision-degraded` and `inngest-provision-failure`,
  `diff <(jq -S --arg n "$n" '.[$n]' apps/web-platform/infra/sentry/alert-reference.json) <(jq -S --arg n "$n" '.[$n]' "$SCRATCH/live.json")`
  exits 0 and `jq -e --arg n "$n" '.[$n] != null' "$SCRATCH/live.json"` exits 0. If the org grows past
  100 workflows, follow the `Link` header. This is an independent read beside the workflow's own
  `sentry_alert live fidelity` step, which uses a different token.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change (one internal
paging rule split into two, plus docs). No user-facing surface, copy, pricing or legal implication.

## Test Scenarios

- Op-contract rows T1-T8 plus T1b, T2b, T4c, T7b, and the Guard Contract matrix (M1, M2, M3, M5,
  M6, M10, M11, H1, H1b, H2). A second non-`tagged_event` condition or trigger row is not pinned by
  the test; the `plan_pr` reference gate catches both before merge.
- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` (unchanged) keeps pinning the
  emitted degraded line format that T5 relies on.
- T25 in `sentry-monitors-audit.test.sh`; the C4 suite.

## Dependencies & Risks

- **Draft #9263** edits `issue-alerts.tf`, `alert-reference.json` and, when it lands, the README and
  C4 counts too; it claims frequencies 29 and 32. Whichever merges second rebases and bumps the
  counts by one more. 33 does not collide with it.
- **CREATE-gate ancestry.** If another Sentry PR applies first, update the branch and re-push.
- **In-place update of a live rule.** Only the stage condition changes. If the apply rejected the
  update, the old two-stage rule stays live (no loss of paging), and the apply run goes red. If the
  CREATE fails, `depends_on` skips the narrowing, so the old rule keeps paging both stages.
- **Rejected alternative: purely additive PR** (add the degraded rule, narrow the old one later).
  It avoids touching a live rule, but the operator's direction for this PR is to narrow it, and
  `depends_on` closes the only coverage gap the in-place edit could open. Leaving both stages on the
  old rule would also keep double-emailing the degraded stage whenever the old rule is unthrottled.
- **Shared issue group.** Mitigated by the exact single stage row (T2b/T3) and documented in both
  comment blocks and the runbook.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6. It is filled here.
- The two ADR-257 blockquotes share wording but differ in indentation (3 vs 4 spaces) and the
  3-space copy adds "the deferral is closed.". A replacement keyed on the text alone matches twice
  or not at all; copy each multi-line old string exactly, with its own indent and `>` prefixes.
- `alert-reference.json` must equal the projection byte-for-byte after `jq -S`. Do not hand-sort
  conditions by eye: `sort_by(tostring)` compares the serialized objects, so `detail` sorts before
  `stage`. The `plan_pr` artifact is the authority if they disagree.
- Keep the runbook heading `### Reading an inngest-provision-failure page (#9176)` verbatim; the
  stages table links its anchor.
- Re-grep `frequency_minutes` on `origin/main` and in open PRs right before ship; a sibling can claim
  33 during the pipeline (AC5).
