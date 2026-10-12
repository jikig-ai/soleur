# Tasks: route technical forks in closing prose to the CTO agent

Plan: `knowledge-base/project/plans/2026-10-12-feat-closing-prose-technical-fork-gate-plan.md`

Branch: `feat-one-shot-closing-prose-technical-fork-gate`. Closes #10057; refs #10056 and `hr-technical-fork-is-not-an-operator-question`.

## Phase 0: Baselines, funding, dry run (no product code)

- 0.1 Run and record: the pre-ask suite (140 pass), `devin-matcher-parity`, `settings-hook-exec-bit`, `hook-input-contract`, `guard-vacuity-floor` (note `n_fires`), `unkept-promise-hook.test.sh`.
- 0.2 Re-measure skill headroom against the merge-base with `lint-skill-body-budget.py --base`; record `wc -c` for one-shot, plan, work.
- 0.3 Fund the `work` pointer: one bounded pass for a clause-for-clause relocation of the step 3.5 "no-marker branch" tail into `work/references/`; grep `plugins/soleur/test` for asserted tokens first; net bytes <= 0. No qualifying candidate means the fallback (no `work` pointer; say so in the PR body).
- 0.4 Draft the scratchpad sample extractor (not committed): last `text` block of each assistant turn, tool-use-only turns excluded, `?` in the stripped window, newest 300 from the local transcripts; feed `{stop_hook_active:false,last_assistant_message}` to the real hook.
- 0.5 Probe or record as unmeasured: how two simultaneous Stop blocks surface (plugin unkept-promise, ralph `stop-hook.sh`, this hook) and a non-text `last_assistant_message`.
- 0.6 Dry run: an empty lib and an empty executable hook in a scratch copy through `grep-q-pipe-guard`, `settings-hook-exec-bit`, `hook-input-contract`, `lint-orphan-test-suites.sh` and shellcheck, to see which census reacts.

## Phase 1: Failing tests first

- 1.1 Write `.claude/hooks/pre-closing-technical-fork-gate.test.sh`: fixtures B1-B7, A1-A8, Z1, U1, U2, U3, L1, W1, O1, O2, E1-E5, J1, G3, F1-F6, M1, N1, R1-R4, P1, X1, X2, T1, V8; mutation rows G1-1 to G1-11 and G2-1 to G2-3 (G1-10 escape scope, G1-11 judged-unit cap); harness rows H1 and H3; SUT execution marker; accounting identity; floor `(( TOTAL < MIN_CASES ))` reported by `printf` + `exit 1`. It fails (hook absent).
- 1.2 Extend the pre-ask suite: lib-sourcing assertions, the five non-regression rows, `sed` reads repointed at the lib keyed by variable name, the `RULING_OPVOCAB_RE` byte-equality row, V1 literal and `MIN_CASES` raised together.

## Phase 2: Lib and pre-ask refactor

- 2.1 Create `.claude/hooks/lib/technical-fork-cues.sh` (pure: no `emit_incident`, no `.claude/` paths; `_TFC_LOADED` guard; `tfc_self_check`; `TFC_LIB` is the one path variable each consumer uses): SHARED moved byte-identical, CLOSING added (CL1, CL2a, CL2b, CL3), BUSINESS|ACTION split (no `headline`), CLOSING-only `CLOSING_EXTRA` veto, narrowed CL2a/CL2b, `AUTHZ_VERB_RE` stays in the pre-ask hook, `tfc_is_fork <unit> <groups>` (0 fork, 1 pass, 2 bad args; sets `TFC_HIT`), no cap in the lib.
- 2.2 Refactor the pre-ask hook to source the lib and call `tfc_is_fork "$__rq" shared`; all 140 cases and V1-V5, including the 30-60 KB deny rows, pass unchanged. A flipped case reverts the refactor.
- 2.3 Time the worst SHARED regex on a 1500-byte unit; shellcheck; no `eval`.

## Phase 3: Closing hook and registration

- 3.1 Create `.claude/hooks/pre-closing-technical-fork-gate.sh` per the contract (`LC_ALL=C`, `GITHUB_ACTIONS` exit, `"timeout": 10`, judge the last 12 units, `Operator-only` escape scoped to its sentence plus the next unit, the reason's first imperative is the CTO spawn, byte-constant reason and `systemMessage`, ledger row = cue + length + sha256 after the JSON is printed; fail open on every parse doubt, absent `stop_hook_active` and a missing lib included; strip fences FIRST from a 200 KB tail, then code spans and quoted lines, then a 1500 B `LC_ALL=C` cut; URL-safe `?` unit boundary; emit_incident with only the matched unit; 1500 B window; per-unit 600 B cap in the caller; three escape forms; `systemMessage` with the kill switch); mode 100755.
- 3.2 Register under `Stop` in `.claude/settings.json`; add the ledger row to `devin-dispositions.tsv`; run the parity suite.
- 3.3 Turn the Phase 1 suite green; run the declared discoverability command and record its literal output (expected `1`).

## Phase 4: False-positive sample

- 4.1 Run the extractor through the hook; record counts only (size, hits, class per hit, cue, over-broad percentage, BUSINESS-vetoed count, recall estimate). Zero operator-class or ambiguous hits; at most 15% blocked. Narrow, add a synthesized fixture, re-run the whole sample; two failed rounds drop the cue (CL2b first).

## Phase 5: Registries and ratchets

- 5.1 `guard-vacuity-floor.test.sh`: append the suite to the effective `PROMOTED_FILES`, raise `MIN_FIRING_SUITES` by one (re-measure `n_fires` on any rebase), never `MAX_DEFERRED`.
- 5.2 Regenerate `suite-shard-legs.tsv` and `suite-durations.tsv`; check `test-affected-paths.sh` derivation.

## Phase 6: Skill carriers

- 6.1 One pointer each: one-shot (step 8, signage only), `commands/go.md` (extend the existing line-629 sentence, no new line), work (step 3.5, funded by 0.3), plan (Post-Generation Options); each links `technical-ruling-delegation.md` and names the closing message / "Decision for you:" list as the carrier.
- 6.2 `lint-skill-body-budget.py --base`, and the `components.test.ts` wiring check, stay green.

## Phase 7: Record

- 7.1 ADR-084 addendum (reversal for a cue arm, forward pointers on the 2026-10-11 text, one forced reconsideration, ralph-loop residual, shared-label coupling, cue-growth tripwire, graduation checklist); the exact three C4 strings in `model.c4`; regenerate `model.likec4.json`; `c4-count-parity.test.sh` and `c4-model-freshness.test.sh`.
- 7.2 Compound learning (carrier lesson; shared vocabulary must grow; sample-extractor recipe; tripwire). 7.3 One follow-up issue for the rule's `[hook-enforced:]` tag; comment on #10056 with the graduation criterion.

## Phase 8: Pre-push and ship

- 8.1 `bash scripts/pre-push-ratchet-lane.sh`; then by name: `guard-vacuity-floor`, `grep-q-pipe-guard`, `lint-shell-capture-exit.py`, `lint-shell-trace-credential-refusal.py`, `lint-agents-enforcement-tags.py`, `lint-rule-ids.py`, shellcheck, `lint-orphan-test-suites.sh`, `incident-sandbox-coverage.test.sh`, `markdown-lint.sh`.
- 8.2 Rollback simulation in a scratch worktree (`git revert --no-commit`, then the gates the revert must pass); outcome in the PR body.
- 8.3 PR body: `Closes #10057`, the follow-up filed, net-issue-flow NET 0 verified with `net-issue-flow.sh`, the sample counts, the S1 dissent. `soleur:ship` step 5.5 (`archive-kb.sh`) BEFORE arming auto-merge.
