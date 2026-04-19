---
category: best-practices
tags: [testing, security, destructive-tests, allowlist, regex, runbook]
date: 2026-04-18
related_rule: cq-destructive-prod-tests-allowlist
related_issues: [1448, 2597]
---

# Destructive-test allowlist regex must pin the exact synthetic-identifier shape

## Problem

PR #2597 (MU1 verification artifacts) introduced an `assertSyntheticEmail`
gate on `auth.admin.deleteUser` — compliant with `cq-destructive-prod-tests-
allowlist`. The first pass used a permissive regex:

```typescript
const SYNTH_EMAIL_RE =
  /^mu1-integration-[0-9a-f-]+@soleur-test\.invalid$/i;
```

Security review flagged this as too wide. The synthetic emails are always
`mu1-integration-<v4-uuid>@soleur-test.invalid`, but `[0-9a-f-]+` accepts
`mu1-integration-a@soleur-test.invalid` — any hex-ish blob of any length.

The risk was theoretical for the test file alone (it constructs emails
with `randomUUID()`), but the same regex was copy-pasted into the
**operator runbook's manual sweep one-liner**. If an unrelated test
suite, fixture, or seed script ever persisted a user matching the
permissive pattern (e.g. `mu1-integration-1@...`), the operator sweep
would delete it silently.

## Solution

Pin the regex to the exact identifier shape the test generates — v4
UUID (8-4-4-4-12 hex):

```typescript
const SYNTH_EMAIL_RE =
  /^mu1-integration-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@soleur-test\.invalid$/i;
```

Exact-shape regex costs nothing at test time, but makes the operator
sweep safe to run in `-c dev` even as the test suite evolves. The
runbook and test MUST share the regex shape; if they drift, the
runbook can match users the test never created.

## Key Insight

The `cq-destructive-prod-tests-allowlist` rule says "gate on a synthetic
allowlist." What it doesn't say is that the allowlist is often a
**three-site contract**: (1) the test fixture that generates the
identifier, (2) the test's allowlist guard before `deleteUser`, and
(3) the operator runbook's manual sweep for orphaned fixtures. All
three must use the *same* shape, and the shape must be the *exact*
identifier pattern the fixture generates — never a permissive prefix
that could match a future unrelated test's leftovers.

Secondary insight: the runbook sweep one-liner should also gate on the
**Supabase URL shape** before running any delete, so a typo'd `-c prd`
instead of `-c dev` cannot delete real users even if their email
accidentally matches the prefix. Defense-in-depth is cheap when the
detection surface is one `throw` statement.

## Prevention

Two places the pattern should be checked in future PRs:

1. When adding a new destructive-prod test site, grep for
   `cq-destructive-prod-tests-allowlist` or `assertSynthetic*` to find
   sibling sites and confirm the regex shape matches the fixture's
   identifier generator exactly.
2. When writing an operator runbook that sweeps fixture leftovers,
   copy the regex from the test file (same source), and add a
   non-prod URL assertion at the top of the sweep snippet.

## Session Errors

**CWD drift after `cd apps/web-platform` for vitest** — Subsequent Bash
calls assumed repo-root CWD; `ls apps/web-platform/infra/` failed.
Recovery: `pwd` + absolute paths. Prevention: rule
`cq-for-local-verification-of-apps-doppler` already prescribes single-
call `cd <abs-path> && cmd` — no new enforcement needed; sharpen
adherence.

**Learning-file path citation drift** — Runbook initially cited
`knowledge-base/project/learnings/2026-04-05-docker-seccomp-blocks-bwrap-
sandbox.md` but actual path is `security-issues/docker-seccomp-blocks-
bwrap-sandbox-20260405.md`. Caught by grep before commit. Prevention:
when citing a learning path in any doc, `find knowledge-base/project/
learnings -iname "*<keyword>*"` before writing the link.

**Speculative follow-up milestoning** — Filed #2607 (orphan GC) to
Phase 4 initially; review flagged as speculative and it was re-
milestoned to Post-MVP/Later. Prevention: already covered by
`wg-when-deferring-a-capability-create-a` re-evaluation criteria; the
simplicity reviewer caught the miss in the same session.

## Cross-references

- AGENTS.md rule `cq-destructive-prod-tests-allowlist`
- PR #2597 review commit `8d67b6b3`
- Test: `apps/web-platform/test/mu1-integration.test.ts`
- Runbook: `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md`
