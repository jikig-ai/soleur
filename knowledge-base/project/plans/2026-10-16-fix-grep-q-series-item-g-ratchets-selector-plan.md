---
title: "chore: grep -q pipe-guard series, Item G (the --ratchets selector in scripts/test-all.sh) recorded as not fixed"
date: 2026-10-16
slug: fix-grep-q-series-item-g-ratchets-selector
branch: feat-one-shot-grep-q-pipe-guard-item-g-ratchets-selector
issue: 9217
lane: cross-domain
type: chore
---

# chore: grep -q series Item G, `--ratchets` selector: decision record (recorded as not fixed)

## Enhancement Summary

**Deepened on:** 2026-10-16
**Scope of the pass:** a decision record with one comment-only edit, already reviewed by the CTO agent (binding ruling), a three-seat
plan-review panel and a fact-check seat, so the deepen pass ran the mechanical gates and the verify-the-negative sweep instead of a
per-section research fan-out (nothing in the plan is a framework or library claim to research).
**Gates run:** 4.6 user-brand impact (present, threshold `none`, no sensitive path), 4.7 observability (not triggered), 4.8 PAT sweep
(0 hits), 4.9 UI wireframe (no UI surface), 4.10 encryption posture (no `.tf`, store or connection), 4.11 guard contract (no guard
delivered), 4.12 scope check (1 unfenced section, no `unmapped` row). Cited rule id `wg-when-deferring-a-capability-create-a` resolves to
an active rule; commit `ee8644bded` is an ancestor of `origin/main`; cited issues and PRs resolved live.

### Key improvements

1. Q1 now names the one real path-level edit guard (the opt-in freeze edit-lock) and measures that it locks nothing here.
2. Every negative claim ("no hook, CODEOWNERS entry or AGENTS rule bans the edit") was re-grepped: `.github/CODEOWNERS`,
   `.claude/hooks/guardrails.sh`, `AGENTS.md` and `AGENTS.rules.md` each contain 0 mentions of `test-all`.
3. The reviewer-found miscount (10, not 9, always-on files) and the answered `runner-changed` question are carried into Phase 2/3.

### New considerations discovered

- The follow-up's per-path sample must be drawn from the guard's own derived pairs; the first not-selected probe path is not shown to
  be a producer, so its result is provisional until Phase 1 confirms it.

Spec lacks valid lane: defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this one-shot branch.

## Overview

Item G of the pipe-fed `grep -q` sweep (tracker #9217) proposes a `--ratchets` flag for `scripts/test-all.sh`
that would run "exactly the `grep -lis ratchet` set" as one local command. The series brief calls that runner a
"forbidden-to-edit file". This plan answers three questions with evidence and records a binding ruling:

1. What does "forbidden-to-edit" mean? A cost label, not a prohibition (Research Insights, Q1).
2. Is the selector still needed? No: the property it buys is already bought by `--affected` plus the pre-push
   ratchet lane, and the membership it proposes is a text-mention heuristic (Q2).
3. Change, or recorded as not fixed? **Recorded as not fixed** (CTO ruling below), with the one genuine residual
   gap split into a separate tracked follow-up instead of being folded into this PR.

**Ruled by CTO agent, 2026-10-16: B plus C filed as a separate follow-up issue; do not implement A.** The runner
edit costs a full-battery `--affected` degrade and arms every `--pr-gated` battery, and buys nothing the existing
lanes do not already give. The residual gap (the pipe guard is not a lane member) is real, small, and a separate
decision about a lane member, so it gets its own issue.

The PR is a decision record: no edit to `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` or
`scripts/lib/test-relevance-paths.sh`. It does not close #9217 and does not emit the series DONE promise.

## Research Insights

### Premise Validation (Phase 0.6)

Checked against `origin/main` at `ee8644bded`:

- #9217 is OPEN (21 comments; latest 2026-10-15, the Item F merge record, whose "Next slices" line names Item G
  as "a forbidden-to-edit file"). Held.
- `git grep -e '--ratchets'` finds the flag only in prose (archived plans and the guard header). `scripts/test-all.sh`
  has no such flag. Held: Item G is unbuilt.
- #8621 (converge the two affected selectors) is OPEN. #9552 (Item H) is MERGED. Held.
- Brief premise corrected: "forbidden-to-edit" is not enforced by any hook, CODEOWNERS entry or AGENTS rule.
  Checked: `.claude/settings.json` PreToolUse Write/Edit hooks (worktree-write-guard, guardrails, iac-plan-write-guard,
  kb-domain-allowlist-guard, no-memory-write, new-scheduled-cron-prefer-inngest, security_reminder_hook,
  skill-security-scan-write); `grep -rn 'test-all' .claude/hooks/*.sh` (hits only in suites and `pkill-self-match-guard.sh`
  comments); `.github/CODEOWNERS` (the `*` fallback only); `AGENTS.rules.md` (no rule names the file).
- The repo's only path-level edit guard is the opt-in freeze edit-lock (`guardrails:freeze-edit-lock`, `.claude/hooks/lib/freeze-lock.sh`,
  ADR-089): it denies edits outside ONE absolute prefix named in `.claude/.freeze-lock`, and fails open on an absent or malformed file.
  Measured here: the state file is absent and `freeze_active_prefix` echoes nothing, so no path is locked, and the lock never names a
  file. It cannot be what "forbidden-to-edit" refers to.
- Brief premise corrected: the guard header (`.claude/hooks/grep-q-pipe-guard.test.sh`, near the `THE PRE-PUSH AFFECTED
  LANE DOES NOT SELECT THIS GUARD` line) overstates the gap; a probe selected the guard for two of three producer
  paths (see Q3).
- ADR corpus: ADR-242 (local gate = affected set plus always-on ratchets; 2026-10-01 amendment adds the #9400 lane)
  governs the mechanism. Its alternatives table does not list a `--ratchets` flag. The archived 2026-10-05 sweep plan
  (Item 6a) already declined to fold it in. No ADR rejects it by name; no ADR is changed by this PR.

### Q1. What "forbidden-to-edit" means (cost label)

- `scripts/test-all.sh` is a member of `PR_GATE_MACHINERY_PATHS` (`scripts/lib/test-relevance-paths.sh`): an edit arms
  every `--pr-gated` self-test battery on that PR's CI run (ADR-262).
- `bash scripts/test-all.sh --print-selection --paths=scripts/test-all.sh` prints `AFFECTED_FALLBACK reason=runner-changed`,
  `MODE=full (degraded: runner-changed)` and "about 117 min of suite time". Any runner edit that is not a
  registration-only diff degrades the local default `--affected` and pre-push stage 2 (`scripts/hooks/pre-push`) to the
  full battery. A new flag arm is not registration-only. `--affected` is refused (rc 4) while a sibling holds the gate.
- Learning `2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`: a dedicated `elif` arm once produced a silent
  full battery (#9197).

### Q2. Is Item G still needed (property list)

- P1. "One local command runs the ratchets a diff can trip." Bought by `scripts/pre-push-ratchet-lane.sh` (#9400, pre-push
  stage 1: 11 fast members, 1 conditional, plus the branch-touched tier; the Item B slice S3 evidence on #9217 records `members=24 red=0` for a real push) and by
  `scripts/test-all.sh --affected` (diff-selected suites plus 114 `ALWAYS_ON_SUITES` entries in `scripts/lib/test-affected-paths.sh`).
- P2. "The repo-global shrink-only ratchets that file-selected runs miss are seen locally." The incident behind the need
  (learning `2026-10-05-a-guard-built-from-spellings-needed-an-allowlist-and-the-affected-run-saw-two-ratchets-my-targeted-tests-could-not.md`:
  trap-ownership rule c and `fixture-relative-assert`) names two ratchets that are both lane members today.
- The proposed membership, `grep -lis ratchet scripts/*.test.sh scripts/lib/*.test.sh .claude/hooks/*.test.sh`, measured
  today: 36 files; 27 explicitly registered in `test-all.sh`, 9 reached only through `SUITE_GLOBS`; 10 are in `ALWAYS_ON_SUITES` (matched by label);
  3 are lane member files (`alarm-issue-filing-guard`, `lint-diagnosis-claims`, `test-affected-kb-consumers`), and 2 of those 3 are also always-on, so the lane and the always-on floor already overlap. It is a
  text-mention heuristic: it includes `orphan-process-reaper`, `tmpfs-guard`, `zot-restart-loop-alarm` and
  `pre-push-ratchet-lane.test.sh`, none of which is a repo-global shrink-only ratchet. A selector built on it is the
  content-reference heuristic that `TEST_GROUP=affected` (#8591) uses and #8621 wants converged away from; a declared
  `RATCHET_SUITES` list would duplicate `ALWAYS_ON_SUITES`.

### Q3. The genuine residual gap (separate follow-up, option C)

- `.claude/hooks/grep-q-pipe-guard.test.sh` is not a lane member (CTO read the 12-row `LANE_MEMBERS` table). Measured
  runtime: `rc=0` in 18 s wall at load about 10 (CTO measured 19 s), so it fits a lane tier.
- `bash scripts/test-all.sh --print-selection --paths=<path>` today: selected (`AFFECTED_SELECTED ... 1 edge:declared`) for
  `scripts/cutover-inngest.sh` and `apps/web-platform/infra/web-private-nic-guard.sh`; not selected (`0`) for
  `scripts/expenses-verify-by-check.sh`. So the guard header's "does not select this guard for a producer file" is true
  for some producers and false for others; the follow-up issue states the measured sample, not the header's figure.
- Why not in this PR: Item G is the selector only; an unconditional 18 s member on every push to cover producer-file edits
  is a different trade than a conditional-tier member (like `test-affected-kb-consumers`) triggered on producer or owner-suite
  paths; the lane member table is pinned by `scripts/pre-push-ratchet-lane.test.sh`, so the change is small but not a one-liner.
- Answered (Kieran review): `scripts/lib/test-affected-paths.sh` IS a `runner-changed` trigger for `--affected` (`_aff_runner_in_diff`
  is set on either runner file; `--print-selection --paths=scripts/lib/test-affected-paths.sh` returns `AFFECTED_FALLBACK reason=runner-changed`).
  So widening the declared edge is worse than a lane member: every future edit of that array file forces a full battery. The follow-up
  proposes the lane member only.
- The guard's effective selection does not come only from the 12-entry `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` array: the
  `edge:declared` regex printed for `scripts/cutover-inngest.sh` is much larger (it includes `^apps/web-platform/`, `^tests/`, `^scripts/lib/`),
  so selection arrives through derived or merged edges. The follow-up states the measured per-path result and does not repeat the header's
  array-only description.

### Institutional learnings (learnings-researcher, read)

- `2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`, `2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-and-a-glob-registered-suite-degrades-the-affected-gate.md`:
  runner edits degrade the gate; against a flag.
- `2026-09-30-print-affected-set-prints-classes-not-selection-and-the-ask-was-half-shipped.md`: anything in the always-on
  floor already runs on every `--affected` pass; against a flag.
- `2026-10-15-a-new-nonpaging-marker-moved-a-pin-in-a-suite-the-affected-gate-never-selects.md`: pinned-count suites
  under `apps/web-platform/test/infra/` are CI-only; a gap, but a separate list and not Item G.
- `test-failures/2026-10-13-home-git-repo-makes-ratchet-nonrepo-control-walk-up.md`: any ratchet run through the lane
  inherits its `TMPDIR` pin; neutral.

### Property List and Cut List (Phase 0.6b)

| Mechanism in the ask | Property it buys | Already on main? (authority grepped) | Disposition |
|---|---|---|---|
| `--ratchets` flag in `scripts/test-all.sh` | P1 one local ratchet command | `scripts/pre-push-ratchet-lane.sh --print-members` (lane) and `scripts/test-all.sh --affected` (ALWAYS_ON); grepped `scripts/lib/test-affected-paths.sh` and the lane table | **Cut** |
| membership = `grep -lis ratchet` set | P2 repo-global ratchets seen locally | the two incident ratchets are lane members; set measured as a text-mention heuristic | **Cut** |
| (CTO) lane/edge coverage of the pipe guard | P3 a producer-file edit cannot reach CI before the guard runs locally | not covered for some producers (measured) | **Split to follow-up issue** |

### Value-Proposition Measurement (Phase 0.6c)

The only cost/benefit claim is the runner-edit cost: 117 minutes of suite time at manifest weights, from
`bash scripts/test-all.sh --print-selection --paths=scripts/test-all.sh` (the command that produced the number), against
a selector that would save the minutes between "run ~36 named suites" and a lane that already runs in 1 to 2 minutes.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "This PR is Item G only: the `--ratchets` selector in `scripts/test-all.sh`" [brief] | Overview; Phase 1 to 3 | mapped |
| 2 | "check what the repo's file-edit guard and the tracker's earlier comments say about editing it before touching it" [brief] | Research Insights Q1; Phase 1 | mapped |
| 3 | "take any technical ruling to the CTO agent rather than the operator" [brief] | CTO ruling (Overview); `decision-challenges.md` rows | mapped |
| 4 | "Done = Item G merged, or recorded on #9217 as not fixed with a reason and a `Ruled by CTO agent` line" [brief] | Phase 3 (#9217 comment) | mapped |
| 5 | "then `soleur:postmerge` for the PR" [brief] | Phase 5 | mapped |
| 6 | "Do not emit DONE for this PR" [brief] | Phase 5; AC | mapped |
| 7 | "Determine: what "forbidden-to-edit" means here (hook/guard/CODEOWNERS/AGENTS rule), what the selector would do and whether it is still needed given the existing pre-push ratchet lane, and whether the right outcome is a change or "recorded as not fixed"" [brief] | Research Insights Q1 to Q3 | mapped |
| 8 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/<branch>/decision-challenges.md" [brief] | Phase 1; Files to Create | mapped |
| 9 | "Open dissent issues #9971, #9950, #10074 and follow-up #10313 (awaits an operator decision) stay unchanged" [brief] | Non-Goals; AC | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| #9217 comment recording Item G as not fixed | "recorded on #9217 as not fixed with a reason and a `Ruled by CTO agent` line" | asked |
| `decision-challenges.md` | "Persist every decision as a row" | asked |
| Follow-up issue for the pipe-guard lane gap | — | inferred — justification: the CTO ruled C is real but out of scope, and `wg-when-deferring-a-capability-create-a` requires a tracking issue for a deferred capability; without it the gap is invisible |
| One-sentence amendment of the guard header's STILL OPEN list | — | inferred — justification: after this PR the header would still list Item G as open, and the Item D/E/H records already updated that same sentence; a stale claim in the guard file rots |
| Sampling extra producer paths with `--print-selection` | — | inferred — justification: the follow-up issue must state a measured gap, and the guard header's figure was falsified by the first probe |
| Plan review and tasks.md | — | inferred — justification: the plan skill's enforcement contract (plan-review, then tasks.md) applies to every plan |

### Split Assessment

- Subsystems touched: 2 (`knowledge-base`, `.claude`)
- Planned files: 5 | Estimated changed lines: 160
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled (2026-10-16): record Item G as not fixed; no edit to the runner; split the pipe-guard lane
gap into a separate follow-up (conditional lane member preferred). No other domain has an implication: this is test-gate
tooling with no user-facing, legal, financial or brand surface.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; a wrong record on #9217 would send a later
  session toward an expensive runner edit or hide the pipe-guard lane gap.
- **If this leaks, the user's data is exposed via:** no vector; the PR contains plan text, a ruling table, a GitHub
  comment and one comment line in a test file, with no credentials or personal data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches no path in the preflight sensitive-path regex (checked against
  `SENSITIVE_PATH_RE` in `plugins/soleur/skills/preflight/SKILL.md`), so no scope-out bullet is needed.

## Open Code-Review Overlap

Open `code-review` issues naming a planned file: none for `.claude/hooks/grep-q-pipe-guard.test.sh`, the plan, or the
specs files. #8659 and #7942 name `scripts/test-all.sh`, which this PR deliberately does not edit; acknowledged, no action.

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh`: only the header sentence that begins `# STILL OPEN (listed, not planned here)`. Say
  Item G is recorded as not fixed with its reason on #9217 and list what remains (Item I, the Wave A3 carriers, the #9639 and #9638
  triage). Comment lines only; the suite must still pass. The neighbouring `THE PRE-PUSH AFFECTED LANE DOES NOT SELECT THIS GUARD`
  sentence is left alone: its correction belongs to the follow-up issue, which owns the measurement.

## Files to Create

- `knowledge-base/project/plans/2026-10-16-fix-grep-q-series-item-g-ratchets-selector-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-g-ratchets-selector/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-g-ratchets-selector/decision-challenges.md`

GitHub artifacts (not files): one comment on #9217, one new follow-up issue (child of #9217).

## Implementation Phases

### Phase 1. Refresh the evidence (read-only)

1. `git fetch origin main`; confirm `git grep -e '--ratchets' origin/main -- scripts/test-all.sh` prints nothing and #9217 has no
   newer Item G comment (`gh issue view 9217 --json comments --jq '.comments[-1].createdAt'`).
2. Sample the pipe-guard selection over at least six producer paths drawn from the guard's own derived pairs (the `JOINED:` lines the
   guard prints, or its `PJ-DERIVE` recipe), one path per `--print-selection` call (about 13 s each unloaded):
   `bash scripts/test-all.sh --print-selection --paths=<path> 2>&1 | grep 'grep-q-pipe-guard\|AFFECTED_SUMMARY'`. Record
   selected/not-selected counts. Already measured: `scripts/cutover-inngest.sh` 1, `apps/web-platform/infra/web-private-nic-guard.sh` 1,
   `scripts/expenses-verify-by-check.sh` 0 (provisional: not shown to be a producer in the guard's sense), `.claude/hooks/grep-q-pipe-guard.test.sh` 1.
   Only confirmed numbers go into the follow-up issue.
3. `decision-challenges.md` is already written (see Files to Create); re-read it and add the plan-review rows.

### Phase 2. File the follow-up issue (option C)

`gh issue create` with labels `meta/machinery`, `type/chore`, `domain/engineering`, `priority/p3-low` and milestone
`Post-MVP / Later` (the filing gate `guardrails:require-filing-justification` needs a measured fix size or the machinery
ledger; the body supplies both).
Title: `grep -q pipe guard not selected by the pre-push lane for producer or owner-suite edits`. Body: the gap and the Phase 1 sample
(confirmed numbers only); the 18 s runtime; the proposal: a `conditional`-tier member in `scripts/pre-push-ratchet-lane.sh` triggered on
producer or owner-suite paths, plus its row in `scripts/pre-push-ratchet-lane.test.sh`; the rejected alternative (widening the declared
edge in `scripts/lib/test-affected-paths.sh`, which is a `runner-changed` trigger and would force a full battery on every edit); the note
that the guard's effective edges are derived or merged, not only the 12-entry declared array; and that the guard header's `DOES NOT SELECT
THIS GUARD` sentence should be corrected to the measured form as part of that follow-up. Child of #9217 (`Ref #9217`).

### Phase 3. Comment on #9217

Post with `gh issue comment 9217 --body-file <file>`; do not close the issue. Text (fill `<new>` with the Phase 2 issue number
and `<counts>` with the confirmed Phase 1 sample; the posted text must contain neither slot):

```text
## Item G (`--ratchets` selector in scripts/test-all.sh): recorded as not fixed

Ruled by CTO agent, 2026-10-16: not implemented; the existing lanes already answer the need.

- "Forbidden-to-edit" is a cost label, not a prohibition. No hook, CODEOWNERS entry or AGENTS rule bans the edit. Any
  non-registration-only edit of scripts/test-all.sh (a PR_GATE_MACHINERY_PATHS member) arms every --pr-gated battery on CI and
  degrades the author's own --affected and pre-push stage 2 to the full battery (AFFECTED_FALLBACK reason=runner-changed, about
  117 min). #9552 bounded only registration-only edits.
- Need: scripts/pre-push-ratchet-lane.sh (#9400, pre-push stage 1) runs the diff-reachable cheap ratchets, including the two
  from the 2026-10-05 incident learning (trap-ownership, fixture-relative-assert). scripts/test-all.sh --affected adds the
  114 always-on suites (as of ee8644bded).
- Membership: the `grep -lis ratchet` set is 36 files (27 explicitly registered, 9 via SUITE_GLOBS only; 10 in ALWAYS_ON_SUITES,
  3 lane member files). It is a text-mention heuristic that includes non-ratchets. A selector on it is the content-reference
  heuristic #8621 wants converged away from; a declared list would duplicate ALWAYS_ON_SUITES.
- Residual real gap, split out: .claude/hooks/grep-q-pipe-guard.test.sh (18 s measured) is not a lane member and the declared
  edge selects it for some producer paths and not others (sample: <counts>). Tracked in #<new>.

Remaining in the series: Item I, the Wave A3 carriers, the #9639/#9638 triage. This tracker stays open.
```

### Phase 4. Amend the guard header

Edit only the `STILL OPEN` sentence as described under Files to Edit. Then run the guard (`bash .claude/hooks/grep-q-pipe-guard.test.sh`,
expect rc 0) and the real-diff selection preview `bash scripts/test-all.sh --print-selection` (expect no `AFFECTED_FALLBACK` line).

### Phase 5. Ship and postmerge

Commit plan, tasks and decision-challenges with the header edit. PR body uses `Ref #9217` (never `Closes`), quotes the ruling
line, lists the follow-up issue. After merge, run `soleur:postmerge` for the PR. Do not emit the series DONE promise.

## Decisions

The three CTO rulings are the rows of `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-g-ratchets-selector/decision-challenges.md`
(Class `technical`, each starting `Ruled by CTO agent, 2026-10-16:`). The plan-review taste items are appended there too.

## Non-Goals

- No edit to `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lib/test-relevance-paths.sh` or
  `scripts/pre-push-ratchet-lane.sh`. The lane member (option C) is the follow-up's work.
- No change to #9971, #9950, #10074 or #10313.
- Items I, the Wave A3 carriers and the #9639/#9638 triage are not started here.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git diff --name-only origin/main...HEAD` lists no path in `PR_GATE_MACHINERY_PATHS` (`scripts/test-all.sh`,
  `scripts/lib/test-affected-paths.sh`, `.github/workflows/ci.yml`, `scripts/suite-shard-legs.tsv`, `scripts/suite-shard-legs-heavy.tsv`)
  and not `scripts/lib/test-relevance-paths.sh` or `scripts/pre-push-ratchet-lane.sh`. Pipeline-written files
  (the generated knowledge-base index if regenerated, `specs/<branch>/session-state.md`) are allowed alongside the three created files and the one header edit.
- [ ] `bash scripts/test-all.sh --print-selection` (the real diff, no `--paths`) prints no `AFFECTED_FALLBACK` line.
- [ ] `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0 after the header edit. The edit is non-empty and comment-only:
  `git diff -U0 origin/main...HEAD -- .claude/hooks/grep-q-pipe-guard.test.sh | grep -c '^[+-][^+-]'` prints a number of at least 1, and
  `git diff -U0 origin/main...HEAD -- .claude/hooks/grep-q-pipe-guard.test.sh | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*#'` prints nothing.
- [ ] `decision-challenges.md` has a `| Item | Class | Ruling |` table whose three CTO rows each start `Ruled by CTO agent, 2026-10-16:`.
- [ ] The follow-up issue exists, is open, carries only confirmed Phase 1 numbers (not the guard header's figure), and references #9217.
- [ ] #9217 carries the comment: `gh issue view 9217 --json state,comments --jq '[.comments[] | select(.body | test("Ruled by CTO agent, 2026-10-16"))] | length'`
  prints at least 1, that comment names the follow-up number and contains neither `<new>` nor `<counts>`, and the issue state is still `OPEN`.
- [ ] The PR body contains `Ref #9217` and no `Closes #9217`.
- [ ] Gates run with their own invocation: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`
  and `npx markdownlint-cli2` over the plan, `tasks.md` and `decision-challenges.md`.
- [ ] Every cited path resolves. Repo paths: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | sort -u | while read p; do [ -f "$p" ] || echo "BROKEN $p"; done`
  prints nothing. Learnings cited by bare filename: `grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md' <plan> | grep -v -e '-plan\.md' | sort -u | while read f; do [ -n "$(find knowledge-base/project/learnings -name "$f" -print -quit)" ] || echo "BROKEN $f"; done`
  prints nothing.

### Post-merge

- [ ] `soleur:postmerge` run for the PR (CI on main green; deploy arm skipped by design for a comment-only and docs change).
- [ ] The series DONE promise is not emitted.

## Observability

Skipped (Phase 2.9 and deepen Phase 4.7): the only non-knowledge-base path in Files to Edit is a comment-only edit to a test file under
`.claude/hooks/`, which is outside the Phase 2.9 trigger set (`apps/*/server`, `apps/*/src`, `apps/*/infra`, `plugins/*/scripts`), and the
PR adds no production code and no infrastructure surface.

## Architecture Decision (ADR/C4)

Skipped (Phase 2.10): no architectural decision is made or changed. The ruling reaffirms ADR-242's existing decision; a
competent engineer reading ADR-242 and the C4 files would not be misled after this PR.

## Guard Contract

Skipped (Phase 2.12): this PR delivers no guard, lint or gate. The follow-up issue (option C) would deliver one and carries its own contract.

## Sharp Edges

- Do not cite the guard header's "95 producer files and 93 owner suites" as measured; the CTO did not recount it and the
  first probe contradicted the header's broad claim. Cite the Phase 1 sample.
- A `--print-selection` call can slow down on a contended host; run the sample in the background if it does, and never poll with `sleep`.
- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; this plan fills it (threshold `none`).
