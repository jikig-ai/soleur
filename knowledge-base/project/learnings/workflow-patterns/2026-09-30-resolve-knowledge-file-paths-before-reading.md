---
title: "Resolve knowledge-file paths from the tracked file list"
date: 2026-09-30
category: workflow-patterns
module: knowledge-base
---

## Problem

A read command used a guessed date in a learning filename and failed even
though the intended file existed under a different date.

## Prevention

Resolve knowledge-base examples with `rg --files <directory>` before opening
them. Do not infer a filename from a remembered date or title.

## Addendum — 2026-10-09 local test preparation

Two delegated test-file reads used relative paths after the working directory
changed. Both failed visibly and were corrected against the absolute feature
worktree before test selection. An optional runtime-discovery `ls` also returned
exit 2 because some supplied globs had no matches; guarded directory discovery
then established that no Node 22 binary was present in the checked locations.

Bind each batched read to an explicit absolute worktree or working directory.
Use guarded glob discovery for optional runtime locations and inspect each
probe's status independently; an absent candidate is not a test verdict.

## Addendum — 2026-10-09 recovery proposal preflight

A read-only compiler-export investigation referenced the generated
`next-env.d.ts`; it is not tracked and is not an export prerequisite. Resolve
tracked imports from Git and distinguish generated inputs before treating an
absent file as missing source.

The fresh offline build proposal's preview also refused every tracked `.npmrc`
by filename. Key-only inspection established that both exported files contain
the public `min-release-age` setting. The corrected admission allows only that
key with a numeric value from pinned Git source. Environment files and other
npm options remain refused; private npm credential configuration is not read.
The preview refusal ran no export, build, image/container action or rehearsal,
and consumed no authorization. Narrowly classify public configuration before
either dropping a required build input or allowing a credential-bearing file.

The subsequent main sync also imported an extra blank line at EOF in the
git-data decision record. `git diff --check` over the incoming range reported
it; the one-line formatting correction preserves the record's content. Check
the merged range, not only the uncommitted diff, before asserting whitespace
passed after a clean merge.

A later RLS warning investigation guessed `rls-fuzz.yml` and a root migration
script glob; both reads failed visibly. Tracked-file discovery resolved the
workflow to `.github/workflows/rls-authz-fuzz.yml` and the runner to
`apps/web-platform/scripts/run-migrations.sh`. Discover workflow and script
paths before constructing batched reads, just as for knowledge-base files.
The workflow deliberately uses filename tracking for duplicate integer
prefixes; the warning does not mean a migration was skipped. Its production
catalog comparison remains separately gated and was skipped in this run.

After an interrupted turn, resuming the old shell watch returned `Unknown
process id`. Query GitHub directly before rearming a bounded watch; shell
session handles are transient, not durable CI evidence. Direct probes found
the pushed head fully green. The next main sync again imported a blank EOF,
this time in `2026-10-09-feat-runtime-image-cve-scan-plan.md`; the merged-range
whitespace check caught it and its final blank line was removed.

The delegated TypeScript import scan initially indexed a call expression's
first argument without checking that an argument existed. A zero-argument
call caused a visible parser-probe failure; adding the argument-count guard
made the repeated read-only scan pass. Treat auxiliary parser failures as
incomplete import evidence until the corrected scan succeeds.

A maintenance merge used `--stat=0`, which Git rejected because `--stat`
takes no value. No merge occurred on that attempt. The corrected `--no-stat`
command merged cleanly. Inspect each command's result rather than letting a
later successful command conceal an earlier printed error in a shell batch.

The evidence head's CI image check failed while resolving the pinned public
Node base: Docker Hub's token endpoint returned HTTP 504 before any application
or CLI compilation. Preserve that upstream failure and its source/job identity
instead of treating it as a source-build verdict. It does not authorize retrying
a separately consumed local recovery build.

Fetching the completed job log with `gh api` was refused because its response
contained terminal escapes. `--allow-escape-sequences` admitted the response
to a task-owned log file; ANSI/control sequences were stripped before bounded
display. Keep escape-bearing logs out of the host terminal and investigate the
underlying job failure from normalized text.

## Addendum — 2026-10-10 maintenance and proposal admission

The clean main sync through `df1891cbbb` reported five inherited whitespace
findings when checking the incoming range: three Markdown EOF blanks, a shell
line's trailing whitespace, and a deliberately re-spaced scanner fixture.
All five files exactly match main. The fixture's C8b assertion requires its
whitespace normalization case; do not erase that evidence as a formatting fix.
The feature diff against main passes separately. Report the check's scope
instead of calling the entire imported range whitespace-clean.

`docker buildx ls --format '{{.Name}} {{.Driver}} {{.Status}}' printed a template
error: the formatter's top-level context is not one builder record. Bounded
`--format '{{json .}}'` discovery succeeded. A later optional `rg` query for
font imports returned its normal no-match status and stopped a `set -e` read
batch; the remaining files were read separately. Guard expected no-match
probes and keep required reads independent of optional searches.

The new production-image proposal's preview refused an existing contained
plugin fixture symlink. Its corrected admission resolves the target chain
from pinned Git blobs, requires a tracked regular-file target inside the same
module, bounds traversal and rejects escapes/cycles. The image inventory also
checks contained targets, target text and content hashes. Preview then passed
without export, downloads, container actions or authorization consumption.

The delegated proposal inspection also guessed `server/soleur-flow.ts` and a
`scripts/build-server*` path; both searches printed missing-file errors.
Directory discovery and the tracked package scripts resolved the actual
locations. Use the package's declared build command rather than inferring
script filenames from its purpose.

## Addendum — 2026-10-10 production candidate warnings

The approved production-Dockerfile build requested GitHub CLI 2.96.0, which
the rolling apt repository no longer carried. Its existing explicit fallback
installed 2.102.0 and the stage passed. Record the actual installed version;
do not describe this candidate as exact pinned-tool parity or silently re-pin
source under a consumed build authorization.

Next's default Turbopack build passed with 28 warnings: SDK externalization,
a dynamic subprocess path, and 26 dynamic-filesystem tracing warnings.
Successful compilation does not qualify those runtime paths. npm's install
audit summaries also remain dependency findings, not a build-failure verdict.
The unchanged lockfile and existing Dependabot alerts were verified separately.

One bounded log inspection included Next's ANSI coloring in its output.
Subsequent displays stripped ANSI before showing warnings and source traces.
Normalize the entire captured log before selecting either warning snippets or
tail lines; source snippets can contain terminal escapes even when surrounding
Docker progress lines do not.

## Addendum — 2026-10-10 open-web-egress sync

The next main merge stopped on three legal disclosure/hash conflicts. Keep
the feature's expanded engine-record disclosure and main's new web-access
bullet in both canonical and mirror policies, then regenerate canonical
privacy and data-protection hashes; selecting either hash side loses merged
content. The legal-document hash guard passed after resolution.

A follow-up search guessed `check-legal*` globs despite the hash file naming
the actual `check-tc-document-sha.sh` guard. Both glob reads failed visibly;
tracked-file discovery found the declared guard. Delegated egress triage also
guessed a nonexistent `feat-open-web-egress/session-state.md`; discovery
resolved its existing spec/tasks files instead. Use declared references and
verified file lists before forming optional search paths.

A recursive `.soleur` report search walked old source exports and installed
dependencies, producing truncated output. Its identified process finished
before an attempted termination, which printed `No such process`; the command
then exited zero. Bound ignored-artifact discovery by directory depth and
exclude exported source/node_modules rather than recursing all task scratch.
Recovered GitHub RLS log display was also narrowed from per-migration lines
to the final migration/test summaries after output truncation.

The pre-existing-main forwarder finding's first issue-create attempt was
blocked before filing because it omitted a milestone and the hook's explicit
filing-exit fields. The corrected operational filing uses the verified
`Post-MVP / Later` milestone and `User-Impact:` / `Fix-Size:` fields in its
own body. Prose describing impact and size is not the hook's required syntax.
The next filing was refused because the hook resolves a relative `--body-file`
from its root CWD. Use the existing worktree file's absolute path. A third
attempt was refused because estimated guard size did not meet the measured
`Fix-Size:` syntax. This is a mandatory pre-existing-audit finding, so its
body now names the actual `Mandated-By:` rule rather than inventing a measured
future test size or labeling a product defect as verification machinery.

The local-fixture preparation also invoked the historical Node 22 path after
an existence probe had reported it absent, producing exit 127. Keep dependent
version probes conditional on successful availability, then discover another
existing runtime without installing or downloading under this test scope.

The staged incoming-range whitespace check caught one inherited blank line
at EOF in `cc-dispatcher-real-factory.test.ts`. Removing that final blank line
preserves every test assertion; it is outside the selected local fixture set.

The full staged merge scanned through `gitleaks stdin` reported one redacted
generic-key finding in the inherited `agent-web-access.pen` wireframe. stdin
loses file/line attribution, so main's existing exact `.gitleaksignore`
fingerprint could not apply. Mapping the diff offset to that file and rerunning
the supported path-aware `gitleaks git --staged --redact` scan passed with zero
findings. No new waiver or credential-value inspection was performed.

The authorized selected30 rerun at `c1856ee92e` passed 255 unit tests but
failed one of 66 component tests: the settings rollback test could find its
combobox while initial settings were still loading, then dispatch a change
before the engine catalog was ready. Waiting for the selector to be enabled
before changing it preserves the rollback assertion and removes that implicit
load-timing assumption. The unit log also exposed an incomplete observability
mock: missing `hashUserId` caused the real logger formatter to fall back to raw
data. Supply a deterministic synthetic hash mock and assert the rejection
path uses it; a green test count alone must not conceal that warning.

Later maintenance probes combined merge statistics, long skill paragraphs and
fixture diffs in one output budget, truncating the display despite bounded
line counts. Read the required tail separately, keep long paragraph matches
out of the main transcript, and delegate multi-file inspection before
collecting full diffs. GitHub's log output also represents some ANSI markers
as literal `^[[` sequences; normalize both actual escapes and that rendered
form before displaying the final migration/test summary.

An unanchored failure search in a shell-suite transcript matched hundreds of
expected negative-test assertions and truncated the useful result. Anchor on
the suite runner's literal status marker after its timestamp, then inspect its
durable failure log and the bounded fixture diagnostics; expected text such as
`[FAIL]` inside a test assertion is not a suite failure.

When reading or probing from an explicit worktree, pass its absolute path as
the command's working directory. An `rg` call without that context was refused
before process creation. `git diff --check` on a large incoming main range can
also fail on unrelated committed whitespace; bound and report the exact
offending path and hunk before resolving the feature merge.

`gh run view --json` exposes `jobs`, with each job carrying its `steps`; asking
for a top-level `steps` field is rejected. The GitHub Actions job-logs endpoint
returns log text containing terminal escapes, so `gh api` requires
`--allow-escape-sequences` when redirecting that response to an ignored
diagnostic file.

Keep independent GitHub CLI pipelines in separate commands or parallel tool
calls; a comma in a `jq` program does not sequence shell commands and can make
`jq` parse the next CLI invocation as an option.

The session-start cleanup entry point is
`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`; the similarly
guessed `plugins/soleur/scripts/git-worktree.sh` path does not exist.

`git worktree list` can enumerate hundreds of unrelated agent worktrees. Pipe
it through a branch/path filter when only the active task worktree matters.

## Addendum — 2026-10-23 plugin helper path lookup

The session tally is plugin-owned, not repo-root-owned. Resolve pipeline
tally and review helpers under the installed Soleur root (`local/scripts/`
and `local/skills/review/scripts/`) instead of guessing their locations in
the worktree.

## Addendum — 2026-10-23 bounded test-script lookup

A focused test was invoked from the repository root using an app-relative path
and failed before starting. Resolve script paths with `rg --files` from the
explicit worktree and invoke the path relative to that same directory (for
example, `apps/web-platform/scripts/dev-ledger-parity.test.sh`).

## Addendum — 2026-10-23 commit hook worktree resolution

When a commit hook misidentifies a feature worktree as main/master, verify the
branch and `git status` explicitly, then retry with `git -C <absolute-worktree>
commit ...` rather than trusting the hook's current-directory resolution.

## Addendum — 2026-10-23 review helper arguments

Use `pipeline-tally.sh show` to read counts; `status` is unsupported. The
fix-round seat resolver accepts canonical seat names, so use
`code-simplicity-reviewer`, not the informal `simplicity` label.

## Addendum — 2026-10-23 bounded worktree lookup and validation paths

Resolve the active feature spec by searching for a unique known manifest digest
or exact feature slug; do not guess its folder name. When running validation
from a worktree root, use repository-root-relative paths, and when running from
an app directory, use app-relative paths. A failed path lookup exits before
validation and must be corrected before reporting test status. Vitest's
configured root also rejects absolute test paths outside that root; in isolated
sandboxes, set `--root` to the sandbox app and pass its test path relative to
that root.

Migration filenames in an active feature may have suffixes that differ from
the table or RPC name. Use `rg --files apps/web-platform/supabase/migrations |
rg <migration-number-or-token>` before opening a guessed filename; the failed
`169_codex_history_transfer_acknowledgment.sql` lookup stopped before further
inspection.

When running multiple checks, keep each command's working directory and paths
consistent: `apps/web-platform/scripts/dev-ledger-parity.test.sh` is invoked
from the repository root, while the same script is `scripts/dev-ledger-parity.test.sh`
from the app directory. If a migration-parity fixture reports refusal-set
drift after adding a `.down.sql`, inspect its pinned literal and include the new
file only after reviewing its refusal classification; do not treat the harness
failure as a feature migration failure.

For a malformed patch-tool hunk, re-read the exact target block and rebuild the
whole hunk; a rejected patch changes nothing and must not be reported as applied.

Static SQL tests that compare statement order must search within the specific
function body; an anchored global search can select the same statement from an
earlier function and fail despite correct SQL. For PostgreSQL function grants,
an integration call under `SET ROLE` is clearer than fixture catalog privilege
introspection; this fixture's aggregate check returned false for a valid grant.

Run Vitest from `apps/web-platform`, not the repository root: the root command
recurses into ignored `.soleur/candidate-*` worktrees and produces duplicate
test discoveries. The failed root run did not test the target suite.
