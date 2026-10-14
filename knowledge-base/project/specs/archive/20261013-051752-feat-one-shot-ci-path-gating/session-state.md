# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-25-feat-ci-path-gating-plan.md
- Status: complete (planning subagent)
- Branch: feat-one-shot-ci-path-gating · PR: #8897 (draft)

### Errors
- None. One expected non-zero exit: `diff` between the live "CI Required"
  ruleset contexts and `scripts/required-checks.txt` — the difference is the
  file's own documented deltas (CodeQL omitted by design — GHAS
  integration_id 57789; cla-check/cla-evidence live in the separate
  13304872 ruleset). Verified, not a defect.

### Decisions
- Mechanism is uniformly **detect + `if:`** — no `on.pull_request.paths`
  anywhere. Reason: every gatable non-required job shares a file with
  required jobs (a trigger filter would suppress required contexts on the
  same trigger), and every standalone required-check file must keep
  always-run jobs. The prescribed "required check → detect job + job-level
  if:" pattern is satisfied because a job whose steps skip still reports
  success — the required context never goes missing.
- Real residual scope = **two files**: `dependency-review.yml` (in-job
  detect, ~15 s → ~7 s on ~100% of pushes) and `pr-quality-guards.yml`
  (new `detect` job gating five advisory file-scoped jobs, ~60–75 s → ~8 s
  per typical push). Everything else got a named "already done /
  ungateable / deliberately ungated" verdict in the plan table — an honest
  mostly-already-done outcome per the brief.
- `skill-security-scan-pr-trailer.yml` deliberately NOT touched: already
  in-job gated on `no_new_skills`; the residual tighten (~20 s) collides
  with open PR **#8878** in the same file and would duplicate the gate's
  fail-closed AMRT diff semantics through a second mechanism.
- `guard-script-fixture-tests` deliberately not gated despite ~40–77 s cost:
  required context whose fixture suites reference real files across
  `scripts/`, `apps/`, `plugins/` — the detect surface cannot be bounded
  honestly.
- `ci.yml` not gated: `test` is a required `if: always()` aggregator over
  the whole suite; a green `test` must mean the suite ran. Existing in-job
  gating (detect-changes → critical-css; e2e step-level) stands.
- Fail-open-to-run on every detect error path — for content gates, "skip on
  uncertainty" is the only unsound direction; `sweep` additionally treats a
  registry-fetch failure as run.
- Ledger: `pr-quality-guards.yml` row goes 10 → 11 jobs (detect);
  `dependency-review.yml` row keeps `paths: no` (trigger-invisible gating —
  ci.yml-row convention) with a consequence clause.

### Collision record
- Open PRs touching `.github/workflows/`: #8878
  (`skill-security-scan-pr-trailer.yml` — deferred anyway), #6778 + #8873
  (`infra-validation.yml`), #8886 (`cutover-inngest.yml`), #7390/#8831
  (`apply-web-platform-infra.yml`, `reusable-release.yml`), #7999
  (`git-data-rung2-rehearsal.yml`). None touch the three files this plan
  edits.

### Measurements recorded (baselines for Phase 5)
- `dependency-review.yml`: job-time 13–18 s over 5 sampled runs
  (33308683651, 33178051096, 33084122211, 32418589463, 32415810920);
  run-level avg 470 s is runner-queue wait, not billed minutes. Would-run
  rate on a manifest regex: 0/25 recent merged PRs.
- `pr-quality-guards.yml` per-job (runs 36158193413 / 36155885239 /
  36152743033): settings-json-integrity 19–21 s, stray-worktree 4–5 s,
  userid-bypass 14–17 s, client-pii 11–14 s, sweep-completeness 11–19 s;
  would-run rates 0% / 0% / 40% / 12% / 0%.
- `skill-security-scan-pr-trailer.yml`: 23–29 s recent runs (unchanged).
- `enforcement-contracts.json` currently registers 1 sibling set /
  1 trigger — `sweep` output will skip ~always today; it stays for the
  registry-growth case, not the current rate.

### Components Invoked
- soleur:plan (via planning subagent — planning-only mandate, no
  implementation)

## Work Phase (next agent — resume prompt)

Implement `tasks.md` Phase 1→4. Phase 0 re-verifications are mandatory and
cheap (live ruleset diff + open-PR collision re-check + ledger-test baseline
+ rebase check). Two files change plus `scripts/pr-fanout-ledger.txt` and a
new `plugins/soleur/test/ci-path-gating.test.sh`. This PR's own checks are a
live exercise: `pr-quality-guards.yml`'s self-trigger runs all five gated
jobs here, and `dependency-review`'s self-trigger runs the scan once.
