---
title: "chore: checkpoint a skeleton plan file before the plan Phase 1 research fan-out"
date: 2026-08-10
slug: chore-plan-skeleton-checkpoint-before-research-fanout
issue: 7418
closes: 7418
branch: feat-one-shot-7418-plan-skeleton-checkpoint
type: chore
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
plan_revision: v2
---

# chore: checkpoint a skeleton plan file before the plan Phase 1 research fan-out

> ## ⚠ Superseded 2026-08-10 (v3) — the `pipeline_resume:` cursor was NOT shipped
>
> **Everything below describes v2, which was implemented and then rejected at review.** It is
> retained as a point-in-time record of the reasoning, not as a description of what merged. A
> 12-agent post-implementation panel found **twelve blocking defects** in the cursor mechanism
> behind a fully green suite, and every one reduced to the same shape: a second progress signal
> that could disagree with the file's own content, resolving to a fail-open arm. Two were fatal —
> the verdict table routed `deepening`+sections-present and `finalize`+sections-present (the only
> shapes those states can have) to *re-plan from scratch*, discarding completed plans; and because
> a cap-trip and every `deepen-plan` HALT **deleted** the key, a designed refusal became
> indistinguishable from success and advanced a stub into `/work`.
>
> **What shipped instead** (CTO ruling, recorded in ADR-176 §Considered Options 5–6): the
> durability half only. Phase 0.7 writes the skeleton before the fan-out and Phase 1.7 persists
> `## Research Insights` in a single Edit — but completion is asserted from **content**
> (`## Acceptance Criteria`, the one heading in all three detail-level templates) rather than from
> any progress key. The cursor, both tables, the resume cap, the strict-advance rule, the
> bounded-deletion rule and `deepen-plan`'s cursor semantics are all deleted; `deepen-plan` reverts
> to `main` untouched.
>
> Corrections to specific claims below, all measured at /work:
> - **`## Overview` is NOT a valid completion conjunct** — the MINIMAL template has none, so the
>   old predicate re-planned finished minimal plans from scratch.
> - **The `338 of 1531` figure in §Research Reconciliation was produced by the unbounded reader
>   this plan condemns.** Bounded: **321 of 1531 across 41 values** (`planning`×2, `complete`×5).
>   The rejection of `status:` reuse survives the correction — the collision with human meaning was
>   always the load-bearing part, never the magnitude.
> - **The checkpoint does not subdivide the expensive blocks.** §D2a's claim that the Phase 1.7
>   write covers "a stall *inside* the fan-out — the modal case" is false: that write happens after
>   every research agent returns. Phase 1's agents are haiku-pinned; the un-pinned 11-agent
>   Phase 2.5 block is the real cost and is unprotected either way.
> - **"No added cost on the happy path" was false.** Measured ~12–15 extra tool calls / ~15–30k
>   tokens for v2; the shipped design costs two Writes and one directory loop.
> - **ADR-144 → ADR-174 → ADR-175 → ADR-176.** THREE ordinals collided on this one branch.
>   ADR-144 was picked with an `origin/main`-scoped probe and was already claimed by a pushed
>   branch. ADR-174 was verified free across all 62 refs and a sibling landed it on `main`
>   mid-session. ADR-175 was verified free again and a sibling landed *that* during a Phase 7
>   BEHIND auto-sync, ~30 minutes later. An ordinal probe must quantify over all pushed refs
>   AND be re-run after every sync, right up to merge — this is not a plan-time question.
> - All line-number citations below (`plan/SKILL.md:247` etc.) are stale — the files were
>   restructured. Cite by heading anchor, per `cq-cite-content-anchor-not-line-number`.
>
> No `spec.md` exists for this branch (one-shot path, no brainstorm), so `lane:` defaulted to
> `cross-domain` (TR2 fail-closed) per `plan/SKILL.md` Save Tasks.
>
> **v2** after a 6-agent review panel returned 8 P0s against v1. The v1→v2 changes are recorded in
> §Review Revisions.

## Enhancement Summary

**Deepened on:** 2026-08-10 · **Revision:** v2 (post 6-agent panel) + deepen pass

**Halt gates run:** 4.5 network-outage (no trigger), 4.55 downtime/cutover (no serving surface),
4.6 user-brand impact (**pass** — section present, threshold `aggregate pattern`, no sensitive path),
4.7 observability (**applied** — section added, see below), 4.8 PAT-shaped (**pass** — no matches),
4.9 UI wireframe (**pass** — 0 UI globs in Files sections; the 2 whole-file hits were this plan's own
prose *stating* the absence, the same self-reference class as R2), 4.10 encryption posture
(**pass** — no store or connection).

**Added by the deepen pass:**

1. **`## Observability` section + AC12 + task 3.8.** §4.7's skip-list does not exempt `.md` inside
   `plugins/*/skills/`, so the gate applies. Supplying it was the right call independently: it closes
   the debuggability gap review raised — a mis-resume was otherwise indistinguishable from a normal
   run, with a double-billed pipeline as the operator's only symptom.
2. **Follow-up 6.5 — a gate-definition mismatch.** `plan` §2.9 and `deepen-plan` §4.7 disagree on
   whether a prompt-only change needs an Observability section. Recorded rather than papered over.

**Verified during the pass (not asserted):** every cited AGENTS rule ID is active and none appears in
`scripts/retired-rule-ids.txt`; every cited issue/PR (#7418, #7349, #7416, #4133, #7247, #3625,
#4116) resolves and #7247 matches its usage in `one-shot/SKILL.md:97`; every `knowledge-base/` path
resolves; the ADR ordinal was re-derived at /work over all pushed branches (ADR-176; the plan's
ADR-144 pick was `origin/main`-scoped and collided — see §Architecture Decision); the unbounded frontmatter
reader returns empty against this file (the R2 regression fixture).

## Overview

`soleur:plan` spends its most expensive stretch — a multi-agent research fan-out plus domain-leader
spawns — before it writes a single byte to the plan file. The first write is `## Open Code-Review
Overlap` at `plan/SKILL.md:247`. An API stall in that window converts the whole spend into zero
deliverable, and `one-shot`'s partial-artifact recovery (`one-shot/SKILL.md:195-201`) cannot help,
because it only recovers artifacts that exist.

This plan makes the skill **write first and research second**: derive the path from the issue title
the premise gate already fetched, write a skeleton, persist the research findings as soon as they
land, and carry a dedicated machine-owned cursor key (`pipeline_resume:`) that `one-shot` reads to
decide resume-vs-advance. The cursor is **deleted** at finalization, so a merged or archived plan is
inert by construction.

Scope: four prompt/reference files, one new contract test, one ADR.

## Problem Statement / Motivation

Observed 2026-08-10 during `/one-shot #7349`: the planning subagent was terminated by a stalled
response after **44 tool calls and ~268k subagent tokens (~19 minutes)**, having reached the
domain-leader review stage. Recovery found no plans dated today, no specs dir for the branch, and no
uncommitted changes. The run survived only because the subagent context happened to still be
resumable via `SendMessage` — a harness affordance, not a pipeline guarantee.

Two defects compound:

1. **Write-last ordering.** The skill has no documented step that creates the plan file at all.
   Sections appear at `:247`, `:369`, `:412` (conditionally `:476`, `:491`, `:551`, `:569`); nothing
   says when the file first exists. In practice it is created at the first section write — after
   every expensive spawn.
2. **All-or-nothing recovery.** `one-shot/SKILL.md:197` recognises a partial artifact only when the
   file already has "frontmatter + Overview + Acceptance Criteria sections". Anything less is
   discarded and the phase re-runs from scratch.

## Research Reconciliation — Premise vs. Codebase

| Premise | Reality (verified) | Plan response |
|---|---|---|
| First write is ~line 247 | **Confirmed.** `plan/SKILL.md:247`. | Skeleton write before Phase 1. |
| one-shot recovery is all-or-nothing | **Confirmed.** `one-shot/SKILL.md:195-201`. | D4. |
| "keep eval-gated blocks intact; run the eval harness if a gated block is touched" | **Neither file is eval-gated.** `gated-skills.json` registers only `commands/go.md`, `agents/support/ticket-triage.md`, `brainstorm/references/brainstorm-domain-config.md`, `incident/SKILL.md`; `grep -c 'eval-gate:block'` = 0 for all edited files. | **No eval-harness run required.** The fences here are *workflow-fidelity sentinels*. |
| "frontmatter + `## Overview` + placeholder headings" | The heading set varies by detail level (chosen at Step 4, after research) and conditional sections are gate-triggered; stubbing one a plan skips guarantees a deepen-plan halt (`deepen-plan/SKILL.md:396,452,560`). | Skeleton = minimal frontmatter + `## Overview` (D2). |
| Skeleton can carry `lane:`/`type:`/`closes:` | **False.** `lane:` is derived from `spec.md` at `plan/SKILL.md:742-748`; `type:` at Step 2 (`:279`); the closing issue is decided *by planning* — `one-shot/SKILL.md:97` re-reads `issue:`/`closes:` after the subagent returns (#7247). | D2 restricts the skeleton's frontmatter. |
| **v1 claim: "plan frontmatter already carries `status:` across ~10 plans — conforming, not inventing"** | **FALSIFIED, by ~34x.** **338 of 1531** plans carry `status:`, across **44+ values**: `draft`(132), `planned`(93), `ready`(23), `ready-for-work`(21), `plan`(11), `deepened`(6), `complete`(6)… `status: planning` and `status: complete` already exist with *human draft-state* meaning. | **v2 abandons `status:` entirely** for a dedicated key (D3). |
| **v1 claim: "frontmatter is parsed, so the self-reference trap dissolves"** | **FALSIFIED against this very file.** The prescribed reader (`plan/SKILL.md:1013` gsub awk) is line-anchored, not frontmatter-bounded. Run on v1 of this plan it returned `planning` — from a fenced YAML *example*, while the frontmatter had no such key. | **v2 mandates frontmatter-bounded parsing** + a body-collision fixture (D3a). |
| v1 assumed `## Research Insights` is written by `plan` | **False.** That section is authored by `deepen-plan` (`deepen-plan/SKILL.md` §7). `plan` mentions it only as a scratch destination (`:263`). v1's checkpoint therefore bought a filename and nothing else for a stall *inside* the fan-out — the modal case. | **D2a adds a real `## Research Insights` write at Phase 1.7.** |
| v1 claimed the committed file carries the terminal state | **False.** Save Tasks (`plan/SKILL.md:759-767`) commits *inside* `plan`, before deepen-plan; `deepen-plan` never commits (`grep -n 'git add\|git commit' deepen-plan/SKILL.md` → nothing). | D3's cursor is deleted at `plan` finalization, so the committed artifact is inert. |
| v1 chose ADR-173 | **Triple-claimed** on pushed branches `feat-kb-archival-convention`, `feat-one-shot-7393-…`, `feat-one-shot-7394-…`. | **ADR-176** — first free ordinal (ADR-001…173 all claimed, no gaps) when the probe quantifies over **all pushed branches**, not just `origin/main`. v2's ADR-144 pick used the `origin/main`-only method and collided; see §Architecture Decision. |

## Proposed Solution

### D1 — New Phase 0.7 "Skeleton Checkpoint", after Phase 0.6, before Phase 1

The premise gate already runs `gh issue view <N> --json state,title,…` (`plan/SKILL.md:122`), so the
issue title — and therefore the slug — is free at that point.

1. Resolve the plans directory from `git rev-parse --show-toplevel`, so the write cannot land in the
   bare repo root (`2026-05-15-one-shot-plan-subagent-cwd-divergence.md`). `one-shot/SKILL.md:138`
   already forces `cd <WORKING_DIRECTORY> && pwd` first, so moving the write earlier *shortens* the
   exposure window.
2. Derive `PLAN_PATH` from the issue title, falling back to the feature description for freeform
   invocations (no `#N`). **The premise gate only fires when refs are cited** (`:122`, `:127`), so
   the freeform arm is a real path and is covered by T8.
3. Branch on existing state (D8), then write the skeleton.

**Write-denial arm.** `.claude/hooks/iac-plan-write-guard.sh` is a PreToolUse *deny* hook on plan
markdown (this plan's own first Write was blocked by it). Phase 0.7 must specify: on denial, retry
once with a minimal Overview (title only); if still denied, **proceed skeleton-less** and log the
reason — degrading to today's behaviour rather than aborting the run.

### D2 — The skeleton is minimal; frontmatter carries only what Phase 0.6 knows

```yaml
  title: "<from gh issue view --json title>"
  date: <UTC date>
  slug: <derived>
  branch: <git branch --show-current>
  issue: <N>                 # provisional — planning may re-target
  pipeline_resume: research
  resume_attempts: 0
```

Then `## Overview` and nothing else.

*(The block above is indented deliberately so no line begins at column 0 — this file must not be a
false positive for its own cursor key. That discipline is what D3a mandates and what v1 failed.)*

**Deliberately absent: `lane:`, `type:`, `closes:`, `priority:`, `domain:`,
`brand_survival_threshold:`, `requires_cpo_signoff:`, and `status:`.** All are derived after
research. Pre-seeding `lane:` is actively harmful — it bakes in the fail-closed `cross-domain`,
which *widens* the Phase 2.5 domain fan-out this change exists to protect. Finalization adds them
and rewrites `issue:`/`closes:` unconditionally.

**No conditional section is stubbed** — see the Research Reconciliation row on deepen-plan's
placeholder rejects. Any placeholder prose must avoid the literal tokens `TODO`, `TBD`, `N/A`,
`placeholder`.

**Overview sanitation.** `lint-infra-no-human-steps.py:74-80` scans `knowledge-base/project/plans`,
and the write-guard hook gates the Write itself; both fail prose pairing a human-actor token with an
infrastructure imperative. Phase 0.7 must prescribe a *sanitized restatement*, never a verbatim
issue-body paste.

### D2a — Phase 1.7 writes `## Research Insights` (this is what makes the checkpoint pay)

v1's cursor advanced past the research fan-out without persisting anything, because `plan` writes no
research section today — the first write remained `## Open Code-Review Overlap`. A stall *inside* the
fan-out (the modal case, and the shape of the motivating incident) would still have lost everything.

Phase 1.7 Consolidate Research therefore gains a real section write: file paths, applicable
learnings, external findings, and the Premise Validation note. This is the single highest-value line
in the plan — it is what converts "we saved a filename" into "we saved the research".

### D3 — The cursor is a dedicated key, `pipeline_resume:`, deleted at finalization

**Not `status:`.** That namespace holds 338 plans across 44+ values, including `planning` and
`complete` with human draft-state meaning; reserving tokens inside it would require a migration, an
out-of-enum arm, and a validator, and would still collide with six other `status:` enums elsewhere in
the repo (`file-todos`, `resolve-debt`, ADR template, distribution-content…). A dedicated key is
closed by construction and needs none of that.

| `pipeline_resume` | Resumes at | Set after |
|---|---|---|
| `research` | Phase 1 | skeleton write |
| `drafting` | Step 2 Issue Planning | `## Research Insights` lands (D2a) |
| `gates` | Phase 2.5 | `## Open Code-Review Overlap` + `## Files to Edit` land |
| `finalize` | Step 4 | `## Domain Review` + `## User-Brand Impact` land |
| `deepening` | deepen-plan §1 | `plan` finalization completes |
| *(key absent)* | — | deepen-plan exit, **or** `plan` finalization on the direct path |

**Presence is the boolean.** Key present ⇒ unfinished. Key absent ⇒ finished. One field, one owner
per value, no two-field invariant that can disagree. `one-shot` never maps a token to a phase — it
reads presence, plus the single token `deepening` to choose which skill to re-invoke.

**Deletion, not mutation — and why that is safe here.** v1 argued deletion is unreliable at the end
of a context-pressured run. That objection is answered by D4: a leftover key on a plan that *passes*
the section assertion resolves to **Undetermined**, not Resume, so a leak degrades to a re-run rather
than an infinite loop. Deletion buys something mutation cannot: a merged or archived plan has no key
at all, so no future reader can mistake it for in-flight. That dissolves the archive/merge hazards
(`archive-kb.sh:103-104,166`, `worktree-manager.sh:1737-1754`, `ship/SKILL.md:123`) without editing
any of them.

**Ordering.** Persist the section, *then* advance the cursor, in a single Edit where possible. The
cursor must never claim more progress than the file contains.

### D3a — Frontmatter-bounded parsing is mandatory

Every read of `pipeline_resume:` / `branch:` extracts **only from the first `---`…`---` block**. The
canonical in-repo model is `.github/workflows/review-reminder.yml:67,84,124`
(`sed -n '/^---$/,/^---$/{…}'`). The line-anchored gsub awk form at `plan/SKILL.md:1013` is correct
for a *known-frontmatter* key in a single file but **must not** be used for a key that may appear in
a body.

Proof this is load-bearing: run against v1 of this document, the unbounded form returned `planning`
from a fenced example at line 93 while the frontmatter had no such key. The contract test therefore
ships a **fixture whose body contains `pipeline_resume:` at column 0**, asserting the reader ignores
it.

### D4 — Both paths are conjunctive; the table is total

"Cursor absent ⇒ complete" is a negative assertion, and absence has causes other than completion
(interrupted write, clobber, revert). ADR-126's posture — an `undetermined` read is never a positive
result — applies in both directions.

| `pipeline_resume` | Positive section assertion (frontmatter + Overview + Acceptance Criteria) | Verdict |
|---|---|---|
| absent | passes | **Complete** → continue |
| absent | fails | **Undetermined** → full re-run |
| `deepening` | fails | **Resume** deepen-plan |
| `deepening` | passes | **Undetermined** → full re-run (a leaked cursor, not an in-flight one) |
| any other known token | fails | **Resume** plan |
| any other known token | passes | **Undetermined** → full re-run |
| present but **unrecognized** | either | **Undetermined** → full re-run |

Fail-open on read, fail-closed on enforce (ADR-089 posture), and total over the key's real domain.

**Both paths use this table.** The success path (`one-shot/SKILL.md:172`, after extracting
`### Plan File`) evaluates the *same conjunct* — not a bare presence check. v1 hardened only the
recovery branch, leaving the stub-to-`/work` path open on the success path, which is the outcome
`## User-Brand Impact` names as worst.

**Every arm terminates in "continue to step 3."** No arm ends at a skill invocation — that is the
concrete guard against the ADR-083 CONTINUATION-GATE concern.

### D5 — Resume is bounded, and a designed halt is not a stall

Without a bound the design converts "stop and lose the spend" into "loop and re-spend indefinitely",
and it does so *deterministically* for a `deepen-plan` HALT (§4.6–4.10 are designed refusals, not
crashes) — the recovery action for a crash is the worst possible action for a halt.

- `resume_attempts:` lives in the skeleton, incremented by `plan`/`deepen-plan` on resume entry.
- **Cap 2.** At cap, the cursor is deleted and a one-line reason is written to the plan body;
  `one-shot` then takes the Undetermined arm exactly once and, if that also fails, stops and files an
  `action-required` issue rather than looping.
- **Strict advance.** The cursor must strictly advance between attempts; the same token twice trips
  the cap immediately regardless of count.
- **Designed halts delete the cursor.** A `deepen-plan` HALT is a terminal, correct outcome — it
  removes `pipeline_resume` and records the halt reason, so it can never be replayed as a crash.

This also re-discloses cost: an unbounded loop would multiply spend with no re-disclosure, against
`hr-autonomous-loop-skill-api-budget-disclosure`.

### D6 — Resume re-runs the cheap gates; it never inherits them

Phases 0.6, 2.7 (GDPR), 2.8 (IaC), 2.9 (Observability), 2.10 (ADR/C4), 2.11 (Encryption) and 3
(SpecFlow) are grep/read gates costing near nothing next to a fan-out. **All of them re-run
unconditionally on resume**, regardless of cursor position.

This is required, not optional: ADR-032:425-427 records the exact rule — *"a plan recovered from disk
after a subagent crash carries its 'verify X before shipping' Phase-0 gates as UNVERIFIED claims —
re-run the empirical probes, do not inherit them as done."* v1's T2 asserted the opposite
("premise validation not repeated") and was wrong. Skipping 2.7 would also silently bypass
`hr-gdpr-gate-on-regulated-data-surfaces`.

**Resume detection therefore lives at Phase 0**, above 0.5 — otherwise 0.5's brainstorm-ambiguity
`AskUserQuestion` (`plan/SKILL.md:92`) can fire inside a Task subagent that cannot answer it and hang
the pipeline. Phase 0.5 idea refinement is skipped on resume; 0.6 is not.

**Mode preservation.** `plan`'s canonical mode predicate (`:349`) treats a plan-file-path argument as
a headless signal, so a naive resume would silently strip an operator-attached session of its review
gates. The resume invocation must carry an explicit mode flag rather than relying on the path.

### D7 — Recovery selects by frontmatter `branch:`, with a tiebreak and an archive exclusion

`one-shot/SKILL.md:196` selects via a same-day glob. The skeleton widens two pre-existing weaknesses:
a run starting at 23:5x UTC and recovering after midnight misses its own file, and abandoned
skeletons from earlier same-day runs now match.

Select by frontmatter `branch:` (bounded, non-recursive, `plans/*.md` only — `plans/archive/` holds
286 plans, 49 with `branch:`), date glob as fallback. **A tiebreak is mandatory**: duplicate `branch:`
values already exist on `main` (`feat-one-shot-7278-registry-restart-lever`,
`feat-one-shot-5000-5004-cron-sandbox-bwrap-fix`, `feat-flagsmith-adoption` — two files each).
Tiebreak: highest date prefix, then newest mtime. Use a bounded command
(`grep -l -m1` over `plans/*.md`) per `hr-never-run-commands-with-unbounded-output`.

Phase 0.7's own lookup uses the **same** selector, not a freshly derived path — otherwise a
midnight-rollover resume derives a different filename and writes a second skeleton.

### D8 — Idempotency

| State | Action |
|---|---|
| No file | Write skeleton, `pipeline_resume: research`, `resume_attempts: 0` |
| Cursor present, same `branch:` | Resume at the token; **never re-Write the skeleton** |
| Cursor present, different branch | Foreign artifact — not selected by D7; write a new skeleton |
| Cursor absent (finished plan) | **Never overwrite.** Headless: do not re-plan; return the path and let the pipeline advance (Save Tasks is skipped, `tasks.md` already exists). Interactive: ask |

**§Managing Plan Documents must be reconciled.** `plan/SKILL.md:882-883` currently says a re-run must
"update in place… preserve prior content", which directly contradicts the resume rule that the cursor
phase is treated as never-started and its stray content removed. That section is in Files to Edit.

**Bounded deletion.** "Remove stray content" means: from the cursor phase's anchor heading to the
next `^## `, only while the cursor is present, never touching frontmatter. Unbounded destructive
prose on the least-tested path is not acceptable.

**No rename in the normal path.** The slug comes from the issue title, so Step 2's "Convert title to
filename" bullet (`:279`) **moves** into Phase 0.7 (it does not become a conditional no-op — v1 said
both). Step 2 still refines frontmatter `title:`. A `git mv` is reserved for a genuinely misleading
slug and happens once, at finalization only.

**Exact-path `git add`.** `plan/SKILL.md:764` runs `git add knowledge-base/project/plans/` — a
directory add that would sweep abandoned skeletons into the commit. Narrow it to the exact plan path.

### Alternative approaches considered

| Alternative | Why not |
|---|---|
| Reserve values inside `status:` (v1) | 338 plans, 44+ values, `planning`/`complete` already taken with other meaning; needs migration + validator + out-of-enum arm. A dedicated key needs none. |
| `<!-- planning in progress -->` HTML comment (issue's proposal) | Invisible when rendered, so a leak is silent; `preflight` scrubs comments (`preflight/SKILL.md:492`). |
| `one-shot` scans for "the first missing section" (issue's proposal) | The expected section set varies by detail level chosen after research; every conditional section a plan skips reads as missing. |
| Two fields (`status:` + `resume_from:`) (v1) | Creates states that can disagree, and a deletion at finalization anyway. Presence of one key is the boolean. |
| `one-shot` maps the token to a phase | Puts plan's phase vocabulary in two files coupled only by a test. |
| Pre-seed the full heading set with `_(pending)_` stubs | Trips deepen-plan 4.6/4.7/4.10 for conditional sections. |
| Fold in the stale 1800→2400 budget figure | Deferred to its own issue: the stale value appears in 5 places across 4 files, and a `grep -cF '1800-word cumulative cap'` AC passes green while `plan/SKILL.md:969` still teaches `1800 - current`. Replacing one stale literal with another that has been bumped 14 times is not a fix — cite `SKILL_DESCRIPTION_WORD_BUDGET` by name instead. |
| Checkpoint-commit the skeleton | Genuinely tempting — an untracked file is what worktree recreation and `worktree-manager.sh:1751`'s plain `mv` destroy. Deferred: it changes commit shape and `one-shot/SKILL.md:108`'s empty-branch cleanup semantics. Recorded as residual risk. |

## Technical Considerations

- **Workflow-fidelity sentinels.** `plan-anti-bypass-protocol` (`plan/SKILL.md:6-17`) and
  `one-shot-anti-bypass-protocol` (`one-shot/SKILL.md:8-24`) are asserted by
  `workflow-fidelity.test.ts` via `lib/workflow-fidelity.ts:57,63`. Do not disturb the fences.
- **Naming collision.** `one-shot/SKILL.md:210` already uses "checkpoint" to mean *"a checkpoint,
  never a stopping point"*. Do not introduce checkpoint-as-durable-state prose into that file; the
  phase name stays inside `plan/SKILL.md`.
- **`Status:` in session-state.md.** `one-shot/SKILL.md:181` writes `- Status: complete`
  unconditionally on the success path. That literal is unrelated to the plan cursor and must be
  disambiguated in the prose, and made consistent with D4's verdict.
- **`deepen-plan` has a Workflow port** (`workflows/deepen-plan.workflow.js:54-56`) that can write to
  a `-deepened` file rather than in place. The cursor must be scoped to the prose path explicitly, or
  the port must clear it too — otherwise the file `one-shot` holds never loses its cursor.
- **Skill description budget is 2400/2400 — zero headroom** (`components.test.ts:16`). No
  `description:` may gain a word; this change is body-only.
- **Test discovery.** `plugins/soleur` `.test.ts` runs under **bun test**, not vitest —
  `scripts/test-all.sh:732` runs `bun test plugins/soleur/` (directory glob), so a new test is
  auto-discovered. `bunx vitest` reports a spurious failure.
- **Existing assertions over `plan/SKILL.md`** that must stay green: `observability-schema-parity`,
  `wireframe-feedback-pause`, `mandatory-wireframes-hardening`,
  `ship-soak-followthrough-enrollment-gate`, `scratch-path-collision`, `lane-frontmatter.test.sh`
  (whose A5 requires `lane:` + `spec.md` to remain inside the `## Save Tasks` block — safe to add
  prose there, unsafe to move the extraction out).

## User-Brand Impact

- **If this lands broken, the user experiences:** a `/one-shot` run that re-runs research it already
  paid for, loops and re-spends without bound, or advances a stub plan into `/work` — producing a PR
  against their repository that implements nothing they asked for. `work/SKILL.md:130` only fails on
  a *missing* plan file, so there is no existing net beneath D4.
- **If this leaks, the user's data/workflow is exposed via:** no new exposure vector. No network
  calls, no new persisted user data, no credential handling, no third-party surface.
- **Brand-survival threshold:** `aggregate pattern`

Rationale: a mis-resume is bounded (D5), reversible and non-disclosing. The brand cost arrives only
if the resume logic is systematically wrong across runs — an aggregate pattern, not a single-user
incident — so no per-PR CPO sign-off is added.

## Observability

This change ships prompt code that executes on the operator's own self-hosted CLI (observability
layer 7), so the observable surface is the artifacts the run leaves on disk, not a server-side sink.
The recovery verdict is deliberately recorded because a mis-resume is otherwise indistinguishable
from a normal run — which was raised as a debuggability gap during review.

```yaml
liveness_signal:
  what: "Recovery verdict line written to session-state.md on every plan-phase transition — `Recovery verdict: <resume|complete|undetermined|legacy> (cursor=<x>, attempts=<n>, selector=<branch|date-glob>)`"
  cadence: "once per one-shot plan phase, plus once per resume attempt"
  alert_target: "operator-read artifact committed with the branch; no paging surface exists for a local CLI workflow, and inventing one would be theatre"
  configured_in: "plugins/soleur/skills/one-shot/SKILL.md — the `## Plan Phase` block that already writes session-state.md"

error_reporting:
  destination: "session-state.md (verdict + reason) and the plan body (halt/cap reason); an `action-required` GitHub issue on cap-trip"
  fail_loud: "yes — a cap-trip deletes the cursor, records the reason, and files the issue rather than looping silently"

failure_modes:
  - mode: "resume loop — the same phase re-stalls repeatedly"
    detection: "`resume_attempts` in plan frontmatter exceeds 1, or the cursor fails to strictly advance between attempts"
    alert_route: "cap trips at 2 -> cursor deleted, reason written, `action-required` issue filed"
  - mode: "stub plan advanced to /work"
    detection: "D4's conjunctive test — cursor absent but the positive section assertion fails"
    alert_route: "Undetermined arm -> full re-run; never advances"
  - mode: "cursor leaked into a finished plan"
    detection: "cursor present while the positive section assertion passes"
    alert_route: "Undetermined arm -> full re-run (not an infinite resume)"
  - mode: "skeleton written outside the worktree, or lost before commit"
    detection: "selector finds no plan whose frontmatter `branch:` matches the current branch"
    alert_route: "date-glob fallback, then the existing full re-run path"

logs:
  where: "knowledge-base/project/specs/<branch>/session-state.md, committed with the branch"
  retention: "repo history — permanent"

discoverability_test:
  command: "grep -A6 '^## Plan Phase' knowledge-base/project/specs/$(git branch --show-current)/session-state.md"
  expected_output: "a `Recovery verdict:` line naming one of resume|complete|undetermined|legacy, with the cursor value, attempt count and selector used"
```

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment (framing pass):** proceed; five amendments raised, all adopted into v1 — conjunctive
completeness test, opaque resume token, drop post-research frontmatter fields, slug from the issue
title with no rename, and a frontmatter carrier instead of an HTML comment. Two more folded in:
branch-based recovery and deepen-plan coverage. The review also corrected two premises in the plan's
own framing (`lane:` derivability, `issue:`/`closes:` mutability).

**Assessment (devex pass on v1):** three ship-blockers — the `drafting` token anchored on a section
`plan` never writes (so the checkpoint bought a filename and nothing else for the modal stall);
execution order ≠ file order in `plan/SKILL.md`, making line-number ordering a false proxy; and
`status: deepening` had no terminal exit on the direct-`/plan` path while a designed halt was
indistinguishable from a stall. All three are resolved in v2 (D2a, D3, D5).

**Product/UX Gate:** not applicable — Product assessed **NONE**. The mechanical UI-surface override
does not fire: no path in `## Files to Edit` matches `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx` or any UI-surface term. All targets are prompt, reference, test and ADR files.

Legal, Finance, Marketing, Sales, Support and Operations were assessed and are not implicated: no
contractual surface, no expense, no external communication, no customer-facing artifact, no
infrastructure.

**Agents invoked:** cto (×2 — framing and devex), repo-research-analyst, learnings-researcher,
functional-discovery, scoped advisor consult (`model: fable`), dhh-rails-reviewer,
kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer
**Skipped specialists:** none

## Review Revisions (v1 → v2)

The 6-agent panel returned 8 P0s. All are resolved; the four largest changed the core contract.

| # | Finding | Raised by | Resolution |
|---|---|---|---|
| R1 | `status:` namespace already holds 338 plans / 44+ values incl. `planning`, `complete` | dhh, simplicity, kieran, architecture (independently) | Dedicated key `pipeline_resume:` (D3) |
| R2 | Prescribed reader is line-anchored, not frontmatter-bounded — reproduced returning `planning` from v1's own fenced example | dhh, spec-flow, architecture | Frontmatter-bounded parsing + body-collision fixture (D3a) |
| R3 | Resume loop unbounded; a deepen-plan HALT loops deterministically | spec-flow, cto, architecture | `resume_attempts` cap 2, strict advance, halts delete the cursor (D5) |
| R4 | `drafting` anchored on `## Research Insights`, which `plan` never writes | cto | Phase 1.7 now writes it (D2a) |
| R5 | Resume at `finalize` skipped gates 2.7–2.11 + Phase 3; T2 contradicted ADR-032 | spec-flow, architecture | All cheap gates re-run on resume (D6) |
| R6 | Success path used a bare presence check, leaving the stub→`/work` path open | spec-flow | Same conjunct on both paths (D4) |
| R7 | D4 table had no out-of-enum / malformed arm | kieran, simplicity, architecture | Table made total (D4) |
| R8 | ADR-173 triple-claimed on pushed branches | architecture | ADR-176 (verified free) |
| R9 | `git add` on the plans *directory* sweeps abandoned skeletons | kieran, architecture | Exact-path add (D8) |
| R10 | `plan-issue-templates.md` is the canonical frontmatter template and was missing | kieran | Added to Files to Edit |
| R11 | §Managing Plan Documents ("preserve prior content") contradicts the resume rule | architecture | Reconciled in D8 |
| R12 | Branch selector ambiguous — duplicate `branch:` values exist today; archive not excluded | architecture, spec-flow | Tiebreak + archive exclusion + bounded command (D7) |
| R13 | Resume flips an attached session headless via the path-argument predicate | spec-flow | Explicit mode flag (D6) |
| R14 | Write-denial by the guard hook had no defined arm | spec-flow | Degrade to skeleton-less (D1) |
| R15 | Unbounded "delete stray content" on the least-tested path | cto | Bounded to heading→next `^## ` (D8) |
| R16 | ~10 ACs were ceremony (restating the full suite, asserting untouched files, standing gates) | dhh, simplicity, cto | 21 ACs → 12 |
| R17 | D7 (1800→2400) fixes 1 of 5 sites; its AC passes while the harmful text remains | simplicity, cto, kieran | Cut to its own issue |
| R18 | Risks claimed the scope diff would catch a bare-root skeleton — it is a three-dot diff over *committed* files | dhh | Corrected; residual risk stated |

Deferred to follow-up issues (filed at `/work`): the stale 1800 budget figure across 4 files (R17);
checkpoint-committing the skeleton for durability; an `archive-kb` guard refusing to archive a
cursor-bearing plan (largely dissolved by deletion-at-finalization).

## Open Code-Review Overlap

One open `code-review` issue mentions a file this plan edits (64 open issues scanned):

- **#4133** — *follow-through(#4116): Schema parity test for `## Observability` block* — names
  `plan/SKILL.md` §2.9 and `deepen-plan/SKILL.md` §4.7. **Disposition: Acknowledge.** Different
  concern; this plan does not touch the Observability schema. Noted for triage only: its criteria
  appear already satisfied by `plugins/soleur/test/observability-schema-parity.test.ts`. Verifying
  and closing it is out of scope (`hr-before-asserting-github-issue-status`).

## Architecture Decision (ADR/C4)

### ADR

**ADR-176 (provisional) — "Plan artifacts checkpoint before research; a plan-owned cursor key
mediates resume."** Verified free across `origin/main` **and every pushed branch**: enumerating
`git ls-tree -r <ref> knowledge-base/engineering/architecture/decisions/` over all 62 `origin/*` refs
yields ADR-001…ADR-173 with **no gaps**, so ADR-176 is the first free ordinal. The ordinal stays
provisional until `/ship`'s collision gate re-verifies; if it moves, sweep this plan **and**
`tasks.md` in the same edit
(`2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md`).

> **Corrected at /work (was ADR-144).** The plan's original pick was verified with an
> `origin/main`-scoped probe ("0 files on `origin/main`, 0 references in `knowledge-base/`"), which is
> the *same insufficient method* the plan had just caught for ADR-173 — a branch-claimed ordinal is
> invisible to it. ADR-144 is in fact claimed by
> `origin/feat-one-shot-6766-6774-ci-guards-cannot-fail`
> (`ADR-144-discoverability-test-kind-and-required-suffix-invariant.md`). An ordinal probe must
> quantify over pushed branches, not just the default branch.

New ADR — a corpus sweep found none governing plan-artifact format or lifecycle. It must:

- **Relate to ADR-015 via an `amends:` frontmatter edge, not a rewrite.** ADR-015's Decision governs
  *Work's* Phase-4 exit on the `work → {one-shot|ship}` leg; this is the `plan → one-shot` leg —
  orthogonal. ADR-112:122-126 rejected exactly this "amend instead of new ADR" shape.
- **Cite ADR-032:425-427** as the basis for D6 (recovered plans must re-run their verification gates).
- **Inherit ADR-121's posture** — a positive claim, malformed ≠ absent — while stating that the
  carrier differs (frontmatter key, not an HTML comment in a table cell), and that ADR-089's
  malformed→absent collapse is explicitly **not** inherited.
- **Cite ADR-126** for "assert the artifact the consumer reads", which is why D4 pairs the cursor
  with a positive section assertion on every arm.
- **Reconcile ADR-026 and ADR-151** — ADR-026:34 makes the canonical plan template the single source
  of truth for required controls; ADR-151:274-276 treats plans as point-in-time records excluded from
  sweeps. A mutable cursor is in tension with the latter, which is precisely why it is deleted at
  finalization.
- **Record that CONTINUATION-GATE is un-ADR'd** — it exists only in `one-shot` prose
  (`:206,:210,:238`) — and that ADR-083's "do not edit one-shot" rejection rested on *redundancy*,
  which does not transfer to a recovery branch that has nowhere else to live.
- **Respect ADR-132** — region markers must be HTML comments; `pipeline_resume:` collides with
  neither `lint-infra-ignore` regex.

### C4 views

**No C4 impact.** All three `.c4` files were read in full (`model.c4` 656 lines, `views.c4` 70,
`spec.c4` 54), not keyword-grepped. Enumerated: external human actors (`founder`, `emailSender`,
`betaContact`, `contributor`) — only `founder` participates, already modelled; external systems
(`anthropic`, `github`, `cloudflare`, `doppler`, `discord`, `stripe`, `systemdUser`, `plausible`,
`resend`, `pushService`, `ghcr`, `projectZot`) — only `anthropic`, via calls the pipeline already
makes; containers (`webapp`, `engine`, `plugin`, `infra`) — the change is prompt text inside
`plugin`, writing a markdown file to an existing directory; actor↔surface access relationships —
unchanged. No element description is falsified, so no `.c4` edit and no `views.c4 include` line.

### Sequencing

ADR authored in this PR, `status: accepted`. No soak gate, so no Follow-Through Enrollment.

## Files to Edit

- `plugins/soleur/skills/plan/SKILL.md` — Phase 0.7 (D1/D2/D8); Phase 1.7 `## Research Insights`
  write (D2a); cursor advance at 4 sites; resume-mode block at Phase 0 (D6); finalization deletes the
  cursor; move the filename-derivation bullet; reconcile §Managing Plan Documents; exact-path
  `git add`.
- `plugins/soleur/skills/plan/references/plan-issue-templates.md` — the canonical frontmatter
  template (`:18-22`, `:148-152`, `:302-306`) currently defines only `title`/`type`/`date`; it must
  document the skeleton keys or it becomes the most-wrong of three competing definitions.
- `plugins/soleur/skills/one-shot/SKILL.md` — conjunctive recovery branch (`:195-201`), same conjunct
  on the success path (`:172`), branch selector with tiebreak (`:196`), `Status:` disambiguation
  (`:181`), every arm terminating in "continue to step 3".
- `plugins/soleur/skills/deepen-plan/SKILL.md` — set the cursor to `deepening` on entry, delete on
  exit; halts delete it with a reason. Scope note for `workflows/deepen-plan.workflow.js:54-56`.

## Files to Create

- `plugins/soleur/test/plan-skeleton-checkpoint.test.ts` (+ a fixture whose **body** contains
  `pipeline_resume:` at column 0)
- `knowledge-base/engineering/architecture/decisions/ADR-176-*.md`

## Implementation Phases

### Phase 1 — Contract test first (RED)

`plugins/soleur/test/plan-skeleton-checkpoint.test.ts`, three assertions that can actually drift:

1. Phase 0.7 exists in `plan/SKILL.md`, positioned **after** `### 0.6.` and **before**
   `### 1. Local Research`.
2. The cursor key literal `pipeline_resume:` appears in `plan/SKILL.md`, `one-shot/SKILL.md` and
   `deepen-plan/SKILL.md`; the **token vocabulary** (`research|drafting|gates|finalize`) appears in
   `plan/SKILL.md` only — `one-shot` may name `deepening` and nothing else.
3. The frontmatter reader: against the shipped fixture (body contains `pipeline_resume: research` at
   column 0, frontmatter does not), the prescribed extraction returns empty.

### Phase 2 — `plan/SKILL.md` (GREEN)

Phase 0.7 per D1/D2/D8; Phase 1.7 research-section write per D2a; cursor advances; Phase-0 resume
detection with gate re-run per D6; finalization deletes the cursor; move the filename bullet;
reconcile §Managing Plan Documents; narrow `git add`.

### Phase 3 — `one-shot/SKILL.md` (GREEN)

D4's total table on both paths; D7 selector; arm termination; `Status:` disambiguation.

### Phase 4 — `deepen-plan/SKILL.md`, templates reference, ADR-176 (GREEN)

Cursor entry/exit/halt semantics; frontmatter template; ADR.

### Phase 5 — Verify

Contract test, sibling assertions, full suite.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — Phase 0.7 is correctly positioned.** In `plan/SKILL.md`, the line number of
   `^### 0\.7\.` is greater than that of `^### 0\.6\.` and less than that of
   `### 1. Local Research`. *(All three anchors verified present today; `### 1. Local Research` is at
   `:131`.)*
2. **AC2 — Filename derivation moved.** `grep -cF 'Convert title to filename' plan/SKILL.md` returns
   1, at a line number below `### 1. Local Research`. *(Today: 1, at `:279` — after research.)*
3. **AC3 — Research is persisted.** `plan/SKILL.md` Phase 1.7 prescribes writing a
   `## Research Insights` section to the plan file. *(Today `plan` writes no research section; this is
   the line that makes the checkpoint pay.)*
4. **AC4 — Token vocabulary stays in `plan`.** `plan/SKILL.md` contains `research`, `drafting`,
   `gates`, `finalize` as cursor values; `one-shot/SKILL.md` contains `pipeline_resume:` and
   `deepening` but none of the other four as cursor tokens.
5. **AC5 — Frontmatter-bounded parsing.** Every prescribed read of `pipeline_resume:`/`branch:` in
   all three skills is bounded to the first `---`…`---` block; the contract-test fixture proves the
   reader ignores a column-0 body occurrence.
6. **AC6 — D4's table is total and applied on both paths.** `one-shot/SKILL.md` contains an arm for
   each of: absent+passes, absent+fails, `deepening`, known-token, unrecognized — and the success
   path (`### Plan File` extraction) evaluates the same conjunct, retaining the existing positive
   section assertion (`grep -cF 'frontmatter + Overview + Acceptance Criteria'` ≥ 1 — **retained**).
7. **AC7 — Resume is bounded.** `resume_attempts` appears in the skeleton; a cap of 2, a
   strict-advance rule, and a cursor-deleting terminal arm are all specified; `deepen-plan` halts
   delete the cursor.
8. **AC8 — Gates re-run on resume.** `plan/SKILL.md`'s resume block states that Phase 0.6 and the
   conditional gates 2.7–2.11 and Phase 3 re-run unconditionally, citing ADR-032.
9. **AC9 — Selector is bounded, tie-broken, archive-excluded.** `one-shot/SKILL.md`'s selector globs
   `plans/*.md` (non-recursive), names a tiebreak, and falls back to the date glob.
10. **AC10 — Contract test green and a real coupling.**
    `bun test plugins/soleur/test/plan-skeleton-checkpoint.test.ts` passes; the fixture assertion
    fails if the reader is reverted to an unbounded `^pipeline_resume:` scan (proven by the fixture
    itself in CI, not by a one-off manual demo).
11. **AC11 — ADR exists and is wired.** `ADR-176-*.md` exists with `status: accepted`, an
    `amends: [ADR-015]` edge, and citations to ADR-032/121/126/089/026/151/083/132.
12. **AC12 — Recovery verdict is recorded.** `one-shot/SKILL.md`'s `## Plan Phase` block writes a
    `Recovery verdict:` line naming the verdict, the cursor value, `resume_attempts` and the selector
    used. Without it a mis-resume is indistinguishable from a normal run, and the operator's only
    symptom is a double-billed pipeline.
13. **AC13 — Full suite green.** `bash scripts/test-all.sh` passes, and
    `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes over all
    changed docs (each gate's own invocation, not a reconstruction).

### Post-merge (operator)

None. Every step is automatable in-session — no vendor console, no credential mint, no infrastructure
change.

## Test Scenarios

> **Superseded (v3).** T1-T15 below all exercise the `pipeline_resume:` cursor, which was assessed
> and dropped — see the banner at the top of this file. They are retained as a record of what the
> rejected design was expected to do. The scenarios that apply to what SHIPPED are pinned
> mechanically by `plugins/soleur/test/plan-skeleton-checkpoint.test.ts` (18 assertions, 8 mutations
> proven RED against a green control):
>
> | Shipped scenario | Pinned by |
> |---|---|
> | Skeleton is written before any Task spawn | Phase 0.7 sits after 0.6 and before Phase 1 |
> | Filename derived exactly once, pre-research | single `Convert title to filename` site, before Phase 1 |
> | Research persisted, and only when whole | `## Research Insights` after 1.7 + the single-Edit rule |
> | A finished MINIMAL plan is not re-planned | `## Overview` absent from MINIMAL; not a conjunct |
> | Completion predicate agrees with the templates | `## Acceptance Criteria` in all three detail levels |
> | Body `branch:` never selects a plan | body-collision fixture, executed |
> | A `---` block in the body never re-arms the read | re-entrant-range fixture, executed |
> | A quoted `branch:` still resolves | quoted fixture (the non-empty positive control) |
> | No leading frontmatter reads as empty | no-frontmatter fixture (#4724) |
> | The cursor stays dropped | drift guard over `plugins/soleur/skills/` |
>
> There is no browser or API surface in this change, so `/soleur:qa` has nothing executable to run.


| # | Scenario | Expected |
|---|---|---|
| T1 | Fresh run, no existing file | Skeleton written before any Task spawn; cursor `research` |
| T2 | Stall right after skeleton write | Resume at `research`; **Phase 0.6 re-runs** (ADR-032), 0.5 skipped |
| T3 | Stall inside the research fan-out, after 1.7 | `## Research Insights` is on disk; resume at `drafting` does not re-spawn the fan-out |
| T4 | Stall after Phase 2.5 | Resume at `finalize`; gates 2.7–2.11 + Phase 3 still re-run |
| T5 | Session Summary emitted, cursor still present, sections incomplete | Success path resolves Resume, not `/work` |
| T6 | Cursor absent but Acceptance Criteria missing | **Undetermined** → full re-run, not advance |
| T7 | Legacy plan: no cursor, all sections, `status: draft` in frontmatter | Complete — legacy `status:` is never consulted |
| T8 | Freeform invocation with no `#N` | Slug derived from the description; premise gate no-ops |
| T9 | Same-branch duplicate plan files | Tiebreak selects deterministically; `plans/archive/` excluded |
| T10 | Deterministic re-stall at the same token | Strict-advance trips the cap; cursor deleted; one full re-run, then stop + `action-required` |
| T11 | `deepen-plan` HALT at §4.6 | Cursor deleted with reason; **not** replayed as a crash |
| T12 | Direct `/plan`, operator picks `/work` not `/deepen-plan` | Cursor already deleted at plan finalization; nothing stale ships |
| T13 | A plan whose **body** contains the cursor key at column 0 (this file) | Frontmatter-bounded reader returns empty |
| T14 | Phase 0.7 Write denied by the guard hook | Retry minimal, then proceed skeleton-less; run continues |
| T15 | Attached session resumed | Mode flag preserves the review gates; no silent headless flip |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Stub plan advanced to `/work`** (highest severity) | D4 conjunctive on **both** paths; T5, T6. `work/SKILL.md:130` provides no net, so this is the load-bearing guard |
| Unbounded resume re-spend | D5 cap + strict advance + terminal arm; T10, T11 |
| Cursor read from a document body | D3a bounded parsing + shipped fixture; T13 — reproduced against v1, so this is a regression test, not a hypothetical |
| Resume inherits unverified gates | D6 re-runs them, per ADR-032; T2, T4 |
| Skeleton is untracked for the research window | Accepted residual risk: `ls`/frontmatter find it, but worktree recreation and `worktree-manager.sh:1751`'s plain `mv` would not. **v1 wrongly claimed one-shot's scope diff would catch it — that is a three-dot diff over committed files and cannot see an untracked one.** Checkpoint-commit deferred to a follow-up |
| Abandoned skeletons committed | Exact-path `git add` (D8) |
| Merged/archived plan misread as in-flight | Cursor deleted at finalization — inert by construction |
| Maintenance drift as phases are reordered | Contract test asserts position and vocabulary ownership; residual diligence cost acknowledged |

## References & Research

- Issue #7418; surfaced by `/one-shot #7349` (PR #7416)
- `plugins/soleur/skills/plan/SKILL.md:6-17,92,122,127,131,247,263,279,349,369,412,742-748,759-767,882-883,1013`
- `plugins/soleur/skills/one-shot/SKILL.md:8-24,97,108,138,172,181,195-201,206,210,238`
- `plugins/soleur/skills/deepen-plan/SKILL.md:396,452,560`; `workflows/deepen-plan.workflow.js:54-56`
- `plugins/soleur/skills/plan/references/plan-issue-templates.md:18-22,148-152,302-306`
- `plugins/soleur/skills/preflight/SKILL.md:492,500,708`; `work/SKILL.md:130-132`
- `plugins/soleur/test/components.test.ts:16`; `lib/workflow-fidelity.ts:57,63`; `scripts/test-all.sh:732`
- `scripts/lint-infra-no-human-steps.py:74-80,227-228`; `.claude/hooks/iac-plan-write-guard.sh`
- `.github/workflows/review-reminder.yml:67,84,124` — the canonical frontmatter-bounded reader
- `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh:103-104,166`;
  `git-worktree/scripts/worktree-manager.sh:1737-1754,2130`
- ADRs: ADR-015, ADR-026, ADR-032, ADR-083, ADR-089, ADR-112, ADR-121, ADR-126, ADR-132, ADR-151
- Learnings: `2026-05-15-subagent-crash-recovery-via-on-disk-artifacts.md`,
  `2026-05-15-one-shot-plan-subagent-cwd-divergence.md`,
  `2026-05-17-planning-subagent-exceeded-scope-and-summary-vs-disk-drift.md`,
  `2026-05-11-write-tool-rejects-post-git-mv-path-until-read.md`,
  `2026-05-15-ci-sentinel-paren-safety-substring-match-against-canonical-prose.md`,
  `2026-07-06-ac-self-reference-grep-trap-and-verify-config-enabled-state.md`,
  `2026-04-02-one-shot-dead-resolve-todo-parallel-step.md`,
  `2026-08-06-the-collision-gate-cleared-the-issues-i-passed-it-not-the-one-i-worked-on.md`,
  `2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md`
- Functional-overlap discovery: 2 registries queried; 4 Tier-3 unverified candidates, all discarded.
  No community dependency — the contract is between Soleur's own prompts.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`
  Phase 4.6.
- **A body occurrence of a frontmatter key is indistinguishable from the real one to a line-anchored
  reader.** The repo's canonical gsub awk form (`plan/SKILL.md:1013`) is correct only for a key that
  cannot appear in a body. Any key a document might *document* needs `sed -n '/^---$/,/^---$/{…}'`
  bounding. v1 of this plan shipped the unbounded form and was measurably misread as in-flight by its
  own example block — the fixture in Phase 1 exists so that cannot recur.
- **"Cursor absent ⇒ complete" is a negative assertion and must never stand alone.** Absence has
  causes other than completion. AND it with a positive assertion about the content the cursor claims
  exists, or the first non-completion cause silently advances a stub.
- **A designed refusal must not look like a crash.** `deepen-plan`'s HALT gates are correct terminal
  outcomes; a recovery mechanism that replays them loops forever on the first try, deterministically,
  with no transient failure involved. Terminal states must clear the resume cursor.
- **Reserving tokens inside a free-text field is a migration, not a convention.** `status:` in
  `plans/` holds 338 files across 44+ values; three reviewers independently measured it after v1
  claimed "~10". Before reusing an existing key for machine semantics, count the corpus.
- `plugins/soleur` tests are **bun test**, not vitest.
- **Quoting a guard's trigger list is itself a trigger.** This plan's first Write was blocked by
  `.claude/hooks/iac-plan-write-guard.sh` because a Sharp Edge enumerated the guard's own actor and
  imperative tokens verbatim. Point at the script's lists; never reproduce them — and never reach for
  the `iac-routing-ack` opt-out to silence a false positive, since it asserts a real infrastructure
  step was reviewed.
