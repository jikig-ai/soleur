---
title: Dormant namespace transport source implementation
date: 2026-10-14
pr: 9051
starting_source_sha: 42e17c9785b5b0b76a8d2a302db933113ca2c677
status: source-implementation-and-focused-review-pending
---

# Authorized scope

The user explicitly authorized source implementation and independent review on
October 14, using synthetic tests only. Ruled by CTO agent: implement one dormant
Unix JSON HTTP client for the existing namespace adapter, with an absolute socket
deadline. The [transport interface](transport-interface.md) owns the exact scope,
behavior, acceptance scenarios and preserved holds. This source authorization
supersedes the injected-only implementation limit; it grants no operational
invocation or approval consumption. Actual profile admission and immutable Config
observations remain pending, along with builder, SQL and retained-resource wiring.

# Starting-head evidence

Fresh GitHub reads verify supplied head `42e17c9785b5b0b76a8d2a302db933113ca2c677`
is OPEN, draft and disarmed. Existing [CI 38554827142](https://github.com/jikig-ai/soleur/actions/runs/38554827142)
aggregate log explicitly reports `DRAFT_LIGHT=true`, skipped Web/scripts/scripts-
heavy legs, `draft: full battery owed at ready`, and exit 1. This is the intended
draft red, not a full-suite pass. Existing [tenant run 38554826899](https://github.com/jikig-ai/soleur/actions/runs/38554826899)
completed successfully at that same head; its executed test log reports 308 passed
files / one skipped and 6,532 passed tests / eleven skipped / one todo. That green
run does not explain the earlier source-bound teardown/BYOK timeouts. No agent
issued a live rerun, database operation or credential-discovery action.

Ref #10082 and Ref #9791 were freshly verified OPEN. SAST remains VOID and
latest-source C.9 remains unverified. No blocker or customer-content disposition
is cleared. Current-source preparation/export and final-head CI receipts require
refresh after the new source is committed.

# Session errors

The workflow counter and first contract commit refused their read-only Git
metadata locks; exact approved retries succeeded. GitHub reads that refused
sandbox network access likewise used exact approved retries. An unsupported
`gh run view --no-color` flag was removed; the failed/empty log was not evidence.
Two guessed registration filenames and one affected-index filename were absent;
`rg --files` identified the existing orphan-suite census instead. Broad output
was truncated; bounded reads replaced it. Source/test files absent before creation
were not treated as implementation failures. Prevention: use discovered names,
documented CLI flags and explicit producer receipts before interpreting output.
Routine worktree reaping and shared MCP restoration were excluded to preserve
the existing shared-write hold.

# Initial implementation verification

The first new test run returned `TRANSPORT_RED_RC=1` because the source module
was absent. The code worker waited for that receipt before implementation.
The first integration run refused synthetic socket creation in the sandbox;
its exact approved retry passed 17 contract tests with explicit
`TRANSPORT_RC=0`. The guard-removal control repeats duplicate-key refusal with
that guard removed and requires one intended assertion failure and zero errors.
The complete offline wrapper then passed under inherited `PYTHONOPTIMIZE=1`
with explicit `OFFLINE_RC=0`, including all 53 preceding adapter tests and the
17 new transport tests. Source review and committed-head pairing remain pending.
Shell syntax, ShellCheck and scoped capture-exit lint passed. Staged secret
scanning covered 42,567 bytes with zero findings. The initial staging refusal
left the index empty; its zero-byte scan counted as no evidence, and successful
staging preceded the measured scan. No daemon/build/SQL/provider/auth operation
ran. The test worker corrected an invalid bytes literal before execution and
an accept-side socket wrapping race before the passing run; neither produced
an observed behavior verdict.

# Focused review and oracle corrections

Three independent seats reviewed pushed
`9c24ddc76c0caa9fbcb55bdce1d4c7740123ea69`. Security and protocol integrity
reported no blocking source finding; each repeated 17 tests with an explicit
successful process receipt after synthetic socket escalation. Test design scored
8.1/10, Grade B, and classified the suite as component integration with unit
cases. It found three P2 oracle gaps and a P3 failed-setup cleanup gap. The
[learning](../../learnings/test-failures/2026-10-14-sanitized-errors-hide-before-io-test-calls.md)
owns their causes and corrections. The corrected 23-test suite passed with
explicit `CORRECTED_TRANSPORT_RC=0`; independent correction review remains owed.
Implementation bytes are unchanged. No full panel, SAST or runtime clearance
is claimed.

The static census passed 681 covered / zero orphans after its exact sandbox
retry. The failed enumerator's derivative orphan diagnostics were discarded.
Fixture relative/directory ratchets passed 63/71 assertions, with the latter's
required temporary-directory escalation. The vacuity meta-guard's initial
120-second timeout had no output; a bounded 240-second retry passed all 25
assertions. Existing draft checks settled at 69 pass / eleven skipped / only
required `test` red; its executed aggregate verdict remains separately owed.
The first source push was rejected without detail; remote reobservation showed
the original head unchanged, and a second source push succeeded. Two moderate
default-branch dependency advisories remain unresolved and are not clearance.

Fresh pairing and file-only export at `9c24ddc76c` passed: 5,062 production/plugin
inputs, 188 forward migrations, 49 preparation components and 6,784 exported
leaves. These receipts confer no build or runtime authority and become historical
when the test/reviewer/main inputs change. Later exact-head evidence belongs to
the PR description and ignored local receipts.

Ruled by CTO agent: namespace source alone does not make recovery approval-ready.
The next meaningful source boundary is a finite GET-only image observation
collector and file-only action manifest, followed by remaining builder/session/
retained transport controls. Empty or unresolved image slots must refuse; no
historical renderer or fixture image may fill a current-source slot. One eventual
fresh observation approval must bind actual source/probe/manifest digests,
endpoint, fixed requests, deadline and owned outputs. No such operational action
is requested or authorized here. Existing service-image observation would still
leave the separately approved current-source image build, resource/dependency
enforcement, session births/lock evidence, complete writers/quiescence and
authentication pending. Every hold remains.
