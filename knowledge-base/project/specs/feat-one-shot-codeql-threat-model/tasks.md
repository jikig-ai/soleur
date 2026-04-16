---
title: "Switch CodeQL threat model to remote only"
status: pending
date: 2026-04-16
---

# Tasks: Switch CodeQL threat model to remote only

## Phase 1: Switch threat model and verify

- [ ] 1.1 Run PATCH API call to set `threat_model=remote` (include `languages` to prevent reset)
- [ ] 1.2 Verify via GET that `threat_model` is `remote` and `languages` are preserved
- [ ] 1.3 Poll analyses endpoint for re-analysis completion after config change
- [ ] 1.4 Verify zero open alerts after re-analysis

## Phase 2: Update documentation

- [ ] 2.1 Add `[Updated 2026-04-16]` note to `knowledge-base/project/specs/feat-enable-github-security-quality/tasks.md` recording threat model switch
- [ ] 2.2 Add `[Updated 2026-04-16]` note to `knowledge-base/project/specs/feat-enable-github-security-quality/session-state.md`
