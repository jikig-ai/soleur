---
date: 2026-09-15
category: integration-issues
module: web-platform-codex-replay
severity: high
tags: [codex, replay, observability, privacy, fail-closed]
---

# Codex replay translation must fail closed while making drift discoverable

## Problem

The Codex App Server can return persisted turns and item kinds that the neutral
web event contract does not understand. Silently skipping an item makes a
reconnect look complete when the transcript is incomplete; accepting the raw
provider object leaks protocol payloads across the adapter boundary. Malformed
history pages and recognized items also need to stop before dispatch persists a
partial replay.

## Solution

Keep translation pure and allowlist only payloads the neutral contract can
represent. The lifecycle source validates page, turn, and recognized-item
shapes, then throws a stable `codex_replay_invalid` error for malformed input.
Unsupported item kinds are dropped with a structured
`engine_replay_item_dropped` event carrying only a bounded item type and reason.
Malformed pages and items emit `engine_replay_failed` with a stable failure
class before throwing. The observability sink accepts narrow metadata and
swallows sink failures so telemetry cannot change provider behavior. Provider
payloads and native identities never enter those events.

## Key Insight

Replay compatibility is a data-loss boundary, not a best-effort parser. The
safe shape is a pure translator plus a lifecycle-owned validator and a
privacy-bounded signal for every discard or hard failure. Tests must cover both
the supported mapping and the unsupported/malformed branches; a green happy
path alone cannot show that replay drift is visible.

## Prevention

- Add a translator test before admitting each provider item kind.
- Bound and sanitize every field copied into telemetry; never include provider
  payloads, prompts, credentials, or native handles.
- Keep replay failure classes stable so dashboards and alerts survive provider
  vocabulary changes.
- Run the focused engine gate after each replay mapping change.

## Session Errors

1. The first review classification dump exceeded the context budget. **Prevention:** emit only bounded counts and cap path listings.
2. An inline shell environment assignment expanded before the command and produced `No such file or directory`. **Prevention:** export the variable in a prior command or use a literal absolute path; the companion shell learning records the reusable form.
3. Review subagents returned usage-limit errors. **Prevention:** emit explicit review coverage and use the documented inline fallback instead of claiming independent panel results.
4. A malformed JavaScript orchestration snippet failed before running its shell probe. **Prevention:** keep `functions.exec` snippets minimal and syntax-check the promise/brace structure before invoking tools.
5. A shell probe using `rm -f` was rejected by the command guard. **Prevention:** use Python or a safe temporary-file lifecycle instead of destructive shell cleanup patterns.
6. A preflight shell probe accidentally used command substitution despite the no-substitution ship/preflight contract. **Prevention:** pass values through per-worktree files and `read`, then run a separate bounded parser step.
7. A follow-up tool call assumed a shell variable persisted across calls and opened the wrong absolute path. **Prevention:** re-derive or pass the literal per-worktree path in every independent command invocation.
8. A merge-resync probe used a non-existent worktree path and failed before inspection. **Prevention:** copy the absolute worktree path from the session context and verify it with `test -d` before running dependent commands.
9. A broad generated-JSON diff emitted more than a megabyte and was truncated by the tool boundary. **Prevention:** inspect generated artifacts with bounded metadata (`wc`, `jq`, `head`) and prefer the source-of-truth regeneration script over raw diff output.
10. Worktree cleanup encountered an unregistered root-owned directory and could not remove it. **Prevention:** inspect ownership after cleanup, report the exact environment limitation, and do not claim orphan cleanup completed when permissions prevent it.
11. A post-resync Vitest/TypeScript probe ran from the repository root, where the app config and compiler are not installed. **Prevention:** derive the app working directory from the test package location before invoking project-local tooling.
12. A duplicate full-gate run waited on the repository-wide advisory lock behind several sibling gates and was interrupted after twelve minutes. **Prevention:** reuse a completed full-gate result when the diff is unchanged, and treat a contended rerun as blocked evidence rather than launching another interleaved run.
13. A local legal-lockstep probe compared only committed files (`origin/main...HEAD`) while the legal edits were still unstaged, so it reported a false missing-file result. **Prevention:** use the working-tree diff while validating before commit, then repeat against the pushed commit.
14. A migration-lint probe used a root-level script path that does not exist; the canonical script is under `apps/web-platform/scripts/`. **Prevention:** resolve plan paths with `rg --files` before invoking them.
15. A GitHub CLI job inspection requested an unsupported `steps` JSON field and failed before returning job state. **Prevention:** query the documented `gh` fields first, or use the Actions REST endpoint for step-level details.
16. A bounded `gh pr checks` probe yielded no captured output after its timeout even though the process had exited. **Prevention:** avoid chaining a sleep to a status probe at the yield boundary; run the status command directly and print its exit code.
17. A 30-second sleep used as a polling delay also yielded an undefined result at the tool timeout boundary. **Prevention:** use short direct status probes instead of timeout-length sleeps.
18. The first local constraint-gate invocation yielded before returning its session identifier, making its result unrecoverable from that tool call. **Prevention:** always print and retain the session ID when `yield_time_ms` can be reached, then resume with `write_stdin`.
19. The legal mirror-ratchet gate caught canonical-only additions to the three published legal mirrors. **Prevention:** every legal disclosure amendment must update canonical and Eleventy mirror surfaces together, then rerun the ratchet before pushing.
20. A combined PR-status probe (`git status`, remote SHA, PR JSON, and all checks) exceeded the tool context and was truncated before its result could be reviewed. **Prevention:** run bounded status, remote, PR, and check probes separately with explicit output caps.
21. A qualification-record read used the live spec path after the plan had been archived, so the file lookup failed. **Prevention:** resolve archived plan artifacts with `rg --files` before reading a path copied from an earlier resume prompt.

22. A broad CI-log filter matched routine PASS output and exceeded the tool output budget, truncating the diagnostics. **Prevention:** filter for suite summaries and failure annotations only, and cap each job's output independently.
23. A migration-checklist read used a path that was not present in the archived spec. **Prevention:** list the archived spec files before opening a named artifact.
24. A combined investigation command included full-length legal-register rows and routine CI output, truncating the useful findings. **Prevention:** select bounded line ranges or clip long Markdown rows before combining independent probes.
25. The session-start worktree cleanup could not fast-forward the separate local `main` checkout because it has diverged from `origin/main`; cleanup itself completed and the active feature worktree was preserved. **Prevention:** treat cleanup's merge/pull warning as a separate main-checkout resync task, and use the already-fetched `origin/main` ref to resync feature worktrees without pulling from the bare root.
26. A context patch expected a just-appended learning entry that had not reached the worktree, so the patch failed without changing the file. **Prevention:** re-read the exact anchor and apply one bounded patch, then verify `git status` and the edited lines.

27. A GitHub search API probe omitted the leading slash, so `gh api` treated `/search/issues` as a repository-relative route and returned 404. **Prevention:** prefix global GitHub REST routes such as `/search/issues` with `/`.

28. A legal-record inspection printed full-length register rows and exceeded the tool output budget, truncating useful context. **Prevention:** select narrow line windows and clip content in the reader itself.

29. The default login shell emitted repeated `Failed to create stream fd: Operation not permitted` diagnostics even though commands completed; a non-login shell removed the noise. **Prevention:** use the non-login shell for bounded worktree probes when login startup emits stream errors.

30. The new migration guard test's regex did not account for the parentheses around the JSONB key-removal expression, so the first focused run failed at the assertion rather than the SQL guard. **Prevention:** match the exact reviewed SQL expression, then rerun the focused migration suite before proceeding.

31. Combined GDPR-gate and legal-policy reads exceeded the output budget, truncating the relevant gate details. **Prevention:** inspect gate and policy sections in separate, narrowly bounded reads.

32. The first legal mirror-ratchet run found that the canonical DPD amendment had not been added to its published mirror. **Prevention:** verify all six canonical/mirror amendment-history entries explicitly, then run the mirror ratchet.

33. A repeated patch block targeted the same GDPR amendment line twice, so apply_patch rejected the patch atomically. **Prevention:** make one file-specific hunk per target and inspect the exact source line before retrying.

34. The C4 freshness test needed the uncached pinned `likec4` CLI and failed with `EAI_AGAIN` under restricted network access; the approved network rerun passed. **Prevention:** request network access when a required pinned tool is absent from the local cache.

35. The C4 producer test could not create its fixture under sandbox-read-only `/var/tmp`; the approved rerun passed 14/14. **Prevention:** rerun tests that require system temporary paths with the needed filesystem access.

36. A C4 test invocation yielded without its session identifier being included in the forwarded output, so the first poll used a guessed ID and failed. **Prevention:** serialize the complete command result, including `session_id`, whenever execution can yield.

37. Staging the final learning update was denied because this worktree's shared Git index is under the read-only `.git` path. **Prevention:** request the required Git-metadata write access before staging or committing from this managed worktree.

38. The post-push Dependabot alert query could not resolve GitHub from the restricted network; the approved read confirmed the remote warning reflected 2 critical, 15 high, and 14 medium alerts on the default branch. **Prevention:** use the approved network path for read-only follow-up when a remote command reports a network denial.

39. A GitHub check query used malformed jq quoting, and the subsequent full `gh run view --log-failed` output was truncated. **Prevention:** verify query quoting and obtain failed-check metadata before opening only the named job.

40. Local RLS diagnostics hit a missing `pg_isready`, sandbox-blocked Docker/loopback access, and an unapplied migration 138; the migration-list JSON probe also included non-JSON CLI diagnostics. **Prevention:** use the project-supported migrated test database and do not reset or apply migrations to a shared local database without a confirmed target and state.

41. A later patch duplicated existing Session Error entries 31–33; the duplicates were removed. **Prevention:** enumerate existing IDs and verify the final sequence is unique after editing the learning log.

42. A full work-skill read exceeded the output budget, and an initial multi-file patch failed on a stale comment anchor without changing files. **Prevention:** locate workflow headings first, read bounded sections, and apply small hunks against exact current text.

## Related

- `knowledge-base/engineering/architecture/decisions/ADR-223-pluggable-web-agent-engine-boundary.md`
- `knowledge-base/project/specs/feat-pluggable-web-agent-engines/codex-qualification-record.md`

## Tags

category: integration-issues
module: apps/web-platform/server/codex-app-server-lifecycle-source.ts
