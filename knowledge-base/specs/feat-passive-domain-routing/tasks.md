# Tasks: Passive Domain Leader Routing

## Phase 1: AGENTS.md Rule

### 1.1 Add Passive Domain Routing section
- [ ] Read `AGENTS.md`
- [ ] Add `## Passive Domain Routing` section between Workflow Gates and Communication
- [ ] Write 2 bullets: (1) behavioral rule with qualifying language, (2) background spawn mechanism with config file reference
- [ ] Modify line 22: scope "Zero agents until user confirms direction" to exclude passive domain routing

## Phase 2: Brainstorm Auto-Fire

### 2.1 Rewrite Phase 0.5 Processing Instructions
- [ ] Read `plugins/soleur/skills/brainstorm/SKILL.md` lines 60-85
- [ ] Replace AskUserQuestion with direct Task spawn for relevant domains
- [ ] Add explicit workshop conditional: "If the user explicitly requests a workshop, follow the named section. Otherwise, use assessment Task Prompt."
- [ ] Change parallel handling: spawn relevant domains in parallel
- [ ] Simplify fallback: "If no domains are relevant, continue to Phase 1"

### 2.2 Update domain config file header
- [ ] Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
- [ ] Replace header instruction: remove "use AskUserQuestion tool", describe auto-fire pattern
- [ ] Add note: Routing Prompt and Options columns retained for workshop reference

## Phase 3: Plugin Documentation

### 3.1 Update plugin AGENTS.md
- [ ] Read `plugins/soleur/AGENTS.md`
- [ ] Update Domain Leaders table: entry points now include passive routing
- [ ] Update "Adding a New Domain Leader" checklist: note passive routing coverage
