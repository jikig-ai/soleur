# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-12-ci-epic-11556-ac-chain-followthrough-plan.md
- Status: complete

### Errors
- `mechanical` is not a valid decision-challenge class → reclassed `taste` (fixed in-subagent)
- `gh issue view --jq` number+string concat error → fixed jq shape (fixed in-subagent)
- 4 `pending - assumed` technical rows remain in decision-challenges.md → parent carries ONE batched soleur:engineering:cto spawn before work (technical-ruling-gate)

### Decisions
- Probe `main-health-monitor-mutations-12626.sh` discriminates scheduled runs by `actor.login == "soleur-ai[bot]"` + `created_at >= 2026-11-12T19:46:34Z`, cancelled excluded, per-run mut-leg assertion, exit vocabulary 0/1/2/3/78
- Classifier follow-up issue: in-job detect step modeled on verified ci.yml:2137–2168, fail-closed, v1 markdown-only allowlist, `--rows` lever folded in (binding CTO carry), refs #11556/#12626/#9729
- Lever-A re-rank via merge_group `suite-timings-scripts-*` + `regenerate-shard-manifest.py --timings-dir/--runs`; stale 185400ms row at suite-durations.tsv:429 to be reconciled against regenerated table
- Lever-F/p90 measured via watch-wallclock-p90-11774.sh --dry-run (goals 1200s PR / 900s merge_queue); critical path now `test-scripts (6/8)` 2483s
- #12269 soak untouched; #12647/#12651 verified OPEN; trackers #12455/#12618 CLOSED — 18:00Z run 43275349911 failed on PRE-merge code (sha 2f8e28a164), not a regression

### Components Invoked
- soleur:plan (full execution incl. plan-sharp-edges.md)
- soleur:deepen-plan (all phases; Reviewed-Coverage: sequential-fallback — no nested-spawn in this harness)
- scripts/lint-guard-contract.py, plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh, markdownlint-cli2, gh

## Operator Constraints
None present in the resume brief — the brief carries no `## Operator Constraints` section, no HOLDS list, and epic #11556's body carries none (verified live at Step 1.5: zero holds-list markers).

## Work Phase
- Status: implementation complete; Phase-2/3 gates in final verification; PR #12698 (draft), branch pushed through 116ac789e2
- Probe + fixture suite landed (26 assertions, 7/7 mutants, harness row): `scripts/followthroughs/main-health-monitor-mutations-12626.{sh,test.sh}`, registered LAST in test-all.sh followthroughs block; orphan census 845/0 clean
- Manifest: `--incremental --write` seated the suite (floor 1272ms→1799ms after re-price, leg 2); `--timings-dir --write --allow-growth` re-priced the light group on 5 green merge_group runs (43308874521, 43286327218, 43278615612, 43185108804, 43138951876): 42 rows moved, +51.5% measured weight, predicted legs 1761–1817s (spread 89s); dedupe-soak row reconciled 185400→81308ms; heavy group zero drift, no write
- Tracker #12716 filed (scheduled-run confirmation; `secrets=GH_TOKEN`, probe staged in bare-root overlay + [main] worktree for the HOOK_CWD gate)
- Classifier issue #12717 filed; committed body artifact `classifier-issue-body.md`
- p90 re-measured 2026-11-12T22:10Z: `test` p90 4343s PR / 2937s merge_group (goals 1200/900; PR p90 breaches bound 3300×1.30) — sample still pre-#12654-dominated
- Epic #11556 commented (comment-6837335240): enrollment status, #12717, re-rank result, honest Lever-F numbers, 14-day goal explicitly unverified
- Tracker hygiene: #12647/#12651 OPEN untouched; #12269 directive intact (soak to 2026-11-30); #12455/#12618 CLOSED (pre-merge reds, #12618 auto-closed 21:25Z on run 43277321607)

### Gate findings from the re-price (116ac789e2)
- The +51.5% re-price moved two rows past committed-weight guards; both fixed via the prescribed mechanisms:
  - `scripts/image-cve-public-claim-guard` 1,223 floor → 11,494 measured (> LOCAL_FAST_CAP_MS=10000): demoted off ALWAYS_ON_SUITES to edge-selection per the #9763/#11648 withdrawn mechanism; edge set = the guard's own SURFACES list verbatim (`AFFECTED_SCRIPTS_IMAGE_CVE_PUBLIC_CLAIM_GUARD_PATHS`); justifications-TSV row dropped (two-directional parity), withdrawal recorded as a comment row.
  - `scripts/test-all-affected-c` 517,988 → 646,747 (> CORPUS_SUITE_CAP_MS=600000): exemption row at 794,024 (≤1.3× slack), same #11679 amortization tracker as sibling shard -d.
- Guards re-verified standalone: fast-tier-budget 9/9, corpus-weight-budget 14/14, always-on-ledger 14/14 (floor 114 ≤ 118 ≤ 119), lint-orphan 845/845, probe suite 26/26, watch-brand-hex 174/174, test-all-group-affected 174/174, test-all-affected a/b/c/d 19+92+51+85.
- First battery attempt: full mode (runner-changed), ~700 suites green before crashing at test-all.sh:7244 `ython3` — byte-offset corruption from editing the runner mid-run (self-inflicted, not a defect). Second attempt refused rc=4 (sibling full-gate in feat-one-shot-12666-12583-9340-batch); battery-refusal-wait episode armed per skills/ship/references/battery-refusal-wait.md. Third attempt (stable tree): progressed cleanly to the tail under sustained sibling contention, then the adapter's 2400s budget killed it mid-drain — `AFFECTED_GATE reason=failed-before-budget`, ~30 `[UNACCOUNTED]` suites (dispatched, never measured; coverage unresolved, NOT a verdict).
- Provisional reds from the budget-killed run, resolved by isolated re-run: `apps/web-platform [repo-wide+component]` c4-code-panel F-A1 stale-reload flake (TimeoutNaNWarning under load~21) — isolated bundle GREEN 289/289 files, 3069/3069 tests; `apps/web-platform/test/approval-guard1-mutation` control HALT on decide-boundary 16s walkSources timeout — isolated battery GREEN rc=0, mutants selected=371 killed=365 equivalent=4 gaps=2 unresolved=0, checks 794/794, 2425s. Both confirmed contention flakes, not diff verdicts.
- Fourth battery launched ~03:05Z uncontended (sibling drained, load ~4): FULL mode (runner-changed fallback persists), width=4. Note: adapter `timeout -k 10 2400` is a hard 40-min ceiling; full mode estimates ~64min wall at width=4 — a clean drain may be unreachable under the cap; a budget expiry with zero provisional reds lands rc=6 BUDGET_DEFERRED → CI authoritative (sanctioned).

## Technical-ruling gate
- cto_spawns=1 (batched, 4 rows): all four pending technical rows ruled `Ruled by CTO agent, 2026-11-12` — each confirmed its assumed default (N=2 close threshold; actor.login discriminator; cancelled excluded; per-run leg assertion). No plan/tasks amendment needed (rulings == assumed defaults).
- technical-ruling-gate.sh --branch: PASS (8 rows)
