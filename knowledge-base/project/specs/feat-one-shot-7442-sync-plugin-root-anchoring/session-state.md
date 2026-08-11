# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-11-fix-sync-plugin-root-anchoring-plan.md`
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope check: PASS — `git diff origin/main...HEAD --name-only` listed only `plans/` + `specs/` paths.

### Errors
None blocking. Two subagent claims were falsified by direct read during planning and are recorded in the plan's Research Reconciliation rather than propagated:
1. A research agent asserted relocating `rule-prune.sh` was "safe — critically portable". False: `rule-prune.sh:52` derives its data root from its own location, so a move breaks it everywhere.
2. The same agent cited a `scheduled-rule-prune.yml` workflow that does not exist.

A live citation check also corrected the plan's own recurrence chain — #4826 is "nav-rail position resume", the class's victim, not a member.

### Decisions
- **The remedy #7442 proposes is a measured no-op on its target surface.** `CLAUDE_PLUGIN_ROOT` is unset in a plain CLI bash session, so `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` expands to the bug itself, and no `:-` fallback can reach a marketplace install. Root resolution is therefore a blocking Phase 0 with a bound decision tree, not an assumption.
- **Scope is the shape, not the reporter: 29 anchorable sites, not the 4 the issue named.** The other 21 are un-anchorable repo-root `scripts/` sites already owned by open issue #6222 (`Ref`, never `Closes`).
- **Do not relocate `rule-prune.sh`** — its data root is `$SCRIPT_DIR/..` and its telemetry producer `emit_incident()` is not in the payload; a move breaks four sites in a production Inngest cron.
- **A more severe issue than #7442 was split out and filed as #7450** (P0, `type/security`): `gh pr checkout` makes `$(git rev-parse --show-toplevel)` the contributor's tree, putting untrusted code behind 5 redaction gates. Fix before, not with, this plan.
- **The guard as originally specified cannot go green** (BF-2) — two committed artifacts require the `:-` form. Phase 0 must fix the predicate's verb/target set.

### Verification performed by the parent before accepting the plan
| Claim | Method | Result |
| --- | --- | --- |
| `CLAUDE_PLUGIN_ROOT` unset on CLI | direct `echo` probe in this session | **Confirmed** — expands to `./plugins/soleur` |
| `gh pr checkout` at `review/SKILL.md:63` | `grep -n` | Confirmed |
| bare `bash scripts/domain-model-drift.sh` in `review/SKILL.md` | line-start grep MISSED it; full-line read found it at :276 as an **inline span** | Confirmed; citation accurate |
| 5 redaction-gate git-root sites | `grep -rn` for the literal | Confirmed, all 5 |
| `worktree-manager.sh:48` `source` five levels up | `sed -n '44,52p'` | Confirmed |
| #6222 state + scope overlap | `gh issue view` | OPEN; owns the repo-root class, but **proposes the git-root anchor as its remedy** — falsified by #7450, so #6222 is blocked on it |

### Collision re-probe (post-planning)
Plan frontmatter `closes: 7442` — already cleared at Step 0a.5. The only ref planning newly introduced is **#6222**, which is `Ref`-only and OPEN; no merged PR claims it. No new abort condition.

### Components Invoked
- `soleur:plan` → `soleur:deepen-plan` (isolated Task subagent)
- Research: `repo-research-analyst`, `learnings-researcher`
- Plan review: `architecture-strategist`, `spec-flow-analyzer`, `code-simplicity-reviewer`, scoped strong-model advisor
- Deepen review: `security-sentinel`, `test-design-reviewer`
- Deepen gates: 4.5 (fired, disposition + telemetry recorded), 4.6/4.7/4.8 PASS, 4.9/4.10/4.55 skipped (no trigger)

## Work Phase

- Status: implementation complete; full-suite exit gate deferred to post-review (see below).
- Commits: `a16af4bce` relocation · `632f09d92` rule-prune gate · `9484afac7` anchoring + T0 · `09a7460fa` guard · ADR-177 · `783ff94c2` orphan tombstone.

### Phase 0 outcome — a fourth branch the plan's decision tree did not enumerate

`CLAUDE_PLUGIN_ROOT` is UNSET in the bash tool environment (three ways: `${VAR+SET}` empty,
`env | grep -c` = 0, fallback expanding). Measured from inside a plugin-provided **skill**
execution context, not merely a plain session. So the issue's proposed
`${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` expands to the defect it was meant to fix.

Remedy bound to the **bare** token, which is fail-closed under either substitution
hypothesis. Full reasoning + rejected alternatives: ADR-177.

### Task-list reconciliation — why the plan's boxes are NOT ticked

The CTO ruling reshaped scope after `tasks.md` was written, so ticking its 53 boxes would
assert work that was superseded rather than done. What actually changed:

| Plan said | Shipped | Why |
| --- | --- | --- |
| Anchor 29 sites across 19 files | Anchored the **command surface** only (`sync.md` 6 + `go.md` 2) | The 100-site skills migration needs a `server/safe-bash.ts` change; bundling an allowlist edit behind a P1 bug fix is how allowlist regressions ship. Deferred to #7453. |
| `${CLAUDE_PLUGIN_ROOT:-…}` prefix | **Bare** `${CLAUDE_PLUGIN_ROOT}`, payload-relative | The `:-` form is the vector, measured. |
| Relocate `domain-model-drift.sh` **and** `rule-prune.sh` | Relocated the first only | Both `rule-prune.sh:52` and `rule-metrics-aggregate.sh:34` derive their data root from `$SCRIPT_DIR/..`; a move silently repoints them. |
| Phase 6 C4 modelling | Deferred to #7452 | Outside the CTO's stated scope boundary; a modelling addition, not a fix for #7442. |
| Guard over `plugins/soleur/**/*.md` | Scoped to `commands/**/*.md` | Residency (P2) would red unpredictably against the unaudited skills corpus. Exclusion stated in the guard's docstring, not implied. |
| AC8: halt literal count = 1 | 2 | Both call sites are gated, not just the pruner. |
| Deferral 4 (make rule-prune customer-capable) | **Closed, not deferred** | ADR-177: the area is monorepo-only by construction. |

### Defects found in my own work by my own tests

1. **The Phase 5 sentinel was line-separable.** T0 extracted the invocation line-wise and the
   decoys executed. Fixed by variable-anchoring the operand so the line is fail-closed in
   isolation; `|| true` on the assignment so `set -e` cannot abort before the message prints.
2. **`scripts/domain-model-drift.test.sh` resolved its SUT as a sibling**, so the relocation
   broke it in a way no path-literal grep could see. Repointed with a fail-loud guard.
3. **`ADR-174` cited in the preflight message** before the ordinal was checked; corrected to
   `ADR-177`.

### Exit-gate note (honest)

`test-all.sh` was launched detached and **queued on the advisory lock** behind three sibling
worktree runs (~58 min each); `/tmp` was at 83%, firing both `LOW_TMP_HEADROOM` and
`SIBLING_RUN_DETECTED`. I killed my queued run by PID (ancestry excluded; siblings verified
untouched) rather than hold it against a tree review may still change. The gate runs once
against the final tree. `tsc --noEmit` completed independently: **rc=0, zero errors**.
