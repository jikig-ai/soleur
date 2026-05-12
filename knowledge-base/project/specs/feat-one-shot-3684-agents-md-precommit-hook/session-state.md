# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-12-chore-agents-md-precommit-hook-rule-budget-anchor-parity-plan.md
- Status: complete

### Errors
None

### Decisions
- Anchor-parity check shifted from naive `grep -F` to a literal-substring contract. Live deepen-pass scan found 10 of 21 existing `[skill-enforced:]` segments dangle under the issue body's proposed semantics. Plan ships an opt-in `--check-anchors` flag plus AC15 migration table to make the live state pass — without this, the check would be unsatisfiable on day one.
- Shared `scripts/lib/agents-payload-bytes.sh` library consolidates the `B_ALWAYS = wc -c AGENTS.md + wc -c AGENTS.core.md` formula across the 3 callers (compound advisory, cron post-apply revert, new pre-commit hook) — single source of truth for the formula. Thresholds remain owned per-caller.
- Warn threshold raised 18 k → 20 k across all four surfaces (compound `SKILL.md:220`/`:226`, AGENTS.docs.md:6 rule body, new lint script default). Today's payload at 21,985 B already exceeds 18 k, making the old warn fire on every commit.
- Lefthook is the right hook framework (no new framework). 2 new commands (`agents-rule-budget`, `agents-skill-enforced-anchor`) wired alongside the existing 3 AGENTS lints at priority 5; path-array glob form per the documented `2026-03-21-lefthook-gobwas-glob-double-star.md` learning.
- `--no-verify` bypass intentionally permitted (mirrors the precedent set by `gitleaks-staged` in the same `lefthook.yml` block). The hook is fast-feedback; the load-bearing CI floor remains the cron post-apply revert in `scheduled-compound-promote.yml`.

### Components Invoked
- soleur:plan (skill)
- soleur:deepen-plan (skill)
- gh CLI, Bash, Read, Write
