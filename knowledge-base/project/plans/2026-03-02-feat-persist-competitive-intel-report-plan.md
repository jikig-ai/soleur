---
title: "feat: persist competitive intelligence report as living document"
type: feat
date: 2026-03-02
---

# Persist Competitive Intelligence Report as Living Document

## Overview

Add a shell step to `scheduled-competitive-analysis.yml` that pushes the agent-generated `competitive-intelligence.md` report directly to main. The report becomes a living document in `knowledge-base/overview/` alongside `brand-guide.md` and `business-validation.md`.

Related: #353, brainstorm at `knowledge-base/brainstorms/2026-03-02-living-competitive-intel-brainstorm.md`

## Problem Statement

The competitive-intelligence agent writes `knowledge-base/overview/competitive-intelligence.md` during scheduled GitHub Action runs, but the CI workspace is ephemeral. The file is discarded after the workflow completes. Agents that read from `knowledge-base/overview/` (CPO, brand-architect) cannot access competitive intelligence from disk. Humans must search GitHub Issues.

## Proposed Solution

Add a single shell step after `claude-code-action` in `.github/workflows/scheduled-competitive-analysis.yml` that pushes the report directly to main.

**Why direct push instead of PR?** The original plan used `gh pr merge --squash --auto`, but SpecFlow analysis revealed three blockers:
1. `allow_auto_merge` is OFF on this repo — `--auto` fails immediately
2. GITHUB_TOKEN cascade limitation — bot PRs don't trigger CI/CLA workflows, so required checks never pass
3. No branch protection ruleset blocks regular pushes to main (only force-push and deletion are blocked)

Direct push is simpler, fully autonomous, and avoids all PR/auto-merge complexity.

### `.github/workflows/scheduled-competitive-analysis.yml`

**Permission change (line 19):**

```yaml
permissions:
  issues: write
  contents: write          # was: read
  id-token: write
```

**New step after "Run scheduled skill" (after line 50):**

```yaml
      - name: Persist competitive intelligence report
        run: |
          FILE="knowledge-base/overview/competitive-intelligence.md"
          if [ ! -f "$FILE" ]; then
            echo "::warning::Report file not found, skipping persist step"
            exit 0
          fi

          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

          git add "$FILE"

          # Skip if report content is identical to what's on main
          if git diff --cached --quiet; then
            echo "::notice::Report unchanged, skipping"
            exit 0
          fi

          git commit -m "docs: update competitive intelligence report"

          # Retry with rebase if main has diverged during the run
          git push origin main || {
            git pull --rebase origin main
            git push origin main
          }
```

## Acceptance Criteria

- [ ] Workflow permission updated to `contents: write` (was: `read`)
- [ ] New "Persist competitive intelligence report" step added after Claude step
- [ ] Step only runs when Claude step succeeds (default behavior)
- [ ] Missing file produces `::warning::` and exits 0, not failure
- [ ] Identical content produces no commit (no-op with `::notice::`)
- [ ] Commit uses `github-actions[bot]` identity
- [ ] Push retries with rebase if main has diverged
- [ ] GitHub Issue creation preserved (existing behavior untouched)

## Test Scenarios

- Given the agent writes the report file, when the persist step runs, then the file is committed and pushed to main
- Given the agent fails to write the file, when the persist step runs, then a warning is logged and the step exits 0
- Given an identical report to what's on main, when `git diff --cached --quiet` succeeds, then no commit is created
- Given main has diverged during the run, when `git push` fails, then it retries with `git pull --rebase` and succeeds
- Given the Claude step fails, when `if: success()` evaluates, then the persist step is skipped entirely

## Context

- **Single file changed:** `.github/workflows/scheduled-competitive-analysis.yml`
- **No plugin changes:** No version bump required
- **No new dependencies:** Uses only `git` CLI (available in `ubuntu-latest`)
- **No `[skip ci]`:** Removed from commit message — GitHub ignores it for PR-triggered workflows anyway, and direct pushes to main should trigger CI normally (validates the commit)
- **No `GH_TOKEN` env:** Not needed — direct push uses the checkout token, not `gh` CLI

## References

- Workflow: `.github/workflows/scheduled-competitive-analysis.yml`
- Agent: `plugins/soleur/agents/product/competitive-intelligence.md`
- Spec: `knowledge-base/specs/feat-living-competitive-intel/spec.md`
- SpecFlow analysis: auto-merge disabled, GITHUB_TOKEN cascade, no PR-blocking rulesets
- Learning: `knowledge-base/learnings/2026-02-27-competitive-intelligence-agent-implementation.md`
- Learning: `knowledge-base/learnings/integration-issues/github-actions-auto-release-permissions.md`
