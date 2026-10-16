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

Spec lacks valid lane: defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this one-shot branch.

## Overview

Item G of the pipe-fed `grep -q` sweep (tracker #9217) proposes a `--ratchets` flag for `scripts/test-all.sh`
that would run "exactly the `grep -lis ratchet` set" as one local command. The series brief calls that runner a
"forbidden-to-edit file". This plan answers three questions with evidence and records a binding ruling:

1. What does "forbidden-to-edit" mean? A cost label, not a prohibition (Research Insights, Q1).
2. Is the selector still needed? No: the property it buys is already bought by `--affected` plus the pre-push
   ratchet lane, and the membership it proposes is a text-mention heuristic (Q2).
3. Change, or recorded as not fixed? **Recorded as not fixed** (CTO ruling below), with the one genuine residual
   gap (the guard is not selected by the local affected gate for 51 of 98 producer files and 33 of 97 owner suites) split into follow-up #10447.

**Ruled by CTO agent, 2026-10-16: record Item G as not fixed; do not implement the runner edit.** The runner
edit costs a full-battery `--affected` degrade and arms every `--pr-gated` battery, and buys nothing the existing
lanes do not already give.

> **Correction, 2026-10-16:** a first Phase 1 measurement counted the existence of the `AFFECTED_SELECTED` line instead of its selected bit and
> wrongly found no gap; a second CTO ruling withdrew option C on that basis. A corrected, bit-parsed and control-checked measurement found the
> gap real, and the CTO restored the first ruling: option C is filed as #10447 and the false parts of the guard header are corrected in this PR.

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
- Brief premise corrected: the guard header's `THE PRE-PUSH AFFECTED LANE DOES NOT SELECT THIS GUARD` sentence was false
  (see Q3 and `selection-measurement.md`).
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

### Q3. The residual gap claimed by the guard header (measured: real; follow-up #10447)

- Measured over the guard's whole pair population (98 producers, 97 owner suites) with `--print-selection --paths=<path>`, reading the selected
  bit (third tab-separated field of the `AFFECTED_SELECTED` line naming the guard) with a negative control: selected for 47 producers and 64 owner suites,
  NOT selected for 51 producers and 33 owner suites, 0 `AFFECTED_FALLBACK`. Per-path rows and a re-measure recipe:
  `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-g-ratchets-selector/selection-measurement.md`.
- The guard is not a stage-1 ratchet-lane member, by design; stage 2 (`--affected`) selects it only for the 47 and 64. CI's full battery runs it, so the
  gap is local feedback only. The proposal in #10447 is a conditional-tier lane member whose trigger is derived from the guard's own pairs.
- Do not widen the declared edge array to "fix" it: `scripts/lib/test-affected-paths.sh` is itself a `runner-changed` trigger (an edit to it
  prints `AFFECTED_FALLBACK reason=runner-changed`), so every future edit of that file would force a full battery.

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
| (CTO) lane/edge coverage of the pipe guard | P3 a producer-file edit cannot reach CI before the guard runs locally | NOT selected for 51 of 98 producers and 33 of 97 owner suites (measured in Phase 1) | **Split to follow-up #10447** |

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
| Amendment of the guard header (STILL OPEN list and the `DOES NOT SELECT THIS GUARD` sentence) | — | inferred — justification: after this PR the header would still list Item G as open, and its selection claim was falsified by the Phase 1 measurement; a stale claim in the guard file sends the next reader to re-open option C |
| Sampling extra producer paths with `--print-selection` | — | inferred — justification: the guard header's figure was falsified by the first probe, so the full population was measured instead of a sample |
| Plan review and tasks.md | — | inferred — justification: the plan skill's enforcement contract (plan-review, then tasks.md) applies to every plan |

### Split Assessment

- Subsystems touched: 2 (`knowledge-base`, `.claude`)
- Planned files: 6 | Estimated changed lines: about 530 (mostly knowledge-base prose)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled (2026-10-16): record Item G as not fixed; no edit to the runner; split the pipe-guard lane
gap into follow-up #10447. No other domain has an implication: this is test-gate
tooling with no user-facing, legal, financial or brand surface.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; a wrong record on #9217 would send a later
  session toward an expensive runner edit or leave a false selection claim in the guard header.
- **If this leaks, the user's data is exposed via:** no vector; the PR contains plan text, a ruling table, a GitHub
  comment and one comment line in a test file, with no credentials or personal data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches no path in the preflight sensitive-path regex (checked against
  `SENSITIVE_PATH_RE` in `plugins/soleur/skills/preflight/SKILL.md`), so no scope-out bullet is needed.

## Open Code-Review Overlap

Open `code-review` issues naming a planned file: none for `.claude/hooks/grep-q-pipe-guard.test.sh`, the plan, or the
specs files. #8659 and #7942 name `scripts/test-all.sh`, which this PR deliberately does not edit; acknowledged, no action.

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh`: the header sentences that begin `# STILL OPEN (listed, not planned here)` and
  `# THE PRE-PUSH AFFECTED GATE DOES NOT SELECT THIS GUARD` (it read `AFFECTED LANE` before this PR). The first says Item G is recorded as not fixed and lists what remains (Item I,
  the Wave A3 carriers, the #9639 and #9638 triage); the second keeps its meaning and gets the measured figures (selected for 47 of 98 producers
  and 64 of 97 owner suites, not for 51 and 33) and #10447. Comment lines only; the suite must still pass.

## Files to Create

- `knowledge-base/project/plans/2026-10-16-fix-grep-q-series-item-g-ratchets-selector-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-g-ratchets-selector/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-g-ratchets-selector/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-g-ratchets-selector/selection-measurement.md` (the Phase 1 evidence)

GitHub artifacts (not files): one comment on #9217 and the follow-up issue #10447.

## Implementation Phases

### Phase 1. Refresh the evidence (read-only) — done 2026-10-16

1. `git fetch origin main`; `git grep -e '--ratchets' origin/main -- scripts/test-all.sh` prints nothing; #9217's newest comment is the
   Item F record of 2026-10-15. Held.
2. Measured the guard's whole population, not a sample: pairs from the guard's own `PJ-DERIVE` block (98 producer files, 97 owner suites);
   the declared edge regex printed on the `AFFECTED_SELECTED` line matches 47 producers and 64 owner suites (spot check of 8: all bit 1); the other
   51 and 33 were each run through `bash scripts/test-all.sh --print-selection --paths=<path>`, reading the selected bit. Controls: a bogus path gives
   bit 0, `scripts/cutover-inngest.sh` gives bit 1. Result: all 84 are bit 0 (NOT selected), 0 `AFFECTED_FALLBACK`, all rc 0. Per-path rows:
   `selection-measurement.md`.
3. Three CTO rulings followed: the first split the gap into a follow-up, the second (made on a first measurement that counted line presence instead of
   the selected bit) withdrew it, and a third restored the first after the corrected measurement. All rows are in `decision-challenges.md`.

### Phase 2. File the follow-up issue

Filed 2026-10-16 as #10447 (labels `meta/machinery`, `type/chore`, `domain/engineering`, `priority/p3-low`; milestone `Post-MVP / Later`; `Ref #9217`).
It states the confirmed figures, lists the 84 unselected paths, proposes a conditional-tier member of `scripts/pre-push-ratchet-lane.sh` whose trigger is
derived from the guard's own pairs, and rejects widening the declared edge array.

### Phase 3. Comment on #9217

Post with `gh issue comment 9217 --body-file <file>`; do not close the issue. The posted text must contain no unfilled slot. Content:
the ruling line `Ruled by CTO agent, 2026-10-16`; "forbidden-to-edit" is a cost label, not a prohibition (the `PR_GATE_MACHINERY_PATHS`
arming and the `runner-changed` degrade, about 117 min); the need is already met by the pre-push ratchet lane and `--affected` plus the
114 always-on suites (as of `ee8644bded`); the `grep -lis ratchet` set is a 36-file text-mention heuristic; the measured pipe-guard selection gap
(51 of 98 producers and 33 of 97 owner suites not selected) with the evidence file and #10447 named; the false parts of the header sentence corrected in this PR; a
correction note for the first, wrong measurement; the remaining series items (Item I, the Wave A3 carriers, the #9639/#9638 triage); the tracker stays open.

### Phase 4. Amend the guard header

Edit the two header sentences as described under Files to Edit. Then run the guard (`bash .claude/hooks/grep-q-pipe-guard.test.sh`,
expect rc 0) and the real-diff selection preview `bash scripts/test-all.sh --print-selection` (expect no `AFFECTED_FALLBACK` line).

### Phase 5. Ship and postmerge

Commit plan, tasks and decision-challenges with the header edit. `soleur:ship` archives these knowledge-base artifacts inside the PR
(`wg-kb-artifacts-archived-in-pr`), so the header cites `selection-measurement.md` by name, not by a live path. PR body uses `Ref #9217` (never `Closes`), quotes the ruling
line, states the measured pipe-guard selection. After merge, run `soleur:postmerge` for the PR. Do not emit the series DONE promise.

## Decisions

Every CTO ruling is a row of `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-g-ratchets-selector/decision-challenges.md`
(Class `technical`, each starting `Ruled by CTO agent, 2026-10-16:`); the plan-review taste items are `taste` rows there too.

## Non-Goals

- No edit to `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lib/test-relevance-paths.sh` or
  `scripts/pre-push-ratchet-lane.sh`. Option C (a lane member) is #10447's work.
- No change to #9971, #9950, #10074 or #10313.
- Items I, the Wave A3 carriers and the #9639/#9638 triage are not started here.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git diff --name-only origin/main...HEAD` lists no path in `PR_GATE_MACHINERY_PATHS` (`scripts/test-all.sh`,
  `scripts/lib/test-affected-paths.sh`, `.github/workflows/ci.yml`, `scripts/suite-shard-legs.tsv`, `scripts/suite-shard-legs-heavy.tsv`)
  and not `scripts/lib/test-relevance-paths.sh` or `scripts/pre-push-ratchet-lane.sh`. Pipeline-written files
  (the generated knowledge-base index if regenerated, `specs/<branch>/session-state.md`) are allowed alongside the created files and the one header edit.
- [ ] `bash scripts/test-all.sh --print-selection` (the real diff, no `--paths`) prints no `AFFECTED_FALLBACK` line.
- [ ] `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0 after the header edit. The edit is non-empty and comment-only (it replaces the `STILL OPEN` and `DOES NOT SELECT THIS GUARD` sentences):
  `git diff -U0 origin/main...HEAD -- .claude/hooks/grep-q-pipe-guard.test.sh | grep -c '^[+-][^+-]'` prints a number of at least 1, and
  `git diff -U0 origin/main...HEAD -- .claude/hooks/grep-q-pipe-guard.test.sh | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*#'` prints nothing.
- [ ] `decision-challenges.md` has a `| Item | Class | Ruling |` table whose CTO rows each start `Ruled by CTO agent, 2026-10-16:`.
- [ ] Follow-up #10447 exists and is open, and `selection-measurement.md` states 47/98 producers and 64/97 owner suites selected, 51 and 33 not, with the two controls.
- [ ] #9217 carries the comment: `gh issue view 9217 --json state,comments --jq '[.comments[] | select(.body | test("Ruled by CTO agent, 2026-10-16"))] | length'`
  prints at least 1, that comment names `selection-measurement.md` and contains no unfilled slot, and the issue state is still `OPEN`.
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

Skipped (Phase 2.12): this PR delivers no guard, lint or gate. The follow-up #10447 (option C) would deliver one and carries its own contract.

## Sharp Edges

- Cite the pipe-guard selection figures only from `selection-measurement.md` (98 producers, 97 owner suites at `ee8644bded`); the
  header's earlier "95 and 93" were stale (the population is 98 and 97) and its "most owner suites" was wrong (33 of 97). Re-measure after any change to the edge list.
- Parse the selected bit (third tab-separated field) of the `AFFECTED_SELECTED` line; `--print-selection` prints that line for every suite, so counting its presence
  measures nothing. Run a bogus-path control (bit 0) and a known-producer control (bit 1) before reading any count.
- A `--print-selection` call can slow down on a contended host; run the sample in the background if it does, and never poll with `sleep`.
- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; this plan fills it (threshold `none`).
