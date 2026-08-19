---
title: The infra-config gate may write production, bounded to one graded re-push
status: accepted
date: 2026-08-13
issue: 7104
supersedes_claim: "R18.11: the ADR should record the step-boundary collapse — the boundaries were RESTORED instead"
---

# ADR-189 — A bounded, graded re-push, and no verification surface that actuates

## Context

`apply-deploy-pipeline-fix.yml`'s verification step proves a config push landed on prod host
`web-1`. It cannot recover from the one failure mode the repo has documented at
`push-infra-config.sh`: the handler-bootstrap bridge's `systemctl restart webhook` returns ~10 ms
before the push fires, so the push hits a still-restarting listener. It gets HTTP 202 — the webhook
answers the moment the hook *triggers*, not when the async handler finishes — but no files are
written. The verify step then re-polls a status that will never change and fails. The documented
recovery is a manual `workflow_dispatch` re-run, on a host whose only no-SSH remediation channel is
the one that just failed.

PR-A (#7509) shipped the sensor: a saved-plan apply, the `DPF_REPLACED` discriminator, and the
frame-stability arm. This ADR records what PR-B does with it.

## Decision

**The gate may now write production, bounded to a single shape-gated re-push — and the verification
surface itself never writes.**

Sensing, adjudication and actuation are separate steps:

> A verification gate does not share a step with its own verdict, and does not share a step with the
> write it triggers. The gate senses and adjudicates; when its verdict is *remediate*, the
> remediation is planned and graded in one step and applied in the next; a second invocation of the
> same verification artifact renders the terminal verdict; and the escalation credentials live in
> none of them.

**This reverses what R18.11 asked this ADR to record.** The earlier design put plan, destroy-guard,
narrowness assert, apply and both verification passes inside one step's control flow, and asked for
an ADR recording that step-boundary collapse. The boundaries were **restored** instead. The decisive
argument is that this workflow *already* uses exactly this boundary for its **first** apply —
`Terraform plan` plans and grades (destroy-guard, `host_creates` halt, DPF sensor), `Terraform apply`
consumes the saved plan — roughly 400 lines above where a second production apply was about to be
actuated from inside a verification step.

Four independently-found fail-opens dissolve structurally rather than each needing a conditional:
"a write was attempted" becomes a native step outcome; the `ALLOW_MISSING_STATUS` escape hatch
cannot green a run that already wrote, because pass 2 is a different step that hardcodes it `false`
and never reads the dispatch input; the post-latch window disappears because pass 2 is a fresh
invocation with the existing `sleep 8` preamble and a full attempt budget; and boundedness is
structural, because a step cannot run twice in a job — no latch, and no "set only after execution"
rule to get wrong.

### The extraction, and a deviation from ADR-150

Under the split, both passes run the same ~240 lines. Inline that meant duplicating the body across
two YAML steps — the exact duplication the design had already rejected, and it would have broken the
production call-site pin's `head -1` anchoring. So the body moved verbatim to
`apps/web-platform/infra/infra-config-verify.sh`: **one tested file invoked twice**, rather than 240
duplicated lines of untestable YAML.

**Placement deviates from ADR-150 deliberately** — `apps/web-platform/infra/`, not `scripts/`. Three
reasons, all measured: the body does `source ./infra-config-gate.sh`, a relative path that resolves
only from `INFRA_DIR` (which stays the step's `working-directory`); the directory's convention is
`<name>.sh` + `<name>.test.sh` registered in `infra-validation.yml`, which fixes ADR-150's own
recorded regret that `scripts/cutover-inngest.sh` shipped **without** a companion suite; and the
orphan-suite lint makes that registration impossible to skip silently.

The move is verbatim and was machine-verified, not asserted — the pre-move `run:` block parsed from
the base revision with PyYAML, compared byte-for-byte with no whitespace normalization:

```
pre-move body sha256   2a23f9583fb7c6ad76ded1bf153bb9c6df7c456e6fa64174307178e870d1ed98
extracted body sha256  2a23f9583fb7c6ad76ded1bf153bb9c6df7c456e6fa64174307178e870d1ed98
19774 bytes, 240 lines
```

That check is **not** a standing suite assertion. The technique's prescribed baseline is
`git show origin/main:<the workflow>`, and that revision *becomes* the post-move version at merge —
the baseline flips, and the guard would either fail or pass vacuously for the next contributor. The
same PR then parameterises the script, so a permanent byte-identity assert would be red by its own
second commit. The hashes above are the durable record instead.

### The invariant the cardinality assert pins

**Measured 2026-08-13 against live prd state, read-only:**

```
changing_resources_total  1
managed_mode_changing     1
terraform_data.deploy_pipeline_fix | managed | delete,create
destroy-guard             host_creates=0, resource_deletes=1
```

`host_creates=0` is the load-bearing half and it is the number nothing had ever evaluated.
`deploy_pipeline_fix` carries
`depends_on = [terraform_data.apparmor_bwrap_profile, terraform_data.infra_config_handler_bootstrap]`,
the latter carrying an SSH `remote-exec` provisioner, and `-target` is transitive at the resource
level. Had the plan reached it, the recovery would have run a `remote-exec` against the cloudflared
bridge this job tears down three steps later. It does not.

Before this measurement the safety argument was **circular**: the no-SSH claim rested on the
cardinality assert, and the cardinality assert rested on nothing. The hermetic test stubs
`terraform`, so it certified the stub; production could not reach it. Had the real number been
greater than 1, the assert would have aborted **every** recovery on the failure path of a real
incident — and because the path ships dark, nobody would ever have learned.

The measurement used the **singular** `-target` form that actually ships, not the four-target form
of the first apply. A number that licenses a guard has to describe the command being guarded.

## Consequences

- **The recovery ships dark and cannot be exercised on demand.** After PR-A a no-op dispatch passes
  pass 1, so it no longer reaches the recovery — measured on run `31714143720`. AC14 was withdrawn
  for this reason. What is genuinely unproducible is *"the handler published no frame"*; everything
  downstream of that decision is deterministically exercisable read-only, and
  `terraform apply <planfile>` is already proven in production by that same run. So the first-run
  residual is *"one apply of a plan whose shape was measured"*, not *"the whole recovery"*.
- **Pass 1's soft-fail is the one new failure mode, and it is the catastrophic one.** A mis-keyed
  `if:` would skip every re-push step; pass 2 would never run; and the **five** `success()`-gated
  steps downstream would re-arm — two of which close the founder's GitHub issues, one of which swaps
  the running container. That is #6594's latched false-green reintroduced by its own remedy. Two
  things contain it: an `always()`-keyed terminal-verdict backstop, and a guard pinning every
  workflow `if:`/`env:` reference against the shell that produces it.
- **actionlint cannot see this class, so the guard is not redundant.** Measured at 1.7.7: a mistyped
  **step id** is caught; a mistyped **output name** produces no finding at all, because `outputs`
  types as `{string => string}` so every name is valid. CI's actionlint job also treats rc=1 as
  acceptable and is absent from `scripts/required-checks.txt`. A general
  `scripts/lint-workflow-output-literals.py` belongs to #7527's scope.
- **The apply is keyed on the grade, never on `success()`.** A grading step whose assert was written
  as an `echo` without `exit 1`, or loosened later by an editor "making it work", would otherwise
  let the apply run. Keying on the measured literal means loosening the assert also requires editing
  the `if:` — two producers must agree.
- **R17.4's residual is NARROWED, not closed.** "Assert the webhook is alive after every apply"
  covered apply #1 only, and now covers the re-push too — which was impossible under the inline
  shape.

  > **Corrected 2026-08-19 (#7104 PR-B review, S4).** This read "is closed rather than carried".
  > It is not closed: the probe is gated on `steps.repush_apply.outcome == 'success'`, so an apply
  > that FAILS partway — having already re-delivered some of the FILE_MAP — leaves the listener
  > unprobed. The residual after this change is "every SUCCESSFUL apply", not "every apply". The
  > gap is deliberate (a failed apply has its own terminal arm and its own lever) but it is a
  > narrower claim than the one this bullet made.

  What the probe now buys, and it is the load-bearing part, is that its FAILURE is readable: it
  carries an `id:` and routes to the `unreachable` mode with the `-replace` lever. Before the
  PR-B review it had no `id:`, so a re-push that bricked the sole no-SSH channel was reported to
  the operator as "the infra-config gate never ran (outcome=success)".
- **The re-push apply drops the `doppler run` wrapper, and that is an unvalidated behaviour
  change.**

  > **Recorded 2026-08-19 (#7104 PR-B review, S7).** Apply #1 runs under a `doppler run` wrapper;
  > `repush_apply` does not, because `terraform apply <planfile>` rejects `-var` and takes every
  > value from the graded plan file — which is precisely the property the split buys. But run
  > **31714143720**, cited elsewhere in this ADR as evidence, executed the **wrapped** form. So
  > the unwrapped shape is reasoned-about rather than measured, and this ADR should not have
  > presented it as validated by that run.
  >
  > Why it is nonetheless expected to hold: a saved plan carries its variable values, so the
  > provider needs no `TF_VAR_*` at apply time. Why that is not proof: the provider still needs
  > its own credentials, which reach the step through `env:` rather than through the wrapper.
  > The first firing of this recovery is what will settle it, and #7576 lists it as one of the
  > forensics to read.
- **A recovered run is now visible by push, not only by pull.** As otherwise designed it was a green
  job, an unchanged summary, a Sentry event matching no alert rule, and a ledger built not to
  notify. A `**Self-healed:**` line in `Post-apply summary` is the only channel that changes that.
- **The ledger is a counter, not an alert route.** No `sentry_issue_alert` rule matches
  `op=infra-config-repush-attempted`, exactly as #7527 records for
  `op=infra-config-preframe-degraded`. Saying otherwise would be the anti-pattern this work exists
  to avoid.
- **There is NO backend lock, and `-lock-timeout` is inert.** An earlier revision of this ADR said
  "backend lock handling is now explicit", citing the `-lock-timeout=120s` on both the re-push plan
  and apply. That is false. `apps/web-platform/infra/main.tf:19` sets `use_lockfile = false` — R2
  does not support the S3 conditional writes terraform's native locking needs — so there is no lock
  to time out on and the flag changes nothing. The flags are kept (harmless, and correct the day the
  backend gains locking), but the SOLE serializer for this path is the shared
  `terraform-apply-web-platform-host` concurrency group, and `main.tf:18` already warns against
  dropping that group in the belief that R2 locks. The alert step's re-push-failure arm says the
  same thing to the operator rather than routing them to a lock that cannot exist.
- **The re-push re-delivers the same bytes; it is not a credential rotation.** Measured in
  `server.tf`: the payload is two `templatefile()` renders whose inputs are unchanged.
  - This was previously justified by claiming "#7095 records that a malformed value on that channel
    bricks a host that cannot be re-provisioned." That inflates what #7095 says, and the inflation
    is load-bearing because it is what carried the CPO sign-off threshold. #7095 is titled *"prod
    has not deployed since 2026-07-29 — web-1's baked Doppler token was revoked, so the zot gate
    goes dark and the pull falls through to an unauthenticated GHCR fetch"*: a STALE credential
    serving STALE CODE, with the site UP throughout. No host was bricked and none needed
    re-provisioning. The byte-identity property is still worth stating — it is what makes the
    re-push idempotent — it is simply not backed by a host-bricking precedent.
- **The plan JSON is secret-bearing.** `tfplan-repush.json` carries the live prd Doppler token and
  the webhook HMAC in cleartext — terraform's JSON serialization ignores `sensitive` — so it is
  removed by a `trap ... EXIT` that survives every abort path and is never `cat`ed.
- **Boundedness is per-RUN, not per-issue or per-host.** A step cannot execute twice in one job, so
  "at most one re-push" is structural for the run that fires it. It is NOT a global budget: a job
  RE-RUN produces a fresh, independently eligible re-push, and so does the next push. That is the
  intended behaviour — each run re-senses and re-grades from scratch — but it means the honest claim
  is "one write per run", and anyone reading this as "one write, ever" would be wrong.
- **R17.8's free win, available only because `use_lockfile = false`.** The "assert the webhook is
  alive after every apply" invariant previously covered apply #1 only, and under the rejected inline
  design it was unfixable. Under the step split it is one duplicated step with an `if:`. It is free
  here specifically because there is no backend lock to hold across the extra probe.
- **R20.5's measurement: the window this cannot close is 9 s.** The handler's own
  `webhook-self-restart` fires at `+3 s`, and the observed restart settle is `6 s`, so `6 + 3 = 9 s`
  of exposure remains after any probe succeeds. This is why the Phase 2 readiness probe must be
  advisory-with-timeout and can never be a proof.
- **A verification surface does not actuate — ESTABLISHED HERE, not inherited.**

  > **Corrected 2026-08-19 (#7104 PR-B review, S1).** This bullet previously read *"ADR-072 bans a
  > verification surface from actuating"* and attributed the principle to ADR-186's reading of it.
  > **ADR-072 contains no such principle.** Verified: zero occurrences of *actuate* or
  > *verification surface* in that document; its Option-2 rejection turns on a flock collision, and
  > ADR-186 frames the matter as *signal availability*. No `AP-NNN` covered it either. The
  > invariant genuinely exists and is well enforced in this PR — the false part was the citation,
  > which is worse than no citation: it presents a claim as settled precedent that a reader
  > following the reference cannot find, and the next document to cite it inherits the phantom.

  The principle is therefore stated as ORIGINATING here and registered as **AP-024**. Sensing,
  adjudication and actuation are three separate steps; the production write lives in the actuation
  step, which is not a verification surface. It is enforced by the T5 actuation sweep over
  `infra-config-verify.sh` and by Guard 2 (8) over the sourced library — both allow-lists since
  the #7104 PR-B review, because the deny-list they replaced was measured evadable 8 ways out of 9.
- **What the split separates, and what it does NOT.**

  > **Corrected 2026-08-19 (#7104 PR-B review, S2).** The earlier formulation implied the split
  > separates everything that matters. It separates the WRITE, the BLAST RADIUS, the CREDENTIALS
  > and the VERDICT. It does **not** separate the AUTHORIZATION: `repush_needed=true`, emitted by
  > the verification surface, is the sole authoriser of the production write.

  The honest formulation: *the verification surface authorizes but does not perform the write, and
  what it authorizes is independently shape-graded and independently credentialed.* That is a
  weaker and true claim, and it is the one the guards actually enforce — Guard 3 grades the plan's
  cardinality AND its address set at a step the gate does not control, and `repush_apply` carries
  no `env:` at all.
- **Sunset condition, verbatim from the ruling.** *"Ship the bounded recovery (this PR) first;
  implement the root-cause readiness probe as Phase 2, blocked on the first firing's forensics."*
  When Phase 2 lands and the root cause is named and fixed at source, this recovery becomes dead
  code and should be removed rather than left as a second mechanism nobody reasons about.
  Phase 2 is filed as **#7576**, blocked explicitly on the first firing of this recovery.

  > **Qualified 2026-08-19 (#7104 PR-B review, S6).** As written this sunset is a WISH: it carries
  > no `SOLEUR-DEBT:` marker, no follow-through script, and no ledger row, so nothing will ever
  > raise it. And it is gated on an event measured at **n=1 in ~13 months** — which is the same
  > unfireability argument this ADR uses three bullets earlier to REJECT the >=3-in-30-days
  > escalation trigger. Applying that argument in one direction and not the other is the
  > inconsistency, not the sunset itself.
  >
  > Rather than manufacture a trigger that cannot fire, the honest position is recorded: **this
  > recovery may well outlive its sunset condition, and that is accepted.** The cost of leaving it
  > is one bounded, graded, single-attempt write behind four guards; the cost of a trigger nobody
  > can fire is a document that reads as governed and is not. #7576 carries the removal as an
  > explicit deliverable so the sunset lives on a tracked issue rather than in this paragraph.
- **C4: no edit.** No new external actor, external system, container or access relationship.

## Alternatives rejected

- **Fixing it at the source instead of recovering from it (the CTO's three reasons).** The obvious
  objection to this whole ADR is that a bounded re-push treats a symptom. It was put to the CTO and
  rejected for Phase 1 on three grounds, all verified:
  1. **The root cause is NOT established.** `infra-config-apply.sh:80` does `rm -f "$STATE_FILE"`
     before any work, so a handler that ran and was killed leaves NO frame. Nonce-1 observed a
     *readable stale 13/13 frame*, which means the handler never reached that line. "The async
     handler exec was disrupted" is inference, not measurement.
  2. **A readiness probe cannot be a proof.** `webhook.service` is `Type=simple` (active at fork,
     before the `hooks.json` parse and the `:9000` bind); the bootstrap ALREADY asserts `is-active`
     at `server.tf:164` and that assertion PASSED during nonce-1; and
     `StartLimitIntervalSec=0` + `Restart=on-failure` plus the handler's own `+3 s`
     `webhook-self-restart` reopen the window after any probe succeeds (the 9 s above).
  3. **Blast radius is inverted from the naive read.** This recovery repeats a byte-identical,
     already-authorized, nonce-idempotent write. A fail-closed readiness assertion would instead sit
     inside the SOLE no-SSH delivery path for a host that cannot be re-provisioned (cx33, 0/6
     stock). Phase 2's probe must therefore be advisory-with-timeout, never blocking.

  The ≥3-in-30-days escalation trigger that would normally accompany a recovery like this was
  deliberately NOT built: at the observed rate (n=1 in ~13 months) it is unfireable, so it would be
  a mechanism that never runs pretending to be a safety net.

- **`continue-on-error` on the verification step, adjudicating afterwards.** Rejected in
  `decision-challenges.md`: it converts a fail-closed gate into a fail-open one, which is strictly
  worse than the race it fixes. The step-level error-tolerance key is now banned from this workflow
  by assertion.
- **A higher-order `infra_config_bounded_verify` orchestrator taking a function name.** Cut. The one
  function added is the pure predicate `infra_config_should_repush`; the `if`/`else` that consumes
  it stays in the YAML.
- **A `repush_once` function.** A function invites `if ! repush_once`, which suspends `errexit` for
  a body containing a production `terraform apply`.
- **Widening the poll loop with an inline latched re-push.** Found inert: `infra_config_count_invariant`
  never reads `start_ts`, so on the #7220 shape the invariant *holds* and the loop breaks on attempt
  1 — the re-push was unreachable on the exact shape it existed for. Confirmed independently three
  times.
- **Widening `scripts/infra-config-red-alert.sh` to file the ledger.** Rejected: three labels
  hardcoded across five sites, fail-open by contract, and it means *red* — the ledger is written on
  runs that recovered.
  - **Partly SUPERSEDED at review.** The ledger is still not filed through that helper, and should
    not be: it is a per-run counter, not a notification. But the reasoning above was used to
    conclude that a green recovered run needs no operator-facing record at all, and that conclusion
    was wrong — the Sentry breadcrumb matches no alert rule and the ledger issue is created CLOSED
    and only body-edited, so a production write to the sole no-SSH channel was reaching nobody. The
    helper now carries a fourth `recovered` reach mode with its OWN label
    (`ci/infra-config-recovered`), priority (p2), title, body and Sentry op. The separation is the
    part that mattered in the original objection and it is preserved structurally rather than by
    declining to reuse the helper: `ci/infra-config-red` is the dedupe key, so a self-heal filed
    into it would swallow a real P1 gate failure as a comment.
