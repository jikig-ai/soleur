---
title: Verify Codex tool surfaces and git comparison direction before acting
date: 2026-09-30
category: runtime-errors
module: Codex session and Git workflow
---

## Problem

This session recovered from several interface mistakes: an `exec` script used
the unavailable `functions` global instead of `tools`; a tool call used the
wrong question schema; a multiline `exec` call had a JavaScript syntax error;
an embedded Python heredoc was compiled together with its shell wrapper; a
shell probe ended in a dangling `&&`; an inspection guessed a source path that
did not exist; one patch hunk did not match; and a `jq` status summary applied
`group_by` at the wrong pipeline level and rejected the GitHub CLI's check-run
shape. I also read `git diff HEAD..origin/main` as main removing feature code;
that direction showed branch-only additions as deletions because main had not
merged them.

## Prevention

Use `tools.*` inside `functions.exec`; call collaboration tools directly with
their namespace. Check the active question schema. Resolve paths with `rg
--files` before opening them. Re-read exact source after a patch mismatch and
split the edit into smaller hunks. For shell wrappers with embedded
languages, run the native syntax check and compile only the extracted
heredoc. Avoid trailing command separators in shell probes. Before calling a
diff intentional, record its direction and the merge base; compare both
`<merge-base>..origin/main` and `<merge-base>..HEAD` to separate upstream work
from feature-only changes. For check status summaries, first materialize the
check-run list as an array, then group or map it.

The pre-commit hook also started `test-all.sh --affected` despite the operator's
authorization to rely on CI; it was interrupted and rerun with only the
`bun-test` hook excluded. The first typecheck caught an RPC fixture typed too
narrowly for the boolean acknowledgment response; its result type was widened.
The GitHub job-log endpoint returned plain text despite the `logs` suffix, so
the download needed `file` inspection before treating it as an archive.

Two resumed-session probes repeated those shape mistakes: the embedded-Python
extractor searched for a double-quoted heredoc marker and failed before
compiling anything, and one `exec_command` omitted the worktree argument and
read the project root on a different branch. Use a regex over the exact
single-quoted heredoc marker, and always pass the feature worktree as the
command's `workdir`; a failed lookup is not evidence that a file is absent.
An attempted learning-file patch copied context from a different learning and
was rejected without a write; re-read the target tail and patch its exact
content rather than borrowing nearby prose.

The first attempt to inspect an in-progress CI job log was refused because its
cleanup command used `rm -f`; no log file was created. The retry correctly
reported that GitHub exposes failure logs only after the overall run
completes, while `rg` returned 1 because it received no failure lines. Avoid
temporary files when a filtered pipeline is enough, and distinguish
"logs unavailable yet" from a test verdict before interpreting an empty grep.
After the workflow completed, the tenant job log showed 5,695 passing and 1
failing unit test: the new Codex history-transfer handler assertion. Its
annotations also contained expected in-flight migration warnings, which were
not the failure cause. Use the failed step's test summary, not adjacent
annotations, to classify a tenant-integration failure.

The next CI run passed the new acknowledgment assertion but failed the
following abort assertion because that test file's mutable `generation` fixture
was left at 1. Reset provider mode and generation in `beforeEach`; adjacent
real-handler tests share the hoisted fixture even though Vitest creates fresh
test functions.

The following CI run reached `ws-resume-by-context-path.test.ts` and failed its
Codex context-path collision case: its synthetic run uses auth-mode generation
7, but the shared RPC mock did not return `true` for the new per-member
acknowledgment query. Keep synthetic Codex dispatch fixtures explicit about
the recorded acknowledgment; the fail-closed production check is working as
intended. Tenant-integration uses the same broad Vitest batch, so this one
fixture correction can resolve both CI failures.

Immediately after pushing the correction, `gh pr checks --watch` briefly
reported that no checks existed because GitHub had not published the new
workflow statuses yet. Confirm the PR head and `gh run list` for the branch,
then retry the watcher once the runs appear; the new CI was active and did
not need a manual rerun.

During the durable-ack continuation, `bun run typecheck` was invoked at the
repository root, which has no such script; run `npm run typecheck` from
`apps/web-platform`. Two migration probes also carried a root-relative path
while already inside `apps/web-platform`, and a later gate call named the app's
lint script from the repository root. Check `pwd` against the script's owning
package before invoking it. The PR-diff form of the FK-precondition lint skips
an untracked migration, so run the explicit-file form while a migration is
still uncommitted; it caught missing `to_regclass` checks for both FK targets.

The operator authorized CI-only test validation, but the first WIP commit used
`LEFTHOOK_EXCLUDE=bun-test` and still ran `plugin-component-test` because they
are separate hooks with different globs. It completed 3,809 tests successfully
with 12 skipped. Read `lefthook.yml`, exclude every test-running hook by its
exact key, and verify the hook output lists each skip; the work skill now pins
that procedure. The app's Web Platform tests remain for CI.

The first work-skill edit exceeded its 362,000-byte body budget by 502 bytes,
so the commit hook refused it. Keep only a conditional pointer in the loaded
skill and place the procedure in a reference file read at that named step.

CI caught that the compacted work-skill sentence had also removed an exact
prescription anchor asserted by `fullsuite-merge-gate.test.ts`. When editing
that guidance, preserve the asserted wording and its nearby full-suite pointer;
the CI-only hook reference can be linked from the same sentence.

The next CI run passed that assertion and caught the privacy-policy SHA omitted
from `legal-doc-shas.ts`. Every non-T&C canonical legal edit requires its hash
refresh in the same PR; check `tc-document-sha-guard` after legal edits and
record the document tier and CLO status in the PR description.

RLS fuzz then found the two new authenticated Codex acknowledgment RPCs missing
from its `ATTACK_SQL` classification. Add real cross-tenant cases and a valid
Codex binding plus positive acknowledgment fixture; a missing-record `false`
alone would make these denial checks vacuous.

The first real fixture exposed that `agent_engine_runs` defaults its auth-mode
generation to zero, which the acknowledgment table correctly rejects. Seed a
positive generation explicitly before inserting the acknowledgment.

The Codex lifecycle added three WebSocket message types, but CI's exact
`KNOWN_WS_MESSAGE_TYPES` guard did not include them. When adding a wire message,
update `apps/web-platform/test/ws-known-types-guard.test.ts` alongside the
shared wire schema and handlers; this guard intentionally rejects both missing
and stale entries.

The named Chrome-for-Testing browser session did not inherit the authenticated
Zen Browser session; a redacted snapshot showed its own login form. Inspect
only the task's isolated browser session and say which window needs sign-in;
never infer authentication from another browser. GUI focus attempts using this
host's Hyprland `hyprctl dispatch` syntax failed; consult the installed
`hyprctl --help` and local API rather than retrying the removed legacy syntax.

`domain-model-drift.sh drift` exited 1 after reporting zero stale citations
and 45 undocumented tables; its stderr also had 180 awk escape warnings.
Keep stale-citation, undocumented-fact, and blind-spot counts distinct. The
migration 145 SQL tests expected a local Docker container and silently skipped
in CI; integration tests should provision and remove their own disposable CI
container. A helper assertion with `git check-ignore -v` can return success on
a negation rule; use `git check-ignore -q` when checking whether a capture is
ignored.

The sandboxed Pencil CLI failed before argument parsing because Node could not
read network interfaces (`uv_interface_addresses`). Retry credential-free CLI
inspection through the approved escalated path; the same command succeeded
outside the sandbox and confirmed the stored Pencil session was active.

The Codex continuation began from the main checkout instead of the named PR worktree. `cleanup-merged` printed read-only lock errors and skipped cleanup; it did not alter worktrees. Resolve and verify the requested worktree explicitly before reading feature files. A sandboxed GitHub CLI request then failed with `error connecting to api.github.com`; retry network-dependent reads with the approved escalated path rather than treating the missing response as PR state. A direct lookup also used a nonexistent spec-local CLO packet path; the canonical packet lives under `knowledge-base/project/specs/feat-one-shot-codex-web-rollout/`. For slow typechecks, capture output and the final exit marker; an empty early poll is not a verdict. The first completed typecheck caught stale reducer/UI fixture types, which were fixed before the successful rerun.

The next CI run caught plain-function mock types, a native resend button outside
the shared primitive, socket-readiness probes accepting PostgreSQL's temporary
initialization server, and stale dispatch/refusal-set expectations. Use
`vi.mocked` for typed spies, the shared Button, TCP readiness for disposable
PostgreSQL, the real dispatch contract, and reviewed exact migration sets.
CI-only validation means these corrections still require a fresh CI verdict.

The QA browser launched headlessly and was invisible to the operator. For an
interactive sign-in, use both `--session codex9051` (daemon isolation) and
`--session-name codex9051` (saved-state identity), plus `--headed` at launch.
Verify the visible window before asking for sign-in. The first sandboxed launch
could not write its runtime socket; the approved retry succeeded. Hyprland's
dispatcher help calls returned general usage instead of a focus API; use the
measured workspace location without guessing a legacy dispatch command.
