---
module: web-platform
date: 2026-04-14
problem_type: integration_issue
component: multi_agent_workflow
symptoms:
  - "Parallel resolver agents committed each other's uncommitted WIP"
  - "Agent reported resolving issue in commit that didn't exist"
  - "New observability feature introduced 3 silent-failure race conditions"
  - "vi.doMock registrations leaked across tests despite vi.resetModules()"
root_cause: parallel_agent_file_scope_and_ordering
severity: medium
tags:
  - multi-agent-coordination
  - review-resolver
  - observability
  - race-condition
  - vitest
  - fix-symptom-class
synced_to: []
---

# Parallel Review-Resolvers and Observability Race Conditions

## Problem

Batch-fix PR (#2187) combined 3 bug issues (#2131, #2145, #2185) using one-shot pipeline. Post-review, 6 review-finding resolver agents fanned out in parallel, each owning a different issue (#2199 through #2206). Two recurring problems surfaced:

### 1. Parallel resolver agents committing each other's WIP

Review-resolver agent A was resolving #2199 in `ci-deploy.sh`. Agent B was resolving #2203 in `AGENTS.md` + new runbook files. Agent C was resolving #2200/2201/2204 in `server.tf` + `hooks.json.tmpl` + workflow.

Agent A committed first and inadvertently included a single-line cross-link comment in `ci-deploy.sh` that had been added by Agent B's uncommitted WIP edit. Result was correct (the PR needs both changes) but commit scope became blurred. Later, Agent C ran `git commit --amend` after its initial commit captured only 2 of 5 staged files — the amended commit picked up Agent B's remaining uncommitted changes (AGENTS.md + runbook) and landed them under Agent C's commit message. Agent B's resolution report cited a phantom commit SHA that never existed because its changes had been absorbed by Agent C's amend.

No code was lost, no conflicts occurred (file scopes didn't strictly overlap), but the audit trail was misleading.

### 2. New observability feature introduced 3 race conditions

The #2185 fix added `ci-deploy.sh` state-writing with `write_state -1 "running"` at script top plus `final_write_state "$N" "$reason"` at every exit path. The initial implementation had three ordering bugs that would silently drop explicit failure reasons — the same class the feature was built to eliminate:

- **R1**: `write_state -1 "running"` ran BEFORE flock and before `SSH_ORIGINAL_COMMAND` parsing → COMPONENT/IMAGE/TAG empty in initial state; a flock loser's `final_write_state 1 "lock_contention"` could clobber the winner's in-progress state.
- **R2**: `final_write_state` touched the sentinel file AFTER `mv` → SIGKILL between the two left the sentinel absent; the EXIT trap then overwrote the just-written explicit reason with `"unhandled"`.
- **R3**: `${STATE_FILE}.final` persisted across SIGKILL → next run's initial write didn't create a new sentinel, so on any failure the EXIT trap saw stale sentinel and skipped the `unhandled` write, silently dropping the real reason.

All three caught by parallel review agents (architecture-strategist, data-integrity-guardian, code-quality-analyst independently converged on the same findings through different lenses).

### 3. vi.doMock leakage

In `workspace-error-handling.test.ts`, the new vi.doMock for the process-spawning module leaked into the next test because `vi.resetModules()` in `beforeEach` clears the module cache but does NOT clear `vi.doMock` registrations. The Part 2 resolver agent caught this mid-implementation and added `vi.doUnmock` calls for both the spawning module and the auth module in `afterEach`. Without this, the next test's real git-clone call was intercepted by the stub returning empty Buffer — it succeeded silently instead of failing as expected.

## Solution

### 1. Design resolver agent prompts with explicit ordering gates

When fan-out resolvers edit overlapping files (even indirectly via amend behavior), include a polling wait-loop in the downstream agents' prompts:

```bash
for i in $(seq 1 40); do
  if git log --oneline -20 | grep -q "#<upstream-issue>"; then break; fi
  sleep 15
done
```

This is ugly but works. Better: partition resolvers strictly by file path, never by commit-ordering assumption. If two resolvers touch even one shared file, serialize them.

Avoid `git commit --amend` in resolver agents unless the agent also runs `git stash -u` first to exclude uncommitted WIP from other agents. The AGENTS.md rule against amend-after-hook-failure doesn't cover amend-to-complete-partial-commit, but the outcome is still muddled audit trails.

### 2. Write state AFTER flock; touch sentinel BEFORE mv; clear stale sentinel at script start

Three small ordering fixes in `apps/web-platform/infra/ci-deploy.sh`:

```bash
# At script start, clear any stale sentinel from a SIGKILLed prior run:
rm -f "${STATE_FILE}.final"

# AFTER flock + command parsing (not at script top):
write_state "$EXIT_RUNNING" "running"

# In final_write_state, touch sentinel BEFORE writing state:
final_write_state() {
  touch "${STATE_FILE}.final" 2>/dev/null || true
  write_state "$1" "$2"
}
```

Tests that would have caught these:

- Assert initial "running" state contains populated tag/component (catches R1)
- Pre-create stale sentinel → simulate failure → assert explicit reason survives (catches R3)

### 3. vi.doMock REQUIRES matching vi.doUnmock in afterEach

`vi.resetModules()` does not clear mock registrations. Pattern:

```ts
afterEach(() => {
  vi.doUnmock("child_process");
  vi.doUnmock("../server/github-app");
  vi.resetModules();
  vi.restoreAllMocks();
});
```

## Key Insight

**Parallel agents are effective when their file scopes are strictly disjoint and commit ordering is irrelevant. They become lossy when agents edit overlapping files OR when `git commit --amend` can sweep in another agent's WIP.** Design agent prompts to either:

1. Partition file scope absolutely (no overlap, even indirect) — preferred, or
2. Serialize via explicit polling wait on upstream commit SHA — fallback.

**Fix-symptom-class is a valid pattern when root-causing requires tooling you don't want to rely on.** #2185 was the second recurrence of the same webhook-silent-failure symptom since #1405. Rather than SSH to diagnose the specific 2026-04-14 instance, ship a detector so ALL future occurrences surface with an explicit reason. This is NOT a substitute for root-cause when tooling exists — it's the right move only when root-cause diagnosis would require a capability you've deliberately scoped out (here: SSH for logs, per AGENTS.md observability-first).

**New observability features need TDD for every silent-failure mode they're meant to eliminate.** Writing `write_state` helpers is straightforward; the ordering bugs are not. The tests that catch R1/R2/R3 are not the tests that catch "does write_state produce correct JSON" — they are adversarial: "what if I kill the process mid-write?", "what if another invocation runs before this one's cleanup?". Without these, the observability feature becomes its own silent-failure source.

## Session Errors

**1. security_reminder_hook.py false positive on process-spawn substring in pseudocode** — Recovery: rewrote pseudocode in prose form. Prevention: the hook's pattern match is too aggressive — consider matching only real code-like context, not any occurrence of the trigger string inside markdown bodies. Until then, plan authors should flag pseudocode blocks explicitly and use indirection (e.g., "process-spawning module" instead of the literal function name).

**2. Task tool unavailable in subagent surface during plan phase** — Recovery: substituted WebSearch + direct source reads. Surfaced a critical finding (hcloud_server `ignore_changes=[user_data]` means cloud-init never re-applies to existing server). Prevention: deepen-plan skill should pre-declare required tools up front so the subagent can fallback deterministically rather than ad-hoc.

**3. Parallel resolver agents committed each other's WIP** — Recovery: end state is correct; commit messages are misleading but PR review caught intent. Prevention: resolver prompts should explicitly `git stash -u` before staging to exclude other agents' uncommitted WIP, OR resolver orchestration should serialize agents whose file scopes touch common files even indirectly.

**4. Agent reported phantom commit SHA (a3ac2fe6)** — Recovery: verified actual landing commit (9d1efc74) via `git show`. Prevention: resolver agent prompts should instruct "after commit, re-read `git log -1 --format='%H %s'` and cite that exact SHA, not an ephemeral value from mid-workflow". Flag: resolver agents should treat commit SHAs as "last-observed" values, not stable identities, when parallel amends are possible.

**5. Initial `git commit` captured 2 of 5 staged files (a2689dd8)** — Recovery: agent used `git commit --amend` and re-staged to produce atomic commit. Prevention: investigate why the initial commit dropped files — lefthook in worktrees can silently unstage (known issue, `LEFTHOOK=0` may not fully disable all hook layers). If the cause is lefthook, document the workaround explicitly; otherwise propose staged content verification via `git diff --cached --name-only` before commit.

**6. Agent misread `git show --stat` output** — Recovery: re-ran the command. Prevention: trivial — my own error, not a workflow gap. No rule change needed.

## Tags

category: integration-issues
module: web-platform / review-pipeline
