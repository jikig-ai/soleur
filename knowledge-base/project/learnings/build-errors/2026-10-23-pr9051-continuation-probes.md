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
