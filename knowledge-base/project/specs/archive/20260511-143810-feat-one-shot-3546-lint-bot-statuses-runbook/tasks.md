---
title: "Tasks — ops(ci): document lint-bot-statuses runbook"
plan: knowledge-base/project/plans/2026-05-11-ops-ci-document-lint-bot-statuses-runbook-plan.md
issue: 3546
---

# Tasks

## 1. Phase 1 — Author the runbook

- 1.1. Read the three template runbooks: `skill-security-scan-required-check.md`, `codeql-bot-coverage.md`, `ruleset-bypass-drift.md`. Pick `codeql-bot-coverage.md` as the primary template (most recent, last_updated 2026-05-11).
- 1.2. Create `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md` with the frontmatter template from the plan.
- 1.3. Write the **Trigger** section: when an operator should read this runbook (CI failure, adding a required check, adding a bot workflow, debugging a stuck bot PR).
- 1.4. Write the **What this lint is (and isn't)** section: PR-time auto-merge-deadlock guard, NOT a code-quality lint, NOT a runtime check on the bot's PR.
- 1.5. Write the **The as-built behavior** section:
  - 1.5.1. Subsection for `lint-bot-synthetic-statuses.sh` (rejects `[skip ci]`).
  - 1.5.2. Subsection for `lint-bot-synthetic-completeness.sh` (verifies synthetics for each entry in `scripts/required-checks.txt`).
  - 1.5.3. Subsection for the App-token escape hatch (`gh pr create` in `prompt:` blocks is exempt).
- 1.6. Write the **Required-checks config** section: pointer to `scripts/required-checks.txt`, the `CodeQL` exclusion rationale (cite the file's own comment block), the two-source-of-truth pairing with `.github/actions/bot-pr-with-synthetic-checks/action.yml`.
- 1.7. Write the **Drift triage** section with the five failure modes from acceptance criterion 3.
- 1.8. Write the **How to extend** section with the three-edit recipe for adding a new required check and the test-fixture pointer.
- 1.9. Write the **Cross-references** section linking sibling runbooks, the composite action, and the test fixture.
- 1.10. Write the **Re-evaluation** section per the issue body.

## 2. Phase 2 — Bidirectional cross-references

- 2.1. Verify the existing reference in `skill-security-scan-required-check.md` to `lint-bot-statuses` links to the new runbook path (edit if it links to a script or a non-existent file).
- 2.2. Add a cross-reference row in `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` § Cross-references.
- 2.3. Add a cross-reference row in `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` cross-references section.

## 3. Phase 3 — Verification

- 3.1. Run the verification grep block from the plan's Phase 3 to confirm the new file exists, cross-references resolve, and CI lint scripts still pass locally.
- 3.2. Confirm `git status` shows only the four files (1 new, 3 edits) listed in the plan.
- 3.3. Open the PR with `Closes #3546` on its own line and `Ref #3542 #2719` for lineage.

## 4. PR + merge

- 4.1. Push branch and open PR.
- 4.2. Verify `lint-bot-statuses` CI job passes on the PR (it should — this PR does not touch any scheduled workflow).
- 4.3. Apply auto-merge once review-bot approves: `gh pr merge <N> --squash --auto`.
- 4.4. Poll `gh pr view <N> --json state --jq .state` until `MERGED`, then run `cleanup-merged`.
