---
title: "fix(ci): gate web-platform-release's event-SHA checkouts on the upstream event's trust shape (CodeQL alert #216)"
type: fix
date: 2026-11-03
slug: fix-codeql-216-untrusted-checkout
branch: feat-one-shot-codeql-216-untrusted-checkout
issue: none
closes: none
priority: P2
domain: engineering
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(ci): gate web-platform-release's event-SHA checkouts on the upstream event's trust shape (CodeQL alert #216)

CodeQL alert **#216** (`actions/untrusted-checkout/medium`, open, `refs/heads/main`)
flags `.github/workflows/web-platform-release.yml:283` — the `resolve-target` job's
`actions/checkout` with `ref: ${{ github.event.workflow_run.head_sha || github.sha }}`.
The medium query reports: *"Potential unsafe checkout of untrusted pull request on
non-privileged workflow."*

## User-Brand Impact

- **If this lands broken, the user experiences:** a release/deploy pipeline that
  clean-skips or fail-closes wrongly — deploys silently not happening, or false
  `release_run_missing`/`bad_sha` pages. The blast radius of a mistake here is the
  deploy chain itself, which is why every existing guard row must stay green.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the defect
  being fixed, not by this diff — on `main` today a fork PR whose head branch is
  literally `main` satisfies `branches: [main]` on the `workflow_run` trigger, and
  `verify-doppler-secrets` then executes `apps/web-platform/scripts/verify-required-secrets.sh`
  from that attacker-controlled tree under `doppler run -c prd` (all prd secrets in
  env). That exposure is what this fix removes.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** a leaked prd secret bundle is a severe but
  bounded infrastructure incident (rotate Doppler + downstream), not an
  aggregate-pattern user-data breach; the fix is defensive hardening on a rare edge.

## Premise Validation

- `gh api /repos/jikig-ai/soleur/code-scanning/alerts/216` — verified: open,
  `actions/untrusted-checkout/medium`, path `.github/workflows/web-platform-release.yml`,
  line 283, message "Potential unsafe checkout of untrusted pull request on
  non-privileged workflow." The only open `actions/*` alert in the repo.
- Issue `#216` in this repo is an unrelated CLOSED issue ("Self-iterating
  implementation loop against test suites") — the `#216` in scope is the CodeQL
  alert id, a contextual citation, not a work-target issue.
- No open issue tracks this alert (medium severity alerts get no tracker per scope).
- No open or merged PR names `web-platform-release.yml` + `untrusted-checkout`;
  sibling worktree `feat-one-shot-codeql-dedupe-fix` (PR #12000) touches
  `codeql-to-issues.yml`, a different file — no overlap.
- ci.yml runs on `pull_request`, so `workflow_run.head_sha` *can* genuinely be an
  untrusted PR head SHA (fork PR from a branch named `main` passes `branches:
  [main]`; the repo's own comment at line 68–70 acknowledges this).

## Research Insights

- **The query semantics were read from source** (`github/codeql`
  `actions/ql/lib/codeql/actions/security/UntrustedCheckoutQuery.qll` +
  `UntrustedCheckoutMedium.ql` + `Helper.qll` `inNonPrivilegedContext` +
  `ast/internal/Ast.qll` `isPrivilegedExternallyTriggerable`):
  - `PRHeadCheckoutStep` matches a checkout whose `ref:`/`repository:` argument
    *expression text* contains a head-SHA pattern (`containsHeadSHA` regexes include
    `github.event.workflow_run.head_sha`, `\bhead_sha\b`, `merge_sha`, `head.sha`),
    or whose `ref:` is a `steps.<id>`/`needs.<job>` expression where the id/job
    matches `.*(head|sha|commit).*`.
  - The medium variant fires only in a **non-privileged** job
    (`inNonPrivilegedContext`). `resolve-target` declares `permissions:
    {contents: read, actions: read}` → non-privileged → flagged.
    `verify-doppler-secrets` (line 1186) has **no** job-level permissions →
    inherits the workflow's `contents: write` → privileged → outside the medium
    query's scope (and the critical/high path-queries did not match it).
  - **The query has NO `if:` sanitizer and NO `persist-credentials` sanitizer.**
    `persist-credentials: false` alone cannot clear this alert class, and neither
    can an `if:` gate on the same `ref:` expression. The only ways the sink goes
    away: the `ref:`/`repository:` expression stops naming a head-SHA source, or
    the checkout is removed entirely.
- **Established repo precedent (ADR-074, fix-constraints two-stage split):** the
  documented remedy for `untrusted-checkout*` alerts is to make the sink
  *structurally absent* — never check out the untrusted ref in the privileged
  context — not to bolt credentials hygiene onto it.
- **Runtime reality in this file:** `resolve-target`'s `resolve` step re-checks
  `WR_HEAD_BRANCH == 'main'` and `WR_EVENT == 'push'` **after** the checkout, so
  the untrusted tree already lands on the runner before the clean-skip. The fix
  must hoist that same event-shape check *above* the checkout.
- **Coupled surfaces that must stay green:**
  - `workflow-run-deploy-invariants.test.sh` — G3 (bare-`github.sha` sites on the
    workflow_run arm; the `github.event.workflow_run.head_sha || github.sha`
    expression is the ONE permit, and `DISPATCH_SHA` read-scope), G7 six-state
    taxonomy, W3 (`resolve` step may not carry `if:`/`continue-on-error`), P1–P3
    (RELEASE_PATH_FILTER pathspec coupling; **exactly one** `actions/checkout` in
    `resolve-target` with `fetch-depth` unset/1 — `deploy-arm.sh` keys the deploy
    arm on its `--depth=1 origin <sha>` log line).
  - `resolve-target-decision.test.sh` — executes the `resolve` step body against
    fixtures; unaffected by the checkout change.
  - Downstream checkouts at lines 1010, 1048, 2102 use
    `ref: ${{ needs.resolve-target.outputs.head_sha }}` — job-id `resolve-target`
    does not match the `.*(head|sha|commit).*` heuristic → unflagged, trusted by
    construction through the 40-hex-validated output. Unchanged.
- **Mechanism minimality (0.6b):** the ask's mechanisms are checkout-ref
  constraint / `persist-credentials: false` / gating. Query source eliminates
  `persist-credentials` as a *clearing* mechanism (kept only as convention
  hygiene on the sibling checkout). The minimal mechanism that both clears the
  alert and genuinely restricts trust is a gate step feeding a validated
  `deploy_sha` into `ref:` — the "gate the privileged step" option from the
  scope, realized so the gate is real at runtime AND the pattern is gone
  statically. Alternatives considered and cut: (a) remove the checkout and read
  the three tree files via the contents/compare API — the ADR-074 "sink
  structurally absent" ideal, but it rewrites the lazy `git fetch --depth=2`
  deepen + diff and the `deploy-arm.sh` `--depth=1 origin <sha>` log contract —
  rejected as more blast radius than the property buys; (b) dismiss the alert —
  leaves the real fork-PR edge unguarded; (c) checkout `github.sha` — flagged by
  G3 (bare `github.sha` on the arm) and breaks the SHA-pin invariant the budget
  step exists for; (d) `workflow_run.event`/`head_branch` `if:` on the step alone
  — invisible to the query (no sanitizer), alert stays.
- **Sibling sink hardened in the same diff:** `verify-doppler-secrets` (line
  1181) checks out the identical untrusted expression and then *executes* a
  script from that tree under `doppler run -c prd` — strictly worse than the
  flagged site. Its job `if:` gains the identical trusted-shape conjunct and its
  checkout gains `persist-credentials: false` (convention; the job performs no
  git writes). Job permissions stay inherited — downscoping them would move it
  into the medium query's `inNonPrivilegedContext` and *create* a new alert on
  the same `ref:` expression; the `if:` gate is the runtime fix.
- **Premise re-check on the "trusted" definition:** a `push` event to branch
  `main` can only be produced by a collaborator or the merge queue — forks push
  to their own repositories. `workflow_run.event == 'push' && head_branch ==
  'main'` is therefore the exact trust boundary `resolve` already encodes; the
  gate mirrors it and the two are commented as coupled.

## Domain Review

### Engineering

The fix adds a `gate` step ahead of `resolve-target`'s checkout that emits
`trusted`/`deploy_sha` only for proven-trusted event shapes, conditions the
checkout and the tree-parsing `budget` step on it, and applies the same
event-shape gate at job level to `verify-doppler-secrets`. No new jobs, no new
triggers, no new autonomous surface; `resolve-target`'s step count grows by one
`run:` step so the P2 exactly-one-checkout invariant is untouched. Two new
invariant rows (P4, P5) pin the gate shape in the existing suite.

### Security

The flagged checkout is constrained so an attacker-controlled tree can never
materialize on the runner; the strictly-worse sibling (tree-script execution
under `doppler run -c prd`) is gated identically. The scanner-visible pattern
is removed by making `ref:` consume a *validated* output rather than the raw
event field — semantic indirection, not cosmetic renaming.

## Observability

(The surface changed is the release pipeline's own gating; its observability is
the existing `::error::`/`::notice::` annotations, `skip_reason` outputs,
`notify-gated` Slack page, and `release-outcome` classification — all preserved.)

```yaml
liveness_signal:
  what: "release-outcome job classifies every non-push-arm run (delivered / clean-skip / non-delivery) and notify-gated pages on non-delivery"
  cadence: "per workflow_run completion"
  alert_target: "operator Slack page via notify-gated; email via release-outcome"
  configured_in: ".github/workflows/web-platform-release.yml (release-outcome, notify-gated)"

error_reporting:
  destination: "GitHub Actions check-run annotations (a release-pipeline failure, not app runtime)"
  fail_loud: "::error::deploy blocked [skip_reason=<reason>] annotation on resolve-target; job exits non-zero"

failure_modes:
  - mode: "untrusted-shape upstream event (fork-PR CI on branch 'main')"
    detection: "resolve-target clean-skips with skip_reason=not_main|not_push; checkout+ budget skipped"
    alert_route: "none — green clean-skip by design (pre-existing state semantics)"
  - mode: "gate emits trusted=false on a genuinely deployable run (regression)"
    detection: "deploy never runs; release-outcome classifies non-delivery"
    alert_route: "operator Slack page via notify-gated / email via release-outcome"

logs:
  where: "GitHub Actions run logs (resolve-target, verify-doppler-secrets steps)"
  retention: "GitHub default retention"

discoverability_test:
  command: "bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh"
  expected_output: "workflow-run-deploy-invariants.test.sh"
```

## Encryption Posture

```yaml
posture: unchanged
rationale: >
  No new secret is minted, stored, or transmitted. The diff narrows WHERE an
  existing secret-bearing job (verify-doppler-secrets, DOPPLER_TOKEN_PRD) may
  run, and pins persist-credentials: false so the workflow's write-scoped
  GITHUB_TOKEN no longer persists into that job's checked-out tree.
```

## Files to Edit

- `.github/workflows/web-platform-release.yml` —
  (a) new `gate` step in `resolve-target` before the checkout (emits `trusted`,
  `deploy_sha`; trusted iff `workflow_run.event == 'push' && head_branch ==
  'main' && head_sha is 40-hex`, or the event is not `workflow_run` — the
  dispatch arm, where `deploy_sha = $GITHUB_SHA`);
  (b) the checkout gets `if: steps.gate.outputs.trusted == 'true'` and
  `ref: ${{ steps.gate.outputs.deploy_sha }}`;
  (c) the `budget` step gets the same `if:` (it parses tree files — absent when
  the gate declines);
  (d) `verify-doppler-secrets` job `if:` gains the identical trusted-shape
  conjunct and its checkout gains `persist-credentials: false`;
  (e) comments updated to name the coupling (gate vs. resolve's runtime
  re-check) and alert #216.
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` —
  new P4 row pinning the gate + `if:` + `ref:` shape on `resolve-target`'s
  checkout, and P5 row pinning `verify-doppler-secrets`'s trusted-shape job
  `if:`; MIN_ROWS floor raised accordingly (80 → 82).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-codeql-216-untrusted-checkout/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-codeql-216-untrusted-checkout/session-state.md`
- `knowledge-base/project/specs/feat-one-shot-codeql-216-untrusted-checkout/decision-challenges.md`

## Scope Check

### Ask Mapping

| Ask (from the operator scope) | Status | Plan item |
|---|---|---|
| "verify which checkout is flagged" | mapped | Premise Validation: `gh api .../alerts/216` → line 283 `resolve-target` checkout confirmed; sibling sites enumerated (1010/1048/1181/2102) |
| "constrain it (merge ref / base SHA, `persist-credentials: false`, or gate the privileged step)" | mapped | `gate` step + `if:`-conditioned checkout + gate-derived `ref:` in `resolve-target` (the "gate the privileged step" arm, realized so it also removes the static pattern — `persist-credentials` alone cannot clear this query, verified from source) |
| "follow the established pattern" | mapped | ADR-074 untrusted-checkout precedent (sink unreachable before trust is established); `persist-credentials: false` convention applied to the sibling checkout; comment style + invariant-test pinning conventions followed |
| "reference alert #216 in the PR body; no tracker issue" | mapped | PR body cites "CodeQL alert #216"; no `Closes #N` |

### Plan-Item Provenance

| Plan item not in the ask | Status | Justification |
|---|---|---|
| `verify-doppler-secrets` job `if:` gate + `persist-credentials: false` | justified — same defect class, strictly worse exposure | same untrusted `workflow_run.head_sha` checkout expression, but it *executes* `apps/web-platform/scripts/verify-required-secrets.sh` from the tree under `doppler run -c prd` (all prd secrets). "Read surrounding steps before deciding" explicitly authorizes this analysis; leaving it gated only by a post-checkout runtime check would re-ship the same class one job over. |
| `budget` step `if:` | justified — mechanical necessity | it parses files from the checked-out tree; when the gate declines there is no tree, and its missing-file path exits 1 — the `if:` preserves the GREEN clean-skip semantics of the untrusted path. |
| P4/P5 invariant rows in `workflow-run-deploy-invariants.test.sh` | justified — repo guard convention | every load-bearing invariant on this pipeline is pinned by a suite row (P1–P3, G3–G13, W1–W5); the new gate shape is exactly such an invariant. |

### Split Assessment

- Files to Edit: 2 (`web-platform-release.yml`, `workflow-run-deploy-invariants.test.sh`). Files to Create: 3 spec artifacts.
- Single coherent change: one trust-boundary fix + its pins. No split.
- Recommendation: proceed as one PR.

## Guard Contract

### Guard 1 — checkout trust gate on `resolve-target` (P4 row)

**Property.** On the `workflow_run`/`workflow_dispatch` arms of
`web-platform-release.yml`, no `actions/checkout` step in `resolve-target` may
materialize a tree whose ref derives from an unvalidated upstream event field:
the step must be conditioned on `steps.gate.outputs.trusted == 'true'` and its
`ref:` must read the gate-validated `deploy_sha` — never an expression matching
the `containsHeadSHA`/`PRHeadCheckoutStep` patterns (CodeQL
`actions/untrusted-checkout`).

**Assembly.** The chokepoint is the step sequence inside `jobs.resolve-target.steps`:
exactly one `actions/checkout@` uses-step (P2 already bounds the count), the
`gate` step must exist and emit both `trusted` and `deploy_sha`, and the
checkout's `if:`/`with.ref` are asserted by exact string equality — any ref
expression naming an event field again (in any spelling) fails the row. The
runtime contract the row certifies: `trusted` is emitted `true` only for
`push`-to-`main` upstream events (collaborator-only) or non-`workflow_run`
(dispatch → `github.sha`).

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert `ref:` to `github.event.workflow_run.head_sha \|\| github.sha` (guard's own dispatch — the head-SHA pattern returns) | P4 RED |
| 2 | Drop the checkout's `if:` (step runs unconditioned on any event shape) | P4 RED |
| 3 | Delete the `gate` step (no `trusted`/`deploy_sha` producer — second-member/absent-assembly row) | P4 RED |
| 4 | Rename the output so `ref:` reads `steps.gate.outputs.head_sha` (precondition satisfied, property fails — a head-patterned ref through the gate) | P4 RED |

### Guard 2 — `verify-doppler-secrets` trusted-shape job gate (P5 row)

**Property.** `verify-doppler-secrets` — which executes
`apps/web-platform/scripts/verify-required-secrets.sh` from its checked-out
tree under `doppler run -c prd` — must not run at all on a `workflow_run` event
whose upstream shape is not `push`-to-`main`; its checkout must not persist
credentials into that tree.

**Assembly.** The chokepoint is the job's own `if:` — the only expression
evaluated before any of its steps materialize the tree (step-level gates would
leave earlier steps unbounded, and the checkout is step 1). Asserted by the job
`if:` containing both `github.event.workflow_run.event == 'push'` and
`github.event.workflow_run.head_branch == 'main'` conjuncts, and the checkout's
`with.persist-credentials == false`.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert job `if:` to bare `github.event_name != 'push'` (guard's own dispatch — the untrusted shape reaches the secrets-bearing job again) | P5 RED |
| 2 | Drop the `head_branch == 'main'` conjunct (fork-PR `main`-squat shape readmitted — second-member row: the `event` check alone is insufficient) | P5 RED |
| 3 | Remove `persist-credentials: false` (write-scoped token persists into the tree again — precondition satisfied, property fails) | P5 RED |
| 4 | Move the gate from job `if:` to a step `if:` after the checkout (reorder row — the tree materializes before the gate evaluates) | P5 RED |

## Acceptance Criteria

- [ ] `gh api repos/jikig-ai/soleur/code-scanning/alerts/216` reports the alert
  `fixed`/`dismissed` on `refs/heads/main` after merge (CodeQL re-analysis on
  the PR ref is the pre-merge proxy: the line-283 instance must not be `open`
  on this branch).
- [ ] `resolve-target`'s `ref:` no longer contains `github.event.workflow_run.head_sha`
  (or any `containsHeadSHA`-matching token); the checkout and `budget` steps are
  conditioned on `steps.gate.outputs.trusted == 'true'`.
- [ ] `verify-doppler-secrets` skips entirely on untrusted-shape workflow_run
  events; its checkout sets `persist-credentials: false`.
- [ ] Untrusted-shape runs still end GREEN via resolve's existing
  `not_main`/`not_push` clean-skip (six-state taxonomy unchanged); `deploy`
  remains blocked by `should_deploy != 'true'` and the skipped
  `verify-doppler-secrets` need.
- [ ] `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh` passes
  locally, including the new P4/P5 rows; `bash
  plugins/soleur/test/resolve-target-decision.test.sh` passes (resolve step
  body unchanged).
- [ ] `deploy-arm.sh`'s `--depth=1 origin <sha>` arm-identification contract is
  preserved (the trusted-path checkout still emits it — verified by P2 staying
  `unset`/`1` and deploy-arm tests green).

## Test Scenarios

- Run `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` — all rows
  green incl. P4/P5 and the ≥5-mutant battery.
- Run `plugins/soleur/test/resolve-target-decision.test.sh` — fixture-driven
  execution of the unchanged `resolve` body stays green.
- YAML-parse the workflow (`python3 -c 'import yaml; yaml.safe_load(open(...))'`
  with the `on:`-key caveat) to confirm the `if:`/`ref:` structure.
- Post-merge: confirm alert #216 flips to fixed on `main` via `gh api`.

## Task Design

N/A — no new autonomous-task surface (no new workflow, cron, registered check,
or daemon); this edits steps inside an existing workflow and its existing test.

## Enhancement Summary

### Key Improvements (deepen-plan)

- Read the CodeQL query source rather than guessing at remediation: the medium
  variant's only sink is a `ref:`/`repository:` expression matching head-SHA
  patterns — `persist-credentials: false` and `if:` gates are NOT sanitizers.
  This eliminated the two cheapest candidate fixes and forced the structural
  one.
- Verified the negative claims inline (depth-1 sequential fallback, no spawned
  agents — `Reviewed-Coverage: sequential-fallback`): `resolve-target` job-id
  does not match the `.*(head|sha|commit).*` heuristic; `deploy_sha`/`steps.gate`
  match no `containsHeadSHA` regex; the existing `git -c ... fetch` deepen does
  not match `git\s+(fetch|pull)` and stays unflagged.
- Found the strictly-worse sibling sink (`verify-doppler-secrets` executes a
  tree script under `doppler run -c prd` with no event-shape gate at all) by
  enumerating every `actions/checkout` in the file instead of only the flagged
  one — scope-checked as a justified inclusion.
- Mapped the blast radius before designing: `workflow-run-deploy-invariants.test.sh`
  G3 permit semantics, P2 exactly-one-checkout + depth-1 deploy-arm contract,
  W3 no-`if:` on `resolve`, DISPATCH_SHA read-scope, six-state taxonomy, and
  `release-outcome`/`notify-gated` result classification — each constrains the
  fix's shape (no `github.sha` in the new `ref:`; gate must not shadow the
  `EVENT_NAME" = "workflow_dispatch"` span anchor; untrusted path must remain a
  GREEN clean-skip).

### New Considerations Discovered

- The gate must use `$GITHUB_EVENT_NAME`/`$GITHUB_SHA` (native runner env) for
  the dispatch arm — a `${{ github.sha }}` span on a non-`DISPATCH_SHA:` line in
  `resolve-target` reds G3, and a second `DISPATCH_SHA:` definition reds the
  count bound.
- `excludes_wr` in the analyser substring-matches `github.event_name !=
  'workflow_run'` — adding that conjunct to `verify-doppler-secrets`'s `if:`
  reclassifies it as wr-unreachable in the guard's model (conservative;
  harmless — its `github.sha` site is already permit-exempt).
- `release-outcome`/`notify-gated` already key on `always()` + result/skip_reason,
  so a `skipped` verify-doppler-secrets on the untrusted path classifies the
  same as today's green — no new notification semantics.
