---
title: "ADR ordinal collision on rebase: renumber YOUR ADRs, protect main's — key on the discriminating issue number"
date: 2026-07-05
tags: [adr, rebase, reconciliation, ordinals, c4, one-shot, merge-conflict]
category: workflow-patterns
---

# ADR ordinal collision surfaced at rebase — renumber your own, protect main's

## What happened

A long-running feature branch (#6005, cosign private-GHCR verify) authored **ADR-085**
(cosign) + **ADR-086** (minter). Meanwhile a sibling PR (#6007, operational-inbox) merged to
main and **also took ADR-085**. The `adr-ordinals` CI gate would have hard-failed on the
duplicate, and `model.c4` carried BOTH ADR-085 references (main's inbox + my cosign) after the
rebase auto-merged the file.

## The reconciliation pattern

1. **`git ls-tree origin/main` the decisions dir at rebase-start** to find the highest ADR
   ordinal actually on main — a plan/branch-time ordinal is stale the moment a sibling ADR
   lands (same class as the migration-number-collision hazard). Here main reached 085, so the
   free numbers were 086/087.
2. **Renumber MINE, never main's.** `git mv` the two ADR files (rename the LATER one first —
   minter 086→087 — so the earlier rename's target 086 doesn't collide with the not-yet-moved
   minter). Then cosign 085→086.
3. **The discriminator is the issue number, not the ADR number.** In shared files (`model.c4`,
   `principles-register.md`) main's ADR-085 and mine coexist. `#6007` = main's inbox (protect);
   `#6005` = my cosign (rewrite). The surgical sed is `sed -i '/#6005/ s/ADR-085/ADR-086/g'` —
   line-scoped by the discriminating issue ref, so main's `#6007` lines are untouched. A blanket
   `s/ADR-085/ADR-086/g` would have corrupted main's inbox references.
4. **Order matters inside a file that references both your ADRs.** The minter file (→087)
   references its own old number (086→087) AND the cosign ADR it supersedes (085→086). Do the
   higher substitution first: `s/ADR-086/ADR-087/g; s/ADR-085/ADR-086/g`. Same for any AP-row /
   ghcr-read-credential.tf that cites both.
5. **Regenerate derived artifacts, don't hand-merge them.** `model.likec4.json` is a generated
   snapshot — take either side of the conflict to finish the rebase, then
   `scripts/regenerate-c4-model.sh` from the merged `.c4` sources (deterministic).
6. **Verify with the real gates, not intuition.** `scripts/check-adr-ordinals.sh` (not a raw
   `uniq -d` — legit multi-part ADRs like `ADR-033-a/b/c` are not collisions), the c4-freshness
   test, and the touched infra suites. Update the downstream issue/PR bodies too (the minter
   follow-up issue #6031 cited ADR-086 → ADR-087; the PR body cited ADR-085 → ADR-086).

## Machine-quirk footnote

On this operator's laptop, **bash heredocs (`cat >> f <<'EOF'`) truncate silently** under the
BD_PROCHOT throttle / libc-segfault instability — a `gh pr edit --body-file` then applied a body
missing its appended marker, and `gh pr edit` still exited 0. Use `printf '…\n' >> f` (or the
Write tool) instead of heredocs when the append is load-bearing, and VERIFY the result landed
(`grep -c <marker>` the live body) rather than trusting the exit code.
