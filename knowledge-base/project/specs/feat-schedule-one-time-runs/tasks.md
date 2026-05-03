---
feature: schedule-one-time-runs
plan: knowledge-base/project/plans/2026-05-03-feat-schedule-one-time-runs-plan.md
spec: knowledge-base/project/specs/feat-schedule-one-time-runs/spec.md
issue: 3094
pr: 3067
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks: `soleur:schedule --once`

## Phase 1 — Extend `soleur:schedule` with `--once` (single SKILL.md edit)

### 1.1 Argument parsing (Step 0/1)
- [ ] 1.1.1 Add `--once`, `--at <YYYY-MM-DD>`, `--issue <N>`, `--comment <id>`, `--name <kebab-case>` to flag-extraction in Step 0
- [ ] 1.1.2 Reject `--cron` + `--once` together with explicit error
- [ ] 1.1.3 Reject neither `--cron` nor `--once` with explicit error (no silent default)
- [ ] 1.1.4 `--at` validation via `python3 datetime.fromisoformat`; reject past, reject >50 days
- [ ] 1.1.5 Reject if `.github/workflows/scheduled-<name>.yml` already exists
- [ ] 1.1.6 Print create-time WARNING when current branch ≠ default branch

### 1.2 One-time YAML template (Step 3)
- [ ] 1.2.1 Generate cron `0 9 <day> <month> *` from `--at <YYYY-MM-DD>`
- [ ] 1.2.2 Set `permissions: contents: read, issues: write, actions: write`
- [ ] 1.2.3 Set `timeout-minutes: 20` and `--max-turns 25`
- [ ] 1.2.4 Set `env: ISSUE_NUMBER, COMMENT_ID, FIRE_DATE, WORKFLOW_NAME`
- [ ] 1.2.5 Embed agent prompt: pre-flight (date guard FIRST, idempotency, repo-not-archived, issue-OPEN-same-repo, comment-matches-issue) → task → self-disable LAST
- [ ] 1.2.6 Pre-flight failure path: post observation comment to issue, disable, exit 0
- [ ] 1.2.7 Self-disable failure path: post follow-up comment to issue with manual-disable hint
- [ ] 1.2.8 YAML write verification via `python3 yaml.safe_load` (NOT `yq`, NOT grep)

### 1.3 `list` mode detection
- [ ] 1.3.1 Parse cron expression: 5-field with explicit single-day + single-month + `*` year → `[one-time]`
- [ ] 1.3.2 All other patterns → `[recurring]`
- [ ] 1.3.3 Output format includes mode tag and the cron expression

## Phase 2 — Documentation + tests

### 2.1 SKILL.md disambiguation section
- [ ] 2.1.1 Add "When to use this skill vs harness `schedule`" section at top of SKILL.md
- [ ] 2.1.2 Include comparison table with at least 4 distinguishing rows
- [ ] 2.1.3 Include at least 2 example use cases for each skill
- [ ] 2.1.4 Add closing line: "If the agent doesn't need access to your repo, prefer harness `schedule`."

### 2.2 SKILL.md known-limitations section
- [ ] 2.2.1 Document default-branch-only cron constraint
- [ ] 2.2.2 Document GHA cron variance ~15 min
- [ ] 2.2.3 Document `--at` 50-day cap and the underlying GHA 60-day inactivity reason

### 2.3 Tests
- [ ] 2.3.1 Create `plugins/soleur/test/schedule-skill-once.test.sh`
- [ ] 2.3.2 TS1 — assert `gh workflow disable` appears as LAST instruction inside agent prompt (token-revocation regression guard)
- [ ] 2.3.3 TS2 — assert literal `[[ "$(date -u +%F)" == "$FIRE_DATE" ]]` appears as FIRST agent-prompt step (date guard / D3)
- [ ] 2.3.4 TS3 — assert stale-context preamble lines (OPEN issue, repo match, comment-issue match, observation-on-failure) all present
- [ ] 2.3.5 TS4 — assert disambiguation section present with at least 2 examples per skill
- [ ] 2.3.6 Verify `bun test plugins/soleur/test/components.test.ts` still passes (skill description budget)

## Phase 3 — Defer-and-track + dogfood

### 3.1 File deferred-scope-out issues
- [ ] 3.1.1 File issue: connected-repo path with full CLO guardrail set (TOS clause, prompt-redaction gate, authorization TTL >14d). Milestone: Post-MVP / Later. Label: `deferred-scope-out`.
- [ ] 3.1.2 File issue: `/soleur:schedule prune` cleanup command. Milestone: Post-MVP / Later. Label: `deferred-scope-out`.
- [ ] 3.1.3 File issue: `list` rich state output (pending/disabled_inactivity/fired-failed). Milestone: Post-MVP / Later. Label: `deferred-scope-out`.
- [ ] 3.1.4 File issue: optional `references/one-time-template.yml.tmpl` extraction if SKILL.md grows beyond ~400 lines. Milestone: Post-MVP / Later. Label: `deferred-scope-out`.

### 3.2 Pre-PR readiness
- [ ] 3.2.1 PR body contains `Closes #3094`, `Ref #3093`, `Ref #3096`
- [ ] 3.2.2 PR body contains `## Changelog` section
- [ ] 3.2.3 Set semver label via `/ship` (target: `semver:minor` — new skill capability)
- [ ] 3.2.4 CPO sign-off recorded (PR comment or domain-leader artifact)
- [ ] 3.2.5 Trigger `user-impact-reviewer` at review time per `single-user incident` threshold

### 3.3 Post-merge dogfood (TS-dogfood — the real regression test)
- [ ] 3.3.1 Pick an existing OPEN issue; add a comment with documented task spec ("post a confirmation comment that this workflow fired")
- [ ] 3.3.2 Run `/soleur:schedule create --once --at <today+1> --skill <noop> --issue <N> --comment <id> --name dogfood-test`
- [ ] 3.3.3 Merge to main
- [ ] 3.3.4 Wait ~24h
- [ ] 3.3.5 Verify result comment posted to issue
- [ ] 3.3.6 Verify `gh workflow view dogfood-test.yml --json state` returns `disabled_manually`
- [ ] 3.3.7 Comment dogfood outcome on the merged PR
