---
title: "docs(arch): record merge-queue grouped-landing canary + session-found follow-ups"
type: docs
date: 2026-11-01
slug: docs-mq-grouped-canary-followups
branch: feat-one-shot-11678-mq-canary-followups
issue: 11678
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# docs(arch): record merge-queue grouped-landing canary + session-found follow-ups

## Overview

The #11678 merge-queue batching arc shipped on 2026-11-01: PR #11681 (squash
`c743ff93`, 00:07Z) raised `max_entries_to_merge` to 3 with CLA group
enumeration, `merge-queue-jump.sh` and Guard-2 `{1,3}`; hotfix #11753
(`220633355f`, 01:55Z) demoted the verifier's ref-embedded-oid equality check to
provenance-only after it falsely ejected rebuilt/multi-member candidates. The
grouped landing the ADR-270 addendum listed as the one unobserved canary path has
since been observed (run `41269037117`, `members=3`). What remains is durable
record-keeping and three session-found machinery items, all landing on this
branch's draft docs PR #11768:

1. Append the grouped-landing canary addendum to ADR-270 — members=3 evidence,
   `head_ref` deepest-member naming, per-member squash landing shape, the
   post-hotfix ejection-stopped state, and the #11688 residual.
2. Add a second-occurrence evidence comment to #11682 (the
   `ship-cmo-content-gate` stale-cwd defect — this session hit it with a valid
   `Reviewed-By-CMO` trailer plus a marketing diff and had to bypass via GraphQL
   mutations).
3. File a focused bug for the `affected-index-ratchet` advisory check being red
   on every head (pre-existing main drift: live 1512 vs baseline 1510).
4. Write the embedded-oid semantics learning into
   `knowledge-base/project/learnings/workflow-patterns/`.
5. Record #11688's mergeQueue entry state in the addendum (measured at plan
   time: not queued, auto-merge disarmed, last removal `failed_checks` at
   01:14Z — pre-hotfix).

## Enhancement Summary

**Deepened on:** 2026-11-01
**Sections enhanced:** gate verification pass over all sections (deepen-plan
Phases 4.4–4.13 run in-process; the agent fan-outs of Phases 2/3/4/5 could not
run — this harness has no Task tool, so skill/learnings/research/review
sub-agents were applied inline by the planner instead, same resolution as
`specs/feat-one-shot-9963-syslog-systemd-journald-path`).

### Gate Verdicts (deepen-plan)

- **4.4 Precedent-diff:** learning-file frontmatter diffed against the sibling
  corpus file `learnings/workflow-patterns/2026-10-31-verify-platform-semantics-before-scoping-a-knob-issue.md`
  — precedent adopted verbatim. No lock/SQL/atomic patterns in scope.
- **4.5 Network-outage / 4.55 Downtime:** no trigger → skipped.
- **4.6 User-Brand Impact:** PASS — section present, threshold `none`, concrete
  artifact named; files are `knowledge-base/**` only, outside the sensitive-path
  regex, so no scope-out bullet required.
- **4.7 Observability:** pure-docs (`knowledge-base/**` only) → gate skips
  silently; the `## Observability` block still validates (5 fields present and
  non-placeholder; `discoverability_test.command` starts with allowlisted
  `grep`, carries no SSH and no shell metacharacters; `expected_output` is the
  literal `1`).
- **4.8 PAT-shaped variable:** PASS — zero matches.
- **4.9 UI wireframe:** no UI-surface files → skipped.
- **4.10 Encryption Posture:** no `.tf`/migration/cloud-init/compose files; the
  word "queue" in prose is GitHub's merge-queue feature, not a store this plan
  introduces, and no new cross-component connection is created → skipped.
- **4.11 Guard Contract:** deliverable contains no guard → skipped.
- **4.12 Scope Check:** PASS — exactly one unfenced `## Scope Check`; all
  subsections present; all asks mapped; `Recommendation: single PR` present.
- **4.13 Task Design:** no new autonomous-task surface → skipped.

### Citation Verification (deepen quality checks)

- Squash SHAs `c743ff93`, `220633355f`, `4393472919`, `0e8a6ebb02`,
  `95231bda1b`, `4366c47940` — all confirmed ancestors of `origin/main`.
- PR states re-verified live: #11681, #11753, #11739, #11734, #11756, #11728
  all MERGED; #11768 OPEN (this branch's WIP draft).
- Issue states re-verified live: #11678 CLOSED; #11682, #10959, #10860,
  #10448, #10865 OPEN.
- Rule-ID citation audit: only `wg-cla-signed-author-before-merge` is cited;
  verified ACTIVE in `AGENTS.md`.
- Label audit: `type/bug`, `priority/p2-medium`, `domain/engineering`,
  `meta/machinery` all exist (`gh label list`).
- Every `knowledge-base/` path the plan cites resolves on disk.
- All plan-prescribed probes were executed at plan time (run list, GraphQL
  queue read, alert-gate run list) — outputs recorded in Research Insights.

### New Considerations Discovered

- #11688 `mergeStateStatus` drifted `UNKNOWN` → `DIRTY` between the parent
  session's measurement and this pass; Phase 0 of the plan re-reads live state
  at write time so the addendum never cites a stale verdict.
- The members=3 group produced **one push event per member landing** (three
  `codeql-main-alert-gate.yml` runs) — measured during planning and written
  into the addendum content spec.

## Research Insights

**Relevant file paths.**

- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` —
  addenda are appended at EOF as `### Addendum <date>` siblings; the newest is
  `### Addendum 2026-10-31 (#11678)` at :982 whose "Open measurements for the
  canary" list (:1028-:1034) this addendum answers.
- `scripts/merge-queue-cla-verify.sh` — post-hotfix semantics at :62-66
  (ref-embedded oid is minted at group (re)creation and is provenance-only; the
  binding is each entry's `headCommit.oid == HEAD_SHA`) and the
  `merge-queue-cla-verify=OK members=N anchor=<kind> embedded=<oid>` emit at
  :186.
- `.claude/hooks/ship-cmo-content-gate.sh` — the stale-cwd defect mechanism:
  `BASE_REF` resolves `origin/main` then `git log ${BASE_REF}..HEAD` (:85-92)
  and `git diff ${BASE_REF}...HEAD` (:98) evaluate the *session cwd*, so a
  session rooted at the main checkout sees an empty range and an empty
  marketing diff even when the real branch carries the trailer and the diff.
- `.github/workflows/ci.yml` :417-:459 — `affected-index-ratchet` is
  `continue-on-error: true` (advisory, absent from
  `scripts/ci-required-ruleset-canonical-required-status-checks.json`); the job
  runs `python3 -I scripts/ci-pr-affected-replay.py ratchet` and emits
  `SOLEUR_PR_AFFECTED_RATCHET exit=N reason=<r>`.
- `plugins/soleur/scripts/sync-pr-behind.sh` :249-:300 — the canonical
  queue-state GraphQL read (`isInMergeQueue`, `mergeQueueEntry{state}`,
  `autoMergeRequest`, newest `REMOVED_FROM_MERGE_QUEUE_EVENT`), also reachable
  as `sync-pr-behind.sh <N> --queue-state`.
- `knowledge-base/project/learnings/workflow-patterns/` — corpus convention:
  `YYYY-MM-DD-<slug>.md`, YAML frontmatter (`module`/`date`/`problem_type`/
  `component`/`symptoms`/`root_cause`/`resolution_type`/`severity`/`tags`),
  `# Learning:` H1, `## Problem`/`## Solution` body.
- `knowledge-base/engineering/operations/runbooks/merge-queue-jump.md` — the
  queue-jump runbook the 2026-10-31 addendum references.

**Institutional learnings that apply.**

- `learnings/workflow-patterns/2026-10-31-verify-platform-semantics-before-scoping-a-knob-issue.md` —
  same arc: verify platform-knob semantics before scoping.
- `learnings/workflow-patterns/2026-10-26-resumed-ship-tails-bypassing-cmo-gate-and-doc-parity.md` —
  the hook that #11682's defect lives in.
- `learnings/2026-10-29-deferred-re-decisions-are-superseded-by-events-and-bills-are-architecture-driven.md`
  — record outcomes as observed rather than deferring.
- Sharp-edges applied: verify every cited issue/PR state cheaply (done, Phase
  0.6); run every prescribed command once before shipping the plan (the two
  read-only probes below were executed during planning); `gh label list`
  confirmed `type/bug`, `priority/p2-medium`, `domain/engineering`,
  `meta/machinery` all exist; plan-into-PR-body records route through `ship`,
  so all durable records here are files, issue comments, or a new issue.

**Premise Validation (Phase 0.6).** Checked: #11678 CLOSED; #11682 OPEN with
expected labels (`type/bug`, `priority/p2-medium`, `domain/engineering`,
`meta/machinery`); #10959/#10860/#10448/#10865 all OPEN with the titles the
brief describes; ADR-270, `merge-queue-cla-synthetics.yml`,
`ci-pr-affected-replay.py`, `lint-followthrough-varq-ban.sh`,
`merge-queue-jump.sh`, the runbook, and the canonical required-checks JSON all
exist on this branch. Spot-checks re-run cheaply: the six newest
`merge-queue-cla-synthetics.yml` runs are all `success` (post-01:55Z); PR
#11688 is OPEN, `mergeStateStatus` now reads `DIRTY` (was `UNKNOWN` in the
parent session's measurement), `isInMergeQueue=false`,
`autoMergeRequest=null`, newest removal event `failed_checks` at
2026-11-01T01:14:01Z (pre-hotfix ejection — it has NOT re-entered the queue).
`alert-gate` push runs confirm one push event per member landing: the members=3
group produced three `codeql-main-alert-gate.yml` runs on three distinct squash
SHAs (`0e8a6ebb02` 03:44Z, `95231bda1b` 04:02Z, `4366c47940` 05:03Z).
Collision precheck: #11682/#10959/#10860/#10448/#10865 clean; #11678 names only
this branch's own draft PR #11768 (expected); #11688 names itself. Nothing was
stale except the #11688 `mergeStateStatus` drift noted above, which the
addendum records as the residual.

**Property List (Phase 0.6b).**

1. The grouped-landing canary outcome is durably recorded in ADR-270.
2. The second stale-cwd occurrence of `ship-cmo-content-gate` is documented on
   the existing defect issue (#11682).
3. The `affected-index-ratchet` main drift is tracked in a focused issue with
   the measured numbers, consequence, fix size, and S4 references.
4. The embedded-oid semantics miss is captured in the learnings corpus.
5. #11688's queue state is measured and recorded.
6. The ship path avoids the known-broken gates (docs-titled PR, worktree cwd,
   no `git stash`).

**Cut List (Phase 0.6b).**

- "Wait for / synthesize a live grouped landing to observe the canary" → cut:
  the property (canary outcome recorded) is already covered by run
  `41269037117` (`members=3`, plus five `members=2` runs and one `members=1`
  run post-hotfix); re-observation buys nothing.
- A new GitHub issue for the CMO-gate stale-cwd defect → cut: identical defect
  is already filed as #11682; the second occurrence is evidence, filed as a
  comment.
- A fix for the ratchet baseline in this PR → cut: out of scope per the brief;
  this PR files the drift-repair issue.

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Reality (measured 2026-11-01) | Plan response |
|---|---|---|
| #11688 `mergeStateStatus UNKNOWN` | Now `DIRTY`; still not queued, auto-merge disarmed | Addendum records current state and the owner-rearm residual |
| Canary "the one unobserved path" | Already observed: `41269037117` logged `members=3 anchor=headCommit` | Record-as-observed addendum; no waiting step |
| "Bug (a) needs a filing" | #11682 already covers the identical defect | Evidence comment, not a new filing |

## Implementation Phases

### Phase 0 — Re-read live state (all read-only)

State moves; the addendum must cite the values at write time, not this plan's.

1. `gh run list --workflow merge-queue-cla-synthetics.yml -L 10 --json databaseId,conclusion,createdAt` —
   confirm no post-01:55Z failure (failures must end at/before 01:45Z).
2. Queue-state read for #11688 — either
   `bash plugins/soleur/scripts/sync-pr-behind.sh 11688 --queue-state` (the
   canonical read) or the equivalent `gh api graphql` against
   `pullRequest{ isInMergeQueue mergeQueueEntry{ state position } state
   autoMergeRequest{ enabledAt } timelineItems(itemTypes:[REMOVED_FROM_MERGE_QUEUE_EVENT]) }`.
   Record `isInMergeQueue`, `autoMergeRequest`, newest removal `reason` +
   `createdAt`. (Plan-time result: `false` / disarmed / `failed_checks`
   01:14Z.)
3. For the addendum's squash-shape claim, re-confirm the three landing commits:
   `git log origin/main --format='%h %s' -8` naming `0e8a6ebb02` (#11734),
   `95231bda1b` (#11756), `4366c47940` (#11728), and one
   `codeql-main-alert-gate.yml` run per member
   (`gh run list --workflow codeql-main-alert-gate.yml -L 12 --json headSha,createdAt`).

### Phase 1 — ADR-270 addendum (the docs deliverable)

Append at EOF of `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`,
as a sibling `###`-level heading matching the established convention:

`### Addendum 2026-11-01 (#11678, #11768): grouped-landing canary — ejection stopped, members=3 observed`

Content, answering the 2026-10-31 addendum's open measurements (:1028-:1034):

- **Grouped `merge_group.head_ref` shape + which member `pr-<N>` names:**
  `gh-readonly-queue/main/pr-11756-0e8a6ebb...` — deepest-member naming; the
  embedded oid equals the group's final integrated head.
- **`merge-queue-cla-verify` log evidence:** run `41269037117` (03:24:17Z)
  logged `merge-queue-cla-verify=OK members=3 anchor=headCommit
  embedded=0e8a6ebb0242538b67953fd44f72a89fab715012 pr11734@b073c17123
  pr11728@263f0dd5b2 pr11756@3fd3d716d4` — the `headCommit` anchor bound the
  candidate while the embedded oid remained provenance (the #11753 hotfix's
  semantics hold on a real group). Five further post-hotfix groups logged
  `members=2`; one `members=1`.
- **In-flight member listing:** entries enumerable while building (the members=3
  enumeration succeeded against the live `mergeQueue.entries`).
- **Per-member squash + push-event shape:** each member landed its own single
  squash commit on main (`0e8a6ebb02` #11734, `95231bda1b` #11756,
  `4366c47940` #11728) and its own `codeql-main-alert-gate.yml` push run —
  push-event count per group = N (one per member), the ADR-276 dedupe
  interaction measured.
- **ALLGREEN bisection-vs-group-atomic ejection:** still unobserved — no
  post-hotfix ejection exists to discriminate; record as open.
- **Ejection stopped:** all post-01:55Z synthetics runs succeeded (seven:
  `41263787987`, `41264507975`, `41268398857`, `41269037117`, `41270354718`,
  `41271524552`, `41273043596`); `tampered pairing is refused` rejections end
  at 01:45Z pre-hotfix.
- **Residual:** #11688 ejected pre-hotfix (`failed_checks` 01:14Z), is not
  queued, auto-merge disarmed, `mergeStateStatus DIRTY`; re-arm is the PR
  owner's action (owners notified on #11688 per the brief); its only failing
  check is advisory `affected-index-ratchet` (Phase 3's filing).
- Prose rule: record facts, no actor+imperative pairs — the ADR dir is inside
  `lint-infra-no-human-steps.py`'s `SCAN_DIRS`, so the addendum must not read
  as prescribed human steps.

### Phase 2 — Evidence comment on #11682

`gh issue comment 11682` with a second-occurrence note: the #11678 session hit
the same gate with a valid pushed `Reviewed-By-CMO` trailer AND a
marketing-path diff on the branch; the hook's `git log origin/main..HEAD` /
`git diff origin/main...HEAD` evaluated the session cwd (main checkout), saw an
empty range + empty diff, and denied anyway; bypass was GraphQL mutations
(`markPullRequestReadyForReview` / `enablePullRequestAutoMerge`). Note the
marketing-diff variant: even the path check fails closed on stale cwd, not only
the trailer check. Reference `.claude/hooks/ship-cmo-content-gate.sh` :85-:98.

### Phase 3 — File the `affected-index-ratchet` drift bug

Focused filing per the brief's default (rationale: a distinct measured defect +
a concrete user-visible consequence that #10959's reveal-4 worklist does not
name — see `decision-challenges.md`).

- Title: `ci: affected-index-ratchet red on every head — stale accept baseline vs live refs on main`
- Labels: `type/bug`, `priority/p2-medium`, `domain/engineering`, `meta/machinery`
- Body must carry: the measured row `SOLEUR_PR_AFFECTED_RATCHET exit=1
  reason=stale-accept live=1512 baseline=1510` (check-run on `4366c47940`, run
  `41273043589` job `124749556077`); the moved/added ref pairs
  `scripts/lint-followthrough-varq-ban.sh:{318,354,599}` anchors
  `a156176796ef`/`0e28e1d32b7b`/`538ede2b0768`; the
  `oracle-inputs-changed: scripts/test-all.sh` warning; consequence (every head
  shows a red advisory check; it is the only failing check on #11688 and it
  trains reviewers to ignore the signal); fix size (~accept rows / edge
  declarations regenerated via `python3 -I
  scripts/ci-pr-affected-replay.py ratchet --print-baseline`); and
  `Ref #10959 #10860 #10448 #10865` with a one-line relationship note
  (#10865's soak pauses on red "until it is repaired" — this is the repair
  issue it waits on).

### Phase 4 — Learning entry

Create `knowledge-base/project/learnings/workflow-patterns/2026-11-01-<slug>.md`
(slug at write time, e.g. `minted-oid-is-provenance-headcommit-is-the-binding`)
following the corpus frontmatter: `module: System`, `problem_type:
workflow_issue`, `component: development_workflow`, `root_cause:
wrong_assumption` (the verifier bound a mint-time ref-embedded oid to
`head_sha`; on rebuild/multi-member groups the minted oid legitimately
diverges), `resolution_type: workflow_improvement`, `severity: medium` (it
ejected real PRs before the hotfix), `tags: [merge-queue, graphql, adr-270,
clarify-binding-vs-provenance]`. Body: `## Problem` — strict
ref-embedded-oid == head_sha ejected rebuilt/multi-member candidates (three
ejections incl. #11688, fixed by #11753); `## Solution` — embedded oid is
provenance recorded at mint; the binding is each entry's `headCommit.oid ==
HEAD_SHA`; pin: when two identifiers name the same object at different times,
bind on the per-entry record, treat the minted one as an audit trail, and write
the regression row that exercises divergence before relying on the check.

### Phase 5 — PR metadata + commit

- Retitle draft PR #11768 to `docs(arch): record merge-queue grouped-landing canary + machinery follow-ups (#11678)` —
  `docs`-prefixed so `ship-cmo-content-gate.sh` reads `IS_FEAT=0` and the
  trailer/marketing checks are never reached on this diff.
- `Ref #11678` in the PR body (ship owns the body; no `Closes` — the issue is
  already closed).
- Commits via `git -c user.name="Jean Deruelle" -c
  user.email="jean.deruelle@jikigai.com"` (the worktree already resolves this
  identity; `wg-cla-signed-author-before-merge` — never
  `noreply@anthropic.com`, never `devin-ai-integration[bot]`).
- No `git stash` anywhere (worktree rule).

### Phase 6 — Ready + merge arm (from the worktree cwd)

- Run `gh pr ready 11768` and `gh pr merge 11768 --squash --auto` **from
  `/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-11678-mq-canary-followups`** —
  every cwd-evaluating hook (`ship-cmo-content-gate`, `cla-signed-author-gate`,
  `pre-merge-rebase`, `ship-unpushed-commits-gate`) resolves the correct HEAD
  there; running them from the main checkout is the #11682 defect shape.
- Expected: docs title → CMO gate exits at `IS_FEAT=0`; required checks come
  from `scripts/ci-required-ruleset-canonical-required-status-checks.json`;
  `affected-index-ratchet` is advisory (`continue-on-error`) and does not
  block.
- If a hook still denies on a stale cwd despite the worktree cwd, the
  documented bypass is the GraphQL mutation pair
  (`markPullRequestReadyForReview`, `enablePullRequestAutoMerge`) — the same
  bypass the #11678 session used; record any use of it on #11682 as further
  evidence.
- Queue semantics once armed: the PR enters the merge queue like any other
  (`max_entries_to_merge=3`, so it may land grouped — that is the machinery
  working as recorded, not an event to report).

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` — append `### Addendum 2026-11-01` at EOF.

## Files to Create

- `knowledge-base/project/learnings/workflow-patterns/2026-11-01-<embedded-oid-slug>.md` — the embedded-oid semantics learning.
- `knowledge-base/project/specs/feat-one-shot-11678-mq-canary-followups/tasks.md` — task breakdown.
- `knowledge-base/project/specs/feat-one-shot-11678-mq-canary-followups/decision-challenges.md` — ruling ledger.

## External artifacts (not files)

- Issue comment on #11682 (Phase 2).
- New issue: ratchet drift bug (Phase 3) — record its number in `tasks.md` or
  the session summary.

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong or missing
  engineering record — ADR-270 would misstate how the merge queue lands grouped
  candidates, and two machinery defects (stale-cwd CMO gate, red advisory
  ratchet) would stay untracked. Sole-facing artifact: internal/operator docs
  and issue tracking, no end-user surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing — the diff is knowledge-base documentation; all quoted identifiers
  (run IDs, SHAs, PR numbers) are already public in the repo's own records.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** docs-and-filings only; the worst
  outcome is an inaccurate internal record, not a user-facing artifact or data
  exposure.

## Observability

```yaml
liveness_signal:
  what: "ADR-270 carries the 2026-11-01 addendum and the ratchet-drift issue exists"
  cadence: "checked once at ship time; thereafter the record is static"
  alert_target: "none — the record itself is the signal"
  configured_in: "knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md"
error_reporting:
  destination: "required CI checks on PR #11768 (ci.yml required contexts per scripts/ci-required-ruleset-canonical-required-status-checks.json)"
  fail_loud: "a red required check or a lint-infra-no-human-steps.py finding on the ADR addendum"
failure_modes:
  - mode: "addendum lands with wrong run IDs or SHAs"
    detection: "Phase 0 re-read + AC greps pinning the run-ID literals"
    alert_route: "PR checks + review"
  - mode: "#11682 comment or new issue filed with wrong numbers"
    detection: "issue body re-read after create (gh issue view)"
    alert_route: "PR checks + review"
logs:
  where: "git history on this branch; GitHub issue/PR records"
  retention: "permanent"
discoverability_test:
  command: grep -c 'Addendum 2026-11-01' knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md
  expected_output: "1"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change
(knowledge-base documentation, one issue comment, one issue filing).

## Architecture Decision (ADR/C4)

No architectural decision is made: the addendum records observations against an
existing accepted ADR — it does not reverse, extend, or create a decision. A
competent engineer reading the ADR corpus plus C4 is not misled by this record;
the grouped-landing facts answer the ADR's own "open measurements" list.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "ADR-270 addendum recording the grouped-landing canary outcome (members=3 run evidence, head_ref naming, per-member squash shape, ejection-stopped state, #11688 residual) — docs PR (this branch's draft #11768). Include `<!-- iac-routing-ack -->` if the addendum touches infra text." [brief] | Phase 1; Files-to-Edit ADR-270; ack line in plan frontmatter area | mapped |
| 2 | "Comment on #11682 with the second occurrence (session hit the gate with Reviewed-By-CMO trailer + marketing diff, bypassed via GraphQL mutations)." [brief] | Phase 2 | mapped |
| 3 | "File the affected-index-ratchet drift bug (or justify #10959 coverage): title, measured numbers, consequence (every head shows red advisory check; only failing check on #11688), fix size (~accept rows/edge declarations), Ref #10959 #10860 #10448 #10865." [brief] | Phase 3 | mapped |
| 4 | "Learning entry in knowledge-base/project/learnings/workflow-patterns/ on the embedded-oid semantics miss (mint-time ref-embedded oid = provenance; per-entry headCommit.oid = binding) following the corpus's frontmatter pattern." [brief] | Phase 4; Files-to-Create learning | mapped |
| 5 | "MergeQueue state check for #11688 via `gh api graphql` to record whether it re-entered the queue." [brief] | Phase 0.2 → recorded in Phase 1 addendum | mapped |
| 6 | "Do NOT use `git stash`. Do NOT use `gh pr ready`/`gh pr merge` for feat-titled PRs (CMO gate bug, unfixed) — this PR should be docs-titled; if the gate still blocks, GraphQL mutations are the documented bypass." [brief constraint] | Phase 5, Phase 6 | mapped |
| 7 | "plan must carry the `## Observability` block (5 fields) — for a docs/KB PR most fields are N/A but the block must exist; discoverability_test.command must run WITHOUT SSH." [brief constraint] | `## Observability` | mapped |
| 8 | "Commits must be authored+committed by a CLA-signed identity (wg-cla-signed-author-before-merge) — use the repo's allowlisted identity via `git -c`, never `devin-ai-integration[bot]` and never `noreply@anthropic.com`." [brief constraint] | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 0 re-read probes | "MergeQueue state check for #11688 via `gh api graphql`"; "no post-01:55Z `tampered pairing is refused` rejections" | asked |
| Phase 1 ADR-270 addendum | "ADR-270 addendum recording the grouped-landing canary outcome … docs PR" | asked |
| Phase 2 #11682 comment | "Comment on #11682 with the second occurrence" | asked |
| Phase 3 ratchet bug filing | "File the affected-index-ratchet drift bug (or justify #10959 coverage)" | asked |
| Phase 4 learning entry | "Learning entry in knowledge-base/project/learnings/workflow-patterns/" | asked |
| Phase 5 PR metadata + identity | "this PR should be docs-titled"; "use the repo's allowlisted identity via `git -c`" | asked |
| Phase 6 ready + merge arm | "if the gate still blocks, GraphQL mutations are the documented bypass" | asked |
| tasks.md + decision-challenges.md | "persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/<branch>/decision-challenges.md" | asked |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base`
- Planned files: 4 (1 edit + 3 create) | Estimated changed lines: ~160
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `grep -c 'Addendum 2026-11-01' knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` returns 1.
- [ ] AC2: The addendum names run `41269037117`, the literal `members=3`, the `gh-readonly-queue/main/pr-11756-` head_ref shape, and all three member landing SHAs (`0e8a6ebb02`, `95231bda1b`, `4366c47940`).
- [ ] AC3: The addendum states the post-hotfix ejection-stopped evidence (all seven post-01:55Z runs) and records #11688's queue residual (not queued, disarmed, `failed_checks` removal at 01:14Z).
- [ ] AC4: `gh issue view 11682 --comments` shows a new comment describing the second occurrence (trailer + marketing diff invisible to the stale-cwd evaluation; GraphQL bypass used).
- [ ] AC5: A new issue exists titled for the ratchet drift, carrying the `live=1512 baseline=1510` measurement, the `lint-followthrough-varq-ban.sh` anchor list, `Ref #10959 #10860 #10448 #10865`, and labels `type/bug`, `priority/p2-medium`, `domain/engineering`, `meta/machinery`.
- [ ] AC6: A new file under `knowledge-base/project/learnings/workflow-patterns/` dated 2026-11-01 states the provenance-vs-binding rule (mint-time embedded oid = provenance; per-entry `headCommit.oid` = binding) with corpus frontmatter (`problem_type`, `root_cause`, `resolution_type`, `severity`, `tags`).
- [ ] AC7: `git diff --name-only origin/main...HEAD` contains no path outside `knowledge-base/` (plus the branch's own spec artifacts), and no `.ts`/`.tsx`/workflow/script edit exists — this is a docs-only PR.
- [ ] AC8: Every commit on `origin/main..HEAD` is authored AND committed by `jean.deruelle@jikigai.com` (`git log --format='%ae %ce' origin/main..HEAD | sort -u` returns one line).
- [ ] AC9: PR #11768 title starts `docs` (verify via `gh pr view 11768 --json title`).

## Test Scenarios

- **AC1/AC2/AC3 (unit — content grep):** given the addendum appended, when the
  greps above run, then all literals resolve (run them once before commit —
  they are the plan's own probes).
- **AC4 (integration):** given the comment posted, when `gh issue view 11682
  --comments` runs, then the comment body contains `stale`/`cwd` context and
  the GraphQL bypass note.
- **AC5 (integration):** given the issue created, when `gh issue view <new>`, then
  labels and `Ref` lines are present; record the number in the session summary.
- **AC7 (unit — diff scope):** given the branch, `git diff --name-only
  origin/main...HEAD` lists only `knowledge-base/` paths.
- **AC8 (unit — git):** given the commits, `git log --format='%ae %ce'
  origin/main..HEAD | sort -u` prints exactly `jean.deruelle@jikigai.com
  jean.deruelle@jikigai.com`.
- **Lint (integration):** `python3 scripts/lint-infra-no-human-steps.py
  --changed --base origin/main` returns clean on the branch's changed docs;
  `npx markdownlint-cli2` is clean on the new/edited docs.

## Open Code-Review Overlap

One hit: #10245 (`review: merge-queue learning on PR 9707`) — a findings-0 QA
review record of a merged PR, not a scope-out touching these files.
Disposition: **acknowledge** (unrelated review record; nothing to fold or
defer).

## Success Metrics

- ADR-270's 2026-10-31 "open measurements" list is answered by the addendum
  (grouped head_ref, member listing, per-member squash + push-event count,
  headCommit correlation).
- #11682 carries the second-occurrence evidence without a duplicate filing.
- The ratchet drift is tracked in a focused, measured issue the S4 soak can
  point at.
- No session-found gate workaround needed on the ship path (docs title +
  worktree cwd); if one was needed, it is recorded on #11682.

## Dependencies & Risks

- **State drift between plan and work:** run IDs/PR state were measured at plan
  time; Phase 0 re-reads them at write time so the addendum cites live values.
- **#11688 may re-arm mid-run:** if it re-enters the queue before the addendum
  lands, record the *newer* state (the addendum cites the read, not a fixed
  claim).
- **Sibling ADR edits:** ADR-270 is a hot document (addenda land per event);
  append-at-EOF + a merge-base re-check before commit bounds the conflict
  surface.
- **The CMO gate bug is unfixed:** mitigated by docs-title + worktree cwd;
  GraphQL bypass is the documented fallback and doubles as #11682 evidence.
- **Ratchet issue duplicates:** #10959 covers reveal-4 worklist items but not
  the measured main-drift pair; the filing `Ref`s it rather than duplicating.

## Non-Goals

- No fix to `affected-index-ratchet` itself (filed for a later PR).
- No fix to `ship-cmo-content-gate.sh` (tracked by #11682).
- No re-observation of a grouped landing (already observed).
- No status flip of ADR-270 (already `accepted` per the 2026-10-09 amendment).

## References

- ADR-270: `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` (addendum convention at EOF; open measurements :1028-:1034).
- Verifier semantics: `scripts/merge-queue-cla-verify.sh` :62-66, :186.
- Gate defect: `.claude/hooks/ship-cmo-content-gate.sh` :85-98; issue #11682.
- Advisory check: `.github/workflows/ci.yml` :417-:459;
  `scripts/ci-pr-affected-replay.py`.
- Canonical required checks:
  `scripts/ci-required-ruleset-canonical-required-status-checks.json`.
- Queue read: `plugins/soleur/scripts/sync-pr-behind.sh` :249-:300.
- Related: #11678 (closed), #11681, #11753, #11739, #11734, #11756, #11728,
  #11688, #11682, #10959, #10860, #10448, #10865.
