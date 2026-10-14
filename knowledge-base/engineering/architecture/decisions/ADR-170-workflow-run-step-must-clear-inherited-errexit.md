# ADR-170 — A workflow `run:` step must clear inherited errexit before treating an exit code as data

- **Status:** accepted
- **Date:** 2026-08-06
- **Extends:**
  [ADR-166 — a CI-emitted operator-facing message may only name a cause the job measured](ADR-166-a-ci-message-may-only-name-a-cause-the-job-measured.md)
  (substantively, not merely as precedent for the gate's shape — see *Relation to AP-021* below:
  the defect this ADR fixes was itself producing two distinct AP-021 violations, and it also
  supplies the precedent that a recurring operator-facing CI defect class earns a
  `scripts/lint-*` gate registered in `test-all.sh`),
  [ADR-126 — cron liveness must assert the consumed artifact](ADR-126-cron-liveness-must-assert-the-consumed-artifact.md)
  (a check must assert the thing it claims about — here, that the alerting path is REACHABLE,
  not merely that the workflow is green)
- **Related:** #7311 (the deferred latent class this ADR's rule deliberately does not reach)
- **Supersedes:** nothing
- **Issue:** #7304
- **Enforced by:** `scripts/lint-workflow-errexit-capture.py` +
  `scripts/lint-workflow-errexit-capture.test.sh`, registered in `scripts/test-all.sh` (the
  `scripts` shard feeds the aggregate `test` job, which is in the CI Required ruleset — so this
  is **blocking**, not advisory). Ships with **no** `.highwater`: the tree is at 0.

## Context

GitHub invokes a `run:` step that declares no `shell:` key as `/usr/bin/bash -e {0}`. Errexit is
therefore already on before the body's first line, and the house-standard opening line
`set -uo pipefail` only *adds* flags — it cannot clear one. `shell: bash` does not change this
either: Actions maps it to `bash --noprofile --norc -eo pipefail {0}`.

The consequence is that the capture-then-branch idiom does not work as written:

```bash
set -uo pipefail
terraform plan -no-color -input=false -out=tfplan
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "::error::terraform plan failed (exit $rc)"
  exit $rc
fi
set -e          # <- the re-arm, with no matching `set +e`, is the tell
```

On a failing command the shell dies **at the command**. `rc=$?` never runs, and every line below
it — the `$GITHUB_OUTPUT` write, the `::error::` annotation, the issue filing, the email — is
unreachable. The failure is perfectly silent: the step simply stops.

This class is invisible until the failure path runs, which is exactly when it must work.

### Six occurrences, and what was already tried

| # | Site | Fixed | Enforcement added |
|---|---|---|---|
| 1 | `reusable-release.yml` token-preflight | earlier | in-workflow comment |
| 2 | `apply-web-platform-infra.yml` GHCR restore | earlier | in-workflow comment |
| 3 | `git-data-rung2-rehearsal.yml` capture poll | #7025 / 2026-07-30 | in-workflow comment |
| 4 | `scheduled-supabase-advisor-scan.yml` | 2026-07-30 | in-workflow comment |
| 5 | `follow-through-closure-guard.yml` | 2026-07-30 | in-workflow comment |
| 6 | `scheduled-prod-version-drift.yml` | **this ADR** | **mechanical gate** |

Occurrence 6 is what forced the decision. The checker it calls returns 0 for the two QUIET
verdicts (`CLEAN`, `DRIFT_PENDING`) and 1/2 for the two that ALERT (`DRIFT_SUSTAINED`,
`CHECK_ERROR`). Errexit therefore killed the step on **exactly the two verdicts the alarm exists
to raise** and let the silent ones through — an alarm that is quiet when it has nothing to say
and dark precisely when production is stale. It failed 8 of 8 scheduled runs emitting zero
diagnostic output.

The 2026-07-30 plan that fixed occurrences 3–5 stated in its own text that the repo already
carried four learnings plus five in-workflow comments on this rule and it had still recurred. It
responded by fixing siblings by hand and appending to a learning. **It built no mechanical
gate.** Six days later — `447211a1a` 2026-07-30T22:40 to `1af49f532` 2026-08-06T01:40, six days
and two hours — the class recurred on the production-staleness alarm.

Four learnings and two hand sweeps is the rest of what had been tried. On the comment count the
honest answer is that it depends entirely on the pattern, so the number is published with the
command rather than asserted: at this branch's base commit,

```bash
git grep -h -iE '#.*(inherited|invocation).*(-e|errexit)|#.*set \+e so' \
  546294c1f -- '.github/workflows/*.yml' | wc -l   # -> 17
```

The 2026-07-30 plan's "five" and an earlier revision of this ADR's "six" are both counts of
something narrower that neither stated. The argument does not rest on the figure — whatever the
exact number of comments, prose was the whole intervention and the class recurred anyway.

## Decision

**Any workflow `run:` step that treats a command's exit code as *data* MUST clear errexit
explicitly** — `set +e` (bracketed with a `set -e` re-arm) or `|| rc=$?` on the capture.
`set -uo pipefail` is not a substitute and never has been.

This is enforced mechanically. `scripts/lint-workflow-errexit-capture.py` scans every `run:` body
in `.github/workflows/*.yml` and `.github/actions/*/action.yml`.

**The rule anchors on the `$?` / `${PIPESTATUS[n]}` READ, not on the assignment shape.** This
wording is load-bearing and was arrived at by measurement, not by taste. The obvious rule — "a
command-substitution assignment is a finding" — reaches only **8 of the 17 sites**, because the
other **9 are bare commands** followed by `rc=$?`. Shipping it would have covered less than half
its class while reading as full coverage.

*(An earlier revision of this ADR said "2 of the 17", inherited from the plan and never
re-derived. It is wrong, and its own explanatory clause did not close — 2 + 9 = 11, not 17. The
split is 8 assignments / 9 bare, obtained by classifying the gate's own output on `origin/main`;
the conclusion is unchanged, since 8/17 is still a minority and the read anchor is still what
covers all seventeen. Recording the correction rather than quietly fixing the number, because
this is the paragraph asking the reader to trust a measurement over their intuition.)*
`${PIPESTATUS[n]}` is included for the same reason: two real sites, including one of the six
occurrences justifying this gate, never touch `$?`.

Anchoring on the read is also what keeps the gate quiet: it fires only where the code itself
proves the author expected to handle a failure.

**Direction of error: prefer false negatives.** A missed finding leaves today's (zero) coverage
unchanged; a false positive blocks an unrelated PR and gets the gate disabled, at which point it
protects nothing.

### Relation to AP-021

This is a substantive extension of ADR-166, not just a citation of its shape. The errexit bug was
producing two AP-021 violations in the workflow it broke:

1. With `steps.check` aborting, the Sentry heartbeat's first conjunct
   (`steps.check.outcome == 'success'`) was false, so the monitor checked in `status=error` on all
   8 runs. The operator did receive a signal — a low-fidelity, **mis-attributed** one saying "the
   monitor is broken" when what had been measured was drift.
2. Its sibling defect (below) had the workflow posting *"the checker is evaluating again"* on
   dead ticks — a recovery the job never measured.

The step's own comment asserting that `outcome` reads `failure` "only on a runner-level death"
was falsified by the bug, and that comment was the stated justification for the heartbeat
expression. Restoring errexit correctness restores AP-021 compliance here.

### A distinct, adjacent defect this decision does NOT cover

Clearing errexit does **not** fix the empty-string coercion fail-open, and the two are worth
keeping separate. Actions `==` is loose: operands of differing types are cast to Number, an unset
step output is `''`, and `''` casts to 0 — so `'' == '0'` is **true**. A step that dies before
writing `$GITHUB_OUTPUT` therefore satisfies every `== '0'` gate downstream.

Measured on run `31054501973`: the step gated `exit_code != '0' && != '1'` was **skipped** while
its exact logical complement, gated `== '0' || == '1'`, **ran**. The workflow was one open issue
away from auto-closing the issue reporting its own breakage, with an empty verdict.

The remedy is a `steps.<id>.outcome == 'success'` conjunct on every consumer of a step's outputs,
which is what discriminates "the step ran and measured 0" from "the step never ran". Applied here
to all six consumers; not generalised into a repo-wide gate by this ADR, because the population
has not been surveyed.

## Consequences

- 17 sites across 7 files were corrected. An **eighth** workflow file,
  `cla-evidence-timestamp.yml`, is also edited: it is outside AP-022's anchoring rule (no `$?`
  read, and its body sets `-euo pipefail` itself), and is corrected here because review showed
  the deferral's fail-loud premise is false there. Nine are `terraform plan` handlers that already ended
  `exit $rc`, so the change cannot turn a failed production plan green — it restores the
  `::error::` that names why it failed.
- One correction is a genuine fail-open fix rather than a cosmetic one:
  `infra-validation.yml`'s plan step carries `continue-on-error: true`, and its job-failing guard
  is `if: steps.plan.outputs.exit_code != '0'`. Under the coercion above that guard is **skipped**
  on the abort path, so a failing production `terraform plan` could report green.
- Three comments asserting "`-e` is intentionally omitted so we can capture terraform plan's exit
  code" were false and are corrected (two rewritten here; the third was already corrected and
  quotes the old claim in order to refute it). These comments are the propagation vector — they
  are what the next author copies.
- The gate ships fail-closed at 0 with no `.highwater`. That is a deliberate trade: it is what
  forced six edits to the auto-applied prod-infra root, which would otherwise have been
  unnecessary on their own merits. The alternative was a `.highwater` of 9. A gate that ships at
  0 with no baseline is strictly stronger, and the blast radius is bounded by the shape of the
  edits themselves — each is a single `set +e` inside a handler that already ends `exit $rc`,
  so a failing plan still exits non-zero and only gains the `::error::` naming why. (The gate
  itself has no diff mode: it scans `--root` whole. Do not read this as a `--changed` flag.)
- New workflow authors writing a capture will now get a CI failure on the PR that introduces it,
  rather than a silent dark alarm discovered by an unrelated post-merge check months later.

## Alternatives Considered

**`defaults: run: shell: bash -uo pipefail {0}` at workflow level.** One line, fixes every step
including future ones. **Rejected: it cannot express per-step intent.** The overwhelming majority
of steps *should* keep errexit; clearing it workflow-wide silently removes fail-fast from every
step that legitimately relies on it, converting one dark alarm into a workflow-wide hazard. Only
the handful of steps that treat an exit code as data want it off. Secondary reasons: locality,
greppability, and per-step lintability — and the repo has already voted for the bracket form
(14 bracketed `set +e` statements in `apply-web-platform-infra.yml`, each with its own rationale).

**`|| rc=$?` on the capture only.** Retained as an acceptable idiom for a body with a single
capture, and the linter exempts it. Insufficient as the fix for the drift workflow specifically:
it repairs the headline capture and leaves four documented `list_rc` safety branches dead.

**Documentation-only (the status quo).** Rejected on measured recurrence: four learnings, six
in-workflow comments and two hand sweeps produced a sixth occurrence.

**`shellcheck` / `actionlint`.** Rejected, measured: neither models the runner-injected `-e` —
both see a standalone snippet with no knowledge of how Actions invokes it. `actionlint` already
runs in this repo's CI and caught none of the six.

## What this does NOT claim

- It does not claim that every unprotected command is a finding. The `$?` read is required; a
  body that never reads an exit status is not making this mistake.
- It does not claim the **13 latent sites** are safe in general (counted as SITES, not as
  file-line ranges; `pr-auto-close-scanner.yml:84,85,86` is three). They are assignments from a
  fallible command guarded only by an emptiness check, with no `$?` read.
  **Only 5 of the 13 are inherited-errexit sites at all** — the other 8 open with an explicit
  `set -euo pipefail`, so errexit there is deliberate authorship and a gate anchored on
  inheritance would never match them; covering those needs a second, separately justified rule.
  The "an abort here is fail-loud, so deferral leaves no user-visible hole" argument holds for
  the deferred set but is **not** universal: review found one site
  (`cla-evidence-timestamp.yml`) where it is false — the step is gated `if: failure()`, so the
  job is already red and an abort adds no signal while destroying the only durable one. That
  site was fixed in this PR rather than deferred. Tracked: **#7311**.
- It does not claim `shell: bash` is wrong to write — only that it does not clear `-e`, and the
  gate fires through it.
- It does not survey the empty-string coercion class repo-wide. That is a separate decision.
