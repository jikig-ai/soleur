---
title: "Tasks — fix the prod version-drift alerter's inherited-errexit outage (#7304)"
date: 2026-08-06
issue: 7304
branch: feat-one-shot-7304-drift-alerter-errexit
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-06-fix-prod-version-drift-alerter-inherited-errexit-plan.md
---

# Tasks — #7304

Derived from the deepened plan. **Read the plan first** — several tasks below carry corrections
that were only established at deepen time and whose naive forms are wrong.

## Phase 0 — Preconditions (no edits)

- [x] 0.1 Confirm `git branch --show-current` == `feat-one-shot-7304-drift-alerter-errexit`.
- [x] 0.2 Capture the pre-fix control reading:
      `gh run list --workflow=scheduled-prod-version-drift.yml --limit 8 --json conclusion`
      → expect 8/8 `failure`. Record in `acceptance-evidence.md`.
- [x] 0.3 Create the calibration worktree for Phase 4:
      `git worktree add /tmp/errexit-calib origin/main`. Do **not** delete until AC13 passes.

## Phase 1 — Fix the outage (the 7 step bodies)

- [x] 1.1 Add `set +e` immediately after `set -uo pipefail` in **all 7** `run:` bodies of
      `.github/workflows/scheduled-prod-version-drift.yml`. Full rationale comment on the `check`
      step; one-line back-reference on the other six.
- [x] 1.2 Correct the false-premise comment at **L248** (*"this step runs `set -uo pipefail` with
      no -e"*) — keep the guard's real rationale, fix the premise.
- [x] 1.3 Correct the false-premise comment at **L560** (*"with `exit 0` … and no `-e`"*) — this is
      the stated rationale for the Sentry heartbeat expression and was factually wrong.

## Phase 1b — Disarm the empty-string coercion fail-open (SECOND defect)

- [x] 1b.1 Add a `steps.check.outcome == 'success' &&` conjunct to every `if:` referencing
      `steps.check.outputs.exit_code` — **L182, L271, L325, L402, L460, L497**. The heartbeat at
      L565 is the in-file precedent.
- [x] 1b.2 Verify no B3/B4/B6 substring assertion breaks (a *leading* conjunct preserves them all).

## Phase 2 — Pin it, in BOTH directions

- [x] 2.1 **B14** — extract the `check` body via the existing `$DRIFT_STEP_BODY_OUT` hook; stub the
      checker to exit `{0,1,2}`; run under **`bash -e`**. Assert per the plan's table.
      - [x] 2.1a FRESH `$GITHUB_OUTPUT` tmpfile per arm; assert exactly 8 lines (the body appends).
      - [x] 2.1b Generate the stub's `DRIFT_*` keys from `$X_EXTRACTED_KEYS` / `$SUT` — never hand-copy.
      - [x] 2.1c `drift| == 7` (not `≥`), with a comment that its only power is 0-vs-7.
      - [x] 2.1d Self-check probe: `bash -e -c 'set -uo pipefail; x="$(exit 1)"; echo REACHED'` must
            NOT print `REACHED`; share one invocation variable with the body run.
      - [x] 2.1e Stub marker `DRIFT_REASON=STUB_MARKER_7304` must reach `$GITHUB_OUTPUT`.
- [x] 2.2 **B14b** — `PYEXTRACT` emits count of steps declaring `shell:` (+ `defaults.run.shell`);
      assert `0`. This is what makes B14's `bash -e` simulation self-invalidating.
- [x] 2.3 **B15** — count of bodies lacking an errexit clear, over `code()`; assert count `== 0`
      (the **numerator**, never the ratio). Add the comment explaining why the Phase 4 linter does
      NOT subsume it (`notify`/`notify_error` have no `$?` read).
- [x] 2.4 **B16** — execute the `issue` body with `gh` stubbed to fail; assert the
      `A FAILED LOOKUP IS NOT "NOTHING FOUND"` branch is reached (implements T5).
- [x] 2.5 **B17** — count of `exit_code` gates lacking an `outcome == 'success'` conjunct; assert `0`.
- [x] 2.6 **Part C axis11** — delete `set +e` from the `check` body; require RED labelled `B14`.
      **CODE-ONLY, line-based mutator** (skip lines whose first non-space char is `#`) — the Phase 1
      comment contains the literal `set +e`, so a naive replace mutates prose and the axis reports
      SURVIVED. Follow the axis3/axis9 shape.
- [x] 2.7 **Part C axis12** — strip one `outcome == 'success'` conjunct; require RED labelled `B17`.
- [x] 2.8 Raise `MIN_B`, `MIN_C` (11→12+), `MIN_ASSERTIONS` by exactly the added count; add the
      `MIN_ASSERTIONS == MIN_A + MIN_B + MIN_C` check; record the Part C wall-clock delta.

## Phase 3 — The other 12 confirmed sites (narrow brackets)

- [x] 3.1 `scheduled-cron-artifact-age.yml:80` — the **second dark alarm**.
- [x] 3.2 `scheduled-inngest-health.yml:220-229` — **narrow bracket only** (121-line body drives an
      automated prod restart). Capture spans a multi-line substitution.
- [x] 3.3 `infra-validation.yml:1280` — `set +e` before L1280, `set -e` after L1283.
      **Do NOT add `set -u`.** AC names `infra-validation.yml:1320-1322` as the verified consumer.
- [x] 3.4 `apply-github-infra.yml:245` + rewrite the false-premise comment at **L240**.
- [x] 3.5 `apply-sentry-infra.yml:282`, `:592` + rewrite the false-premise comment at **L579**.
      *(Only L579 carries it — L272-288 has no such comment.)*
- [x] 3.6 `apply-web-platform-infra.yml` ×6 — L1183, 1331, 1516, 1740, 2456, 3065.
      **Leave `L449` alone** — it is the already-corrected exemplar.
- [x] 3.7 File ONE tracking issue for the 13-site latent class (inventory in §Appendix below).

## Phase 4 — The mechanical gate

- [~] 4.1 **Deviated, deliberately.** The plan said fixtures first. I wrote the detector first
      and calibrated it against the PRESERVED pre-fix worktree (`origin/main`), then wrote the
      fixtures. The plan's reason for fixtures-first was that Phase 3 erases the evidence — that
      risk was addressed instead by keeping the pristine tree until AC13 was recorded, which is
      a stronger check than author-written fixtures (it found the 2-of-17 and the 13-false-
      positive problems, which fixtures alone would not have). Fixtures exist and pass (27/27).
- [x] 4.2 Write `scripts/lint-workflow-errexit-capture.py`. Anchor on the **`$?` /
      `${PIPESTATUS[n]}` read**, look backwards over `\` continuations. Match compound `set` forms
      (`set -euo pipefail` re-arms). Strip comments; skip quoted heredocs; scan composite actions.
- [x] 4.3 **Calibrate:** must report **17** against `/tmp/errexit-calib` (origin/main) and **0**
      against the fixed tree. The gate is not accepted otherwise.
- [x] 4.4 Write `scripts/lint-workflow-errexit-capture.test.sh`. Required must-FIRE fixtures:
      bare command + next-line `rc=$?`; same-line `; rc=$?`; `${PIPESTATUS[0]}`;
      **`shell: bash`**; `set +e` then `set -euo pipefail`; body with no `set` line; multi-line
      substitution. Must-NOT-FIRE fixtures each need a **positive control** (a known-firing shape in
      the same file, asserting the linter names that line and not the guarded one).
- [x] 4.5 Register both in `scripts/test-all.sh` beside the `lint-workflow-step-env-refs` pair
      (L350-351). Inherit its nothing-scanned-is-a-failure contract; assert a **per-kind** scanned
      count (workflows ≥ N *and* composite actions ≥ 7).

## Phase 5 — ADR + register + learning

- [x] 5.1 Re-derive the ADR ordinal from freshly-fetched `origin/main` (max 169; **167 is a gap,
      do not reuse**). Write `ADR-170`. `Enforced by:` must assert **blocking**, per ADR-166.
- [x] 5.2 Add the **AP-022** row to
      `knowledge-base/engineering/architecture/principles-register.md` (tier `hook`, source ADR-170).
- [x] 5.3 **Append** to
      `knowledge-base/project/learnings/best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md`.
      Do **not** create a new learning file.
- [x] 5.4 N/A — the ordinal did NOT move. Re-derived from freshly-fetched `origin/main` at
      ship time: max is ADR-169, 167 is a gap and was not reused, so ADR-170 stands.

## Phase 6 — Verify

- [x] 6.1 `bash scripts/prod-version-drift-check.test.sh` → 0, Parts A/B/C all run, `C0 … GREEN`.
- [ ] 6.2 `bash scripts/test-all.sh scripts` → green (the shard's OWN invocation, not a file list).
- [x] 6.3 `actionlint` on every edited **workflow** (not composite actions).
- [x] 6.4 Record all AC evidence in
      `knowledge-base/project/specs/feat-one-shot-7304-drift-alerter-errexit/acceptance-evidence.md`.

## Appendix — sweep inventory

### CONFIRMED (17) — all fixed by this PR

| File | Sites |
|---|---|
| `scheduled-prod-version-drift.yml` | L106, 212, 350, 476, 516 |
| `scheduled-cron-artifact-age.yml` | L80 |
| `scheduled-inngest-health.yml` | L220-229 |
| `infra-validation.yml` | L1280 |
| `apply-github-infra.yml` | L245 |
| `apply-sentry-infra.yml` | L282, L592 |
| `apply-web-platform-infra.yml` | L1183, 1331, 1516, 1740, 2456, 3065 |

### LATENT (13) — deferred to ONE tracking issue, deliberately outside the gate's rule

Assignments from a fallible command guarded only by an emptiness check, with **no `$?` read**. An
inherited-`-e` abort here is **fail-loud** (the job goes red and visible), the opposite direction
from the outage — which is why deferral leaves no user-visible hole.

`apply-github-infra.yml:339-344` · `pr-auto-close-scanner.yml:84,85,86` *(its L82 sibling IS
`|| true`-protected — an internal inconsistency, strongest candidate)* · `cla-evidence-timestamp.yml:325-332`
*(`head -1` under `pipefail` also admits a SIGPIPE-141 abort)* · `codeql-1537-revisit-watch.yml:76-77` ·
`scheduled-inngest-health.yml:550` · `web-platform-release.yml:401`, `:796` ·
`apply-web-platform-infra.yml:1009`, `:3893`, `:4328` ·
`.github/actions/cf-tunnel-ssh-bridge/action.yml:170`, `:228`

**Re-evaluation criterion:** widen the gate's rule once the confirmed class has held at 0 for one
release cycle.

### VERIFIED SAFE (not findings)

`scheduled-zot-restart-loop.yml` and `scheduled-terraform-drift.yml` use the `|| rc=$?` idiom and
are genuinely protected — checked explicitly, not assumed. `apply-web-platform-infra.yml` has ~8
further `terraform plan` capture sites already covered by existing `set +e` brackets.
