# Learning: a measurement PR found two holes in the file-tool hook, and the fix broke 21 tests through three wholesale mocks

## Problem

PR 1a of #10455 set out to measure what a sibling tenant can read of the real CLI's persisted output in a shared HOME. Three things were non-obvious.

1. **The file tools are contained by one PreToolUse hook, and the hook judged one field.** The CLI's Read, Grep, Glob, LS and Notebook tools run in the CLI process outside bwrap, so `denyRead` never applies to them. `extractToolPath` returned the first truthy of `file_path`, `path` and `notebook_path`, so an in-workspace decoy in one field hid an escaping path in another. A leading `~` (expanded to the shared HOME by the CLI) was anchored under the workspace as a literal directory and passed containment. Both were found by a review seat reading the code, not by any test, because the existing rows sent one field each and no tilde.
2. **A measurement is only as good as its proof the thing was produced.** The existing two-tenant G2 test already ran the real vendored CLI. Per-run synthesized markers for prompt text and tool output had to be proven persisted at a named host path before a zero-hit result from the sibling meant anything, and the sibling's one-pass search needed a canary it can read, or a dead grep reads zero for every class and stays green.
3. **Adding an export to a widely mocked module is a test-suite change.** `pathFieldsEscape` was a new export of `tool-path-checker`. Three test files replace that module wholesale (`vi.mock(spec, () => ({...}))`), so 21 tests failed with `No "pathFieldsEscape" export is defined on the mock`. The suites targeting the changed files all passed; only the consumer set derived by `git grep` of the changed symbols (80 files) found it.

## Solution

- `pathFieldsEscape(toolInput, isInside)` checks every present location field (a non-string field counts as an escape); `isPathInWorkspace` refuses a leading `~`; the hook and `permission-callback` both use it. Eight new hook rows fail on the old code (verified by reverting the production files and re-running).
- G2: markers proven persisted host-side per class (`not_exercisable` fails the test), a canary the sibling can read as the search's positive control, a reachability probe of A's recorded messaging socket path from the sibling's mount view, `grep -a` instead of `-I`, and a pin of the readable shared-HOME state as required plus optional members (timing-dependent files are optional). The env marker was cut because it was not independent of the tool-output marker.
- The three mock factories now spread `importOriginal` and override only the seams each suite drives.

## Key Insight

Containment that judges one extracted value is bypassed by the other values the tool reads, so enumerate every location-bearing field, not the first truthy one. A claim that a measurement found nothing needs a positive control in the same instrument and a host-side proof that each class was produced at all. And before adding an export to a module, `git grep 'vi.mock(.*<module>'` to find every wholesale mock; a green targeted run says nothing about them.

## Session Errors

1. **Ran `git stash list` in a probe** — blocked by the repo hook. Recovery: dropped the probe. **Prevention:** already hook-enforced (`hr-never-git-stash-in-worktrees`); no new rule.
2. **A scan floor `>= 3` flaked once in four runs** because CLI backups and snapshots rotate. Recovery: floor `>= 2` plus the required-member pin carries non-vacuity. **Prevention:** a floor over files the producer rotates must count only required members.
3. **A scripted multi-edit aborted before writing** (an anchor occurred twice). Recovery: the abort left the file untouched (confirmed by `diff` against a backup) and the script was re-run with the right count. **Prevention:** keep the assert-then-write shape and diff against a pristine copy after any scripted edit.
4. **New export broke 21 tests through wholesale mocks.** Recovery: spread `importOriginal`. **Prevention:** before adding an export, grep every `vi.mock` of that module; run the grep-derived consumer set, not only the targeted suites. The work skill already says to default to `importOriginal`; the new part is doing the grep at the moment of adding the export.
5. **The affected gate queued behind a sibling worktree's two-hour run** (waited 1,141 s of a 7,200 s budget). Recovery: cancelled only my own runners and ran the 80 grep-derived consumer suites directly; the full affected gate runs again at ship. **Prevention:** none needed beyond the existing contention banners; read `--capacity` before launching.
6. **First `proc.sh kill_mine` call used a pattern containing `/`**, which the tool says can never match. Recovery: basename pattern. **Prevention:** the tool already says so.
7. **Vitest swallowed `console.log` from the test**, so the measurement needed an opt-in file sink while exploring. The sink was later removed with the recording-only code. **Prevention:** write measurements to a file from the start, and cut the sink once an assertion pins the result.
8. **Two closing messages promised an action** and tripped the unkept-promise stop hook. Recovery: ended each with a plain `Paused:` sentence. **Prevention:** hook-enforced.
9. **Assumed the measurement harness had to be built** when G2 already drove the real CLI. Recovery: read the file before writing code; the plan's "stub" wording was wrong. **Prevention:** read the existing test before planning a measurement.

## Open items recorded (not claimed covered)

A symlinked directory planted in the workspace and reached through a relative Glob pattern (the pattern check is syntactic); Task/subagent hook coverage; `history.jsonl`, `debug/`, `todos/`, `tasks/` and the production HOME are unmeasured, and the production census needs the operator's authorisation.

## Tags
category: security-issues
module: apps/web-platform/server (sandbox-hook, tool-path-checker, sandbox), apps/web-platform/test
