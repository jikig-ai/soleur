---
title: "fix(ship): Phase 2 learning probe is branch-scoped, not a repo-wide one-week window"
date: 2026-09-22
slug: fix-ship-phase2-branch-scoped-learning-probe
branch: feat-one-shot-8470-ship-learning-probe-branch-scoped
issue: 8470
closes: none   # Ref #8470 only — #8470 closes after the re-measure, never at merge
type: bug
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(ship): Phase 2 learning probe is branch-scoped (Ref #8470)

## Enhancement Summary

**Deepened on:** 2026-09-22 · **Sections enhanced:** 7 · **Agents:** plan-review panel (DHH,
Kieran, code-simplicity, CTO), advisor consult, test-design-reviewer, architecture-strategist,
learnings-researcher.

### Key Improvements

1. The probe's committed arms run only after a successful fetch (a stale `origin/main` had
   re-created the defect), and pathspecs are root-anchored (`:/`) so a subdirectory cwd works.
2. A `compound:`/`learning:` commit-subject arm stops one-shot from running compound twice when
   compound only updated or archived.
3. The regression suite pins behaviour over 11 fixture rows with a real local bare remote, a
   hermetic `bash --noprofile --norc`, and an any-fence-kind exactly-one-block rule.
4. ADR-229 amendment keyed on the test file's first first-parent commit on `main`, written as an
   explicit trigger change (interactive Skip), in this PR.

### New Considerations Discovered

- Ship Phase 1.5 already forbids `|| true` on the fetch; the first draft violated it.
- Two other ship lines (Headless Mode Detection, Important Rules) contradicted a conditional Phase 2.
- Deepen-plan Phase 4.7 covers `plugins/*/skills/*.md`, so the Observability block is required.

## Overview

Ship Phase 2 decides whether compound already ran for the feature by asking git for any learning
commit in the whole repository over the last week. In this repository that answer is always yes
(12 of 12 sampled weeks, per #8470), so the feature-scoped follow-up check is skipped and compound
does not run. This plan:

1. **(A)** replaces that question with a branch-scoped one — "did THIS branch add a learning file,
   committed or not?" — as a single executable fenced block that prints one decisive token
   (`BRANCH_LEARNING=present|absent`), and makes the predicate unambiguous: `absent` ⇒ compound runs
   (interactive Skip is offered only when no unarchived artifacts exist, exactly as today);
2. adds a behavioural regression test that extracts that block from the `## Phase 2: Capture
   Learnings` section and executes it against fixture repositories — it goes RED on the old
   `--since="1 week ago"` form;
3. **(C)** amends ADR-229 **in this PR** to record the fix and arm the re-measure rule against the
   fixing PR's merge event (no date needs filling), leaving exactly one post-merge action: a comment
   on #8470 stating the actual `mergedAt`, the six-week deadline and the `SINCE` value;
4. **(B)** the PR body carries `Ref #8470`, never a closing keyword.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Out of scope (D): the `ship → plan` and `postmerge → plan` transitions, the unmodelled in-ship
`review` call noted in ADR-229, and #8326.

## Research Insights

**Premise Validation (Phase 0.6).** #8470 is OPEN (`gh issue view 8470`), its body carries the
triage procedure and the re-open trigger verbatim; no closing PR exists. Draft PR #8567 is OPEN
(WIP title/body). The cited probe exists on this branch at `plugins/soleur/skills/ship/SKILL.md`
§`## Phase 2: Capture Learnings` (`git log --oneline --since="1 week ago" -- knowledge-base/project/learnings/`).
ADR-229's #8399 ruling bullet already states the re-open trigger (merge-relative: ≥5 full-pipeline
`review → ship` rows or six weeks) and its Alternatives table already REJECTS enrolling a
follow-through sweeper probe for this measurement (the gitignored invocation log cannot exist on
the hosted runner) — so a sweeper enrollment is a rejected mechanism, not an unconsidered one.
Stale premise found: the brief's and issue's "ship/SKILL.md is at its 274000-byte ceiling" — it is
at 262718 B after PR #8474 (see Reconciliation).

**Property List (Phase 0.6b).**
- P1 — On a branch that added no learning, ship Phase 2 routes to the compound path (runs it, or
  offers Skip only when no unarchived artifacts exist).
- P2 — On a branch whose compound already wrote a learning (committed or not), ship Phase 2 does not
  run compound again.
- P3 — The probe's verdict is one unambiguous token, so two readers cannot branch differently.
- P4 — A regression to any repo-wide/time-window probe reddens CI.
- P5 — ADR-229 records that the fix landed and against which event the re-measure is taken; #8470
  stays open until that re-measure.

**Cut List (Phase 0.6b).**
- Extract Phase 2 to `references/` + load directive (issue fix-path step 1) → bought "fits the byte
  ceiling" → already satisfied inline (11282 B headroom, ~+1050 B delta). Cut.
- `knowledge-base/project/learnings/**/*FEATURE*` Glob → bought nothing P1/P2 need; it reintroduces
  the repo-wide-in-time false positive. Cut.
- Follow-through sweeper enrollment for the six-week re-measure → ADR-229 Alternatives rejects it
  (log absent on the runner); a date probe would auto-CLOSE #8470 without the re-measure. Cut; the
  merge comment (§D) plus the ADR record carry it.
- Post-merge ADR edit to fill the merge date → `gh pr view 8567 --json mergedAt` already derives it.
  Cut; ADR amended in this PR, event-keyed.

**Value-proposition measurement (0.6c):** not a cost/perf claim — skipped.

**Relevant files.** `plugins/soleur/skills/ship/SKILL.md` (Phase 1 feature-name extraction ~L131;
Phase 1.5 `git fetch origin main` ~L154; Phase 2 L255-286); `plugins/soleur/test/workflow-fidelity.test.ts`
(sub-step anchor test, `SECTION.ship`); `plugins/soleur/test/skill-body-budget.json` (ship 274000);
`scripts/lint-skill-body-budget.py` (`--base origin/main`, OK today);
`plugins/soleur/test/ship-pr-title-guard.test.ts` (per-gate SKILL.md test shape);
`plugins/soleur/test/ship-incident-pir-gate.test.ts:559-594` and `plugins/soleur/test/lib/git-fixture-env.ts`
(`gitFixture`, `gitFixtureEnv`); `plugins/soleur/test/fixture-env-adoption.test.sh` (enforces helper use);
`scripts/test-all.sh:2781` (`bun test plugins/soleur/` auto-discovers the new suite);
`plugins/soleur/skills/compound/SKILL.md` (compound writes the learning before committing; archives
via `archive-kb.sh` on `feat-*`).

**Institutional learnings applied.**
- `2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md` — every sentence about git
  behaviour in the new prose was RUN in a throwaway fixture before being written (table in §A),
  including the merge-of-newer-main shape.
- `2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md` — fixtures cover
  realistic topology (diverged branch + merge commit), not just linear history.
- `2026-06-11-digest-launch-quality-fallback-content-and-fence-parse.md` — fence extraction must be
  exact; the test counts fences of ANY language tag and asserts exactly one in the section.
- `2026-04-06-rule-audit-budget-baseline-drift.md` — re-measure `wc -c` at work time; the plan
  states the delta (~+1050 B), not an absolute.
- `2026-04-11-stale-main-and-playwright-first-workflow-gaps.md` — fetch before reading
  `origin/main`; the block trusts its committed arm only after a successful fetch (plan-review revision).

**CLAUDE.md / AGENTS conventions.** `cq-write-failing-tests-before` (write the suite first, watch
row 1 fail on the current SKILL.md); `cq-assert-anchor-not-bare-token`; `cq-cite-content-anchor-not-line-number`
(new prose cites the test path, not line numbers); `hr-never-git-stash-in-worktrees`;
`wg-use-closes-n-in-pr-body-not-title-to` inverted here by design (`Ref`, #8470 must stay open).

## Research Reconciliation — Issue vs. Codebase

| Issue / brief claim | Reality (measured 2026-09-22) | Plan response |
|---|---|---|
| "ship/SKILL.md is at its 274000-byte ceiling; extract Phase 2 to `references/` to free bytes" (#8470 fix path step 1) | `wc -c` = **262718** B; ceiling 274000 → 11282 B headroom (PR #8474 freed it). `lint-skill-body-budget.py --base origin/main` → OK. The drafted Phase 2 replacement measures **+981 B** (1609 → 2590), ~+1050 B with the §A.2 lines. | Keep Phase 2 **inline**. Extraction would add a load directive, a reachability-guard dependency and a second file for a 2.4 KB section, and it would move the probe block away from the section the anchor test scopes. Ceiling untouched. |
| "The probe must also count an uncommitted learning" (#8470 design caveat) | Confirmed necessary: compound writes the file before its commit. | `git status --porcelain … \| grep -E '^(\?\?\|A)'` arm in the same block. |
| Phase 2 also globs `knowledge-base/project/learnings/**/*FEATURE*` | That glob is repo-wide in TIME: any older learning whose filename contains the feature slug (e.g. `ship`, `plan`) satisfies it — a second instance of the same defect class. | **Cut** — the branch-scoped probe covers the property. |
| "Keep the `skill: soleur:compound` literal in the Phase 2 section" | Pinned by `plugins/soleur/test/workflow-fidelity.test.ts` → "every sub-step is invoked by its key's SKILL.md in the section that owns it" (`SECTION.ship = "## Phase 2: Capture Learnings"`). | The rewrite keeps all three existing compound calls inside the section. |
| "Prefer extending an existing test" | The ship SKILL.md content tests are **one bun file per gate** (`ship-pr-title-guard.test.ts`, `ship-undeferred-operator-step-gate.test.ts`, `ship-incident-pir-gate.test.ts`, …), auto-discovered by `run_suite "plugins/soleur" bun test plugins/soleur/` in `scripts/test-all.sh`. `workflow-fidelity.test.ts` pins FSM/sub-step claims and runs in the `grok-fidelity` check; a git-fixture behavioural test does not belong there. | New `plugins/soleur/test/ship-learning-probe.test.ts`, following the per-gate convention. No registration edit needed. It is a TS file, so the bash `assert_fixture_dir` byte-identity constraint does not apply; git spawns go through `gitFixture`/`gitFixtureEnv` (`plugins/soleur/test/lib/git-fixture-env.ts`), which `fixture-env-adoption.test.sh` enforces. |
| Advisor consult: "move the probe into `skills/ship/scripts/learning-probe.sh`; test the script" | A script test stays GREEN if SKILL.md reverts to an inline `--since` probe that no longer calls the script, so the SKILL.md section would still need its own pin — two artifacts plus a path-resolution concern (`CLAUDE_PLUGIN_ROOT` on user hosts) for a 4-line block. | Stay **inline** and test the block the agent actually runs, extracted from the section. The advisor's other point (hermetic env) is already met by `gitFixtureEnv`. |

## Proposed Solution

### A. New `## Phase 2: Capture Learnings` body (inline, `plugins/soleur/skills/ship/SKILL.md`)

Replace the section from its heading up to (not including) `## Phase 3: Verify Documentation`
with the text below (drafted and measured: 1609 → **2590 B, +981 B**; with the two one-line
edits in §A.2 ship stays ~263.8 KB of a 274000 B ceiling). The heading line and every `skill: soleur:compound` call are preserved.

````markdown
## Phase 2: Capture Learnings

Did **this branch** add a learning? Ask the branch, not the calendar: a repo-wide `--since` window is non-empty in essentially every week here, so it never said "compound has not run" (#8470). Run this block as written:

```bash
{ git status --porcelain -- ':/knowledge-base/project/learnings/' | grep -E '^(\?\?|A)'
  git fetch -q origin main 2>/dev/null && {
    git log --diff-filter=A --format=%h origin/main..HEAD -- ':/knowledge-base/project/learnings/'
    git log --format=%s origin/main..HEAD | grep -E '^(compound|learning): '
  } 2>/dev/null
} | grep -q . && echo "BRANCH_LEARNING=present" || echo "BRANCH_LEARNING=absent"
```

It counts a learning compound wrote but has not committed yet, counts an ADDED file or a branch commit whose subject starts `compound:` or `learning:` (compound's own commit prefixes; editing an old learning in any other commit is not capturing one), and trusts the committed arms only after a successful fetch — a stale `origin/main` would widen the range to main's own learnings (Phase 1.5's fetch rule). Every doubt resolves toward running compound. Pinned by `plugins/soleur/test/ship-learning-probe.test.ts`.

**`BRANCH_LEARNING=present`:** compound already ran for this branch — continue to Phase 3.

**`BRANCH_LEARNING=absent`:** compound has not run for this branch, so it runs now unless the interactive Skip below applies. First check for unarchived KB artifacts matching the feature name (excluding `archive/` paths) using the Glob tool:

- Brainstorms / Plans / Spec directory globs — unchanged

**If unarchived artifacts exist:** … unchanged (Do NOT offer Skip; `skill: soleur:compound`, or `--headless`) …

**If no unarchived artifacts exist:** … unchanged (Headless: `skill: soleur:compound --headless`; Interactive: Yes → `skill: soleur:compound` / Skip) …

After compound completes (or is skipped), continue to Phase 3 immediately. … unchanged
````

The "unchanged" spans are copied byte-for-byte from the current section; only the opening probe
paragraph, the `learnings/**/*FEATURE*` Glob line and the "If no recent learning exists" lead-in
change. The full drafted text is reproduced at work time from the current section plus this diff.

**Why a commit-subject arm (deepen-plan, architecture review).** `soleur:one-shot` runs
`skill: soleur:compound` BEFORE ship (its steps 6-7), and compound sometimes only UPDATES an
existing learning (`learning: update <topic>`, compound/SKILL.md "Managing Learnings") or only
archives artifacts (`compound: consolidate and archive feat-<slug> artifacts`,
compound-capture/SKILL.md). With the added-file arm alone that session reads `absent`, the artifacts
are already archived, and headless ship runs compound a second time. Compound's own commit prefixes
close that gap; a hand-written `learning:` commit is still a captured learning.

### A.2 Two one-line consistency edits elsewhere in `plugins/soleur/skills/ship/SKILL.md`

- `## Headless Mode Detection` bullet `- Phase 2: auto-invoke \`skill: soleur:compound --headless\` (forward flag, no user prompt)`
  → append ` when the Phase 2 probe prints \`BRANCH_LEARNING=absent\``. Otherwise it reads as
  unconditional and contradicts the `present` → Phase 3 branch.
- `## Important Rules` line `- **Ask before running soleur:compound.** The user may have already documented learnings.`
  → `- **Phase 2's probe decides whether compound runs.** Ask only on its interactive no-artifacts path.`
  (the old line already contradicted the unarchived-artifacts path, which never asks).

**Probe semantics (each row RUN in a throwaway fixture with a local bare `origin`, 2026-09-22):**

| # | Fixture state | Probe prints | Old `--since` form |
|---|---|---|---|
| 1 | origin/main has a learning committed today; branch adds none | `absent` | hashes (→ "learning exists") — **the defect** |
| 2 | branch has an untracked new learning | `present` | — |
| 3 | branch has a committed new learning | `present` | — |
| 4 | branch has a **committed** modification of an existing learning | `absent` | hashes |
| 5 | branch merged a newer main (fetched) that carries a learning | `absent` | hashes |
| 6 | no `origin` remote | `absent` | — |
| 7 | fetch fails and local `origin/main` is stale (older than the branch point); branch merged local `main` carrying a learning | `absent` | hashes |
| 8 | row 2 run from a subdirectory of the repo | `present` | — |
| 9 | branch has a staged (`A `) new learning | `present` | — |
| 10 | branch commit `learning: update <topic>` modifies an existing learning | `present` | hashes |
| 11 | fetch fails, branch has a COMMITTED new learning (no-crash + accepted miss) | `absent` | — |

Row 6 is a no-crash check (it cannot distinguish a fetch-gated from an ungated log; row 7 does).
Accepted misses, all in the safe direction (compound re-runs): a learning staged with
`git add -N` (` A`), a renamed learning committed under another prefix, a committed learning when
the fetch fails (row 11), a repo whose default branch is not `main` or has no
`origin` (the rest of ship already hardcodes `origin/main`). A shallow clone with no merge-base can
over-count (LOW; not built for).

### B. Regression test — `plugins/soleur/test/ship-learning-probe.test.ts` (new)

bun:test, modelled on `ship-pr-title-guard.test.ts` (reading SKILL.md) and
`ship-incident-pir-gate.test.ts` (fixture repos via `gitFixtureEnv`).

1. **Section extraction:** read `plugins/soleur/skills/ship/SKILL.md`; slice from the line starting
   `## Phase 2: Capture Learnings` to the next line starting `## ` (the scoping
   `workflow-fidelity.test.ts` uses). Assert the heading was found — a miss is a failure, not a skip.
   While scanning, skip heading detection INSIDE a fence (a `## ` comment line in the probe must
   not end the slice early).
2. **Exactly one fenced block of ANY kind in the section:** count lines matching
   `/^\s*(`{3,}|~{3,})/` (indented, tilde and four-backtick fences all count) and assert the count
   is exactly **2**, not "even". The extractor uses the same regex, and the extracted block must
   contain `BRANCH_LEARNING=` (H1 guard). Failure message: "ship Phase 2 must contain exactly one fenced
   block — the learning probe the agent runs. A second block can re-introduce a repo-wide probe the
   behavioural rows never execute (#8470). Put other snippets in another phase."
3. **Backstop text ban:** no fenced line in the section matches `/--(since|after|until|before)\b/`.
   Behaviour rows already catch these inside the one block; the ban exists for a block the test
   does not execute.
4. **Behaviour rows 1-11** (table above), one `test()` each. Each builds `origin.git` with
   `git init -q -b main --bare` and a work repo with `git init -q -b main` (pin the branch: the
   fixture env blanks `init.defaultBranch`), `git remote add origin ../origin.git` (not a hand-set
   `remote.origin.url`, or `git fetch origin main` updates only `FETCH_HEAD`), and
   `git push origin HEAD:refs/heads/main`. Row 6 removes the remote; rows 7 and 11 use
   `git remote set-url origin <nonexistent>` (row 7 after `update-ref`-ing a stale
   `refs/remotes/origin/main`). All git goes through `gitFixture(dir)` / `gitFixtureEnv(dir)` from
   `plugins/soleur/test/lib/git-fixture-env.ts`. Run
   `spawnSync("bash", ["--noprofile", "--norc", "-c", block], { cwd, env })` where `env` is
   `gitFixtureEnv(dir)` with `BASH_ENV`, `ENV`, `SHELLOPTS` and `BASHOPTS` deleted (the helper
   sweeps only `GIT_*`; `BASH_ENV` executes a file on every non-interactive bash and an exported
   `pipefail` changes the pipeline's status). Assert `stdout.trim()` **toBe** the expected token line
   and `status === 0`.
5. Temp dirs via `mkdtempSync(join(tmpdir(), "ship-learning-probe-"))`, removed in `afterAll`;
   export `TMPDIR=/var/tmp` locally.

### C. ADR-229 amendment (in this PR)

File: `knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-and-offline-classification.md`.

- `## Status`: → `Amended 2026-09-19 (#8325), 2026-09-21 (#8399) and 2026-09-22 (#8470).`
- One inline amendment appended to the #8399 ruling bullet, after the **Re-open trigger**
  sentences, in the ADR's existing `**[Amended …]**` style (architecture review — it CHANGES the
  trigger, so it must say so rather than read as a record):
  **[Amended 2026-09-22 (#8470): the fix is the PR that adds
  `plugins/soleur/test/ship-learning-probe.test.ts` (#8567). The re-measure's `SINCE` is that
  file's first first-parent commit on `main`:
  `git log --first-parent --diff-filter=A --reverse --format=%cI origin/main -- plugins/soleur/test/ship-learning-probe.test.ts | head -1`
  — `--first-parent` so a merge-commit landing reports the merge, not the earlier branch commit
  (which would admit pre-fix rows); `--reverse | head -1` survives a later delete and re-add. The
  trigger itself changes in one respect: an interactive **Skip** at ship Phase 2 also produces a
  class-D row, so a class-D row re-opens the gate question only after its session is checked for a
  Skip.]**
- `## Verification`: one bullet naming `plugins/soleur/test/ship-learning-probe.test.ts`.

**Decision — amend in this PR, not post-merge.** (1) The only merge-dependent value is the merge
time, and a command derives it exactly, so no date needs writing; (2) a post-merge ADR edit is a
second PR against protected `main` whose sole content is a date, and a guessed pre-merge date is
wrong whenever merge slips; (3) `wg-architecture-decision-is-a-plan-deliverable`. The residual
post-merge step is one `gh issue comment`, which the pipeline runs itself.

### D. Post-merge (after ship Phase 7 confirms MERGED — pipeline agent, not operator)

```bash
M=$(gh pr view 8567 --json mergedAt -q .mergedAt)
# jq, not GNU `date -d` (absent on macOS) — verified: 2026-09-22T10:00:00Z -> 2026-11-03
D=$(gh pr view 8567 --json mergedAt | jq -r '(.mergedAt|fromdateiso8601)+42*86400|strftime("%Y-%m-%d")')
gh issue comment 8470 --body "Fix landed in #8567 at ${M} (ship Phase 2 probe is now branch-scoped). Re-run the triage procedure in this issue's body with SINCE=\"${M}\" once >=5 full-pipeline review->ship rows exist, or on ${D} (six weeks), whichever comes first. Check each class-D row's session for an interactive Skip before re-opening the gate question. Close this issue only then. Recorded in ADR-229 (amended 2026-09-22)."
```

No closing keyword appears. **No follow-through sweeper enrollment:** ADR-229's Alternatives table
already rejects a sweeper probe for this measurement (the gitignored invocation log cannot exist on
a hosted runner), and a date-only sweeper probe would CLOSE #8470 on exit 0 without the re-measure.
If ship Phase 5.5's follow-through enrollment gate fires on this PR anyway, take its
operator-attestation override citing that Alternatives row.

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md` — `## Phase 2: Capture Learnings` body (§A), plus one clause in the `## Headless Mode Detection` Phase 2 bullet and one `## Important Rules` line (§A.2).
- `knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-and-offline-classification.md` — Status line, one sentence in the #8399 ruling bullet, one `## Verification` bullet (§C).

`plugins/soleur/test/workflow-fidelity.test.ts` is NOT edited: its comment "(ship Phase 2 has
three)" stays true (the draft keeps three compound calls).

## Files to Create

- `plugins/soleur/test/ship-learning-probe.test.ts` (§B).

## Non-Goals

- Moving Phase 2 prose to `references/` or `scripts/` (not needed: ~+1050 B within 11282 B headroom).
- Raising any ceiling in `plugins/soleur/test/skill-body-budget.json`.
- Changing the unarchived-artifact check or its placement (it still runs only on `absent`).
- Resolving a non-`main` default branch (ship hardcodes `origin/main` throughout).
- Any rule instrumentation, hook, or new write site (ADR-179 d4); no `pgrep -f`; no `git stash`.
- D-scope items: `ship → plan`, `postmerge → plan`, the in-ship `review` call, #8326.

## User-Brand Impact

- **If this lands broken, the user experiences:** a ship run that skips compound (no learning
  captured, plan/spec left unarchived — recoverable by a follow-up PR), or one that re-runs compound
  after it already captured a learning (a duplicate-learning prompt and extra tokens). Both are
  bounded to the operator's own session; no product surface is touched.
- **If this leaks, the user's workflow is exposed via:** nothing new — the probe reads the local
  repository's own git log and status and fetches `origin main`, which ship already does; no new
  credential, no new output surface.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff is skill prose, one ADR sentence and a hermetic test; no user data, auth, schema or runtime path is touched.`

## Guard Contract

### Guard 1 — ship Phase 2 branch-scoped learning probe test

**Property.** Ship Phase 2's probe prints `BRANCH_LEARNING=present` if and only if the current
branch captured a learning — an uncommitted or staged add under `knowledge-base/project/learnings/`,
or, read after a successful fetch, a commit in `origin/main..HEAD` that adds such a file or whose
subject starts `compound:`/`learning:` — and `absent` otherwise.

**Assembly.** One chokepoint: the only fenced block inside the slice of
`plugins/soleur/skills/ship/SKILL.md` from the line starting `## Phase 2: Capture Learnings` to the
next line starting `## `. The agent executes that block; the test extracts and executes exactly it
(behaviour) and bans any second fenced block of any language (population), with a text backstop
on range-by-date flags in any fence. The token's consumer (the `present`/`absent` lead-ins) and the
compound call it leads to live in the same slice; the call is pinned by `workflow-fidelity.test.ts`.

**Mutation matrix** (write the suite first; run each against a temporary edit of the tracked
SKILL.md, restored with `git checkout -- plugins/soleur/skills/ship/SKILL.md`):

| # | Mutation | Expected |
|---|---|---|
| 1 | The pre-fix SKILL.md (old `--since="1 week ago"` block) | RED (rows get hashes or empty, not the token; text ban) |
| 2 | Drop the `git status --porcelain` arm | RED (rows 2, 8) |
| 3 | Drop `--diff-filter=A` | RED (row 4) |
| 4 | Un-gate the log from the fetch (`git fetch … \|\| true;` then the log) | RED (row 7) |
| 5 | Drop the `:/` pathspec magic | RED (row 8) |
| 6 | Append a second fence (tagged `sh`, untagged, `~~~`, or indented under a list item) holding a repo-wide probe after the compliant block | RED (exactly-one-fence) |
| 7 | Rename the heading (dispatch: the slice resolves to nothing) | RED (heading-found assertion) |
| 8 | Drop `\|A` from the porcelain pattern | RED (row 9) |
| 9 | Drop the commit-subject arm | RED (row 10) |

**Harness rows:**

| # | Edit to the SUITE or input | Expected |
|---|---|---|
| H1 | Break the extractor so it returns `""` | RED (every row: `bash -c ""` prints no token) |
| H2 | Must-PASS non-canonical SKILL.md: committed arm rewritten as `git diff --name-only --diff-filter=A origin/main...HEAD -- ':/knowledge-base/project/learnings/'` (still fetch-gated) | GREEN — the suite pins behaviour, not bytes |

**Anchor.** The expected-verdict table and the SKILL.md block can change in one diff, so the suite
proves consistency, not integrity. What sits outside the commit: #8470's body names the fixture
cases (committed / uncommitted / none), and ADR-229's Verification names the suite, so weakening
it also edits an ADR a reviewer reads. Accepted for a skill-prose guard.

## Observability

Plan Phase 2.9's path list does not name `plugins/*/skills/`, but deepen-plan Phase 4.7 exempts
only `.md` files OUTSIDE `plugins/*/skills/`, so this change is in scope and declares the block.
The surface is agent-executed skill prose on the operator's own machine (observability layer 7):
there is no server, cron or network sink.

```yaml
liveness_signal:
  what: the probe's one output line, BRANCH_LEARNING=present or BRANCH_LEARNING=absent, printed in the ship session transcript
  cadence: once per ship run, at Phase 2
  alert_target: none; the operator-visible session output is the surface, and the longitudinal read is the #8470 triage
  configured_in: plugins/soleur/skills/ship/SKILL.md, section Phase 2 Capture Learnings
error_reporting:
  destination: stderr of the ship session; git errors inside the probe are deliberately swallowed and resolve to absent
  fail_loud: false by design; every failure path routes to running compound, the recoverable direction, and the suite pins each path (rows 6 and 7)
failure_modes:
  - mode: probe regresses to a repo-wide or date-window form
    detection: plugins/soleur/test/ship-learning-probe.test.ts rows 1-11 and the fenced range-flag ban, in the bun test shard of CI
    alert_route: red required CI check on the PR
  - mode: compound skipped on a branch with no learning, in real sessions
    detection: the #8470 triage procedure over .claude/.skill-invocations.jsonl, class D rows with SINCE at the fix merge
    alert_route: the post-merge comment on #8470 carries the re-run rule and date; ADR-229 records it
  - mode: compound re-run after it already captured (false absent)
    detection: a duplicate-learning prompt in the session; accepted, safe-direction cost
    alert_route: none required
logs:
  where: the skill invocation log .claude/.skill-invocations.jsonl (local, gitignored) and the session transcript
  retention: local, rotated by the existing log-rotation hook
discoverability_test:
  command: grep -o -m1 -e BRANCH_LEARNING=absent plugins/soleur/skills/ship/SKILL.md
  expected_output: "BRANCH_LEARNING=absent"
```

Verified against the drafted section (2026-09-22): the command prints exactly
`BRANCH_LEARNING=absent`; its first token `grep` is on Check 10's allowlist; it carries no
`| ; & < > $` or backtick and finishes in milliseconds.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-229 (§C) — an extension of its 2026-09-21 ruling (arming the re-open trigger against the
fixing PR). No new ADR; no ordinal to reserve.

### C4 views

No C4 change. Checked in `knowledge-base/engineering/architecture/diagrams/model.c4`: the `ship`
component ("Validates artifacts, creates PR, manages merge lifecycle") and the `compound` component
("Captures learnings and promotes to constitution") keep their roles; no external human actor,
external system/vendor, container or data store is added; no actor↔surface access relationship
changes (the probe reads the local repo and fetches the existing `origin`). `views.c4` and
`spec.c4` carry no element this touches. The work phase runs
`bash plugins/soleur/test/c4-count-parity.test.sh` to back the conclusion.

### Sequencing

The amendment ships with the fix; the re-measure it describes happens after merge (§D).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal workflow-skill tooling change (one skill section,
one ADR sentence, one test). No UI-surface path in Files to Edit/Create, so the Product/UX gate
does not run.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 max) searched for
`plugins/soleur/skills/ship/SKILL.md`, `ADR-229`, `workflow-fidelity.test.ts`,
`ship-learning-probe`, `Capture Learnings`: zero matches.

## Plan Review Revisions (2026-09-22)

Panel: DHH, Kieran, code-simplicity, CTO (devex), plus the Step 4.5 advisor consult. All applied
findings are Mechanical (correctness or simplification of plan-introduced machinery); none drops
operator-requested scope, so nothing is persisted to `decision-challenges.md`.

- **Fetch gating (CTO P-high, Kieran P2):** `|| true` on the fetch contradicted Phase 1.5's own
  rule and could re-create the defect via a stale `origin/main` (measured `present` in that case).
  The committed arm now runs only after a successful fetch; row 7 pins it; fixtures use a real
  local bare remote.
- **Subdirectory cwd (Kieran P2):** `:/` pathspec on both commands; row 8.
- **Text pins vs H4 (DHH P1, Kieran P1):** literal pins removed; the suite pins behaviour.
- **Exactly-one-fence counts every fence (Kieran P2)**; ban widened to
  `--(since|after|until|before)` (Kieran P2); failure message explains the rule (CTO).
- **Row 4 is a COMMITTED modification (Kieran P2)**; accepted misses stated (Kieran P2, CTO).
- **Cut:** the `SHIP_LEARNING_PROBE_SKILL` env override and the row-count floor (DHH, simplicity);
  mutation matrix trimmed from 9+4 to 7+2 rows; ADR "Armed" paragraph shrunk to one sentence.
- **ADR key (CTO):** `SINCE` derived from the test file's first commit on `main`, not only the PR
  number; interactive Skip named as a class-D confounder (CTO).
- **Not taken:** move the probe to a script (advisor) — see Reconciliation; drop the fetch entirely
  (DHH, simplicity) — superseded by the fetch-gating fix; drop the fenced text ban (simplicity) —
  kept only as a backstop for a block the suite does not execute.

## Deepen-Plan Revisions (2026-09-22)

Agents: test-design-reviewer, architecture-strategist; halts 4.6/4.7/4.8/4.9/4.10/4.11 run.

- **Observability (Phase 4.7 halt):** Phase 4.7 exempts `.md` only OUTSIDE `plugins/*/skills/`, so
  the plan's earlier "not triggered" was wrong; the 5-field block is now declared with a verified
  Check 10-compatible probe.
- **Double compound in one-shot (architecture):** added the `compound:`/`learning:` commit-subject
  arm (rows 10), since one-shot runs compound before ship and compound may only update or archive.
- **SINCE key (architecture):** `--first-parent --reverse | head -1`; the ADR text now uses the
  `**[Amended …]**` style and states the Skip exemption as a trigger change.
- **Consistency (architecture):** §A.2 fixes the Headless Mode Detection bullet and the Important
  Rules line that contradicted Phase 2.
- **Fence counting, branch pinning, shell hermeticity, rows 9/11, slice robustness (test-design).**
- **Not taken:** a copy-based mutation harness with a path env var (test-design) — the battery is a
  one-time, single-worktree run; the reviewers earlier cut that seam as permanent machinery for a
  one-off exercise.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.
- **Keep time-gated follow-through vocabulary out of the PR body.** Ship Phase 5.5's follow-through
  enrollment gate reads the PR body AND this plan, extracts `Ref #8470`, and would demand sweeper
  enrollment for a tracker ADR-229 already ruled unenrollable. If it fires, use the override (§D);
  never enroll a date probe that would auto-close #8470.
- The exactly-one-fence rule makes Phase 2 a one-snippet section by design; future Phase 2 snippets
  belong elsewhere or need the suite's extractor re-scoped in the same PR.
- `workflow-fidelity.test.ts`'s anchor test is textual; the rewrite must keep a real
  `skill: soleur:compound` call inside the section, not only a mention.
- Run the mutation battery by editing the tracked SKILL.md and restoring it with
  `git checkout --` — never `git stash` (worktree rule).
- PR body: `Ref #8470`. Never `Closes`/`Fixes`/`Resolves` #8470, in title or body.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 — `bun test plugins/soleur/test/ship-learning-probe.test.ts` passes: rows 1-11, the
  exactly-one-fence check and the fenced range-flag ban, against the edited SKILL.md.
- [x] AC2 — the same suite is RED against the pre-fix SKILL.md (written first, per
  `cq-write-failing-tests-before`) and against mutations 2-9; H2 is GREEN. Outcomes recorded in the
  PR body as a table.
- [x] AC3 — the `learnings/**/*FEATURE*` Glob instruction is gone from Phase 2:
  `awk '/^## Phase 2: Capture Learnings/{p=1;next} /^## /{p=0} p' plugins/soleur/skills/ship/SKILL.md | grep -c 'learnings/\*\*/\*FEATURE\*'` prints `0`.
- [x] AC4 — `bun test plugins/soleur/test/workflow-fidelity.test.ts` green.
- [x] AC4b — §A.2 applied: `grep -c 'when the Phase 2 probe prints' plugins/soleur/skills/ship/SKILL.md` prints `1`, and `grep -c 'Ask before running soleur:compound' plugins/soleur/skills/ship/SKILL.md` prints `0`.
- [x] AC5 — `python3 scripts/lint-skill-body-budget.py --base origin/main` → OK, and
  `git diff --quiet origin/main -- plugins/soleur/test/skill-body-budget.json` exits 0.
- [x] AC6 — ADR-229's Status line names `2026-09-22 (#8470)`; the #8399 ruling bullet carries the
  "Armed 2026-09-22 (#8470)" sentence with the `git log --diff-filter=A` key and the Skip clause;
  `## Verification` names `ship-learning-probe.test.ts`.
- [x] AC7 — `bash plugins/soleur/test/c4-count-parity.test.sh` and
  `bash plugins/soleur/test/fixture-env-adoption.test.sh` green.
- [ ] AC8 — the PR body contains `Ref #8470` and
  `gh pr view 8567 --json title,body -q '.title+" "+.body' | grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #8470'` prints `0`.
- [x] AC9 — `git diff origin/main -- plugins/ | grep -c SOLEUR_RULE_APPLIED` prints `0`, and
  `git diff --name-only origin/main` lists no `rule-metrics.json`.

### Post-merge (pipeline, not operator)

- [ ] AC10 — `gh issue view 8470 --json state -q .state` prints `OPEN`.
- [ ] AC11 — the §D comment is on #8470 with the resolved `mergedAt`, the six-week date and the
  `SINCE` value.

## Test Scenarios

1. Fixture rows 1-11 (table in §A): exact token line, exit 0.
2. Pre-fix SKILL.md → suite RED (the #8470 regression).
3. Mutations 2-9 → RED; H2 → GREEN.
4. `workflow-fidelity.test.ts` sub-step anchor — still green.
