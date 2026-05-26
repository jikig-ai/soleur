---
title: "Composite-action extraction belongs inline when a multi-file rollout PR creates the Nth copy"
date: 2026-05-18
category: best-practices
tags:
  - github-actions
  - composite-actions
  - code-review
  - scope-out-discipline
  - actionlint
  - workflow-edits
related_prs:
  - 3971
  - 3964
related_issues:
  - 3968
related_learnings:
  - 2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md
  - 2026-05-11-scope-out-bundling-hides-cheap-inline-fixes.md
  - 2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
---

# Composite-action extraction belongs inline when a multi-file rollout PR creates the Nth copy

## Problem

PR #3971 was scoped per #3968 as a mechanical sister-workflow rollout: apply the Sentry-heartbeat pattern from PR #3964 (canonical at `scheduled-oauth-probe.yml:528-559`) to 7 sister `scheduled-*.yml` workflows. Each migration replaced ~30 lines of buggy two-step plumbing with ~25 lines of byte-identical heartbeat plumbing (modulo the per-workflow status-branch logic, which legitimately diverges across 4 truth-tables: `job.status`, `failure_mode`, dual-signal `failure_mode AND tripwire.outcome`, `exit_code`).

After implementation, two of four review agents (pattern-recognition-specialist, code-quality-analyst) independently flagged the resulting 8× block duplication as a P2 dedup opportunity. The natural framing was "defer to a separate composite-action extraction PR" — both agents explicitly recommended deferral with rationales like "Reasonable, not overengineering — but defer" and "extract on 9th heartbeat or first ingest-domain change."

The pipeline filed the deferral as an `architectural-pivot` scope-out. `code-simplicity-reviewer` returned **DISSENT** with reasoning that flipped the disposition to fix-inline.

## Solution

The DISSENT reasoning is the canonical pattern for this class of finding:

> The current "pattern" is literally `Ctrl-C / Ctrl-V of 25 lines of YAML 8 times`. That is not a pattern — it is the absence of one. Extracting a composite action is not a pivot; it is the conventional GitHub Actions remedy for exactly this situation.
>
> "Reasonable, not overengineering — but defer" is a scheduling preference, not a criterion match. The CONCUR gate asks whether the *criterion* fits, not whether the reviewer would personally defer.
>
> "deferred-scope; document the trigger condition (extract on 9th heartbeat or first ingest-domain change)" is itself an admission that the fix is mechanical and trigger-driven — which is the opposite of needing a planning cycle. A fix with a known trigger and a known shape is a fix you do now, because filing it costs more than doing it.

Applied: extracted `.github/actions/sentry-heartbeat/action.yml` (composite action, 5 inputs: `monitor-slug`, `status`, `sentry-{ingest-domain,project-id,public-key}`). Each of 8 call-sites collapsed from ~20 lines of inline `env:` + bash to ~10 lines of `uses:` + `with:`. **Per-workflow status computation stayed at the call-site** as a GHA ternary expression (`${{ <bool-expr> && 'ok' || 'error' }}`) because the 4 truth-tables legitimately diverge:

```yaml
# job.status branch (4 workflows):
status: ${{ job.status == 'success' && 'ok' || 'error' }}

# failure_mode branch (2 workflows):
status: ${{ steps.probe.outputs.failure_mode == '' && 'ok' || 'error' }}

# dual-signal branch (1 workflow — drift-guard):
status: ${{ steps.check.outputs.failure_mode == ''
            && steps.tripwire.outcome != 'failure'
            && 'ok' || 'error' }}

# exit_code branch (1 workflow — terraform-drift):
status: ${{ (steps.plan.outputs.exit_code == '0'
             || steps.plan.outputs.exit_code == '2')
            && 'ok' || 'error' }}
```

Net diff: -229 lines, +162 lines across 10 files (new action + 8 workflow rewrites + tasks.md AC update). Single PR landed both the migration AND the dedup.

## Key Insight

**When a PR creates the Nth byte-identical copy of a block, the extraction PR is THIS PR.** The "extract on 9th heartbeat" or "extract on next change" trigger is itself the criterion failing — if the right time to extract is whenever someone next touches this, then the right time is whoever is currently touching it, because they have the full context loaded. Filing as scope-out costs more (issue write + future triage + context reload + 8-file re-edit after diff has rotted) than doing it now (~30 LOC composite + 8 × ~5-line call-site edits with full context loaded).

The four scope-out criteria all fail concretely:

- **cross-cutting-refactor:** 8 files but all under `.github/workflows/scheduled-*.yml` (same top-level dir, same purpose) — materially RELATED, criterion fails.
- **contested-design:** Both reviewers named one approach (composite action). No second approach with tradeoffs surfaced.
- **architectural-pivot:** Composite-action extraction is the textbook GHA remedy for inline-block duplication; no design space to explore (inputs `monitor-slug` + `status`, body is the curl). No planning cycle needed.
- **pre-existing-unrelated:** PR #3971 introduced 7 of 8 copies; the duplication did NOT exist on main at this scale before this PR.

The `code-simplicity-reviewer` CONCUR/DISSENT gate is the load-bearing check that catches this class — the original reviewer agents will recommend defer because it's a scheduling preference, but the gate asks the strict question of whether the criterion FITS, not whether deferral feels reasonable.

## Prevention

When applying the review-finding triage, before invoking the CONCUR gate, self-check the following predicate:

1. Did THIS PR add ≥3 byte-identical copies of the block being flagged?
2. Is the proposed fix a mechanical extraction (no design alternatives the reviewer can name)?
3. Does the reviewer's deferral rationale name a "trigger condition" (next change to X, Nth copy, etc.)?

If all three are yes, the scope-out criterion does not fit — fix inline. The CONCUR gate will DISSENT regardless; doing the self-check first saves the round-trip.

## Session Errors

1. **PreToolUse `security_reminder_hook` flakiness on workflow edits.** The hook fires on every `.github/workflows/*.yml` edit (regardless of edit content) and blocks roughly the first edit in each parallel batch. New_strings in this session contained zero `${{ github.event.* }}` / `github.head_ref` interpolation (most edits REMOVED code), so the hook was firing on the file-pattern alone. **Recovery:** Retry the blocked edit on the next turn — always succeeds. **Prevention:** Refine `.claude/hooks/security_reminder_hook.py` to only block when `new_string` contains an untrusted-input expansion regex (`\$\{\{\s*(github\.event|github\.head_ref|github\.pull_request\.(title|body|head\.ref|head\.label))`). Current behavior is over-broad and trains the operator to ignore hook denials, weakening the actual signal when a real injection lands.

2. **`set -uo pipefail` inline predicates abort under zsh-snapshot env.** The review skill's inline classification script aborted at `ZSH_VERSION: unbound variable` because the user's shell-snapshot uses `set -u` and references `ZSH_VERSION` before guarding it. **Recovery:** Classified inline by inspecting file extensions directly (avoided the script). **Prevention:** When a skill prescribes `set -uo pipefail` for inline predicate computation, either (a) document the workaround `set +u; <command>; set -u`, or (b) wrap the predicate computation in a heredoc that does its own `set -uo pipefail` so the shell snapshot's strictness doesn't apply.

3. **`terraform fmt` (no `-check`) re-formatted unrelated `issue-alerts.tf`.** Plan said `terraform fmt -check`; executed command was `terraform fmt` which mutates. Pre-existing 4-space drift on a sibling file got normalized as a side effect, contaminating the diff. **Recovery:** `git checkout -- apps/web-platform/infra/sentry/issue-alerts.tf`. **Prevention:** When validating IaC, default to `terraform fmt -check -diff` (read-only); reserve `terraform fmt` for explicit format-the-PR-files-only sweeps with `-write=false` + targeted file args.

4. **`actionlint` rejected `action.yml` as malformed workflow.** Composite-action definitions use a distinct schema (`name`, `description`, `inputs`, `runs`) — actionlint validates `.github/workflows/*.yml` (which require `on:` + `jobs:`). Passing `action.yml` to actionlint produces 5+ spurious "section missing" / "unexpected key" errors that look like real regressions. **Recovery:** Re-ran actionlint excluding `action.yml`. **Prevention:** Add to the review/work skills' Sharp Edges section: "Do NOT pass `.github/actions/*/action.yml` to `actionlint` — it only validates workflows. Composite actions need a dedicated `action-validator` tool or schema validation can be skipped at the PR-gate tier (the workflow that calls the action will fail-fast on schema problems at first run)."

5. **Branch-base divergence from main after worktree create.** Worktree was created from `origin/main@813d29bf`; PR #3969 merged into main shortly after. `git diff main..HEAD` then showed 4 unrelated `apps/cla-evidence/` files as "deltas" of my branch (they were actually commits-on-main since my fork point). **Recovery:** Verified init commit (`77705cbf`) was empty; confirmed `git diff origin/main..HEAD` showed only my actual changes. **Prevention:** When reasoning about "what my branch changed", always use `origin/<branch>..HEAD` (commits unique to my branch) or `$(git merge-base main HEAD)..HEAD` (since-divergence). Never `main..HEAD`, which conflates "my changes" with "main moved forward." This is already documented as `rf-when-a-reviewer-or-user-says-to-keep-a` for review agents; consider lifting to a Plan-skill instruction.
