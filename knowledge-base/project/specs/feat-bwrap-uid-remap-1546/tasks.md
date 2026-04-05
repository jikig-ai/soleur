# Tasks: investigate bwrap sandbox UID remapping (#1546)

## Phase 1: Document Findings and Close

- 1.1 [x] Update issue #1546 with investigation findings from the plan
- 1.2 [x] Close issue #1546 as "not fixable at this level" with documented limitation
- 1.3 [x] Commit plan file

## Phase 2: Follow-up (New Issue)

- 2.1 [x] Create GitHub issue: verify bwrap sandbox works in production Docker container (#1557)
  - Check if Docker's default seccomp profile allows user namespaces
  - If sandbox is non-functional, assess severity and fix options
  - Milestone: Post-MVP / Later (or promote based on severity)
