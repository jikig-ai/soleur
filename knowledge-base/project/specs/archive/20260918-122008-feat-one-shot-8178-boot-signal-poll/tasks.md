---
title: "Tasks — git-data boot-signal poll (#8178)"
branch: feat-one-shot-8178-boot-signal-poll
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-17-fix-git-data-boot-signal-poll-plan.md
issue: 8178
---

# Tasks — git-data boot-signal poll (#8178)

Derived from the finalized plan after the review panel. Spec carries no `lane:` of its
own, so it defaults fail-closed to `cross-domain` (TR2).

## Phase 0 — Preconditions (no code)

- [x] 0.1 Re-run the three arm probes under `doppler run -p soleur -c prd_terraform`
      (`BS_TABLE=t520508_soleur_git_data_prd_logs`): full UNION, `remote()` alone,
      `s3Cluster` alone. Record rc + row counts in the PR body — this is the pre-fix
      control (QG1).
- [x] 0.2 Confirm `secrets.DOPPLER_TOKEN` is in scope for both poll steps and that
      `Install Doppler CLI` precedes both in `git_data_host_create` and
      `git_data_host_replace`.
- [x] 0.3 Run the plan-time lint battery: `scripts/lint-guard-contract.py`,
      `scripts/lint-infra-no-human-steps.py --changed --base origin/main`,
      `scripts/lint-diagnosis-claims.sh` (AP-021) and
      `scripts/lint-workflow-errexit-capture.py` (AP-022). The last two are
      path-scoped and this change moves prose and an rc capture across their bounds.
- [x] 0.4 Read ADR-149 item 4 (amendment target) and ADR-192 (verdict vocabulary,
      and the `CLUSTER_DOESNT_EXIST` clause this change falsifies).
- [x] 0.5 Note PR #8252 as a rebase-order interaction on the same two files.

## Phase 1 — `bs_read_classify` (RED first)

- [x] 1.1 Write failing assertions for `bs_read_classify` covering all eight rc
      classes: `credentials-absent` (3), `reader-exit-1` (1), `credentials-rejected`,
      `source-under-maintenance`, `table-missing` (500 `CLUSTER_DOESNT_EXIST`),
      `reader-refusal` (2/64/78), `transport` (6/7/28/35), `other`.
- [x] 1.2 Add a fixture whose body carries BOTH an auth marker and `maintenance`, and
      pin that `source-under-maintenance` wins — the precedence `_bs_read_remedy` has
      today via sequential assignment.
- [x] 1.3 Create `scripts/lib/betterstack-read-classify.sh`. The function returns 0
      unconditionally (never ending on `grep -q … && printf`).
- [x] 1.4 Have `_bs_read_remedy` in `scripts/cutover-inngest.sh` call it. The function
      stays at its current name, location and arity; its output must not change.
- [x] 1.5 Place the `source` line AFTER the script's first column-0
      `set -euo pipefail`, and add no second one.
- [x] 1.6 Update `apps/web-platform/infra/cutover-inngest-workflow.test.sh` so its
      render driver inlines `bs_read_classify` alongside the two functions it already
      extracts by text — otherwise the generated driver dies under `set -euo pipefail`.
- [x] 1.7 Run the existing cutover suites GREEN (NFR1).

## Phase 2 — The sourced poll library (RED first)

- [x] 2.1 Write `tests/scripts/test-git-data-boot-signal-poll.sh` first, carrying the
      full mutation and harness matrices from the plan's `## Guard Contract`.
- [x] 2.2 Build the harness: shim `betterstack-query.sh` via `BETTERSTACK_QUERY_SCRIPT`
      AND stub `doppler` as a shell function. The shim answers by matching the SQL it
      is handed and by reading `BS_TABLE` / `BS_TABLE_S3` from the environment.
- [x] 2.3 Add the anti-vacuity floor: the suite exits non-zero below its declared
      minimum assertion count and prints the count (QG3).
- [x] 2.4 Implement `scripts/lib/git-data-boot-signal-poll.sh` — `git_data_boot_read`,
      `git_data_boot_answered`, `git_data_boot_poll`, `git_data_boot_poll_decide` —
      with every signature and closing brace at column 0.
- [x] 2.5 Verify the anchor predicate is `dt > fromUnixTimestamp(<anchor - 120>)`,
      never a bare integer and never a quoted literal, and that an empty anchor fails
      closed.
- [x] 2.6 Register the suite in `scripts/test-all.sh` (QG4).

## Phase 3 — Wire the birth job

- [x] 3.1 Replace the poll step's inline body with `source` + calls; keep the `rc=$?`
      capture in the `run:` block so AP-022's hook still sees it.
- [x] 3.2 Drop the three `secrets.BETTERSTACK_QUERY_*` bindings; add
      `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}`; retarget the credentials-absent
      guard at `DOPPLER_TOKEN` (its text currently says "Fix the workflow secrets").
- [x] 3.3 Delete `2>/dev/null`; route stderr to a file under `${RUNNER_TEMP}`.
- [x] 3.4 Branch the per-poll line on whether the read answered.
- [x] 3.5 Pin `BS_TABLE` and `BS_TABLE_S3` unconditionally, assigning from
      `scripts/lib/betterstack-sources.sh`'s `BS_GIT_DATA_TABLE` /
      `BS_GIT_DATA_TABLE_S3` — do NOT re-spell the identifiers as literals (FR9,
      deepen-pass finding). The follow-through script sources the same declaration.
- [x] 3.6 Add `Stamp boot-trail run anchor (git-data create)` immediately before apply.

## Phase 4 — Wire the replace job (its own commit)

- [x] 4.1 Add `id: apply` to `Terraform apply (git-data-host -replace) —
      both-volumes-preserved assert`.
- [x] 4.2 Add the anchor stamp before that apply.
- [x] 4.3 Add the poll step with `id: poll`, sourcing the same library.
- [x] 4.4 Write replace-specific remediation text: no re-dispatch instruction; route
      to the out-of-job `git ls-remote` liveness check (FR11).
- [x] 4.5 Port the `Dispatch summary` empty-outcome backstop and outcome-pair case,
      with their `APPLY_OUTCOME` / `POLL_OUTCOME` env bindings.
- [x] 4.6 Amend `Post-replace readiness note`'s summary to name the in-job boot signal
      as a second gate; leave its Better-Stack-cannot-pull claim alone.

## Phase 5 — Follow-through enrolment

- [x] 5.1 Write `scripts/followthroughs/git-data-boot-poll-8178.sh`: locate a git-data
      job in an `apply-web-platform-infra.yml` run newer than the merge commit and
      assert its poll answered. Exit 2 while none exists, 1 on a failed poll, 0 only
      on a post-merge dispatch whose poll answered.
- [x] 5.2 Write its `.test.sh` and register both in `scripts/test-all.sh`.
- [ ] 5.3 Add the tracker directive and `follow-through` label to #8178, with
      `secrets=GH_TOKEN` (the sweeper forwards only declared names — plan soak section,
      corrected at /work). Done at ship, once the merge date fixes `earliest=`.

## Phase 6 — Records

- [x] 6.1 ADR-149: add `### Addendum — #8178 (2026-09-17)`. Do not rewrite item 4.
- [x] 6.2 ADR-192: add an addendum retiring the "has never stored a row" / "has not yet
      occurred" clauses — measured false (31 rows before 2026-09-15, oldest
      `dt 2026-09-04 15:15:56`).
- [x] 6.3 `principles-register.md`: add the anchored-window rule as a new AP row and
      cite it from ADR-149's addendum.
- [x] 6.4 `model.c4`: correct the `gitDataStore -> betterstack` and
      `github -> betterstack` edge descriptions. Run
      `plugins/soleur/test/c4-count-parity.test.sh` (QG9) — prose only, no count moves.
- [x] 6.5 `git-data-birth.md`: readiness row, `## After the birth` parity note, and the
      replace arm of the partial-birth decision tree.
- [x] 6.6 Write the learning file — knowledge-base/project/learnings/2026-09-18-the-measured-facts-my-resume-brief-handed-me-were-the-defects.md

## Phase 7 — Gates

- [x] 7.1 QG2 — three batteries at review: 24 rows (31/32 killed, 1 equivalent), then 25/25 on the second-pass survivors. Verdicts in the PR body.
- [x] 7.2 QG5 / QG6 — FR1 (no BETTERSTACK_QUERY binding), FR2 (stderr reaches the log), FR8 (anchor), FR9 (table pin) and the NFR2 scrub fixtures are named assertions in the two suites.
- [x] 7.3 QG7 — actionlint (docker rhysd/actionlint) clean except 4 SC1083 warnings byte-identical on origin/main; each poll step's run body is extracted and EXECUTED by the suite.
- [x] 7.4 QG8 / QG10 — lint-guard-contract, lint-infra-no-human-steps --changed, lint-diagnosis-claims, lint-workflow-errexit-capture, lint-shell-trace-credential-refusal, the fixture ratchets and guard-vacuity-floor all green; QG10 citation check PASS.
- [ ] 7.5 QG11 — post-merge, event-gated; carried by the follow-through directive.
