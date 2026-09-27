# Tasks: #8211 PR2 PM4 docs — ADR-220 D1b and ADR-239 accepted

Plan: `knowledge-base/project/plans/2026-09-27-docs-git-data-d1b-accepted-pm4-plan.md`

## Phase 1: Setup

- [ ] 1.1 Run `git fetch origin pull/9048/head`, then `git cat-file -e 0f5cf8934f^{commit}`.
- [ ] 1.2 Check that `git diff 0f5cf8934f HEAD -- .github/workflows/git-data-cutover.yml` prints
  nothing.
- [ ] 1.3 Read the Hetzner server with a `GET`. It must still be id `167392038`, created
  `2026-09-25T09:24:32Z`. If it is not, stop: ADR-239 does not flip.

## Phase 2: Core Implementation

- [ ] 2.1 Re-apply the workflow header:
  `git show 0f5cf8934f -- .github/workflows/git-data-cutover.yml | git apply -R`.
- [ ] 2.2 ADR-220: append `### 2026-09-27 (#8211 PR2, post-merge): D1b is accepted`, about 4
  statements:
  - the condition is met (run 36339208990);
  - the history (run 35119099336);
  - the D5 row;
  - the frontmatter stays `proposed`.
- [ ] 2.3 ADR-239:
  - [ ] 2.3.1 Change `status: adopting` to `status: accepted` in the frontmatter.
  - [ ] 2.3.2 Before `## References`, append `## Amendment 2026-09-27 — accepted (#8211 PR2, post-merge)`.
- [ ] 2.4 C4:
  - [ ] 2.4.1 In the `model.c4` comment block, replace the TARGET sentences with the one-line LIVE
    statement.
  - [ ] 2.4.2 Set the label to `Transport and root authentication LIVE (ADR-220 D1b accepted
    2026-09-27).`
  - [ ] 2.4.3 Change the ADR-237 clause to `(ADR-237, accepted 2026-09-27)`.
  - [ ] 2.4.4 Run `bash scripts/regenerate-c4-model.sh`.
- [ ] 2.5 Runbook: add lines only.
  - [ ] 2.5.1 Add a ticked `#7226` sub-item under the Preconditions `**#7226 / #5914**` bullet.
  - [ ] 2.5.2 Add a Done line to host-key item 4 (run 36119817656, PR #9036).
  - [ ] 2.5.3 Add a Done line to Post-merge order item 5 (runs 35119099336 and 36339208990).

## Phase 3: Testing and ship

- [ ] 3.1 Run the plan's AC1–AC6 locally:
  - YAML equality and the header greps;
  - the ADR `numstat` checks;
  - C4 freshness and count parity;
  - the runbook `numstat` check and greps;
  - `scripts/markdown-lint.sh`.
- [ ] 3.2 Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`, then push.
- [ ] 3.3 Ship:
  - Export `CLAUDE_PLUGIN_ROOT` for the Phase 7 poll.
  - The PR is UNTRUSTED-CI, so merge with auto-merge only.
  - The required checks must be green by name on the exact head SHA.
  - The PR body says `Ref #8211` and `Ref #5914`, and has no `Closes`.
