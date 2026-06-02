---
title: "Tasks — fix(pencil): open_document wipe snapshot + commit guards"
issue: 3274
lane: procedural
plan: knowledge-base/project/plans/2026-06-03-fix-pencil-open-document-wipe-snapshot-and-commit-guards-plan.md
---

# Tasks — pencil open_document wipe guards (#3274)

## Phase 1 — ux-design-lead snapshot + collapse gate (mitigation 2)

- [ ] 1.1 Edit `plugins/soleur/agents/product/design/ux-design-lead.md` Step 2 item 3 (`open_document`): add pre-open snapshot (`stat -c %s` + `sha256sum`) for existing files. (AC1)
- [ ] 1.2 Add post-open collapse HARD GATE: halt + surface pre/post sizes verbatim if post-open size < 50% of pre-open OR ≤ 64 bytes; treat as parse-failure wipe. (AC2, AC3)
- [ ] 1.3 Add new-file exemption (collapse gate applies only to pre-existing non-empty `.pen`). (AC4)
- [ ] 1.4 Fold in dangling-citation fix at line 57: repoint `AGENTS.md:cq-pencil-mcp-silent-drop-diagnosis-checklist` to pencil-setup SKILL Sharp Edge + learning file; keep the `>0 bytes` assertion. (AC7)
- [ ] 1.5 Add Important-Guidelines note: un-committed `.pen` under an app tree is doubly at risk (gitignored + wipeable); save+commit under `knowledge-base/product/design/`.

## Phase 2 — brand-workshop commit-after-first-save (mitigation 3)

- [ ] 2.1 Edit `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` step 4.5.a: commit the `.pen` to the worktree branch immediately after first save, before the iteration loop. (AC5)
- [ ] 2.2 Reinforce committed `.pen` MUST be under `knowledge-base/product/design/` (never an app tree). (AC6)
- [ ] 2.3 Leave step 5 (brand-guide.md commit) unchanged; new commit is additive + earlier.

## Phase 3 — regression guards

- [ ] 3.1 Create `plugins/soleur/test/ux-design-lead-open-document-snapshot-guard.test.sh` (model: `ux-design-lead-output-path-guard.test.sh`): assert snapshot, collapse gate, new-file exemption, retired-citation absent, canonical path present. `chmod +x`. (AC8, AC10)
- [ ] 3.2 Create `plugins/soleur/test/brand-workshop-pen-commit-after-save.test.sh`: assert commit-after-save instruction + canonical-path reinforcement. `chmod +x`. (AC9)

## Phase 4 — verify

- [ ] 4.1 Run both new `.test.sh` (exit 0).
- [ ] 4.2 Run existing `ux-design-lead-output-path-guard.test.sh` (no regression).
- [ ] 4.3 Run `bash scripts/test-all.sh` (full suite green; new tests auto-discovered). (AC11)

## Phase 5 — ship

- [ ] 5.1 PR body uses `Closes #3274`. (AC12)
- [ ] 5.2 File deferred-tracking issue for upstream Pencil adapter empty-state refusal (mitigation 1), labeled `blocked`, referencing #3274.
