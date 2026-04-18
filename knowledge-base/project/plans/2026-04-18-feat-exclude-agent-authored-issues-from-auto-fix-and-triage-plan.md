# feat: exclude agent-authored issues from auto-fix and auto-triage

**Issue:** #2344
**PR:** #2533 (draft)
**Branch:** `feat-exclude-agent-issues-auto`
**Worktree:** `.worktrees/feat-exclude-agent-issues-auto/`
**Milestone:** Phase 3: Make it Sticky (from #2344)
**Priority:** `priority/p2-medium`
**Type:** `type/feature`
**Domain:** `domain/engineering`, `domain/product`

## Overview

Turn the ad-hoc `ux-audit` filter that currently exists in two scheduled workflows into a **first-class, documented governance pattern** for excluding agent-authored GitHub issues from automation loops (auto-fix, auto-triage, and any future issue-consuming workflows).

Today the load-bearing rule from the brainstorm (`2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md` — "Exclude label from auto-fix and auto-triage workflows … row 5 is the load-bearing one. Without it the other four are just speed bumps.") lives as a single hard-coded label (`ux-audit`) sprinkled across two jq filters. The next agent-authored stream (e.g. `ux-audit` on a different surface, `seo-audit`, `legal-audit`, CodeQL-to-issues expansions, scheduled community monitor findings) has to re-discover the pattern and copy/paste the filter. That's exactly how governance loops get re-introduced.

Goal: make exclusion declarative at two layers:

1. **`fix-issue` skill** accepts `--exclude-label` as a first-class option that any caller (scheduled-bug-fixer, future schedulers, manual invocation) can pass to avoid picking up agent-authored issues.
2. **Auto-consuming workflows** (`scheduled-daily-triage`, `scheduled-bug-fixer`, and any future ones) share a single canonical exclusion list derived from a documented convention: `ux-audit` (legacy), plus the `agent:*` label family that already tags `agent:ux-design-lead` issues and is the documented convention for future agent-authored streams.

Non-goals (kept out of scope):

- Changing the `ux-audit` skill or any agent's labeling behavior (those already label correctly — see `scheduled-ux-audit.yml` labels `ux-audit` + `agent:ux-design-lead`).
- Building a generic "agent-authored detection" layer (e.g. parsing PR author metadata). Label-based exclusion is the documented mechanism (brainstorm pattern 2, row 4–5).
- Adding new agent-authored issue streams. This plan makes the opt-in available; adopters land in their own PRs.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #2344) | Reality in codebase | Plan response |
|---|---|---|
| "Add `--exclude-label ux-audit` to `fix-issue` skill" | `fix-issue` SKILL.md takes exactly one input (`$ARGUMENTS` = issue number). It does not accept flags or an exclude list today. Filtering happens **upstream in `scheduled-bug-fixer.yml`**, not in the skill. | Add the `--exclude-label` flag as a real skill-level option (parsed from `$ARGUMENTS`) so manual invocations and future callers can pass it. Keep upstream workflow-level filters too — defense-in-depth matches the existing auto-merge-gate pattern. |
| "any auto-triage workflow" | Only one exists: `scheduled-daily-triage.yml`. It already excludes `ux-audit` via an inline jq filter. | Generalize the filter to exclude the entire documented label family (`ux-audit` + `agent:*`) and extract it into a canonical jq snippet reused across workflows. |
| "Document the pattern as a first-class opt-in for other agent-authored issue streams" | Pattern documented only in one learning file (`2026-04-15-brainstorm-calibration-pattern-...md`). No runbook or convention page exists. | Add a short reference doc — `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` — and cross-link from the learning, from `scheduled-ux-audit.yml` top comment, and from the two consumer workflows. |
| Issue says: "Blocker-for-merge of #2341" | #2341 is already **CLOSED** (shipped) with hard-coded `ux-audit` exclusion in both consumer workflows. The governance loop is already broken in practice. | This is a hardening PR that generalizes an already-working mitigation — not an outage fix. Priority stays `priority/p2-medium`. |

## Files to edit

- `plugins/soleur/skills/fix-issue/SKILL.md` — add `## Inputs` section describing accepted args, add `## Phase 0: Parse arguments` that extracts `--exclude-label` values into `$EXCLUDE_LABELS`, teach Phase 1 to short-circuit with a benign exit message when the issue carries any excluded label.
- `.github/workflows/scheduled-bug-fixer.yml` — replace the single hard-coded `ux-audit` jq clause (line 106) with a loop that excludes both `ux-audit` AND any label starting with `agent:`. Pass `--exclude-label ux-audit --exclude-label agent:*` to the skill invocation as defense-in-depth.
- `.github/workflows/scheduled-daily-triage.yml` — replace the single-label jq filter (line 76) with the same canonical pattern.
- `knowledge-base/project/learnings/2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md` — add a "See also" link to the new reference doc so the institutional learning points at the enforcement surface.

## Files to create

- `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` — canonical opt-in doc: label convention (`agent:<role>` + stream-specific tag like `ux-audit`), which workflows honor it, how to add a new stream, how to test.
- `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md` — the exact jq clause referenced from both workflows, so the next editor touches one file when the list changes.

No new top-level files, no schema changes, no migration, no dependencies.

## Implementation Phases

### Phase 1 — Skill surface: parse `--exclude-label` in fix-issue

Edit `plugins/soleur/skills/fix-issue/SKILL.md`:

- Add `## Inputs` section (before `## Constraints`):
  - `$ARGUMENTS` accepts one of: `<issue-number>` OR `<issue-number> --exclude-label <label> [--exclude-label <label> …]`.
  - Bare numbers still work (backward compatible with existing `scheduled-bug-fixer.yml` prompt: `Run /soleur:fix-issue $ISSUE_NUMBER`).
- Add `## Phase 0: Parse arguments`:
  - Extract issue number (first positional arg).
  - Collect all `--exclude-label <val>` pairs into an `$EXCLUDE_LABELS` array (shell; shown as pseudocode in the skill markdown).
- In `## Phase 1: Read and Validate`, after fetching the issue JSON, add an **agent-authored short-circuit** check:
  - If any label in the issue intersects `$EXCLUDE_LABELS` (exact match), exit with a benign message: `"Issue #N carries excluded label '<label>'. fix-issue will not operate on agent-authored issues."` No failure-handler label, no PR, no comment — the scheduler already skipped it upstream; this is defense-in-depth for manual invocations.
  - Wildcard support: if an exclude-label arg ends in `*` (e.g. `agent:*`), treat it as a prefix match. Document this explicitly.

Test manually (no shell-level tests exist for the skill; behavior tested via the workflow dry-run in Phase 3):

- `claude /soleur:fix-issue 2378 --exclude-label ux-audit` on an actual `ux-audit` issue should print the benign exit and create nothing.
- `claude /soleur:fix-issue <normal-bug>` (no flags) should behave exactly as today.

### Phase 2 — Canonical jq snippet + workflow adoption

Create `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md`:

- Contains the canonical clause (two forms — one for list-then-filter, one inline) that excludes any issue whose labels include `ux-audit` OR any label starting with `agent:`.
- Documented as copy-paste into `gh issue list --jq …` consumers.

Example canonical clause (the doc should present this verbatim, with a comment block explaining each branch):

```jq
# Exclude agent-authored issues (see plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md).
# - ux-audit: legacy stream-specific tag still in active use.
# - agent:*: canonical agent-authored prefix; adopted by any future agent-native skill
#   that files issues.
map(select(
  (.labels | map(.name) | index("ux-audit") | not) and
  (.labels | map(.name) | any(startswith("agent:")) | not)
))
```

Edit `.github/workflows/scheduled-daily-triage.yml`:

- Line 76: replace the inline `index("ux-audit") | not` clause with the canonical clause above.
- Update the surrounding comment to cite `agent-authored-exclusion.md` rather than explaining the filter inline.

Edit `.github/workflows/scheduled-bug-fixer.yml`:

- Line ~100–107: extend the per-priority `gh issue list --jq` to exclude the same label family. Match `scheduled-daily-triage.yml` — same clause verbatim.
- In the `Fix issue` step (line ~129), append `--exclude-label ux-audit --exclude-label agent:*` to the skill prompt so the skill independently verifies (defense-in-depth): `Run /soleur:fix-issue ${{ steps.select.outputs.issue }} --exclude-label ux-audit --exclude-label 'agent:*'`.

### Phase 3 — Documentation + cross-links

Create `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md`. Contents:

1. **Why this exists.** One-paragraph summary of the governance loop (cite the 2026-04-15 learning). Emphasize: label-based exclusion is the load-bearing mechanism.
2. **Label convention.** Every agent-native skill that files GitHub issues MUST apply:
   - A **stream tag** (e.g. `ux-audit`) identifying the source agent/skill — matches the existing `ux-audit` label.
   - An **`agent:<role>` label** (e.g. `agent:ux-design-lead`, `agent:ticket-triage`) identifying the authoring agent.
   - Reference `scheduled-ux-audit.yml` lines 58–63 as the canonical example.
3. **Workflows that honor exclusion.** List `scheduled-bug-fixer.yml` and `scheduled-daily-triage.yml` with the exact lines that filter. Any future issue-consuming workflow MUST include the canonical jq clause from `exclude-label-jq-snippet.md` and the `--exclude-label ux-audit --exclude-label 'agent:*'` flag on any `fix-issue` invocation.
4. **Adding a new agent-authored stream.** 5-bullet checklist:
   - Apply both the stream tag AND `agent:<role>` label at `gh issue create` time.
   - If the stream tag is new (not `ux-audit`), add it to the canonical jq clause in `exclude-label-jq-snippet.md` AND to both consumer workflows.
   - Default milestone `Post-MVP / Later` (brainstorm pattern 2, row 1).
   - Add per-run cap and global cap to the authoring skill.
   - Announce the new stream in the PR description so reviewers verify the exclusion.
5. **How to test.** Three manual checks: run the authoring skill end-to-end in dry-run, run daily-triage with a workflow_dispatch, run the bug-fixer manually with the new stream's label on a test issue to confirm it's skipped.

Edit `knowledge-base/project/learnings/2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md`:

- Append a "Routed to definition" block at the bottom citing `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` as the enforcement surface.

Edit `.github/workflows/scheduled-ux-audit.yml`:

- Top-of-file comment: add a one-line pointer to `agent-authored-exclusion.md` so future editors see the governance contract from here too.

### Phase 4 — Verify

1. **Run `markdownlint-cli2 --fix`** on the three new/modified `.md` files (targeted paths per [cq-markdownlint-fix-target-specific-paths]).
2. **Syntax-check workflow YAML** with `actionlint` or `yamllint` locally (the two modified workflows — the jq change is a string, not YAML structure, but we still want to eyeball indentation).
3. **Manual workflow_dispatch of `scheduled-daily-triage.yml`** in the PR branch (after push) to confirm the generalized filter doesn't regress — no `ux-audit` issues should be triaged, and no current non-agent issue should be dropped.
4. **Manual workflow_dispatch of `scheduled-bug-fixer.yml`** with `inputs.issue_number` set to an actual `ux-audit` issue (e.g. the first finding filed by `scheduled-ux-audit`). Expected: the skill's Phase 1 short-circuit logs the benign exit message and no PR is opened.
5. **Regression check for normal p3-low bug flow:** trigger `scheduled-bug-fixer.yml` without `issue_number` input against a real `priority/p3-low` `type/bug` issue. Expected: unchanged behavior — the skill runs, opens a PR, labels it, auto-merge gate evaluates.

All four verifications are per [wg-when-a-feature-creates-external] (every new/changed mechanism is exercised once before merge) and [wg-after-merging-a-pr-that-adds-or-modifies] (post-merge workflow validation).

## Acceptance Criteria

- [ ] `plugins/soleur/skills/fix-issue/SKILL.md` parses `--exclude-label` (multi-value, supports `*` suffix wildcard for prefix matching like `agent:*`) and exits benignly when the issue carries any excluded label.
- [ ] Backward compatibility: `claude /soleur:fix-issue <number>` (bare) still works and behaves as before.
- [ ] `scheduled-bug-fixer.yml` selection step excludes `ux-audit` AND any `agent:*` label via the canonical jq clause.
- [ ] `scheduled-bug-fixer.yml` invokes the skill with `--exclude-label ux-audit --exclude-label 'agent:*'` (defense-in-depth).
- [ ] `scheduled-daily-triage.yml` uses the same canonical jq clause.
- [ ] `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` exists and documents: the label convention, which workflows honor it, the 5-bullet "add a new agent-authored stream" checklist, and the manual test plan.
- [ ] `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md` exists and is referenced from both consumer workflows' comment blocks.
- [ ] The 2026-04-15 governance learning file carries a "Routed to definition" pointer to the new reference.
- [ ] Manual `workflow_dispatch` runs of `scheduled-daily-triage.yml` and `scheduled-bug-fixer.yml` (with and without `ux-audit` issues in the queue) produce expected behavior.
- [ ] Manual regression: a real `priority/p3-low` `type/bug` issue is still fixable end-to-end.

## Test Scenarios

Infrastructure/tooling changes have no code-level tests. The skill-level change is test-exempt under [cq-write-failing-tests-before] (infrastructure/tooling-only task). Verification is the 5-step Phase 4 manual plan above.

## Risks

- **Wildcard parsing in the skill (`agent:*`) is a new surface.** Risk: the glob-to-prefix translation in the skill's Phase 0 parser is subtle. Mitigation: the skill is markdown-level pseudocode that the agent interprets at runtime — the prompt explicitly says "treat trailing `*` as prefix match." No regex injection risk because the exclude-label args come from workflow YAML, not user input.
- **Label convention drift.** If a future agent-authored skill forgets the `agent:<role>` label, the exclusion silently fails. Mitigation: the 5-bullet checklist in `agent-authored-exclusion.md` is the contract; reviewer of any new agent-native PR must verify both labels are applied. Consider adding a CI lint in a follow-up (not this PR) that asserts any new `gh issue create` with `--label ux-audit-like-tag` also sets an `agent:*` label.
- **jq clause generalization could accidentally skip legitimate issues.** Mitigation: Phase 4 step 3 runs the generalized filter against the live tracker before merge; any drop is visible.
- **Skill defense-in-depth collides with scheduler filter.** If the scheduler already filters and the skill ALSO skips, there's zero observable behavior change on the happy path. That's the intent; the short-circuit fires only for manual invocations or misconfigured schedulers.

## Open Code-Review Overlap

None. Scanned `gh issue list --label code-review --state open` (64 open). No open code-review issue mentions `plugins/soleur/skills/fix-issue/SKILL.md`, `scheduled-bug-fixer.yml`, or `scheduled-daily-triage.yml`.

## Domain Review

**Domains relevant:** engineering, product

### Engineering (CTO)

**Status:** reviewed (planner assessment; governance/tooling change inside existing CI surfaces — no new architecture, no new dependencies, no infrastructure provisioning).
**Assessment:** The change is well-bounded: one skill markdown edit, two workflow string edits, two small reference docs. The defense-in-depth pattern (filter upstream + re-check in the skill) matches the existing auto-merge-gate pattern in `scheduled-bug-fixer.yml` (lines 157–212 re-check file count and priority even though the skill already applied the label). No architectural implications; CTO full invocation not required.

### Product (CPO)

**Tier:** NONE.
**Rationale:** The plan adds a skill flag and a jq filter. It discusses agent-authored issue flows but implements zero user-facing surface (no new pages, no new components, no modal, no UI text). Mechanical escalation rule (new `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) — no matches. CPO full invocation skipped.

No wireframes, no copywriter review, no spec-flow-analyzer invocation.

## Alternatives Considered

| Approach | Rejected because |
|---|---|
| Hard-code a second label (`ux-audit` and `codeql-auto`) in each workflow when we hit the next agent-authored stream | This is exactly the pattern #2344 is trying to prevent. |
| Detect agent authorship via PR author (`[bot]` suffix) instead of label | PRs and issues are different objects — issues have no author slug; even if they did, authorship is set by the agent's token, which can change. Labels are stable and declarative. |
| Build a dedicated "agent-issue-registry" workflow that re-labels daily | Over-engineered for the current footprint (1 active agent-authored stream). The label-convention approach scales to N streams with zero new moving parts. |
| Put the jq clause directly in `AGENTS.md` as a hard rule | AGENTS.md is for rules the agent would violate without prompting on every turn. A jq snippet belongs in a reference doc. AGENTS.md gets a pointer in the existing "When deferring a capability, create a GitHub issue" gate family if needed, but not required for this PR. |

## Deferral Tracking

None. This plan consumes a deferral (#2344 was itself a deferral from #2341's brainstorm) and introduces no new ones.

## PR Metadata (for /ship)

- **Title:** `feat(governance): exclude agent-authored issues from auto-fix and auto-triage`
- **Body closes:** `Closes #2344`
- **Semver label:** `semver:patch` (additive governance hardening; no new agent, skill, or user-facing capability — the `fix-issue` skill's input surface extension is backward compatible).
- **Labels:** `type/feature`, `domain/engineering`, `domain/product`, `priority/p2-medium` (inherited from #2344).
- **Changelog section:**

  ```markdown
  ## Changelog

  - Added `--exclude-label` option to the `fix-issue` skill (backward compatible).
  - Generalized the agent-authored exclusion filter in `scheduled-bug-fixer.yml` and `scheduled-daily-triage.yml` to cover `ux-audit` and any `agent:*` label.
  - Documented the governance pattern in `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` as a first-class opt-in for future agent-native issue streams.
  ```
