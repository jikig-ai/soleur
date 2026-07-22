---
title: "Plan prescribing `bun update <pkg>` for a transitive-only Dependabot bump contradicts the surgical-edit ban list"
date: 2026-07-18
category: workflow-patterns
tags: [dependabot, lockfile, bun, plan-vs-work, security-bump]
module: plan, work, deepen-plan
---

# Plan prescribing `bun update <pkg>` for a transitive-only bump is a banned command

## Problem

A one-shot pipeline remediating 8 Dependabot alerts (undici + js-yaml transitive
bumps) produced a plan whose **Phase 2** prescribed, verbatim:

```
cd apps/web-platform && bun update undici js-yaml
bun update js-yaml
```

Executing `bun update undici js-yaml` **overshot**: it elevated `undici` and
`js-yaml` from transitive deps to **direct** deps in `apps/web-platform/package.json`
(`"js-yaml": "^5.2.1"`, `"undici": "^8.7.0"` — both MAJOR jumps past the intended
`7.28.0` / `3.15.0`), and also bumped unrelated direct deps (sentry, swr). This is
the exact ban-list case documented in
[`work-lockfile-bumps.md`](../../../../plugins/soleur/skills/work/references/work-lockfile-bumps.md):
bun has no clean transitive-only mode, so `bun update <pkg>` either elevates the
target to a direct `package.json` dep or bumps every direct caret-ranged dep.

## Solution

The guardrail worked: the **work** phase caught the deviation because
`work-lockfile-bumps.md` already exists as the authority. Recovery:

1. `git checkout -- apps/web-platform/package.json apps/web-platform/bun.lock` (revert the overshoot).
2. Apply the **surgical `bun.lock` edit** — replace only the version string + `sha512` integrity on each target entry (fetch the sha via `npm view <pkg>@<ver> dist.integrity`); dependency/bin metadata is identical across the 3.14.2→3.15.0, 4.2.0→4.3.0, and 7.24.6→7.28.0 bumps, so no structural change is needed.
3. Validate with `bun install --frozen-lockfile` in both dirs (validates the integrity sha against the registry tarball; refuses if the lockfile diverges from `package.json`).
4. Verify `git diff --stat origin/main -- '*/package.json'` is empty.

## Key Insight

**A plan is authoritative for INTENT, never for the exact command** — same class as
`hr-when-a-plan-specifies-relative-paths-e-g`. For a transitive-only lockfile bump,
the plan's intent ("bump undici/js-yaml to patched") is correct, but its prescribed
mechanism (`bun update <pkg>`) is on the work skill's ban list. `/work` must
consult `work-lockfile-bumps.md` whenever the diff touches `bun.lock`, and prefer
the surgical edit as the first attempt — not execute the plan's literal `bun`
command.

## Session Errors

1. **Plan prescribed a banned `bun update <pkg>`.** Recovery: revert package.json + bun.lock, use the surgical version+sha edit. **Prevention:** plan/deepen-plan for a transitive-only or Dependabot lockfile bump should reference `work-lockfile-bumps.md` and NOT prescribe `bun update <pkg>`; `/work` treats any `bun.lock` transitive bump as a surgical-edit task.
2. **npm rewrote the root `package-lock.json` `name` field to the worktree dir name** on `npm install` (root `package.json` has no `name`). Recovery: restored to origin/main's value to keep the diff surgical. **Prevention:** already documented in `work-lockfile-bumps.md` §Sharp Edges — verify the `name` field after any `npm update`/`npm install` in a worktree. One-off (covered).

## Tags
category: workflow-patterns
module: plan, work
