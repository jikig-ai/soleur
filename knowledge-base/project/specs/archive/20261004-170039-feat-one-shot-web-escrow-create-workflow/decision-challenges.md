# Decision challenges - feat-one-shot-web-escrow-create-workflow

Appended by plan and plan-review on 2026-10-04 (headless pipeline: not asked, persisted for the ship phase to render and file).
The plan proceeds with the owner's stated direction in every row; where a reviewer argued for a change, the default taken is named.

## User-Challenge

1. **"The one deliberate gate change" is two.** The brief names the two "NO other job / NO other workflow FILE" rows of
   `terraform-target-parity.test.ts`. A second edit is forced by CI: the main-root planner census
   (`MAIN_ROOT_TF_WORKFLOWS`, `expect(found.length).toBe(3)`) finds any workflow with `terraform plan`/`apply` and an
   `INFRA_DIR`, so the new file reddens it, and the census row also demands `TF_VAR_terraform_version` parity. Default taken:
   both edits, both flagged for explicit review in the PR body; the apply-job rows and the "NO other job" row stay byte-identical.
   Re-evaluate: none needed unless the owner wants the census edit declined (the workflow would then ship red).
2. **Retirement tripwire inside the workflow (CTO, devex).** Considered: abort when #9372 closes. Default taken: not built (it needs a
   `gh` call and `issues: read`, which the owner's "no host contact, no state verbs" shape and the suite pin absent, and it could block
   an authorized dispatch). Retirement is a single checklist comment on #9372 listing every coupled artifact (plan R2). Re-evaluate
   at #9372.

## Taste

3. **Suite size (DHH, simplicity, CTO).** About 700 lines and about 20 distinct mutants for a workflow meant to be deleted with #9372.
   Default taken: kept (the owner asked for mutant rows over each listed pin), with duplicate mutants merged (24 to 20) and the
   text-hygiene rows collapsed into one parsed pass. Cheap to cut further at work time without losing an owner-listed pin.
4. **Names reader as a script vs a mode in the existing checker (DHH, simplicity).** Default taken: a 70-line script, because the
   checker and the preflight wrapper are tested production-path scripts run by two birth jobs, and the inline alternative is an AC3
   violation. The work phase re-checks whether a names-only mode is smaller before writing it (plan Phase 1).
5. **Guard 3's exempt-file shape row (DHH, simplicity).** Reviewers would keep only a filename exclusion. Default taken: keep the
   structural pins, because the owner wrote "only with the structural pins".
6. **Docs as a second PR (DHH, simplicity; the CTO and CLO prefer one PR).** Default taken: single PR; the split assessment names the
   docs as the seam if review wants a smaller diff.
7. **ADR-263 addendum vs a new ADR (architecture).** Default taken: the addendum, as the owner asked.
8. **Cleanup of runner-local plan files (CLO asked, simplicity would cut).** Default taken: kept as one `rm -f` line inside the summary
   step (no separate step).
9. **Pre-apply copy of the state object and a second names check inside the apply step (architecture).** Default taken: declined; it
   adds a raw state read to a workflow scoped to no state verbs, and #7992 tracks versioning. Re-evaluate before any web-class volume
   is formatted (#9372 criterion 2).
10. **`plan_only` defaults to true and the guard form is `inputs.plan_only != true`.** The brief gave no default; true is the safe one and
    matches the repo's Guard 5 convention.
11. **Whether the workflow's own pass floor and `PROMOTED_FILES` entry are the right registration (CTO).** Mandatory under the
    shrink-only vacuity ledger; the retirement checklist reverses it.

## Not Yet Specified candidates

None.
