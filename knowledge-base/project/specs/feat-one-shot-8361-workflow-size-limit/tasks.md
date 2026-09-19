# Tasks: fix(ci) — apply-web-platform-infra.yml under GitHub's 500 KB workflow-file limit (#8361)

Plan: `knowledge-base/project/plans/2026-09-19-fix-ci-workflow-file-size-limit-plan.md`

## Phase 1: Gate test (RED first)

- [ ] 1.1 Write `plugins/soleur/test/workflow-file-size.test.ts` by transcribing the reference sketch in the plan's Guard Contract (bun:test; `readdirSync` with `withFileTypes` + `isFile()`, sorted; per-row `mkdtempSync` dirs cleaned in `afterAll`): `oversizedWorkflows(dir, gateBytes, minFiles = 1)` over a non-recursive `readdirSync` of `.github/workflows/` filtered to `/\.ya?ml$/`, `statSync().size`, constants `WORKFLOW_FILE_GATE_BYTES = 490_000` and `GITHUB_WORKFLOW_FILE_LIMIT_BYTES = 512_000` (docs URL in a comment), live call with `minFiles: 20` asserting `apply-web-platform-infra.yml` is in the walk
- [ ] 1.2 Add the six fixture rows of the mutation matrix (1, 2, 2b, 3, 4-harness, 5-must-PASS) as in-suite tests with the exact `expect` strings from the plan (row 5 includes the `minFiles: 3` negative control)
- [ ] 1.3 Run `bun test plugins/soleur/test/workflow-file-size.test.ts` — RED naming `apply-web-platform-infra.yml`, size 513306, over 23306

## Phase 2: Relocate comment blocks (no behavior change)

- [ ] 2.1 Create `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` with the frontmatter block from the plan's Files to Create (`title`, `date`, `owners`, `category`, `tags`, `applies_to`, `related_issues: [8361]`) and a one-paragraph preamble; sections for blocks 2, 3, 4, 5, 9 open with `See also: <existing per-target runbook>` (do not edit those runbooks)
- [ ] 2.2 For blocks 1–10 of the plan's ranked table, in order: copy the block verbatim (strip `# `) under `## <job_id>` (step-level: `## <job_id>/<step name>`); in the workflow keep the first line + the Keep-column lines, add `# Rationale: knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md §<job_id>`; never add/remove blank lines
- [ ] 2.3 `wc -c .github/workflows/apply-web-platform-infra.yml` ≤ 480,000 (simulation: 476,295 after blocks 1–10); if not, take the next-largest untouched job-header block with the same Keep discipline; stop at ≤ 480,000
- [ ] 2.4 AC3 parity: YAML-equality `python3 -c` command vs `f64b0ebc2` exits 0 (authoritative); non-comment `diff` prints nothing (diagnostic)
- [ ] 2.5 `bash scripts/generate-kb-index.sh` then `--check` clean
- [ ] 2.6 `python3 scripts/lint-infra-no-human-steps.py <runbook>` and `python3 scripts/lint-credential-path-literals.py <runbook>` exit 0 — reword per plan step 4 if flagged; no `lint-infra-ignore` markers

## Phase 3: Verification

- [ ] 3.1 `bun test plugins/soleur/test/workflow-file-size.test.ts` GREEN
- [ ] 3.2 `bash scripts/lint-workflows.sh` exits 0 (install pinned actionlint the way `ci.yml` does if missing); `python3 scripts/lint-workflow-run-body-syntax.py`, `scripts/lint-workflow-errexit-capture.py`, `scripts/lint-shell-trace-credential-refusal.py` exit 0
- [ ] 3.3 AC5: run all 49 referencing suites by their own invocation (list command in the plan; `bash` for `.test.sh`/`tests/scripts/test-*.sh`, `bun test <file>` for `plugins/soleur/test/*.test.ts`, vitest for the two `apps/web-platform/test/` files) — `plugins/soleur/test/terraform-target-parity.test.ts` explicitly green; if a suite reds on a moved line, restore the line (never edit the test) and record it in the PR body
- [ ] 3.4 AC6 pointer/heading count parity: `grep -c '^ *# Rationale: …§'` in the workflow equals `grep -c '^## '` in the runbook
- [ ] 3.5 PR body: `Closes #8361`, the measured AC1 byte count, any step-4 rewordings and any restored lines; no workflow dispatch of any kind
