---
name: cron-list
description: "This skill should be used to list scheduled cron workflows (recurring vs one-time, --json supported) — the first-class Read verb that runs the list step of soleur:schedule."
---

# cron-list

Lists existing scheduled cron workflows — the **Read** verb of the cron CRUD
set. A thin pointer: the listing logic lives once in `soleur:schedule` so the
recurring-vs-one-time classifier never drifts across files.

## When to use

- Auditing which scheduled workflows exist and their cadence before creating,
  triggering, or deleting one.

## When to use this skill vs other cron skills

The cron CRUD set: `soleur:schedule` (Create — and the canonical home of the
list/delete logic), **`cron-list` (Read — this)**, `soleur:cron-delete`
(Delete), `soleur:trigger-cron` (Run-now / fire on demand). `schedule` remains
the create entry point and keeps its `list`/`delete` prose as the single source
of truth — these verbs cross-link to it, they do not re-implement it.

## Procedure

Execute the **``### `list` ``** section of
[`plugins/soleur/skills/schedule/SKILL.md`](../schedule/SKILL.md): enumerate
`.github/workflows/scheduled-*.yml`, classify each by cron shape (5-field with
explicit single integers for minute/hour/day/month + `*` for year → one-time;
anything else → recurring), and display the mode tag + cron. With `--json`,
emit an array of `{name, cron, mode, skill}`.

Any worked example MUST derive the count dynamically — the number of scheduled
workflows is environment-dependent (it differs between a feature worktree and
the bare-root/main checkout), so never hardcode it:

```bash
git ls-files '.github/workflows/scheduled-*.yml' | wc -l
```

## Known limitations

Inherited from `soleur:schedule`: V1 reports mode + cron only. Richer per-run
state (`pending` / `disabled_inactivity` / `fired-failed`) is deferred — run
`gh workflow list` and `gh workflow view <NAME>` directly for now.

## Cross-references

- Canonical logic + full caveats: [`soleur:schedule`](../schedule/SKILL.md) `### list`.
