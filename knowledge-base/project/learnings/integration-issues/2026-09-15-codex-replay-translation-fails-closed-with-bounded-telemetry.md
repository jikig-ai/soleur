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

43. Two task-file reads overlapped at their shared boundary, making the same DSAR line appear duplicated; a cleanup patch was correctly rejected because no duplicate existed. **Prevention:** use disjoint ranges when concatenating adjacent file excerpts, and verify suspected duplicates with exact line numbers before editing.

44. A broad keyword search over long legal-register paragraphs exceeded the output budget and truncated the useful matches. **Prevention:** inspect named register rows or bounded sections with targeted selectors, and clip legal prose before combining results.

45. A second qualification-record read used the live spec path after the plan was archived and failed; the exact archived path was listed in this same session. **Prevention:** copy the path directly from the latest `rg --files` result instead of reconstructing it.

46. A compliance-posture query included broad processor terms and emitted long historical rows, truncating the current finding context. **Prevention:** search the specific vendor-table row with an exact provider name and clip the match before reading it.

47. `gh run view --log-failed` returned no logs while another job kept the parent workflow in progress. **Prevention:** wait for the overall run to finish before requesting its failed-job log.

48. A broad timeout/shard search over the CI workflow matched hundreds of unrelated lines and truncated the relevant job settings. **Prevention:** locate the exact job header first, then inspect only that job's bounded YAML block.

49. The GitHub Actions job-log API response was saved with a `.zip` suffix but contained plain UTF-8 text, so `unzip -l` failed. **Prevention:** inspect the downloaded response type or first bytes before choosing a decoder; the job endpoint may return a text log directly.

50. A 65-line excerpt from the web-platform job log exceeded the output budget because Vitest emitted long assertion payloads on individual lines. **Prevention:** select the failure lines first, clip each line, and keep the extracted context to the smallest useful window.

51. A full work-skill read, broad repository search, and large status listing exceeded the output budget and hid useful details. **Prevention:** read one exact skill phase at a time, search the relevant source directories with path-specific patterns, and summarize status with counts before listing paths.

52. A Node diagnostic tried to spawn `git` and hit `EPERM`; the error included the full changed-path list and was truncated. **Prevention:** run Git through the shell tool, write large path lists to a temporary file, and parse only the needed matches separately.

53. A Python one-liner used escaped quotes inside an f-string expression and failed at parse time. **Prevention:** keep `python -c` snippets simple; prefer `.format()` with direct indexing or write a short script file when quoting becomes nested.

54. The focused ESLint ratchet test received empty JSON from ESLint's child-process stdout pipe in the sandbox, although direct ESLint with file redirection produced a valid report. **Prevention:** when subprocess output is empty despite a zero exit, reproduce with a file redirect first and rerun the pipe-dependent gate with the approved process permissions before treating it as a code failure.

55. Printing every ESLint `no-unused-vars` finding exceeded the output budget and truncated the list before the changed-file rows. **Prevention:** report aggregate counts first, then filter diagnostics to the exact changed-path set before printing locations.

56. The main-branch commit guard could not resolve the shell tool's `workdir` and classified a feature-worktree commit as `main`; it blocked before staging. **Prevention:** when the hook's CWD differs from the target worktree, include `git -C <absolute-worktree-path>` so branch resolution uses the explicit checkout.

57. A commit hook's test-all output was buffered while the session handle remained active; a separate shell's process listing did not show that session, and an unnecessary interrupt canceled the run. **Prevention:** use the original session handle as the liveness source, inspect a redirected log for progress, and never infer its exit from another shell's process namespace.

58. Correction to #56: `guardrails:block-commit-on-main` matches `cd <worktree> && git commit` and resolves that directory, while its commit matcher does not cover `git -C <worktree> commit`; using the latter would evade the guard. **Prevention:** prefix commits with an explicit `cd <absolute-worktree-path> &&`, and never use `git -C` for the commit command.

59. The follow-up issue filing gate rejected a machinery issue without a `meta/machinery` label, but that label is absent from the repository. **Prevention:** verify the required filing label exists; when it does not, use the gate's explicit `User-Impact` and measured `Fix-Size` body fields so the filing remains classifiable without inventing a label.

60. The filing gate next rejected a `Fix-Size: 0 lines / 0 files` placeholder as inline-sized, so the requested follow-up was not created. A label-creation probe then confirmed `meta/machinery` already exists despite the earlier filtered listing returning no row. **Prevention:** for machinery follow-ups, use the exact machinery label and omit inline-size fields; verify labels with a direct name query before filing.

61. A read-only `gh issue view` verification initially failed because the restricted sandbox could not connect to GitHub; the same query succeeded through the approved elevated network path. **Prevention:** retry remote verification through the approved network path after recording the sandbox denial, rather than treating the issue state as unknown.

62. The full commit hook's repository-write boundary failed because the worktree was edited while `scripts/test-all.sh` was still running; the isolated `.github/scripts/test/run-all.sh` suite then passed with an unchanged before/after status. **Prevention:** treat a live full-gate worktree as immutable until its original session exits; perform issue, ledger, and learning edits only after the gate completes.

63. A direct `git commit` invocation was blocked by the branch guard because the shell tool's `workdir` did not resolve to the target worktree; retrying with an explicit absolute `cd` reached the hook successfully. **Prevention:** use `cd /absolute/worktree && git ...` for commit and other branch-sensitive writes.

64. The full commit hook returned nonzero after 6,242 seconds with a summary of 422/427 suites passing, but the tool output did not retain the individual failing suite. CI-aligned isolated runs then passed for the Bun, web-platform, and all three scripts shards (the first shard finished with 137/139 passed and two relevance skips). **Prevention:** capture long hook output to a bounded log or run the CI-aligned groups and shards before deciding whether a documented hook bypass is justified; do not claim the full aggregate gate is green without its failure identity.

65. A process diagnostic probe was rejected because its search pattern embedded a commit-command literal that the shell guard treats as a write attempt. **Prevention:** use neutral process markers such as the script path or executable name when checking for live jobs; do not include commit command text in probe literals.

66. Resume probes hit sandbox restrictions on GitHub DNS, Git metadata locks, and npm's registry/cache. Cleanup initially described its read-only lock failure as contention. Approved retries reached the real operations; an unrelated orphan directory still reported EACCES. **Prevention:** distinguish sandbox denials from contention or application failures, and use the harness escalation path rather than changing permissions or treating a skipped cleanup as completed.

67. Several combined reads exceeded the output budget; reading the first lines of the conflicted minified C4 JSON emitted an entire large artifact. **Prevention:** bound diagnostic output by bytes as well as lines, inspect generated JSON with structured projections, and read large instruction files in separate bounded sections.

68. The checkpoint push succeeded while its installed hook printed `Can't find lefthook in PATH`. The configured pre-push client PII check then passed when invoked directly over its complete client roots. **Prevention:** verify hook executable availability and retain each configured gate's explicit verdict; a successful push does not establish that the hook ran.

69. Planned filename probes and an unmatched shell glob failed during resume research; discovery found `agent-engine-adapter-composition.ts` and `138_agent_engine_runs.sql`. **Prevention:** resolve plan-relative paths through `rg --files` before reading, and pass file filters to the search tool instead of expanding unverified globs in the shell.

70. The main resync conflicted in legal amendment paragraphs, their hashes, and the generated C4 artifact; upstream also allocated the feature's provisional ADR number. **Prevention:** retain both independent dated legal notices, recompute hashes from resolved bytes, regenerate derived diagrams, and verify ADR ordinal uniqueness after every resync.

71. Historical aggregate diagnostics could not recover the 6,242-second run's failure identity. The earlier repository-write failure (error 62) is a separate run, and `422/427` includes non-failure deductions. **Prevention:** retain the complete log, timing records, and immediate command exit status outside printed tool output; never infer a failed-suite count or identity from that summary alone. Infra relevance must be derived from the feature diff after a main merge is committed, not from upstream files temporarily staged during the merge.

72. Merge takeover repeated the sandbox network/cache and Git-index denials from error 66, and a guessed `scripts/lint-kb-structure.sh` invocation failed because that file does not exist. Broad instruction and diff reads also exceeded the output budget. **Prevention:** discover validator paths from the hook configuration before invoking them, use bounded sections and semantic comparisons, and retry actual sandbox failures through the approval path. The existing `generate-kb-index.sh --check` passed; the nonexistent invocation provides no validation evidence.

73. Finishing the inherited merge resolved its original conflicts but did not establish mergeability against current main: GitHub still reported conflicts after the push. A fresh fetch exposed another generated-diagram conflict and a second ADR ordinal collision. **Prevention:** verify the live PR head and mergeability after recovery, resync against current main, regenerate derived artifacts, and recheck ordinal uniqueness before reporting the branch conflict-free.

74. The recovery probe initially required every historical ADR ordinal to be unique and failed on unchanged legacy names. Comparing the complete duplicate map against current main confirmed no added collisions, and ADR-225 is unique. **Prevention:** check the newly allocated ordinal directly and compare repository-wide findings with the merge base before treating historical naming as a new regression.

75. The settings regression commit's fresh hook run captured the full-gate failure identity: `scripts/test-all.sh` ran 439 suites (429 passed, 6 failed, 4 skipped); failing suites were `scripts/lint-legal-scope-block-placement-unit`, `apps/web-platform [repo-wide+component]`, `plugins/soleur/test/_base-notice-frontmatter.test.sh`, `plugins/soleur/test/notice-frontmatter.test.sh`, `.claude/hooks/guardrails.test.sh`, and `scripts/lib/scratch-root.test.sh`. The changed settings suites, ESLint, and TypeScript check passed separately. **Prevention:** preserve the complete gate log and report the exact failing suite set; do not infer that an aggregate failure belongs to the changed files or claim the aggregate gate is green from focused evidence.

## Related

- `knowledge-base/engineering/architecture/decisions/ADR-225-pluggable-web-agent-engine-boundary.md`
- `knowledge-base/project/specs/feat-pluggable-web-agent-engines/codex-qualification-record.md`

## Tags

category: integration-issues
module: apps/web-platform/server/codex-app-server-lifecycle-source.ts
