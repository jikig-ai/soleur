---
title: Sanitized dependency errors can hide before-I/O test calls
date: 2026-10-14
category: test-failures
tags: [codex, qualification, test-design, deadlines, error-sanitization]
module: scripts/codex-qualification
---

# Problem and correction

The namespace transport's first 17 synthetic tests passed. Focused review found
that raising an assertion from `socket.socket` did not prove a refusal preceded
socket access: the client deliberately sanitized all dependency exceptions to
`Refused`, which satisfied the same test. External mock call counts now assert
zero calls after every preflight refusal. An array-normalization discriminator
requires the intended call-count assertion failure with zero setup errors.

Three other fixture shapes hid their intended properties. One readiness wait
made the shrinking-budget comparison empty; excessive nesting could fail in the
JSON parser before the explicit bound; whitespace-only chunks and omitted bodies
could fail parsing or EOF after a missing size guard. Corrected mocks force
connect/send/header/body/EOF readiness waits and partial writes. Complete valid
responses now exercise accepted/rejected adjacent depth, chunk-count and byte
limits with specific refusal messages. Peer setup failures explicitly close
acquired sockets and temporary directories. The corrected 23-test suite passed
with `CORRECTED_TRANSPORT_RC=0`; independent reverification remains separate.

The owning test-design agent now requires these checks. The existing constitution
already requires discriminating negative controls; no new global rule is needed.

# Session errors and prevention

- Broad output truncation and guessed missing paths: discover names with
  `rg --files`, then read bounded sections. A reviewer likewise corrected a
  guessed rollout-spec path before analysis.
- Git metadata, synthetic socket, census and temporary-directory refusals:
  exact approved retries only; failed producer output is not evidence. An empty
  staged secret scan was discarded and repeated after successful staging.
- Unsupported `gh run view --no-color`: remove the unsupported flag and verify
  the actual log read's exit receipt.
- Incorrect commentary count: replace the initial 75-test claim with the executed
  tenant log's 6,532 passes, eleven skips and one todo. Do not infer a count from
  a workflow conclusion or an old summary.
- Source push rejected without detail: reobserve the remote SHA before retrying.
  The retry succeeded with the remote still at the supplied starting head.
- Vacuity guard timed out without output: retain unresolved status and retry
  under a bounded longer deadline; do not claim a passing meta-guard.
- Worker bytes-literal and accept-side socket-wrapper fixture defects were
  corrected before passing execution. Initialization failures now have cleanup
  regressions. Failed peer binds produced setup errors, never behavior evidence.
- A follow-up worker request initially hit the harness thread limit; it was
  retried after the three active review seats finished. Failed delegation is
  not independent coverage or a counted successful dispatch.

No real daemon, build, SQL, credential, provider, browser or account action was
performed. Operational authorization and all existing holds remain separate
from synthetic transport evidence.

# Addendum: final source synchronization

A moving remote ref introduced a later commit than the initially inspected
pair, so the actual `MERGE_HEAD` was checked before resolving generated legal
hashes from combined document bytes. Later synchronization merged the inspected
immutable SHA directly. Incoming files not yet merged were absent in the local
worktree; use `git show <inspected-ref>:<path>` before inclusion. Two incoming
evidence-comment trailing spaces were removed without changing data fields.

A completed aggregate job's log was unavailable through `gh run view` while its
workflow was active. Its job-log API required an explicit escape-output flag;
redirect raw bytes privately and sanitize before emitting metadata. Failed or
empty reads are not evidence. These refusals and source synchronization renewed
no runtime permission and did not clear any hold.

The image-observation focused review reproduced parent-path redirection between
validation and `open`, and a raw exception from a transport `request` property.
The writer now walks and pins every parent component with no-follow directory
descriptors, creates/cleans the leaf relative to that descriptor, and checks
the named parent identity after writing. Manifest hashes are checked against
caller-supplied expected values. Synthetic tests pin parent-swap refusal,
partial/zero-write and fsync cleanup, malformed content, late/backward/nonfinite
deadlines, no retry after failed collection, and fixed error messages without
private exception text. The first red test run also exposed a missing test
import, invalid fixture-message expectations and an exhausted mock clock; these
were setup defects, not evidence. A repository search named two nonexistent
paths and returned errors; `rg --files` located the actual README, session-state
and learning records. Use discovered paths and give each mock sequence enough
ticks to reach the intended refusal boundary.

An integrity follow-up combined a failing `fsync` with a close operation that
released its descriptor and then raised. Cleanup retried the close, exposed
`EBADF`, and left the manifest. Transfer descriptor ownership before closing;
make cleanup best-effort in each independent step, and pin file and directory
close failures separately. Both new synthetic regressions pass in the expanded
17-case image-observation suite.

Test design found the first directory-close regression did not inspect whether
the newly opened child descriptor was closed; reverting ownership assignment
could leak that descriptor while every original assertion stayed green. Record
all directory fds opened in the writer call and assert each is EBADF after the
refusal, with test-finally cleanup. The file close control also covers both
fsync failure and successful fsync followed by a released-descriptor close
error.

The secret-scan command used `exit "$rc" && ...`; `exit` correctly ended the
shell before the commit steps. The staged scan itself passed and no commit was
attempted by that command. Confirm staged state, then put the guarded follow-up
commands on a separate tool call without a terminal `exit`.

The first file-only export summary expected `build_recipe` in the returned
metadata and compared the preview hash with assembly built for a different
destination. Assembly itself completed; the receipt intentionally excludes the
recipe body, which lives in `build-recipe.json`, and its hash binds the output
path. Re-run preview and assembly against one fresh identical destination, then
compare matching receipt fields and inspect the separate recipe file.

A grouped focused command invoked sibling-module unittest names from the
worktree root and failed import before running those two suites. Re-run them
from `scripts/codex-qualification`, their supported module context, and record
the failed invocation as setup-only rather than a code verdict.

The resumed image-observation test was first invoked from the repository root,
where its sibling-module import was unavailable; run it from
`scripts/codex-qualification`, as the wrapper does. A follow-up edit reused the
root-relative path from that module directory and failed without changing files;
use the worktree root for repository-relative edits. A synthetic clock fixture
then exhausted its sequence across repeated refusal cases, and a test assertion
referenced a local from another method. Both were corrected before the passing
32-case run. CI also recorded a dev anonymization RPC HTTP 502 during tenant
fixture teardown and an infra cutover shell-suite failure; no live retry was
issued, and the latter artifact omitted its named suite transcript.

The bounded PR-check monitor was intentionally stopped at exit 130 after it
reported BEHIND, because CI-only polling must stop until the branch is synced.
This is a cancelled watch, not a CI failure. The exact `origin/main` SHA was
fetched and the canonical sync script merged/pushed it; the replacement watch
must bind to the new head.

The first follow-up sync invocation guessed `scripts/lib/sync-pr-behind.sh`, a
path that does not exist in this checkout. It made no changes. `rg --files`
located the canonical script at `plugins/soleur/scripts/sync-pr-behind.sh`; use
discovery before copying a path from another workflow layout.

A cleanup command that ended with `rm -f` was refused by command policy before
execution. The bounded log read was repeated using Python `TemporaryFile`, which
cleans up when its context closes. Keep local evidence handling self-cleaning
without a shell deletion command. Two documentation patch attempts also failed
because their context did not match the on-disk line wraps; no files changed.
Re-read exact tails and apply one file at a time when patch context fails.

The first post-sync offline wrapper invocation yielded output but its shell
session was no longer available when queried for an exit receipt. Re-run the
bounded suite with explicit `rc=0; command || rc=$?` capture and a final status
line; use only that second run's explicit `POST_MAIN_7243_OFFLINE_RC=0` as the
success evidence.
