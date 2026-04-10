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
- [ ] Insert compound invocation before the "Context headroom notice" in Phase 4
- [ ] Update the existing context headroom notice to explicitly recommend `/clear`
- [ ] Add safety-net commit+push after compound for any post-Phase-3.6 artifacts
- [ ] Verify the AskUserQuestion options still appear after exit gate

### 2.2 Add exit gate to review/SKILL.md

- [ ] Read `plugins/soleur/skills/review/SKILL.md`
- [ ] Add pipeline detection (check for one-shot or work Phase 4 invocation context)
- [ ] Add exit gate sequence after Step 5 Summary Report (direct invocation only)
- [ ] Exit gate: compound + commit + `/clear` recommendation
- [ ] Add note that pipeline callers handle compound themselves

### 2.3 Add exit gate to plan/SKILL.md

- [ ] Read `plugins/soleur/skills/plan/SKILL.md`
- [ ] Add pipeline detection (one-shot subagent context with return contract)
- [ ] Insert exit gate before Post-Generation Options AskUserQuestion (direct invocation only)
- [ ] Exit gate: compound + commit verification + `/clear` recommendation
- [ ] Update Post-Generation Options preamble to include `/clear` note

### 2.4 Add exit gate to work/SKILL.md

- [ ] Read `plugins/soleur/skills/work/SKILL.md`
- [ ] Add `/clear` advisory in Phase 4 direct-invocation path after compound (step 3)
- [ ] Keep automatic review -> compound -> ship chain intact (no blocking prompt)
- [ ] Add advisory note: "After shipping, run `/clear` to reclaim context for next task"
- [ ] Verify one-shot path unchanged (## Work Phase Complete marker)

## Phase 3: Convention Update

### 3.1 Add exit gate convention to constitution.md

- [ ] Read `knowledge-base/project/constitution.md`
- [ ] Add exit gate convention to Architecture > Always section
- [ ] Convention text: "Workflow skills must run compound + commit + push before presenting handoff options. Skip in pipeline mode. Display `/clear` recommendation."

## Phase 4: Testing and Validation

### 4.1 Verify no pipeline regression

- [ ] Read one-shot SKILL.md and trace the plan subagent path -- confirm exit gate does not fire
- [ ] Read work SKILL.md Phase 4 one-shot path -- confirm `## Work Phase Complete` marker unaffected
- [ ] Read work SKILL.md Phase 4 direct path -- confirm review -> compound -> ship chain intact
- [ ] Verify review pipeline detection skips exit gate when called by work

### 4.2 Run markdownlint on all modified files

- [ ] Run `npx markdownlint-cli2 --fix` on all 5 modified files
- [ ] Verify no lint errors remain
