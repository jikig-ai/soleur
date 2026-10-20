# Learning: distinguish sandbox restrictions from lock contention during a held resume

During the documentation-only resume of PR #9051, the budget tracker printed
`Read-only file system`, then `lock-failed` and `UNKNOWN`. The lock path was in
shared Git metadata, which this session's sandbox exposed read-only. This was
not evidence that another process held the lock. An approved escalated rerun
successfully initialized the existing ledger and checked the agent-round gate;
the subsequent approved counter update also succeeded.

A later GitHub CLI read through mise failed because its managed installation
directory was read-only. The approved escalated PR read succeeded. Neither
restriction established anything about the earlier Config acquisition failure.

Several broad skill reads and a process-argument query produced truncated
output. Prefer heading discovery followed by bounded sections, and limit each
result before batching reads. A line limit alone does not bound long process
arguments; avoid collecting unrelated process arguments when inspecting a
known command session. Truncated output is not a complete read or verdict.

A description patch with hunks ordered opposite to the file failed atomically.
Re-read the file and order hunks by their position before retrying; the rejected
patch changed no evidence or source.

The commit guard rejected a worktree-scoped command as a main-branch commit.
The branch and staged paths verified correctly in that worktree. Include the
absolute worktree `cd` in the command so the guard can evaluate its context.

The CTO separately allowed this learning, a factual PR-description correction,
and automatic CI observation. No acquisition entry point, resolver/transport
probe, new operational manifest, binding refresh, main resync or qualification
was authorized. Historical receipt and marker hashes and private modes matched
under read-only verification; the spent evidence remained unchanged.

The proposal-only continuation repeated output truncation when independent read
results together exceeded the orchestration tool's aggregate output limit. Bound
the sum of the batch, not just each nested command; use narrow symbol/section
reads for long prose lines. A no-match `rg` returned 1 and short-circuited an
unrelated read joined with `&&`; repeat that read independently. A guessed
`apps/web-platform/scripts/*config*py` path did not exist; the source-review record
correctly locates the modules under `scripts/codex-qualification/`. Discover paths
before searching their contents. None of these tooling errors diagnoses the
historical Config refusal or authorizes an operational probe.
