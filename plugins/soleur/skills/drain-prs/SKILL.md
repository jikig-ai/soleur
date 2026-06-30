---
name: drain-prs
description: "This skill should be used when draining open remote GitHub PRs: triage every open pull request into mergeable tiers, confirm scope with the operator, then fix and merge the green ones. The PR-counterpart to drain-labeled-backlog."
---

# Drain PRs

Triage all open **remote** GitHub PRs and drain the mergeable ones in one operator-confirmed pass: enumerate → triage into tiers → **confirm scope** → fix each in-scope PR to green → merge. The PR-counterpart to `drain-labeled-backlog` (which drains labeled *issues*). Distilled from the 2026-06-30 drain session that merged 11 PRs across tiers.

## When to use

- The open-PR backlog has accumulated (dependabot bumps, bot-fixes, stale feature branches) and you want to triage and merge the mergeable ones in one pass.
- You want a single triage view that separates "ready to merge now" from "needs a lockfile fix / conflict resolution / review" so nothing green sits unmerged and nothing broken merges by accident.

Use `merge-pr` for a single named PR. Use `drain-labeled-backlog` for labeled *issues* (not PRs). Use this skill to drain the open-PR queue.

<decision_gate>
**Merging is outward-facing — confirm before any merge.** This skill confirms tier scope with the operator via `AskUserQuestion` **before merging anything**, and supports per-PR opt-out within a tier (not just per-tier accept/reject). Confirming a tier means **the selected PRs are squash-merged to `main`** — this is not a preview; it lands code (higher irreversibility than the issue-drain, which ends at PR-opened). Respects `wg-zero-agents-until-user-confirms`.

**API budget.** Fixing or reviewing PRs may delegate to `/soleur:review` (feature PRs) and spawn review agents, which run autonomously and spend non-trivial Anthropic credit against the key in your session, scaling with PR count and review-cycle depth. The `--dry-run` flag prints the full tier table with zero merges and zero delegation. Soleur does not bill or proxy these calls — Anthropic does. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.
</decision_gate>

## Prerequisites

- `gh` authenticated, `jq` available.
- Current directory is a git worktree (not the bare root) — fix-recipes that touch files (lockfiles, generated files, stale branches) need a working tree.

## Arguments

<arguments> #$ARGUMENTS </arguments>

Optional flags (any subset):

- `--tiers <list>` — comma-separated tiers to drain (e.g., `ready-green,needs-lockfile-fix`). Default: prompt for tier scope at the decision gate. Tiers: `ready-green`, `needs-lockfile-fix`, `needs-conflict-resolution`, `needs-review`, `broken`. Drafts are always excluded.
- `--pr <N,…>` — restrict the whole run to an explicit set of PR numbers (still triaged + still gated).
- `--dry-run` — print the full tier table and exit with zero merges and zero delegation. More valuable here than in the sibling because this skill *merges*.

## Workflow

### 1. Prerequisites check

Verify `gh` and `jq` are on PATH (abort with installation guidance if missing). Verify the current directory is a git repository: `git -C . rev-parse --git-dir >/dev/null 2>&1` — `git` errors clearly on non-repo paths, so a fail-fast precheck beats a confusing downstream error.

### 2. Enumerate + triage

Delegate to the helper [triage-prs.sh](./scripts/triage-prs.sh):

```bash
bash plugins/soleur/skills/drain-prs/scripts/triage-prs.sh
```

The helper runs `gh pr list --state open --json number,title,headRefName,isDraft,mergeable,reviewDecision,labels,author,createdAt,statusCheckRollup` (two-stage `gh --json … | jq`, never `gh --jq` with `--arg` — learning `2026-04-15-gh-jq-does-not-forward-arg-to-jq`) and classifies each PR into **six tiers**:

| Tier | Signal | Default handling |
|------|--------|------------------|
| `ready-green` | `mergeable=MERGEABLE`, no failing/pending checks | merge directly |
| `needs-lockfile-fix` | deps PR (`labels` has `dependencies`) failing `lockfile-sync` / `test-webplat` / `e2e` on a frozen-install step | fix-recipe (a) → merge |
| `needs-conflict-resolution` | `mergeable=CONFLICTING`, few/no other failures | fix-recipe (b) → merge |
| `needs-review` | `bot-fix/review-required` label, or a feature PR with no review | review (delegate or inline) → merge |
| `drafts` | `isDraft=true` | **skip** — author-owned WIP, never merged |
| `broken` | `CONFLICTING` **and** many failing checks | surface; fix only if in explicit scope |

Pass `--dry-run` to stop here and print the table.

### 3. Decision gate (confirm scope)

Present the tier table via `AskUserQuestion`. The operator selects which tiers to drain and may opt individual PRs out within a tier. Nothing merges until this returns. (See the `<decision_gate>` block above for the irreversibility + budget framing.)

### 4. Per in-scope PR — ensure green, then merge

For each selected PR: bring it to green via the fix-recipes below if needed, then:

```bash
gh pr merge <N> --squash
```

- **Merge queue active on `main`** (the current default — adopted via the `merge_queue` Terraform ruleset): `gh pr merge --squash` **enqueues** the PR; the queue handles `update-branch` + serialization + the final merge automatically. Do not hand-roll update/wait loops.
- **Queue inactive (fallback):** if the merge is rejected for "not up to date", run `gh pr update-branch <N>`, then wait for CI to go green using the **Monitor tool** (NEVER a backgrounded poll loop — `hr-monitor-not-run-in-background-for-polling`, hook-enforced by `background-poll-prefer-monitor.sh`), then merge. Because every merge re-bases the rest under strict protection, merges serialize one at a time.

### 5. Review delegation

- **Feature PRs** (`needs-review`, non-trivial diff): delegate to `/soleur:review`. Merge only if it passes.
- **Single-file bot-fixes** (`bot-fix/review-required`): inline diff review (`gh pr diff <N>`) is sufficient; the diff is small and the change is mechanical.

### 6. Fix-recipes

See `knowledge-base/project/learnings/workflow-patterns/2026-06-30-update-branch-drifts-lockfiles-and-npm11-pin.md` and `knowledge-base/project/learnings/workflow-patterns/2026-06-30-stale-bot-cron-pr-hallucinated-api-and-registration-sweep.md` for the full failure analyses.

- **(a) Lockfile drift on deps PRs.** `gh pr update-branch` / a main-merge silently desyncs the lockfiles. Regenerate **both** and verify the frozen gates locally:
  ```bash
  cd apps/web-platform
  bun install && bun install --frozen-lockfile          # bun.lock — must exit 0
  npx --yes npm@11 install --package-lock-only           # package-lock.json — npm@11 ONLY
  ```
  The `lockfile-sync` CI gate pins **npm@11**; regenerating `package-lock.json` with local npm produces a divergent shape and fails the gate. On a lockfile **merge conflict**, resolve by regenerating (`git checkout --ours -- <lockfiles>` then re-run), not by hand-picking hunks.
- **(b) Generated-file conflicts** (e.g. `knowledge-base/project/rule-metrics.json`). Regenerate from current `main` via the owning aggregate script (`rule-metrics-aggregate.sh`) after `git merge origin/main`; do NOT hand-merge conflict markers in a generated artifact.
- **(c) Stale bot PR (especially crons).** Rebase first (`gh pr update-branch`) to re-validate against current `main` — an old green predates current gates. Then check for a hallucinated substrate API (`tsc --noEmit`) and missing registration locations per **ADR-033 §Registration checklist** (the canonical list of every gated location for a new `cron-*` function). Mirror the structurally-closest live twin signature-for-signature rather than the PR's prose.

### 7. Cleanup + report

```bash
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged
```

Report the drain delta: before/after open-PR count and the per-tier outcome (merged / skipped / deferred).

## Pipeline detection

If `$ARGUMENTS` contains a `RETURN CONTRACT` section (i.e., this skill is being driven by another skill), run headless: skip the interactive decision gate and `--dry-run` prompts; drain only tiers explicitly named via `--tiers`. Follows the same pattern as `plan`, `review`, and `ship`.

## Sharp edges

- **Drafts are always skipped.** A draft PR is author-owned WIP; merging it would ship incomplete work. No flag overrides this.
- **`gh pr merge --squash` cannot bypass server-side required checks.** Branch protection enforces `CI Required` server-side, so a mis-triaged red PR fails *loudly* at merge time rather than silently landing — the triage is an optimization, not the safety boundary.
- **The two `2026-06-30-*` learnings and ADR-033 §Registration checklist** referenced in the fix-recipes landed in PR #5808 — they are on `main`. If a future reorg moves them, update the paths here.
- **Never poll CI from a backgrounded Bash loop.** Use the Monitor tool for the queue-inactive CI wait (`hr-monitor-not-run-in-background-for-polling`).
- **Lockfile drift reads as a *test* failure, not a lockfile error.** A red `test-webplat`/`e2e` shard on a deps PR is usually recipe (a), not a real regression — check the install step before assuming the bump broke something.

## Test

Unit tests live at [drain-prs.test.sh](../../test/drain-prs.test.sh). Run them with:

```bash
bash plugins/soleur/test/drain-prs.test.sh
```

Covers: one synthetic PR per tier (ready-green, lockfile-fail, conflicting, review-required, draft, broken), an empty-list case, and the tier-grouped JSON output shape.
