# Tasks: infra-validation tail (#6509 ships; #7258 held)

Issue: #6509 · Branch: `feat-one-shot-6509-7258-zot-infra-validation-tail` · PR: #9906 (draft) · Lane: cross-domain (fail-closed default; no spec.md precedes this plan)

Plan: `knowledge-base/project/plans/2026-10-10-fix-registry-template-render-fixture-hold-zot-entry-gate-delete-plan.md`

## Phase 0 — Gates (done at plan time; re-check at work start)

- 0.1 Re-run `git fetch origin main`; confirm `git log HEAD..origin/main -- apps/web-platform/infra/web-zot-consumer-probe.sh apps/web-platform/infra/web-probe.tf` is still empty or, if a repo-list probe has landed, re-evaluate the held #7258 deletion (Phase 4).
- 0.2 Confirm `git diff --name-only origin/main...HEAD` stays outside every "Files NOT to Touch" path.

## Phase 1 — Fixture arms (RED first)

- 1.1 Header carve-out note in `.github/scripts/test/fixtures-validate-infra-templates.sh` (real registry pair, derived populations).
- 1.2 Helpers `reg_root` (copies the registry template + `zot-registry.tf` only, via python) and `reg_noop_guard` (cmp anchor; reset RC/OUT before `bad`).
- 1.3 F23a baseline (arm name exactly `F23a-registry-baseline-renders`): rc 0, `ok  cloud-init-registry.yml`, `rendered+validated 1/1 file`.
- 1.4 F23b: FIRST and LAST distinct `${var}` of the template; delete the key's assignment line inside the `templatefile(` map only; rc 2, `terraform failed to render`, `"<key>"`.
- 1.5 F23c: FIRST and LAST distinct `$${TOKEN` plus `%%{http_code}`; un-double first occurrence (non-identifier-anchored); rc 2 and `terraform failed to render`.
- 1.6 F23d: undeclared `${undeclared_var}`; rc 2, `terraform failed to render`, `"undeclared_var"`.
- 1.7 F23e: must-PASS extra unused map key, rc 0. (The no-call-site rc 4 arm was cut: F6a covers it.)

## Phase 2 — Mutation proof (record in PR body)

- 2.1 One-time full sweeps (16 var drops, 28 token un-doubles, `%%{`, undeclared, no-`.tf`, extra-key) on scratch copies; then the 5-row suite/SUT table from the plan; record the arm that went RED for each, then restore.
- 2.2 Run the suite with a no-op `cloud-init` shim on PATH (render arms); CI is authoritative for the real schema step.

## Phase 3 — Targeted local checks

- 3.1 `bash plugins/soleur/test/fixture-relative-assert.test.sh`; baseline stayed UNCHANGED (row 58 kept; see evidence.md), so no `--write-baseline`.
- 3.2 `shellcheck` the fixtures file; `python3 scripts/lint-guard-contract.py` on the plan.
- 3.3 Do NOT run the full battery locally.

## Phase 4 — #7258 disposition (no deletion)

- 4.1 Comment on #7258 with the evidence, the trigger consequence and the unblock criteria (plan Phase 4). No new issue.
- 4.2 PR body: `Closes #6509`; `Refs #7258` (no close keyword); threshold `none` + reason; mutation table; Trigger-Filter Proof; reduced-panel disclosure; net-issue-flow closes 1 / files 0; attribution line.

## Phase 5 — Ship and verify

- 5.1 Proportionate review panel (disclose reduction); push before review; merge through the normal queue; never sync a queued PR.
- 5.2 After merge run `soleur:postmerge`: confirm no apply/replace/mint run started for the merge commit, `Infra Validation` ran on the PR, and the `workflow_run`-triggered release/post-merge-monitor runs skipped/declined (no release published).
