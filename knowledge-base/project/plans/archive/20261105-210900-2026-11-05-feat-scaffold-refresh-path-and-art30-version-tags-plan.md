---
title: "feat: constraint-scaffold stage-a refresh path and Art. 30 version-tag strip (tracker #12146 items 2 and 3)"
date: 2026-11-05
slug: scaffold-refresh-path-and-art30-version-tags
branch: feat-one-shot-12146-scaffold-refresh-art30-tags
issue: 12146
type: feat
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

<!-- lane: the branch has no spec.md to carry a lane from, so the fail-closed default cross-domain applies (TR2). -->

## Enhancement Summary

**Deepened on:** 2026-11-05
**Gates run:** Phase 4.6 (User-Brand Impact present, threshold `aggregate pattern`), 4.7 (Observability: `bash` verb allowlisted, command not suite-shaped, `expected_output` a matchable literal, verified with `tokenizeExpected`), 4.8 (no PAT-shaped variable), 4.9 (no UI surface), 4.11 (Guard Contract lint green), 4.12 (one unfenced Scope Check, no `unmapped`/`BLOCKED`). 4.4, 4.5, 4.55, 4.10, 4.13 do not trigger (no scheduled job, no network symptom, no downtime-class change, no new store or connection, no new autonomous task).
**Live verification:** cited PRs and issues (#12136 merged, #12177 open draft, #8626 open and it does edit the register, #8381 open, #12102 closed), all six ledger hashes recomputed from git history, rule id `cq-write-failing-tests-before` active, label `semver:patch` exists, ADR-071/074/129 exist, every referenced repo path is tracked.
**Agents used:** security-sentinel, test-design-reviewer, architecture-strategist (plus the earlier plan-review panel and the CTO and CLO rulings).

### Key improvements

1. No downgrade: the ledger row order is the rank; an installed file newer than the plugin's template is refused (the ledger alone could not tell stale from newer).
2. The refusal report is template-side only and width-bounded: the earlier `diff -u` would have printed a user's edited workflow, including any secret pasted into it, into the agent transcript.
3. Path safety is stricter: the physical destination directory must equal `$TARGET/.github/workflows` (repo containment let a symlinked `.github` redirect the write); symlink and untracked arms exit before any diff; a pre-write recheck narrows the TOCTOU window and the residual is stated.
4. The Stage A to Stage B wire interface and the `contents: read` privilege are frozen in the ADR-071 amendment and asserted by test case 12, so "append a ledger row" cannot ship a change that silently disables an older Stage B.
5. The test design is hardened: ledger and template manipulated in a per-case sandbox copy, live-lock positive control, destinations that hold ledger-member bytes so a guard (not classification) is what refuses, a fake hash tool for the empty-digest arm, bash 3.2 and BSD portability, labelled sub-rows, an anti-vacuity floor.
6. SKILL.md and the ledger now say a refresh is a content upgrade (install command, model id, token wiring), not only a pin bump.

### New considerations

- 75 appears in four documentation sites besides the matrix; all are listed in Phase 3.
- A pre-existing `take_run_lock` race is filed as a tracked scope-out rather than left invisible.

## Overview

Tracker #12146 left three boxes open after PR #12136 moved every claude-code-action pin in this repository to
v1.0.263. This plan ships items 2 and 3 in one pull request (draft PR #12177). Item 1 (the operator-digest run) is
handled in the parent session and is not touched here.

- **Item 2, scaffold refresh path.** A repository that already ran the constraint-scaffold skill keeps the
  claude-code-action pin its first install wrote, because `constraint-scaffold.sh` refuses to overwrite an existing
  artifact (exit 66, no `--force`). Add a third mode, `--refresh-stage-a`, that re-emits exactly one file
  (`apps/web-platform/.github/workflows/fix-constraints-stage-a.yml`), and only when the existing bytes are an exact,
  ledger-listed historical emission of the template.
- **Item 3, Art. 30 register.** Remove the claude-code-action version tags (and two stale commit SHAs) from the PA-33
  entry in `knowledge-base/legal/article-30-register.md`, so the register states the control ("pinned by commit SHA")
  and points at the workflow files for the value.

PR body uses `Ref #12146`, never a closing keyword. The tracker is closed by hand after its probe passes.

## Research Reconciliation: Spec vs. Codebase

| Brief claim | Reality (verified 2026-11-05) | Plan response |
|---|---|---|
| Installed repos keep the v1.0.236 pin | Six historical template emissions exist: four on v1.0.101 (2026-07-01 to 2026-09-30), one on v1.0.236 (2026-10-05, which also added the 7-line `github_token` block), one on v1.0.263. A v1.0.101-era copy also lacks `github_token` and hard-fails on OIDC. | Whole-file replace, not a pin-line edit (CTO ruling R2/R3). Ledger covers all six eras. |
| "if the scaffold template carries a pin, decide whether the lockstep guard should cover it" | `fix-constraints-stage-a.template` is already in `EXPECTED_CARRIERS` of `claude-pin-lockstep.test.ts` and in its census. | No change to the lockstep test (CTO R4). The refresh derives the pin from the template at run time, so no new carrier appears. |
| Register states version tags at "~3 places" (700, 712, 719) | True, but lines 700 and 719 also carry a full 40-hex SHA (`5aa6f47e...`, v1.0.161) that no workflow carries any more, and line 719 says "all three action-using members" (stale count). | Strip tags and both SHAs, make the count generic (CLO ruling). |
| Scaffold emits into the repo | It emits under `apps/web-platform/.github/workflows/`. In this repository only `constraint-gates.yml` lives there; the stage-a/b dogfood copies live at repo-root `.github/workflows/` and are parity-tested by `parity.test.sh`. | This repo has no installed stage-a copy for the refresh to act on. The test uses hermetic fixture repos; there is no live in-repo consumer. |
| "refuse-to-overwrite ... has no re-emit path" | ADR-071 Consequences (b) makes refuse-if-exists an invariant for gate executables, split from append-once prose. | A third class is added by an ADR-071 amendment in this PR (Phase 3). |

## Research Insights

### Premise Validation (Phase 0.6)

- #12146 is OPEN. #12102 (the probe's trigger) is CLOSED, so the probe currently reports ACTION REQUIRED until the
  boxes are ticked. PR #12177 is this branch's draft PR (state OPEN, draft, base main).
- Collision pre-check hit: PR #12177 (ours) and three `test-all.sh` processes owned by another worktree
  (`feat-one-shot-12013-affected-gate-lock-chain`). Neither is a duplicate of this work. Open PR #8626 edits the Art. 30
  register (ledger anchors); it does not touch PA-33 lines 700/712/719, but a textual rebase conflict on the register is
  possible at ship time.
- Cited artifacts exist on `origin/main`: the script, the stage-a template, the lockstep test, the register, the probe
  script `scripts/followthroughs/claude-code-action-residual-pins-12136.sh`.
- ADR corpus: ADR-071 (refuse-if-exists for executables; no opt-out of the bite-proof) and ADR-074 (two-stage split).
  Neither rejected a refresh mode. Their invariants constrain the design, which is why the ADR-071 amendment is a
  deliverable here.

### Property List and Cut List (Phase 0.6b)

Properties the work must buy:

- P1. A repository that installed the scaffold can obtain the current stage-a workflow without hand-editing a workflow file.
- P2. A user-edited stage-a workflow is never silently overwritten.
- P3. A stale pin is never silently skipped: current means a quiet no-op, anything else is a loud, coded refusal with a template-side report on stdout.
- P4. The refresh adds no new claude-code-action pin carrier that can drift out of the lockstep guard's view.
- P5. The Art. 30 register states the pin control without any perishable value.

Cut list (mechanism, property it would buy, what already covers it or why it is cut):

- `--force` flag: buys P1 but violates P2. Cut.
- Sibling script: buys P1; duplicates about 150 lines of guards that already live in `constraint-scaffold.sh`. Cut (CTO R1).
- Pin-line-only edit: buys P1 for v1.0.236 copies only; leaves v1.0.101 copies broken (no `github_token`). Cut (CTO R3).
- Pristine-modulo-pin heuristic: refuses the v1.0.236 copy unless normalisation widens, and widening is how an edited file gets admitted. Cut (CTO R3).
- Bite-proof inside the refresh: it exercises config, runner and baseline; a stage-a swap changes none of them. Cut (CTO R5).
- Refreshing `constraint-gates.yml`, `fix-constraints-stage-b.yml`, config, runner: none carries a pin; they decide what CI enforces. Cut (CTO R2).
- Extending the lockstep guard or `EXPECTED_CARRIERS`: the template is already a carrier. Cut (CTO R4).
- Founder-visible step: gate maintenance is agent-owned (SKILL.md recovery model). Cut (CTO R7).
- A pointer from `model-launch-review` to the new flag: that skill runs in this repository, which has no installed copy; buys nothing in P1-P5. Cut.
- Documented-manual-step-only: the brief requires a shipped refresh path. Cut.

### Rulings

Ruled by CTO agent, 2026-11-05 (seven rulings, summarised; full text in `decision-challenges.md`):

- R1 shape: new flag `--refresh-stage-a` on the existing script, third mode. New exit code 75 ("existing file is not a known pristine emission"). Reuse 0, 2, 64, 65, 67, 69, 70.
- R2 scope: exactly one file, `apps/web-platform/.github/workflows/fix-constraints-stage-a.yml`, held in a one-row (template, destination, ledger) table. Recorded by an ADR-071 amendment plus a pointer line in ADR-074; no new ADR.
- R3 clobber guard: sha256 ledger of every historical substituted emission; overwrite only on an exact byte match; any other bytes are refused (75) with a bounded, template-side-only report (deepen-plan security review: the user's file is never printed) on stdout. Already-current is a no-op exit 0.
- R4 lockstep: pin derived from the template at run time; `claude-pin-lockstep.test.ts` stays byte-identical.
- R5 no bite-proof in the refresh; verification is hash classification before the write and `cmp` after.
- R6 new test file `refresh-stage-a.test.sh` plus two committed fixtures and sorted registry rows.
- R7 documentation is agent-facing only (SKILL.md Usage, header comment, Self-tests row).

Ruled by CLO agent, 2026-11-05: strip every version tag and both stale 40-hex SHAs from PA-33 (d)(1), (d)(8), (g)(4);
say "pinned by commit SHA" with the workflow files as source of truth; add a dated in-cell amendment note at (d)(1) and
(g)(4); drop the "it was v1.0.236" history sentence. This is a clarification only. It triggers no PA-8 re-verification,
needs no external counsel, and has no mirror to update. Exact text is in Phase 5.

### Institutional learnings applied

- `2026-09-19-cleanup-on-failure-is-a-property-of-the-window-not-the-arms.md`: arm the trap before the first write; this mode has its own trap and must not reuse `remove_emitted_artifacts` (it would delete the user's workflow). The exit-site table in Phase 2 is by position relative to the first write.
- `best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`: the ledger must be anchored outside the commit. Anchor: every ledger row must be reproducible from the template's git history (Guard Contract).
- `2026-10-21-mktemp-cleanup-armed-late-leaks-every-early-exit.md`: arm the temp-file cleanup right after `mktemp`.
- `2026-11-05-a-branch-dispatch-of-the-workflow-you-edited-is-skip-masked-...md`: the refreshed workflow cannot be dispatch-verified from a branch; verification here is byte equality with the template, which parity and emit tests already pin.
- `2026-09-03-four-ways-i-destroyed-evidence-in-the-pr-that-exists-to-preserve-it.md` and `2026-09-27-a-status-flip-sweep-...legal-registers...md`: correct the register in-cell with a dated marker, never silently rewrite; grep the legal tree after the edit.
- `test-failures/2026-10-30-audit-accept-rows-...md`, `2026-11-03-one-malformed-accept-row-...md`, `best-practices/2026-10-18-ratchet-guards-must-pin-...md`, `2026-10-04-a-new-suite-is-invisible-to-repo-ratchets-until-tracked...md`: a new suite needs registry rows; stage the new test (`git add`) before running repo-global ratchets; use the incumbent-preserving incremental regen, never a full re-price; one malformed accept row drops every exemption.
- Bash 3.2 portability (`2026-10-11-ci-job-images-force-color-...md`): no `mapfile`, no `\x1b` in sed, no `realpath -m`; hash with `sha256sum` else `shasum -a 256`.

## Open Code-Review Overlap

None. Queried the open `code-review` issues for every path in Files to Edit and Files to Create; no body names any of them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Ship items 2 and 3 of the open follow-through tracker #12146 as ONE PR (draft PR already exists: #12177)" [brief] | Phases 1-5 on this branch, single PR | mapped |
| 2 | "Use `Ref #12146` in the PR body, never `Closes #12146`" [brief] | AC11, Phase 6 | mapped |
| 3 | "Design and ship a refresh path (flag or sibling command) with a test." [brief] | Phases 1-4, AC1-AC7 | mapped |
| 4 | "route it to soleur:engineering:cto, never to the operator" [brief] | CTO rulings R1-R7, recorded in decision-challenges.md | mapped |
| 5 | "Keep apps/web-platform/test/claude-pin-lockstep.test.ts intact (do not weaken it)" [brief] | R4; AC8 asserts the file is byte-identical to main | mapped |
| 6 | "Strip the version tags so the register says only \"pinned by commit SHA\", with the workflow files as the source of truth" [brief] | Phase 5, AC9-AC10 | mapped |
| 7 | "Route the exact wording to the soleur:legal:clo agent, not the operator." [brief] | CLO ruling, Phase 5 | mapped |
| 8 | "rely on CI's required `test` check (...); read infra-validation and sandbox-canary-capture-gate by hand" [brief] | Phase 6 | mapped |
| 9 | "Never push to a PR in the merge queue", "Never --admin merge, never touch the ruleset" [brief] | Phase 6 constraints | mapped |
| 10 | "Registry files (...): new rows in sorted position." [brief] | Phase 4, AC6 | mapped |
| 11 | "Out of scope: the affected-index-ratchet failures, Better Stack incident soleur-egress-gw-probe-silent-prd, digest-scrub.sh token-pattern gap." [brief] | Non-Goals | mapped |
| 12 | "After merge, tick the item-2 and item-3 boxes in #12146 and verify with: GH_TOKEN=\"$(gh auth token)\" bash scripts/followthroughs/claude-code-action-residual-pins-12136.sh (item 1's box is handled separately ...; do not tick it)" [brief] | Phase 7 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `--refresh-stage-a` mode, ledger, exit 75 | "Design and ship a refresh path (flag or sibling command) with a test" | asked |
| Fixtures and `refresh-stage-a.test.sh` | "with a test" | asked |
| SKILL.md Usage block, header comment, Self-tests row | "The design choice (flag vs sibling command, what it may overwrite, how it avoids clobbering user edits)" | asked (documenting the path is part of shipping it) |
| ADR-071 amendment and ADR-074 pointer | — | inferred — justification: plan Phase 2.10 makes the ADR a deliverable of the plan that changes an architectural invariant (ADR-071 Consequences (b)); the CTO ruled it (R2). |
| Registry rows (`suite-durations.tsv`, `suite-shard-legs.tsv`) | "Registry files (...): new rows in sorted position." | asked |
| Register edit with in-cell amendment notes | "Strip the version tags so the register says only \"pinned by commit SHA\"" | asked (the notes are the CLO's ruled wording) |
| Stripping the two stale SHAs and the count | "so it cannot go stale again" | asked (CLO ruled a SHA is as perishable as a tag) |
| Tick boxes 2 and 3 and run the probe | "After merge, tick the item-2 and item-3 boxes" | asked |

### Split Assessment

- Subsystems touched: 3 (plugins/soleur/skills, knowledge-base, scripts)
- Planned files: 12 | Estimated changed lines: about 480 (test about 200, script about 140, ADR/SKILL about 70, fixture about 110 by copy)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

**If this lands broken, the user experiences:** a founder's repository whose auto-recovery workflow
(`fix-constraints-stage-a.yml`, a job that holds the founder's `ANTHROPIC_API_KEY`) is either left on a stale
claude-code-action pin that bundles a vulnerable Bun, or is silently rewritten over a hand edit the founder made.
The first is the status quo; the second is the failure the clobber guard exists to prevent.

**If this leaks, the user's workflow is exposed via:** a refresh that replaced a user-edited stage-a file with the
template would change what a secret-bearing, untrusted-`pull_request` job runs without the founder reading a diff.
The ledger-only overwrite rule and the refusal (exit 75, file byte-unchanged, template-side report only) bound that exposure to
bytes the template already shipped. No credential value is read, written or logged by the mode.

**Brand-survival threshold:** aggregate pattern

Reasoning for the threshold: the mode writes only bytes the first install would have written, behind a clean-tree guard
and an exact-match ledger, and its failure direction is "refuse" (the pre-existing state). It touches no path matched by
the preflight sensitive-path regex.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Spawned for the flag-versus-sibling fork. Ruled R1-R7 above: flag on the existing script, one-file scope,
sha256 ledger clobber guard, no new pin carrier, no bite-proof in the refresh, new test file with two fixtures, agent-only
docs. Flagged the one unverified claim (each historical emission hashes cleanly after substitution); this plan verified it
(see Phase 1, six hashes computed from git history).

### Legal (CLO)

**Status:** reviewed
**Assessment:** Spawned for the register wording. Ruled that the edit is a de-perishing clarification of PA-33 with no change to
recipients, TOMs or lawful basis; no PA-8 re-verification (the trigger manifest only fires on infra paths), no external
counsel, no mirror copy. Leave the 2026-07 counsel review and the LIA untouched as dated records.

No Product/UX gate: no file under a UI surface (the mechanical UI-surface override did not fire). Finance, Marketing,
Operations, Sales and Support: no implications.

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md` with a dated 2026-11-05 amendment
(no new ordinal). Decision: add a third artifact class to Consequences (b), "template-keyed re-emittable workflow",
overwritten only when its bytes appear in the emission ledger. State why this one is allowed (secret-bearing third-party
action whose bundled runtime ships security fixes), what stays refuse-only (`constraint-gates.yml`, stage-b, config,
runner, baseline), and that the refresh skips the bite-proof because the swap changes none of what the bite exercises.
Add to Alternatives Considered: `--force`, sibling script, pin-line-only edit, pristine-modulo-pin heuristic. Add a
one-line pointer in ADR-074 (stage A is the one re-emittable workflow). This is a task in Phase 3, not a follow-up issue.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`). Checked against the feature:

- external human actor: `founder` (runs the scaffold; already modeled) and the untrusted contributor actor (already modeled; its description already cites fix-constraints Stage A). No new actor.
- external system: `anthropic` (already modeled; the refresh adds no Anthropic call) and GitHub Actions (no new edge).
- container/data store: none touched.
- actor-to-surface access relationship: unchanged (`constraintscaffold -> webapp "Generates L1 import-boundary gate (CI)"` at model.c4 line 1057 still holds).

Conclusion: no C4 impact, and no `.c4` file is edited. The `constraintscaffold` component description (model.c4
line 280, "Generates the L1 dep-cruiser import-boundary gate plus the two-stage ... auto-recovery workflows") remains
true when one of those workflows can be re-emitted, and it already omits the existing `--refresh-baseline` mode, so modes
are not description-worthy in this model. No count embedded in an edge description moves: `plugins/soleur/test/c4-count-parity.test.sh`
ran green on this branch (13 passed, 0 failed). (Plan review cut an earlier one-line description tweak as unneeded.)

### Sequencing

The decision is true on merge; nothing is soak-gated.

## Implementation Phases

Test-first (`cq-write-failing-tests-before`): Phase 1 writes the failing suite, Phase 2 makes it pass.

### Phase 1, RED: ledger, fixtures, failing suite

1.1 Create `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.emitted.sha256`: one row per
historical emission, `<sha256>  <pin-tag>  <date>`, comment (`#`) and blank lines allowed. The six hashes were computed
for this plan (`git show <commit>:<template> | sed 's|__TARGET_DIR__|apps/web-platform|g' | sha256sum`):

| Template commit | Date | Pin tag | sha256 of the substituted emission |
|---|---|---|---|
| d86256032e | 2026-07-01 | v1.0.101 | b8187a33c668e44a00cff048117d2ed1b6d568b90b5c10b28f21bb5e46d99386 |
| 48b13c1f2e | 2026-07-01 | v1.0.101 | 889e8a08481de2af5909b59043f8df0a59207374aa30f35deca3676a0fe536bc |
| f5f51c84b0 | 2026-08-17 | v1.0.101 | e68d1cc2ce56c3e60c6ed939172ef19d83bcb85a606ae8442934898e873941e3 |
| 6d27cd17da | 2026-09-30 | v1.0.101 | 5130360de005d5534dfab73ad5fb1af8dd8a196c72e97eb1eb08d17ceb7facbe |
| 21c9168e59 | 2026-10-05 | v1.0.236 | 45fdc5c5e0060d8ced95d64688061dc567beba1329a9323b6b6a7817ecdd2895 |
| 0195929c1d | 2026-11-05 | v1.0.263 | 58377282013228a6bd5bbf1a9d647ee2710622711efa58710999b3c46585a1da |

Ledger file shape: a `#` header, then one data row per line, `<sha256>  <pin-tag>  <date>  <what a refresh changes>`;
only the first whitespace-separated field is read (`awk '{print $1}'`, so blanks, tabs and trailing notes need no special
handling). Row ORDER is the sequence: rows are appended chronologically, newest last, never reordered or removed, and the
line index of a row is its rank (the downgrade guard in Phase 2 step 9 reads it). The header says so, carries the
regeneration command so a reviewer can re-derive any row from git history, and carries the compatibility note: "A row
certifies only that Soleur emitted these bytes once. Append a row only if the new template keeps the frozen A-to-B interface
and the `contents: read` permission set (ADR-071 amendment 2026-11-05)." The per-row change notes come from the template
commits (so a reviewer sees that a refresh is a content upgrade, not only a pin bump): d86256032e initial (`bun install
--frozen-lockfile`, model sonnet-4-6); 48b13c1f2e model to sonnet-5; f5f51c84b0 install step to `npm ci --ignore-scripts`;
6d27cd17da model to claude-sonnet-5-5; 21c9168e59 adds the `github_token` input and moves to action v1.0.236; 0195929c1d moves
to action v1.0.263. The ledger contains no `claude-code-action` string and no 40-hex action SHA (a sha256 is 64 hex and does
not match a boundary-anchored 40-hex scan). There is no commit column (a PR cannot know its own squash-commit id). The rows are
GENERATED by that command at implementation time, never typed. Refresh converges the file on the current template, including the
install command: a 2026-07-01-era copy that installed with bun moves to `npm ci`; this adds no precondition because the sibling
`constraint-gates.yml` template already runs `npm ci --ignore-scripts` (constraint-gates-workflow.template line 65), so a repo
whose gate works already has the lockfile.

1.2 Create ONE committed fixture, `plugins/soleur/skills/constraint-scaffold/test/fixtures/stage-a.v1.0.236.emitted`, a
byte copy of the substituted emission at 21c9168e59 (the era the tracker names; ledger row 5 of 6, so a scan that stops at
the first row cannot pass). The non-`.yml` suffix plus the `test/fixtures/` path hide it from the lockstep census by two
independent reasons (the census scans only `.yml/.yaml/.template` and skips `test` and `fixtures` segments). Plan review cut the
second (v1.0.101) fixture: classification is a hash lookup, so a second byte shape exercises the same code path.

1.3 Create `plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh`. Structure (deepen-plan test-design
review): hermetic `git init` fixtures via `CONSTRAINT_SCAFFOLD_REPO_ROOT` and the repo's `git-fixture-env.sh` chokepoint;
build ONE base fixture repo and `cp -R` it per case; for every case that varies the ledger or the template, copy `scripts/` and
`references/` into a per-case sandbox and run the COPY (the script derives `REF_DIR` from its own location, so
`CONSTRAINT_SCAFFOLD_REPO_ROOT` alone cannot move the ledger); accumulate-then-exit with the independent `cases` counter, the
instrument self-test and a `MIN_ROWS` anti-vacuity floor as in `parity.test.sh`; sub-rows are labelled (`3a`, `3b`, ...) so a
failure names the behavior; a STATE assertion (bytes unchanged, no lock) is recorded only when the rc assertion for that
sub-row already matched, so the RED run does not report false greens. Portability (bash 3.2, BSD): hash helper is
`sha256sum` else `shasum -a 256`; mode read with `ls -l | cut -c1-10`, never `stat`; strip a final newline with
`printf '%s' "$(<f)"`; boundary-anchored greps `(^|[^0-9a-f])[0-9a-f]{40}([^0-9a-f]|$)` (no `\b`); "file not rewritten" is
checked by backdating with `touch -t 200001010000` and asserting `! [ dest -nt ref ]` plus an unchanged inode. Twelve cases:

1. Refresh the v1.0.236 fixture (clean, committed, under `umask 077`): 1a rc 0; 1b bytes equal the fresh emission; 1c mode is `-rw-r--r--`; 1d no leftover temp file or lock directory.
2. Already current, with the ledger REMOVED in the sandbox (already-current is the one input that never consults the ledger): 2a rc 0 and "already current"; 2b not rewritten (backdated mtime, inode).
3. Edited copy (the fixture plus one appended line carrying a fake `sk-ant-` token): 3a rc 75; 3b bytes unchanged; 3c stdout lists template-side lines and hunk headers but NOT the existing-side line and not the planted token (the refusal output never prints the user's file content); 3d no leftover. Mutation pair: the same fixture unedited is case 1.
4. Final newline stripped from the fixture: rc 75, bytes unchanged.
5. Guards before the write, each with a destination that holds ledger-member bytes and a dirtied DIFFERENT tracked file: 5a dirty tree gives 67, bytes unchanged; 5b live lock (the lock directory pre-created with the test shell's own pid, which `kill -0` sees as live) on a clean tree gives 69 (positive control that the lock is reached); 5c dirty tree plus the live lock gives 67 (tree check precedes the lock); 5d symlinked destination on a dirty tree gives 75 (symlink check precedes the tree check); 5e destination untracked but byte-valid on a clean tree gives 67 (the refresh must be reviewable with `git diff`).
6. Existence precedes everything: 6a stage-a absent on a dirty tree with a live lock held gives 70; 6b config absent gives 70; 6c dangling-symlink destination gives 70; 6d in 6a the pre-created lock's pid file is still the test shell's pid (the mode took no lock).
7. Ledger anchor to the template: 7a the CURRENT template's substituted hash is in the real ledger (the RED forcer for every template change; its failure message prints the regeneration command and the ledger path); 7b downgrade: in the sandbox, fake the template as an OLDER ledger row's bytes while the destination holds the NEWEST row's bytes: rc 75, "installed file is newer than this plugin's template", bytes unchanged, no diff printed.
8. Ledger unusable (sandbox: removed, zero data rows, comment-only): the stale fixture is refused with rc 75 and bytes unchanged.
9. Symlink and hash-tool arms: 9a symlinked destination file whose target holds ledger-member bytes outside the repo gives 75, target unchanged, no diff printed; 9b symlinked parent (`.github` pointing at another directory inside the repo) gives 75 and the pointed-at file is unchanged (the physical destination directory must EQUAL `$TARGET/.github/workflows`, containment under the repo root is not enough); 9c `sha256sum` and `shasum` shadowed on `PATH` by a strict fake that emits an empty digest (any other argv exits 64) gives 69 with bytes unchanged.
10. After a refresh, 10a rc 0 and the destination changed; 10b the other emitted files (stage-b, constraint-gates.yml, config, runner, baseline), each holding distinct sentinel contents, are byte-unchanged.
11. No pin literal: 11a positive control (a known 40-hex string and a `claude-code-action@` string fed through the same helper are found); 11b `constraint-scaffold.sh` has neither; 11c the ledger has neither; both files are checked to exist first (`grep` rc 2 is not a pass).
12. Frozen Stage A to Stage B interface and privilege (architecture review): the current Stage A template keeps `name: fix-constraints-stage-a`, both artifact-name prefixes `fix-constraints-patch-` and `fix-constraints-giveup-`, an `on:` block whose only trigger is `pull_request` (no `pull_request_target`, `workflow_run`, `issue_comment`), and `permissions` of exactly `contents: read` with no `id-token` and no write scope. The constants are frozen from the oldest ledger era; the case does not compare against the current Stage B template.

Run it; it fails (flag unknown, exit 64). That is the RED.

### Phase 2, GREEN: the mode in `constraint-scaffold.sh`

Edit `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh`:

- Header: add `--refresh-stage-a` to Modes; add exit 75 to the matrix; extend 70 to "no .dependency-cruiser.cjs, or no fix-constraints-stage-a.yml to refresh"; update the line-131 `die` text to "(expected none, --refresh-baseline or --refresh-stage-a)".
- Arg parse: third `case` arm, `MODE="stage-a"`.
- New functions: `sha256_of <file>` (`sha256sum`, else `shasum -a 256`, else die 69), `fresh_stage_a <dest>` (`sed "s|__TARGET_DIR__|$TARGET_REL|g" "$REF_DIR/fix-constraints-stage-a.template"`), `ledger_has <sha>` (scans every non-comment row; absent file or no data rows means "no match"), `refresh_stage_a`.
- Three named variables (template, destination, ledger) drive the mode; it handles exactly one file.
- Mode dispatch sits after `detect_nextjs` (65) and before the `MODE == refresh` block; it never reaches `resolve_base_ref`, the three-dirs check, the TMPDIR check or any depcruise call.

Ordering and exit-site table (by position relative to the first write, the `mv`):

| Exit | Position | State left behind |
|---|---|---|
| 2, 64, 65 | before any read of the target | nothing written |
| 70 (stage-a or config missing, dangling symlink) | before the write, before the symlink check, the tree check and the lock | nothing written, no lock taken |
| 75 (symlinked destination, or physical destination directory is not exactly `$TARGET/.github/workflows`) | before the write | existing file byte-unchanged; goes through `die`, never prints a diff |
| 67 (destination untracked, or dirty tree) | before the write | nothing written |
| 69 (lock held, no hash tool or malformed hash, `mktemp` failure, fresh-emission verification failure) | before the write | nothing written; temp file removed by `_wt_cleanup` |
| 0 (already current) | before the write | no write |
| 75 (not a known emission; ledger unusable; installed file NEWER than this plugin's template; destination changed during the run) | before the write | existing file byte-unchanged |
| 69 (`mv` itself fails) | at the write | original intact (rename is atomic in the same directory); temp file removed |
| 0 (refreshed) | after the write | success; no fallible step follows the `mv` |

Steps in `refresh_stage_a`, in this order (plan review fixed the order: the 70 check must precede every check that can
fail for another reason or write a lock, so the Observability probe deterministically reaches 70 on a dirty tree and
stays read-only):

1. Arg parse (64), then `detect_nextjs` (65). Initialise `STAGE_A_TMP=""` at top level and read it everywhere as `${STAGE_A_TMP:-}`, so an early `die` under `set -euo pipefail` cannot trip an unbound variable inside the EXIT trap and replace the intended exit code with 1.
2. Existence: `[[ -f "$CFG" ]]` then `[[ -f "$FIXWORKFLOW_A" ]]`, else 70 (a dangling symlink is not a file, so it is also 70). Before any tree check and before the lock.
3. Path safety, through `die` (never the diff path): `[[ -L "$FIXWORKFLOW_A" ]]` refuses (75); compute the physical destination directory ONCE (`physdir`) and require it to EQUAL the physical `$TARGET/.github/workflows` (a symlinked parent such as `.github -> ../../../.github` passes a repo-containment check and would redirect the write to the repo-root dogfood workflow); use that one physical string for `mktemp`, `chmod`, `mv` and `cmp`. `physpath` alone cannot see a symlinked file, hence both checks.
4. `git -C "$REPO_ROOT" ls-files --error-unmatch -- "$FIXWORKFLOW_A"` (untracked destination refuses with 67: "commit the workflow first so the refresh is reviewable with git diff"), then `require_clean_tree` (67). The hash gate in step 9, not the tree guard, is the clobber control; the tree guard makes the result reviewable and revertable.
5. Arm the traps, THEN `take_run_lock` (69), as `--refresh-baseline` does. The mode REUSES the single trap owner `_wt_cleanup` (ADR-129): add the `STAGE_A_TMP` removal to it, and branch its "interrupted" message on `MODE` so a stage-a interrupt does not print the `--refresh-baseline` text. It already calls `remove_emitted_artifacts` only when `MODE=default`. Do NOT add HUP or PIPE to the shared trap lines (`bite-proof.test.sh` pins them by grep, and a stray top-level `trap - EXIT INT TERM` line would shift its disarm pin); instead every pipeline that feeds `head` is wrapped `{ ... || true; }` so SIGPIPE cannot abort the script. Every new `trap` line stays indented inside a function or `if` block.
6. `mktemp "$DEST_DIR/.fix-constraints-stage-a.XXXXXX"` (explicit template so BSD `mktemp` on bash 3.2 works), assign `STAGE_A_TMP` immediately.
7. Write the fresh emission to the temp file; compute `want` (hash of the temp file) and `have` (hash of the destination). Require both to match `^[0-9a-f]{64}$`, else 69: an empty `have` must never reach classification (fail-open: it would match every row). Verify the temp file against a second `sed` pass (`cmp -s`) before the write.
8. `have == want`: print `already current`, exit 0 (the one input that never consults the ledger).
9. Ledger classification (exact first-field equality, e.g. `awk -v h="$X" '/^[[:space:]]*#/ || !NF {next} {n++} $1 == h {print n; exit}'` printing the row's 1-based rank among data rows and nothing on a miss, so the caller tests for non-empty OUTPUT, not the exit code, which is 0 either way; a missing or empty ledger therefore matches nothing): `want` must resolve to a ledger row, else 75 ("this plugin's ledger lacks its own template; update the plugin"); `have` not in the ledger means print `FAILED (75): fix-constraints-stage-a.yml differs from every known emission (edited, or a version this ledger does not know); left unchanged`, then a template-side-only report, then exit 75; `rank(have) > rank(want)` means 75 with "installed file is newer than this plugin's template; update the plugin, do not downgrade" and NO diff. Do NOT use `die` for the not-a-known-emission arm (it exits before the report); hand-roll `say`, the report, `log`, `exit 75`. The report never prints the user's file: `{ diff -- "$dest" "$STAGE_A_TMP" | grep -v '^< ' | cut -c1-200 | head -60 || true; }` keeps the hunk headers and only the template-side lines (the ones diff prefixes with a right angle bracket), bounded in width and count, so a secret pasted into an edited workflow, a minified line or control characters in repo-controlled content never reach the agent transcript. The agent reads its own file when it merges by hand.
10. Pre-write recheck: `[[ -f "$dest" && ! -d "$dest" && ! -L "$dest" ]]` and re-hash the destination, which must equal `have`, else 75 ("changed during the run"). Then `chmod 0644 "$STAGE_A_TMP"` (mktemp creates 0600; a silent mode change on a founder's file is a defect), `mv` over the destination, then print `refreshed fix-constraints-stage-a.yml ... review with git diff`.

Stated residual (security review): between the step-10 recheck and the `mv` there is a microsecond window in which an editor,
`git checkout` or another agent could change the file; the lock excludes only other scaffold runs. The file is tracked and
the tree was clean, so the lost edit is recoverable from the editor buffer or reflog; a claim-then-verify rename was
considered and cut as disproportionate. `rename(2)` never follows a symlink at the final component, so a swap to a symlink
inside the window cannot redirect the write.

All other messages go stdout first, then stderr, through the existing `say`/`log` path. Bash 3.2 safe. The (template,
destination, ledger) triple is three named variables, not a table (R2 scopes the mode to one file).

### Phase 3, docs and records

- `plugins/soleur/skills/constraint-scaffold/SKILL.md`: add a Usage block after `--refresh-baseline` ("Refresh a stale auto-recovery workflow, agent-only, clean tree, workflow committed"): when to run it, that refresh converges the file on the CURRENT template (install command, model id and token wiring as well as the pin), the 75 refusals (edited, unknown version, installed newer than the plugin) and how to merge by hand (the report shows only template-side lines; read your own file), no bite-proof, never run by the founder, and the recovery for a SIGKILL (delete a leftover untracked `.fix-constraints-stage-a.*` file next to the workflow, never `git add -A`). Fix the sentence that calls the baseline "the only re-writable artifact" (it spans a line break: anchor on the phrase, not a line number); add a Self-tests row for `refresh-stage-a.test.sh`; add 75 to the 71-74 prose and to the "66..74" cleanup sentence ("75 is stage-a-mode only, removes nothing, and leaves the file byte-unchanged"); link the ledger from `references/` per the plugin reference-link rule. `description:` is NOT touched (word budget).
- SKILL.md also tells a pin-bump author what to do: when `fix-constraints-stage-a.template` changes, append a ledger row (the regeneration command is in the ledger header) only if the change keeps the frozen A-to-B interface and the `contents: read` permission set; the template itself is not edited for this, because any template edit changes its own emission hash.
- `constraint-scaffold.sh` header: Modes, exit 75 ("refused, not retryable"), 70 extended, the cleanup prose that lists 66..74; the 66 refusal for an existing stage-a file appends a hint to `--refresh-stage-a` while keeping the prefix `fix-constraints-stage-a.yml already present`, which `emit-fix-constraints.test.sh` line 185 matches by substring.
- ADR-071 amendment (dated 2026-11-05), content fixed by the architecture review: (1) Consequences (b) is rewritten as an enumeration of FOUR classes with the consequence-of-overwrite rationale for each (prose is append-once; executables are refuse-only; the baseline JSON is re-writable only via `--refresh-baseline`; and the new template-keyed re-emittable workflow); (2) the re-emittable class is limited to workflows whose token scope is `contents: read` and which hold no write credential: Stage B and any write-scoped workflow stay refuse-only, and a ledger row may not admit a Stage A emission whose `permissions:` differs from `contents: read` (changing that needs an ADR-074 amendment; case 12 asserts it); (3) the frozen Stage A to Stage B wire interface is (a) `name: fix-constraints-stage-a`, (b) artifact names `fix-constraints-patch-<pr>` and `fix-constraints-giveup-<pr>`, (c) the ADR-074 `meta.json` schema; a Stage A change to any of these is not a ledger-append event, it needs a Stage B refresh path first (verified: none of the six historical Stage A emissions changed (a) or (b)); Stage B staleness (for example the c99a4451df pagination fix) is accepted and safe only because of this frozen interface; (4) the Decision sentence "a `prove_bite` step at the tail of both modes" is amended: the bite-proof runs in every mode that can change what the gate enforces (config, runner, baseline); the Stage A refresh changes none of them, so skipping it is a property of the mode's write set, not an opt-out, and the rejected `--skip-bite-proof` flag stays rejected; (5) Alternatives Considered gets one line each for `--force`, a sibling script, a pin-line-only edit and a pristine-modulo-pin heuristic. ADR-074 gets one pointer sentence (Stage A is the one re-emittable workflow; the A-to-B interface is frozen as listed in the ADR-071 amendment).

### Phase 4, registries

- Stage the new test (`git add`) before running any repo-global ratchet (`git ls-files` readers see nothing otherwise).
- Run `python3 scripts/regenerate-shard-manifest.py --incremental --write` (the header of the manifest names this exact form for "suite added"), never a full `--timings-dir` re-price. Verify the diff is exactly one new row in each of `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`, positioned after `.../constraint-scaffold/test/parity.test.sh` and before `.../drain-prs/...` (sorted position), and that no other row moved.
- Run `bash scripts/lint-orphan-test-suites.sh`. The new suite is run by the existing `plugins/soleur/skills/*/test/*.test.sh` glob in `scripts/test-all.sh`.
- `scripts/ci-pr-affected-audit.accept.tsv`: run the replay ratchet (`python3 scripts/ci-pr-affected-replay.py`, check its `--help` for the exact flags first) and add accept rows only for pairs it reports for the new suite, each in sorted position, each with a reason. Out of scope: any pre-existing ratchet failure ("affected-index-ratchet failures"). Grep the report for the single `stale-accept` line to confirm no malformed row.

### Phase 5, Art. 30 register (item 3), wording ruled by the CLO

Edit `knowledge-base/legal/article-30-register.md` (the PA-33 entry), three in-cell replacements, nothing else:

1. Line ~700, field (d), member (1): replace `uses \`anthropics/claude-code-action@5aa6f47e977fec3321f32c06d8076b1f503f832c\` (v1.0.161); **active**;` with
   `uses \`anthropics/claude-code-action\` (pinned by commit SHA; the workflow file is the source of the pinned value); **active**; *[amended 2026-11-05 (#12146): the version tag and commit SHA previously recorded here were removed as perishable, and the SHA no longer matched any workflow in this repository. The register states the control only; the pinned value lives in the workflow files.]*`
2. Line ~712, member (8): replace `(pinned by commit SHA, v1.0.263 as of 2026-11-05 (#12102); it was v1.0.236 when this member was added)` with
   `(pinned by commit SHA; the workflow file is the source of the pinned value)`.
3. Line ~719, field (g), item (4): replace the exact old text below (it ends immediately before the `(5)` item that starts "Concurrency and loop guards")

   ```text
   **(4) Pinned action SHA** — `anthropics/claude-code-action@5aa6f47e977fec3321f32c06d8076b1f503f832c` (v1.0.161), pinned by commit rather than by tag, on all three action-using members.
   ```

   with
   `**(4) Pinned action SHA** — \`anthropics/claude-code-action\` is pinned by commit SHA rather than by tag on every action-using member. The workflow files are the source of truth for the pinned value, and \`apps/web-platform/test/claude-pin-lockstep.test.ts\` enforces that this repository's copies (the workflow files, the constraint-scaffold template and the operator-digest provisioning asset) carry one and the same (SHA, tag) pair. *[amended 2026-11-05 (#12146): the version tag, the commit SHA and the count of action-using members previously recorded here were removed as perishable; the count had also drifted from the member enumeration.]*`

(The backslash-escaped backticks in the replacement texts above are rendering escapes for this document; the register text uses plain backticks.)

The amendment notes do not quote the removed strings (an absence grep must not count its own audit trail). Leave alone,
as dated records: `knowledge-base/legal/audits/2026-07-counsel-review-7086.md`, the LIA
`2026-07-31-claude-eval-fleet-and-ci-lia.md` (its "three files" is a dated measurement, no tag), and the "now 4" snapshot paragraph dated 2026-11-01 in line 700. Verify with
`grep -rnE '5aa6f47e|v1\.0\.[0-9]{2,}' knowledge-base/legal` (no leading-context quantifier; `{2,}` skips unrelated `v1.0.0` template versions in `compliance-posture.md` and the 2026-05 counsel review; the one expected survivor is `audits/2026-07-counsel-review-7086.md`, a signed dated record), then run
`bash scripts/lint-legal-registers.sh` and `bash scripts/lint-art30-reverification.sh` (expected: no trigger fires) and the
repo's markdownlint on the file.

### Phase 6, verification and PR

- Run locally, each as its own command (a brace expansion `test/{a,b}.test.sh` runs only the first file and passes the rest as arguments; use `for t in refresh-stage-a parity emit-fix-constraints; do bash "plugins/soleur/skills/constraint-scaffold/test/$t.test.sh" || exit 1; done`): the new suite, `parity.test.sh`, `emit-fix-constraints.test.sh`, `bite-proof.test.sh` (it pins the trap arm and disarm lines by grep, so the shared-trap edit must be checked, not assumed), `git diff origin/main -- apps/web-platform/test/claude-pin-lockstep.test.ts` (must be empty), and the Phase 5 legal lints.
- Repo ratchets that scan the new shell shapes (`mv "$tmp" "$dest"`, `rm -f`, `> "$tmp"`, `have="$(...)"`, the new test's `rm -rf "$fx"`): `plugins/soleur/test/fixture-relative-assert.test.sh` (its baseline `fixture-relative-assert.baseline.txt` is pinned by row equality, so a rise reddens exactly like a fall; it already carries rows for `constraint-scaffold.sh`), `plugins/soleur/test/fixture-dir-operand-assert.test.sh`, and `python3 scripts/lint-shell-capture-exit.py` (its baseline `lint-shell-capture-exit.baseline.txt` may only shrink). Write the new code guard-first (`assert_fixture_dir` before a destructive operand, `|| true` on captures that can fail) rather than baselining new rows; if a row legitimately moves, regenerate that baseline in the same commit and say why.
- File the `take_run_lock` tracking issue named in Non-Goals (check the label with `gh label list --limit 200 | grep deferred-scope-out` first).
- Everything else (generator, lockstep, components) is left to CI's required `test` check.
- PR body: `Ref #12146`; `## Changelog` section; `semver:patch` label (a new agent-only flag on an existing skill, no new component); mention the decision-challenges rulings. Never a closing keyword.
- Merge discipline: rely on CI's required `test` check (required: test, lockfile-sync, markdown-lint, tenant-integration-required); read `infra-validation` and `sandbox-canary-capture-gate` by hand. Before any push run `bash plugins/soleur/scripts/sync-pr-behind.sh 12177 --queue-state`; never push to a PR in the merge queue. Check each push's real exit code (no `| tail`). `git add` and `git commit` in separate calls; `cd` into the worktree first; no `rm -rf` inside the worktree. Never `--admin`, never touch the ruleset; if the owner-run merge freeze blocks the merge, stop with the PR queued or ready and report.

### Phase 7, post-merge (tracker boxes)

- Tick the item-2 and item-3 boxes in #12146 (not item 1): read the body with `gh issue view 12146 --json body`, replace only the two `- [ ]` markers whose text starts with `**Scaffold refresh path.**` and `**Art. 30 register version tags.**`, write back with `gh issue edit 12146 --body-file <file>`, then re-read and confirm exactly those two flipped and the `<!-- soleur:followthrough ... -->` directive is intact.
- Verify: `GH_TOKEN="$(gh auth token)" bash scripts/followthroughs/claude-code-action-residual-pins-12136.sh`. Expected: exit 5 (ACTION REQUIRED, one box, item 1, still unticked) until the parent session ticks item 1; exit 0 only after all three. Report the exit code and output verbatim. Do not close #12146.

## Files to Edit

- `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh`
- `plugins/soleur/skills/constraint-scaffold/SKILL.md`
- `knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md`
- `knowledge-base/engineering/architecture/decisions/ADR-074-fix-constraints-two-stage-privileged-split.md`
- `knowledge-base/legal/article-30-register.md`
- `scripts/suite-durations.tsv`
- `scripts/suite-shard-legs.tsv`
- `scripts/ci-pr-affected-audit.accept.tsv` (only if the registry lint or replay ratchet reports the new suite)

## Files to Create

- `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.emitted.sha256`
- `plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh`
- `plugins/soleur/skills/constraint-scaffold/test/fixtures/stage-a.v1.0.236.emitted`
- `knowledge-base/project/specs/feat-one-shot-12146-scaffold-refresh-art30-tags/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-12146-scaffold-refresh-art30-tags/decision-challenges.md`

Not touched: `apps/web-platform/test/claude-pin-lockstep.test.ts`, the other four templates (including
`fix-constraints-stage-a.template` itself), the SKILL.md `description:`, the C4 model files, the operator-digest asset,
any workflow file.

## Guard Contract

The matrices below are a design-time review of the guard, derived before the guard is written. The rows that name a
test case are covered by a shipped case; the rest are a one-time manual check at implementation time, not a mutation
harness to build (plan review: do not read this as scope for an automated mutation runner).

### Guard 1 — stage-a clobber guard (overwrite only a ledger-listed historical emission)

**Property.** A `--refresh-stage-a` run replaces `fix-constraints-stage-a.yml` only when its bytes are exactly a
ledger-listed historical emission of the template, and otherwise leaves the file byte-identical and exits 75.

**Assembly.** The chokepoint is the single `mv` in `refresh_stage_a`; every path to it passes through the three-way
classification (equal to fresh, ledger member, else refuse). The destination set is exactly one file; every other emitted
file has no write path in this mode, and case 10b snapshots all of them. The members that drift are the ledger rows; the
ledger is read by the same parser the script uses (first whitespace-separated field of each non-comment line), never by
a hand-written list in the test. There is one write site; the symlink check and the tree check run before it on the same
destination.

**Mutation matrix.** Each row is an edit that MUST turn the named test RED.

| # | Mutation | Must redden |
|---|----------|-------------|
| 1 | Append one comment line to the ledger-member copy | case 3a, 3b |
| 2 | Drop the final newline of the ledger-member copy | case 4 (proves exact-byte match, not normalised text) |
| 3 | Remove the ledger file, or empty it to zero data rows or comment-only | case 8 (a refresh happening anyway; must fail closed) |
| 4 | Make `ledger_has` stop at the first row | case 1 (the fixture is ledger row 5 of 6) |
| 5 | Make `ledger_has` treat "no match" as "allow" | cases 3, 4, 8 |
| 6 | Reorder: move the clean-tree check after the `mv` | case 5a (dirty tree must leave the file unchanged; the destination holds ledger-member bytes so only the guard can refuse it) |
| 7 | Dispatch: make the mode parse but run nothing (exit 0, nothing checked) | case 1b (file must equal the fresh emission) and case 10a |
| 8 | Add a write to stage-b or constraint-gates.yml inside the mode | case 10b |
| 9 | Remove the symlink check | case 9a |
| 10 | Move the 70 check after the lock or the tree check | case 6a, 6d (rc 70, and the pre-created live lock is untouched) |
| 11 | Let an empty or malformed hash classify (fail open: `have` empty matches any row) | case 9c (fake hash tool emitting an empty digest) |
| 12 | Drop the rank comparison (a newer installed file is rewritten to an older template) | case 7b |
| 13 | Print the existing side of the diff (leaks a secret pasted into an edited workflow) | case 3c |
| 14 | Weaken the physical-destination-directory equality to repo containment | case 9b |
| 15 | Skip the pre-write recheck | no shipped case (a race cannot be driven deterministically); design-time review only, residual stated in Phase 2 |
| 16 | Let the template gain a write permission or a second trigger | case 12 |

**Harness rows.** Suite edits that MUST redden: stub `fail()` to a no-op or delete the `cases` conservation check (the
instrument self-test inherited from `parity.test.sh` catches it); replace the fresh-emission comparison in case 1 with a
tautology (the mutation pair case 1 vs case 3 catches it, because an always-pass compare lets case 3's refusal look like
success). Must-PASS input that is not the canonical: the already-current file (case 2), which differs from the stale
fixture in exactly the way the contract permits (a no-op, not a refusal).

**Anchor.** The ledger stores hashes that the same commit could also edit, so it proves consistency, not integrity. What
sits outside the commit: the ledger header carries the regeneration command, so a reviewer re-derives any row from git
history; case 7 ties the newest row to the working-tree template, which `claude-pin-lockstep.test.ts` (KNOWN_ACTION_PINS,
minimum tag) and `parity.test.sh`/`emit-fix-constraints.test.sh` pin separately. Stated residual: a typo'd or forged row
is not detected by a test (plan review cut a history-reproducibility anchor test as a second line of defence that skips on
shallow clones and is edited in the same commit). A missing or typo'd row fails safe: that install era is refused (75),
never clobbered. A removed row is the same safe direction. A forged row that admits an edited file's hash needs a
deliberate, reviewable ledger diff.

## Observability

Layer 7: code under `plugins/` that executes on a founder's machine or a hosted runner with no human reading stdout.
This is a CLI generator, not a server; there is no Sentry or Better Stack surface for it, and ADR-071 states the
hosted-runner deviation (a mirrored-not-paged halt marker is #8381, out of scope here).

```yaml
liveness_signal:
  what: "the mode's one-line verdict on stdout: 'refreshed ...', 'already current', or 'FAILED (<code>): ...'"
  cadence: "per run (agent-invoked, on demand)"
  alert_target: "the invoking agent's transcript; coded exit status (0, 64, 65, 67, 69, 70, 75)"
  configured_in: "plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh (die/say path)"
error_reporting:
  destination: "stdout first, then stderr (agent runtimes surface stdout and swallow stderr); layer 7, no Sentry"
  fail_loud: "every non-zero exit prints 'constraint-scaffold: FAILED (<code>): <msg>' on stdout; 75 also prints a bounded template-side-only report (never the user's file)"
failure_modes:
  - mode: "installed stage-a is user-edited or from an unknown version"
    detection: "ledger miss, exit 75, template-side report on stdout, file byte-unchanged (cases 3, 4)"
    alert_route: "invoking agent merges by hand per SKILL.md"
  - mode: "ledger missing or empty"
    detection: "fail closed: refused, nothing written (case 8)"
    alert_route: "invoking agent; the ledger is in the skill's references/"
  - mode: "template changed without a ledger row"
    detection: "test case 7 reddens in CI (required test check) and prints the regeneration command"
    alert_route: "PR author at CI time"
  - mode: "rename or compare failure at the write"
    detection: "exit 69 before the write (or at the mv), original intact, temp file removed by the shared trap"
    alert_route: "invoking agent"
logs:
  where: "the invoking session's stdout/stderr; no persistent log"
  retention: "the session transcript"
discoverability_test:
  command: "bash plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh --refresh-stage-a"
  expected_output: "(70)"
```

(In this repository `apps/web-platform/.github/workflows/fix-constraints-stage-a.yml` does not exist, so the probe
deterministically reaches the exit-70 arm without writing anything, because the 70 check precedes the tree check and the lock. The expected token is `(70)`: preflight Check 10 tokenizes `expected_output` with `tokenizeExpected` (`plugins/soleur/test/lib/discoverability-test-parser.ts`, which splits on commas, the word `or`, quotes, brackets and `/`, not on whitespace; verified by running it: `(70)` is one token) and substring-matches a token against stdout, so only a 70 satisfies it. A value whose every token contains whitespace (such as `FAILED (70)`) is rejected by deepen-plan Phase 4.7 as prose, which is the second reason to use the whitespace-free token. Re-check at deepen time that the command stays inside
the 15-second preflight cap and the read-only sandbox.)

## Acceptance Criteria

- [ ] AC1. `constraint-scaffold.sh --refresh-stage-a` on a fixture holding the v1.0.236 emission rewrites the file byte-equal to the fresh emission (mode 0644) and exits 0.
- [ ] AC2. On an already-current file it exits 0, prints `already current` and does not write (inode unchanged, backdated mtime not advanced), even when the ledger is absent.
- [ ] AC3. On an edited copy (any byte differing from every ledger member, including a stripped final newline) it exits 75, leaves the file byte-identical and prints a bounded template-side-only report on stdout (never the existing file's content, never a planted token).
- [ ] AC4. Dirty tree exits 67; missing stage-a, missing config or a dangling symlink exits 70 (also on a dirty tree, with no lock taken); a symlinked destination, or a physical destination directory other than `$TARGET/.github/workflows`, exits 75; an untracked destination exits 67; none of them writes. Exit 64 and 65 are pre-existing paths and are not re-tested.
- [ ] AC5. A missing, empty or comment-only ledger refuses a stale file (never refreshes); an installed file whose ledger rank is newer than the plugin's template is refused with no diff (no downgrade); an empty or malformed hash is a 69, never a match; the lock and temp file are released on every exit.
- [ ] AC6. `refresh-stage-a.test.sh` exists with the 12 cases and their labelled sub-rows, passes, and has one new sorted row in each of `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`; `bash scripts/lint-orphan-test-suites.sh` passes; accept rows exist only where the replay ratchet required them.
- [ ] AC7. `constraint-scaffold.sh` and the ledger contain no `claude-code-action@` and no word-bounded 40-hex string; the pin comes only from the template at run time.
- [ ] AC8. `git diff origin/main -- apps/web-platform/test/claude-pin-lockstep.test.ts` is empty and that test passes; `parity.test.sh`, `emit-fix-constraints.test.sh`, `bite-proof.test.sh` still pass locally; `generator.test.sh` is left to CI; the fixture-relative, fixture-dir-operand and shell-capture-exit ratchets are green with no baseline growth.
- [ ] AC9. `grep -rnE '5aa6f47e|v1\.0\.[0-9]{2,}' knowledge-base/legal` returns only `audits/2026-07-counsel-review-7086.md` (a dated record left alone) and no hit inside `article-30-register.md`; the three replacements match the CLO text verbatim.
- [ ] AC10. `bash scripts/lint-legal-registers.sh` and `bash scripts/lint-art30-reverification.sh` pass; markdown-lint passes on the register, SKILL.md and the ADRs.
- [ ] AC11. PR body contains `Ref #12146` and no `Closes`/`Fixes`/`Resolves #12146`; it has a `## Changelog` section and a `semver:patch` label.
- [ ] AC12. ADR-071 carries the dated 2026-11-05 amendment (four-class enumeration, the `contents: read` privilege rule, the frozen Stage A to Stage B interface, the amended bite-proof sentence, one-line alternatives); ADR-074 has the pointer line; case 12 passes; no `.c4` file is edited.
- [ ] AC13. `decision-challenges.md` has the `| Item | Class | Ruling |` rows for R1-R7 and the CLO ruling, each `Ruled by ...` cell copied from the agent reply, and `ship/scripts/technical-ruling-gate.sh` passes on it.
- [ ] AC14. Post-merge: boxes 2 and 3 of #12146 are ticked, box 1 untouched, the directive comment intact, and the probe's output and exit code are reported verbatim.

## Test Scenarios

Covered by the 12 cases in Phase 1.3 and the mutation matrices in the Guard Contract (mutation M drives guard G red, not
only command X reaches state Y). Integration check: after a refresh, run `parity.test.sh`-style comparison of the
refreshed fixture file with `sed "s|__TARGET_DIR__|apps/web-platform|g"` of the template (case 1 does this directly; hashing a fresh emission twice, once as `want` and once through the second `sed` pass, is the in-script equivalent).

## Plan Review Outcome (2026-11-05, headless)

Panel: DHH, Kieran, code-simplicity (threshold is `aggregate pattern`, so no architecture-strategist or spec-flow). The
CTO was not re-spawned as a devex reviewer: it authored the design under review, so a second pass would not be independent.
All findings below are Mechanical (one right answer) and were applied to this plan.

- Applied, correctness (Kieran): the refusal path hand-rolls `exit 75` instead of `die` and neutralises `diff` rc 1 and SIGPIPE under `set -euo pipefail`; verify the temp file before the `mv` and make the `mv` the last fallible step (the old "original intact on cmp failure" claim was false); `chmod 0644` after `mktemp`; explicit `mktemp` template for BSD; symlink check is `-L` plus parent containment (`physpath` cannot see a symlinked file); `have` must be a 64-hex string before classification and the ledger match is exact first-field equality (an empty hash would otherwise match every row); reuse the single trap owner `_wt_cleanup` instead of a second handler; explicit step order with the 70 check first; local test command is a loop, not a brace expansion; the three repo ratchets that scan new shell shapes are named; register verification grep uses `{2,}`; the old text of PA-33 (g)(4) is quoted for a deterministic `Edit`; discoverability token is `(70)`; "8-line" corrected to 7-line.
- Applied, simplification (DHH + code-simplicity, both agree): Guard 2 and its history-reproducibility test cut (it skipped on shallow clones, was editable in the same commit, and was not in the CTO's ruling; the residual is stated in Guard 1's Anchor); suite cut from 20 to 11 cases; one fixture (v1.0.236, the tracker's named era) instead of two; C4 description tweak cut; Phase 6 local verification trimmed to what CI does not cover; the one-row table became three variables; Guard Contract matrices marked as a design-time check, not a harness to build.
- Applied, DHH P1 #3 (pin-bump discoverability), differently: the template is NOT edited (any template edit changes its own emission hash), so the guidance lives in the ledger header, the SKILL.md block and case 7's failure message, which prints the regeneration command.
- Not applied: nothing was declined.

## Deepen-Plan Outcome (2026-11-05, headless)

Findings from security-sentinel (8), test-design-reviewer (8) and architecture-strategist (6) were all Mechanical (one right
answer) and are applied above. Judgement calls, recorded here so a later reader sees what was not taken:

- Not taken, security #3 claim-then-verify rename: disproportionate for a tracked, clean-tree file; a pre-write re-hash narrows the window and the residual is stated in Phase 2.
- Not taken, security #5 stale-temp sweep and HUP/PIPE traps: the shared trap lines are pinned by `bite-proof.test.sh`; pipelines are wrapped instead, and SKILL.md names the SIGKILL recovery.
- Not taken, security #6 CODEOWNERS rows, runtime structural re-check and a history-reproducibility test: out of scope and listed in Non-Goals; case 12 asserts the structural properties on the template in CI.
- Taken in reduced form, security #7: the `take_run_lock` race is a tracked scope-out, not fixed here.
- Taken, architecture #3: no lockfile precondition is added because the sibling `constraint-gates.yml` already runs `npm ci --ignore-scripts`, so a repo whose gate works already has the lockfile; the content-upgrade fact is documented instead.

## Non-Goals

- The affected-index-ratchet failures, Better Stack incident `soleur-egress-gw-probe-silent-prd`, the `digest-scrub.sh` token-pattern gap, item 1 of #12146 (all named out of scope in the brief). Pre-existing, owned elsewhere.
- Installs that predate the two-stage split (the old `issue_comment` dispatcher): there is no stage-a file, the mode exits 70; migrating them is a separate default-mode question. Not tracked as a deferral: no such install is known and the gate was never promoted to required.
- Refreshing config, runner, baseline, `constraint-gates.yml` or stage-b (CTO R2).
- Installed copies of the operator-digest asset (item 1, parent session).
- A pre-existing race in `take_run_lock` (the `mkdir` and the pid write are not atomic, so a second run in the gap reads an empty owner and takes a live lock; `kill -0` EPERM reads as stale). It predates this change and also affects `--refresh-baseline`; fixing the shared helper is out of scope. Tracked: Phase 6 files one `deferred-scope-out` issue for it (re-evaluation: when the lock is next touched), with the milestone from `knowledge-base/product/roadmap.md`.
- A CODEOWNERS row for the template and ledger (the file only has a `*` fallback and its own header says routing is not enforcement) and a runtime structural re-check of the rendered workflow (case 12 asserts the same properties on the template in CI; a compromised plugin can already run arbitrary code in the agent session).

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. It is filled above.
- The ledger hashes are of the `__TARGET_DIR__`-substituted emission for `apps/web-platform` (the v1 target). A future second target would need its own ledger rows; out of scope (v1 is Next.js-only, one target).
- Fixtures contain historical action pins on purpose. They are invisible to the lockstep census by path (`test`, `fixtures`) and by extension (`.emitted`). If a future census widens, add an explicit carve-out rather than weakening the guard.
- `git add` the new test before repo-global ratchets, or they read an empty `git ls-files` and pass falsely.
- The register edits are in single very long table cells. Use exact-string `Edit` replacement of the quoted fragments, not line-based edits; GFM silently drops cells past the header count, so re-render-check the table row count is unchanged.
- PR #8626 also edits the register; expect a possible textual conflict at ship time and resolve by re-applying only the three fragments.
- The merge freeze is owner-run. If it blocks the merge, stop with the PR ready or queued and report; do not escalate to `--admin`.

## Work-phase Amendment (2026-11-05)

- The `take_run_lock` race was planned as a tracked `deferred-scope-out` issue (Non-Goals, Phase 6, tasks 6.0). The
  second-reviewer gate (code-simplicity-reviewer) returned DISSENT: the fix is under the 100-line, 4-file
  inline threshold and this PR adds a third caller of the helper. It was fixed inline instead, so no issue is
  filed. Two changes in `take_run_lock`: an owner-less lock directory younger than a minute is held rather than
  taken over, and a failed `kill -0` is confirmed with `ps -p` before the owner is called gone (EPERM on a live
  process of another user). Test cases 13a-13c in `refresh-stage-a.test.sh`; each reddens when its half of the
  fix is removed. The stale-takeover `rm -rf` between two simultaneous takers remains a narrower residual.
  Suite floor `MIN_ROWS` is 67.
- The canonical `assert_fixture_dir` guard was copied into `constraint-scaffold.sh` and called before the two new
  write sites, because the fixture-relative and fixture-dir-operand ratchets count unproven write operands
  (the plan said to write guard-first rather than baseline new rows).
