---
date: 2026-09-18
topic: parallel-test-all-green-baseline
issue: 8231
branch: feat-8231-parallel-test-all-next
lane: cross-domain
brand_survival_threshold: none
---

# #8231 next move — establish the local green baseline first

## What We're Building

Not the parallel scheduler yet. The existing deepened plan
(`knowledge-base/project/plans/2026-09-17-feat-parallel-local-test-all-suites-plan.md`) shipped
Phase 0 on 2026-09-17 and stopped on one precondition: Phase 1 (interference diagnosis of #7376,
by repetition) and Phase 4 (fault-injection correctness gate) both need a serial baseline where a
RED suite is a signal. The baseline had 20 red suites.

This branch makes the local serial battery green on a developer host, by closing the five open
issues that own every remaining red suite. Then the existing plan resumes at Phase 0.5 unchanged.

## The re-measurement that re-scoped this (2026-09-18)

The 20 reds were measured while `bun` was an unrunnable mise shim. Today `bun --version` → 1.3.14,
rc 0. Re-running the 21 baseline-red suites (20 + the one Phase 0 fixed) standalone, same host,
16 cores:

| Result | Count |
|---|---|
| Now green | 12 |
| Still red | 9 |

The 9 still-red suites map onto five open issues. None is a defect CI can see: `ci.yml` on `main`
(push, 2026-09-17T22:25Z) is green. They are host-vs-CI divergences.

| Suite(s) | Cause | Owning issue |
|---|---|---|
| `gitleaks-merge-commit`, `.claude/hooks/git-commit-secret-scan`, `code-to-prd` | unpinned mise `gitleaks` shim (resolves, cannot run); CI pins 8.24.2 | #8266 |
| `_base-notice-frontmatter`, `notice-frontmatter` (rc 127) | hard dependency on GNU `/usr/bin/time`, absent on this host | #8250 |
| `apps/web-platform [repo-wide+component]` | Node 26 admitted by `engines`, suite fails on it | #8261 |
| `.claude/hooks/guardrails` (1/123), `scripts/lib/scratch-root` | kb-index sentinel under-fire; scratch-root containment | #8263 |
| `scripts/lint-legal-scope-block-placement-unit` | arm (a) assertions report rc 0 where rc 1 is expected | #8238 |

## Why This Approach

Four options were weighed with the operator:

1. **Fix the local-vs-CI gaps first (chosen).** Restores the plan's assumption with no change to
   its method. Also makes the pre-commit hook (`lefthook.yml` → `test-all.sh`) usable on this
   host class, where it currently fails on red suites that have nothing to do with the commit.
2. Diagnose on a CI runner — main is green there and a 4-core GitHub runner is the #7376 hardware.
   Rejected for now: needs a new dispatch workflow and leaves the developer host red.
3. Differential against a frozen known-red set — rejected: changes the plan's method and
   takes 9 suites out of the correctness gate.
4. Pivot to #8045 (hook glob scoping, decision-challenge UC-1) — not taken. UC-1 remains open
   and on the record; the Phase 0.4a gate already passed at 6.22× (floor 2.0×).

## Key Decisions

| Decision | Detail |
|---|---|
| Next move | Close #8238, #8250, #8261, #8263, #8266 as the #8231 precondition |
| Delivery shape | One bundled PR on this branch — the acceptance criterion is a single green serial battery, which only a combined change can show |
| #8231 | Stays OPEN. This PR uses `Ref #8231`, never `Closes` |
| Existing plan | Not re-planned. Resumes at Phase 0.5 after the green baseline is measured |
| Toolchain pinning | Open — see below. The repo pins only `.bun-version`; there is no `mise.toml` / `.tool-versions` |
| Domain review | Carried forward from the existing plan (operator choice): internal verification machinery, threshold `none` |
| Premise correction | The blocker is not #8112. #8112 is the main-branch health monitor. The residual reds are host divergence, and CI is green |

## Open Questions

1. **gitleaks on developer hosts:** add a repo toolchain pin (`mise.toml`), or make each consumer
   distinguish "unrunnable" from "found" and skip/declare (the #8266 class fix)? #8266's fail-open
   in `git-commit-secret-scan.sh` has to be fixed whichever way this goes; the pin question only
   decides whether the host goes green or goes explicitly SKIPPED.
2. **Is SKIPPED green enough for Phase 1?** A suite that declares an unmet host dependency and
   skips is a stable signal for differential testing. A suite that is red is not. The plan should
   state that a declared skip satisfies the precondition.
3. **scratch-root:** #8263 says host-shape or HEAD-state dependent. The HOME-fallback arm returns
   the live `$HOME/.cache` while the test passes an overridden `HOME`, which points to an
   environment leak into `bash -c` rather than resolver logic. Verify before fixing.
4. **Node 26 (#8261):** narrow `engines`, or fix the suite. The first is a one-line change that
   leaves a developer on Node 26 with a refused install instead of a red battery.

## User-Brand Impact

- **Artifact:** the local `scripts/test-all.sh` battery and the pre-commit hook that runs it.
- **Vector:** a local gate that is red for host reasons trains developers to bypass it
  (`--no-verify`), so a real regression reaches a PR unseen. #8266's
  `git-commit-secret-scan.sh` row is fail-open: an unrunnable gitleaks allows a commit carrying
  a credential.
- **Threshold:** `none` (carried forward from the plan). Note that the #8266 fail-open is a
  secret-scanning bypass. The plan should weigh whether that one row alone warrants review at
  `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** Carried forward from the 2026-09-17 plan's Domain Review. The only delta is this
precondition drain, which touches test harnesses, one commit hook, and `engines`. No user-facing surface.
