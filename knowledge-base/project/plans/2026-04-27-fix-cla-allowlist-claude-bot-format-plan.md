# Fix: CLA allowlist uses wrong format for Claude bot identity

- **Issue:** [#2907](https://github.com/jikig-ai/soleur/issues/2907) (P2, `type/bug`)
- **Branch:** `feat-one-shot-2907`
- **Worktree:** `.worktrees/feat-one-shot-2907/`
- **Files to edit:** `.github/workflows/cla.yml` (one line)
- **Files to create:** none
- **Type:** `fix(ci)` / `semver:patch`
- **Detail level:** MINIMAL (one-line workflow edit; CI-only, no production code, no migration)

## Overview

The `contributor-assistant/github-action` v2.6.1 enforces CLA signatures on every committer of a pull request. The allowlist in `.github/workflows/cla.yml:34` currently reads:

```yaml
allowlist: "dependabot[bot],github-actions[bot],renovate[bot],deruelle,app/claude,claude"
```

PRs authored by `claude-code-action` (e.g. `soleur:fix-issue` output, scheduled bug-fixer) carry commits whose committer GitHub login is **`claude[bot]`** (verified in §Research Reconciliation). Neither `app/claude` nor the bare token `claude` matches that login, so the CLA check fails on every Claude-authored PR until the operator amends commit authorship to `deruelle` (which is allowlisted) — exactly the workaround applied to PR #2893.

The fix adds `claude[bot]` to the allowlist. The pre-existing `app/claude` entry stays (defense-in-depth: it's the App-slug form returned by GitHub's PR-author API and is harmless if unused by the action). The bare `claude` entry is dead weight and is removed in the same edit to keep the allowlist minimal.

## Research Reconciliation — Spec vs. Codebase

The issue body's premise is mostly correct but contains one factual nuance worth recording so the fix is durable.

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "Claude GitHub App's actual login is `claude[bot]`" | **Confirmed.** `git log --all --pretty='%an <%ae>'` shows every Claude-authored commit on `main` carries author `claude[bot] <209825114+claude[bot]@users.noreply.github.com>`. Recent examples: 0a455f8c, e4cbfa04, fa0d6c94, 4bcaecb9. | Add `claude[bot]` to allowlist. |
| "`app/claude,claude` matches neither the bot's GitHub login nor any known format" | **Partially incorrect.** `app/claude` IS the login that `gh pr view --json author --jq '.author.login'` returns for Claude-authored PRs (it's the **App-slug** form GitHub uses on the PR-author surface). What it does NOT match is the **commit-committer** login `claude[bot]` — and the contributor-assistant action checks **every committer** per its README ("ALL committers must sign"). | Keep `app/claude` (defense-in-depth for any future check that uses the PR-author surface, e.g. `scheduled-bug-fixer.yml:213` already pattern-matches `app/claude`). Drop the bare `claude` token (matches no known surface). |
| "PR #2898 passed CLA because its commit was authored by `github-actions[bot]`" | **Confirmed.** `gh pr view 2898 --json commits` shows the bot-fix commit has the email `41898282+claude[bot]@users.noreply.github.com` which GitHub's API resolves to login `github-actions[bot]` (allowlisted), with display name `claude[bot]`. The merge commit has author `deruelle` (also allowlisted). Both committers cleared the allowlist by coincidence. | No change required — this is the false-positive path the fix is removing. |
| "PR #2893 evidence: cla-check failed for `claude[bot]` author" | **Confirmed via remediation trail.** The current state of PR #2893 shows `cla-check: SUCCESS` with a single commit authored by `deruelle` — i.e. authorship was rewritten as the issue describes. The original failure is no longer recoverable from `gh` (force-push erases the prior commit) but the remediation trail and `git log` evidence on `main` corroborate the issue body. | Validation step (below) will rerun the gate against an unrewritten `claude[bot]`-authored PR. |

**Action surface check.** The contributor-assistant README is explicit: the allowlist is keyed by **GitHub username**, with wildcard support (`bot*`). The action checks committers; it does not separately check the PR-author login. Therefore `claude[bot]` (the committer login) is the load-bearing entry. `app/claude` is harmless but unused by the CLA action; it is retained because `scheduled-bug-fixer.yml:213` and `scripts/lint-bot-synthetic-completeness.sh:12` already match on `app/claude` for the PR-author surface and consistency across workflows aids future maintenance.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (21 open issues); no body matches `.github/workflows/cla.yml` or `claude[bot]`.

## Hypotheses (L7 only — no network/SSH symptom; gate `hr-ssh-diagnosis-verify-firewall` does not apply)

| Hypothesis | Verification | Status |
|---|---|---|
| Allowlist token `claude[bot]` will match the committer login the action checks | contributor-assistant README §5 ("Users and bots in allowlist") states allowlist is GitHub-username keyed; `git log` on `main` confirms `claude[bot]` is the committer login on every Claude-authored merge | **Confirmed** |
| Removing `app/claude` would break some other CLA path | The action checks committers, not PR authors. `app/claude` is unused by `cla.yml`. **However**, three other workflow files match `app/claude` for PR-author detection (`scheduled-bug-fixer.yml:213`, `scripts/lint-bot-synthetic-completeness.sh:12`, `bot-pr-with-synthetic-checks/action.yml`). Keeping `app/claude` in `cla.yml` adds zero cost and zero coupling but reads as deliberate to a future maintainer. | **Keep** |

## Implementation Phases

### Phase 1: Edit the allowlist

Single-line edit to `.github/workflows/cla.yml` line 34.

- [ ] Read `.github/workflows/cla.yml` (already read at plan time; re-read pre-edit per `hr-always-read-a-file-before-editing-it`).
- [ ] Apply this exact edit:

    ```diff
    -          allowlist: "dependabot[bot],github-actions[bot],renovate[bot],deruelle,app/claude,claude"
    +          allowlist: "dependabot[bot],github-actions[bot],renovate[bot],deruelle,app/claude,claude[bot]"
    ```

    Net change: replace bare token `claude` with `claude[bot]`. Keep `app/claude` (defense-in-depth). Order preserved.

- [ ] Verify YAML is still parseable: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/cla.yml'))"` — must exit 0.
- [ ] No other workflow files need updating: the `app/claude` matchers in `scheduled-bug-fixer.yml` and `bot-pr-with-synthetic-checks` use shell pattern matching against `gh pr view --json author` output (which returns `app/claude`), not the CLA action's allowlist. These are unrelated surfaces and remain correct.

### Phase 2: Verify on a real bot-authored PR (post-merge)

The fix only matters when a `claude[bot]`-authored PR runs the CLA workflow. We cannot fully validate pre-merge because:

1. `pull_request_target` triggers on the **base branch's** workflow file — pre-merge, the base (`main`) still has the broken allowlist, so a feature-branch PR runs the old config.
2. The CLA check on this PR (#2907's PR) will run with the **new** config from `main` only after merge.

The cheap pre-merge proxy is YAML-parse + diff inspection (Phase 1). The load-bearing post-merge probe is:

- [ ] Post-merge: monitor the next `soleur:fix-issue`-generated PR (the scheduled bug-fixer runs daily; `gh pr list --author 'app/claude' --state open --limit 5` shows recent ones).
- [ ] Confirm `gh pr checks <N> | grep cla-check` reports `pass` without authorship rewriting.
- [ ] If the next bot-fix PR is generated within 48h of merge: explicit verification.
- [ ] If no bot-fix PR is generated within 48h: the daily community-digest cron (also `claude[bot]`-authored, e.g. PR #2899) is a sufficient probe; capture the same `cla-check: pass` evidence from one of its CI runs.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/workflows/cla.yml` line 34 contains `claude[bot]` and no longer contains the bare token `claude`.
- [ ] `app/claude` retained (defense-in-depth across the wider workflow surface).
- [ ] YAML parses cleanly (`yamllint` or `yaml.safe_load`).
- [ ] PR body contains `Closes #2907`.
- [ ] No other files modified.

### Post-merge (operator)

- [ ] First post-merge `claude[bot]`-authored PR (bot-fix or community digest) shows `cla-check: pass` without commit-authorship rewriting.
- [ ] If the post-merge probe fails: open a follow-up issue immediately documenting the failing committer login (from `git log` on the failing PR's commit) and re-evaluate the allowlist token.

## Test Strategy

No automated tests. The CLA workflow is itself the integration test, and its trigger surface (`pull_request_target` against `main`) cannot be exercised from a feature branch — see Phase 2 rationale. The pre-merge gate is YAML validity; the post-merge gate is a real bot-PR run.

This is consistent with the project convention for `.github/workflows/*.yml` single-line config edits — the merged branches `2026-03-19-chore-cla-ruleset-integration-id-plan.md` and `2026-03-20-chore-standardize-claude-code-action-sha-plan.md` followed the same pattern (no unit tests for YAML edits; production observation is the validator).

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `claude[bot]` is not the actual committer login the contributor-assistant action keys on (e.g., it might use `committer.email`-derived identity differently) | LOW | `git log` evidence is direct: every merged Claude-authored commit on `main` has `%an = claude[bot]`. The contributor-assistant action README explicitly cites the `dependabot[bot]` format as the canonical pattern. If post-merge verification fails, the follow-up is a 5-minute fix (read the failing commit's resolved login from the action logs and update the entry). |
| Removing the bare `claude` token breaks something | NEGLIGIBLE | The bare token matches no known login surface. Nothing in this repo references the bare-`claude` allowlist entry. `git log -p .github/workflows/cla.yml` shows it was added speculatively at the same time as `app/claude` and never tested against a real PR. |
| Future Anthropic GitHub App rename changes the bot's login | MEDIUM (out of scope) | If Anthropic ships a new App, both `claude[bot]` and `app/claude` would change. Detection is the `cla-check: fail` signal on the next bot-PR; remediation is a one-line edit. Not worth a wildcard `*[bot]` pattern (would weaken the allowlist's audit trail). |
| Pre-merge probe gives false confidence | MEDIUM | Phase 2 explicitly documents this: pre-merge YAML-parse is necessary but not sufficient. The acceptance criterion is post-merge bot-PR observation. |

## Non-Goals

- Switching to a wildcard pattern (`*[bot]`) — too permissive; weakens the audit trail.
- Adding `claude` (bare display-name) — not a GitHub login; matches no surface.
- Restructuring how the contributor-assistant action is invoked (action version, params other than allowlist) — not in scope.
- Updating the `app/claude` matchers in `scheduled-bug-fixer.yml` / `bot-pr-with-synthetic-checks/action.yml` — those operate on the GitHub PR-author REST surface (`gh pr view --json author`) which still returns `app/claude`. They are correct as-is.

## Domain Review

**Domains relevant:** none

This is an infrastructure/CI-only change (one line in a GitHub Actions workflow). No user-facing surface, no product or marketing implications, no legal change (the CLA document and signature flow are unchanged — only the allowlist that bypasses the flow for pre-approved bot identities is corrected). No domain leader gate fires.

## Files to Edit

- `.github/workflows/cla.yml` — line 34 only.

## Files to Create

- None.

## PR Body Reminder

```
Closes #2907

Replaces the bare `claude` allowlist token with `claude[bot]` (the actual GitHub
committer login Anthropic's GitHub App emits). Keeps `app/claude` for defense-in-
depth across the wider workflow surface (`scheduled-bug-fixer.yml`,
`bot-pr-with-synthetic-checks`).

Pre-merge validation: YAML parse + diff inspection. Post-merge validation: next
`claude[bot]`-authored PR (bot-fix or community-digest cron) clears `cla-check`
without commit-authorship rewriting.
```
