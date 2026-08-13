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
- **R17.4's residual is closed** rather than carried: "assert the webhook is alive after every apply"
  covered apply #1 only, and now covers the re-push too. Impossible under the inline shape.
- **A recovered run is now visible by push, not only by pull.** As otherwise designed it was a green
  job, an unchanged summary, a Sentry event matching no alert rule, and a ledger built not to
  notify. A `**Self-healed:**` line in `Post-apply summary` is the only channel that changes that.
- **The ledger is a counter, not an alert route.** No `sentry_issue_alert` rule matches
  `op=infra-config-repush-attempted`, exactly as #7527 records for
  `op=infra-config-preframe-degraded`. Saying otherwise would be the anti-pattern this work exists
  to avoid.
- **Backend lock handling is now explicit.** `-lock-timeout` on both the re-push plan and apply, so
  a cancelled recovery cannot leave the S3 backend lock held and block every later apply on the sole
  no-SSH remediation path.
- **The re-push re-delivers the same bytes; it is not a credential rotation.** Measured in
  `server.tf`: the payload is two `templatefile()` renders whose inputs are unchanged. This matters
  because #7095 records that a malformed value on that channel bricks a host that cannot be
  re-provisioned.
- **The plan JSON is secret-bearing.** `tfplan-repush.json` carries the live prd Doppler token and
  the webhook HMAC in cleartext — terraform's JSON serialization ignores `sensitive` — so it is
  removed by a `trap ... EXIT` that survives every abort path and is never `cat`ed.
- **C4: no edit.** No new external actor, external system, container or access relationship.

## Alternatives rejected

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
