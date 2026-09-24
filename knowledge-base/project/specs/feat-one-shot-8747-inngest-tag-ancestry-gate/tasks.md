# Tasks — fix(ci): refuse off-main vinngest-v* tags (#8747)

Plan: `knowledge-base/project/plans/2026-09-24-fix-inngest-bootstrap-tag-ancestry-gate-plan.md`

## Phase 1 — RED (tests first)

- [ ] 1.1 Add `MOCK_CRANE_LOG` to the crane stub, `reset_state` and `run_bump` in `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`.
- [ ] 1.2 Add behaviour rows B1–B9 (real git; annotated tag on a side-branch commit, squash-merge shape; B9 clones via `file://` with `--depth 1`).
- [ ] 1.3 Add Guard 2 shape asserts S1–S6 over the `build` block (job-key slice, comment-stripped); raise `MIN_ASSERTIONS`.
- [ ] 1.4 Add the exact-string `if: ${{ !inputs.mirror_only }}` and position asserts to `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` (job-set assert unchanged).
- [ ] 1.5 Run both suites; confirm they fail for the expected reasons.

## Phase 2 — GREEN

- [ ] 2.1 Add `target_on_main` + stage `ancestry` to `.github/scripts/bump-inngest-bootstrap-pin.sh`, after `TARGET` and before the `crane digest` loop; update the header RESULT CONTRACT stage list.
- [ ] 2.2 In `.github/workflows/build-inngest-bootstrap-image.yml`: `build` checkout `fetch-depth: 0`; inline step "Refuse a commit that is not on main (#8747)" (`if: ${{ !inputs.mirror_only }}`, before `Build + verify + push`); header comment.
- [ ] 2.3 Run the two suites, `bash .github/scripts/test/run-all.sh`, `bash .github/scripts/test/test-inngest-bootstrap-tag-guard.sh`, `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`.
- [ ] 2.4 Apply Guard 1 rows 2 and 7 and Guard 2 rows 2 and 3 once locally; record the failing assert per row for the PR body.

## Phase 3 — Record the decision

- [ ] 3.1 Amend ADR-232 (§7, `ancestry` in §6, amendment note, sequencing line naming #8782, two Alternatives rows).
- [ ] 3.2 Update `knowledge-base/engineering/operations/runbooks/inngest-server.md` §Bootstrap-image release (tag on main after merge, delete command, automated bump, carrier-changing PR flow, rollback by re-cut).
- [ ] 3.3 Run `plugins/soleur/test/c4-count-parity.test.sh` (backs "no C4 change").

## Phase 4 — Follow-through

- [ ] 4.1 Comment on #6766 (incident + required-check deadlock warning before #4326).
- [ ] 4.2 Comment on #4326 (now the next PR that completes the flow).
- [ ] 4.3 Link #8780, #8781, #8782 from the PR body.

## Post-merge (pipeline-executed, immediately)

- [ ] 5.1 Cut `vinngest-v1.1.40` on the squash-merge commit; watch the run: inline step `verdict=on-main`, bump `result=opened` (auto-merge armed iff `mirror_status=ok`).
- [ ] 5.2 After the bump merges: pin is `v1.1.40`, `git merge-base --is-ancestor "vinngest-v1.1.40^{commit}" origin/main` exits 0, AC6 + GuardA green on main.
