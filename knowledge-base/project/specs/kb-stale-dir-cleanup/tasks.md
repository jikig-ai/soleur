# Tasks: KB Project Directory Migration

## Step 1: Move files with `git mv`

- [ ] 1.1 Move top-level files from brainstorms/, learnings/, plans/, specs/ into project/ counterparts
- [ ] 1.2 Move archive subdirectory files individually (target dirs already exist)
- [ ] 1.3 Move specs feature subdirs (specs/feat-*/*)
- [ ] 1.4 Verify old dirs removed and file counts correct

## Step 2: Update 4 source files

- [ ] 2.1 Update `apps/web-platform/server/workspace.ts` — nest KB dirs under `project/`
- [ ] 2.2 Update `apps/web-platform/test/workspace.test.ts` — expect `project/` subdirs
- [ ] 2.3 Update `apps/web-platform/test/canusertool-sandbox.test.ts` — update synthetic path
- [ ] 2.4 Update `scripts/test-all.sh` line 6 — update comment path

## Step 3: Best-effort sed on content cross-references (~139 files)

- [ ] 3.1 Run sed with all 4 patterns across all moved content files (cross-directory, not just intra-directory)
- [ ] 3.2 Verify zero double-prefix (`project/project/`) introduced

## Step 4: Verify and commit

- [ ] 4.1 Grep verification: zero old-path refs in source files
- [ ] 4.2 Run `bun test` in `apps/web-platform/`
- [ ] 4.3 Commit and push
