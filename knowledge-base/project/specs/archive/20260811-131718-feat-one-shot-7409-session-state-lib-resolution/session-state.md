# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-10-fix-session-state-lib-plugin-resolution-plan.md`
- Status: complete

### Errors

None blocking. Six defects were found **in the plan itself** during review/deepen and fixed
before handoff — each would have caused rework or a false-green at `/work` or `/ship` time:

1. **AC1 would have failed a correct implementation** — `git grep -c 'session-state' -- .claude/hooks/lib/`
   still returns matches post-fix (repointed `source` lines contain the filename). Rewritten to `test ! -e`.
2. **AC3 was vacuous** — `expected_duration_min=240` is the default at *both* `worktree-manager.sh:1354`
   and `session-state.sh:194`, so asserting it proves nothing whether or not the env var is read. Changed
   to `137`; the same latent defect exists in the **existing** suite at `lease-protects-active.test.sh:253`.
3. **The plan would have hard-FAILED `/soleur:preflight` Check 6 at ship time** — Step 6.5 requires a
   *bullet-form* `- **Brand-survival threshold:**` line; the draft's non-bulleted form yields an empty
   match. Fixed and re-verified against the gate's own regex.
4. **AC6 would have gone red** on `lease-protects-active.test.sh:128`, a line inside the AC's own grep
   scope that the plan never listed — found by *running* the AC against the tree.
5. **Two rationale grounds were factually wrong** — `plugins/soleur/AGENTS.md:182` is skill-scoped (not
   about top-level `scripts/`), and `plugins/soleur/lib/` was dated a month off. Both were load-bearing
   for the destination choice.
6. **`acquire_lease` was misclassified** as advisory alongside `release_lease`; degrading it open silently
   manufactures the exposure this plan removes.

### Decisions

- **MOVE, not duplicate** — `.claude/hooks/lib/session-state.sh` → `plugins/soleur/scripts/lib/session-state.sh`.
  Destination resolved a three-way disagreement (CTO: `hooks/lib/`; advisor: `scripts/`) by synthesis:
  `scripts/lib/` keeps the ADR-156 A1 carve-out matching with zero edit *and* answers the cohesion objection.
- **P1 resolves with no environment variable** — `$SCRIPT_DIR/../../../scripts/lib/…` is layout-invariant
  across repo and cache install. This is what makes the primary fix deterministic; it deliberately does not
  depend on `CLAUDE_PLUGIN_ROOT`, which was measured **unset** on the CLI path (a measurement itself flagged
  as confounded and demoted out of the critical path).
- **Disposition follows the destructiveness gradient** — the reap path stays fail-closed; advisory
  `with_lock` / `release_lease` sites degrade open loudly. Hard-failing there would convert exit 127 into a
  prettier exit 127 for exactly the users #7409 is about.
- **ADR-178 recorded** (the provisional ADR-175 collided at ship time — a sibling landed `ADR-175-preflight-probe-execution-boundary` mid-pipeline and main reached ADR-176, so this renumbered to 177; the sibling's two `model.c4` ADR-175 citations were deliberately left untouched), with C4 edits to **two**
  falsified descriptions plus `model.likec4.json` regeneration — omitting that is a guaranteed CI red via
  the byte-diff freshness gate.
- **Scope corrected upward from the issue**: seven invocation sites, not six (the issue omitted `one-shot`).
  Separately discovered that the lease library's own 34 KB test suite **has never gated CI** —
  `test-all.sh` globs `.claude/hooks/*.test.sh` flat, so `lib/*.test.sh` is an orphan. The move de-orphans it.
- **This PR arms the reaper.** Pre-fix, marketplace users could never reap anything; post-fix an
  unrecoverable operation goes live for them for the first time. A dedicated cache-layout refusal test with
  a mutation arm was added — nothing previously covered that direction.

Three taste/user-challenge dissents (two-PR split; ADR-093 amendment vs standalone ADR; the `AP-023`
register row) are recorded in `decision-challenges.md` for `/ship` to surface as an `action-required`
issue rather than being silently applied.

### Components Invoked

- `Skill: soleur:plan`
- `Skill: soleur:deepen-plan`
- `Agent: soleur:engineering:research:repo-research-analyst`
- `Agent: soleur:engineering:research:learnings-researcher`
- `Agent: soleur:engineering:cto` (Phase 2.5 domain review)
- `Agent: fable` (Step 4.5 scoped strong-model advisor consult)
- `Agent: soleur:engineering:review:architecture-strategist` (plan-review panel)
- `Agent: soleur:product:spec-flow-analyzer` (plan-review panel)
- `Agent: soleur:engineering:review:code-simplicity-reviewer` (plan-review panel)
