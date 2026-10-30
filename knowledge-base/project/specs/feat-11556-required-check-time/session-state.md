# Session state — feat-11556-required-check-time (work resume)

Branch: feat-11556-required-check-time | Worktree: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-11556-required-check-time
PR: #11561 (draft) | Issue: #11562 | Epic: #11556
Plugin root: /home/jean/.local/share/devin/cli/plugins/cache/github.com_jikig-ai_soleur_plugins_soleur-5a09ea60/0.0.0-unversioned (local session, hooks live)
Plan: knowledge-base/project/plans/2026-10-29-ci-required-check-atomic-suites-plan.md
Tasks: knowledge-base/project/specs/feat-11556-required-check-time/tasks.md
Push: remote branch is PRE-REBASE at 1bad9ae99 → `git push --force-with-lease` needed.

## Done (committed)
- d480451773: rc_g hoisted to unconditional (was gated block 13, called by blocks 28/37/38 → command-not-found on arms b/d); AFFECTED_CONSUMED_EDGES now lists 4 arm labels sharing TEST_ALL_AFFECTED_BATTERY_PATHS (scripts/lib/test-affected-paths.sh:373-376); deleted scripts/*.tsv.n strays. lint-orphan now GREEN.

## Done (UNCOMMITTED in working tree)
- scripts/test-all.sh ~7245-7250: replay arm registrations changed `bash "$f"` → literal `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` (totality checker resolves battery via argv token).
- .github/workflows/ci.yml ~1435-1439 + ~1479-1483: stale ~9.5min/leg comments rewritten (no literal numbers; point at runbook).

## Totality pre-regen (expected red): 7/50 — causes: arms not pinned in manifests + the $f unresolved (now fixed). Re-run AFTER regen.

## Arm runs in flight (detached setsid, logs+rc in worktree)
- replay arm a `--rows 1-193` → .work-run-replay-1-193.log/.rc (running since 10:10, ow_* soak probes PASSing)
- affected arm d `--rows 37-38` → .work-run-affected-37-38.log/.rc (restarted ~10:16 post-rc_g-fix; th4 census rows [ok])

## Remaining arms to run (each: cd worktree; bash X --rows A-B > log 2>&1; echo $? > rc)
- replay: 194-386, 387-578 | affected: 1-13, 14-32, 33-36
- LAUNCH FORM (learned): `cd` INSIDE the bash -c string, or run setsid as its own exec — `cd X && setsid A & setsid B` backgrounded the whole `cd && A` so B ran from bare root on STALE copy.

## Phase 3 remaining
- Record per-arm wall times → build --timings-dir (dir per run, suite-timings.tsv rows `label<TAB>ms`). --timings-dir mutually exclusive with --runs (elif); --durations wins. To keep incumbent medians AND price new arms: pass N downloaded green-run artifact dirs + a local dir with the 7 new labels' rows.
- `python3 scripts/regenerate-shard-manifest.py --runs 5 --write` LIGHT ONLY as LAST isolated commit (never hand-edit TSVs; manifests committed deterministic; re-run --incremental after rebase).
- Verify new -a/-b/-c/-d labels pin to DISTINCT legs post-regen; re-run scripts-shard-totality.test.sh → target green.
- `--legs K` dry-run K∈{8,10,12} verification-only (K bump only if worst leg still >bound).
- Runbook ci-test-scripts-sharding.md: topology table (~L27-40), Measured history (~L196+), add dated ~2wk regen-ownership checkpoint + rebase-regen note.
- Affected-gate exit: `bash scripts/affected-tests.sh` before Phase-3 close.

## Phase 4 remaining
- Fresh p90 baseline via jobs API (~10-15 green PR runs; queue vs execution) → runbook Measured history.
- CLO invariants: scripts/required-checks.txt byte-identical; fetch-depth:0 preserved; no merge_group cancel; timeout-minutes:60 unchanged.
- tasks.md: tick 2.1-2.3, 3.1-3.4, 4.1-4.3 as verified.
- Epic #11556 actuals + #11562 comment (post-merge follow-through ok).

## Pipeline after verification
push (--force-with-lease) → soleur:review → resolve-todo-parallel → compound → ship.
CLA author gate: commits must be authored by CLA-signed identity (jean.deruelle@jikigai.com is fine).

## Learnings this session
- `cd X && setsid A & setsid B` → B ran from bare root, STALE suite copy. Always put cd inside bash -c.
- Cross-arm dep: gated-block function defs invisible to sibling arms (rc_g). Static analysis found only rc_g; verified by arm-d failure + fix.
- run_suite argv must carry LITERAL path for totality checker.

## Floor finding (in-flight fix)
- Arm affected-1-13 rc=2: 19 cases vs ceil(243*13/38)=84. Case emitters per block are 1-30 (non-uniform) — linear MIN_CASES scaling is wrong for sparse arms.
- Fix being applied: ranged floor → `cases >= EXPECTED_EXECUTED` (≥1 case per dispatched block); full run (ROWS_HI==0) keeps MIN_CASES=243. Integrity already carried by _site_seq==DECLARED_TOTAL + EXECUTED==range + PASS+FAIL==cases.
- Arm results so far: replay-1-193 rc=0 (891 assertions, 85 mutants); affected-1-13 rc=2 (floor only — rows all [ok]).

## Update (post-fix commits)
- d5e9655bed committed: ranged floor = EXPECTED_EXECUTED (>=1 case/block), full-run keeps MIN_CASES=243; literal argv in run_suite; ci.yml comments fixed.
- Arm results: replay 1-193/194-386/387-578 ALL rc=0 (891/891/890 assertions); affected 1-13/33-36/37-38 ALL rc=0 (19/51/86 cases). affected-14-32 STILL RUNNING (m* rows spawn sandboxed --affected fixtures, ~5min each under contention).
- Timings dir started at /tmp/timings-local/suite-timings.tsv (label<TAB>ms<TAB>pass); pending -b arm time.
- Runbook topology table updated (uncommitted).

## Update 2
- d5e9655bed committed: ranged floor=EXPECTED_EXECUTED; literal argv in replay arms; ci.yml comments.
- Arm results FINAL for 6/7: replay-1-193/194-386/387-578 all rc=0; affected-1-13=0 (19c), 33-36=0 (51c), 37-38=0 (86c). affected-14-32 (pid 4017682) STILL RUNNING at m5+ rows, ~50min, sandboxed fixture children active — NOT wedged, just slow under contention.
- NOTE: an earlier 14-32 run seems to have finished once with "91 passed, 1 failed of 92 — l1: affected+subagent rc=1 ran=9" (investigate l1 row if the live run also fails l1: sandbox runs --affected with SOLEUR_SUBAGENT=1 + SANDBOX_DIFF_NAMES=.github/workflows/apply-sentry-infra.yml, expects rc=0 ran>0).
- Runbook topology row updated (uncommitted). Timings dir /tmp/timings-local/suite-timings.tsv has 6 arm rows (label<TAB>ms<TAB>pass); add affected-b once rc lands.

## Update 3 — regen + totality state
- ALL 7 ARMS GREEN (affected-14-32 rerun rc=0; earlier l1 fail = contention flake, passes isolated).
- Arm timings: replay a/b/c=1756/930/971s; affected a/b/c/d=996/5915/1926/2479s (contended).
- Pricing method: CI-median x local-share. CI medians (5 green PR/merge runs in /tmp/timings-ci): replay 1322511ms, affected 1746404ms. Estimated arm ms written to scripts/suite-durations.tsv by full regen.
- Committed manifest (UNCOMMITTED in git): arms at legs replay 2,7,4 / affected 7,1,8,3; legs 1678-1758s, spread 79s.
- Totality still 6 red: (a) ref_glob double-counts special-cased ci-pr-affected-replay.test.sh — FIXED in scripts-shard-totality.test.sh (subtract `"$f" == "..."` specials, lines ~155-160, UNCOMMITTED); (b) lint-orphan halves co-located 5,5 by regen — FIX IN PROGRESS: restore HEAD manifest + keep durations (has arm estimates) + run --incremental --write (pins lint-orphan 5,2 verbatim).
- timings dirs: /tmp/timings-ci/<runid>/, /tmp/timings-local, /tmp/timings-est

## Update 4 — Phase 3 essentially DONE
- Generator arm-separation added (assign() post-pass: -<letter> siblings distinct legs). lint-orphan a=1/b=5, my arms replay 2,7,4 / affected 7,1,8,3. Spread 441s (<10min bound).
- Totality fix: ref_glob subtracts `"$f" == "..."` glob-loop specials.
- Commits: 60b93ac5d3 (machinery+runbook+totality), fe302de771 (regen, isolated). TOTALLITY NOW GREEN (52 rows).
- CLO invariants OK: required-checks.txt byte-identical, fetch-depth:0 intact, no merge_group cancel.
- affected-gate `bash scripts/test-all.sh --affected` RUNNING (degraded to MODE=full since runner changed) → .work-run-affected-gate.log/.rc
- Plan's literal `bash scripts/affected-tests.sh` doesn't exist — real mechanism is test-all.sh --affected.
- REMAINING: p90 baseline via jobs API → runbook Measured history; tasks.md checkboxes; push --force-with-lease; soleur:review→resolve-todo-parallel→compound→ship.

## Update 5 — pushed + review phase
- Push done: a5c01e4091 forced (pre-rebase remote). Commits on branch now include e82f08c (split), d480451 (rc_g+edges), d5e9655 (floor+argv+ci.yml), 60b93ac (gen+totality+runbook topo), fe302de (regen), a5c01e4 (docs+tasks+state).
- Affected gate: rc=4 refused (sibling) → relaunched SOLEUR_ALLOW_FULL_GATE=1 (degraded MODE=full since runner changed) → .work-run-affected-gate.rc pending.
- Pipeline now: soleur:review (skill running) → resolve-todo-parallel → compound → ship. Review SKILL.md at plugin cache skills/review/SKILL.md; steps: classification → merge-tree check → panel agents → synthesis → issues → exit gate.

## Update 6 — rebase done, review panel starting
- Rebased onto origin/main (dbc59724); suite-durations.tsv conflict resolved by checkout --ours + re-regen (legs 1678-1758s, spread 79s). Re-verified: totality 51/51 green. Pushed f5711f3 (PANEL_SHA).
- Review classification: code → 8-agent panel; design-risk YES → design pass first: code-simplicity + architecture-strategist + performance-oracle (economics claim). Panel after dedup = 6.
- Affected gate still running (SOLEUR_ALLOW_FULL_GATE=1 MODE=full) → .work-run-affected-gate.rc
- Agent defs: /home/jean/.local/share/devin/cli/plugins/cache/github.com_jikig-ai_soleur_plugins_soleur-5a09ea60/0.0.0-unversioned/agents/engineering/review/*.md

## Update 7 — design-pass findings + fixes (UNCOMMITTED)
Design pass (simplicity+arch+perf) found missed rename blast radius — all 3 seats converge:
- FIXED: test-all-pr-battery-gate.test.sh — L_TAA→4 labels + TAA_ARMS, own-taa/local arms, UNIVERSE, sixth-site anchor re-pointed at -d skip text
- FIXED: test-all-infra-coverage-notice.test.sh:414 — GATED row → 4 arm rows (DOCS_SKIP floor self-corrects)
- FIXED: ci-pr-selection.sh:202 → 4 case entries; ci-pr-selection.test.sh:1493 mutation re-anchored on -a
- FIXED: lint-orphan surface-2 — subtract only glob_special ∩ raw1 (diverted files); c4-from-components skip-only special stays glob-covered
- FIXED: regen — separate_arm_groups() extracted, called by BOTH assign() and incremental path; dead default=None removed
- FIXED: totality — glob_special coverage assertion (ref_static label OR run_suite token; c4 vs replay shapes); -<letter> convention asserted on --rows labels
- FIXED: stale comments (test-relevance-paths.sh:201, test-affected-paths.sh:182), runbook predicted-leg wording + --incremental-only guidance
- lint-orphan re-green (773, 0 orphans). Suites running: battgate, infranotice, prsel, tot4 → .work-run-*.rc
- DEFERRED (report to panel): est src tier (measured-tag fudge), per-block declared floors (residual), ADR for arm convention, --rows preamble extraction (4th copy), exit-code parity
- PENDING: design-pass verdict → 6-agent panel → synthesis; affected-gate run queued position 3

## Update 8 — review-fix commit pushed, panel in flight
- All design-pass fixes verified: battgate 96/96 (34/34 mutants), prsel 4583/4583 (101/101), infranotice 266/266, totality 51/51, lint-orphan 0 orphans, fixture-assert 63/63.
- Commit 92e2740f99 pushed (normal push, no force needed).
- Note: 3 consumer suites initially ran in BARE ROOT (main) due to `cd X && setsid A & setsid B` parsing bug — only battgate inherited the worktree. Fixed by literal-path cd inside each bash -c.
- PANEL_SHA=92e2740f99. 6 panel seats spawned (git-history, pattern-recognition, security, data-integrity, agent-native, code-quality) — arch+perf deduped from design pass.
- Affected gate: MODE=full running (m6* rows).

## Update 9 — review panel synthesis + fixes
- 6-seat panel: no P0s. Two P1s found and fixed:
  1. fast-tier-budget red: full --timings-dir re-price exposed pre-existing always-on weight drift (8 labels 11-378s real vs stale committed prices). Fixed via --durations seed regen (incumbent prices preserved + arm estimates seeded). Budget suite green 9/9.
  2. affected-index-ratchet: baseline keyed on retired replay label; each arm audits same file → 9 new-pairs. Fixed: -3 stale baseline rows + 54 anchor-keyed accept rows (18/arm: README 12, gitignore 2, ruff 4 across suite+lint-ratchet.py+ci-pr-affected-replay.py reach). Ratchet exit=0.
- Fix-inline applied: reorder-guard overclaims corrected (add/delete only), stale numerals (six→nine labels, M1..M16→M1..M35, one-mega-suite→plural), separate_arm_groups WARN on >n siblings + ascii_lowercase, usage hints on unknown-arg (3 batteries), regen command in totality fail msgs.
- Defer to issues: est src tier, per-block declared floors, --rows preamble extraction (5th copy trigger=met), exit-code parity, arm-convention ADR, split-checklist doc.
- totality re-running on final manifest; affected-gate still in flight.
