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

Later continuation probes guessed migration/test/hook and Hyprland documentation
paths that were absent. Resolve names with `rg --files` and inspect the actual
hook configuration before reading. A heredoc extraction initially selected too
many refusal-list rows; the corrected extraction matched the exact 59-member
CI set. Large skill reads truncated; read bounded sections and disclose any
unread scope instead of claiming a complete workflow attestation.

The infrastructure census compared a CI merge checkout with a subsequently
advanced `origin/main`, falsely attributing a sibling PR's new resources to this
branch as deletions. Inspect both trees and synchronize main before retrying;
do not weaken the guard to hide a stale-checkout comparison.

One reconnect patch first selected the replay branch rather than its sibling;
source rereading caught and corrected it before execution. A server-stamped
replay frame establishes stream continuity, but `handleResumeStream()` does not
bind the new WebSocket session's conversation. Keep held-message resend disabled
until explicit session recovery is confirmed; do not infer admission from replay.
The temporary screenshot harness's dependency deprecation and server termination
were investigated and repeated captures succeeded, as recorded in its QA report.

The worktree's pre-push hook later printed `Can't find lefthook in PATH` while
the Git push itself succeeded. Do not count that hook as run from the push
result; inspect the tracked `lefthook.yml`, run the affected bounded gate
directly, and record the missing hook runner. Avoid reading `.git/hooks` via
`git rev-parse --git-path` from a linked worktree because it resolves into the
shared repository metadata. An exploratory glob against a nonexistent Codex
spec path also emitted an `rg` error; locate artifacts with `rg --files` first.

The fixture-content hook scans every changed fixture file and rejected two
pre-existing production-shaped UUIDs in the test file touched by this fix.
Replace those fixture values with descriptive synthetic IDs before treating
the gate as passing; changing unrelated fixtures in the same touched file is
still within the synthesized-data rule.

## Addendum — 2026-10-01 resumed review

The sandbox command runner failed before starting even `pwd`, with process
creation error 2. Explicit shell and working-directory retries did not resolve
it; an approved unsandboxed probe worked. Each escalation then prompted the
operator, including read-only probes. After the operator disabled the sandbox,
root commands worked without `sandbox_permissions`; existing child agents may
retain the permission profile inherited at spawn. Check each active tool's
permission instruction rather than assuming that a parent update propagated.

Several reads guessed workflow, configuration, or learning paths that were
absent. Discover paths with `rg --files` before reading. The ordinary
`gh run list` response also omitted recent runs that the exact run API and PR
check rollup returned. An incomplete listing is not an absent workflow or a
CI verdict: query the known run ID and confirm its `head_sha`, then cross-check
the repository Actions API. No causal diagnosis of the listing is established.

On the next PR continuation, the rollout record was under the feature's
`feat-one-shot-codex-web-live-paths/` spec directory, not the similarly named
`feat-one-shot-codex-web-rollout/` directory. A broad recursive inventory
produced thousands of lines before locating it. Resolve the exact feature
folder first and cap any discovery output; similarly named plan/spec slugs are
not interchangeable.

On 2026-10-03, invoking ESLint from the repository root failed because its
config is app-local; run it from `apps/web-platform`. A guessed `.tsx` test
filename and a root-relative `apps/web-platform/test` search from inside that
app both failed; resolve the exact basename with `rg --files test` in the
current app directory. The first Semgrep report parser also treated its
`paths.scanned` array as an object, and `--config=auto` rejected metrics-off
mode before scanning. Match the JSON schema (`len(paths.scanned)`) and permit
Semgrep's normal metrics behavior for auto config; the corrected scan completed
with zero findings. A normal `git merge` printed hundreds of file-stat lines
when main had advanced substantially; use `git merge --quiet --no-edit` when
only the merge result matters. This host has no `lefthook` executable, so a
successful `git commit` without hook output is not evidence that local hooks
ran; run required non-test checks directly and rely on required CI for suites.

On the 2026-10-03 PR #9051 continuation, an architecture review discovery
command guessed the migration directory as `migrations/`; this repository keeps
them under `apps/web-platform/supabase/migrations/`. A follow-up inventory also
guessed a Codex held-turn cache filename that does not exist. Resolve paths with
`rg --files` from the worktree before searching or reading, and correct failed
path probes before relying on their output.

That continuation also tried `plugins/soleur/skills/review/agents/` before
finding the actual agent definitions under `plugins/soleur/agents/`. For review
role discovery, resolve the canonical `agents/<domain>/...` tree from the repo
root rather than assuming agent files are nested under the invoking skill.

The same continuation's domain-model drift probe emitted repeated GNU awk
warnings because an awk regexp used `\\\"` escapes; its output was not treated
as clean validation. A guessed GitHub CLA-signatures REST endpoint returned 404;
do not infer signature state from that endpoint, and use the actual PR check or
repository's documented CLA workflow instead.

On 2026-10-03, a resumed PR check invoked the app-level `typecheck` script
from the repository root, where that script is undefined. Run app scripts from
the owning package directory (here, `apps/web-platform`); root scripts are not
automatically forwarded. A migration glob also guessed a timestamped filename
and produced a missing-file error; enumerate exact paths with `rg --files
apps/web-platform/supabase/migrations` before opening a migration.

The same review continuation also tried to spawn an already-used agent name,
then attempted a fourth concurrent child while the three Codex child slots were
occupied. Check `collaboration.list_agents` before choosing task names and wait
for a slot before spawning; Codex allows three children including completed
threads in some session states, so use unique names and bounded waves.

GitHub CLI's `gh pr view --json` does not expose a `deployments` field; use the
REST deployments endpoint for a branch preview check. The first endpoint probe
also duplicated the repository name and returned 404; confirm the owner/repo
from `gh repo view` or PR metadata before retrying. The corrected read-only
endpoint returned an empty deployment list for this branch.

The targeted review seat resolver rejected the shortened seat name
`deployment-verification`; pass the canonical leaf name
`deployment-verification-agent` from the script's supported seat list. An
append hunk then failed because it targeted a paragraph in the wrong file;
re-read the exact target tail and patch each artifact independently.

## Addendum — 2026-10-03 resumed CI diagnosis

Session cleanup needed an approved retry to write shared Git and temporary
locks. GitHub log downloads also required a network retry outside the sandbox;
an empty redirected log from the failed download contained no CI evidence.
Discovery guessed absent handler-test and migration/workflow paths; resolve
the exact paths from the CI failure names and `rg --files` before reading.
An append patch mixed unrelated historical contexts and failed without edits;
the corrected change uses one reread paragraph per hunk.

CI found that the conversation creator binds the engine before its caller can
check cancellation. Fence inside the creator after awaited reads and inserts,
including the duplicate lookup, so closing a pending chat prevents a later
binding. Exact stream expectations must include the conversation identity.
Archive tests must stub storage and co-uploader dependencies; reaching a live
service-client constructor is an unisolated unit fixture, not proof that test
credentials are needed. A historical copy-draft warning was misclassified as
an infrastructure imperative; scope the linter exemption to that paragraph
without exempting current migration or deployment instructions.

The app-local Markdown linter executable and one installed skill reference were
absent. The approved transient Markdown CLI lint passed; the CI-only hook
procedure was read from its tracked repository reference. Do not interpret a
missing installed reference or executable as evidence that the repository lacks
the capability.

The fixture-content lint rejected historical UUID literals in two touched test
files. Replace them with the linter's existing synthesized values, preserving
identity relationships, instead of weakening the linter or adding waivers.

Semgrep completed the five-file fix scan with zero findings but reported partial
parsing of a pre-existing inline TypeScript import type in `ws-handler.ts`.
Verify the expression exists in the review base and disclose that scan limit;
zero findings are not a claim that every source line parsed. A bounded output
limit on a whole-file `git show` still truncates relevant evidence; pipe the
source through a specific symbol search instead of reading the entire handler.

Adding the session log to the Markdown scan exposed four historical headings
without blank lines; insert the missing separation and rerun the scan. An
ancestor-down inventory also guessed a missing migration 144 down file; use the
tracked filename inventory before probing paired migration bodies.

Independent review found the retained-schema refusal trusted an advisory SQL
classifier that strips executable dollar-quoted bodies. A nested `DO` can erase
the protected column while classifying as harmless. The owning reconciliation
gate now refuses every paired down while migration 145 remains; unrelated
ledger-only cleanup still works. Define regression controls for opaque SQL,
benign paired SQL and permitted ledger-only cleanup rather than attempting a
partial SQL sandbox. The new concurrency fixture also used a fixed lock sleep;
coordinate explicit release after the competing writer result instead.

Further reviewer source probes guessed missing migration/verification files
and an external classifier file; the classifier is embedded in the script.
Discover names before reads, narrow output after a truncation, and do not count
failed reads as verified source. GitHub rejects logs with terminal escapes;
permit the API transport then strip ANSI formatting before bounded display.
A failed job's logs can be fetched through the job endpoint while its enclosing
workflow continues. Network retries and shared Git lock writes require the
approved harness escalation; a piped command needs pipefail to retain failure.

The new runner fixture's ambient-environment spread unnecessarily named and
cleared a Supabase token, triggering the Management API host-pin lint. Supply
only the synthetic database URL, fixture PATH and probe switch by construction;
do not weaken the host-pin gate or add a fake API host. Main merges can introduce
historical copy detection into allowlisted reference paths even when both files
exactly match the base. Verify that identity before requesting the guard's
explicit operator rename waiver; do not rewrite contributor history or silently
disable the gate. OpenAI verification also looped in the automation browser;
the regular dashboard route was opened without copying browser state or secrets.

ESLint invoked from repository root could not find the app's configuration;
run the pinned executable with the app as cwd. The controlled locker cleanup
then exposed an explicit throw in finally; move error-propagating cleanup into
its own function while preserving database-drop teardown, and rerun lint.
Failure-marker searches can also exit through a truncated pipeline; retain
pipefail, distinguish expected negative controls from real suite failures, and
narrow to the real failed suite before assigning a cause.
