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
