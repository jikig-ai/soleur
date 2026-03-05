---
title: "fix: close remaining schedule skill template gaps"
type: fix
date: 2026-03-05
semver: patch
issue: "#382"
deepened: 2026-03-05
---

# fix: close remaining schedule skill template gaps

## Enhancement Summary

**Deepened on:** 2026-03-05
**Research sources:** Context7 claude-code-action docs, 5 institutional learnings, 3 reference workflows, constitution audit
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios)

### Key Improvements

1. Discovered that `claude_args` should use YAML block scalar (`>-`) for multi-flag readability, matching `scheduled-bug-fixer.yml` pattern
2. Identified `contents: write` permission gap -- template hardcodes `contents: read` but some skills need write access for git push
3. Added edge case: `--max-turns` and `timeout-minutes` relationship -- timeout should always exceed expected turn execution time
4. Found that `claude-code-action` official docs confirm `--max-turns` is a first-class CLI argument (Context7 verified)

### Institutional Learnings Applied

- `2026-02-27-schedule-skill-template-gaps-first-consumer.md` -- original gap catalog, 3 of 6 items still open
- `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md` -- workflows needing `git push` must use `contents: write`; the template should not hardcode `contents: read`
- `2026-03-03-scheduled-bot-fix-workflow-patterns.md` -- cascading priority and label pre-creation patterns (confirms Change 3)
- `2026-02-21-github-actions-workflow-security-patterns.md` -- confirms SHA pinning and exit code checking patterns already in template

---

## Overview

The `soleur:schedule` skill generates GitHub Actions workflow YAML for cron-based agent runs. Issue #382 identified 6 template gaps discovered during the #370 daily triage brainstorm. Investigation reveals that 4 of the 6 gaps have already been fixed in prior PRs (#341, #344). Three remaining gaps persist, and the Known Limitations section is stale.

## Problem Statement

The schedule skill template (`plugins/soleur/skills/schedule/SKILL.md`) produces workflows that require manual post-generation edits. The learning document `2026-02-27-schedule-skill-template-gaps-first-consumer.md` cataloged 6 gaps. Two are structural (always needed regardless of skill) and still absent from the generated YAML:

1. **No `timeout-minutes`** -- LLM-backed workflows can run for the 6-hour GitHub default if the agent gets stuck. All three reference workflows set explicit timeouts (20-60 min). Constitution line 102 mandates this.
2. **No `--max-turns`** -- Without a turn cap, agents can exhaust token budgets. All three reference workflows include `--max-turns`.
3. **No label pre-creation step** -- The prompt instructs the agent to create issues with a `scheduled-<name>` label, but `gh issue create --label foo` fails if the label does not exist. Constitution line 101 mandates `gh label create ... || true` pre-steps.

Additionally, the Known Limitations section (lines 166-176) lists items that are now resolved, creating confusion for users.

## Current State vs Issue Description

| # | Issue's Gap Description | Template State | Fixed In |
|---|------------------------|---------------|----------|
| 1 | Missing `plugin_marketplaces` | Present since v3.5.0 | #321 |
| 2 | Missing `plugins` | Present since v3.5.0 | #321 |
| 3 | Missing `claude_args` | `--model` + `--allowedTools` present; `--max-turns` missing | #344 (partial) |
| 4 | Missing `id-token: write` | Present | #341 |
| 5 | Hardcoded action versions | SHA resolution in Step 2 since v3.5.0 | #321 |
| 6 | No concurrency group | Present since v3.5.0 | #321 |

## Proposed Solution

Update `plugins/soleur/skills/schedule/SKILL.md` with four changes to the template and one cleanup pass.

### Change 1: Add `timeout-minutes` to template YAML

Add `timeout-minutes: <TIMEOUT>` to the job block. Collect timeout as a new input in Step 1 with a sensible default (30 minutes).

**Before (SKILL.md line ~86):**

```yaml
jobs:
  run-schedule:
    runs-on: ubuntu-latest
    steps:
```

**After:**

```yaml
jobs:
  run-schedule:
    runs-on: ubuntu-latest
    timeout-minutes: <TIMEOUT>
    steps:
```

#### Research Insights

**Best Practices (from reference workflows):**

- `scheduled-daily-triage.yml` uses `timeout-minutes: 60` (200 issues, 80 turns)
- `scheduled-bug-fixer.yml` uses `timeout-minutes: 20` (1 issue, 25 turns)
- `scheduled-competitive-analysis.yml` uses `timeout-minutes: 45` (web research, 45 turns)
- The relationship between `--max-turns` and `timeout-minutes` matters: each turn can take 10-30 seconds depending on tool calls. A workflow with 30 max-turns needs at minimum 15 minutes; 30 minutes provides a 2x safety margin.

**Default selection rationale:** 30 minutes balances cost protection against premature termination. This matches the pattern from the constitution (line 102: "set `timeout-minutes` to prevent runaway billing"). Users can override for long-running skills.

### Change 2: Add `--max-turns` to `claude_args`

Collect max-turns as a new input in Step 1 with a sensible default (30 turns).

**Before (SKILL.md line ~98):**

```yaml
claude_args: '--model <MODEL> --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch'
```

**After:**

```yaml
claude_args: >-
  --model <MODEL>
  --max-turns <MAX_TURNS>
  --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch
```

#### Research Insights

**Context7 documentation confirms:** `--max-turns` is a first-class CLI argument for `claude-code-action`. The official migration guide shows the pattern:

```yaml
claude_args: |
  --max-turns 15
  --model claude-4-0-sonnet-20250805
  --allowedTools Edit,Read,Write,Bash
```

**YAML block scalar format:** The `scheduled-bug-fixer.yml` uses `>-` (folded strip) for `claude_args`, which is more readable for multi-flag values than a single-line string. Adopt this format:

```yaml
claude_args: >-
  --model <MODEL>
  --max-turns <MAX_TURNS>
  --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch
```

The `>-` folded scalar joins lines with spaces and strips the trailing newline, producing the same single-line string but with better readability in the YAML source.

**Default selection rationale:** 30 turns is sufficient for most single-skill invocations:

- Triage (multi-issue): 80 turns
- Bug fix (single issue): 25 turns
- Analysis (web research): 45 turns
- General skill: 30 turns (covers most cases)

### Change 3: Add label pre-creation step

Insert a step between checkout and the claude-code-action step.

```yaml
      - name: Ensure label exists
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh label create "scheduled-<NAME>" \
            --description "Scheduled: <DISPLAY_NAME>" \
            --color "0E8A16" 2>/dev/null || true
```

#### Research Insights

**Institutional learning applied:** The `2026-03-03-scheduled-bot-fix-workflow-patterns.md` learning confirms this exact pattern. The `scheduled-bug-fixer.yml` pre-creates `bot-fix/attempted` label. The `scheduled-daily-triage.yml` pre-creates 16 labels. The `scheduled-competitive-analysis.yml` pre-creates `scheduled-competitive-analysis` label. Every reference workflow follows this pattern.

**Constitution enforcement (line 101):** "GitHub Actions workflows that create issues with labels must pre-create labels via `gh label create <name> ... 2>/dev/null || true`"

**Edge case:** The `2>/dev/null || true` suffix is essential -- it silences the "already exists" error on subsequent runs and prevents the step from failing the workflow.

### Change 4: Clean up Known Limitations

Remove or update items in the Known Limitations section (lines 166-176) that are no longer accurate:

**Items to REMOVE (already fixed):**

- "No `--allowedTools` in `claude_args`" (line 174) -- fixed in #344
- The `id-token: write` mention is not in Known Limitations but was in the learning doc

**Items to UPDATE (being fixed in this PR):**

- "No `timeout-minutes`" (line 173) -- remove after adding to template
- "No `--max-turns` in `--claude_args`" (line 171) -- remove after adding to template (note: line 171 says "No `--max-turns` in `claude_args`" but the label says "claude_args" not "--claude_args")
- "No label pre-creation" (line 172) -- remove after adding to template

**Items to KEEP (genuinely unresolved, out of scope):**

- "Skills only" (line 167) -- agents cannot be reliably invoked in CI
- "Issue output only" (line 168) -- PR and Discord output modes are v2
- "No state across runs" (line 169) -- each run starts fresh
- "No skill-specific arguments" (line 170) -- template prompt has no argument passthrough
- "No cascading priority selection" (line 175) -- separate feature per #370

### Non-goals

- Changing existing deployed workflows (template change only)
- Adding skill-specific argument passthrough (documented as Known Limitation, separate feature)
- Adding cascading priority selection (separate feature, documented in Known Limitations)
- Changing the `permissions` block to `contents: write` (skill-specific; the template uses `contents: read` as a safe default -- users who need write access for `git push` must edit manually, per the token revocation learning)

## Technical Considerations

- **Input collection:** Two new inputs (`timeout-minutes` and `--max-turns`) need to be added to Step 1 (interactive) and Step 0 (argument bypass). Use defaults: 30 minutes timeout, 30 max-turns.
- **Backward compatibility:** Existing workflows are unaffected. Only newly generated workflows get the improvements.
- **Step 0 argument bypass:** Add `--timeout` and `--max-turns` flags to the `$ARGUMENTS` bypass path for programmatic callers.
- **YAML block scalar:** Use `>-` (folded strip) for `claude_args` to improve readability without changing semantics. The `>-` format folds newlines into spaces and strips trailing newline, producing identical output to a single-line string.
- **Step 4 summary update:** The confirmation output after generation (SKILL.md lines 117-131) should also display the new timeout and max-turns values.

### Research Insights: Token Revocation Awareness

The `2026-03-02-claude-code-action-token-revocation` learning revealed that `claude-code-action` revokes its GitHub App installation token in its post-step cleanup. Workflows that need to `git push` must do so inside the agent prompt, not in a subsequent step. The template's `contents: read` permission is the correct safe default -- skills that need write access (like competitive-analysis) are rare and require manual edits. Adding a note to the Known Limitations about this is preferable to changing the default permission.

### Consistency Check: Reference Workflow Comparison

| Feature | Template (after fix) | daily-triage | bug-fixer | competitive-analysis |
|---------|---------------------|-------------|-----------|---------------------|
| `timeout-minutes` | `<TIMEOUT>` (default 30) | 60 | 20 | 45 |
| `--max-turns` | `<MAX_TURNS>` (default 30) | 80 | 25 | 45 |
| Label pre-creation | Present | Present (16 labels) | Present (1 label) | Present (1 label) |
| `--allowedTools` | Present | Present | Present | Present |
| `id-token: write` | Present | Present | Present | Present |
| `plugin_marketplaces` | Present | Present | Present | Present |
| `plugins` | Present | Present | Present | Present |
| `concurrency` | Present | Present | Present | Present |
| SHA-pinned actions | Present (Step 2) | Present | Present | Present |
| `claude_args` format | `>-` block scalar | Single line | `>-` block scalar | Single line |

After this fix, the template achieves parity with all three reference workflows on every structural dimension.

## Acceptance Criteria

- [ ] Generated workflow YAML includes `timeout-minutes` on the job block (`plugins/soleur/skills/schedule/SKILL.md` Step 3 template)
- [ ] Generated workflow YAML includes `--max-turns` in `claude_args` (`plugins/soleur/skills/schedule/SKILL.md` Step 3 template)
- [ ] Generated workflow YAML includes a label pre-creation step with `gh label create ... || true` (`plugins/soleur/skills/schedule/SKILL.md` Step 3 template)
- [ ] `claude_args` uses `>-` block scalar format for readability (`plugins/soleur/skills/schedule/SKILL.md` Step 3 template)
- [ ] Known Limitations section accurately reflects current state -- stale items removed (`plugins/soleur/skills/schedule/SKILL.md` lines 166-176)
- [ ] Step 1 collects timeout (default 30) and max-turns (default 30) inputs (`plugins/soleur/skills/schedule/SKILL.md` Step 1)
- [ ] Step 0 `$ARGUMENTS` bypass supports `--timeout` and `--max-turns` flags (`plugins/soleur/skills/schedule/SKILL.md` Step 0)
- [ ] Step 4 confirmation summary displays timeout and max-turns values (`plugins/soleur/skills/schedule/SKILL.md` Step 4)
- [ ] Existing scheduled workflows remain unaffected (template change only -- verify with `git diff` that only SKILL.md is modified)

## Test Scenarios

- Given the schedule skill is invoked with `create`, when a user provides name/skill/cron/model and accepts defaults for timeout and max-turns, then the generated YAML includes `timeout-minutes: 30`, `--max-turns 30`, and a label pre-creation step
- Given the schedule skill is invoked with `--timeout 45 --max-turns 50`, when Step 0 parses arguments, then the values `timeout-minutes: 45` and `--max-turns 50` appear in the generated YAML
- Given no `--timeout` or `--max-turns` flags are provided, when the template is generated, then defaults of 30 and 30 are used
- Given the Known Limitations section, when a user reads it, then only genuinely unresolved limitations are listed (skills only, issue output only, no state, no skill-specific args, no cascading priority)
- Given the `claude_args` field in the generated YAML, when parsed by GitHub Actions, then the `>-` block scalar produces a single-line string identical to the previous format
- Given a user runs `soleur:schedule list` after generation, when the workflow file is parsed, then timeout and max-turns values are extractable from the YAML

## Files to Modify

| File | Change | Lines |
|------|--------|-------|
| `plugins/soleur/skills/schedule/SKILL.md` | Step 0: add `--timeout`, `--max-turns` to argument bypass | ~18 |
| `plugins/soleur/skills/schedule/SKILL.md` | Step 1: add timeout (item 5) and max-turns (item 6) inputs | ~38-40 |
| `plugins/soleur/skills/schedule/SKILL.md` | Step 3: add `timeout-minutes`, `--max-turns`, label step, `>-` format | ~68-104 |
| `plugins/soleur/skills/schedule/SKILL.md` | Step 4: add timeout/max-turns to confirmation summary | ~117-131 |
| `plugins/soleur/skills/schedule/SKILL.md` | Known Limitations: remove 3 stale items, keep 5 valid items | ~166-176 |

## References

- Issue: #382
- Learning: `knowledge-base/learnings/2026-02-27-schedule-skill-template-gaps-first-consumer.md`
- Learning: `knowledge-base/learnings/2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md`
- Learning: `knowledge-base/learnings/2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`
- Learning: `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md`
- Learning: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- Reference workflow: `.github/workflows/scheduled-daily-triage.yml`
- Reference workflow: `.github/workflows/scheduled-bug-fixer.yml`
- Reference workflow: `.github/workflows/scheduled-competitive-analysis.yml`
- Context7: `claude-code-action` docs -- `claude_args` configuration, `--max-turns`, automation mode
- Constitution lines 101-104 (label pre-creation, timeout-minutes, id-token, allowedTools)
- Prior fixes: #321 (v3.5.0), #341 (v3.7.4 id-token), #344 (v3.7.6 allowedTools)
