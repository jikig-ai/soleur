---
name: drain-prs
description: "This skill should be used when draining open remote GitHub PRs: triage every open pull request into mergeable tiers, confirm scope with the operator, then fix and merge the green ones. The PR-counterpart to drain-labeled-backlog."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# Drain PRs

Triage all open **remote** GitHub PRs and drain the mergeable ones in one operator-confirmed pass: enumerate → triage into tiers → **confirm scope** → fix each in-scope PR to green → merge. The PR-counterpart to `drain-labeled-backlog` (which drains labeled *issues*). Distilled from the 2026-06-30 drain session that merged 11 PRs across tiers.

## When to use

- The open-PR backlog has accumulated (dependabot bumps, bot-fixes, stale feature branches) and you want to triage and merge the mergeable ones in one pass.
- You want a single triage view that separates "ready to merge now" from "needs a lockfile fix / conflict resolution / review" so nothing green sits unmerged and nothing broken merges by accident.

Use `merge-pr` for a single named PR. Use `drain-labeled-backlog` for labeled *issues* (not PRs). Use this skill to drain the open-PR queue.

<decision_gate>
**Merging is outward-facing — confirm before any merge.** This skill confirms tier scope with the operator via `AskUserQuestion` **before merging anything**, and supports per-PR opt-out within a tier (not just per-tier accept/reject). Confirming a tier means **the selected PRs are squash-merged to `main`** — this is not a preview; it lands code (higher irreversibility than the issue-drain, which ends at PR-opened). Respects `wg-zero-agents-until-user-confirms`.

**API budget.** Fixing or reviewing PRs may delegate to `soleur:review` (feature PRs) and spawn review agents, which run autonomously and spend non-trivial Anthropic credit against the key in your session, scaling with PR count and review-cycle depth. The `--dry-run` flag prints the full tier table with zero merges and zero delegation. Soleur does not bill or proxy these calls — Anthropic does. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.
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
bash "${CLAUDE_PLUGIN_ROOT}/skills/drain-prs/scripts/triage-prs.sh"
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

For each selected PR: bring it to green via the fix-recipes below if needed, then arm it (under the merge queue this ENQUEUES the PR; it is not yet merged):

```bash
gh pr merge <N> --squash --auto
```

- **Never arm a cross-repository (fork) PR, or one touching `.github/**`, without explicit operator confirmation.** `merge_group` runs the candidate's workflows in the base-repo context with repo secrets, so a pre-queue-green fork or workflow edit can exfiltrate them before anyone reads a run. Check each PR before arming: `gh pr view <N> --json isCrossRepository --jq .isCrossRepository` and `gh api repos/{owner}/{repo}/pulls/<N>/files --paginate --jq '.[].filename | select(startswith(".github/"))'` (not `gh pr view --json files`: it stops at 100 files, so a large PR could hide a workflow edit); `true` or any output means stop and ask (the tier confirmation at the decision gate does not cover it).
- **Merge queue is active on `main`** (#9454, ADR-270; the `merge_queue` rule lives in `infra/github/ruleset-ci-required.tf`) — `gh pr merge <N> --squash --auto` **enqueues** the PR (a green PR enqueues, so the bullet and the block above agree); the queue handles the up-to-date merge, serialization and the final merge automatically — do not hand-roll update/wait loops, and never push `gh pr update-branch` or a merge of `origin/main` to a PR that is in the queue (a push dequeues it). An admin-bypass merge (only via [settle-then-admin-merge.md](${CLAUDE_PLUGIN_ROOT}/skills/ship/references/settle-then-admin-merge.md)) is the last resort, not the drain path. CodeQL is advisory on `main` (it reports no status on `merge_group`); the post-merge `codeql-main-alert-gate.yml` run is the signal. History: a first adoption (#5800) was reverted the same day for exactly that reason (ADR-032 amendment, upstream `github/codeql-action#1537`); #5840 stays open as the upstream tracker.
- **Dequeue arm — a PR that leaves the queue.** When CI is red on the queue's temp ref `gh-readonly-queue/main/pr-<N>-<sha>`, the failing check-run is on the queue SHA, not the PR head, so `gh pr checks <N>` still reads green. Read the run instead: `gh run list --event merge_group --limit 100 --json databaseId,headBranch,conclusion,url --jq '.[] | select(.headBranch | startswith("gh-readonly-queue/main/pr-<N>-"))'`, (about 8 runs per queue entry, so a smaller `--limit` can miss the PR on a busy queue), then diagnose the failing job from that run. The dequeue is silent (a `failed_checks` removal is re-queued by GitHub 2 to 3.5 minutes later while auto-merge stays armed; a red advisory job does not dequeue, so do not push over it): the PR stays OPEN with auto-merge disarmed, so `gh pr view <N> --json state,autoMergeRequest` reads `OPEN`/`null` or stays armed; section 7's wait names it (`LEFT THE MERGE QUEUE UNMERGED`, reason from the queue's removal event). Recipe: [merge-queue-dequeue.md](${CLAUDE_PLUGIN_ROOT}/skills/ship/references/merge-queue-dequeue.md). On a conflict or lockfile / `kb-index` drift, the local arm is: merge `origin/main` into the PR branch (merge-pr §3.1 "Route conflicts"), push, re-arm `gh pr merge <N> --squash --auto`. Cap it at ONE re-enqueue per PR before escalating to the operator.
- **If the PR is not in the queue** (an admin-bypass path, or a rejection that names "not up to date"), run `gh pr update-branch <N>` — **but never when both sides moved the `knowledge-base/` file count**, which a server-side merge resolves without the `kb-index` driver; merge `origin/main` locally and push instead (see [merge-pr/SKILL.md](../merge-pr/SKILL.md) §3.1 "Route conflicts"), then wait for CI to go green using **Claude: Monitor tool** / **Grok: AwaitShell** (`plugins/soleur/lib/harness.ts` `pollInstructions()`) — NEVER a backgrounded poll loop (`hr-monitor-not-run-in-background-for-polling`, hook-enforced by `background-poll-prefer-monitor.sh`), then merge.

### 5. Review delegation

- **Feature PRs** (`needs-review`, non-trivial diff): delegate to `soleur:review`. Merge only if it passes.
- **Single-file bot-fixes** (`bot-fix/review-required`): inline diff review (`gh pr diff <N>`) is sufficient; the diff is small and the change is mechanical.

### 6. Fix-recipes

See `knowledge-base/project/learnings/workflow-patterns/2026-06-30-update-branch-drifts-lockfiles-and-npm11-pin.md` and `knowledge-base/project/learnings/workflow-patterns/2026-06-30-stale-bot-cron-pr-hallucinated-api-and-registration-sweep.md` for the full failure analyses.

- **(a) Lockfile drift on deps PRs.** `gh pr update-branch` / a main-merge silently desyncs the lockfile. There is exactly ONE lockfile per directory since ADR-191 — do not recreate `bun.lock`:

  ```bash
  cd apps/web-platform
  npx --yes npm@11 install --package-lock-only           # package-lock.json — npm@11 ONLY
  ```

  The `lockfile-sync` CI gate pins **npm@11**; regenerating `package-lock.json` with local npm produces a divergent shape and fails the gate. On a lockfile **merge conflict**, resolve by regenerating (`git checkout --ours -- <lockfiles>` then re-run), not by hand-picking hunks.
- **(b) Generated-file conflicts.** Since #8377 / ADR-235 exactly one generated artifact is still committed: `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (the KB index trio and `rule-metrics.json` are untracked caches and cannot conflict). Resolve it with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-regenerable-conflicts.sh" origin/main`, which completes the merge and regenerates from the MERGED sources; do NOT hand-merge conflict markers in a generated artifact, and do NOT side-pick (`--ours`/`--theirs` each yield an artifact matching neither side's sources). The same holds for a HAND-AUTHORED file whose conflict sits beside clean hunks: `git checkout --theirs <file>` takes that side's WHOLE file and silently drops the other side's non-conflicting edits (#9134, `model.c4`); `git checkout -m <file>` recreates the markers so only the conflicting hunk is resolved.
- **(c) Stale bot PR (especially crons).** Rebase first (`gh pr update-branch`) to re-validate against current `main` — an old green predates current gates. Then check for a hallucinated substrate API (`tsc --noEmit`) and missing registration locations per **ADR-033 §Registration checklist** (the canonical list of every gated location for a new `cron-*` function). Mirror the structurally-closest live twin signature-for-signature rather than the PR's prose.

### 7. Cleanup + report

Arming returns at ENQUEUE, not at merge. Run `cleanup-merged` only once the PRs it should reap read `MERGED`. Wait on each enqueued PR with a BOUND (90 polls x 60s, the Phase 7 cap), through the Monitor tool / AwaitShell (never a backgrounded loop): `bash "${CLAUDE_PLUGIN_ROOT}/scripts/monitor-pr-checks.sh" <N> --interval 60 --max-polls 90`. It reads the merge queue (`sync-pr-behind.sh <N> --queue-state`) and ends `MERGED`, or `LEFT THE MERGE QUEUE UNMERGED` with the removal reason (the dequeue arm above: ONE re-enqueue, then report), or a timeout; it never syncs or pushes. An enqueued PR that never reaches `MERGED` is that dequeue arm, not a merged PR:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh" cleanup-merged
```

Report the drain delta: before/after open-PR count and the per-tier outcome (merged / enqueued / skipped / deferred), listing an enqueued PR as enqueued until it reads `MERGED`.

## Pipeline detection

If `$ARGUMENTS` contains a `RETURN CONTRACT` section (i.e., this skill is being driven by another skill), run headless: skip the interactive decision gate and `--dry-run` prompts; drain only tiers explicitly named via `--tiers`. Follows the same pattern as `plan`, `review`, and `ship`.

## Sharp edges

- **Drafts are always skipped.** A draft PR is author-owned WIP; merging it would ship incomplete work. No flag overrides this.
- **`gh pr merge --squash --auto` cannot bypass server-side required checks.** Branch protection enforces `CI Required` and the merge queue re-runs the checks on its own candidate, so a mis-triaged red PR never lands — but under the queue it does not fail at merge time: a red candidate is a SILENT dequeue (the PR stays OPEN, auto-merge disarmed). See it with the dequeue arm in step 4 (`gh run list --event merge_group`, or `gh pr view <N> --json state,autoMergeRequest`); the triage is an optimization, not the safety boundary.
- **An operator-authorized admin merge removes the server-side check the bullet above relies on.** It goes through [settle-then-admin-merge.md](${CLAUDE_PLUGIN_ROOT}/skills/ship/references/settle-then-admin-merge.md) step 2 (`"${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh"`, which must exit 0) and that file's merge block, never through a `gh pr checks --required` watch (#8458, #8500). For a PR that is BEHIND with the new head's checks unsettled, "CI was green" is encoded as `--green-sha <prior-green-sha>`: it certifies the current head only when that head is GitHub's own verified merge of the green sha and the base — see the reference's "was-green carryover" section.
- **The two `2026-06-30-*` learnings and ADR-033 §Registration checklist** referenced in the fix-recipes landed in PR #5808 — they are on `main`. If a future reorg moves them, update the paths here.
- **Never poll CI from a backgrounded Bash loop.** Use the Monitor tool (Claude) or AwaitShell (Grok) for the post-`update-branch` CI wait (`hr-monitor-not-run-in-background-for-polling`).
- **Lockfile drift reads as a *test* failure, not a lockfile error.** A red `test-webplat`/`e2e` shard on a deps PR is usually recipe (a), not a real regression — check the install step before assuming the bump broke something.

## Test

Unit tests live at [drain-prs.test.sh](../../test/drain-prs.test.sh). Run them with:

```bash
bash plugins/soleur/test/drain-prs.test.sh
```

Covers: one synthetic PR per tier (ready-green, lockfile-fail, conflicting, review-required, draft, broken), an empty-list case, and the tier-grouped JSON output shape.
