# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/fix-10248-boundary-wrapper-prefix/knowledge-base/project/plans/2026-10-14-fix-boundary-anchored-gates-wrapper-prefix-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Reviewed-Coverage of planning fan-out: sequential-fallback (subagent had no nested agent-spawn; plan-review + deepen research ran sequentially inline)

### Errors
- Plan-review agent panel and deepen-plan research/review fan-out could not run — no agent-spawn capability in the planning subagent; executed as sequential inline pass (Reviewed-Coverage: sequential-fallback recorded in the plan's Enhancement Summary). Mechanical gates run directly.
- `discoverability_test.command` initially prescribed a suite invocation; swapped to a Check-10-compliant `grep -m1` probe.
- Stale/wrong-path citations corrected in deepen (hook-tool-kind.sh WARN idiom; grep-rewrite.test.sh path).

### Decisions
- Fragment home: plugins/soleur/scripts/lib/wrapper-boundary.sh (reachable from both .claude/hooks and plugin-cache consumers); incidents.sh is the hook-side carrier via nested source.
- rtk atom admits only globals + exec subcommands; string-payload flags excluded so `rtk run -c 'gh pr merge'` cannot match — anchor-faithful both directions.
- Site census grep-derived: 18 production sites + 2 test-fixture restatements, count floor + justified-exemption registry.
- `_merge_args` (pre-merge-rebase) must consume the fragment in grep AND sed (`^[^g]*` strip breaks on `X=g rtk gh pr merge`).
- Deferred to decision-challenges.md as `pending - assumed` (technical, awaiting CTO consult): launcher arg-grammars (sudo -u, env -C, timeout N), string-payload unparsed-wrapper escalation, pkill PFX consolidation.

### Components Invoked
- soleur:plan (inline), soleur:deepen-plan (inline), plan-sharp-edges.md, lint-guard-contract.py, markdownlint, rtk-grammar-parity.test.sh (11/11), gh issue/pr verification
- Commits: c0614250f8, f334af1d12 — pushed; draft PR #10288

## Work Phase
- Technical rulings: all 7 `pending - assumed` rows CONFIRMED in one batched `soleur:engineering:cto` consult (per technical-ruling-gate.sh); gate green.
- Phase 1 (RED): `wrapper-boundary.sh` created (SOLEUR_ENV_ASN_RE / SOLEUR_LAUNCHER_RE / SOLEUR_RTK_RE / SOLEUR_BOUNDARY_PFX + LOADED sentinel + canonical-TSV pin); TSV gained flag-global + flag-string class rows; parity suite extended to 15 arms (green); `boundary-prefix.test.sh` created — census RED as designed, behavioral matrix green.
- Phase 2: `incidents.sh` nested-source carrier (unset-first, headless_or_stderr warn on load failure); `precommit-guard.sh` sources `$(dirname)/lib/wrapper-boundary.sh` + COMMIT_RE consumes the fragment with the pre-fix env/launcher alternation as `:-` fallback. `rtk git commit` refuses on main — verified incl. plugin-cache-shaped layout.
- Phase 3: all 20 derived sites interpolate `${SOLEUR_BOUNDARY_PFX}` (18 production + 2 test-fixture CMD_RE). `_merge_args` reworked per Design Note A (boundary+prefix strip; `^[^g]*` gone). Per-hook rtk rows: T7b/T1b/T2b/T3b clones, guardrails stash+create+conflict rows, net-issue-flow deny/allow loop rows, soak deny row, prod-write defer A1b/A2b/A3b + nomatch, parity T-M2 (rtk + rtk run intercept) + T-M3 (_merge_args unit).
- Phase 4: #10248 comments past-tense (pre-merge-rebase.sh, guardrails.sh); known-external-tools.md boundary coverage rewritten post-fix (residual classes disclosed: unknown wrappers + string payloads). Exemption registry line refs re-pointed after comment drift (230/704).
- Deviations: `rtk-foo gh issue create` negative moved off the issue-create surface — filing gate's word-boundary scan already denies it by design; negative pinned on the stash surface instead.
- Test evidence: boundary-prefix 51/51, rtk-grammar-parity 15/15, guardrails 364/364, pre-merge-rebase 215/215, parity 17/17, auto-close 49/49, follow-through 25/25, cla-signed 7/7, ship-unpushed 17/17, net-issue-flow 40, soak 26, operator-step 26/26, runbook 26/26, prod-write-defer 222/222, guard-vacuity-floor 23/23. Fixture baselines regenerated (no residue change).
- Parent PR #10227 MERGED (d3714354a0) mid-work — rebase --onto origin/main now unblocked.
