# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9813-extension-aware-edges/knowledge-base/project/plans/2026-10-10-chore-extension-aware-affected-edges-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- Initial `gh issue view` JSON pipe failed (no stdin JSON); fixed with `--json` fields directly.
- Presumed script `scripts/test-affected-kb-consumers` does not exist — it is a suite label; implementation is `scripts/test-affected-kb-consumers.test.sh` + `.baseline.txt`.
- Background measurement `3192e0` superseded by re-running probes directly (`--paths` kb-md → `selected=118 of=596`, kb-sh → `118`).
- 4 MD038 markdownlint violations on the plan; fixed; both artifacts lint clean.
- Plan-design defect corrected during deepen-plan: malformed-entry mint redesigned to `^glob:<verbatim>` (hit arm's malformed rule matches it).
- Planning subagent reported no subagent capability in its environment — Task-based phases ran sequentially inline (deviation recorded in plan).
- `requires_cpo_signoff: true` set (single-user-incident threshold) — CPO consult arranged by pipeline parent before `soleur:work`.

### Decisions
- Third declared edge kind `glob:<literal-head>/<pattern>` minted `^glob:…`; degrade ladder: head dir missing → `^<head>/`, malformed → `^glob:<verbatim>` (always-match), no metachar → literal recurse; hit arm recomputes validity and returns match on malformed.
- Uniform `glob:` for all six kb-walker suites including `operator-ack-guard`; `lint-trap-tempfile-ownership` gets 7 entries (`.sh .bash .py .ts .mjs .js` + `bunfig.toml`).
- Kind is declared-array-only: consumed/relevance arrays stay verbatim substring edges; G3 awk gains `GLOBENT`; census linter + kb-consumers oracle `covers()` learn the kind.
- Bench raw compare flags the six labels' rows on every probe → FR-5 prescribes scripted row-wise stream-diff + bench `--runs 1` for timing.

### Components Invoked
- `soleur:plan` (Phases 0–6.5, incl. skeleton, premise validation, measurement, scope check, observability, encryption posture, guard contract, sharp-edges read, plan-review, tasks.md, commit d5751c1b10)
- `soleur:deepen-plan` (Phases 1–9, all halts evaluated/passed; `lint-guard-contract.py` green on 5 guards; commit e5b77f2126)

## Collision Re-probe (post-planning)
- `linked:issue #9813`: none. `#9813 in:body` open: none; merged: #9816 (docs citation, zero path intersection).
- Anchor probe over planned files: open PRs #6778, #7390, #9640 touch `scripts/test-all.sh` incidentally (stale drafts, different scope); #9893 (OPEN, credential argv→stdin, different defect) adds `AFFECTED_TESTS_SCRIPTS_ARGV_BEARER_SWEEP_PATHS` in `test-affected-paths.sh` (~L926), `check_rule_d` hunks in `lint-shell-trace-credential-refusal.py` (~L1200), and a suite registration in `test-all.sh` (~L5381) — nearby-but-different regions; merge-conflict risk only, flagged for ship.

## CPO Sign-off (requires_cpo_signoff: true)
- Verdict: **APPROVED with conditions** (soleur:product:cpo consult, 2026-10-10).
- Condition 1 (blocking, APPLIED): five plan sites said malformed mints bare `^` — a bare `^` is select-nothing (`e=""` → `*\n\n*`), not always-match. Amended lines ~199, ~225, ~392, ~571 to `^glob:<entry verbatim>` before `soleur:work`.
- Condition 2 (advisory, for work phase): pin the malformed-shape invariant with a cross-site comment at mint arm / hit-arm revalidation / census arm (one invariant, three sites).

## Work Phase (Tier C — sequential)
- RED→GREEN derive rows Rg1-5 (121/121). Hit arm `glob:*)` + mint arm landed; header comments pin the malformed-shape invariant at three sites (CPO cond 2 satisfied).
- Lib swap: six arrays → `glob:`; trap-tempfile 7-entry set; +2 literal `.md` edges the consumer oracle surfaced as REAL reads (provision-* DPA_FILE for ack-guard; ADR-207 for agent-runnable via battery-tag-authorship hop).
- Oracle discipline: fixture kb literals composed via `${_KB}`/`${_kn}`/`"knowledge""-base/…"` or renamed to carry `sandbox`/`fixture` tokens — the oracle's FIXTURE regex charges a bare `knowledge-base/<path>` token as a real read.
- G3 awk `GLOBENT` admitted at three sites; 7 new RC_TABLE rows (90 classifier rows pass).
- Census arm + M21-26 (92 passed, 26 gated rows).
- kb-consumers oracle `covers()` `^glob:` arm (22/22).
- Verification: kb-md declines all six (kb-consumers still selects); kb-sh selects all six at 3 depths; rename-source selects; .py/.bash/.ts/.mjs/.js/bunfig.toml → trap-tempfile only; malformed → still selects; receipt carries `^glob:` verbatim.
- Stream-diff vs merge-base: ZERO sel-bit flips on both bench probes; 18 rows differ in edge text only (six declared + ~12 closure-minted `^glob:`/literal edges on runner-fixture suites — widening only, fail-safe).
- fanout-suite-scope 53/53; c4-model-freshness 4/4; markdownlint clean.
- Flakes: two rc=143 arm kills (p4, tg4-.py) — external tmp reaper deleted TESTROOT mid-run; tg4 .py row passed in the sibling run.
- Commits: bd2a6df306 (impl), 480a43c8e6 (pin fixes), dd3c331706 (ADR + tasks). Force-with-lease push synced the rebased history to PR #9945.

## Review Phase
- Class: code (`.sh` present) → 8-seat panel. design-risk SET (new vocabulary three files must learn + economics justification) → design pass first: simplicity + architecture + performance (3 seats, dedup applied).

## Review Findings Applied (design pass + panel, 9 seats)
- **B1 (blocking, arch+pattern):** path-semantic malformed heads (`..`,`/`,`//`,`/./`,`/../`) minted dead edges the census passed → doctrine extended at all five sites with closed-charset + repo-relative-head clauses; `*/`-terminated tails (dead, unmatchable) added after pattern A3. Rg3 covers 13 malformed shapes; M27 pins `../`,`/`/`*/` census REDs.
- **agent-runnable (security advisory → disposition change):** Guard-1 `g1_discover` is content-keyed (`git grep --untracked` for the marker on ANY extension) — **.sh would under-cover a kb .md quoting the marker → kept `knowledge-base/` (~16 committed s); tg rows re-structured (_TG_GLOB_WALKERS five / _TG_ALL_SIX six).
- **GLOBENT superset (3 seats):** qualified at all doctrine comments; `ok_idx_glob_dotdot` pins the `../`-admission as deliberate.
- **Doc precision:** census error direction per branch; `covers()` dir-ref assumption; ~248s five-walker attribution; ADR frontmatter; stale banners/comments; `_kn`→`_KB`; fnmatchcase; dead-tail wording.
- **Verdicts:** arch SHIP-WITH-FIXES, simplicity SHIP-WITH-FIXES, performance SHIP-WITH-FIXES, security SHIP, data-integrity SHIP-WITH-FIXES, agent-native SHIP-WITH-FIXES, git-history SHIP, code-quality SHIP-WITH-FIXES, pattern SHIP-WITH-FIXES.
- **Deferred advisories (not in scope):** pre-existing under-cover siblings repo-write-boundary/guard-vacuity-floor/lint-orphan (kb-less whole-tree corpus — glob kind now makes the fix expressible; follow-up issue candidate); `_affected_glob_split` extraction (deferred to next grammar touch); `|` in verbatim mints (cosmetic); `*bunfig.toml` overmatch (widen-only).
- Verification pending: final clean battery + orphan + kb-consumers runs.

## Compound Phase
- Learning: knowledge-base/project/learnings/workflow-issues/2026-10-10-a-declared-edge-must-say-what-the-walker-reads-and-a-malformed-one-must-fail-wide.md (10-item session-error inventory, preventions, test patterns, related docs).
- Rule budget: [OK] B_ALWAYS=43166 (98 rules, longest 596B, constitution 317) — no promotions proposed (all insights domain-scoped → learning + ADR only).
- Deviation analyst: no hard-rule deviations; rule-metrics aggregate ran (81 unused-8w, informational).
- Deferred-scope-out filed: #9969 (under-cover siblings — whole-tree corpus suites the glob kind now makes expressible + review advisories).
- Archive-kb deferred to ship Phase 6 (ship reads the spec dir — its Phase 6 step 5.5 archives after the last live read, same PR).
- Post-rebase note: origin/main advanced +6 (#9893 argv-bearer merged — additive, zero conflicts, ARGV_BEARER_SWEEP literal .md edges only; suite count 600→601, q4's >=100 pin holds).

## CI Fallout Round (first CI run on the pushed branch)
- `shard-totality-mutations` legs 15-28/29-42 FAILED — anchors pinned the old `--rows 1-10`/`11-20` tiling; M21-27's re-split to `1-13`/`14-27` missed them all (ANCHOR MISSING). Fixed by re-tiling every anchor/mutant; both legs verified 15/15 locally.
- `test-scripts (4/8)` FAILED — T10 derive-span read-census flagged my trailing comments spelling `tail X`/`head X` (the awk parses comment words as the commands' operand form). Reworded to `_gt`/`_gh`; derive-cache 19/19 green.
- `test-scripts (5/8)` FAILED — `test-all-killed-classification` T14 budget fixture (`elapsed '' want >=40`; unrelated suite, looks CI-load flake — retried on rerun).
- `test` aggregator failed as consequence. Lesson recorded: --rows tiling anchors live in a SECOND battery (shard-totality-mutations) — a DECLARED_TOTAL bump must grep for the range literals repo-wide, not just the two registrations.
- Hit-arm restructure: the `*)` head/tail checks are now `[[ == ]]` tests — the budget splice counts `    *) return 0 ;;` as a SUBSTRING and a bare arm at ≥4 indent collides (T14 CI failure root cause). Anchors re-verified unique.
