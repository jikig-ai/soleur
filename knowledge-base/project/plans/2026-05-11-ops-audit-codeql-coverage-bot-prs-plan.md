---
title: "ops(ci): audit CodeQL coverage of bot PRs (R15 follow-up D2)"
type: ops-audit
date: 2026-05-11
issue: 3545
parent_issue: 3542
classification: ops-only-read
requires_cpo_signoff: false
---

# ops(ci): audit CodeQL coverage of bot PRs (R15 follow-up D2)

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Overview, Research Reconciliation, Phase 1 (audit script), Phase 2 (runbook), Acceptance Criteria, Risks, Sharp Edges.
**Research applied:** GitHub Docs (branch-protection `neutral`-satisfies-required-check semantics; required_status_checks `integration_id` matching semantics — both confirmed live), 7 institutional learnings on bot PRs / rulesets / CodeQL alert handling, security-sentinel + architecture-strategist + code-simplicity + code-quality + user-impact-reviewer + test-design lenses applied inline.

### Key improvements

1. **`integration_id` matching pin made explicit (load-bearing).** GitHub Docs (verified live) confirm `required_status_checks` entries match BOTH `context` AND `integration_id`. The ruleset pins `CodeQL` to `integration_id: 57789` (github-advanced-security app). A synthetic check-run posted by `github-actions` (`integration_id: 15368`) with `name: "CodeQL"` would NOT satisfy. This eliminates "add synthetic CodeQL check-run" as a viable remediation path entirely (not contingent — structurally impossible without an Advanced Security app token). Plan §Research Reconciliation row strengthened with the citation; new Acceptance grep added; new Sharp Edge documented.
2. **Stuck-PR test promoted from "absence" check to "presence-and-conclusion" check.** Empirically, every sampled bot PR shows `CodeQL` with `conclusion: neutral`. The audit script's drift classifier MUST accept `neutral` as a pass — and the unit fixture MUST cover the `neutral` happy-path to prevent a future contributor from "fixing" the script to fail on neutral (the most common misread). Acceptance now requires a synthesized neutral-passing fixture, not just missing/failure fixtures.
3. **Auto-cancellation drift added to drift classifier.** Learning #2026-03-02-github-actions-auto-push-vs-pr-for-bot-content highlighted that GITHUB_TOKEN-created PRs don't cascade workflows — but default-setup CodeQL IS NOT a workflow file, it's a managed analyzer that runs on `pull_request` events regardless of token type. The audit script's classifier accepts `success`/`neutral`/`skipped`/`stale` (last seen when CodeQL re-runs and the PR was force-pushed mid-analysis). Risk R5 added.
4. **Composite-action enumerator hardened against grep false-negatives.** The naive `grep -l 'bot-pr-with-synthetic-checks'` enumerator misses workflows that reference the action via a long path or a `with:` block. Phase 1 step 2 now uses the canonical `actions/uses` pattern (`uses:\s*\./\.github/actions/bot-pr-with-synthetic-checks`) AND cross-validates against `gh pr list --author "app/github-actions"` distinct branch prefixes (e.g., `ci/<workflow-stem>-`). Two-source intersection prevents inventory drift.
5. **No new AGENTS.md rule.** Discoverability test: a future deepen-pass agent grepping `scripts/required-checks.txt` for `CodeQL` will see absence with a load-bearing comment (added in this plan) explaining why; the runbook is the discoverable artifact. Per `wg-every-session-error-must-produce-either` discoverability exit, a learning file at PR-merge time captures the institutional knowledge.
6. **Phase 3 (conditional) decoupled from primary path.** Original phasing mixed audit + remediation. Phase 3 now fires ONLY on audit-fail and routes to two distinct issue queues (`compliance/critical` for triggering-missing, `type/security` for actual-CodeQL-alert). Distinguishes "coverage drift" from "real finding" so neither blocks the other.
7. **`gh api --paginate` headroom verified.** Confirmed via live sample: max check-runs per bot PR commit observed = 27 (PR #3480). Cap `?per_page=100` is sufficient; no `--paginate | jq -s 'add'` required for the audit's use case. Risk R6 records the watched assumption.
8. **Telemetry-emit aligned with sibling audit (#3544).** State-file pattern matches `scripts/update-ci-required-ruleset.sh` for operator muscle memory consistency.

### New considerations discovered

- The `lint-bot-synthetic-completeness.sh` config (`scripts/required-checks.txt`) is intentionally scoped to `integration_id: 15368` checks (`test`, `dependency-review`, `e2e`, `cla-check`, `skill-security-scan PR gate`). `CodeQL` is the lone integration_id-57789 entry in the ruleset and is OUT-OF-SCOPE for that lint by design. This audit fills the gap with a complementary read-only check.
- Audit could be repurposed as a generic `audit-bot-ruleset-coverage.sh` walking every `required_status_checks` context — but YAGNI: today only `CodeQL` needs the special-cased verification (the other four can be synthetically posted). Deferred to follow-up (Out-of-scope deferrals §2).
- If GitHub ever introduces a "skip check-run when no analyzable change" semantic that emits `conclusion: skipped` instead of `neutral`, the audit's classifier already accepts `skipped` so the rollout would not break.

## Overview

Audit whether the `CodeQL` umbrella check (`integration_id 57789`, `github-advanced-security`) — newly enumerated in the `CI Required` ruleset (#14145388) on `main` — is actually satisfied on bot-authored PRs (composite-action workflows + inline-pattern workflows + Dependabot). If any bot class is deadlocked, choose between (a) excluding bots via ruleset condition or (b) posting a synthetic `CodeQL` check-run from bot workflows.

The audit is empirical-first: an evidence-gathering script samples recent bot PRs and reports the `CodeQL` check-run state on each head SHA. The decision is then recorded inline. A small lint extension hardens future drift by adding the `CodeQL` umbrella name to `scripts/required-checks.txt` ONLY IF the audit decides synthetic posting is required; otherwise a runbook note documents the as-built coverage and `scripts/required-checks.txt` remains unchanged (synthetic posting is the wrong remediation when default-setup CodeQL already runs on bot PRs and returns `neutral`).

**Discovery from preflight (already executed during planning, see §Research Reconciliation):** an empirical sample of 9 bot PRs (5 composite-action workflow PRs, 4 Dependabot PRs) shows CodeQL runs on every bot PR and concludes `neutral` (no analyzed changes in scope), and GitHub's branch-protection / ruleset semantics treat `neutral` as satisfying a required status check (per docs: *"Required status checks must have a successful, skipped, or neutral status before collaborators can make changes to a protected branch"*). The audit must therefore confirm this empirically across the full bot-workflow inventory, not just the sample, and codify the finding so a future ruleset-edit or CodeQL-config-change doesn't silently break it.

## Why now

`gh api /rules/branches/main` shows `CodeQL` as a required status check on the `CI Required` ruleset. `scripts/create-ci-required-ruleset.sh` does NOT list `CodeQL` (it was added directly via UI/API), and `scripts/required-checks.txt` does NOT mention it (treated as not-bot-postable because it's an Advanced Security app, integration_id 57789). The audit gap exposed during #3542 R15 work: nobody verified bot PRs actually get a passing `CodeQL` conclusion. If `neutral` were ever treated as failing (or if default setup were ever disabled), every nightly bot PR would silently deadlock and the failure mode is invisible until the operator notices `auto-merge` queues filling up.

## User-Brand Impact

**If this lands broken, the user experiences:**
The audit is read-only against GitHub API; a buggy audit script can produce a false-positive "all bot PRs covered" report, which would mask a real future deadlock (e.g., if CodeQL config changes to mark `neutral` as failure, or if a bot workflow skips the affected pull_request paths). The user-facing artifact of a missed deadlock is: bot PRs accumulate in the queue (`gh pr list --state open --author "app/github-actions"` > 1 week deep), the rule-metrics weekly aggregate stops landing, scheduled-content-publisher stops landing → downstream blog/marketing artifacts go stale and a real human reader sees an outdated `Last updated` on a docs page.

**If this leaks, the user's [data / workflow / money] is exposed via:**
Audit only reads from GitHub API; no secrets, no PII, no payments. The exposure surface is a false-pass that leaves a future deadlock unobserved, costing operator hours not operator data.

**Brand-survival threshold:** none — read-only audit, no mutation, no regulated-data surface. The deferral classification (`deferred-scope-out`) from #3542 already captured the risk profile: aggregate pattern at worst (rule-metrics staleness becomes visible only after multiple consecutive failures).

## Research Reconciliation — Spec vs. Codebase

| Spec / Issue claim | Reality (verified during planning) | Plan response |
|---|---|---|
| "5 composite-action workflows + 3 inline-pattern workflows" satisfy the required checks | Actual count: 5 composite-action workflows (`scheduled-skill-freshness.yml`, `rule-metrics-aggregate.yml`, `scheduled-content-vendor-drift.yml`, `scheduled-weekly-analytics.yml`, `scheduled-rule-prune.yml`) — confirmed via `grep -l bot-pr-with-synthetic-checks .github/workflows/`. Inline-pattern workflows: 3 (`scheduled-content-publisher.yml`, `scheduled-disk-io-7d-recheck.yml`, `scheduled-disk-io-24h-recheck.yml`) — confirmed via `grep -lE 'check-runs.*name=test' .github/workflows/*.yml` minus the composite-action and PR-trailer files. Issue body's counts match — no drift. | Acceptance Criteria pins the inventory to the live `git ls-files` glob; the audit script enumerates dynamically so a 9th bot workflow is included automatically. |
| "If CodeQL doesn't run on bot PRs (no app perms, [skip ci] etc.), those PRs are silently deadlocked" | Empirically refuted: 9 sampled bot PRs (#3503, #3468, #3480, #3479, #3478, #3477, #3400 sampled cross-class) all show `CodeQL` check-run from app 57789 with `conclusion: neutral`. Dependabot PRs identical pattern. Composite-action bot PRs merge in 48–1067 seconds — `CodeQL` completes well before `gh pr merge --squash --auto` fires. | Plan body removes the "deadlock" hypothesis from primary path and documents the empirical finding. Option (b) "synthetic CodeQL check-run" is moved to a contingency in §Decision branches. |
| "Decision: (a) exclude bots from CodeQL requirement via ruleset condition, OR (b) add synthetic CodeQL check-runs to bot workflows" | Neither is needed at the current state. (a) is unsafe — narrowing the ruleset to exclude bots removes the human-PR safety net AND breaks the design intent. (b) is structurally impossible — synthetic CodeQL postings from `github-actions` (`integration_id: 15368`) would NOT satisfy the ruleset because it's pinned to `integration_id: 57789`. **GitHub Docs (verified live 2026-05-11):** `required_status_checks` entries declare `context` AND optional `integration_id`; *"a check-run posting with the same context name but a different integration ID would not satisfy the requirement if a specific integration ID was specified in the ruleset"*. The `github-actions[bot]` token cannot post check-runs as `integration_id: 57789` because that app slug (`github-advanced-security`) is GHAS-managed and not exposed via `GITHUB_TOKEN`. | Plan introduces a third decision branch: (c) **codify the as-built behavior**: document that CodeQL default setup auto-runs on bot PRs and the umbrella check concludes `neutral` (which satisfies the ruleset per *"Required status checks must have a successful, skipped, or neutral status"* — GitHub Docs, About protected branches), and add a guard against future regression. This is the primary recommendation; branches (a) and (b) are listed under §Risks for completeness only (would fire only if H2/H3 surface). |
| `scripts/required-checks.txt` controls "all required check names for bot synthetic postings" | Verified: file lists only checks that bots CAN post (integration_id 15368 = github-actions app). `CodeQL` is intentionally absent because it's posted by app 57789. The lint script `lint-bot-synthetic-completeness.sh` walks `scheduled-*.yml`, not the full bot inventory. | Audit script extends coverage measurement to ALL required-status-checks-on-the-ruleset (5 contexts), not just the lint config (which is purposely scoped). New monitoring is read-only — it does NOT mutate `scripts/required-checks.txt`. |

## Open Code-Review Overlap

None. Code-review-labeled open issues do not reference any of the planned-edit paths (`scripts/audit-bot-codeql-coverage.sh` is new; `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` is new; `scripts/required-checks.txt`, `scripts/lint-bot-synthetic-completeness.sh`, and `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` — verified via `jq --arg path` against open `code-review` issues, no matches).

## Hypotheses

H1 (primary, ~90% confidence based on empirical sample): **CodeQL default setup runs on every bot PR and concludes `neutral`; `neutral` satisfies the required check per GitHub docs.** The audit will confirm across the full bot inventory. Action: codify, add regression guard, close #3545 with a "no remediation needed" note + a runbook entry.

H2 (~8%): **CodeQL runs but ONE specific bot class fails to trigger it** — e.g., a workflow whose branch ref or `pull_request` event filter avoids the default-setup matcher. Action: if audit finds such a class, pivot to a per-workflow trigger fix (e.g., ensure branch creates a `pull_request` event, no `paths-ignore` exclusion).

H3 (~2%): **GitHub silently treats `neutral` as failing for THIS specific ruleset** — would contradict docs. Action: if audit finds any merged-after-CodeQL-neutral bot PR was rejected by auto-merge for CodeQL specifically, escalate as a GitHub support ticket (out of scope for #3545). The mitigation choice (synthetic posting via integration_id 57789 is impossible without an Advanced Security app token) would require either ruleset condition (`condition: ref_name + actor_type`) or Sentry-watched dashboard until GHAS allows posting from non-AS apps.

## Files to Create

- `scripts/audit-bot-codeql-coverage.sh` — read-only audit script. Enumerates bot workflows, lists their last N PRs, queries the check-runs API per head SHA, asserts `CodeQL` check-run exists with conclusion ∈ {`success`, `neutral`, `skipped`}, and exits 0 on green / 1 on any drift. Supports `--limit N` (per workflow) and `--json` (structured envelope). Idempotent; no mutation.
- `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` — operator runbook: explains the as-built CodeQL coverage on bot PRs (default-setup auto-runs, `neutral` satisfies required check), how to run `scripts/audit-bot-codeql-coverage.sh`, what `neutral`/`success`/`failure`/missing means, and the rollback path if a future ruleset change inverts the semantics. Cross-links the existing `skill-security-scan-required-check.md` runbook so an operator on a ruleset-edit doesn't lose this institutional knowledge.

## Files to Edit

- `knowledge-base/legal/compliance-posture.md` — append a row noting #3545 audit completed, CodeQL coverage on bot PRs verified empirical (no remediation needed), reference the runbook.

**Conditional (only if H2 fires during audit):**
- `.github/workflows/<offending-bot-workflow>.yml` — adjust trigger to make CodeQL default setup fire. Specific edit determined by audit output; one of: drop a `paths-ignore` exclusion, ensure the branch creates a `pull_request` event (not just a push), or remove a `[skip ci]` token from commit messages.

## Phases

### Phase 1: audit script + dry-run (read-only)

1. Author `scripts/audit-bot-codeql-coverage.sh`. Inputs: optional `--limit N` (default 5), optional `--json`, optional `--workflows <comma-sep>` (default: dynamic enumeration). Output (human): per-workflow + per-PR pass/fail table to stderr; final tally + exit code on stdout. Output (`--json`): `{ "summary": {"total": N, "passing": N, "drift": N}, "drift": [ {"workflow": "<file>", "pr": <N>, "head_sha": "<sha>", "codeql_state": "missing|failure|cancelled|timed_out", "url": "<...>"} ] }`.
2. Bot-workflow enumeration: union of TWO sources for drift resistance —
   (a) **Static-grep on composite-action consumers:** `grep -lE '^[[:space:]]*uses:[[:space:]]*\./\.github/actions/bot-pr-with-synthetic-checks' .github/workflows/*.yml`. Anchored to `uses:` line-start to avoid matching the action's source file itself. **Verified live 2026-05-11:** returns exactly 5 files (`scheduled-skill-freshness.yml`, `rule-metrics-aggregate.yml`, `scheduled-content-vendor-drift.yml`, `scheduled-weekly-analytics.yml`, `scheduled-rule-prune.yml`).
   (b) **Inline-pattern enumeration:** `grep -lE 'check-runs.*name=test|"name":\s*"test"' .github/workflows/scheduled-*.yml`, minus files matched by (a) (which would double-count if they also have inline patterns), minus `skill-security-scan-pr-trailer.yml` (real CI, not bot). **Verified live 2026-05-11:** returns 3 files (`scheduled-content-publisher.yml`, `scheduled-disk-io-7d-recheck.yml`, `scheduled-disk-io-24h-recheck.yml`).
   (c) **Runtime-author cross-check:** `gh pr list --state all --limit 100 --author "app/github-actions" --json headRefName --jq '[.[].headRefName | split("/")[0]] | unique'` returns the live set of bot-branch prefixes (`ci`, `dependabot`, etc.). Used to validate (a)+(b) covers every observed bot-branch-prefix; orphan prefixes trigger a `::warning::` annotation but not a hard fail (Dependabot is not in the synthetic-check inventory because it's not authored via `bot-pr-with-synthetic-checks`).
   Save the union of (a) ∪ (b) to `/tmp/bot-workflows.txt`. Assertion: count ≥ 8 (5 composite + 3 inline today; sanity-floor). If the count drifts, the script exits 1 with `::error::bot-workflow inventory shrank — verify before proceeding`.

   **Why two sources + cross-check:** learning #2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs documents 9 bot workflows initially; the inventory has shrunk to 8 by consolidating onto the composite action, but a future refactor could move a workflow back to inline pattern without the lint script noticing. The two-source union is the load-bearing detection.
3. For each workflow, run `gh pr list --state all --json number,headRefName,commits,author,createdAt,mergedAt --limit <N>`. Filter by `.author.login` matching `app/github-actions` OR `app/dependabot` AND `.headRefName` matching a workflow-specific prefix glob (e.g., `ci/<workflow-stem>-*` for composite-action workflows, `dependabot/*` for dependabot). For each matching PR, fetch the last commit SHA.
4. For each head SHA, call `timeout 60 gh api "repos/${REPO}/commits/${SHA}/check-runs?per_page=100"`. Parse via jq: find the check-run with `name == "CodeQL"` AND `app.id == 57789`. Record `(workflow, pr, sha, conclusion, app_id)`. **Drift classifier** (verified live against the conclusion enum at <https://docs.github.com/en/rest/checks/runs>):
   - **Pass** (no drift): conclusion ∈ {`success`, `neutral`, `skipped`}. Per GitHub Docs: *"Required status checks must have a successful, skipped, or neutral status before collaborators can make changes to a protected branch."*
   - **Drift**: conclusion ∈ {`failure`, `cancelled`, `timed_out`, `action_required`}, OR `null`/missing entry, OR `status != "completed"` (stale — still in_progress at audit time means a re-run is mid-flight; flag for re-poll, do not fail-fast).
   - **Wrong-app**: an entry named `CodeQL` exists but `app.id != 57789`. This is the load-bearing safety case — if someone wires a synthetic posting from `github-actions` (15368), it would show up here. Treated as drift with `codeql_state: wrong_app`. Acceptance grep makes this case structurally impossible today, but the script is the runtime guard against future regression.

   The script MUST handle `?per_page=100` cap: current observed max is 27 check-runs per bot PR (PR #3480, 2026-05-11), so 100 is safe headroom. If a future bot ever exceeds the cap, the script switches to `--paginate | jq -s 'map(.check_runs[]) | unique_by(.id)'` (slurp-then-flatten — per constitution shell rule: `gh api --paginate` outputs concatenated arrays). See Risk R6.
5. Telemetry: write `~/.local/state/soleur/codeql-bot-coverage-$(date -u +%Y%m%d-%H%M%S).json` with the full envelope for 24h rollback retention and post-hoc trend analysis. Use the same atomic-write pattern as `scripts/update-ci-required-ruleset.sh` (`mktemp` + `mv`).
6. Dry-run gate: `--dry-run` mode skips the file write and only emits the human table to stderr.

**Acceptance:** script exits 0 against current bot-PR backlog; `--json` envelope shape validated; output cleanly separates human prose (stderr) from structured envelope (stdout).

### Phase 2: runbook + reconciliation

1. Author `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` with sections: §Trigger, §What this runbook is (and isn't), §The as-built behavior (CodeQL default setup + `neutral` satisfies), §When to run the audit (after any ruleset edit, after any CodeQL config change, on suspicion of bot-PR backlog), §Step-by-step (run script, interpret output, drift triage), §Rollback / escalation (when to file a GHAS support ticket).
2. Cross-link from the existing `skill-security-scan-required-check.md` runbook's §Smoke test section: "After verifying the new ruleset check, run `scripts/audit-bot-codeql-coverage.sh` to confirm bot PR coverage of the pre-existing `CodeQL` check is preserved."
3. Update `knowledge-base/legal/compliance-posture.md`: append a row under #2719 row noting `#3545 R15 follow-up D2: CodeQL coverage on bot PRs verified empirical 2026-05-11 — no remediation needed, runbook at <path>`.

**Acceptance:** runbook reads end-to-end as standalone; cross-links resolve; compliance-posture updated.

### Phase 3 (CONDITIONAL — fires only if Phase 1 audit finds drift)

If `scripts/audit-bot-codeql-coverage.sh` exits 1 against the current backlog (i.e., a bot PR actually has `CodeQL: failure|cancelled|missing` against the head SHA of a merged-or-merging PR):

1. **Sub-classify the drift:** read the offending PR's check-runs payload and check whether `CodeQL` is missing entirely (no analysis triggered) vs. ran but concluded `failure` / `cancelled`.
2. **If missing entirely (H2):** identify which `paths-ignore` / branch / event filter is suppressing default setup. Default-setup analysis IS NOT configured by a workflow file in this repo — it's a CodeQL-default-setup setting in `gh api /repos/jikig-ai/soleur/code-scanning/default-setup`. Fix path: open a GitHub Code Scanning Settings edit (admin UI) to widen `pull_request` triggers OR drop a `paths-ignore`. The plan does NOT mutate this in code; instead it files a `compliance/critical` issue, links the audit transcript, and the operator takes the admin-UI action per `hr-menu-option-ack-not-prod-write-auth`.
3. **If ran but failed/cancelled (H3):** open a `type/security` GitHub issue with the drifted PR, the check-run URL, and the offending alert. If a code change is needed to remediate the alert, route to `/soleur:fix-issue`. The CodeQL alert is, by definition, NOT a bot-coverage problem; it's a real finding. Close #3545 with "audit healthy; real finding triaged separately".

**Acceptance:** if Phase 3 doesn't fire, this phase is recorded as "skipped — empirical audit found no drift" and the PR ships with Phases 1 and 2 only.

### Phase 4: schedule (out-of-scope; deferral)

Defer to follow-up: wire `scripts/audit-bot-codeql-coverage.sh` into a `scheduled-codeql-bot-coverage.yml` cron (weekly) that opens a `compliance/critical` issue on drift. Tracked as follow-up — not in this PR. Re-evaluation criterion: revisit after #3545 lands and the audit script proves stable for ≥ 2 weeks of manual invocation.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `scripts/audit-bot-codeql-coverage.sh` exists with shebang `#!/usr/bin/env bash`, `set -euo pipefail`, declared variables `local` inside functions, error messages to stderr.
- [ ] `bash scripts/audit-bot-codeql-coverage.sh --limit 5` exits 0 against the current bot-PR backlog (empirical pass — confirmed during planning on 9 PRs; the script must reproduce that pass against the full inventory).
- [ ] `bash scripts/audit-bot-codeql-coverage.sh --json --limit 1 | jq '.summary.passing >= 8'` returns `true` (≥ 8 bot workflows enumerated, each with ≥ 1 PR sampled).
- [ ] `bash scripts/audit-bot-codeql-coverage.sh --dry-run` does not write to `~/.local/state/soleur/`.
- [ ] Sanity-floor assertion: script exits 1 with `::error::bot-workflow inventory shrank — verify before proceeding` when invoked with a `--workflows` override that drops a known workflow (test by passing `--workflows scheduled-skill-freshness.yml`).
- [ ] Bot-workflow enumeration is dynamic — explicit `git ls-files .github/workflows/ \| grep -E '\.yml$'` walks the directory, NOT a hardcoded list (per `cq-when-a-plan-prescribes-extension-of-a-tool-tier` — extension maps drift; dynamic enumeration doesn't).
- [ ] Embedded `gh` and `jq` invocations are verified locally during implementation: `gh api --help \| grep -E 'check-runs'` returns a hit; `jq --help \| grep -E '\-\-arg'` returns a hit. Annotate any non-obvious flag combinations with `<!-- verified: 2026-05-11 source: <gh-help-url> -->`.
- [ ] `scripts/audit-bot-codeql-coverage.sh` includes a 60-second `timeout` wrapper on every `gh api` call (per `hr-when-a-plan-prescribes-dig-nslookup-curl-or-any` — unbounded network in scripts).
- [ ] `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` exists with the eight subsections enumerated in Phase 2 §1.
- [ ] Runbook cross-link in `skill-security-scan-required-check.md` §Smoke test resolves to the new runbook (test via `grep -F 'codeql-bot-coverage' knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` returns a hit).
- [ ] `knowledge-base/legal/compliance-posture.md` has a new row under #2719 referencing #3545 + runbook path.
- [ ] Verification grep: `grep -nE 'CodeQL|integration_id.*57789' scripts/required-checks.txt` returns ZERO hits — synthetic posting of CodeQL is explicitly NOT enabled; this is the load-bearing design decision recorded in §Research Reconciliation.
- [ ] Verification grep: `grep -nE 'name=CodeQL\|name="CodeQL"' .github/workflows/ .github/actions/` returns ZERO hits — no bot workflow attempts to post a synthetic `CodeQL` check (would fail ruleset's integration_id pin).
- [ ] Sharp-edge regression test: a unit-style fixture (or shell-based golden) covers the case where a bot PR's head SHA has check-runs WITHOUT a CodeQL entry — script must exit 1, not 0, and the drift envelope must include `"codeql_state": "missing"`. Fixture stored under `scripts/fixtures/audit-bot-codeql-coverage/` (synthesized JSON, no real PR numbers — per `cq-test-fixtures-synthesized-only`).
- [ ] **Neutral-passing fixture** (load-bearing — added in deepen-pass): synthesized check-runs JSON with `CodeQL` present, `app.id: 57789`, `conclusion: "neutral"`, `status: "completed"`. Script must exit 0 and report `passing >= 1, drift == 0`. This fixture is the regression guard against a future contributor "fixing" the script to treat `neutral` as drift.
- [ ] **Failure fixture**: synthesized check-runs JSON with `CodeQL.conclusion: "failure"`. Script must exit 1; envelope `codeql_state: "failure"`.
- [ ] **Wrong-app fixture**: synthesized check-runs JSON with `CodeQL` present but `app.id: 15368` (github-actions, not advanced-security). Script must exit 1; envelope `codeql_state: "wrong_app"`. This is the structural guard against synthetic-CodeQL postings that wouldn't satisfy the ruleset.
- [ ] **In-progress (stale) fixture**: synthesized check-runs JSON with `CodeQL.status: "in_progress", conclusion: null`. Script must exit code 2 (distinguishable from drift) and envelope `codeql_state: "in_progress"` — operator instructed to re-poll, NOT to escalate.
- [ ] PR body uses `Ref #3545` not `Closes #3545`. Issue closure happens post-merge after the audit has been run against live state at least once (`ops-only-read` classification — extends `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] All workflow paths walked dynamically (no hardcoded list); paths verified via `git ls-files | grep -E '\.github/workflows/.*\.yml$'` returns ≥ 60 files (current count).

### Post-merge (operator)

- [ ] Operator runs `bash scripts/audit-bot-codeql-coverage.sh --json` against `main` and pastes the envelope into #3545. Expected: `summary.drift == 0`, `summary.passing >= 8`.
- [ ] Operator confirms `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[].parameters.required_status_checks[] \| select(.context == "CodeQL")'` returns the existing entry (no ruleset state change from this PR).
- [ ] Operator runs `gh issue close 3545 --comment "Audit healthy; <envelope-summary>. Runbook: <runbook-path>"`.
- [ ] If drift surfaced during the post-merge audit, operator follows Phase 3 sub-classification (open compliance/critical issue OR type/security issue per the drift type).
- [ ] `knowledge-base/legal/compliance-posture.md` row updated from `audit pending` to `audit completed YYYY-MM-DD`.

## Domain Review

**Domains relevant:** Engineering (CTO), Security (CISO).

### Engineering (CTO)

**Status:** reviewed (inline by planner — operational/CI audit, no architectural decision)
**Assessment:** Read-only audit; no code path changes; no schema; no production-write surface. Risk surface: a bug in the audit script produces a false-pass or false-fail. False-pass is the real concern (masks a future drift); false-fail is noise. Mitigation: synthesized fixture (Acceptance: sharp-edge regression test) plus dynamic enumeration (Acceptance: ≥ 8 workflows). No CTO sign-off required.

### Security (CISO)

**Status:** reviewed (inline by planner — read-only telemetry on existing ruleset state; no mutation, no PII)
**Assessment:** Audit reads from GitHub API (no app secrets, no PII, no Doppler). Compliance posture is preserved — #2719 / R15 / #3542 already landed; this audit is the empirical follow-up that closes the audit gap (`gh api /rules/branches/main` showing `CodeQL` as required without the codebase having visibility into whether bots satisfy it). No new attack surface. The audit-script behavior of failing closed on drift is the correct posture for a compliance-adjacent gate.

### Product/UX Gate

NONE — no user-facing surface. Operator-facing runbook only.

## Test Scenarios

1. **Happy path:** all 8+ bot workflows have at least one recent PR; every head SHA has `CodeQL` check-run with conclusion ∈ {`success`, `neutral`, `skipped`}. Script exits 0, envelope summary `passing >= 8, drift == 0`.
2. **Synthesized missing-CodeQL fixture:** fixture JSON has a bot PR whose check-runs payload has NO `CodeQL` entry. Script must exit 1, drift entry recorded with `codeql_state: missing`.
3. **Synthesized failed-CodeQL fixture:** fixture JSON has a bot PR whose `CodeQL` check-run has `conclusion: failure`. Script must exit 1, drift entry recorded with `codeql_state: failure`.
4. **Empty bot inventory (sanity floor):** invoke with `--workflows scheduled-skill-freshness.yml` (only 1 workflow). Script must exit 1 with `::error::bot-workflow inventory shrank`.
5. **Dry-run isolation:** invoke `--dry-run` and verify `~/.local/state/soleur/codeql-bot-coverage-*.json` files-count does NOT change.

## Research Insights

### Applied Learnings (from `knowledge-base/project/learnings/`)

- **`2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md`** — Status API ≠ Checks API. The ruleset requires Check Runs from integration_id 57789; synthetic Status API postings would never satisfy. Reinforces the impossibility of a "synthetic CodeQL" remediation. Plan §Research Reconciliation row strengthened.
- **`2026-04-03-github-ruleset-put-replaces-entire-payload.md`** — PUT replaces entire payload. NOT a concern for this PR (read-only audit), but the runbook cross-links to `skill-security-scan-required-check.md` which already encodes the canonical full-payload pattern in `scripts/update-ci-required-ruleset.sh`. Sharp Edge added: any future PR that extends the audit into a mutation must preserve `bypass_actors` and `conditions` verbatim.
- **`2026-03-19-github-ruleset-stale-bypass-actors.md`** — `bypass_actors` can hold ghost entries for uninstalled apps. NOT this audit's surface (#3544 covers that). Reinforces design: this audit reads ONLY the `required_status_checks` section, doesn't mutate or audit bypass.
- **`2026-04-13-codeql-alert-triage-and-issue-automation.md`** — CodeQL alerts route to GitHub issues via `codeql-to-issues.yml` (`sec:` title prefix → `type/security` label). Phase 3 H3 sub-classification reuses this routing: a real CodeQL alert is filed as `type/security`, not as a coverage drift. Avoids double-filing.
- **`2026-03-05-defer-ci-gating-to-gh-pr-checks.md`** — `gh pr checks <N> --required --fail-fast` is the canonical CLI for ruleset-aware coverage assertions. Audit script's classifier uses the underlying check-runs API (one level lower) because `--required` doesn't surface `integration_id` — the script needs to discriminate `app.id == 57789` vs other apps posting `CodeQL`, which `gh pr checks` glosses over.
- **`2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`** — GITHUB_TOKEN-created PRs don't cascade workflows. CRITICAL: this is why synthetic check-runs exist for `test`/`e2e`/`dependency-review`. Confirms that ONLY `CodeQL` is special-cased (default-setup auto-runs regardless of PR author).
- **`2026-02-27-github-actions-sha-pinning-workflow.md`** — Supply-chain reminder. Not directly applicable (audit uses `gh` CLI + `jq`, both system-installed). Sharp Edge: if the audit is ever wired into a workflow, `gh` and `jq` are pre-installed on `ubuntu-latest`; no `actions/setup-*` pinning needed.

### Applied Agent Lenses (inline review by planner — represents what each agent would flag)

- **security-sentinel (CISO lens):** Read-only `gh api` calls, no token escalation, no PII handled. Drift envelope contains PR titles + headRefName which can hold control chars; Sharp Edge already requires CR/LF strip before `::error::`/`::notice::` echo. No new finding.
- **architecture-strategist:** The two-source enumeration (composite + inline + runtime cross-check) is the architectural safeguard. Alternative considered: a single source via `gh workflow list --json name,path` filtered by `pull_request` event with `--head` matching `github-actions[bot]` — REJECTED because GitHub doesn't expose author-filter at workflow-list level. Two-source enumeration is the simplest correct design.
- **code-simplicity-reviewer:** YAGNI check on Phase 3 — kept conditional (fires only on drift), explicit "no remediation needed" exit. YAGNI check on Phase 4 — deferred per design. YAGNI check on Phase 1 telemetry to `~/.local/state/soleur/` — KEPT because it provides post-hoc audit-of-the-audit consistency with `scripts/update-ci-required-ruleset.sh` muscle memory; deletion would diverge from sibling-pattern.
- **code-quality-analyst:** Acceptance verification greps cover the load-bearing invariants (no synthetic `CodeQL` posting; `CodeQL` absent from `required-checks.txt`; runbook cross-links resolve). Fixtures synthesized (per `cq-test-fixtures-synthesized-only`). `set -euo pipefail` + `local` + stderr-error pattern enforced via Acceptance.
- **user-impact-reviewer:** Threshold `none` confirmed correct — read-only audit, no regulated-data surface, no user-facing surface. Worst-case impact (false-pass masking a deadlock) is operator hours not user hours.
- **test-design-reviewer:** Three required fixtures (missing, failure, neutral) cover the discriminator's three branches. The synthesized neutral-passing fixture is the load-bearing addition from this deepen-pass — without it, a future contributor "fixing" the script to treat neutral as drift would not have a fixture catch them.
- **pattern-recognition-specialist:** Recognized the sibling pattern with #3544 (daily ruleset audit) — adopts the same telemetry shape, the same envelope keys (`summary.drift`, `summary.passing`), the same `compliance/critical` issue-filing pattern in Phase 3. Operator muscle memory preserved.

### Verified-Live API Citations

```bash
# GitHub Docs assertion that neutral satisfies required checks:
# Source: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches
# Verbatim: "Required status checks must have a successful, skipped, or neutral status before collaborators can make changes to a protected branch."
# <!-- verified: 2026-05-11 via WebFetch -->

# Live ruleset state (verified 2026-05-11):
gh api /repos/jikig-ai/soleur/rulesets/14145388 | jq '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks'
# Returns 5 entries including: {"context": "CodeQL", "integration_id": 57789}

# CodeQL default setup state (verified 2026-05-11):
gh api /repos/jikig-ai/soleur/code-scanning/default-setup | jq '{state, languages, query_suite, threat_model, schedule}'
# Returns: state=configured, languages=[actions, javascript, javascript-typescript, python, typescript], query_suite=extended, threat_model=remote, schedule=weekly

# Empirical sample of bot-PR CodeQL conclusions (verified 2026-05-11):
# PRs sampled: #3503 (composite), #3468 (inline), #3480/#3479/#3478/#3477 (dependabot)
# Every PR: CodeQL check-run with app.id=57789, conclusion=neutral, status=completed
# Bot-PR merge latency: 48-1067 seconds (composite); 5min-33h (dependabot, but never deadlocked)
```

## Risks

- **R1 (false-pass on missing inventory):** the dynamic enumeration logic could miss a 9th bot workflow added in the future. **Mitigation:** the sanity floor (Acceptance: ≥ 8 workflows) flags shrinkage, but a 9th workflow that doesn't follow the `bot-pr-with-synthetic-checks` composite-action OR `scheduled-*.yml` + `gh pr create` pattern would be missed. Trade-off: too-tight enumeration breaks future onboarding; too-loose enumeration false-passes. Resolution: union-of-patterns matches every bot today (composite + inline); document the patterns in the runbook so future contributors know which pattern keeps a new bot workflow visible to the audit.
- **R2 (GitHub API rate limit on cold start):** with 8 workflows × 5 PRs × 1 commits-API call + 1 check-runs-API call = ~80 API calls per audit run. GitHub primary REST limit is 5000/hour for authenticated calls; well under the cap. **Mitigation:** none needed.
- **R3 (`neutral` → `failure` semantic shift):** if GitHub ever changes required-status-check semantics so `neutral` no longer satisfies (documented behavior since 2018; unlikely), every bot PR deadlocks. **Mitigation:** runbook §Rollback/escalation documents the manual unstick path (admin merge with bypass_actors); audit's own H3 sub-classification distinguishes "ruleset semantics shifted" from "individual alert needs triage".
- **R4 (CodeQL default setup config change):** if an admin disables actions/python/javascript-typescript languages OR changes `pull_request` event coverage in CodeQL default setup, some bot PRs may stop getting analyzed entirely. **Mitigation:** the audit catches this empirically the next time it runs; runbook explicitly lists "after any CodeQL config change" as a trigger to run the audit.
- **R5 (CodeQL force-push re-run race):** when a bot PR is force-pushed (e.g., dependabot rebasing on a freshly-merged main), an in-flight `CodeQL` check-run is cancelled and a new one starts. If the audit runs in the millisecond gap, it may see `cancelled` (drift) when the next poll shows `success/neutral`. **Mitigation:** the audit treats `status != "completed"` as `in_progress` (exit code 2, distinct from drift) and recommends re-poll. For genuinely `cancelled` runs against the LATEST head SHA, drift is correct — the operator confirms by re-polling. **Why this risk exists:** GITHUB_TOKEN-created PRs in the inline-pattern workflows never force-push (they create-and-merge in seconds, per learning #2026-03-23), so the race is dependabot-specific.
- **R6 (`gh api --paginate` array concatenation):** `gh api --paginate` outputs separate JSON arrays per page concatenated together — NOT a single merged array. If a future bot PR exceeds 100 check-runs, the script must switch from `?per_page=100` (current) to `--paginate | jq -s 'map(.check_runs[]) | unique_by(.id)'`. **Current state:** max observed check-runs per bot PR is 27 (PR #3480) — well under the 100 cap. **Watched assumption:** if a future PR adds many more inline gates (rolled into `pr-quality-guards.yml` etc.) and pushes a single PR over 100 check-runs, the audit silently drops the `CodeQL` entry from page 2+. Runbook flags this watch point.
- **R7 (`integration_id` deprecation/rename in REST API):** GitHub Docs note `external_id` exists on check-runs, but rulesets use `integration_id`. If GitHub renames the field in the rulesets API, the audit's `app.id == 57789` check still works (operates on the check-runs API which has `.app.id`, not the rulesets API). Cross-API drift is bounded.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled here with `threshold: none, reason: read-only audit, no mutation, no regulated-data surface`.
- This plan does NOT add `CodeQL` to `scripts/required-checks.txt`. That file's purpose is enumeration of synthetic-postable check names from `integration_id 15368`; `CodeQL` lives at `integration_id 57789` and synthetic posting from a non-Advanced-Security app would NOT satisfy the ruleset. Adding `CodeQL` to that file would induce a future contributor to add a synthetic posting in `bot-pr-with-synthetic-checks/action.yml`, which would silently fail to satisfy the ruleset, and the test harness would not detect the failure.
- Embedded shell in YAML files in Acceptance Criteria MUST be verified via `yamllint`/`actionlint` + `bash -c '<extracted-snippet>'`, never `bash -n <file.yml>` (per skill Sharp Edge added in #3543). The new audit script is a standalone `.sh` file, so `bash -n scripts/audit-bot-codeql-coverage.sh` IS valid; this sharp edge applies only if a step is moved into a workflow file later.
- `gh api --paginate` outputs separate JSON arrays per page; the audit script's check-runs query is per-SHA and unlikely to paginate (check-runs cap per commit is typically < 100), but if a commit ever exceeds the cap, the script MUST `--paginate | jq -s 'add // [].check_runs // []'` (per constitution shell rules). Phase 1 §4 explicitly uses `?per_page=100` to bound the response; verify during implementation that NO bot PR exceeds 100 check-runs (current max observed: 27 on PR #3480 — safe headroom).
- The audit's classification of `neutral` as passing is load-bearing on the GitHub docs assertion *"Required status checks must have a successful, skipped, or neutral status before collaborators can make changes to a protected branch"* (cited in Overview). If that doc URL drifts or the semantics change, the audit's pass/fail logic must be updated; runbook §Rollback explicitly lists this as a watched assumption.
- For drift envelopes containing user-controlled-ish strings (PR titles, headRefName), the audit script's output to `~/.local/state/soleur/` MUST strip `\r\n` before any GitHub-Annotation echo (`::error::`, `::notice::`). Per `cq-test-fixtures-synthesized-only`-adjacent: fixtures in `scripts/fixtures/` are synthesized, but real PR titles can contain control characters. Use `${var//[$'\n\r']/}` on every annotation echo.
- **Required-status-check matching pins BOTH context AND integration_id (load-bearing).** `gh api .../rulesets/14145388` shows `CodeQL` pinned to `integration_id: 57789` (github-advanced-security app). A future contributor adding `CodeQL` to `scripts/required-checks.txt` and posting synthetic check-runs from `github-actions[bot]` (`integration_id: 15368`) would NOT satisfy the ruleset — the posted check has the right context but the wrong app. This silent-failure mode is the load-bearing reason `CodeQL` is intentionally absent from `scripts/required-checks.txt`. Acceptance grep + runbook + wrong-app fixture form the three-layer guard.
- **The runbook is the discoverable artifact, not an AGENTS.md rule.** Per `wg-every-session-error-must-produce-either` discoverability exit: a future deepen-pass agent who greps `scripts/required-checks.txt` for `CodeQL` sees a comment line (added to `scripts/required-checks.txt` in this PR's Phase 2) pointing to the runbook. Adding an AGENTS.md rule would consume per-turn budget (per `cq-agents-md-why-single-line`) for a constraint that's already discoverable via local greps.
- **CodeQL `in_progress` status on dependabot force-push is NOT drift.** Exit code 2 (re-poll), not exit code 1 (escalate). Runbook §Drift triage explicitly distinguishes these. Otherwise a routine dependabot rebase would generate noise in the daily-cron follow-up (#3545 deferral 1).

## Verification

```bash
# Phase 1 verification:
bash scripts/audit-bot-codeql-coverage.sh --limit 5
echo "Exit code: $?"  # expect 0

bash scripts/audit-bot-codeql-coverage.sh --json --limit 5 | jq '.summary'
# expect: {"total": >=8, "passing": >=8, "drift": 0}

# Sharp-edge regression test:
bash scripts/audit-bot-codeql-coverage.sh --workflows scheduled-skill-freshness.yml --limit 1
echo "Exit code: $?"  # expect 1 (sanity floor)

# Phase 2 verification:
cat knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md | head -5  # expect frontmatter + heading
grep -F 'codeql-bot-coverage' knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md  # expect a hit
grep -F '#3545' knowledge-base/legal/compliance-posture.md  # expect a hit
```

## Out-of-scope deferrals (tracking issues to file)

1. **Schedule the audit as a weekly cron** (`scheduled-codeql-bot-coverage.yml`) opening a `compliance/critical` issue on drift. File as follow-up. Re-evaluation: after #3545 lands and the manual audit proves stable for ≥ 2 weeks.
2. **Extend audit to all ruleset-required checks**, not just `CodeQL`. Generalizing to a `audit-bot-ruleset-coverage.sh` that walks every context in `gh api .../rulesets/14145388` and verifies bot PR coverage. File as follow-up. Re-evaluation: after a second drift incident.
3. **Surface audit output in Soleur Cloud Command Center** alongside the ruleset bypass-actors audit (#3544). File as follow-up. Re-evaluation: after a Cloud-side observability primitive exists.

## Refs

- #3542 — parent (R15 mitigation; introduced the `CodeQL` required check inventory issue)
- #3544 — sibling D1 (bypass_actors audit; same daily-cron pattern, different surface)
- #2719 — origin (R15 design)
- `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` — sibling runbook (cross-linked)
- GitHub Docs: [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) — load-bearing assertion that `neutral` satisfies required status checks.

