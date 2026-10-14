---
title: Protect the marketplace repo — ruleset, Terraform-owned manifest, and a reconcile trigger
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-08-12-marketplace-repo-protection-brainstorm.md
closes: 7493
created: 2026-08-12
---

# Spec: Protect `jikig-ai/soleur-marketplace`

## Problem Statement

`jikig-ai/soleur-marketplace` is the plugin's sole distribution channel and has no CI, no
required review and no CODEOWNERS — it is unreviewed by construction. Live state at spec time:
**zero rulesets, no branch protection, one collaborator**. Four `claude-code-action` workflows
install the plugin from it, two of which ship into *users'* generated CI, carrying
`ANTHROPIC_API_KEY` and a `GITHUB_TOKEN` with `issues: write`; the plugin they install ships
executable hooks and skills.

`scheduled-marketplace-drift.yml` detects a repoint within 24 h. **Detection is not prevention**,
and the two controls that would prevent it were deferred by ADR-182 on preconditions that have
since been resolved against the live API (see the brainstorm's evidence table).

## Goals

- **G1.** A direct push to `main` on `jikig-ai/soleur-marketplace` is rejected for every actor
  except the declared bypass set.
- **G2.** `.claude-plugin/marketplace.json` in that repo is produced from a source-of-truth file
  in this monorepo that is subject to CI, required checks and CODEOWNERS review.
- **G3.** A detected content drift is **corrected** within the daily drift cycle, not merely
  filed.
- **G4.** The unattended `apply-github-infra.yml` pipeline still succeeds end-to-end after G1
  and G2 land together — no apply-time deadlock between the ruleset and the file write.
- **G5.** The sole maintainer retains an emergency-fix path on the marketplace repo.

## Non-Goals

- **NG1.** Retiring the legacy `jikig-ai/soleur` marketplace entry — tracked in #7489. This work
  does not modify `.claude-plugin/marketplace.json` in this monorepo, which is a **different
  file** serving the legacy entry. Do not conflate the two.
- **NG2.** Adding CI or CODEOWNERS inside `soleur-marketplace` itself — G2 makes it unnecessary.
- **NG3.** A `schedule:` on `apply-github-infra.yml`. Rejected: a daily unattended apply over the
  whole GitHub infra root carries far more blast radius than an event-driven dispatch scoped to
  an actual drift verdict.
- **NG4.** Any change to the plugin's install or update UX.

## Functional Requirements

- **FR1.** Declare `github_repository_ruleset.marketplace_pr_required` in
  `infra/github/ruleset-marketplace-pr-required.tf`, targeting `main` on
  `jikig-ai/soleur-marketplace`, `enforcement = "active"`, with a `pull_request` rule.
- **FR2.** Bypass actors, mirroring the sibling rulesets:
  `OrganizationAdmin` (`actor_id = 0`, `bypass_mode = "pull_request"`),
  `RepositoryRole` (`actor_id = 5`, `bypass_mode = "pull_request"`), and
  `Integration` (`actor_id = 3261325` — the `soleur-ai` **App ID**, not the installation id
  `122213433`; `bypass_mode = "always"`, required so FR4's write can apply unattended).
- **FR3.** Add the source-of-truth manifest at
  `infra/github/soleur-marketplace-manifest.json`, byte-identical to what is published today.
  Placement is load-bearing: `/infra/github/` is already a CODEOWNERS-pinned path, so G2's
  review property holds with no CODEOWNERS edit.
- **FR4.** Declare `github_repository_file.marketplace_manifest` writing that file to
  `.claude-plugin/marketplace.json` on the marketplace repo's `main`, sourced via `file()` from
  FR3.
- **FR5.** Extend `apply-github-infra.yml`'s `paths:` trigger to include
  `infra/github/soleur-marketplace-manifest.json`. Without this the existing
  `infra/github/*.tf` glob does not match the `.json` sibling, and editing the manifest would
  not publish it — a silent no-op.
- **FR6.** Adopt both new resources through the existing `import_ruleset` / `import_repository`
  helper pattern in `apply-github-infra.yml`, so the first apply is an adoption rather than a
  create against live objects that already exist.
- **FR7.** In `scheduled-marketplace-drift.yml`, on a `MISMATCH` verdict, dispatch
  `apply-github-infra.yml` **after** the issue file/comment step has delivered, passing a
  `reason` input identifying the drift run.
- **FR8.** FR7 dispatches **only** when at least one finding is a manifest-content finding
  (`version_key_present`, `source_path`, `source_url`, `source_type`, `source_pinned`,
  `entry_count`, `entry_name`). It MUST NOT dispatch when the only finding is
  `plugin_manifest_unresolvable` — that fires when *this monorepo* moved `plugins/soleur`, where
  the manifest is correct and reconciling it would rewrite a correct file on every tick while
  the real breakage persists.
- **FR9.** Retain all existing drift assertions. Under FR4 their role changes from *detector* to
  *verifier that Terraform's write took effect*; a `github_repository_file` that silently fails
  to apply is the silent-failure class this repo gates against.
- **FR10.** Amend ADR-182: mark both deferred alternatives as shipped, record the resolved
  preconditions, and **correct** its claim that drift would be "auto-reconciled by the next
  apply" — which was false absent FR7, since the apply has no schedule.

## Technical Requirements

- **TR1.** `permissions:` on the drift workflow gains `actions: write` and nothing else. The
  dispatch MUST use the automatic `secrets.GITHUB_TOKEN`. Introducing a product secret would
  invalidate the workflow's ADR-033 gate-override justification (iii), which explicitly rests on
  "NO PRODUCT SECRETS ARE CONSUMED".
- **TR2.** `workflow_dispatch` is one of the two documented exceptions to the rule that a
  `GITHUB_TOKEN`-triggered event does not create a new workflow run. Verify the dispatched run
  actually starts; do not assume.
- **TR3.** The dispatch must not convert a `MISMATCH` into a green-looking run. The existing
  Sentry heartbeat conjunct and the `delivered` gate keep their current semantics; a failed
  dispatch is an error annotation, not a silent pass.
- **TR4.** Resolve whether `github_repository_file` under the pinned `integrations/github
  ~> 6.10` (`infra/github/versions.tf:12-13`) requires `overwrite_on_create = true` for the
  first apply against the already-populated path, against the provider schema — not by
  assumption. The live file exists, so a plain create would 422.
- **TR5.** The `[ack-destroy]` destroy-guard must be exercised against the new resources; the
  plan for the first apply must show adoptions and zero destroys.
- **TR6.** `archive_on_destroy = true` on `github_repository.soleur_marketplace` stays untouched.

## Acceptance Criteria

- **AC1.** `gh api repos/jikig-ai/soleur-marketplace/rulesets` returns a non-empty array with the
  new ruleset `active` and the three FR2 bypass actors.
- **AC2.** An unprivileged direct push to `main` on the marketplace repo is rejected.
- **AC3.** Editing `infra/github/soleur-marketplace-manifest.json` in a merged PR causes the
  published `.claude-plugin/marketplace.json` to match it, via a green `apply-github-infra` run.
- **AC4.** A `workflow_dispatch` of `scheduled-marketplace-drift.yml` against an
  intentionally-drifted manifest files the issue **and** triggers an apply that restores it,
  with the issue body still recording the original findings verbatim.
- **AC5.** A simulated `plugin_manifest_unresolvable`-only verdict files an issue and dispatches
  **nothing** (FR8).
- **AC6.** `apply-github-infra` is green end-to-end with FR1 and FR4 both live — the G4
  no-deadlock property.
- **AC7.** ADR-182 carries the FR10 amendment, including the corrected reconciliation claim.

## Risks

| Risk | Mitigation |
|---|---|
| Ruleset blocks the App's file write → unattended apply wedges | FR2 `Integration` bypass actor, declared in the same PR. AC6 is the explicit test. |
| Auto-remediation destroys forensic evidence of an attack | FR7 orders issue-delivery before dispatch; findings are already captured sanitized-verbatim in the issue body, and the marketplace repo's git history retains the edit. |
| First apply proposes CREATE against live objects and 422s | FR6 adoption-by-import, mirroring `import_repository` (`infra/github/README.md`). |
| The `Integration` bypass widens who can push unreviewed | Net-negative risk: the App can already push that repo unreviewed today. Post-change its write originates from a CODEOWNERS-reviewed file in this monorepo. |
| Reconcile flapping between Terraform and a human editor | FR1 makes a competing human write require a PR, so the flap cannot form. Revisit only if observed. |
