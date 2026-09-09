# Tasks — rung-2 boot evidence commit

Derived from
`knowledge-base/project/plans/2026-09-09-feat-git-data-rung2-boot-evidence-commit-plan.md`.
Read that plan first — it carries the full exit-path routing table and the acceptance criteria.
Open questions are in `decision-challenges.md` beside this file.

Branch: `feat-one-shot-git-data-rung2-boot-evidence` (currently unpushed)
PR: #8002 (open, draft)

## Phase 1 — Preconditions (mechanical)

- [ ] 1.1 `git rev-parse --show-toplevel` is this worktree — `--out` is relative.
- [ ] 1.2 `test ! -e apps/web-platform/infra/git-data-rung2-boot-evidence.env`.
- [ ] 1.3 `git fetch origin main`.
- [ ] 1.4 `git status --short` clean apart from planning artifacts.
- [ ] 1.5 Re-probe the sibling interlock:
      `grep -vE '^[[:space:]]*#' apps/web-platform/infra/cloud-init-git-data.yml | grep -c 'sentry_dsn'`
      must print `2`. The plan and the PR body both claim it has released; assert it.
- [ ] 1.6 Do **not** re-run the hash computation or re-extract the divergence list.

## Phase 2 — Produce the evidence file

- [ ] 2.1 Run the capture exactly as in plan Phase 2, from the worktree root, wrapped in
      `env -u DOPPLER_TOKEN doppler run -p soleur -c prd_terraform --`, with `--host-name`,
      `--evidence-url`, `--window '7 DAY'`, `--divergence` and `--out`. `--divergence` is
      required. `--since` is deliberately omitted; the Sentry read is wider as a result.
- [ ] 2.2 Route on the trap line using the plan's exit-path table. Every path is mapped:
      `0` / `1` / `2`-TRANSIENT / `2`-DERIVATION-FAULT / `64` / `78` / no-line-printed.
- [ ] 2.3 `2` + `TRANSIENT` → widen (`30 DAY`, then `2 MONTH`). Read the message first: the
      unset-variable, control-read-failed and dark-warehouse arms are not window-shaped. Floor:
      after `2 MONTH`, stop and file against #7811. **Never re-dispatch a rehearsal.**
- [ ] 2.4 `2` + `DERIVATION FAULT` → **do not widen, do not retry.** It is deterministic. Read
      the fail-closed diagnostic, which names the offending file.
- [ ] 2.5 No `RUNG2_CAPTURE_VERDICT=` line at all → `doppler run` failed before exec. Wrapper
      failure, never a rehearsal FAIL.
- [ ] 2.6 `RUNG2_SENTRY_CROSSCHECK` must be `CLEAN`. `UNAVAILABLE`, `NOT_RUN` and `FATAL` all
      stop the work — there is no waiver path.
- [ ] 2.7 Do not edit the produced file. If a re-run is needed, delete it first so 1.2 stays
      honest.

## Phase 3 — Verify before committing

- [ ] 3.1 Run the gate with **one** argument, as CI does:
      `git_data_rung2_rehearsal_gate apps/web-platform/infra/cloud-init-git-data.yml`.
      Expect a line beginning `RELEASED`.
- [ ] 3.2 On HOLD, adjudicate by cause using the plan's Phase 3 table. A hash mismatch from a
      genuine payload change is the one case that justifies a re-rehearsal, and it escalates to
      the lead rather than being decided inline.
- [ ] 3.3 Run `gitleaks detect --config .gitleaks.toml --no-git --source <the .env>` locally.
      This file is a new tracked `.env` under `apps/` and is **not** allowlisted; the
      `gitleaks scan` job is a required check. Do not widen `.gitleaks.toml` to make it pass.
- [ ] 3.4 Run the AC1 shape greps and the AC5 residual source-identifier greps.
- [ ] 3.5 **AC7** — read `nft_metadata_drop` from the capture's host-rows output (it is in the
      run output, **not** in the `.env`, which records queries rather than rows). Expect `yes`.
      This is the only measured boolean of the five and the sole basis for the #7772 claim; the
      capture PASSes regardless of its value, so a human must check it. Paste the observed
      `boot_complete` row into the PR body. If it reads `no`, drop the #7772 sentence and stop.

## Phase 4 — Commit

- [ ] 4.1 Commit the planning artifacts under `knowledge-base/project/{plans,specs}/` **first**,
      so the evidence commit is `HEAD` when AC4 runs.
- [ ] 4.2 `git add` only the `.env` and commit.
- [ ] 4.3 Run AC2 (after `git fetch origin main` + rebase) and AC4.

## Phase 5 — Push, sign off, mark ready

- [ ] 5.1 `git push -u origin feat-one-shot-git-data-rung2-boot-evidence`. Nothing exists on the
      remote before this.
- [ ] 5.2 Read AC3 observation 2 explicitly: the freshness step must log
      `rung-2 evidence is valid for the current template.`, not its dormant line. Its job
      `deploy-script-tests` is **not** in `scripts/required-checks.txt` and `main` is not branch
      protected, so a red result would not block a merge. Read the conclusion.
- [ ] 5.3 Confirm `gitleaks scan` green (AC5) and that `.gitleaks.toml` is unmodified.
- [ ] 5.4 CPO sign-off comment (`requires_cpo_signoff: true`), naming the User-Brand Impact
      framing and acknowledging that after merge the birth is held by one blind environment
      approval plus prose. The PR does not move to ready without it.
- [ ] 5.5 Set PR #8002's body to the plan's `## PR body (draft)`. It must carry the four
      mandatory statements plus the post-hoc-capture disclosure, and use `Ref` with no `Closes`
      (AC6, encoded as a `gh pr view` grep).
- [ ] 5.6 Mark ready.

## Phase 6 — After merge

- [ ] 6.1 The `push: branches:[main]` run of `infra-validation.yml` is green and its freshness
      step prints the armed line.
- [ ] 6.2 Re-run the gate against `main`; confirm `RELEASED`.
- [ ] 6.3 Comment on #7025 naming which precondition closed and which remain — specifically that
      the DO-NOT-DISPATCH banner and ADR-149's stale item-8 disposition rows are still open and
      still owned there.

## Notes

- PR #7999 merging first is preferred, not required. It corrects what the capture *says*, not
  what this evidence *is*.
- The evidence is captured locally and post-hoc from the S3 archive, **not** downloaded as the
  run's artifact — the runbook's `## After a PASS` sequence does not apply because the
  2026-09-04 run wrote no artifact. This is disclosed in the PR body.
- Exactly one file in the evidence commit; AC4 is the guard against picking up PR #7999.
