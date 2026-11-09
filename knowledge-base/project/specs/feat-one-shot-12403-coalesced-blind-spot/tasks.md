# Tasks — fix: feed coalesced push-commit messages to the kill-switch and [ack-destroy] gates

Plan: `knowledge-base/project/plans/2026-11-09-fix-kill-switch-ack-destroy-coalesced-blind-spot-plan.md`
Issue: #12403 (epic #10390). Branch: `feat-one-shot-12403-coalesced-blind-spot`.

## Phase 1 — Workflow + lib comment

- [ ] 1.1 In `.github/workflows/apply-web-platform-infra.yml`, `preflight` job, step `id: kill_switch` (~line 248): add `EVENT_MSGS_JSON: ${{ toJSON(github.event.commits.*.message) }}` to `env:` beside `HEAD_MSG`.
- [ ] 1.2 In the same step's `run:` body (after `set -euo pipefail`): build `ALL_MSGS` = `HEAD_MSG` + `jq -r 'join("\n")'` of `${EVENT_MSGS_JSON:-null}`, guarded by `[[ -n "$more_msgs" && "$more_msgs" != "null" ]]` — verbatim #12404 idiom; point the `if [[ ... [skip-web-platform-apply] ... ]]` test at `$ALL_MSGS`.
- [ ] 1.3 In the `apply` job "Terraform plan" step (~lines 868-871): rename `POLICY_MSGS` → `ALL_MSGS` (build, concat, `deploy_policy_gate "$counts" "$ALL_MSGS" || exit 1`).
- [ ] 1.4 Same step (~line 878): `[[ "$HEAD_MSG" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]` → `[[ "$ALL_MSGS" =~ ... ]]`; keep both anchored regexes byte-identical.
- [ ] 1.5 Update `tests/scripts/lib/deploy-policy-gate.sh` comment (~lines 6-8): `POLICY_MSGS` → `ALL_MSGS`; extend the 20-cap note to name all three consumers.
- [ ] 1.6 Byte gate: `wc -c .github/workflows/apply-web-platform-infra.yml` ≤ 490,000 (baseline 489,262). Keep new comment prose minimal — rationale lives in the runbook. `actionlint` the file; extract each touched `run:` block and `bash -n` it.

## Phase 2 — Test pins + executed span

- [ ] 2.1 `tests/scripts/test-deploy-access-token-forget.sh` G11 (~line 133): `"$POLICY_MSGS"` → `"$ALL_MSGS"` literal.
- [ ] 2.2 `tests/scripts/test-destroy-guard-counter-web-platform.sh` `_ack_line` pin (~line 2097): `HEAD_MSG.*ack-destroy` → `ALL_MSGS.*ack-destroy`.
- [ ] 2.3 Same file: new `T66` block — `T66a` preflight job block carries `EVENT_MSGS_JSON` env (comment-stripped); `T66b` kill_switch run-block tests `$ALL_MSGS` against the canonical skip regex; `T66c` apply-step ack test reads `$ALL_MSGS`.
- [ ] 2.4 Same file: `T66d-g` executed span — extract the `preflight` job's `run:` body via `_job_block`, run under `bash -e` with stub `GITHUB_OUTPUT`: (d) token in second commit of `EVENT_MSGS_JSON` → `skip=true`; (e) token mid-line → `skip=false`; (f) `EVENT_MSGS_JSON` unset/`null` → HEAD_MSG-only verdict; (g) tip-only token → `skip=true`.
- [ ] 2.5 Re-derive the exact-count anti-vacuity floor (`121` → `121+N`) with a green suite run, in the same commit.

## Phase 3 — Docs + wrap-up

- [ ] 3.1 `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` (~lines 1033-1037): document any-commit reach for both tokens + the `event.commits` ≤20-entry residual (fail-open for skip, fail-closed for ack).
- [ ] 3.2 Run full green: `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`, `bash tests/scripts/test-deploy-access-token-forget.sh`, `bash tests/scripts/test-destroy-guard-regex-parity.sh`, `bun test plugins/soleur/test/workflow-file-size.test.ts`.
- [ ] 3.3 Verify AC1-AC11 against the diff; confirm `git grep -c 'POLICY_MSGS' -- .github tests scripts` returns 0 and `git grep -cF 'toJSON(github.event.commits.*.message)' .github/workflows/apply-web-platform-infra.yml` returns 2.
- [ ] 3.4 Confirm decision-challenges.md pending technical rulings were resolved (CTO batched ruling) before ship — if the ruling lands tip-only for a gate, keep the concat but scope that gate's regex accordingly.
