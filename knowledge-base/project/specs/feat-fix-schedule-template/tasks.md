# Tasks: fix schedule skill template remaining gaps

Issue: #382
Plan: `knowledge-base/project/plans/2026-03-05-fix-schedule-template-remaining-gaps-plan.md`

## Phase 1: Template Updates (`plugins/soleur/skills/schedule/SKILL.md`)

- [x] 1.1 Add `timeout-minutes` input to Step 1 (interactive collection) with default 30
  - Add as item 5 after model input
  - Validate: positive integer, minimum 5 minutes
- [x] 1.2 Add `--max-turns` input to Step 1 (interactive collection) with default 30
  - Add as item 6 after timeout input
  - Validate: positive integer, minimum 5 turns
- [x] 1.3 Add `--timeout` and `--max-turns` flags to Step 0 argument bypass path (~line 18)
  - Update the conditional: "If `$ARGUMENTS` contains `--name`, `--skill`, `--cron`, `--model`, `--timeout`, and `--max-turns` flags"
  - Make `--timeout` and `--max-turns` optional with defaults (only `--name`, `--skill`, `--cron`, `--model` required)
- [x] 1.4 Update template YAML in Step 3 (~lines 68-104):
  - [x] 1.4.1 Add `timeout-minutes: <TIMEOUT>` to the job block (after `runs-on`)
  - [x] 1.4.2 Convert `claude_args` from single-line string to `>-` block scalar format
  - [x] 1.4.3 Add `--max-turns <MAX_TURNS>` to `claude_args`
  - [x] 1.4.4 Add label pre-creation step between checkout and claude-code-action step

## Phase 2: Known Limitations Cleanup (`plugins/soleur/skills/schedule/SKILL.md` lines 166-176)

- [x] 2.1 Remove stale Known Limitations:
  - Remove "No `--allowedTools` in `claude_args`" (fixed in #344)
  - Remove "No `timeout-minutes`" (fixed in this PR)
  - Remove "No `--max-turns` in `claude_args`" (fixed in this PR)
  - Remove "No label pre-creation" (fixed in this PR)
- [x] 2.2 Verify remaining limitations are still accurate:
  - "Skills only" -- still true
  - "Issue output only" -- still true
  - "No state across runs" -- still true
  - "No skill-specific arguments" -- still true
  - "No cascading priority selection" -- still true
- [x] 2.3 Update Step 4 confirmation summary (~lines 117-131) to display timeout and max-turns values

## Phase 3: Validation

- [x] 3.1 Run markdownlint on updated SKILL.md
- [x] 3.2 Verify template YAML is valid (manual review of indentation, `>-` scalar correctness)
- [x] 3.3 Compare generated template structure against all 3 reference workflows for parity
- [x] 3.4 Verify `>-` block scalar produces correct single-line string (no trailing newline)
