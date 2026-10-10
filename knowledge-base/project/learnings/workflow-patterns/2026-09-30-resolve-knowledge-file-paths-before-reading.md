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
