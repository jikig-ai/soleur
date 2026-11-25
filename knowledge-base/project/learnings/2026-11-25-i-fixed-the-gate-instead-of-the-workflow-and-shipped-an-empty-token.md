---
title: I fixed the gate instead of the workflow and shipped an empty token
date: 2026-11-25
category: workflow-issues
module: ci-workflows, bastion-host-create, infra-privileged-tier-census, shard-manifest, ship
tags: [reusable-workflow, environment-secret, tier-b-census, shard-manifest, weight-budget, ship-kb-archive-gate, pr-quality-guards]
issue: 12866
pr: 12873
---

# Learning: I fixed the gate instead of the workflow and shipped an empty token

PR #12873 (the bastion host) took seventeen CI cycles between "ready" and merge. This note
covers that stretch; the pre-ready findings are in
`2026-11-19-a-reusable-workflow-hides-its-steps-from-every-suite-that-reads-the-caller.md`.

The main finding came six days after the merge, while I reviewed the PR that was meant to
record these lessons. One CI red had been "fixed" by changing the workflow until the gate
went quiet. That change broke the workflow, the gate passed, and a test pinned the broken
shape.

## 1. A reusable-workflow caller must pass an environment secret by name

The bastion job body moved into a reusable `bastion-host-create.yml` to stay under the
workflow byte gate. Its caller passed `DOPPLER_TOKEN_INFRA_PRIVILEGED` through `secrets:`. Tier
census G1b then failed: a job that names an environment secret must declare `environment:`,
and GitHub does not allow `environment:` on a `uses:` caller.

I reasoned that the called job's own `environment:` would supply the secret, so the caller's
copy did not matter. I dropped it from the caller and pinned the omission in
`terraform-target-parity.test.ts`. G1b went green. **The reasoning was wrong.** GitHub's
"Reuse workflows" doc says:

> The caller workflow must still pass the secret … You can pass a secret by name even if it
> only exists in the environment.
> If the caller workflow doesn't pass an environment secret, the secret resolves to an empty
> string in the reusable workflow. The workflow run doesn't show an error.

So on `main` the token was empty inside the called workflow. The credential loader took the
read-only arm, and the job would have stopped at `bastion-host-create is HELD`. It failed
closed, with nothing planned or created, but neither bastion Operator Hold could ever have
run. No dispatch had happened since the merge, so nothing showed it.

**Fixed in PR #13054:**

- The caller passes the secret by name again.
- The callee declares it `required: true`, so a caller that drops it fails at call time
  instead of resolving it to empty. `required` checks that the secret is passed, not that it
  has a value.
- The parity test requires passed == declared, plus `required: true`.
- G1b now covers a **local** reusable caller when the called file is a `workflow_call`
  workflow with at least one Tier-B job, and every Tier-B job there declares a Tier-B
  `environment:`. The compliant fixture gains a caller/callee pair, so control H0 proves the
  accepted shape. Three new mutants must still go red: a callee with no Tier-B job, a remote
  `uses:`, and a callee that is not `workflow_call`. With the cover removed, G1b and H0 go red.

**The general lesson:** when a gate rejects a change, check whether the gate's model is
missing a case before changing the code to fit it. Here the gate had no notion of a reusable
caller. The cheapest check was the vendor doc for the mechanism I was relying on. I asserted
a platform behaviour ("the environment supplies it") without reading the page that defines it.

## 2. Regenerate shard tables with the generator, never by hand

`test-all-corpus-weight-budget` printed `registration(s) with no committed weight row: <suite>`.
Adding the row to `suite-durations.tsv` by hand turned that gate green. Then
`infra-suite-registration` went red, because the row has no **shard placement** in
`suite-shard-legs.tsv`, and only the generator writes the two together:

```bash
python3 scripts/regenerate-shard-manifest.py --group <light|heavy|infra> --incremental --write
```

**Fixed in PR #13054:** the failure message now prints that command. A new assertion (M4b)
requires the message to name the generator; with the remedy line deleted, M4b fails.

## 3. Which arm commands ship-kb-archive-gate accepts

I drove `.claude/hooks/ship-kb-archive-gate.sh` with PreToolUse JSON from a worktree whose
KB is archived, using the real HEAD SHA:

| Command | Verdict |
|---|---|
| `gh pr merge <N> --squash --auto` | allowed |
| `gh pr merge --squash --auto` (HEAD's PR) | allowed |
| `gh pr merge --squash --auto --match-head-commit <40-hex>` | allowed |
| `bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge --squash --auto --match-head-commit <40-hex>` | allowed |
| `gh pr merge <N> … --match-head-commit <40-hex>` | denied: extra operands |
| `… --match-head-commit "${H:?…}"` | denied: names no 40-hex SHA |
| two `gh pr merge` calls in one command (ship's if/else block) | denied: more than one invocation |

Ship's SKILL.md arm block breaks three of these rules: it passes the PR number, uses a
variable SHA, and makes a second invocation in its if/else. The lock wrapper is fine. **Use
the lock-wrapped, flag-only form with the SHA written out**; dropping the lock loses the
serialisation of parallel auto-merge arming. The doc/hook mismatch is tracked in #12963 and
#12697.

## 4. Editing the PR body during CI cancels quality-guards

`pr-quality-guards.yml` triggers on `pull_request: types: [… edited]`. Its concurrency group
is per-ref, with `cancel-in-progress` on `pull_request`. So `gh pr edit --body` cancels the
in-flight `quality-guards` run and starts a new one. That is by design (the body gates must
re-read the body), and it recovers by itself. But it costs a full run and leaves a `cancelled`
row on the PR. **Prevention:** finish the body before `gh pr ready`, and batch later edits.

## Session Errors

1. **A reusable caller was changed to satisfy census G1b and stopped passing the privileged
   token** (1b33b482ff, merged in 0d09246a05). The route read an empty token and would have
   HELD. Recovery: PR #13054 restores the pass and teaches G1b the reusable-caller case.
   **Prevention:** G1b now accepts the correct shape, the parity test pins it, and the callee
   requires the secret (item 1).
2. **My first fix to the G1b message taught the same wrong rule**: "stop passing the
   environment-only secret". A test I added pinned that text. The code-quality review seat
   caught it by reading the GitHub doc. Recovery: reverted both before merge.
   **Prevention:** for any rule about a vendor platform, quote the vendor doc in the change
   (item 1).
3. **Hand-added weight rows had no shard placement**, so `infra-suite-registration` went red
   after the weight-budget gate went green. Recovery: regenerated with the generator
   (74a5d73bc6). **Prevention:** the message now names the generator, and M4b pins it
   (item 2).
4. **The archive-gate hook refused three arm forms in a row**: a second invocation, a variable
   SHA, and an extra PR-number operand. Recovery: a single flag-only invocation with the SHA
   written out. My first draft of this note wrongly listed the lock wrapper as refused; driving
   the hook corrected it. **Prevention:** #12963 and #12697 (item 3).
5. **A PR body edit cancelled a quality-guards run.** Recovery: none needed, it re-queued.
   **Prevention:** finish the body before ready (item 4).
6. **Merging main pushed the workflow over the 490,000-byte gate** (490,274 bytes). Recovery:
   moved the `workspaces_luks_recut` history to the job-rationale runbook behind a
   `# Rationale:` pointer (739574e906). **Prevention:** one-off; the gate's message already
   names the relocation.
7. **A review-scan-gate run returned `refuse rules=0`** (a transient rules fetch). Recovery:
   reran it and got `ok`. **Prevention:** one-off.

## Tags

category: workflow-issues
module: ci-workflows, bastion-host-create, infra-privileged-tier-census, shard-manifest, ship
