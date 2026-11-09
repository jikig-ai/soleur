# Implementation progress (subagent checkpoint)

PLAN: knowledge-base/project/plans/2026-11-09-ci-s4-stage-retirement-plan.md
TASKS: tasks.md — tick checkboxes as phases complete.

## DONE
- Phase 1 COMMITTED (f72f997357): created scripts/ci-oracle-surface.txt (11 members), rewrote
  ci-oracle-review.sh resolution chain (base surface.txt -> base replay.py importlib -> HEAD surface.txt;
  empty/unreadable -> fail api/shape never not-oracle). Updated ci-oracle-review.test.sh (surface+legacy+head
  arm fixtures, STUB_GIT_SHOW_SURFACE env via no-colon default, new rows row_oracle_list_empty/
  row_legacy_fallback/row_head_fallback added to loop) and bot-synthetic-unreachability.test.sh
  (oracle source -> surface file, dropped ratchet required-checks assertion). Both suites green.
- Phase 2+3 ci.yml edits DONE (uncommitted): deleted pr-selection job+comments, affected-index-ratchet
  job+comments, needs lists x4, if: PR terms x3, aggregator SKIP_LEGS/ACTIVE/HEAD_SHA_OK env +
  PR-AFFECTED-SKIP tolerance arm + cached-skip remedy + tolerated plumbing. yaml jobs==20.
  oracle-selection comments re-anchored; oracle-index-check comment updated (worst leg ~12min
  test-all-affected-d); oracle-review comment -> resolved oracle list.
- Registry removals DONE (uncommitted): required-checks.txt row+comment, canonical JSON row (11),
  ruleset-ci-required.tf block (comment kept "S4 ratchet member" wording — NO 'affected-index-ratchet'
  literal allowed anywhere in .github/infra/scripts/plugins/tests/.claude/apps per AC census),
  test-audit-ruleset-bypass T-rsc-7 12->11 + history line, probe-merge-group-coverage MIN_CONTEXTS 14->13,
  canonical-parity floors -ge 11, admin-merge-ready fixtures (rules-branches-main.json context,
  check-runs.json run, README dated note + counts 13->12/15->14), admin-merge-ready.test.sh >=12 +
  required=14, pr-fanout-ledger.txt appended "-2 2026-11-09 ... yaml.safe_load is 20."
- ci-oracle-lane-suites.txt: removed 5 retired members + comment updates. ci-oracle-lane-legs.tsv:
  REPACKED LPT (worst leg leg1 test-all-affected-d ~10.2min+checkout ~12min wall).
- action.yml verified: derives CHECK_NAMES from required-checks.txt at runtime — no edit.
- ci-push-dedupe.test.sh: MAJOR REWRITE DONE but NOT YET RUN. Header: PR_GATED_PINNED="" (deliberate),
  PR_TERM_PRE/PRSEL_IF="" kept exported; UNGATED_PINNED dropped the 2 names; AGG_DIGEST recomputed =
  c6b0d2a8b48a96f10baf81f133a575faf073fec1d68455829121be1ab112746a. chk.py modes rewritten:
  prsel=absence pin (P-JOB-PRESENT + kept P-TOPENV/P-TOPDEFAULTS); prcensus=zero-refs pin (C-REF/C-VARS on
  any found); legparity=absence pin (L-SKIPRE/L-TERM/L-DRIVER-PRESENT/nonempty PRGATED); zero-prsel=copies
  verbatim when job absent; darkequiv=absence pin (DE-JOB-PRESENT/DE-CONS). Mutation span COND_DEFAULT..
  oracle-reference-census REWRITTEN via /tmp/span.txt splice: BUN_HDR/COND updated to or_term-only;
  post-removal mutants added (y-prsel-job-returns x2, y-pr-term-returns, y-pr-need-returns, y-pr-e2e-needs,
  y-prneeds-extra, y-agg-skipre-returns, y-census-*, y-leg-pinned, y-driver-returns, vars_step_if set,
  y-vars-step-env/job-env, y-top-env/top-defaults).

## TODO NEXT (in order)
1. ci-push-dedupe.test.sh: relabel live_check lines (~893-898: "PR-SELECTION ABSENT", "PR-SELECTION
   REFERENCE CENSUS (zero)", "DARK LEVER ABSENT"); update budget comment ~927-934 (lever retired, check
   stays as re-introduction guard); RUN `bash scripts/ci-push-dedupe.test.sh`; fix _FLOOR + MUT floor
   literals to measured values.
2. ci-draft-light.test.sh: same shape — drop pr-selection from LIGHT_PINNED (:110), PR_T_* grammar
   (:85-93), `["pr-selection"] if n in PRGATED` (:159), ev() translations (:186-192), A-NEEDS-SET
   (:353 -> remove pr-selection), needs fixture literals (:978-1102 -> post-removal sets).
3. plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh pr-selection arms (:585-637,727,852,1045-1100).
4. apps/web-platform/test/c4-likec4-version-pin.test.ts:259 PR_AFFECTED_WEBPLAT_IF -> drop pr-selection clause.
5. ci-e2e-classify.sh:23 + ci-shard-totality-classify.sh:27 comment re-anchors.
6. Phase 4 deletions: scripts/ci-pr-affected-replay.py, ci-pr-affected-preactivation.sh,
   ci-pr-affected-audit.accept.tsv, ci-pr-selection.sh, ci-pr-selection.test.sh,
   plugins/soleur/test/ci-pr-affected-replay.test.sh, ci-pr-affected-preactivation.test.sh,
   runbooks/ci-pr-affected-activation.md.
7. test-all.sh: remove registrations (:5651-5653, :7152, :7554-7558) + comments (:2840,:3576).
8. ci-oracle-lane.sh: drop replay.py from is_excluded_path (:181), memberless is_oracle_data_path
   (:167-173), comments (:60-75).
9. ci-oracle-lane.test.sh pins (O-DOCPARITY -> literal byte-pin of is_doc_path body in ci-oracle-lane.sh;
   exclusion/legs fixtures).
10. suite-durations.tsv (remove 4 rows :195-198,:398 incl ci-pr-selection), suite-shard-legs.tsv
    (:197-200,:400), test-affected-kb-consumers.baseline.txt (:165-171).
11. test-affected-paths.sh: remove dead-suite edges (:530-531,:2060-2129,:4128,:4958-4983) + comments
    (:1125,:4293-4294). MINIMAL diff (oracle surface).
12. test-suite-lanes.sh: remove 3 lane_declare replay rows (:135-148) + comments; test-suite-lanes.test.sh:
    remove/adapt replay-arm section 6 (arm floor<3, replay_file checks, empty-override comparison).
    lint-betterstack-emitter-read.sh:185 remove accept.tsv allowlist row. lint-orphan-test-suites.sh:269
    + guard-vacuity-floor.test.sh:1363 comments.
13. fixture-relative-assert.baseline.txt regen; scripts-shard-totality.test.sh:158 replay-split
    subtraction; terraform-target-parity.test.ts:10563 + ci-head-verdict.test.sh:1216 comments.
14. .claude/hooks/grep-q-pipe-guard.test.sh:2170 fixture row substitute.
15. code-quality-followups-watch.yml:81 comment.
16. Runbooks ci-oracle-lane.md (:17,:74,:181) + ci-test-scripts-sharding.md (:31,:350-354,:518).
17. ADR-276 amendment (dated ### Stage status line: S4 retired NO-GO 2026-11-09, dissent pair).
18. VERIFY: full Phase-5 battery + residual-zero greps + jobs==20 + test-all.sh --affected probe;
    receipts in specs/feat-one-shot-9729-s4-retire/receipts/.
19. Commits per phase via `git -C <worktree> commit`; update tasks.md checkboxes; final summary format.
NOTE: draft PR #12521 exists — do NOT touch; do NOT push; do NOT merge.
