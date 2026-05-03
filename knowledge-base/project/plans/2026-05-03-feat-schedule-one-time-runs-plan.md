---
title: feat(schedule) — add --once flag for one-time scheduled agent runs
date: 2026-05-03
type: feature
issue: 3094
pr: 3067
branch: feat-schedule-one-time-runs
worktree: .worktrees/feat-schedule-one-time-runs
brainstorm: knowledge-base/project/brainstorms/2026-05-03-schedule-one-time-runs-brainstorm.md
spec: knowledge-base/project/specs/feat-schedule-one-time-runs/spec.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plan: `soleur:schedule --once` (one-time scheduled agent runs)

## Overview

Extend `plugins/soleur/skills/schedule/SKILL.md` with a `--once --at <ISO-date>` flag that generates a one-time GitHub Actions workflow. The workflow fires at the specified date, fetches its task spec from a referenced issue + comment, executes the documented work, and self-disables inside the agent prompt (forced by `claude-code-action` token revocation).

Scope is plugin users running Soleur in their own repo. Connected-repo path (Soleur writing schedules into customer repos) is deferred — separate issue is filed for the full CLO guardrail set.

The plan is intentionally small: one file edit, one test file, one dogfood run. The brand-survival risks (token leak, cross-tenant exec, stale-context wrong action) are addressed by four load-bearing defenses, not by audit checklist coverage.

## User-Brand Impact

**Artifact:** `soleur:schedule --once` — generated `.github/workflows/scheduled-*.yml` files committed to the user's repo, executed by `claude-code-action` against the user's secrets.

**Vector:** Token/secret leak via inlined prompts in workflow YAML; cross-tenant or wrong-repo execution; stale-context wrong action 2 weeks after authoring; reminder silently fails to fire.

**If this lands broken, the user experiences:** A scheduled agent fires 2 weeks after authoring against drifted state — posts a misleading comment to a closed issue, opens a PR against a deleted branch, or runs against a repo the user no longer owns. The user has no warning, no rollback, and the action is permanent on the public record.

**If this leaks, the user's data/workflow is exposed via:** Inline prompts committed to public git history forever (mitigated: context fetched at runtime, not inlined). Or a workflow that fires under stale authorization weeks after the user authored it (mitigated: fire-time stale-context preamble).

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan time before `/work` begins (covered by brainstorm Phase 0.5 carry-forward). `user-impact-reviewer` will be invoked at review-time per `plugins/soleur/skills/review/SKILL.md`.

## Four Load-Bearing Defenses

The plan-review consensus stripped the audit-checklist framing in favor of naming the defenses that actually carry the brand-survival weight:

| # | Defense | What it prevents | Where it lives |
|---|---------|------------------|----------------|
| **D1** | Issue+comment ID context reference (no inline prompts) | Token/secret leak via committed YAML | Workflow `env:` block; agent fetches at runtime |
| **D2** | Fire-time stale-context preamble | Wrong action against drifted state | First steps of agent prompt |
| **D3** | In-prompt date guard `[[ $(date -u +%F) == "$FIRE_DATE" ]]` | Cross-year re-fire (cron `0 9 17 5 *` repeats every May 17) | First step of agent prompt — **PRIMARY defense** |
| **D4** | `gh workflow disable` inside agent prompt | Re-fire on next cron tick | Last step of agent prompt — secondary defense |

D3 is primary, D4 is secondary. The plan-review caught that the original framing inverted these — disable can fail, the date guard cannot.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|------------|------------------|---------------|
| TR3: shared template base for recurring + one-time | SKILL.md embeds YAML inline; no separate template file | Inline branching in SKILL.md. Template extraction to `references/*.tmpl` is a possible future refactor (open question), not this PR. |
| TR6: verify YAML write via `grep` | Existing skill uses `python3 -c "yaml.safe_load"` | Stay with `python3 yaml.safe_load(...)['on']['schedule'][0]['cron']`. Drop the spec's `yq` suggestion — adds CI dependency for zero capability gain. |
| FR1: `--comment` and `--issue` flags optional | Spec leaves `--comment` optional | Make `--issue` AND `--comment` BOTH mandatory for `--once`. Drop `--comment-url` parsing; drop comment auto-pick. |
| `--name` optional with derivation | Spec specifies derivation | `--name` MANDATORY for `--once`. No derivation logic — operator-supplied name is self-documenting at `disable`/`prune` time. |
| Test framework | Bash content-assertions in `plugins/soleur/test/*.test.sh` | Single test file with 3-4 load-bearing assertions. Real regression test is the post-merge dogfood. |

## Open Questions Resolved at Plan Time

Per user direction:

| Question | Resolution |
|----------|------------|
| `--at` strict ISO format vs `--in '2 weeks'` alias | **Strict** `YYYY-MM-DD` only. Default time = 09:00 UTC. |
| Comment ID resolution: paste URL vs flags | **Flags only.** `--issue <N> --comment <id>`. URL parsing dropped. |
| `create` without `--cron` and without `--once` | **Explicit error.** No silent default. |

## Open Questions Deferred

| Question | Resolution |
|----------|------------|
| Extract `references/one-time-template.yml.tmpl`? | Defer. Inline branching is fine for one extension; revisit if SKILL.md crosses ~400 lines. |
| `list` reconciliation against on-disk files | Defer to a follow-on. V1 operators can run `gh workflow list` directly. |
| `--force` for workflow file collision | Defer. V1 errors on collision; no `--force`. |

## Implementation Phases

### Phase 1 — Extend `soleur:schedule` skill with `--once` (single SKILL.md edit)

**Goal:** Add `--once` flag, validation, one-time YAML template, and minimal `list` mode-detection in one cohesive SKILL.md edit.

#### 1.1 Argument parsing additions (Step 0/1 of skill)

- Accept flags: `--once`, `--at <YYYY-MM-DD>`, `--issue <N>`, `--comment <id>`, `--name <kebab-case>`. All five MANDATORY for `--once` mode.
- Reject `--cron` + `--once` together → error: `Cannot specify both --once and --cron`.
- Reject neither `--cron` nor `--once` → error: `Specify either --once <ISO-date> or --cron <expression>`.
- `--at` validation: parse via `python3 -c "from datetime import datetime; datetime.fromisoformat(...)"`. Reject past dates. Reject >50 days out (GHA auto-disables workflows after 60d inactivity; 10d margin).
- Reject if `.github/workflows/scheduled-<name>.yml` already exists. No `--force` flag.
- If current branch ≠ default branch (`git symbolic-ref refs/remotes/origin/HEAD | sed 's@^.*/@@'`), print **WARNING** (not error): "GHA cron triggers fire only from the default branch. Merge this workflow before <fire-date> or it will not fire."

#### 1.2 One-time YAML template (Step 3 of skill)

When `--once`, generate:

```yaml
name: "Scheduled (once): <DISPLAY_NAME>"
on:
  schedule:
    - cron: '0 9 <day> <month> *'
  workflow_dispatch: {}
permissions:
  contents: read
  issues: write
  actions: write          # REQUIRED for gh workflow disable
concurrency:
  group: schedule-once-<NAME>
  cancel-in-progress: false
env:
  ISSUE_NUMBER: "<N>"
  COMMENT_ID: "<id>"
  FIRE_DATE: "<YYYY-MM-DD>"
  WORKFLOW_NAME: "scheduled-<NAME>.yml"
jobs:
  fire:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@<sha>
      - name: One-time fire (with self-disable)
        uses: anthropics/claude-code-action@<sha>
        env:
          GH_TOKEN: ${{ github.token }}
        with:
          claude_args: "--max-turns 25"
          prompt: |
            ## Pre-flight (abort with observation comment if any check fails)

            1. **Date guard (PRIMARY cross-year defense):**
               `[[ "$(date -u +%F)" == "$FIRE_DATE" ]] || { gh workflow disable "$WORKFLOW_NAME"; exit 0; }`
            2. **Idempotency:** if workflow is in any disabled state, exit 0.
               `state=$(gh workflow view "$WORKFLOW_NAME" --json state --jq .state); [[ "$state" == "active" ]] || exit 0`
            3. **Repo not archived:** `[[ "$(gh repo view --json isArchived --jq .isArchived)" == "false" ]]`
            4. **Issue OPEN + same repo:** `gh issue view "$ISSUE_NUMBER" --json state,repository_url` — state must be OPEN; repository_url must end in `${{ github.repository }}`.
            5. **Comment exists + matches issue:** `gh api repos/${{ github.repository }}/issues/comments/$COMMENT_ID --jq .issue_url` must end in `/issues/$ISSUE_NUMBER`.

            If ANY pre-flight check fails: post a single observation comment to issue #$ISSUE_NUMBER naming which check failed, disable the workflow, exit 0. Take no other action.

            ## Task

            Fetch the task spec from the referenced comment:
            `gh api repos/${{ github.repository }}/issues/comments/$COMMENT_ID --jq .body`

            Execute the documented work. Post results as a follow-up comment on issue #$ISSUE_NUMBER.

            ## Final step (mandatory, last)

            `gh workflow disable "$WORKFLOW_NAME"` — secondary defense (date guard above is primary).
            If disable fails, post a follow-up comment to issue #$ISSUE_NUMBER:
            "Workflow ran but auto-disable failed. Manual: gh workflow disable $WORKFLOW_NAME"
```

YAML-write verification: `python3 -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); assert d['on']['schedule'][0]['cron'] == '<expected>'; assert d['env']['ISSUE_NUMBER'] == '<N>'" <path>`. Same primitive the existing skill uses; no new dependency.

#### 1.3 `list` minimal updates (Step of skill)

Parse cron expression: 5-field with explicit single-day + single-month + `*` year (e.g., `0 9 17 5 *`) → `[one-time]`; anything else → `[recurring]`. Mode detection only — defer richer state lookup (`pending` / `disabled_inactivity` / etc.) to a follow-on issue.

Output:
```
[recurring] weekly-audit (cron: 0 9 * * 1)
[one-time]  verify-hook-fires (cron: 0 9 17 5 *)
```

**Files to edit:** `plugins/soleur/skills/schedule/SKILL.md` (single file)

### Phase 2 — Documentation + tests

#### 2.1 Disambiguation section (FR6) at top of SKILL.md

```markdown
## When to use this skill vs harness `schedule`

Two skills exist with the name `schedule`. They serve different jobs:

| Use this (`soleur:schedule`) when | Use harness `schedule` when |
|---|---|
| Push commits, open PRs, modify the user's repo | Analyze, summarize, report — no repo writes |
| Use repo secrets (Doppler, Vercel, Cloudflare) | No secrets needed |
| Invoke a Soleur skill (`/soleur:<skill>`) | Generic Claude API task |
| Run Terraform / migrations / deploys | Read-only research, posting somewhere |

Examples for `soleur:schedule`:
- "Open a cleanup PR removing feature flag X in 2 weeks" → `--once`
- "Run a weekly Terraform drift check" → recurring

Examples for harness `schedule`:
- "Summarize recent issues every Monday and post to Slack"
- "Check if a vendor's API changed and email the diff"

If the agent doesn't need access to your repo, prefer harness `schedule`.
```

#### 2.2 Known-limitations section

```markdown
## Known limitations

- **`--once` requires merge-before-fire.** GHA cron triggers fire only from workflows on the default branch. A `--once` workflow on a feature branch must be merged before its fire date.
- **`--at` caps at 50 days.** GHA auto-disables workflows after 60 days of inactivity; 50d gives 10d margin.
- **Cron variance ~15 min.** `--at 2026-05-17` may fire 09:00–09:15 UTC.
```

#### 2.3 Tests (4 load-bearing scenarios in one file)

`plugins/soleur/test/schedule-skill-once.test.sh` — bash content-assertions on SKILL.md:

1. **TS1 — Token-revocation regression guard.** SKILL.md's `--once` template has `gh workflow disable` as the last instruction INSIDE the agent prompt (not a post-step). Catches the highest-blast-radius regression: someone "fixes" the disable into a post-step, the App token gets revoked first, disable silently fails, workflow re-fires every May 17 indefinitely.

2. **TS2 — Date guard present and correct.** SKILL.md contains the literal `[[ "$(date -u +%F)" == "$FIRE_DATE" ]]` line as the FIRST agent-prompt step. This is D3 (the primary cross-year defense).

3. **TS3 — Stale-context preamble present.** SKILL.md contains the OPEN-issue check, comment-issue match check, and observation-comment-on-failure instruction. This is D2.

4. **TS4 — Disambiguation section present.** SKILL.md contains "When to use this skill vs harness `schedule`" with at least 2 examples each. Catches deletion of the namespace-conflation guidance.

These are content-assertion tests — they catch deletion, not semantic drift. Real regression coverage is the post-merge dogfood (TS-dogfood below).

**Files to create:** `plugins/soleur/test/schedule-skill-once.test.sh`

### Phase 3 — Defer-and-track + dogfood

- File issue: connected-repo path with full CLO guardrail set (TOS clause, prompt-redaction gate, authorization TTL >14d). Milestone: Post-MVP / Later. Label: `deferred-scope-out`.
- File issue: `/soleur:schedule prune` cleanup command for fired-and-disabled one-time workflows. Milestone: Post-MVP / Later. Label: `deferred-scope-out`.
- File issue: `list` rich state output (pending / disabled_inactivity / fired-failed). Milestone: Post-MVP / Later. Label: `deferred-scope-out`.
- File issue: Optional `references/one-time-template.yml.tmpl` extraction if SKILL.md grows beyond ~400 lines. Milestone: Post-MVP / Later. Label: `deferred-scope-out`.

**TS-dogfood — post-merge end-to-end verification (real regression test):**
- Pick an existing OPEN issue. Add a brief comment with the documented task spec (e.g., "post a comment confirming this workflow fired").
- Run `/soleur:schedule create --once --at <today+1> --skill <noop-skill> --issue <N> --comment <id> --name dogfood-test`.
- Merge to main.
- Wait ~24h.
- Verify: result comment posted to the issue; workflow auto-disabled; `gh workflow view dogfood-test.yml --json state` returns `disabled_manually`.
- Comment outcome on PR.

## Files to Edit

| File | Change |
|------|--------|
| `plugins/soleur/skills/schedule/SKILL.md` | Add `--once` flag, validation, one-time YAML template, mode detection in `list`, disambiguation section, known-limitations |

## Files to Create

| File | Purpose |
|------|---------|
| `plugins/soleur/test/schedule-skill-once.test.sh` | 4 load-bearing content-assertions (token revocation guard, date guard, stale-context preamble, disambiguation section) |

## Files to NOT Edit

- `plugin.json` (frozen sentinel `0.0.0-dev`)
- `marketplace.json` (frozen sentinel)
- AGENTS.md (insight is domain-scoped per route-to-definition)
- Existing `.github/workflows/scheduled-*.yml` (recurring path untouched)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` query against `plugins/soleur/skills/schedule` and `soleur:schedule` returned zero matches.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Marketing (carried forward from brainstorm)

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Self-disable inside agent prompt (token-revocation learning). Tightened caps. `actions: write` required (added to Phase 1.2 YAML body — was missing in initial draft, caught by plan-review).

### Product (CPO)
**Status:** reviewed (brainstorm carry-forward; sign-off pending)
**Assessment:** Brand-survival threshold `single-user incident`. Non-negotiable: target ref exists, issue OPEN, prompt embeds verify-state-before-acting (Phase 1.2 implements all three).
**CPO sign-off:** ⏳ pending — confirmed via brainstorm participation; explicit ack required before `/work`.

### Legal (CLO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** For plugin-user-in-own-repo scope, exposure is bounded. Non-inline prompt-passing (D1) addresses CLO's biggest concern. Connected-repo guardrails deferred to Phase 3 issue.

### Marketing (CMO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** "Agents that come back" narrative beat. Announcement copy lands at ship phase, not plan/work.

### Product/UX Gate
**Tier:** none — CLI skill, no UI. No `components/**/*.tsx` or `app/**/page.tsx` files.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `--once`, `--at`, `--issue`, `--comment`, `--name` flags implemented in SKILL.md (all mandatory for `--once`)
- [ ] Mode mutex enforced (`--cron` + `--once` together → error; neither → error)
- [ ] `--at` validation: ISO YYYY-MM-DD only; reject past; reject >50 days; reject collision
- [ ] One-time YAML template includes `actions: write` permission, `FIRE_DATE` env var, date guard as FIRST prompt step, `gh workflow disable` as LAST prompt step
- [ ] Stale-context preamble in agent prompt: OPEN issue + same repo + comment matches issue + repo not archived
- [ ] `list` distinguishes `[recurring]` vs `[one-time]` by cron shape
- [ ] Disambiguation section "When to use this skill vs harness `schedule`" present in SKILL.md
- [ ] Known-limitations section names default-branch + cron-variance + 50-day-cap
- [ ] `plugins/soleur/test/schedule-skill-once.test.sh` passes (4 scenarios)
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (skill description budget unchanged)
- [ ] No regression in recurring path (existing 22 scheduled workflows unaffected)
- [ ] CPO sign-off recorded
- [ ] `user-impact-reviewer` invoked at review time and findings addressed
- [ ] 4 follow-up issues filed (connected-repo, prune, list state, template extraction)
- [ ] PR body contains `Closes #3094` and `Ref #3093` and `Ref #3096`

### Post-merge (operator)

- [ ] **TS-dogfood:** Create `--once` schedule against an open issue with `--at <today+1>`. Verify fire next day, result comment posted, auto-disable. Comment results on the merged PR. **This is the real regression test** — content-assertions catch deletion, dogfood catches semantic drift.

## Test Scenarios (4 load-bearing)

| # | Scenario | Type | Defense it guards |
|---|----------|------|-------------------|
| TS1 | `gh workflow disable` is LAST instruction inside agent prompt | Content-assertion | D4 (token revocation regression) |
| TS2 | Date guard `[[ date == FIRE_DATE ]]` is FIRST agent-prompt step | Content-assertion | D3 (cross-year re-fire) |
| TS3 | Stale-context preamble (OPEN, same-repo, comment-matches) | Content-assertion | D2 (drifted-state action) |
| TS4 | Disambiguation section present with examples | Content-assertion | namespace-conflation regression |
| TS-dogfood | End-to-end fire + result + disable | Post-merge real run | All four defenses (semantic) |

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Cross-year re-fire (cron `0 9 17 5 *` repeats) | HIGH | **D3 date guard (PRIMARY)** + D4 self-disable (secondary) |
| Self-disable fails silently and workflow re-fires next year | MEDIUM | D3 date guard catches it; FR4 fallback comment alerts operator on first fail |
| User creates `--once` on feature branch, forgets to merge | MEDIUM | Create-time WARNING; documented in known-limitations |
| `claude-code-action` SHA changes break the prompt template | MEDIUM | SHA-pinning preserved; existing skill already handles this |
| Operator types wrong issue/comment ID combination | LOW (with D2) | D2 fire-time stale-context preamble catches mismatch and aborts with observation comment |
| Repo archived between create and fire | LOW (with D2) | D2 preamble check |
| Inline prompts leak in committed YAML | MITIGATED | D1: prompts fetched at runtime |
| Connected-repo path lands without CLO guardrails | OUT-OF-SCOPE | Phase 3 follow-up issue |
| Content-assertion tests pass while semantic behavior breaks | MEDIUM | TS-dogfood is the real regression catcher; ship blocker if dogfood is skipped |

## Sharp Edges

- D3 (date guard) is the PRIMARY cross-year defense, not "belt-and-suspenders." If a future refactor removes the date guard reasoning that disable will catch it, that reasoning is wrong — disable can fail.
- `gh workflow disable` requires `actions: write` permission. The Phase 1.2 YAML template includes it; do not strip it during refactor.
- `claude-code-action` revokes the App token AFTER the agent step. Self-disable MUST be inside the agent's prompt — not a post-step.
- `--at` strict ISO format: `--at "2 weeks from now"` is rejected. The `date -d` natural-language parser is INTENTIONALLY not used (per `2026-02-21-github-actions-workflow-security-patterns`).
- The 50-day cap on `--at` is driven by GHA's 60-day inactivity auto-disable. Lowering is fine; raising above 60 will silently break.
- Content-assertion tests (TS1-TS4) catch deletion, NOT semantic drift. The dogfood is the real test. Skipping the dogfood means shipping blind.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled.

## Implementation Sequencing

1. Phase 1 (skill extension) — 90 min — single SKILL.md edit covering parsing, YAML template, list mode detection
2. Phase 2 (docs + tests) — 60 min — disambiguation section, known-limitations, single test file
3. Phase 3 (defer-and-track + dogfood prep) — 30 min — 4 `gh issue create` calls + dogfood scaffold

Total estimate: ~3 hours. Single PR. No version bump.

## Resume Prompt

```
/soleur:work knowledge-base/project/plans/2026-05-03-feat-schedule-one-time-runs-plan.md
Branch: feat-schedule-one-time-runs
Worktree: .worktrees/feat-schedule-one-time-runs/
PR: #3067 (draft)
Issue: #3094
Brand-survival threshold: single-user incident
Plan reviewed and simplified per DHH/Kieran/Simplicity consensus. 3 phases; 1 file edit, 1 test file. Ready to implement.
```
