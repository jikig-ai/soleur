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
