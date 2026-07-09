---
title: "A plan that prescribes a provenance breadcrumb naming the removed literal AND a grep-count==0 AC for that literal is self-contradictory"
date: 2026-07-10
category: best-practices
tags: [plan-authoring, acceptance-criteria, grep-assertion, field-removal, telemetry]
issue: 6292
pr: 6296
module: apps/web-platform/infra
---

# Learning: provenance breadcrumbs that name a removed token collide with `grep -c '<token>' == 0` ACs

## Problem

Resolving #6292 removed the `mem_used_mb` field from the `SOLEUR_ZOT_DISK` telemetry reporter.
The plan (Phase 1.3) prescribed adding a provenance breadcrumb comment in the same file:

```
# (#6292) mem_used_mb dropped — page-cache-confounded; OOM confirmation keys on zot_anon_mb/…
```

…while its own AC1 asserted `grep -c 'mem_used_mb' apps/web-platform/infra/cloud-init-registry.yml == 0`.
Executing the plan verbatim made AC1 read **1**, not 0 — the breadcrumb comment is itself a
`mem_used_mb` occurrence. A bare-token `grep -c` cannot distinguish "the field is still emitted"
(the thing the AC guards) from "a comment documents that the field was removed" (harmless).

## Solution

Reword the breadcrumb to describe the removed field WITHOUT the literal token, so the
emission-gone AC stays clean:

```
# (#6292) host used-memory dropped — page-cache-confounded; OOM confirmation keys on zot_anon_mb/…
```

`grep -c 'mem_used_mb'` now returns 0 while the provenance is preserved ("host used-memory" reads
clearly to the next maintainer). The AC's intent ("the field is no longer emitted") is satisfied.

## Key Insight

This is the plan-authoring instance of the general "grep assertion false-matches own comment"
class ([[2026-06-17-grep-assertion-over-script-body-false-matches-own-comments]]). Two internal
contradictions to catch at plan/deepen time:

- **Breadcrumb-vs-AC:** if a plan prescribes a provenance comment that names the removed literal
  AND a `grep -c '<literal>' == 0` AC, the two collide. Fix at authoring time — either (a) the
  breadcrumb avoids the literal (describe the concept: "host used-memory" not `mem_used_mb`), or
  (b) the AC is scoped to the emit construct (`grep -c 'mem_used_mb=' <the LINE= assignment>`),
  not a whole-file bare-token count.
- **General guard:** a whole-file `grep -c '<bare-token>' == 0` AC is only correct when the token
  appears nowhere legitimate — including comments, decode-table docs, and rejected-signal
  rationale. When the same removal legitimately leaves the token in a "was dropped" comment or a
  concept-contrast (e.g. ADR-096 "not the page-cache-confounded host `mem_used`"), prefer an
  emit-site-anchored assertion over a bare-token count.

The cheap catch is running the ACs at work-time (which surfaced it here in one pass), but the
cheaper prevention is writing the breadcrumb concept-first from the start.

## Session Errors

1. **Worktree `create` reported success but did not persist.** The first
   `worktree-manager.sh create feat-one-shot-6292-drop-mem-used-mb` printed "Worktree created
   successfully!" and installed deps, but `git worktree list` did not show it and the branch was
   absent; a sibling worktree appeared and main advanced (#6294) meanwhile — a concurrent session
   mutating worktrees on the shared bare repo. **Recovery:** `git worktree prune` + retry `create`,
   then verify persistence via `git worktree list | grep <name>` before proceeding.
   **Prevention:** after `worktree-manager.sh create`, always assert the worktree is in
   `git worktree list` (and the branch exists) before the first `cd` into it — a success message
   is not proof of persistence under concurrent bare-repo activity.
2. **`draft-pr` cd failed** ("No such file or directory") — a direct consequence of #1.
   **Prevention:** the verify-after-create guard in #1 makes this unreachable.
3. **AC1-vs-breadcrumb literal collision** (the subject of this learning). Caught in AC
   verification; reworded the comment. **Prevention:** write provenance breadcrumbs concept-first
   (avoid the removed literal) when a `count==0` AC guards that literal.
4. **(forwarded from session-state)** Two plan-subagent Write attempts were harness-blocked
   (main-repo path guard while worktrees exist; existing-plan preservation). Recovered by enhancing
   the on-disk plan. Harness guard working as designed; **Prevention:** none needed.
