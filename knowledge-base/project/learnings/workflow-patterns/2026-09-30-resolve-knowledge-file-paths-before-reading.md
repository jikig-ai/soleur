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
