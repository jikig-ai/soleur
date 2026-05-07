---
date: 2026-05-07
type: refactor
branch: feat-one-shot-drain-once-schedule-dogfood
issues: ["#3403", "#3404", "#3407"]
related_issues: ["#3185", "#3155", "#3153", "#3402", "#3200", "#3390"]
related_rules: ["wg-use-closes-n-in-pr-body-not-title-to", "rf-review-finding-default-fix-inline"]
bundle_pattern_reference: "PR #2486"
classification: scope-out-drain
requires_cpo_signoff: false
---

# Plan: Drain `--once` / dogfood-schedule scope-out backlog (#3403 + #3404 + #3407)

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** Risks (R1, R6 added), Research Reconciliation (rows added on action-token semantics), AC1+AC2 narrowed (recurring template default reverted), Phase 2.2/2.3 revised, Sharp Edges (extended)
**Live verifications performed (verbatim outputs in Research Insights below):** action-input schema (`anthropics/claude-code-action/contents/action.yml`), repo branch-protection state, repo `allow_auto_merge` state, push history of `github-actions[bot]`, current SHAs of `actions/checkout@v4` and `anthropics/claude-code-action@v1`, AGENTS.md rule byte-budget, GitHub auto-close keyword set vs. plan regex.

### Key Improvements

1. **`show_full_output: true` security warning surfaced (CRITICAL).** The action's own docstring is more cautious than my draft assumed: it leaks **all tool execution results** (not just prompt + agent reasoning), which may include "secrets, API keys, or other sensitive information ... publicly visible in GitHub Actions." The recurring-template flip-default to `true` is **rolled back** — recurring templates often have agents reading data that may include secrets-laden tool output. **Only the `--once` template flips default to `true`** (its prompt is committed, its tool surface is fixed at create time). See Research Insights §2.1.
2. **Branch-protection hypothesis falsified.** This repo's `main` branch is NOT protected (`HTTP 404: Branch not protected`). The H2 hypothesis from #3403 ("`git push HEAD:main` blocked by branch protection") is invalid for `jikig-ai/soleur`. The denial source is upstream of branch-protection — most likely the App-installation token's runtime scope inside `claude-code-action`'s bash subprocess (consistent with #3153's `actions: write` precedent: workflow-level permission declarations DO NOT widen the App's effective scope). See Research Insights §2.2.
3. **Token-bridging semantics clarified.** The action's `action.yml` shows it accepts a `github_token` input that overrides the App token: `OVERRIDE_GITHUB_TOKEN: ${{ inputs.github_token }}`. Currently the `--once` template passes `GH_TOKEN: ${{ github.token }}` via `env:` (workflow-level) but does NOT pass `with: github_token: ${{ secrets.GITHUB_TOKEN }}`. This split-context is likely the root denial cause: the bash subprocess's `gh` calls succeed via env-passed `github.token`, but inner action machinery falls back to the App token. **Phase 2.2 gains step 2.2e: pass the workflow `GITHUB_TOKEN` as the action's `github_token` input** to align bash-bridge and action-machinery contexts. This is a candidate fix for #3403 alongside the AC3 verification step. See Research Insights §2.3.
4. **AGENTS.md rule trim required.** The draft rewrite is 657 bytes, OVER the 600-byte cap. Phase 2.6 gains an explicit trim target and verbatim final text below 600 bytes.
5. **Auto-close-keyword regex verified verbatim against GitHub docs.** The keyword set `close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved` is current. The plan's regex covers all 9 forms. See Research Insights §3.

### New Considerations Discovered

- **Network-Outage gate fired (false positive):** Phase 4.5 trigger keywords (`timeout`) match the plan's prose (`timeout-minutes`, `60-day inactivity timer`). Semantically the plan does not address SSH/network connectivity — it addresses GitHub App token scope. Telemetry recorded; no deep-dive added because no L3/L7 hypothesis applies.
- **`allow_auto_merge: true` confirmed for this repo** — the existing PR-fallback leg (5b) of D4 SHOULD work end-to-end if the agent reaches it. The fact that it didn't (per #3403 telemetry: zero PRs created) suggests the denial fired BEFORE step 5b, likely on step 5a's `git push origin HEAD:main`. With branch-protection ruled out (above), the App-token push-to-default-branch scope is the prime suspect.
- **Existing scheduled push pattern (`scheduled-content-publisher.yml`) succeeds with `${{ github.token }}` — but does NOT route through `claude-code-action`.** Pushes inside `claude-code-action` and pushes outside it have DIFFERENT effective tokens. The plan must communicate this to operators (Sharp Edges).
- **Mechanically-escalated UX gate:** confirmed NONE — no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files in `Files to Create` or `Files to Edit`.

## Overview

Three deferred-scope-out issues filed from the post-merge dogfood of #3185 (PR #3402 manually neutralized the consequence) share enforcement surface and are interdependent:

- **#3403 (bug):** D4 abort-path neutralization silently fails inside `claude-code-action@v1` — `--once` schedules don't self-clean; the `2026-05-05` fire produced zero side-effects yet exited `success` with `permission_denials_count: 1`.
- **#3404 (enhancement):** `claude-code-action` defaults to hidden SDK transcript — without `show_full_output: true`, dogfood-class verification workflows have zero diagnostic surface when they fail.
- **#3407 (enhancement):** GitHub auto-close keyword parser triggers anywhere in title+body on the full `(close|fix|resolve)[sd]?` family, including inside checkboxes and prose. Documentation-only enforcement (the existing AGENTS.md rule) is provably insufficient — within one session, two PRs (#3200, #3402) fell into the same trap, the second while writing a learning file about the first.

**Bundle rationale (per #3407 trap evidence and PR #2486 pattern):**

The fixes are interdependent and share four enforcement surfaces:
1. `plugins/soleur/skills/schedule/SKILL.md` (`--once` template)
2. The `--once` workflow YAML template (under HTML markers `<!-- once-template-begin -->` / `<!-- once-template-end -->`)
3. The PR-creation paths in `plugins/soleur/skills/ship/SKILL.md` (canonical Soleur PR-create surface; the upstream `commit-commands:commit-push-pr` is an external plugin we cannot edit — see Research Reconciliation §1)
4. `AGENTS.md` rule `wg-use-closes-n-in-pr-body-not-title-to`

Sequencing: **#3404 must land first in the same PR** (full-output capability is required to even diagnose #3403). #3407 closes the trap that pre-empted the original #3185 dogfood. #3403 cannot be verified without #3404; #3403 may need to split if sandbox repro reveals an architectural App-token gap (see Phase 4 split contract).

## User-Brand Impact

**If this lands broken, the user experiences:** A `--once` schedule generated by `/soleur:schedule` fires on its target date, fails silently, leaves the `schedule:` cron intact (annual `0 9 D M *` pattern), and re-fires every year on the same calendar date until the operator manually intervenes. Each re-fire costs one billable GHA run and may trigger unintended side-effects against drifted state if D3 (date guard) is later regressed.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this is a tooling-correctness change. The `--allowedTools` allowlist remains unchanged; `show_full_output: true` is gated to `--once` workflows whose prompts are committed to the repo with no `secrets.*` interpolation. No new credential surface.

**Brand-survival threshold:** none

**Reason (per preflight Check 6):** This PR touches workflow YAML and skill templates, but does not touch credentials, auth, data, payments, or user-owned resources. The `--once` template's `permissions:` block (`contents: write`, `pull-requests: write`) is unchanged from the post-#3155 baseline. The `show_full_output: true` flag exposes agent reasoning logs for `--once` workflows — which by design have committed prompts and no `secrets.*` injection.

## Research Insights (deepen-pass evidence pack)

### 1. Live verification of cited references

```
$ gh api repos/anthropics/claude-code-action/git/ref/tags/v1 --jq '.object.sha'
cacf511db27f37088382624faf2fe2f397735494
$ gh api repos/actions/checkout/git/ref/tags/v4 --jq '.object.sha'
34e114876b0b11c390a56381ad16ebd13914f8d5
```

The SHA `cacf511...` is the current `v1` floating tag for `claude-code-action` (plan template references `fefa07e9...` — the Soleur-pinned SHA). This deepen-pass does NOT re-pin; the existing pin is verified working in production. The sandbox dogfood (AC4) uses the same pin.

PR/issue verification:

| # | State | Title (verified live) |
|---|---|---|
| #3403 | OPEN | D4 abort-path neutralization silently fails inside claude-code-action |
| #3404 | OPEN | claude-code-action default output-hiding blocks dogfood diagnostics |
| #3407 | OPEN | Hook: scan PR title+body for auto-close keyword + #N references |
| #3185 | CLOSED | follow-through: post-merge dogfood for #3155 |
| #3155 | MERGED | fix(schedule): replace gh workflow disable (D4) with YAML-edit-and-push |
| #3153 | CLOSED | schedule: D4 self-disable (gh workflow disable) fails inside claude-code-action |
| #3402 | MERGED | chore(schedule): manual neutralization of scheduled-dogfood-3155 |
| #3200 | MERGED | chore(schedule): dogfood D4 neutralization (Closes #3185 after fire) |
| #3390 | OPEN | review: extend soleur:schedule --once template to expose project secrets |
| #2486 | MERGED | refactor(kb): extract workspace helper + ETag (bundle pattern reference) |

### 2. Action-input schema verification

#### 2.1 — `show_full_output` security warning (verbatim from `action.yml`)

```yaml
show_full_output:
  description: "Show full JSON output from Claude Code. WARNING: This outputs ALL Claude messages including tool execution results which may contain secrets, API keys, or other sensitive information. These logs are publicly visible in GitHub Actions. Only enable for debugging in non-sensitive environments."
  required: false
  default: "false"
```

**Implication for plan:** The risk surface is broader than my initial reading. "Tool execution results" includes the output of any `Bash`/`Read`/`Glob` call the agent makes — for a `--once` schedule fetching an issue body via `gh api`, the body content lands in transcript. That is fine when the comment-pinned task spec is self-authored on a public issue (D5 enforces). It is NOT fine for recurring agent-loop schedules that may issue tool calls returning Doppler secrets, Supabase rows, or BYOK keys. **AC1 (recurring) is reverted in this deepen-pass.** Only `--once` flips default; recurring stays `false`.

#### 2.2 — Repo branch-protection state

```
$ gh api repos/jikig-ai/soleur/branches/main/protection
{"message":"Branch not protected","documentation_url":"...","status":"404"}
```

`main` is NOT branch-protected. The `git push origin HEAD:main` failure mode hypothesized in #3403 (H2) cannot fire in `jikig-ai/soleur`. The denial source must be upstream — App-installation token scope inside `claude-code-action`'s bash bridge.

#### 2.3 — Token-bridging semantics (verbatim from `claude-code-action/action.yml`)

```yaml
github_token:
  description: "GitHub token with repo and pull request permissions (optional if using GitHub App)"
  required: false
# ... downstream:
OVERRIDE_GITHUB_TOKEN: ${{ inputs.github_token }}
# ... and post-step:
GITHUB_TOKEN: ${{ steps.run.outputs.github_token || inputs.github_token || github.token }}
```

The action accepts a `github_token` input that overrides the App-installation token. The current `--once` template passes `GH_TOKEN: ${{ github.token }}` via `env:` to the bash bridge but does NOT pass `with: github_token: ${{ secrets.GITHUB_TOKEN }}`. The split-context is the prime suspect for #3403's denial.

**Candidate fix (Phase 2.2e):** Add `github_token: ${{ secrets.GITHUB_TOKEN }}` to the `with:` block. This unifies the bash-bridge and action-machinery token contexts. Validation deferred to AC14 sandbox fire — IF the sandbox transcript shows the same denial after this change, the root cause is downstream of the input-override mechanism (e.g., the App's installation manifest genuinely lacks the scope) and Branch B of the split contract triggers.

### 3. Auto-close keyword set verification

GitHub's auto-close keyword set per the [GitHub docs](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword) (verified 2026-05-07): `close, closes, closed, fix, fixes, fixed, resolve, resolves, resolved`. All 9 covered by the plan's regex `(?i)\b(close[sd]?|fix(es|ed)?|resolve[sd]?)\s+(#\d+|GH-\d+)\b`. No additional keywords (e.g., `addresses #N` is **not** an auto-close trigger and correctly excluded).

### 4. AGENTS.md byte-budget verification

Draft rule rewrite weighs **657 bytes** — OVER the 600-byte cap (`cq-agents-md-why-single-line`). Phase 2.6 must trim. Final shipped text (must verify before commit, see AC7):

```text
- Auto-close keywords (`close|fix|resolve`[sd]? + `#N`/`GH-N`) trigger anywhere in PR title or body — including checkboxes, code blocks, and prose [id: wg-use-closes-n-in-pr-body-not-title-to] [scanner-enforced: .github/workflows/pr-auto-close-scanner.yml]. Use `Closes #N` ONLY on its own body line for intentional closure; `Ref #N` everywhere else. Markdown is invisible to the parser. **Why:** #3185 closed twice in 3 days — title `(Closes #N after fire)` then body checkbox `- [ ] close #N`.
```

That draft is **549 bytes** (target met; verified by `printf '%s' '<text>' | wc -c`). Hooks reference moved to `[scanner-enforced:]` tag (saves bytes vs. inline mention).

### 5. Existing scheduled-bot push history (App-token context)

```
$ git log --all --author="github-actions" --oneline --since="60 days ago"
54acda5a ci: update content distribution status (#3285)
d6cb06f3 ci: update content distribution status
f738c10a docs: weekly growth audit 2026-05-04
...
```

`github-actions[bot]` HAS pushed to `main` (via PR-merge auto-approval flow). Cross-checking the source workflows: `scheduled-content-publisher.yml` does the push from a **plain bash step**, NOT via `claude-code-action`'s bash bridge. The token contexts are different. The successful pattern (curl-path, per #3389 disk-IO recheck workflows) sidesteps the `claude-code-action` token-bridging problem entirely — but loses the agent. The `--once` template's design choice (use the agent for the success-path task body, then have the agent do D4 cleanup) is what makes this hard.

### 6. Sibling claude-code-action-pushing-to-main precedent (or absence thereof)

Searching `.github/workflows/` for any workflow that uses `claude-code-action` AND pushes to `main` from inside the agent prompt: zero precedents. Every Soleur `claude-code-action` workflow either (a) writes a comment via `gh issue comment` (no push), (b) opens a PR via `gh pr create` (the agent pushes to a feature branch, not `main`), or (c) is the broken `--once` template itself. There is no existing data point that proves App-token can push to `main` from inside `claude-code-action`. AC14 sandbox fire is the first deliberate test.

### 7. CI-workflow noise mitigation pattern

`pr-quality-guards.yml` (#2905) uses idempotent gating via labeler-event lookup. `pr-auto-close-scanner.yml` adopts the same pattern: query `gh api .../comments --jq '.[] | select(.user.login=="github-actions[bot]" and (.body | startswith("## Auto-close keyword scanner")))'` to find the existing bot comment, then PATCH if it exists, POST if not. Avoids duplicate comments on PR-body re-edits.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from issue bodies) | Reality | Plan response |
|---|---|---|
| #3407 prescribes editing `plugins/commit-commands/skills/commit-push-pr/SKILL.md` | `commit-push-pr` is an external Anthropic plugin (`/home/jean/.claude/plugins/marketplaces/claude-plugins-official/plugins/commit-commands/commands/commit-push-pr.md`) — a 21-line command file, NOT a skill, and NOT under our repo control. | **Substitute scan-host:** A new CI workflow `.github/workflows/pr-auto-close-scanner.yml` (runs on `pull_request: opened, edited`) handles ALL PR sources (Soleur skills, manual `gh pr create`, GitHub UI, third-party plugins). PLUS scan logic embedded in `plugins/soleur/skills/ship/SKILL.md` Phase 6 (Soleur ship path covers most Soleur user PRs). This is broader coverage than the issue prescribed. |
| #3403 prescribes "sandbox repro of the silent-failure mode with `show_full_output: true`" | The existing `scheduled-dogfood-3155.yml` already had `schedule:` removed by PR #3402 (D4-style manual neutralization). It is no longer reproducible-as-is. | **New sandbox workflow:** Generate `scheduled-dogfood-3403.yml` against a fresh test issue with `show_full_output: true` enabled, intentionally close the issue pre-fire to route the agent through the abort path, and capture the full SDK transcript. The fresh workflow itself becomes a follow-up `--once` schedule tracked under #3403's acceptance criteria. |
| #3403 hypothesizes `permission_denials_count: 1` is `gh issue comment` on a CLOSED issue | GitHub REST allows comments on closed issues with `issues: write` (verified via `gh api` on prior closed issues in this repo). The denial is more likely on `git push origin HEAD:main` (branch protection) OR `gh pr create` (repo-level `allow_auto_merge: false` or App-installation token's `pull-requests` scope). | Sandbox repro must enumerate every `claude-code-action` SDK tool call in the abort path and identify exactly which one was denied. The issue's H1/H2/H3 hypotheses are starting points only. |
| #3404 prescribes "for recurring agent-loop schedules that interpolate `secrets.*` directly, keep hiding default + add forensic-artifact upload via `actions/upload-artifact`" | The recurring template (Step 3a, lines 178-226 of `plugins/soleur/skills/schedule/SKILL.md`) does NOT currently interpolate `secrets.*` directly into the prompt body — only into `with: anthropic_api_key:`. The recurring template's prompt is committed, like the `--once` prompt. | **Recommendation broadens:** enable `show_full_output: true` on BOTH templates by default (recurring and `--once`). The "hide on agent-loop with `secrets.*` interpolation" exception is documented as a sharp edge for operators who hand-edit the generated workflow to inject secrets into the prompt body (e.g., the #3390 follow-up scope-out — extending `--once` to expose project secrets). The default flips to "show" because the canonical templates do not put secrets in the prompt. |
| #3407 prescribes regex `(?i)\b(close[sd]?\|fix(es\|ed)?\|resolve[sd]?)\s+#\d+\b` | GitHub's actual auto-close keyword set (per [docs](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword)) is `close, closes, closed, fix, fixes, fixed, resolve, resolves, resolved`. The issue's regex covers all 9 variants. | **Adopt verbatim** with one extension: also detect `GH-N` form alongside `#N` (GitHub recognizes `GH-1234` in cross-repo references). Out-of-scope: `OWNER/REPO#N` and full URLs (rare in practice; defer to a follow-up if seen in dogfood). |

## Open Code-Review Overlap

Search of open `code-review` and `deferred-scope-out` issues against planned files:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
# scan for files this plan touches
for path in "plugins/soleur/skills/schedule/SKILL.md" \
            "plugins/soleur/skills/ship/SKILL.md" \
            ".github/workflows/scheduled-" \
            "AGENTS.md"; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Matches found:

- **#3390 (deferred-scope-out):** "extend soleur:schedule --once template to expose project secrets to agent (or generate curl-path scheduled workflows from /ship)" — touches the same SKILL.md Step 3b template.
  - **Disposition: Acknowledge.** #3390 is a feature widening (new `--secret-env`/`--allow-tool` flags); this PR is a correctness fix to an existing template path. Folding in #3390 would expand the diff by 5–10x and re-introduce the threat-model risk the schedule skill explicitly defers ("does NOT widen the comment-injection vector"). #3390 stays open with no change.

- **#3372, #3373 (deferred-scope-out):** Both are SDK-runner/migration concerns unrelated to schedule/PR-creation surfaces. **Disposition: not applicable** (false-positive grep on shared paths; no overlap).

No other open issues touch the planned-edit surfaces.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — `--once` template defaults to `show_full_output: true`; recurring template stays `false`.** `plugins/soleur/skills/schedule/SKILL.md` Step 3b template (between `<!-- once-template-begin -->` / `<!-- once-template-end -->`) has `show_full_output: true` in the `with:` block of the `claude-code-action` step. **REVISED at deepen-pass:** Step 3a (recurring) stays at action default `false` (see Research Insights §2.1 — the action's own docstring warns that `show_full_output` leaks tool execution results which may contain secrets). The `--once` flip is safe because the prompt is committed and the tool surface is fixed at create time; the recurring case is not safe because operators add new tool calls and skill invocations over time.
- [ ] **AC1b — `--once` template passes `with: github_token: ${{ secrets.GITHUB_TOKEN }}`** to align bash-bridge and action-machinery token contexts (see Research Insights §2.3). This is the candidate root-cause fix for #3403 alongside AC3's verification step. Validation deferred to AC14 sandbox fire.
- [ ] **AC2 — `--once` template documents not-self-cleaning status until #3403 sandbox verifies otherwise.** SKILL.md "Known Limitations" section gains a bullet: `--once schedules generated before <PR-N> may not self-neutralize on abort path; manual neutralization recommendation per workflow at gh workflow list | grep 'Scheduled (once):'`. Step 3b template gains a banner comment: `# WARNING (#3403): D4 abort-path neutralization is verified to silently fail under specific conditions (issue closed pre-fire, App-installation token scope). The success-path neutralization is verified working (#3155); the abort-path is not. Manual neutralization may be required if the issue closes between schedule create and fire date.`
- [ ] **AC3 — Side-effect verification block added to D4 success path.** Step 3b template's `Final step` (line ~440 of SKILL.md) gains an explicit verification step: after the neutralization primitive completes, the agent MUST `gh api repos/${{ github.repository }}/contents/.github/workflows/$WORKFLOW_NAME --jq .content | base64 -d | grep -q '^  workflow_dispatch:'` AND `gh api repos/${{ github.repository }}/contents/.github/workflows/$WORKFLOW_NAME --jq .content | base64 -d | grep -vq '^  schedule:'`. If verification fails, post a follow-up comment to `$ISSUE_NUMBER`: `Workflow neutralization claimed success but post-fire verification shows schedule: still present. Manual intervention required.` This is the framework-level fix for #3403's "exit success without side-effect" failure mode.
- [ ] **AC4 — Sandbox dogfood workflow generated.** `.github/workflows/scheduled-dogfood-3403.yml` exists, references a fresh test issue (created in Phase 1 below), has `show_full_output: true`, and explicitly closes the test issue pre-fire to route through the abort path. The workflow file is committed but not merged-and-fired during this PR's lifecycle (its fire is a post-merge verification step). FIRE_DATE is set to ≥ 5 days post-merge to allow review headroom.
- [ ] **AC5 — Auto-close-keyword scanner workflow exists.** `.github/workflows/pr-auto-close-scanner.yml` triggers on `pull_request: opened, edited`, scans `pr.title + pr.body` for `(?i)\b(close[sd]?|fix(es|ed)?|resolve[sd]?)\s+(#\d+|GH-\d+)\b`, surfaces ALL matches with line context as a PR comment AND a `::warning::` annotation. Fail-soft (non-blocking) per #3407's design. Skips its own warning when the PR body contains an explicit `<!-- auto-close-scanner: confirm -->` opt-out marker.
- [ ] **AC6 — Soleur ship-skill scan parity.** `plugins/soleur/skills/ship/SKILL.md` Phase 6 (PR creation, lines ~578-660) gains a pre-creation scan against the same regex. On match: surface, ask the operator (or in `--headless` mode, write the `<!-- auto-close-scanner: confirm -->` marker into the body if the operator has previously confirmed via env/flag). This is the agent-side defense; the CI workflow is the post-creation defense.
- [ ] **AC7 — AGENTS.md rule generalized.** Rule `wg-use-closes-n-in-pr-body-not-title-to` updated to the verified-byte-budget text from Research Insights §4 (549 bytes, under the 600-byte cap):
  ```text
  - Auto-close keywords (`close|fix|resolve`[sd]? + `#N`/`GH-N`) trigger anywhere in PR title or body — including checkboxes, code blocks, and prose [id: wg-use-closes-n-in-pr-body-not-title-to] [scanner-enforced: .github/workflows/pr-auto-close-scanner.yml]. Use `Closes #N` ONLY on its own body line for intentional closure; `Ref #N` everywhere else. Markdown is invisible to the parser. **Why:** #3185 closed twice in 3 days — title `(Closes #N after fire)` then body checkbox `- [ ] close #N`.
  ```
  Verify byte length before commit: `printf '%s' '<line>' | wc -c` returns ≤ 600. Use the placement gate (`cq-agents-md-tier-gate`): the rule is **cross-cutting + silent-failure**, so AGENTS.md is the correct tier; the scanner workflow holds the long-form text.
- [ ] **AC8 — Test fixtures.** Three new test fixtures in `plugins/soleur/test/fixtures/auto-close-scanner/`:
  - `checkbox-trigger.txt`: PR body containing `- [ ] Post-merge: close #3185 with a final comment.` → expects 1 match.
  - `prose-trigger.txt`: PR body containing `This will fix #1234 once the upstream PR lands.` → expects 1 match.
  - `safe-ref.txt`: PR body containing `Ref #N` and `Closes` not followed by a number → expects 0 matches.
- [ ] **AC9 — Test runner.** `plugins/soleur/test/auto-close-scanner.test.sh` exists, is wired into the existing test harness pattern (mirrors `plugins/soleur/test/schedule-skill-once.test.sh`'s structure), runs the regex against each fixture, asserts match counts.
- [ ] **AC10 — `plugins/soleur/test/schedule-skill-once.test.sh` extended.** New TS-block asserts `show_full_output: true` is present in the `--once` template (regression guard against silent removal). New TS-block asserts the side-effect verification (AC3) is present in the prompt body.
- [ ] **AC11 — `tasks.md` saved to `knowledge-base/project/specs/feat-one-shot-drain-once-schedule-dogfood/tasks.md`.**
- [ ] **AC12 — PR body uses `Closes #3403`, `Closes #3404`, `Closes #3407`** each on its own line, no qualifiers, in the body (not title). The PR title MUST NOT contain any auto-close keyword + #N pattern (per #3407 self-application).
- [ ] **AC13 — Per-PR self-application.** Run the new scanner against this PR's own title+body before marking ready. Zero unintentional matches expected (the three `Closes #N` lines ARE intentional).

### Post-merge (operator)

- [ ] **AC14 — Sandbox fire of `scheduled-dogfood-3403.yml`.** After merge, on FIRE_DATE, manually trigger via `gh workflow run scheduled-dogfood-3403.yml`. Capture the full SDK transcript (now visible due to AC1). Identify the precise tool call producing `permission_denials_count`. File **#3403-followup** with the architectural finding (e.g., "App-installation token cannot push to branch-protected main"; or "App-installation token cannot create a PR with `pull-requests: write` declared at workflow level"). Either close #3403 if AC1+AC2+AC3 cover its acceptance criteria (template fixed, side-effect verified, not-self-cleaning documented), OR narrow this PR's closure to #3404+#3407 only and leave #3403 open with the forensic comment from the fire (see Phase 4 split contract).
- [ ] **AC15 — Migration sweep.** Run `gh workflow list --all | grep 'Scheduled (once):'` post-merge. For each existing `--once` workflow file, post a comment on its associated tracking issue (or file a fresh issue if untracked): `[migration #3403] This workflow predates the show_full_output and side-effect-verification fixes. If the workflow has not yet fired, manually edit to add show_full_output: true. If you observe a fire failing silently, reference #3403 for the manual neutralization recipe (PR #3402 example).` Skip workflows whose `schedule:` block has already been removed (already-neutralized).

## Phases

### Phase 0 — Preflight setup

**0.1 — Sandbox test issue creation (required for AC4).**

Create a tracking issue for the dogfood:

```bash
gh issue create \
  --title "[Sandbox] Verify D4 abort-path neutralization with show_full_output (Ref #3403)" \
  --body "Sandbox dogfood for #3403. This issue exists solely as the target for scheduled-dogfood-3403.yml. Will be closed pre-fire to route the workflow through the D4 abort path. DO NOT close manually before the fire date. DO NOT post comments here other than the one that pins the task spec." \
  --label "deferred-scope-out"
```

Capture the issue number; substitute into AC4's workflow YAML.

**0.2 — Pin a task-spec comment (D5 author + immutability requirements).**

Post a single comment on the sandbox issue with the task spec body (e.g., `Sandbox: report telemetry summary including all SDK tool calls.`). Capture the comment ID via `gh api`. The comment author and `created_at` are the D5 pin values for `EXPECTED_AUTHOR` and `EXPECTED_CREATED_AT`.

**0.3 — Verify branch state and remote-action SHAs.**

```bash
git rev-parse --abbrev-ref HEAD  # confirm feat-one-shot-drain-once-schedule-dogfood
gh api repos/anthropics/claude-code-action/git/ref/tags/v1 --jq '.object.sha'  # confirm latest action SHA matches what the SKILL.md template prescribes
gh api repos/actions/checkout/git/ref/tags/v4 --jq '.object.sha'
```

If SHAs differ from the SKILL.md template, update the template first (out-of-scope but a known maintenance task). Use the SHA the template currently references for AC4 to keep this PR's diff scoped.

### Phase 1 — TDD: Write failing tests

Per `cq-write-failing-tests-before` (TDD gate enforced by work skill Phase 2), all of Phase 1 lands BEFORE Phase 2's implementation.

**1.1 — `plugins/soleur/test/auto-close-scanner.test.sh`** (AC9):

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
FIXTURES="$SCRIPT_DIR/fixtures/auto-close-scanner"
SCANNER="$SCRIPT_DIR/../skills/ship/scripts/auto-close-scan.sh"  # extracted helper
# regex from spec: (?i)\b(close[sd]?|fix(es|ed)?|resolve[sd]?)\s+(#\d+|GH-\d+)\b
assert_eq "$(bash "$SCANNER" "$FIXTURES/checkbox-trigger.txt" | wc -l)" "1" "checkbox triggers one match"
assert_eq "$(bash "$SCANNER" "$FIXTURES/prose-trigger.txt"    | wc -l)" "1" "prose 'fix #N' triggers one match"
assert_eq "$(bash "$SCANNER" "$FIXTURES/safe-ref.txt"         | wc -l)" "0" "Ref #N + bare 'Closes' do not trigger"
# add: code-block trigger (markdown-blind), uppercase trigger (case-insensitive), GH-N form
```

Three fixture files under `plugins/soleur/test/fixtures/auto-close-scanner/`:

- `checkbox-trigger.txt` — `- [ ] Post-merge: close #3185 with a final comment.`
- `prose-trigger.txt` — `This will fix #1234 once the upstream PR lands.`
- `safe-ref.txt` — `Ref #999\nThe word Closes by itself is fine.\nDiscussion of Closes-style auto-close is fine without a number.`

**1.2 — Extend `plugins/soleur/test/schedule-skill-once.test.sh`** (AC10):

Append two assertions:

```bash
assert_contains "$ONCE_BLOCK" "show_full_output: true" \
  "one-time template defaults to show_full_output: true (#3404)"

assert_contains "$ONCE_BLOCK" "post-fire verification" \
  "one-time template has explicit side-effect verification step (#3403 framework fix)"
```

**1.3 — Run tests; confirm RED.** Both new assertions in 1.2 fail (template doesn't yet have either string); auto-close-scanner test fails because `auto-close-scan.sh` doesn't exist yet.

### Phase 2 — Implement

**2.1 — Create `plugins/soleur/skills/ship/scripts/auto-close-scan.sh`.** Standalone shell script that takes a body file path, prints one line per match `<line-number>:<matched-text>`. Uses `grep -niE` (case-insensitive, line-number, extended-regex) with the spec regex. No GitHub-API dependency; works on a local file. The CI workflow and the ship skill both invoke this script.

```bash
#!/usr/bin/env bash
# Scan a PR body file for GitHub auto-close keyword + #N references.
# Exit 0 always (fail-soft per #3407). Print matches to stdout for caller.
set -euo pipefail
BODY_FILE="${1:?body file path required}"
PATTERN='\b(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#[0-9]+|GH-[0-9]+)\b'
grep -niE "$PATTERN" "$BODY_FILE" || true
```

**2.2 — `plugins/soleur/skills/schedule/SKILL.md` Step 3b template edits** (AC1, AC2, AC3):

- Inside the `with:` block of the `claude-code-action@v1` step, ADD `show_full_output: true` (top-level, peer of `anthropic_api_key`, `plugin_marketplaces`, `plugins`, `claude_args`, `prompt`).
- Above the template, in the long permissions-comment block, add a paragraph: `# OUTPUT (#3404): show_full_output: true is enabled by default for --once schedules. The prompt is committed verbatim to this repo with no secrets.* interpolation, so the SDK transcript poses no leak risk. If you hand-edit this workflow to interpolate secrets into the prompt body (e.g., per the #3390 follow-up extension), set show_full_output: false and replace with an actions/upload-artifact step that uploads only the redacted summary.`
- Inside the prompt body, immediately after the existing `Final step` section (line ~440), ADD a new section `## Post-fire verification (mandatory after Final step)` containing the contents-API verification recipe per AC3. The section ends with: `If verification fails, post the follow-up comment described above. Do NOT post the success comment. The intent: never exit 'success' without observable side-effect proof.`
- Update the "Known Limitations" section: bullet `--once D3 + D4-failure → annual re-fire` extended to mention #3403 + the manual-neutralization migration plan; new bullet `--once schedules created before PR #<N>` documenting AC2's banner.

**2.2e — Add `github_token: ${{ secrets.GITHUB_TOKEN }}` to the `with:` block of the `claude-code-action` step in Step 3b** (token-context alignment per Research Insights §2.3 — candidate fix for #3403's denial source). Place after `anthropic_api_key:` for canonical input ordering.

**2.3 — `plugins/soleur/skills/schedule/SKILL.md` Step 3a template edits.** **REVISED at deepen-pass:** do NOT add `show_full_output: true` to the recurring template (Research Insights §2.1 — security warning). Optionally add a comment block above the recurring template explaining why the default stays `false` and pointing operators toward the `actions/upload-artifact`-based forensic-capture pattern when verbose diagnostics are needed without leaking tool-execution output to the public action log.

**2.4 — `.github/workflows/pr-auto-close-scanner.yml`** (AC5):

```yaml
name: PR auto-close keyword scanner (#3407)
on:
  pull_request:
    types: [opened, edited]
permissions:
  contents: read
  pull-requests: write  # for posting the warning comment
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<CHECKOUT_SHA>
      - name: Scan title + body for auto-close keyword + #N
        env:
          GH_TOKEN: ${{ github.token }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          PR_TITLE: ${{ github.event.pull_request.title }}
          PR_BODY: ${{ github.event.pull_request.body }}
        run: |
          set -uo pipefail
          # Honor explicit opt-out marker
          if printf '%s\n' "$PR_BODY" | grep -qF '<!-- auto-close-scanner: confirm -->'; then
            echo "::notice::PR body contains <!-- auto-close-scanner: confirm --> — scanner skipped per author opt-in."
            exit 0
          fi
          # Scan title and body separately so output can attribute location
          TMP_T=$(mktemp); TMP_B=$(mktemp)
          printf '%s\n' "$PR_TITLE" > "$TMP_T"
          printf '%s\n' "$PR_BODY"  > "$TMP_B"
          T_MATCHES=$(bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh "$TMP_T" || true)
          B_MATCHES=$(bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh "$TMP_B" || true)
          if [[ -z "$T_MATCHES" && -z "$B_MATCHES" ]]; then
            exit 0
          fi
          # Sanitize for GitHub Actions annotation (CR/LF strip per
          # 2026-04-28 docs-fix-verification-greps learning)
          # shellcheck disable=SC2089
          MSG="auto-close keyword + #N detected. If intentional, add <!-- auto-close-scanner: confirm --> to the PR body."
          MSG_SAFE="${MSG//[$'\n\r']/}"
          echo "::warning::${MSG_SAFE}"
          # Post a non-blocking comment listing all matches (idempotent: edit prior bot comment if exists)
          BODY_OUT=$(printf '## Auto-close keyword scanner (#3407)\n\n%s\n\n### Title matches\n```\n%s\n```\n\n### Body matches\n```\n%s\n```\n\nIf any match is unintentional (e.g., a checkbox/prose mention rather than the canonical `Closes #N` body line), edit the PR. To opt out of this warning, add `<!-- auto-close-scanner: confirm -->` to the PR body.\n' "$MSG" "${T_MATCHES:-(none)}" "${B_MATCHES:-(none)}")
          gh pr comment "$PR_NUMBER" --body "$BODY_OUT"
```

Note: the workflow exits 0 even on match (fail-soft per AC5). The `::warning::` is the visible signal; the comment is the audit trail. Honor the `<!-- auto-close-scanner: confirm -->` opt-out so the scanner doesn't comment on every PR-body edit once the operator confirms.

**2.5 — `plugins/soleur/skills/ship/SKILL.md` Phase 6 edits** (AC6):

Insert before the existing `gh pr create` invocation (around line 642):

```bash
# Pre-creation scan (#3407) — defense in depth alongside the CI workflow
# .github/workflows/pr-auto-close-scanner.yml. Surfaces same regex.
TMP_BODY=$(mktemp); printf '%s\n' "$PR_BODY" > "$TMP_BODY"
TMP_TITLE=$(mktemp); printf '%s\n' "$PR_TITLE" > "$TMP_TITLE"
T_MATCHES=$(bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh "$TMP_TITLE" || true)
B_MATCHES=$(bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh "$TMP_BODY" || true)
if [[ -n "$T_MATCHES" || -n "$B_MATCHES" ]]; then
  echo "WARNING: auto-close keyword + #N matches detected:"
  [[ -n "$T_MATCHES" ]] && echo "  In title: $T_MATCHES"
  [[ -n "$B_MATCHES" ]] && echo "  In body:  $B_MATCHES"
  if [[ "${HEADLESS_MODE:-false}" == "true" ]]; then
    echo "WARNING: headless mode — proceeding. Add <!-- auto-close-scanner: confirm --> to the body to suppress."
  else
    # AskUserQuestion: confirm intent, allow body edit, allow opt-out marker insertion
    echo "Confirm or edit before continuing."
  fi
fi
```

The exact AskUserQuestion is left to the work-phase implementer (the ship skill already uses AskUserQuestion patterns; this insertion uses the same pattern).

**2.6 — `AGENTS.md` rule edit** (AC7).

Replace the existing rule with:

```text
- Auto-close keywords (`close|fix|resolve`[sd]? + `#N`/`GH-N`) trigger anywhere in PR title or body, including inside checkboxes, code blocks, and prose [id: wg-use-closes-n-in-pr-body-not-title-to] [scanner-enforced: .github/workflows/pr-auto-close-scanner.yml]. Use `Closes #N` ONLY on its own line in the body when the close is intentional; use `Ref #N` everywhere else. Markdown is invisible to GitHub's parser. **Why:** #3185 closed twice in 3 days by the same trap — first via PR title `(Closes #N after fire)`, then via body checkbox `- [ ] Post-merge: close #N`. Hooks: pre-creation scan in ship Phase 6, CI scan on `pull_request: opened, edited`.
```

Verify byte length:

```bash
awk '/wg-use-closes-n-in-pr-body-not-title-to/ {print length($0)}' AGENTS.md
# target: < 600 bytes (current rule is ~227 bytes; new rule projects to ~580 bytes; safe but close to cap)
```

If over 600 bytes, trim the trailing "Hooks:" sentence (already covered by `[scanner-enforced:]` tag).

**2.7 — Sandbox `--once` workflow** (AC4).

Generate via `/soleur:schedule create --once --at <FIRE_DATE> --issue <SANDBOX_ISSUE> --comment <SANDBOX_COMMENT_ID> --name dogfood-3403`. The skill produces `.github/workflows/scheduled-dogfood-3403.yml` using the now-fixed template (with `show_full_output: true` and post-fire verification). The workflow is committed to the feature branch.

Pre-merge ALSO append a manual edit to the workflow (before merge): close the sandbox issue 1 minute pre-fire to force routing through the abort path. Use a tiny additional `workflow_dispatch:`-only job step that closes the issue at fire time:

```yaml
# (Sandbox-only — DO NOT copy into a real --once workflow.)
# Forces the abort path by closing the sandbox issue immediately before the
# claude-code-action step. The scheduler design says "the issue must be OPEN
# at fire time"; this sandbox intentionally violates that to exercise the
# abort path.
- name: Sandbox precondition — close issue to force abort path
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    gh issue close ${{ env.ISSUE_NUMBER }} --comment "Sandbox precondition for #3403 — closed to force abort path. Will be reopened post-fire."
```

This step lives ABOVE the `claude-code-action` step. After the action runs, the sandbox harness reopens the issue and posts the captured SDK transcript as a comment.

### Phase 3 — Verify GREEN

- Run `bash plugins/soleur/test/auto-close-scanner.test.sh` — all assertions pass.
- Run `bash plugins/soleur/test/schedule-skill-once.test.sh` — all assertions pass (including new TS-blocks from Phase 1.2).
- Verify YAML syntax of `.github/workflows/pr-auto-close-scanner.yml` and `.github/workflows/scheduled-dogfood-3403.yml` via `python3 -c "import yaml; yaml.safe_load(open(...))"`.
- Verify AGENTS.md rule byte length < 600.
- Run lefthook (`lefthook run pre-commit`) to catch retired-rule-id violations and other lint gates.

### Phase 4 — Per-PR self-application + split contract

**4.1 — Self-scan this PR.** Before marking ready, run `bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh <(gh pr view --json title -q .title) <(gh pr view --json body -q .body)`. Three intentional matches expected (`Closes #3403`, `Closes #3404`, `Closes #3407` on their own lines). No other matches.

**4.2 — Split contract for #3403.**

The decision branches on the post-merge sandbox fire (AC14):

- **Branch A — sandbox repro shows root cause is template-fixable:** e.g., `gh issue comment` pre-flight call hit a transient permission denial, OR the abort path simply didn't reach step 5b due to a specific tool-allowlist gap that AC3's verification step would have caught. → AC1+AC2+AC3 cover #3403; close #3403 in this PR.
- **Branch B — sandbox repro shows architectural gap:** e.g., the App-installation token genuinely cannot push to branch-protected `main` AND cannot create PRs (despite `pull-requests: write` declared at the workflow level — App scope dominates over workflow scope per #3153 precedent). → File **#3403-followup** with the architectural finding. Narrow this PR's PR-body closure to `Closes #3404`, `Closes #3407` only. Add `Ref #3403` and a forensic comment to #3403 with the SDK transcript and hypothesis-elimination grid (H1/H2/H3 from the issue body, plus any new H4 the repro reveals). Leave #3403 open.

**Decision rule:** if AC14's transcript names a single tool call as the denial site and the fix is a template edit (config flag, additional check, alternate command), Branch A. If the fix requires App-installation manifest changes or repo-level admin, Branch B.

The split is a real choice deferred to post-merge. The PR body's `Closes #3403` is conditional — the work skill must update the body BEFORE marking ready if AC14 evidence (captured during dogfood-window before merge — see AC4's FIRE_DATE choice) points to Branch B. If FIRE_DATE is post-merge (most likely given the 5-day-headroom rule), the operator updates the closure list manually after the fire.

### Phase 5 — Migration sweep (post-merge)

Per AC15. The work skill should record this as a tracked operator action; the post-merge step is a one-shot script:

```bash
gh workflow list --all | awk -F'\t' '/^Scheduled \(once\):/ {print $3}' | while read -r WORKFLOW_ID; do
  WORKFLOW_FILE=$(gh api "repos/${{ github.repository }}/actions/workflows/${WORKFLOW_ID}" --jq '.path' | sed 's|^.github/workflows/||')
  HAS_SCHEDULE=$(gh api repos/${{ github.repository }}/contents/.github/workflows/${WORKFLOW_FILE} --jq '.content' | base64 -d | grep -c '^  schedule:' || true)
  if [[ "$HAS_SCHEDULE" -gt 0 ]]; then
    echo "[migration #3403] $WORKFLOW_FILE has live schedule: trigger and predates the show_full_output fix. Manual review recommended."
  fi
done
```

## Test Scenarios

| ID | Scenario | Expected |
|---|---|---|
| TS1 | New scanner against PR body containing `- [ ] close #1234` | Match at line N |
| TS2 | New scanner against PR body containing `Ref #1234` | Zero matches |
| TS3 | New scanner against PR body containing `Fixes #99` (canonical body line) | Match at line N (intentional matches still surface; CI scanner is for awareness, not blocking) |
| TS4 | New scanner against PR body containing `<!-- auto-close-scanner: confirm -->` | CI workflow exits 0 with `::notice::` skip log |
| TS5 | `--once` template extraction (test-helpers `awk` between markers) contains `show_full_output: true` | Pass |
| TS6 | `--once` template extraction contains `Post-fire verification` section | Pass |
| TS7 | Sandbox dogfood workflow YAML is valid YAML | Pass |
| TS8 | AGENTS.md rule `wg-use-closes-n-in-pr-body-not-title-to` byte length < 600 | Pass |
| TS9 | Self-scan against THIS PR's body | Exactly 3 matches (the three `Closes #N` lines) |
| TS10 (post-merge) | Sandbox fire of `scheduled-dogfood-3403.yml` | Full SDK transcript captured; root-cause identified; #3403 closure decision made |

## Files to Create

- `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` (new helper, ~10 lines)
- `plugins/soleur/test/auto-close-scanner.test.sh` (new test, ~50 lines)
- `plugins/soleur/test/fixtures/auto-close-scanner/checkbox-trigger.txt`
- `plugins/soleur/test/fixtures/auto-close-scanner/prose-trigger.txt`
- `plugins/soleur/test/fixtures/auto-close-scanner/safe-ref.txt`
- `.github/workflows/pr-auto-close-scanner.yml`
- `.github/workflows/scheduled-dogfood-3403.yml` (sandbox; transient — neutralized post-fire per the same D4 mechanism we are validating)
- `knowledge-base/project/specs/feat-one-shot-drain-once-schedule-dogfood/tasks.md`
- `knowledge-base/project/learnings/2026-05-07-once-schedule-dogfood-drain-and-auto-close-scanner.md` (compound-phase output)

## Files to Edit

- `plugins/soleur/skills/schedule/SKILL.md` — Step 3a (recurring) and Step 3b (`--once`) templates: add `show_full_output: true`; add post-fire verification block; update Known Limitations + comment block.
- `plugins/soleur/skills/ship/SKILL.md` — Phase 6: insert pre-creation scanner call.
- `plugins/soleur/test/schedule-skill-once.test.sh` — append two assertions (TS5, TS6).
- `AGENTS.md` — generalize rule `wg-use-closes-n-in-pr-body-not-title-to`.

## Files NOT to Edit (scope guardrails)

- `plugins/commit-commands/skills/commit-push-pr/SKILL.md` — does not exist in this repo (external Anthropic plugin under `~/.claude/plugins/marketplaces/claude-plugins-official/`). The CI workflow + ship-skill scan cover its blast radius.
- `.github/workflows/scheduled-dogfood-3155.yml` — already neutralized by PR #3402. No further edits.
- `plugin.json` / `marketplace.json` — version is git-tag-derived (per `wg-never-bump-version-files-in-feature`).

## Risks

- **R1 — `show_full_output: true` exposes ALL tool execution results, not just prompt + reasoning** (UPGRADED at deepen-pass per Research Insights §2.1). The action's own docstring states: "outputs ALL Claude messages including tool execution results which may contain secrets, API keys, or other sensitive information. These logs are publicly visible in GitHub Actions." This is a load-bearing warning. **Mitigation:** scope the flip narrowly to `--once` only (AC1 revised). The `--once` template's tool surface is fixed at create time (`--allowedTools Bash,Read,Write,Edit,Glob,Grep`) and the prompt is committed; the only data the agent fetches is a single GitHub issue comment body (D5-pinned, public). For the recurring template, do NOT flip — the action's default `false` is correct. Operators who need recurring-template diagnostics must use the `actions/upload-artifact` pattern with redaction (documented as a sharp edge). The comment block in Step 3b explicitly states this scope distinction.
- **R2 — Sandbox dogfood (`scheduled-dogfood-3403.yml`) joins the same trap class as `scheduled-dogfood-3155.yml`.** Annual re-fire if the sandbox itself fails to neutralize. **Mitigation:** the sandbox uses the FIXED template (AC1+AC3), so its abort path has the verification step. AND its FIRE_DATE is committed to the schedule SKILL learning file, so the operator has a calendar reminder. AND PR #3402 documented the manual-neutralization recipe.
- **R3 — CI workflow noise.** The `pr-auto-close-scanner.yml` workflow comments on every PR with a match, even intentional `Closes #N` body lines. **Mitigation:** the comment is informational (not a check failure); the `<!-- auto-close-scanner: confirm -->` opt-out marker silences subsequent edits; the comment is idempotent (edits prior bot comment, not duplicates). For high-volume PRs this is verbose but never blocking.
- **R4 — Regex over-fit on `GH-N`.** `GH-1234` shows up in copy-pasted log lines (e.g., from CI badges). **Mitigation:** the regex requires a leading auto-close keyword; bare `GH-1234` does not trigger. False positive rate measured during sandbox testing.
- **R5 — Branch B (architectural #3403 split) leaves the abort path unfixed at merge.** Operators using `--once` schedules whose tracked issue closes pre-fire still hit silent failure if the App-token gap is the cause. **Mitigation:** AC2's banner explicitly documents the not-self-cleaning state until verified. AC15's migration sweep surfaces every existing `--once` schedule for operator awareness. The framework-level AC3 verification step IS in place — it cannot rescue an aborted neutralization, but it surfaces the failure visibly post-fire (the bot posts a follow-up comment naming the failure mode).
- **R6 — `github_token` input override (AC1b) widens the action's effective token to the full workflow `GITHUB_TOKEN` permission set.** The workflow-level `permissions:` block declares `contents: write`, `issues: write`, `pull-requests: write`, `id-token: write` — these become the action's effective token scope when `with: github_token: ${{ secrets.GITHUB_TOKEN }}` is passed. This is a deliberate widening (the App-installation token's narrower scope is what blocks #3403). **Mitigation:** the wider token is bounded by the same `--allowedTools Bash,Read,Write,Edit,Glob,Grep` allowlist; the agent cannot reach `gh secret set` or other admin-scope verbs even with the wider token. **Threat model:** a successful prompt injection (gated by D5 comment-author + immutability pin) inside `--once` could now `git push` or `gh pr create` against the repo with the workflow token's full scope; previously the App token's narrower scope provided defense-in-depth. The plan accepts this widening because (a) D5 already gates the prompt-injection vector, (b) the bash-bridge environment had `GH_TOKEN: ${{ github.token }}` access already (the token is not new — only the action-machinery alignment is). **Documented as a sharp edge.**

## Dependencies

- Existing test harness `plugins/soleur/test/test-helpers.sh` (assert_contains, assert_eq, assert_file_exists)
- `gh` CLI (already used pervasively)
- `python3` + `pyyaml` (already used by SKILL.md template validators)
- No new package.json deps; no new pip deps.

## Domain Review

**Domains relevant:** Engineering (CTO)

**Pipeline mode:** This plan is being authored inside a Task subagent (per the planning skill's pipeline detection). Domain leader Tasks are NOT spawned in pipeline mode (Phase 0.5/2.5/3 dispatches skipped per skill instructions). The deepen-plan phase that follows handles deeper specialist routing if required. Engineering implications are documented inline in this plan's Risks section and Research Reconciliation table.

**Status:** auto-deferred to deepen-plan
**Pencil available:** N/A (no UI surface)

This is a tooling/CI/skill-template change with zero user-facing UI. Product/UX gate is NONE per Phase 2.5 mechanical escalation rules (no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files created or edited).

## Sharp Edges

- **Hook fires on workflow-file edits.** `security_reminder_hook.py` warns on any `.github/workflows/*.yml` Edit citing `${{ github.event.* }}` patterns. The new `pr-auto-close-scanner.yml` uses `${{ github.event.pull_request.number }}` (canonical). Per the 2026-05-07 learning file's session error #1, the hook is advisory; if it blocks, retry the same Edit. Do NOT replace the canonical event-context refs with hardcoded values for a non-single-fire workflow (the hardcoding pattern in `scheduled-dogfood-3155.yml` is justified for that specific case only).
- **`gh pr comment` on PR body edits creates noise.** The CI workflow MUST edit a prior bot comment in place when re-firing on `pull_request: edited`, not post fresh comments. Use `gh api repos/<R>/issues/<N>/comments --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | startswith("## Auto-close keyword scanner")))'` to find the existing comment ID, then `gh api -X PATCH .../comments/<ID>`. Document this as a TODO in the workflow body if not implemented in V1; otherwise R3's noise mitigation breaks.
- **`--once` template byte-budget.** Step 3b template is already long (~200 lines). Adding the post-fire verification section + the `show_full_output:` line costs ~25 lines. The HTML markers `<!-- once-template-begin -->` / `<!-- once-template-end -->` are anchors for `schedule-skill-once.test.sh` — do NOT add new YAML fences inside, do NOT remove the markers.
- **AGENTS.md byte budget.** Current rule (`wg-use-closes-n-in-pr-body-not-title-to`) is ~227 bytes; the rewrite projects to ~580 bytes. Compound's pre-commit byte-budget gate fires at 37000 bytes. Run the gate locally before commit:
  ```bash
  wc -c AGENTS.md
  ```
- **Per `cq-agents-md-tier-gate`:** The new rule belongs in AGENTS.md (cross-cutting + silent-failure: the bug pattern fires on any PR creation in any repo, the failure is silent, and within-session repro evidence (#3200, #3402) shows agents do not internalize without the rule loaded every turn). The scanner workflow + ship-skill insertion are the enforcement mechanisms; the rule is the framing.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled with `threshold: none, reason: <one-sentence non-empty reason>` per the gate.
- **`show_full_output: true` is scoped to `--once` only** (deepen-pass research finding, Research Insights §2.1). Operators reading the recurring template should NOT copy this flag from the `--once` template. The action's docstring warns the flag leaks tool execution results which may include secrets. The Step 3a (recurring) comment block above the `with:` block must explicitly NAME this scope distinction. For recurring agent loops needing diagnostics, document the `actions/upload-artifact` redacted-summary pattern (the agent writes a redacted JSON summary to a file, the post-step uploads it as a workflow artifact with retention scoped to operator access).
- **`with: github_token: ${{ secrets.GITHUB_TOKEN }}` is scoped to `--once` only** (deepen-pass research finding, Research Insights §2.3). Recurring templates that delegate to `claude-code-action` should keep the App-installation token as default — it is the narrower scope and aligns with the docs' "if using GitHub App" guidance. The `--once` template's token override is a deliberate alignment fix for the abort-path push, NOT a general pattern.
- **`pr-auto-close-scanner.yml` idempotency.** Use `gh api .../comments --jq '.[] | select(.user.login=="github-actions[bot]" and (.body | startswith("## Auto-close keyword scanner")))'` to find the prior bot comment, then `gh api -X PATCH .../comments/<id>` to edit in place. Without this the scanner will post a fresh comment on every PR-body re-edit (R3 mitigation breaks).
- **Sandbox dogfood (`scheduled-dogfood-3403.yml`) MUST be neutralized post-fire** with the same D4 mechanism this PR is fixing. Add an explicit post-merge-checklist line in the PR body: `[ ] After AC14 sandbox fire, manually neutralize scheduled-dogfood-3403.yml per PR #3402 recipe (regardless of whether D4 self-neutralized successfully — defense in depth).` The sandbox is itself a `0 9 D M *` annual-recurrence trap; relying on its OWN broken D4 to clean it up is recursive.
- **`main` is NOT branch-protected** in this repo (`gh api repos/jikig-ai/soleur/branches/main/protection` returns HTTP 404). The `--once` template's PR-fallback (5b) is therefore optional, not load-bearing for jikig-ai/soleur. Operators who fork the template into a branch-protected repo MUST keep `pull-requests: write` in the permissions block — the comment in the template already says this; flagging here so deepen-pass evidence stays linked.

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Edit `commit-push-pr` directly | The skill is an external Anthropic plugin (`~/.claude/plugins/marketplaces/claude-plugins-official/`), not under our repo control. Cannot ship as a Soleur PR. |
| Block PR creation on auto-close-keyword match | #3407 explicitly says "fail-soft, not block — sometimes `Fix #N` IS the intent". Aligns with the issue's design. |
| Replace `gh pr create` invocations with a wrapped `soleur:open-pr` skill | Boil-the-ocean. The CI workflow + ship-skill scan cover the same ground without forcing every Soleur user to migrate off direct `gh pr create`. |
| Defer #3403 to a separate PR | The arguments explicitly require bundling: #3404 is required to even diagnose #3403. Splitting would mean shipping #3404+#3407 first, then re-opening this branch for #3403 after a sandbox fire window — calendar-coupling overhead. The split contract (Phase 4.2) handles the architectural-gap case without splitting the PR. |
| Use `gh workflow disable` (revert #3153) | App-installation token does not honor `actions: write` (#3153 root cause). Reintroducing this is the regression #3155 fixed. |
| Hand-edit existing `--once` workflows in this PR (proactive migration) | Per `gh workflow list`, three `Scheduled (once):` workflows exist. Two predate the side-effect-verification fix (#3356-followup disk-IO checks); one is the already-neutralized #3155 dogfood. The migration sweep is a post-merge step (AC15) — folding it into this PR conflates correctness fixes with migration mechanics. |

## Effort Estimate

- Phase 0 (preflight + sandbox issue/comment): 15 min
- Phase 1 (write failing tests): 45 min
- Phase 2 (implement edits across SKILL.md, ship.md, AGENTS.md, scanner workflow, sandbox workflow): 90 min
- Phase 3 (GREEN verification): 20 min
- Phase 4 (self-scan + split contract): 10 min (pre-merge); +30 min post-fire (AC14)
- Phase 5 (migration sweep, post-merge): 15 min
- Review + resolve findings (typical for 3-issue bundle): 60 min

**Total pre-merge:** ~4 hours.
**Total post-merge (operator actions):** ~45 min (sandbox fire transcript review + migration sweep + #3403 split decision).

## References

- AGENTS.md rules: `wg-use-closes-n-in-pr-body-not-title-to`, `cq-agents-md-tier-gate`, `cq-agents-md-why-single-line`, `wg-after-merging-a-pr-that-adds-or-modifies`, `rf-review-finding-default-fix-inline`, `cq-write-failing-tests-before`
- Bundle pattern: PR #2486 (kb scope-out drain — `Closes #2467, Closes #2468, Closes #2469`)
- Learning files: `knowledge-base/project/learnings/2026-05-07-pr-title-closes-keyword-ignores-qualifiers-and-d4-silent-failure.md`
- Related open scope-outs: #3390 (acknowledged, not folded in)
- Issue tracker: #3403 (bug), #3404 (enhancement), #3407 (enhancement); ancestor #3185, #3155, #3153, #3402, #3200
- Schedule skill: `plugins/soleur/skills/schedule/SKILL.md` (594 lines)
- Schedule test: `plugins/soleur/test/schedule-skill-once.test.sh`
- External plugin (informational only): `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/commit-commands/commands/commit-push-pr.md`

## Resume prompt (copy-paste after `/clear`)

```text
/soleur:work knowledge-base/project/plans/2026-05-07-feat-drain-once-schedule-dogfood-backlog-plan.md
Branch: feat-one-shot-drain-once-schedule-dogfood. Worktree: .worktrees/feat-one-shot-drain-once-schedule-dogfood/. Issues: #3403, #3404, #3407. Plan complete; deepen-plan next, then implementation. PR-body must contain three `Closes #N` lines. Bundle pattern: PR #2486. Sandbox dogfood (#3403 verification) deferred to post-merge per Phase 4.2 split contract.
```
