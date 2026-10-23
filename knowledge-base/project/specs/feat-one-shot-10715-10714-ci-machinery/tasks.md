# Tasks — feat-one-shot-10715-10714-ci-machinery

Plan: `knowledge-base/project/plans/2026-10-23-fix-ci-machinery-infra-plan-and-go-gates-h3-plan.md`
Closes #10715, Closes #10714.

## Phase 1 — #10715: sentinel-scoped PR plan matrix

- [ ] 1.1 Create `apps/cla-evidence/infra/.pr-plan-skip` — non-empty sentinel whose content is the justification (9109 failure, why the permission-group read is out of Tier-A reach, and the re-enable path: grant the plan credential `API Token Permission Groups:Read` then delete this file)
- [ ] 1.2 In `.github/workflows/infra-validation.yml` `detect-changes`: declare `plan_directories` in `outputs:`; at the end of the `dirs` step (after `printf 'directories=%s\n'`), filter `DIRS` to roots without `.pr-plan-skip`, emit `plan_directories=<json>` to `$GITHUB_OUTPUT`, and `::notice::` each excluded root
- [ ] 1.3 In the `plan` job: `if:` guard `directories != '[]'` → `plan_directories != '[]'`; `matrix.directory` → `fromJSON(needs.detect-changes.outputs.plan_directories)`
- [ ] 1.4 In `plugins/soleur/test/infra-validation-detect.test.sh`: add `detect_plan_dirs()` mirror + cases (sentinel excluded / sentinel-free kept / all-sentinel → `[]` / `directories` unaffected / committed sentinel exists and `test -s` non-empty)
- [ ] 1.5 `bash plugins/soleur/test/infra-validation-detect.test.sh` green

## Phase 2 — #10714: H3 verified-arm tolerance

- [ ] 2.1 In `plugins/soleur/test/go-session-gates.test.sh` H3 block: per gate, extract the `SOLEUR_PLUGIN_ROOT_RESOLVE` line for `gate=${g}`; PASS iff it ends `verified=true` and `source` ∈ `{plugin-root-token, grok-env, devin-cache}`; FAIL on missing line / `verified=false` / unlisted arm. Exactly 3 `ck` (floor arithmetic preserved); pass message carries the captured line
- [ ] 2.2 Update the H3 comment block: arm is environment-dependent; `verified=true` is the invariant; `devin-cache` is the healthy Devin path per go.md
- [ ] 2.3 `SOLEUR_GO_GATES_SKIP_H3=1 bash plugins/soleur/test/go-session-gates.test.sh` green at ≥239 assertions; unskipped run on a `claude`-carrying host if available (≥241)

## Phase 3 — Verification

- [ ] 3.1 PR's own Infra Validation run: `validate (apps/cla-evidence/infra)` green, no `plan` leg for that root, `::notice::` exclusion visible in detect-changes log (AC7/AC8 — self-demonstrating)
- [ ] 3.2 `python3 scripts/lint-guard-contract.py` on the plan stays green if the plan's Guard Contract is edited
- [ ] 3.3 PR body carries `Closes #10715` and `Closes #10714` on their own lines (never the title)
