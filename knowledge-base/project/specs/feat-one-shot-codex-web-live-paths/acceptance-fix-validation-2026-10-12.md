---
title: Codex Web acceptance fixes and bounded validation
date: 2026-10-12
pr: 9051
status: fixes-validated-full-qualification-incomplete
baseline_sha: 2b826822c086d4348ada891e15fde2aa7b62eac3
---

## Corrected behavior

Provider start/continue/replay/reconcile/approval requests now revalidate the
persisted attempt generation at the transport boundary, including automatic
credential retries. Cancel, erase and disposal retain cleanup access. Active
controller identity scopes Web delivery; superseded text, terminal frames and
errors cannot affect their replacement. Explicit Stop retains delivery identity
until dispatch finishes, preserving its cancelled terminal frame.

The Web mapper emits the complete ordered native answer. Its strict optional
`answerSnapshot` marker prevents all three reducer replacement paths from
mislabeling prior answer text as reasoning. Interleaved items, long answers and
replay retain their text. Existing tool/progress activity remains supported.

A failed settings response triggers one uncached authoritative read, without
repeating the mutation or asserting rollback. Failed reconciliation disables
further selection changes until reload. The route's unreachable default lookup
was removed. Historical migrations and their bytes are unchanged by these fixes.

## Executed checks and source identity

Synthetic RED evidence established four P1 failures with a passing explicit-Stop
control, three mapper/reducer failures with a passing single-item control, and
two settings response-loss failures. The committed text/schema regressions also
failed before implementation. These expected RED outcomes are not runner errors.

After fixes, thirteen affected unit files passed **275 tests**; the settings
component file passed **17 tests**. Process exits and JSON reports passed with
exact file membership and no failures, skips, TODOs or timeouts. Existing Node
22.22.1 was reused, with sanitized environment, isolated HOME/temp/workspaces,
disabled environment-file loading and one fork worker. Logs contain the
fail-closed `pepper_unset` notice and two deliberate database/permission-error
stimuli from settings-route tests; this is not warning-free evidence.

The reused dependency cache contained Claude Agent SDK 0.3.197 while the lockfile
pins 0.3.284. An initial all-source type check exceeded its assigned 2 GiB heap;
a 4 GiB invocation then exposed the stale SDK declaration. No repository fixture
or dependency was changed to conceal that cache mismatch.

A canonical allocator sandbox installed all locked dependencies with install
scripts, audit and funding requests disabled, private npm config/cache and a
sanitized environment. SDK 0.3.284 was verified against the lockfile. All-source
`tsc --noEmit --incremental false` passed with a 4 GiB heap, peak RSS
2,591,916 KiB. All **3,325 tracked application files** matched the live fixed
source byte-for-byte; manifest SHA-256:
`f7f107e6157b70d5c74183bf95c02b3c695e93c89e7e98bfe00425b803658258`.
The owned sandbox and private dependency/cache tree were removed successfully.
Four deprecation warnings came from locked transitive dependencies. Existing
workspace dependencies were not replaced. This compiler pass does not attest
production startup, generated Next route artifacts or live provider behavior.

Raw reports remain in ignored `.soleur/codex9051-text-fix-20261012/`.
The reconstructed P1 patch was independently inspected and retested after
application; its earlier removed sandbox is not the sole validation evidence.
A separate simplicity reviewer found no additional blocking defect introduced
by the final retry, delivery, text and reconciliation changes.

### Main synchronization and repeated affected checks

The fixes were committed at `db6fb7cb5b84d1a6d3619dbdbe06b9646ae3857e`.
Thirteen main commits through `dfb9e2dba52c60244eb856716462f50ca6b74aae`
merged cleanly at `74381e9baffa1b5bca64afd1e16faf7ca139d899`. The same
thirteen unit files and settings component then passed **275 + 17 tests** again,
with both exits zero, exact JSON file membership and no failures/skips/TODOs.
Logs retain the fail-closed pepper notice and intentional settings error stimulus.
The private all-source compiler pass above predates this merge; it is not a
post-merge all-source compiler verdict.

Two further main commits through `67dec0d7c6f9cdb36c98381c9312d3d7f5881788`
merged at `aa45feb8b5bcb35635467ea84d0d5c8f98ec9ee0`. Their seven-path delta
contains operations records and the heartbeat manifest. All `apps/web-platform`
files are byte-identical to the tested `74381e9b` tree. No infrastructure action
or C.9 rerun was performed by either sync. Dockerfile, historical migrations,
lockfiles and the canonical migration runner are unchanged across these main
syncs; application changes still make the older image source-stale.

## Gates that remain incomplete

Required SAST is **VOID**: 568 rules loaded, zero files scanned. Semgrep 1.180.0
failed during OCaml backup-thread startup and a bounded repair received SIGSEGV.
Read-only crash diagnosis found no kernel OOM kill; the exact startup cause
remains unresolved. [Ref #10082](https://github.com/jikig-ai/soleur/issues/10082)
was verified OPEN. Empty findings do not clear review. The two design-validity
seats and bounded fix verification do not constitute the full applicable panel.

The [approved image](production-image-proposal-2026-10-11.md#approved-execution-and-terminal-result--2026-10-11)
belongs to the older baseline, has a build-only anonymous frontend key and no
Codex executable. The CTO ruling declines a source-stale rehearsal as the next
acceptance step. Current-source recovery and authenticated screenshots require
a fresh compatible artifact and separate one-use execution approval.

The [CLO supplement](../../../legal/audits/2026-10-12-codex-web-hosted-auth-restriction.md#consequence-for-remaining-acceptance-criteria)
blocks the proposed hosted App Server authentication route for both modes;
a different API-funded route remains separately PENDING. No permission is
inferred from owner approval, API-key funding or environment delivery.
Production launcher/endpoint composition, protected synthetic grants, actionable
approval wiring, eligible routine execution and separate Web matrices remain
incomplete. Keep draft/default-off/customer-content blocked and preserve every
credential, account/shared-write, deployment and flag/cohort restriction.
