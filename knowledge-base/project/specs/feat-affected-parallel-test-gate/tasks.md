# Tasks: affected-only, parallel test gate (umbrella #9307)

Plan: `knowledge-base/project/plans/2026-09-30-feat-affected-parallel-test-gate-plan.md`
Spec: `knowledge-base/project/specs/feat-affected-parallel-test-gate/spec.md`

Every task is test-first: write the failing test or fixture, see it red, then change the code.

## PR 1 — Soleur-runner selection fix (this branch, PR #9306)

### 1. Anchor directory edges

- [x] 1.1 Write failing rows in `scripts/test-all-affected.test.sh`: KB-only diff with "test" in the path selects none of the five `test`-edge suites; `test/x-community.test.ts` selects them; `apps/web-platform/test/z.ts` selects its own suite and not the root `test/` suites
- [x] 1.2 Run `git grep -n '_diff_touches\|_affected_add_edge' scripts/ plugins/soleur/scripts/` and review every call site
- [x] 1.3 Normalize directory tokens to trailing-`/` prefixes in `_affected_add_edge`; match directory edges as line-start prefixes and file edges as exact lines in `_diff_touches`
- [x] 1.4 Sweep every declared edge array for edges that relied on substring matching
- [x] 1.5 Run the before/after selection diff over the last 30 first-parent commits on `origin/main`; justify every dropped suite as a false positive; record it in `knowledge-base/project/specs/feat-affected-parallel-test-gate/edge-anchoring-corpus.md`

### 2. Always-on audit

- [ ] 2.1 Classify each of the 145 `ALWAYS_ON_SUITES` entries by what it reads (real tree, named subtree, fixtures only)
- [ ] 2.2 For each demotion candidate, capture the observed read-set with `strace -f -e trace=openat,stat,newfstatat` and compare it to the proposed edges
- [ ] 2.3 Move fully covered candidates to declared subtree edges in `scripts/lib/test-affected-paths.sh`
- [ ] 2.4 Set `_MIN_ALWAYS_ON_DECLARED` to the new count minus 5 in the same commit
- [ ] 2.5 Commit the audit table to `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` with before/after summed time from `scripts/suite-durations.tsv`
- [ ] 2.6 Run `bash scripts/lint-orphan-test-suites.sh` (its own invocation) and keep it green

### 3. Selection observability

- [ ] 3.1 Write a failing test asserting the exact expected selected set on a synthesized diff via `--print-selection`
- [ ] 3.2 Add `--print-selection` next to `--print-affected-set`, reusing the pre-pass that decides execution; emit `AFFECTED_SELECTED` per label and one `AFFECTED_SUMMARY`
- [ ] 3.3 Print the `AFFECTED_SUMMARY` line at the start of every affected run
- [ ] 3.4 Confirm `--print-affected-set` output is unchanged against the merge-base for the same registration set

### 4. Dropped-consumer ratchet (Guard 2) and Guard 3 mutation battery

- [ ] 4.1 Create `scripts/test-affected-kb-consumers.test.sh` deriving its population from `--enumerate-commands all`, with one-hop reach into invoked scripts
- [ ] 4.2 Add every Guard 2 and Guard 3 mutation row from the plan; each must redden
- [ ] 4.3 Classify the new suite in the affected census
- [ ] 4.4 Amend ADR-242 (anchored edges, audited floor, `--print-selection`)
- [ ] 4.5 PR body: "affected-suite gate", `Ref #9307`, note the local gate ran full by `runner-changed`, CI green

## PR 2 — plugin-shipped gate (own branch off main)

### 5. Script core, dispatch and contract

- [ ] 5.1 Write `plugins/soleur/scripts/affected-tests.test.sh` with synthesized fixture repos and fake runner shims; write Guard 1 and Guard 5 rows first
- [ ] 5.2 Create `plugins/soleur/scripts/affected-tests.sh` with capability-based dispatch, base-ref order, the changed-set union (committed, staged, unstaged, untracked), `global_paths` and `inert_paths`, one `finish()` exit site
- [ ] 5.3 Implement the rc table 0/1/4/6/7, worst-of aggregation (1 > 4 > 6 > 0), and the mapping from the repo runner's codes (read its `EXIT CONTRACT` header)
- [ ] 5.4 Implement `.soleur-test-gate.json` validation (unknown key, wrong type, malformed JSON -> rc 4) and the vacuous `test_command` denylist
- [ ] 5.5 Add `--explain`, `--self-check`, and the human line plus `AFFECTED_GATE` marker
- [ ] 5.6 Confirm whether classifying the new suite edits `scripts/lib/test-affected-paths.sh` (which would trigger `runner-changed`)

### 6. Adapters

- [ ] 6.1 JS/TS adapter (vitest `related --run`, jest `--findRelatedTests`), honoring the project's `scripts.test`
- [ ] 6.2 Python adapter (test-file-only diffs run those files; testmon if it imports; else full suite with `-n auto` if xdist imports); pytest rc 5 is not a pass
- [ ] 6.3 Go adapter with the reverse-dependency closure from `go list`
- [ ] 6.4 nx/turbo adapter (`nx affected`, `turbo --filter=...[base]`)
- [ ] 6.5 Verify each runner's exit codes and empty-result behavior in the target environment before mapping; add a fixture and Guard 1 rows per adapter

### 7. Budget, CI detection, worker width, cloud

- [ ] 7.1 `timeout` -> `gtimeout` -> bounded-bash watchdog wrapper; `getconf`/`sysctl`/`nproc` for CPU count; list every external binary in the script header
- [ ] 7.2 CI detection (workflow with `pull_request`/`push` trigger and a test command, or `budget_ci: true`); print the matched file; failure before expiry is rc 1
- [ ] 7.3 Worker width `max(1, ncpu/2)` divided by `1 + other running gate processes`, capped onto each runner's own worker option
- [ ] 7.4 Cloud handling: identity-based plugin-root resolution, bounded shallow deepen then `no-base-ref`, toolchain presence check

### 8. Wire call sites (pointer-only edits)

- [ ] 8.1 Create `plugins/soleur/skills/ship/references/affected-gate-contract.md` (rc table with per-skill action, config schema, one example per stack)
- [ ] 8.2 Edit `ship`, `work`, `review`, `test-fix-loop` skill bodies and `grok-pre-push-gate.sh` to call the single entry point; `work` must be net-zero or net-negative (21 bytes free)
- [ ] 8.3 Add the no-local-runner skip verdict to `battery-owed.sh` with a test row; keep its 42/0/2 contract
- [ ] 8.4 Run `python3 scripts/lint-skill-body-budget.py --base origin/main`, `bun test plugins/soleur/test/components.test.ts`, and the harness-parity census

### 9. ADR and build-versus-buy

- [ ] 9.1 Time-boxed read of the community `toolchain` plugin; write the adopt/reject verdict with license terms
- [ ] 9.2 Author ADR-262 via `soleur:architecture` (provisional ordinal; re-check every `origin/*` ref and fresh `origin/main` before merge)
- [ ] 9.3 Run `plugins/soleur/test/c4-count-parity.test.sh` and cite the green run (no C4 file edit)

## PR 3 — opt-in local shard launcher (tracked by #8231)

### 10. Go/no-go measurement

- [ ] 10.1 Measure W=1 vs W=4 in one `taskset` scope with `bytes_tmp`/`bytes_tmpdir` sampled, enough repeats to bound the flake rate
- [ ] 10.2 Record the evidence on #8231; no-go if the cut is under 30% or #7376's suites go red under W (PR 3 ends as a decision record)

### 11. Launcher (only on go)

- [ ] 11.1 Write `scripts/test-all-parallel.test.sh` with Guard 4 rows first
- [ ] 11.2 Create `scripts/test-all-parallel.sh`: pack manifest (absolute path), W workers with `SCRIPTS_SHARD=k/W`, serial tail for non-shardable suites, infra runner pinned to `JOBS=1`, union-equals-full check, deterministic exit aggregation
- [ ] 11.3 Leave `tc_acquire` and the sibling-refusal ordering untouched; default off
