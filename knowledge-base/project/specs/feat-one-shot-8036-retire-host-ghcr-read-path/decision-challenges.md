# Decision Challenges — feat-one-shot-8036-retire-host-ghcr-read-path

Persisted by `plan-review` running headless (pipeline mode, no TTY). `ship` Phase 6 renders these
into the PR body and files an `action-required` issue. Each entry is surfaced, never auto-applied.

Plan: `knowledge-base/project/plans/2026-09-23-fix-retire-host-ghcr-read-path-plan.md`
Operator ruling being challenged: the 1c ruling on #8036, 2026-09-22.

---

## DC-1 — Ship as TWO PRs instead of one

**Class:** user-challenge
**Raised by:** `soleur:engineering:cto` (named-panel devex seat)

**The operator's stated direction is the default.** The 2026-09-22 ruling says *"The follow-up PR
removes the prelude `docker login ghcr.io`, `refetch_ghcr_and_relogin` and the GHCR leg of
`_ghcr_pull_or_recover`, and deletes the stale `ghcr.io` entry from the home docker config"* —
singular, one PR.

**What the reviewer proposes instead.** Split:

- **PR-A — signal-parity reconciliation.** `issue-alerts.tf` (drop the one `ghcr-fallback`
  condition), `alert-reference.json`, `zot-soak-6122.sh` + `.test.sh` (floor `5`→`4`),
  `sentry-zot-mirror-fallback-alert-op-contract.test.ts`, `tests/scripts/test-sentry-alert-live-fidelity.sh`,
  `scheduled-zot-restart-loop.yml`, `variables.tf`, `zot-registry-revert.md`. No host behavior change.
- **PR-B — the script surgery.** `ci-deploy.sh`, `ci-deploy.test.sh`, the new probe, the ADR
  amendments + `model.c4`, the probe one-leggings, the alert-capture re-pin.

**Why it is not merely taste.** The plan's own AC-Q4 already states the constraint as a *commit*
ordering rule ("the soak floor move … land in a commit before the emitter is deleted"), which is a PR
boundary described in a weaker form. And the split resolves a genuine chicken-and-egg the single-PR
shape cannot: `## Files to Edit` prescribes re-pinning `scripts/sentry-alert-live-fidelity.sh`'s
committed capture **after the apply**, but the apply is fired *by merging that same PR*. Split, the
re-pin lands at the head of PR-B.

**Cost of not splitting.** The reviewer's judgement: PR-B's `ci-deploy.sh` diff is the only part where
a mistake costs a release, and in a single PR it arrives diluted by ~15 prose edits across 8 files.
The merge click would also authorize a script push **and** a Sentry apply together rather than one.

**Trade-off in the other direction.** Two PRs is two review cycles, two merges and two applies for a
change the operator scoped as one follow-up; the parity half is operationally inert (ADR-096's
2026-09-22 amendment records the soak is *not enrolled* in the sweeper), so the split buys
reviewability rather than safety.

**Default if unanswered:** ship as ONE PR per the ruling, and resolve the re-pin chicken-and-egg
in-scope by moving the capture re-pin to a post-merge step of the same PR's follow-through.

---

## DC-2 — Absorb `cosign-verify-live-8037.sh` and execute its overdue retirement clause

**Class:** user-challenge (scope addition beyond the 1c ruling)
**Raised by:** `soleur:engineering:cto` (named-panel devex seat)

**Measured facts, not opinion:**

- #8037 is CLOSED/COMPLETED (closed 2026-09-22), yet `scripts/followthroughs/cosign-verify-live-8037.sh`
  carries `# RETIREMENT: when #8037 closes, delete this file and its .test.sh, drop its run_suite line
  in scripts/test-all.sh, and remove the directive from the issue body.` **That clause has fired and
  has not been executed** — the file, its `.test.sh`, its `run_suite` line and the issue-body directive
  are all still live.
- The plan routes its worst failure mode (the sweep clipping the zot auths entry → silent
  `IMAGE_VERIFY_FAIL: result=verify_failed` under `IMAGE_VERIFY_MODE=warn`) to that probe — i.e. to a
  probe on a closed tracker, which the sweeper evaluates only inside its closed-set lookback.

**What the reviewer proposes.** Have `ghcr-read-retired-8036.sh` absorb the cosign-verdict leg AND
delete `cosign-verify-live-8037.sh` + `.test.sh` + the `scripts/test-all.sh` `run_suite` line + the
#8037 directive and label. Net file count goes `-1` instead of `+1`, and the stale retirement clause is
discharged by the PR best positioned to do it.

**Why this is surfaced rather than applied.** Deleting another issue's probe and editing a closed
issue's body is scope the 1c ruling does not cover, and it makes this PR the owner of #8037's cleanup.

**What IS being applied in-scope regardless** (classified Mechanical — the gap is real and the plan
names it as its own worst arm): the new probe will grade the cosign-verdict leg alongside the
conjunction, so detection does not depend on a closed tracker's probe. The deletions stay out of scope
pending this answer.

**Default if unanswered:** keep `cosign-verify-live-8037.sh` in place; the new probe carries the
cosign leg; file the overdue retirement as its own issue rather than folding it in here.
