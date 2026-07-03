# Soleur Claude Code Plugin Development

## Versioning Requirements

**Version is derived from git tags.** The `version-bump-and-release.yml` GitHub Action creates GitHub Releases with `vX.Y.Z` tags via `gh release create` — it never pushes commits to main.

### How It Works

1. PR author adds a `## Changelog` section to the PR body (template provided)
2. `/ship` skill analyzes the diff and sets a `semver:patch`, `semver:minor`, or `semver:major` label
3. On merge to main, the Action reads the label, computes the next version from the latest release tag, creates a GitHub Release, and posts to Slack

### Semver Label Rules

- **MAJOR** (1.0.0 → 2.0.0): Breaking changes, major reorganization
- **MINOR** (1.0.0 → 1.1.0): New agents, commands, or skills
- **PATCH** (1.0.0 → 1.0.1): Bug fixes, doc updates, minor improvements

### Pre-Commit Checklist

Before committing ANY changes:

- [ ] README.md component counts verified (tables accurate)
- [ ] Do NOT edit: `plugin.json` version field (frozen sentinel `0.0.0-dev`), `marketplace.json` version — these are intentionally static
- [ ] PR body includes a `## Changelog` section describing changes

### Directory Structure

Components are organized by domain, then by function.

```text
agents/
├── engineering/
│   ├── design/            # Architecture agents
│   ├── infra/             # Infrastructure agents
│   ├── research/          # Engineering research agents
│   ├── review/            # Code review agents
│   └── workflow/          # Engineering workflow agents
├── finance/               # Financial planning and reporting agents
├── legal/                 # Legal document and compliance agents
├── marketing/             # Brand and marketing agents
├── operations/            # Ops and expense agents
├── product/               # Product analysis and design agents
│   └── design/            # UX design agents
├── sales/                 # Sales pipeline and revenue agents
└── support/               # Support and community agents

commands/                      # Entry-point commands (go, sync, help)

skills/
└── <skill-name>/          # All skills at root level (flat)
```

**Note:** Files at the repo root matching `AGENTS.*.md` (e.g.
`AGENTS.core.md`, `AGENTS.docs.md`, `AGENTS.rest.md`) are the change-class
sidecars introduced by #3493. They are *not* plugin components — the plugin
loader scans `plugins/soleur/{commands,skills,agents}/` only. Edits to the
sidecars route through the `cq-agents-md-tier-gate` placement gate and the
`session-rules-loader.sh` SessionStart hook.

**Workflow scripts (`skills/<name>/workflows/<name>.workflow.js`).** A skill
whose shape is deterministic multi-agent orchestration (parallel fan-out /
loop-until-dry / fan-out-then-verify) MAY ship a dynamic-workflow ([`Workflow`
tool](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code))
port alongside its `SKILL.md`, in a `workflows/` subdirectory. These are **not**
plugin components — the skill loader does not recurse into subdirectories, so
they are not counted in README component tables. Each script is **self-contained**
(the Workflow runtime has no filesystem/import access, so shared helpers like
`safeTitle`/`safeId` are duplicated per script by design — keep the metacharacter
sets identical across copies). The parent `SKILL.md` links its workflow via an
opt-in pointer; the prose skill stays the default. Decision record + the full
migrate-vs-keep inventory: `knowledge-base/project/specs/feat-review-workflow-prototype/spec.md`.

### Adding a New Domain

To add a new domain (e.g., product, growth):

1. Create `agents/<domain>/` for domain-specific agents
2. Add `DOMAIN_META` entry in `docs/_data/agents.js` (label, icon, card description)
3. Add key to `domainOrder` and `DOMAIN_CSS_VARS` in the same file
4. Add CSS variable in `docs/css/style.css`
5. Skills stay flat at root level (the skill loader does not recurse into subdirectories)
6. Commands stay flat under `commands/` (only entry-point commands: go, sync, help). Workflow stages are skills.
7. The plugin loader discovers agents recursively -- no config changes needed
8. Landing page department cards, stats, and legal doc counts update automatically from data
9. If the domain gets a top-level `knowledge-base/<domain>/` directory, add `<domain>` to `SANCTIONED_DIRS` in `.claude/hooks/kb-domain-allowlist-guard.sh` (the advisory guard that flags new top-level KB dirs outside the sanctioned set)

## Command and Skill Naming Convention

Only 3 **commands** remain under `commands/`, using the `soleur:` prefix to avoid collisions with built-in commands:

- `/soleur:go` - Unified entry point that routes to workflow skills
- `/soleur:sync` - Populate knowledge base from existing codebase
- `/soleur:help` - List all available Soleur commands, agents, and skills

The 6 workflow stages are now **skills** under `skills/`:

- `soleur:brainstorm` - Explore requirements, make design decisions
- `soleur:plan` - Create implementation plans with research
- `soleur:work` - Execute plans with incremental commits
- `soleur:review` - Multi-agent code review before PR
- `soleur:compound` - Capture learnings for future work
- `soleur:one-shot` - Full autonomous engineering workflow from plan to PR

**Why skills?** Skills are discoverable by agents and invocable via the Skill tool. Commands are invisible to agents. Workflow stages benefit from agent discoverability and Skill tool invocation (e.g., `/soleur:go` routes to skills, one-shot sequences plan then work via the Skill tool).

**Prefix source:** Both commands and skills get their `soleur:` prefix automatically from the plugin namespace. The `name:` field in frontmatter should NOT include the `soleur:` prefix. Commands live flat in `commands/` (not in a subdirectory) to avoid double-namespacing.

### Primitive Choice: /goal vs. Soleur Skills

Claude Code's `/goal` primitive (v2.1.139+) is a session-scoped completion-condition Stop hook with a Haiku evaluator that reads only the conversation transcript. It is the right tool for **ad-hoc autonomous work outside dedicated Soleur skills** — operator-typed conditions, headless CI, one-off loops not worth building a skill for.

Do NOT propose `/goal` retrofits into existing autonomous Soleur skills (`one-shot`, `test-fix-loop`, `drain-labeled-backlog`, `resolve-todo-parallel`, `resolve-pr-parallel`, `work`). Each already uses a stricter, structurally-verifiable completion mechanism (exit codes, the `<promise>DONE</promise>` marker via `plugins/soleur/hooks/stop-hook.sh`, CLI-output checks). A transcript-only evaluator on top of those would duplicate at higher cost and reintroduce the pseudo-handoff failure class codified by hard rule `hr-when-a-workflow-concludes-with-an`. Operator-facing docs: `/goal-primitive/`.

## Agent Compliance Checklist

When adding or modifying agents, verify compliance:

### YAML Frontmatter (Required)

- [ ] `name:` present and matches filename (lowercase-with-hyphens)
- [ ] `description:` is 1-3 sentences of routing text only -- when to use this agent
- [ ] `description:` contains NO `<example>` blocks, NO `<commentary>` tags (these bloat the system prompt on every turn)
- [ ] `description:` includes a disambiguation sentence if another agent has overlapping scope ("Use [sibling] for [X]; use this agent for [Y].")
- [ ] `model: inherit` (see Model Selection Policy; explicit overrides require justification)

### Token Budget Check (Required when adding agents)

- [ ] Run: `grep -h 'description:' agents/**/*.md | wc -w` -- cumulative word count must stay under ~2500 words (~3.3k tokens, well under the 15k threshold)
- [ ] Reserve ~5 words per sibling needing disambiguation when budgeting the new agent's description -- large domains (marketing: 11 specialists) consume budget faster
- [ ] Detailed instructions, frameworks, and examples belong in the agent body (after `---`), not in `description:`

### Quick Validation Command

```bash
# Check for example blocks in agent descriptions (should return nothing)
grep -l '<example>' agents/**/*.md | xargs grep -l 'description:.*<example>'

# Check cumulative description size
grep -h 'description:' agents/**/*.md | wc -w
# Target: under 2500 words total across all agents
```

## Model Selection Policy

Model selection is governed by three tiers (ADR-053; revised 2026-06-10 for the Fable 5 pricing era — Fable 5 is 2× Opus, 3.3× Sonnet, 10× Haiku per MTok):

1. **Agent frontmatter:** All agents use `model: inherit` in their YAML frontmatter, so agents run on whatever model the user's session is using, respecting their cost/quality preference. Explicit overrides (`haiku`, `sonnet`, `opus`, `fable`) require written justification in the agent body text explaining why the task is fundamentally mismatched with the session model. Current exceptions: the five `engineering/research/*` agents (`repo-research-analyst`, `learnings-researcher`, `best-practices-researcher`, `framework-docs-researcher`, `git-history-analyzer`) are pinned to `model: haiku` (#5087). These are pure read-and-summarize researchers that Soleur's planning/research skills (`/plan`, `/brainstorm`, `/deepen-plan`) spawn via **direct or unpinned `Task` calls** — a cost surface ADR-053's workflow call-site pins (tier 2) structurally do not reach (`deepen-plan`'s workflow deliberately leaves its research fan-out on `inherit`). The `haiku` floor is the safe tier: an absolute floor pin can never *upgrade* a cheaper session, so unlike the `sonnet` frontmatter tiering ADR-053 rejected, it introduces no silent cheap-session upgrade. Reviewers/verifiers are deliberately NOT frontmatter-pinned — they stay `inherit` so a stronger session model still flows through (see tier 3).
2. **Workflow call-site pins:** `skills/*/workflows/*.workflow.js` scripts MAY pin `opts.model` (`'sonnet'` or `'haiku'`) at **mechanical** steps — extract, classify, fetch, commit-message, issue-file, report. Each pin requires a one-line justification comment at the call site. Judgment steps (review, verify/concur adjudication, synthesis, resolution, implementation, principle scoring) MUST NOT be pinned. Pins are **absolute**, never "one tier below session" — only pin where a fixed cheap tier is always correct. Named consequence: an absolute pin can run ABOVE a cheaper session model (a Haiku session still runs a `sonnet`-pinned step on Sonnet); the per-run tier `log()` line is the disclosure. The pin set is enforced mechanically by `plugins/soleur/test/workflow-model-pins.test.ts` — changing the allowlist is a clo-attestation-class change.
3. **Never-downgrade exemption list:** all `engineering/review/*` agents, `data-migration-expert`, security/SAST agents, legal/compliance surfaces (`clo`, `gdpr-gate`, `data-integrity-guardian`), C-suite strategy agents, enumeration-scoring audits (`agent-native-audit` — the platform's own sonnet→opus upgrade precedent for the identical scoring workload, `cron-agent-native-audit.ts`), and any step that gates a merge or touches user data.
4. **SKILL.md prose advisories (ungated fourth surface):** SKILL.md prose MAY advise spawning a Task/Agent with a cheap tier for mechanical sweeps (e.g., deepen-plan's verify-the-negative passes). Each advisory must cite ADR-053 and is discoverable via `grep -rn 'model: sonnet\|model: haiku\|model: fable' plugins/soleur/skills/*/SKILL.md` (the `fable` alternate catches the ADR-083 upgrade variant below) — prose advisories are advisory-only and carry no mechanical gate, so keep them to mechanical-step classes only, with one sanctioned exception: the scoped `fable` upgrade consult at the two named judgment gates (see the Scoped advisor consult bullet below, ADR-083).

- **Effort control:** Reasoning effort is a session-level setting (`effortLevel` in `.claude/settings.json` or the `/model` slider), not configurable per-agent. The Claude Code plugin spec does not support per-agent effort levels.
- **Scoped advisor consult (tier-4 upgrade variant):** for a strong-model second opinion at a decision gate, do NOT use Claude Code's built-in [advisor tool](https://code.claude.com/docs/en/advisor) (`advisorModel`) — it re-sends the full transcript uncached every call and is inherited by every fan-out subagent, the opposite of token-frugal. Instead spawn a scoped `Task(model: fable)` (fall back to `opus`) with a **curated payload** (plan sections / diff+findings+ACs), never the conversation — a Task subagent gets prompt text only, so curation is the cost lever. This is wired at exactly two gates: `plan` Step 4.5 (plan-finalization) and `ship` Phase 5.5 (completion); `one-shot` inherits both transitively. It is an *upgrade* pin for a *judgment* step (vs tier-4's cheap-mechanical downgrades), so the discovery grep is extended to include `fable`: `grep -rn 'model: sonnet\|model: haiku\|model: fable' plugins/soleur/skills/*/SKILL.md`. Decision + cost/tradeoff semantics: [ADR-083](../../knowledge-base/engineering/architecture/decisions/ADR-083-scoped-strong-model-consult-at-decision-gates.md).

## Skill Compliance Checklist

When adding or modifying skills, verify compliance with skill-creator spec:

### YAML Frontmatter (Required)

- [ ] `name:` present and matches directory name (lowercase-with-hyphens)
- [ ] `description:` present and uses **third person** ("This skill should be used when..." NOT "Use this skill when...")

### Token Budget Check (Required when adding skills)

- [ ] Run: `bun test plugins/soleur/test/components.test.ts` -- cumulative description word count must stay under 1,800 words (see #618)
- [ ] Descriptions are for **routing**, not instruction. Remove trigger phrases (`Triggers on "..."`) and verbose restatements. Target ~30 words per skill.
- [ ] No single description exceeds 1,024 characters

### Reference Links (Required if references/ exists)

- [ ] All files in `references/` are linked as `[filename.md](./references/filename.md)`
- [ ] All files in `assets/` are linked as `[filename](./assets/filename)`
- [ ] All files in `scripts/` are linked as `[filename](./scripts/filename)`
- [ ] No bare backtick references like `` `references/file.md` `` - use proper markdown links

### Writing Style

- [ ] Use imperative/infinitive form (verb-first instructions)
- [ ] Avoid second person ("you should") - use objective language ("To accomplish X, do Y")

### Quick Validation Command

```bash
# Check for unlinked references in a skill
grep -E '`(references|assets|scripts)/[^`]+`' skills/*/SKILL.md
# Should return nothing if all refs are properly linked

# Check description format
grep -E '^description:' skills/*/SKILL.md | grep -v 'This skill'
# Should return nothing if all use third person
```

## Domain Leader Interface

Domain leaders are agents that orchestrate a business domain's specialist team. Each leader follows a 3-phase contract:

| Phase | Responsibility | Description |
|-------|---------------|-------------|
| **Assess** | Evaluate current domain state | Check existing artifacts, inventory gaps, report status |
| **Recommend and Delegate** | Propose actions and spawn specialist agents | Prioritize initiatives, parallel dispatch for independent analyses |
| **Sharp Edges** | Document boundaries and constraints | Cross-domain boundaries, quality checks, what NOT to do |

### Current Domain Leaders

| Leader | Domain | Agents Orchestrated | Entry Point |
|--------|--------|-------------------|-------------|
| `cto` | Engineering | Research, review, design agents | Auto-consulted via passive domain routing and brainstorm domain detection |
| `clo` | Legal | legal-document-generator, legal-compliance-auditor | Auto-consulted via passive domain routing and brainstorm domain detection |
| `cmo` | Marketing | 11 specialists | Auto-consulted via passive domain routing and brainstorm domain detection |
| `coo` | Operations | ops-advisor, ops-research, ops-provisioner | Auto-consulted via passive domain routing and brainstorm domain detection |
| `cpo` | Product | spec-flow-analyzer, ux-design-lead, business-validator, competitive-intelligence | Auto-consulted via passive domain routing and brainstorm domain detection |
| `cfo` | Finance | budget-analyst, revenue-analyst, financial-reporter | Auto-consulted via passive domain routing and brainstorm domain detection |
| `cro` | Sales | outbound-strategist, deal-architect, pipeline-analyst | Auto-consulted via passive domain routing and brainstorm domain detection |
| `cco` | Support | ticket-triage, community-manager | Auto-consulted via passive domain routing and brainstorm domain detection |

### Adding a New Domain Leader

1. Create `agents/<domain>/` with leader + specialist `.md` files
2. Follow the 3-phase contract (Assess, Recommend/Delegate, Sharp Edges) -- use `agents/legal/clo.md` as template
3. Add a row to the Domain Config table in `skills/brainstorm/references/brainstorm-domain-config.md` with: domain name, assessment question, leader name, routing prompt, options, and task prompt. New domains are automatically routable via both passive domain routing (AGENTS.md) and brainstorm Phase 0.5
4. Add disambiguation sentences to agents with overlapping scope in adjacent domains (both directions)
5. Verify token budget: `shopt -s globstar && grep -h 'description:' agents/**/*.md | wc -w` (under 2,500)
6. Update docs data files: `agents.js` (DOMAIN_META, DOMAIN_CSS_VARS, domainOrder), `style.css` (CSS variable). Landing page and legal docs update automatically from data.
7. Update AGENTS.md (directory tree, domain leader table) and README.md (agent section, counts)
8. PR must have `semver:minor` label and `## Changelog` section (CI handles version bump at merge time)

## Documentation

Version is derived from git tags via GitHub Releases. See the `version-bump-and-release.yml` workflow for details.
