---
title: CodeQL coverage on bot PRs
audience: operator
on_page_for: scripts/audit-bot-codeql-coverage.sh
issues: [3545, 3542, 2719]
brand_survival_threshold: none
last_updated: 2026-05-11
---

# CodeQL coverage on bot PRs

## Trigger

Run [`scripts/audit-bot-codeql-coverage.sh`](../../../../scripts/audit-bot-codeql-coverage.sh) when:

- Any change is made to the CI Required ruleset (#14145388) — verify `CodeQL` coverage on bot PRs is still satisfied.
- CodeQL default setup configuration is changed (languages, query suite, threat model, schedule).
- A bot PR is observed stuck in the auto-merge queue for >24h with `gh pr view <N> --json mergeStateStatus` showing `BLOCKED`.
- Routinely as part of weekly ops sanity (until a scheduled cron lands — see "Schedule" §below).

## What this runbook is (and isn't)

**Is:** a read-only empirical check that bot-authored PRs (composite-action + inline-pattern workflows) satisfy the `CodeQL` required status check on the `CI Required` ruleset.

**Is not:** a CodeQL alert triage runbook (`type/security` issues from `codeql-to-issues.yml` cover real findings — different workflow, different surface).

## The as-built behavior

The `CI Required` ruleset (#14145388) requires `CodeQL` as a status check, pinned to `integration_id: 57789` (the GitHub Advanced Security app). GitHub's CodeQL default setup is configured for this repo and runs on every `pull_request` event regardless of author. When a bot PR has no analyzable changes in scope (e.g., a markdown-only doc update, a content-publisher PR with no code), CodeQL completes with `conclusion: neutral`.

Per [GitHub Docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches): *"Required status checks must have a successful, skipped, or neutral status before collaborators can make changes to a protected branch."*

So `neutral` satisfies the requirement. Empirical confirmation (2026-05-11, 8 sampled bot PRs): all 8 had `CodeQL` with `app.id: 57789`, `conclusion: neutral` — auto-merged in 48s–17min.

This is why the `CI Required` ruleset's `CodeQL` requirement does NOT block bot PRs even though no bot workflow posts a synthetic `CodeQL` check-run. **Synthetic posting is structurally impossible:** the ruleset pins `CodeQL` to `integration_id: 57789` and `github-actions[bot]` (`integration_id: 15368`) cannot post check-runs as another app.

## When to run the audit

```bash
bash scripts/audit-bot-codeql-coverage.sh --json --limit 5
```

Exit codes:
- `0` — pass (all sampled bot PRs have `CodeQL` with conclusion ∈ {`success`, `neutral`, `skipped`})
- `1` — drift (a bot PR has `CodeQL` missing, failure, cancelled, timed_out, or wrong app)
- `2` — re-poll required (a bot PR has `CodeQL` still `in_progress`)

Output goes to stdout as a JSON envelope; human-readable per-PR pass/fail lines go to stderr.

## Drift triage

### `codeql_state: missing`

`CodeQL` check-run is absent for the head SHA. Possible causes:

1. **CodeQL default setup was disabled or narrowed.** Check `gh api /repos/jikig-ai/soleur/code-scanning/default-setup` — `state` should be `configured`, `languages` should include `actions, javascript, javascript-typescript, python, typescript`, `schedule` should be `weekly` (or `none`-for-event-driven), and `query_suite` should be `extended` or `default`.
2. **PR's diff touched no analyzable language.** A markdown-only PR may not trigger any language analyzer. This is BENIGN — but the audit conservatively flags it; verify by inspecting the PR's `gh pr diff <N>`.
3. **PR was opened against a non-default branch where CodeQL doesn't run.** Verify `gh pr view <N> --json baseRefName` — should be `main`.

Fix path: if (1), restore CodeQL default setup via GitHub Settings → Code security → Code scanning → CodeQL default setup. If (2), no action needed — close the audit drift as benign. If (3), retarget the PR.

### `codeql_state: failure` or `cancelled` or `timed_out`

`CodeQL` ran but did not pass. This is a real finding, NOT a coverage gap. Route to `type/security` via the standard CodeQL alert flow (`codeql-to-issues.yml`). The audit closes by linking the PR to a `type/security` issue and reporting "real finding triaged separately."

### `codeql_state: wrong_app`

A `CodeQL` check-run is posted by an app OTHER than `integration_id: 57789`. This indicates someone wired a synthetic `CodeQL` posting from `github-actions[bot]` or another non-GHAS app — which would NOT satisfy the ruleset. Investigate `.github/workflows/` and `.github/actions/` for a `name: CodeQL` posting and remove it. The ruleset's `integration_id` pin will reject it at merge anyway, but the wrong-app posting is a structural footgun.

### `codeql_state: in_progress`

`CodeQL` is still running against the head SHA at audit time. Exit code 2; re-poll in ~5 minutes. Most common during dependabot force-push rebases. NOT escalated.

## Rollback / escalation

If `neutral` ever stops satisfying the required check (would contradict current GitHub Docs and is unlikely):

1. **Manual unstick:** an org admin merges via `bypass_actors` (`OrganizationAdmin`, `pull_request` mode — see `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md`).
2. **Long-term:** file a GitHub support ticket citing the doc reversal. Audit script's `H3` sub-classification distinguishes "ruleset semantics shifted" from "individual alert needs triage."

## Cross-references

- `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` — parent R15 runbook.
- `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` — sibling audit (#3544) for `bypass_actors`.
- `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md` — sibling lint runbook (#3546) covering pre-merge enforcement of bot-PR synthetic check-run completeness.
- `scripts/required-checks.txt` — synthetic-postable check names (NOT including `CodeQL` by design — see comment block in that file).
- `scripts/audit-bot-codeql-coverage.sh` — the audit script.
- [GitHub Docs: About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) — `neutral` satisfies required checks.

## Schedule

Out-of-scope for #3545; deferred. Re-evaluate after the manual audit proves stable for ≥ 2 weeks.
