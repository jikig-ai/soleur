# Decision Challenges — feat-one-shot-7586-7587-red-apply-no-channel-arm-deadline

Persisted by `plan` in headless mode (ADR-084 / decision-principles.md). `ship` Phase 6 renders this
into the PR body and files it as an `action-required` issue. Each entry is a decision the planning
phase did **not** take unilaterally.

---

## UC-1 — `decisionClass: user-challenge`

**The brief's stated direction.** *"short-circuit the `inngest_consumer` arm while #7228 stays open
(reclaims ~78% of the apply job's runtime). Make the short-circuit self-expiring or loudly
self-reporting so it cannot silently outlive #7228."*

**What the plan recommends instead.** No short-circuit. Resize that one arm's deadline from 230 s to
~30 s (`## Proposed Solution` §3, Cut List **C2**).

**Why the challenge is being raised rather than silently applied.** The brief named a mechanism, and
this is a recommendation against that mechanism. The property underneath it — reclaim the runtime
without the suppression outliving the incident — is fully satisfied, and by strictly less machinery;
but the operator's stated direction is the default, so the substitution is surfaced rather than
assumed.

**The argument for the substitution.**

1. **It preserves a property the short-circuit destroys.** `arm_one` returns 0 via its
   `already armed (status=…)` branch the first time the monitor is live-`up`. A short-circuit never
   re-tests, so once #7228 closes nothing arms the monitor — the "shipped inert and forgotten" shape
   (#6537) the workflow's own block comment already warns about. A 30 s deadline still attempts the
   measurement every apply, so arming remains automatic.
2. **It needs no expiry mechanism at all,** which is the part of the brief's requirement that is
   hardest to keep honest. Nothing is added that could outlive #7228, so there is nothing to expire.
3. **It avoids widening permissions on the highest-privilege job in the repo.** A live
   `gh issue view 7228` read needs `issues: read` on the job that holds production Doppler secrets
   and the fleet-wide apply mutex, and an API blip then becomes either an apply failure or a silent
   revert to hard-arming.
4. **The suppression would have been long-lived.** ADR-100's 2026-08-12 addendum records that #7228
   **cannot close until the #7462 host restore lands** (#7462 verified OPEN). A dated or
   issue-keyed suppression would sit in the workflow for the whole of that window — precisely the
   regime in which self-expiry mechanisms rot (ADR-185's recorded anti-pattern: a one-shot
   verification literal that silently became a permanent ceiling nobody decided on).
5. **The cost is a bounded, self-correcting delay, not a lost property.** With a 30 s window against
   a 180 s feeder period, each apply has roughly a 1-in-6 chance of catching the first beat; at the
   measured 2.71 merge-applies/day the monitor arms within a few days of the feeder coming back, and
   every later apply is a true no-op. The unpause window stays far below the monitor's first absence
   alert (`period + grace` = 240 s), so no false page is possible during a failed attempt.

**What the plan gives up by not short-circuiting.** ~30 s per merge apply instead of ~0 s — about
1.4% of the current apply job, against the ~200 s the resize reclaims. And arming after #7228 closes
is probabilistic-over-a-few-days rather than immediate-on-next-apply.

**If the operator prefers the brief's original direction**, the implementable form is the one the
brief asked for: gate the arm on a live `gh issue view 7228 --json state` read with `issues: read`
added at job level (precedent exists in this same file — `entrypoint_audit` at `:5857` declares
`permissions: { contents: read, issues: write }` and pins an `AUDIT_ISSUE` constant), fail **closed**
to hard-arming when the state is unreadable, and enrol a `scripts/followthroughs/*-7228.sh` probe
using the canonical `gh issue view` body from `scripts/followthroughs/registry-luks-blocker-6929.sh`
with `secrets=GH_TOKEN` in the directive. That is a strictly larger change and the plan does not
recommend it, but it is fully specified here so the choice is real.

---

## Decisions recorded (not challenges — no operator direction changed)

- **The brief's `if: ${{ failure() }}` sibling arm was replaced by a separate `notify-apply-failure`
  job.** Not a challenge: the brief itself instructed *"CRITICAL: `failure()` does NOT fire on
  cancellation … Plan for the cancelled case explicitly … and state in the plan which conditions
  each arm actually covers."* The separate job is the construction that satisfies that instruction;
  the reasoning is in `## Proposed Solution` §1 and Cut List **C1**, and the deciding measurement is
  run `32168637847`.
- **`brand_survival_threshold` was set to `aggregate pattern`, not the `single-user incident` the
  planning phase first proposed.** The operator stated no threshold, so this is a plan-internal
  determination rather than a challenge. It is recorded because it *de-escalates* review rigour: the
  post-mortem covering this same workflow and this same blindness defect declares
  `brand_survival_threshold: aggregate pattern` in its own frontmatter, and declaring a higher
  threshold for the fix than for the incident is incoherent. Give-back: `user-impact-reviewer` is
  retained at review time voluntarily, which the lower threshold would not otherwise require.
