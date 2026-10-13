---
title: "feat: mattpocock/skills audit bundle B4/B10/B12b (brainstorm dialogue discipline, compound null-guardrail finding, help composition map)"
type: feat
date: 2026-09-23
slug: feat-mattpocock-audit-b4-b10-b12b-bundle
branch: feat-one-shot-mattpocock-b4-b10-b12b
issue: none
closes: none
refs: [8284, 8648]
priority: p3-low
domain: product
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Ship the three mattpocock/skills audit improvements that the audit record's reconciliation table
lists as unfiled: B4 (brainstorm Phase 1.2 dialogue discipline), B10 (compound Deviation Analyst
null-guardrail finding) and the second half of B12 (a skill-composition map in the help command).
Founder decision 2026-09-23. Small prose-only edits to four plugin files: the three targets plus one
alignment line in `brainstorm-techniques`.

## Enhancement Summary

**Deepened on:** 2026-09-23.

**Passes run:**
- the halt gates: 4.6 user-brand, 4.7 observability (the probe verb was checked with
  `probe-verb-gate.sh`, rc 0), 4.8 PAT (0 hits), and 4.9, 4.10 and 4.11 (not triggered);
- Phase 4.45 self-audit and verify-the-negative, on the standard tier;
- spec-flow-analyzer;
- pattern-recognition-specialist.

The fan-out was kept proportionate to a four-file prose change, not the full agent roster.

### Key Improvements

1. **B4 gains the missing states:**
   - headless or pipeline brainstorm asks nothing, closing what a lookup can answer and parking
     the rest;
   - pending lookups are collected before exit, and a failed one parks its branch;
   - an out-of-scope branch is parked as soon as it opens.
2. **B10 is scoped to code and config defects a repo check could catch.** Workflow missteps no
   longer turn every run into a `none` proposal.
3. **One guard proposal per item** across step 3.6, step 4 and Error-to-Workflow Feedback.
4. **Constitution Promotion is edited so the headless "never auto-apply" rule holds.** Without the
   two edits, its headless auto-accept would contradict it, and its interactive gate would never
   show a finding from a run with no deviations.
5. **The help map is robust to rendering:**
   - blank lines around it (AC4's extract needs the trailing one);
   - an 83-character on-ramp line;
   - a Codex verbatim-render note.

### New Considerations Discovered

- The brainstorm prose says "user". The new text follows it; "founder" stays in Why-notes only.
- Compound's Constitution Promotion headless path auto-accepts hook proposals
  (`compound/SKILL.md:392`), so any new proposal class needs an explicit carve-out there.

## Research Insights

**Premise Validation.** Cited references checked at plan time:
- `#8648` is OPEN ("WIP: feat-one-shot-mattpocock-audit-record-founder-decisions"). It owns
  `knowledge-base/product/competitive-intelligence.md`, so this plan does not edit that file.
- `#8284` is the MERGED audit-record PR. It is the source of the B-row definitions.
- The audit record's reconciliation table lists B4 and B10 as "Not bundled — remains advisory". It
  lists B12 as shipped only in part: the context tree landed, the `go`/`help` flow map did not.
  The B4, B10 and B12 rows in `competitive-intelligence.md` hold the exact source wording.
- The targets exist on `origin/main`, and none has drifted since this branch was cut. The
  `git diff HEAD origin/main` over the target directories is empty, and `origin/main` is one
  unrelated commit ahead. The targets are `brainstorm/SKILL.md` `#### 1.2 Collaborative Dialogue`,
  `compound/SKILL.md` `## Phase 1.5: Deviation Analyst (Sequential)`, and `commands/help.md`
  (three harness blocks).
- The audit record names `plugins/soleur/skills/help/SKILL.md` for B12. That file is a Devin shim
  that reads `commands/help.md`, so `commands/help.md` is the right target. This matches the
  invocation.
- Checked with `git grep`, these concepts are absent today: `frontier`, `null-guardrail`,
  `no guardrail` and `on-ramp` in the three targets. The only `frontier` hit is an unrelated
  roadmap line.

**Eval gate (the constraint asked for this to be identified).** The command below is the gate's
own lookup. It makes no API call. Each of the four files it checks returns
`{"gated":false,"target":null,"block_id":null}`.

```bash
node plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs --check <file>
```

`gated-skills.json` has four entries: `go.md` go-routing, `ticket-triage.md`,
`brainstorm/references/brainstorm-domain-config.md` lane-inference (a reference file, not
`SKILL.md`), and `incident/SKILL.md`. None covers these edits. `go.md` stays untouched. The work
phase re-runs `--check` after editing (AC6), so an edit that moves a gated block would be caught.

**Tests and lints that read the targets (run by `soleur:work`):**
- `plugins/soleur/test/components.test.ts`, test "help.md carries the operator-* family in each
  harness block". It splits `help.md` on `^### ` and needs each of `Claude Code`, `Devin CLI` and
  `Grok Build` to name `operator-*`. Put the map inside the fenced text blocks and add no new
  `### ` heading ahead of them.
- `plugins/soleur/test/invocation-axis.test.ts` and `harness-parity.test.ts`. `help.md` is
  excluded by path. `brainstorm`/`compound` `SKILL.md` are scanned, so the new prose names no
  `soleur:<name>` of a user-invoked skill. The eight such skills: admin-ip-refresh, cf-token-scope,
  flag-delete, provision-cloudflare, provision-doppler, provision-github, provision-hetzner,
  user-set-role.
- `plugins/soleur/test/workflow-fidelity.test.ts`. It pins the anti-bypass sentinel and
  `BRAINSTORM_CHILD_SKILLS` in brainstorm, and `LIFECYCLE_HANDOFF_SENTINEL` in compound. None of
  these sit in the edited regions.
- `scripts/lint-agents-compound-sync.sh`. It anchors on compound step 8 (the
  `<!-- rule-threshold: 115 -->` sentinel and the per-rule-cap phrase). The B10 edit touches:
  - steps 3.6, 4, 5 and 7, and `### Empty Case`;
  - one clause in `### Error-to-Workflow Feedback`;
  - two clauses in `### Constitution Promotion`.

  It never touches step 8. The deepen self-audit confirmed this against
  `lint-agents-compound-sync.sh`: its sentinel is at step 8, `compound/SKILL.md:297`.
- `bash scripts/markdown-lint.sh <files>` (the lefthook `*.md` hook). The baseline is clean on all
  four targets (`4 file(s) clean`).

**Precedent.** `test-fix-loop/SKILL.md` `### Detect Test Runner` picks a single test command,
first match wins. B10 needs every lint, typecheck and test command, so it borrows the list of
sources (manifests, `Makefile`/`Justfile`), not the first-match order. `go.md` step 5 gives the canonical
lifecycle: plan → work → review → qa (UI gate) → compound → ship, with postmerge after ship.
`drain-labeled-backlog` delegates to `soleur:one-shot`. `drain-prs` takes open PRs through
`soleur:review`. `product-roadmap` `next` routes to `soleur:go`.

**A sibling copy of the fuzzy exit rule.** `git grep 'Continue until the idea is clear' -- plugins`
finds three copies: `brainstorm/SKILL.md` §1.2 (in scope), `brainstorm-techniques/SKILL.md`
`**Exit Condition:**`, and `plan/SKILL.md` §0.5. Brainstorm §1.2 says "see `brainstorm-techniques`
skill for detailed techniques", so leaving that copy fuzzy would contradict the new rule. The plan
aligns that one line. `plan` §0.5 is left alone: it is the short pre-research refinement loop,
skipped whenever a brainstorm exists, and it is not B4's named target.

**Functional overlap.** The functional-discovery check installed nothing. Beyond the audited
`mattpocock/skills` (`grilling`, `retro`, `ask-matt`), nothing overlaps materially.

**Applicable learnings:**
- `knowledge-base/project/learnings/best-practices/2026-04-19-markdownlint-fix-mangles-issue-ref-at-line-start.md`.
  Never start a prose line with `#NNNN`.
- `knowledge-base/project/learnings/2026-07-06-ac-self-reference-grep-trap-and-verify-config-enabled-state.md`.
  An absence-grep ACs must not match the new text's own wording. The ACs below assert the presence
  of the new anchors.

**Property List:**
- P1: A brainstorm ends because every open decision branch was walked or explicitly parked, not
  because the founder got tired. Nothing is silently assumed.
- P2: Questions are asked in dependency order, still one at a time.
- P3: The founder is never asked a fact the agent can look up, and a lookup never holds up the
  questions that do not depend on it.
- P4: For every recurring failure class the session hit, compound checks whether any existing
  pre-commit hook, CI check or lint rule would have caught it. If none would, compound reports a
  null-guardrail finding, even when no hard rule was broken.
- P5: If a check exists but is not wired in, the finding says "wire it in". Compound does not
  reinvent the check.
- P6: `/soleur:help` shows how the skills compose: the main flow, the on-ramps, and what is
  standalone.

**Advisor consult (Step 4.5).**
- Applied: `covered` counts only when the check runs on the paths where the failure happened.
  Monorepo path filters and globs therefore matter.
- Also proposed: an `unknown` outcome and caching the repo-level scan. Plan review later cut both
  (see below).
- Kept: `brainstorm-techniques` gets a copied one-sentence rule rather than a pointer, because that
  skill is also loaded on its own. AC1 pins both copies to the same anchor, `explicitly parked`.

**Plan review (DHH, Kieran, code-simplicity, CTO devex). Applied:**
- **The repo-level finding is cut.** It would report "no hook or CI runs the check command" on
  every run, even with no session errors.
  - DHH (simplify) and CTO (correctness) both flagged it. DHH said it is a repo linter, not a
    retrospective. CTO said it repeats forever in a repo with no CI by choice.
  - When both panels fire on the same scope, the review rule is to delete.
  - It was also not in the operator's wording, which says "for the failure class".
  - Deleting it also dissolves the two-finding cap and the caching proposal.
- **`unknown` is cut.** Uncertainty now resolves to `unwired`, which proposes running the check on
  those paths (DHH and simplicity).
- **The count of open decisions is cut.** DHH and simplicity found that it serves no property, and
  that it can mislead because answers open new branches. The CPO suggestion is recorded in
  `decision-challenges.md`.
- **Reuse the existing Deviation template.** No second step-5 template (DHH and simplicity).
- **Bounded discovery.** Collect all the check commands, not the first one found. Pre-commit
  config counts both as a check and as what runs it. Search hook and CI files with `grep -l`
  rather than reading whole directories, and follow one wrapper level (CTO). The wrong
  "test-fix-loop order" claim and its link are removed (CTO and Kieran).
- **Kieran's fixes:**
  - Step 3.6's lead line is followed by a blank line and non-indented bullets. The indented form
    fails MD007/MD032.
  - Step 3.6 covers only items triaged `recurring`. It annotates an existing proposal (from
    Error-to-Workflow Feedback or step 4) rather than adding a second one.
  - Null-guardrail findings are never applied automatically in headless mode.
  - Step 3.6 does the `.claude/hooks` scan, and step 4 reuses it.
  - The map now says `go` defaults to brainstorm and sends fixes and scoped builds to `one-shot`.
    It adds `postmerge`, says "most other skills", and drops the `operator-*` token. That token
    would have satisfied the per-block `components.test.ts` assertion even if the real SKILLS line
    were deleted.
  - Each AC1 anchor is checked on its own.
- **AC trims:** the parked-rule check for `brainstorm-techniques` is merged into AC1. The
  `plan/SKILL.md` and `go.md`/eval-harness diff checks are consolidated into the scope AC, AC5
  (DHH and simplicity).

**Plan review, not applied (recorded in `decision-challenges.md`):**
- Simplicity proposed moving P5 into Phase 0.5's recurring triage instead of adding a Phase 1.5
  step. That would move the edit away from where the operator named it: the compound Deviation
  Analyst, Phase 1.5.
- Simplicity proposed a single shared map section instead of three byte-identical copies. The
  harness blocks are literal output templates, so a shared section risks being left out when the
  help text is rendered.
- CTO proposed a durable parity test in `components.test.ts` and a note on who maintains the map.
  That is new test infrastructure, and the Cut List keeps it out of scope.

**Cut List:**
- "Frontier per round, numbered, each with a recommended answer" (the `grilling` batching). It buys
  nothing in the list, and the audit explicitly rejects it: one question at a time is kept for the
  non-technical ICP, and `AskUserQuestion` caps at 4 options.
- The "tool economy" and "information access" retro categories. The invocation puts them out of
  scope, and no property needs them.
- The `PHASE-BOUNDARIES` 5-option tree (the first half of B12). It already shipped in
  `brainstorm-techniques/references/phase-boundaries.md`.
- A flow map in `go.md`. `go.md` holds the eval-gated routing table, and P6 needs only the listing
  surface.
- A new test asserting the map. AC4's parity check covers it during work and review; no CI check
  pins the three copies byte-identical (the per-block `components.test.ts` assertion checks only
  `operator-*`). Accepted per decision-challenge T5.
- The repo-level finding, `unknown`, the two-finding cap, the second template and the
  open-decision count. See "Plan review, applied" above.

## Files to Edit

- `plugins/soleur/skills/brainstorm/SKILL.md`: `#### 1.2 Collaborative Dialogue` only (B4).
- `plugins/soleur/skills/brainstorm-techniques/SKILL.md`: the `**Exit Condition:**` line under
  `### Phase 1: Understand the Idea` only (B4 alignment, see Research Insights).
- `plugins/soleur/skills/compound/SKILL.md` (B10):
  - `## Phase 1.5: Deviation Analyst (Sequential)`: steps 3.6 (new), 4, 5 and 7, plus
    `### Empty Case`;
  - one clause in `### Error-to-Workflow Feedback`;
  - two clauses in `### Constitution Promotion`.

  Step 8 is not touched.
- `plugins/soleur/commands/help.md` (B12b):
  - the `### Claude Code`, `### Devin CLI` and `### Grok Build` fenced blocks;
  - one sentence on the Codex bullet in `## Step 2.5`.

**Must not change:** any `description:` frontmatter line, `plugins/soleur/commands/go.md`,
`knowledge-base/product/competitive-intelligence.md` (owned by `#8648`), and
`plugins/soleur/skills/plan/SKILL.md`.

## Files to Create

None.

## Implementation

Each edit is plain prose. The wording below is the target, so work may tighten it but should keep
every clause.

### 1. B4: brainstorm §1.2 dialogue discipline

Keep the `**one at a time**` sentence and the `**Guidelines**` bullets exactly as they are. Replace
the single line `**Exit condition:** Continue until the idea is clear OR user says "proceed"` with
the text below.

The file's instruction prose says "user", not "founder", so the new text does too. The leads end
in a colon like `**Guidelines (...):**`.

```markdown
**Dialogue discipline:** This orders and ends the dialogue. It never batches it: still one question per turn.

- **Keep a list of open decision branches.** Seed it from the feature description and the Phase 1.1 research. Each answer can close a branch or open new ones. If a branch falls outside the feature's stated scope, park it as soon as it opens instead of walking it.
- **Ask in dependency order.** Before asking, check whether the answer depends on another decision that is still open. If it does, ask that upstream decision first. A downstream question waits until the question it depends on is answered.
- **Look facts up; do not ask them.** If the agent can find a fact (codebase, knowledge base, live docs, a pricing page), it is never a question for the user. Run the lookup in the background (a Task agent or a parallel tool call) and keep asking the questions that do not depend on it. Only the questions downstream of the pending fact wait for it. Before leaving this phase, including on "proceed", collect any pending lookups. A returned fact closes the branches it answers. A failed lookup parks its branch.
- **Headless:** In pipeline or headless mode (the predicate in Phase 0.4 Lane Auto-Detect), ask nothing. Resolve every branch a lookup can answer and park the rest.

**Exit condition:** The dialogue is done when every open decision branch has been walked (answered) or explicitly parked (the user deferred it, or it needs information nobody has yet). Nothing is silently assumed. Record parked branches in the brainstorm document's Open Questions section (Phase 3.5). If the user says "proceed" first, stop asking and record every unwalked branch there as parked.
```

In `brainstorm-techniques/SKILL.md`, replace
`**Exit Condition:** Continue until the idea is clear OR user says "proceed" or "let's move on"`
with:

```markdown
**Exit Condition:** Done when every open decision branch has been walked or explicitly parked (deferred and recorded as an open question), with nothing silently assumed. If the user says "proceed" or "let's move on" first, stop asking and record the unwalked branches as parked.
```

### 2. B10: compound Deviation Analyst null-guardrail finding

Insert a new step **3.6** after step 3.5 (`**Ingest recent hook incidents.**`) and before step 4.
Match step 3.5's shape. The `3.6.` lead is a paragraph, followed by a blank line and then
**flat, non-indented** bullets. The indented form fails markdownlint MD007/MD032, which Kieran
confirmed by simulating it. Class labels use Phase 0.5's `**label**` style.

```markdown
3.6. **Null-guardrail check.** A deviation scan only sees broken rules, so a failure class with no guard at all never shows up in it. Check for it directly. Scope:

- each Phase 0.5 inventory item triaged `recurring` that is a code or config defect a repo check could catch in principle (lint, typecheck, test, format);
- each deviation from step 3.

Workflow missteps that no repo check can catch stay with step 4 and Error-to-Workflow Feedback. If the scope is empty, skip this step.

- **Read the repo's own check commands first.** Collect every lint, typecheck and test command, not just the first one found. Look in `package.json` `scripts`, `Makefile`/`Justfile` targets, language manifests (`pyproject.toml`, `Cargo.toml`, `go.mod`), and pre-commit config (`lefthook.yml`, `.husky/`, `.pre-commit-config.yaml`). Pre-commit config is both a check and the thing that runs it. Then find what runs each command: `grep -l` the command name over the CI config (`.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`) and `.claude/hooks/`. Read only the files that match, never a whole directory. A missing directory counts as absent, not as an error. Follow one level of wrapper, such as a `make ci` that calls `lint`. Step 4 reuses this `.claude/hooks` result.
- **Classify each item** as one of:
  - **covered**: an existing hook, CI check or lint rule runs on the paths where the failure happened. Name it.
  - **unwired**: a check exists but nothing runs it on those paths. This includes a CI job whose path filter skips them. When unsure, choose this.
  - **none**: no guardrail at all for this failure class.
- **Propose without duplicating.** An **unwired** item proposes wiring the existing check in, never a second guard. A **none** item proposes the smallest guard that would have caught the class, following step 4's hierarchy. Each item gets at most one guard proposal. If Error-to-Workflow Feedback or step 4 already proposed one, annotate that proposal with the classification instead of adding another.
- **Headless.** Never apply a null-guardrail proposal automatically. When `HEADLESS_MODE=true`, record it in the learning's `## Session Errors` only.
```

Then make these small edits. Each one anchors on existing text.

- **Step 4.** Also skip the proposal when step 3.6 classified the item **covered**, and note the
  check that covers it. Reuse step 3.6's `.claude/hooks` scan when it ran, instead of repeating it.
- **Step 5.** Report a step-3.6 finding that is not already attached to a deviation with the
  **existing** Deviation template:
  - `Rule violated: none (null guardrail)`
  - `Existing enforcement: unwired: <check> | none`
  - `Proposed enforcement`: the wiring step, or the smallest new guard.

  Add no second template.
- **Step 7.** Change `Present each deviation to the user via` to
  `Present each deviation and each unwired or none finding to the user via`.
  Step 6 is unchanged, because Phase 0.5 items already reach `## Session Errors`.
- **`### Error-to-Workflow Feedback`.** Add this to the end of its "If yes" bullet:
  `If step 3.6 already classified this item, annotate that proposal instead of adding a second.`
- **`### Constitution Promotion`.**
  - At the end of the `**Headless mode:**` paragraph, add:
    `Never auto-accept a null-guardrail finding (Rule violated: none (null guardrail)).`
  - In `**1. Deviation Analyst proposals (if any):**`, change
    `If Phase 1.5 produced deviations` to `If Phase 1.5 produced deviations or step-3.6 findings`.
  - Without these two edits, the headless path auto-accepts the proposal that step 3.6 forbids,
    and the interactive path never shows a finding from a run with no deviations.
- **`### Empty Case`.** Change the opening condition to "If step 3 finds no deviations and
  step 3.6 finds no unwired or none item". Keep the rest of the sentence.

**Work-phase amendment (byte ceiling).** `compound/SKILL.md` is a lifecycle skill under the
`skill-body-budget.json` ceiling (57000 bytes, anchored to the merge base by
`scripts/lint-skill-body-budget.py`, ADR-229). The wording above measured 58100 bytes, 1100 over.
Work compressed step 3.6 into a lead paragraph plus three bullets. It folded the step-5 template
note into step 3.6's last bullet ("Report it with step 5's template as `Rule violated: none (null
guardrail)`") and shortened the step-4, Error-to-Workflow and headless clauses. Every clause and AC
anchor is kept, and the result is 56839 bytes. The ceiling was not raised.

**Review-round amendment.** The compression above dropped the "not already attached to a
deviation" condition while step 3.6's scope still took in step-3 deviations, which four review
seats traced to a double proposal and a wrong `Rule violated` label. Review narrowed step 3.6 to
Phase 0.5 recurring code/config items only, reverted step 4 to its original text, and put the
`Existing enforcement: unwired: <check>` or `none` field back into step 3.6's report clause. Step 5
itself is not edited: the template note lives in step 3.6. The file is 56815 bytes.

### 3. B12b: help composition map

In each of the three harness blocks, add this section inside the fenced `text` block, between the
`WORKFLOW SKILLS` list and `AGENTS:`. Put one blank line before the map and one after it, and no
blank line inside it. The text must be byte-identical in all three blocks.

Skill names are bare, as `WORKFLOW SKILLS` already renders them. Do not write the `operator-*`
token here: it would satisfy the per-block `components.test.ts` assertion even if the real SKILLS
line were deleted.

```text
HOW THE SKILLS FIT TOGETHER:
  Main flow:   go -> brainstorm -> plan -> work -> review -> ship -> postmerge
               (go starts at brainstorm by default; qa for UI changes and
               compound for learnings run between review and ship)
  On-ramps:    one-shot              go sends fixes and scoped builds; plan to ship
               drain-labeled-backlog runs one-shot over a labeled issue backlog
               drain-prs             takes open PRs through review to merge
               product-roadmap       its "next" step says where to enter the flow
  Standalone:  most other skills run on their own, for example the legal, flag,
               cron and operator families, incident, invoice and community
```

In `## Step 2.5`, append this sentence to the **Codex** bullet:
`Render the HOW THE SKILLS FIT TOGETHER map verbatim.`
Without it, Codex's skill-mention substitution could rewrite `go` or `one-shot` inside the map
and break its alignment.

Add no `### ` heading. The `components.test.ts` per-block split depends on the three existing ones.

## User-Brand Impact

- **If this lands broken, the user experiences:** a brainstorm that ends too early and loses
  decisions, or one that keeps asking and never ends. Or compound suggests a duplicate hook when
  one already exists. Or `/soleur:help` shows a wrong map that sends the founder to the wrong skill.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new. The changes
  are instruction prose only. Step 3.6 reads the founder's own repo config files, as compound
  already does, and adds no network or third-party data path.
- **Brand-survival threshold:** `none`

## Observability

These are prose instructions, so no runtime process, server or cron is added. The signal is the
instruction text itself, together with the existing CI suites that read it.

```yaml
liveness_signal:
  what: the B10 step-3.6 anchor is present in the distributed compound SKILL.md
  cadence: every PR (the existing bun test and markdown-lint CI jobs read these files)
  alert_target: a red required CI check on the PR
  configured_in: .github/workflows (existing test and markdown-lint jobs); no new config
error_reporting:
  destination: CI check output on the PR
  fail_loud: true
failure_modes:
  - mode: the help map drifts between the three harness blocks
    detection: the AC4 cmp parity command (run during work and review; no CI check pins it)
    alert_route: a red AC during soleur:work and review
  - mode: the compound edit moves the step-8 rule-threshold sentinel
    detection: scripts/lint-agents-compound-sync.sh
    alert_route: a red pre-commit hook and CI
logs:
  where: CI job logs for the PR
  retention: the GitHub Actions default
discoverability_test:
  command: grep -c -e 'Null-guardrail check' plugins/soleur/skills/compound/SKILL.md
  expected_output: "1"
```

## Acceptance Criteria

Set these variables:

```bash
F_B=plugins/soleur/skills/brainstorm/SKILL.md
F_T=plugins/soleur/skills/brainstorm-techniques/SKILL.md
F_C=plugins/soleur/skills/compound/SKILL.md
F_H=plugins/soleur/commands/help.md
```

Check each anchor with its own `grep -F` (line counts merge anchors that share a line). Run the
checks outside `set -e`.

- [x] **AC1 (B4).**
  - In the §1.2 body, `awk '/^#### 1\.2 Collaborative Dialogue/{f=1;next} /^### Phase 2:/{f=0} f' "$F_B"`,
    each of these anchors matches at least once: `**one at a time**`,
    `**Ask in dependency order.**`, `**Look facts up; do not ask them.**`, `**Headless:**`,
    `explicitly parked`, `Open Questions`. `founder` matches zero times.
  - `grep -F -c 'explicitly parked' "$F_T"` ≥ 1.
  - `grep -F -c 'Continue until the idea is clear' "$F_B"` = 0, and the same count on `"$F_T"`
    = 0.
- [x] **AC2 (B10).** In the Phase 1.5 body,
  `awk '/^## Phase 1\.5: Deviation Analyst/{f=1;next} /^## Phase 1\.6/{f=0} f' "$F_C"`,
  each of these anchors matches at least once:
  - `3.6. **Null-guardrail check.**`
  - `recurring`
  - `**unwired**`
  - `no guardrail at all`
  - `package.json`
  - `lefthook.yml`
  - `.husky/`
  - `Makefile`
  - `none (null guardrail)`
  - `HEADLESS_MODE`

  By line order, step 3.6 sits between step 3.5 and step 4: the line numbers from
  `grep -n -e '^3\.5\. ' -e '^3\.6\. ' -e '^4\. \*\*Propose' "$F_C"` are strictly increasing.
  The `### Empty Case` body,
  `awk '/^### Empty Case/{f=1;next} /^<!-- phase-1.6-start -->/{f=0} f' "$F_C"`, contains `3.6`.
  The `### Constitution Promotion` body,
  `awk '/^### Constitution Promotion/{f=1;next} /^### Route Learning/{f=0} f' "$F_C"`, contains
  both `none (null guardrail)` and `step-3.6 findings`. The `### Error-to-Workflow Feedback` body
  contains `step 3.6`.
- [x] **AC3 (B10 lint shape).** `bash scripts/markdown-lint.sh "$F_C"` reports the file clean.
  This catches the indented-bullet MD007/MD032 shape.
- [x] **AC4 (B12b).**
  - `grep -c 'HOW THE SKILLS FIT TOGETHER:' "$F_H"` = 3.
  - The three map extracts are byte-identical and at least 5 lines long. This command exits 0:

    ```bash
    d=$(mktemp -d); awk -v d="$d" '/HOW THE SKILLS FIT TOGETHER:/{f=1;n++} f&&/^$/{f=0} f{print > (d "/map" n)}' "$F_H"; cmp "$d/map1" "$d/map2" && cmp "$d/map1" "$d/map3" && [ "$(wc -l < "$d/map1")" -ge 5 ]
    ```

    The check was validated red and green on a synthetic file at plan time.
  - `grep -F -c 'operator-*' "$F_H"` is unchanged from `origin/main` (6). The map adds no
    `operator-*` token.
  - `grep -F -c 'map verbatim' "$F_H"` = 1 (the Codex render note).
- [x] **AC5 (scope).**
  - `git diff --name-only origin/main...HEAD` lists only:
    - the four `F_*` files;
    - this plan and `knowledge-base/project/specs/feat-one-shot-mattpocock-b4-b10-b12b/*`;
    - any file the pipeline itself writes, such as a compound learning or
      `knowledge-base/INDEX.md`.
  - It never lists `plugins/soleur/commands/go.md`, anything under
    `plugins/soleur/skills/eval-harness/`, `plugins/soleur/skills/plan/SKILL.md`, or
    `knowledge-base/product/competitive-intelligence.md`.
  - `git diff origin/main...HEAD -- plugins | grep -c '^[-+]description:'` = 0.
- [x] **AC6 (eval gate).** For each `F_*`,
  `node plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs --check <file>` prints
  `"gated":false`. This is the gate's own lookup, and it makes no API call. With AC5, it confirms
  no eval-gated block was touched, so the full promptfoo run does not apply.
- [x] **AC7 (suites).** These all pass:
  - `bun test plugins/soleur/test/components.test.ts plugins/soleur/test/invocation-axis.test.ts plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/workflow-fidelity.test.ts`
  - `bash scripts/lint-agents-compound-sync.sh`
  - `bash scripts/markdown-lint.sh "$F_B" "$F_T" "$F_C" "$F_H"`
- [ ] **AC8 (PR body).** The PR body:
  - says this is the mattpocock/skills audit's **B4/B10/B12b bundle**;
  - cites `#8284` (the audit record);
  - notes that `#8648` owns the `competitive-intelligence.md` reconciliation-row update;
  - uses `Ref`, never `Closes`, because there is no tracking issue.

## Domain Review

**Domains relevant:** Product

### Product

**Status:** reviewed
**Assessment:** The CPO rated the change low risk and said to proceed. Four medium or low concerns
were raised, and they were handled as follows:

- **Parked items being lost.** They are already read back: plan Phase 0.5 extracts a matching
  brainstorm's open questions. No change needed.
- **A null-guardrail finding on every run.** This was dissolved when plan review cut the
  repo-level finding. Step 3.6 only covers recurring failure classes the session actually hit.
- **A longer brainstorm.** The open-decision count was applied, then cut in plan review.
- **Goal-labelled help-map rows.** These are taste-class suggestions, recorded in
  `decision-challenges.md`.

No other domain is relevant. This is an instruction-prose change to plugin skills. It touches no
marketing, legal, finance, sales, operations or support surface. The Product/UX gate tier is none:
no UI surface is touched, `commands/help.md` is CLI text, and no component or page file is in the
Files lists.

## Test Scenarios

- A brainstorm where the founder says "proceed" after two questions, with three branches still
  open. Those three appear as parked in the brainstorm document's Open Questions.
- A brainstorm that needs an API's pricing tier. The agent looks it up in parallel and does not ask
  the founder. A question that does not depend on the tier is still asked while the lookup runs.
- A compound run in a repo with a `lint` script in `package.json` and no `lefthook.yml` or
  `.husky/`, where no CI runs `lint`, after a session hit a recurring lint-class error. It reports
  one `unwired` finding that proposes wiring `lint` in, and no new lint guard.
- A compound run where a lefthook `pre-commit` already runs the typecheck that would have caught a
  session type error. The item is `covered`, and no new-guard proposal is made.
- A compound run in headless mode with a `none` finding. The finding is recorded in Session
  Errors, and nothing is applied.
- A brainstorm in pipeline or headless mode. No question is asked; branches a lookup can answer
  are closed, and the rest are parked in Open Questions.
- The user says "proceed" while a background lookup is still running. The lookup is collected
  before §1.2 exits. If it failed, its branch is parked.
- A compound run whose only session error is "skill not found". That is a workflow misstep, outside
  step 3.6's scope, so there is no null-guardrail proposal and the Empty Case wording applies.
- A compound run in a repo with no `.github/workflows/` directory. That counts as absent, not as an
  error.
- A headless compound run with a `none` finding. Constitution Promotion does not auto-accept it.
- `/soleur:help` on each harness renders the map once, between WORKFLOW SKILLS and AGENTS. Codex
  renders it verbatim.

## Non-Goals

- `plan/SKILL.md` §0.5's copy of the fuzzy exit rule. See Research Insights for why; it is a
  sibling wording, not a deferred capability, so no tracking issue is filed.
- Importing `grilling`'s multi-question frontier, or `retro`'s tool-economy and
  information-access categories.
- Any change to `go.md` routing, or to the audit record's reconciliation rows (`#8648`).
