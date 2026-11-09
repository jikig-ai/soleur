# Phase 4 false alarms: why the fetch and the message table are load-bearing

Moved out of `postmerge/SKILL.md` Phase 4 to keep the body under its ceiling (ADR-229); SKILL.md keeps the one-line rule and a pointer.

**Why:** PR #7240 — Phase 4 read `git show main:` while local `main` sat 2 commits behind, reported the PR's own new learning file as MISSING, and the same stale ref undercounted `blkid` occurrences 2-vs-8 in a file the PR had rewritten. **And PR #7770** — Phase 4 addressed the merge SHA correctly, as the paragraphs above instruct, and still reported all 5 spot-checked files MISSING: the worktree had not fetched the merge commit, and git's `exists on disk, but not in <sha>` wording was read as a verdict about the tree. One `git fetch` made all 5 read correctly. Both failures are the same shape — Phase 4 manufacturing a false alarm about the merge it exists to confirm — reached by two different routes, which is why the fetch and the message table above are both load-bearing.
