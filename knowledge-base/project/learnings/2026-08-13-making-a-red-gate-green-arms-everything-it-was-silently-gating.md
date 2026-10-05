# Making a red gate correctly green arms everything it was silently gating

**Date:** 2026-08-13
**Issue:** #7104 (PR-A) · PR #7509
**Category:** integration-issues

## Problem

`apply-deploy-pipeline-fix.yml`'s infra-config gate red on every run that legitimately pushed
nothing. The push is a provisioner on `terraform_data.deploy_pipeline_fix`, so it fires only when
that resource is replaced — but three merge classes (`server.tf`, `seccomp-bwrap.json`,
`apparmor-soleur-bwrap.profile`) are in the workflow's `on.push.paths` and in none of DPF's 24
hashed triggers. Measured live on run `31636951749`: paths-filter intersection exactly `server.tf`,
`Apply complete! Resources: 0 added, 0 changed, 0 destroyed`, then `STALE FRAME`.

The fix — a sensor reporting whether a push was expected, and a freshness assertion selected from
it — was straightforward. **What was not straightforward is what turning that red green did to the
rest of the job.**

## Key insight

**A red step is not only a report. It is a gate on everything downstream of it, including
conditions nobody wrote down.**

Six `if: success()` steps had never been reachable on a no-push run, because the gate red first.
Two of them close the operator's GitHub issues with the comment *"Server state was re-aligned with
HEAD."* On a zero-change apply nothing was re-aligned — so the correct fix made the workflow start
asserting something false to a non-technical founder, on the exact artifact class the plan's own
`## User-Brand Impact` section named as its red line (it named it as the consequence of a
hypothetical fail-open bug, never of the intended behaviour).

The generalisation: **when a fix turns a failing path green, enumerate what that path was
previously preventing, not just what it now reports.** The red was standing in for a condition, and
the gate has to grow that condition explicitly (here: `PLAN_HAS_CHANGES`, derived from the saved
plan — deliberately *not* keyed on `DPF_REPLACED`, since a seccomp/apparmor merge genuinely does
re-align the host without replacing DPF).

## Four more findings from the same review

**A degrade-and-pass arm whose selector the subject controls.** Three of the four "degraded"
tokens were chosen by how the *host being verified* answered: 404, a 200 without a numeric
`start_ts`, or no answer. A wedged or compromised host could decline to be verified and the gate
passed. Fix: keep one assertion sourced from a value the subject cannot influence (`APPLY_START_EPOCH`,
runner-side). **For any arm selected by an input, ask who controls the selector.**

**A verdict dispatch ending in a bare `else`.** The failing side of the dispatch had a fail-closed
default; the passing side did not, so adding one `case` arm to the adjudicator would have created a
new exit-0 path with no edit to the workflow at all. Found by a structural-enumeration seat asked
for a *map* of every path to exit 0 — not by any of the adversarial agents.

**Under-claiming is the same AP-021 miss as over-claiming.** The ADR corrected a plan-review
over-claim ("the equality assert catches a wiped handler") and landed on an under-claim: a wipe
reaching `hooks.json` or the state file *is* detected, so the honest undetected class is narrower.
Both directions are unmeasured claims.

**I wrote a false claim in the act of correcting one.** A plan revision gave a wrong reason for
keeping the doppler wrapper on the apply; I replaced it with my own ("provider config is read from
the environment at apply time"), and review measured that wrong too — every provider takes `var.*`
and a saved plan carries variable values. Two successive drafts, two unmeasured claims, in the
comment congratulating itself for the correction. **The moment you correct someone's reasoning is
the moment your replacement reasoning goes unchecked.**

## The mutation battery was one-axis

A 16-mutation battery reported all-caught. It only ever edited the SUT's decision logic, so it was
structurally blind to three things review found:

- **Neutering `fail()` to a no-op** made the suite print `94 passed, 0 failed`, `OK`, exit 0 — with
  a genuinely broken assertion present. Worse, the anti-vacuity assertion-count floor was itself
  dispatched *through* `fail()`, so the one-line mutation that disarmed every assertion disarmed
  its own backstop.
- **Neither new sensor had a production call-site pin.** Replacing
  `DPF_REPLACED=$(infra_config_dpf_replaced …)` with `DPF_REPLACED=false` left the suite at 100/0
  while pinning every run onto the no-push arm and permanently disabling the #7220 freshness pin —
  the precise blind spot the PR exists not to restore. A pin for exactly this reasoning already
  existed in the same file for `adjudicate_infra_config`, and was not carried to the new code.
- **The TS containment block had no negative control**, so a partial parse, a predicate hardwired
  to `false`, and a trigger set matching everything all passed 112/0.

**Enumerate the AXES a battery edits, not the count it reports.** N mutations on one axis is one
mutation. The axes that recur as blind spots: dispatch (the harness's own `pass`/`fail`), the
production call site, fixture direction, fixture cardinality, and whether the harness fabricates
the truth it verifies.

Corollary now applied here: an assertion floor must adjudicate *directly* (`echo` + `exit 1`), never
through the function it exists to backstop, and the harness needs a known-negative self-test —
**an instrument that has never been shown to emit a FAIL has not returned a pass.**

## Process notes

**Resume stalled agents; don't respawn them.** Three of seven review agents hit the stream watchdog
from wide reads (a 1450-line workflow). Resuming with bounded read scopes — line-anchored
`sed -n` windows under ~120 lines, and instructions to emit findings incrementally — recovered all
three with transcripts intact.

**A dissent can be right.** Two agents disagreed on whether a reporting step's `always()` should
become `success()`. The dissent was correct (the step runs immediately after the gate, so a later
failure cannot retroactively change its `if:`, and `success()` would only delete the event on
cancellation, where thin evidence is more interesting). Followed the dissent over the first report.

## Session Errors

**Killed a suite runner's wrapper and runner PIDs but not its fan-out workers.** `run-registered-suites.sh`
parallelises via `xargs -P 6`; killing the two PIDs I launched left six workers orphaned, still
spawning `ubuntu:24.04` containers 46 minutes later, on a machine the operator had twice flagged as
contended. — **Recovery:** resolved the tree root via `ppid`, verified its `cwd` was my worktree,
killed root+descendants, and removed only the containers whose mounts pointed at that suite's
scratch dir. — **Prevention:** killing a process tree means resolving descendants (`pstree -p`, or
the process-group), never the PIDs you launched; and verify with a follow-up probe rather than
assuming the kill took.

**Stated which files fired the workflow before measuring.** Named `soleur-host-bootstrap.sh` /
`vector.toml` from a truncated `--stat`; the actual paths-filter intersection was exactly
`server.tf`. — **Recovery:** `comm -12` of the commit's file list against the filter. —
**Prevention:** the conclusion happened to survive, which is what makes this the dangerous shape —
measure the intersection before naming its members.

**Wrote "22 hashed triggers"; it is 24.** Counted `file()` path literals and dropped the two
rendered locals (`local.hooks_json`, `local.webhook_doppler_token_env`), and it propagated to four
artifacts. — **Recovery:** re-derived three ways (server.tf block, `TRIGGER_FILES`, paths−extras),
swept by grepping the OLD claim. — **Prevention:** this session's own findings section records
catching that exact granularity error once, for the containment measurement, and it recurred one
section later. A measurement corrected in one place is not a lesson learned; re-derive every
sibling count at the same granularity in the same pass.

**Replaced one unmeasured claim with another.** See above. — **Recovery:** recorded the measured
truth (the wrapper is a no-op) rather than a third plausible reason. — **Prevention:** treat your
own correction as a new claim needing its own evidence, not as inheriting the credibility of the
error it replaces.

**Under-claimed in the ADR.** — **Recovery:** narrowed to the measured class. — **Prevention:** ask
both "is this stronger than what I measured?" and "is it weaker?".

**Did not re-run the ship-side suite after editing the workflow.** The saved-plan apply removed
`terraform apply -target=`, redding three co-target tests in a suite I had run *before* that edit.
— **Recovery:** re-ran on rebase, re-expressed the invariant, mutation-proved it three ways. —
**Prevention:** derive the suite set from `git grep -l` over the changed files' symbols, not from
the suites you remember touching.

**Two unbounded commands.** A subject-check loop over all of `HEAD`'s history and a
`grep -rn '\b22\b'` across the repo, both producing thousands of lines. — **Prevention:**
`hr-never-run-commands-with-unbounded-output` applies to verification greps too; scope to
`git diff --name-only origin/main...HEAD` and `cut -c1-N`.

**Added a consumer with no producer.** Referenced `STABILITY_VERDICT` in the alert step before
wiring it into that step's `env:`. — **Recovery:** caught in the same turn by a producer/consumer
parity check. — **Prevention:** after adding any cross-step value, grep producers and consumers and
compare the counts.

**Ambiguous anchor in a scripted edit** (`RUN_URL:` matched twice). — **Recovery:** the
`assert count==1` aborted before writing, so the file was unchanged. — **Prevention:** this is the
guard working; keep `assert s.count(old)==1` on every scripted replacement.

**Forwarded from the plan phase (session-state.md):** the plan-write guard blocked two writes on
false positives (resolved by rewording, correctly, not via the `iac-routing-ack` opt-out); the
deepen-plan Phase 5 fan-out was not executed and was disclosed rather than left silent; and
`## Implementation Phases` / `## Test Scenarios` were not regenerated — now repointed at a single
Implementation Findings section rather than regenerated into a third drifting copy.

## Tags

category: integration-issues
module: apps/web-platform/infra, .github/workflows
