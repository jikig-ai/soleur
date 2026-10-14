---
title: "A sentinel that certifies a chokepoint must audit the chokepoint's mechanism, not just enumerate the membership"
date: 2026-10-12
category: workflow-issues
module: apps/web-platform/test/helpers/workspace-members-fixtures.ts + test/server/teardown-deleteuser-sentinel.test.ts
issues: [9994, 10096]
---

# The canonical list said "safe" while the helper was silently broken

## Problem

The teardown sentinel's `CANONICAL_HELPERS` set blessed `workspace-members-fixtures.ts` as a
sanctioned raw `admin.deleteUser` site — and every seat (and the original defect analysis) accepted
the certification. In fact `tearDownSharedWorkspace` was broken in the *same* defect class the
sentinel guards: its raw `workspace_members.delete()` fired `workspace_members_audit`, writing
RESTRICT `workspace_member_actions` rows; the subsequent `deleteUser` then 500'd — into a bare
`catch {}`. ~12 caller suites leaked every fixture member silently. A second live misalignment
proved the boundary was never exercised: `attachments-workspace-shared-cascade` called the *new*
helper with a `workspace-fixture-*` email the allowlist rejected, inside another `catch {}` —
a deterministic no-op disguised as teardown.

The architectural lesson that held: **a census guards membership; a claim needs a verifier.**
Enumerating which files may call `deleteUser` cannot tell you whether the blessed call works —
that needs the chokepoint's own failure mode run against a live project (the fixtures suite's live
run is what surfaced it). When a sentinel names a canonical path, the honest audit question is
"what would make this canonical entry silently wrong?" — not "is the list complete?"

## What fixing it took

- `tearDownSharedWorkspace` now delegates per-member teardown to `tearDownTenantUser`
  (`workspace-fixture-` added to `SYNTHETIC_PREFIXES`); the anonymise RPC suppresses the audit
  writer (`session_replication_role='replica'`) so member deletes write no new RESTRICT rows.
- The sentinel became a **ratchet**, not a scope: recursive census over all of `test/**`, three
  enumerated sets (canonical, reviewed-manual, the #10096 drain list), union-of-shapes call-count
  pins per file, and shrink-only semantics — a new carrier anywhere is RED, and a drained file must
  leave the set in the same commit.
- The plain takeaway for the next guard author: **per-file allowlist entries are per-call licenses
  only when the count is pinned** — otherwise "allowlisted" means "unlimited."
