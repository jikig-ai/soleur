# Decision Classes — feat-one-shot-orphan-sweep-readonly-token

Tracker #9927 and #10112 (both stay open: `Ref #9927`, `Ref #10112`; never a closing keyword). Branch
`feat-one-shot-orphan-sweep-readonly-token`, draft PR 10936. This run is a worker fork and cannot spawn the CTO agent; the
technical forks below are answered by the standing CTO ruling of 2026-10-20 (PR 10652, finding F3), quoted in the Ruling cell,
and by the in-repo precedent it points at. None was put to the owner.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 Whether and how to convert the two orphan-sweep jobs from the loader-exported token to the read-only token | technical | Ruled by CTO agent, 2026-10-20: the sweep steps keep the loader-exported token in PR 10652 and a separate follow-up issue is filed; converting the two jobs' authentication needs its own step-level tests and is a separate least-privilege change. Applied here as that follow-up: the shape of `sole-copy-protection-check` (no environment, no loader, pinned Doppler install, one bounded read of `HCLOUD_TOKEN_READONLY`, no fallback) with step-level suite rows R7 and R8. |
| T2 Replacement for the main-only guarantee the dropped `infra-privileged` environment carried | technical | Ruled by CTO agent, 2026-10-20: follow the precedent of `sole-copy-protection-check`, a job-level `if: github.ref == 'refs/heads/main'` (hygiene, not a security boundary) - the runbook Group 3 table records that job as Tier A with no environment. |
| T3 Project identity of the read-only token inside the sweeps | technical | Ruled by CTO agent, 2026-10-20: no duplicate pin; the sole-copy check already pins the Inngest store volume by name and Hetzner id on the same secret and pages on `volume-not-found`, so a token for another project is already a paged condition. Dependency recorded in the plan and the runbook. |
| T4 De-duplication of the failure email against the rung-2 job's existing email step | taste | Gate the new email on `failure() && steps.notify_channel.outcome != 'success'`, so one failed run sends one message. Cheap to reverse. |
