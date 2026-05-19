---
name: brainstorm-verify-issue-body-enumerations-against-live-state
description: Issue body enumerations (counts, candidate lists, "Group N has ~X items") drift between issue creation and brainstorm. Run a `gh run list` / `gh issue view` / direct `ls` sanity-check against live state BEFORE letting the enumeration shape brainstorm scope. Pairs with two adjacent verification patterns documented inline.
metadata:
  type: best-practice
  category: brainstorm-flow
  module: brainstorm
date: 2026-05-18
related_issues: [3948, 3244, 3940, 3990]
related_brainstorm: knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md
---

# Learning: brainstorm verify issue-body enumerations against live state

## Problem

#3948's body listed ~14 group-(c) "agent-loop" cron workflows to migrate to Inngest scheduler (deferred from PR-F #3940, parent #3244). The enumeration was written 2026-05-17 when PR-F brainstorm classified 38 total scheduled workflows. By the time brainstorm started one day later (2026-05-18), three of the listed candidates were no longer recurring crons in any meaningful sense:

- `scheduled-dogfood-once-3049.yml` — fired 2026-05-04, failed once, parent issue #3049 closed
- `scheduled-dogfood-once-3049-v2.yml` — fired 2026-05-04, succeeded post-fix, parent issue closed
- `scheduled-gdpr-gate-preflight-eval-50d.yml` — never fired, cron `0 9 29 6 *` (June 29), self-neutralizes via YAML self-edit at run

All three are self-disabling one-shots from the `/soleur:schedule --once` skill, not recurring agent loops. If the brainstorm had accepted the issue-body enumeration uncritically, the scope would have been ~14 migrations; the live-state-verified scope is 11 (PR-1 + 10 umbrella children + 1 one-shot conversion) plus 2 outright deletions. That's a ~20% scope error sitting in the issue body.

The drift had three concurrent sources:

1. **Time delta** — between issue creation and brainstorm, workflow runs fire and parent issues close.
2. **Author lens** — the issue author classified workflows by file-prefix (`scheduled-*`), not by lifecycle (`recurring vs one-shot`). The `-once-*` naming hint was visible but not load-bearing in the enumeration.
3. **Reference staleness** — the count came from PR-F's brainstorm Phase 1.0 classification, which categorized by intent ("group-(c) agent loops") rather than by current-state ("still firing on cron schedule").

## Solution

Before letting an issue-body enumeration shape brainstorm scope, run a 30-second sanity-check pass against live state. For workflow / cron enumerations specifically:

```bash
# For each named file in the enumeration:
for w in <names>; do
  if [[ -f ".github/workflows/${w}.yml" ]]; then
    echo "EXISTS  ${w}"
  else
    echo "MISSING ${w}"
  fi
done

# For each one-shot-suspect candidate (name contains "once", "v2", "-eval-",
# or any date-bounded substring):
gh run list --workflow "<name>.yml" --limit 3 --json status,conclusion,startedAt
# If runs exist with conclusion=success, the one-shot already fired.

# For named referenced issues in the enumeration:
gh issue view <N> --json state,title
```

For non-workflow enumerations (lists of files, components, services), the analog is `ls`/`find` directly. When the enumeration cites a count ("~14 workflows", "12 services"), state the actual current count explicitly in the brainstorm so the carve-out arithmetic is auditable: `15 candidates − 1 PR-1 − 3 one-shots = 11 umbrella children`. The drift between 14 (cited) and 15 (actual) is itself a signal worth surfacing.

## Key Insight

**Issue bodies are point-in-time snapshots. The longer the issue is open, the more its enumerations drift. The cost of a 30-second `gh run list` / `ls` / `gh issue view` pass is strictly lower than the cost of a brainstorm that bakes a stale scope into a downstream spec.** This is the brainstorm-time analog of the existing premise-validation pattern at Phase 1.0.5 in `plugins/soleur/skills/brainstorm/SKILL.md` — but specifically targeting the *enumeration count and member list* rather than just architectural claims.

The signal is sharpest when the enumeration cites named candidates whose names hint at lifecycle ("once", "v1/v2", date suffixes, "-eval-", "-temp-"). Those names ARE the staleness canaries.

## Two adjacent verification patterns surfaced in the same session

**Pattern (a) — operator override on triad's "simplest-first" PR-1 recommendation is a load-bearing signal.** When CPO + repo-research converged on `scheduled-strategy-review` as PR-1 (weekly shell-only — sidesteps the `claude-code` spawn substrate gap entirely), the operator overrode to pick `scheduled-daily-triage` (daily 4am, label-mutator + comment-writer, claude-code-action). The override is NOT bikeshedding — it's a deliberate choice for a more decisive proof, landing the full primitive stack in one review so subsequent migrations are mechanical reuse instead of re-litigating architecture per-PR. **Brainstorm-flow implication:** when triad converges on simplest-first and operator picks harder, treat the harder target's blast radius as the proof-of-pattern's *acceptance criteria density*, not as a risk to argue against. Re-frame the spec around "lands full stack in one review" rather than "lowest blast radius."

**Pattern (b) — research-agent file-existence claims that contradict orchestrator `ls` are agent CWD/path-resolution false negatives.** The repo-research-analyst returned: *"the requested workflows are sourced from the `apply-pr-3974-recovery` worktree because they were rolled back from main; main only contains 18 scheduled-*.yml files, none of the agent-loop set."* My own `ls .github/workflows/scheduled-*.yml` from the worktree (HEAD `e7ad93e3`, based on `origin/main`) showed 37 files including all 15 candidates. The agent's CWD or branch read was confused; the agent's substance (workflow inventory rows, side-effect classifications, Sentry shape per workflow) was still useful because it grep'd file contents. **Brainstorm-flow implication:** when an agent's existence claim contradicts a direct orchestrator `ls`, the orchestrator's filesystem read wins. Trust the agent's content-of-file claims; downweight its claims about file-presence and branch-state. This pattern is already documented in the brainstorm SKILL.md's "Verifying 'is X mounted/wired/enabled?' claims" section — this session is a new occurrence and confirms the pattern generalizes from `mounted` to `present-on-this-branch`.

## Session Errors

1. **Off-by-one umbrella-children count (recovered inline).** In the brainstorm doc, the migration-set arithmetic was first stated as "10 umbrella children" then corrected to 11 inline within the same section. — Recovery: caught at write time and surfaced as a parenthetical "Wait — that's 11 children, not 10. Re-counting: 15 − 1 − 3 = 11." — **Prevention:** when carving a set via subtract operations, state the arithmetic explicitly *first* (`15 - 1 - 3 = 11`), then enumerate the result. Order matters: arithmetic-then-list catches the off-by-one at compose time; list-then-count discovers it at proofread time.

2. **Repo-research agent stale-branch claim mis-framed inventory provenance.** The agent reported workflows lived on a recovery branch and `main` had only 18 — directly contradicting my own `ls` showing 37. — Recovery: trusted orchestrator's `ls`, treated agent's framing as informational only; used the agent's per-workflow content classifications which were accurate. — **Prevention:** documented as sister Pattern (b) above. Already covered by the brainstorm skill's existing "Verifying 'is X mounted/wired/enabled?' claims" guidance — this occurrence reinforces the pattern rather than requiring a new rule.

## Sister learnings

- `2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md` — the closest sibling, but its focus is *option enumerations* and *library API surface drift*. This learning targets *workflow / cron / one-shot-lifecycle enumerations specifically*. They generalize together into a brainstorm Phase 1.1 maxim: **any enumeration in the issue body that names files, runs, or candidates needs a `gh run list` / `ls` / `gh issue view` sanity-pass before scope-shaping.**
- `2026-05-15-brainstorm-enumerate-umbrella-child-prs-before-leader-spawn.md` — about umbrella PR enumerations being stale relative to merged work; this learning is the sibling-shape for cron workflow enumerations being stale relative to firing history.
- `2026-05-11-brainstorm-parallel-domain-and-research-fan-out-and-duplicate-issue-discovery.md` — `gh issue list --state all --search` as the duplicate-framing canary; here, `gh issue view <N> --json state` is the closure canary.

## Related

- Issue: #3948 (TR9 cron migration); productize follow-up #3990; parent epic #3244; predecessor PR-F #3940
- Brainstorm output: `knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md`
- Spec output: `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md`
- AGENTS.md rules touched: `pdr-when-a-user-message-contains-a-clear` (lane=cross-domain inferred from user-brand-critical override; routes to triad), `hr-weigh-every-decision-against-target-user-impact` (USER_BRAND_CRITICAL gate fired and emitted telemetry)
