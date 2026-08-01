# Decision challenges — #7138

Recorded headless (no operator was asked). `/ship` renders this into the PR body and files it
as an `action-required` issue.

## DC-1 — The plan widens the **email** condition, not only the mirror

**Class:** User-Challenge (the stated direction is the default; this proposes changing it).

**Your stated direction.** "Make the mirror step's condition independent of the classifier
having succeeded" — i.e. change the mirror's `if:` only, per the issue's suggested patch.

**What the plan does instead.** It changes the mirror's `if:` **and** the email step's `if:`,
factored on one shared predicate, plus a third headline branch in the email body.

**Why.** The mirror-only fix produces a Sentry event that pages nobody:

- All 29 `sentry_issue_alert` rules in `apps/web-platform/infra/sentry/issue-alerts.tf` are
  tag-filtered; none matches `gate:release-outcome` / `op:release-alert-undelivered`.
- `model.c4`'s `sentry -> founder` edge records that Sentry pages a human only for events a
  rule matches.
- `main-health-monitor.yml` monitors `scripts/test-all.sh` on main and has no knowledge of
  `web-platform-release.yml`. There is no other backstop.
- The #7095 plan's R12 cut a Sentry issue alert for this domain on the rationale that the
  email subsumes it — a rationale that holds only while the email can fire, which is exactly
  what #7138 breaks.

So the issue's literal AC1 floor ("Sentry event at minimum") is satisfiable without the
operator ever being told. Widening the email restores the push channel.

**What it costs.** One extra `env:` key, one extra headline branch (~8 lines of shell), one
extra Part B execution arm, one extra static assertion (B1d). The new branch is a distinct
subject (`[RELEASE CHECK FAILED]`, not `[RELEASE FAILED]`) precisely so the dominant sub-case —
classifier dies while every other job succeeded — is not paged as a false release failure.

**How to take the other option.** Plan Phase 2, task group T2.x, assertion B1d and Part B arm
5.2 are the complete set. Deleting them leaves Phase 1 intact and still satisfies every
acceptance criterion the issue wrote.

**Default if nobody answers:** the plan ships as written (email widened). Say so if you want
Phase 2 cut.

## DC-2 — The same defect class is live in three other workflows

**Class:** User-Challenge (expands scope beyond the stated work target).

The CTO reviewer found the #7138 shape live on `main` in three more places:
`scheduled-realtime-probe.yml:175` and `:232`, and `scheduled-inngest-health.yml:388` — each
gates a notification step solely on a prior step's non-empty output. These are **strictly worse
than #7138**: they are `schedule:`-triggered, so a red run produces no PR check at all.
`apply-inngest-rls.yml:254` shows the correct shape (`if: failure() && …`) is already known.

The reusable asset is a **linter rule**, not a harness: `lint-workflow-step-env-refs.py`
already parses every workflow and walks each job's step list, so *"a step whose `if:`
references only `steps.<X>.outputs.*` must also reference `steps.<X>.conclusion` /
`failure()` / `always()`"* is ~40 lines against a parser that already holds the AST — inside
the required check, covering all four instances at zero runner cost.

**Options:** (a) build the rule in this PR and fix the three sites; (b) build the rule
advisory-listing them and fix in a follow-up; (c) file one tracking issue naming all three.

**Default if unanswered:** (c) — keeps this PR's blast radius at one workflow.

## DC-3 — The plan's central premise is partly falsified (see R34)

"The Sentry mirror pages nobody" is not established: 4 of 29 alert rules are `ignore_changes`
placeholders unreadable from the `.tf`, and the repo documents a **non-IaC** paging path
(Sentry's built-in high-priority derivation feeding a personal notification rule) that the
mirror's `level:"error"` payload feeds. Phase 2's justification survives on the **job-scope**
argument instead (R35), but if you want the original argument, the live Sentry rules API must
be queried first. Flagged because the scope deviation in DC-1 was sold on the falsified
premise.
