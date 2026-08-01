---
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
closes: 7138
---

# Plan: when the release-outcome classifier itself dies, every alert channel dies with it

No `spec.md` exists for `feat-one-shot-7138-classify-step-failure-alert` — defaulted to
`cross-domain` (TR2 fail-closed). The change is in practice engineering-only; the lane is
recorded as derived, not as judged.

`requires_cpo_signoff: true` follows from the `single-user incident` threshold below. CPO
sign-off is a plan-time gate; `user-impact-reviewer` is invoked at review time by
`plugins/soleur/skills/review/SKILL.md`'s conditional-agent block.

## Overview

`.github/workflows/web-platform-release.yml`, job `release-outcome`, has three steps. Both
notification steps read an **output of the first one**:

| step | `id` | shipped `if:` |
|---|---|---|
| `Classify the run outcome` | `outcome` | *(none — implicit `success()`)* |
| `Email the operator (release did NOT reach production)` | `email` | `steps.outcome.outputs.failed != ''` |
| `Mirror non-delivery to Sentry and fail loudly` | *(none)* | `${{ !cancelled() && steps.outcome.outputs.failed != '' && steps.email.outputs.delivered != '1' }}` |

If the **classify** step fails, it never reaches its terminal `>> "$GITHUB_OUTPUT"` write, so
`steps.outcome.outputs.failed` is `''`. The email step's predicate is false (and its implicit
`success()` is also false). The mirror step's second conjunct is false even though
`!cancelled()` is true. **Both steps skip.** The job goes red — and a red release run is
exactly the signal #7095 established is not sufficient on its own.

This is the same shape as #7136, one level up: #7136 was "the fallback could not fire because
its subject crashed"; this is "**neither** channel can fire because the step they both read
crashed." The classifier is now the single point whose failure silences every downstream
channel.

### Why this needs more than the one-line `if:` change

Three things the issue's suggested patch does not cover, each found by reading the shipped
file rather than the issue:

1. **The mirror step's body has never run with an empty `FAILED`, and the fix is what makes
   that input reachable.** `--arg failed "${FAILED}"` and `(${FAILED})` in the summary line
   are the only unguarded expansions in a step whose every sibling is guarded
   (`${REASON:-unknown}`, `${NEXT_PUBLIC_SENTRY_DSN:-}`, `${GITHUB_SHA:-}`).

   **Correction, applied at plan-review (see §Plan Review Revisions R2).** An earlier draft of
   this plan claimed the unguarded form would *crash* the step under `set -u`. That is wrong,
   and it contradicted the issue, which says the opposite: `FAILED` is declared in the step's
   own `env:`, and GitHub sets a declared key whose expression resolves empty to the empty
   string — set, not unset — so `set -u` does not fire. The guard is kept as a free
   consistency change matching its siblings, **not** as a crash fix, and the empirical answer
   is recorded from harness arm B rather than asserted by either document. What genuinely
   applies here is §4 of the #7136 learning — *"a branch that has never executed is not a
   branch that works; audit the newly-reachable path in the same change"* — which is why the
   empty-`FAILED` message path is executed in Part B rather than reasoned about.

2. **A Sentry event is not, on this project, an operator-visible alert.** `sentry -> founder`
   in `model.c4` states the exit precisely: *"Issue alerts route `actions_v2 notify_email` …
   21 of the 22 rules"* — i.e. Sentry pages a human only for events a `sentry_issue_alert`
   rule **matches**. All 29 rules in `apps/web-platform/infra/sentry/issue-alerts.tf` are
   tag-filtered (`feature`, `op`, `art_33_breach`, …) and **none** matches
   `gate:release-outcome` / `op:release-alert-undelivered`. `main-health-monitor.yml` runs
   `scripts/test-all.sh` on main and has no knowledge of `web-platform-release.yml` at all.
   So the issue's literal AC1 floor ("Sentry event at minimum") produces an event that lands
   in the issue stream and pages nobody. See §Scope decision below.

3. **`steps.outcome.conclusion` is only trustworthy while the classify step carries no
   `continue-on-error`.** `conclusion` is the post-`continue-on-error` value; adding
   `continue-on-error: true` to the classify step would silently flip it to `success` and
   disarm the whole guard, with no test failing. That invariant has to be pinned, not assumed.

### Scope decision — widen the **email** condition too, not only the mirror

The issue's suggested patch changes only the mirror. This plan **also** widens the email
step's condition, because the mirror-only fix does not deliver a push signal:

- The mirror's Sentry event matches no alert rule (evidence above), so it is pull-only.
- The email is the channel this entire job exists to drive. (R25: an earlier draft put
  *"the operator's only push signal"* in quotation marks as if it came from the job's header
  comment. It does not appear anywhere in the file. What the header actually says is that
  *"The only two push notifications in this file hang off `deploy` … and off `await-ci`"* —
  and it exists precisely because **three** of the eight incident runs never reached `deploy`,
  so the deploy-scoped email was structurally silent for them. The argument stands on that;
  the invented quotation is withdrawn.)
- The #7095 plan's R12 explicitly **cut** a Sentry issue alert for this domain, with the
  rationale *"5.5's terminal `release-outcome` job fires on the first failure … it alone
  would have caught all eight."* That rationale is precisely what #7138 falsifies: it assumes
  the email fires. In the classifier-death case it cannot.

The email is widened with a **third headline branch** rather than by relaxing the predicate
alone. Naively widening it would send `[RELEASE FAILED] … production was NOT updated` on the
dominant sub-case (classifier dies while every other job succeeded) — a false urgent page, and
the file's own comment at the `R_DEPLOY` branch is a 10-line argument that *"one wrong urgent
page is exactly what teaches them to stop reading the next one."*

Both conditions are then factored on one shared predicate, which is what makes the harness
able to prove them together:

```
ALERT_WARRANTED  ==  steps.outcome.conclusion == 'failure' || steps.outcome.outputs.failed != ''

email:   ${{ !cancelled() && ALERT_WARRANTED }}
mirror:  ${{ !cancelled() && ALERT_WARRANTED && steps.email.outputs.delivered != '1' }}
```

This is strictly stronger than the issue's suggestion, which would have fired the mirror (and
its `exit 1`) on **every** classifier failure — including ones where the operator was
successfully emailed. Here the mirror stands down when the email delivered, preserving the
two-channel design exactly as #7095 wrote it.

**This is a deviation from the stated work target ("make the mirror step's condition
independent…"), recorded in `decision-challenges.md` for the operator, and separated into its
own phase so it can be cut without touching the core fix.**

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue: fix is "a condition change only" | True for the mirror's `if:`, **false** for its body — `${FAILED}` is unguarded and the fix is what makes `FAILED=''` reachable | Guard it in the same change (Phase 1); execute the empty-`FAILED` body in Part B |
| Issue AC1: "operator-visible alert (Sentry event at minimum)" | No `sentry_issue_alert` rule matches `gate:release-outcome`; `model.c4 sentry -> founder` confirms only matched rules page | Widen the email (Phase 2); record the unrouted-op gap as a tracked scope-out |
| Issue: "verified by executing the condition… `act`, or a scratch workflow" | `act` is referenced **nowhere** in this repo and is **not installed** (`command -v act` → exit 1). It is also a *reimplementation* of the expression evaluator — proving a condition in `act` proves `act`'s semantics, not GitHub's | Execute on **GitHub's own evaluator** via a `pull_request`-triggered harness (Phase 3) |
| Issue: "a scratch workflow… force-fails a classify-shaped step" | A **new** workflow cannot be `workflow_dispatch`-triggered from a feature branch — `HTTP 404: workflow not found on the default branch` (`learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`) | Harness triggers on `pull_request` (+ `workflow_dispatch` for post-merge re-runs), per that learning's Prevention option 1 |
| #7136 plan §Observability: `release-outcome emits SOLEUR_RELEASE_ALERT` | `grep -rn SOLEUR_RELEASE_ALERT .github/` → **zero hits**. The predecessor plan's liveness_signal describes a marker that was never implemented | This plan's `## Observability` describes only what the shipped file actually emits; the missing marker is **not** silently inherited |
| Predecessor `!cancelled()` guard is already asserted | True — `scripts/lint-workflow-step-env-refs.test.sh` **B1b** asserts it, selecting the step by `name.startswith("Mirror non-delivery")` | New assertions extend B1b's block; the mirror step gains `id: mirror` so all selectors key on the id |
| Mirror step has an `id` | It does **not** — B1b selects by name prefix | Add `id: mirror` (Phase 1); switch the test's selector to id |

**Premise validation.** `gh issue view 7136` → **CLOSED** (the R_DEPLOY email bug; its fix is
PR #7137, merged 2026-07-31 as `b11cb43f4`). `gh issue view 7095` → OPEN (the parent P1
incident; not a work target here). `#7138` → OPEN, `type/bug` + `deferred-scope-out`. Neither
predecessor is re-opened, re-implemented, or closed by this plan. No ADR in
`knowledge-base/engineering/architecture/decisions/` proposes or rejects a GitHub-Actions
condition harness; the nearest, ADR-033 (scheduling substrate), is unrelated.

## User-Brand Impact

**If this lands broken, the user experiences:** a release that never reached production, with
no email, no page, and no issue — exactly the 26-hour #7095 outage, in which eight consecutive
red runs were each read as "the known incident" while prod served a build from the day before.
The founder keeps merging; nothing ships; the site looks healthy while serving old code.

**If this leaks, the user's data is exposed via:** nothing. No personal data, credential, or
customer record is added to any payload. The email recipient (`ops@jikigai.com`), the Resend
call, and the Sentry DSN are all unchanged; only *when* they fire changes. The one new content
field is a step name and a run URL.

**Brand-survival threshold:** `single-user incident`. There is exactly one operator on this
alert path; a missed alert is a total loss of the signal, not a degraded one — the same
threshold the #7136 plan carried for the same job.

## Architecture Decision (ADR/C4)

**ADR: none.** This makes no ownership/tenancy, substrate, resolver, or trust-boundary change,
and reverses no existing ADR. A `pull_request`-triggered condition harness is a test technique,
not an architectural decision.

**C4 views — enumerated, and there IS impact.** All three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) were read.
Enumeration for this change:

- **External human actors:** `founder` ("Founder / Operator", `model.c4:8`) — the alert
  recipient. Already modeled.
- **External systems:** `resend` (`model.c4:254`), `sentry` (`model.c4:294`), `github`
  (`model.c4:232`). All three already modeled as elements.
- **Containers / data stores touched:** none.
- **Access relationships that change:** **two gaps found.**
  1. **There is no `github -> resend` edge at all.** The only Resend edges are
     `emailSender -> resend`, `webapp -> resend`, `api -> resend`. But the release-failure
     operator email is sent by an inline `curl` **from a GitHub runner**, not from the app —
     and this plan *changes when that edge fires* (Phase 2 widens its trigger condition). An
     unmodeled edge that this change alters is exactly what the completeness mandate is for.
  2. **`github -> sentry` (`model.c4:528`) describes CI's Sentry edge as cron check-ins plus
     the Terraform applier.** It omits the `release-outcome` mirror's direct store-API POST,
     and therefore also omits the fact — decisive for this plan — that the POST matches no
     `sentry_issue_alert` rule and so does **not** reach the `sentry -> founder` paging exit.

Both are fixed in **Phase 5**. Neither requires a `views.c4` edit: `github` and `resend` are
both already `include`d in `view context` (`views.c4:14`) and `view containers`
(`views.c4:36`), so LikeC4 renders the new relationship automatically.
`apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` are the validation
gate and are run in Phase 6.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (inline — CI/observability change with no product surface).
**Assessment:** The change is confined to CI alerting. The load-bearing engineering risks are
(a) an execution harness that proves less than it appears to (mitigated by the negative-control
arms and the harness↔shipped drift assertion), (b) a fix that moves the crash into the
compensating step (mitigated by the `${FAILED:-}` guard + an executed empty-`FAILED` arm), and
(c) a guard silently disarmed by a future `continue-on-error` (mitigated by an explicit static
assertion). No new infrastructure, no new vendor, no new secret, no persistent store.

### Product/UX Gate

Not applicable. `## Files to Create` and `## Files to Edit` contain **no** path matching
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, and no UI-surface term. The
only user-facing artifact is the text of an operator email, reviewed inline against the
existing file's own alert-fatigue doctrine. The mechanical UI-surface override does not fire.

**GDPR / compliance gate (Phase 2.7).** Run against the target file set:
`bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh "<the three edited files>"` →
no findings (advisory staleness warning only: *"gdpr-gate rules 83 days stale (last verified
2026-05-10)"*). No schema, migration, auth flow, API route, or `.sql` file is touched; no new
processing activity, no new data category, no new recipient. Recorded because trigger (b)
(brand-survival threshold `single-user incident`) fires, not because a regulated surface does.

**Infrastructure-as-Code gate (Phase 2.8) — reviewed, no routing needed.**
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
This plan provisions nothing: no host, no managed service, no credential, no network or DNS
record, no certificate, no recurring job, no vendor account. Nothing is configured outside the
repository. The complete change set is three tracked files plus one new CI workflow, all of
which take effect through the normal merge path. **There are no operator-executed steps in
this plan at all** — see `### Post-merge (operator)` under Acceptance Criteria, which is
explicitly empty. The literal detection vocabulary is deliberately not reproduced here (see
the last Sharp Edge); the scan was performed against the draft and returned nothing.

**Network-outage deep-dive (deepen-plan Phase 4.5).** Not applicable. The keyword scan is
substring-based and previously matched only an infrastructure-class noun used in this
paragraph's own negation. This plan diagnoses no connectivity symptom: nothing here reaches a
host, and the only network calls are the pre-existing Resend and Sentry HTTPS calls whose
*trigger condition*, not whose transport, is being changed. No L3/L7 verification is owed.

**Encryption-posture gate (Phase 2.11).** Skipped — no `*.tf`, no `supabase/migrations/*.sql`,
no cloud-init file, no compose file; no persistent store and no new cross-component connection
(the Resend and Sentry connections both already exist).

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --json number,title,body --limit 200`
returned 62 issues; a `jq … contains($path)` sweep for each of
`.github/workflows/web-platform-release.yml`, `scripts/lint-workflow-step-env-refs.test.sh`,
`scripts/lint-workflow-step-env-refs.py`, and `scripts/test-all.sh` returned zero matches.

## Observability

```yaml
liveness_signal:
  what: the release-outcome job's step summary line — "release-outcome: every upstream job
        succeeded or was skipped — no alert." on a clean run, "release-outcome: FAILED jobs
        → <list>" on a failed one, and (new) the mirror's classifier-death summary line
  cadence: every Web Platform Release run (the job is `if: always()` with `needs:` on all 8
           upstream jobs)
  alert_target: ops@jikigai.com via Resend (the push channel); Sentry store-API event tagged
                gate=release-outcome / op=release-alert-undelivered on non-delivery (pull-only
                today — see failure_modes below)
  configured_in: .github/workflows/web-platform-release.yml, job release-outcome
error_reporting:
  destination: Sentry store endpoint, DSN from the GitHub-side NEXT_PUBLIC_SENTRY_DSN secret
               (a different vendor than Resend, read from a different secret store than the
               host's dead-Doppler blind spot — see the job's own header comment)
  fail_loud: yes — the mirror step ends in `exit 1`, so a non-delivery reddens the run
failure_modes:
  - mode: the classify step itself fails, so `failed` is empty and both channels skip (#7138)
    detection: `steps.outcome.conclusion == 'failure'` in BOTH the email and mirror `if:`,
               executed on GitHub's own evaluator in run 30710703476 (arms A/B/C; the
               harness workflow was deleted before merge per R10 — the run is the
               evidence), and pinned thereafter by B1c/B1d in the required `test` check
    alert_route: operator email (classifier-death headline) + red run; Sentry mirror if the
                 email does not deliver
  - mode: someone adds `continue-on-error: true` to the classify step, flipping `conclusion`
          to `success` and silently disarming the guard above
    detection: static assertion B1e in scripts/lint-workflow-step-env-refs.test.sh
    alert_route: the required `test` check reds on the PR that introduces it
  - mode: a classify HANG (or a run cancelled mid-classify) produces neither a `failure`
          conclusion nor a written output, so no widening of the two conditions can reach it
    detection: a step-level `timeout-minutes` on the classify step turns a hang into a
               `failure` conclusion, which B1c/B1d then fire on; the timeout itself is
               pinned by static assertion B1f
    alert_route: both channels, via the widened conditions
  - mode: the mirror step crashes on an empty `${FAILED}` under `set -u` — i.e. #7136
          reproduced inside the step that exists to compensate for it
    detection: Part B execution arm M1 runs the SHIPPED mirror body with `FAILED=""`;
               mutation arm M3 asserts the unguarded form dies
    alert_route: the required `test` check
  - mode: the Sentry mirror fires but pages nobody, because no `sentry_issue_alert` rule
          matches `gate:release-outcome` (PRE-EXISTING, scoped out — tracking issue in Phase 7)
    detection: none today; the event is visible only by pulling the Sentry issue stream
    alert_route: the Sentry-default rule `Send a notification for high priority issues`
                 (empty filters, ActiveMembers fallthrough) — UI-managed, absent from IaC,
                 and silent on a REPEAT of an identical event. Tracked as #7142
logs:
  where: GitHub Actions run log + job summary for the run; Sentry issue stream (pull)
  retention: GitHub default (90 days)
discoverability_test:
  command: bash scripts/lint-workflow-step-env-refs.test.sh
  expected_output: "All tests passed" — Part A fixtures, Part B execution of the shipped
                   email AND mirror bodies (including the newly-reachable empty-FAILED
                   input), and the static assertions B1a..B1f
```

Every command in the verification path runs locally or on a GitHub runner; none reaches a host.
**Soak follow-through enrollment (2.9.1):** not required — no acceptance criterion is
time-gated; every criterion resolves within the PR's own CI run. **Affected-surface
observability (2.9.2):** the affected surface (a GitHub-hosted runner) is directly inspectable
via the run log and the jobs API, and the harness reads that API itself; no blind execution
surface is involved.

## Implementation Phases

### Phase 0 — Preconditions (verify before writing code)

Each of these is a claim this plan depends on. Verify and record the output; do **not** carry
the plan's assertion forward as fact.

0.1 `command -v act` → confirm absent (recorded here as exit 1). If present, still do **not**
    use it: it is a reimplementation of GitHub's expression evaluator, and proving the
    condition there proves `act`'s semantics, not GitHub's.
0.2 `command -v actionlint` → present at `~/.local/bin/actionlint` (v1.7.7). The new harness
    workflow must pass `bash scripts/lint-workflows.sh`.
0.3 `python3 scripts/lint-workflow-step-env-refs.py` → exit 0 on the current tree (this is
    test A13's steady state; the new harness workflow must not break it).
0.4 Read `.github/workflows/gdpr-gate-self-test.yml` — the in-repo precedent for a workflow
    that triggers on `pull_request` with a `paths:` filter **that includes its own path**.
    Copy its permissions/timeout/pinning conventions.
0.5 Confirm the required-check surface: `test-scripts` in `ci.yml` rolls into the synthetic
    `test` aggregator, which **is** the required status check (ruleset 14145388). The new
    static assertions therefore gate merges. The harness workflow is deliberately **not**
    added to any ruleset — `always()`/`paths:` and required checks are a known-bad pair
    (`learnings/2026-03-20-github-required-checks-skip-ci-synthetic-status.md`).

### Phase 1 — The mirror step (the issue's stated scope)

`.github/workflows/web-platform-release.yml`, step `Mirror non-delivery to Sentry and fail
loudly`:

1.1 Add `id: mirror` (the sibling steps already carry `outcome` / `email`; the test's selector
    moves from a name prefix to this id).

1.2 Replace the `if:` with the shared-predicate form, on **one line** (multi-line YAML folding
    would defeat the byte-equality assertion in 4.6):

```yaml
        if: ${{ !cancelled() && (steps.outcome.conclusion == 'failure' || steps.outcome.outputs.failed != '') && steps.email.outputs.delivered != '1' }}
```

1.3 **Guard `${FAILED}`.** Both occurrences become `${FAILED:-}`:
    - `--arg failed "${FAILED}"` → `--arg failed "${FAILED:-}"`
    - `… release FAILED (${FAILED}) and …` → the branched summary line in 1.4.
    This also keeps the step inside `lint-workflow-step-env-refs.py`'s *guarded-anywhere*
    exemption, matching every sibling expansion in the step.

1.4 **Say the truthful thing in one expansion, not a branch** (R3). When `FAILED` is empty we
    do not know that the release failed — the *classifier* failed — and naming the release as
    the fault sends the operator to the wrong place. A default-value expansion carries that
    without three branched blocks:

```bash
          # #7138 — an EMPTY FAILED means the classifier died before writing $GITHUB_OUTPUT:
          # the release status is UNKNOWN and the alerting job is the fault, not the release.
          FAILED_LABEL="${FAILED:-UNKNOWN (the run-outcome classifier itself failed; release status could not be determined)}"
```

    `$FAILED_LABEL` then replaces `${FAILED}` in the Sentry `msg`, the `failed` arg, the
    `$GITHUB_STEP_SUMMARY` line and the terminal `::error::` line — one substitution, four
    call sites, no branching.

1.5 Add the structured discriminator as a single computed tag, so the event answers
    "classifier or channel?" without a second branch
    (`hr-observability-as-plan-quality-gate` §2.9.2 — *structured fields discriminate
    competing hypotheses in one event*):

```bash
          CLASSIFIER="${FAILED:+ok}"; CLASSIFIER="${CLASSIFIER:-failed}"
```

    The `tags:` object gains `classifier:$CLASSIFIER`. The `op` tag stays
    **`release-alert-undelivered`** — changing it would move the event to a value nothing
    routes on; a discriminator belongs in a new tag key, never in the routing key. The step
    still ends in `exit 1`.

1.6 On the `Classify the run outcome` step, add a comment pinning the invariant that assertion
    B1e enforces:

```yaml
        # #7138 — DO NOT add `continue-on-error:` to this step. `steps.outcome.conclusion`
        # is the POST-continue-on-error value; setting it here flips the value to `success`
        # and silently disarms the classifier-death guard in BOTH steps below. Asserted by
        # scripts/lint-workflow-step-env-refs.test.sh (B1e).
```

### Phase 2 — The email step (the push channel) — separable

Cut this phase and Phase 1 still satisfies the issue's literal ACs; see §Scope decision for
why it should not be cut.

2.1 Replace the email step's `if:` with the shared predicate, in the same `${{ … }}` form so
    the two strings are literally comparable to the harness:

```yaml
        if: ${{ !cancelled() && (steps.outcome.conclusion == 'failure' || steps.outcome.outputs.failed != '') }}
```

2.2 Add `CLASSIFIER: ${{ steps.outcome.conclusion }}` to that step's **own** `env:` — declared
    there, never inherited (this is the #7136 rule, and `lint-workflow-step-env-refs.py`
    enforces it).

2.3 Add a **third headline branch**, ahead of the existing `R_DEPLOY` branch, so the dominant
    sub-case (classifier dies while every other job succeeded) is not paged as a release
    failure:

```bash
          if [[ "${CLASSIFIER:-}" == "failure" ]]; then
            SUBJ_TAIL="we could not tell whether this release reached production"
            BODY="<p><strong>The step that works out whether a release succeeded failed itself, so we cannot tell you whether your changes are live.</strong></p>"
            BODY="${BODY}<p>Attempted version: <code>${VER_LABEL}</code> (tag: <code>${TAG_LABEL}</code>).</p>"
            BODY="${BODY}<p><strong>What this means for you:</strong> the release may have worked or may not have. Nothing here says it failed — only that the check could not answer. Open the run below to see which parts finished.</p>"
          elif [[ "${R_DEPLOY:-}" == "success" ]]; then
            … existing branch, unchanged …
          else
            … existing branch, unchanged …
          fi
```

    `${CLASSIFIER:-}` is guarded like every sibling; an unset value falls through to the
    existing behaviour, which is the safe direction.

2.4 Guard the "What stopped" list so the classifier-death branch does not render an empty
    `<ul></ul>` under a heading that promises content:

```bash
          if [[ -n "${FAILED_HTML:-}" ]]; then
            BODY="${BODY}<p><strong>What stopped:</strong></p><ul>${FAILED_HTML}</ul>"
          fi
```

    The run link and the "send this to your engineer" paragraph stay unconditional — the
    closing text refers to the link, and #7136 §4 is the record of what happens when a branch
    is missing the artefact its own prose points at.

2.5 Subject line for the new branch: `[RELEASE CHECK FAILED] Soleur Web Platform v${VER_LABEL}
    — ${SUBJ_TAIL}`. Deliberately **not** `[RELEASE FAILED]`, which would be a false claim on
    the dominant sub-case.

### Phase 3 — The execution harness (AC2)

**Create** `.github/workflows/release-outcome-condition-harness.yml`.

Why this shape, and not the alternatives:

- **Not `act`.** Absent from the repo and this machine, and a *reimplementation* of the
  evaluator — a green `act` run is a proxy for the invariant, not the invariant
  (`plan` Sharp Edge: *verify the invariant, not a proxy*).
- **Not `workflow_dispatch` on a scratch workflow.** A new workflow file is not dispatchable
  from a feature branch — `HTTP 404: workflow not found on the default branch`
  (`learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`,
  whose Prevention section names *"wire the check into something that already runs on
  `pull_request`"* as option 1 and explicitly bans the scratch-workflow plan shape).
- **Not a job inside `ci.yml`.** One arm must genuinely fail a step, which would redden the
  required `test` aggregator. It has to be isolated in its own workflow.
- **Not a local expression evaluator.** That is reading the YAML with extra steps.

3.1 Triggers — self-bootstrapping `paths:` filter, mirroring `gdpr-gate-self-test.yml`:

```yaml
on:
  pull_request:
    paths:
      - ".github/workflows/web-platform-release.yml"
      - ".github/workflows/release-outcome-condition-harness.yml"
      - "scripts/lint-workflow-step-env-refs.test.sh"
      - "scripts/lint-workflow-step-env-refs.py"
  workflow_dispatch:
```

`workflow_dispatch` is for **post-merge** re-verification (it is dispatchable once the file is
on `main`); the pre-merge evidence comes from the `pull_request` arm. Its own path is in the
filter so the harness re-runs whenever the harness itself changes.

3.2 One matrix job, six arms. The `if:` strings appear **exactly once each** — the arms differ
only in their step *bodies*, which is what makes the drift assertion a single comparison:

```yaml
jobs:
  probe:
    name: probe ${{ matrix.arm }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    # Arms A, B and F deliberately fail a step, which reddens the JOB. Job-level
    # continue-on-error keeps the RUN green; the verdict job below is the pass/fail signal.
    continue-on-error: true
    strategy:
      fail-fast: false
      matrix:
        arm: [A, B, C, D, E, F]
    steps:
      - name: Classify the run outcome (stand-in)
        id: outcome
        env:
          ARM: ${{ matrix.arm }}
        run: |
          set -uo pipefail
          case "$ARM" in
            A|B|F) echo "forcing the classifier to die before it writes GITHUB_OUTPUT"; exit 1 ;;
            C)     echo "failed=" >> "$GITHUB_OUTPUT" ;;
            D|E)   echo "failed=deploy=failure" >> "$GITHUB_OUTPUT" ;;
          esac

      - name: Email the operator (stand-in)
        id: email
        if: <VERBATIM COPY of the shipped email step's if:>
        env:
          ARM: ${{ matrix.arm }}
        run: |
          set -uo pipefail
          case "$ARM" in
            F)   echo "the email step itself crashes"; exit 1 ;;
            A|D) echo "delivered=1" >> "$GITHUB_OUTPUT" ;;
            *)   echo "delivered=0" >> "$GITHUB_OUTPUT" ;;
          esac

      - name: Mirror non-delivery to Sentry (condition under test)
        id: mirror
        if: <VERBATIM COPY of the shipped mirror step's if:>
        env:
          # Declared exactly as the shipped step declares it — an EMPTY step output, so this
          # arm also proves the shipped body's `${FAILED:-}` expansion survives `set -u`.
          FAILED: ${{ steps.outcome.outputs.failed }}
        run: |
          set -uo pipefail
          echo "mirror ran; FAILED='${FAILED:-}'"
```

3.3 Expected truth table — this is the artefact the verdict job asserts:

| arm | classify | email stand-in | `outcome` | `email` | `mirror` | proves |
|---|---|---|---|---|---|---|
| A | dies | delivers | failure | success | **skipped** | classifier death emails the operator, and the mirror stands down when it worked |
| B | dies | does not deliver | failure | success | **success** | the compensating channel still fires — **the #7138 fix** |
| C | clean run, `failed=''` | n/a | success | **skipped** | **skipped** | **negative control** — a healthy release alerts nobody |
| D | `failed=deploy=failure` | delivers | success | success | **skipped** | **negative control** — a delivered alert does not also page Sentry |
| E | `failed=deploy=failure` | does not deliver | success | success | **success** | the pre-existing #7095 path still works |
| F | dies | **crashes** | failure | **failure** | **success** | `!cancelled()` still survives an email-step crash — the #7136 property |

Arms C and D are what make this harness non-vacuous: a naive `if: always()` "fix" passes A, B,
E and F and **fails C and D**. Without them the harness cannot distinguish the correct fix
from the lazy one — the exact vacuity
`learnings/2026-08-01-i-shipped-a-gate-my-own-tests-could-not-see.md` warns about (*"delete
the thing the test is named for and re-run — green means it pins nothing"*).

3.4 A `verdict` job — `needs: [probe]`, `if: always()`, `permissions: { contents: read,
    actions: read }` — reads the jobs API for this run and asserts the table:

```bash
          set -uo pipefail
          gh api "repos/${GH_REPO}/actions/runs/${GH_RUN_ID}/jobs" --paginate \
            --jq '.jobs[] | select(.name | startswith("probe ")) |
                  {job: .name, steps: [.steps[] | {name, conclusion}]}' > "$RUNNER_TEMP/jobs.json"
```

    then, for each `(arm, step, expected)` row, fail loudly on any mismatch and print the whole
    observed table on failure. The verdict job is the workflow's pass/fail signal.

3.5 The verdict job **also** asserts the arm set is complete (six arms observed) — a
    `--paginate` sweep that silently returns fewer jobs than expected must not read as green
    (#7136 learning §7, *"a clean sweep of nothing reads as success"*).

3.6 **Runtime facts to record, not assume.** The plan asserts none of these; the first PR push
    settles all three in under two minutes, and /work records the observed values in the
    evidence artefact:
    - Does a workflow **added by this PR** run on the `pull_request` event? (Expected yes for
      a same-repo PR; if the run does not appear, the harness has not run and Phase 3 is not
      done.)
    - How does a job with job-level `continue-on-error: true` and a failed step **render** as
      a PR check? If it renders red, rename the arms to carry the expectation
      (`probe A (RED BY DESIGN)`) — do **not** switch to step-level `continue-on-error`, which
      would flip `steps.outcome.conclusion` to `success` and make the harness test a different
      predicate than the shipped one.
    - Does the jobs API report the matrix job names as `probe A` (the explicit `name:` above)?
      Adjust the verdict's selector to the observed strings if not.

3.7 The harness must pass `bash scripts/lint-workflows.sh` (actionlint) and
    `python3 scripts/lint-workflow-step-env-refs.py` (test A13 asserts the whole tree is
    clean). Every uppercase expansion in its bodies is either declared in that step's own
    `env:` or written guarded.

### Phase 4 — Static assertions in `scripts/lint-workflow-step-env-refs.test.sh` (AC3)

Extend Part B, beside the existing **B1b**. Refactor B1b's inline extractor into one helper
that returns a named step's `if:` from a named workflow/job, then:

- **B1b** (existing, unchanged in intent): the mirror step's `if:` contains `!cancelled()`.
  Re-point its selector from `name.startswith("Mirror non-delivery")` to `id == "mirror"`.
- **B1c**: the mirror step's `if:` contains the anchor
  `steps.outcome.conclusion == 'failure'` — assert the **whole predicate phrase**, not the
  bare token `conclusion` (`cq-assert-anchor-not-bare-token`).
- **B1d**: the email step's `if:` contains **both** `!cancelled()` and
  `steps.outcome.conclusion == 'failure'`. *(Phase 2 only — drop with Phase 2 if cut.)*
- **B1e**: the `outcome` step declares **no** `continue-on-error` key — the invariant that
  makes `conclusion` trustworthy.
- **B1f (the drift guard — the assertion that makes the harness's evidence transferable)**:
  parse `.github/workflows/release-outcome-condition-harness.yml`, extract its `email` and
  `mirror` step `if:` strings, and assert **whitespace-normalized byte-equality** against the
  shipped ones. Without B1f the harness proves something about a string that may no longer be
  the shipped string, and the whole Phase-3 apparatus becomes theatre.
- **B1g**: the harness workflow exists and declares `on: pull_request` — so the pre-merge
  execution evidence cannot be silently switched off by deleting the trigger.

### Phase 5 — Execute the shipped mirror body locally (Part B), and the C4 edges

5.1 Extend Part B to extract the **mirror** step's `run` body (by `id == "mirror"`) alongside
    the existing `email` extraction, and execute it with the existing `curl` stub plus a
    parseable stub DSN (`https://deadbeef@de.sentry.io/12345`):
    - **M1** — `FAILED=""`, `REASON=""` (**the newly-reachable input**): exit 1 *by design*,
      but stderr must **not** contain `unbound variable`, and the captured payload must carry
      the classifier-death message and `"classifier":"failed"`.
    - **M2** — `FAILED="deploy=failure"`, `REASON="resend_http_500"`: exit 1, payload carries
      the original message, `failed_jobs`, and `"classifier":"ok"`.
    - **M3 — mutation proof**: the same body with `${FAILED:-}` rewritten to `${FAILED}` (via
      `sed`, mirroring the existing B5 `step_prefixbare` technique) and `FAILED` absent from
      the env **must** die with `unbound variable` having captured no payload. Without M3, M1
      could pass vacuously against a harness that never exercised the guard.
5.2 Extend Part B's email execution with an arm for the **new third branch**
    (`CLASSIFIER=failure`): asserts the `[RELEASE CHECK FAILED]` subject, the presence of the
    run link, and the **absence** of an empty `<ul></ul>`. *(Phase 2 only.)*
5.3 `knowledge-base/engineering/architecture/diagrams/model.c4`: add the missing edge —

```
  github -> resend "The release-outcome operator email: an inline `curl` to the Resend API from a GitHub runner (NOT via webapp/api), plus the notify-ops-email composite. This is the ONLY push exit for a failed or unverifiable release. Its sibling `github -> sentry` mirror is a fallback that does NOT page: no sentry_issue_alert rule matches gate=release-outcome, so that event reaches the issue stream and not the `sentry -> founder` email route (#7138)." { technology "HTTPS (Resend API, inline curl from the runner)" }
```

5.4 Amend the `github -> sentry` description (`model.c4:528`) to name the `release-outcome`
    mirror's direct store-API POST and its unrouted status. No `views.c4` edit is needed —
    `github` and `resend` are both already included in `view context` and `view containers`,
    so LikeC4 renders the relationship automatically.

### Phase 6 — Verify

6.1 `bash scripts/lint-workflow-step-env-refs.test.sh` → `All tests passed`.
6.2 `python3 scripts/lint-workflow-step-env-refs.py` → exit 0, `0 findings`.
6.3 `bash scripts/lint-workflows.sh` → clean (actionlint over the new + edited workflows).
6.4 `bash scripts/test-all.sh scripts` → the whole scripts-side suite green (this is the
    invocation `ci.yml`'s `test-scripts` job runs; do **not** substitute a hand-enumerated
    file list — the AC must run the gate's own invocation).
6.5 C4 validation: `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
6.6 **Mutation proof for every new static assertion.** For each of B1c/B1d/B1e/B1f/B1g:
    temporarily revert the property it pins, re-run 6.1, confirm **RED** with the expected
    message, restore. Record each RED output in the evidence artefact. An assertion never seen
    red pins nothing.
6.7 **The harness run.** Push, wait for `release-outcome condition harness`, and capture:
    `gh run view <id> --json jobs --jq '.jobs[] | {name, conclusion, steps: [.steps[] | {name, conclusion}]}'`.
    Write the run URL and the full JSON into
    `knowledge-base/project/specs/feat-one-shot-7138-classify-step-failure-alert/verification-evidence.md`.
6.8 **Harness mutation proof.** In a throwaway commit on a scratch branch (never on the fix
    branch), replace both `if:` strings with `always()`, push, and confirm arms **C and D go
    from `skipped` to `success`** — i.e. the verdict job reds. Delete the scratch branch. This
    is what proves the harness discriminates the correct fix from the lazy one. If a scratch
    push is undesirable, the equivalent is a second temporary matrix arm carrying
    `if: always()` on the mirror-shaped step, asserted `success` on a C-shaped input — but the
    push form is preferred because it exercises the real strings.
6.9 `git grep -n "steps.outcome.outputs.failed" .github/workflows/web-platform-release.yml` —
    confirm no remaining consumer keys on the classifier's output alone.

### Phase 7 — Tracked scope-out

File one issue (labels `type/bug`, `deferred-scope-out`, `domain/engineering`,
`priority/p2-medium` — all four verified present via `gh label list`) for the **pre-existing**
routing gap:

> **`op:release-alert-undelivered` reaches no Sentry issue-alert rule, so the release-outcome
> mirror pages nobody.** All 29 `sentry_issue_alert` resources in
> `apps/web-platform/infra/sentry/issue-alerts.tf` are tag-filtered and none matches
> `gate:release-outcome`. `model.c4 sentry -> founder` records that only matched rules reach
> the email route. Pre-existing since #7095; the #7095 plan's R12 deliberately cut a Sentry
> issue alert for this domain on the rationale that the email subsumes it — a rationale #7138
> falsified for the classifier-death case and this PR restores by widening the email.
> **Re-evaluation criterion:** add a `sentry_issue_alert` filtered on `gate == "release-outcome"`
> (auto-applied — `apply-sentry-infra.yml` runs full-root on push to main with an
> `apps/web-platform/infra/sentry/**` path filter, so nothing outside the merge path is
> involved) if the mirror ever fires in production, or when the next release-alerting change
> touches this file.

Scoped out rather than folded in because it is `pre-existing-unrelated`: it affects the
already-shipped email-non-delivery arm identically, it is a prod alert-rule change on a
deprecated beta provider resource, and Phase 2 removes its urgency by restoring the push
channel this PR's failure mode had removed.

## Files to Edit

| File | Change |
|---|---|
| `.github/workflows/web-platform-release.yml` | Phase 1 (mirror `id`, `if:`, `${FAILED:-}` guard, branched message) + Phase 2 (email `if:`, `CLASSIFIER` env, third headline branch, guarded `FAILED_HTML`) + the 1.6 invariant comment |
| `scripts/lint-workflow-step-env-refs.test.sh` | Phase 4 assertions B1c–B1g (+ B1b selector move) and Phase 5 execution arms M1–M3 and the email third-branch arm |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Phase 5.3 new `github -> resend` edge; 5.4 `github -> sentry` description amendment |
| `CHANGELOG.md` | Per repo convention at ship time (bug-fix entry). Not a version bump — `wg-never-bump-version-files-in-feature`. |

Not edited: `scripts/test-all.sh` (the suite is already registered at
`run_suite "scripts/lint-workflow-step-env-refs" …`), `scripts/lint-workflow-step-env-refs.py`
(no linter behaviour change), `views.c4` / `spec.c4` (no new element to include).

## Files to Create

| File | Purpose |
|---|---|
| `.github/workflows/release-outcome-condition-harness.yml` | Phase 3 — executes the shipped `if:` strings on GitHub's own evaluator across six arms |
| `knowledge-base/project/specs/feat-one-shot-7138-classify-step-failure-alert/tasks.md` | Task breakdown |
| `knowledge-base/project/specs/feat-one-shot-7138-classify-step-failure-alert/verification-evidence.md` | AC2's evidence: harness run URL + jobs-API JSON + every mutation-proof RED output. Durable so `/ship` can fold it into the PR body (`/ship` full-replaces the body — a block written by `/work` would be clobbered) |
| `knowledge-base/project/specs/feat-one-shot-7138-classify-step-failure-alert/decision-challenges.md` | The Phase-2 scope deviation, for `/ship` to render + file as `action-required` |
| `knowledge-base/project/learnings/workflow-patterns/<topic>.md` | At `/compound` time — directory + topic only, never a pre-dated filename |

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 (issue AC1).** With the classify step failed, an operator-visible alert is produced:
   harness arm **B** shows the mirror-shaped step `conclusion: success` (Sentry event — the
   issue's stated floor), and arms **A/B** show the email-shaped step `conclusion: success`
   (the push channel — Phase 2). Evidence: the jobs-API JSON in `verification-evidence.md`.
2. **AC2 (issue AC2 — execution, not reading).** `release-outcome condition harness` ran on
   this PR on GitHub's own expression evaluator; its `verdict` job is green; the captured
   `gh run view --json jobs` output matches the Phase-3.3 table for **all six** arms. The run
   URL is in `verification-evidence.md`. No claim in this AC rests on reading the YAML.
3. **AC2b (the harness is not vacuous).** The Phase-6.8 mutation is recorded: with both `if:`
   strings replaced by `always()`, arms **C and D** flip from `skipped` to `success` and the
   verdict job reds.
4. **AC3 (issue AC3).** `scripts/lint-workflow-step-env-refs.test.sh` gains B1c, B1e, B1f and
   B1g (plus B1d with Phase 2), each demonstrated **RED** under its own mutation with the
   output recorded. `bash scripts/test-all.sh scripts` is green — the gate's own invocation,
   not a hand-enumerated file list.
5. **The fix does not move the crash into the compensating step.** Part B arm **M1** executes
   the shipped mirror body with `FAILED=""` and produces no `unbound variable`; arm **M3**
   proves the unguarded form does die. `python3 scripts/lint-workflow-step-env-refs.py` → 0
   findings.
6. **The alert text does not lie.** M1's captured payload carries the classifier-death message
   and `"classifier":"failed"`; the `op` tag is still `release-alert-undelivered`
   (`git grep -c 'release-alert-undelivered' .github/workflows/web-platform-release.yml` → 1).
   Phase 2's third-branch email arm asserts the `[RELEASE CHECK FAILED]` subject, the run link,
   and **no** empty `<ul></ul>`.
7. **No healthy release is paged.** Arm **C** shows both notification steps `skipped`; arm
   **D** shows the mirror `skipped`.
8. **`!cancelled()` is not regressed.** B1b still passes and arm **F** shows the mirror
   `success` with the email-shaped step `failure`.
9. **C4 is true after the change.** `github -> resend` exists in `model.c4`, the
   `github -> sentry` description names the release-outcome mirror, and
   `vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` is green.
10. **Every claim this PR adds traces to a named source.** Each new assertion, comment and C4
    sentence cites a file+anchor, a run URL, or a command output recorded in
    `verification-evidence.md` — not a paraphrase of this plan.
11. `bash scripts/lint-workflows.sh` clean; the harness is **not** added to any
    branch-protection ruleset
    (`git grep -c 'release-outcome condition harness' apps/web-platform/infra/github/` → 0).
12. PR body contains **`Closes #7138`**. Issues #7136, #7137 and #7095 are referenced as
    context only, and none is closed or reopened.

### Post-merge (operator)

**None.** Every step in this plan is executed by CI or by the agent in-session. The harness is
`workflow_dispatch`-able after merge for regression re-verification, but that is optional and
not a prerequisite for anything.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A workflow added by this PR does not run on `pull_request`, so no pre-merge evidence exists | Self-evident on the first push — if the run does not appear, Phase 3 is not done. Fallback per the workflow-dispatch learning: move the probe into an existing `pull_request` workflow that is not the required `test` aggregator |
| Job-level `continue-on-error` renders the failing arms as red PR checks | Cosmetic; the `verdict` job is the signal. Phase 3.6 records the observed rendering and renames arms if needed. **Never** switch to step-level `continue-on-error` — it flips `steps.outcome.conclusion` to `success` and would make the harness test a predicate the shipped workflow does not use |
| The harness passes while the shipped condition has drifted | **B1f** asserts normalized byte-equality between harness and shipped `if:` strings, gated by the required `test` check |
| The harness passes vacuously (an `always()` "fix" also goes green) | Negative-control arms **C** and **D**, plus the Phase-6.8 mutation that must red the verdict |
| `steps.outcome.conclusion` silently disarmed by a future `continue-on-error:` | **B1e** + the in-file comment at 1.6 |
| GitHub sets no env var for an empty step output, killing the mirror under `set -u` | Guarded `${FAILED:-}` (Phase 1.3) **and** proven by execution: harness arm B declares `FAILED` from an empty output, and Part B arm M1 runs the body with `FAILED=""` |
| Widening the email produces a false `[RELEASE FAILED]` page on the dominant sub-case | The third headline branch (2.3) and a distinct subject (2.5); asserted by the Phase-5.2 arm |
| The Sentry mirror still reaches no alert rule | Explicitly tracked (Phase 7), and Phase 2 removes its urgency by restoring the push channel |
| Six extra runner jobs on every PR | Path-filtered to four files, so it runs only on PRs that can break it (~15s per arm) |

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| `act` (nektos/act) | Absent from the repo and this machine, and a *reimplementation* of GitHub's evaluator — proves `act`'s semantics, not the invariant |
| Scratch `workflow_dispatch` workflow, triggered from the branch, deleted before merge | Impossible (`404: not found on the default branch`) and explicitly named as a banned plan shape in `learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md` |
| A local reimplementation of the GHA expression grammar | Reading the YAML with extra steps; the issue rejects exactly this |
| Static assertion only (B1c), no harness | Fails issue AC2 verbatim |
| Add the job to `ci.yml` | An arm must fail a step, which would redden the required `test` aggregator |
| `steps.outcome.outcome` instead of `.conclusion` | More robust against a future `continue-on-error`, but a silent deviation from the issue's suggestion and confusing to read (`steps.outcome.outcome`). B1e closes the same hole explicitly and is CI-enforced |
| Fold in the `sentry_issue_alert` rule | Pre-existing, orthogonal gap on a deprecated beta provider resource that reaches prod on merge. Tracked (Phase 7) rather than folded into a condition fix |
| Mirror-only change (the issue's literal patch) | Produces a Sentry event that matches no alert rule and pages nobody — see §Scope decision. Retained as the separable Phase 1 so the operator can choose it |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- `bash -n` cannot validate a workflow YAML file; use `actionlint` via
  `bash scripts/lint-workflows.sh` for the YAML and `bash -c '<extracted snippet>'` for
  embedded `run:` shell.
- The `if:` strings must stay on **one line**. YAML folding would change the string the drift
  assertion compares and could silently defeat B1f.
- `awk '/start/,/end/'` self-matches on the start line; if any verification here needs a
  region extract, use the flag-based form. All Phase-6 checks use `yaml.safe_load` instead.
- `apps/web-platform` typechecks run as `cd apps/web-platform && ./node_modules/.bin/tsc
  --noEmit`; `npm run -w …` fails (the repo root declares no `workspaces`). Vitest paths must
  match `test/**/*.test.ts` — the C4 tests already do.
- **A plan section that documents the absence of a forbidden pattern must not reproduce that
  pattern's trigger vocabulary.** The first write of this file was blocked by the
  `hr-all-infrastructure-provisioning-servers` PreToolUse hook because the Phase-2.8 paragraph
  enumerated the literal tokens it was certifying as absent — the same shape as #7003, where a
  line documenting an earlier violation reproduced its trigger tokens and reddened the gate.
  Describe the scan; do not quote its needles. The same class bit the Phase-4.5 network gate
  one section later.
- **Auditing one step of a pair thoroughly is not auditing the change.** R1/R4 below were both
  found by reviewers, not by the author, and both are in the *email* step — which this plan
  audited superficially while giving the *mirror* step a guard, three execution arms and a
  mutation proof. When a change makes an input newly reachable in **two** steps, the audit
  budget must be split evenly, not spent on the one the issue happened to name.

## Plan Review Revisions

Consolidated from a 7-reviewer panel (DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, CTO/devex, CPO), escalated to 5+2 by the `single-user incident` threshold.
**Where a revision conflicts with an earlier section, the revision wins.** Each is tagged
`[mechanical]` (auto-applied), `[taste]`, or `[user-challenge]` per ADR-084.

### Correctness — must fix before `/work` completes

- **R1 `[mechanical]` — P0. The EMAIL step has two bare `${FAILED}`, and Phase 2 is what makes
  them reachable.** `web-platform-release.yml:1357` and `:1360`. Line 1357 sits **between** the
  successful `curl` and the `echo "delivered=1"` write. If the expansion ever dies there, the
  email is *sent* but `delivered` is never written → the mirror fires and POSTs *"the operator
  email was NOT delivered"* → the operator gets the correct email **plus** a red run **plus** a
  Sentry event contradicting it. Guard both to `${FAILED:-}` in Phase 2. Found independently
  by DHH (P0-1) and spec-flow (P0-1); the plan audited the mirror's identical defect and
  missed the sibling it was itself making reachable.
- **R2 `[mechanical]` — the `set -u` crash premise was overstated** (applied inline above).
  A declared `env:` key whose expression resolves empty is *set-and-empty*, so `set -u` does
  not fire. The guards in R1 and Phase 1.3 are consistency, not crash fixes. The empirical
  answer is recorded from the harness, not asserted: the mirror stand-in emits
  `[ -v FAILED ] && echo SET || echo UNSET` into the evidence artefact (spec-flow P1-13).
- **R3 `[mechanical]` — de-branch the mirror message** (applied inline above): one
  `${FAILED:-<fallback>}` expansion replaces the branched `MSG`/summary/`::error::` blocks.
- **R4 `[mechanical]` — P0. The email's unconditional closing paragraph is FALSE on the
  classifier-death branch.** `:1342` ends *"Treat it as urgent: nothing reaches production
  until it is resolved."* On the dominant sub-case the release **did** reach production, so
  the email contradicts its own opening two paragraphs later — the exact wrong-urgent-page
  harm the `R_DEPLOY` comment block exists to prevent. Branch it:
  > *"Treat it as urgent — not because your changes are definitely stuck, but because the
  > alarm that tells you when a release fails is currently broken."*
  Add an AC asserting the classifier-death payload does **not** contain
  `nothing reaches production`. (CPO binding; spec-flow P0-5.)
- **R5 `[mechanical]` — unify the two discriminators.** The email branches on `CLASSIFIER`
  (`steps.outcome.conclusion`); the mirror branches on `-z FAILED`. These disagree in a
  reachable state — any command appended after the classifier's `$GITHUB_OUTPUT` block makes
  `conclusion == 'failure'` **and** `failed != ''`, so the email tells the classifier-death
  story while the mirror tells the release-failed story, in one incident. Both steps key on
  `CLASSIFIER`. (spec-flow P1-6.)
- **R6 `[mechanical]` — the classifier-death branch must not preempt a genuine deploy
  failure.** Phase 2.3 places it ahead of the `R_DEPLOY` branch, so a classifier death **plus**
  a real failed deploy under-alarms. `R_DEPLOY` is already in that step's `env:` and is
  unaffected by the classifier dying. Gate the new branch on
  `CLASSIFIER == failure && R_DEPLOY != 'failure'`, degrading toward the alarm per the file's
  own doctrine. (spec-flow P1-7.)
- **R7 `[mechanical]` — P0. Every `B1x` selector must fail on zero matches.** B1e is a
  *negative* assertion selected by `id == "outcome"`; rename that id and the selector matches
  nothing, "no `continue-on-error` found" reads **PASS**, and — because both widened conditions
  reference `steps.outcome.*` — the rename silently restores #7138 with every test green. Add
  an explicit "exactly one step with this id exists" precondition to every selector for
  `outcome`, `email` and `mirror`. This is the plan's own §3.5 principle (*a clean sweep of
  nothing reads as success*) turned on its own static assertions. (spec-flow P1-16.)
- **R8 `[mechanical]` — pin both disjuncts.** B1c/B1d assert only the
  `steps.outcome.conclusion == 'failure'` phrase; deleting the `steps.outcome.outputs.failed
  != ''` disjunct silently reverts every pre-#7138 path while they stay green. Per DHH P1-2,
  promote B1c/B1d from substring anchors to **whole normalized-string equality** against an
  expected literal — strictly stronger, and it subsumes R8 and B1f at once.
- **R9 `[mechanical]` — the verdict job's snippet has no credentials.** Add `GH_TOKEN`,
  `GH_REPO`, `GH_RUN_ID` to its `env:`; as written it fails on every run and the failure looks
  like a harness-design problem. (spec-flow P1-11.)

### Cuts — converged across reviewers

- **R10 `[taste]` — the harness is one-time evidence, not a permanent fixture.** A permanent,
  deliberately-red, **non-required** check is the exact shape of the bug `bf4816455` fixed on
  `main` four commits ago (*"the drift verdict blocked nothing"*). Run it on the PR, capture
  the run URL + jobs JSON, **delete the workflow file before merge**. The run is immutable
  evidence; the durable guard is B1c/B1d/B1e inside the required `test` check, where it
  belongs. This deletes **B1f**, **B1g**, Phase 3.5's completeness sweep, Phase 6.8, AC2b, and
  the entire `continue-on-error` rendering unknown. (DHH P1-4; code-simplicity HIGH-1.)
- **R11 `[mechanical]` — P0. Phase 6.8 cannot execute.** The harness triggers on
  `pull_request` + `workflow_dispatch`; a push to a scratch branch fires neither, and
  `workflow_dispatch` 404s pre-merge — the very learning this plan cites to reject the
  scratch-workflow shape. Its only workable form opens a throwaway PR, which fires
  `claude-code-review.yml` (no `paths:` filter) and spends a **paid** review, colliding with
  `hr-autonomous-loop-skill-api-budget-disclosure`. **Cut 6.8 and AC2b outright**; arm C's
  recorded `skipped` already proves the discrimination (an `always()` condition cannot produce
  that row). State that one sentence in the evidence artefact. (DHH P1-1, spec-flow P0-9,
  CTO P0-1 — three reviewers, independently.)
- **R12 `[taste]` — three arms, not six.** Keep **A** (mirror stands down when the email
  delivered), **B** (the #7138 fix), **C** (negative control that kills a lazy `always()`).
  Cut **D** (same `delivered != '1'` conjunct as A), **E** (already-shipped #7095 path, not
  modified here), **F** (`!cancelled()`, already merged in #7137 and pinned by B1b in the
  required check). (DHH P1-3; code-simplicity agrees on D/F.)
- **R13 `[mechanical]` — cut M2 and M3; keep M1.** M3's blanket `sed` rewrites the branch test
  too, so the mutant dies before reaching the expansion it exists to guard — it goes red for
  the wrong reason and proves nothing. With R2 it is also testing a state GHA cannot produce.
  M2 duplicates the shipped path. (spec-flow P1-12; code-simplicity.)
- **R14 `[mechanical]` — cut verification steps 6.2 and 6.9.** 6.2 is fully subsumed by 6.4
  (`test-all.sh` runs A13, which runs the linter tree-wide). 6.9 has no stated pass criterion —
  the string legitimately still appears in both `if:` and two `env:` blocks after the fix, so
  the check always passes.
- **R15 `[taste]` — acceptance criteria: 12 → 5.** Cut AC2b (R11), AC8 (B1b is a standing
  guard in the required check), AC10 (unfalsifiable — a review habit, not a post-condition),
  AC11 (first clause restates 6.3; second asserts the absence of a change nobody proposed),
  AC12 (`Closes #N` is the repo-wide `wg-use-closes-n-in-pr-body-not-title-to` gate). Merge
  AC7 into AC2 (it is verbatim arm C) and AC9 into 6.5. Drop AC6's
  `git grep -c … → 1` clause — counting a string occurrence is a diff-review note. Survivors:
  an alert is produced (AC1); it was verified by execution incl. the healthy-release control
  (AC2); the static assertions exist and were each seen red (AC3); the fix does not move the
  crash into **either** compensating path (AC5, extended per R1); the alert text does not lie
  (AC6, extended per R4). (DHH.)

### Scope, deferral, and things the plan did not consider

- **R16 `[user-challenge]` — the defect class is live in three other workflows.**
  `scheduled-realtime-probe.yml:175` and `:232`, and `scheduled-inngest-health.yml:388`, all
  gate a notification step solely on a prior step's non-empty output. These are **strictly
  worse** than #7138: they are `schedule:`-triggered, so a red run produces no PR check at all.
  `apply-inngest-rls.yml:254` shows the correct shape (`if: failure() && …`) is already known
  in-repo. The reusable asset is therefore a **linter rule**, not a harness:
  `lint-workflow-step-env-refs.py` already parses every workflow and walks every job's step
  list, so *"a step whose `if:` references only `steps.<X>.outputs.*` must also reference
  `steps.<X>.conclusion` / `failure()` / `always()`"* is ~40 lines against a parser that
  already holds the AST — and it is inside the required check, covering all four instances at
  zero runner cost. **Decision required from the operator:** build the generic rule in this PR,
  or file one tracking issue naming all three call sites. Recorded in `decision-challenges.md`;
  default if unanswered is the tracking issue (keeps this PR's blast radius at one workflow).
  (CTO P0-2.)
- **R17 `[mechanical]` — Phase 7's re-evaluation trigger is circular.** *"if the mirror ever
  fires in production"* conditions the trigger on noticing the event nobody is told about —
  that is the gap itself. Drop that clause; keep only *"the next change that touches release
  alerting,"* and add a dated re-evaluation. (CPO Condition A, binding.)
- **R18 `[mechanical]` — state the Phase 2 ↔ Phase 7 coupling.** Phase 7's deferral is
  defensible **only** because Phase 2 restores the push channel. Add to the plan: *"If Phase 2
  is cut, Phase 7 must be folded in."* (CPO Condition B.)
- **R19 `[mechanical]` — name the residual honestly.** After this PR the only channel that
  pages on a failed release is a single Resend email to a single address, with a fallback that
  cannot page. **Resend degradation still equals silence** — the #7095 single-point shape, one
  vendor over. Add as a `failure_modes` entry. (CPO.)
- **R20 `[mechanical]` — add the uncovered failure modes.** (a) job timeout
  (`timeout-minutes: 5`) or runner death: *no* step runs, `if:` is never evaluated, so neither
  channel fires — outside this fix entirely; (b) run cancellation: `!cancelled()` is a conjunct
  of both conditions and is **never executed as false in any arm**; (c) the Journey-B compound
  case (classifier dead + Resend down + DSN unset) ends in a red run and nothing else, for
  which Phase 7's deferral rationale does not hold. (spec-flow P1-2, P1-3, table rows 2/4.)
- **R21 `[mechanical]` — C4 corrections.** (a) `model.c4`'s `sentry -> founder` says *"21 of
  the 22 rules"*; `issue-alerts.tf` now has **29** — fix the stale count in the same pass, or
  the plan edits a line it leaves false (CPO §6.1). (b) Trim the `github -> resend` label to
  one clause — a C4 relationship label is rendered in a diagram, not an essay, and the proposed
  ~90-word version embeds a claim Phase 7 exists to invalidate with nothing keeping the two in
  sync (DHH P2-3, CTO, code-simplicity). (c) Restrict 5.4 to the count correction; the
  routing-gap narrative belongs to the Phase 7 issue, not a durable architecture model.
- **R22 `[taste]` — subject line.** `[RELEASE CHECK FAILED]` vs `[RELEASE FAILED]` differ by
  one word mid-bracket and collapse under lock-screen truncation — the whole point is
  at-a-glance distinguishability. Use **`[RELEASE STATUS UNKNOWN]`**: differs at the first
  token and names the operator's actual state. (CPO + spec-flow, independently.)
- **R23 `[mechanical]` — Alternatives rows the plan owes.** (a) `workflow_call` reusable
  workflow as the only true single-source-of-truth for the `if:` — **rejected**, because the
  harness must force the classify step to die, which requires a `debug_force_failure` input on
  the production alerting path; a test hook in the only push channel is worse than a duplicated
  string. (b) `contains(needs.*.result, 'failure')` — removes the classifier coupling entirely
  rather than compensating for it. (c) A `CLEAN` sentinel (`echo "failed=${FAILED:-CLEAN}"`),
  making the predicate `failed != 'CLEAN'` — simpler and degrades toward the alarm where
  `conclusion` degrades toward silence, but it misses the classifier-dies-*after*-writing case
  that `conclusion` catches; the two disjuncts cover each other's holes, so **keep both** and
  record the sentinel. (d) Fix the producer (a `trap … EXIT` writing a fallback verdict) rather
  than the two consumers. (code-simplicity MEDIUM-3, CTO Q5, DHH P2-1.)
- **R24 `[taste]` — naming and cadence.** Rename to `release-outcome-condition-self-test.yml`
  to join the existing `*-self-test` family (`gdpr-gate-self-test`, `vendor-pin-verify`,
  `skill-security-scan-corpus`) rather than starting a second lineage in a 70-workflow
  directory. Name each arm self-describingly and unconditionally
  (`probe A — classifier dies, email delivers (fails by design)`). Moot for the file itself
  under R10, but the naming applies to the run that produces the evidence. (CTO P1-1, P1-3.)

### Round 2 — correctness findings against the test harness itself

- **R25 `[mechanical]` — P0. I fabricated a quotation.** §Scope decision attributes to the
  `release-outcome` header comment the phrase *"the operator's only push signal"*. **That
  string does not exist in the workflow.** The header actually says *"The only two push
  notifications in this file hang off `deploy` … and off `await-ci`"* — which says there are
  **two** push channels, not one, and therefore undercuts the sentence it was cited to support.
  Delete the quotation marks and restate the argument from what the file actually says. This
  is the precise failure the plan's own AC10 exists to catch, committed by the plan that wrote
  AC10. (Kieran P1-7.)
- **R26 `[mechanical]` — P0. The existing `curl` stub cannot capture the mirror's payload.**
  `scripts/lint-workflow-step-env-refs.test.sh` scans argv for `-d`; the mirror step posts with
  `--data "$PAYLOAD"`. `$PAYLOAD_CAPTURE` therefore stays empty — M1's and M2's payload
  assertions fail, and M3's `[[ ! -s "$LAST_PAYLOAD" ]]` passes **vacuously for every arm**.
  Extend the stub to `-d|--data|--data-raw` before writing any mirror arm. (Kieran P1-4.)
- **R27 `[mechanical]` — P0. `run_step`'s `env -i` list is missing what the mirror body reads.**
  It passes only PATH, PAYLOAD_CAPTURE, RESEND_API_KEY, VERSION, TAG, FAILED, FAILED_HTML,
  RUN_URL, GITHUB_OUTPUT, RUNNER_TEMP. The mirror body writes to `$GITHUB_STEP_SUMMARY`, which
  under `set -u` aborts with **`GITHUB_STEP_SUMMARY: unbound variable`** — literally the string
  M1 asserts must be absent, producing a false RED that looks like the bug under test.
  Phase 5.1 must enumerate `NEXT_PUBLIC_SENTRY_DSN`, `GITHUB_STEP_SUMMARY`, `RUN_URL`,
  `GITHUB_SHA`, `PAYLOAD_CAPTURE`. (Kieran P1-3.)
- **R28 `[mechanical]` — PyYAML resolves a bare `on:` key to boolean `True`.** Verified against
  the shipped file: top-level keys come back as `['name', True, 'permissions', 'jobs']`, so
  `doc["on"]` raises `KeyError`. Any assertion that parses a workflow's triggers must use
  `doc.get("on", doc.get(True))` or `yaml.BaseLoader`. Wrapped in the test file's
  `if ! …; then fail` idiom it would fail **open** — the vacuity the plan warns about
  elsewhere. (Kieran P2-9.)
- **R29 `[mechanical]` — AC11's path does not exist and its expected output is unobservable.**
  Rulesets live at repo-root `infra/github/`, not `apps/web-platform/infra/github/` (that
  argument exits 128, "ambiguous argument"). Separately `git grep -c` prints nothing and exits
  1 on zero matches, so `→ 0` is not observable under any path; the correct form is
  `! git grep -q … -- infra/github/`. Moot under R15 (AC11 is cut) but the same error must not
  reappear. Phase 0.5's citation of ruleset **14145388** with `context = "test"` is correct.
  (Kieran P1-6.)
- **R30 `[mechanical]` — `model.c4:232` is wrong.** `github = system "GitHub"` is at **:230**;
  232 is a `description` line. All other C4 citations verified. Per
  `cq-cite-content-anchor-not-line-number`, cite the element declaration, not the line — this
  matters doubly because Phase 5 edits `model.c4` and invalidates its own line numbers.
  (Kieran P2-14.)
- **R31 `[taste]` — rename the step id `outcome` → `classify`.** The Alternatives table rejects
  `steps.outcome.outcome` partly as "confusing to read" — but that confusion is entirely an
  artifact of the step id. `steps.classify.outcome` is both readable **and** the strictly more
  robust property (immune to a future `continue-on-error`), which would retire B1e's
  forever-invariant at zero cost. Reconsider against the churn of updating five references.
  (Kieran P2-10b.)
- **R32 `[mechanical]` — extend the Phase 3.6 record-don't-assume list.** It omits the single
  assumption the whole harness rests on: *does job-level `continue-on-error: true` leave
  `steps.<id>.conclusion` reporting `failure`?* (Reviewer confirms yes, and that the harness
  self-detects if not — arms A/B/F would all show `skipped` and the verdict would red rather
  than pass vacuously. Record it anyway.) (Kieran P2-11.)
- **R33 `[mechanical]` — a Sharp Edge of mine is false.** *"The `if:` strings must stay on one
  line; YAML folding would … silently defeat B1f."* A `>-` folded scalar and a one-line plain
  scalar normalize **byte-identical** once whitespace is collapsed, which is what B1f
  specifies. Harmless, but it would lead an implementer to write a stricter and more brittle
  assertion than the plan actually asks for. Delete the Sharp Edge. (Kieran P2-13.)

### Round 3 — the central premise is partly falsified

- **R34 `[user-challenge]` — P0. "The Sentry mirror pages nobody" is NOT established, and the
  repo contains a documented falsifier.** Three defects in my evidence:
  1. **4 of the 29 rules are unreadable from the `.tf`.** `auth_exchange_code_burst`,
     `auth_callback_no_code_burst`, `auth_per_user_loop`, `auth_signout_burst` each carry
     `conditions_v2 = []`, `filters_v2 = []` under `lifecycle { ignore_changes = [...] }`;
     the file's own comment says the placeholder *"is overwritten by import"* and the live
     state is operator-managed in the Sentry UI. My grep-shaped negative proof covers **25 of
     29**, not 29.
  2. **A non-IaC paging path exists.**
     `knowledge-base/project/plans/2026-07-20-fix-anthropic-key-missing-false-page-plan.md`
     records: *"A Terraform alert rule pages the operator — **FALSE** … The page comes from
     Sentry's built-in level→priority derivation feeding the operator's personal notification
     rule."* The mirror POSTs `level:"error"` — exactly what feeds that derivation. The
     companion plan's CHANGE B (an IaC rule to replace it) **never shipped**.
  3. Therefore the honest statement is: *no **IaC** rule routes this event; delivery depends on
     an un-codified personal Sentry rule that cannot be verified from the repo.* **Verify
     against the live Sentry rules API before Phase 2 is written.**
- **R35 `[mechanical]` — P0. "The email is the only push channel" is false; three others
  exist.** The `deploy` job's inline Resend email (`if: failure()`), `reusable-release.yml`'s
  `notify-ops-email` (`if: failure()`), and the `notify-gated` Slack post all fire on a red
  release. **Phase 2's justification survives, but on a different argument:** all three are
  *job-scoped* and structurally silent for failures outside their own job, whereas
  `release-outcome` is the only channel that fires regardless of which job in the graph fails.
  Rewrite the Overview, the Scope decision, and the C4 edge text on that argument — it is
  sound and survives either answer to R34.
- **R36 `[mechanical]` — P0. The harness's designed failure reaches a PRODUCTION ingress the
  plan never enumerates.** `apps/web-platform/app/api/webhooks/github/route.ts` maps
  `workflow_run` → `engineering.ci_failed`, gated on `conclusion === "failure"`, and the
  org-wide App subscribes to `workflow_run`. The `verdict` job has no `continue-on-error` and
  is *designed* to red — so **every genuine harness failure spawns a production leader agent**
  (`server/inngest/leader-prompts/engineering.ci_failed.ts` → `draft_one_click` operator
  action), and Phase 6.8 would trigger it **twice**. My `## User-Brand Impact` says *"if this
  leaks … nothing"* — it never considered that the change adds a new production **event
  source**. Enumerate it there and in Risks; this independently confirms R11 (cut 6.8).
- **R37 `[mechanical]` — job-level `continue-on-error` has ZERO precedent in this repo.** All
  70 workflows were parsed: no job carries it. The semantics are documented only for the
  *step-level* form. Phase 3.6 must observe the **run conclusion** (which gates R36's webhook),
  not merely the check rendering. Also: the cited precedent `gdpr-gate-self-test.yml` declares
  **no job-level `permissions`**, so "copy its permissions conventions" copies nothing.
- **R38 `[mechanical]` — P0. Three acceptance criteria cannot fail.** (a) **AC11a** —
  `scripts/lint-workflows.sh` *"EXITS 0 ON BOTH 0 AND 1 … Only a HANG is failure here"*, with
  **93 findings** as the documented steady state; "clean" is unfalsifiable. Assert on the diff
  in actionlint's finding set for the two touched files. (b) **AC11b** — the path error in R29.
  (c) **AC9** — `c4-code-syntax.test.ts` tests a syntax-highlighting tokenizer and
  `c4-render.test.ts` mocks `spawn` entirely; **neither reads `model.c4`**, so AC9 passes
  identically if the new edge is malformed or absent. The real gate is
  `scripts/regenerate-c4-model.sh` via `lefthook.yml` `c4-model-regenerate`, backstopped by
  `plugins/soleur/test/c4-model-freshness.test.sh`. Repoint AC9. The plan invoked the
  anti-vacuity doctrine for its own new assertions and then shipped three vacuous ACs.
- **R39 `[mechanical]` — a classify *hang* still silences both channels.** With
  `timeout-minutes: 5`, a hung classify (or a run cancelled mid-classify) produces neither
  `failure` nor a written output, and `!cancelled()` structurally blocks the compensating step.
  The Overview claims the fix closes *"the single point whose failure silences every downstream
  channel"*; it closes only the `conclusion == 'failure'` case. State the residual, or add an
  arm. (Merges with R20.)
- **R40 `[mechanical]` — more C4 corrections.** (a) The proposed `github -> resend` label says
  *"the ONLY push exit for a failed or unverifiable release"* — **false for *failed*** per R35;
  rewrite to "the only push exit that fires regardless of which job fails." (b) `model.c4:528`
  already contains a falsehood the plan edits past: *"its `paths:` filter is the 3 rule files,
  not the whole root"* — `apply-sentry-infra.yml` covers the whole tree. Fix in the same edit.
  (c) `model.c4:529` says *"21 of the 22 rules … `byok_cap_exceeded` … NoOne"*; actual is **29**
  rules, 29 `notify_email`, **2** `NoOne`. Citing this stale line as authority for the central
  premise was the weakest link in the chain. (d) Add the derived `model.likec4.json` (637 KB,
  tracked, lefthook-restaged) to `## Files to Edit`.
- **R41 `[mechanical]` — cite ADR-117 for Phase 7.** It is directly on point and uncited: *"A
  monitor that cannot alarm is not a cheap monitor; it is a false claim of coverage."* It
  sanctions exactly the posture Phase 7 takes — `{kind: "none", tracking_issue}`, *"HONESTLY
  UNFED. Costs an owning issue."* Re-argue the deferral on **change-class blast radius** (a
  workflow `if:` is inert until the next release; a new `sentry_issue_alert` triggers a
  full-root prod apply against 29 live rules and ~45 cron monitors) — not on Phase 2's urgency,
  which R34 undercuts.
- **R42 `[mechanical]` — implementation blockers and a retracted figure.** (a)
  `.claude/hooks/security_reminder_hook.py` `WORKFLOW_GLOBS` blocks Edit/Write on
  `.github/workflows/*.yml` — workflow edits must go through Bash. (b) The post-mortem
  `operations/post-mortems/2026-07-29-v0244-1-published-green-with-an-unpullable-image-postmortem.md`
  **retracts the "eight consecutive runs" figure to 15**, and documents `notify-ops-email`
  firing three times while production stayed down — *"the verdict blocked nothing and reached a
  channel nobody acts on."* The Overview repeats the retracted figure and Phase 2 restores that
  same channel; address the post-mortem or state why this alert differs. (c) Follow-up ADR
  worth proposing separately: ADR-031 does not claim IaC is the exclusive source of truth for
  alert routing, yet the actual paging path for `level:"error"` appears to be an un-codified
  personal UI rule — an unmodeled trust boundary on the only remaining alert exit, which is the
  class ADR-117 forbids.

### Verified during review

Three load-bearing claims were independently re-verified by reviewers and **hold**: the 29
tag-filtered Sentry rules with none matching `gate:release-outcome`; `model.c4`'s
`sentry -> founder` confirming only matched rules page; and `gdpr-gate-self-test.yml` as a real
self-bootstrapping `paths:` precedent. The CPO panel signed off the `single-user incident`
threshold as correct-and-a-floor, and approved the Phase-2 scope deviation as *"not scope
creep — the minimum scope that satisfies the issue's own AC1"*, conditional on R4 and R17.
