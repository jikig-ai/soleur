# Decision challenges: feat-one-shot-6612-sentry-terraform-drift

These are decisions taken during `soleur:plan` (headless, one-shot) that depart from a stated
direction. They are recorded per ADR-084, and `ship` renders them into the PR body and files them as
an `action-required` issue.

---

## DC-1: The Sentry token comes from the GitHub repo secret, not `doppler secrets get`

**Date:** 2026-09-24
**Classification:** User-Challenge (the literal wording of the brief was not followed)

**Stated direction.** "Read `.github/workflows/apply-sentry-infra.yml` FIRST and mirror its
`doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain` plumbing (NOT `--name-transformer tf-var`)." The
issue body for #6612 says the same.

**What the file actually does.** `apply-sentry-infra.yml` binds
`SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}` in the step env at every plan and apply site.
It never calls Doppler for this token. Its header says: "SENTRY_IAC_AUTH_TOKEN comes from a GitHub repo
secret (NOT Doppler) per ADR-031 secret-store-divergence". ADR-031 §Authentication records that Sentry
secrets stay in GitHub repository secrets. The Doppler `soleur/prd` copy exists for operator-local runs.

**Decision.** The plan mirrors the actual plumbing: the repo secret, bound as the raw
`SENTRY_AUTH_TOKEN`, with no `doppler run` of any form. This keeps the two stated goals:

- it mirrors the apply;
- it never uses the tf-var transformer.

It also stays consistent with ADR-031 and avoids a second copy of the credential that could go stale.

**What would flip it.** An explicit instruction to read the Doppler mirror anyway. The cost would be a
second credential source for this leg only, with its own staleness failure mode, contrary to ADR-031.

## DC-2: The CTO-required 60 s re-plan debounce was cut in plan review

**Date:** 2026-09-24
**Classification:** Taste (overrides a domain leader's required change on measured evidence)

**CTO requirement.** Before reporting a failure, re-plan once 60 s after a non-zero result. The goal was
to stop an in-flight apply on the unlocked backend (`use_lockfile = false`) from filing a standing
`infra-drift` issue, which has no auto-close.

**Why it was cut.** DHH, code-simplicity and Kieran fired on it, and so did the advisor consult. The
correctness and simplification panels both flagged it, which is the plan-review "delete over fix"
signal.

- **Too short.** The measured window the debounce targets is merge→apply: queue plus setup, 1 to 8
  minutes (runs 35908698925 and 35883604194). The apply's own write window is about 15 s. A 60 s sleep
  cannot cover the realistic window.
- **Already handled.** Transient vendor errors exit 1, which goes to the `[ERROR]` email and never
  files an issue.
- **Buggy.** The debounce carried a mislabelled-retry annotation bug.

**What replaces it.** The Sentry-specific remediation text in the drift issue tells the reader to check
for a queued or in-progress `apply-sentry-infra.yml` run first. It also says to close the issue once
that run converges.

**What would flip it.** A real false-positive `infra: drift detected in web-platform/sentry` issue
filed during a merge→apply window. The right fix then is a pre-plan
`gh run list --workflow apply-sentry-infra.yml --status in_progress` check. That requires
`actions: read` on the drift workflow. A sleep is not the fix.
