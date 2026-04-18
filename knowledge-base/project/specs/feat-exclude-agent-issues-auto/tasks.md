# Tasks: feat-exclude-agent-issues-auto

**Plan:** `knowledge-base/project/plans/2026-04-18-feat-exclude-agent-authored-issues-from-auto-fix-and-triage-plan.md`
**Issue:** #2344
**PR:** #2533 (draft)

## Phase 1 — Skill surface

- [ ] 1.1 Read `plugins/soleur/skills/fix-issue/SKILL.md` (fresh, pre-edit)
- [ ] 1.2 Add `## Inputs` section documenting `$ARGUMENTS` shape (issue number + optional `--exclude-label <val>` pairs)
- [ ] 1.3 Add `## Phase 0: Parse arguments` block with pseudocode for extracting issue number and `$EXCLUDE_LABELS` array
- [ ] 1.4 Edit `## Phase 1: Read and Validate` to add the agent-authored short-circuit (benign exit on excluded-label match; supports trailing `*` as prefix match)
- [ ] 1.5 Verify backward compatibility: bare `$ARGUMENTS=<number>` still parses as before

## Phase 2 — Canonical jq snippet and workflow adoption

- [ ] 2.1 Create `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md` with the canonical clause (inline and list-filter forms)
- [ ] 2.2 Edit `.github/workflows/scheduled-daily-triage.yml` line 76: replace the single-label filter with the canonical clause; update inline comment to cite the reference doc
- [ ] 2.3 Edit `.github/workflows/scheduled-bug-fixer.yml` selection step (lines ~100–107): replace `index("ux-audit") | not` with the canonical clause
- [ ] 2.4 Edit `.github/workflows/scheduled-bug-fixer.yml` `Fix issue` step prompt: append `--exclude-label ux-audit --exclude-label 'agent:*'` to the skill invocation (defense-in-depth)

## Phase 3 — Documentation and cross-links

- [ ] 3.1 Create `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` with the 5 sections (why, label convention, honoring workflows, new-stream checklist, how to test)
- [ ] 3.2 Edit `knowledge-base/project/learnings/2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md`: append "Routed to definition" block pointing at the new reference
- [ ] 3.3 Edit `.github/workflows/scheduled-ux-audit.yml` top comment: add a one-line pointer to `agent-authored-exclusion.md`

## Phase 4 — Verify

- [ ] 4.1 Run `npx markdownlint-cli2 --fix` on the three `.md` files touched/created (targeted paths only per [cq-markdownlint-fix-target-specific-paths])
- [ ] 4.2 Syntax-check the two workflow YAMLs locally (`actionlint` if available, or visual diff)
- [ ] 4.3 Push branch, then `gh workflow run scheduled-daily-triage.yml --ref feat-exclude-agent-issues-auto` — confirm no regression
- [ ] 4.4 `gh workflow run scheduled-bug-fixer.yml --ref feat-exclude-agent-issues-auto -f issue_number=<a-real-ux-audit-issue>` — confirm skill Phase 1 short-circuits and no PR is opened
- [ ] 4.5 `gh workflow run scheduled-bug-fixer.yml --ref feat-exclude-agent-issues-auto` (no input) — confirm normal p3-low bug flow still runs end-to-end
- [ ] 4.6 Poll run status via Monitor until all three workflow runs complete; investigate any failure per [hr-when-a-command-exits-non-zero-or-prints]

## Phase 5 — Ship

- [ ] 5.1 Run `skill: soleur:compound` to capture learnings from implementation
- [ ] 5.2 Run `skill: soleur:review` (full multi-agent review per [rf-never-skip-qa-review-before-merging])
- [ ] 5.3 Address any P1/P2/P3 review findings inline on this branch (per [rf-review-finding-default-fix-inline])
- [ ] 5.4 Run `skill: soleur:ship` to finalize PR: set `semver:patch` label, add Changelog section, mark PR ready for review, verify `Closes #2344` is in PR body, queue auto-merge
- [ ] 5.5 Post-merge: verify `scheduled-bug-fixer` and `scheduled-daily-triage` next scheduled runs complete green (per [wg-after-merging-a-pr-that-adds-or-modifies])
