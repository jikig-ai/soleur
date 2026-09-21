# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-21-fix-git-data-cutover-fence-probe-and-mapper-assert-sequencing-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None. The issue's copy half was out of date: the rsync body and canary_luks_device were deleted when git-data-cutover.sh became a read-only proof (commit 7fb9c5b39).

### Decisions
- The three wrappers are in the 17-file rung-2 hash-bound set, and the committed evidence is valid for the current tree. The wrapper mapper check is deferred to #8211's batch of wrapper edits, for five reasons recorded in the plan.
- This PR adds a read-only fence-shape probe to the cutover dry run (`refuse_if_fence_not_intact`, reporting `probe=fence-shape`). It takes parameters so #8211 can re-run it on FRESH_ROOT. It touches no hash-bound file (AC7).
- The PR uses `Ref #8101`, not `Closes`, because roadmap L27 and PA-36 §(g)(4) name #8101 as a flag-flip dependency. The carried work goes into #8211's body as checkboxes.
- The wrapper check will be unconditional. #8211's rollback must turn the flag off before remounting plaintext.
- The probe checks shape, not content. The byte-identical pre-receive check is carried to #8211.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; review and research agents (see the plan).
