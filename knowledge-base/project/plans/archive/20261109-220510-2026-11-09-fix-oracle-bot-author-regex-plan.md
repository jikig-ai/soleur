---
title: "ci: oracle-review-required fails closed reason=input on [bot]-authored PRs"
type: fix
date: 2026-11-09
slug: oracle-bot-author-regex
branch: feat-one-shot-12509-oracle-bot-author
issue: 12509
closes: 12509
---

# ci: oracle-review-required fails closed reason=input on [bot]-authored PRs

`scripts/ci-oracle-review.sh` (the required `oracle-review-required` check, added 2026-11-08 via
#12329) validates `PR_AUTHOR` with `^[A-Za-z0-9][A-Za-z0-9-]*$` (~line 133). GitHub App bot logins
end in the literal suffix `[bot]` (`soleur-infra[bot]`, `dependabot[bot]`, `github-actions[bot]`),
which the regex rejects → every bot-authored PR fails closed `verdict=fail reason=input` on a
REQUIRED context. Live victim: PR #12489 (authored pin bump), blocking epic #9927's a1 precondition.
Verified locally: the regex does not match `soleur-infra[bot]`.

Sibling sweep (run pre-edit): `git grep -n 'A-Za-z0-9-.*\*' origin/main -- scripts/ tests/` and
`git grep -n 'PR_AUTHOR\|author=.*=~' origin/main -- scripts/ .github/workflows/` — the merge_group
arm (`mg_arm`, :204-313) never validates a login (its marker author is the literal `-`), and the only
other hit is `watch-lint-ratchet-reeval-10515.sh:179` which already uses the widened
`^[A-Za-z0-9-]{1,39}(\[bot\])?$` shape. So the blind spot is exactly one site, plus two pins that
must move with it: the driver's emitted-grammar comment (:45) and the suite's marker-grammar pin
(`scripts/ci-oracle-review.test.sh` `want()` regex, which reads `author=[A-Za-z0-9-]+` — a `[bot]`
author would otherwise emit a marker the suite itself rejects).

## User-Brand Impact

- **If this lands broken, the user experiences:** automation PRs (pin bumps, authored maintenance)
  stay blocked on a required check, or — the worse arm — a `deruelle[bot]`-shaped spoof slips past
  the owner-author arm; the check's fail-closed design makes both immediately visible as a red
  required context, not a silent merge.
- **If this leaks, the user's [data / workflow / money] is exposed via:** n/a — no user data; the
  exposure is repo-automation throughput (epic #9927's precondition chain) and owner-arm integrity.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff is a regex + its two grammar pins in a CI gate
  script; worst outcome is a wrong verdict on a required check that fails loud, never a silent
  user-facing defect.

## Observability

```yaml
liveness_signal:
  what:            "oracle-review-required check-run conclusion on every PR/merge_group run"
  cadence:         per-run
  alert_target:    "required check goes red — visible on the PR itself"
  configured_in:   .github/workflows/ci.yml (oracle-review-required job)

error_reporting:
  destination:     "check annotation: '::error title=oracle-review-required::<text>' + reason=<token> on GITHUB_OUTPUT"
  fail_loud:       "SOLEUR_ORACLE_REVIEW ... verdict=fail reason=<token> marker line; ci.yml:644 extracts reason="

failure_modes:
  - mode:          "bot-authored PR still fails reason=input after the fix"
    detection:     "check-run annotation reason=input on a [bot] PR"
    alert_route:   "red required check on the PR"

logs:
  where:           "the oracle-review-required job's step output (the marker line)"
  retention:       "GitHub Actions run retention"

discoverability_test:
  command:         grep -n 'PR_AUTHOR.*=~' scripts/ci-oracle-review.sh
  expected_output: (\[bot\])?
```

## Task Design

Not required — no new autonomous-task surface (the ci.yml job already exists; this PR changes no
workflow file).

## Guard Contract

The deliverable edits an existing gate's input validation; one mutation row covers the regression.

### Guard 1 — [bot]-author admission without owner-arm widening

**Property.** A login ending in the literal suffix `[bot]` passes input validation and is judged by
the normal arms; a bot slug equal to the owner (`deruelle[bot]`) must NOT satisfy the author arm.

**Assembly.** `pr_arm()` input-validation block (scripts/ci-oracle-review.sh:129-134) → `$author`
flows to the owner comparison (:186) and the emitted marker; the suite's `want()` grammar pin and
the driver's grammar comment (:45) are the two other consumers of the same shape.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `(\[bot\])?` from the PR_AUTHOR regex (the pre-fix line) | RED — row_bot_author re-fails `reason=input` |
| 2 | Strip the `[bot]` literal to `(\[bo\])?` or `(\[.*\])?` in the emitted grammar pin | RED — marker off grammar / owner-spoof row changes verdict |
| 3 | Widen the owner compare to a prefix match (`= deruelle*`) so `deruelle[bot]` passes author arm | RED — row_bot_owner_spoof returns `author`, not `review-required` |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Widen the PR_AUTHOR regex to admit the `[bot]` suffix" | Phase 1 edit, scripts/ci-oracle-review.sh:133 | mapped |
| 2 | "SWEEP for siblings BEFORE editing … fix all instances of the same shape" | pre-edit sweep (done; one site found) + mg_arm verified login-free | mapped |
| 3 | "Add a regression test asserting a `[bot]` author does NOT fail reason=input" | Phase 2, three rows in ci-oracle-review.test.sh | mapped |
| 4 | "PR body: Closes #12509 … also Ref #12329 and Ref #9927" | ship phase PR body | mapped |
| 5 | "Carry the PR as far as possible … report the owner-review requirement" | ship halts before merge (oracle_diff=1 needs bound owner review) | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| regex widening | "e.g. `^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$`" | asked |
| marker grammar pin + comment update | implied by "fix all instances of the same shape" (a `[bot]` author emits a marker the suite pin rejects — same blind spot, same PR) | inferred — the pin would otherwise make every `[bot]` row a false marker-off-grammar failure |
| `deruelle[bot]` non-spoof row | "asserting a `[bot]` author does NOT fail reason=input" | inferred — pins the security boundary the widening must not cross |

### Split Assessment

- Subsystems touched: 1 — `scripts/` CI gate
- Planned files: 2 | Estimated changed lines: ~15
- Thresholds: >= 4 roots OR > 25 files OR > 800 lines → **single PR**

## Acceptance Criteria

- [ ] AC1: `[[ "soleur-infra[bot]" =~ <new-regex> ]]` matches; `deruelle[bot]` matches as login but `!= deruelle` at the owner compare.
- [ ] AC2: `bash scripts/ci-oracle-review.test.sh` is green, including a new row where `PR_AUTHOR=soleur-infra[bot]` on an oracle diff fails `review-required` (never `input`), a `dependabot[bot]` not-oracle row passes `not-oracle`, and a `deruelle[bot]` row fails `review-required` (no owner-arm spoof).
- [ ] AC3: the emitted marker grammar (driver comment :45 + suite `want()` pin) admits the `(\[bot\])?` suffix — no consumer of `author=` rejects the widened shape (ci.yml:644 reads only `reason=`; ci-oracle-lane.sh does not parse `author=`).
- [ ] AC4: PR body carries `Closes #12509`, `Ref #12329`, `Ref #9927`; PR carried to ready+green; merge left pending bound owner review (both files are RATCHET_ORACLE members → oracle_diff=1 → `review-required`/`approved` is the owner's act, not self-satisfiable).

## Test Scenarios

- Given `EVENT_NAME=pull_request`, an oracle-surface diff, `PR_AUTHOR=soleur-infra[bot]`, and no bound deruelle approval, when the driver runs, then it emits `verdict=fail reason=review-required` (unit — the stub-harness row; proves input passed and the reviews arm ran).
- Given `PR_AUTHOR=dependabot[bot]` and a docs-only diff, when the driver runs, then `verdict=pass reason=not-oracle` (unit).
- Given `PR_AUTHOR=deruelle[bot]` and an oracle diff with no reviews, when the driver runs, then `verdict=fail reason=review-required` (unit — spoof boundary).
- Given the pre-fix regex as a mutation, when row_bot_author runs, then it fails `reason=input` — i.e. the new row measures exactly this defect (mutation matrix row 1).

## Context

- The check was added 2026-11-08 via #12329 (ADR-276 PR3b); the regex predates the first bot-authored oracle-surface PR.
- Precedent for the exact widening shape already in repo: `scripts/watch-lint-ratchet-reeval-10515.sh:179` — `^[A-Za-z0-9-]{1,39}(\[bot\])?$`.
- Owner-arm safety: `[ "$author" = "$REQUIRED_REVIEWER" ]` is an exact-string compare; `deruelle[bot]` never equals `deruelle`, so no sanitization strip is needed or wanted (stripping would make `deruelle[bot]` collide with the owner — the rejected alternative).
- Live victim PR #12489 unblocks on merge (its next check run sees the fixed main-side required context; note the pull_request arm re-execs the BASE-side driver, so the victim may need a base refresh/re-run after merge — a merge_group/`main` advancement is what carries the fixed driver into its base).

## References

- Issue: #12509 (this fix), `Closes #12509`
- Ref: #12329 (introduced the gate), #9927 (blocked epic), #12489 (live victim PR)
- Precedent: scripts/watch-lint-ratchet-reeval-10515.sh:179
