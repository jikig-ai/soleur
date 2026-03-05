---
title: "fix: close remaining schedule skill template gaps"
type: fix
date: 2026-03-05
semver: patch
issue: "#382"
---

# fix: close remaining schedule skill template gaps

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

Update `plugins/soleur/skills/schedule/SKILL.md` with three changes:

### Change 1: Add `timeout-minutes` to template YAML

Add `timeout-minutes: <TIMEOUT>` to the job block. Collect timeout as a new input in Step 1 with a sensible default (30 minutes).

**Before:**
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

### Change 2: Add `--max-turns` to `claude_args`

Collect max-turns as a new input in Step 1 with a sensible default (30 turns).

**Before:**
```yaml
claude_args: '--model <MODEL> --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch'
```

**After:**
```yaml
claude_args: '--model <MODEL> --max-turns <MAX_TURNS> --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch'
```

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

### Change 4: Clean up Known Limitations

Remove or update items that are no longer accurate:
- Remove "No `--allowedTools` in `claude_args`" (fixed)
- Remove "No `id-token: write`" if it was listed (fixed)
- Update remaining items to reflect current state
- Add cross-reference to this fix

### Non-goals

- Changing existing deployed workflows (template change only)
- Adding skill-specific argument passthrough (documented as Known Limitation, separate feature)
- Adding cascading priority selection (separate feature, documented in Known Limitations)

## Technical Considerations

- **Input collection:** Two new inputs (`timeout-minutes` and `--max-turns`) need to be added to Step 1 (interactive) and Step 0 (argument bypass). Use defaults: 30 minutes timeout, 30 max-turns.
- **Backward compatibility:** Existing workflows are unaffected. Only newly generated workflows get the improvements.
- **Step 0 argument bypass:** Add `--timeout` and `--max-turns` flags to the `$ARGUMENTS` bypass path for programmatic callers.

## Acceptance Criteria

- [ ] Generated workflow YAML includes `timeout-minutes` on the job block
- [ ] Generated workflow YAML includes `--max-turns` in `claude_args`
- [ ] Generated workflow YAML includes a label pre-creation step with `gh label create ... || true`
- [ ] Known Limitations section accurately reflects current state (stale items removed)
- [ ] Step 1 collects timeout and max-turns inputs with sensible defaults
- [ ] Step 0 `$ARGUMENTS` bypass supports `--timeout` and `--max-turns` flags
- [ ] Existing scheduled workflows remain unaffected (template change only)

## Test Scenarios

- Given the schedule skill is invoked with `create`, when a user provides name/skill/cron/model, then the generated YAML includes `timeout-minutes`, `--max-turns`, and label pre-creation step
- Given the schedule skill is invoked with `--timeout 45 --max-turns 50`, when Step 0 parses arguments, then the values propagate into the generated YAML
- Given no `--timeout` or `--max-turns` flags are provided, when the template is generated, then defaults of 30 and 30 are used
- Given the Known Limitations section, when a user reads it, then only genuinely unresolved limitations are listed

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/skills/schedule/SKILL.md` | Add timeout/max-turns inputs, label pre-creation step, update template YAML, clean Known Limitations |

## References

- Issue: #382
- Learning: `knowledge-base/learnings/2026-02-27-schedule-skill-template-gaps-first-consumer.md`
- Learning: `knowledge-base/learnings/2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md`
- Reference workflow: `.github/workflows/scheduled-daily-triage.yml`
- Reference workflow: `.github/workflows/scheduled-bug-fixer.yml`
- Reference workflow: `.github/workflows/scheduled-competitive-analysis.yml`
- Constitution lines 101-104 (label pre-creation, timeout-minutes, id-token, allowedTools)
- Prior fixes: #321 (v3.5.0), #341 (v3.7.4 id-token), #344 (v3.7.6 allowedTools)
