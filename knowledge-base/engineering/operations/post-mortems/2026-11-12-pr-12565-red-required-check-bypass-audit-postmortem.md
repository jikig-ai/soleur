---
title: "PR #12565 merged over a red required `test` check via ruleset bypass — enforcement-gap audit"
date: 2026-11-12
incident_pr: 12565
incident_window: "2026-11-10T12:03:58Z auto-merge armed → 2026-11-11T17:33:39Z merged (required `test` check red ~21h at merge)"
recovery_at: "2026-11-12 — audit + detective probe shipped (this PR)"
suspected_change: "plugins/soleur/scripts/run-health-emit.test.sh was registered without a committed weight row; the `test-scripts (3/8)` corpus-weight-budget check redded at 2026-11-10T20:28Z, the `test` aggregate redded 20:43Z, and the PR landed anyway via a ruleset-bypass merge"
brand_survival_threshold: aggregate pattern
status: audit-complete (probe shipped; bypass-policy decision pending operator)
triggers:
  - integrity (CI enforcement surface, not availability — no user-facing outage)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "N/A — no personal-data surface; CI-enforcement audit"
---

# PR #12565 red-required-check bypass — audit

This is the #12666 enforcement-gap audit. It answers the issue's four audit questions with
pinned evidence. It records facts, not accusations: every actor named below acted inside a
capability the ruleset deliberately grants; the defect under audit is the ABSENCE OF A
SIGNAL, not the act of merging.

## Pinned timeline (verified against the GitHub API on 2026-11-12)

| When (UTC) | Event |
|---|---|
| 2026-11-10T12:03:58Z | PR #12565 (head `d46da3095c`) auto-merge armed by deruelle, mergeMethod MERGE |
| 2026-11-10T20:28Z | `test-scripts (3/8)` FAILURE: `[check] registration(s) with no committed weight row: plugins/soleur/scripts/run-health-emit.test.sh` |
| 2026-11-10T20:43Z | `test` aggregate FAILURE — a REQUIRED context on ruleset 14145388 (`CI Required`, enforcement active) |
| 2026-11-11T17:33:39Z | PR #12565 merged by deruelle → merge SHA `aae21955e6`, ~21 h after `test` went red |

Negative evidence, also pinned: the PR carries **no** `added_to_merge_queue` /
`removed_from_merge_queue` timeline events, and there is **no** `gh-readonly-queue` CI run
on merge SHA `aae21955e6`. Native GitHub auto-merge cannot land over a failing required
check — the merge was an explicit bypass action by a bypass-capable identity.

The live ruleset 14145388 (`CI Required`, enforcement `active`) carries
`required_status_checks` + `merge_queue` and bypass actors
`OrganizationAdmin:pull_request` and `RepositoryRole(id=5):pull_request` (canonical:
`scripts/ci-required-ruleset-canonical-bypass-actors.json`; source of truth:
`infra/github/ruleset-ci-required.tf`).

## Q1 — Which bypass actor/mode executed the merge?

An explicit bypass merge by a bypass-capable identity (user `deruelle`), landing the head
over a required check that had been red for ~21 h. The mode was NOT the merge queue: no
queue timeline events exist and no `merge_group` run exists on the merge SHA. Whether the
surface action was `gh pr merge --admin`, the REST merge endpoint, or the UI "merge without
waiting" affordance is not distinguishable from the events API; all three land through the
same bypass-capable actor classes the ruleset grants (`OrganizationAdmin` /
`RepositoryRole(id=5)` with `pull_request` bypass mode).

## Q2 — Should `pull_request` bypass remain enabled for `OrganizationAdmin`/`RepositoryRole(5)`?

**Held for the operator — production-mutating.** This is the one question in the audit the
workflow may not answer itself: the bypass-actor list lives in Terraform
(`infra/github/ruleset-ci-required.tf`), and editing it is a production-mutating ruleset
change. The decision is recorded as a pending operator action in
`knowledge-base/project/specs/feat-one-shot-12666-12583-9340-batch/decision-challenges.md`
(authorize a follow-up Terraform PR editing the bypass-actor list). This PR ships the probe
+ audit only — no ruleset change.

Context for that decision (not a ruling): the bypass actors exist for the documented
settle-then-admin-merge escape hatch
(`plugins/soleur/skills/ship/references/settle-then-admin-merge.md` +
`plugins/soleur/scripts/admin-merge-ready.sh`), which is a PRE-merge readiness gate that
would have refused #12565's red `test` — it reads GREEN from positive counts, never from an
empty body. The gap this incident exposes is not the existence of the hatch but that its
use is silent.

## Q3 — Should the integrity gates sit in a leg that cannot be path-gated or skipped?

**No move needed — the surfaces are already disjoint.** The integrity gates that caught
this defect class are UNGATED members of the `test-scripts` matrix:

- the corpus-weight-budget check (leg 3) that redded #12565 for the missing weight row,
- the lint-orphan suite (leg 2) that polices suite registration,
- the shard-manifest regen check,
- the always-on-ledger suites.

The only whole-leg skip levers on `test-scripts` cannot reach these artifacts:

- the **oracle lane** (`scripts/ci-oracle-lane.sh`) skips on doc-path-only diffs and
  `ORACLE_INDEX`-confined edits; its `is_oracle_data_path` allowlist is EMPTY
  (`_never_a_member_`), and `scripts/suite-*.tsv` weight manifests are `outside_surface`
  → full battery;
- **draft-light** fires on draft PRs only;
- **push-dedupe** fires on `push` events only, not `pull_request`.

So an oracle-only diff cannot touch suite registrations or weight rows, and the weight-row
check could not have been skipped on #12565's diff — the check DID run and DID red. The
failure was downstream of CI entirely: a red required check that nothing enforced and
nothing paged.

## Q4 — Is there an alert path today when a required check is bypassed? If not, add one.

**There was none.** Every existing mechanism covers a different surface:

| Mechanism | What it covers | Why it did not fire |
|---|---|---|
| `cron-ruleset-bypass-audit.ts` (Inngest, daily) | ruleset CONFIG drift (bypass_actors widened, required checks removed, enforcement suspended) | the ruleset was unchanged — this was per-merge bypass USE, not drift |
| `scripts/probe-merge-group-coverage.sh` | offline structural proof that required contexts have merge_group producers | says nothing about individual merges |
| `plugins/soleur/scripts/admin-merge-ready.sh` | PRE-merge readiness gate for `--admin` merges | opt-in; it was not consulted |
| `.github/workflows/post-merge-monitor.yml` | bot-fix pipeline only | #12565 was not a bot-fix commit |

**Added (this PR):** `scripts/merge-bypass-audit.sh` +
`.github/workflows/merge-bypass-audit.yml`, running on every `push` to `main` plus
`workflow_dispatch` backfill. For each merge SHA it reports `ok` (queue authority ran, or
the source PR head had every required context green at merge), `bypass` (+ deduped
`compliance/critical` issue + `::error`), `check_flipped_after_merge` (green at merge, red
later — a CI regression, never bypass), or exits 2 on any unread API answer. The push
trigger covers queue merges, direct merges, admin merges, and direct pushes through one
chokepoint; `workflow_dispatch` provides backfill — including on `aae21955e6`, which must
fire BYPASS.

## Root cause

A required red check is DETECTED but not ENFORCED and not REPORTED: the ruleset grants a
bypass path by design (the admin-merge escape hatch), and nothing observed its use. The
defect class recurs silently for any future bypass merge until the probe lands.

## Action items

- [x] Detective probe + workflow shipped in this PR (Q4).
- [x] This audit committed (Q1/Q3 findings, durable indexed home).
- [ ] Operator decision on the `pull_request` bypass-actor list (Q2) — pending in
  `decision-challenges.md`; any change routes through Terraform
  `infra/github/ruleset-ci-required.tf`, never an ad-hoc ruleset PUT.
- [ ] Backfill-verify `aae21955e6` fires BYPASS via `workflow_dispatch` during this PR
  (the probe's success metric).
- [ ] Issue comment on #12666 linking this doc (lead).
