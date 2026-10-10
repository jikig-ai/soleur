# Tasks: web-2 LUKS ledger flip and Article 30 closeout (PR 1 of the #9372 closeout)

Plan: `knowledge-base/project/plans/2026-10-10-feat-web2-luks-ledger-flip-and-article-30-closeout-plan.md`

Branch `feat-one-shot-9372-web2-luks-ledger-closeout`, draft PR #9941. PR 2 (retire the rebirth and reboot workflows) is a
separate branch and is not tasked here. This PR carries `Ref #9372`, never a closing keyword.

## Phase 0: Re-verify before writing (no writes)

- 0.1 `git fetch origin main`; check #9925, #9051, #9529, #8626 state; rebase if #9925 merged.
- 0.2 Re-run the grader read-only (`doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/web2-luks-live-6931.sh`
  with `SOLEUR_FT_EARLIEST=2026-10-10T20:10:00Z`) and the Hetzner volume read (read-only token). Stop and report on #9372 if the
  grader is not PASS or any probe row after the readiness row is non-green.
- 0.3 Baselines green: `python3 scripts/lint-encryption-posture.py --repo-sweep`, `bash scripts/lint-encryption-posture.test.sh`
  (47/47), `bash scripts/lint-legal-registers.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 0.4 Read the apply run's log (bounded, pattern plus `head`) for run id, dispatcher, approver, delete result and timestamps.

## Phase 1: Linter commit (tests first)

- 1.1 Fixtures: web-class repo (indexed volume and attachment sharing a `for_each`, key pair in a sibling file, token and secret
  on one Doppler config, provisioner with unquoted `MAPPER_NAME`, a `variables.tf` host map).
  - 1.1.1 Must-RED cases first, run against the unmodified linter and watched failing.
  - 1.1.2 Must-PASS cases: the canonical web-class fixture, a differently named `for_each` local, a singleton row without the new keys.
- 1.2 Schema: optional `device_binding.apparatus`, `device_binding.key_chain`, row-level `multiplicity` (names match #8626).
- 1.3 Linter, each behind a `MUTATION-TARGET: MB-Ln` marker:
  - 1.3.1 Indexed binding (same `for_each` expression on volume and attachment; every other index form rejected).
  - 1.3.2 Key chain (consumer user_data args, token config equals secret config, secret value is the password result).
  - 1.3.3 Uniqueness of a password across luks rows (explicit and implicit claims) and web-1 / web-class separation.
  - 1.3.4 Apparatus pin and the unquoted-assignment resolver; mount evidence read from the pinned file.
  - 1.3.5 Multiplicity (one supported `for_each` shape, fail closed otherwise; key set equals the variable's keys).
  - 1.3.6 An indexed row missing `apparatus`, `key_chain` or `multiplicity` FAILs.
  - 1.3.7 Fail closed on `for_each` or `volume_id` inside a nested block the extractor cannot parse.
- 1.4 Mutation battery MB-L1..MB-L8 (prefix avoids #8626's MB-14..MB-25); TS-15 and MB-8 untouched.
- 1.5 Green: new cases, TS-15, real ledger unchanged and passing.

## Phase 2: Ledger commit

- 2.1 Rewrite `hcloud_volume.workspaces` from measured facts (volume 107059048, readiness row, probe rows, grader PASS); remove
  `exception`; `live_verification: available` with the qualifying evidence text; `live_coverage_floor` 3.
- 2.2 Linter on the real tree passes with 0 failing checks; exactly three `available` rows.
- 2.3 Run `scripts/followthroughs/registry-luks-live-8386.test.sh` (it mentions the floor in a remediation message).

## Phase 3: Legal commit

- 3.1 CLO drafts one marker text (owner veto recorded in the PR body, not assumed).
- 3.2 Place it under the three conditional-span cells (Article 30 PA-1 (e), the cross-host row (g), the compliance-posture DPA-scope
  row) and the four related sentences; pointer in the web-1 destruction record; dated pointer in `nfr-register.md`.
- 3.3 Verify byte-equality of the three spans after bold removal; grep the added lines for the forbidden phrases.
- 3.4 Create `knowledge-base/legal/audits/2026-10-counsel-review-9372.md` (marker evidence, bounded Art. 5(2) statement for the
  deleted plaintext volume, not-discharged items citing #9948, #9949, #7992, the #9642 pointer).
- 3.5 `bash scripts/lint-legal-registers.sh`.

## Phase 4: Architecture and runbook records

- 4.1 ADR-140 dated addendum (Layer A contract changes).
- 4.2 ADR-263 dated addendum, appended after #9925's addendum if it merged; status stays `adopting`.
- 4.3 Runbook `web2-luks-rebirth-9372.md` closing row 2: dated "done by PR #9941" line.
- 4.4 `bash plugins/soleur/test/c4-count-parity.test.sh` green; no `.c4` edit.

## Phase 5: Tracking and owner surfacing

- 5.1 Confirm #9948 and #9949 exist with the milestone (filed at plan time).
- 5.2 PR body section for #9642 via `decision-challenges.md` (surfaced, not decided).
- 5.3 Comment on #9572: which checkboxes are done, dissolved or carried by #9948.
- 5.4 Do not close or comment-close #9372 in this PR.

## Phase 6: Ship

- 6.1 Rollback simulation in a scratch detached worktree (revert commit 2; lint, lint suite, legal lint).
- 6.2 `git diff --name-only origin/main...HEAD` is inside the allowed set from the plan's acceptance criteria.
- 6.3 `soleur:ship`; PR body `Ref #9372` only.
- 6.4 After merge: re-run the grader read-only; confirm the CI `encryption-posture` job is green on main.
