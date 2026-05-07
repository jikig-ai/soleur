---
date: 2026-05-07
category: integration-issues
related_issues: ["#3403", "#3404", "#3407", "#3185", "#3155", "#3200", "#3402", "#3420"]
related_prs: ["#3411", "#3402", "#3200", "#3155"]
related_rules: ["wg-use-closes-n-in-pr-body-not-title-to", "cq-agents-md-tier-gate", "rf-review-finding-default-fix-inline"]
related_learnings: ["2026-05-07-pr-title-closes-keyword-ignores-qualifiers-and-d4-silent-failure.md"]
tags: [claude-code-action, scheduled-workflows, github-auto-close, silent-failure, dogfood, programmatic-enforcement, exit-code-propagation, token-context-split, show-full-output, sandbox-recurrence-trap]
synced_to: []
---

# Learning: `claude-code-action` boundary semantics + auto-close keyword trap — bundled fix for #3403/#3404/#3407

Six interdependent insights, all surfaced by PR #3411 closing three sibling deferred-scope-outs filed from the post-merge dogfood of #3185. Three are facets of the same `claude-code-action`-as-an-action-boundary problem; three are about programmatic enforcement replacing documentation-as-defense.

See [`2026-05-07-pr-title-closes-keyword-ignores-qualifiers-and-d4-silent-failure.md`](./2026-05-07-pr-title-closes-keyword-ignores-qualifiers-and-d4-silent-failure.md) for the predecessor learning that documented the original symptoms; this learning captures the bundled remediation.

## Problem

Three deferred-scope-out issues (#3403/#3404/#3407) all traced to the same post-merge dogfood (#3185, verifying #3155's D4 abort-path neutralization). The dogfood fired on 2026-05-05, exited `success`, and produced zero observable side-effects despite `permission_denials_count: 1` — diagnostically opaque because `claude-code-action`'s default hides the SDK transcript. Within the same session, two PRs (#3200 then #3402) closed #3185 prematurely via the `Closes #N` auto-close keyword in different markdown contexts (title qualifier; body checkbox).

## Insight 1 — Agent-prompt `exit 1` is swallowed by `claude-code-action`'s tool-call boundary

A `Bash` tool call's exit code lands in the SDK transcript as **data**, not as the workflow step's exit code. When a verification step inside the agent prompt detects "neutralization claimed success but `schedule:` still present" and exits 1, `claude-code-action` records it in the transcript but the **workflow conclusion is unaffected** — the step (and the run) reads `success`.

To genuinely fail a workflow conclusion based on side-effect verification, the verification MUST run as a real GHA-shell post-step OUTSIDE the action.

```yaml
- name: One-time fire (with self-neutralization)
  uses: anthropics/claude-code-action@<SHA> # v1
  with:
    # in-prompt verification is observational only —
    # it can post a comment but cannot fail the run
    ...

- name: Post-fire verification (#3403)
  if: always()
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    set -uo pipefail
    for attempt in 1 2 3; do
      CONTENT=$(gh api "repos/$REPO/contents/.github/workflows/$WORKFLOW_NAME" --jq .content | base64 -d)
      STILL_HAS_SCHEDULE=$(printf '%s' "$CONTENT" | grep -cE '^[[:space:]]*schedule:' || true)
      [[ "$STILL_HAS_SCHEDULE" == "0" ]] && exit 0
      sleep 10  # contents API replication lag
    done
    echo "::error::Post-fire verification failed"
    exit 1
```

The post-step uses `secrets.GITHUB_TOKEN` (workflow scope) and only READS via the contents API — `claude-code-action`'s App-token revocation does not affect it. The 3-attempt retry tolerates the contents API's <5s typical / up to 60s pathological replication lag.

The schedule SKILL.md's prior comment "Do NOT add any post-step to this workflow file" was correct only for *agent-driven WRITES* (which would silently fail with the revoked App token). It conflated writes with reads. The bundle PR clarifies this distinction inline.

## Insight 2 — `show_full_output: true` is a `--once`-only flag

The `claude-code-action` docstring warns:

> "outputs ALL Claude messages including tool execution results which may contain secrets, API keys, or other sensitive information. These logs are publicly visible in GitHub Actions."

"Tool execution results" includes the output of any `Bash`/`Read`/`Glob` call the agent makes. For `--once` workflows whose prompts are committed verbatim with a fixed `--allowedTools` allowlist (`Bash,Read,Write,Edit,Glob,Grep`) and no `secrets.*` interpolation, the leak risk is bounded to whatever the agent reads. For recurring workflows, the operator hand-edits the prompt over time → unbounded surface.

The bundle's #3404 fix scopes the flip to `--once` only:

| Template | `show_full_output` |
|---|---|
| Step 3b `--once` template | `true` (committed prompt, fixed tool surface, no `secrets.*` in prompt) |
| Step 3a recurring template | action default `false` |

A long anti-copy comment block on the recurring template warns operators against pasting the flag, AND a new lefthook gate (`scripts/lint-scheduled-show-full-output.sh`) mechanically forbids it: any workflow whose `name:` does NOT start with `"Scheduled (once):"` and contains `show_full_output: true` is rejected unless waived with `# allow-show-full-output: <reason>`.

Pattern: documentation-as-defense kept failing → migrate to programmatic enforcement.

## Insight 3 — Token-context split inside `claude-code-action` is the prime suspect for #3403's silent denial

The action accepts a `with: github_token` input that overrides the App-installation token (per `action.yml`: `OVERRIDE_GITHUB_TOKEN: ${{ inputs.github_token }}`). Without this input, the bash subprocess runs with `env: GH_TOKEN: ${{ github.token }}` (workflow scope) while inner action machinery uses the App-installation token (narrower).

For `git push origin HEAD:main` from inside the bash bridge, the effective token is unclear. The 2026-05-05 fire's `permission_denials_count: 1` with run conclusion `success` and zero observable side-effects is consistent with a denial deep inside the action's bash bridge.

Adding `github_token: ${{ secrets.GITHUB_TOKEN }}` to the `with:` block aligns both paths to the workflow `GITHUB_TOKEN` permissions. Validation deferred to the post-merge sandbox dogfood (`scheduled-dogfood-3403.yml`, fires on-demand via `workflow_dispatch`). If the candidate fix is necessary AND sufficient, #3403 closes via Branch A of the plan's split contract; otherwise the architectural App-token gap gets a follow-up issue (Branch B) and the framework-level fixes (Insight 1's post-step, Insight 2's transcript visibility) ship anyway.

The bundle PR also extends `cq-agents-md-tier-gate` rule to recognize `[scanner-enforced:]` alongside `[hook-enforced:]` and `[skill-enforced:]` — the new `[scanner-enforced:]` tag flavor for fail-soft CI gates.

## Insight 4 — GitHub auto-close keyword regex is markdown-blind across the full keyword family

GitHub's parser fires on `(close|fix|resolve)[sd]?` + `#N` / `GH-N`, anywhere in title or body, including markdown checkboxes / code blocks / blockquotes / prose. Markdown is invisible to the parser. PR #3185 was closed twice in three days by the same trap:

- **#3200** title contained `(Closes #3185 after fire)` → parser ignored the parenthesized qualifier.
- **#3402** body contained `- [ ] Post-merge: close #3185 with a final "manual neutralization landed" comment.` → parser ignored the checkbox markdown AND fired on `close #3185` while the same body's #3407 issue body literally documented the trap.

Documentation-only enforcement (the prior AGENTS.md rule which framed the issue as "title-only") failed within the same session that authored the rule.

The bundle's #3407 fix:
1. **Shared regex helper** [`plugins/soleur/skills/ship/scripts/auto-close-scan.sh`](../../../plugins/soleur/skills/ship/scripts/auto-close-scan.sh):
   ```
   \b(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#[0-9]+|GH-[0-9]+)\b
   ```
2. **CI surface** [`.github/workflows/pr-auto-close-scanner.yml`](../../../.github/workflows/pr-auto-close-scanner.yml) — fires on `pull_request: opened, edited`, idempotent bot comment (PATCH-in-place via `gh api --paginate ?per_page=100`), fail-soft with `<!-- auto-close-scanner: confirm -->` opt-out marker.
3. **Agent-side surface** in ship SKILL.md Phase 6 pre-creation scan — surfaces matches before `gh pr edit`/`gh pr create`. This is the only **blocking** layer; the CI workflow is observational (the auto-close has already fired by the time CI runs on `pull_request: opened`).
4. **Generalized AGENTS.md rule** for the full keyword family with `[scanner-enforced:]` tag, 571 bytes (under 600-byte cap).

The single shared regex prevents the drift class where regex updates miss one of the surfaces.

## Insight 5 — Sandbox dogfoods are themselves recurrence traps; design them to fail safely

Original `scheduled-dogfood-3155.yml` had `cron: '0 9 5 5 *'`. When the abort path silently failed (Insight 1), no manual neutralization was triggered. PR #3402 had to manually strip `schedule:` from the file. Without that intervention the workflow would have re-fired every May 5th annually, hitting the same broken D4 mechanism each year.

The new `scheduled-dogfood-3403.yml` learns from this:
- **Trigger:** `workflow_dispatch:` only — no `schedule:` cron. Operator manually fires post-merge with `gh workflow run scheduled-dogfood-3403.yml`. No annual recurrence is structurally possible.
- **D3 (date guard):** disabled in the prompt with an explicit SANDBOX MODIFICATION note. With no cron, cross-year defense is irrelevant; the date guard would only block on-demand re-runs.
- **Idempotency:** precondition step skips if issue #3420 is already CLOSED; post-step `if: always()` reopens #3420 so the workflow is re-runnable. Multiple fires capture multiple transcripts with no state drift.

Shape: a one-time diagnostic instrument should be `workflow_dispatch:` with self-resetting state, not a `--once` cron with manual cleanup. The latter trades a bounded recurrence trap for the very class of bug being diagnosed.

## Insight 6 — Scope-out dissent → fix-inline (the simplicity-reviewer protocol works)

Two scope-out filings drew DISSENT during the review-resolution phase:

- **Template extraction** (move `--once` template from inline-in-SKILL.md to `references/once-template.yml`): claimed `architectural-pivot`. Dissent: "the inline-template pattern lives only in the schedule skill (one top-level dir), not 'across the codebase' — fails the architectural-pivot definition. Fix-inline OR drop." Reviewer was correct.
- **Lint gate for `show_full_output: true` in recurring schedules**: claimed `architectural-pivot`. Dissent: "a single grep script is a routine gate addition with an obvious default design — not architectural-pivot. Fix-inline."

Both dissents flipped the disposition correctly:
- Lint gate: fix-inlined as `scripts/lint-scheduled-show-full-output.sh` + lefthook entry. ~50 lines, surfaces immediately on staged-workflow edits.
- Template extraction: dropped from this PR. The cost-benefit didn't favor a 700-line refactor mixed with a 3-issue bundle; the genuine simplicity-reviewer's other point ("done as its own follow-up PR with shared-extractor design, that follow-up IS the architectural-pivot") was acknowledged but not filed — would re-enter normal /soleur:plan flow if the maintenance pressure justifies it.

The simplicity-reviewer pre-filing co-sign is precisely what blocks the rationalization "I don't feel like fixing this here, let me invent a criterion." The DISSENT is fail-safe toward fix-inline. PR #3411 demonstrates the protocol works as designed.

## Solution

Bundle PR #3411 ships:

| Surface | Change |
|---|---|
| `plugins/soleur/skills/schedule/SKILL.md` Step 3b (`--once`) template | `show_full_output: true`, `github_token: ${{ secrets.GITHUB_TOKEN }}`, in-prompt Post-fire verification (observational), real GHA-shell Post-fire verification post-step (load-bearing). |
| Step 3a (recurring) template | Anti-copy comment blocks for both `show_full_output` and `github_token`. |
| Schedule SKILL.md "Known Limitations" | New bullet documenting `--once` D4 abort-path silent failure (#3403) and migration sweep recipe. |
| `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` | New shared regex helper (`LC_ALL=C` pinned, fail-soft, line-prefix output). |
| `plugins/soleur/skills/ship/SKILL.md` Phase 6 | Pre-creation scan section before `gh pr edit` / `gh pr create`. |
| `.github/workflows/pr-auto-close-scanner.yml` | New CI gate, idempotent bot-comment edit-in-place, fail-soft with opt-out marker. |
| `.github/workflows/scheduled-dogfood-3403.yml` | New post-merge sandbox; `workflow_dispatch:`-only; idempotent precondition+reopen post-steps; load-bearing post-step verification. |
| `AGENTS.md` rule `wg-use-closes-n-in-pr-body-not-title-to` | Generalized to full `(close\|fix\|resolve)[sd]?` family + `#N`/`GH-N` + markdown-blindness; tagged `[scanner-enforced:]`. |
| `AGENTS.md` rule `cq-agents-md-tier-gate` | Extended to enumerate `[scanner-enforced:]` alongside `[hook-enforced:]` / `[skill-enforced:]`. |
| `scripts/lint-scheduled-show-full-output.sh` + lefthook | New gate forbids `show_full_output: true` in non-`Scheduled (once):` workflows; waiver via `# allow-show-full-output: <reason>`. |
| Tests | `auto-close-scanner.test.sh` (23/23 incl. parameterized 9-keyword matrix), `schedule-skill-once.test.sh` (42/42 incl. TS8/TS9/TS10 for show_full_output, github_token, post-fire verification). |

## Prevention

- **`claude-code-action` writes belong in agent prompts; reads belong in post-steps.** Whenever a workflow needs to verify a side-effect that the agent claims, do the verification in a `- run:` post-step using `secrets.GITHUB_TOKEN`. The action's tool-call boundary is the wrong layer for workflow-conclusion enforcement.
- **`show_full_output: true` is `--once`-only by lint.** The lefthook gate now enforces this mechanically. Operators who add the flag to a recurring workflow get an immediate failure with a clear message; waiver requires an explicit comment naming the reason.
- **Token context inside `claude-code-action` is unclear; pass `with: github_token`** whenever the agent prompt issues writes that touch branch-protected resources. The App-installation token's runtime scope can silently differ from the workflow `GITHUB_TOKEN`'s declared permissions.
- **Auto-close keyword scanner has two surfaces but one regex.** Any future regex update touches `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` only. Both the CI workflow and the ship SKILL.md Phase 6 scan delegate to the same script.
- **Sandbox dogfoods use `workflow_dispatch:` only.** Never use `schedule:` cron for diagnostic instruments — the cron's recurrence trap reproduces the very class of bug being diagnosed.
- **Trust simplicity-reviewer dissents.** The protocol's DISSENT-fails-toward-fix-inline behavior caught two over-stretched `architectural-pivot` claims this PR. Don't argue with the dissent; either fix-inline or drop the finding.

## Session Errors

- **GraphQL rate limit exhausted** on `gh issue create` for sandbox issue #3420.
  - **Recovery:** Checked `gh api rate_limit --jq .resources` (reset ~50s); reordered work to do non-API edits first; resumed when GraphQL bucket refilled.
  - **Prevention:** At session start, check `gh api rate_limit` so an early-session burst (issue creation, PR list, etc.) doesn't deplete the bucket halfway through.
- **PreToolUse `security_reminder_hook` fired twice** on workflow YAML Writes (`pr-auto-close-scanner.yml` and `scheduled-dogfood-3403.yml`).
  - **Recovery:** Hook is advisory; retried each Write successfully.
  - **Prevention:** Already documented in plan Sharp Edges; no new action needed.
- **`tasks.md` already existed** (written by deepen-plan subagent), so first Write attempt failed.
  - **Recovery:** Read first, then Edit.
  - **Prevention:** When invoked downstream of plan/deepen-plan, always Read existing spec files before Writing — they may have been seeded.
- **Schedule test TS1 anti-regression false-positive** after adding the verification post-step.
  - **Recovery:** Updated the assertion from "no post-steps" to "the only allowed post-step is named 'Post-fire verification (#3403)'".
  - **Prevention:** When adding deliberate exceptions to anti-regression rules, update both the rule's wording AND the underlying intent comment so future readers know the new exception is genuinely safe.
- **AGENTS.md `cq-agents-md-tier-gate` rule exceeded 600-byte cap** after adding `[scanner-enforced:]` enumeration (663 bytes).
  - **Recovery:** Trimmed prose; final 553 bytes.
  - **Prevention:** When adding to AGENTS.md rules, measure the new byte length BEFORE deciding the wording: `awk '/<id>/ {print length($0)}' AGENTS.md`.
- **code-simplicity-reviewer DISSENTed twice** on scope-out filings; both correctly identified them as fix-inline candidates.
  - **Recovery:** Fix-inlined the lint gate; dropped template extraction from this PR.
  - **Prevention:** The simplicity-reviewer protocol IS the prevention — pre-filing co-sign caught both rationalizations.
- **Forwarded from plan/deepen session-state.md:** Phase 4.5 (network-outage gate) false-positive trigger on `timeout` keyword.
  - **Recovery:** Telemetry-only; no action.
  - **Prevention:** Deepen-plan's gate could refine its keyword list, but the gate's "fail-soft and report" posture handled it correctly.

## Related Documents

- [`2026-05-07-pr-title-closes-keyword-ignores-qualifiers-and-d4-silent-failure.md`](./2026-05-07-pr-title-closes-keyword-ignores-qualifiers-and-d4-silent-failure.md) — predecessor learning capturing the original symptoms across #3200 and #3402.
- PR #3402 — manual neutralization of `scheduled-dogfood-3155.yml` (the recurrence-trap precedent).
- PR #3411 — bundle fix shipping all six insights.
