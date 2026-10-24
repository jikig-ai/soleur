# Tasks: WikiSkill pattern layer + proposer index/ledger reader (#8293)

Plan: `knowledge-base/project/plans/2026-10-24-feat-wikiskill-pattern-layer-proposer-index-ledger-reader-plan.md`
PR body: `Ref #8293` (never `Closes`); `Ref #10552` only where relevant. Do not touch #10552, #10550, #10551.
One PR, seven commits in the order below. Tests first inside every phase.

## Phase 0: Preconditions (no commit)

- [x] 0.1 Read-only re-verification: `gh issue view 10552 --json state` (no comment), tracked learnings count, ADR next free ordinal, green baseline for `apps/web-platform/test/server/inngest/cron-compound-promote*`
- [x] 0.2 Confirm the PR author login of an app-authored PR is `soleur-ai[bot]`; confirm which container hosts the handler (for the C4 edge)
- [x] 0.3 `bash plugins/soleur/test/c4-count-parity.test.sh` green
- [x] 0.4 Capture the scheduled-path golden marker key set and value types on `main` before editing the handler

## Phase 1: ADR, C4, docs (commit 1)

- [x] 1.1 ADR-297 via `soleur:architecture create` (decision, reader contract, Alternatives = Cut List, reader classification table, WikiSkill CC BY 4.0 attribution, status adopting)
- [x] 1.2 `model.c4`: `kb` description gains "pattern wiki (project/patterns)"; add the `api -> github` edge; regenerate `model.likec4.json` if required; run c4 tests
- [x] 1.3 `promotion-log.md` header: accepted-or-pending only, Octokit lookup, drop the nonexistent workflow reference (no schema change)
- [x] 1.4 `compound-promote-runbook.md`: `input` option, new marker fields, stale workflow reference (~L208)
- [x] 1.5 `betterstack-log-query.md`: marker field list gains the five fields
- [x] 1.6 Legal: PA-31 §(c) dated note; DPIA addendum (triggers 15 and 2, "does not cure" sentence); `Superseded` markers in the memo §2 and `compliance-posture.md` (~L169)

## Phase 2: Pattern module, schema, lint (commit 2)

- [x] 2.1 RED: `compound-promote-patterns.test.ts` and `compound-promote-patterns-live-tree.test.ts`
- [x] 2.2 `compound-promote-patterns.ts`: `parsePatternPage`, `loadOpenPatterns` (injected `piiRegex`), `renderPatternIndex` (nonce-fenced block; title/summary/tags/evidence keys only)
- [x] 2.3 `compound-capture/assets/pattern-page-template.md`
- [x] 2.4 Extract the shared `fenceBlock` from `draftAdditiveEdit`; use `gray-matter` (`engines: {}`); runtime evidence-path validation; whole-file PII scan + handle/UUID/host denylist
- [x] 2.5 Register the live-tree and patterns-handler suites in `apps/web-platform/test/repo-wide-suites.ts`; bump `BASELINE_DECLARED_PROBES` (76 -> 77, re-read at work time) with its comment

## Phase 3: Ledger reader (commit 3)

- [x] 3.1 RED: `compound-promote-ledger.test.ts` (+59 / exactly 60 / +61 days, human author, title builder/parser pin, 502 / 403 / page-cap, property test, bot-login pin vs the reaper literal)
- [x] 3.2 `compound-promote-ledger.ts`: `promotePrTitle`, `PROMOTE_PR_TITLE_RE`, `readLedger` (via `fetchAllPages`, cap 5 pages, `incomplete_results` / `total_count` / `closed_at` / drift fail closed), `decideSuppression`; `SOLEUR_BOT_LOGIN` export in `_cron-shared.ts`

## Phase 4: Handler wiring (commit 4)

- [x] 4.1 RED: `cron-compound-promote-patterns-handler.test.ts` (scheduled path ignores `input`; patterns path; empty patterns; invalid input; ledger failure; suppression; replay; `allowedPaths`; fence)
- [x] 4.2 `readRunOptions`, hoisted state, `stage` variable, `ledger-read` step (patterns path only)
- [x] 4.3 `collect-patterns` step; `empty-corpus` with `input_source:"patterns"`
- [x] 4.4 Hoist normalisation above the empty/truncated check; suppression on the patterns path; extend the existing `no-qualifying-clusters` emit; no new return
- [x] 4.5 Title built with `promotePrTitle` (same string as before)
- [x] 4.7 Document the interim operating rule (no manual patterns run before the 2026-10-25 marker or while a `self-healing/auto` PR is open) in the runbook
- [x] 4.6 `compound-promote-marker.ts`: five typed fields; update marker test (allowed-keys) and census (return count, `TARGET_ALLOW_RE.test(` count stays 2)

## Phase 5: Seed (commit 5)

- [x] 5.1 Candidate clusters from `SOLEUR_WM_WINDOW_DAYS=90 SOLEUR_WM_DIGEST_PATH=<scratchpad>/dg90.md bash scripts/weakness-miner.sh`
- [x] 5.2 Dedupe by Jaccard > 0.5; keep clusters with >= 5 evidence learnings; write up to 8 pages by hand (summary, Root cause, Fix); ship fewer if fewer qualify; < 3 recorded as insufficient
- [x] 5.3 Live-tree test green; no names, handles, credential shapes

## Phase 6: Retarget the three concepts (commit 6)

- [x] 6.1 `compound-capture/SKILL.md` Step 7 and the three "Required Reading" menu copies -> read-only pointer to the template and a reviewed PR, still usable in repos without a patterns directory
- [x] 6.2 Delete `assets/critical-pattern-template.md`; sweep its reference
- [x] 6.3 `learnings-researcher.md` Step 3b -> `required_reading` pages, guard for an absent directory, legacy `critical-patterns.md` fallback
- [x] 6.4 Zero live hits for `critical-patterns|common-solutions`; add the `generate-kb-index.test.sh` pinning case (script itself untouched)

## Phase 7: Trackers (commit 7)

- [x] 7.1 File the flip-tracker issue (`Ref #8293`, context `Ref #10552`) with the Effect Measurement Plan and the deferred deliverables and triggers
- [x] 7.2 File the `/compound` upsert deferral issue

## Phase 8: Gates

- [ ] 8.1 `python3 scripts/lint-guard-contract.py <plan>`; vitest shard; `generate-kb-index.test.sh`
- [ ] 8.2 `soleur:gdpr-gate` over the diff; `user-impact-reviewer` and observability-coverage reviewer at review
- [ ] 8.3 PR body: `Ref #8293`, effect unmeasured until #10552 clears, no causal claim about the dump, `## Changelog`
