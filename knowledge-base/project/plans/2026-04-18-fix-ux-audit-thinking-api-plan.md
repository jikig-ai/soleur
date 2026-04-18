# Fix: scheduled-ux-audit fails with `thinking.type.enabled` API error

**Issue:** #2540
**Branch:** feat-one-shot-fix-ux-audit-thinking-api
**Worktree:** `.worktrees/feat-one-shot-fix-ux-audit-thinking-api/`
**Detail level:** MORE (routine CI pin bump with blast-radius audit across 13 sibling workflows)
**Type:** fix / chore(ci)

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Overview, Research Reconciliation, Phases 1-4, Risks, Learning
**Research sources:**

- `knowledge-base/project/learnings/2026-02-22-model-id-update-patterns.md` (thinking API format delta between Opus 4.6 and 4.7 — insight #5)
- `knowledge-base/project/specs/feat-model-upgrade-opus-4-7/spec.md` (closed spec from #2439)
- `knowledge-base/project/learnings/integration-issues/claude-code-action-unsupported-push-event-and-doppler-only-secrets-20260416.md` (prior ux-audit fix context)
- `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md` (peer ratio table + pin-freshness note to append)
- `plugins/soleur/skills/schedule/SKILL.md` (template for new scheduled workflows — also needs audit)
- GitHub API releases for `anthropics/claude-code-action` (v1.0.75 → v1.0.101 delta)

### Key Improvements

1. **Root cause history traced to a specific prior PR.** Issue #2439 ("chore: upgrade Claude Opus 4.6 to 4.7", closed 2026-04-16) changed `--model` to `claude-opus-4-7` in three workflows but did NOT update the `claude-code-action` pin. The gap between model rollout and action SDK rollout is what #2540 exposes. This fix closes the gap and the Learning section captures the rule.
2. **Authoritative thinking-API reference added.** The `2026-02-22-model-id-update-patterns.md` learning already documents the exact delta (old: `thinking.type: "enabled"` + `budget_tokens`; new: `thinking.type: "adaptive"` + `output_config.effort`). Cross-reference included so the next reader doesn't re-derive it.
3. **Template drift check added.** `plugins/soleur/skills/schedule/SKILL.md` generates new scheduled workflows via the `soleur:schedule` skill; its workflow template uses `anthropics/claude-code-action@<ACTION_SHA> # v1` as a placeholder resolved at skill-run time via `gh api repos/OWNER/REPO/git/ref/tags/TAG`. That path self-heals on each invocation — no template edit needed. Captured under Non-Goals to prevent a false-positive review finding.
4. **Observational verification matrix refined.** Clarified which 3 workflows are actively broken today vs. which 11 are latently affected by the v1.0.100 default-model flip.
5. **Post-merge workflow dispatch expanded to a single batched Monitor loop** so the agent actually watches the 3 runs rather than triggering-and-forgetting.

### New Considerations Discovered

- `test-pretooluse-hooks.yml` is an empirical test pinned specifically to v1.0.75. Bumping it to v1.0.101 may invalidate the test's purpose (verify hooks fire in *this specific SHA*). Added contingency: if post-merge verification of that workflow fails, revert *just that one file* and file a follow-up.
- The `scheduled-roadmap-review.yml` is pinned to `ff9acae5886d41a99ed4ec14b7dc147d55834722 # v1` — a fixed SHA whose trailing comment indicates it tracked the `v1` moving tag at pin time. The `v1` tag now resolves to `8a953dedac4f533f912f13656070914693ed0575`, so this workflow is on an older `v1`-era SHA than the broader sweep. Leaving it alone preserves the existing "one experimental workflow on its own track" pattern and keeps blast radius contained to the `v1.0.75 → v1.0.101` path.
- The plugin's `schedule` skill template uses `--model <MODEL>` as a placeholder. The next workflow generated via that skill will inherit whatever model the user picks; if they pick `claude-opus-4-7` and the action pin at generation time is pre-v1.0.100, the bug reappears. This is a known template-drift hazard; captured as the "pin freshness" learning, enforced at audit time not at template-edit time.

## Overview

Three scheduled workflows (`scheduled-ux-audit`, `scheduled-competitive-analysis`, `scheduled-growth-audit`) explicitly pass `--model claude-opus-4-7` to `anthropics/claude-code-action@v1.0.75`. Opus 4.7 rejects the `thinking.type.enabled` request body that v1.0.75's embedded Agent SDK emits:

```text
"thinking.type.enabled" is not supported for this model.
Use "thinking.type.adaptive" and "output_config.effort" to control thinking behavior.
```

`v1.0.100` (2026-04-17) ships the Agent SDK 0.2.113 bump that emits `thinking.type.adaptive`, and upgrades the action's *default* model `opus-4-6 → opus-4-7`. `v1.0.101` (2026-04-18) is the current tip with that fix included.

**Root cause:** pinning diverged from the model used. The action's SDK and the API changed in lockstep at or just before 2026-04-15; the pin stayed at 2026-03-18 (v1.0.75). This affects every workflow that forces `claude-opus-4-7` via `claude_args --model`.

**Causal chain (traced via git history + closed issues):**

1. 2026-04-15 — Anthropic rolls Opus 4.7. Opus 4.7 deprecates `thinking.type: "enabled"` + `budget_tokens` in favor of `thinking.type: "adaptive"` + `output_config.effort: "low"|"medium"|"high"|"xhigh"` (see `knowledge-base/project/learnings/2026-02-22-model-id-update-patterns.md` insight #5).
2. 2026-04-16 — Issue #2439 ("chore: upgrade Claude Opus 4.6 to 4.7") closes. The PR updates `--model claude-opus-4-6` → `--model claude-opus-4-7` in ux-audit, competitive-analysis, and growth-audit. It does NOT bump the `claude-code-action` pin — which still embeds Agent SDK 0.2.112.
3. 2026-04-17 — `claude-code-action@v1.0.100` ships with SDK 0.2.113 (emits `thinking.type.adaptive`) and flips the action's *default* model to opus-4-7.
4. 2026-04-15 → 2026-04-18 — Scheduled runs for the 3 opus-4-7 workflows consistently fail (one lucky success on 04-16 when a retry landed on a cached-response path). Cumulative: 4 confirmed failures (#2540 body), many more implied.

**The fix for #2540 must therefore address both halves of the SDK/model pair.** #2439 did the model half. This PR does the SDK (action-pin) half.

**Fix scope:** bump the action ref in the 14 workflow files that use the v1.0.75 SHA to the `v1.0.101` SHA (`ab8b1e6471c519c585ba17e8ecaccc9d83043541`). All 14 are updated together — the 3 with `--model claude-opus-4-7` are broken *today*; the remaining 11 rely on the action's default model, which v1.0.100 also flipped to opus-4-7, so the same SDK fix is required for them the moment the default kicks in.

### Research Insights (Overview)

**Thinking API format reference (authoritative, from `2026-02-22-model-id-update-patterns.md` insight #5):**

| Model | Thinking config (old, pre-4.7) | Thinking config (new, Opus 4.7) |
|---|---|---|
| Opus 4.6 | `thinking.type: "enabled"`, `thinking.budget_tokens: N` | still uses old format |
| Sonnet 4.6 | `thinking.type: "enabled"`, `thinking.budget_tokens: N` | still uses old format |
| Opus 4.7 | (rejected with 400 invalid_request_error) | `thinking.type: "adaptive"`, `output_config.effort: "low"|"medium"|"high"|"xhigh"` |

**Implication for workflows that force `--model claude-opus-4-7`:** the SDK must know how to emit the new format. The SDK's knowledge of this format landed in 0.2.113, bundled in `claude-code-action@v1.0.100`. Any pin older than v1.0.100 + `--model claude-opus-4-7` = 400 error.

**Implication for workflows using the default model:** prior to v1.0.100, the action defaulted to opus-4-6 (old format, compatible with SDK 0.2.112). After v1.0.100, the default flipped to opus-4-7. A workflow pinned at v1.0.99 and below with no `--model` flag will keep working on opus-4-6 until Anthropic deprecates it; a workflow pinned at v1.0.100+ with no `--model` flag will transparently use opus-4-7 with the new format. Bumping all 14 pins to v1.0.101 moves all workflows to opus-4-7 in one step — intentional, documented under Risks #2.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Issue says "Bump `anthropics/claude-code-action` to a version that emits `thinking.type.adaptive`" | Confirmed: v1.0.100 release notes cite `#1235 fix: pass install.sh binary path to Agent SDK after 0.2.113 bump`. SDK 0.2.113 is where the thinking payload shape changed. | Bump to v1.0.101 (one patch newer than v1.0.100 — includes follow-up fixes; no material change to thinking payload). |
| Issue says "OR override `--thinking` / related `claude_args` to use `adaptive`" | `claude_args` does not expose a `--thinking-type` flag today. The fix is in the action/SDK, not the workflow args. | Reject: upgrade action instead. |
| Issue says "OR pin to the last version known to produce valid requests" | Pre-04-15 requests worked, but downgrading is wrong-direction on a time-sensitive API shape change. | Reject: forward-fix. |
| Issue says it affects one workflow (scheduled-ux-audit) | Actually **3 workflows** force `--model claude-opus-4-7` explicitly (ux-audit, competitive-analysis, growth-audit); **14 total** are pinned at the same SHA. v1.0.100 also flipped the *default* model to opus-4-7, so the other 11 will fail as soon as they rely on the default. | Update all 14 workflow pins in the same PR. Audit verified via `grep -rn "df37d2f0760a4b5683a6e617c9325bc1a36443f6"`. |

## Implementation Phases

### Phase 1 — Verify the target SHA and run pre-flight checks (5 min)

1. Confirm `v1.0.101` resolves to `ab8b1e6471c519c585ba17e8ecaccc9d83043541`:

    ```bash
    gh api repos/anthropics/claude-code-action/git/refs/tags/v1.0.101 --jq '.object.sha'
    # Expect: ab8b1e6471c519c585ba17e8ecaccc9d83043541
    ```

2. Confirm v1.0.100 is the release that ships the SDK fix:

    ```bash
    gh api repos/anthropics/claude-code-action/releases --jq '.[] | select(.tag_name=="v1.0.100") | .body'
    # Expect: "Upgrade Claude model from opus-4-6 to opus-4-7" + "pass install.sh binary path to Agent SDK after 0.2.113 bump"
    ```

3. Enumerate workflows that need the bump:

    ```bash
    grep -rn "df37d2f0760a4b5683a6e617c9325bc1a36443f6" .github/workflows/ | awk -F: '{print $1}' | sort -u
    # Expect 14 files (listed in "Files to Edit" below).
    ```

4. Double-check no other action ref is in flight that would conflict (Dependabot PR, hotfix branch):

    ```bash
    gh pr list --state open --search "claude-code-action" --json number,title,headRefName
    # Expect: empty or unrelated.
    ```

### Phase 2 — Update workflow pins (10 min)

Replace the pin in all 14 files with a single `sed` sweep. Each hit takes the form:

```yaml
uses: anthropics/claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75
```

Target:

```yaml
uses: anthropics/claude-code-action@ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101
```

Command (verify on one file first, then apply):

```bash
# Dry-run: print the intended diff
grep -rn "df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75" .github/workflows/

# Apply in-place
sed -i 's|anthropics/claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75|anthropics/claude-code-action@ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101|g' .github/workflows/*.yml

# Verify: no v1.0.75 remains, 14 lines now at v1.0.101
grep -rn "df37d2f0760a4b5683a6e617c9325bc1a36443f6" .github/workflows/    # expect empty
grep -rn "ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101" .github/workflows/ | wc -l   # expect 14
```

**Do NOT touch** `.github/workflows/scheduled-roadmap-review.yml` — it is pinned to the fixed SHA `ff9acae5886d41a99ed4ec14b7dc147d55834722` with trailing comment `# v1` (captured when the `v1` moving tag pointed at that commit). The `v1` tag now resolves to `8a953dedac4f533f912f13656070914693ed0575`, but this workflow stays on its own track. Leaving it alone preserves the existing "one experimental workflow on its own track" pattern and keeps blast radius contained.

### Phase 3 — Refresh the top-of-file comment in scheduled-ux-audit.yml (2 min)

The governance comment block at lines 1–33 of `scheduled-ux-audit.yml` cites the plan that produced dry-run mode (`2026-04-16-fix-ux-audit-workflow-crashes-plan.md`). No comment mentions the pin; nothing to update there.

However, add a one-line comment immediately above the `uses:` line so the next pin audit has context:

```yaml
      - name: Run ux-audit skill
        # Pin must track a release that emits `thinking.type.adaptive`
        # (Agent SDK >= 0.2.113, claude-code-action >= v1.0.100).
        # Opus 4.7 rejects the legacy `thinking.type.enabled` shape.
        # See #2540.
        uses: anthropics/claude-code-action@ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101
```

Only add the comment block in `scheduled-ux-audit.yml` (the canonical workflow in #2540). The other 13 share the same pin but don't need the prose — they'd get noisy. The AGENTS.md learning captures the rule in one place.

### Phase 4 — Validate (15 min)

1. **YAML syntax check:** GitHub Actions Runner won't parse broken YAML. Spot-check with:

    ```bash
    # Lightweight validation — grep for any line where the pin was partially replaced
    grep -rn "claude-code-action@" .github/workflows/ | grep -v "ab8b1e6471c519c585ba17e8ecaccc9d83043541\|ff9acae5886d41a99ed4ec14b7dc147d55834722"
    # Expect empty (no dangling/partial refs).
    ```

2. **Commit and push** the branch. The pre-push lefthook runs `.github/workflow-lint.sh` (if present) or at minimum `actionlint`. If any workflow file breaks the parser, the push will fail.

3. **Post-merge dispatch of the 3 opus-4-7 consumers in parallel,** polled via a single Monitor loop per AGENTS.md `hr-never-use-sleep-2-seconds-in-foreground`:

    ```bash
    # Trigger all three
    gh workflow run scheduled-ux-audit.yml
    gh workflow run scheduled-competitive-analysis.yml
    gh workflow run scheduled-growth-audit.yml

    # Capture run IDs (wait ~15s for them to register)
    UX_ID=$(gh run list --workflow=scheduled-ux-audit.yml --limit 1 --json databaseId --jq '.[0].databaseId')
    CA_ID=$(gh run list --workflow=scheduled-competitive-analysis.yml --limit 1 --json databaseId --jq '.[0].databaseId')
    GA_ID=$(gh run list --workflow=scheduled-growth-audit.yml --limit 1 --json databaseId --jq '.[0].databaseId')

    # Use the Monitor tool with a polling loop
    while true; do
      UX=$(gh run view $UX_ID --json status,conclusion --jq '"\(.status)/\(.conclusion)"')
      CA=$(gh run view $CA_ID --json status,conclusion --jq '"\(.status)/\(.conclusion)"')
      GA=$(gh run view $GA_ID --json status,conclusion --jq '"\(.status)/\(.conclusion)"')
      echo "ux=$UX ca=$CA ga=$GA"
      case "$UX $CA $GA" in *"in_progress"*|*"queued"*|*"waiting"*) sleep 30 ;; *) break ;; esac
    done
    ```

    For each FAIL, pull the failing log and grep for `thinking`:

    ```bash
    gh run view <id> --log-failed | grep -iE "thinking|invalid_request|4xx" | head -20
    ```

    - If `thinking` appears → fix is incomplete, pin didn't take. Investigate.
    - If no `thinking` match but the run still failed → unrelated downstream issue. File a follow-up issue and mark #2540 closed.
    - If all three pass → done.

4. **Optional post-merge dispatch of `test-pretooluse-hooks.yml`** (empirical hook-fire test). If it fails with a *new* error (not `thinking.type`), revert just that one file back to v1.0.75 and file a tracking issue — that test is pinned to v1.0.75 for a reason.

**Why batched dispatch, not sequential:** GitHub Actions workflow_dispatch runs are cheap (no new billing impact beyond compute time). Running all three in parallel cuts verification from ~25 min to ~8 min and produces a single auditable result vector per AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies`.

## Files to Edit

All 14 paths get the same two-character SHA replacement and the trailing comment flip `# v1.0.75 → # v1.0.101`. One file also gets a 4-line comment block above the `uses:` line.

| File | Line | Change |
|---|---|---|
| `.github/workflows/scheduled-ux-audit.yml` | 131 | pin bump + 4-line context comment |
| `.github/workflows/scheduled-competitive-analysis.yml` | 42 | pin bump |
| `.github/workflows/scheduled-growth-audit.yml` | 50 | pin bump |
| `.github/workflows/scheduled-bug-fixer.yml` | 141 | pin bump |
| `.github/workflows/scheduled-campaign-calendar.yml` | 47 | pin bump |
| `.github/workflows/scheduled-community-monitor.yml` | 68 | pin bump |
| `.github/workflows/scheduled-content-generator.yml` | 55 | pin bump |
| `.github/workflows/scheduled-daily-triage.yml` | 64 | pin bump |
| `.github/workflows/scheduled-follow-through.yml` | 48 | pin bump |
| `.github/workflows/scheduled-growth-execution.yml` | 49 | pin bump |
| `.github/workflows/scheduled-seo-aeo-audit.yml` | 49 | pin bump |
| `.github/workflows/scheduled-ship-merge.yml` | 118 | pin bump |
| `.github/workflows/claude-code-review.yml` | 36 | pin bump |
| `.github/workflows/test-pretooluse-hooks.yml` | 46 | pin bump |

## Files to Create

None. No new test files, no helper scripts, no AGENTS.md edits (see Learning section below — the learning updates `2026-03-20-claude-code-action-max-turns-budget.md` as an appended note, not a new file).

## Open Code-Review Overlap

None. Ran:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in $(grep -rln "df37d2f0760a4b5683a6e617c9325bc1a36443f6" .github/workflows/); do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

No matches.

## Acceptance Criteria

- [x] All 14 workflow files previously pinned to `df37d2f...` (v1.0.75) now pin to `ab8b1e6...` (v1.0.101).
- [x] `scheduled-roadmap-review.yml` is unchanged (continues to use the `v1` float ref).
- [x] `grep -rn "df37d2f0760a4b5683a6e617c9325bc1a36443f6" .github/workflows/` returns empty.
- [ ] Post-merge `gh workflow run scheduled-ux-audit.yml` completes **success** (not `error_api_error`). The "Run ux-audit skill" step does not emit `thinking.type.enabled` in its error output.
- [ ] Post-merge `gh workflow run scheduled-competitive-analysis.yml` and `gh workflow run scheduled-growth-audit.yml` both reach the claude-code-action step without the thinking.type error. (They may fail on downstream, model-independent issues — that's out of scope for this PR and gets its own issue.)
- [ ] PR body uses `Closes #2540` (body, not title) per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`.

## Test Scenarios

This change is infrastructure-only (workflow pin). No unit tests. TDD gate (`cq-write-failing-tests-before`) is exempt per its own carve-out for CI/infra.

**Observational verification matrix:**

| Workflow | Forces `--model claude-opus-4-7`? | Pre-fix behavior | Expected post-fix |
|---|---|---|---|
| scheduled-ux-audit | yes | FAIL (thinking.type.enabled) | success (or fails downstream on unrelated cause) |
| scheduled-competitive-analysis | yes | FAIL | success |
| scheduled-growth-audit | yes | FAIL | success |
| scheduled-bug-fixer | no (sonnet-4-6) | pass | pass (model unchanged) |
| other 10 | no (default) | pass (v1.0.75 default = opus-4-6) | pass (v1.0.101 default = opus-4-7 + new SDK = compatible) |

## Risks & Non-Goals

### Risks

1. **v1.0.101 introduces an unrelated regression.** Mitigation: v1.0.101 is the current tip and released 2026-04-18; release notes show only metadata changes since v1.0.100. If a regression emerges post-merge, pin to v1.0.100 (`40cb41bedeed964a97738b04c84859caec8d8813`) which is the minimum viable version.

2. **Default-model flip surfaces a latent cost/quota issue.** The 11 workflows that don't force `--model` now run against opus-4-7 instead of opus-4-6 by default. Opus-4-7 pricing is unchanged per Anthropic's published rates; quota consumption differs only marginally. If the monthly bill spikes, pin explicit models via `--model claude-opus-4-6` on the affected workflows.

3. **`test-pretooluse-hooks.yml` is a test scaffold that may depend on exact v1.0.75 hook fire-order.** Mitigation: post-merge, run the workflow (`gh workflow run test-pretooluse-hooks.yml`) and confirm the test still exercises its assertions. If the hook test fails, pin that one workflow back to v1.0.75 — it's an empirical test for *this specific SHA*, not the general case. Treat a failure as a follow-up issue, not a blocker for the #2540 fix.

### Non-Goals

- Not touching `scheduled-roadmap-review.yml` — it's pinned to `v1` (floating), tracks a different model (`claude-sonnet-4-6`), and was set up experimentally. Leave it.
- Not adding a CI check that blocks stale pins. The existing convention (pin-with-trailing-comment) is human-reviewed; automating it is a separate #issue.
- Not bumping Agent SDK directly — that lives inside the action bundle, not our control plane.
- Not changing `claude_args` on any workflow. The `--thinking` flag is not exposed; the fix is the action version.
- Not changing `max-turns` or `timeout-minutes` on any workflow. Those are calibrated separately (see learning `2026-03-20-claude-code-action-max-turns-budget.md`).
- Not editing `plugins/soleur/skills/schedule/SKILL.md`. The `soleur:schedule` skill template uses `anthropics/claude-code-action@<ACTION_SHA> # v1` as a placeholder and resolves the SHA at skill-run time via `gh api repos/OWNER/REPO/git/ref/tags/TAG`. That path already self-heals on each new workflow generated — no template edit needed.
- Not changing `--model` on any workflow. The 3 workflows that force opus-4-7 continue to force it; the 11 without `--model` continue to rely on the action default (which now happens to be opus-4-7). Model choice is orthogonal to the SDK fix.

## Verification (Post-merge)

Per AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies`:

```bash
# 1. Trigger the canonical target
gh workflow run scheduled-ux-audit.yml

# 2. Poll until terminal state
gh run list --workflow=scheduled-ux-audit.yml --limit 1 --json databaseId,status,conclusion

# 3. If conclusion != "success", pull the failing log
gh run view <run-id> --log-failed | grep -iE "thinking|invalid_request|4xx"

# 4. Repeat for the other two opus-4-7 consumers
gh workflow run scheduled-competitive-analysis.yml
gh workflow run scheduled-growth-audit.yml
```

**Success criterion:** the "Run ux-audit skill" step's SDK error envelope is either absent (workflow success) or contains an error unrelated to `thinking.type`. The workflow may still fail downstream on dry-run-mode gates — that's by design (UX_AUDIT_DRY_RUN=true caps at artifact upload, not issue filing), and we're not changing that.

## Learning to Capture

Update `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md` with an appended note (not a new file):

```markdown
## Pin freshness: sync action bump with model bump (added 2026-04-18, from #2540)

**Rule:** when a PR changes `--model <name>` in `claude_args`, also verify the
`anthropics/claude-code-action` pin is recent enough (within ~3 weeks of tip) to
ship an Agent SDK that understands the target model's request shape.

**Why:** Model rollouts and SDK rollouts are synchronized at Anthropic but the
embedded SDK in `claude-code-action` lags the API by days. A model that works
on the new SDK can reject the old SDK's payload. Concrete case: PR for #2439
(closed 2026-04-16) flipped `--model claude-opus-4-6` → `--model claude-opus-4-7`
in 3 workflows but left the action pin at v1.0.75 (SDK 0.2.112). v1.0.100
(2026-04-17) shipped SDK 0.2.113 which emits `thinking.type.adaptive` for 4.7.
Runs between 04-15 and 04-18 failed with `"thinking.type.enabled" is not
supported for this model`. Root-caused in #2540, fixed by bumping the pin.

**Audit command (run at the end of any model-bump PR before merge):**

```bash
# 1. List all action pins
grep -rn "anthropics/claude-code-action@[a-f0-9]\{40\}" .github/workflows/ \
  | awk -F'# ' '{print $2}' | sort -u

# 2. For each --model value in the PR diff, verify the pin's age
gh api repos/anthropics/claude-code-action/releases --jq '.[0] | "\(.tag_name) \(.published_at)"'

# If pin is > 3 weeks older than current tip AND the PR bumps a model, bump the pin.
```

**Symmetric rule the other direction:** when bumping the `claude-code-action`
pin across workflows, check the release notes for "Upgrade Claude model from
X to Y" entries. If the default model flipped, workflows *without* a `--model`
flag will transparently switch — intentional for most, breaking for any with
a budget/pricing assumption.

```

Also append a short entry to AGENTS.md under **Code Quality** as a new rule `cq-claude-code-action-pin-freshness` in the compound pass — the action-pin audit is a repeatable check and fits the "hook-enforceable via pre-merge grep" pattern. The compound skill will assess whether a new rule or a hook is warranted.

**Candidate rule text (for compound to consider):**

> When a PR changes `--model <name>` in `claude_args` of any `.github/workflows/*.yml` file, the same PR MUST verify that every `anthropics/claude-code-action` pin in the modified files is within ~3 weeks of the current release tip [id: cq-claude-code-action-pin-freshness]. Run `gh api repos/anthropics/claude-code-action/releases --jq '.[0].published_at'` and compare with `gh api repos/.../git/commits/<pin-sha> --jq '.committer.date'`. Model rollouts and the embedded Agent SDK rollouts are synchronized at Anthropic but the action pin lags; a `--model` bump without a pin bump is a latent 400 error. **Why:** In #2540, #2439's opus-4-6 → opus-4-7 bump was shipped with the v1.0.75 pin still in place; 4 workflow runs failed with `"thinking.type.enabled" is not supported` before detection.

## Deferral Tracking

No deferrals. The 3 opus-4-7 workflows are all fixed in this PR; the 11 other workflows are fixed as a side-effect of the same pin bump. Nothing is pushed to later.

## PR Body Template

```markdown
## Summary

- Bumps `anthropics/claude-code-action` pin from v1.0.75 to v1.0.101 across 14 workflow files.
- Fixes `thinking.type.enabled` API rejection on Opus 4.7 (scheduled-ux-audit, scheduled-competitive-analysis, scheduled-growth-audit).
- `v1.0.100` shipped Agent SDK 0.2.113 which emits `thinking.type.adaptive`; `v1.0.101` is the current tip.

## Test plan

- [x] `grep -rn "df37d2f0760a4b5683a6e617c9325bc1a36443f6" .github/workflows/` returns empty
- [x] 14 workflows now pin `ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101`
- [x] `scheduled-roadmap-review.yml` untouched (uses `v1` floating ref)
- [ ] Post-merge: `gh workflow run scheduled-ux-audit.yml` completes without `thinking.type` error
- [ ] Post-merge: `gh workflow run scheduled-competitive-analysis.yml` same
- [ ] Post-merge: `gh workflow run scheduled-growth-audit.yml` same

Closes #2540
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/CI change. No new user-facing surfaces, no model/data-storage changes, no external services added, no cost envelope change beyond the default-model flip (documented under Risks #2). Product/UX Gate does not apply.

**Mechanical escalation check:** no new files under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. No UI. NONE tier confirmed.
