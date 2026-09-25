# Column defaults can invalidate the next backfill predicate

Migration 141 added `conversations.engine_binding_state` with default `pending`,
then tried to mark conversations with persisted engine runs `bound` only when
their state was `legacy`. Existing rows received `pending`, so the first
backfill matched no rows. A read-only production aggregate after PR #8849
found one persisted conversation run with a `pending` conversation marker.

For a new status column, derive each backfill predicate from the value rows
actually hold immediately after `ADD COLUMN`. Verify the joined count before
and after deployment. Here migration 142 updates only conversations joined to
persisted conversation runs; it does not read prompt or message content.

The same review found that an UPDATE-only marker trigger left INSERT values
tenant-selectable, and a custom GUC was a weak transition authority. Migration
142 adds an INSERT guard and authorizes marker transitions by the trusted
function owner. The local RLS integration test exercises normal binding,
forged INSERTs, and GUC spoofing.

## Session command errors

- The worktree manager returned a usage error for `--help`; its help entry is
  `help`. Run it from the repository root when creating sibling worktrees, or
  the resulting worktree is nested beneath the current one.
- `gh issue create` rejected the first #8909 filing without `--milestone`.
  Include the milestone on the first invocation; the hook made this
  constraint discoverable before any issue was created.
