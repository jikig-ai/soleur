# Tasks — fix the rung-2 rehearsal capture poll (Ref #7025)

Derived from `knowledge-base/project/plans/2026-07-30-fix-rung2-capture-poll-errexit-plan.md`
(post-6-agent-review). **Ref #7025 — do NOT use `Closes`/`Fixes`.**

Phase order is load-bearing: the contract change (1) ships before its consumer (2).

## Phase 0 — Preconditions

- [ ] 0.1 Confirm branch is `feat-one-shot-7025-rung2-capture-poll-errexit`, not main.
- [ ] 0.2 Baseline the gates (measured green this session: 43 / 58 / 30 / 101 assertions):
      `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`,
      `bash tests/scripts/test-git-data-birth-readiness-gate.sh`,
      `bash tests/scripts/test-git-data-rung2-evidence-capture.sh`,
      `bash apps/web-platform/infra/git-data-luks.test.sh`.
- [ ] 0.3 Re-read `.github/workflows/git-data-rung2-rehearsal.yml` capture step (`id: capture`)
      before editing (`hr-always-read-a-file-before-editing-it`).

## Phase 1 — Fix the capture step (contract change)

- [ ] 1.1 `.github/workflows/git-data-rung2-rehearsal.yml`: line 277 `set -uo pipefail`
      → `set -euo pipefail`.
- [ ] 1.2 Bracket **only** the capture pipeline with `set +e` … `set -e`.
      **`rc=${PIPESTATUS[0]}` MUST immediately follow the pipeline**, with `set -e` after it.
      `set -e` is a builtin (a pipeline) and RESETS `PIPESTATUS` — re-arming first makes `rc`
      always 0, a silent false PASS (measured).
- [ ] 1.3 Add the comment block naming the inherited-`-e` trap, the ordering rule, and the
      `web-platform-release.yml` "Run live-verify harness" precedent (cite by **step name**,
      not line number — `cq-cite-content-anchor-not-line-number`).
- [ ] 1.4 Do NOT touch the `tee`, the deadline, the attempt cap, the sentinel block, the
      three-way summary, or `exit "$rc"`.
      **SUPERSEDED AT IMPLEMENTATION by task 1.5 on the next line:** the summary is now
      FIVE-way (PASS / FAIL / WRAPPER FAILURE / UNEXPECTED EXIT / TRANSIENT). Obeying the
      "do not touch the three-way summary" clause literally would revert the wrapper
      fast-fail and restore the ~16-minute paid-host burn its guard arm exists to prevent.
      `exit "$rc"` is unchanged and must stay.
- [ ] 1.5 **Wrapper-auth fast-fail.** Track consecutive no-sentinel `rc=1` attempts; break
      after 2. Add a fourth summary class
      `### Rung-2 rehearsal: WRAPPER FAILURE (doppler auth/config)` naming the credential as
      the thing to check. (Measured: without this, an auth failure burns all 20 attempts /
      ~16 min on a paid host and reports the least actionable verdict.)
- [ ] 1.6 Add a second `upload-artifact` for `/tmp/rung2/capture.log` gated on **non-PASS** —
      today the diagnostic is discarded on exactly the paths that need it.
- [ ] 1.7 Add a next action + runbook link to the FAIL and TRANSIENT summary branches.
- [ ] 1.8 Fix the `teardown_only` / `dry_run` survivor gate:
      `always() && !inputs.dry_run` → `always() && (inputs.teardown_only || !inputs.dry_run)`.

## Phase 2 — The behavioural regression guard

All arms go in `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`, **inside** the
existing `if command -v python3` block (outside it they silently skip). Follow the file's
`pass()`/`fail()` idiom. `cd "$ROOT"` — the step declares no `working-directory:`.

- [ ] 2.1 Extract the `run:` body keyed on **`id: capture`** (NOT the step name — free text,
      zero consumers). Empty extraction must **FAIL** with a message naming the id.
- [ ] 2.2 Derive the env from the parsed `workflow env | job env | step env` maps, substituting
      a placeholder for any `${{ … }}`. Do not hardcode the seven names.
- [ ] 2.3 Fixture: `mktemp -d` + `trap`; stub `doppler` and `sleep` on `PATH`.
      **`rm -rf /tmp/rung2` before each arm** — the body hardcodes that path for `mkdir`, the
      `tee`, the sentinel `grep -q` and `--out`, so the arms are otherwise not isolated.
      Note in the header that these arms cannot run concurrently.
      Assert `command -v sleep` resolves to the stub, and that the `doppler` stub counter > 0.
      **Execute (`bash -e "$extracted"`), never `source`** — `SECONDS` would leak.
- [ ] 2.4 **Arm 13:** stub returns 2, 2, then PASS. Assert `--- capture attempt 2/20` appears,
      exit 0, `capture_rc=0` written, PASS line in `$GITHUB_STEP_SUMMARY`.
- [ ] 2.5 **Arm 13b (mutation):** strip `set +e` → assert 1 attempt, non-zero exit, empty
      `capture_rc`. Must go RED.
- [ ] 2.6 **Arm 13c (ordering mutation):** move `set -e` before the `rc=` read → assert the arm
      goes RED. This guards the silent-false-PASS regression.
- [ ] 2.7 **Arm 13e:** stub always exits 1 with no sentinel → assert the loop stops at attempt
      **2** and the summary carries `WRAPPER FAILURE`.
- [ ] 2.8 **Arm 13d:** text-level, this workflow only — every `run:` body that reads
      `${PIPESTATUS[…]}` must have `set +e` as its nearest preceding toggle, with no command
      between the pipeline and the read. Report a non-zero scanned-body count.
- [ ] 2.9 Retain the check that the upload step still gates on `capture_rc == '0'`. Drop the
      speculative `continue-on-error` assertion.
- [ ] 2.10 Raise the anti-vacuity floor from 43 — **keep `-lt`** (the file's own comment
      rejects `-eq`). Update all **three** literal sites plus the `RAISED 28 -> 39 -> 43`
      header note.

## Phase 3 — Sibling steps (same latent assumption)

- [ ] 3.1 `scheduled-supabase-advisor-scan.yml` — guard `out="$(…)"; rc=$?`. Fix the comment
      that claims a non-zero "must NOT abort the loop". Note in the PR body: the real harm is
      **misclassification** — `issue_class` is never written, so a class-A RLS violation is
      filed as class B.
- [ ] 3.2 `follow-through-closure-guard.yml` — guard the
      `grep -oE 'actions/runs/[0-9]+' | head -1 | sed …` substitution. Correct form here is
      `|| true` / `|| echo ""` (no `PIPESTATUS` read), **not** a `set +e` bracket.
- [ ] 3.3 `deploy-docs.yml` — **four** sites across the pause and resume steps (the `jq -r`
      detector read, the pause `PUT`, the `curl` probe, the resume `PUT`). House form is
      `|| status="000"` since both steps already branch on the code.
- [ ] 3.4 `apply-web-platform-infra.yml` — birth-job step "Poll for the git-data
      boot-completion signal": guard `out=$(bash scripts/betterstack-query.sh …); rc=$?`.
- [ ] 3.5 Re-derive **every** touched comment from the guarded code — fixing one site and
      "correcting" the comment only produces a new false statement.
- [ ] 3.6 File the tracking issue (labels `code-review`, `domain/engineering`). Body carries
      the measured counts (637 bodies; 56 in the audited class, 13 of them reading a numeric rc), names the 9 `Terraform plan` steps whose
      comments assert the opposite of their code, names the deferred repo-wide lint, and
      records the `capture_only` recovery input from DC-4. **Do NOT bulk-flip `-uo` → `-euo`.**

## Phase 4 — Docs, ADR, learning

- [ ] 4.1 `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md`: add
      `## After a PASS` with the literal `gh run download <id> -n git-data-rung2-boot-evidence`
      → `git checkout -b` → `gh pr create` sequence, plus the staleness-race warning. Echo the
      same sequence into `$GITHUB_STEP_SUMMARY` on the PASS branch.
- [ ] 4.2 `ADR-149-git-data-host-birth-route-and-readiness-interlock.md`: one-line correction
      under `### Disposition — #7025` — the shipped route's capture poll could not poll under
      inherited errexit. **No change to `## Decision` or the alternatives table.**
- [ ] 4.3 Append to
      `knowledge-base/project/learnings/best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md`:
      the `|| true` and `|| rc=$?` disqualifications, the `set -e`-resets-`PIPESTATUS` ordering
      trap, the measured actionlint/shellcheck result (`SC2034` only), and a **correction** to
      that file's own default-shell claim. **Do NOT create a fifth learning file.**

## Phase 5 — Verify + ship

- [ ] 5.1 Walk all 15 pre-merge ACs. Use `! grep -q` (not `grep -c … == 0`, which exits 1),
      and anchor `set` greps with `^[[:space:]]*set [-+]e$` (unanchored `set -e` matches every
      `set -euo pipefail` line — 9 hits in this file).
- [ ] 5.2 Scope any `|| true` assertion to the **extracted body** — `|| true` legitimately
      appears twice elsewhere in this workflow.
- [ ] 5.3 Prove arms 13b/13c/13e go RED against their mutations.
- [ ] 5.4 Full gates: `bash apps/web-platform/infra/run-registered-suites.sh`,
      `bash scripts/check-adr-ordinals.sh`, `bash scripts/test-all.sh`.
- [ ] 5.5 Confirm `git diff` touches neither `git-data-birth.md` nor any
      `git-data-rung2-boot-evidence.env`.
- [ ] 5.6 PR body: `Ref #7025` (no closing keyword); render `decision-challenges.md`; disclose
      the two armed automations (advisor scan may file a p1-high security issue previously
      masked as class B; the closure guard will begin reopening issues).
