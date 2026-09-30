# Decision challenges — feat-one-shot-8572-git-data-pin-fault-paging

Plan-time Taste and User-Challenge findings that were not applied silently, recorded per ADR-084 so
they are auditable outside the headless planning session. `ship` renders this record into the PR
body.

---

## DC-1 — Legal markers land in the PR, conditioned on the deploys (the CLO ruling stands over DHH and simplicity)

**Date:** 2026-09-28
**Classification:** Taste
**Decision:** The CLO ruling is kept.

- DHH and code-simplicity proposed leaving `article-30-register.md` and the counsel audit out of
  this PR. Their version writes each superseded marker once, in the post-apply evidence PR, as a
  fact rather than a condition.
- The CLO ruled the opposite. Waiting leaves the register saying "no alert routes" once an alert
  does route (the stale-truth defect, #8207 rule). So the markers land here, conditioned on the
  merge and both deploys, and a dated verification line follows (the #9077 precedent).
- The brief routes legal forks to the CLO, so the CLO ruling governs. The cost is one small
  evidence PR.

## DC-2 — The derived rule counts in C4 and README prose stay

**Date:** 2026-09-28
**Classification:** Taste
**Decision:** The counts are kept, updated with a grep-derived formula (AC8).

- DHH proposed rewording the `model.c4` `sentry -> founder` edge and the sentry README so they carry
  no count. That would end the count churn on every alert PR.
- Rejected here as out of scope: it rewrites a convention other PRs chose (#8505, #8630, #8719).
- Worth a separate decision if the count churn keeps costing review time.

## DC-3 — The push-side `pin_absent` / `pin_invalid` / `ssh_client_absent` arms stay (simplicity review rejected)

**Date:** 2026-09-28
**Classification:** User-Challenge (it would narrow the operator's stated scope)
**Decision:** The operator's direction is kept.

- Code-simplicity proposed classifying only `host_key_mismatch` on the push. Its reasoning: the pin
  and the ssh client are process-wide, so the boot event already reports the other three.
- Kept, for two reasons:
  - The boot event fires once per boot, so it cannot keep re-paging while a fault persists (P4).
    The push arms emit at every session end.
  - Issue #8572's acceptance names the push op explicitly.

## DC-4 — The CTO's shared erasure/push classifier is deferred

**Date:** 2026-09-28
**Classification:** Taste (the domain leader was overruled on risk)
**Decision:** The shared classifier is deferred to #9152, characterization tests first.

- The CTO recommended moving `removeGitDataRepo` onto the new classifier to prevent drift.
- The plan-time advisor, DHH, code-simplicity, Kieran and architecture-strategist found this could
  re-bucket Art. 17 erasure outcomes that the existing tests do not cover. Examples: exit 128 over
  ssh, empty stderr, a `null` fallback.
- The erasure path is untouched in this PR. The two paths share only the `SSH_HOST_KEY_MISMATCH`
  constant.
