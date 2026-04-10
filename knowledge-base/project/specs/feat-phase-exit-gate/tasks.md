# Tasks: Standardized Phase Exit Gate

## Phase 1: Setup and Audit

### 1.1 Verify entry robustness across all 4 workflow skills

- [ ] Audit brainstorm entry (Phase 0): confirm CLAUDE.md loaded, no prior artifacts needed
- [ ] Audit plan entry (Phase 0): confirm CLAUDE.md, constitution, spec, brainstorm loaded from disk
- [ ] Audit work entry (Phase 0): confirm CLAUDE.md, constitution, tasks loaded from disk
- [ ] Audit review entry (Phase 0): confirm CLAUDE.md loaded, PR metadata fetched via gh
- [ ] Document audit findings (all entries already robust -- no code changes needed)

## Phase 2: Core Implementation

### 2.1 Add exit gate to brainstorm/SKILL.md

- [ ] Read `plugins/soleur/skills/brainstorm/SKILL.md`
- [ ] Insert compound invocation BEFORE the "Context headroom notice" at line 303 of Phase 4
- [ ] Compound runs FIRST (per constitution line 96: compound before commit)
- [ ] Add scoped commit+push after compound: `git add knowledge-base/project/brainstorms/ knowledge-base/project/specs/feat-<name>/` (NOT `git add -A knowledge-base/`)
- [ ] Replace existing context headroom notice text with: "All artifacts are on disk. Run `/clear` then `/soleur:plan` for maximum context headroom."
- [ ] No pipeline detection needed (brainstorm is never invoked by one-shot)
- [ ] Verify the AskUserQuestion options still appear after exit gate

### 2.2 Add exit gate to review/SKILL.md (HIGHEST RISK -- review has zero pipeline detection)

- [ ] Read `plugins/soleur/skills/review/SKILL.md`
- [ ] Add pipeline detection after Step 5 Summary Report: check conversation for prior `skill: soleur:work` or `soleur:one-shot` output
- [ ] Pipeline mode: skip exit gate, let calling pipeline handle compound/commit
- [ ] Direct invocation mode: add exit gate sequence (compound + commit + `/clear`)
- [ ] Use advisory language only -- no "announce", "stop", "return" (per constitution line 98)
- [ ] Handle edge case: review may produce no local files (GitHub issues are remote-only); `git status --short` may be empty
- [ ] Add note that pipeline callers handle compound themselves

### 2.3 Add exit gate to plan/SKILL.md

- [ ] Read `plugins/soleur/skills/plan/SKILL.md`
- [ ] Add pipeline detection: check for `RETURN CONTRACT` text in conversation (one-shot subagent)
- [ ] Insert exit gate between "Plan Review" section and "Post-Generation Options" section (~line 435)
- [ ] Exit gate: compound FIRST, then commit verification via `git status --short`, then `/clear` recommendation
- [ ] Scope git add to: `knowledge-base/project/plans/` and `knowledge-base/project/specs/feat-<name>/`
- [ ] Update Post-Generation Options preamble to reinforce `/clear` recommendation
- [ ] Verify the Save Tasks section's existing commit+push is not duplicated

### 2.4 Add exit gate to work/SKILL.md (MINIMAL CHANGE)

- [ ] Read `plugins/soleur/skills/work/SKILL.md`
- [ ] Add single advisory line between compound (step 3) and ship (step 4) at line ~433
- [ ] Text: "Tip: After shipping, run `/clear` to reclaim context headroom for the next task."
- [ ] Do NOT make this a blocking prompt or AskUserQuestion
- [ ] Verify the advisory does not use stop/return/done language
- [ ] Verify one-shot path unchanged (`## Work Phase Complete` marker at line 425)

## Phase 3: Convention Update

### 3.1 Add exit gate convention to constitution.md

- [ ] Read `knowledge-base/project/constitution.md`
- [ ] Insert new rule in Architecture > Always section after line 98 (companion to the pipeline handoff rule)
- [ ] Convention text: "Workflow skills (brainstorm, plan, work, review) must run compound + commit + push before presenting handoff options to the user -- skip the exit gate when invoked by a pipeline orchestrator (one-shot, ship); display a `/clear` recommendation at handoff to encourage context headroom recovery between phases"

## Phase 4: Testing and Validation

### 4.1 Verify no pipeline regression

- [ ] Read one-shot SKILL.md and trace the plan subagent path -- confirm exit gate does not fire when `RETURN CONTRACT` is in context
- [ ] Read work SKILL.md Phase 4 one-shot path (line 425) -- confirm `## Work Phase Complete` marker unaffected
- [ ] Read work SKILL.md Phase 4 direct path (line 427) -- confirm review -> compound -> ship chain intact with advisory inserted
- [ ] Verify review pipeline detection correctly identifies work Phase 4 invocation and skips exit gate

### 4.2 Run markdownlint on all modified files

- [ ] Run `npx markdownlint-cli2 --fix` on all 5 modified files
- [ ] Verify no lint errors remain
