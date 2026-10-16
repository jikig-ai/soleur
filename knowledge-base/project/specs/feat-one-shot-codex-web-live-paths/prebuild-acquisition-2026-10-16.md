---
title: Separate prebuild evidence acquisition from runtime qualification
date: 2026-10-16
pr: 9051
status: synthetic-source-verified-focused-review-and-approval-pending
---

# CTO ruling and scope

Ruled by CTO agent after the operator requested CTO consultation: acquisition
of actual image and executable provenance is agent-owned work. The operator
must not be asked to invent service profiles or supply a nonexistent current
renderer image. Separate prebuild evidence acquisition from the existing
complete eleven-role observation and profile gate.

At `bec74df32f1b318305a699a04292f3a77f831b02`, the exact-head candidate receipt
has `image_id=null` and `execute_authorized=false`. Retained October 11 build
and inspection records refer to source `2b826822c086d4348ada891e15fde2aa7b62eac3`;
they cannot qualify current source. The retained dependency manifest supplies
six repository/platform references, not observed local Docker identities.
Its byte hash is
`e48e6011aef57ddb47b0f575c6eb9ee86f0c73cf02a7544fef249fbff6b888f4`.
Its registry Config digests must never be substituted for observed local IDs.

## Source-only implementation

Add a dormant acquisition boundary with separate file-only `prepare` and
explicit `execute` modes. Preserve the existing eleven-role collector and
namespace Policy. Register synthetic tests and bind the new components in
the operational source census.

The finite acquisition manifest binds exact source/component bytes,
operational and pairing hashes, the six pinned dependency references, retained
manifest bytes, selected local executable hashes, explicit Unix endpoint,
endpoint filesystem identity, private output directory and a fixed replay
marker. Preparation opens no socket and invokes no Docker/buildx executable.

Execution requires a separately reviewed manifest and fresh approval of the
exact command through the harness. A manifest, digest, execute flag or marker
cannot establish human authorization. The exclusive, no-follow, mode-0600
marker is replay prevention only; consume and fsync it before the first socket
request and retain it on failure. No default execution, retry or fallback.

Acquire only `GET /version`, `GET /info`, and six exact percent-encoded
repository/platform image inspections. Bound the pass to 60 seconds and each
request to 10 seconds. A missing image or malformed/late response stops the
attempt and preserves only private partial evidence; it never triggers a pull.
No image/container enumeration, registry access, build, startup, SQL, provider,
browser, account, recovery, deployment or flag/cohort operation is included.

Project daemon metadata to version/identity/security/resource fields. Retain
complete image Configs only in private receipts; public output contains
hashes, counts and status. Check the requested platform reference against
returned RepoDigests and bind the independently returned immutable local Id.
Recheck the explicit endpoint filesystem identity around requests. These
checks do not authenticate the daemon administrator or establish ownership.
All execution/profile/authentication/ownership/quiescence authority stays
false and issuer verification/independent review stays pending.

## Acceptance and test scenarios

- Preparation performs filesystem/Git reads and exclusive private writes only;
  construction never contacts a transport or consumes a replay marker.
- The executed allowlist has exactly eight ordered bodyless GET requests;
  altered method/path/source/endpoint/digest/budget inputs refuse.
- Gate failure prevents every request; a successful gate is consumed before
  the first request, and success or failure cannot replay the same attempt.
- A single shrinking deadline bounds the pass and each request; timeout,
  malformed metadata, image mismatch, incomplete Config or 404 stops without
  retry and without making later requests.
- Receipts retain projected daemon fields, exact source/reference/Config
  bindings and partial-failure state; all authority flags stay false.
- Symlinked or replaced output/manifest/endpoint paths fail closed. Synthetic
  tests exercise these boundaries without contacting a real daemon.

## User impact and remaining gates

Worst target-user failure: false clearance for an unrelated image or resource
could lead to disclosure or modification outside the intended synthetic
fixture. Source consistency, self-reported daemon identity and filesystem
observations are not provenance authentication or runtime clearance.

After separately approved acquisition, review actual dependency Configs and
any absent payloads. Finish builder admission, dependency networking/resource
and context-writer isolation before requesting a separate current-source build
approval. Obtain the new renderer and remaining browser/TLS/resolver/migration
observations under separate exact actions, then close the complete eleven-role
profile gate before namespace creation or recovery.

Hosted authentication stays BLOCKED in both modes; an alternate API-funded
route stays PENDING. Build approval is consumed and the withdrawn October 11
command stays forbidden. Keep draft/disarmed/default-off/customer-blocked.
Recovery, authenticated screenshots, routine qualification, permitted Web/CLO
matrices, full review/QA/preflight and promotion remain pending.

## Observability

- Layer: local CLI status and private receipt files; no server-side sink.
- Signal: exact manifest/runner/source hashes, bounded request counts,
  completion/failure state and projected observation hashes.
- Failure: fixed sanitized diagnostics; partial private evidence and the
  retained replay marker distinguish failure from a never-started action.
- Owner: the coordinating agent reviews the receipt before any further action.
- Discoverability test: source-only synthetic acquisition tests, without SSH,
  daemon connections, provider calls or operational execution.

## Synthetic verification

The new test module first failed because `prebuild_acquisition` did not exist.
It now passes 16 cases, including the actual prepare/execute functions over
fake transports, persistent replay refusal across a forked process, copied
directory and mid-request path replacement, FIFO/symlink refusal, retained
byte binding, one shrinking deadline and contradictory daemon metadata.
The related operational/preparation/candidate tests pass 31 cases. Both runs
used `python3 -E -B -W error`; no real socket connection or acquisition ran.
Bash syntax and whitespace checks pass. Focused independent source review,
exact-head refresh and fresh exact-action approval remain pending.

## Session corrections

The initial evidence search used the retired rollout directory rather than
the live-paths directory. Discover current filenames before following older
slugs. GitHub CLI subprocesses in this worktree encountered a sandboxed mise
installation refusal; the canonical read-only checks succeeded under exact
tool approval. Check every producer exit and retain failed probes as errors,
never as a CI or qualification verdict.
An additional helper lookup guessed a filename; the canonical monitor's
actual helper reference identified the read-only attribution script. Follow
the resolved reference rather than deriving a helper name from its purpose.
