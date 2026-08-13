---
title: The infra-config gate picks its freshness assertion from whether a push was expected
status: accepted
date: 2026-08-13
issue: 7104
supersedes_claim: "R17.1: asserting frame equality also catches a wiped handler and a post-push tamper"
---

# ADR-186 — Gate freshness is conditional on whether a push was expected

## Context

`apply-deploy-pipeline-fix.yml`'s `Verify infra-config apply succeeded` step proves that a config
push landed on prod host `web-1`. It polls `/hooks/infra-config-status`, which returns a **frame**
describing the last handler run, and adjudicates: count invariant, per-file content match, and a
**freshness pin** requiring `FRAME_START_TS >= APPLY_START_EPOCH` (#7220).

The push is a `provisioner` **on** `terraform_data.deploy_pipeline_fix` (DPF), so it fires only when
DPF is replaced. But this workflow's `on.push.paths` filter is a **superset** of DPF's 22 hashed
triggers — it also contains `server.tf`, `seccomp-bwrap.json` and `apparmor-soleur-bwrap.profile`
(pinned as set equality by `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`). A merge
touching only those fires the workflow, replaces nothing, pushes nothing, and publishes no new
frame — and the freshness pin then reds a run that did nothing wrong. A no-op `workflow_dispatch`
is a fourth such class.

**This is measured, not projected.** Run `31636951749` (2026-08-12, `main` @ `0d644396`): the
paths-filter intersection was exactly `server.tf`, terraform reported `No changes` and
`Apply complete! Resources: 0 added, 0 changed, 0 destroyed`, and the gate red with `STALE FRAME`
naming the 2026-08-06 frame. The gate was red on `main` for this reason when this ADR was written.

## Decision

**The gate selects its freshness assertion from whether a push was expected on this run.**

A new pure adjudicator `infra_config_dpf_replaced` reads the plan the apply consumes and reports
`true`/`false`, returning non-zero on anything it cannot classify. The verify step then branches:

| `DPF_REPLACED` | Assertion | Rationale |
|---|---|---|
| `true` | `FRAME_START_TS >= APPLY_START_EPOCH` (unchanged #7220 pin) | A push was expected, so a frame that predates the apply means the handler died before publishing — the #7220 shape. |
| `false` | `FRAME_START_TS == PRE_APPLY_FRAME_START_TS` | No push was expected, so no *new* frame should exist. Requiring a newer one reds a correct run. |

Three supporting changes are dependencies, not extras:

1. **The apply consumes the saved plan file** rather than re-planning. Previously the destroy-guard
   graded `tfplan` and the apply then discarded it — the graded plan was never applied and the
   applied plan was never graded.
2. **A separate pre-apply capture step** (`id: pre_frame`) records the frame's `start_ts` *before*
   the apply, exporting `PRE_FRAME_STATUS` ∈ `{ok,http404,unreachable,malformed,error}` **and**
   `PRE_APPLY_FRAME_START_TS`.
3. **The verdict lives in `infra-config-gate.sh`** (`infra_config_frame_stability`), driven by
   `infra-config-gate.test.sh` — the same reason #6594 extracted `adjudicate_infra_config`.

## What a `stable` verdict actually establishes — a correction

The plan review (R17.1) justified the equality assert by claiming it also catches *"a post-push
tamper of `hooks.json` or the Doppler token"* and *"a wiped handler [that] still returns 200 with
its last frame"*. **Both claims are false, and shipping them would have put an unmeasured claim in
this ADR — the AP-021 failure this ADR exists to avoid.**

- A **wiped handler leaves the last frame in place**, so `PRE == POST` and equality **passes**.
- The frame records **the last write**; it is not a re-read of the bytes on disk, so a post-push
  tamper does not move it either.

Equality establishes exactly one property: **frame stability across this run** — the endpoint
answered, the frame parses, and it is the same frame it was before the apply, i.e. *no unexpected
push occurred*. It is a divergence detector, not a liveness or integrity detector. Both holes
remain **open** and are tracked separately.

What the assert *does* buy, which R17.1 did not claim: it reds the **plan/apply divergence** — a
credential rotation landing between plan and apply would make the apply push while `DPF_REPLACED`
said no push was expected, and equality catches exactly that.

## The asymmetry rule, stated so nobody tidies it into symmetry

The `true` arm fails closed on missing evidence. The `false` arm, when no pre-reading was obtained,
**degrades and escalates rather than failing closed.** That is deliberate:

> **Fail-closed is proportionate to what the missing evidence would have PROVEN, not to the fact
> that some evidence is missing.**

Concretely, the degraded arm is reachable **only** when the pre-poll failed *and* the post-poll
returned 200 — so the channel is demonstrably reachable now, and a genuinely unreachable endpoint
still reds via the existing `000/502/503` branch. The missing evidence bears only on an anomaly
detector, not on the dying-handler shape (which lives on the `true` arm, where `APPLY_START_EPOCH`
still applies). Failing closed there would trade one false-red class for another on the very
workflow whose false-reds are this change's subject — and a gate that reds on network blips trains
its operator to re-run past it, which is how a real red gets ignored.

**There is deliberately no lower bound on frame age.** On a no-push run an ancient frame is
*correct* — the 2026-08-06 frame was correct on 2026-08-12. Any max-age assert would re-introduce
the exact false-red this change removes. The **upper** bound is a different claim and fails closed
on both sub-arms: a frame claiming to start in the future is a host-clock anomaly or a fabricated
frame.

A green-but-degraded run escalates to Sentry (`op=infra-config-preframe-degraded`, level `warning`)
from **its own step**, not by widening the gate step's `env:`. It does **not** reuse
`infra_config_red_alert`: that helper hardcodes the prefix `"infra-config delivery gate RED: "` and
files a `ci/infra-config-red` issue, both measurably false on a green run. Keeping that helper
monotonic — it means red — is worth more than reusing it.

## Distinction from ADR-072

ADR-072 is the obvious counter-precedent and review will reach for it, so state the difference
plainly. (The plan review characterised it as *"different hook, different lock"*; that is not what
ADR-072 governs, and the real distinction is more useful.)

ADR-072 fixed `await-ci`, a gate waiting on a CI check-run that **was going to arrive** — the
`test` aggregator simply had not been created yet under runner contention. Its remedy was to stop
waiting on a fixed clock and wait adaptively on liveness, failing closed when CI genuinely
concluded red.

This gate's failure is the opposite shape. On a no-push run the newer frame is **never coming**,
because nothing was pushed and nothing will publish one. Waiting longer — the ADR-072 remedy —
cannot help and would only convert a fast false-red into a slow one. The fix has to be a change of
*predicate*, not of patience: assert what should be true on this run (the frame is unchanged)
rather than waiting for something that will not happen.

Both ADRs share one principle, which is worth naming: a gate must assert against the state its run
should actually produce, not against a proxy that merely correlates with success on the common
path.

## Consequences

- **A no-push merge now goes green**, correctly, instead of redding and being re-run by hand.
- **The `host_creates` destroy-guard now grades the plan that is actually applied.** This was a
  pre-existing TOCTOU, fixed as a dependency rather than as a bonus.
- **Free safety improvement:** with `use_lockfile = false`, applying a saved plan makes a
  break-glass apply run outside CI (the ADR-096 path, in no concurrency group) fail closed with a
  stale-plan error instead of silently last-writer-wins.
- **One existing invariant narrows.** `Verify webhook is alive post-apply` sits between apply and
  verify; the pre-apply capture adds no SSH dependency (it is HTTPS through the same ingress as
  verify) and so does not constrain the teardown placement, but the "assert the webhook is alive
  after every apply" invariant is unchanged in scope only because this change adds no second apply.
  PR-B's re-push does add one, and must restate this.
- **Response-file separation is load-bearing.** The pre-capture writes
  `/tmp/infra-config-status-pre.txt`, **not** `/tmp/infra-config-status-response.txt`, because the
  red-gate alert step reads the latter path by literal string and would otherwise adjudicate a
  pre-apply frame as a post-apply one.
- **`server.tf` in the paths filter contradicts its own comment.** The filter carries
  *"server.tf is DELIBERATELY ABSENT from this list and must stay absent (R13)"* at L106 and the
  entry `- "apps/web-platform/infra/server.tf"` at L133, 27 lines below. The workflow does what its
  own comment forbids, and that is the class that produced run 31636951749. Removing it would
  eliminate the class outright but would also stop `server.tf`-borne seccomp/apparmor changes
  applying — a separate blast-radius decision, filed rather than folded in here. The `false` arm is
  correct regardless of how that resolves.

## Alternatives considered

- **`continue-on-error` on the verify step, adjudicating afterwards** (the issue's suggested
  shape). Rejected by the operator and recorded in `decision-challenges.md` (UC1): seven downstream
  steps key off job status — under `continue-on-error` the job reads green at that point, so the
  P0 `#7220` red-gate alert's `failure()` condition goes dark, two steps auto-close GitHub issues
  and one swaps the running container.
- **Skip the freshness pin entirely on the `false` arm** (the plan's original R1(B)). Rejected: DPF
  was not replaced *precisely because* none of its hashed files changed, and `FILE_MAP ⊆
  TRIGGER_FILES` holds (measured 20/20; now pinned by a test), so the per-file content match is
  guaranteed by construction on that arm. Skipping the pin as well reduces it to "the endpoint
  answered 200 and some frame of unbounded age reports `exit_code: 0`".
- **Fail closed when no pre-reading was obtained.** Rejected — see the asymmetry rule above.
