---
branch: feat-one-shot-10198-root-anchored-glob
created: 2026-10-23
---

# Decision Challenges — feat-one-shot-10198-root-anchored-glob

Rulings table for headless one-shot planning (ADR-084 channel). `pending - assumed` rows are
technical forks the planner could not escalate (no agent-spawn capability in this harness); the
named default was applied and is challengeable at review.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Root-form spelling: generalize to ANY `/`-free head (`glob:x*.sh` file-prefix glob) vs empty-head-only (`glob:*.sh`) | technical | pending - assumed: generalize — one rule, one code path per site; an empty-only carve-out needs its own decline arm for `x` heads and buys nothing. Reclassification is safe: `/`-free heads are census-RED malformed today, so no live array can carry one |
| `_affected_glob_split` home: new `scripts/lib/affected-glob.sh` vs inside `test-affected-paths.sh` vs per-site inline | technical | pending - assumed: new lib — the data file is mass-edited by the in-flight S4 drain PR #10945 (zero-collision requirement from the issue) and is index-grammar data-shaped; a purpose-named lib also hosts the doctrine comment |
| Missing glob lib posture in test-all.sh: fold into `_AFF_LIB_OK` degrade vs hard-require (`_REL_LIB` class) | technical | pending - assumed: fold into `_AFF_LIB_OK` — the mint/hit arms are only reachable inside the classify walk, which already degrades to select-all when the index is missing; a hard-require would make a missing NEW lib wedge the whole runner where today nothing does |
| th8 coverage doctrine: per-member witness (literal + well-formed root glob `[[ == ]]` match) vs bare-tail class form (`*<ext>`/`**<ext>` only) | technical | pending - assumed: per-member witness — the census object is the FILE itself, so a literal `x.test.sh` or a subset glob that matches it genuinely covers it (th6's literal-satisfaction decline applies to CLASS certification, a different question) |
| Reclassification safety claim (`glob:x*.sh` malformed→narrow cannot silently narrow anything live) | technical | ruled — evidence: the lint census REDs every `/`-free head today ("its head does not end in /", pinned by M22), so no tracked array can hold the shape; hand-placed `^glob:` relevance entries swept by `git grep '\^glob:' scripts/lib/test-relevance-paths.sh` in Phase 3 |
| `covers()` root arm and dir-less DIR refs (`docs`, `knowledge-base`) | technical | ruled — a `/`-free dir ref must decline: `glob:*` certifying a whole directory would be the #9969 hole one layer down; the arm requires dir-less AND not-a-dir (`p not in _tracked()[1] and not isdir(p)`) |
| Issue's stated triggers did not fire (dir-less corpus count still 0; SUITE_GLOBS unchanged) | operator (priority/schedule) | operator pulled the issue — recorded as fact in the plan's Premise Validation and in the ADR-242 decision-28 text; no action |
