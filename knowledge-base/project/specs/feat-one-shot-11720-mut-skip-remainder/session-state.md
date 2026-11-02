# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-02-chore-mut-skip-guard-remainder-plan.md
- Status: complete (3 review rounds applied: advisor floor-constructibility + spec-flow 23 findings + Kieran P0 floor-shape fix; DHH + simplicity seats pending at write time)
- Scope: batch-2 = 4 files (registry-store-not-luks, registry-zot-credential-shape, workspaces-luks-deadman-fired, egress-gw + PROMOTED_FILES promotion); registry-clientip descoped (gen-3); 6 files remain in #11720 for later batches

### Errors
None — planning ran inline (Devin depth-1: child skills' fan-outs originate at orchestrator)

### Decisions
- Shipped convention is seam-check, NOT env -u (issue wording stale; env -u self-reds sibling pins)
- Constructible floor: pure-assignment window, _eff=${MUT_SKIP:+0}/_eff=${_eff:-$MUT_ROWS} (Kieran-verified)
- Floor trips exit 1 (verdict-class), instrument failures exit 2 — deadman converted
- Per-file IV axes added so seam checks are mutation-pinnable; excluded literal set = each suite's axis names (REGSTORE_/REGCREDSHAPE_ lack _GUARD_)
- deadman conjunct-set canon preserves order-insensitivity; QP/CK exact pins
- egress-gw already floor-bearing (pass -lt 30) → promotion moves deferred→covered; meta-guard edit at :1089 live PROMOTED_FILES site only + grounds comments + MIN_FIRING_SUITES 61→65 (ALL FOUR promoted per CTO ruling A); counters diff: deferred 47→43, def_fires 31→30, def_construct 16→13, covered 383→387, fires 366→370
- Epic #10390: delegation valid to 2026-11-20, no delegated acts due (CTO Own-the-epic run); holds in plan ## Operator Holds + decision-challenges.md; cto_spawns=1

### Components Invoked
run_subagent: repo-research-analyst, learnings-researcher, functional-discovery, CTO (Own the epic + domain sweep), COO, spec-flow-analyzer, advisor-consult, Kieran/DHH/simplicity plan-review seats

## Next
deepen-plan → technical-ruling gate → soleur:work → review → fix-round → qa → compound → ship (PR #11849) → postmerge → DONE

## Implementation log (2026-11-02, work phase)

- All four ports landed and are green: registry-store 55/55, registry-zot 52/52,
  deadman 58/58, egress-gw 77/77. Commits: 09eb4b6a6d, 0adf2c1562+5d4b2f653e,
  91aabdb5ca, 55da4cdcc3, 6182204715.
- Floor discovery during implementation: a literal `<<-SQL` inside extractor/mutation
  text opens a PHANTOM heredoc span in the meta-guard's heredoc_lines_of — every later
  line (including the floor) counts as heredoc body and is invisible. The four files
  were NEVER floor-bearing before; this is why covered-fires moved 366->370 with the
  deferred ledger untouched at 47 (not 43). Evasion: `<<[-]SQL` in awk/grep/comments,
  `<<\x2dSQL` inside python strings.
- Second floor-discovery: build_mutant needs a standalone column-0 `fi` — one-line
  `if ... fi` floor/ledger blocks were rewritten multi-line.
- Floor shape uses the constructible `_eff=${MUT_SKIP:+0}` window (not the donor's
  `[ -n ] &&` rebind); deadman floor exit normalized 2 -> 1.
- Meta-guard: all four added to the LIVE PROMOTED_FILES regex (line ~1089) + grounds
  paragraph; MIN_FIRING_SUITES 61 -> 65. Full run: 25/25 green, covered 387,
  fires 370, deferred 47/31/16, all four PROMOTED entries score FIRES.
- Runtime: four suites measure ~4-9s each (~24s added to the serial leg); the
  15-minute deploy-script-tests-fixed ceiling is not approached — no timeout bump.
- Acceptance: no env -u in infra-validation.yml; run lines plain `run: bash`;
  registry-clientip byte-identical; fixture parity suite 71/71 green.
