---
name: cron-delete
description: "This skill should be used to delete a scheduled cron workflow by name — the first-class Delete verb that runs the delete step of soleur:schedule, with a confirm gate."
---

# cron-delete

Deletes a scheduled cron workflow by name — the **Delete** verb of the cron CRUD
set. A thin pointer: the delete logic lives once in `soleur:schedule`.

## When to use

- Removing a scheduled workflow (recurring or one-time) that is no longer needed.

## When to use this skill vs other cron skills

The cron CRUD set: `soleur:schedule` (Create — and the canonical home of the
list/delete logic), `soleur:cron-list` (Read — list), **`cron-delete` (Delete —
this)**, `soleur:trigger-cron` (Run-now / fire on demand). `schedule` remains
the create entry point and keeps its `list`/`delete` prose as the single source
of truth — these verbs cross-link to it, they do not re-implement it.

## Arguments

<arguments> #$ARGUMENTS </arguments>

Required: `<name>` (the schedule name, matching
`.github/workflows/scheduled-<name>.yml`).
Optional: `--yes` / `--confirm` (skip the confirmation prompt).

## Procedure

Execute the **``### `delete <name>` ``** section of
[`plugins/soleur/skills/schedule/SKILL.md`](../schedule/SKILL.md):

1. Verify `.github/workflows/scheduled-<name>.yml` exists; if not, point the
   operator to `soleur:cron-list` to see available schedules.
2. Confirm (unless `--yes`/`--confirm`).
3. Remove the file.
4. Report that the schedule stops once the deletion is merged to the default
   branch (GHA cron triggers fire only from workflows on the default branch).

## Known limitations

- A one-time (`--once`) schedule whose tracked issue closed pre-fire may not
  self-neutralize on the abort path — see `soleur:schedule` "Known Limitations"
  for the migration sweep. Deleting the workflow file here is always sufficient
  to stop future fires once merged.

## Cross-references

- Canonical logic + full caveats: [`soleur:schedule`](../schedule/SKILL.md) `### delete <name>`.
