---
feature: feat-one-shot-adr-237-accepted
plan: knowledge-base/project/plans/2026-09-27-docs-adr-237-accepted-host-key-step-4-plan.md
lane: single-domain
---

# Tasks — flip ADR-237 to accepted (host-key post-merge step 4)

## 1. Core Implementation

- [ ] 1.1 ADR-237 frontmatter: `status: adopting` → `status: accepted` (no other frontmatter change).
- [ ] 1.2 Leave `## Status` byte-identical.
- [ ] 1.3 Insert `## Addendum — 2026-09-27 (#7226): accepted at post-merge step 4` before `## References`
  (text per plan Phase 1; cites run 36119817656, the three `role=... verdict=ok` lines, both `pinned` lines,
  the exit-5 `already_cut_over` store-probe failure, and TOFU_ARM/#5914 + step 5 as still open).
- [ ] 1.4 Runbook Preconditions: tick `- [x] Step 4` and append the run-id evidence sentence; nothing else.

## 2. Verification

- [ ] 2.1 AC1–AC5 greps/diffs from the plan (status value, Status paragraph unchanged, one addendum, checkbox, diff scope has no `knowledge-base/legal/**`).
- [ ] 2.2 Commit exact paths only with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`; no local test battery.

## 3. Ship

- [ ] 3.1 PR body: `Ref #7226`, `Ref #5914` (never Closes).
- [ ] 3.2 Required checks green by name on exact head SHA → `admin-merge-ready.sh` → `gh pr merge --admin --match-head-commit <sha>`.
