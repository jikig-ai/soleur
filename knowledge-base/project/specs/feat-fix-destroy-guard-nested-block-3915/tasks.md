---
plan: knowledge-base/project/plans/2026-05-25-fix-destroy-guard-nested-block-removal-plan.md
branch: feat-fix-destroy-guard-nested-block-3915
lane: single-domain
closes: 3915
---

# Tasks — fix: destroy-guard nested-block removal (#3915)

Hierarchical task breakdown derived from `2026-05-25-fix-destroy-guard-nested-block-removal-plan.md` (v2 — post plan-review). Mark each task as completed via `- [x]` as it lands.

## 1. Preconditions

- [ ] 1.1 Confirm worktree CWD = `.worktrees/feat-fix-destroy-guard-nested-block-3915` (bare repo from `pwd` would clobber working state)
- [ ] 1.2 Tooling probe: `command -v jq actionlint shellcheck terraform` returns all four
- [ ] 1.3 Read `.github/workflows/apply-github-infra.yml:234-251` to lift exact byte boundaries of the inline destroy-guard
- [ ] 1.4 Read `.github/workflows/apply-github-infra.yml:244` for the `[ack-destroy]` regex (must be preserved byte-identical)
- [ ] 1.5 Confirm `.github/CODEOWNERS:74` still routes `/infra/github/` to `@deruelle` (no edit required)

## 2. RED — failing tests + fixtures

- [ ] 2.1 Create `tests/scripts/fixtures/` directory
- [ ] 2.2 Synthesize `tfplan-nested-block-removal.json` — `github_repository_ruleset.ci_required`, `actions:["update"]`, `required_check[]` length 15 → 14
- [ ] 2.3 Synthesize `tfplan-no-changes.json` — empty `resource_changes`
- [ ] 2.4 Synthesize `tfplan-resource-delete.json` — resource with `actions:["delete"]`, `before` populated, `after:null`
- [ ] 2.5 Capture `tfplan-real-ruleset-baseline.json`:
  - [ ] 2.5.1 `cd infra/github && terraform init -backend=false && terraform plan -refresh=false -out=tfplan`
  - [ ] 2.5.2 `terraform show -json tfplan > /tmp/raw.json`
  - [ ] 2.5.3 Redact via `jq 'del(.. | .bypass_actors? | .[]?.actor_id?)' /tmp/raw.json > tests/scripts/fixtures/tfplan-real-ruleset-baseline.json`
  - [ ] 2.5.4 Manual scan: no actor_id integers, no token-shaped strings
- [ ] 2.6 Create `tests/scripts/test-destroy-guard-counter.sh` with 4 cases (per Test Scenarios table in plan)
- [ ] 2.7 Run test: must FAIL on missing `tests/scripts/lib/destroy-guard-filter.jq` — this is the RED state

## 3. GREEN — filter + workflow edit

- [ ] 3.1 Create `tests/scripts/lib/destroy-guard-filter.jq` with the path-specific filter from plan §Phase 2.1
  - Uses `$side` value-arg (NOT `(before; after)` filter-arg — that's Kieran's P0-1)
  - No recursion (path-specific to `github_repository_ruleset.*.rules[].required_status_checks[].required_check[]`)
  - Returns `{resource_deletes, nested_deletes}` object
- [ ] 3.2 Edit `.github/workflows/apply-github-infra.yml` "Destroy guard" step with the new body (plan §Phase 2.2)
  - Preserve `working-directory: ${{ env.INFRA_DIR }}`
  - Preserve `env: HEAD_MSG: ${{ github.event.head_commit.message }}`
  - Use `jq -f "${GITHUB_WORKSPACE}/tests/scripts/lib/destroy-guard-filter.jq"`
  - Sum `destroy_count = resource_deletes + nested_deletes` before gate
  - Preserve `[ack-destroy]` regex byte-identical from line 244
  - Preserve `"on github infra"` literal in error message
- [ ] 3.3 Run `bash tests/scripts/test-destroy-guard-counter.sh` — must exit 0 (GREEN)
- [ ] 3.4 Run `shellcheck -x tests/scripts/test-destroy-guard-counter.sh` — must exit 0
- [ ] 3.5 Run `actionlint .github/workflows/apply-github-infra.yml` — must exit 0

## 4. Pre-ship sanity

- [ ] 4.1 `git grep -nE 'resource_changes\[\?\]\?.*delete.*length' .github/workflows/apply-github-infra.yml` returns zero matches (AC5 part 1 — old filter gone)
- [ ] 4.2 `git grep -nE 'destroy_count=\$\(' .github/workflows/apply-github-infra.yml` returns exactly one match (AC5 part 2 — new assignment present)
- [ ] 4.3 `diff` against pre-edit file confirms `[ack-destroy]` regex byte-identical (AC6)
- [ ] 4.4 Draft PR body includes `Closes #3915` line + Test Plan section enumerating the 4 AC2 cases

## 5. Ship

- [ ] 5.1 Commit (suggested message): `fix(ci): widen destroy-guard to catch github_repository_ruleset.required_check removals (#3915)`
- [ ] 5.2 Push branch and create draft PR
- [ ] 5.3 PR body cites `Closes #3915` and `Partially unblocks #4392 (AC20 resolved; AC21 still passive)`
- [ ] 5.4 PR body includes Test Plan section (AC12 — promoted from old plan v1; kept as PR-body content not as AC)
- [ ] 5.5 Run review (`/soleur:review`) — verify no regression in `[ack-destroy]` regex, surface label, or workflow structure
- [ ] 5.6 Mark PR ready, run `/soleur:ship`

## 6. Post-merge (operator)

- [ ] 6.1 AC8 — `gh issue close 3915 --comment "Fixed in <merge-sha>. Path-specific filter now catches nested-block removals; AC20 verified via unit test against PR #4395-shape fixture."`
- [ ] 6.2 AC9 — `gh issue comment 4392 --body "AC20 follow-up resolved by PR <N>. Sibling-workflow gap tracked at #<follow-up-N>. AC21 still passive — next bot PR after #4385 will close it."`
- [ ] 6.3 AC10 — `gh issue create --title "chore: extend destroy-guard widening to apply-sentry-infra and apply-web-platform-infra" --body "<body citing this PR + cap-coupling rationale>" --label chore --label domain/engineering`

## Plan-Review Trail (informational — does NOT need re-execution)

Plan v1 → v2 changes driven by three reviewers (DHH, Kieran, simplicity):

- **Kieran P0-1 + P0-2 (dissolved by v2):** v1 used recursive-walk jq with `def f(before; after)` filter-args and a same-length array stop. Both bugs would have shipped broken (returns 0 on the PR #4395 shape). v2 path-specific filter has no recursion, no filter-args.
- **DHH P0.1 (accepted):** Recursive walk was overengineered for one known failure mode. v2 path-specific.
- **DHH P0.2 (accepted):** Shared script extraction premature. v2 uses a `.jq` file referenced by both workflow and test — single source of truth without an over-shared bash module.
- **DHH P1.3 (accepted):** Cap-coupling to 3 workflows was preemptive. v2 scoped to `apply-github-infra.yml`; sibling workflows tracked at follow-up issue (AC10).
- **DHH P1.4 (accepted):** AC bloat trimmed — 14 ACs → 10 (7 pre-merge, 3 post-merge).
- **DHH P1.5 + Simplicity #3 (accepted):** Test cases 6 → 4.
- **Kieran P1-1 (accepted):** Added captured real-CI fixture as regression anchor.
- **Kieran P1-2/P1-3/P2-4 (accepted):** AC5 strengthened to include `destroy_count=$(` presence check; AC6 pinned to byte-identical regex; error message preserves `"on github infra"` literal.
- **DHH P2.6 (rejected):** "single-user-incident inflated" — user explicitly set this threshold in the original input citing #4333 chain. Kept.
- **Simplicity #1 (rejected):** `grep tfplan.txt for "will be destroyed"` — verified WRONG. The PR #4395 plan output used `- required_check {` minus-prefix on the block opener; `will be destroyed` only appears for resource-level deletes. Sharp Edge documents this so future plan iterations don't re-propose.
