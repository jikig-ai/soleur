---
date: 2026-05-09
category: best-practices
tags: [agents-md, rule-ids, plan-skill, deepen-plan-skill, multi-agent-review]
issue: "#3485"
pr: "#3486"
---

# Learning: LLM-authored plans cite fabricated and retired AGENTS.md rule IDs; multi-agent review catches them, single-pass review does not

## Problem

The `deepen-plan` subagent that authored the #3485 remediation runbook cited two AGENTS.md rule IDs that did not exist:

- **`cq-when-a-pr-has-post-merge-operator-actions`** — fabricated. Not in active AGENTS.md, not in `scripts/retired-rule-ids.txt`. Cited 3x across the plan as the load-bearing rationale for "use `gh issue close` post-apply, not `Closes #3485` in PR body".
- **`cq-gh-issue-label-verify-name`** — retired 2026-04-23 (per `scripts/retired-rule-ids.txt`: "gh rejects invalid --label with clear error before issue creation"). Cited 2x as the rationale for the live `gh label list` check.

Both citations were structurally indistinguishable from real ones (correct prefix `cq-`, plausible naming convention, accompanying behavioral description). The plan still made sense if you didn't grep for the rule IDs — the cited behaviors are correct independent of whether the rule exists.

The plan was about to merge with these zombie citations until the `code-quality-analyst` review agent grepped AGENTS.md for each cited ID and surfaced both as P1 findings.

## Root Cause

Two compounding factors:

1. **The plan was written by an LLM (deepen-plan subagent) which generalized "this is the kind of thing AGENTS.md would have a rule for" into a rule ID without verifying existence.** The fabricated ID's prefix and shape match the project's naming convention so well that the citation reads as authentic.
2. **No automated link-check exists for AGENTS.md rule citations in `knowledge-base/project/{plans,specs,learnings}/**`.** A plan can reference any string and ship — the only catch is human review.

The retired ID is a special case: it _did_ exist on `main` at one point, so a deepen-plan run that learned the project before 2026-04-23 might cite it confidently. The retirement registry (`scripts/retired-rule-ids.txt`) is the source of truth, but plan/deepen-plan don't consult it.

## Solution

### Inline fix (PR #3486 commit `878680d8`)

Replaced both citations:

- All 3 `cq-when-a-pr-has-post-merge-operator-actions` → `wg-use-closes-n-in-pr-body-not-title-to` (the real auto-close-keywords-trigger-anywhere rule that explains why this artifact-only PR uses `Ref #3485` not `Closes #3485`).
- Both `cq-gh-issue-label-verify-name` citations: dropped the AGENTS.md attribution; the convention now lives in the planning skills (verified at `plan/SKILL.md:721`, `deepen-plan/SKILL.md:556`). Added a parenthetical noting the retirement and reason.

### Detection that worked

Multi-agent review with `code-quality-analyst` ran a verification grep on every cited rule ID:

```bash
grep -E "id: (<cited-id>)" AGENTS.md scripts/retired-rule-ids.txt
```

This found both bugs in one pass. Single-pass LLM review (no separate verifier) consistently misses this class — the citations are too plausible to flag without a grep.

## Key Insight

**LLM-authored plans treat rule IDs as plausible-sounding tokens, not as facts that must exist in a registry.** This is the same failure mode as hallucinated URLs and hallucinated CLI flags: an LLM completes a citation that fits the local pattern without round-tripping to the source. The citation is silent until someone greps for it.

The fabrication is high-leverage because:

- Citations propagate: a plan citing fabricated rule X gets read by the next agent, which now believes X exists and may cite it again.
- They are content-free: the surrounding prose explains the behavior, so no test or build step depends on the ID resolving.
- They erode AGENTS.md's role as canonical truth — readers can't trust that a cited ID is a real rule.

## Prevention

### Skill-level (plan + deepen-plan)

Add a rule-ID verification step to both `plan` and `deepen-plan` skills. Before any commit:

```bash
# Extract every cited rule ID from the new/modified plan
grep -oE '\b(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]+' <plan-file> | sort -u | while read -r id; do
  # Verify it exists (active or retired)
  if ! grep -qE "\[id: ${id}\]" AGENTS.md && \
     ! grep -qE "^${id} " scripts/retired-rule-ids.txt; then
    echo "FABRICATED: $id"
  elif grep -qE "^${id} " scripts/retired-rule-ids.txt; then
    echo "RETIRED: $id (do not cite as active)"
  fi
done
```

If any IDs are fabricated or retired, fail the skill before the commit.

### Multi-agent review keeps catching it

Even with a skill-level check, multi-agent review (specifically `code-quality-analyst`) is the second line of defense. Continue invoking it on plan-only PRs even though the change is "non-code" — the review framing automatically grep-verifies cited rule IDs.

## Session Errors

1. **Bash CWD doesn't persist across tool calls** — `cd apps/web-platform/infra && git log ...` failed with "No such file or directory" when the prior `cd` was in a different command. **Recovery:** chain commands in a single Bash call or use worktree-absolute paths. **Prevention:** AGENTS.md already covers this implicitly; no rule needed.
2. **`hcloud` had no active context/token** — first firewall query failed with "no active context (see `hcloud context --help`)". **Recovery:** inline `HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain) hcloud ...` prefix. **Prevention:** discoverable via clear CLI error — no rule needed; runbook templates that use hcloud should pre-source the token.
3. **`prd_terraform` `CF_API_TOKEN` lacks rulesets:read scope** — Phase 5 verification returned `Authentication error` (10000); rulesets PUT works (Terraform apply succeeded), only GET rejects. **Recovery:** fell back to Phase 6 `terraform plan` regression as canonical verification (state alignment confirms both drifts in one shot). **Prevention:** when designing post-apply API verification steps, prefer `terraform plan` regression over direct CF API GET — Terraform's state-refresh path uses different scope and is the same token's primary use.
4. **`PIPESTATUS[0]` reset across statements** — `tee | tail; echo ---; echo "exit=${PIPESTATUS[0]}"` reports the echo's exit, not terraform's. **Recovery:** plan-output content was unambiguous so the wrong exit didn't change correctness. **Prevention:** capture exit immediately after the pipeline (same statement) or use `set -o pipefail` + check `$?`.
5. **`gh run view --json htmlUrl`** — field doesn't exist; correct is `url`. **Recovery:** caught immediately via `gh`'s "Available fields" error message. **Prevention:** discoverable; no rule needed.
6. **Fabricated/retired AGENTS.md rule IDs in plan** — see Problem section. **Recovery:** multi-agent review caught it; replaced inline. **Prevention:** see Prevention section above (skill-level grep verification).
7. **Post-merge AC + tasks boxes unchecked despite phases ran** — pattern-recognition-specialist and code-quality-analyst both flagged. **Recovery:** checked boxes inline + added Outcome blocks with sha256 evidence and run IDs. **Prevention:** the `work` skill's task-execution loop already says "Mark off the corresponding checkbox in the plan file" — but for runbook plans where the work IS the operator phases (not separate code-edit tasks), the checkbox-update happens implicitly. Consider adding an explicit "for runbook plans, also check off the Acceptance Criteria boxes during/after execution" reminder to the `work` skill.
8. **Freeze gate triggered on docs-only PRs** — Phase 2 freeze said "expect empty queue" but two docs PRs were queued. Operator authorized "proceed". **Prevention:** future runbook templates should narrow the freeze condition to "no PR in queue that touches `apps/*/infra/**`" rather than "no PR in queue at all" — docs PRs cannot couple drift.

## Related

- `scripts/retired-rule-ids.txt` — registry of retired AGENTS.md rule IDs
- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — same pattern catalogue, this is one more entry
- `plugins/soleur/skills/plan/SKILL.md`, `plugins/soleur/skills/deepen-plan/SKILL.md` — skills that authored the citations
- AGENTS.md `cq-rule-ids-are-immutable` — rule IDs cannot be reintroduced after retirement; lint-rule-ids.py enforces on AGENTS.md but not on cited references in `knowledge-base/`
