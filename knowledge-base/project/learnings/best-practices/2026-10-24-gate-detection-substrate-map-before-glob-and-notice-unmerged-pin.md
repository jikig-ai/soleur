---
date: 2026-10-24
pr: 11016
issue: [11014, 11015]
tags: [plan-gates, detection-sets, attribution, skill-body-budget, test-anchors]
---

# Learning: enumerate the substrate map before writing detection globs; NOTICE pins for unmerged sources need the PR-head SHA

## Problem

Adding the `## Task Design` conditional plan gate (#11015) produced a detection set scoped to `scheduled-*.yml` + `cron-*`/`oneshot-*` Inngest functions — the two paths the author already knew. The structural-enumeration review seat mapped **seven** substrate families that create autonomous tasks (any `.github/workflows/*.yml`, Inngest registration-side edits, `CHECK_REGISTRY`/API reminder arms, `cron.schedule(` migrations, host `cron.d`/`.timer`, `setInterval` daemons, `github_repository_file` in TF). A name-glob detection set describes the naming convention, not the mechanism class; the convention has 14+ counterexamples in-tree.

Separately, a `NOTICE` attribution entry pinned `at HEAD c55ee46` — the audit SHA on upstream `main` — for a file that exists only on the peer's **open, unmerged PR branch** (`software-factory-skill @ b59cab42`). The pin was syntactically correct and factually empty.

## Solution

- Detection contracts belong in a **substrate table** (substrate × file-list/diff signal) in a canonical reference file, not an inline glob list — `plugins/soleur/skills/plan/references/task-design-gate.md` §Detection.
- For convention-justified rules (`_`-prefix = shared code), state the rule as SHOULD + name the known counterexamples + prescribe the naming for new files ("name new helpers `_<name>.ts`") — a false invariant as the load-bearing justification invites a bypass when a reader finds the exception.
- Attribution pins for **unmerged** upstream sources must carry the PR number, branch, and PR-head SHA (`PR #1316, branch software-factory-skill @ b59cab42`), never upstream `main`'s HEAD — `gh api repos/<owner>/<repo>/pulls/<N>` resolves it.

## Key Insight

A gate whose trigger is "new X" is only as wide as the enumeration of ways X gets created. Do the enumeration FIRST (structural map), then write the globs — writing the globs first produces a gate that documents the convention and misses the mechanism.

## Session Errors

1. **Both lifecycle skills pushed over byte ceilings** by the new gate sections. **Prevention:** when a new conditional gate's contract exceeds ~1KB, extract it to `references/<gate>.md` with a stub pointer immediately (ADR-229 pattern) instead of iterating compressions.
2. **A byte-budget trim deleted §4.9's pass-through tail** (stray block on main sat under §4.10). **Prevention:** before deleting a block for bytes, grep its `Step N`/`Why:` referent and relocate, never drop — two review seats caught this independently.
3. **NOTICE inserted before the wrong `MIT License (upstream)` anchor** (3 occurrences in-file). **Prevention:** anchor NOTICE edits on the entry's bundle paragraph tail (`this entry is its attribution.`), not on repeated license headings.
4. **NOTICE pin cited a SHA where the file never existed.** **Prevention:** verify `gh api /contents/<path>?ref=<sha>` before citing; unmerged-PR sources pin the PR head.
5. **Test needle `# key:` mismatched emitted `#   key:` indentation.** **Prevention:** pin needles to the emitted whitespace shape and mutation-drive each new assertion.
6. **`non-_` invariant stated as fact while 4 helpers contradicted it.** **Prevention:** grep the directory the invariant describes before asserting it.
7. **Step 0b fast-path skip read as preceding the hard error.** **Prevention:** order gating text before the skip sentence; pin the ordering with an assertion.
8. **`--design-*` values unvalidated → newline YAML injection.** **Prevention:** free-text flags that write into generated YAML get the same single-line regex treatment as Step 0c's flags.
9. **factory-map cited `agents/...` without `plugins/soleur/` + a wrong "seven layers" set.** **Prevention:** resolve every citation path + re-read the cited section's enumeration before restating it.
10. **Detection glob list missed 5+ real substrates.** **Prevention:** structural-enumerate creation paths before writing detection (Key Insight).
11. **Test anchors on bare tokens / count-1 parity / headings only.** **Prevention:** anchor on wiring forms (`taskDesign: {`, `GATE_VERDICT`), per-copy `grep -cF` counts, and substitution tokens — then drive a mutation red.
12. **`(Conditional)` qualifier, `note=` telemetry, pinned halt message dropped in compression.** **Prevention:** when compressing a new sibling section for bytes, diff its convention fields against the nearest sibling before trimming.
13. **Tally increment run from the bare root wrote the wrong ledger** (early-session). **Prevention:** pipeline-tally commands always carry `-C <worktree>` or workdir.
14. **`last_reviewed` hook false-positive on staged unrelated changes** — resolved with literal paths. **Prevention:** literal absolute paths in hook-adjacent git commands.
15. **Stale `non-`_`-prefixed` assertion after contract rewrite.** **Prevention:** re-run the suite after every contract edit, not just at task end.
16. **`UNFENCED` keyword dropped in a rewrite while a test pinned it.** **Prevention:** grep the contract's pinned keywords before/after rewriting it.

## Tags

plan-gates, detection-sets, attribution, skill-body-budget, test-anchors
