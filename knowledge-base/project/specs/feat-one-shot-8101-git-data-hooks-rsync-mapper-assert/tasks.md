# Tasks: git-data cutover fence probe + #8101 sequencing

Plan: `knowledge-base/project/plans/2026-09-21-fix-git-data-cutover-fence-probe-and-mapper-assert-sequencing-plan.md`
Issue: #8101 (Ref, not Closes). Lane: single-domain.

## 1. Setup

- 1.1 Confirm the rung-2 hash is unchanged before starting:
  `git_data_rung2_user_data_sha256 apps/web-platform/infra/cloud-init-git-data.yml` must print
  `a0b5f37b…0517`.
- 1.2 Do not touch any rung-2 bound file: the three wrappers, the bootstrap, the cloud-init
  template, `modules/git-data-userdata/*` and the evidence file.

## 2. RED (`apps/web-platform/infra/git-data-cutover-access.test.sh`)

- 2.1 Add the `"h="*` ssh shim arm with the `SHIM_FENCE` modes (ok, r5, r10–r16, r255, line2, exec).
- 2.2 Add rows F1–F16, including F8b and F12b. F16 uses awk-extracted functions in a harness.
- 2.3 Update the shape rows:
  - 2.3.1 AC2: timeline, `timeout` string, ssh-stdin count.
  - 2.3.2 `case_main_order`: seven calls.
  - 2.3.3 Runtime R5b and R5c.
  - 2.3.4 Grep the suite for any other exact-count row.
- 2.4 Add parity row P1: the probe literals must equal the bootstrap `_own` rows.
- 2.5 Runtime arm:
  - 2.5.1 Install the `git` package and add the `git` group.
  - 2.5.2 Add a `plant_fence` helper, and call it after the r5 `rm -rf`.
  - 2.5.3 Add rows `rf2` and `rfsrc`, and update `RUNTIME_ROWS`.
- 2.6 Add mutation rows M1–M5, M7, M8, M10, M11 and harness row H-a.
- 2.7 Run the suite and confirm the new rows are RED.

## 3. GREEN (`apps/web-platform/infra/git-data-cutover.sh`)

- 3.1 Give `_store_emit` an optional reason argument.
- 3.2 Add `refuse_if_fence_not_intact [root] [expected_source] [serving_hooks]`:
  - one `gd_capture '^ok$'` call;
  - remote bytes that begin `h=`;
  - remote exits 10–16 mapped per the plan's D1 table.
- 3.3 Call it as a plain statement in `main()` after the store-empty probe, and update the log lines.
- 3.4 Update the header comment: the new item 3, "shape not content", and the #8211 carry sentence.
  Write it as plain prose with no backticked call.
- 3.5 Add a hooks pointer comment at the census.
- 3.6 Recount `MUTANT_FLOOR` and `FLOOR` exactly, with per-section arithmetic.
- 3.7 Run the suite and confirm it is green.

## 4. Docs and issues

- 4.1 Runbook `git-data-luks-cutover-5274.md`:
  - 4.1.1 Dispatch step 7.
  - 4.1.2 "Exit 0 means".
  - 4.1.3 Add a `fence_not_intact` row to § Verdict map.
  - 4.1.4 Rewrite the #8101 bullet in § Preconditions as one line.
- 4.2 Edit #8211's body additively: append the `## Carried from #8101 (acceptance criteria)`
  checkbox section. Re-read the body to verify it appears once.
- 4.3 Comment on #8101: a link to the #8211 section, "blocked by #8211", and the re-evaluate trigger.
- 4.4 Run `lint-infra-no-human-steps.py --changed --base origin/main`.

## 5. Verify

- 5.1 Run AC1–AC11 from the plan.
- 5.2 The PR body says `Ref #8101`.
