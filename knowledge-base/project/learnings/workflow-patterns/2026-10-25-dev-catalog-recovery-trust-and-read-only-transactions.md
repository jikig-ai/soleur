# Learning: recover dev catalog evidence with verified trust and explicit transactions

## Problem

Recreating PR 9051's worktree restored committed source, not its ignored evidence.
The first metadata collector attempts stopped on a custom public-host alias,
missing provider CA trust and an identity probe whose requested read-only default
did not establish the checked state. Suppressing all connection stderr also hid
the concrete certificate failure.

A separate instrumentation mistake used `^(ti|di|dlr)-[0-9]+` with PostgreSQL
`substring`: its capture group returned only the prefix, not the full workflow
identifier. A prefix observation could not identify the active writer.

## Correction

- Resolve the public URL's canonical DNS name and compare its project ref with
  the parsed pooler username; separately verify dev and production public refs
  differ. Never print credentials or infer a target from a config label alone.
- Obtain the public root certificate from the provider's verified official
  source and HTTPS endpoint. Scope it to the process and retain its digest;
  preserve certificate and hostname verification.
- Issue explicit `BEGIN ... READ ONLY` for identity and catalog probes, check
  server-reported read-only state, and use REPEATABLE READ for the catalog
  snapshot. An environment setting is not proof of the effective transaction.
- Capture connection diagnostics privately and redact known password, username
  and host values before exposing a bounded failure reason. A failed query is
  unmeasured, never a clean result.
- Use a noncapturing regex group for the full workflow match, then correlate
  the observed run ID with a direct GitHub read. Even a correlated advisory
  holder does not establish complete writer exclusion.

## Workflow corrections

The issue-filing gate rejected a prose-only Fix-Size field. The inherited audit
finding was filed under its actual mandatory rule ID on a standalone
`Mandated-By:` line before implementation; no measured size was invented.
Sandbox failures in Git/CLI launchers were rerun through the escalation path,
not treated as evidence that recovery or a shared operation succeeded.

The [dated recovery record](../../specs/feat-one-shot-codex-web-live-paths/recovery-evidence-2026-10-25.md)
owns the observed counts, digests, limitations and remaining gates.

## Recovery continuation — 2026-10-26

The commit guard evaluated the session's default-branch directory rather than
the shell tool's `workdir`. Explicit `git -C <absolute-worktree>` selected the
verified feature branch without bypassing the guard. Prefer that form for
mutating Git operations when the session starts at the repository root.

The original recovery directory and its Git registration disappeared despite
a current branch lease; the actor is not established. The committed/pushed
fixes survived, while uncommitted merge resolutions and ignored captures did
not. Track the event, recover from the known commit in a distinct worktree,
and use a reversible Git worktree lock while active. Do not identify an
unverified cleanup implementation as the cause. A lock is not protection
against arbitrary filesystem removal. Run global tool-cache installation from
a stable directory, and preserve source checkpoints before long waits.
