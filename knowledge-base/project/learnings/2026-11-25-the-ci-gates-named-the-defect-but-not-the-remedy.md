---
title: The CI gates named the defect but not the remedy
date: 2026-11-25
category: workflow-issues
module: ci-workflows, shard-manifest, infra-privileged-tier-census, ship
tags: [shard-manifest, weight-budget, reusable-workflow, environment-secret, merge-queue, ship-kb-archive-gate, pr-quality-guards]
issue: 12866
pr: 12873
---

# Learning: the CI gates named the defect but not the remedy

PR #12873 (the bastion host) spent seventeen CI cycles between "ready" and merge. Two of the
red rounds were gates that said exactly what was wrong and nothing about how to fix it. Each
time, the obvious fix was the wrong one. This covers that post-ready stretch. The
pre-ready findings are in
`2026-11-19-a-reusable-workflow-hides-its-steps-from-every-suite-that-reads-the-caller.md`.

## 1. Regenerate shard tables with the generator, never by hand

`test-all-corpus-weight-budget` printed `registration(s) with no committed weight row: <suite>`.
The obvious fix was to add the row to `suite-durations.tsv` by hand, and that turned this gate
green. But `infra-suite-registration` (heavy shard and quality-guards) then failed, because a
weight row needs a matching **shard placement** in `suite-shard-legs.tsv`, and only the generator
writes the two together:

```bash
python3 scripts/regenerate-shard-manifest.py --group <light|heavy|infra> --incremental --write
```

**Fixed in this PR:** the weight-budget failure message now prints that command and says why
a hand-added row is not enough.

## 2. A reusable-workflow caller must not pass an environment-only secret

The bastion job body moved into a reusable `bastion-host-create.yml` (for the workflow byte
gate). The caller passed `DOPPLER_TOKEN_INFRA_PRIVILEGED` through `secrets:`, which failed the
tier census G1b check: "every Tier-B job declares an `environment:` key". The remedy that
message suggests cannot be applied, because GitHub does not allow `environment:` on a
`uses:` caller job.

The real fix is to stop passing the secret. The **called** job declares its own
`environment:`, and GitHub supplies the environment secret there. Pass the other secrets by
name, and do not use `secrets: inherit` (census G3f allows it only on release callers).

**Fixed in this PR:** the G1b failure detail now starts with both remedies: add
`environment:`, or, for a reusable caller, stop passing the environment-only secret.

## 3. The arm command the hook accepts is not the one ship documents

`.claude/hooks/ship-kb-archive-gate.sh` accepts exactly two forms:

- `gh pr merge <N>` with no flags, or
- `gh pr merge --squash --auto --match-head-commit <40-hex>` with **no** PR number, run from the
  PR's worktree.

The second form also allows no variable SHA, no `with_lock` wrapper, no `cd … &&` prefix and no
second invocation in the same command. Ship's SKILL.md arm block uses
`gh pr merge <number> … --match-head-commit "${H:?…}"` inside the merge-main lock, which breaks
three of those rules, so following the doc word for word is always refused. This is already
tracked in **#12963** and **#12697**, both open, so it was not fixed here. Until they land,
run the two-step arm check first, then the second form above with the 40-hex SHA written out.

## 4. Editing the PR body during CI cancels quality-guards

`pr-quality-guards.yml` triggers on `pull_request: types: [… edited]`, and its concurrency
group is per-ref with `cancel-in-progress` on `pull_request`. So a `gh pr edit --body` cancels
the in-flight `quality-guards` run and starts a new one. This is by design, because the body
gates have to re-read the new body, and it heals itself. But it costs a full quality-guards
run and leaves a scary `cancelled` row in the check list. **Prevention:** finish the PR body
before `gh pr ready`, and batch any later edits into one.

## Session Errors

1. **Hand-added weight rows had no shard placement.** `infra-suite-registration` went red
   after the weight-budget gate went green. Recovery: regenerated with the generator
   (74a5d73bc6). **Prevention:** the failure message now names the generator (item 1).
2. **A reusable caller passed an environment-only secret** and failed census G1b. Recovery:
   dropped it from the caller's `secrets:` (1b33b482ff). **Prevention:** the G1b detail now
   names the reusable-caller remedy (item 2).
3. **The ship-kb-archive-gate hook refused four arm-command forms in a row** (a second
   invocation, a variable SHA, an extra PR-number operand, the lock wrapper). Recovery: the
   bare form, run from the worktree. **Prevention:** tracked in #12963 / #12697 (item 3).
4. **A PR body edit cancelled a quality-guards run.** Recovery: none needed, it re-queued.
   **Prevention:** finish the body before ready (item 4).
5. **Merging main pushed the workflow over the 490,000-byte gate** (490,274 bytes). Recovery:
   moved the `workspaces_luks_recut` history to the job-rationale runbook behind a
   `# Rationale:` pointer (739574e906). **Prevention:** one-off; the gate's own message
   already names the runbook relocation.
6. **A review-scan-gate run returned `refuse rules=0`**, a transient rules fetch. Recovery:
   re-ran it and got `ok`. **Prevention:** one-off.

## Tags

category: workflow-issues
module: ci-workflows, shard-manifest, infra-privileged-tier-census, ship
