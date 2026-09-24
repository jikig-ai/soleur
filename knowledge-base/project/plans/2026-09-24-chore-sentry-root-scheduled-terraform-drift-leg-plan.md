---
title: "chore(infra): add the Sentry root to scheduled terraform drift, authenticated like its apply"
date: 2026-09-24
slug: chore-sentry-root-scheduled-terraform-drift-leg
branch: feat-one-shot-6612-sentry-terraform-drift
issue: 6612
closes: 6612
type: chore
priority: p3-low
domain: engineering
lane: single-domain
brand_survival_threshold: none
---

# chore(infra): add the Sentry root to scheduled terraform drift, authenticated like its apply

## Overview

The Sentry Terraform root (`apps/web-platform/infra/sentry`) has no scheduled drift check. Today the
`drift-check` job in `.github/workflows/scheduled-terraform-drift.yml` plans two roots:
`apps/web-platform/infra` and `infra/github`.

After #6589, ADR-031 recorded that "declared ≡ applied" holds only when an apply succeeds, and nothing
checks whether it does. Four paths leave the root divergent with no detector:

- `[skip-sentry-apply]`
- an apply that failed and was never retried, including one the destroy gate failed on purpose
- a hand edit made through Sentry's web UI
- the aftermath of the unlocked (`use_lockfile = false`) concurrent-writer race

This plan adds the Sentry root as a **third matrix leg**. The leg runs a **full-root**
`terraform plan -detailed-exitcode` (no `-target=`), so a divergent root returns exit 2. From there the
job's existing reporting takes over: the `infra-drift` issue, the ops email and the Sentry check-in.

**The leg authenticates the way `apply-sentry-infra.yml` actually does.** That workflow binds the GitHub
repository secret `secrets.SENTRY_IAC_AUTH_TOKEN` as the raw env var `SENTRY_AUTH_TOKEN` and runs a plain
`terraform plan`, with no `doppler run` at all. The issue brief and the task both describe the apply's
plumbing as `doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain`, which the file contradicts (see Research
Reconciliation). The brief's binding constraint still holds: the leg never uses
`--name-transformer tf-var`.

The other deliverables are:

- An appended ADR-031 amendment.
- A stub-driven test suite, plus a real-terraform fixture arm that runs locally, proving that the leg's
  code path turns divergence into `exit_code=2`.
- A post-merge proof that the real Inngest cron function dispatches a run containing the new leg, and
  that the leg authenticates against live Sentry and prints the clean verdict on the converged tree.

This is **v2**, revised after plan review (see `## Plan Review Revisions`). v1 carried a 60 s re-plan
debounce, a refresh-count line, a 410 classifier, a token-confinement census, a C4 edit and a 23-row
suite. Each was cut on measured evidence.

## Research Reconciliation — Spec vs. Codebase

| Spec / brief claim | Reality (measured 2026-09-24) | Plan response |
|---|---|---|
| "mirror [`apply-sentry-infra.yml`'s] `doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain` plumbing" (task brief; issue body §Scope 1) | `apply-sentry-infra.yml` binds `SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}` in step env at every plan/apply site (`Full-root plan + destroy gate`, `Terraform plan (full root)`). Its header says "SENTRY_IAC_AUTH_TOKEN comes from a GitHub repo secret (NOT Doppler) per ADR-031 secret-store-divergence". ADR-031 §Authentication says "Sentry secrets stay in **GitHub repository secrets**, not Doppler", and the Doppler `soleur/prd` copy exists only for operator-local runs (§Local-token source). `gh secret list` (names only) shows the repo secret `SENTRY_IAC_AUTH_TOKEN`. | Mirror the **actual** plumbing: the repo secret bound as raw `SENTRY_AUTH_TOKEN`, with no `doppler run`. This meets both goals the brief states (mirror the apply; avoid `--name-transformer tf-var`). The literal wording is recorded as a User-Challenge in `specs/feat-one-shot-6612-sentry-terraform-drift/decision-challenges.md` (DC-1). |
| Implicit: the tf-var-transformed Doppler path only mangles the token | Doppler `prd_terraform` also carries `SENTRY_ORG`, `SENTRY_PROJECT` and a **personal** `SENTRY_AUTH_TOKEN`. Key names were read via `doppler secrets --only-names`. The personal token is named in ADR-031's 2026-09-11 amendment, and its revocation is #8090. `--name-transformer tf-var` would inject `TF_VAR_sentry_org` / `TF_VAR_sentry_project`, which the apply never sees. A transformer-less `doppler run` would bind the personal token (#7797 class). | The Sentry leg runs **no** `doppler run` of any form. Its variable surface is therefore identical to the apply job's: both load `.github/actions/infra-credentials`, and otherwise the variables fall back to their `default`s. |
| Issue: "Confirm the drift plan runs full-root (no `-target=`)" | The drift step's `terraform plan` carries no `-target=` for any leg today. | Pin it (S3; Guard 1 row 3). |
| The `scheduled-sentry-alert-drift.yml` header ("WHY NOT ADD apps/web-platform/infra/sentry TO scheduled-terraform-drift.yml's MATRIX INSTEAD") and the Sentry README ("DELIBERATELY not the fix") argue against this leg: vendor read failures would red it for non-drift reasons, and a probe that reds that way gets muted. | Both documents make that argument *for the alert rules*, and both record that since #8451 **no resource reads the removed endpoint**. Main's full-root plans have converged since: runs 35789724629, 35883604194 and 35906267802 print `No changes. Your infrastructure matches the configuration.`, and runs 35903124451 and 35908698925 show a real pending change converging. The property #6612 needs (state ≡ config for **every** resource type, cron and uptime monitors included) is not covered by the alert-rule probe. The README itself says "the remaining gap (cron and uptime monitors) is unchanged". | Keep both detectors, which are complementary, and replace the "why not" paragraphs with a short complementarity note. Vendor read failures land on the job's existing **drift/error split**: exit 1 goes to the `[ERROR]` email and never to an `infra-drift` issue. |
| Brief: "the drift workflow also carries a Cloudflare token-drift scan gated `matrix.directory == 'apps/web-platform/infra'`" | Confirmed. The gate is exact equality, so the new leg does not match it even though its path begins with that root's path. All nine `steps.token_drift.*` consumers test positively (`== 'dead'`, `contains(…,'gate-absent')`, `outcome == 'failure'`, …). A skipped step's outputs are `''` and its outcome is `skipped`, so none of them fire on the new leg (repo-research audit). **However**, the existing suite guard T3 that pins this gate is a substring match that the new entry satisfies (Kieran P1). | Logic unchanged. Update the leg-set comments, pin the guard's exactness (S4), and **anchor T3** (Phase 2.6). |
| Implicit: the remediation command in the drift issue can be `gh workflow run apply-sentry-infra.yml --ref main` | `apply-sentry-infra.yml`'s `workflow_dispatch` declares `inputs.reason` with `required: true` (~L111–116), so that command fails with "missing required input". | Remediation text uses `gh workflow run apply-sentry-infra.yml --ref main -f reason="reconcile drift (#<issue>)"` everywhere (DHH P1). |
| Implicit: the error email shows the error | `Prepare email content` sends `head -c 4000` of the plan output. The Sentry root prints ~96 `Refreshing state...` lines before any `Error:`, so an `[ERROR]` email would show only refresh noise. The email is this leg's reliable error channel (#8630). | Strip refresh lines from the email snippet (all legs; Phase 2.5; E1) (DHH P2). |

## Research Insights

**Premise validation (Phase 0.6).**

- #6612 is OPEN and is the target. It was filed by merged PR #6582, which did not touch the drift
  workflow.
- On `origin/main` (`e14ccd4a28`), the drift matrix is `apps/web-platform/infra` + `infra/github`, and
  the file has no `infra/sentry` string.
- The cited apply plumbing does not exist as described (Research Reconciliation row 1).
- Guardrail siblings, all OPEN and none absorbed: #6437, #8349, #8495, #7619, #3829, #6591, #7634,
  #7985, #4781 (PR #8654 OPEN, still shipping), #8630.
- PR #8654 touches three files this plan also edits, but at other offsets, so the hunks are disjoint
  and a 3-way merge is clean in either order. The PRs stay separate and are never bundled.

  | File | #8654 edits | This plan edits |
  |---|---|---|
  | `scheduled-sentry-alert-drift.yml` | around lines 156 and 196 | header lines 15–20 |
  | `infra/sentry/README.md` | around line 22 | around lines 64–66 and 259–266 |
  | ADR-031 | around line 803 | an appended block before `## Consequences`, around line 1057 |

- Because this PR edits `apps/web-platform/infra/sentry/README.md`, it matches `apply-sentry-infra.yml`'s
  `paths:` (`apps/web-platform/infra/sentry/**`). So the PR runs `plan_pr`, a full-root plan with the
  prod token that gives a free pre-merge baseline (AC-B). Its merge also triggers a 0-change apply,
  which is expected and not noise.
- **Does merging THIS alone mutate production?** No resource is added, changed or removed by the
  diff. The only production-facing effect of the merge is the path-triggered `apply-sentry-infra.yml`
  run. Its full-root plan applies whatever main holds unapplied, and AC-B pins that to
  `No changes` at merge time. The drift leg itself only plans. The PR body's first line states this
  answer (AC15-pre).

**Property List (Phase 0.6b).**

- P1: a divergence between the Sentry root's live state and its declared config is detected within
  one cron period (≤ 12 h), whatever caused it: a skipped or failed apply, a hand edit through Sentry's
  web UI, or a concurrent unlocked writer.
- P2: the detection reaches the operator through the existing channels: the `infra-drift` issue and
  the ops email.
- P3: a run that **cannot** plan the root (auth failure, vendor 5xx/410) is reported as an error, never
  as drift and never as clean.
- P4: the detector authenticates with the same credential and variable surface as the apply. This
  rules out a false clean (wrong org) and a false drift (a different `TF_VAR_*` source).
- P5: the new leg does not disturb the other legs or their leg-gated steps, and does not double-fire
  them.
- P6: it is proven, not asserted, that the cron fires the leg and that the leg's code path yields exit 2
  on divergence.
- P7: a transient vendor error never files a standing `infra-drift` issue. The drift/error split
  already guarantees this, because exit 1 goes to the email and never to the issue. The one
  remaining transient-drift case is a plan landing between a merge to `main` and that merge's apply.
  Per plan review it is **accepted and made recognizable**, not suppressed. See Plan Review
  Revisions R1.

**Cut List (Phase 0.6b).**

| Cut mechanism | Property it would buy | Why it is cut |
|---|---|---|
| `doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain` | P4 | Already covered by the repo secret the apply uses (ADR-031 §Authentication). Adding it would create a second credential source with its own staleness mode. |
| A new standalone Sentry drift workflow, schedule or Inngest function | P1/P2 | Already covered by `scheduled-terraform-drift.yml`'s matrix, reporting steps and Inngest dispatcher (ADR-033). |
| A `-target=` allow-list | Nothing | Would reintroduce the #6589 blindness. |
| A new Sentry cron monitor for the leg | Nothing | The per-job check-in to `scheduled-terraform-drift` already fires per leg, and a new monitor costs $0.78/mo. |
| A follow-through tracker for "wait for the next 06:00/18:00 run" | P6 | Covered by `soleur:trigger-cron` firing `cron/terraform-drift.manual-trigger`. That event is registered on the same `createFunction` as `{ cron: "0 6,18 * * *" }` (`cron-terraform-drift.ts`), and the schedule trigger itself is unchanged and shown live by every recent run (35899473356, 35824770896, 35764339625: all `workflow_dispatch` by `soleur-ai[bot]` at 06:00/18:00 UTC). |
| A shared concurrency group with `apply-sentry-infra.yml` | P7 | Harmful. A group keeps one pending run and cancels the older one, so a pending drift run could cancel a pending apply (CTO). |
| A 60 s re-plan debounce (v1 of this plan; CTO required change #1) | P7 | Measured, it does not cover the window it targets. The merge→apply window is 1–8 min (queue + setup; runs 35908698925 and 35883604194), while the apply's own write window is about 15 s. Transient vendor errors are already exit 1 → email, never an issue. It was cut in plan review (R1). |
| A `Refreshed N managed resource(s)` count line (v1) | P6 | Terraform already guarantees it. With no `-target`, exit 0 against 96 declared resources means every one is in state and was refreshed: empty or foreign state plans `to add`, a lost resource plans `to add`, and the wrong org 404s into re-adds. Cut in plan review (R3). |

**Relevant files.**

- `.github/workflows/scheduled-terraform-drift.yml`
  - matrix `strategy.matrix.directory` (~lines 38–52)
  - `Terraform plan (drift detection)`, `id: plan` (~95–134)
  - token-drift gate `if: matrix.directory == 'apps/web-platform/infra'` (~161)
  - leg-set comments (~42–51, ~150–157, ~566–577, ~965–970, ~1769–1774)
  - `Create or update drift issue` (~1137)
  - `Sentry check-in (final)` (~1261)
- `.github/workflows/apply-sentry-infra.yml`
  - header §Authentication divergence (~49–58)
  - `Terraform plan (full root)` (~793), whose `env: SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}` is the mirrored plumbing
  - the apply job loads `./.github/actions/infra-credentials` (~689), as `drift-check` does
- `apps/web-platform/infra/sentry/`
  - `main.tf`: `use_lockfile = false`, key `web-platform/sentry/terraform.tfstate`, `provider "sentry" { base_url = … var.sentry_org … }`
  - `variables.tf`: all three variables have defaults
  - `versions.tf`: `jianyuan/sentry` `0.15.7`, `required_version >= 1.9`
  - `.terraform.lock.hcl` is committed, as `init -lockfile=readonly` needs
  - 96 `resource` blocks (59 cron, 33 issue-alert, 4 uptime), none using `count`/`for_each`. Converged
    apply run 35883604194 refreshed 95; one block was added and applied afterwards (35908698925).
- `apps/web-platform/server/inngest/functions/cron-terraform-drift.ts`: triggers
  `[{ cron: "0 6,18 * * *" }, { event: "cron/terraform-drift.manual-trigger" }]` and dispatches at
  `ref: main`. `cron-manifest.ts` lists `cron-terraform-drift`, so `soleur:trigger-cron` accepts it.
- `apps/web-platform/infra/sentry/cron-monitors.tf`, `sentry_cron_monitor.scheduled_terraform_drift`:
  `failure_issue_threshold = 1`, `recovery_threshold = 1`, `max_runtime_minutes = 15`.
- Suites that parse the drift workflow, all checked for breakage:
  - `plugins/soleur/test/terraform-drift-step-order.test.sh`. T3 runs `grep -qF -- "- $guard_dir"`.
    That is a **substring** match, so after this change the new `- apps/web-platform/infra/sentry` line
    satisfies it on its own. A deleted or renamed main-root entry would then pass T3 while silently
    disabling the token-drift detector. **This plan anchors T3** (Kieran P1; Phase 2.6).
  - `plugins/soleur/test/token-drift-workflow-causes.test.sh`: no leg-count assertions.
  - `plugins/soleur/test/terraform-target-parity.test.ts`: `MAIN_ROOT_FORMS` regexes end at the main
    root. `TF_VAR_terraform_version` is workflow-level and undeclared in the Sentry root, and
    Terraform ignores environment values for undeclared variables, as it already does on the
    `infra/github` leg.
  - `plugins/soleur/test/c4-count-parity.test.sh`: counts heartbeat usages and slugs, and no new
    heartbeat step is added.
  - `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`: no slug change.
  - No lint allowlists consumers of `secrets.SENTRY_IAC_AUTH_TOKEN`. The existing consumers are
    `apply-sentry-infra.yml`, `sentry-audit-gate.yml` and `reusable-release.yml`.
- `plugins/soleur/test/*.test.sh` is auto-globbed by `scripts/test-all.sh`, so it needs no
  `run_suite` line. The ci.yml `test` shards have no `setup-terraform`, so the suite's real-terraform
  arm is conditional (see Test Scenarios). It is run locally in `soleur:work`, where
  `terraform v1.9.8` is on PATH.

**Institutional learnings applied.**

- `2026-04-05-terraform-doppler-dual-credential-pattern.md`: `--name-transformer tf-var` mangles every
  name, which is why the backend creds are extracted separately. The Sentry token needs the same
  treatment one step further: no Doppler at all.
- `2026-09-21-a-removed-vendor-api-is-a-migration-with-a-backlog-not-a-brownout-to-retry.md` and
  `integration-issues/2026-08-19-a-vendor-brownout-is-not-a-flake-and-the-header-said-so-all-along.md`:
  a 410 is not a flake. The drift leg makes one attempt and never retries, exactly like the apply
  after #8451. The apply already classifies 410s per address on every push, so the drift leg does not
  duplicate that classifier.
- `best-practices/2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md`:
  green is a hypothesis. AC15 therefore greps the step's own executed verdict line, which appears
  only when the step runs, not script text that the log also echoes. S3 pins the full-root, no-`-target`
  property that makes exit 0 non-vacuous.
- `test-failures/2026-07-17-a-drift-guard-scoped-by-resource-name-is-addition-blind.md`: count token
  references over the WHOLE workflow file, not only the one step you wrote (S2).
- `best-practices/2026-05-20-tf-var-injection-precedent-shape-match.md`: this workflow is multi-root and
  plan-only, so per-leg differences belong behind a guard, as with the existing `ssh_key_path`
  `VAR_ARGS` guard.
- The ADR amendment convention (ADR-031 carries eight dated `**Amendment (…)**` blocks): append, never
  rewrite.

**CLAUDE.md / AGENTS.md conventions applied.**

- hr-github-app-auth-not-pat: no PAT.
- hr-no-ssh-fallback-in-runbooks: all probes are `gh`/`curl`.
- cq-silent-fallback-must-mirror-to-sentry: a missing secret is a named `::error::` + exit 1, never
  silent.
- hr-verify-repo-capability-claim-before-assert: the auth claim was read from the file.
- Before **every** push, run
  `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` and
  `bash scripts/lint-diagnosis-claims.sh`.

**External research.** Skipped. There is a precise in-repo precedent, the apply workflow. The
functional-overlap registry search found nothing that does this job (the closest is a generic
drift-report plugin).

## Implementation Phases

### Phase 1 — RED: the suite first (cq-write-failing-tests-before)

Create `plugins/soleur/test/terraform-drift-sentry-leg.test.sh`. It must fail against `origin/main`,
which has no matrix entry and no Sentry arm. The rows are listed in Test Scenarios. Shape of the suite:

- **Extraction.** Use `python3` + `yaml.safe_load`, the same idiom as
  `token-drift-workflow-causes.test.sh`. From `jobs.drift-check`:
  - write the step with `id == 'plan'`'s `run` to `$TMP/plan-step.sh`;
  - write the `Prepare email content` step's `run` to `$TMP/email-step.sh`;
  - dump the matrix list.

  **Extraction floor:** the plan script must contain `detailed-exitcode` and be ≥ 10 lines, else
  `FATAL` exit 2.
- **Execution mirrors Actions exactly.** A bare `run:` with no `shell:` runs as `bash -e {0}`, with
  **no pipefail**; the file's own comment at the heartbeat-reconcile step says so. Run each extracted
  script with `bash --noprofile --norc -e`, from a scratch cwd. Env: `MATRIX_DIR`, `GITHUB_OUTPUT`,
  `RUNNER_TEMP`, `CI_SSH_PUB`, `DOPPLER_TOKEN=stub`, and `SENTRY_IAC_AUTH_TOKEN`. All values are
  synthesized (cq-test-fixtures-synthesized-only).
- **PATH stubs.**
  - `terraform` appends its argv to `$TMP/tf.argv`. It records `SENTRY_AUTH_TOKEN=SET|UNSET`, an
    equality flag against `$EXPECT_SENTRY_TOKEN`, and `TF_VAR_sentry_auth_token=SET|UNSET`, never a
    value. It then prints a fake plan body and exits `$STUB_TF_RC`.
  - `doppler` exits 97 when `MATRIX_DIR` is the Sentry root. Otherwise it records its argv and `exec`s
    everything after `--`.
- **Anti-vacuity.** Print `N passed / M failed`. Exit 1 if `PASS+FAIL` is below the floor, where the
  floor is the literal count of assertion calls in the file at authoring time, with a comment saying
  so. That makes it a floor rather than an equality, per the step-order suite's precedent.

### Phase 2 — GREEN: the workflow change (`.github/workflows/scheduled-terraform-drift.yml`)

1. **Matrix.** Append `- apps/web-platform/infra/sentry`. Give it a comment block in the style of the
   `infra/github` entry that covers:
   - #6612 and ADR-031;
   - that it authenticates like `apply-sentry-infra.yml` (repo secret `SENTRY_IAC_AUTH_TOKEN` → raw
     `SENTRY_AUTH_TOKEN`, no `doppler run`);
   - why the tf-var transformer is refused (it drops the raw token and injects `TF_VAR_sentry_*` the
     apply never sees);
   - that the plan is full-root.

   Keep the list-of-strings shape.
2. **Plan step `env:`.** Add
   `SENTRY_IAC_AUTH_TOKEN: ${{ matrix.directory == 'apps/web-platform/infra/sentry' && secrets.SENTRY_IAC_AUTH_TOKEN || '' }}`.
   The secret materializes only in the Sentry leg's plan step. On the other legs the expression yields
   `''` (Kieran verified the `&& ||` semantics).
3. **Plan step `run:`.** Leave the existing `VAR_ARGS` + `doppler run` block **byte-identical** inside an
   `else` arm. Add a first arm, placed inside the existing `set +e` … `set -e` bracket:

   ```bash
   if [[ "$MATRIX_DIR" == "apps/web-platform/infra/sentry" ]]; then
     # (#6612) Raw-token path mirroring apply-sentry-infra.yml: NO doppler run of any form.
     # The inline prefix overrides any ambient SENTRY_AUTH_TOKEN a $GITHUB_ENV export could carry.
     if [[ -z "${SENTRY_IAC_AUTH_TOKEN:-}" ]]; then
       echo "::error::sentry_iac_token_absent — SENTRY_IAC_AUTH_TOKEN is empty; the sentry leg cannot authenticate (ADR-031 §Authentication)."
       PLAN_OUTPUT="SENTRY_IAC_AUTH_TOKEN is not configured (empty) — the sentry leg cannot authenticate."
       EXIT_CODE=1
     else
       PLAN_OUTPUT=$(SENTRY_AUTH_TOKEN="$SENTRY_IAC_AUTH_TOKEN" \
         terraform plan -detailed-exitcode -no-color -input=false 2>&1)
       EXIT_CODE=$?
     fi
   else
     # ... existing VAR_ARGS + doppler run --preserve-env --name-transformer tf-var ... (byte-identical)
   fi
   ```

   Everything after this stays shared and unchanged: the output writes, the redaction `sed`,
   `STACK_NAME` (which yields `web-platform/sentry` for this leg) and the 0/2/else annotations. There is
   one attempt and no retry, per #8451.
4. **Drift-issue remediation for this stack.** `Create or update drift issue`'s "Next Steps" currently
   says "run `terraform apply` locally", which is harmful on an unlocked backend. Add
   `MATRIX_DIR: ${{ matrix.directory }}` to that step's `env`, keyed on the directory rather than on
   the `STACK_NAME` sed. When `MATRIX_DIR == apps/web-platform/infra/sentry`, replace that line with:

   > first check whether an `apply-sentry-infra.yml` run on `main` is queued or in progress (a plan
   > landing between a merge and its apply shows that merge's blocks as `to add` — close this issue once
   > it converges); otherwise re-run the CI apply from `main`:
   > `gh workflow run apply-sentry-infra.yml --ref main -f reason="reconcile drift (#<this issue>)"` —
   > never a local apply (the backend has `use_lockfile = false`, ADR-031). If the drift is a hand edit
   > made in Sentry's web UI, revert it there or codify it in a PR.

   Other stacks keep their current text byte-identical.
5. **Error email shows the error (all legs).** In `Prepare email content`, change the snippet source to
   `PLAN_SNIPPET=$(grep -v ': Refreshing state\.\.\.' "${RUNNER_TEMP}/plan-output.txt" | head -c 4000 | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')`.
   Without pipefail, only the last stage's status matters, so an all-filtered file yields an empty
   snippet rather than a step failure (E1, E2).
6. **Anchor T3 in `plugins/soleur/test/terraform-drift-step-order.test.sh`.** Replace
   `grep -qF -- "- $guard_dir" <<<"$BLOCK"` with an exact-line match
   `grep -qxE "[[:space:]]+- ${guard_dir//./\\.}[[:space:]]*" <<<"$BLOCK"`, and state the reason in a
   comment: a prefix-sharing sibling entry (`…/infra/sentry`) satisfied the substring form. Verify it by
   mutation. Delete the `- apps/web-platform/infra` line from a sandbox copy while the Sentry entry
   remains, then run the suite with `WF` pointed at the copy. It must go red, and it is green on the
   unmutated tree. If `WF` is not overridable, add `WF="${TERRAFORM_DRIFT_WF:-…}"` in the same shape as
   `heartbeat-reconcile-issue-step.test.sh`'s `HEARTBEAT_ISSUE_STEP_WF`.
7. **Comments that assert the leg set** (comment-only):
   - ~566–577: "`drift-check` is a 2-leg matrix" → "a multi-leg matrix; on every leg but
     `apps/web-platform/infra` (today `infra/github` and `apps/web-platform/infra/sentry`) it is
     SKIPPED".
   - ~965–970: "skipped on the `infra/github` matrix leg" → "on every leg but
     `apps/web-platform/infra`".
   - ~1769–1774: "matrix is `apps/web-platform/infra` + `infra/github`" → "the matrix does not include
     the rehearsal root".
   - ~150–157: "running it twice" → "once per leg".

   Then `grep -nE '2-leg|two-leg' .github/workflows/scheduled-terraform-drift.yml` must print nothing.

### Phase 3 — Docs and ADR (same PR — wg-architecture-decision-is-a-plan-deliverable)

1. **ADR-031 amendment** (append-only). Place a new block after the `**Amendment (2026-09-21, #8451)…**`
   block's final `**Exit.**` paragraph, immediately before `## Consequences`, titled:
   `**Amendment (2026-09-24, #6612) — the root gains a scheduled drift check; "declared ≡ applied"
   now has a monitor.**`

   Keep it to about 12 lines, covering:
   - **What changed.** A Sentry leg of `scheduled-terraform-drift.yml` runs a full-root
     `plan -detailed-exitcode` twice daily (Inngest, ADR-033).
   - **What it closes.** Path 3 of the #6589 amendment's three divergence paths. Paths 1
     (`[skip-sentry-apply]`) and 2 (a failed or unretried apply, destroy-gated ones included) are now
     **detected within ≤ 12 h**, not prevented.
   - **The `use_lockfile = false` accepted consequence.** The aftermath of a concurrent unlocked writer
     is now **detected within one cron period** instead of never. The race itself is not prevented.
   - **Authentication.** The repository secret, bound as raw `SENTRY_AUTH_TOKEN`, with no `doppler run`.
     The store rule is unchanged. The tf-var transformer is refused, and so is a plain
     `doppler run -c prd_terraform`, which binds the personal token (#7797, #8090).
   - **Routing.** Vendor read failures are exit 1: they go to the `[ERROR]` email, never to an issue,
     and are never retried. The two frozen `sentry_alert` rules carry `ignore_changes = all`, so the
     leg sees their existence only; field fidelity stays with `scheduled-sentry-alert-drift.yml`.

   Prior text stays byte-identical (AC13).
2. **`apps/web-platform/infra/sentry/README.md`** (not a dated artifact, so it is edited in place).
   - §Drift detection: replace the "Everything else in the root is still not on
     `scheduled-terraform-drift.yml`'s matrix…" paragraph (~259–266) with a third detector. That
     detector is the full-root drift leg, covering every resource type. Describe its auth, its
     error/drift split, and the remediation (the `-f reason=` form from Phase 2.4).
   - Leave the backend-creds sentence (~64–66) as is and append: "(the drift leg reads the Sentry token
     from the same repository secret as the apply)".
3. **`.github/workflows/scheduled-sentry-alert-drift.yml` header** (comment only, ~15–20). Replace the
   "WHY NOT ADD … INSTEAD" paragraph with a note of about 4 lines. The #6612 drift leg now plans the
   full root (state ≡ config for every type, twice daily). This workflow remains the field-level
   fidelity check for every `sentry_alert`, including rules under `ignore_changes`. The two are
   complementary, and the drift leg's vendor failures go to the `[ERROR]` email, not to an issue. PR
   #8654's hunks in this file sit at ~156/~196, so they do not overlap.
4. **Post-mortem tracker row.** In
   `knowledge-base/engineering/operations/post-mortems/sentry-iac-delete-path-silent-noop-postmortem.md`,
   change the #6612 row's status cell from `open` to `closed by PR #<N>`. That cell only.

### Phase 4 — Pre-push gates and verification (local; no credentials)

- `bash plugins/soleur/test/terraform-drift-sentry-leg.test.sh`, with terraform on PATH so the R arms
  run. Quote the `R-arms: ran` line in the PR body.
- `bash plugins/soleur/test/terraform-drift-step-order.test.sh` (anchored T3), plus its sandbox-copy
  mutation from Phase 2.6.
- `bash plugins/soleur/test/token-drift-workflow-causes.test.sh`
- `bun test plugins/soleur/test/terraform-target-parity.test.ts`
- `bash plugins/soleur/test/c4-count-parity.test.sh` (backs the "no C4 impact" conclusion)
- `bash tests/scripts/test-sentry-alert-drift-workflow.sh` (header-only edit, must stay green)
- `bash scripts/lint-orphan-test-suites.sh`
- `actionlint` on both edited workflows, if installed. Otherwise CI's workflow lint covers them.
- `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-24-chore-sentry-root-scheduled-terraform-drift-leg-plan.md`
- Before **every** push:
  - `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`
  - `bash scripts/lint-diagnosis-claims.sh`

### Phase 5 — Post-merge proof (automated; see Acceptance Criteria → Post-merge)

Fire the real cron function, poll until its run completes, and read the Sentry leg's executed verdict
from the job log. No production write: the drift job only plans, and a plan persists no state.

## Files to Edit

- `.github/workflows/scheduled-terraform-drift.yml`:
  - the matrix entry
  - the plan step's `env` + Sentry arm (with the empty-secret guard)
  - the Sentry remediation line and `MATRIX_DIR` env in the drift-issue step
  - the refresh-stripped email snippet
  - the leg-set comments
- `plugins/soleur/test/terraform-drift-step-order.test.sh`: anchor T3's matrix-membership grep, and make
  `WF` overridable if it is not already.
- `.github/workflows/scheduled-sentry-alert-drift.yml`: header comment only (~15–20).
- `apps/web-platform/infra/sentry/README.md`:
  - the §Drift detection paragraph (~259–266)
  - the backend-creds sentence (~64–66)
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`: appended amendment only.
- `knowledge-base/engineering/operations/post-mortems/sentry-iac-delete-path-silent-noop-postmortem.md`:
  the #6612 row status cell.

## Files to Create

- `plugins/soleur/test/terraform-drift-sentry-leg.test.sh`

Not touched:

- any `apps/web-platform/infra/sentry/*.tf`, including the frozen `sentry_alert` rules
- `apply-sentry-infra.yml`
- the Inngest function
- `cron-monitors.tf`
- the C4 model (see `### C4 views`)
- `plugins/soleur/skills/work/SKILL.md`

## Open Code-Review Overlap

1 open code-review issue mentions a touched surface (`scheduled-terraform-drift`):

- #3828 (review: extract composite action for 9-workflow Sentry Crons check-in fan-out).
  **Acknowledge.** It concerns the check-in composite. This plan neither adds to nor edits that
  composite (the `sentry-heartbeat` composite is reused unchanged). It is a different concern, and
  #3828 remains open.

No open code-review issue names `scheduled-sentry-alert-drift.yml`, the Sentry README, ADR-031, the
step-order suite, or the post-mortem.

## Acceptance Criteria

### Pre-merge (CI + local; no credentials)

- [ ] AC1. `strategy.matrix.directory` of `drift-check` contains `apps/web-platform/infra/sentry`
  exactly once, and the two existing entries remain (S1).
- [ ] AC2. On the Sentry arm, the run satisfies all of the following (B1–B3, S3):
  - `terraform plan` is invoked exactly once, with `-detailed-exitcode`, `-no-color` and
    `-input=false`;
  - no argument begins with `-target`;
  - `doppler` is never invoked (the stub exits 97, so any call reds the run).
- [ ] AC3. Terraform sees `SENTRY_AUTH_TOKEN` equal to the synthesized `SENTRY_IAC_AUTH_TOKEN`, even
  when a different ambient `SENTRY_AUTH_TOKEN` is preset. `TF_VAR_sentry_auth_token` is unset (B1, B7).
- [ ] AC4. Terraform stub exit codes 2, 0 and 1 map to `exit_code=2`, `0` and `1` respectively. In each
  case `stack_name=web-platform/sentry`, and the step exits 0 under `bash -e` (B1–B3).
- [ ] AC5. With `SENTRY_IAC_AUTH_TOKEN` empty, the step writes `exit_code=1`, prints
  `::error::sentry_iac_token_absent`, and never invokes terraform (B4).
- [ ] AC6. **Regression.** The `apps/web-platform/infra` and `infra/github` legs still invoke
  `doppler run --preserve-env --name-transformer tf-var -- terraform plan -detailed-exitcode …`. Their
  `stack_name` values are `web-platform` and `infra/github` (B5).
- [ ] AC7. **Least privilege.** Across the WHOLE workflow file,
  `grep -c 'secrets\.SENTRY_IAC_AUTH_TOKEN' .github/workflows/scheduled-terraform-drift.yml` prints `1`.
  That one line also contains `matrix.directory == 'apps/web-platform/infra/sentry'`, and it sits in the
  `plan` step's `env` (S2).
- [ ] AC8. The token-drift step's guard is still exact
  `matrix.directory == 'apps/web-platform/infra'` (S4). `setup-terraform` in `drift-check` keeps
  `terraform_wrapper: false` (S5). T3 in the step-order suite is anchored. It goes red on a sandbox
  copy with the main-root entry deleted and the Sentry entry present, and green on the real file
  (Phase 2.6).
- [ ] AC9. The email snippet built from a plan output of 120 `x.y: Refreshing state... [id=1]` lines
  followed by `Error: boom` contains `Error: boom` and no `Refreshing state` (E1). An all-refresh output
  yields an empty snippet with step rc 0 (E2).
- [ ] AC10. For the Sentry stack, the drift-issue body contains `-f reason=` and does not contain
  the generic step-2 line (the one beginning `If the drift is intentional,`). The other stacks' bodies are byte-identical to `origin/main`'s
  (I1, I2).
- [ ] AC11. **Real terraform** (run locally; `terraform_data` + `backend "local"` fixture). The
  extracted step runs with `MATRIX_DIR=apps/web-platform/infra/sentry` and writes:
  - R1, converged: `exit_code=0`;
  - R2, changed `input`: `exit_code=2`;
  - R3, declared-but-never-applied block: `exit_code=2` with `1 to add`;
  - R4, block removed from config but still in state: `exit_code=2` with `1 to destroy`.

  This is the non-destructive "detects drift" proof the brief asks for, run through the real step
  script with no credentials. In CI without terraform, the suite prints
  `R-arms: SKIPPED (terraform absent)` and does not count those rows.
- [ ] AC12. Every Phase 4 suite passes, and `grep -nE '2-leg|two-leg' .github/workflows/scheduled-terraform-drift.yml`
  prints nothing.
- [ ] AC13. The ADR-031 diff is append-only:
  `git diff --numstat origin/main -- knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md | awk '{print $2}'`
  prints `0`. The appended block contains `#6612` and the phrase `within one cron period`.
- [ ] AC-B. **Pre-merge baseline.** This PR's `apply-sentry-infra.yml` `plan_pr` job (triggered by the
  README path) prints `No changes. Your infrastructure matches the configuration.` in its log. Check
  with `gh run view <id> --log --job <plan_pr-job-id> | grep -c 'No changes\. Your infrastructure matches'`,
  which must be ≥ 1. If the job instead shows a pending change, name it in the PR body as the expected
  first-run drift.
- [ ] AC15-pre. PR body requirements:
  - The first line answers "does merging this mutate production?". The answer: there is no resource
    diff, the path-triggered Sentry apply is expected to be 0-change per AC-B, and the drift leg only
    plans.
  - It uses `Closes #6612`.
  - It says this PR is not bundled with #4781 / PR #8654 or #8630.
  - It cites the real-root divergence evidence (apply run 35903124451:
    `sentry_alert.zot_mirror_fallback_rate will be updated in-place … Plan: 0 to add, 1 to change`).

  Before every push, both pre-push lints and `lint-guard-contract.py` pass on this plan.

### Post-merge (automated by the pipeline; operator input only for the admin-merge approval)

- [ ] AC-PM1. **The cron fires the new leg.**
  1. Wait for the post-merge `apply-sentry-infra.yml` run to complete.
  2. If the current UTC time is within ±30 min of 06:00 or 18:00, wait for that scheduled run instead of
     firing (the `terraform-drift` concurrency group would queue behind it, or cancel a pending run).
     Otherwise fire
     `bash plugins/soleur/skills/trigger-cron/scripts/trigger.sh --event cron/terraform-drift.manual-trigger`
     via `soleur:trigger-cron`.
  3. Poll (Monitor with an until-loop, 30 s interval, 20 min cap) until
     `gh api 'repos/jikig-ai/soleur/actions/workflows/scheduled-terraform-drift.yml/runs?per_page=10' --jq '[.workflow_runs[] | select(.triggering_actor.login=="soleur-ai[bot]" and .status=="completed")][0] | "\(.id) \(.created_at) \(.head_sha)"'`
     yields a run created after the merge, whose `head_sha` is the merge commit or a descendant. A manual
     or scheduled run both count: both go through the same Inngest function.

  Then check that `gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs --jq '.jobs[].name'` lists
  `drift-check (apps/web-platform/infra/sentry)`.
- [ ] AC15. **The leg authenticates and plans the live root.** Read the job log with
  `gh run view <id> --log --job <job-id>`, piped only through `grep -c` and never printed whole. The job
  log echoes the unexpanded script, so every pattern below targets an *executed* line: an expanded
  `$STACK_NAME`, or a rendered `##[error]`.

  | Pattern | Required count |
  |---|---|
  | `No drift detected in web-platform/sentry` | 1 |
  | `##\[error\]Terraform plan failed in web-platform/sentry` | 0 |
  | `##\[error\]sentry_iac_token_absent` | 0 |
  | `failed to perform health check` | 0 |

  A green job conclusion or check-in step is NOT evidence. The plan step never exits non-zero, and the
  check-in step is `continue-on-error`. If the tree was legitimately unconverged at dispatch (a
  pending change named under AC-B), the log shows `Drift detected in web-platform/sentry` instead,
  which still proves authentication and liveness. The pipeline then re-fires once after the pending
  apply and requires the clean verdict.

## Test Scenarios

`plugins/soleur/test/terraform-drift-sentry-leg.test.sh`. Every input is synthesized, and nothing uses
the network.

| Row | Arm | Input | Expected |
|---|---|---|---|
| S1 | structural | matrix list | contains `apps/web-platform/infra/sentry` exactly once; every entry is an existing dir with a `backend "s3"` block; every entry, driven through the extracted plan step with stub rc 2, yields `exit_code=2` |
| S2 | structural | whole workflow file | `secrets.SENTRY_IAC_AUTH_TOKEN` count = 1 (literal, commented); that line contains `matrix.directory == 'apps/web-platform/infra/sentry'`; the YAML key path is `jobs.drift-check.steps[id=plan].env.SENTRY_IAC_AUTH_TOKEN` |
| S3 | structural | plan-step `run`, non-comment lines | no `-target`; the Sentry arm contains `-detailed-exitcode` and no `doppler` |
| S4 | structural | `Cloudflare token drift` step `if:` | exact `matrix.directory == 'apps/web-platform/infra'` (no `contains`/`startsWith`) |
| S5 | structural | `hashicorp/setup-terraform` step in `drift-check` | `terraform_wrapper: false` |
| B1 | behavioural | Sentry leg, stub rc 2 | `exit_code=2`, `stack_name=web-platform/sentry`, doppler never called, exactly one terraform call, argv has `-detailed-exitcode`, no `-target`, `SENTRY_AUTH_TOKEN=SET`, `TF_VAR_sentry_auth_token=UNSET`, step rc 0 under `bash -e` |
| B2 | behavioural | Sentry leg, stub rc 0 | `exit_code=0` |
| B3 | behavioural | Sentry leg, stub rc 1 | `exit_code=1` |
| B4 | behavioural | Sentry leg, `SENTRY_IAC_AUTH_TOKEN=''` | `exit_code=1`, `::error::sentry_iac_token_absent`, terraform never called |
| B5 | behavioural regression | `apps/web-platform/infra` rc 2; `infra/github` rc 0 | doppler argv has `run --preserve-env --name-transformer tf-var --`; `exit_code` 2 / 0; `stack_name` `web-platform` / `infra/github` |
| B7 | behavioural | Sentry leg, ambient `SENTRY_AUTH_TOKEN=decoy-x`, `SENTRY_IAC_AUTH_TOKEN=iac-y` | terraform's equality flag says it saw `iac-y`; no value printed |
| E1 | email step | `plan-output.txt` = 120 refresh lines + `Error: boom` | snippet contains `Error: boom`, no `Refreshing state` |
| E2 | email step | `plan-output.txt` = 120 refresh lines only | step rc 0 under `bash -e`; snippet empty |
| I1 | issue step (text) | the `Create or update drift issue` step `run` | contains the Sentry branch keyed on `MATRIX_DIR` with `-f reason=` |
| I2 | issue step (text) | same | the non-Sentry "Next Steps" lines are byte-identical to `origin/main`'s (a literal copy pinned in the suite) |
| R1 | real terraform (skip if absent) | converged `terraform_data` fixture | `exit_code=0` |
| R2 | real terraform | fixture `input` changed | `exit_code=2`, `Plan:` line |
| R3 | real terraform | new block, not in state (declared-not-applied) | `exit_code=2`, `1 to add` |
| R4 | real terraform | block removed from config, still in state | `exit_code=2`, `1 to destroy` |
| H1 | harness (must-RED) | stub `terraform` ignores `STUB_TF_RC` (always 0) | B1 reds |

## Guard Contract

### Guard 1 — the Sentry drift leg turns a divergent root into `exit_code=2` with the apply's credential

**Property.** Whenever the Sentry root's refreshed live state differs from its declared config, a
`drift-check` run authenticates with the apply's credential and produces `exit_code=2` on the
`apps/web-platform/infra/sentry` leg. That output is what the `infra-drift` issue and the ops email read.

**Assembly.** The property flows through these links, in order:

1. The dispatcher `cron-terraform-drift.ts`. Both of its triggers dispatch at `ref: main`.
2. The `drift-check` matrix list. It is the sole declaration site of a leg; there is no `include:`.
3. The job's `setup-terraform` (with `terraform_wrapper: false`), `infra-credentials`, backend-creds
   and `init -lockfile=readonly` steps.
4. The `plan` step's Sentry arm: the env binding plus the invocation. This is the single chokepoint
   where the leg diverges from the others.
5. The shared tail: the `GITHUB_OUTPUT` writes of `exit_code` and `stack_name`.
6. The consumers keyed on `steps.plan.outputs.exit_code`: the label, the issue, the email content, the
   email, and the check-in.

Coverage of each link:

| Links | Covered by |
|---|---|
| 2, 3 (the wrapper), 4, 5 | this suite, directly |
| 1 | AC-PM1 |
| 6 | the existing position and `always()` coverage in `terraform-drift-step-order.test.sh` |

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `- apps/web-platform/infra/sentry` matrix entry | S1 RED |
| 2 | Route the Sentry arm through `doppler run --preserve-env --name-transformer tf-var --` | B1 RED (the doppler stub exits 97; `SENTRY_AUTH_TOKEN=UNSET`) |
| 3 | Add `-target=sentry_cron_monitor.scheduled_terraform_drift` to the Sentry invocation | S3 + B1 RED |
| 4 | Drop `-detailed-exitcode` from the Sentry invocation | B1 RED (argv); R2–R4 RED where terraform exists |
| 5 | Flip `terraform_wrapper: false` → `true` | S5 RED |
| 6 | Guard's own dispatch: delete every assertion call / make extraction return empty | floor FATAL (exit 1) / extraction FATAL (exit 2) |
| 7 | Second member after a compliant first: a 4th matrix entry whose path skips the shared `exit_code` write | S1's per-entry drive RED |
| 8 | Bind `SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}` unconditionally on a second step (e.g. `Terraform init`) | S2 RED (count 2, missing gate) |
| 9 | Delete the `- apps/web-platform/infra` entry (the Sentry entry still present) | step-order T3 RED (anchored), S1 RED |

**Harness rows.** H1: a stub that ignores `STUB_TF_RC` must red B1, so a vacuous harness is visible.
The must-PASS non-canonical row is S1's per-entry drive of `infra/github`. That input differs from the
canonical Sentry path and must pass through the unchanged `else` arm.

**Anchor.** The guard compares no stored hash. The one stored value is S2's literal count `1`, and that
count sits next to a key-path assertion, so a substitution that keeps the count still fails on the
path. The literal `apps/web-platform/infra/sentry` is pinned in both the suite and the workflow, so a
single diff could delete both. That diff would contradict the appended ADR-031 amendment naming this leg
as the "declared ≡ applied" monitor, and it would pass review on a required-check PR. This is accepted:
the suite proves consistency, and AC-PM1/AC15's live evidence proves integrity.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; no user-facing surface changes.
  The indirect failure is the one this PR closes. If the leg silently authenticates wrong or plans
  nothing, a Sentry monitor or alert that drifted out of its declared state stays undetected, and a
  user-facing outage could page nobody for longer. AC15's executed-verdict grep and AC-PM1's live
  dispatch rule that out.
- **If this leaks, the user's data is exposed via:** no user data is involved. The credential at stake
  is the Sentry IaC integration token (`project:admin`, `alerts:write`), which this PR binds into one
  more step: the Sentry leg's plan step, under the main-only `infra-privileged` environment. Actions
  masking applies, and S2 confines the binding to that one step. Plan text in a drift issue shows
  attribute diffs of Sentry config. Those values are already public: they are declared in the
  repository's `.tf`, and the same full-root plan is already tee'd into public `apply-sentry-infra.yml`
  logs on every apply.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the only touched path under apps/*/infra/ is the Sentry root's README (documentation); the functional change is a read-only CI plan of operator alerting configuration that carries no user data and changes no user-facing surface.`

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor `scheduled-terraform-drift` (per-leg end-of-job check-in, now 3 legs) + the `drift-check (apps/web-platform/infra/sentry)` job and its executed `No drift detected in web-platform/sentry` / `Drift detected in web-platform/sentry` line in each Inngest-dispatched run"
  cadence: "twice daily, 06:00 and 18:00 UTC (Inngest cron-terraform-drift)"
  alert_target: "ops email via ./.github/actions/notify-ops-email on exit_code != 0; `infra-drift` GitHub issue on exit_code == 2; Sentry monitor issue on a missed check-in"
  configured_in: ".github/workflows/scheduled-terraform-drift.yml (drift-check job) + apps/web-platform/infra/sentry/cron-monitors.tf (sentry_cron_monitor.scheduled_terraform_drift)"
error_reporting:
  destination: "ops email `[ERROR] Terraform plan failed for web-platform/sentry` (Resend) whose snippet now carries the error text rather than refresh lines; run annotations; Sentry check-in status=error"
  fail_loud: "`::error::Terraform plan failed in web-platform/sentry (exit N)` or `::error::sentry_iac_token_absent`, plus the [ERROR] email"
failure_modes:
  - mode: "root diverged (skip-sentry-apply, failed/unretried apply, hand edit via Sentry's web UI, concurrent unlocked writer)"
    detection: "full-root terraform plan -detailed-exitcode returns 2 on the sentry leg"
    alert_route: "`infra: drift detected in web-platform/sentry` issue (label infra-drift) + [DRIFT] email"
  - mode: "plan lands between a merge to main and its apply (transient)"
    detection: "exit 2 whose plan shows the just-merged blocks as `to add`; the issue body's remediation says to check for a queued/in-progress apply first"
    alert_route: "the same infra-drift issue; closed once the apply converges (accepted residual, R1)"
  - mode: "sentry leg cannot authenticate (secret empty, revoked, or under-scoped)"
    detection: "named `sentry_iac_token_absent` exit 1, or the provider's `failed to perform health check` → exit 1"
    alert_route: "[ERROR] email + Sentry check-in status=error (the monitor pages no alert workflow today, #8630, so the email is the reliable route)"
  - mode: "vendor read failure during refresh (5xx/429/410)"
    detection: "exit 1 on the single attempt (never retried, per #8451)"
    alert_route: "[ERROR] email, never an infra-drift issue (drift/error split)"
  - mode: "dispatcher stops firing"
    detection: "missed check-in on sentry_cron_monitor.scheduled_terraform_drift (checkin_margin 60 min) + cron-inngest-cron-watchdog"
    alert_route: "Sentry monitor issue + watchdog"
logs:
  where: "GitHub Actions run logs for scheduled-terraform-drift.yml (job `drift-check (apps/web-platform/infra/sentry)`); plan text copied into the infra-drift issue body/comments on exit 2"
  retention: "GitHub Actions log retention (90 days default); issue comments indefinitely"
discoverability_test:
  command: "grep -o -m1 -F 'apps/web-platform/infra/sentry' .github/workflows/scheduled-terraform-drift.yml"
  expected_output: "apps/web-platform/infra/sentry"
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-031** (`ADR-031-sentry-as-iac.md`) with an appended `**Amendment (2026-09-24, #6612)**`
block (Phase 3.1). The amendment extends the #6589 amendment in two ways:

- path 3 of "three live paths leave the root divergent" is closed;
- the `use_lockfile` accepted consequence gains its detector.

No new ADR is needed: nothing is reversed and no new substrate is introduced.

### C4 views

**No C4 impact.** All three model files were read against the change:

- `spec.c4`: element kinds and the `external` tag.
- `views.c4`: `sentry` is already included in both views that list external systems (lines 28 and 54).
- `model.c4`: the `sentry` system at ~407 and the edges at ~622, ~762 and ~764.

What the enumeration found:

- **External human actors.** None new. The operator (`founder`) is reached via `sentry -> founder` and
  by email.
- **External systems.** `github`, `sentry` and `cloudflare` (the R2 state backend, narrated on the
  `github -> cloudflare` edge at ~622) are all already modeled. There is no new vendor.
- **Containers and data stores.** None new. `web-platform/sentry/terraform.tfstate` is read, never
  written.
- **Access relationships.** Unchanged. The `github -> sentry` edge (~762) already names
  `scheduled-terraform-drift` as an emitter on it, and it already carries the technology
  "Terraform provider, SENTRY_AUTH_TOKEN". The drift leg is the same actor→system pair, with the same
  credential class and the same protocol.

No embedded cardinality moves: there is no new check-in emitter or monitor. This is backed by a green
`plugins/soleur/test/c4-count-parity.test.sh` run (Phase 4), not by reasoning alone.

### Sequencing

The change is true at merge. The ADR text describes the state the merge creates, and AC-PM1 and AC15
observe it.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** GO, with 4 required changes. The CTO confirmed the following:

- The auth choice: the repo secret, with an inline `SENTRY_AUTH_TOKEN=` prefix that is load-bearing
  against an ambient `$GITHUB_ENV` value, and no Doppler. The alternatives are ruled out.
- Gating the token per leg is adequate least privilege.
- The Sentry-specific remediation.
- The trigger-cron post-merge proof.

Disposition of the required changes after plan review:

| # | CTO required change | Disposition |
|---|---|---|
| 1 | A re-plan debounce against an in-flight apply | **Reversed in plan review (R1).** It is logged as DC-2 in `decision-challenges.md` for `ship` to surface. |
| 2 | 410 classification, never retried | Met structurally: there is a single attempt and no retry, and the apply already classifies 410s per address. |
| 3 | A named `sentry_iac_token_absent` guard | Kept (B4). |
| 4 | Use `plan_pr` as the pre-merge baseline | Kept (AC-B). |

**Why R1 reversed the debounce.** The measured window the debounce targets is merge→apply, which runs
1–8 minutes (runs 35908698925 and 35883604194), so 60 s cannot cover it. Transient vendor errors are
already exit 1, which goes to the email and never to an issue. The remaining false positive is now made
recognizable instead: the issue's remediation says to check for a queued or in-progress apply first.

**CTO recommendations:**

- **Public plan text.** Acknowledged (see User-Brand Impact).
- **Read-only Sentry integration.** Rejected (see Alternatives).
- **`infra-drift` auto-close.** Out of scope; it is pre-existing behaviour for every leg.

**Other domains.**

- **Product/UX.** No surface: the Files lists contain no UI files, so the mechanical UI override did not
  fire.
- **Legal, Marketing, Sales, Finance, Operations, Support.** No implications. There is no new vendor,
  cost, data processing or user-facing copy. Sentry bills monitor seats, not check-ins or API reads.

## Encryption Posture

Skipped: no new persistent store and no new cross-component connection. The leg reuses two existing,
already-modeled connections:

- `github -> sentry`: the same HTTPS provider API the apply uses.
- `github -> cloudflare` R2: the same state backend, read-only.

No file in the Files lists matches the detection set (`.tf`, migrations, cloud-init, docker-compose).

## Infrastructure (IaC)

Not triggered. Nothing is provisioned: no resource, secret, vendor account, service or DNS record. The
change adds a read-only `terraform plan` of an existing root to an existing workflow, using existing
secrets. It prescribes no hand-performed provisioning step.

## Plan Review Revisions

Panel: DHH, Kieran, code-simplicity, plus the Step 4.5 advisor consult. The simplification and
correctness panels both fired on the debounce, the refresh line, the 410 classifier, the token census
and the test-suite bulk. Per plan-review, **delete was preferred over fix**.

- **R1 (Mechanical; both panels): the 60 s re-plan debounce is cut.**
  - DHH measured the targeted merge→apply window at 1–8 min.
  - Simplicity showed that exit 1 already never files an issue.
  - Kieran found a mislabelled-retry annotation bug in it.
  - The advisor argued against re-planning on exit 2.
  - Cutting it also dissolves B8–B11, Guard 1 rows 7–8 and a Sharp Edge.
  - Replacement: the Sentry remediation text names the in-flight-apply case.
  - This overrides a CTO required change. It is recorded as DC-2 in
    `specs/feat-one-shot-6612-sentry-terraform-drift/decision-challenges.md`, where `ship` surfaces it.
- **R2 (Mechanical): the 410 classifier is cut.** A single attempt means a 410 is never retried, and
  the apply already classifies 410s per address.
- **R3 (Mechanical): the `Refreshed N` line and the AC15 refresh floor are cut.** With a full root and
  no `-target`, exit 0 already proves every declared resource is in state and refreshed. The line
  would also have edited all three legs' shared tail.
- **R4 (Mechanical; Kieran P1): AC15 greps executed lines only.** The job log echoes the unexpanded
  script, so a bare `sentry_iac_token_absent` would match on every clean run. Job and check-in
  conclusions were dropped as evidence (Kieran P2).
- **R5 (Mechanical; Kieran P1): T3 anchored.** Its substring `grep -qF "- apps/web-platform/infra"`
  was satisfied by the new `…/infra/sentry` entry, which would have hidden a deleted main-root entry.
- **R6 (Mechanical; DHH P1): the remediation command carries `-f reason=`.** `workflow_dispatch`
  requires that input.
- **R7 (Mechanical; DHH P2): the email snippet strips refresh lines.** Otherwise the `[ERROR]` email,
  which is this leg's reliable error channel, showed only refresh noise.
- **R8 (Mechanical): the token check is simplified.** Guard 2's multi-location census became S2's
  whole-file count plus key path (simplicity F6).
- **R9 (Mechanical): suite cuts and corrections.**
  - Cut: H2 (a brittle text transform), B6 (merged into B5), and the arbitrary floor of 35.
  - The suite runs under `bash -e`, not `-eo pipefail`, which is what Actions actually uses (Kieran).
  - AC13 now uses `--numstat` (Kieran).
  - AC-PM1 now polls, avoids the ±30 min cron windows, and accepts manual or scheduled runs (Kieran).
  - `discoverability_test.expected_output` was corrected (Kieran).
- **R10 (Mechanical): the C4 edit and the `likec4.json` regeneration are cut.** The edge already names
  the emitter and the credential. "No C4 impact" is backed by the enumeration plus a green
  `c4-count-parity`.
- **R11 (Mechanical): documentation trimmed.** The ADR amendment is about 12 lines, and the sibling
  header gets a short complementarity note instead of a full rewrite.
- **Kept against the simplification panel:**
  - R1–R4 real-terraform arms: the brief explicitly asks for a local/fixture plan proving detection, and
    dropping operator-requested scope is never Mechanical.
  - The empty-secret guard (CTO required).
  - The inline `SENTRY_AUTH_TOKEN=` prefix instead of step-env `SENTRY_AUTH_TOKEN` (simplicity F4).
    CTO and Kieran both judge the prefix load-bearing, because the Tier-B loader exports every key into
    `$GITHUB_ENV`. It also avoids setting `SENTRY_AUTH_TOKEN=''` on the other two legs.
  - S5.
- **Advisor alternatives (per-leg matrix data, or a Terraform-variable token through Doppler):** see
  Alternatives.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain` into env (the brief's wording) | This is not what the apply does, and it contradicts ADR-031 §Authentication. It would add a Doppler read and a second copy of the token whose staleness would red this leg alone (DC-1). |
| `doppler run --preserve-env --name-transformer tf-var` plus a step-env `SENTRY_AUTH_TOKEN` | The transformer injects `TF_VAR_sentry_org`/`TF_VAR_sentry_project` from `prd_terraform`. The apply never sees that variable surface, so this risks phantom drift. |
| Token as a Terraform variable, `provider "sentry" { token = var.sentry_auth_token }`, fed through `doppler run` like the other legs (advisor) | Disqualified. `--name-transformer tf-var` maps Doppler `prd_terraform`'s **personal** `SENTRY_AUTH_TOKEN` to exactly `TF_VAR_sentry_auth_token` (#7797, #8090). It would also edit the root and its apply and move the token into Doppler, against ADR-031. |
| Matrix `include:` objects with a per-leg `plan_wrapper` (advisor) | Breaks the list-of-strings shape the step-order T3 greps, and runs the command through an unquoted `$PLAN_WRAPPER` word-split. The branch is confined anyway: the `else` arm is byte-identical and pinned by B5. |
| A 60 s re-plan debounce on non-zero (v1; CTO) | Measured not to cover the 1–8 min merge→apply window. Transient vendor errors already go to email, never to an issue (R1). |
| Re-plan on exit 1 only (advisor) | Exit 1 never files an issue, so this buys nothing. |
| Pre-plan check for an in-progress `apply-sentry-infra` run, skipping or annotating (DHH option) | Needs `actions: read` added to the workflow for a rare case. The remediation text covers the rare case instead. Revisit if a false-positive issue ever actually fires. |
| A shared `concurrency:` group with `apply-sentry-infra.yml` | GitHub keeps one pending run per group and cancels the older one, so a pending drift run could cancel a pending apply. |
| Derive the branch from the root (`grep jianyuan/sentry versions.tf`) | A main root that gained the Sentry provider would silently lose its Doppler variables. |
| A dedicated read-only Sentry integration for drift (CTO recommendation) | Needs a browser session to mint, and buys little. The apply's own `plan_pr` already runs the identical plan with this token, and the job holds stronger Tier-B credentials. |
| Prove detection with a live Sentry edit or a throwaway PR against the real root | Mutates production or adds noise PRs. AC11 (fixture), the cited run 35903124451 (real-root divergence) and AC15 (live clean plan) together cover the chain non-destructively. |
| A local real-root plan with a modified `.tf`, using credentials from Doppler's operator mirror | Reads secret values locally, which the guardrail forbids. It is also redundant with the above. |
| A follow-through tracker awaiting the next scheduled run | `soleur:trigger-cron` fires the same Inngest function now (AC-PM1). |
| An auto-close arm for `infra-drift` issues | Applies to every leg, so it is a separate concern. No #6612 capability is deferred. |

## Non-Goals

- Changing any `.tf` in the Sentry root, including the frozen rules `auth_per_user_loop` (566671) and
  `sandbox_startup_failure` (669246).
- These sibling issues and PRs: Sentry cron-monitor alert routing (#8630), the check-in composite
  (#3828), #6437, #8349, #8495, #7619, #3829, #6591, #7634, #7985, and #4781 / PR #8654.
- Revoking the personal Doppler `SENTRY_AUTH_TOKEN` (#8090).
- Preventing the `use_lockfile = false` race. This change detects it; it does not prevent it.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- **Never use `doppler run -c prd_terraform` for anything Sentry in this job.** It binds a personal
  token under `SENTRY_AUTH_TOKEN` (#7797, #8090). The Sentry arm must stay free of `doppler`, which the
  exit-97 stub enforces.
- **The inline `SENTRY_AUTH_TOKEN="$SENTRY_IAC_AUTH_TOKEN" terraform …` prefix is load-bearing.** The
  Tier-B loader exports every Tier-B key into `$GITHUB_ENV`, and the prefix overrides any ambient value
  (B7). If the loader exports a `TF_VAR_sentry_*`, it reaches the apply the same way, and that is the
  parity this plan wants.
- **The job log echoes the unexpanded `run:` script.** Any post-merge grep must target an executed line
  (an expanded `$STACK_NAME`, or a rendered `##[error]`), never a literal that also appears in the
  script (R4).
- **`terraform_wrapper: false` is load-bearing** for `-detailed-exitcode` (setup-terraform #152). S5
  pins it.
- **Actions runs a shell-less `run:` as `bash -e {0}`, without pipefail.** The existing `set +e` bracket
  must enclose the whole Sentry arm, or a plan exit 2 kills the step before `exit_code` is written. The
  suite mirrors `bash -e` exactly. A comment at ~L257 in the workflow claims `-eo pipefail`, which is
  wrong. Do not "fix" the suite to match that comment.
- **A plan landing between a merge and its apply** files an `infra-drift` issue that shows the merged
  blocks as `to add`. This is the accepted residual (R1). The Sentry remediation text says to check for
  a queued or in-progress apply first.
- **Three check-ins per run go to one monitor.** With `recovery_threshold = 1`, a Sentry-leg `error`
  followed by another leg's `ok` can resolve the monitor issue within the same run. The ops email is the
  reliable error channel. This is pre-existing multi-leg behaviour, and routing is #8630.
- **This PR's README edit triggers `apply-sentry-infra.yml`**: `plan_pr`, and then a 0-change apply
  after merge. That is intended (AC-B). AC-PM1 waits for that apply to finish before firing.
- The ADR-031 amendment is **append-only**. Do not edit the #6589 amendment's "3. No scheduled drift
  check covers this root" line or the `(follow-up)` Consequences bullet. The new block supersedes them
  by reference (AC13).
