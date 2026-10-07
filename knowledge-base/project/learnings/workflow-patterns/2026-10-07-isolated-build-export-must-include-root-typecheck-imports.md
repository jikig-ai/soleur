---
title: Include root imports in an isolated full-source application build
date: 2026-10-07
category: workflow-patterns
tags: [codex, recovery, nextjs, build-context, source-export]
pr: 9051
---

# Include root imports in an isolated full-source application build

## Problem

An offline recovery candidate exported only `apps/web-platform` and
`plugins/soleur` at `66f424cb0a592a54ea33d12cc64a1cbbd627e8c6`. Locked
dependency installation and Webpack compilation completed, but Next's
TypeScript pass failed because `cron-compound-promote.test.ts` imports the
root `scripts/lib/frontmatter-strip/strip.ts`. The export lacked that helper.
No test suite, application process or database ran. This was a preparation
error, not evidence of a repository build defect.

## Correction

Export the unchanged helper from the same Git revision, trace its imports,
and compare its Git blob to that revision before resuming compilation. The
verified helper blob was `3a342407f091d37033bf815aa6e8309394f89874`. Preserve
the failed build record separately from the corrected attempt. Keep the
complete selected typecheck surface; do not exclude tests to make it pass.

Production Docker builds prune most tests through `.dockerignore`; a full
source export has a different typecheck surface. Compilation of the latter
does not attest production runner-image parity. A recovery candidate must
also contain the nested plugin mountpoint in both its image and any parent
runtime bind source before a read-only filesystem is applied. Image assembly
and mount verification remain distinct from an authorized recovery rehearsal.

## Session diagnostics

Sandboxed Docker/GitHub access and shared Git locks required narrowly scoped
escalation. The go preamble restored the worktree's MCP file from local main;
restore the original clean HEAD version after that incidental session change.
An earlier build helper named under `/tmp` was absent; prepare the inspected
replacement under task-owned worktree scratch and record its scope. Bound
tool output before returning dependency inventories or skill excerpts.
An absent build container after completion is not a crash verdict: read the
build record and captured exit instead. None of these diagnostics authorizes
repeating a recovery rehearsal whose one-attempt permission has expired.

Limit discovery to the known feature directory: searching every session-state
file produced truncated output. The Docker ignore file is app-local at
`apps/web-platform/.dockerignore`; a root-path probe failed and was corrected.
Build warnings were traced to the pinned source's existing Sentry options,
middleware convention and client instrumentation, plus Webpack cache advice;
they do not attest production tooling parity or qualify startup.

The corrected build reached successful type checking and static generation,
then exceeded the preparation wrapper's 480-second deadline during trace
collection. Its last observed resource sample was about 3.3 GiB of a 6 GiB
limit; the wrapper intentionally removed its owned container. This is an
incomplete build, not a runner crash or a pass. Preserve that record and use
a longer bounded build deadline. A recovery admission guard must require
every named build step, the final image result and the mount check to pass;
`all()` over whatever step rows exist cannot prove that missing steps ran.

After compilation completed, BuildKit interpreted `FROM sha256:<image-ID>`
as a registry tag and attempted a host-side metadata lookup. `--network=none`
controls build-step networking; it did not prevent that resolution, and
`--pull=false` did not make the raw ID a valid local FROM reference. Preserve
the failed assembly record and use verified local-ID create/copy/commit on a
container whose state proves it was never started. Perform the mount-only
probe separately with `--pull=never` and network `none`. Do not claim the
failed builder made no external lookup. No OpenAI auth/provider request or
application startup occurred. An image-inspection template also referenced
an absent optional WorkingDir field; use the exact image ID as the required
identity instead of relying on optional configuration keys.

The local commit of the 3.5 GiB payload then exceeded a 180-second client
deadline. No candidate image was visible on readback, and the unstarted owned
container was removed. Preserve this incomplete assembly record, revalidate
the payload and use a longer bounded commit stage. A completed compilation
does not make a timed-out image commit a prepared candidate.

A later documentation patch omitted the feature-spec directory prefix for
two existing records and was rejected atomically. Read back all three targets
to confirm no partial edit, then apply each patch against its verified absolute
path. The corrected record links the completed local image while preserving
the distinction between preparation and an authorized rehearsal.

The preceding evidence head's `lint-bot-statuses` job failed its infra-document
step: an account-report bullet containing “operator” was adjacent to an automated
image-proof bullet containing “mount.” The linter deliberately joins adjacent
non-blank actor/imperative lines. These were distinct factual subjects, with no
human infrastructure instruction. Separate account evidence from prepared-image
results with a semantic heading and run the scoped infra-document guard before
committing. Keep the linter unchanged; blank lines do not break its adjacency
model, and no waiver or suppression is needed for this correction.

The post-rehearsal evidence commit initially failed to create the shared
worktree `index.lock` because the sandbox exposed that Git metadata as
read-only. No commit was created by the failed command. The same exact commit
command succeeded with scoped sandbox escalation. A successful prior staging
operation does not prove subsequent Git metadata writes are permitted; verify
each result and distinguish sandbox access from rehearsal authorization.
