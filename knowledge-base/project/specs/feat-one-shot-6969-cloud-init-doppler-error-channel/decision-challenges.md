# Decision challenges — feat-one-shot-6969-cloud-init-doppler-error-channel

Recorded in headless mode per [decision-principles.md](../../../../plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md)
(ADR-084). These are **not** applied — the operator's stated direction is the default. `/ship` renders
this file into the PR body and files it as an `action-required` issue.

---

## DC-1 — Cut the bounded retry from this PR (`decisionClass: user-challenge`)

**Operator's stated direction (the default).** Issue #6969 scopes three items, of which item (2) is
*"Add a bounded retry with backoff around the download … Keep it fail-closed after the retries."* The
plan implements it (Phase 2).

**The challenge.** Three independent signals argue the retry should be **cut**, shipping the error
channel alone:

1. **`code-simplicity-reviewer`** — the sharpest form: *"R10 is a real defect **created by the retry the
   plan should not be shipping**. The CTO review found true defects; the response was to build machinery
   around them rather than to delete the feature that caused them."* The retry is the sole reason the
   plan needs a distinct `doppler_retry` stage (R20/R29), a false-page analysis (RK9), a latency budget
   against the 900 s boot window (RK5), an attempt-ordering rule, and a baked helper to hold it all.
2. **`knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`**
   — *"If a plan's own text says the deciding datum is currently unavailable, the FIRST deliverable is
   the thing that makes it available — and it ships ALONE, in its own artifact, ahead of any fix."*
3. **`knowledge-base/project/learnings/2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md`**
   — same class: ship the component's own error channel before any black-box remediation.

**Why the plan nonetheless retains it.**
- The issue explicitly scopes it, and scope the operator specified is the default.
- It is **not a fix for a diagnosed cause** — every hypothesis is `UNKNOWN`, so it is not the "fix"
  whose coupling the learning warns about.
- AC-C makes it evidence-**preserving**: each failed attempt emits its own breadcrumb before sleeping,
  so a retry that succeeds still yields exit code, stderr and attempt count.

**Explicitly NOT used as justification.** The argument *"both changes ride the same image and the same
next host birth, so no fire occurs between them"* is **circular** — the `2026-07-16` learning names that
exact reasoning as the failure. It is not part of the case for keeping the retry.

**What is genuinely separable regardless of the decision.** One item in Phase 2 is **not** part of the
retry and should ship even if the retry is cut: **`timeout 45` per attempt with `rc=124` recorded**. The
failing call is the **only unbounded Doppler invocation in `cloud-init.yml`** (measured: 11 bounded
siblings, 1 unbounded — and the unbounded one is the one that failed). Without the timeout the channel
is structurally blind to a hang, which is the most common shape of H1, its own leading hypothesis. That
is error-channel work, not retry work.

**Options for the operator**
| | Option | Consequence |
|---|---|---|
| **A** | **Keep the retry** (what the plan implements) | Ships as planned. Retains R20/R29/RK5/RK9 machinery and their ACs. |
| **B** | **Cut the retry; keep the timeout** | Phase 2 reduces to capture + `timeout` + re-raise. Deletes R20, R29, RK5, RK9, AC-C, AC-D and the attempt-ordering rule. Smallest diff that still ends the blindness. Retry returns as its own issue once a cause is measured. |
| **C** | Cut both | **Not recommended** — leaves the channel blind to a hang. |

**Plan's disposition:** implements **A**, with Phase 2 written as a deliberately separable block so **B**
is a clean descope at `/work` or review time. The plan names the retry as the designated descope target.

---

## DC-2 — `host_name` on the two non-failing emitters (`decisionClass: taste`)

**Challenge (`code-simplicity-reviewer`).** The issue asks for `host_name` on "the whole boot-stage
emitter". The plan scopes it to the **baked** emitter only (one `sed` sentinel, on the failing path) and
defers the `bootcmd` beacon and the inline `_emit` to a tracking issue, on the grounds that folding a
three-site attribution improvement into a P0 error-channel PR makes a rollback expensive.

**Operator's stated direction** was "apply this to the whole boot-stage emitter, not just the doppler
stage". The plan partially narrows that. Flagging rather than silently descoping.

**Disposition:** narrowed, with a tracking issue required before the PR is marked ready.
