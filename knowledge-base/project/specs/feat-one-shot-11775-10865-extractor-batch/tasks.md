# Tasks — feat-one-shot-11775-10865-extractor-batch

Plan: knowledge-base/project/plans/2026-11-03-feat-tally-ci-wall-ratchet-ceilings-and-derive-sut-walk-plan.md
Issues: #11775 (Closes), #10865 (Ref — do NOT close), learning 2026-11-02-stem-minted-suts-are-never-walked-by-the-derive.md

## 1. Setup

- [ ] 1.1 Confirm worktree on `feat-one-shot-11775-10865-extractor-batch`, `git fetch origin main`, note `git rev-parse origin/main` as base.
- [ ] 1.2 Re-check live ratchet state: `gh run list --workflow ci.yml --event merge_group -L 3`; if `new-pair` still red, read the latest job log for the pair list (pre-acceptance grep per runbook before any disposition).
- [ ] 1.3 Re-check `gh pr list --label s4-drain --state open` is empty before any baseline edit.

## 2. Workstream A — `ci_wall_s` dimension (#11775)

- [ ] 2.1 `plugins/soleur/scripts/pipeline-tally.sh`: add `ci_wall_s` to `_tally_dim` (+ `ci-wall-s` alias), `_tally_load`, `_tally_write`, `_tally_ledger_ok` (count keys + `capped=` vocab), `init --max-ci-wall-s` (+ `--max-ci_wall_s`), `show` printer, header DIMENSIONS/call-out docs.
- [ ] 2.2 `plugins/soleur/skills/ship/references/pipeline-tally-render.md`: `ci_wall_s` in `tally:` + `Pipeline-Tally:` lines; absent-marker rule (0 → declared absent token; >0 → `ci_wall_s=N`).
- [ ] 2.3 `plugins/soleur/skills/ship/SKILL.md`: at each `incr ci_cycles` site, measure the driven run's wall (`gh run view <id> --json startedAt,updatedAt` delta, or per-job times) and `incr ci_wall_s <s>`; skip when unmeasurable.
- [ ] 2.4 `plugins/soleur/scripts/pipeline-tally.test.sh`: sweep every fixture/assert for the new keys; add rows — incr/gate/cap, aliases, absent at 0, positive render, old-schema ledger, corrupt value → `unreadable`.
- [ ] 2.5 Run `bash plugins/soleur/scripts/pipeline-tally.test.sh` — green.

## 3. Workstream B — ceiling re-rule (#10865)

- [ ] 3.1 Pull the whole-population series (non-cancelled ci.yml `pull_request`+`merge_group` runs since 2026-10-26T21:59:35Z floor; per `affected-index-ratchet` job `completed_at - started_at`; overall + since-2026-11-02 p95, max, daily p95, mean billed minutes).
- [ ] 3.2 Inline-CTO ruling on the series; update `decision-challenges.md` row 1 from `pending` to the ruling.
- [ ] 3.3 `scripts/followthroughs/ratchet-observation-window-10865.sh`: set `P95_MAX`/`MAX_MAX` per ruling; dated comment; drop PROVISIONAL + "re-rule owed" verdict text if final (update verdict strings + header (d)).
- [ ] 3.4 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: re-pin `ow_u_*` helpers, `row_ow_*` texts, sentinel greps, `ow_mutate` strings to the ruled values.
- [ ] 3.5 `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`: dated observation-log row (series + ruling); ceiling mentions updated.
- [ ] 3.6 `knowledge-base/engineering/architecture/decisions/ADR-276-*.md`: dated amendment recording the re-rule.
- [ ] 3.7 If the ruling raises spend past 4,400 billed-min/week: STOP — operator (budget-owner) decision per `decision-challenges.md`.

## 4. Workstream C — derive fix + drain

- [ ] 4.1 `scripts/test-all.sh` `_affected_derive`: seed BFS frontier with existing stem-minted SUT files (probe `f`), execution mode only (`_PRINT_AFFECTED==0` path); keep the early-out untouched.
- [ ] 4.2 `scripts/test-all.sh` `_affected_edge_token`: extend the D1 `$(cd)` arm past redirects between target and `&& pwd` (`2>/dev/null`, `2>&1`, `pwd -P`); normpath as D1; keep greedy fallback + `_alt` re-run.
- [ ] 4.3 `scripts/test-affected-derive.test.sh`: fixture rows (stem SUT walk; cd-prefix spelling matrix; two-stem frontier; SUT→SUT transitive; absent SUT no-op; declared∪derived dedup) + Guard-1 mutation rows.
- [ ] 4.4 Run `python3 -I scripts/ci-pr-affected-replay.py ratchet --report <f>` + `audit --all-refs` to fixpoint; declare real reads / accept mentions per rubric (pre-acceptance grep per pair).
- [ ] 4.5 Retire the `trusted-verdict.sh` entry in `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` after proving the derived edge via `--print-selection`; sweep sibling declarations of the same class.
- [ ] 4.6 `ratchet --print-baseline` → adopt iff different (prune-only); if baseline edited: `s4-drain` label + mirror comment on #10448.
- [ ] 4.7 Live `betterstack-emitter-read ↔ image-cve-triage.sh` pair: disposition only if still unrepaired (accept row if mention per pre-acceptance grep).
- [ ] 4.8 Widening proof: base-runner vs head `--print-selection` streams (default probes + a stem-SUT path probe); assert Guard-1 invariant; `affected-prepass-bench.sh --added-edges <delta>` for unchanged-sel rows.

## 5. Docs + gates

- [ ] 5.1 `ADR-268` dated note: machine line gains `ci_wall_s` + absent marker.
- [ ] 5.2 Learning file: update the "out-of-scope follow-up" note to point at this PR.
- [ ] 5.3 Local gates: `test-affected-derive.test.sh`, `test-affected-derive-cache.test.sh`, `ci-pr-affected-replay.test.sh`, `test-affected-kb-consumers.test.sh`, `pipeline-tally.test.sh`, ratchet exit 0.
- [ ] 5.4 Verify AC1–AC10; PR body `Closes #11775`, `Ref #10865`, `Ref #11556`, `Ref #10448`; if `s4-drain` claimed, mirror comment posted on #10448.
