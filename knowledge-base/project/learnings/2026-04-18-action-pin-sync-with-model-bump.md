---
title: claude-code-action pin must be bumped alongside --model changes
date: 2026-04-18
category: integration-issues
module: ci
tags: [claude-code-action, github-actions, opus-4-7, thinking-api, sdk-drift]
related_issues: [2540, 2439]
related_learnings:
  - 2026-02-22-model-id-update-patterns.md
  - 2026-03-20-claude-code-action-max-turns-budget.md
---

# Learning: claude-code-action pin must be bumped alongside `--model` changes

## Problem

After #2439 flipped `--model claude-opus-4-6 → --model claude-opus-4-7` in three
scheduled workflows (ux-audit, competitive-analysis, growth-audit), every run
between 2026-04-15 and 2026-04-18 failed with:

```text
API Error: 4xx invalid_request_error
"thinking.type.enabled" is not supported for this model.
Use "thinking.type.adaptive" and "output_config.effort" to control thinking behavior.
```

The PR that upgraded the model did not also upgrade the `anthropics/claude-code-action`
pin. The pin stayed at `v1.0.75` (SHA `df37d2f0...`), which embeds Agent SDK
`0.2.112`. SDK 0.2.112 emits `thinking.type.enabled` — a shape Opus 4.7 rejects.
Four scheduled runs failed before detection (tracked in #2540).

## Root Cause

Anthropic synchronizes model rollouts with SDK rollouts, but the embedded SDK
in `claude-code-action` lags the API by days. A workflow that forces
`--model <new-model>` against a pin older than the matching SDK bump will send
the deprecated payload shape and get a 400.

Concretely:

- `v1.0.100` (2026-04-17) shipped SDK `0.2.113` which emits `thinking.type.adaptive`.
- `v1.0.100` also flipped the action's **default** model from opus-4-6 to opus-4-7,
  so the same SDK fix is required for workflows that don't pin `--model` explicitly —
  the moment the default kicks in, the old SDK's payload fails.

## Solution

Bumped all 14 workflows pinned at `v1.0.75` to `v1.0.101`
(SHA `ab8b1e6471c519c585ba17e8ecaccc9d83043541`) in a single PR. `scheduled-roadmap-review.yml`
uses a separate older pinned SHA (`ff9acae5... # v1`) and was intentionally left
alone to preserve blast-radius isolation.

## Prevention

Added rule `cq-claude-code-action-pin-freshness` to `AGENTS.md` Code Quality:

> When a PR changes `--model <name>` in `claude_args` of any
> `.github/workflows/*.yml` file, the same PR MUST verify that every
> `anthropics/claude-code-action` pin in the modified files is within ~3 weeks
> of the current release tip.

Audit command:

```bash
# Current tip
gh api repos/anthropics/claude-code-action/releases --jq '.[0] | "\(.tag_name) \(.published_at)"'

# Resolve your pin to a commit date
gh api repos/anthropics/claude-code-action/git/commits/<PIN-SHA> --jq '.committer.date'
```

If the pin is more than ~3 weeks older than current tip AND the PR bumps a
model, bump the pin in the same PR.

### Symmetric rule (the other direction)

When bumping the `claude-code-action` pin, read the release notes for
`Upgrade Claude model from X to Y` entries. If the default flipped, workflows
**without** `--model` will transparently switch model — intentional for most,
but breaking for any workflow with budget or pricing assumptions.

## Session Errors

- **Plan contained factually wrong SHAs.** The plan file cited `8a953ded...` as
  the v1.0.100 fallback SHA — it's actually what the `v1` floating tag resolves
  to. It also described `scheduled-roadmap-review.yml` as "using the floating
  `@v1` ref" when the file is actually pinned to a fixed SHA `@ff9acae5... # v1`.
  Both errors survived the plan+deepen phase and only surfaced in the review
  phase via `code-quality-analyst`. **Prevention:** plan/deepen agents citing
  external SHA-to-version mappings should resolve each claim via `gh api
  repos/.../git/refs/tags/<tag>` before writing it, not rely on recall or
  model memory. Propose a deepen-plan instruction addition: "For any cited
  external SHA or version reference, resolve it via `gh api` in the same
  pass and show the command + output in a fenced block. Do not cite
  SHAs from memory."
- **Spec dir naming collision.** The plan subagent wrote `tasks.md` to
  `knowledge-base/project/specs/feat-one-shot-fix-ux-audit-thinking-api/`
  (matching branch name), but a subsequent session-state write used a
  shortened name `feat-fix-ux-audit-thinking-api/`, producing two sibling
  dirs that had to be consolidated mid-session. **Prevention:** skill
  instructions that reference `feat-<name>` should explicitly say "use the
  exact current branch name from `git branch --show-current`, not an
  abbreviation." One-shot's Step 1 already says to write to
  `knowledge-base/project/specs/feat-<name>/session-state.md` — ambiguity is
  in what `<name>` means when the branch has a workflow prefix like
  `one-shot-`.
- **git-history-analyzer false-positive redundancy claim.** The agent saw
  the fresh push commit SHA `eb5822a6` on my feature branch and concluded
  the PR was redundant with main. Had to verify via `git log origin/main`
  that main still had v1.0.75. **Prevention:** git-history-analyzer should
  verify the target branch of commits before concluding "already merged" —
  file-level `git show origin/main:<path>` is authoritative vs. commit-log
  inspection.
