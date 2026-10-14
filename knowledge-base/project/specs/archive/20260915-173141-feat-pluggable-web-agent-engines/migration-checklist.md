# Migration Checklist — feat-pluggable-web-agent-engines (#8082)

Migration: `apps/web-platform/supabase/migrations/138_agent_engine_runs.sql`

## Scope

Migration 138 adds workspace engine defaults, immutable conversation/routine
run bindings, append-only engine events, owner/member RLS policies, and the
membership-scoped SECURITY DEFINER RPCs used by the web adapter boundary.

## dev apply — pending (post-merge CI)

The dev apply is deferred to the `tenant-integration` pull-request workflow,
which runs `apps/web-platform/scripts/run-migrations.sh` against the dev
configuration with the unmerged-apply allowance. This keeps the shared dev
database aligned with the PR head without a hand-applied migration.

## prd apply — pending (post-merge, automated)

The release workflow applies migration 138 after PR #8082 merges to `main`.
Its `verify-migrations` job is the post-merge runtime check for the three new
tables and their RPC grant/RLS posture. Preflight Check 1 therefore skips the
pre-merge REST probe under its documented deferral path; ship Phase 7 performs
the same read-only verification after the release migration completes.

## Privacy and retention

The migration carries lawful-basis and retention annotations. Account erasure
anonymises workspace settings and run identity while preserving bounded event
lineage for operational audit; customer-content enablement remains gated on a
separate retention and vendor-erasure disposition.
