# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-02-chore-mut-skip-guard-batch3-plan.md
- Status: complete (plan + deepen-plan gates all run; sequential-fallback disclosed — Devin depth-1, no subagent spawns)
- Scope: batch-3 = final 6 files of #11720 (bwrap-probe-rollback, faithful-canary-sandbox, ghcr-blocked, inngest-step-524, sandbox-alerts, web-nic-guard-unpinned-url) + 6 PROMOTED_FILES promotions + MIN_FIRING_SUITES 65→71; registry-clientip descoped (gen-3), inngest-cutover-flip-silent out of scope (new file)

### Errors
None — planning ran inline (Devin depth-1: child skills' fan-outs originate at orchestrator)

### Decisions
- Shipped convention is seam-check, NOT env -u (issue item-3 wording stale; batch-2 CTO ruling carried forward)
- All six floors are phantom-heredoc-hidden today (no bare `SQL` terminator anywhere) → `<<-` evasion sweep is load-bearing; promoted to Solution step 1 + AC10 + Guard-3 row 2
- Uniform promotion of all six (batch-2 ruling A extended): PROMOTED_FILES at live :1096 site + MIN_FIRING_SUITES 65→71; predicted counter diff vs measured baseline: covered 387→393, fires 370→376, deferred 47→47
- inngest-524 is middle-generation (mutate_red sans fragments, S1/C1 controls, magic `_floor=74/50`) — deepest port; ghcr/web-nic already have IV axes (need only literal-absence seam + IV rows)
- decision-challenges.md: 2 technical rows carry `Ruled by CTO agent, 2026-11-02:` (batch-2 carry-forwards); 3 taste rows; 1 operator-scope row (Ref #11720 default at ship)

### Components Invoked
plan skill (SKILL.md executed inline), deepen-plan skill (halt gates run inline), sharp-edges catalogue pass, lint-guard-contract.py, technical-ruling-gate.sh --branch, markdownlint, gh CLI (issue/PR/issue-list), meta-guard baseline run (25/25 green)

## Next
soleur:work → review → fix-round → qa → compound → ship (PR #11885 placeholder on this branch; merge queue needs `test` check-run on head → GraphQL enqueuePullRequest; archive-kb.sh inside PR before merge)

## Measured facts (2026-11-02, this branch)
- Meta-guard baseline: floor-bearing 434, covered 387, deferred 47 (31 fires/16 construct), fires 370, construct 17, MIN_FIRING_SUITES=65, 25/25 green
- Suite runtimes: bwrap 4.5s, fcsb 7.1s, ghcr 15.9s, inngest-524 3.3s, sandbox 30.0s, web-nic 2.8s (~64s total)
- Phantom `<<-` sites per file: bwrap 5 (:74/:279/:360/:362/:424), fcsb 2 (:75/:372), ghcr 7 (:90/:420/:501/:503/:549/:557/:564), inngest-524 3+ (:126/:337/:398 — 4 literal instances), sandbox 5 (:77/:364/:480/:482/:486), web-nic 3 (:84/:296/:362)
- Missing IV axes: BWRAP_/FCSB_/SPEND_/SANDBOX_ALERTS_ need `*_GUARD_IV` added; GHCR_/UNPINNED_ have IV
- assert_fixture_dir md5-identical across all 7 files (parity pinned)
- doppler-config-inventory.txt fresh (stamped 2026-11-02) — P16 not an issue this branch

## Work Phase (2026-11-02)

- Six suites ported by four parallel fan-out agents (orchestrator-verified):
  bwrap 66/66 P32 M34; fcsb 71/71 P44 M27; ghcr 95/95 P44 M51; inngest-524 100/100 P62 M38;
  sandbox 76/76 P41 M35; web-nic 54/54 P35 M19. All `MUT_SKIP=1` inner runs green.
- Floor-RED proof per file: +1 PRESENCE_ROWS bump → exit 1 `[FATAL] assertion floor` → reverted.
- Phantom-span sweep: zero `<<-` opener-regex hits outside real `<<PY`/`<<'ROWS'` heredocs.
- Meta-guard promotion landed: covered 387→393, fires 370→376, deferred 47→47, unclassified 0,
  25/25 green; MIN_FIRING_SUITES 65→71; six PROMOTED_FILES entries at live :1096 site + grounds comment.
- AC6: six suites measured ~142s total (baseline ~64s); serial leg worst ~6.7min + delta → no
  timeout-minutes bump needed.
- lint-shell-capture-exit: 0 new findings. GDPR gate: not triggered (no canonical-regex path in diff).
- Affected-test exit gate queued behind sibling run (feat-prod-readiness-gap-analysis lock).
- Commits: 6 per-file ports + 1 meta-guard promotion.

## Review Phase (2026-11-02) — dedup ledger

| raw finding | canonical defect key | reporting seat(s) | disposition |
|---|---|---|---|
| web-nic EM needle satisfiable by #-commented decoy | dead-text emitter needle | security-sentinel | FIXED (comment-filter selector + EM mutate_red row; MUT_ROWS 20) |
| inngest-524 -target= scans whole workflow not MAIN_PLAN | allowlist scope too wide | security-sentinel | FIXED (main_plan slice, sibling-parity) |
| AC6 timeout evidence cites matrix job not fixed leg | evidence mis-attribution | performance-oracle | FIXED (session-state + ship checks PR's own leg timing) |
| $$escaped expands to PID in 5 files | planted-text mismatch | pattern-recognition | FIXED (\\x24\\x24escaped) |
| command -v python3 missing ghcr/web-nic | missing FATAL parity | pattern/code-quality | FIXED |
| dead EXPL_QRY/EXPL_VAR + printf arg | dead code/format defect | shellcheck lint | FIXED |
| inngest EMIT_PROBE/probe_ts dead read; thin attr pins; stale "TWO units"/fixture-count comments | pre-existing inngest-524 defects | code-quality/test-design | DEFERRED → family cleanup issue (pre-existing on main) |
| pre-battery fail>0 gate absent in 5/6; MUT_ROWS_RUN asymmetry; SELF relative form in 2 | convention-internal asymmetries (also in merged batch-2) | code-quality/pattern | DEFERRED → family cleanup issue |
| seam greps cover literal text only (constructed env names evade) | seam coverage limit — affects ALL convention suites incl. merged donors | security/architecture | DEFERRED → family cleanup issue |
| if:/continue-on-error: pins only ghcr/web-nic | family parity gap | security | DEFERRED → family cleanup issue |
| floor self-reference (-1 alongside deletion) | documented accepted anchor gap | security | DOCUMENTED in plan Anchor (accepted) |
| JQ_DIR trap; EXPECT_1 vestigial; sandbox >=1 anchor; census vocab drift | cosmetic/pre-existing | code-quality/pattern | DEFERRED → family cleanup issue |
| PROMOTED_FILES 4-site staleness | meta-guard design | architecture | DEFERRED → separate concern (pre-existing) |

Panel: 8 seats (class=code, tier=none, design-risk unset) — git-history, pattern, architecture,
security, code-quality, performance, test-design, shellcheck-lint. All SHIP, 0 P1.
