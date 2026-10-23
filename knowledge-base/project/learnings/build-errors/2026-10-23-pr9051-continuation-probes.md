---
title: Resolve worktree paths and match exact notice text before batching PR continuation checks
date: 2026-10-23
category: build-errors
module: pr9051-continuation
---

## Problem

During PR #9051 continuation, one compound inspection command had a shell syntax
error, one source probe assumed `apps/web-platform/client/ws-client.ts` instead
of the actual `apps/web-platform/lib/ws-client.ts`, and a legal-file probe named
a nonexistent `knowledge-base/legal/privacy-policy.md`. The first focused UI test
run also failed because its expected phrase did not match the new disclosure's
exact wording. The migration-parity harness was first run from the app directory,
so a repository-root-relative Doppler fixture failed; the root-level rerun exposed
a stale pinned refusal-list expectation. A later legacy-protection fixture
referenced a PR branch before creating it, so the harness stopped on a missing
synthetic ref. The next run also showed a stale pinned later-row entry for
162_workspace_egress_audit_rollup.down.sql and an overly narrow check that did
not allow the scanner's additional refusal class to coexist with `-`.

## Prevention

Use `rg --files` to resolve source and policy filenames before combining reads.
Keep shell probes simple enough to validate their quoting, and make UI copy tests
assert stable, exact claims that match the rendered disclosure. Run the parity
harness from the repository root and create each synthetic branch in the same
case before referring to its PR ref. Keep pinned classifications aligned with
the classifier output and allow additive refusal classes when checking a row.
When the commit guard's harness CWD resolves to the bare root's `main` overlay,
use `git -C <feature-worktree> commit` so the guard checks the actual worktree
branch. Rerun the focused suite after correcting a copy expectation; do not treat
a failed run as a verification result.

## Addendum — continuation tool boundaries

The resumed workflow tally could read its ledger but could not acquire its lock
under the sandbox's read-only shared Git metadata. Rerunning that exact operation
with harness approval succeeded. GitHub log reads through the mise `gh` shim
attempted an unavailable cache update; the installed binary avoided that update,
but network access still required escalation. Cleanup kept branches whose GitHub
state it could not query; it was rerun with approved network access. Treat each
refusal as unmeasured, rather than interpreting an exit-zero wrapper as success.

Resolve migration and workflow filenames with `rg --files` before reading them:
the actual paths here are `173_codex_history_notice_issuance.sql` and
`rls-authz-fuzz.yml`. Focused proxy tests create only synthetic loopback listeners;
the sandbox refused those sockets, and the exact tests passed with harness
approval. No provider or shared database access is implied by that local test.

The FK linter is an app-level shell script, not a root-level Python module.
Vitest's app configuration still resolves relative test globs from the caller's
working directory: invoking it at repository root with `--config` found zero
tests. Run the pinned app binary from `apps/web-platform`; the corrected run
executed 28 tests. A delivery mock's `calls` records attempted sends, including
throws; use `results` to distinguish accepted sends from the failed-send cleanup
case. Docker sandbox denial can produce a skipped integration case; rerun with
approval and verify an executed case before claiming SQL evidence. The first
fresh-container attempt timed out downloading its image; a separately created
and dropped synthetic database in the existing local test container passed.
The observed Node deprecation originates in `@tailwindcss/node`; scoped ESLint's
three fallthrough warnings match HEAD. An agent-owned exec session cannot be
polled from the lead's tool session; ask the owning agent for its final verdict.
An anchored hook-name probe used the wrong indentation and matched nothing;
the corrected key-name lookup found the hooks. The installed plugin lacks the
CI-only hook-exclusion reference present in this worktree; no exclusion was used.

Semgrep's `auto` configuration requires metrics, so the metrics-disabled rerun
used explicit JavaScript, TypeScript, Python, OWASP and local custom packs.
The default engine crashed before scanning on `io_uring_queue_init`; the
documented `EIO_BACKEND=posix` and single-worker rerun completed. A TypeScript
inline import type caused a partial parse; replacing it with the equivalent
named type import restores scanner coverage. A TLS finding matched a forbidden
configuration string in policy data, not an executed setting. The cancellation
regression's first TypeScript run found a mock argument type too broad for an
existing implementation; the corrected record type passed the compiler.

The continuation also exposed a streaming-shell failure boundary: a SQL
producer can emit valid bytes and then exit nonzero while the consumer still
commits at EOF. Assemble the complete SQL in a checked command substitution
before starting psql, and inject producer failures both before and after partial
output. Keep disposable migration fixtures structurally faithful to every
relation and column the pre-migration guard locks or queries; otherwise an
unrelated missing-table error can masquerade as the intended refusal. Run
`test_rehearsal.py` directly from its path (or set its script directory on
`PYTHONPATH`); unittest module loading from the hyphenated
`codex-qualification` directory cannot import its local `prepare` module. A
runner admission failure on a changed hash is an independent-review hold, not a
reason to refresh the pin automatically.

Keep safety barriers that must survive a later preparation failure before the
fallible preparation step. Migration 170's separate grant revocation must
commit before reading or assembling the replacement SQL; the owner-scoped
function replacement and grant restoration remain one later atomic apply.
Likewise, after an acknowledgment RPC error or false result, read the
tenant-scoped durable acknowledgment state before reporting failure. This
recovers an ambiguous commit without repeating notice issuance or provider work.
