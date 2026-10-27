# Tasks: registry-host-replace dispatcher cap hit fails closed (#10650, #9149)

Plan: knowledge-base/project/plans/2026-10-27-fix-registry-host-replace-cap-hit-fail-closed-plan.md

## Phase 1: RED rows first (tests only commit)

- [ ] 1.1 Create `plugins/soleur/test/lib/registry-gate-gh-stub.sh` (shared refusing `gh` stub: run list, exact compare range, contents `.sha` per path and ref via sha1sum blob hash, `.content` at the watermark ref only, modelled 502, exit 64 plus refusal file for anything else)
- [ ] 1.2 Extend `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh`: extract `gate`, add `run_gate`, no-op `sleep` shim, rows K1, K2, K3v, K6, V16; raise the floor from a measured count
- [ ] 1.3 Extend `apps/web-platform/infra/registry-render-delta.test.sh`: switch to the shared stub (29 existing rows stay green), add `cap_compare_of`, rows K3, K4, K5; move the equality literal
- [ ] 1.4 Add `gate-unproven` to the kind loop in `scripts/followthroughs/registry-htpasswd-stdin-10119.test.sh`
- [ ] 1.5 Run the suites against the unmodified workflow, record the RED set (K1 read-count, K2, K3v, K3, K4, K5, K6, V16, probe loop), commit tests alone

## Phase 2: GREEN

- [ ] 2.1 Gate cap arm in `.github/workflows/registry-host-replace-dispatch.yml`: hoist `INFRA/TF/VARS`, `blob_at` with 3 attempts (any non-40-hex result is unprovable), `if ! _b=... || ! _a=...` loop over all three inputs (not the `&& ||` form: SC2015), `unproven=cap` before `exit 1`, `::notice::`, cap-aware `deliver=false` sentence, rewritten cap comment, STEP MAP line
- [ ] 2.2 Verdict step: `GATE_UNPROVEN` env (`${GATE_UNPROVEN:-}`), `gate-unproven` arm before `gate-failed` with its own WHAT/WHY/STATE
- [ ] 2.3 Suites and probe test green; drive mutations 1, 2, 4, 6 and the stub-ignores-ref harness row RED once; note in PR body

## Phase 3: Documentation and closed sets

- [ ] 3.1 Runbook: `gate-unproven` row in the kind table (re-fire replaces the host; add/delete/rename of a render input lands here by design), fix stale `gate-failed` prose
- [ ] 3.2 `FAIL_KINDS` in `scripts/followthroughs/registry-htpasswd-stdin-10119.sh`; reword the header sentence in `scripts/registry-delivery-change.sh`
- [ ] 3.3 `bash scripts/test-all.sh --print-selection --paths=plugins/soleur/test/lib/registry-gate-gh-stub.sh`; record the selection, comment on #11325 if render-delta is not selected

## Phase 4: Validation and PR

- [ ] 4.1 `actionlint` on the workflow (expect no output; the wrapper exits 0 on findings), the run-body lints named in AC8, c4-count-parity
- [ ] 4.2 `bash plugins/soleur/scripts/affected-tests.sh` (expect lock queueing) plus both suites directly
- [ ] 4.3 `rg` for other literals pinning the old cap behaviour
- [ ] 4.4 PR body: `Closes #10650`, `Closes #9149` only if AC1-AC7 hold, `Ref #10205`, `Ref #11325`, Changelog, RED-first evidence; `gh pr merge --squash --auto` only after green checks; never push to a PR in the merge queue
