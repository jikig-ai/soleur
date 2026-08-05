---
title: "Fix: the prod version-drift alerter goes dark on exactly the two verdicts it exists to alert on"
date: 2026-08-06
type: bug-fix
issue: 7304
branch: feat-one-shot-7304-drift-alerter-errexit
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

# Fix: the prod version-drift alerter goes dark on exactly the two verdicts it exists to alert on

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Enhancement Summary

**Deepened on:** 2026-08-06
**Panel:** architecture-strategist, code-simplicity-reviewer, spec-flow-analyzer,
test-design-reviewer, user-impact-reviewer, plus two claim-verification passes and a linter
prototype run over all 697 `run:` bodies.

### Key improvements

1. **A SECOND, distinct live defect found and added as Phase 1b — the empty-string coercion
   fail-open.** GitHub coerces `''` and `'0'` both to number 0, so on a dead tick the *closer* step
   ("the checker is evaluating again") **runs** while its exact logical complement is skipped —
   verified live in run `31054501973`'s step conclusions. The workflow auto-closes the issue
   reporting its own breakage, with an empty verdict. **`set +e` does not fix this**, and the first
   draft's Scope Limits actively forbade fixing it.
2. **The Phase 4 linter rule was rewritten — the first draft would have caught 2 of 17 sites.** A
   prototype proved it: 9 of the 17 confirmed sites are *bare commands* (`terraform plan …` +
   `rc=$?`), not command-substitution assignments. The rule now anchors on the **`$?` /
   `${PIPESTATUS[n]}` read** and looks backwards. Independently confirmed by two reviewers.
3. **Three acceptance criteria were unsatisfiable as written** and are now measured and executable:
   AC5 (counted its own prescribed comment prose → returned 14, not 7), AC16 (its glob matched the
   repo's *already-corrected* exemplar, so it could only reach 0 by mutilating the one correct doc
   in the tree), and AC6 (forbade two comment fixes the same plan mandates).
4. **Mandatory pre-fix calibration added** — the gate must report **17 on `origin/main`** and **0 on
   the fixed tree**. Without it, Phase 4 authors the linter after Phase 3 has erased all evidence,
   which is exactly how the 2-of-17 rule would have shipped reading as full coverage.
5. **Narrow brackets, not top-of-body `set +e`**, at `scheduled-inngest-health.yml` (121-line body
   driving an automated prod restart) and `infra-validation.yml` — plus `set -u` removed there as an
   unbudgeted new abort condition.

### New considerations discovered

- The safety claim **holds at 9/9** terraform sites (every handler ends `exit $rc`) — verified
  independently three times. `set +e` there is strictly better than today.
- `infra-validation.yml` was **mis-analysed in the safe direction**: its guard is fail-closed on
  empty today, so nothing is silently swallowed; what is lost is the sticky PR-comment content.
- Two more false-premise comments sit **inside the headline file** (L248, L560) — L560 is the stated
  rationale for the Sentry heartbeat expression and was simply wrong until this fix.
- `B15` survives despite a cut recommendation: the linter's `$?` conjunct can **never** fire on the
  two `jq -n` bodies, so B15 is the only thing guarding them.
- `ci/prod-version-drift` does not exist as a label yet — it is bootstrapped lazily by the step the
  bug has always prevented from running.

## Overview

`.github/workflows/scheduled-prod-version-drift.yml` has failed on **8 of the last 8 scheduled
runs** (verified live: runs `31054501973` … `30992678866`, all `conclusion: failure`), emitting no
diagnostic output at all.

GitHub invokes a `run:` step with no `shell:` key as `/usr/bin/bash -e {0}` — **errexit is already
on**. The step body opens with `set -uo pipefail`, which only *adds* flags and does **not** clear
`-e`. So at:

```bash
out="$(bash scripts/prod-version-drift-check.sh 2>&1)"; rc=$?
```

a non-zero command substitution aborts the shell **at that line**: `rc=$?` never runs, `$out` is
never echoed, and every downstream branch (verdict parse, `$GITHUB_OUTPUT` write, issue filing,
email, Sentry check-in gating) is unreachable.

The checker's contract makes this maximally perverse — errexit kills **exactly the two alerting
verdicts** and lets the quiet ones through:

| exit | verdict | intent | under inherited `-e` |
|---|---|---|---|
| 0 | `CLEAN` | no alert | ✅ works |
| 0 | `DRIFT_PENDING` | no alert | ✅ works |
| 1 | `DRIFT_SUSTAINED` | **ALERT** | ❌ step dies, silent |
| 2 | `CHECK_ERROR` | **ALERT** | ❌ step dies, silent |

The alarm is silent when there is nothing to say and dark precisely when production has sustained
drift or the check itself broke. The workflow's own inline comment already declares the intent the
implementation fails to achieve: *"The checker's exit code is DATA, not a job failure."*

### This is the sixth occurrence of a class that prose has already failed to stop

| # | Site | Fixed | Enforcement added |
|---|---|---|---|
| 1 | `reusable-release.yml` token-preflight | earlier | in-workflow comment |
| 2 | `apply-web-platform-infra.yml` GHCR restore | earlier | in-workflow comment |
| 3 | `git-data-rung2-rehearsal.yml` capture poll | #7025 / 2026-07-30 | in-workflow comment |
| 4 | `scheduled-supabase-advisor-scan.yml` | 2026-07-30 (Phase 3) | in-workflow comment |
| 5 | `follow-through-closure-guard.yml` | 2026-07-30 (Phase 3) | in-workflow comment |
| 6 | **`scheduled-prod-version-drift.yml`** | **this plan** | **mechanical gate** |

`scheduled-zot-restart-loop.yml`'s own comment says of #3: *"This is the same defect, and the same
fix, that reusable-release.yml documents at its token-preflight step; it was applied there and
missed here."* And the 2026-07-30 plan
(`knowledge-base/project/plans/2026-07-30-fix-rung2-capture-poll-errexit-plan.md`, Phase 4 item 3)
states plainly:

> The repo already carries **four learnings** on this rule … plus **five in-workflow comments** —
> and it still recurred.

That plan responded by fixing siblings by hand and appending to a learning. **It built no
mechanical gate.** Six days later the class recurred here, on the repo's production-staleness
alarm. Four learnings + six in-workflow comments + two manual sweeps is the complete set of
interventions already tried, and the measured result is recurrence. A repo-wide detector is
therefore not gold-plating — it is the only intervention **not yet tried**, and it is the argument
`scripts/lint-workflow-step-env-refs.py` already makes in its own docstring:

> This class is invisible until the failure path runs, which is exactly when it must work. That is
> what makes it worth a dedicated gate rather than a code-review habit.

## Measured evidence

### Root-cause reproduction (local, deterministic)

```console
$ bash -e -c 'set -uo pipefail; case "$-" in *e*) echo "errexit STILL ON";; esac'
errexit STILL ON

$ bash -e -c 'set -uo pipefail; out="$(bash -c "echo hi; exit 1" 2>&1)"; rc=$?; echo "REACHED rc=$rc"'; echo "shell_rc=$?"
shell_rc=1          # REACHED never prints — byte-for-byte the CI symptom

$ bash -e -c 'set -uo pipefail; set +e; out="$(bash -c "echo hi; exit 1" 2>&1)"; rc=$?; echo "REACHED rc=$rc out=$out"'
REACHED rc=1 out=hi
```

### End-to-end proof against the SHIPPED step body (both directions)

The real `check` step body was extracted from the workflow via PyYAML and run under `bash -e`
(GitHub's actual invocation) in a sandbox with the checker stubbed to a chosen exit code:

| body | stub exit | step exit | stdout lines | `drift\|` lines | `::error::` | `$GITHUB_OUTPUT` |
|---|---|---|---|---|---|---|
| **current** | 1 (`DRIFT_SUSTAINED`) | **1** | **0** | **0** | **0** | **EMPTY** |
| **current** | 0 (`CLEAN`) | 0 | 7 | 7 | 0 | full, `exit_code=0` |
| fixed (`set +e`) | 1 (`DRIFT_SUSTAINED`) | 0 | 8 | 7 | 1 | full, `exit_code=1` |
| fixed (`set +e`) | 2 (`CHECK_ERROR`) | 0 | 8 | 7 | 1 | full, `exit_code=2` |
| fixed (`set +e`) | 0 (`CLEAN`) | 0 | 7 | 7 | 0 | full, `exit_code=0` |

**Row 2 is the load-bearing row.** The CLEAN path passes *unchanged* against the broken body. A fix
verified only on exit 0 would look green while changing nothing — the exact trap #7304 warns about.
Every acceptance criterion below is therefore paired: an exit-1/exit-2 arm **and** an exit-0 arm,
with the unfixed body required to FAIL the exit-1 arm (Part C mutation axis).

### The defect is not confined to line 106 — 5 of 7 steps in this workflow carry it

Machine audit of every `run:` step in the workflow (no `shell:` key anywhere, no `set +e` anywhere):

| step `id` | name | explicit `rc` capture | status |
|---|---|---|---|
| `check` | Check production version drift | `rc=$?` *(same line as capture)* | **firing today** |
| `issue` | File or update the drift issue | `list_rc=$?` | latent |
| `notify` | Email ops on first detection | — | latent (`jq -n`) |
| `issue_error` | File or update the check-error issue | `list_rc=$?` | latent |
| `notify_error` | Email ops when the check cannot evaluate | — | latent (`jq -n`) |
| *(unnamed)* | Close the drift issue when production is CLEAN | `list_rc=$?` | latent |
| *(unnamed)* | Close the check-error issue … | `list_rc=$?` | latent |

The four `list_rc=$?` sites are **dead code today**. Each is followed by
`if [[ "$list_rc" -ne 0 ]]; then … "A FAILED LOOKUP IS NOT 'NOTHING FOUND'" …` — error handling the
author deliberately wrote, which inherited errexit silently deletes. Fixing only line 106 would
leave four documented safety branches unreachable.

Lexer note for the gate: `check`'s capture is `out="$(…)"; rc=$?` — the `$?` read is **same-line,
semicolon-separated**. A detector that only inspects the *next* line misses the canonical instance.

### Repo-wide sweep — 17 CONFIRMED sites across 7 files

All **697 `run:` bodies across 78 files** (71 workflows + 7 composite actions) were extracted and
evaluated **per step body**, tracking `set +e`/`set -e` linearly, walking `\` continuations, and
excluding heredocs and `if`/`until` conditions. **No `shell:` key anywhere in the tree clears
`-e`**: every `shell:` key and all three `defaults: run:` blocks are plain `shell: bash`, which maps
to `bash --noprofile --norc -eo pipefail {0}` and does **not** clear errexit. *(Bodies that clear it
with an explicit `set +e` statement do exist — ~45 of them across 20 workflows. The claim is about
`shell:` keys, and is stated that way deliberately: a linter author reading a broader claim would
build the wrong rule.)*

| File | Sites | Failure mode |
|---|---|---|
| `scheduled-prod-version-drift.yml` | 5 (L106, 212, 350, 476, 516) | **the outage** — alarm 100% silent on drift |
| `scheduled-cron-artifact-age.yml` | 1 (L80) | identical topology; reporting step gates `if: steps.age.outputs.rc != '0'` with no `always()`, so an aborted step skips it — **silent stale-cron alarm** |
| `scheduled-inngest-health.yml` | 1 (L220-229) | `curl_rc` handling dead → `pool_probe_unavailable` misclassification |
| `infra-validation.yml` | 1 (L1280) | **no `set` line at all** + `continue-on-error: true` → abort swallowed silently, outputs never written |
| `apply-github-infra.yml` | 1 (L245) | `::error::` dead; comment asserts a **false premise** |
| `apply-sentry-infra.yml` | 2 (L282, L592) | same; L579-583 repeats the false premise |
| `apply-web-platform-infra.yml` | 6 (L1183, 1331, 1516, 1740, 2456, 3065) | `::error::` annotations dead on prod-infra plans |

**Measured safety finding that reverses the obvious concern.** Every one of the 9 `terraform plan`
sites already ends its handler with `exit $rc`:

```bash
terraform plan -no-color -input=false -out=tfplan
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "::error::terraform plan failed (exit $rc)"
  exit $rc          # ← already terminates
fi
set -e              # ← the re-arm PROVES the author believed -e was off
```

So adding `set +e` there **cannot** turn a failed prod `terraform plan` green: the job still fails,
it merely now also emits the `::error::` that is currently dead code. Strictly better. The trailing
`set -e` re-arm with no matching `set +e` is itself the proof of intent — the author wrote the
second half of a bracket whose first half was never there.

Three of these sites carry a comment asserting *"`-e` is intentionally omitted so we can capture
terraform plan's exit code"*. `-e` was never omitted; it is inherited. **The comment must be
corrected, not just the code** — a false premise left in place is how this class propagates into
the next step someone copies.

## Research Reconciliation — issue claims vs. codebase

| Claim (#7304) | Reality | Plan response |
|---|---|---|
| Fails every run, no output | **TRUE** — 8/8 `failure`; reproduced end-to-end | Accepted |
| Root cause is L106 + inherited `-e` | **TRUE**, verified 3 ways | Accepted |
| Contract 0=CLEAN/PENDING, 1=SUSTAINED, 2=CHECK_ERROR | **TRUE** — checker header L49-52 + `classify_drift` returns | Accepted |
| Fix: `set +e` around the capture | **Correct but under-scoped** — 4 further steps in the same file carry the shape with already-dead `list_rc` handling | Widened to all 7 bodies |
| "Worth checking the sibling scheduled workflows" | **TRUE and larger than a check** — 17 confirmed sites / 7 files; 6th occurrence | Fixed inline (Phase 3) **and** a mechanical gate (Phase 4) |
| Verify both directions | **Essential** — measured: CLEAN passes unchanged against the broken body | Every AC paired; Part C axis requires the unfixed body RED |
| *(implicit)* `set +e` on terraform steps might mask failures | **FALSE, measured** — every handler already `exit $rc`s | Fix is safe; AC pins it |

**Premise validation (Phase 0.6).** `#7304` is `OPEN`, unlabeled, `closedByPullRequestsReferences`
empty — not stale. All cited artifacts verified present. Cited siblings #7247/#7267 (zot outage)
are context only. **ADR-corpus grep for the proposed mechanism** (`errexit`, `set -e`, `set +e`,
shell contract) returned 11 ADRs; none decides the workflow-step shell contract and none rejects a
lint gate for it. The closest, **ADR-166**, *establishes the precedent* that a recurring
operator-facing CI defect class earns a `scripts/lint-*` gate + optional `.highwater` registered in
`test-all.sh`. This plan follows that shape rather than diverging from it.

**Network-outage gate (Phase 1.4).** The trigger scan is a case-insensitive substring match and
fires on *"unreachable"* in the phrase *"every downstream branch is unreachable"*. That is lexical,
not semantic: there is no SSH, DNS, firewall or connectivity symptom, and the root cause is
deterministically reproduced locally in one shell command. The L3→L7 checklist is **N/A**; no
firewall/egress hypothesis is carried.

## User-Brand Impact

**If this lands broken, the user experiences:** production silently serving an old build with no
alert — the site returns HTTP 200 and looks healthy while merged fixes never reach users. This is
the *exact* failure the workflow was built to eliminate (a 2026-07-30 incident left prod ~21h
stale, found only incidentally). The alarm is dark for that scenario today and has been for at
least a day. The `scheduled-cron-artifact-age` alarm is dark the same way.

**If this leaks, the user's data / workflow / money is exposed via:** no new exposure vector. This
change adds no data flow, no store, no endpoint, no credential. The pre-existing surface (the
checker echoing a charset-restricted, length-bounded `build_sha` from untrusted `/health` into an
issue body) is unchanged and remains bounded at the source.

**Brand-survival threshold:** `single-user incident` — the operator is a single non-technical
founder; one undetected stale-prod window means their merged fixes are not live and nothing tells
them. `user-impact-reviewer` is invoked at review time; CPO sign-off required at plan time.

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (COO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The fix is two characters of shell per step and carries essentially no
implementation risk — now confirmed by measurement for the terraform sites, where the handlers
already terminate. The architectural question is enforcement, and the evidence is unusually
decisive: six occurrences, four learnings, six in-workflow comments, two hand sweeps, recurrence
six days after the last sweep. Documentation-only enforcement of a shell-semantics invariant is
measurably not working. A repo-wide detector modelled on the existing
`lint-workflow-step-env-refs.py` — same file family, same registration path, same fail-closed
posture, no new dependency — is proportionate. Because Phase 3 drives the confirmed count to 0, the
gate should ship **without** a `.highwater`; a gate that ships at 0 with no baseline is strictly
stronger than one carrying debt. Correcting the three false-premise comments matters as much as the
code: those comments are the propagation vector.

### Operations (COO)

**Status:** reviewed
**Assessment:** This is a live production-observability outage, not a latent defect, and it is
**two** dark alarms (drift + cron-artifact-age), not one. Remediation must restore both on the
merge that lands, and the post-merge criterion must be a real observed run reaching a verdict — not
a green CI, which the broken workflow could also produce on a CLEAN tick. Operational subtlety:
because releases have been blocked (#7247/#7267), the first live run after merge may legitimately
report `DRIFT_SUSTAINED` and file a P0 issue + email. **That is the alarm working, not a
regression** — the acceptance criteria must say so explicitly, or the operator will be told a
successful fix is a new failure.

### Product/UX Gate

Not applicable. No file in `## Files to Create` / `## Files to Edit` matches any UI-surface term or
glob (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any `.pen` surface). The
mechanical UI-surface override does not fire. Product tier: **NONE**.

## GDPR / Compliance Gate (Phase 2.7)

**Skipped — no regulated-data surface.** No schema, migration, `.sql`, auth flow or API route is
touched. None of the four expansion triggers fire: (a) no LLM/external-API processing of
operator-derived data; (b) the `single-user incident` threshold is declared but no new processing
activity is introduced; (c) no new cron reads `learnings/` or `specs/`; (d) no new
artifact-distribution surface. The existing Resend email to `ops@jikigai.com` is unchanged in
recipient, content and lawful basis.

## Infrastructure (IaC) Gate (Phase 2.8)

**Reviewed and skipped — no new infrastructure.** No server, service unit, cron substrate, vendor
account, DNS record, TLS cert, secret, firewall rule or monitoring webhook is introduced. The
Sentry cron monitor (`sentry_cron_monitor` slug `scheduled-prod-version-drift`, already present at
`apps/web-platform/infra/sentry/cron-monitors.tf:1116`) is unchanged.

No operator-driven provisioning step is created: **every** post-merge criterion in this plan is
executed by the shipping agent via `gh`, not by a human. The plan edits `apply-*.yml` workflow
files, but strictly to add a shell flag and correct three comments — no Terraform resource, root,
variable, provider, backend or `-target=` set is added, removed or altered, and no remote host is
configured. `git diff` scoping is pinned by AC7.

## Encryption Posture Gate (Phase 2.11)

**Skipped.** No persistent store and no new cross-component connection is introduced. No `.tf`,
`supabase/migrations/*.sql`, `cloud-init*.yaml` or `docker-compose*.yaml` file is in scope.

## Architecture Decision (ADR/C4) Gate (Phase 2.10)

Detection **fires** on one clause: *"a new cross-cutting invariant every consumer must honor."*
Phase 4 introduces a repo-wide CI gate binding **every** workflow `run:` step in the repository,
present and future. Per ADR-166's precedent, that is an architectural decision and a deliverable of
**this** plan, not a follow-up.

### ADR

**Create `ADR-170 — a workflow `run:` step must clear inherited errexit before treating an exit
code as data`.**

- **Decision:** GitHub runs a `run:` step with no `shell:` key under `bash -e {0}`, and `shell: bash`
  does not change that. Any step that treats a command's exit code as *data* (capture-then-branch)
  MUST clear errexit explicitly (`set +e`) or protect every capture (`|| rc=$?`). `set -uo pipefail`
  is **not** a substitute and never has been. Enforced mechanically, not by comment.
- **Extends:** ADR-166 / principle **AP-021** (a CI-emitted operator-facing message may only name a
  cause the job measured). This is a **substantive** relation, not merely precedent for the gate's
  shape: with `steps.check` aborting, the heartbeat's first conjunct is false, so the Sentry monitor
  has been checking in `status=error` on all 8 runs. The operator therefore had a signal — a
  *low-fidelity, mis-attributed* one saying "the monitor is broken" when what was measured was
  drift. Worse, the Phase 1b coercion fail-open had the workflow posting *"the checker is evaluating
  again"* on dead ticks. Both are AP-021 violations, and this plan restores AP-021 compliance for
  this workflow. The step's own comment asserting `outcome` is failure "only on a runner-level
  death" was falsified by the errexit bug.
- **Register:** add row **AP-022** to
  `knowledge-base/engineering/architecture/principles-register.md` (enforcement tier `hook`,
  matching AP-021←ADR-166). Like ADR-166, `Enforced by:` must assert **blocking**, not advisory —
  the `scripts` shard feeds the aggregate `test` job, which is in the CI Required ruleset.
- **Alternatives Considered:** (a) `defaults.run.shell` override — rejected, see Phase 1;
  (b) documentation-only, the status quo through five prior occurrences — rejected on measured
  recurrence; (c) `shellcheck`/`actionlint` — rejected, measured: neither models the
  runner-injected `-e`, and `actionlint` already runs in this repo without catching any of the six.
- **Enforced by:** `scripts/lint-workflow-errexit-capture.py` +
  `scripts/lint-workflow-errexit-capture.test.sh`, registered in `scripts/test-all.sh`.

**The ordinal is provisional.** `origin/main`'s max ADR ordinal is **169** (verified against
`origin/main`, not the worktree; ordinal **167 is a pre-existing gap and must NOT be reused**).
`/ship`'s ADR-Ordinal Collision Gate re-verifies before merge. If it moves, sweep the whole feature
artifact set in the same edit — **use this command, not a `{plans,specs}/feat-…/` brace expansion**
(there is no `plans/feat-…/` directory; the plan is a dated file directly under `plans/`, so the
brace form exits 2 and sweeps nothing, silently missing the plan itself):

```bash
grep -rn 'ADR-170' \
  knowledge-base/project/plans/2026-08-06-fix-prod-version-drift-alerter-inherited-errexit-plan.md \
  knowledge-base/project/specs/feat-one-shot-7304-drift-alerter-errexit/ \
  knowledge-base/engineering/architecture/
```

The plan, `tasks.md`, the ADR body, the principles-register row, **and AC19/AC23** all name the
ordinal. (The first draft cited AC17/AC22 — wrong ACs, corrected at deepen time; a renumber
following it would have left two stale.)

### C4 views

**No C4 impact — enumeration performed by reading all three model files**
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), not a keyword
grep. Checked and found already modelled or out of scope:

- **External human actors:** none added or changed. The operator (alert recipient) already exists;
  their relationship to this alarm is unchanged — the alarm is being *repaired*, not rerouted.
- **External systems / vendors:** GitHub Actions, Resend, Sentry and `app.soleur.ai/health` are
  each already modelled as the drift alarm's edges. No vendor added or removed.
- **Containers / data stores:** none touched. No store added; the Sentry cron monitor already
  exists in `cron-monitors.tf`.
- **Actor↔surface access relationships:** unchanged. No ownership, tenancy or trust boundary moves.

The change is a shell-flag correction plus a CI lint gate; CI lint scripts are not modelled as C4
elements (verified — no existing `lint-*` script appears in any of the three files). A future
engineer reading only the ADRs + C4 would not be misled about the system after this ships.

### Sequencing

None — the decision is true the moment the gate lands. No soak, no `status: adopting`.

## Observability

```yaml
liveness_signal:
  what: Sentry cron check-in "scheduled-prod-version-drift" (existing sentry_cron_monitor,
        apps/web-platform/infra/sentry/cron-monitors.tf:1116) — reports whether the MONITOR ran,
        independently of whether prod is stale.
  cadence: every scheduled tick (cron "*/30"; measured delivery ~11 runs/day)
  alert_target: Sentry cron-monitor miss/error alert -> ops@jikigai.com
  configured_in: .github/workflows/scheduled-prod-version-drift.yml (final `sentry-heartbeat`
        step, if: always()) + apps/web-platform/infra/sentry/cron-monitors.tf

error_reporting:
  destination: (1) GitHub issue labelled ci/prod-version-drift + action-required;
               (2) Resend email to ops@jikigai.com; (3) Sentry cron check-in status=error.
               Channels 1 and 2 are deliberately INDEPENDENT (a dead issue step must not
               suppress the email).
  fail_loud: true — every failure arm emits an ::error:: annotation naming the channel that did
             NOT deliver (e.g. "the DRIFT verdict reached the email channel only").

failure_modes:
  - mode: Step aborts before writing $GITHUB_OUTPUT (THE BUG — inherited errexit)
    detection: Part B "B14" executes the SHIPPED step body under `bash -e` with the checker
               stubbed to exit 1 and 2, asserting exit_code/verdict/::error:: are produced.
               Part C axis11 deletes `set +e` and requires the suite to go RED.
    alert_route: CI red on the PR (scripts shard of test-all.sh) — before merge, not at 03:00.
  - mode: The same class recurs in ANY other workflow step, present or future
    detection: scripts/lint-workflow-errexit-capture.py, run live over .github/workflows/*.yml
               and .github/actions/*/action.yml in the `scripts` shard.
    alert_route: CI red on the PR that introduces it.
  - mode: Checker reaches no verdict (CHECK_ERROR / 127 / 126 / 124 / 139)
    detection: workflow steps `issue_error` + `notify_error`, gated exit_code != 0 && != 1
    alert_route: GitHub issue (p1-high) + email + Sentry status=error
  - mode: The alarm itself stops running (workflow disabled, wedged, repo-level failure)
    detection: Sentry cron monitor misses its check-in window
    alert_route: Sentry -> ops@jikigai.com

logs:
  where: GitHub Actions run log for scheduled-prod-version-drift (every checker line is
         greppable as `drift| `); Sentry cron-monitor check-in history.
  retention: GitHub Actions default (90 days); Sentry per-project retention.

discoverability_test:
  command: >-
    gh run list --workflow=scheduled-prod-version-drift.yml --limit 5
      --json conclusion,createdAt,databaseId
  expected_output: >-
    Recent runs with conclusion "success". On the CURRENT (broken) main this returns 8/8
    "failure" — so this command is also the pre-fix control reading. NO ssh.
```

### Soak Follow-Through Enrollment (Phase 2.9.1)

**Not required.** No acceptance criterion is time-gated: the post-merge criterion is *"the next
dispatched run reaches a verdict and writes `exit_code`"*, satisfiable on the first run after merge
and forceable immediately via `gh workflow run`. No `adopting → accepted` flip and no N-day window
is declared, so no `scripts/followthroughs/` probe and no `<!-- soleur:followthrough -->` directive
is enrolled.

### Affected-surface observability (Phase 2.9.2)

The failing surface is a GitHub Actions step, which is **not** a blind surface — its stdout is in
the run log and `$GITHUB_OUTPUT` is inspectable via `gh`. It *looked* blind precisely because of
this bug (the step died before emitting anything). The in-surface probe requirement is satisfied by
the B14 assertions, which execute the shipped body itself rather than a paraphrase, and whose
fields (`exit_code`, `verdict`, `drift|` line count, `::error::` presence) discriminate all three
verdict classes in a single run.

## Open Code-Review Overlap

**None.** Queried all 64 open `code-review` issues; zero bodies reference any file in this plan's
edit set.

## Scope Limits (hard)

1. **Do not touch `scripts/prod-version-drift-check.sh` logic.** The checker is correct; its exit
   codes are the contract. The permitted change there is none.
2. **Do not change any heartbeat expression, verdict semantics, threshold, pathspec, cron, or
   `permissions:` block.** Those are pinned by Parts B and C and are not this bug.
   **EXCEPTION (Phase 1b, mandatory):** the `if:` conditions that compare
   `steps.check.outputs.exit_code` against `'0'`/`'1'` MUST gain a
   `steps.check.outcome == 'success' &&` conjunct. This is the empty-string coercion fail-open
   documented below — it is a *distinct* defect from the errexit bug, it is live-armed today, and
   `set +e` does not disarm it. Without this carve-out the plan would forbid its own fix.
3. **In sibling files, change only the errexit bracket and the three false-premise comments.** No
   Terraform resource, `-target=` set, guard filter, or unrelated logic.
4. **Do not lower any `MIN_*` floor.** Floors ratchet up only.

## Files to Edit

| File | Change |
|---|---|
| `.github/workflows/scheduled-prod-version-drift.yml` | `set +e` in all **7** `run:` bodies + correct the false-premise comments at L248/L560 (Phase 1); add `steps.check.outcome == 'success' &&` to the six `exit_code` gates (Phase 1b) |
| `knowledge-base/engineering/architecture/principles-register.md` | Add the **AP-022** row (source ADR-170, enforcement tier `hook`, NFR link), mirroring AP-021←ADR-166. An ADR minting a blocking repo-wide gate with no register row leaves the register stale — it is what the architecture skill and future planners read. Next free id verified: AP-021 is the current max. |
| `scripts/prod-version-drift-check.test.sh` | Part B `B14` (both-direction execution) + `B15`; Part C `axis11`; raise `MIN_B`/`MIN_C`/`MIN_ASSERTIONS` (Phase 2) |
| `.github/workflows/scheduled-cron-artifact-age.yml` | `set +e` (L80 site) (Phase 3) |
| `.github/workflows/scheduled-inngest-health.yml` | `set +e` (L220-229 site) (Phase 3) |
| `.github/workflows/infra-validation.yml` | `set +e` (L1280 site; body has no `set` line at all) (Phase 3) |
| `.github/workflows/apply-github-infra.yml` | `set +e` (L245) **+ correct the false-premise comment** (Phase 3) |
| `.github/workflows/apply-sentry-infra.yml` | `set +e` (L282, L592) **+ correct the false-premise comment** (Phase 3) |
| `.github/workflows/apply-web-platform-infra.yml` | `set +e` ×6 (L1183, 1331, 1516, 1740, 2456, 3065) (Phase 3) |
| `scripts/test-all.sh` | Register the linter suite + live scan (Phase 4) |
| `knowledge-base/project/learnings/best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md` | Append the 6th occurrence + the gate (Phase 5) |

## Files to Create

| File | Purpose |
|---|---|
| `scripts/lint-workflow-errexit-capture.py` | Repo-wide detector (Phase 4) |
| `scripts/lint-workflow-errexit-capture.test.sh` | Its unit suite, incl. must-not-false-positive fixtures (Phase 4) |
| `knowledge-base/engineering/architecture/decisions/ADR-170-workflow-run-step-must-clear-inherited-errexit.md` | The decision (Phase 5) |
| `knowledge-base/project/specs/feat-one-shot-7304-drift-alerter-errexit/tasks.md` | The task breakdown **and** the full sweep inventory (17 confirmed + 13 latent). AC15 and Phase 3 both consume this file; the first draft named it as a consumer without ever producing it. The directory exists and is empty. |

**No `.highwater` file.** Phase 3 drives the confirmed count to 0, so the gate ships fail-closed
with no baseline — the `lint-workflow-step-env-refs.py` posture. If a site proves genuinely
un-fixable in-session, add the file with the ratchet-down-only header and a named reason per
carried hit; do **not** round the count up.

## Implementation Phases

Ordered by dependency, not by file. Phase 1 (contract change) precedes Phase 2 (its tests); Phase 4
authors the gate only after Phase 3 has driven the tree to 0, so the gate can ship with no baseline.

### Phase 1 — Fix the outage

For **each of the 7** `run:` bodies in `.github/workflows/scheduled-prod-version-drift.yml`, insert
immediately after the existing `set -uo pipefail`:

```bash
set -uo pipefail
# `set +e` is REQUIRED; `set -uo pipefail` is NOT a substitute. Actions runs a `run:` block with
# no `shell:` key under `bash -e {0}` — errexit is ALREADY ON and `set -uo pipefail` only ADDS
# flags. Without this, `out="$(…)"; rc=$?` aborts AT the capture on exactly the two verdicts that
# alert (1 = DRIFT_SUSTAINED, 2 = CHECK_ERROR), so rc, the run-log echo, $GITHUB_OUTPUT and every
# ::error:: below are dead code. Measured: 8/8 scheduled runs failed with zero output.
set +e
```

Comment the `check` step fully as above; the other six carry a one-line back-reference. Both
orderings (`set +e` before or after `set -uo pipefail`) are equivalent — neither `-u` nor
`-o pipefail` can re-enable `-e`; `apply-web-platform-infra.yml` uses the reverse order and is
equally correct. **Do not** place `set +e` between a pipeline and a `PIPESTATUS` read (the
`git-data-rung2-rehearsal.yml` ordering trap: `set` is a builtin, so bash resets `PIPESTATUS` after
it) — no such read exists in these bodies and none may be introduced.

**Also correct the two false-premise comments INSIDE this file** (found at deepen time; the first
draft of this plan corrected sibling files while leaving the propagation vector in the very
workflow whose outage it caused):

| line | current text | correction |
|---|---|---|
| **248** | *"this step runs `set -uo pipefail` with no -e, so an unchecked create falls through…"* | The premise is false — `-e` is inherited and was never cleared. Rewrite to say the `set +e` above is what makes it true, and keep the guard's actual rationale (an unchecked `create` must not fall through to a line asserting an issue exists). |
| **560** | *"with `exit 0` at the end of the body and no `-e`, that is 'failure' only on a runner-level death"* | Same premise, and it is the **heartbeat's** justification — the conjunct `steps.check.outcome == 'success'` only means what this comment claims once `set +e` is present. Rewrite to cite the `set +e` explicitly. |

These two are not cosmetic: comment 560 is the stated reasoning for the Sentry liveness expression,
and it was simply **wrong** until this fix. Leaving them is how occurrence #7 gets written.

**Alternatives considered and rejected:**

- **`defaults: run: shell: bash -uo pipefail {0}` at workflow level.** One line, fixes all steps
  and all future ones. **Rejected — the decisive reason is that it cannot express per-step intent.**
  The overwhelming majority of steps *should* keep errexit; clearing it workflow-wide silently
  removes fail-fast from every step that legitimately relies on it, converting one dark alarm into
  a workflow-wide hazard. Only the handful of steps that treat an exit code as *data* want it off.
  Secondary reasons: locality, greppability, and per-step lintability — and the repo has already
  voted for the bracket form (14 bracketed `set +e` statements in `apply-web-platform-infra.yml`,
  each with its own rationale comment).

  *(The first draft led with "Part B extracts and executes `run:` bodies, so a defaults-level fix is
  invisible to the tests." That reasoning is backwards and was demoted at deepen time: a harness
  that hard-codes `bash -e` while the workflow declares another shell is simply a wrong harness —
  an argument to fix the harness, not to reject a design. The B14b assertion now pins that premise
  explicitly rather than relying on it implicitly.)*
- **`|| rc=$?` on the capture only** (the `reusable-release.yml` / `scheduled-zot-restart-loop.yml`
  idiom). **Insufficient here:** it repairs L106 but leaves the four `list_rc` safety branches dead.
  It remains an acceptable alternative for a Phase 3 body containing a single capture.

### Phase 1b — Disarm the empty-string coercion fail-open (a SECOND, distinct defect)

**Found at deepen time and verified live against run `31054501973`. `set +e` does NOT fix this.**

When the `check` step aborts, `$GITHUB_OUTPUT` is never written, so `steps.check.outputs.exit_code`
is `''`. GitHub Actions expressions coerce operands of differing types **to number** — so `''` → 0
and `'0'` → 0, and **`'' == '0'` is TRUE**. The consequence on the dead tick, observed in the real
run's step conclusions:

| step | gate | dead-tick outcome |
|---|---|---|
| `File or update the check-error issue` (L325) | `exit_code != '0' && != '1'` | **skipped** |
| `Close the check-error issue once the checker can evaluate again` (L497) | `exit_code == '0' \|\| == '1'` | **success — IT RAN** |

Those two gates are exact logical complements over the same empty value, and the *closer* is the one
that fired. So on every dead tick the workflow executes the step that posts *"The version-drift
checker is evaluating again (verdict: ); drift is monitored once more"* — **auto-closing the very
issue that reports the checker is broken, with an empty verdict.** No such issue is open today only
because the filing step could never run either; the mechanism is armed, and it survives this plan's
errexit fix. Any future abort — OOM, job timeout, a `set -u` trip — reproduces it.

This is an **AP-021 / ADR-166 violation** in its own right: an operator-facing message naming a
recovery the job never measured.

**Fix.** Add a `steps.check.outcome == 'success' &&` conjunct to every `if:` that compares
`steps.check.outputs.exit_code` — L182, L271, L325, L402, L460, L497. The heartbeat at L565 already
leads with exactly this conjunct and is the in-file precedent; the comment there ("a step that dies
before writing its output leaves the output empty, and an output-only test reads that as a value
rather than as a death") is the rationale, already written, never applied to the six consumers.

**Pin it (B17).** Extend `PYEXTRACT` to emit the count of steps whose `if:` references
`steps.check.outputs.exit_code` **without** an `outcome == 'success'` conjunct; assert `0`. Add a
Part C `axis12` that strips one conjunct and requires RED labelled `B17`. Note this also means
`ALERT_STEPS_REACHABLE_WHEN_CLEAN` (B4) was never testing the empty case — B17 is what covers it.

### Phase 2 — Pin it, in BOTH directions

Extend `scripts/prod-version-drift-check.test.sh`. The harness already writes the `check` body to
`$DRIFT_STEP_BODY_OUT` (`$TMP/check-body.sh`) for execution (used today by B13) — B14 reuses that
hook; no new extraction machinery is needed.

**B14 — the capture reaches its consumers, executed rather than grepped.** For each stub exit code
in `{0, 1, 2}`: build a sandbox containing `scripts/prod-version-drift-check.sh` stubbed to emit a
full `DRIFT_*` output set and `exit <code>`; run the extracted body with `GITHUB_OUTPUT=<tmpfile>`
under **`bash -e`** — the runner's actual invocation. *Running it under a bare `bash` would make the
test pass against the broken body.*

| stub | assert |
|---|---|
| 1 | body exits 0; `exit_code=1` **and** `verdict=DRIFT_SUSTAINED`; `$GITHUB_OUTPUT` has exactly 8 lines; `drift\|` line count `== 7`; exactly one `::error::` matching `Production is serving a stale build` |
| 2 | body exits 0; `exit_code=2` **and** `verdict=CHECK_ERROR`; 8 output lines; `drift\|` `== 7`; exactly one `::error::` matching `could NOT be evaluated` |
| 0 | body exits 0; `exit_code=0`, `verdict=CLEAN`; 8 output lines; `drift\|` `== 7`; **zero** `::error::` |

Five implementation details, each a defect found at deepen time. Skipping any of them yields a test
that passes for the wrong reason:

1. **A FRESH `$GITHUB_OUTPUT` tmpfile per arm.** The body appends (`>> "$GITHUB_OUTPUT"`,
   workflow L169). A shared file means the exit-1 arm's `grep` finds `exit_code=0` left by a prior
   arm and passes for the wrong reason. Asserting **exactly 8 lines** catches both contamination
   and a partially-written output.
2. **Generate the stub's `DRIFT_*` key set from `$X_EXTRACTED_KEYS`** (already emitted by
   `PYEXTRACT`) or from the same `$SUT` scan B12 uses — do **not** hand-copy it. A hand-written stub
   becomes a *third* independent copy of the key contract (checker, workflow, stub); rename a key
   and B12 goes red while the stub silently rots.
3. **`drift| == 7`, not `≥ 7`, and comment WHY.** The count is stub-deterministic, so pinning costs
   no flake and discriminates more. Its only real power is 0-vs-7 ("did the echo loop run at all") —
   say so, or a later editor will "strengthen" it into a content assertion that duplicates B13.
4. **Add a self-check probe** immediately before the body runs:
   `bash -e -c 'set -uo pipefail; x="$(exit 1)"; echo REACHED'` must **not** print `REACHED`.
   Route the probe and the body through **one shared invocation variable** so they cannot diverge.
   This makes B14 self-diagnosing instead of silently depending on axis11.
5. **Emit a stub marker** (`DRIFT_REASON=STUB_MARKER_7304`) and assert it reaches `$GITHUB_OUTPUT` —
   proof the *stub* produced the result, not a stale real checker or an empty run.

**B14b — pin B14's own simulation premise: `STEPS_WITH_SHELL_KEY == 0`.** B14's fidelity claim
("`bash -e` is GitHub's actual invocation") is true *only because this workflow declares no `shell:`
key anywhere* — verified at deepen time: zero `shell:` keys, no `defaults: run:`. Nothing currently
pins it. If someone adds `shell: bash`, the real invocation becomes
`bash --noprofile --norc -eo pipefail {0}` and **B14 keeps passing while simulating a runner that no
longer exists.** Extend `PYEXTRACT` to emit the count of steps declaring `shell:` plus any
`defaults.run.shell`, and assert `0`. Three lines; the cheapest high-value assertion in the plan.

**B15 — every `run:` body in this workflow clears errexit.** Extend `PYEXTRACT` to emit the **count**
of step bodies lacking both a `set +e` and an errexit-clearing `shell:` key, computed over the
existing comment-stripping `code()` helper so **prose cannot satisfy the assertion**. Assert the
count `== 0`.

> **B15 is NOT redundant with the Phase 4 linter — do not delete it as "covered by the gate."**
> Record this rationale in a comment on the assertion itself. The linter fires only where a `$?`
> read proves the author expected to handle failure. The `notify` and `notify_error` bodies are
> `jq -n` steps with **no `$?` read**, so the linter can never fire on them. If a future edit drops
> `set +e` from `notify`, B15 is the only thing that catches it. **Assert the count (numerator),
> never the ratio `0 of 7`** — pinning the denominator makes adding a legitimate 8th step go red for
> a misleading reason.
>
> Honest residual: B15 asserts *presence*, not *position*. A `set +e` placed after a capture
> satisfies it. The linter is position-aware but only for bodies with a `$?` read — so a future body
> with a late clear and no `$?` read is caught by neither. Narrow, and stated rather than hidden.

**B16 — the `list_rc` branch is actually reachable (implements T5).** The plan's stated reason for
widening beyond line 106 is that four documented `list_rc` safety branches are dead code. Nothing
currently executes them. Extract the `issue` step body, stub `gh` on `PATH` to exit non-zero, run
under `bash -e`, and assert the `A FAILED LOOKUP IS NOT "NOTHING FOUND"` branch is reached (the
`::error::Could not query existing drift issues` annotation is emitted and
`first_detection=lookup_failed` is written). Without this, the plan *claims* coverage of the branches
that justify its own scope and implements none of it.

**Part C `axis11` — proves B14 is not vacuous.** Delete `set +e` from the `check` body in a sandbox
copy of the workflow, assert the mutation landed (`diff -q`), and require the child suite to go RED
**with an expected-FAIL label that is a literal prefix of B14's assertion description** — `fail()`
prints `  FAIL: $1` and `mutate_and_assert_red` greps for `FAIL: <label>`, so the label must match
the description's start, not be a free-text axis name.

> **axis11 MUST be a CODE-ONLY, line-based mutator, in the axis3 / axis9 shape.** The Phase 1
> comment block's first line contains the literal string `` `set +e` is REQUIRED ``. A naive
> `s.replace("set +e", "", 1)` therefore mutates the **comment**, `diff -q` reports the mutation
> "landed", the child stays GREEN, and the axis reports `SURVIVED` — while the artifact is correct.
> The harness already documents this exact trap twice (axis3 and axis9 both carry
> "MUTATES CODE ONLY, NEVER PROSE" warnings). Skip lines whose first non-space character is `#`.

**Floors.** Raise `MIN_B`, `MIN_C` and `MIN_ASSERTIONS` by exactly the number of assertions added
(`MIN_C` 11 → 12: one assertion per axis plus C0). **Also add a one-line check that
`MIN_ASSERTIONS == MIN_A + MIN_B + MIN_C`** — that equality is what makes the global floor non-slack
and it currently holds only by coincidence (117 = 57+49+11). Note in a comment that floors catch
*deletion*, not *collapse*: the `FAIL > 0` early exit precedes every floor check, so a B14 that
degrades to a single `fail` can never trip one. Finally, **record the Part C wall-clock delta** —
axis11 is the 12th child and every child re-runs Parts A+B, so B14's three sandbox builds are paid
12×; this harness has been burned by exactly that before.

### Phase 3 — The other 12 confirmed sites

Add the errexit bracket at each site from the sweep table. All are mechanical; the terraform
handlers already `exit $rc`, so no failure semantics change (measured — see Overview).

1. **`scheduled-cron-artifact-age.yml:80`** — same topology as the headline bug; its reporting step
   gates on `steps.age.outputs.rc != '0'` with no `always()`, so the abort skips it outright. This
   is a **second dark alarm**, not cosmetic.
2. **`scheduled-inngest-health.yml:220-229`** — revives the `curl_rc` branch so a probe blip is
   classified `pool_probe_unavailable` rather than misreported. **Bracket `set +e` … `set -e` around
   L220-229 only** — this site sits inside the `else` arm of a three-way conditional (L210-245), and
   a body-top `set +e` would disarm a large amount of surrounding classification logic. Note the
   capture spans a **multi-line** substitution (`response="$(curl \` at L220, `curl_rc=$?` nine
   lines later at L229) — the linter's continuation-walking must handle this, and it needs a fixture.
3. **`infra-validation.yml:1280`** — body has **no `set` line at all**. Add **`set +e` before L1280
   and `set -e` after L1283** — a bracket, matching the eight terraform siblings. Do **NOT** add
   `set -uo pipefail` here (the first draft did): `-u` is not an errexit change, it is a *new* abort
   condition on every unset-variable reference in a body that has never run under it, which Scope
   Limit 3 does not authorise.

   **Corrected risk analysis (the first draft got this wrong, in the safe direction).** The abort is
   *not* silently swallowed today. The step aborts → `exit_code` is never written → the downstream
   guard `if: steps.plan.outputs.exit_code != '0'` → `run: exit 1` at
   `infra-validation.yml:1320-1322` evaluates `'' != '0'` → **true** → the job already fails.
   A failed plan is caught today, by accident. What is actually lost is the **sticky PR comment
   content** (L1315 renders an empty plan and a blank exit code). Adding `set +e` cannot convert a
   hard failure into a silent pass here: it makes `exit_code` correct, and the guard is fail-closed
   on empty either way. The AC must name `infra-validation.yml:1320-1322` as the consumer it
   verifies, not a vague "downstream consumer".
4. **`apply-github-infra.yml:245`, `apply-sentry-infra.yml:282,592`** — add `set +e`, **and rewrite
   the false-premise comment** at `apply-github-infra.yml:240` and `apply-sentry-infra.yml:579`
   claiming *"`-e` is intentionally omitted so we can capture terraform plan's exit code"*. Replace
   with the measured truth: `-e` is inherited from the runner and `set -uo pipefail` does not clear
   it; the `set +e` below is what makes the capture work, and the trailing `set -e` re-arms it.

   **There are TWO such comments, not three** (corrected at deepen time). A third grep hit,
   `apply-web-platform-infra.yml:449`, is the **already-corrected** form —
   `# THIS COMMENT USED TO SAY "\`-e\` is intentionally omitted", AND THAT NEVER WORKED.` — and must
   be left alone. Any verification grep for this class MUST exclude the corrective sentence or it
   matches a file that needs no change (this is exactly what made the first draft of AC16
   unsatisfiable).
5. **`apply-web-platform-infra.yml`** ×6 — add `set +e` before each captured `terraform plan`.

Each edit adds a one-line comment naming the failure it prevents, not a restatement of the rule.

**Latent class (13 sites), triaged and consciously excluded.** These are assignments from a fallible
command guarded only by an emptiness check (`if [[ -z "$X" ]]`), with no `$?` read. Errexit kills
only the *non-zero-exit* half of the intended handling; the guard still fires for the
"exits 0 but yields nothing" case (e.g. `curl -sS` without `--fail` on an HTTP 401), so each retains
partial protection. The Phase 4 gate deliberately does **not** fire on them (see DIRECTION OF
ERROR). The full inventory goes in `tasks.md`, and **one** tracking issue is filed for a future
widening pass per `wg-when-deferring-a-capability-create-a`, with re-evaluation criteria: *"widen
the gate's rule once the confirmed class has held at 0 for one release cycle."* Two members are
noted there as the strongest candidates: `pr-auto-close-scanner.yml:84-86` (its sibling call at L82
*is* `|| true`-protected — an internal inconsistency), and `cla-evidence-timestamp.yml:325-332`
(`head -1` under `pipefail` also admits a SIGPIPE-141 abort).

### Phase 4 — The mechanical gate (so there is no seventh occurrence)

Create `scripts/lint-workflow-errexit-capture.py`, modelled directly on
`scripts/lint-workflow-step-env-refs.py` — same docstring discipline: state WHY, state WHY NOT
shellcheck/actionlint with measured counts, state the DIRECTION OF ERROR.

**The rule — the `$?` read is the tell, NOT the assignment shape.**

> **Anchor on the READ, then look backwards at the command.** A line that reads an exit status into
> a variable — `X=$?` **or** `X=${PIPESTATUS[n]}` — while errexit is in effect is the trigger.
> Inspect the immediately preceding *logical* command (walking `\` continuations backwards); it is a
> finding unless: the step has an errexit-clearing `shell:` key (or job/workflow
> `defaults: run: shell:` that clears it); a `set +e` is in effect at that point (tracked linearly,
> since a later `set -e` re-arms); or the command is protected by `|| true` / `|| rc=$?` / `|| VAR=…`,
> is the condition of `if`/`while`/`until`, or is an operand of `&&`/`||`. The read may be same-line
> (`cmd; rc=$?`) or on the next non-blank logical line.
>
> `${PIPESTATUS[n]}` is **not** optional: occurrence #3 (`git-data-rung2-rehearsal.yml:323`) and
> `web-platform-release.yml:1004` both read `rc=${PIPESTATUS[0]}` and never touch `$?`. A `$?`-only
> rule is blind to them, including to one of the six occurrences this gate is justified by.

**This wording is a deepen-time correction and is load-bearing.** The first draft said *"a
command-substitution assignment is a finding"*. A prototype of that rule run over the real tree
found **2 of 17 sites**. The reason: **9 of the 17 confirmed sites are bare commands, not
assignments** —

```bash
doppler run … -- terraform plan -no-color -input=false -out=tfplan
rc=$?
```

— so an assignment-shaped rule is structurally blind to every terraform site. Shipping the original
wording would have produced a gate that passes over more than half the class it was built to catch,
while reading as full coverage. The `$?` read is the only conjunct present in all 17.

That conjunct is also what makes the gate fail-closed with near-zero noise: it fires only where the
code itself proves the exit code was meant to be data.

**Calibration (measured at deepen time, prototype over 697 `run:` bodies in 78 files):** the
corrected rule returns **exactly 17 findings across exactly the 7 named files**, matching —
independently and site-for-site — sweeps run by two separate agents using different methods. Three
independent methods agreeing on the same 17 is the evidence that the rule is neither over- nor
under-fitted. A working prototype is in the session scratchpad; `/work` should treat it as a
starting point, not the deliverable (it lacks the heredoc skip, `${PIPESTATUS[n]}`, the
composite-action `shell:` resolution edge cases, and the docstring).

**MANDATORY: calibrate against the PRE-FIX tree before Phase 3's fixes are credited.** Phase 4
authors the gate *after* Phase 1 + Phase 3 have erased all 17 instances, so the only calibration
inputs left in the working tree are synthetic fixtures the linter author wrote themselves. That is
exactly how the original assignment-anchored rule (2 of 17) would have shipped reading as full
coverage. Therefore:

```bash
git worktree add /tmp/errexit-calib origin/main      # pristine pre-fix tree
python3 scripts/lint-workflow-errexit-capture.py --root /tmp/errexit-calib   # MUST report 17
python3 scripts/lint-workflow-errexit-capture.py                            # MUST report 0
```

The gate is not accepted until it reports **17 on `origin/main`** and **0 on the fixed tree**. A
rule that only satisfies the second is indistinguishable from a rule that finds nothing. Write the
**fixture set first** — it is the executable specification of the rule — and calibrate it against
the 17-site table while the evidence still exists.

**Measured false-positive contribution per lexer clause** (prototype, whole tree — the discipline
`lint-workflow-step-env-refs.py` uses, whose exemptions are each justified by a number):

| clause | findings WITHOUT it | verdict |
|---|---|---|
| `set +e` / `set -e` linear tracking | **40** (+23) | load-bearing by far |
| `if`/`while`/`until` condition exclusion | **19** (+2) | keep, small but real |
| `\|\| true` / `\|\| rc=$?` protection exclusion | **17** (+0) | **contributes nothing** — the read-anchor already excludes these (a `\|\| rc=$?` line is itself the read). Keep as cheap defence-in-depth, but do NOT claim it as load-bearing, and do not write a fixture that pretends it is. |

Required lexer details, each measured from a real instance:

- `out="$(…)"; rc=$?` — the `$?` read is **same-line, semicolon-separated**. A next-line-only
  detector misses the canonical instance.
- `shell: bash` does **not** clear `-e` (verified: every `shell:` key and all three
  `defaults: run:` blocks in this tree are `shell: bash`). Only a custom `shell:` whose command
  string lacks `-e` does.
- Track `set +e` / `set -e` **linearly within the body** — a `set -e` re-arm after a handler must
  not be read as protecting a later capture. **Match the COMPOUND forms, not just the literal
  `set -e`**: `set -euo pipefail`, `set -eu`, `set -eo pipefail` all re-arm errexit, and
  `set +eu` / `set -uo pipefail +e` all clear it. A matcher keyed on the exact string `set -e`
  misses `set -euo pipefail` — which would let a `set +e` followed by the house-dominant
  `set -euo pipefail` read as "cleared" while errexit is actually back on, shipping an inert fix
  that looks correct in the diff. Fixture required (must FIRE).
- **Walk `\` line continuations.** `scheduled-inngest-health.yml` opens `response="$(curl \` at
  L220 and reads `curl_rc=$?` at L229 — nine physical lines later, one logical command. A
  physical-line matcher misses a confirmed site. Fixture required.
- A body with **no `set` line at all** is not exempt (`infra-validation.yml`). Fixture required
  (must FIRE).
- Skip quoted heredoc bodies (`<<'EOF'`) — literal text, never executed as the step's shell.
- Strip comment lines before matching (reuse the `code()` discipline), or the gate is satisfiable
  by prose *and* false-fails on prose that names the commands.
- Scan `.github/actions/*/action.yml` composite `run:` bodies too — they inherit the same shell.

**DIRECTION OF ERROR:** prefer false negatives. A missed finding leaves today's (zero) coverage
unchanged; a false positive blocks an unrelated PR and gets the gate disabled.

Write `scripts/lint-workflow-errexit-capture.test.sh` with fixtures for: the bug shape (must FIRE);
same-line `; rc=$?` (must FIRE); `set +e` present (must not fire); `|| rc=$?` (must not fire);
`if`-condition capture (must not fire); a custom `shell:` that clears `-e` (must not fire);
**`shell: bash` + bug shape (must FIRE** — the highest-value anti-false-negative case); a `set -e`
re-arm before a later unprotected capture (must FIRE); a comment describing the bug (must not fire);
quoted heredoc containing the shape (must not fire).

Register **both** in `scripts/test-all.sh` beside the `lint-workflow-step-env-refs` pair (L350-351)
— the unit suite **and** a live scan over the real tree:

```sh
run_suite "scripts/lint-workflow-errexit-capture"      bash    scripts/lint-workflow-errexit-capture.test.sh
run_suite "scripts/lint-workflow-errexit-capture-live" python3 scripts/lint-workflow-errexit-capture.py
```

Confirm it lands in the `scripts` shard (`bash scripts/test-all.sh scripts`, CI `ci.yml:722`).

### Phase 5 — ADR + learning

1. Write `ADR-170` per the Architecture Decision section (re-verify the ordinal against
   freshly-fetched `origin/main` first; **167 is a gap and must not be reused**).
2. **Append** to
   `knowledge-base/project/learnings/best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md`
   — do **not** create a new learning file. The 2026-07-30 plan already ruled that adding files has
   not worked. New content: the sixth occurrence; the 17-site sweep result; the
   "four learnings + six comments + two sweeps failed" tally; the `set -e`-re-arm-without-`set +e`
   tell; and the pointer to the gate that replaces prose.

## Acceptance Criteria

### Pre-merge (PR)

**Both-direction pairing is mandatory. AC1-AC3 are worthless without AC4.**

1. **AC1 (exit 1 / alerting path).** With the checker stubbed to exit 1, the shipped `check` body
   run under `bash -e` exits 0, writes `exit_code=1` and `verdict=DRIFT_SUSTAINED` to
   `$GITHUB_OUTPUT`, emits ≥7 `drift| ` lines, and emits exactly one `::error::` matching
   `Production is serving a stale build`.
2. **AC2 (exit 2 / cannot-evaluate path).** Same with stub exit 2 → `exit_code=2`,
   `verdict=CHECK_ERROR`, exactly one `::error::` matching `could NOT be evaluated`.
3. **AC3 (exit 0 / the quiet path stays quiet).** Stub exit 0 → `exit_code=0`, `verdict=CLEAN`,
   ≥7 `drift| ` lines, **zero** `::error::`.
4. **AC4 (the control — proves AC1 is not vacuous).** Part C `axis11` deletes `set +e` from the
   `check` body, asserts the mutation landed byte-wise, and the child suite goes RED **with a FAIL
   line naming `B14`**. Recorded verbatim in `acceptance-evidence.md`.
5. **AC5.** The **statement** count, anchored — not a bare-token grep:

   ```bash
   grep -cE '^[[:space:]]*set \+e[[:space:]]*$' .github/workflows/scheduled-prod-version-drift.yml   # -> 7
   ```

   **A bare `grep -c 'set +e'` is WRONG here and was corrected at deepen time (measured: returns 14,
   not 7).** The Phase 1 comment block itself contains the literal `` `set +e` is REQUIRED ``, so an
   unanchored grep counts every comment line too and the AC fails against a *correct*
   implementation. Anchoring to a whole line beginning with optional whitespace excludes comments,
   which start with `#`. Per `cq-assert-anchor-not-bare-token`. B15 separately reports `0` of `7`
   bodies without an errexit clear, computed over the comment-stripped `code()` helper.
6. **AC6.** Mechanical, not prose — the added/removed lines must be only errexit statements or
   comments:

   ```bash
   git diff -U0 origin/main -- .github/workflows/scheduled-prod-version-drift.yml \
     | grep '^[+-]' | grep -vE '^(\+\+\+|---)' \
     | grep -vE 'set \+e|set -e|^[+-][[:space:]]*#|steps\.check\.outcome'   # -> empty
   ```

   Two carve-outs, both mandated by this same plan: `^[+-]\s*#` for the **false-premise comment
   corrections at L248 and L560** (Phase 1), and `steps.check.outcome` for the **Phase 1b coercion
   fix**. Without them AC6 as first worded ("only `set +e` lines") forbade two fixes the plan
   requires — a self-contradiction caught at deepen time.

6b. **AC6b (Phase 1b).** B17 reports `0` steps gating on `steps.check.outputs.exit_code` without an
   `outcome == 'success'` conjunct, and Part C `axis12` goes RED labelled `B17`. Additionally, a
   direct probe: with `exit_code` unset, no step gated on `== '0'` may be reachable — this is the
   defect that made the *closer* run on a dead tick while its own complement was skipped.
7. **AC7.** Same mechanical form per edited sibling workflow. Additionally: **every added `set +e`
   has a matching `set -e` re-arm** (the bracket shape all eight terraform siblings already use), or
   a named exemption in the plan. **No Terraform resource, `-target=` set, guard filter or job/step
   condition is altered**, and `set -u` is **not** introduced into `infra-validation.yml`.
8. **AC8.** `scripts/prod-version-drift-check.sh` is unmodified:
   `git diff --quiet origin/main -- scripts/prod-version-drift-check.sh`.
9. **AC9.** `bash scripts/prod-version-drift-check.test.sh` exits 0; Parts A, B and C all run
   (`C0 unmutated control is GREEN` present in output).
10. **AC10.** `MIN_B`, `MIN_C`, `MIN_ASSERTIONS` each **increased** vs `origin/main`; none decreased.
11. **AC11.** `python3 scripts/lint-workflow-errexit-capture.py` exits 0 over the real tree, and
    reports a **non-zero scanned-file count** (a gate that scanned nothing is not a passing gate).
12. **AC12.** `bash scripts/lint-workflow-errexit-capture.test.sh` exits 0, and its fixture set
    includes the `shell: bash` case and the same-line `; rc=$?` case, both asserted to **FIRE**.
13. **AC13 (the gate is not vacuous).** Reverting Phase 1 in a scratch copy makes the linter report
    `.github/workflows/scheduled-prod-version-drift.yml` and exit 1. Evidence recorded.
14. **AC14.** Both new suites appear in `scripts/test-all.sh` and execute under
    `bash scripts/test-all.sh scripts`.
15. **AC15.** All **17** confirmed sweep sites are fixed; the linter finds none. The full sweep
    table (confirmed + latent) is in `tasks.md`.
16. **AC16.** The **two** false-premise comments no longer assert that `-e` is omitted — scoped to
    the two real files, and excluding any corrective sentence that quotes the old claim in order to
    refute it:

    ```bash
    grep -h 'is intentionally omitted' \
         .github/workflows/apply-github-infra.yml \
         .github/workflows/apply-sentry-infra.yml \
      | grep -v 'USED TO SAY' | wc -l          # -> 0
    ```

    **Three deepen-time corrections are baked into this AC; the naive form was unsatisfiable.**
    (a) `grep -c` over a glob emits a **per-file** `file:count` line and can never equal a scalar
    `0`. (b) The glob `apply-*.yml` also matches `apply-web-platform-infra.yml:449`, which is the
    repo's **already-corrected** exemplar — it quotes the banned phrase precisely to refute it, so a
    glob-scoped AC can only be driven to 0 by mutilating the one correct piece of documentation in
    the tree, contradicting Scope Limits 3, `## Files to Edit`, and AC7. (c) The house style for the
    correction (`apply-web-platform-infra.yml:449`) *quotes the old claim*, so the `USED TO SAY`
    exclusion is required or the AC rebounds to non-zero the moment the fix is written in the very
    style the plan tells the implementer to imitate.
17. **AC17.** One tracking issue exists for the latent-class widening pass, carrying its
    re-evaluation criteria and the 13-site inventory.
18. **AC18.** `actionlint` passes on every edited workflow. *(Composite actions under
    `.github/actions/*/action.yml` are **not** run through `actionlint` — it validates workflows
    only and emits spurious schema errors against the action schema; none is edited by this plan,
    but if one becomes edited, validate its embedded `run:` shell with `bash -n` on the extracted
    snippet instead.)*
19. **AC19.** `ADR-170` exists, `Status: accepted`, `Enforced by:` names the linter + its test +
    `test-all.sh`, and `## Alternatives Considered` contains the `defaults.run.shell` rejection.
20. **AC20.** The `2026-07-02` learning is **appended to**; no new learning file is created for this
    class.
21. **AC21.** PR body uses `Closes #7304`.
22. **AC22.** `bash scripts/test-all.sh scripts` is fully green — run the shard's **own**
    invocation, never a hand-enumerated file list (the gate's scope must equal the scope whose
    result is claimed).
23. **AC23.** The ADR ordinal in the filename, ADR body, this plan, `tasks.md` and AC19 all agree,
    and `ADR-170-*.md` (or its post-collision-gate replacement) exists on disk.

### Post-merge (automated — no operator step)

24. **AC24.** Immediately after merge the shipping agent dispatches
    `gh workflow run scheduled-prod-version-drift.yml`, then polls
    `gh run list --workflow=scheduled-prod-version-drift.yml --limit 3 --json conclusion,databaseId`
    until that run completes.
25. **AC25 (the real fix criterion — and its own CLEAN-tick trap).** That run's `check` step reaches
    a verdict: its log contains `drift| DRIFT_VERDICT=` and the step wrote a non-empty `exit_code`.
    **A `success` conclusion alone is insufficient** — the pre-fix workflow also went green on a
    CLEAN tick.

    **Record the observed verdict verbatim, and if it is `CLEAN`, AC25 is NOT satisfied as
    evidence.** The plan's own Row 2 proves the CLEAN path passes *unchanged* against the broken
    body — so a CLEAN post-merge tick demonstrates nothing, and merging this PR triggers a deploy,
    which is precisely what converts prod from the discriminating (DRIFT) state into the
    non-discriminating one. On a CLEAN observation, the exit-1 evidence must instead come from
    re-running the AC1/AC4 arms **against the merged-commit body**. This is the same trap the plan
    catches for the pre-merge ACs; it was present in the first draft's own post-merge criterion.
26. **AC26 (do not misread a working alarm as a regression — for the OPERATOR, not just the agent).**
    If that run reports `DRIFT_SUSTAINED` and files a `ci/prod-version-drift` issue + email, **the
    fix succeeded** — releases have been blocked by #7247/#7267, so real drift is expected. Verify
    the filed issue body carries a non-empty `Detail:` and `Undeployed (first 10):` (proving output
    plumbing works end-to-end), then treat the drift itself as a **separate** operational matter.
    #7304 closes on the alerter's behaviour, not on prod's staleness.

    **The ship message MUST say this in the operator's own words.** A non-technical founder would
    otherwise receive an unexplained P0 `action-required` issue and email as the direct result of a
    merge, and learn to discount the one alarm this plan exists to restore. Note also that
    `ci/prod-version-drift` does **not exist as a label yet** (verified) — the workflow bootstraps
    it lazily via `gh label create … || true`, which has never run because of this bug. Its
    first-time creation on the first real drift is expected, not a fault.
27. **AC27.** The Sentry monitor `scheduled-prod-version-drift` records a check-in for that run.
28. **AC28.** `gh workflow run scheduled-cron-artifact-age.yml` is likewise dispatched and its
    `age` step observed writing a non-empty `rc` output (the second dark alarm).

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | checker exits 1, body under `bash -e` | verdict + `exit_code=1` + `::error::` reach outputs |
| T2 | checker exits 2, body under `bash -e` | verdict + `exit_code=2` + `::error::` reach outputs |
| T3 | checker exits 0 (CLEAN) | outputs written, **no** `::error::`, no alerting step reachable |
| T4 | `set +e` deleted (axis11) | suite RED, FAIL line names B14 |
| T5 | `gh issue list` fails inside the `issue` step | `list_rc != 0` branch is **reached** (dead code today) |
| T6 | linter vs. the bug shape | exit 1, names file + line |
| T7 | linter vs. same-line `; rc=$?` | exit 1 |
| T8 | linter vs. `shell: bash` + bug shape | exit 1 (does **not** clear `-e`) |
| T9 | linter vs. `set +e` / `\|\| rc=$?` / `if`-condition / errexit-clearing `shell:` | exit 0 |
| T10 | linter vs. `set -e` re-arm followed by a later unprotected capture | exit 1 |
| T11 | linter vs. a comment describing the bug, and vs. a quoted heredoc | exit 0 |
| T12 | `terraform plan` fails in an edited `apply-*.yml` (simulated) | `::error::` emitted **and** job still fails via `exit $rc` |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **`set +e` masks a genuinely fatal error.** | Measured: every terraform handler already ends `exit $rc`, so the job still fails and merely gains its dead `::error::` back (T12). In the drift workflow, every step already has explicit rc handling and `::error::` arms — that *is* the design, currently unreachable. The heartbeat's first conjunct already documents that it should read `failure` only on runner-level death; `set +e` makes that comment **true** rather than changing intent. AC6/AC7 pin that nothing else moves. |
| **Fix verified only on the CLEAN path.** | Measured and explicitly guarded: CLEAN passes *unchanged* against the broken body. AC1/AC2 + the AC4 control mutation make an exit-0-only verification impossible to mistake for a pass. |
| **`infra-validation.yml` has `continue-on-error: true`** — adding `set +e` could let a failed plan pass silently. | Phase 3 item 3 requires confirming the outputs are written **and** the downstream consumer still red-flags a non-zero plan. Called out as its own step, not folded into the mechanical sweep. |
| **The new linter is noisy and gets disabled.** | Fail-closed on the "author expected to handle failure" conjunct; documented DIRECTION OF ERROR (prefer false negatives); calibrated against the measured 17-site set; ships with no `.highwater`. |
| **The linter false-negatives on `shell: bash`.** | T8 + AC12 assert it FIRES there. |
| **Blast radius: 7 workflow files incl. the auto-applied prod infra root.** | Every sibling edit is a shell flag plus comments; AC7 pins the diff shape per file. No `.tf`, no `-target=`, no job condition. |
| **ADR ordinal collides during the pipeline.** | Provisional 170; `/ship`'s collision gate re-verifies; renumber sweeps plan + tasks + ADR + AC19/AC23 in one edit; 167 is a gap and must not be reused. |
| **Post-merge run legitimately reports DRIFT_SUSTAINED and reads as a new failure.** | AC26 states the disambiguation explicitly (COO finding). |
| **Raising `MIN_*` floors hides a shrink elsewhere.** | Raised by exactly the added-assertion count; AC10 asserts increase-only. Also assert `MIN_ASSERTIONS == MIN_A + MIN_B + MIN_C` — the equality is what makes the global floor non-slack and holds only by coincidence today. Floors catch *deletion*, not *collapse* (the `FAIL > 0` early exit precedes every floor check). |
| **Shipping the gate with no `.highwater` is what FORCES 6 edits to the auto-applied prod infra root.** | Stated plainly rather than presented as independent remediation: the nine terraform sites are cosmetic on their own merits (every handler already `exit $rc`s; the only gain is reviving a dead `::error::`). Nothing requires touching `apply-web-platform-infra.yml` except the decision to ship fail-closed at 0. The alternative is a `.highwater` of 9. The trade is taken deliberately — a gate that ships at 0 with no baseline is strictly stronger — but it is a trade, and AC7's per-file diff pin is what bounds it. |
| **A top-of-body `set +e` in a long sibling step disarms far more than the capture.** | `scheduled-inngest-health.yml`'s target body is 121 lines with 6 command substitutions and drives an **automated prod restart** from `failure_mode`/`failure_detail`. Phase 3 mandates a **narrow bracket** (`set +e` immediately before the capture, `set -e` immediately after the `$?` read) at that site and at `infra-validation.yml`, matching the 9 terraform siblings — never the top-of-body form. AC7 asserts a matching re-arm per added `set +e`. |
| **The Phase 1b coercion fix touches `if:` conditions that Parts B/C pin.** | B3/B4/B6 assert `if:` *structure* by substring; adding a leading `steps.check.outcome == 'success' &&` conjunct preserves every asserted substring. B17 + `axis12` are added to pin the new conjunct so it cannot be silently dropped later. |

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| `set +e` per step body | **Chosen.** Visible, executable in a test, lintable; matches the house pattern (`apply-web-platform-infra.yml`, `git-data-rung2-rehearsal.yml`). |
| `\|\| rc=$?` on the capture only | Fixes L106; leaves four documented `list_rc` branches dead. Retained as acceptable for a single-capture sibling body. |
| `defaults: run: shell:` at workflow level | Rejected — invisible to the PyYAML body-extraction tests, unlintable per step, silently rebinds future steps. |
| Documentation-only (status quo) | Rejected on measured recurrence: 4 learnings + 6 comments + 2 sweeps → 6th occurrence. |
| `shellcheck` / `actionlint` | Rejected — neither models the runner-injected `-e`; `actionlint` already runs here and caught none of the six. |
| Fix only `scheduled-prod-version-drift.yml` (issue's literal ask) | Rejected — the sweep the issue itself requested found 12 more confirmed sites, including a **second dark alarm** (`scheduled-cron-artifact-age.yml`). |
