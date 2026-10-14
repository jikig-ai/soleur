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

# Pushed correction reverification

Test design independently reverified pushed
`8db5c652a77e55fc9a3c78e08e6153239b166f78`, passed all 23 tests with actual
process exit zero, and closed all four findings with no new actionable issue.
Its score is 8.9/10, Grade B; component integration with unit cases passes the
pyramid check. The production transport bytes are identical to the preceding
security/integrity-reviewed source. The complete corrected wrapper also passed
after main inclusion under inherited optimization, with explicit
`CORRECTED_OFFLINE_RC=0`. This closes the focused source slice only.

Main is included through `755dfdc6a33e42eb292fe3c7700a93d4e55205de`.
The moving remote ref advanced beyond the two initially inspected commits;
`MERGE_HEAD` identified the actual three-commit union before conflict resolution.
The version-checkout change amended three canonical legal documents and their
mirrors. The sole conflict in generated legal hashes was resolved from the
merged raw document bytes, retaining both branches' prose. The nine-document
hash guard passed. The mirror-drift ratchet passed with its existing 80-line
baseline warning and past September 30 target; Ref #7465 was freshly verified
OPEN. No legal disposition or deadline was changed. Two trailing spaces in
incoming evidence comments were removed without changing their data fields;
staged whitespace and secret scanning passed. No incoming operational command
or version-check network action ran.

The re-paired source binds 5,063 runtime/plugin inputs, all 188 migrations,
49 preparation components and 6,785 source export leaves. Runtime manifest is
`e6a5fdd2a5a8a68a681286139d40d221414426613fc41ce1325921a17f370e84`;
schema remains `baeb4ee9428e8187d98743d6fe84dd84a20c98162a5440f140df9891edc9f172`;
components are `677a32323a0667e12cfbdc0be840bbd1e0013d5e7396d1adc9010fb730e2675f`.
Final evidence-only source pairing, file-only export and exact-head CI/description
receipts remain separately attributable in the PR description and ignored logs.

An operator interruption occurred after the correction push and before its CI
watch started. Resumption verified a clean worktree, exact remote head and no
existing monitor process before arming the bounded watch. The new unrestricted
sandbox profile changes no task authorization. Every runtime, credential,
provider/account, shared-write and promotion hold persists.
