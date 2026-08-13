---
title: "I wrote two guards against vacuity, and the vacuity guard was itself neuterable"
date: 2026-08-13
category: best-practices
module: scripts/plugin-delivery-canary.sh
issue: 7490
pr: 7505
tags: [guards, vacuity, mutation-testing, test-harness, redaction, self-reference]
---

# I wrote two guards against vacuity, and the vacuity guard was itself neuterable

## Problem

PR #7505 shipped two new guards over the plugin delivery path: a **legacy-resolver probe**
(`scripts/plugin-legacy-resolver-probe.sh`) that enumerates every settings site which can resolve to
the retired marketplace, and a **delivery canary** (`scripts/plugin-delivery-canary.sh`) that installs
the published plugin in CI and asserts completeness, integrity and freshness of what was delivered.

Both were built with the whole apparatus the repo asks for: eight-row mutation matrices per guard,
synthesized-only fixtures, `--self-test`, and an explicit **anti-vacuity floor** (`if [[ "$cases" -lt
75 ]]; then fail "..."`) whose stated purpose is that "if the fixture builder or the seam silently
stopped producing cases, every row above would vanish and this suite would exit 0 having asserted
nothing."

149 assertions pass across the two suites. Review then found four places where a guard can still hold
while asserting nothing — and the most instructive one is *inside the anti-vacuity floor itself*.

## Root cause

Each of the four is the same defect wearing different clothes: **the guard and the thing it guards
share a failure mode**, so one fault silences both.

1. **The vacuity floor is enforced through the function it is meant to survive.** Both suites end:

   ```bash
   if [[ "$cases" -lt 75 ]]; then
     fail "vacuity guard: only $cases assertions ran; expected >= 75"
   fi
   printf '\nTotal: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
   [[ "$fails" -eq 0 ]]
   ```

   `fail()` increments `fails`; the exit status reads `fails`. So the floor detects "no assertions
   ran" *by calling the assertion machinery*. Neuter `fail()` — redefine it, break its arithmetic,
   lose it to an editing slip — and every row goes quiet **and so does the guard that exists to
   notice the quiet**. The suite prints a total and exits 0. A floor that routes through the
   suspect cannot witness the suspect; it has to `exit 1` directly.

2. **`materialize_reference()` has no fixture.** After three measured transports (per-file
   raw.githubusercontent: unfinished at 30 min against a 15-min budget; codeload tarball: 28 MB of
   ~181 MiB in 300 s; `git archive`: no network, exact), the integrity reference now comes from git.
   But `reference_list()` *falls back to the trees API* when materialization returns non-zero — so a
   broken `materialize_reference` does not fail, it silently downgrades to the transport that was
   measured non-viable. No fixture exercises the fetch-if-missing → archive → extract chain, so
   nothing distinguishes "materialized" from "fell back".

3. **`redact_path` is untested.** It is the jq function keeping operator home paths and unrelated
   repository names out of `measurements.md` and out of bodies posted upstream. Its correctness is
   load-bearing for disclosure, and no assertion covers it. Note it has real logic to get wrong: the
   project prefix must be tried *before* the home prefix, because the project lives under home and a
   home-first substitution would consume it.

4. **Declared sites are deletable without a test noticing.** The probe declares seven precedence
   sites; only `managed-settings` and `user-settings-local` are named in assertions.
   `project-settings-local`, `project-settings` and the rest can be dropped from the chain and all 38
   assertions still pass — the exact under-coverage shape the guard was written to catch in *others*.

The common thread with #7495's learning ([the guard I added created a sixth declaration
site](2026-08-13-the-guard-i-added-created-a-declaration-site-nothing-enforced.md)) is that mutation
matrices prove the rows you wrote are live. They say nothing about rows you did not write, and
nothing about the harness that counts them.

## Solution

Not yet applied — tracked as follow-up work off this PR. The four fixes, and why each is shaped that way:

- **Vacuity floor:** replace `fail "..."` with a direct `printf >&2` + `exit 1`, so the floor cannot
  be silenced by the machinery it audits. Add a meta-test that runs the suite with `fail()` stubbed
  to a no-op and asserts a non-zero exit.
- **`materialize_reference`:** fixture the three arms — sha present in the checkout, sha absent (fetch
  path), sha unfetchable. Assert the fallback is *reported*, never silent: a downgrade to the trees
  API must surface as a finding, since that transport was measured non-viable.
- **`redact_path`:** assert both prefixes and the ordering that makes them work — a fixture whose
  project path is nested under the home path, asserting `<project>` wins.
- **Site coverage:** one assertion per declared site that the site appears in the `--json` site list
  with its resolved path and read status. Cardinality alone is not enough; a renamed site would keep
  the count.

## Key insight

**An anti-vacuity guard must not be reachable through the code path it audits.** The floor in both
suites was written for exactly the right reason and then wired through `fail()`, which put it inside
the blast radius of the fault it was built to detect. The test is mechanical: for each guard, name the
single edit that makes the guard stop firing, then ask whether that same edit also makes the *thing
being guarded* stop reporting. If one edit does both, the guard is decorative.

Generalizes past test harnesses. The same shape appears in item 2 — a fallback that fires on the
failure of the preferred path, reporting nothing, so the degraded mode is indistinguishable from the
good one — and it is the same class as the P1 already fixed in this PR, where an exclusion could
excuse a path the repository actually **serves**, turning the completeness assertion into a tautology.

## Session Errors

1. **The first canary draft was not implementable** — it appended findings to an array that is a
   shell local of a *different* workflow step. Recovery: findings routed out via sanitized job
   outputs. Prevention: when a plan prescribes cross-step data flow in a GitHub Actions workflow,
   name the carrier (job output, artifact, env file) at plan time; "append to `findings`" is not a
   mechanism when the steps are separate processes.

2. **The headless/attached predicate was a disjunction** — which made the attached branch dead code in
   exactly the pipeline that runs the plan. Recovery: corrected to the repo's own conjunction,
   `[[ ! -t 0 ]] && [[ -n "${CLAUDECODE:-}" ]]`. Prevention: for any mode predicate, evaluate it
   against the pipeline that will actually run it before shipping — a branch that cannot be reached in
   its own harness is not a branch.

3. **The canary blamed the delivery channel for a defect in its own invocation.** Recovery: fixed to
   distinguish invocation failure from delivery failure. Prevention: a guard's failure vocabulary must
   separate "I could not run" from "the thing I watch is broken" — conflating them files false alarms
   against an innocent subsystem.

4. **The canary's reference came from the network**, over two transports measured non-viable.
   Recovery: re-materialized from git via `git archive`. Prevention: measure transport cost against
   the job budget *before* writing the consumer; all three measurements are now recorded in the
   script header so nobody re-derives them.

5. **A `shellcheck` directive was never in effect** (P2). Recovery: repaired. Prevention: a
   disable/enable directive that silences nothing is indistinguishable from one that works — assert
   the directive's effect, not its presence.

6. **The heartbeat could never have checked in, and the alarm had a silent state** (P1) — pre-existing
   on `origin/main`: the composite declared three required inputs the calling step never passed.
   Recovery: repaired inline. Prevention: `actionlint` already reports this class; run it over the
   *whole* workflow when adding a job to it, not just the diff.

7. **An exclusion could excuse a path the repository SERVES** (P1), masking non-delivery. Recovery:
   exclusions are now direction-aware — a delivered-MORE path is excused, a served-but-missing path
   fails. Prevention: every exclusion in a completeness comparison needs a direction, and a control
   row proving the exclusion still excuses what it was written for.

8. **The probe had two demonstrated false negatives** (P1). Recovery: both closed with named rows.

9. **PR #7505 conflicted with `main` on a generated artifact** (`model.likec4.json`). Recovery:
   `git checkout --theirs` then re-ran `scripts/regenerate-c4-model.sh`; `c4-model-freshness` and
   `c4-count-parity` both green. Prevention: routed — `merge-pr/SKILL.md` §3.1 now carries a
   generated-artifact row naming the owning generator for each known member.

10. **`rule-metrics-aggregate.sh` exits 5 on its orphan-rule_id gate** — seven hook-emitted rule_ids
    (`pre-merge-auto-close-scan`, `hr-in-github-actions-run-blocks-never-use`, `git-commit-secret-scan`
    and four more) are not tagged in `AGENTS.md`, so compound cannot write `rule-metrics.json`.
    Pre-existing and unrelated to this branch; the aggregator writes *before* exiting, so the partial
    file was reverted per the skill's own guidance. Prevention: the gate assumes every emitting ID is
    an `AGENTS.md` rule, but hooks legitimately emit non-rule diagnostic IDs — the gate needs an
    allowlist for those, or the emitters need registering. One-off for this PR, recurring for the repo.

11. **Ten `hook_self_fault` (unparseable stdin) events in `.claude/.rule-incidents.jsonl`** — PreToolUse
    hooks that ran **with their guards disarmed** (ADR-157). Historical (the log carries null
    timestamps, so none can be attributed to this session) and already surfaced by the aggregator's own
    warning. Noted, not actioned here.

## Tags

category: best-practices
module: scripts/plugin-delivery-canary.sh
