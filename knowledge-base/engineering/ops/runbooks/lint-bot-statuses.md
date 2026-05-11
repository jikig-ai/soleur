---
title: lint-bot-statuses CI job
audience: operator
on_page_for: scripts/lint-bot-synthetic-completeness.sh + scripts/lint-bot-synthetic-statuses.sh
issues: [3546, 3542, 2719]
threshold: none
last_updated: 2026-05-11
---

# `lint-bot-statuses` CI job

## Trigger

Read this runbook when:

- The `lint-bot-statuses` check is RED on a PR (it's a job inside [`.github/workflows/ci.yml`](../../../../.github/workflows/ci.yml), not a standalone workflow).
- You are adding a new entry to [`scripts/required-checks.txt`](../../../../scripts/required-checks.txt).
- You are adding a new `scheduled-*.yml` workflow that calls `gh pr create`.
- A second lint failure in the same area required reading the bash source to understand the diagnostic (the re-evaluation threshold for #3546).

## What this lint is (and isn't)

**Is:** a pre-merge gate that prevents bot PRs from being created in a state that would deadlock auto-merge. Specifically:

1. [`scripts/lint-bot-synthetic-statuses.sh`](../../../../scripts/lint-bot-synthetic-statuses.sh) rejects `[skip ci]` markers in any `scheduled-*.yml` workflow that calls `gh pr create`. `[skip ci]` suppresses the `test` Check Run, and a missing required check blocks auto-merge forever.
2. [`scripts/lint-bot-synthetic-completeness.sh`](../../../../scripts/lint-bot-synthetic-completeness.sh) verifies every `scheduled-*.yml` workflow whose shell `run:` block calls `gh pr create` also posts synthetic check-runs (`-f name=…` or `-f context=…`) for every entry in [`scripts/required-checks.txt`](../../../../scripts/required-checks.txt). Bot PRs authored by `GITHUB_TOKEN` do NOT trigger CI (GitHub's anti-loop guard), so without synthetic postings the required-check rules on the `CI Required` ruleset (#14145388) never go green.

**Is not:**

- A code-quality lint. It only checks the PR-creation surface, not runtime behavior.
- A check that bot PRs *actually* go green. If a bot workflow's `gh api ... check-runs` call returns non-2xx at runtime (token-scope regression, rate limit, API outage), the synthetic posting silently fails and auto-merge deadlocks. The lint does not detect this — see [`codeql-bot-coverage.md`](codeql-bot-coverage.md) §Trigger for the empirical-audit complement.
- A check on non-`scheduled-*.yml` workflows. The hardcoded `PATTERN="scheduled-*.yml"` scopes both scripts; a future `monthly-*.yml`, `hourly-*.yml`, or one-off `release-*.yml` is invisible to the lint. Either rename to a `scheduled-*` prefix or extend the `PATTERN`.
- A pre-commit hook. [`lefthook.yml`](../../../../lefthook.yml) does NOT invoke either script. Operators editing a `scheduled-*.yml` workflow can pre-flight locally with `bash scripts/lint-bot-synthetic-completeness.sh` + `bash scripts/lint-bot-synthetic-statuses.sh` — but the only enforced gate is the CI job.

## The as-built behavior

### `lint-bot-synthetic-statuses.sh`

Greps each `.github/workflows/scheduled-*.yml` file for `gh pr create`. If present and the file also contains the literal `[skip ci]` substring, the lint fails. Otherwise prints `ok: <file>`. Exit 0 on clean, 1 on any failure.

### `lint-bot-synthetic-completeness.sh`

Greps each `.github/workflows/scheduled-*.yml` file for `gh pr create`. For each match:

1. Loads required-check names from [`scripts/required-checks.txt`](../../../../scripts/required-checks.txt). Per line: strips trailing inline comments, strips one matched pair of outer double quotes, but **preserves spaces inside check names** (e.g., `skill-security-scan PR gate`).
2. Greps the workflow file for `-f name=<name>` OR `-f context=<name>` patterns covering each required check.
3. Reports any missing synthetics with the literal CI-log-grep-able form `FAIL: <file> is missing synthetic check-runs for: <names>`.

**App-token escape hatch.** Detection uses the `has_shell_pr_create` helper, which walks YAML indentation to determine whether `gh pr create` appears under a `run:` block. Anything outside a `run:` block (including `prompt:` blocks of `claude-code-action` steps, or future `with:` consumers) is treated as the App-token path — `app/claude` triggers real CI on the resulting PR, so synthetics are unnecessary.

## Required-checks config

[`scripts/required-checks.txt`](../../../../scripts/required-checks.txt) is the single source of truth for what synthetics every bot workflow must post. As of 2026-05-11 it contains:

```
test
dependency-review
e2e
skill-security-scan PR gate
cla-check
```

**`CodeQL` is intentionally absent.** The `CI Required` ruleset pins `CodeQL` to `integration_id: 57789` (`github-advanced-security`). A synthetic check-run posted by `github-actions[bot]` (`integration_id: 15368`) with `name=CodeQL` would NOT satisfy the ruleset — the GHAS integration_id is the load-bearing match condition. CodeQL default setup runs on every PR (including bot PRs) and concludes `neutral`, which satisfies the required check per GitHub Docs. See [`codeql-bot-coverage.md`](codeql-bot-coverage.md) for the empirical audit + the load-bearing comment block in [`scripts/required-checks.txt`](../../../../scripts/required-checks.txt) for the rationale.

**Adding a new required check requires THREE edits in one PR:**

1. [`scripts/required-checks.txt`](../../../../scripts/required-checks.txt) — add the check name on its own line (no quoting; spaces inside the name are preserved).
2. [`.github/actions/bot-pr-with-synthetic-checks/action.yml`](../../../../.github/actions/bot-pr-with-synthetic-checks/action.yml) — extend the `CHECK_NAMES` array so every composite-action consumer picks up the new synthetic automatically.
3. Update this runbook's "as of 2026-05-11" config block above.

Inline-pattern bot workflows (the 3 `scheduled-*.yml` files that don't use the composite action — see `codeql-bot-coverage.md` for the inventory) post synthetics directly. Each one must be edited to add the new `gh api ... check-runs -f name=<NEW>` block. The lint will fail-loud at PR time if any is missed.

## Drift triage

| Symptom | Failing script | Likely cause | Fix |
|---|---|---|---|
| `FAIL: <file> contains [skip ci]` | statuses | A `scheduled-*.yml` was edited to add `[skip ci]` to a commit message inside `gh pr create` | Remove `[skip ci]`. Bot PRs need CI (or synthetics) to satisfy the ruleset. |
| `FAIL: <file> is missing synthetic check-runs for: <names>` | completeness | A new required check was added to `required-checks.txt` but the bot workflow wasn't updated — OR — a new bot workflow was added without synthetics | Add `-f name=<check>` (or `-f context=<check>`) to a `gh api .../check-runs` call in the workflow's shell `run:` block. Use the composite action if possible (see "How to extend"). |
| `FAIL: config parser` / unexpected blank lines | completeness (parser) | A regression in the config loader (e.g., strip-all-whitespace bug fixed in PR #3543) — multi-word check names like `skill-security-scan PR gate` were collapsed to `skill-security-scanPRgate` | Verify `bash scripts/lint-bot-synthetic-completeness.sh` locally; if the lint passes but CI fails, suspect a parser regression. See learning `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`. |
| New bot workflow with shell `gh pr create` but no synthetics | completeness | A `scheduled-*.yml` author posted PR-creation logic before adding synthetic check-runs | Add the synthetic-posting block OR refactor to use [`.github/actions/bot-pr-with-synthetic-checks`](../../../../.github/actions/bot-pr-with-synthetic-checks/action.yml). |
| False-positive on a `claude-code-action` workflow | completeness | The `gh pr create` lives in a `prompt:` block (App-token path) but the heuristic mis-classified it as shell | Verify the call site: if the only `gh pr create` reference in the file is inside a `prompt:` block, the App token triggers real CI and the file is correctly exempt. If the heuristic still flags it, file a fix-script-detection issue. |

## How to extend

### Adding a new required check

1. Edit [`scripts/required-checks.txt`](../../../../scripts/required-checks.txt) — append the check name on its own line.
2. Edit [`.github/actions/bot-pr-with-synthetic-checks/action.yml`](../../../../.github/actions/bot-pr-with-synthetic-checks/action.yml) — extend the `CHECK_NAMES` array.
3. Update this runbook's "as of 2026-05-11" config block.
4. For each inline-pattern bot workflow (not using the composite action), edit the workflow's `run:` block to add a `gh api .../check-runs -f name=<NEW>` call.

Verify locally before pushing: `bash scripts/lint-bot-synthetic-completeness.sh`.

### Adding a new bot workflow

Prefer the composite action. Create `.github/workflows/scheduled-<feature>.yml` with:

```yaml
- uses: ./.github/actions/bot-pr-with-synthetic-checks
  with:
    branch: ci/<feature>-<date>
    title: "<feature>: <date>"
    body: "..."
```

The composite action handles synthetic posting for ALL required checks automatically. No `lint-bot-statuses` action required.

If you need inline synthetic posting (e.g., a `scheduled-*.yml` that has additional state-machine logic), follow the pattern in [`scheduled-content-publisher.yml`](../../../../.github/workflows/scheduled-content-publisher.yml) or [`scheduled-disk-io-24h-recheck.yml`](../../../../.github/workflows/scheduled-disk-io-24h-recheck.yml). Verify locally before pushing.

## Operator-debug commands

The `lint-bot-statuses` check is a JOB inside [`.github/workflows/ci.yml`](../../../../.github/workflows/ci.yml), not a standalone workflow file. To verify it ran green on `main`, query the `ci.yml` workflow and filter by job name:

```bash
gh run list --workflow=ci.yml --branch=main --limit=1 --json databaseId --jq '.[0].databaseId'
# 75347492121

gh run view 75347492121 --json jobs --jq '.jobs[] | select(.name == "lint-bot-statuses") | {name, status, conclusion}'
# {"conclusion":"success","name":"lint-bot-statuses","status":"completed"}
```

To re-run the failing lint locally against your branch:

```bash
bash scripts/lint-bot-synthetic-completeness.sh
bash scripts/lint-bot-synthetic-statuses.sh
```

Both scripts honor `WORKFLOW_DIR` and `CONFIG_FILE` env overrides for testing against alternate locations.

## Re-evaluation

Per #3546: re-evaluate this runbook's coverage after the **2nd** lint failure that required reading the bash source to understand. If the next operator hits a diagnostic this runbook does not cover, file a PR amending the runbook before triaging the underlying lint failure.

## Cross-references

- [`skill-security-scan-required-check.md`](skill-security-scan-required-check.md) — parent R15 runbook; references this gate.
- [`codeql-bot-coverage.md`](codeql-bot-coverage.md) — sibling audit; covers the empirical runtime-drift question this lint does NOT answer.
- [`ruleset-bypass-drift.md`](ruleset-bypass-drift.md) — sibling audit; covers `bypass_actors` on the same ruleset.
- [`.github/workflows/ci.yml`](../../../../.github/workflows/ci.yml) — the `lint-bot-statuses` job definition.
- [`.github/actions/bot-pr-with-synthetic-checks/action.yml`](../../../../.github/actions/bot-pr-with-synthetic-checks/action.yml) — composite action consumed by 5 of 8 bot workflows.
- [`scripts/required-checks.txt`](../../../../scripts/required-checks.txt) — source-of-truth check list.
- [`plugins/soleur/test/lint-bot-synthetic-statuses.test.sh`](../../../../plugins/soleur/test/lint-bot-synthetic-statuses.test.sh) — fixture-based test harness.
- Learning: `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md` — the most recent parser regression.

## Refs

- #3546 (this runbook)
- #3542 (parent R15 mitigation)
- #2719 (R15 origin)
- #826, #827, #842, #1014, #1468 (lint history)
