---
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
closes: 7136
---

# Plan: the release-failure email step dies on an unbound `R_DEPLOY` before it can send

## Overview

`.github/workflows/web-platform-release.yml`, job `release-outcome`, step **"Email the
operator (release did NOT reach production)"** reads `${R_DEPLOY}` at line 1315. `R_DEPLOY`
is declared in the `env:` of a **different** step (`Classify the run outcome`, line 1240).
Step-level `env:` does not cross step boundaries, so the variable is unset here; the body
runs under `set -uo pipefail`, and bash terminates the shell on an unset expansion.

The step dies **before** the `curl` to Resend. No email is sent. Confirmed from the run log,
not inferred from the YAML:

```
release-outcome  Email the operator (release did NOT reach production)
  /home/runner/work/_temp/dbd591da-…sh: line 26: R_DEPLOY: unbound variable
  ##[error]Process completed with exit code 1.
```

The bare `${R_DEPLOY}` was introduced by commit `3faa95fa8` (PR #7097). It has never
successfully evaluated — **this alert path has never once delivered.**

### The failure is silent by construction

The downstream **"Mirror non-delivery to Sentry and fail loudly"** step is gated on
`steps.email.outputs.delivered != '1'`. The email step died before writing *any* output, so
`delivered` is empty — the condition is true, yet the run log shows that step **`skipped`**.
Verified on run 30703438860:

| step | conclusion |
|---|---|
| Classify the run outcome | success |
| Email the operator (release did NOT reach production) | **failure** |
| Mirror non-delivery to Sentry and fail loudly | **skipped** |

A step whose predecessor *failed* does not run without `if: always()` / `failure()`. So the
compensating path — the one designed to guarantee "neither can end in silence" — was itself
disarmed by the same crash. Both alert channels are dead simultaneously.

### Blast radius

Every `Web Platform Release` run on `main` has failed `deploy` (`reason=image_pull_failed`)
since ~2026-07-30. On the three most recent, `release-outcome` also failed:

| Run | Date | `deploy` | `release-outcome` |
|---|---|---|---|
| 30703438860 | 2026-08-01 14:16 | failure | failure |
| 30688451384 | 2026-08-01 06:48 | failure | failure |
| 30650563981 | 2026-07-31 17:17 | failure | failure |

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| `R_DEPLOY` unbound kills the step | Confirmed verbatim in the run log | Fix as described |
| Step runs under `bash -e` with nounset | It is `set -uo pipefail` — **no** `-e`. Irrelevant to the outcome: `set -u` alone terminates a non-interactive shell on unset expansion | No change to the fix |
| Sentry mirror "does not compensate" because it reads `delivered=0` | Stronger than stated: the mirror step is **`skipped`**, not mis-fed — it lacks `if: always()` | Add `!cancelled()` to the mirror's `if:` so a future crash in the email step still mirrors |
| shellcheck/actionlint should catch this | It cannot. shellcheck's SC2154 deliberately exempts `ALL_CAPS` names as presumed-environment, and it has no view of the workflow's `env:` blocks. Measured: `shellcheck -s bash` on the extracted step body reports **zero** findings | Build a workflow-aware linter; do not tune actionlint |
| "at least the last three failed releases" went unnotified | Confirmed, and the step has in fact **never** delivered: the bare `${R_DEPLOY}` arrived with the branch itself in commit `3faa95fa8` (PR #7097) | Framing in the PR body corrected from "regressed" to "never worked" |

## Second defect in the same step (found while reading the branch)

The `else` (deploy-did-not-succeed) branch and the shared tail are mis-scoped. These three
lines sit **inside** the `else` block:

```
BODY="${BODY}<p>Attempted version: …"
BODY="${BODY}<p><strong>What stopped:</strong></p><ul>${FAILED_HTML}</ul>"
BODY="${BODY}<p><a href=\"${RUN_URL}\">Open the failed run</a> …"
```

So in the `R_DEPLOY == success` branch the email contains **no run link and no list of what
failed** — while the unconditional tail tells the operator *"Send the run link above to your
engineer."* That branch has never executed in production (the step always died first), so the
defect is unobserved rather than absent. In scope: it is the same step, the same never-run
branch, and shipping the `R_DEPLOY` fix is exactly what makes this branch reachable for the
first time.

## User-Brand Impact

**If this lands broken, the user experiences:** production silently stops taking new builds
while every surface reports healthy. The operator merges work for days believing it is live.
This already happened — the outage began ~2026-07-30 and no notification was ever sent.

**If this leaks, the user's workflow is exposed via:** no new exposure vector; the email body
carries version/tag/job-name metadata already public in the repo's Actions log. The change
adds no new recipient and no new secret read.

**Brand-survival threshold:** single-user incident. There is exactly one operator on this
alert path; one undelivered email is a total loss of the signal, not a degraded one.

## Observability

```yaml
liveness_signal:
  what: release-outcome emits `SOLEUR_RELEASE_ALERT` to the step summary and stdout on every
        run where any upstream job failed, carrying delivered=0|1 and the chosen branch
  cadence: every Web Platform Release run that has a failed/cancelled upstream job
  alert_target: ops@jikigai.com via Resend; Sentry `op:release-alert-undelivered` on non-delivery
  configured_in: .github/workflows/web-platform-release.yml (job release-outcome)
error_reporting:
  destination: Sentry (store endpoint, DSN from GitHub secret — a different vendor than Resend)
  fail_loud: yes — the mirror step exits 1, turning the run red on non-delivery
failure_modes:
  - mode: a variable the step reads is not declared in its own env: (this bug)
    detection: scripts/lint-workflow-step-env-refs.py, run in CI on every PR
    alert_route: CI job fails on the PR that introduces it — before it can reach main
  - mode: email step crashes for any other reason before writing outputs
    detection: mirror step gains `!cancelled()`, so it runs even when the email step failed
    alert_route: Sentry op:release-alert-undelivered + red run
  - mode: Resend rejects or is unreachable
    detection: HTTP code captured; delivered=0 with reason=resend_http_<code>
    alert_route: Sentry op:release-alert-undelivered + red run
logs:
  where: GitHub Actions run log + job summary for the run
  retention: GitHub default (90 days)
discoverability_test:
  command: bash scripts/lint-workflow-step-env-refs.test.sh
  expected_output: "All tests passed" — includes a live execution of the shipped step body
                   under both R_DEPLOY branches, asserting no unbound-variable death
```

No `ssh` anywhere in the verification path.

## Implementation Phases

### Phase 1 — Fix the workflow

1. Add `R_DEPLOY: ${{ needs.deploy.result }}` to the email step's **own** `env:` block.
2. Change the reference to `${R_DEPLOY:-}` so it matches every sibling expansion
   (`${VERSION:-unknown}`, `${TAG:-no tag was created}`, `${RESEND_API_KEY:-}`,
   `${REASON:-unknown}`). An unset value then takes the **"production was NOT updated"**
   branch — the safe direction: it over-warns rather than falsely reassuring.
3. Audit every other variable the step reads against its declared `env:` (mechanised by
   Phase 2's linter, which is the durable form of this audit).
4. Hoist the run link and the "What stopped" list out of the `else` branch so both branches
   carry the link the unconditional tail refers to.
5. Add `!cancelled()` to the mirror step's `if:` so it survives an email-step crash.

### Phase 2 — The linter (`scripts/lint-workflow-step-env-refs.py`)

Fail-closed check: for every `run:` step in `.github/workflows/*.yml`, every **`ALL_CAPS`
shell variable reference that is never guarded anywhere in that step** must be declared in
the step / job / workflow `env:`, assigned within the same step, exported to `$GITHUB_ENV`
by an earlier step of the same job, or runner-provided.

Discriminators required to reach zero false positives (each measured against the 70 workflow
files on `main`, not assumed):

| Rule | Without it |
|---|---|
| Strip `${{ … }}` before shell parsing | GitHub expressions parse as shell vars |
| Strip single-quoted regions and `\$` escapes via a quote-state lexer | 6 false positives — literal `$VAR` text in error strings, SQL, and markdown |
| A name guarded **anywhere** in the step is exempt | 16 false positives — the `[[ -n "${X:-}" ]] \|\| exit 1` then bare `${X}` idiom |
| Carry `$GITHUB_ENV` writes forward within a job | 41 false positives — the standard cross-step export |
| Restrict to `ALL_CAPS` | ~977 false positives — jq `--arg` names and lowercase locals (shellcheck's SC2154 domain) |

Measured result on `main`: **exactly one finding — the `R_DEPLOY` bug.** No allowlist, no
highwater baseline; the gate is fail-closed from the first commit.

The linter must **fail loudly when it scans zero files** rather than reporting a clean sweep
of nothing — the silent-empty shape `scripts/lint-workflows.sh` already guards against, and
which bit twice while developing this plan (a stale CWD produced `TOTAL: 0`, indistinguishable
from success).

### Phase 3 — Tests and registration

`scripts/lint-workflow-step-env-refs.test.sh`, registered in `scripts/test-all.sh` (required
— `scripts/lint-orphan-test-suites.sh` fails any unregistered `scripts/*.test.sh`) and wired
into the CI lint job.

Two test classes:

1. **Linter unit tests** over synthetic fixtures: catches the bug shape; exempts each of the
   five discriminators above; fails closed on zero files scanned.
2. **Execution test against the shipped YAML** — extract the real email step's `run` body from
   `web-platform-release.yml`, execute it under `bash` with exactly its declared `env:`, with
   `curl`/`jq` stubbed, for `deploy=failure` and `deploy=success`. Assert: no unbound-variable
   death, and the correct subject/branch for each. This is the acceptance criterion's
   "verified against a forced-failure run" — it runs the shipped text under the failure
   condition on every CI run, which a one-off dispatch would not.

## Acceptance Criteria

- [ ] The email step declares every variable it reads in its own `env:`.
- [ ] `${R_DEPLOY:-}` is guarded like its siblings; an unset value takes the "not updated" branch.
- [ ] A test asserts the step's referenced variables are a subset of its declared `env:` keys,
      and fails on the pre-fix YAML.
- [ ] Verified by executing the shipped step body under both branches, not only by reading YAML.
- [ ] The linter reports zero findings across `.github/workflows/*.yml` after the fix.
- [ ] The linter exits non-zero when it scans zero files.
- [ ] The mirror-to-Sentry step runs even when the email step fails outright.
- [ ] Both email branches contain the run link the message tells the operator to send.

## Test Scenarios

1. `python3 scripts/lint-workflow-step-env-refs.py` → exit 0, "0 findings", on the fixed tree.
2. Same linter against the pre-fix step (fixture) → exit 1, naming `R_DEPLOY` and the step.
3. Shipped-body execution, `R_DEPLOY=failure` → subject contains "production was NOT updated";
   body contains the run URL and the failed-jobs list.
4. Shipped-body execution, `R_DEPLOY=success` → subject contains "production WAS updated";
   body contains the run URL.
5. Shipped-body execution, `R_DEPLOY` **absent from the environment entirely** → does not die;
   takes the "NOT updated" branch.
6. Linter run against an empty directory → exit non-zero.

## Risks

- **Linter false positives on future workflows.** Mitigated by the five measured
  discriminators and by an exemption that is already idiomatic in this repo (`${X:-}`
  anywhere in the step). A genuinely new pattern fails the PR that introduces it, which is
  the intended direction of the gate.
- **Quote-state lexer mis-tracking inside an unquoted heredoc** could under-report
  (false negative). Accepted: the gate is additive over today's zero coverage, and
  under-reporting cannot break a passing build.
- **Scope.** The email-body hoist is a content change to a never-executed branch. It ships
  with the fix that first makes that branch reachable; it is not deferred to a second PR.
