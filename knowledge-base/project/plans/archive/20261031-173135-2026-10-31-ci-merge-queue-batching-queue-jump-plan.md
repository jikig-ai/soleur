---
title: "ci: group merge-queue entries for batchable traffic + a documented queue-jump path for urgent PRs"
date: 2026-10-31
slug: ci-merge-queue-batching-queue-jump
branch: feat-11678-merge-queue-batching
issue: 11678
lane: cross-domain
type: feat
brand_survival_threshold: single-user incident
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# Plan: Merge-queue grouping + documented queue-jump path

## Overview

Two merge-queue improvements for `main`, sequenced. First, a committed
queue-jump script + runbook that moves an urgent PR to the head of the queue
via GraphQL `enqueuePullRequest(jump: true)` — a gated middle tier between
waiting serially and `gh pr merge --admin` (which bypasses all required
checks). Second, `max_entries_to_merge` 1 → 3 under ADR-270's raise checklist:
CLA group enumeration (merge-blocking, fail-closed), the Guard-2 safety-pin
rewrite, three measured preconditions, and a first-grouped-merge canary. Per
GitHub docs the knob batches merge *landings*, not `merge_group` *builds* — A
amortizes post-merge work (push CI / deploy / alert-gate per group) rather than
shortening queue wait, which is build-slot-bound (`max_entries_to_build = 2`,
unchanged). Track: `apps/web-platform` — none; this is repo CI/ruleset
machinery.

## Scope Check

| Ask item | Source | Mapping |
|---|---|---|
| Documented queue-jump path | Issue Proposal B (operator-approved: script + runbook) | FR1, FR5 |
| Group batchable entries | Issue Proposal A (operator-approved scope B+A) | FR2–FR4 |
| `max_entries_to_merge` value = 3 | inferred — CTO-ruled (flake math 0.85^N: 3≈61% vs 5≈44%) | FR3 |
| CLA group enumeration | ADR-270 raise checklist + CLO MUST | FR2 |
| Guard-2 / T-mq-1.m9 rewrite | repo-research: parity + safety pin surfaces | FR3, FR7 |
| Measurement preconditions (headCommit, head_ref shape, ejection clock) | ADR-270 checklist + CTO assessment | FR4, TR1 |
| Urgency bar + attribution for jump | CLO requirement (attributed, deliberate, recorded) | FR1, FR5 |
| Split assessment | One PR is correct: B is small and same-subsystem; A's checklist work is gated by the same ruleset surface. Splitting would strand the ADR-270 addendum across two branches. | — |

No unmapped asks; `inferred` items are CTO/CLO-ruled and named above.

## Research Insights

- `enqueuePullRequest(input:{pullRequestId, expectedHeadOid, jump})` is the
  mutation; `gh pr merge` has no `--jump` (v2.103.3 verified). The web UI's
  "Jump the queue" is admin/write-gated — the script under the actor's own
  `gh` auth inherits that authority, zero new credential surface.
- Zero `enqueuePullRequest` call sites exist in-repo (repo-research sweep) —
  B is greenfield but thin. Re-enqueue precedent: `gh pr merge <N> --squash
  --auto` (auto-merge re-arm); for an already-queued PR the script offers
  `dequeuePullRequest` + re-enqueue(jump).
- The ==1 pin is in THREE parity sources (tf L349, DR skeleton L117, README
  L110) **and** a Guard-2 safety assertion
  (`tests/scripts/test-audit-ruleset-bypass.sh` `_mq_guard2` ~L885–895) plus
  mutation row `T-mq-1.m9` (~L1040) — a parity-preserving raise still goes RED
  until the pin is deliberately rewritten.
- `merge-queue-cla-verify.sh` L59–61 strictly validates
  `head_ref =~ ^refs/heads/gh-readonly-queue/main/pr-<N>-<40hex>$` — one PR.
  `merge-queue-cla-synthetics.yml` L54–55 anticipated this change: "If that is
  ever raised, this workflow must enumerate PRs."
- ~53 files reference `gh-readonly-queue`; operative `pr-<N>-` readers beyond
  the verify script: `sync-pr-behind.sh` L556, `monitor-pr-checks.sh` L451,
  `merge-queue-dequeue.md` L28, `drain-prs/SKILL.md` L88,
  `merge-queue-stall-check.yml` L221, `test-trio-baseline-census.sh` L95.
- Measured: `merge_group` flake ~15.4% (37/240); healthy entries merge 15–18
  min; #11646 dwelled 3h53m build-slot-bound; queue ≈22% of runner demand
  (max_entries_to_build is the contention knob, not merge).
- ADR-285: `github-actions[bot]`-armed queue entries got zero `merge_group`
  runs — enqueuer identity is load-bearing; a future jump workflow must mint
  the soleur-infra App token, never `GITHUB_TOKEN` (script path is unaffected:
  it uses the actor's own gh auth).

## Implementation Phases

### Phase 1 — Queue-jump script + runbook (ships independently)

- New `scripts/merge-queue-jump.sh` (CODEOWNERS explicit row per merge-queue
  machinery convention). Behaviour: reads `mergeQueueEntry` for the PR via
  GraphQL; for an armed-but-not-yet-enqueued PR attempts
  `enqueuePullRequest(jump: true)` directly (a jump enqueues at the front);
  for a never-armed PR refuses with a named reason; pins `expectedHeadOid`
  to the PR's current `headRefOid`; prints in-flight entry count and requires
  `--reason "<text>"` (the deliberate-act body — doubles as the attribution
  comment) plus `--yes` when stdin is not a TTY (non-TTY without both →
  refuse); RE-READS `headRefOid` + entry state after confirmation and
  immediately before the mutation (a vanished entry because the PR MERGED
  exits 0, not error). No `dequeuePullRequest` branch — the mutation is
  attempted once and fails loud; the manual dequeue+re-enqueue recipe lives
  in the runbook (a dequeue emits a removal event that concurrent watchers
  read as a real dequeue and can race a tail re-enqueue — the runbook fences
  live watchers before any manual dequeue). On successful mutation, posts
  the attribution comment; if the comment post fails after a successful
  jump, exits with a distinct "jumped-but-unattributed" code (never masks it).
- New runbook `knowledge-base/engineering/operations/runbooks/merge-queue-jump.md`:
  urgency bar (prod-down / security / data-loss), rebuild-cost caveat
  (jump rebuilds every in-progress entry), the tiered model (queue → jump →
  `--admin`), attribution model, and the `merge-queue-cla-synthetics`
  note that the synthetic's hook coverage is unaffected by a jump.
- Test suite `plugins/soleur/test/merge-queue-jump.test.sh` mirroring the
  merge-queue script conventions (fixture battery + assertion floor:
  not-queued refusal, armed-not-yet-enqueued, stale `expectedHeadOid`, and
  the GraphQL stub serving both entry-present and entry-absent shapes).
  Auto-registered via `SUITE_GLOBS` (`plugins/soleur/test/*.test.sh`) — do
  NOT add a `run_suite` line (double-registration).

### Phase 2 — CLA group enumeration (precondition, must precede Phase 3)

- `scripts/merge-queue-cla-verify.sh`: enumerate every constituent PR of the
  group — PRIMARY source `mergeQueue(branch:"main").entries` filtered by
  `headCommit.oid == HEAD_SHA` (binds members to the exact candidate under
  verification; immune to position renumbering — a Phase-1 jump or a member
  ejection reorders `positions` mid-verify, and a position-keyed set can
  eject healthy groups on a jumped PR's pending CLA or under-enumerate after
  a removal). `positions ≤ named PR's position` is the documented fallback
  if the correlation does not hold. Invariants (fail closed): the `pr-<N>`
  parsed from `head_ref` MUST appear in the enumerated member set and MUST
  be its maximal member; `entries` pagination (`pageInfo.hasNextPage`) must
  be handled or die; zero enumerated members is a failure, never a pass;
  the entries read gets at least the existing `gh_read` retry budget.
  Verify each member head's latest `cla-check` + `cla-evidence` check-runs
  (app 15368) completed/success. Fail closed on enumeration gaps
  (unparseable group, unresolvable member, gh error) → failure post →
  ejection, never partial success. The reworked script MUST still green
  singleton groups: it goes live on the default branch at merge while
  `max_entries_to_merge` only moves at the post-merge apply — singleton
  coverage is the backward-compat contract for the merge→apply window (an
  out-of-band console/API raise before the PR merges leaves old script +
  grouped refs: if a grouped `head_ref` still parses as `pr-<N>-<sha>` the
  old regex verifies only the named member — call out in rollout notes).
- TR1 measurements land first: `MergeQueueEntry.headCommit` ↔ candidate
  `head_sha` correlation (decides primary vs fallback source), grouped
  `merge_group.head_ref` shape AND which member its `pr-<N>` names (deepest
  vs leader — an inversion flips the required direction), whether in-flight
  group members remain in `mergeQueue.entries` while building (if they drop
  on dispatch, enumeration is empty → wedge), the `check_response_timeout`
  clock origin, and ALLGREEN bisection-vs-group-atomic ejection behaviour
  (the 0.85^N sizing assumes group-atomic — verify before raising).
- Companion edits: `merge-queue-cla-synthetics.yml` comment/contract;
  `merge-queue-cla-verify.test.sh` (GOOD_REF battery + F3 rejections +
  pass floor + a negative row: green head-PR + red member → fail);
  `merge-queue-cla-workflow-wiring.test.sh` W-property floors if env/steps
  change; `required-checks-merge-group-coverage.test.sh` + fixture if the
  posting shape changes.

### Phase 3 — The raise (one apply-sized PR content, after Phase 2)

- `infra/github/ruleset-ci-required.tf` L349 → `max_entries_to_merge = 3`
  (+ comment block re-derivation); `scripts/create-ci-required-ruleset.sh`
  L117 (all seven params stay in lockstep); `infra/github/README.md` params
  table L110.
- `tests/scripts/test-audit-ruleset-bypass.sh`: Guard-2 safety assertion
  rewritten as a sanctioned-set check `{1,3}` (the transitional window —
  a value-only 3→1 rollback PR must stay GREEN; sanction removal of 1 is a
  separate deliberate act after the soak), mutation row `T-mq-1.m9`
  reworked to mutate to an *unsanctioned* value → RED, fixture
  `t_mq_param_parity_noncanonical_pass` (H2, ~L1153–1208 — hardcodes =1 in
  all three sources) migrated to the sanctioned value, `_mq_write_queue_block`
  fixture comment refreshed.
- Sweep of `pr-<N>-` readers (list in Research Insights) — update triage
  commands that assume one PR per group; each emits a shared caveat line
  ("grouped refs name the deepest member — if no run under `pr-<N>-`, list
  recent `merge_group` runs and correlate by `headSha`/`createdAt`"). The
  stall-check template additionally notes the aging window covers only
  `position <= max_entries_to_build`, so a group's later members degrade to
  head-entry visibility.
- `test-trio-baseline-census.sh` gains a grouped-shape fixture row in this
  PR (not conditional): chained per-PR squashes make `HEAD^1` judge only
  the last member's delta — the row pins the measured shape.
- Keep: SQUASH, ALLGREEN, min=1, wait=0, max_build=2; timeout=75 pending the
  TR1 re-derivation (checklist requires re-deriving it against the larger
  group unconditionally — land the derived number or a recorded keep-75
  justification in the same PR).
- Apply path: `apply-github-infra.yml` (`0 add / 1 change / 0 destroy`),
  matching the 75-min raise precedent; no `[skip-github-apply]` /
  `[ack-destroy]`. Post-apply verify selects `.type=="merge_queue"`.

### Phase 4 — Records + canary

- ADR-270 addendum: measured group semantics (grouped `head_ref` shape,
  `headCommit` correlation result, ejection-clock origin, group-merge
  commit/push shape, first-ejection observation) + the jump-path decision.
  Not a new ADR.
- CLO addendum on `2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md`,
  conditioned on merge of the implementing PR.
- Canary (agent-run, no SSH): first grouped merge — per-PR squash commit
  shape, push-event count per group (ADR-276 dedupe interaction), per-member
  CLA coverage; first ALLGREEN group ejection — blast-radius observation;
  live config read-back (`maximumEntriesToMerge=3`).

## Files to Create

- `scripts/merge-queue-jump.sh`
- `plugins/soleur/test/merge-queue-jump.test.sh`
- `knowledge-base/engineering/operations/runbooks/merge-queue-jump.md`

## Files to Edit

- `scripts/merge-queue-cla-verify.sh` (enumeration)
- `.github/workflows/merge-queue-cla-synthetics.yml` (comment/contract)
- `plugins/soleur/test/merge-queue-cla-verify.test.sh`
- `plugins/soleur/test/merge-queue-cla-workflow-wiring.test.sh`
- `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` +
  fixture (conditional on posting shape)
- `infra/github/ruleset-ci-required.tf` (value + comment)
- `scripts/create-ci-required-ruleset.sh` (value + sync-guard comment)
- `infra/github/README.md` (params table + jump-path pointer)
- `tests/scripts/test-audit-ruleset-bypass.sh` (Guard-2 pin + T-mq-1.m9)
- `tests/scripts/test-trio-baseline-census.sh` (grouped-shape fixture row —
  chained per-PR squashes make `HEAD^1` judge only the last member's delta)
- `plugins/soleur/scripts/sync-pr-behind.sh` L556, `monitor-pr-checks.sh`
  L451, `plugins/soleur/skills/ship/references/merge-queue-dequeue.md` L28,
  `plugins/soleur/skills/drain-prs/SKILL.md` L88,
  `.github/workflows/merge-queue-stall-check.yml` L221 (grouped-ref triage
  fallback line) — AND their test files (`sync-pr-behind.test.sh` L951,
  `monitor-pr-checks.test.sh` L501, `merge-queue-stall-check.test.sh`,
  `ship-phase-7-poll-fixtures.test.sh`, `drain-prs.test.sh`), plus
  conditional `pr-<N>-` fixture batteries pending TR1's head_ref finding
  (`ci-pr-affected-replay.test.sh`, `merge-queue-cla-workflow-wiring.test.sh` L474)
- `.github/CODEOWNERS` (explicit row for `merge-queue-jump.sh`)
- `knowledge-base/engineering/architecture/decisions/ADR-270-...md` (addendum)
- `knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` (addendum)

## Acceptance Criteria

- [ ] `bash scripts/merge-queue-jump.sh --help` exits 0 and prints usage;
  `merge-queue-jump.test.sh` passes its assertion floor (including
  not-queued refusal and stale-`expectedHeadOid` rows).
- [ ] `merge-queue-cla-verify.sh` on a fixture group with a non-green member
  exits non-zero and writes the `reason=` output (fail-closed enumeration).
- [ ] `tests/scripts/test-audit-ruleset-bypass.sh` green with the sanctioned
  value 3, and mutating any of the three parity sources to an unsanctioned
  value produces RED.
- [ ] Live `mergeQueue(branch:"main").configuration` reports
  `maximumEntriesToMerge=3` post-apply; the anonymous
  `rules/branches/main` probe prints `3`.
- [ ] ADR-270 carries the dated addendum recording the four group-semantics
  measurements and the jump-path decision.
- [ ] First grouped merge observed: per-PR squash commits, per-member CLA
  synthetic coverage, push-event count recorded in the addendum.

## Technical Requirements

- TR1 (measurement preconditions): `headCommit` correlation, grouped
  `head_ref` shape, ejection-clock origin — resolved and recorded before
  Phase 3 lands (Phase 2's enumeration design depends on the first two).
- TR2 (auth): jump script uses the actor's own `gh` auth only; the CLA
  synthetic keeps `GITHUB_TOKEN` (15368) — never harmonized onto an App
  token. Any future workflow mint uses `mint-infra-app-token` +
  `infra-privileged` environment (ADR-241 G7f registration).
- TR3 (parity): the seven merge_queue params move together across tf / DR
  skeleton / README; Guard-2 derives the sanctioned set.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carried forward from
brainstorm `## Domain Assessments`; no fresh assessment per carry-forward rule)

### Engineering

**Status:** reviewed
**Assessment:** (CTO, brainstorm) — A batches landings not builds; B script
first, then max=3 behind CLA enumeration + Guard-2 rewrite + measurements +
canary; keep ALLGREEN/min=1/wait=0/timeout=75/max_build=2.

### Legal

**Status:** reviewed
**Assessment:** (CLO, brainstorm) — enumeration MUST be merge-blocking and
fail-closed with a negative test; keep 15368 auth; jump = designed exception,
attributed/deliberate/recorded; CLO addendum conditioned on implementing-PR
merge. GDPR: no new PII processing surface (attribution lands on the GitHub
PR timeline — an existing surface, no new persistent store); `soleur:gdpr-gate`
analysis discharged by the CLO's own Phase 0.5 assessment.

### Product/UX Gate

Tier: NONE — no user-facing surface (Files lists contain no UI-surface paths;
mechanical override did not fire).

## Infrastructure (IaC)

### Terraform changes

`infra/github/ruleset-ci-required.tf` `merge_queue` block only (value +
comment re-derivation). No new resources, providers, or sensitive variables.
Backend: existing R2 remote state (`soleur-terraform-state`).

### Apply path

`apply-github-infra.yml` in-place update — `0 add / 1 change / 0 destroy`
(the 60→75 raise precedent, plan `2026-10-11-fix-merge-queue-check-response-timeout-75`).
No host resources; no downtime. Post-apply live read selects `.type=="merge_queue"`.

### Distinctness / drift safeguards

Single environment (repo rulesets); `scheduled-terraform-drift.yml` runs
full `terraform plan` on `infra/github` and diffs `merge_queue` param
values — a value applied outside Terraform shows as drift (workflow comment
L46–51); the anonymous probe covers live read-back without credentials.

## Observability

```yaml
liveness_signal:
  what: live ruleset merge_queue params read back (anonymous REST) + stall probe coverage
  cadence: daily (scheduled-terraform-drift) + every ~10 min stall dispatch on real queue depth
  alert_target: GitHub issues (merge-queue-stall / action-required labels)
  configured_in: .github/workflows/scheduled-terraform-drift.yml, merge-queue-stall-check.yml
error_reporting:
  destination: stderr (jump script, non-zero exit with named reason) + check-run failure posts (CLA synthetic failure step)
  fail_loud: yes — verify failure posts BOTH cla names as failure and dequeues; jump script never exits 0 on a failed mutation
failure_modes:
  - {mode: "grouped entry ejected healthy (timeout-clock miscount)", detection: "merge-queue-stall-check ages position<=max_entries_to_build entries >45min", alert_route: "action-required issue"}
  - {mode: "CLA enumeration gap / unresolvable member", detection: "cla-verify die() → failure post on candidate", alert_route: "check-run failure, dequeue"}
  - {mode: "jump mutation rejected (permission/schema/stale head)", detection: "script non-zero + reason on stderr", alert_route: "actor's shell"}
logs:
  where: GitHub Actions run logs (cla-synthetics, stall-check); jump script is stateless (no logs)
  retention: GHA default (~90d)
discoverability_test:
  command: "curl -s https://api.github.com/repos/jikig-ai/soleur/rules/branches/main | jq -r '.[] | select(.type==\"merge_queue\") | .parameters.max_entries_to_merge'"
  expected_output: "3"
```

## Guard Contract

### Guard 1 — CLA group enumeration (merge-queue-cla-verify.sh)

**Property.** Every constituent PR of a merged group has its head's latest
`cla-check` + `cla-evidence` (app 15368) verified completed/success before the
synthetic posts success.

**Assembly.** The group's membership derived from `mergeQueue(branch:"main").entries`
(positions ≤ named PR's) — the derivation is structural (queue state), not a
member list; the verify must enumerate, not parse a single `pr-<N>` ref.

**Mutation matrix:**

| # | Edit | Expected |
|---|---|---|
| 1 | Group fixture where a non-head member lacks `cla-evidence` success | RED (failure post) |
| 2 | `mergeQueue.entries` read returns an unparseable/empty payload | RED (fail-closed, not vacuous success) |
| 3 | Verify step dispatches with zero enumerated members (guard's own dispatch) | RED — a `0 checked` enumeration is a failure, not a pass |
| 4 | Suite row: fixture where head-PR green AND all members green | must-PASS — the honest path |
| 5 | Suite row: must-PASS input that is NOT the canonical singleton (a 3-member all-green group) | must-PASS — pins multi-member acceptance |

### Guard 2 — Sanctioned `max_entries_to_merge` (test-audit-ruleset-bypass.sh `_mq_guard2`)

**Property.** The three parity sources carry `max_entries_to_merge` from the
sanctioned set ({3} after this change) and identical values.

**Assembly.** The three producers (tf block, DR skeleton JSON, README table
row) — the chokepoint is the seven-param comparison across all three, plus the
value-membership assertion.

**Mutation matrix:**

| # | Edit | Expected |
|---|---|---|
| 1 | Raise tf only to an unsanctioned value (e.g. 7) leaving others at 3 | RED (parity + membership) |
| 2 | Set all three sources to an unsanctioned identical value (e.g. 9) | RED — parity alone must not certify an unauthorized raise |
| 3 | Remove the membership assertion while keeping parity | RED (guard's own dispatch — vacuity row) |
| 4 | Suite row: sanctioned value in one source, different sanctioned-legal shape in comment text | must-PASS where the contract permits (value is pinned, comment wording is not) |
| 5 | Suite row: all three sources at 3 | must-PASS — the post-change canonical |

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-270** (addendum, not new ADR — CTO-ruled): record the grouped-merge
semantics (head_ref shape, headCommit correlation, ejection-clock origin,
commit/push shape), the CLA enumeration design, and the queue-jump decision.
In-scope task in Phase 4.

### C4 views

No C4 impact — enumerated per the completeness mandate: (a) external human
actors: none new (queue machinery operated by the same actor/system set);
(b) external systems: GitHub already modeled as `system "GitHub"` (source
control, CI/CD — `model.c4`); (c) containers/data-stores: none new (stateless
script; ruleset is GitHub-internal); (d) access relationships: unchanged
(actor → GitHub edge already exists).

## Encryption Posture

```yaml
at_rest:
  - store: "Terraform state (ruleset config incl. merge_queue params)"
    mechanism: "R2 remote backend (soleur-terraform-state), provider-managed encryption"
    evidence: "existing backend config in infra/github/main.tf (unchanged)"
    defends_against: "state disclosure at rest"
    does_not_defend: "holder of R2 credentials with bucket read"
    disclosed_as: "existing posture, unchanged by this plan"
in_transit:
  - connection: "gh/curl → api.github.com (GraphQL + REST)"
    tls: provider TLS
    cert_verification: on
    does_not_defend: "endpoint compromise of the token itself"
    disclosed_as: "standard GitHub API TLS"
```

No new persistent store; the only artifact written by the jump path is a GitHub
PR timeline comment on an existing surface.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Label-triggered jump workflow | Larger auth surface (App mint + labeler-authorization gate) + ADR-285 enqueuer-identity failure mode; script is its tested core anyway. Documented as deferred; no tracking issue (re-evaluation trigger lives in the jump runbook: cadence becomes routine) |
| `max_entries_to_merge = 5` | P(group green) ≈ 44% at the measured 15.4% flake rate; 3 ≈ 61% — CTO-ruled |
| `min_entries_to_merge` >1 / wait >0 | Taxes every solo merge for burst-only benefit — CTO-ruled, kept 1/0 |
| Raise `max_entries_to_build` | Real dwell lever but explicitly the issue's non-goal; canary-gated separate lever, documented deferred (re-evaluation trigger: burst dwell persists post-A) |
| HEADGREEN grouping | Members could merge on the head's cumulative build with no per-PR verification — CLA hole (CLO) |
| `--admin` merge as the urgency path | Bypasses all required checks — jump keeps the integrated-state gate (CPO tier model) |

## Open Questions (resolved before Phase 3, not blocking Phase 1)

1. `MergeQueueEntry.headCommit` ↔ candidate `head_sha` correlation (TR1).
2. Grouped `merge_group.head_ref` shape (TR1).
3. `check_response_timeout` clock origin — enqueue or build dispatch (TR1;
   if from enqueue, timeout re-derivation is a Phase-3 prerequisite).
4. `enqueuePullRequest` on an already-queued PR: mutation-alone vs
   dequeue+re-enqueue — resolved by the script's live probe at first use;
   the runbook documents both branches.
