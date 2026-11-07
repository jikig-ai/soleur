---
title: "workflow: make work Phase 2, review's lead gate and the Grok pre-push gate honour a brief's ci-is-the-gate constraint (Ref #12247, #12251)"
date: 2026-11-07
slug: ci-is-the-gate-token-reaches-work-review-grok-gate
branch: feat-one-shot-12247-ci-is-the-gate-readers
issue: 12247
closes: 12247
type: feat
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-11-07
**Sections enhanced:** Research Insights, Proposed Solution, Technical Considerations, Implementation Phases (1, 3, 4, 5, 6, 7), Guard Contract, Acceptance Criteria, Sharp Edges Applied
**Seats used (all bounded; the CTO seat was not respawned, spawn cap):** plan-review (DHH, Kieran, code-simplicity), sharp-edges catalogue verifier, security-sentinel, test-design-reviewer, architecture-strategist, pattern-recognition-specialist, verify-the-negative grep sweep. The Phase 4.5 network-outage deep-dive was not spawned: the trigger word was a CI `timeout-minutes` ceiling, recorded under `## Hypotheses`.
**Halts run mechanically:** 4.6 user-brand (pass), 4.7 observability (pass after the `expected_output` literal fix), 4.8 PAT sweep (no hits), 4.11 guard contract (`lint-guard-contract.py` green), 4.12 scope check (1 unfenced section, compliant), 4.9/4.10/4.13 and 4.55 not triggered.

### Key Improvements

1. A blocking pin was found before any code: work/SKILL.md names `affected-tests.sh` on one line only, so the planned swap would have reddened `fullsuite-merge-gate.test.ts`; fixed with a fence comment and a scoped pin.
2. The plugin-root anchoring ratchet (work 7 and review 4 `bash scripts/test-all.sh` sites) was missing from the pin list; the downward regeneration is now an expected, bounded edit.
3. Byte budget is paid by extraction (review caveat sentence and work compat paragraph move to the contract reference), never by dropping content.
4. The test design is now feasible against the real helpers: PATH-shim `gh` call log, fake plugin tree for the wrapper, one combined `set -euo pipefail` Grok harness with the skip-flag init inside the sentinels, errexit-safe helpers, sandbox-allocated mutation battery with an instrument control, and four added mutants.
5. Hardening folded in: `"$BASH"` instead of a PATH lookup, reader status captured on its own line, a machine line `AFFECTED_GATE_SKIPPED reason=operator-ci-is-the-gate`, a live-repo row that the resolved reader path answers the flag.

### New Considerations Discovered

- The two lead-gate sentences change command (bare `test-all.sh` to the plugin gate with `.soleur-test-gate.json` budget and content-trigger semantics): recorded as decision row P8 and linked to the contract's rc table.
- Residuals now stated for the ADR amendment: a valid token lets a locally failing commit reach `git push` at three sites (bounded by CI and the merge queue); review-time skipping trusts the branch under review; the Grok skip note is log-only.
- Dissents recorded, not acted on (spawn cap): S1 (Grok log-only visibility) and S2 (refuse the token when the diff edits the gate scripts); see `decision-challenges.md`.

## Overview

The earlier change (#12246) lets a brief's `ci-is-the-gate` constraint reach `soleur:ship` Phase 4 through
`battery-owed.sh`. The same local affected-test run also happens earlier (work Phase 2 exit, review's lead
gate) and later (the Grok pre-push gate at ship Phase 6), and none of those read the token. This plan makes
those three call sites honour it by reusing the one reader and its exit contract, and decides whether the
separate C-quoted-path gap in the reader's condition 3 (#12251) rides along.

## Research Insights

Measured on 2026-11-07 against this worktree (branch base `ea579b39d0`, `origin/main` at `a984074042`). Every figure carries the command that produced it.

### Premise Validation (Phase 0.6)

| Cited premise | Check | Result |
|---|---|---|
| #12247 and #12251 are open targets | `gh issue view <N> --json state,closedByPullRequestsReferences` | Both OPEN, no closing PR. Both carry `deferred-scope-out`, `meta/machinery`, milestone "Post-MVP / Later"; neither carries a `soleur:followthrough` directive, so neither is a follow-through tracker. |
| #12246 merged as `5efbce1bd2` | `git log --oneline -8 -- plugins/soleur/skills/ship/scripts/battery-owed.sh` | Holds. |
| Suite is 221/0 | `grep -n 'print_results' plugins/soleur/test/ship-battery-owed.test.sh` | Floor is `print_results 221` (line 1248). Not executed here (no local battery). |
| Byte ceilings ship 273781, one-shot 51991 | `wc -c` on the four SKILL.md files and `plugins/soleur/test/skill-body-budget.json` | **Stale in part.** Measured sizes: ship 273813, one-shot 51991, work 359177, review 475913. Pinned ceilings (merge-base anchored): ship 273955, one-shot 52000, work 359189, review 475921. Headroom: ship 142 B, one-shot 9 B, work 12 B, review 8 B. The brief's 273781 matches nothing in the repo; this plan uses the measured values. |
| "review's local gate and Grok gate do not read the token" | `grep -n 'ci-is-the-gate\|battery-owed' plugins/soleur/skills/{work,review}/SKILL.md plugins/soleur/scripts/grok-pre-push-gate.sh` | Holds: zero hits. The only token reader is `battery-owed.sh:121`; ship/SKILL.md:411-419 is the only consumer. |
| webplat shard timeout raised 25 to 35 | `gh pr view 12279`, `git log -S'timeout-minutes: 35'` | PR #12279 merged 2026-11-07T05:58:46Z (`86c0bf20e7`). |
| #12030 queue still flaky | `gh run list --workflow ci.yml --event merge_group --limit 8` | Latest 8 merge_group runs all `success`, 40 to 74 min wall. `test-webplat` shards of the latest run took 26.2 and 25.7 min (above the old 25 ceiling, below the tracker's 30 min flip trigger). #12030 is OPEN and stays untouched by this plan; its follow-ups (pin mutation batteries to one shard) are a separate CI change. |

Collision pre-check (`collision-precheck.sh 12247` and `12251`): the only open PR naming them is this branch's own draft PR #12294. Foreign `test-all.sh` processes belong to the worktree `feat-one-shot-12231-star-suites-last`; this plan runs no battery, so there is no contention to manage.

ADR-corpus check of the proposed mechanism: ADR-242 (`## Amendment — 2026-11-06 (#12246)`) already records the token and says work and review do not read it; no ADR rejects a second consumer. ADR-242 is amended again (pointer-style, same file) rather than a new ADR written; see "Architecture Decision (ADR/C4)".

### Property List (Phase 0.6b)

1. P1: a run whose brief declared CI the gate does not pay the local affected gate at work Phase 2 exit, except on the infra surface, in a merge, or on an unmeasurable diff.
2. P2: the same holds at review's lead gate.
3. P3: the same holds for the Grok pre-push gate's affected-tests step.
4. P4: all four consumers (ship included) decide from one reader; no site re-parses the token; only exit 42 skips.
5. P5: a skipped gate is printed and recorded, never reported as "tests passed".
6. P6: `--full`, the fix loop (`soleur:test-fix-loop`) and every other gate that is not named above still run.
7. P7 (#12251): the no-token infra refusal sees C-quoted paths and submodule gitlinks the way the token arm already does.

### Cut List (Phase 0.6b)

| Mechanism | Property | What already covers it / why cut |
|---|---|---|
| Re-parse the token inside work, review and the Grok script | P1-P3 | Forks the reader (the brief forbids it); `battery-owed.sh` already parses, sanitises and refuses. Cut. |
| Token consult inside `affected-tests.sh` mapped to a new rc | P1-P3 | Also reaches `soleur:test-fix-loop` (SKILL.md:43) and ship's OWED arm, which must stay token-blind (P6); widens a 1037-line contract. Cut unless the CTO rules otherwise (F1). |
| Read CI evidence (conditions 1-4) at work/review/Grok time | none new | At those points the head is normally unpushed; CI-evidence skipping is ship's job. Cut pending F2. |
| New test file | P1-P5 | `plugins/soleur/test/ship-battery-owed.test.sh` already owns the fixtures (`build_fixture`, `ss18_write`, `make_stub`) and needs no registry row; extend it. |
| Touch `skill-body-budget.json` | none | Forbidden by the brief; ceilings only move down. |
| Honour the token in `lefthook.yml` bun-test (per commit) | none requested | The brief names three sites; adding a fourth is a scope addition (F5). Recorded as a tracked deferral. |

### Repo facts the plan depends on

- Reader: `plugins/soleur/skills/ship/scripts/battery-owed.sh` (487 lines). Token parse lines 102-125; token arm lines 281-298 (always exits: 42, 0 or 2); non-token CHANGED at line 259; `INFRA_RE` at line 268; consumer in `plugins/soleur/skills/ship/SKILL.md:411-419`.
- Sites to wire: `plugins/soleur/skills/work/SKILL.md:1033-1043` (step 9), `plugins/soleur/skills/review/SKILL.md:191-209` (lead gate), `plugins/soleur/scripts/grok-pre-push-gate.sh:40` and `:208`.
- Pins that constrain the edit (from the repo-research pass): `plugins/soleur/test/fullsuite-merge-gate.test.ts:56` (`affected-tests.sh` token in ship, work, review, test-fix-loop and the Grok script); `plugins/soleur/test/fanout-suite-scope.test.sh:659-685` (a bare affected gate line and `GATE=...affected-tests.sh` stay in the Grok script); `plugins/soleur/test/workflow-fidelity.test.ts:399-425` (sed-extracts `^step() {` and `^run_step() {` from the Grok script); `ship-battery-owed.test.sh` T16 (lines 748-795) and T18p (lines 1228-1243). No test executes the Grok script end to end (run-first check: `grep -rnE '(bash|sh|exec|\./)[^#]*grok-pre-push-gate\.sh' plugins/soleur/test scripts apps/web-platform/test .github` returned only two accept/ratchet TSV rows and no test body on 2026-11-07).
- Registries: adding rows to the EXISTING `ship-battery-owed.test.sh` needs no `suite-durations.tsv` or `suite-shard-legs.tsv` row (both keyed by the test path; the suite already has rows at lines 317 and 319). The `ci-pr-affected-audit.accept.tsv` rows for this suite cite `ship-battery-owed.test.sh:96`, `:465`, `:468`, `:1105` and `:1114`, so new rows go AFTER line 1228 (before the floor) to keep those cites valid, and the floor at line 1248 is bumped by the exact number of new assertions.
- Declared edges already cover `battery-owed.sh`, `operator-constraints.md`, `ship/SKILL.md` and the suite (`scripts/lib/test-affected-paths.sh:1183-1186`); the Grok script is covered by the globs at `:3724` and `:3832`.

### Institutional learnings that apply

- `2026-11-06-a-nine-seat-review-and-a-16-mutant-battery-both-missed-what-a-fresh-verifier-found.md`: ask what each git plumbing call hides by configuration (`--ignore-submodules=none`, symlinked directories, corrupt `MERGE_HEAD`); run one fresh read-only verifier over the final diff.
- `test-failures/2026-10-14-c-quoted-names-evade-extension-anchored-list-filters.md`: git C-quotes `"`, `\` and control bytes regardless of `core.quotePath=false`, which governs only bytes at or above 0x80. For #12251 `-z` is the fix; `core.quotePath=false` alone is a partial fix and is rejected.
- `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md`: budget as `ceiling - wc -c`, extract into `references/` instead of compressing, diff compressed text clause by clause, run `python3 scripts/lint-skill-body-budget.py --base origin/main` before adding prose.
- `workflow-issues/2026-10-20-a-queued-gate-is-not-a-verdict-and-a-name-matcher-cannot-find-a-wrapper-run-process.md`: a deferral is "CI is the gate", never green; print the machine line.
- `2026-10-19-a-fail-closed-gates-tests-asserted-the-safe-verdict-which-two-causes-produce.md`: for a gate whose safe answer is the refusal, assert the CAUSE (reason text), not only the rc; end-anchor pinned command lines.
- `2026-09-20-the-gate-that-caught-it-was-the-one-suite-i-had-no-reason-to-run.md`: nothing may poll `battery-owed.sh`; it is an optimisation to race, never to wait on.
- `2026-07-18-image-baked-and-latent-is-a-claim-verify-a-published-tag-exists.md`: never chain `grok-pre-push-gate.sh && git push`; push in its own call.

### F12 finding (archival)

Phase 6.45 archives `specs/<branch>/` (including `session-state.md`) after the last live reads, and the reader reads only the working-tree path, so the token stops applying at archival. Which local gates still run after that point was measured: ship Phase 6 (Grok gate) precedes 6.45; ship Phase 7 holds no battery except the CI auto-fix path, which invokes `soleur:test-fix-loop` (ship/SKILL.md:2566-2570). Evidence from #12246's own history (`gh pr view 12246 --json commits`): the archive commit (20:43Z) follows the compound learning commit (20:40Z) and two CI-fix commits follow it. A fix loop reacting to a red CI check must run tests; it is correctly token-blind. Conclusion: no gate still needs the token after archival; the existing sentence in `operator-constraints.md` item 5 stays true and is NOT edited; the Grok-after-archival limitation is recorded once, in the ADR-242 amendment.

### Open Code-Review Overlap

None. `gh issue list --label code-review --state open` was matched against every file in `## Files to Edit` and `## Files to Create` with `jq --arg`; zero hits.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured 2026-11-07) | Plan response |
|---|---|---|
| "Byte budgets: ship/SKILL.md 273781, one-shot/SKILL.md 51991" | ship is 273813 B (ceiling 273955), one-shot 51991 B (ceiling 52000); work 359177 B (359189), review 475913 B (475921). | Every SKILL.md edit is planned and acceptance-tested as a byte DELTA against the file's current size; `skill-body-budget.json` is not touched. |
| "Reuse battery-owed.sh and its exit contract; DO NOT fork the reader" | The reader has no argument parsing; exit 42 is the only skip; the token arm always exits (42, 0 or 2) and never falls through to the CI-evidence conditions. | Add one flag (`--token-only`) to the same script; no site re-parses the token. Wrapper and Grok gate branch on exit 42 only. |
| "Work Phase 2 ... do not read the token" (#12247) | Work has TWO affected-gate prescriptions: step 9 (`affected-tests.sh`) and the fan-out lead gate (bare `bash scripts/test-all.sh`). Review has one (the lead gate, also bare `bash scripts/test-all.sh`, with `affected-tests.sh` only as the "plugin-portable" spelling). | All three prescriptions route through the wrapper. The two bare `test-all.sh` prescriptions are rewritten while keeping the spans that `collision-precheck.test.sh` and `fanout-suite-scope.test.sh` pin (decision row P2). |
| "Grok pre-push gate does not read the token" | True, and ship Phase 6 runs this gate at push time even after Phase 4 (so a Phase-4 skip alone still left a ~35 min gate at push). The gate has no test that executes it; pins are textual (`fanout-suite-scope.test.sh`, `fullsuite-merge-gate.test.ts`, `workflow-fidelity.test.ts`). | Inline `--token-only` branch around the existing `run_step "affected-tests gate" bash "$GATE"` line, with the block extractable for a behavioural test. |
| "(F12) Phase 6.45 archives session-state.md, so the token stops applying; check whether any gate still needs it" | Measured: no gate reads it after archival except a Grok push made after archival (archive push, Phase 7 CI-fix push), which runs the full affected gate (stricter). `soleur:test-fix-loop` is rightly token-blind. | No code change; limitation recorded in the writer reference and ADR-242 amendment (ruling F12). |
| "(L1) a section inside an invisible HTML block still reads; accepted" | Header line 101 of `battery-owed.sh` documents it. | Carried unchanged; no work. |
| "#12251: fix is -z or core.quotePath=false" | `core.quotePath=false` fixes only bytes at or above 0x80; tab, `"` and `\` stay C-quoted (learning 2026-10-14). The same `CHANGED=` line also lacks `--ignore-submodules=none`. | Separate PR (ruling F4); this PR carries `Ref #12251` and a handoff recipe (`-z` plus `--ignore-submodules=none`, never `core.quotePath=false` alone). |
| "Re-check #12030 before assuming the queue is still flaky" | OPEN; latest 8 merge_group runs green; webplat shards 26 min vs 35 min ceiling and the 30 min flip trigger. | Out of scope; no CI matrix or timeout edit. |

## Hypotheses

The Phase 1.4 network-outage pattern scan fired on the word "timeout" in the brief. It names a GitHub Actions job ceiling (`timeout-minutes` on `test-webplat`, tracker #12030), not a connectivity symptom, and this change has no SSH, firewall, DNS or TLS surface. L3 firewall, L3 DNS, L7 TLS and L7 service layers are therefore not applicable; no service-layer hypothesis is proposed. Telemetry line `SOLEUR_RULE_APPLIED rule=hr-ssh-diagnosis-verify-firewall` was emitted when the gate fired.

## Problem Statement

A brief that says "rely on CI's required test check" still pays the local affected gate at four moments of a one-shot run: work Phase 2 (step 9 and, when agents fan out, the lead's consolidation gate), review's lead gate after the panel, and the Grok pre-push gate at ship Phase 6. Only ship Phase 4 reads the operator's `ci-is-the-gate` token. Measured cost of one cold affected gate: 2134 s (ADR-242, 2026-11-04 amendment), so a token run can spend roughly half an hour per site before ship ever sees the token.

## Proposed Solution

Four small pieces, all reusing the existing reader and its exit contract (42 skips; 0 and 2 and everything else run the gate).

1. **Reader flag.** `battery-owed.sh --token-only`: no valid token returns OWED (exit 0) immediately, with no `gh`, `jq` or `timeout` dependency and no CI-evidence condition; a valid token runs the existing token arm unchanged (infra surface, merge in progress, unmeasurable diff and unresolvable `origin/main` still refuse); any other argument, or a second argument, is UNDECIDABLE (exit 2). Ship Phase 4 still calls the script bare, so its behaviour does not change.
2. **Wrapper.** New `plugins/soleur/scripts/gate-or-skip.sh` (15 characters; shorter than `affected-tests.sh`, so each swap costs 0 or fewer bytes). On a bare invocation it runs `battery-owed.sh --token-only` resolved beside itself (never through `CLAUDE_PLUGIN_ROOT`); the reader's output (verdict line or refusal reason) is always printed; exit 42 additionally prints `affected gate: SKIPPED (NOT run, NOT passed); CI test is the gate` plus the machine line `AFFECTED_GATE_SKIPPED reason=operator-ci-is-the-gate` (the `AFFECTED_GATE` convention of the contract) and exits 0; anything else, and any invocation WITH arguments (`--full`, `--explain`, `--base`), `exec`s `affected-tests.sh "$@"` and returns its rc. Used by work step 9, work's fan-out lead gate and review's lead gate. Not used by `soleur:ship` (calls the reader directly), `soleur:test-fix-loop` (a fix loop must run tests) or `lefthook.yml` (deferred, #12297).
3. **Grok gate inline.** `grok-pre-push-gate.sh` makes the same `--token-only` call around its existing `run_step "affected-tests gate" bash "$GATE"` line; only that step is waived (fast CI jobs, web-platform-build and grok-fidelity still run); on a skip it prints a `[note]` line, sets a flag and ends with a distinct banner (`PASS WITH SKIPPED GATE ...`, never "PASS — safe to git push"), exit 0.
4. **Docs and pins.** The contract reference gains a short wrapper section (the "SKIPPED is not passed" rule, consumers and non-consumers) and receives two pieces of prose moved verbatim out of the byte-capped SKILL.md files (work's compat-spelling paragraph, review's `SOLEUR_SUBAGENT=1` caveat); the writer reference's "work and review do not read it" sentence is corrected; ADR-242 gets a short dated amendment; tests pin the reader flag, the wrapper, the Grok block and each call site.

### Technical Considerations

- **Byte accounting (measured by applying the planned text in memory today).** review: lead-gate sentence +18 B, then MOVE (not delete) the unpinned 170 B tail sentence ("The `SOLEUR_SUBAGENT=1` exit-4 path is a deliberate-export convention ... not claim.") verbatim into the contract reference = -152 B net (headroom 8 B). work: step-9 swap -2 B, fan-out sentence -30 B, plus one short clause that keeps the literal `affected-tests.sh` in the file (about 60 B; see the next bullet), then MOVE the 430 B compat-spelling paragraph (step 9) to the contract reference = about -402 B net. The CTO's flip condition (go to per-site inline branches if review cannot point at the wrapper without a net byte increase) did not fire: review nets negative by extraction, not by dropping content.
- **The work step-9 clause is load-bearing, not decoration (plan-review finding).** `plugins/soleur/skills/work/SKILL.md` names `affected-tests.sh` on exactly ONE line (the step-9 fence, measured by `grep -c`), and `plugins/soleur/test/fullsuite-merge-gate.test.ts` (DISPATCH test) requires that literal in work, review, ship, test-fix-loop and the Grok script. Swapping the fence to `gate-or-skip.sh` with no other mention turns that test red. The clause (for example a fence comment line "wraps affected-tests.sh; skips only on a brief's ci-is-the-gate token") keeps the literal; review already carries it twice.
- **Pins that must keep holding** (each re-run file-selected at work time): `collision-precheck.test.sh` span (review/work lead gate keeps `bash scripts/test-all.sh --print-selection`, no `TEST_GROUP=affected`, and the "Two backstops" / "Two mechanical backstops" anchors); `fanout-suite-scope.test.sh` (`TEST_GROUP=affected bash scripts/test-all.sh` stays in work and review; a bare gate line and `GATE=...affected-tests.sh` stay in the Grok script); `fullsuite-merge-gate.test.ts` (`affected-tests.sh` literal stays in ship, work, review, test-fix-loop and the Grok script - other prose in work and review already carries it; verify by grep after the edit); `workflow-fidelity.test.ts` (the Grok script keeps `^step() {` and `^run_step() {` and the `scripts/test-all.sh`, `grok-fidelity-gate.sh`, `readme-counts` strings); `ship-battery-owed.test.sh` T16 (ship dispatch unchanged) and T18p (the writer reference's fenced example is not edited); and the plugin-root anchoring ratchet (`apps/web-platform/test/plugin-root-anchoring.test.ts` over `apps/web-platform/test/fixtures/plugin-root-skills-ratchet.tsv`), which pins `bash scripts/test-all.sh` at 7 occurrences in work and 4 in review (measured with `grep -c`): the rewritten sentences must hold those counts, or - if sites are genuinely deleted - the two rows are regenerated DOWNWARD only, per the fixture header, never upward and never as a way to admit a new CWD-relative anchor.
- **Trust.** The wrapper and Grok block add no parser. The token stays a hint the same commit can write; what bounds it is unchanged (live ruleset, merge queue, the arm's infra refusal, the printed words). The skip is visible at every site and exits 0 by ruling, so the printed `SKIPPED (NOT run, NOT passed)` line is the only distinction from a pass: the contract reference says so, and ship Phase 4 still records the PR-Test-plan sentence.
- **The two lead-gate sentences change command, not only wiring (deepen-pass finding).** Work's fan-out lead gate and review's lead gate currently prescribe the bare `bash scripts/test-all.sh`; routing them through the wrapper makes them the SAME gate as work step 9 and ship Phase 4 (`affected-tests.sh`), which in this repo adds `.soleur-test-gate.json` semantics (`budget_seconds` 2400 and the `content_trigger_*` keys, measured 2026-11-07) and the gate's rc mapping (runner rc 3 and 4 map to 1 and 4; rc 6 is pass-with-note; rc 7 is a disclosed gap). Both sentences already named `affected-tests.sh` as the "plugin-portable" spelling of the lead's run, and the delegated run is the same `test-all.sh --affected`, but the behavioural delta is real: each rewritten sentence therefore links the contract's rc table (`affected-gate-contract.md`) and says rc 6 and 7 are never reported as passed. Recorded as decision row P8 (planner's call, flagged for the PR body); the CTO's F1 already chose to route work and review through the wrapper.
- **Match anchors for the SKILL.md rewrites** (measured 2026-11-07; match by content, not line number): work fan-out starts "The lead runs the gate ONCE, after collecting fan-out work — the bounded default `bash scripts/test-all.sh` (bare" and ends before "Two mechanical backstops exist"; work step-9 fence is the single line `bash "${CLAUDE_PLUGIN_ROOT}/scripts/affected-tests.sh"` under "Affected-Test Exit Gate"; the compat paragraph starts "A deprecated compat spelling also exists (#8621)" and ends "not the ship gate."; review's lead sentence starts "The lead runs the gate ONCE after the panel returns — the bounded default `bash scripts/test-all.sh` (bare resolves `--affected`;" and ends at "(#10333). Two backstops:"; the review tail sentence starts "`SOLEUR_SUBAGENT=1` exit-4 path is a deliberate-export convention" and its line break splits the opening backtick token, so a verbatim move must handle the newline.
- **Dogfood limit.** The parent writes this branch's `session-state.md` token before `soleur:work` (the file does not exist at plan time: the spec directory holds only `decision-challenges.md` and `tasks.md`), but this PR's work run executes before the wrapper exists, so it cannot benefit, and after Phase 6.45 archival the live-branch smoke can no longer read it. The brief's standing constraint (file-selected suites only, no affected battery to completion) covers it. The smoke check is `bash plugins/soleur/skills/ship/scripts/battery-owed.sh --token-only; echo rc=$?` - never the wrapper itself, because a missing token would make the wrapper run the whole gate. The live-branch smoke is conditional on the file existing; the deterministic proof is the T19 fixture rows.
- **Known limitation (F12 ruling).** After Phase 6.45 archival no gate sees the token. A Grok push made after archival runs the affected gate in full (stricter). Not extended to `specs/archive/`: that would read an older run of the same branch name and widen the trust surface.
- **Accept rows.** The suite's existing accept rows cite `ship-battery-owed.test.sh` lines 96, 465, 468, 1105 and 1114; every new test row is appended after the T18p block (before the `print_results` floor) and no helper above line 1228 is edited, so those cites stay valid. If the replay ratchet asks for new rows, key them by 12-hex anchor and cite the final file:line after the last insertion.

## Implementation Phases

Order is tests first (`cq-write-failing-tests-before`); the matrix in `## Guard Contract` was written before the code.

### Phase 1 - RED: T19 rows (append to `plugins/soleur/test/ship-battery-owed.test.sh`)

1.1. Add `run_gate_tok` / `ctl19` helpers AFTER the last T18p assertion and before the `# The floor counts` comment (do not edit `run_gate` or any helper above the T18p block: the accept-row cites sit above it). Every new helper ends in `printf` plus `return 0` (or `|| true`), as `run_gate` and `run_gate_out` do: `test-helpers.sh` sets errexit, so the first non-zero wrapper or reader status would otherwise kill the suite silently. Reuse fixtures with the `ctl18` branch-rename trick instead of a new `build_fixture` per row (each costs a git init, clone and push).
1.2. Reader rows (real fixtures: `build_fixture`, `ss18_write`, `make_stub`; the gh stub also logs its argv to `$DIR/calls.log` through a NEW stub-writer helper in the T19 block - the existing `make_stub` is not edited). The shared token arm is already pinned by T18, so these rows pin only what the flag adds:

- T19a no token + CI-evidence-skippable fixture (T1 shape): bare run is SKIPPABLE (control), `--token-only` run is OWED, reason `no operator ci-is-the-gate token`, and the gh stub's call log is empty (no CI state read); the BARE control on the same fixture asserts the call log is NON-empty, so an empty log cannot be a shim that never fired. The call log comes from a PATH-shim `gh` that appends argv and then `exec`s the stub's `gh` (no edit to `make_stub`).
- T19b token + `--token-only` + the T18d incident shape (dirty, behind main, no CI evidence): SKIPPABLE with the same verdict text as the bare run; and a second row on a GREEN-CI fixture asserting the reason text is the operator-token verdict (not the CI verdict), which is what catches a token arm that falls through to condition 4.
- T19c token + `--token-only` + infra path: OWED with the infra reason (the one refusal worth re-pinning through the new entry; merge-in-progress and unresolvable-`origin/main` are T18 rows and are not repeated).
- T19d `--bogus` with a token present: UNDECIDABLE and reason `unknown argument` (a bare run on the same fixture is SKIPPABLE, so a parser that ignores the argument is caught); `--token-only extra` and an empty-string argument: UNDECIDABLE with the same reason (second-member rows), and a lone `--token-only` on the same fixture returns 42 as the control.
- Must-PASS non-canonical inputs (token as the second of three bullets, nested branch name) are already pinned through the shared parse by the T18x rows; T19 does not repeat them.

1.3. Wrapper rows against a FAKE plugin tree built in a fixture root (`plugins/soleur/scripts/gate-or-skip.sh` copied from the repo; stub `skills/ship/scripts/battery-owed.sh` and stub `plugins/soleur/scripts/affected-tests.sh` that log argv and return a configured rc; no git fixture needed):

- reader rc 42: exit 0, stdout holds the reader's verdict line and `SKIPPED (NOT run, NOT passed)`, the gate stub was NOT invoked, the reader stub saw exactly `--token-only`.
- reader rc 0, 2, 137 and a missing reader: the gate stub IS invoked once with no arguments (one non-42 code kills the `-eq 42` to `-ne 0` mutant; the missing-reader row exercises only the `-r` guard, whose removal is behaviourally equivalent because bash returns 127, so it is NOT counted as a mutant kill).
- gate rc passes through unchanged (rows for 0 and 6; `exec` makes the rest structural).
- `--full` and `--explain`: the reader stub (configured to return 42) is NOT invoked and the gate stub receives the arguments verbatim - with rc 42 configured, both "reader not consulted" and "gate ran" can kill the consult-with-arguments mutant. An empty-string argument also bypasses the token.
- `CLAUDE_PLUGIN_ROOT` pointing at a decoy tree whose reader returns 42: no skip (siblings resolve from the wrapper's own directory; env-directed roots are a trust class, ADR-179).
- flag parity: extract the flag string from the wrapper source AND from the Grok block, assert each is NON-EMPTY (a reworded wrapper must not pass vacuously), and run the REAL `battery-owed.sh` with each inside a `build_fixture` work tree that has no token: the reason must be `no operator ci-is-the-gate token`, with a `--bogus` control in the same directory returning `unknown argument` - this discriminates only if argument parsing precedes the `git rev-parse --is-inside-work-tree` check, so a parse placed after it cannot pass (a bare 'not inside a work tree' expectation would stay green for a misplaced parse).
- a reader stub that PRINTS `SKIPPABLE`-shaped text but exits 1 (and one that exits 2 after printing a verdict): the gate runs - the wrapper asserts on the exit code, never on stdout.
- live-repo row: the reader path the wrapper resolves (its own sibling `../skills/ship/scripts/battery-owed.sh`) exists, is readable and answers `--token-only --bogus` with `UNDECIDABLE` - so renaming or moving the reader cannot silently disable the feature through the `-r` fall-through; the same row resolves the path the Grok script builds.
- a plain git repo with no `knowledge-base/` and no `origin/main`: `--token-only` returns OWED (exit 0), not UNDECIDABLE noise, because the short-circuit precedes the `origin/main` check (the plugin ships to repositories with neither).
- the reader's output is printed on every path (an infra refusal's reason explains why the token was ignored); the plan accepts the one extra line on the no-token path.

1.4. Grok rows. Two sentinel pairs, each commented `(sliced by ship-battery-owed.test.sh T19)` so a later editor does not delete them as dead comments (house form: `# name:start` / `# name:end`, as in `roadmap-reconcile.test.sh`), are extracted with exact-line `awk` (`/^# grok-token-dispatch:start$/{f=1;next} /^# grok-token-dispatch:end$/{f=0} f`, never a range) (`grok-token-dispatch` around the Phase 2 branch, `grok-token-banner` around the final banner branch; each extraction has a non-empty floor) and executed in a harness with stub `run_step`, stub reader and stub `GATE`: reader rc 42 means `run_step` is not called and the skip flag is set; reader rc 0 or 2 means `run_step "affected-tests gate"` is called once; the banner branch prints `PASS WITH SKIPPED GATE` only when skipped and the `PASS — safe to git push` echo sits only in the not-skipped branch (this also pins the banner against edits outside the dispatch block); the real file still contains the bare gate line and `GATE=...affected-tests.sh`; and the count of non-comment `battery-owed.sh` / `--token-only` invocations in the Grok script is exactly 1 (a second, unextracted consumer branch would otherwise go unseen).

Grok harness shape (test-design finding, blocking): the skip-flag initialisation lives INSIDE the dispatch sentinels, and the two extractions are concatenated and run in ONE `set -euo pipefail` shell with a stub `run_step` that records its calls and a trailing stub standing in for the remaining steps, asserting exit 0 and the banner - so deleting the init, or renaming the flag in only one block, aborts a non-skip push under `set -u` and reds the suite. The stub reader logs its argv and fails unless the argument is exactly `--token-only`, and the REAL reader is also run with the Grok-extracted flag string (flag parity above). The invocation count is defined as comment-stripped lines matching the `"$BATTERY_OWED"` call (the `BATTERY_OWED=` assignment line also contains `battery-owed.sh` and must not count), expected exactly 1, with `--token-only` lines counted separately (also 1).
1.5. Call-site pin rows (text extraction, each with a non-empty-extraction floor): work step 9's fenced block, with `#` comment lines stripped, has a command line invoking `${CLAUDE_PLUGIN_ROOT}/scripts/gate-or-skip.sh` and NO non-comment `affected-tests.sh` invocation (the comment line keeps the literal for the fullsuite DISPATCH pin, which stays the owner of that literal - this suite does not duplicate it); work's fan-out lead sentence and review's lead sentence carry the `${CLAUDE_PLUGIN_ROOT}/scripts/gate-or-skip.sh` command form (not the bare basename); the ship dispatch stays owned by T16; NEGATIVE (ruling F1): `test-fix-loop/SKILL.md` and `lefthook.yml` - and the executables that actually run the gate (`plugins/soleur/scripts/affected-tests.sh`, `plugins/soleur/scripts/lib/affected-tests/*`, `plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh`, `scripts/test-all.sh`) - are asserted READABLE and non-empty first, then `grep -c` of `gate-or-skip` and of `--token-only` is 0 in each, together with `battery-owed`, `session-state` and `ci-is-the-gate` for the executables (a negated `grep` alone passes on rc 2 for a missing or renamed file); fence and span extraction is flag-based (`awk` with an explicit open flag and a non-empty floor), never a `/A/,/B/` range, and the work step-9 pin is scoped to the fence so the basename living elsewhere in the span cannot satisfy it; `operator-constraints.md` item 4 carries two distinct anchors (`--token-only` and `gate-or-skip.sh`), not a bare token. Every extraction-floor row emits exactly one assertion on every path, so the assertion count is path-stable.
1.6. Do NOT bump the floor yet; run the suite once to confirm the new rows are RED for the right reason (reader flag unknown, wrapper missing, prose not yet edited).

### Phase 2 - GREEN: reader flag (`plugins/soleur/skills/ship/scripts/battery-owed.sh`)

2.1. After the `owed`/`skippable`/`undecidable` helpers and before the `git` checks, parse arguments: no argument, or exactly `--token-only`; anything else (one unknown flag, or a second argument of any kind) calls `undecidable "unknown argument ..."` without echoing the argument.
2.2. Immediately after `OPERATOR_CI_WORDS` is computed and before condition 1: `--token-only` with no token calls `owed` with the reason `--token-only: no operator ci-is-the-gate token (CI state is not consulted at this site)`.
2.3. Header: replace "Work Phase 2 and review do not read it (#12247)" with the consumer list; add the `--token-only` line to the exit-contract block. Leave the `CHANGED="$(git diff --name-status -M` line (anchor, not a line number: it shifts after 2.1-2.2) and the "#12251" sentence in the token-arm comment untouched (separate PR).

### Phase 3 - GREEN: wrapper (`plugins/soleur/scripts/gate-or-skip.sh`, mode 0755)

3.1. As specified in Proposed Solution item 2, `set -uo pipefail` (no `-e`, like `collision-precheck.sh`), siblings resolved from `${BASH_SOURCE[0]}` with `$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)` (precedent: `plugins/soleur/scripts/collision-precheck.sh`, the same `cd -P ... && pwd -P` form; the `2>/dev/null` plus the readable-reader guard keep a failed `cd` from resolving to `/battery-owed.sh`), the reader status captured as `"$BASH" "$OWED" --token-only; rc=$?` on its own line (never inside `if`, never piped, never `local rc=$(...)`, so a lost or odd status can only run the gate), token consulted only when `$#` is 0, `[[ -r "$OWED" ]]` guard so a missing reader falls to the gate, `exec "$BASH" "$GATE" "$@"` (and `"$BASH" "$OWED" --token-only` for the reader: no `PATH` lookup of `bash`, plan-review hardening) as the last line.
3.2. Header comment: exit mapping, why only 42 skips, why any argument bypasses (a preview or `--full` must reach the gate), why test-fix-loop and ship do not use it, ADR-179 sibling-path note.

### Phase 4 - GREEN: Grok gate (`plugins/soleur/scripts/grok-pre-push-gate.sh`)

4.1. Resolve `BATTERY_OWED` beside the script (`../skills/ship/scripts/battery-owed.sh`), next to the existing `GATE=` line; keep `GATE=` exactly.
4.2. Wrap the Phase 2 step between `# grok-token-dispatch:start` and `# grok-token-dispatch:end` sentinels as in Proposed Solution item 3; initialise the skip flag to 0 INSIDE the dispatch sentinels; `|| rc=$?` so `set -e` cannot abort; branch on 42 only.
4.3. Replace the final banner with a two-way branch wrapped in a second sentinel pair (`# grok-token-banner:start` / `:end`). Before editing, `grep -rn "safe to git push" plugins scripts .claude knowledge-base/engineering` to confirm nothing parses the banner string (ruling F3 asked for this check; measured 2026-11-07 outside `knowledge-base/project`: the only hit is the script's own banner line, so no consumer exists today - re-run it, the tree may have moved); update any consumer found.
4.4. Update the header comment (Phase 2 line) to say the step is waived only by exit 42 of `battery-owed.sh --token-only`.

### Phase 5 - SKILL.md call sites (byte-measured)

5.1. `plugins/soleur/skills/work/SKILL.md`: swap the step-9 fenced command to `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate-or-skip.sh"` and keep the literal `affected-tests.sh` in a short fence comment (the DISPATCH pin needs it); rewrite the fan-out lead sentence to name step 9's wrapper while keeping the "Two mechanical backstops" anchor and the `bash scripts/test-all.sh --print-selection` preview; move the compat-spelling paragraph (anchor: "A deprecated compat spelling also exists (#8621)") verbatim into `affected-gate-contract.md`; add no other prose.
5.2. `plugins/soleur/skills/review/SKILL.md`: rewrite the lead-gate sentence per Technical Considerations (state in one clause that `affected-tests.sh` delegates `--affected` to `scripts/test-all.sh` in this repo, so the lead's run is the same run as the bare `bash scripts/test-all.sh` it replaces); move the unpinned tail sentence verbatim to `affected-gate-contract.md`; keep the "Two backstops" anchor.
5.3. After each file: `wc -c` against the size recorded in Research Insights and `python3 scripts/lint-skill-body-budget.py --base origin/main`; the AC is net delta at or below 0 for work and review, and ship and one-shot byte-identical.
5.4. Components are written canonically (`soleur:ship`, `soleur:test-fix-loop`) in everything added.

### Phase 6 - Docs, ADR, edges

6.1. `plugins/soleur/skills/ship/references/affected-gate-contract.md`: add a short `## Token-aware front door (gate-or-skip.sh)` (about 10 lines, plus a row in the exit table for the skip and an update of the intro line "wired from ship Phase 4, work Phase 2 exit, review ..." to say work and review call the wrapper; also records that `one-shot/SKILL.md` still describes the Grok gate as running the gate unconditionally and is byte-frozen by its 9 B headroom; bare-only token, consumers and non-consumers, the "SKIPPED is not passed" rule; the exit mapping lives in the script header) and the two relocated paragraphs (compat spelling; `SOLEUR_SUBAGENT=1` caveat).
6.2. `plugins/soleur/skills/one-shot/references/operator-constraints.md`: item 4 only (readers: ship Phase 4 bare; `--token-only` readers named). Item 5 is untouched: the Grok-after-archival limitation is recorded once, in the ADR amendment. The fenced example stays byte-identical (T18p).
6.3. `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`: a pointer entry at the TOP of the frontmatter `amended_by:` list (newest first; form `"#12247 (2026-11-07) — <one clause>; see ## Amendment — 2026-11-07 (#12247)"`) and `## Amendment — 2026-11-07 (#12247)` appended at the end of the file after the last subsection; it opens with "supersedes the closing sentence of the 2026-11-06 amendment" (history is superseded by pointer, never rewritten), updates the skip-channel count of that amendment (four becomes six: ship Phase 4, work step 9, work fan-out, review lead, Grok gate, plus the existing CI-evidence path), and states the residuals - with a valid token a commit that fails the local suites can reach `git push` with no local test run at three sites, bounded by the required `test` check and the merge queue; review-time skipping trusts the branch under review; the Grok skip note is log-only (ship deletes the log on green) and Phase 4 already printed the verdict for the same token (and when `--full` outranked the token at Phase 4, the Grok step waiving the affected gate is coherent because the full battery already ran); the declaration is the operator's assertion that a CI test gate exists. The ADR-183 pointer paragraph gets a one-line "also applies at work, review and Grok gate; see 2026-11-07" pointer. Format precedent: the 2026-11-06 amendment kept to 10-15 lines (consumers, `--token-only`, wrapper, Grok inline, non-consumers and why, the F12 limitation, rejected alternatives A and C, #12297); the rulings file is archived at Phase 6.45, so the amendment must carry them.
6.4. `scripts/lib/test-affected-paths.sh`: add the new reads to `AFFECTED_PLUGINS_SOLEUR_TEST_SHIP_BATTERY_OWED_TEST_SH_PATHS` (wrapper, Grok script, work and review SKILL.md, test-fix-loop SKILL.md, `lefthook.yml`; the contract reference is not read by any new row, so it gets no edge), then confirm with `bash scripts/test-all.sh --print-selection` (read-only preview) that an edit to the wrapper selects this suite.

### Phase 7 - Verification (file-selected only, no affected battery)

7.1. Floor: run the suite once and take the total from the suite's own PASS counter (the self-test's deliberate FAIL is already subtracted by the file), then set `print_results` to that exact number in the same commit - never a hand tally.
7.2. Mutation battery per `## Guard Contract`, run in a sandbox allocated by `scripts/soleur-sandbox.sh` holding copies of `plugins/soleur`, `scripts/lib` and `lefthook.yml` (the suite hardcodes `GATE="$HERE/../skills/..."` and the reader sources `../../../scripts/lib`, so an in-place mutation of the live tree is wrong), each mutation scoped to its own line range (the reader has two `skippable` sites; the Grok script has many `run_step` lines), an instrument control (a pristine run exits 0; only rc 1 counts as caught, a crash is rejected), the mutation-landed check (file differs and `bash -n` passes), a lead-unique scratch name such as `lead-12247-mut.py` and no shared scratch file; at most two targeted fix rounds plus one verification pass.
7.3. One fresh read-only verifier over the final diff with the question "what does each git call and each `exec` hide?" (learning 2026-11-06).
7.4. Lints and pins: `bash plugins/soleur/test/ship-battery-owed.test.sh`, `bash plugins/soleur/test/collision-precheck.test.sh`, `bash plugins/soleur/test/fanout-suite-scope.test.sh`, `bun test plugins/soleur/test/fullsuite-merge-gate.test.ts plugins/soleur/test/workflow-fidelity.test.ts`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `python3 scripts/lint-skill-body-budget.py --base origin/main`, `python3 scripts/lint-guard-contract.py <this plan>`, `cd apps/web-platform && npx vitest run test/plugin-root-anchoring.test.ts` (file-selected), plus the suites that enumerate `plugins/soleur/scripts/*` (`plugins/soleur/test/invocation-axis.test.ts`, `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`, `plugins/soleur/test/components.test.ts`), `shellcheck` on the three scripts, markdownlint on the changed `.md` files.
7.5. Smoke on this branch, only if `knowledge-base/project/specs/<branch>/session-state.md` exists at that moment: `bash plugins/soleur/skills/ship/scripts/battery-owed.sh --token-only; echo rc=$?` (with the parent-written token expect 42 and the verdict line; accept any printed reason otherwise and paste the ACTUAL line into the PR Test plan rather than asserting 42).

## Files to Edit

- `plugins/soleur/skills/ship/scripts/battery-owed.sh` (flag, no-token short-circuit, header; no fall-through guard)
- `plugins/soleur/scripts/grok-pre-push-gate.sh` (inline token branch, banner, header)
- `plugins/soleur/skills/work/SKILL.md` (step 9 command, fan-out sentence, move compat paragraph)
- `plugins/soleur/skills/review/SKILL.md` (lead-gate sentence; MOVE the tail sentence to the contract reference)
- `plugins/soleur/skills/ship/references/affected-gate-contract.md` (short wrapper section, two relocated paragraphs)
- `plugins/soleur/skills/one-shot/references/operator-constraints.md` (item 4 only)
- `plugins/soleur/test/ship-battery-owed.test.sh` (T19 rows after T18p, floor)
- `scripts/lib/test-affected-paths.sh` (declared edges for the new reads)
- `apps/web-platform/test/fixtures/plugin-root-skills-ratchet.tsv` (EXPECTED: the work fan-out rewrite and the moved compat paragraph delete `bash scripts/test-all.sh` sites in work (7 now, about 5 after) and the review lead rewrite deletes one in review (4 now, 3 after); measure with `grep -c` after the edit and regenerate only those two rows, downward regeneration of those two rows)
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` (amendment)

## Files to Create

- `plugins/soleur/scripts/gate-or-skip.sh` (mode 0755)
- `knowledge-base/project/specs/feat-one-shot-12247-ci-is-the-gate-readers/decision-challenges.md` and `tasks.md` (plan artifacts)

Not edited, deliberately: `plugins/soleur/skills/ship/SKILL.md` and `plugins/soleur/skills/one-shot/SKILL.md` (byte-identical), `plugins/soleur/test/skill-body-budget.json`, `plugins/soleur/skills/test-fix-loop/SKILL.md`, `lefthook.yml`, `apps/web-platform/test/claude-pin-lockstep.test.ts`, the stale accept row for `real-sdk-ask-probe-workflow.test.sh`, `.github/workflows/*`, the ruleset.

## User-Brand Impact

- **If this lands broken, the user experiences:** a pipeline run whose brief said "rely on CI" either still waits on the local affected gate (the flag or wrapper is wrong and falls through to the gate - the safe direction) or, in the wrong direction, finishes work or review without a local gate run while CI's required `test` check still gates the merge; the PR Test plan sentence says the local gate was not executed.
- **If this leaks, the user's workflow is exposed via:** a planted or wrong `ci-is-the-gate` line in `specs/<branch>/session-state.md` waiving a local run at three more sites; bounded by the unchanged infra, merge-in-progress and unmeasurable-diff refusals, the live ruleset and merge queue, and the verdict line printing the operator's words. No user data, credential or money path is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal plugin tooling that only decides whether an optional local run happens; every merge stays gated by CI's required checks and the merge queue, so a wrong skip costs time, not a user-visible incident. The diff touches no sensitive path (no `apps/` auth, API, migration or `.sql` file), so no scope-out line is required.

## Observability

```yaml
liveness_signal:
  what: the verdict line "battery-owed: SKIPPABLE|OWED|UNDECIDABLE ..." printed by battery-owed.sh and, for the wrapper, "affected gate: SKIPPED (NOT run, NOT passed); CI test is the gate"; the Grok gate prints "[note] affected-tests gate SKIPPED" and a "PASS WITH SKIPPED GATE" banner
  cadence: per gate invocation (work Phase 2 exit, review lead gate, Grok pre-push gate)
  alert_target: the session transcript and the PR Test plan sentence recorded by ship Phase 4 (observability layer 7, cli-stdout-artifact; no Soleur-side sink by design)
  configured_in: plugins/soleur/skills/ship/scripts/battery-owed.sh (say), plugins/soleur/scripts/gate-or-skip.sh, plugins/soleur/scripts/grok-pre-push-gate.sh

error_reporting:
  destination: stdout and stderr of the script in the caller's session (layer 7); the exit code is the machine signal
  fail_loud: an unknown argument prints "UNDECIDABLE — unknown argument" and exits 2, which every caller treats as "run the gate"; a reader that cannot run exits non-zero and the gate runs

failure_modes:
  - mode: a typo or older reader ignores or rejects the flag
    detection: unknown argument exits 2 and the wrapper falls through to affected-tests.sh (layer 7, visible in the transcript); the flag-parity row runs the real reader with the wrapper's flag string
    alert_route: the caller's transcript; ship-battery-owed.test.sh T19 reds in CI
  - mode: a skip is reported as a pass
    detection: the SKIPPED line is printed on every skip path and the Grok banner never contains "safe to git push" when skipped; pinned by T19 rows
    alert_route: PR Test plan sentence and the review seat reading it
  - mode: the wrapper or Grok block skips on a non-42 status
    detection: reader rc 0, 2, 137 and missing-reader rows assert the gate runs; Guard 2 mutation rows 1 and 5
    alert_route: CI test check on the PR

logs:
  where: the caller's tool-result stdout (layer 7); no persisted log
  retention: session transcript and the PR body

discoverability_test:
  command: bash plugins/soleur/skills/ship/scripts/battery-owed.sh --token-only --bogus
  expected_output: UNDECIDABLE
```

## Guard Contract

Matrix written before the code (Phase 1 derives its rows from it).

### Guard 1 — token-only reader: 42 only through the token arm

**Property.** Under `--token-only`, exit 42 is reachable only through the existing token arm; with no valid token the verdict is OWED without reading any CI state, and an unknown or extra argument is UNDECIDABLE.

**Assembly.** The argument parse (top of `battery-owed.sh`), the no-token short-circuit (after `OPERATOR_CI_WORDS`, before condition 1), the token arm (always exits), and the single other `skippable` call site at the bottom of the file (CI evidence). The chokepoint is "every `skippable` call is reached only from the arm or from the bottom after condition 4"; there are exactly two such sites, and under the flag the second is unreachable only because the arm always exits (no extra guard is added: plan-review cut it as YAGNI, and mutation 5 keeps the property pinned by the reason-text assertion on a green-CI fixture). The wrapper's flag string and the Grok block's flag string must equal the parser's accepted string (flag-parity row).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the no-token short-circuit (CI-evidence-skippable fixture, no token) | RED (T19a: `--token-only` must be OWED where the bare run is SKIPPABLE) |
| 2 | Move a `gh` call above the short-circuit | RED (call log must be empty) |
| 3 | Parse only `$1` (drop the `$#` test) so `--token-only extra` passes | RED (second-member row) |
| 4 | Make the parser ignore unknown arguments (`--bogus` with a token present) | RED (UNDECIDABLE expected, SKIPPABLE observed) |
| 5 | Let the token arm fall through (remove its final `skippable`) on a green-CI fixture | RED (shared-arm mutant already killed by the existing T18 rows; T19b's green-CI row adds the flag-path variant) |
| 6 | Short-circuit to `exit 42` when a token exists, before the infra check | RED (shared-arm mutant already killed by the existing T18 infra rows; T19c re-pins it through the flag) |

**Harness rows.** (a) Suite edit that must go RED: make `run_gate_tok` drop the `--token-only` argument; T19a then sees the bare verdict and reds. (b) Must-PASS inputs that are not the canonical fixture: the token as the second of three bullets with comma and period words (permitted by the reader's alphabet), and a nested branch name (`feat/x/y` reads `specs/feat/x/y/session-state.md`). (c) Control: the T19a and T19d fixtures also run bare and assert the verdict they should have, so the suite cannot go green on a runner that ignores the fixture.

**Anchor.** The flag-parity row compares a stored string (the wrapper's flag) to the thing it protects (the reader's parser) by running the real reader with it; what lives outside this commit is `ship/SKILL.md`'s bare call (unchanged, T16) and the CI test check.

### Guard 2 — consumers skip only on 42 and only on a bare invocation

**Property.** Every consumer of the flag (wrapper, Grok block) runs the affected gate for every reader status other than 42, and the wrapper consults the reader only on an invocation with no arguments.

**Assembly.** The wrapper's single branch; the Grok block's single branch (plus its banner branch); the call sites that must route through the wrapper (work step 9, work fan-out sentence, review lead sentence); the call sites that must NOT (ship Phase 4, `test-fix-loop/SKILL.md`, `lefthook.yml`, spawned review agents). The chokepoint is the one `[ "$rc" -eq 42 ]` per consumer; there are two consumers and the suite must find both (a non-empty floor on each awk extraction, so "0 checked" cannot pass).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Wrapper: change `-eq 42` to `-ne 0` | RED (reader rc 2, 137 and missing-reader rows must run the gate) |
| 2 | Wrapper: consult the reader even when arguments are present | RED (`--full` and `--explain` rows) |
| 3 | Wrapper: skip but exit 1 (or print no SKIPPED line) | RED (exit 0 and the printed line are asserted) |
| 4 | Grok block: move the token branch AFTER `run_step "affected-tests gate"` | RED (the stub gate must record zero invocations when the reader says 42 - observed inside the window, not after) |
| 5 | Grok block: skip on any rc below 43 | RED (rc 0 and 2 rows) |
| 6 | Grok banner: print "safe to git push" on a skip | RED |
| 7 | Wrapper: drop `"$@"` from the final `exec` | RED (argument-verbatim row) |
| 8 | Wrapper: replace `exec` with a plain call (rc not propagated) | RED (gate rc 6 passthrough row) |
| 9 | Grok block: remove the `rc=$?` capture guard (the `or`-assignment) under `set -e` | RED (the combined harness aborts on reader rc 2) |
| 10 | Grok block: remove the skip-flag initialisation | RED (the combined harness aborts under `set -u` on a non-skip push) |

Pinned by rows without a mutant (plan-review cut the mutants, kept the rows): the sibling-resolution decoy tree, the negative parity rows (`test-fix-loop/SKILL.md` and `lefthook.yml` must not reference the wrapper or `--token-only`, ruling F1), the work step-9 call-site pin and the `affected-tests.sh` literal pin.

**Harness rows.** (a) Suite edit that must go RED: make the fake-tree builder omit the gate stub; every "gate IS invoked" row reds. (b) Must-PASS non-canonical inputs: reader stub returning 42 with extra stdout noise and a trailing newline-less verdict; arguments containing spaces for the `--explain` row. (c) Non-empty floors for every awk-extracted block and for the flag string extracted in the parity row.

**Anchor.** Text pins prove consistency of this diff with itself; the outside anchors are the merge-base byte lint (`lint-skill-body-budget.py`), the existing fullsuite/fanout pins, and CI's required test check.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-242 (not a new ADR): `## Amendment — 2026-11-07 (#12247)` plus a frontmatter pointer line. Decision in one line: the operator's `ci-is-the-gate` token is now honoured at work Phase 2, review's lead gate and the Grok pre-push gate through a `--token-only` mode of the same reader (wrapper for work and review, inline for Grok), and not at `soleur:test-fix-loop`, `lefthook.yml` (tracked, #12297) or after archival. Alternatives recorded: per-site inline branches (A, runner-up), a token consult inside `affected-tests.sh` mapped to a new rc (C, rejected: widens a contract that `soleur:test-fix-loop` consumes), bare reader calls with CI-evidence conditions at these sites (rejected: head usually unpushed). Rulings: this plan's `decision-challenges.md` F1-F5, F12. Authored in Phase 6.3 as a plan task, not a follow-up.

### C4 views

No C4 change. Read in full on 2026-11-07: `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, `spec.c4`. Checked and found already modeled or unaffected: external human actors (the founder and operator; no new correspondent or reviewer); external systems (`github` for the unchanged `gh api` calls; no new vendor or webhook); containers and data stores (`plugin.skills`, `plugin.kb` already hold skills and `specs/`; the new wrapper is a script inside the existing `plugin` system, and shared bash primitives are already described on the `plugin` element); actor-to-surface access relationships (unchanged: the reader still reads the branch's own `session-state.md` from the working tree). Derived cardinalities on the model (106 skills, 67 agents) do not move: no skill or agent is added. AC: `bash plugins/soleur/test/c4-count-parity.test.sh` is green.

### Sequencing

The ADR describes the merged state; nothing is soak-gated, so no `adopting` status note.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#12247: work Phase 2, review's local gate and the Grok pre-push gate (plugins/soleur/scripts/grok-pre-push-gate.sh) do not read the token. Reuse battery-owed.sh and its exit contract (42 skippable / 0 owed / 2 undecidable). DO NOT fork the reader." [brief] | Phases 2-5 (flag, wrapper, Grok inline, call sites) | mapped |
| 2 | "#12251: battery-owed.sh condition 3/4 infra check misses C-quoted paths ... Ask the CTO whether it is a separate PR or folds into #12247's PR. Do not bundle unless the CTO says so; record the ruling." [brief] | Ruling F4 in `decision-challenges.md`; handoff recipe in Non-Goals | mapped (ruled: separate PR) |
| 3 | "(F12) Phase 6.45 archives session-state.md, so the token stops applying after archival; check whether any gate still needs it after that point." [brief] | Research Insights F12 finding; ruling F12; the ADR-242 amendment carries the limitation (`operator-constraints.md` item 5 untouched) | mapped |
| 4 | "(L1) a section inside an invisible HTML block (<style>, <pre>) still reads; documented in the script header, accepted." [brief] | Research Reconciliation row (carried, no work) | mapped |
| 5 | "Re-check how the webplat shard timeout tracker #12030 stands ... before assuming the queue is still flaky." [brief] | Research Insights premise table (measured) | mapped |
| 6 | "Rely on CI's required test check ... Read infra-validation and sandbox-canary-capture-gate by hand. Do not run the local affected battery to completion." [brief] | Phase 7 (file-selected suites only); AC on reading the two checks | mapped |
| 7 | "Never push to a PR in the merge queue; never --admin merge; never touch the ruleset." [brief] | AC: none of those actions appear in tasks | mapped |
| 8 | "PR body citing a follow-through tracker uses `Ref #N`, never `Closes #N`. Net-issue-flow gate ..." [brief] | `## Acceptance Criteria` PR-body rows; decision row P4 | mapped |
| 9 | "Registry rows go in sorted position ...; accept rows keyed by 12-hex anchor and cite file:line, re-check line numbers after any insertion." [brief] | Technical Considerations "Accept rows"; Phase 6.4 | mapped (no new TSV row expected) |
| 10 | "Components written canonically (`soleur:ship`, not `/ship`) ..." [brief] | Phase 5.4 | mapped |
| 11 | "No bare pipe into `grep -q` (use a here-string)." [brief] | Test Scenarios note; AC | mapped |
| 12 | "Mutation-battery discipline for any new guard ... Cap fix rounds at two targeted rounds plus one verification pass." [brief] | Guard Contract; Phase 7.2 | mapped |
| 13 | "Byte ceilings only move down ... prefer extracting prose into references/ over growing SKILL.md bodies." [brief] | Technical Considerations byte accounting; Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `--token-only` flag on `battery-owed.sh` | "Reuse battery-owed.sh and its exit contract" (ask 1) | asked |
| `gate-or-skip.sh` wrapper | "work Phase 2, review's local gate" (ask 1); CTO ruling F1 chose the wrapper under the byte ceilings in ask 13 | asked |
| Grok gate inline branch | "the Grok pre-push gate (plugins/soleur/scripts/grok-pre-push-gate.sh)" (ask 1) | asked |
| Work fan-out lead-gate sentence | "work Phase 2" (ask 1): the fan-out lead gate is a second Phase 2 gate | asked |
| `affected-gate-contract.md` section | inferred - justification: the contract reference is where callers look up the gate's rc contract, and the work compat paragraph must move somewhere to pay the byte budget (ask 13) | inferred |
| `operator-constraints.md` item 4 | inferred - justification: item 4 says work and review do not read the token, which this change makes false (the T18p-style doc/consumer parity would rot) | inferred |
| ADR-242 amendment | inferred - justification: ADR-242's 2026-11-06 amendment states the token's scope; leaving it stale makes the recorded architecture lie (plan Phase 2.10) | inferred |
| `test-affected-paths.sh` declared edges | inferred - justification: the suite now reads the wrapper, the Grok script and four more files; without edges an edit to them would not select this suite | inferred |
| Deferral issue #12297 (lefthook) | "Do not bundle unless the CTO says so" (ask 2) plus CTO ruling F5: a deferral needs a tracking issue (`wg-when-deferring-a-capability-create-a`) | inferred |
| Observability and Guard Contract sections | inferred - justification: plan Phases 2.9 and 2.12 require them for script edits and a guard deliverable | inferred |

### Split Assessment

- Subsystems touched: 3 - `plugins/soleur`, `scripts`, `knowledge-base`
- Planned files: 10 | Estimated changed lines: about 420 (tests about 250, scripts about 90, docs and ADR about 80)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the #12251 fix is the one split, already ruled separate)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `battery-owed.sh --token-only` returns exit 0 with reason text `no operator ci-is-the-gate token` and an empty `gh` call log on a fixture where the bare run is SKIPPABLE; with a token it returns 42; with `--bogus` or a second argument it returns 2 (T19a-d, reasons asserted, not only rcs).
- [ ] Ship Phase 4 is unchanged: `plugins/soleur/skills/ship/SKILL.md` and `plugins/soleur/skills/one-shot/SKILL.md` are byte-identical to `origin/main` (`git diff --quiet origin/main...HEAD -- <both>` exits 0; assert on the rc, three-dot so a moving `origin/main` tip cannot flip it) and T16/T18 still pass.
- [ ] `gate-or-skip.sh` skips (exit 0, prints `SKIPPED (NOT run, NOT passed)`) only for reader status 42 on a bare invocation; every other status and any argument run `affected-tests.sh` with the arguments verbatim (T19 wrapper rows, fake plugin tree).
- [ ] `grok-pre-push-gate.sh` waives only the affected-tests step on 42, keeps `GATE=...affected-tests.sh` and the bare `run_step "affected-tests gate" bash "$GATE"` line, and its skip banner never contains `safe to git push`.
- [ ] `plugins/soleur/skills/work/SKILL.md` and `plugins/soleur/skills/review/SKILL.md` each have a net byte delta at or below 0 versus their current sizes (work 359177, review 475913), `python3 scripts/lint-skill-body-budget.py --base origin/main` is green, and `skill-body-budget.json` is untouched.
- [ ] The pins named in Technical Considerations pass when run file-selected (`collision-precheck.test.sh`, `fanout-suite-scope.test.sh`, `fullsuite-merge-gate.test.ts`, `workflow-fidelity.test.ts`).
- [ ] `test-fix-loop/SKILL.md` and `lefthook.yml` contain neither `gate-or-skip` nor `--token-only` (negative rows).
- [ ] Mutation battery per the Guard Contract: unmutated control green first, each mutant proven landed (file differs, `bash -n` passes), every mutant killed with the exact expected row; a lead-unique scratch name; at most two targeted fix rounds plus one verification pass.
- [ ] `print_results` floor equals the exact new assertion count.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` and `python3 scripts/lint-guard-contract.py` on this plan are green; ADR-242 carries the 2026-11-07 amendment and pointer line.
- [ ] No new row was needed in `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/suite-durations.tsv` or `scripts/suite-shard-legs.tsv`; if the replay ratchet required accept rows, they are keyed by 12-hex anchor with final file:line cites and sit in the file's existing order.
- [ ] After the push: the required checks (`test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`) are the gate; `infra-validation` and `sandbox-canary-capture-gate` are read by hand with `gh pr checks` and the ACTUAL conclusions are recorded in the PR Test plan (the diff holds no `apps/web-platform/infra/` or sandbox path, so a not-triggered or skipped conclusion is the likely reading, but the AC is the recorded reading, not a predicted one). No push after the PR enters the merge queue, no `--admin`, no ruleset change.
- [ ] PR body: `Closes #12247`, `Ref #12251`, `Ref #12297`, `Ref #12246`; the net issue flow is declared (files #12297, closes #12247: net 0); the Test plan carries the smoke-check verdict line and "local affected battery NOT executed per operator constraint; operator declared CI test the gate".

### Post-merge (operator)

None. The behaviour is delivered by the merge; there is no soak, no follow-through tracker and no operator step. (Verification of a workflow that calls these scripts through `claude-code-action`, if ever needed, is a dispatch on `main` after merge; a branch dispatch of such a workflow is skip-masked. This PR edits no workflow.)

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** One batched CTO spawn ruled F1-F5 and F12 on 2026-11-07: wrapper plus inline Grok branch (F1), `--token-only` mode (F2), waive only the affected-tests step and keep exit 0 with a distinct banner (F3), #12251 as a separate PR (F4), lefthook deferred to #12297 (F5), no change for post-archival (F12). Full text in `knowledge-base/project/specs/feat-one-shot-12247-ci-is-the-gate-readers/decision-challenges.md`. No legal, finance, marketing, operations, product, sales or support implication: internal plugin tooling, no user-facing surface, no regulated data, no vendor or cost change.

## Test Scenarios

- Given a token and a dirty, behind-main tree with no CI evidence, when `battery-owed.sh --token-only` runs, then it exits 42 and prints the operator's words (ASCII-filtered).
- Given no token and a tree CI would skip, when `--token-only` runs, then it exits 0 and the `gh` stub log is empty.
- Given a token and a diff under `apps/web-platform/infra/`, when `--token-only` runs, then OWED with the infra reason.
- Given a reader that exits 137 or is missing, when the wrapper runs bare, then `affected-tests.sh` runs once.
- Given `gate-or-skip.sh --full`, then the reader is not consulted and the gate receives `--full`.
- Given the Grok gate with a reader stub at 42, then `run_step "affected-tests gate"` is never called, the fast jobs, build and fidelity steps are unaffected, and the banner reads `PASS WITH SKIPPED GATE`.
- Regression: the T16 ship dispatch block and the T18 token rows are unchanged.
- Style note for every new shell row: no bare pipe into `grep -q` (use a here-string), fixtures synthesized and never captured, repo-relative reads from `$HERE`.

## Sharp Edges Applied

Catalogue pass (`plugins/soleur/skills/plan/references/plan-sharp-edges.md`, read in full by a verification seat on 2026-11-07) and the changes it forced:

- Pin census before rewriting a line: the work step-9 swap would have broken the `fullsuite-merge-gate.test.ts` literal pin (work names `affected-tests.sh` once); fixed with a fence comment, and a floor row asserts it. The plugin-root anchoring ratchet (7 and 4 `bash scripts/test-all.sh` sites) was missing from the pin list; added with a hold-or-regenerate-downward rule.
- Universal claims run first: "other prose in work already carries the literal" was false and is replaced by a measured count; "no test executes the Grok script" now carries its grep; "nothing parses the banner" carries its grep and result.
- Extract, never drop, when paying a byte ceiling (learning 2026-09-23): review's caveat sentence moves to the contract reference.
- Equivalent-mutant check: the unreachable fall-through guard was cut instead of defended; mutation 5 stays killed by the reason-text assertion on a green-CI fixture.
- Vacuous-pass checks: negative parity rows assert the file is readable before counting; extractions are flag-based with non-empty floors; the flag-parity row asserts a non-empty flag string and pins `GIT_CEILING_DIRECTORIES`; the banner has its own sentinel pair and the Grok invocation count is pinned at 1.
- Ambient-state checks: the live-branch smoke is conditional on the file existing (the deterministic proof is the fixture rows); the `origin/main` byte-identity AC uses a three-dot `git diff --quiet` and asserts the rc; the `infra-validation` / `sandbox-canary-capture-gate` AC records the actual conclusions instead of predicting them.
- Anchors, not line numbers: the `CHANGED=` line, the T18p insertion point and every pin are cited by content; the floor comes from the suite's own PASS counter.

## Non-Goals and Deferrals

- **#12251 (C-quoted paths in condition 3).** Separate PR (ruling F4). Handoff recipe: replace the `CHANGED=` pipeline with `git -C "$_top" diff -z --no-renames --ignore-submodules=none --name-only refs/remotes/origin/main...HEAD -- | tr '\0' '\n'` (the form the token arm already uses; both rename paths appear), keep `INFRA_RE`, add rows for `é.tf`, a tab, a double quote, a backslash and a submodule gitlink under `ignore = all`, each with a no-fix control; `core.quotePath=false` alone is rejected (partial). This PR cites it as `Ref #12251`.
- **lefthook `bun-test` per-commit hook.** Tracked as #12297 with its re-evaluation criterion (measure per-commit cost; reuse `--token-only`).
- **#12030 webplat shard follow-ups** (pin mutation batteries to one shard): CI change, untouched.
- **Reading the token from `specs/archive/`:** rejected (trust surface, older run of the same branch name).
