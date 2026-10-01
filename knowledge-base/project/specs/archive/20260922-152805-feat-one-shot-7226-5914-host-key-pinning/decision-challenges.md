# Decision challenges: feat-one-shot-7226-5914-host-key-pinning

These are decisions from plan review that go against the direction the operator stated. They are
recorded here under ADR-084 so the operator can review them outside this headless session.
`ship` renders this file into the PR body and files an `action-required` issue from it.

---

## DC-1: Split the app change (#5914) into a second PR that lands after the first pin publication

**Date:** 2026-09-21
**Classification:** User-Challenge. It moves scope the operator asked for (#5914, git-auth.ts)
out of this PR.
**Raised by:** plan-review. `dhh-rails-reviewer` rated it P0; `code-simplicity-reviewer`
rated it "cut the arm". The two panels agree.
**Status:** open. The plan keeps the operator's direction by default.

The operator dispatched "#7226 + #5914". The plan follows that. It changes git-auth.ts in this
PR and keeps a temporary `accept-new` arm. That arm is reachable only while no pin is loaded
and the store flag is off. It is tracked by #5914, which this PR references rather than closes,
and it must be deleted before the flag is ever turned on.

**What the reviewers propose instead:**

1. **PR-A.** Ships the infra and CI half only: bridge, connection blocks, cutover workflow,
   the git-data key mint.
2. **Operator.** Runs the rung-2 rehearsal, the evidence PR, and the replace. The replace
   publishes the pin.
3. **PR-B.** Ships the app, strict from its first commit, and closes #5914 outright.

**What the proposal removes from this PR:**
- the `null` arm
- the `pin_absent_store_disabled` Sentry op
- the Encryption Posture exception
- Guard 1's exact-count allow-list entry
- the transitional clause in PA-36

**What it costs:** #5914's fix lands days later, behind the rung-2 interlock. Until then the
app keeps accepting any host key (the status quo).

**To accept:** move D4, Guard 5 and the app files into a PR-B plan, and drop post-merge step 5.

---

## DC-2: Redeploying through a forced patch release (D6)

**Date:** 2026-09-21
**Classification:** Taste.
**Raised by:** `dhh-rails-reviewer` (make it a runbook step) and the `cto` devex panel (a heavy
mechanism). The plan keeps D6 because the CPO sign-off requires a *mechanical* bound on how
long the app can run with a stale pin.
**Status:** open. #8211's same-version redeploy is the intended replacement.
