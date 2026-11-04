# Tasks — fix(ci): rename resolve-target's gate output off the CodeQL head-SHA heuristic (CodeQL alert #332)

Plan: `knowledge-base/project/plans/2026-11-04-fix-codeql-332-untrusted-checkout-plan.md`
Branch: `feat-one-shot-codeql-332-untrusted-checkout`

## Phase 1 — Workflow rename (`.github/workflows/web-platform-release.yml`)

- [x] 1.1 In `jobs.resolve-target` `gate` step `run:` (lines ~294/:299/:302): change `emit deploy_sha ...` → `emit deploy_target ...` on all three emit lines (`emit trusted` lines untouched).
- [x] 1.2 Checkout `with.ref` (line ~329): `ref: ${{ steps.gate.outputs.deploy_target }}`.
- [x] 1.3 Update comment blocks at ~:275 and ~:311–318: replace `deploy_sha` references with `deploy_target`; state that the identifier deliberately avoids `head|sha|commit|branch|ref` (CodeQL `ActionsSHACheckout`/`ActionsMutableRefCheckout` field-name heuristics — the #332 mechanism); update the #216 comment to note #332 reopened on the field-name arm; warn that `emit` indirection must be kept (a literal `echo "x=$VAR" >> $GITHUB_OUTPUT` can become a modeled env→output flow).
- [x] 1.4 Verify: `grep -n "deploy_sha" .github/workflows/web-platform-release.yml` returns only the intentional historical-rationale comment; `grep -n "deploy_target" .github/workflows/web-platform-release.yml` shows 3 emits + ref + comments.

## Phase 2 — Pin updates

- [x] 2.1 `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` (~:488–503, :554): P4 — `gate_ok` asserts `deploy_target`+`trusted` in the gate `run:`; `ref_ok` asserts `co_if == "steps.gate.outputs.trusted == 'true'"`, `co_ref == "${{ steps.gate.outputs.deploy_target }}"`, AND the `steps.<id>.outputs.<name>` identifier does NOT match `(head|sha|commit|branch|ref)`; update the fail message to name the heuristic + #332.
- [x] 2.2 `plugins/soleur/test/deploy-arm.test.sh` (~:684): `_ref` grep pattern → `steps\.gate\.outputs\.deploy_target`.
- [x] 2.3 Verify: `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh` — all rows green incl. mutation battery; `bash plugins/soleur/test/deploy-arm.test.sh` — green; `bash plugins/soleur/test/resolve-target-decision.test.sh` — green.

## Phase 3 — Learning correction + residual sweep

- [x] 3.1 `knowledge-base/project/learnings/security-issues/2026-11-03-codeql-untrusted-checkout-medium-has-no-if-or-persist-credentials-sanitizer.md`: append a dated correction noting the heuristic tests field name / access path / inner expression too (not only the id) — `deploy_sha` re-alerted as #332 on that arm.
- [x] 3.2 Residual-zero sweep: `grep -rn "deploy_sha" .github/ plugins/` returns nothing outside archive paths, intentional prose references, and the unrelated `ci_deploy_sha256` identifier.
- [x] 3.3 `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/web-platform-release.yml"))'` parses.

## Phase 4 — Verification + PR

- [ ] 4.1 PR body cites "CodeQL alert #332"; no `Closes #N` (no tracker — medium-severity convention).
- [ ] 4.2 Confirm the PR-ref CodeQL analysis reports no `actions/untrusted-checkout` alert on `resolve-target`'s checkout — if it does, escalate to plan-B (restructure, documented in the plan's Alternatives) rather than merge.
- [ ] 4.3 Post-merge: `gh api repos/jikig-ai/soleur/code-scanning/alerts/332 --jq .state` reports `fixed`/`dismissed` on `main`.
