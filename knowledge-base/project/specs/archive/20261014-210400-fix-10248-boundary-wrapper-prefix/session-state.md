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

## Review Phase (design-validity pass)
- Seats: code-simplicity-reviewer + architecture-strategist — both SIGN-OFF-WITH-FINDINGS ("simplest correct shape"; no simpler mechanism exists).
- Landed in-PR:
  - P2 (both seats): provision arm — consuming file must source incidents.sh/wrapper-boundary.sh, not just interpolate.
  - P2 (simplicity): comment-strip asymmetry — consumption check now strips trailing comments identically to candidacy.
  - P2 (arch): census widened to .claude/hooks/lib/ + scripts/lib/ — incidents.sh detect_bypass (:302-318) entered as justified exemptions (space-boundary class, rtk already caught).
  - P3: exemption comment refs re-pointed; command-vocab extension note added.
- Deferred: boundary-alternation canonicalization → filed #10315 (milestone Post-MVP/Later, meta/machinery); `:-` alternation drift = documented debt (benign, fires only when lib absent); doppler fallback verified verbatim pre-PR form.
- Suite post-fix: boundary-prefix.test.sh 52/52 (census 32 candidates, 20 consuming, 12 exempt).

## Review Phase (full panel)
- Panel: 9 seats — design pass 2 + class panel 7 (architecture dedup'd via design pass).
- Verdicts so far: 5× SIGN-OFF-WITH-FINDINGS, 1× SIGN-OFF (performance), 1× BLOCK (git-history) → resolved in-PR.
- BLOCK finding (git-history P1, code-quality F1 convergent): `ship-kb-archive-gate.sh` — a 21st site landed on main after the pre-rebase enumeration; variable-composed boundary (`_MERGE_BOUNDARY`/`_MERGE_PREFIX`) is census-invisible AND has no rtk atom → `rtk gh pr merge` skipped the wg-kb-artifacts-archived-in-pr gate. Fixed: `${SOLEUR_RTK_RE:-RTK_UNPROVISIONED_10248}` joins `_MERGE_PREFIX`'s first group (preserves the file's richer env-asn/keyword/arg-launcher grammar); census gained a composed-variable second pass (36 candidates: 24 consuming + 12 exempt); T06b pins rtk/rtk-run deny + rtk-foo pass.
- Landed fixes from all seats: `--` end-of-options member (rtk F4 — clap inert anywhere in the wrapper span, TSV flag-global row added); fail-soft rows unescaped (real unset-var expansion now exercised); comment-strip symmetry in consumption AND provision AND composed checks; awk one-pass replacing `grep -v | grep -q` (pipefail SIGPIPE trap); provision arm file-level check; partition-completeness arm in parity (16/16); unset-first in 3 direct-lib test fixtures; doc third-residual disclosure (launcher arg-grammars + boundary-shape #10315).
- Deferred/lows accepted: `:-` fallback drift (documented debt, degraded-path only); doppler fallback = verbatim pre-PR form; doc flag-row extraction pin (F5 low); `^`-shape candidacy assumption now commented.
- Suite state: boundary-prefix 54/54 (census 36/24/12), parity 16/16, kb-archive 97/97.

## Review Phase (panel residual batch)
- Second batch landed after seats 5-9 reported:
  - security-sentinel: comment-strip provision grep (shared LOW with pattern+integrity seats — landed); inherited-env on carrier-missing path accepted as documented debt (requires env control; the :` fallback keeps the degraded path fail-soft not silent).
  - pattern-recognition: composed-site blind spot closed by the composed-pass (landed); "exactly the old matching" comment overclaims reworded to superset wording at guardrails.sh:137-141 + precommit-guard.sh:66-68; lib header "~18 per-site lists" corrected (~4 had lists, ~15 had none); line-pin citations repointed to content anchors (hook-input-contract.test.sh:845, hooks/README.md:415); doppler :- fallback marked verbatim pre-fix literal.
  - agent-native: partial-source warn now unsets fragment vars so state and message agree (incidents.sh:40-42, precommit-guard.sh:62); doc globals line gains `--`; doc residual classes now three (launcher arg-grammars disclosed + boundary-shape #10315).
  - integrity: partition-completeness arm (parity 18/18); `(^|`-shape candidacy assumption commented; doc flag-row extraction pins added (globals + string-payloads arms).
  - performance: SIGN-OFF clean — lazy-DFA consumption everywhere, no =~ interpolation, deterministic grammar.
- Census hygiene: line-shifted exemptions re-pinned (incidents.sh:305-321, guardrails.sh:231/705).
- Suite state: boundary-prefix 54/54 (36/24/12), parity 18/18, kb-archive 97/97, guardrails 364/364, incidents helper 9/9, operator-step 26/26, runbook 26/26, pmr-parity 17/17.
- Open: full test-all scripts battery still queued behind sibling worktrees; tasks 4.1 pending its result.

## Battery + Ship Phase
- test-all.sh scripts battery finished: 601/614. All 8 fails triaged; 4 real (all fixed): capture-exit-live S1 on parity member-split greps, tempfile-ownership rule(c) mktemp, env-adoption ceiling (git_fixture_env added), kb-consumers baseline (3 one-hop argv-code rows). 4 contention (green isolated): weight-drift, orphan-reaper x2 — the 8th was a self-test EXPECTED row.
- Advisory lint-bot-statuses CI fail was the tempfile rule(c) — fixed before it even landed.
- tasks.md 4.1 ticked. KB artifacts archived in-PR per wg-kb-artifacts-archived-in-pr.
- Merge remains operator-owned: PR marked ready pending CPO/operator call; no auto-merge armed.
