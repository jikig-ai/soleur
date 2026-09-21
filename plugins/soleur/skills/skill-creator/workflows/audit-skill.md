# Workflow: Audit a Skill

<required_reading>
**Read these reference files NOW:**

1. references/recommended-structure.md
2. references/skill-structure.md
3. references/authoring-levers.md
</required_reading>

<process>
## Step 1: List Available Skills

**DO NOT use AskUserQuestion** - there may be many skills.

Enumerate skills in chat as numbered list:

```bash
ls ~/.claude/skills/
```

Present as:

```
Available skills:
1. create-agent-skills
2. build-macos-apps
3. manage-stripe
...
```

Ask: "Which skill would you like to audit? (enter number or name)"

## Step 2: Read the Skill

After user selects, read the full skill structure:

```bash
# Read main file
cat ~/.claude/skills/{skill-name}/SKILL.md

# Check for workflows and references
ls ~/.claude/skills/{skill-name}/
ls ~/.claude/skills/{skill-name}/workflows/ 2>/dev/null
ls ~/.claude/skills/{skill-name}/references/ 2>/dev/null
```

## Step 3: Run Audit Checklist

Evaluate against each criterion:

### YAML Frontmatter

- [ ] Has `name:` field (lowercase-with-hyphens)
- [ ] Name matches directory name
- [ ] Has `description:` field
- [ ] Description says what it does AND when to use it
- [ ] Description is third person ("Use when...")

### Structure

- [ ] SKILL.md under 500 lines
- [ ] Body structured with markdown headings: markdown headings structure a skill body; XML tags are optional semantic wrappers inside a section and never replace headings
- [ ] Any XML wrappers are closed and sit inside a section
- [ ] Has a `#` title with purpose (or an essential-principles section for a router)
- [ ] Has a completion criterion (`## Success criteria` or per-phase exit conditions)

### Invocation

Apply the decision test in `references/authoring-levers.md` (could the model usefully reach for this on its own, or must another skill reach it?). Either of these is a finding:

- [ ] A human-only skill (fails the test, and meets ADR-236's K1-K3) lacks `disable-model-invocation: true` in its frontmatter
- [ ] A skill that sets `disable-model-invocation: true` is named by another file (a skill, agent, rule, or workflow) as something the model should invoke. Search for its name across `plugins/soleur/` and `AGENTS.rules.md`, then read each hit.

### Router Pattern (if complex skill)

- [ ] Essential principles inline in SKILL.md (not in separate file)
- [ ] Has intake question
- [ ] Has routing table
- [ ] All referenced workflow files exist
- [ ] All referenced reference files exist

### Workflows (if present)

- [ ] Each has required_reading section
- [ ] Each has process section
- [ ] Each has success_criteria section
- [ ] Required reading references exist

### Content Quality

- [ ] Principles are actionable (not vague platitudes)
- [ ] Steps are specific (not "do the thing")
- [ ] Success criteria are verifiable
- [ ] No redundant content across files

## Step 4: Generate Report

Present findings as:

```
## Audit Report: {skill-name}

### ✅ Passing
- [list passing items]

### ⚠️ Issues Found
1. **[Issue name]**: [Description]
   → Fix: [Specific action]

2. **[Issue name]**: [Description]
   → Fix: [Specific action]

### 📊 Score: X/Y criteria passing
```

## Step 5: Offer Fixes

If issues found, ask:
"Would you like me to fix these issues?"

Options:

1. **Fix all** - Apply all recommended fixes
2. **Fix one by one** - Review each fix before applying
3. **Just the report** - No changes needed

If fixing:

- Make each change
- Verify file validity after each change
- Report what was fixed
</process>

<audit_anti_patterns>

## Common Anti-Patterns to Flag

**Skippable principles**: Essential principles in separate file instead of inline
**Monolithic skill**: Single file over 500 lines
**Mixed concerns**: Procedures and knowledge in same file
**Vague steps**: "Handle the error appropriately"
**Untestable criteria**: "User is satisfied"
**Tag-only body**: Top-level XML tags standing in for sections, with no markdown headings
**Invocation mismatch**: Human-only skill left model-invocable, or a user-invoked skill that another file tells the model to invoke
**Missing routing**: Complex skill without intake/routing
**Broken references**: Files mentioned but don't exist
**Redundant content**: Same information in multiple places
</audit_anti_patterns>

<success_criteria>
Audit is complete when:

- [ ] Skill fully read and analyzed
- [ ] All checklist items evaluated
- [ ] Report presented to user
- [ ] Fixes applied (if requested)
- [ ] User has clear picture of skill health
</success_criteria>
