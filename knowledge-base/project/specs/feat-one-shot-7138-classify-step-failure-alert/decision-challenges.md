# Decision challenges — #7138

Recorded headless (no operator was asked). `/ship` renders this into the PR body and files it
as an `action-required` issue.

## DC-1 — The PR widens the **email** condition, not only the mirror

**Class:** User-Challenge (the stated direction is the default; this changed it).

**Your stated direction.** *"Make the mirror step's condition independent of the classifier
having succeeded"* — i.e. change the mirror's `if:` only, per the issue's suggested patch.

**What shipped instead.** Both conditions changed, factored on one shared predicate, plus a
third headline branch in the email body. Phase 2 (the email half) is separable and can still
be cut without touching the core fix.

### The original justification was measured FALSE and is withdrawn

The plan argued the mirror-only fix produces a Sentry event that *"pages nobody"*, because all
29 `sentry_issue_alert` rules in `issue-alerts.tf` are tag-filtered and none matches
`gate:release-outcome`. Plan review (R34) flagged that as only partly established. Pulled from
the **live** Sentry rules API on 2026-08-01:

> There are **30** live rules. The 30th is absent from Terraform: `Send a notification for
> high priority issues`, with `filters: []`, `environment: null`, and conditions
> New/ExistingHighPriorityIssueCondition → `NotifyEmailAction`.

It matches **any** high-priority issue in every environment. Sentry derives high priority from
`level`, and the mirror POSTs `level:"error"`. **The mirror does page the operator**, so the
issue's literal AC1 was satisfiable by the mirror-only change. Full evidence in
`verification-evidence.md` §4.

### Why Phase 2 still shipped

**The channel speaks the operator's language.** On a classifier death the mirror-only fix
produces a Sentry issue titled *"release-outcome: the run-outcome classifier FAILED…"*. You
are explicitly non-technical; that is not an artefact you can act on. The email's UNKNOWN
branch says your changes are live, says the alarm itself is broken, and links the run. That
difference is the whole justification, and it is the one I should have led with.

**An argument I withdrew at review.** An earlier draft led with *"`release-outcome` is the
only channel that fires regardless of which job failed"*. That is true of the **job**, and
the email and the mirror are both **steps inside that same job** — so it argues equally for
the mirror-only fix and distinguishes nothing. `architecture-strategist` caught it. It is
struck rather than demoted, because you read this document to decide whether to cut Phase 2
and a non-sequitur in that position is worse than no argument at all.

The CPO panel approved the deviation as *"not scope creep — the minimum scope that satisfies
the issue's own AC1"*, but did so **before** the premise was falsified. You should know the
basis moved.

**What it cost.** One extra `env:` key, one extra headline branch, one extra execution arm,
one extra static assertion (B1d).

**How to take the other option.** Cutting Phase 2 means reverting the email step's `if:`, its
`CLASSIFIER` env key, the third headline branch, assertion B1d, and Part B arms B6a–B6f.
Phase 1 is untouched by that and still satisfies every acceptance criterion the issue wrote.

**Default taken:** shipped as written (email widened). Say the word and Phase 2 comes out.

## DC-2 — The same defect class is live in three other workflows

**Class:** User-Challenge (expands scope beyond the stated work target).

The CTO reviewer found the #7138 shape live on `main` in three more places:
`scheduled-realtime-probe.yml:175` and `:232`, and `scheduled-inngest-health.yml:388` — each
gates a notification step solely on a prior step's non-empty output. These are **strictly
worse** than #7138: they are `schedule:`-triggered, so a red run produces no PR check at all
and nobody is looking. `apply-inngest-rls.yml:254` shows the correct shape
(`if: failure() && …`) is already known in-repo.

The reusable asset is a **linter rule**, not a harness: `lint-workflow-step-env-refs.py`
already parses every workflow and walks each job's step list, so *"a step whose `if:`
references only `steps.<X>.outputs.*` must also reference `steps.<X>.conclusion` /
`failure()` / `always()`"* is roughly 40 lines against a parser that already holds the AST —
inside the required check, covering all four instances at zero runner cost.

**Options:** (a) build the rule in this PR and fix the three sites; (b) build it advisory-only
and fix in a follow-up; (c) file one tracking issue naming all three.

**Default taken:** (c) — filed as **#7143**, keeping this PR's blast radius at one workflow.
The three sites are unchanged and still live.

## DC-3 — Two failure modes this PR does not close

Not a choice so much as a disclosure, because the Overview originally claimed this fix closed
*"the single point whose failure silences every downstream channel"*. It closes the
`conclusion == 'failure'` case only.

1. **A classify *hang*, or a cancelled run, still silences both channels.** With
   `timeout-minutes: 5`, a hung classify produces neither a `failure` conclusion nor a written
   output; and `!cancelled()` is a conjunct of both conditions, so a cancellation structurally
   blocks the compensating step.
2. **Resend is still a single point of failure for the push channel.** After this PR the only
   channel that *pages* in plain language is one Resend email to one address — the #7095
   shape, one vendor over. The Sentry mirror is a real second exit, but only via the
   un-codified rule DC-1 describes, tracked as **#7142**.
