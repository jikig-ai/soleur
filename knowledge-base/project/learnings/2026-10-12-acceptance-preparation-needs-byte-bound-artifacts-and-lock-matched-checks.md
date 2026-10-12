---
title: Acceptance preparation needs surviving artifacts and lock-matched checks
date: 2026-10-12
category: test-failures
tags: [codex-web, review, provenance, typecheck, semgrep]
---

The P1 sandbox disappeared before patch export after an interrupted agent turn.
Reconstructed edits were labeled separately from earlier GREEN evidence, checked
against the unchanged baseline and retested after application. Export artifacts
before cleanup and keep them outside the allocated tree. An allocator contains
no Git metadata; compare source files rather than attempting Git diff inside it.

Several visible instrument errors were corrected: a guessed component-test path,
ignored scratch discovery, the plural `components` project selector instead of
the configured `component`, a nonexistent `/usr/bin/npm` candidate returned by
`readlink -f`, and an extraneous patch context. Discover paths with `rg --files`,
read actual project names and require an executable file before using a resolved
path. Missing JSON after a startup error is not a test verdict.

The root initially assigned only 2 GiB to all-source TypeScript checking and it
aborted at its heap ceiling. Four GiB was a measured workaround, but a stale SDK
cache still differed from the lockfile. A private allocator tree with locked
dependencies and scripts disabled passed at four GiB. Do not fix application
fixtures based on declarations from an unqualified dependency cache. npm also
refuses loading the same `/dev/null` path as both user and global config; distinct
empty task-owned files resolve that configuration error without exposing real
configuration. The private tree was removed after source-byte comparison.

Semgrep rejects auto configuration with metrics disabled. Explicit public packs
fixed that invocation, but the core's backup-thread failure and subsequent
SIGSEGV left zero scanned files. Removing a memory cap was not a verified repair.
Read-only coredump diagnosis and Ref #10082 preserve the unresolved crash rather
than converting empty findings into a pass.

The fix-round tally was posted after edits; the branch had no configured cap,
but the ordering mistake remains. Gate and increment before starting a round.
An approved image built before review corrections cannot qualify corrected
source. The CTO ruling avoids spending another one-use rehearsal on that stale
image. A fresh candidate must also have genuine synthetic browser configuration
before authenticated QA is requested.

Provider permission cannot be supplied by an operator approval. The published
hosted App Server authentication restriction is a live-execution blocker; its
scope must be distinguished from an unproven blanket ban on hosting a binary.
