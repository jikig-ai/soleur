---
module: planning
date: 2026-05-20
problem_type: logic_error
component: plan_skill
symptoms:
  - "Plan body claimed a cross-referenced #N was a 'fabricated PR reference' because `gh pr view N` failed"
  - "The same #N actually resolved as a real CLOSED issue via `gh issue view N`"
root_cause: insufficient_probe
severity: low
tags: [planning, github-cli, pr-vs-issue, route-to-definition]
synced_to: [soleur:plan, soleur:go]
---

# Plan-time PR-vs-issue disambiguation and self-derived in-body counts

## Problem

Two recurring sharp edges surfaced during scaffolding PR #4122 (apply-web-platform-infra.yml workflow, closes #4114):

### A. False "fabricated PR" claim from one-sided probe

Issue #4114's body cross-referenced `PR-H #3244 / #4066`. The plan-deepen subagent ran `gh pr view 3244`, got `Could not resolve to a PullRequest`, and concluded `#3244` was a "fabricated PR reference" — flagging the discrepancy in the plan's Enhancement Summary and removing the reference from the Overview.

Reality: `#3244` is a legitimate **closed umbrella issue** (`feat: Command Center server-side agentic runtime`) which PR #4066 (PR-H) closes one acceptance criterion of. PR-H's body itself reads `Closes umbrella **#3244**'s outstanding acceptance criterion` and `Ref #3244 (umbrella stays open until operator AC-PM5 flips post-merge)`. The plan author's probe was correct (`gh pr view 3244` does fail), but the conclusion was wrong — GitHub numbers are unified across PRs and issues; "not a PR" does not mean "fabricated."

Caught at multi-agent review by `git-history-analyzer`, which ran the symmetric `gh issue view 3244` probe and found the issue.

### B. Plan-prose count carried into workflow header without re-deriving

The plan's §Phase 0.3 estimated `~40 resources after /work expansion`. After `/work` ran the actual grep, the count was 67. The workflow header inherited an off-by-one from the plan's mental tally — `"68 explicit targets"` (line 16) and `"~68 targets"` (timeout-minutes budget comment) — even though `grep -c '\-target=' .github/workflows/apply-web-platform-infra.yml` returns 67.

Caught at multi-agent review by `code-quality-analyst` + `pattern-recognition-specialist`.

## Solution

Both fixed inline in commit `c89e07c9`:

- Plan body Overview rewritten to disambiguate: `#3244` cited as the legitimate closed umbrella issue (`PR #4066 closes one criterion of umbrella issue #3244`).
- Workflow header L16 and L105 corrected to `67 explicit targets` and `~67 targets`. Added a 5-line `ALLOW-LIST MAINTENANCE` comment block above the `terraform plan` step pointing future authors at the matching `-target=` insertion site and the `scheduled-terraform-drift.yml` backstop.

## Key Insight

**GitHub `#N` references are unified across PRs and issues.** A one-sided probe (`gh pr view N` OR `gh issue view N`) is necessary-but-not-sufficient to declare a reference fabricated/unresolved. The symmetric probe is two lines of bash:

```bash
gh pr view N --json state,title 2>&1 || true
gh issue view N --json state,title 2>&1 || true
```

`/soleur:go` already encodes this pattern for route-time disambiguation (see SKILL.md §"PR-vs-issue type resolution"). The same rule must apply at plan-time when an issue body cross-references `#N`.

**Counts in comments/header prose must be derived at write-time, not carried from plan-prose estimates.** Plan §Phase X says `~40 resources` → /work runs the grep → /work writes the count to the workflow header. If the header quotes a count, derive it from the workflow file itself, not the plan: `grep -cE '^[[:space:]]+-target=' <workflow>`.

## Prevention

1. **Plan/deepen-plan probe protocol.** When the plan author runs `gh pr view N` for a cross-referenced number and receives `Could not resolve to a PullRequest`, the IMMEDIATE next action is `gh issue view N`. Only after BOTH probes fail may the number be flagged as fabricated. Recommended skill edit: `/soleur:plan` and `/soleur:deepen-plan` should add a Sharp Edges bullet enforcing the symmetric-probe rule.
2. **In-body count derivation.** Workflow/script header counts must be re-derived from the artifact itself at write-time (`grep -c`, `wc -l`, etc.). Plan-prose count estimates are starting hypotheses, not facts. When `/work` writes a count into a workflow comment, the count derivation grep must run on the as-written file, not on the plan body.

## Session Errors

1. **PreToolUse `security_reminder_hook.py` silently blocked first `Write` of `.github/workflows/apply-web-platform-infra.yml` despite the workflow already using the safe env-var routing pattern for `github.event.head_commit.message`.** The hook printed a "Be aware of these security risks" message that reads as advisory, but the file did not land (`ls` returned no such file). Re-issuing the identical Write on the second attempt succeeded. **Recovery:** re-issued Write with identical content. **Prevention:** the hook's message phrasing ("Be aware of these security risks") suggests advisory behavior but is blocking on first invocation. Consider differentiating advisory vs blocking phrasing in `.claude/hooks/security_reminder_hook.py`, OR add a one-line note to the hook output explaining the "retry once" behavior.

2. **Plan body falsely declared `#3244` fabricated.** Documented as Problem A above. **Recovery:** corrected plan + flagged the symmetric-probe rule for `/soleur:plan` route-to-definition. **Prevention:** when the plan/deepen-plan author runs `gh pr view N` for a cross-referenced number and it returns `Could not resolve to a PullRequest`, run `gh issue view N` BEFORE concluding the reference is unresolved.

3. **Off-by-one in workflow header target count** (`68` quoted vs `67` actual). Documented as Problem B above. **Recovery:** inline edit to `67`. **Prevention:** when a workflow's header quotes a count of in-body items, derive the count via grep on the as-written file, not from plan-prose estimates.
