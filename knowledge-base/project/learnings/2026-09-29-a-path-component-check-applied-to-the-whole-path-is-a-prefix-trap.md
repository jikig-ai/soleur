---
title: "A path-component check applied to the whole path is a prefix trap — and a hook pinned to the checkout is a version bug, not a staleness bug"
date: 2026-09-29
category: best-practices
module: hooks
issues: [9239]
prs: [9241]
tags: [resolver, plugin-cache, path-anchoring, systemd, stale-worktree, self-publish]
---

# A path-component check applied to the whole path is a prefix trap — and a hook pinned to the checkout is a version bug, not a staleness bug

## Problem

#9239 shipped a resolver shim so `.claude/settings.json` stops exec'ing the
*checkout's* copy of `memory-backstop.sh` and instead picks the newest
`BACKSTOP_REVISION` among the checkout, a managed copy, and both plugin
caches. The incident behind it: three TasksMax/pids.max crashes happened
because a resumed session's *worktree* owned the executed code — updating the
plugin updated nothing on the exec path.

During review, a defensive filter — "cache candidates must contain a `soleur`
path component" — was applied to the **whole candidate path**. The repo's own
affected-gate runs under `/var/tmp/soleur-run.<pid>.*/`, an ancestor dir that
contains `soleur`, so every foreign-plugin fixture candidate matched and the
gate went red on the very test written to pin the exclusion.

## What actually generalizes

**Check a namespaced name on the part that is namespaced, not on the string
that happens to contain it.** The cache layout is
`<cache-root>/<marketplace>/<plugin>/<version>/hooks/…`; the trust question is
about `<plugin>`, so strip the root first:

```bash
rest="${p#"$HOME"/.claude/plugins/cache/}"
case "$rest" in *soleur*/*) … ;; esac
```

The same shape bites anywhere a "does this path belong to X" check runs against
an absolute path — tmpdir names, worktree roots, `$HOME` components are all
environment-controlled and will eventually contain the token. Compare the
suffix after the known root, or match on a pinned segment.

**A marker ordered by `>` needs a strictly-greater gate, not a different
gate.** Guard 1 originally required `new != old`. A *decreased* marker merges
green while being undeliverable everywhere — three review lenses found it
independently. When the ordering is `>`, the gate must reject `<=`.

**The thing that fixes stale state must outlive the thing that ran it.** The
sweep could not rely on the hook that *adopted* the stale scope (it might
never fire again); `repair_stale_scopes` runs from any *newer* session's
SessionStart and converges every `soleur-agent-*.scope` in place. Persistent
harm (a systemd scope's caps) needs a reconciler, not a one-time patch.

**Publish-before-exec turns a crash into a completed upgrade.** Install to the
managed path *then* exec; a hook that dies still leaves the host upgraded.

## Session Errors

- **Three implementation agents hit a transient free-model rate limit mid-fan-out.**
  Recovery: `run_subagent --resume` preserved transcripts; all three completed.
  Prevention: none needed (transient infra), but the partial-worktree state
  was inspected before resuming — resume is only safe when the files tell the
  same story.
- **`git fetch` without `--no-tags` tripped the tag-authorship census.** —
  Recovery: `--no-tags` added; the census went green. Prevention: already
  enforced — `battery-tag-authorship` reds on the shape.
- **Fixture-relative-assert baseline went stale twice** (vendored hook, then
  the new Guard-1 test file). Recovery: `--write-baseline` after the file set
  settled. Prevention: the gate names the fix; on diffs that *add files*
  expect the regeneration, don't treat the first regen as final.
- **Stale-base census failure after `origin/main` advanced +29 commits.**
  Recovery: rebase. Prevention: expected on a fast-moving repo; the failure
  mode is recognizable (census orphans named after someone else's merge).
- **Attempted `git stash` in a worktree** — hook blocked it correctly.
  Prevention: already hook-enforced (hr-never-git-stash-in-worktrees).
- **Nested `[[ ]]` syntax error in a test edit** — caught by `bash -n`
  immediately. One-off; prevention is the syntax check that already exists.
- **Agent C disclosed `rm -rf /tmp/tmp.*`** during fixture cleanup — broader
  than intended, no observed damage. Prevention: scope deletions to a
  captured `$TMPDIR` variable, never a wildcard over a shared directory.

## Prevention

- The resolver suite carries the ancestor-trap arm (`soleur-tainted` fixture
  root) and the foreign-namesake exclusion arm, so both halves of the trap
  are pinned.
- Guard 1's fixture suite (`scripts/check-backstop-revision.test.sh`) pins
  the strictly-greater contract, the watched-file set, the decoy-comment
  anchor, and the BASE_REF override — a `!=` regression is a red arm, not a
  review finding.

## Related

- ADR-261 (version-independent hook resolution) — the design record.
- #7166 / #7169 (ADR-161/162 family) — the backstop's origin.
- #9246 — pre-existing re-entry `OOMPolicy` defect found during review,
  filed separately.
