---
date: 2026-11-09
tags: [ci, security, teardown, oracle]
category: workflow-patterns
---

# S4 retirement: sentinel re-scope + `python3 -` cwd shadowing (#9729)

## What happened

The S4 retirement PR (#12521) deleted `ci-pr-affected-replay.py` while `oracle-review-required` still
imported `RATCHET_ORACLE` from it. Re-scope: committed `scripts/ci-oracle-surface.txt` (11 members,
self-membered) + fallback chain base-surface → base-replay.py (legacy) → HEAD-surface, all with
fail-closed-on-empty. Two findings worth recording:

1. **`python3 -` puts the process CWD at `sys.path[0]`** — inside a `contents:read` required gate
   running on a PR-controlled merge-ref checkout, a planted `argparse.py` at repo root shadows the
   stdlib and forges the list / execs code. `python3 -I -` drops it. The same exposure existed on
   main's primary path; the fallback arm now runs `-I`.
2. **A deleted producer's required context strands its own PR** — atomic diff + `gh pr merge
   --admin` is the only merge path, and the merge message MUST carry `[ack-destroy]` on its own
   line or `apply-github-infra.yml`'s destroy guard fails the post-merge apply (#12282 precedent).
   Also: the PR's own `oracle-review-required` stays green because the job re-execs the **base**
   driver (`ci.yml:630-641`), not because of the fallback chain — the chain is for post-merge bases.

## Prevention

- Teardowns deleting a sentinel's list-source: re-scope + verify BEFORE the deletion is staged
  (plan ordering constraint); require the self-member line so a dir-listing/symlink/comment file
  can never pass as the list.
- Review seat check: grep deleted identifiers against ALL test files, not only the files the
  deletion touched — `PR_AFFECTED_WEBPLAT_IF` survived in a vitest file's exception arm and would
  have ReferenceError'd the whole suite.
