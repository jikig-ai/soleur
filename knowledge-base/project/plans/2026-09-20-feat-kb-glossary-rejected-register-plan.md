---
title: "feat(kb): domain glossary + rejected-request register wired into triage"
date: 2026-09-20
slug: feat-kb-glossary-rejected-register
branch: feat-one-shot-8289-kb-glossary-rejected-register
issue: 8289
closes: 8289
type: feature
lane: cross-domain
priority: p2-medium
domain: product
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

> **CPO sign-off required at plan time before `/work` begins.** It is recorded in
> `## Domain Review` → Product/UX Gate → Findings, with five conditions, all adopted into this plan.
> `soleur:engineering:review:user-impact-reviewer` is armed for the review phase by
> `plugins/soleur/skills/review/SKILL.md`'s conditional-agent block.
>
> `lane: cross-domain` is derived, not defaulted: four domains are relevant (engineering, support,
> legal, product). No `spec.md` existed at plan time, so there was nothing to carry a lane forward from.

## Overview

Bundle 3 of the five-bundle port from the `mattpocock/skills` peer audit. Soleur already keeps
decisions (ADRs), learnings and deferrals, but it keeps no shared vocabulary and no record of what
was decided against. The consequence is that every agent invents its own nouns and every returning
feature request is argued from scratch.

Four deliverables, scoped exactly to issue #8289:

- A committed ubiquitous-language glossary under `knowledge-base/`, plus the format doc that governs
  it and a write discipline that sharpens a term the moment a decision settles it. Consumers read it:
  `brainstorm`, `plan`, `spec-templates`, `architecture`, `triage`, and bundle 1's rephrase skill.
- A rejected-request register: one file per rejected concept recording why, checked at triage by
  concept similarity rather than keyword. An already-implemented `wontfix` is never written there —
  that would seed the dedup check with rejections that never happened.
- Two intake pre-checks in the triage skill and the ticket-triage agent: a redundancy search keyed on
  domain concept with the searched surfaces reported, and a prior-rejection lookup against the
  register.
- A questionnaire-generation skill that converts a decision the founder cannot answer into a
  document aimed at whoever can, interviewing only about the send rather than the subject.

## Enhancement Summary (deepen-plan)

**Deepened on:** 2026-09-20 · **Halt gates:** 4.6, 4.7, 4.8, 4.9, 4.10, 4.11 — all pass
**Preceded by:** a six-reviewer `plan-review` panel whose findings are logged as R1–R27 below.

### Halt-gate results

| Gate | Verdict |
|---|---|
| 4.6 User-Brand Impact | PASS — section present, threshold `single-user incident`, concrete artifact and vector |
| 4.7 Observability | PASS — all five fields present and non-placeholder; `discoverability_test.command` starts with `bash` (allowlisted) and contains no `ssh` |
| 4.8 PAT-shaped variable | PASS — zero matches across all four PAT patterns |
| 4.9 UI-wireframe | SKIP — no UI-surface path in either file list; the two `components/**/*.tsx` matches are prose explaining that the override does not fire |
| 4.10 Encryption Posture | SKIP — no persistent store, no cross-component connection; the one `*.tf` match is prose stating the globs match nothing |
| 4.11 Guard Contract | PASS — `lint-guard-contract.py` green, and the **adequacy read** passes: the Assembly names the *chokepoint* (the glob, plus three enumerated dispatches) rather than a snapshot of today's members |

### Deepen findings applied

1. **Every cited rule ID verified active.** All 15 `(hr|wg|cq|rf|pdr|cm)-*` tokens in the plan resolve to
   an `[id: …]` in `AGENTS.md`/`AGENTS.rules.md` or to a live row in `scripts/migrated-rule-ids.txt`
   (`cq-ac-must-not-depend-on-concurrent-sessions`; plus `wg-architecture-decision-is-a-plan-deliverable`
   in `decision-challenges.md`). **Zero fabricated, zero retired** — the fabrication class that shipped
   five bad citations in #3486.
2. **Every prescribed GitHub label exists.** `action-required`, `follow-through`, `compliance/critical`,
   `deferred-scope-out`, `code-review`, `meta/machinery`, `wontfix` — all confirmed against
   `gh label list --limit 300`.
3. **The emitter template's extension is corrected from `.md` to `.template`**, matching bundle 2's direct
   precedent. Three measured reasons, all of which would have bitten at `/work`: every one of the six
   files in `constraint-scaffold/references/` uses `.template`; `scripts/markdown-lint.sh` scopes to
   `git ls-files '*.md'`, so a `.md` template full of `<placeholder>` tokens and `>` answer stubs would
   fight the linter; and `components.test.ts`'s references/-reachability assertion walks **only** `.md`
   files, which is why `boundary-readme.template` is legitimately un-named from its own `SKILL.md`
   without being an orphan. The two genuine prose references (`glossary-format.md`,
   `rejected-request-register.md`) keep `.md` and now carry an explicit must-be-named-from-`SKILL.md` note.
4. **`compound` is the tightest lifecycle ceiling this plan touches** — 54256 / 57000, **2744 bytes** of
   headroom, against `brainstorm`'s 6372 and `plan`'s 4729. R3 added that file, so the constraint is new;
   the sharpening trigger must be a sentence, not a section. The ceiling ratchets down-only.
5. **Precedent diff run for all three pattern-bound behaviours** (the lint's dispatch shape, the probe's
   exit contract, and the `.test.sh`-under-`scripts/` question) — recorded as its own subsection rather
   than asserted. The third one is what confirmed R20's relocation was right rather than merely
   convenient.

6. **Verify-the-negative pass (Phase 4.45): twelve negative claims checked by command, zero
   contradictions.** Every absolute or negative assertion this plan rests on was re-grepped against the
   named or implied implementation file, and all twelve came back CONFIRMS with a `file:line` citation —
   including the four that would have been most expensive to discover wrong at `/work`: that
   `scripts/lint-agents-rule-budget.py` counts *only* `AGENTS.md` + `AGENTS.rules.md` (so the hook pointer
   genuinely costs zero always-loaded bytes), that `skill-body-budget.json` has exactly ten ceiling keys
   and `compound` is one of them, that `.openhands/skills/ticket-triage/SKILL.md` carries neither the
   `eval-gate` markers nor the `meta/machinery` rule, and that `scripts/*.test.sh` is absent from
   `test-all.sh --print-suite-globs`. One refinement from that pass: `compound`'s headroom is 2744 bytes
   raw and **2886 after the frontmatter strip**, which is the basis the lint actually measures.
   Nothing here needed changing — which is the point of running it rather than assuming it.

### What deepen-plan did NOT change

The research fan-out found no new best-practice or framework guidance to fold in, and that is the honest
result rather than a gap: this plan ships Markdown and one shell lint into an existing plugin, so its
correctness surface is entirely **this repository's own conventions** — which is what the six-reviewer
panel and the gates above measured. No Context7 query, no web search and no external-pattern lookup would
have caught any of R1–R27, because every one of them was a fact about this repo that only a command could
settle.

## Research Insights

### Premise Validation (Phase 0.6)

Eleven premises were checked by command. Six held; **eight diverged** and each divergence changes the
plan's shape. Nothing here is inferred — every row names the command that produced it.

| # | Premise as stated | Measured reality | Plan response |
|---|---|---|---|
| P1 | Bundle 1 = #8287 (PR #8297 merged), bundle 2 = #8288 (PR #8352 merged `53a8fac7f`) | HOLDS. `gh issue view` → both CLOSED; `gh pr view` → #8297 merged 2026-09-19T04:04Z, #8351 merged 05:19Z, #8352 merged 21:28Z | Proceed |
| P2 | #8290 and #8292 must stay open | HOLDS. Both OPEN | Non-Goal; no `Closes` for either |
| P3 | Tier 1 audit entry "landed via PR #8284" in `knowledge-base/product/competitive-intelligence.md` | **STALE.** PR #8284 is still `OPEN` (`mergedAt: null`); `git show origin/main:knowledge-base/product/competitive-intelligence.md \| grep mattpocock` returns nothing, and so does the branch copy | Cite `plugins/soleur/NOTICE` (which does carry the pinned SHA) as the provenance authority, never competitive-intelligence.md. No dependency on #8284 landing |
| P4 | Bundle 1 shipped `operator-explain`, which must read the glossary | **WRONG NAME.** `plugins/soleur/skills/operator-explain/` does not exist; `grep -rn operator-explain` returns zero. Bundle 1 shipped the peer `wait-what` as **`operator-rephrase`** (`ls -d plugins/soleur/skills/operator-*` → `operator-bootstrap`, `operator-digest`, `operator-rephrase`) | Wire `operator-rephrase`. See P5 — this is not optional |
| P5 | `operator-rephrase` is a consumer to wire | **STRONGER THAN THAT.** Its `## Vocabulary` section says verbatim: *"v1 ships with no vocabulary source, and that is the durable state. There is no repository glossary to draw approved terms from… A repository glossary is a separate piece of work tracked in #8289; if one lands later, this skill can cite it then."* | Landing the glossary makes shipped prose FALSE. Rewriting that paragraph is a **required** deliverable, not a courtesy wiring |
| P6 | `origin/main` tops at ADR-230, so a new ADR starts at **ADR-231** | **ALREADY CLAIMED.** Enumerated across all 97 `origin/*` refs: ADR-231 is taken by `origin/feat-one-shot-8361-workflow-size-limit` (`ADR-231-workflow-files-are-byte-budgeted…`). Two further branches claim a *different* ADR-230 title (`feat-8322-affected-test-gate`, and #8360's `feat-one-shot-auto-inngest-pin-bump`) | Next free is **ADR-232**. Re-derive across every `origin/*` ref immediately before merge |
| P7 | `plugins/soleur/skills/triage/SKILL.md` is the issue-intake surface | **IT IS NOT.** Its own description: *"This skill should be used when triaging legacy local todo files in `todos/`. For GitHub issues, use soleur:support:ticket-triage agent."* Workflow is Step 1 present finding → Step 2 handle decision → Step 3 loop → Step 4 summary, over files in `todos/` (which exists and is populated). `grep -cniE 'dedup\|duplicate\|reject\|declin'` → **0** | Both pre-checks still land there, but scoped to what a `todos/` finding *is* — an internally-generated review finding that can legitimately restate an already-built or already-refused concept. Recorded as a reconciliation row, not silently reinterpreted |
| P8 | `plugins/soleur/agents/support/ticket-triage.md` can perform the register write | **READ-ONLY BY DECLARATION.** Its Sharp Edges: *"Do not close or modify issues. Read-only access via `gh issue list` and `gh issue view`."* | The agent gets READ-only pre-checks; the register **write** lands on the attended `triage` path behind a confirmation gate. An agent that cannot close an issue cannot be the one that records why it was closed |
| P9 | The unattended daily pass will pick the pre-checks up | **IT CANNOT — but not for the reason I first wrote.** `.github/workflows/scheduled-daily-triage.yml` is **deleted**; `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` says *"Source: extracted from .github/workflows/scheduled-daily-triage.yml (deleted in the same commit)"* and carries a self-contained `DAILY_TRIAGE_PROMPT` referencing no skill or agent file. My first reading was that its `--allowedTools` had no file-read verb; the product lens corrected me and the correction is right. Line 171 **does** grant `Read,Glob,Grep`. The real blocker is line 216: *"This cron never clones, so `gh` runs from…"* — there is **no working tree**, so `Read` has nothing to point at | Out of scope and out of reach. Deferred to a filed issue whose named blocker is the **absent checkout**, not a missing tool. This distinction is load-bearing: a follow-up written against the wrong cause gets closed by a one-line `--allowedTools` change that fixes nothing |
| P10 | No `*glossar*` file exists | **KB-SCOPED ONLY.** `find knowledge-base plugins -iname '*glossar*'` returns `plugins/soleur/docs/pages/glossary.njk` — a **public SEO** glossary of 10 product-category terms (Company-as-a-Service, MCP, skill, vibe coding), pinned by `plugins/soleur/test/seo-aeo-drift-guard.test.ts` (≥8 canonical terms + a `DefinedTermSet` JSON-LD block) | Named explicitly, with a declared audience split and a one-line cross-pointer. `operator-rephrase` §Vocabulary already adjudicated it: *"do not point at `plugins/soleur/docs/pages/glossary.njk` — that is marketing surface"* |
| P11 | Phase 5 runs `scripts/lint-skill-body-budget.py` | **WOULD ERROR.** `--base` is `required=True`; the bare form exits non-zero on a missing argument | Phase 5 invokes it as `--base <merge-base>` |

Also corrected: the shipped skill count is **100**, not 99 and not the 101 an earlier revision of this plan claimed. `ls -d plugins/soleur/skills/*/ | wc -l` returns 101 because `flag-bootstrap/` holds only a `SETUP.md`; the producer every consumer actually uses is `find plugins/soleur/skills -type f -name SKILL.md | wc -l` → **100**, which is what `scripts/sync-readme-counts.sh --check` reports and what `discoverSkills()` returns. The transition is therefore **100 → 102**. The
convention claim the naming contract rests on still holds exactly: `0` shipped skills match
`^(create|setup|manage|generate)-`.

`gh repo view --json isPrivate` → **`false` (PUBLIC)**. `hr-third-party-content-grep-on-undertaking`
therefore binds at full force and is **pre-merge only** (git permanence).

### Property List (Phase 0.6b)

Each deliverable restated as an observable outcome, so a mechanism can be compared against it.

- **PR-1 (vocabulary).** An agent resolving a term finds one committed, greppable, plain-text
  definition, and a second agent in a later session resolves the same term the same way.
- **PR-2 (write discipline).** When a session settles what a term means, the settlement is recorded
  at that moment rather than batched, so the artifact does not drift behind the decisions.
- **PR-3 (durable no).** A concept refused once is discoverable as refused, by concept rather than by
  keyword, together with the reason, by whoever handles the next request for it.
- **PR-4 (no false rejections).** Nothing that was *built* is ever discoverable as *refused*.
- **PR-5 (auditable redundancy).** A claim that a request is already implemented carries the surfaces
  that were searched, so the claim can be checked rather than taken on trust.
- **PR-6 (third bucket).** A question that is neither technical (resolve it) nor authorization / cost
  / scope (ask the founder) has a route: a document aimed at the person who holds the answer.
- **PR-7 (send-shaped interview).** The founder is asked only what they can always answer — who it
  goes to and what is needed back — never the subject matter they invoked the skill because they
  lacked.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Why it is cut |
|---|---|---|
| A fresh redundancy-search procedure specified from scratch at triage | PR-5 | `plugins/soleur/skills/brainstorm/SKILL.md` `#### 1.1 Research (Context Gathering)` **already specifies it, more sharply**: *"A negative carries only the scope that produced it — 'I deliberately did not look there' is a reason to hedge, never a reason to conclude"*, plus the functional-noun re-sweep (`git ls-files \| grep -iE '<fn1>[-_ ]<fn2>'`, where the `[-_ ]` class is load-bearing) and the two classes `INDEX.md` excludes per ADR-174. The triage pre-check **cites** that section instead of restating it; a second copy would diverge |
| A second glossary term-store, or extending `glossary.njk` | PR-1 | `glossary.njk` is Nunjucks with `{{ site.url }}` interpolation and a JSON-LD tail — not greppable plain text — and its own preamble requires every entry to *"cite an external source"*, which `lane`, `shard` and `rung` have none of. Its term list is public ABI under `seo-aeo-drift-guard.test.ts` |
| Restating each term's definition in the glossary | PR-1 | Where a canonical definer already exists the entry is a **pointer**, not a restatement (e.g. `lane` → `brainstorm/references/brainstorm-domain-config.md` `## Lane Inference`, cited by `brainstorm/SKILL.md`). A second copy drifts from the first — the exact failure `operator-rephrase` §Register already names about `operator-digest` |
| A new `AGENTS.md` rule for the glossary read/write discipline | PR-1, PR-2 | `cq-agents-md-tier-gate`: a domain-scoped rule (skills, docs) belongs in its enforcing skill, never AGENTS.md. Cost avoided: ~600 B body + ~55 B index pointer against 1080 B of headroom to the WARN tier |
| A prior-rejection check inside the unattended Inngest pass | PR-3 | Unreachable: `DAILY_TRIAGE_PROMPT`'s `--allowedTools` has no file-read verb (P9). Deferred with a named blocker, not silently dropped |
| Seeding the store with a **synthesized** example entry | PR-3 | A synthesized example is a rejection that never happened — it violates PR-4 directly. **This row was originally written as "the store ships empty", and that is now superseded:** the product lens found a real, dated, concept-scoped refusal already on record (the server-side-Playwright decision at `knowledge-base/product/roadmap.md`), so AC-4c seeds exactly that one. Seeding a *recorded* rejection satisfies PR-3 without touching PR-4; seeding an *invented* one remains cut. Two reviewers caught the contradiction between this row and AC-4c before `/work` — the row is corrected rather than deleted so the reasoning stays auditable |

### Repo facts that constrain the plan (all measured)

- **Skill description word budget is at `2499/2499` — zero headroom.** Authority:
  `SKILL_DESCRIPTION_WORD_BUDGET` in `plugins/soleur/test/components.test.ts`; measured through the
  same `discoverSkills()`/`parseComponent()` path the test uses → 100 skills, 2499 words. Bundle 1 set
  the precedent twice (`+27 for #8287 (operator-rephrase…)`, `+30 for #8287 (operator-bootstrap…)`),
  each logged "against a N/N zero-headroom baseline".
- **`B_ALWAYS = 42920`** (`python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`);
  `B_ALWAYS_WARN = 44000`, `B_ALWAYS_REJECT = 46000`, `PER_RULE_CAP = 600`. `AGENTS.rest.md` no longer
  exists, so every rule body is counted. `hr-technical-fork-is-not-an-operator-question`'s body is
  **315 bytes**.
- **`scripts/lint-rule-bodies.py --check` blocks any `hr-*`/`wg-*` body edit** without a hash-bound
  ack. Documented remedy: edit the body → `python3 scripts/lint-rule-bodies.py --write` (regenerates
  `.claude/rule-body-hashes.txt`) → append `<id>|<sha256>|<date>|<PR>|<reason>` to the CODEOWNERS-owned
  WORM file `.claude/rule-weakening-acks.txt`. Abundant precedent for clarification-not-weakening acks
  (e.g. `hr-when-in-a-worktree-never-read-from-bare|…|2026-07-07|6183|Added non-bare Concierge caveat…
  (clarification, not a weakening…)`).
- **Exactly four eval-gated blocks** (`plugins/soleur/skills/eval-harness/gated-skills.json`):
  `go-routing`, `ticket-triage`, `lane-inference`, `incident-threshold`. `triage/SKILL.md` is **not**
  gated. The `ticket-triage` block wraps only the severity-assignment bullet. Costs:
  `promptfooconfig-go-routing.yaml --repeat 3` ≈ **144 API calls**; `-ticket-triage` ≈ **108**.
  `--dry-run --target <id>` prints the estimate with zero calls; the gate is fail-closed on any error.
- **`plugins/soleur/test/skill-body-budget.json` pins ceilings for exactly 10 lifecycle skills**
  (budget keys = FSM keys ∪ destinations ∪ `ONE_SHOT_CHILD_SKILLS`). Current headroom on the files this
  plan edits: `brainstorm` 134628/141000 (6372 B), `plan` 115271/120000 (4729 B). `triage`,
  `spec-templates`, `architecture` and `operator-rephrase` are **not** governed. Registering a new
  skill in `workflow-fidelity.ts` would pull it into this ratchet.
- **`plugins/soleur/commands/help.md` carries no literal per-skill list.** It is a generator template:
  *"[List all skills found with brief descriptions, grouped by the token before the first hyphen:
  flag-\*, cron-\*, provision-\*, release-\*, resolve-\*, legal-\*, operator-\*, kb-\*, and so on.]"* —
  **triplicated** across the Claude Code / Devin CLI / Grok Build blocks, each of which also carries
  *"The operator-\* family is not routed from /soleur:go"*. That line is the in-repo precedent for
  declaring a family not-routable.
- **`plugins/soleur/commands/go.md`** routing table sits between
  `<!-- eval-gate:block:go-routing:start -->` / `:end`, 9 rows, ordered by evaluation priority with
  `default → soleur:brainstorm` last and one row carrying an explicit *"Must fire BEFORE the `review`
  row"* ordering constraint.
- **Test-suite registration.** `scripts/lint-orphan-test-suites.sh` tracks `*.test.sh` only;
  `SUITE_GLOBS` (from `scripts/test-all.sh --print-suite-globs`) glob-registers
  `plugins/soleur/test/*.test.sh`. A `*.test.ts` under `plugins/soleur/test/` is auto-discovered by
  `run_suite "plugins/soleur" bun test plugins/soleur/`, and root `bunfig.toml` preloads
  `./plugins/soleur/test/lib/git-tripwire.ts`. The `git-fixture-env.sh` sourcing requirement binds
  **shell** suites only.
- **`knowledge-base/INDEX.md` is tracked and generated** (`scripts/generate-kb-index.sh`, total 6659
  files) with a dedicated merge driver (`scripts/merge-kb-index.sh`, installed by `npm prepare`), and
  `generate-kb-index.sh --check` is gated through `plugins/soleur/test/kb-index-merge-driver.test.sh`.
  `conventions` is already a valid facet in `knowledge-base/kb-categories.txt`.
- **`plugins/soleur/NOTICE`** carries the `mattpocock/skills` stanza at the pinned SHA with `Used in:`
  and `Portions adopted:` lists, extended once per bundle with a trailing `(#8287)` / `(#8288)`, and
  records per bundle which upstream elements were **deliberately not adopted**.
- **Attribution placement precedent**, immediately after the closing frontmatter fence:
  `<!-- Inspired by mattpocock/skills/skills/engineering/wizard/ (MIT, Copyright (c) 2026 Matt Pocock). -->`
  in `plugins/soleur/skills/operator-bootstrap/SKILL.md`.
- **Emitted-artifact precedent (bundle 2, from NOTICE, verbatim):** the `server/README.md` that
  `constraint-scaffold` emits *"is Soleur-authored, shares no sentence with either peer file (checked by
  an 8-word shingle comparison at ship), and carries no credit… The template the README is rendered
  from carries the attribution comment; the emitter strips that first line."* Governed by
  `knowledge-base/project/constitution.md` line 192 (vendored credit kept in the corpus, stripped from
  emitted output).
- **Existing shingle instrument:** `plugins/soleur/test/agent-originality.test.ts` (162 L, `SHINGLE_N =
  8`) compares Soleur agents *against each other*, and already carries both an instrument self-check
  describe block and a "bodies actually produce shingles (guards a vacuous pass)" floor — the shape to
  copy, not the comparison to reuse.

### Peer sources read at the pinned SHA

Fetched read-only with `gh api repos/mattpocock/skills/contents/<path>?ref=c55ee46073ed923f86ce59a5eb3b6d895095d1b7`.
Line counts match the issue's measured basis exactly.

| Peer path | Lines | Feeds |
|---|---|---|
| `skills/engineering/domain-modeling/SKILL.md` | 74 | `kb-glossary` write discipline (challenge-against-glossary, sharpen-fuzzy-language, update-inline, "a glossary and nothing else") |
| `skills/engineering/domain-modeling/CONTEXT-FORMAT.md` | 60 | glossary format reference (opinionated single term, `_Avoid_` list, tight definitions, project-specific-only test) |
| `skills/engineering/triage/OUT-OF-SCOPE.md` | 105 | register convention (one file per concept, durable reason, concept-not-keyword matching, and the built-is-not-rejected prohibition) |
| `skills/engineering/triage/SKILL.md` (step 1 only) | 112 | the two intake pre-checks |
| `skills/productivity/to-questionnaire/SKILL.md` | 54 | `questionnaire-generate` (grill-the-send, two-exchange interview, `<questionnaire-template>` shape) |

`skills/engineering/domain-modeling/ADR-FORMAT.md` (2733 B) is deliberately **not** read into scope:
Soleur's ADR format is already governed by `plugins/soleur/skills/architecture/references/adr-template.md`.

### Institutional learnings that bind this plan

- `knowledge-base/project/learnings/2026-09-18-the-design-pass-deleted-the-mechanism-the-panel-would-have-reviewed.md`
  (bundle 1) — run the design pass **before** the panel; a correct fix can introduce second-order P1s
  at the artifact's destination. Ask what else lives where a new artifact lands.
- `knowledge-base/project/learnings/2026-09-19-i-classified-nineteen-failing-files-from-the-first-one-i-read.md`
  (bundle 1 ship) — never classify a multi-file failure from its first named failure; enumerate the
  whole set first.
- `knowledge-base/project/learnings/2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md`
  (bundle 2, ADR-229) — a regenerated file that every sibling PR also regenerates cannot stay
  mergeable. Directly relevant to `knowledge-base/INDEX.md`; the merge driver is the existing answer.
- `knowledge-base/project/learnings/2026-09-18-every-p1-lived-in-a-guard-i-added-and-two-fixes-reintroduced-their-class.md`
  — deterministic lints found three P1s before any agent ran; a file-selected suite set cannot see
  repo-global ratchets. This is why Phase 5 runs the ratchets by their own invocations.
- `knowledge-base/project/learnings/2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in.md`
  (ADR-193) — count **axes**, not rows; floors count thresholds, not rows.
- `knowledge-base/project/learnings/2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md`
  — the four vacuity classes; assert the negative property over the whole context, never a prefix.
- `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`
  — measure the budget at plan time; the cap in this learning (1800) is itself stale, which is the
  lesson: read the constant, never a remembered number.
- `knowledge-base/project/learnings/workflow-issues/2026-03-26-new-skill-budget-ceiling-and-convention-mismatch.md`
  — read three sibling `SKILL.md` files for the real convention; reference docs prescribe aspirational
  ones. This is the same defect `skill-structure.md` carries and that bundle 4 owns.
- `knowledge-base/project/learnings/2026-02-12-command-vs-skill-selection-criteria.md` — "should an
  agent invoke this autonomously?" decides skill vs command. Both new capabilities are agent-invoked,
  so both are skills.
- `knowledge-base/project/learnings/2026-09-18-a-census-cell-naming-two-markers-reports-the-union-as-each-member.md`
  — a count with a multi-noun label is a union; split the alternation before quoting it.
- `knowledge-base/project/learnings/2026-05-15-deepen-plan-must-grep-cited-attribution-on-main.md` —
  verify cited provenance against git history, not PR state. This is what caught P3.
- The **write-mostly artifact** precedent cited by `brainstorm/SKILL.md` `#### 1.1` (#2723):
  `knowledge-base/project/learnings/technical-debt/` shipped with structured frontmatter and **zero
  closures**. A register with no reader is that artifact — which is why PR-3's reader (the prior-
  rejection pre-check) must ship in the same increment or neither ships.

### Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (66 open) and matched every path
in `## Files to Create` / `## Files to Edit` with a standalone `jq --arg`.

- **#4133** — *follow-through(#4116): Schema parity test for `## Observability` block* — names
  `plugins/soleur/skills/plan/SKILL.md`. **Acknowledge.** Different concern entirely: #4133 wants a
  parity test for the Observability schema; this plan's edit to that file is a one-line glossary
  read-pointer. No shared region, no rework risk, no double-counting. #4133 stays open.

No other planned path appears in any open `code-review` issue.

## Research Reconciliation — Issue Body vs. Codebase

The issue body is the scope. Where it names an artifact that measurement contradicts, the intent is
honoured and the divergence is recorded here rather than silently reinterpreted.

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "bundle 1's `operator-explain`" reads the glossary | No such skill. Bundle 1 shipped `operator-rephrase` | Wire `operator-rephrase`, and rewrite its `## Vocabulary` paragraph, which currently asserts no glossary exists |
| Tier 1 entry "landed via PR #8284" | PR #8284 is OPEN; the entry is on neither `origin/main` nor this branch | Provenance authority is `plugins/soleur/NOTICE`. No dependency on #8284 |
| `triage/SKILL.md` is the issue-intake surface for the pre-checks | It triages **legacy local `todos/*.md`**. Its own body: *"The `soleur:review` skill now creates GitHub issues directly for all new findings. This triage skill handles only legacy local `todos/*.md` files that predate the GitHub issue integration."* | Pre-checks land there **scoped to what a todo finding is**, per the operator's stated direction. Two domain leaders recommended cutting them from this file entirely; recorded as a User-Challenge (DC-1) with the operator's direction kept as the default |
| `ticket-triage.md` performs the register write | Declared read-only: *"Do not close or modify issues."* | Read-only pre-checks there; the write procedure is owned by `knowledge-base/project/rejected/README.md` and gated by a lint plus a typed confirmation |
| The `wontfix` label carries the rejection signal | `wontfix` has been applied to **0 issues in repository history** (3,182 closed). Rejection is expressed as a `not-planned` closure (187 instances) | The register keys on the concept, not on a label. The convention names the `not-planned` closure state, not `wontfix` |
| The register serves "every re-arriving feature request" from outside | **Zero external filers.** 300-issue sample of the open backlog: 3 distinct authors, all internal — `deruelle` 215, `app/soleur-ai` 68, `app/github-actions` 17; 1,507 open issues total | v1 is an **internal concept-dedup index** over a large, largely agent-generated backlog. The requester-facing half (auto-posted closing comments, a public rejection record, the three-way "do you still feel the same way" prompt) is a **Non-Goal** — it designs for an audience that does not exist yet |
| A new ADR starts at ADR-231 | ADR-231 is claimed on `origin/feat-one-shot-8361-workflow-size-limit` | **ADR-232**, re-derived across every `origin/*` ref immediately before merge |
| `find knowledge-base -iname '*glossar*'` returns zero, so no glossary exists | True for `knowledge-base/`, but `plugins/soleur/docs/pages/glossary.njk` exists as a **public SEO** glossary | Declared audience split plus a one-line cross-pointer. Not a second copy |
| (my own working premise, corrected by the legal lens) root `knowledge-base/` ships to every plugin installer | **False.** `.claude-plugin/marketplace.json` sets `"source": "./plugins/soleur"`, so the payload is `plugins/soleur/` only. Customers receive the four-item seed tree `plugins/soleur/knowledge-base/` (`INDEX.md`, `kb-categories.txt`, `kb-tags.txt`, `project/learnings/` × 10 onboarding docs) — not Soleur's company KB | The glossary and the register are **Soleur's own corpus**, publicly readable because the repo is public, but not distributed as Software. No seed copy is added to the payload tree in v1 |

## User-Brand Impact

**If this lands broken, the user experiences:** a questionnaire document, written in the founder's
voice and sent under the founder's name to their accountant or lawyer, that either asks the recipient
something the founder already knows — wasting the single async round-trip they get — or restates
internal project detail the founder never intended to share outside the company.

**If this leaks, the user's workflow is exposed via:** the `## Context` section of an emitted
questionnaire, which is assembled from in-session material and then leaves the repository by email;
and, secondarily, via a publicly readable `knowledge-base/project/rejected/` whose `why` fields read as
a roadmap-negative, and which — if an entry ever names a person rather than a role — becomes a
personal-data record in a public git history.

**Brand-survival threshold:** single-user incident

Consequences, per plan Phase 2.6 Step 3: `requires_cpo_signoff: true` is set in the frontmatter, and
`user-impact-reviewer` is invoked at review time by `plugins/soleur/skills/review/SKILL.md`'s
conditional-agent block. The threshold also escalates the `plan-review` panel to include
`architecture-strategist` and `spec-flow-analyzer`.

## Architecture Decision (ADR/C4)

Detection fires: this plan stands up a **new durable KB substrate with its own authority** that two
existing mechanisms already partially cover, and a future engineer reading only the current ADRs would
be misled about which store answers "was this concept refused?".

### ADR

**ADR-232 — Rejected concepts are a distinct KB substrate from a `not-planned` close.**

Decision, one line: *rejected concepts are recorded as durable, concept-keyed files under
`knowledge-base/project/rejected/`, distinct from a GitHub `not-planned` closure (per-issue,
per-wording, unindexed by concept), from the `deferred-scope-out` label (the inverse — work intended to
be done, drained by `drain-labeled-backlog`), and from an ADR's rejected-alternatives table (scoped to
one decision's mechanisms); the concept file is the authority the intake pre-check queries before a
request is re-proposed.*

Authored via `/soleur:architecture` as an in-scope task of Phase 1, not a follow-up. The
`## Alternatives Considered` table is the **go/no-go gate** for the register, not paperwork after it,
and must carry all four rows below with the measurement that decides each:

| Alternative | Why not |
|---|---|
| `gh issue list --state all --search <keywords>` over `not-planned` closes — already treated as authoritative by `scripts/sweep-followthroughs.sh`, which refuses to reopen one because *"NOT_PLANNED is a deliberate wontfix. Reopening it would override a human"* | Keyed on the **request's wording**, not the concept — the exact failure the issue names, where "night theme" must reach `dark-mode`. Carries a decision but no concept key, no alias set, and no durable reason surviving the issue's closure |
| The `deferred-scope-out` label plus `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` | Opposite polarity. The live label description is *"Review-origin issue that meets a scope-out criterion"* — deferred means **will be done later** |
| ADR `## Alternatives Considered` tables | Records alternatives rejected *inside* an accepted decision, scoped to mechanisms. Five live spellings across 230 ADRs with no canonical form and no index — unqueryable by concept |
| `knowledge-base/project/learnings/technical-debt/` as the shape to copy | It is the cautionary precedent, not the model: structured frontmatter, 11 entries, **zero closures** (#2723). This is why PR-3's reader ships in the same increment |

### C4 views

**No C4 impact**, and here is the enumeration behind that conclusion rather than an assertion. All
three model files were read — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
— not grepped for the feature's own noun.

- **External human actors:** none added. The questionnaire's recipient (accountant, lawyer, vendor)
  never interacts with a Soleur container — the founder sends the document outside Soleur entirely, by
  email from their own client. No inbound surface is created, so there is no actor-to-container edge to
  model.
- **External systems / vendors:** none. Nothing in this plan calls a third-party API at runtime. The
  peer repo is read read-only at plan time via `gh api`; no runtime dependency is created.
- **Containers / data stores:** none. Every artifact is a tracked Markdown file in the existing
  `knowledge-base/` tree, already modelled as the knowledge-base container.
- **Actor↔surface access relationships:** unchanged. No ownership, tenancy or sharing boundary moves;
  the founder's access to `knowledge-base/` is what it already was.
- **Derived cardinalities:** `model.c4` embeds counts in edge prose (workflow totals, monitor counts)
  which `plugins/soleur/test/c4-count-parity.test.sh` gates as required context. This plan adds no
  workflow, no scheduled job, no monitor and no heartbeat slug, so no count moves — **backed by a green
  run of `plugins/soleur/test/c4-count-parity.test.sh`**, not by reasoning about actors (Phase 5).

### Sequencing

The decision is true the moment the register directory and its reader land, so ADR-232 ships at
`status: accepted` in this PR. No soak, no `adopting` interim.

## Observability

Plugin-prose and knowledge-base change plus one new shell lint. No file under `apps/*/server/`,
`apps/*/src/` or `apps/*/infra/` is touched and no new runtime surface appears, so the Phase 2.9 schema
is **not mandated**, and the honest conclusion is that this plan introduces **no observability layer at
all**: `scripts/lint-rejected-register.sh` is a local-development and CI deterministic gate.

**An earlier revision of this block cited "layer 7" for every failure mode, and that citation was
wrong.** Layer 7 (`cli-stdout-artifact`, defined in
`plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`) is *"a property of the
EXECUTION surface, not of where the file lives"*, and explicitly warns: *"Do NOT accept this layer for
code that only runs server-side — citing 7 there is an evasion."* The lint lives at repository root and
is wired into Soleur's own `lefthook.yml`; it is **not in the plugin payload**
(`.claude-plugin/marketplace.json` sets `"source": "./plugins/soleur"`), so it never executes on a
customer's machine. Layer 7 additionally requires that a synchronous stdout marker be paired with a
durable committed artifact carrying the same fields, and this gate's only signal is stderr in the
invoking session. Citing the layer would have satisfied `hr-observability-layer-citation` in form while
contradicting the plan's own packaging finding four sections earlier. The block below is therefore kept
for its `failure_modes` and `discoverability_test`, which are useful, with the layer claim withdrawn.

```yaml
liveness_signal:
  what: scripts/lint-rejected-register.sh exits 0 over every file in knowledge-base/project/rejected/
  cadence: every commit touching that glob (lefthook pre-commit) and every full-battery run
  alert_target: the committing session's own terminal (blocking, fail-closed)
  configured_in: lefthook.yml (pre-commit, glob "knowledge-base/project/rejected/*.md")
error_reporting:
  destination: non-zero exit plus printf to stderr naming the offending file and the failed field
  fail_loud: true — the lint blocks the commit; there is no warn tier and no bypass arm
failure_modes:
  - mode: an entry is written for a concept that is already implemented (the poisoning class)
    detection: lint rejects any entry whose redundancy_check is not exactly not-implemented, whose searched list is empty or absent, or which carries an implemented_at key at all
    alert_route: no layer — blocking pre-commit lint plus a pre-push mirror and a CI step over the full glob (see the chokepoint note)
  - mode: an entry claims not-implemented but records no evidence
    detection: the same lint asserts searched is a non-empty list of command-plus-result lines
    alert_route: no layer — same invocation
  - mode: an entry names a person rather than a role, creating a personal-data record in public git
    detection: the same lint rejects an entry whose requester field is anything but a role token from a closed vocabulary
    alert_route: no layer — same invocation
  - mode: a pre-check block reports a Verdict with no command behind it (performative audit)
    detection: the lint rejects a Verdict line inside a pre-check block containing zero executed-command lines
    alert_route: no layer — same invocation
  - mode: the lint is de-registered from lefthook, or its suite stops running
    detection: scripts/lint-orphan-test-suites.sh reports the companion .test.sh as an orphan; the suite's own dispatch floor reds on zero cases
    alert_route: no layer — repo-global ratchet, Phase 5
logs:
  where: stderr of the invoking session; no persistent sink (no server surface involved)
  retention: session-scoped
discoverability_test:
  command: bash scripts/lint-rejected-register.sh knowledge-base/project/rejected/2026-09-20-server-side-browser-automation.md
  expected_output: "lint-rejected-register: OK (1 file checked, 1 entry)" on exit 0
  # R2: an earlier revision pointed this at README.md -- the ONE path the glob
  # deliberately excludes -- so the probe stayed green with every entry check
  # deleted, and it contradicted AC-4c, which ships one seed entry.
```

No blind execution surface (sandbox, container dispatch, scheduled worker) is touched, so Phase 2.9.2
does not fire.

### Precedent diff (Phase 4.4)

Three pattern-bound behaviours, each diffed against its sibling precedent rather than invented:

- **The lint's dispatch shape** copies `distribution-content-liquid-guard` (`priority:` / `glob:` /
  `run: bash scripts/<lint>.sh {staged_files}`) for pre-commit, and the `client-pii-grep` gate for the
  pre-push mirror. Both live in `lefthook.yml`; neither is paraphrased.
- **The probe's exit contract** copies `scripts/followthroughs/ccla-representative-icla-7922.sh`, whose
  live shape is `exit 2` (not yet), `exit 5` (action required) and a terminal `exit 2` default —
  verified in that file, not recalled.
- **A `.test.sh` under `scripts/`** is a real and common shape in this repo
  (`lint-agents-compound-sync.test.sh`, `lint-agents-rule-budget.test.sh`, and 93 more), but every one
  is registered by a hand-written `run_suite` line rather than by a glob. That is precisely why the
  battery is relocated to `plugins/soleur/test/` (R20): the precedent exists, and following it would
  have required a runner edit AC-33 forbade.

### Phase 2.9.1 — Follow-Through Enrollment (fires, but on Flow D — not on the store)

**The store probe is cut (R13), and its budget moves to the questionnaire's return leg (R6).** Three
measured reasons for the cut: `wg-pm-class-followthrough-for-operator-dogfood` does not fire here (no
operator-only route, no cross-origin form POST, no custom CSP, no new `process.env.*` read), so
enrollment was discretionary rather than mandated; AC-4c ships one seed entry in this PR whose add-commit
lands at the start of the window, so the probe would have counted **its own seed** as usage — the exact
confound `--diff-filter=A` was chosen to avoid; and the plan had already spent a section refusing to
invent a usage signal for the glossary, then exempted the store from its own test.

What is enrolled instead is the one flow in this bundle with a genuine time-gated external dependency and
a signal that cannot be confounded: **a questionnaire still `status: sent` past its own `needed_by`.**

- **Probe:** `scripts/followthroughs/questionnaire-unanswered-8289.sh`, notify-only.
- **Signal:** for each file under `knowledge-base/project/questionnaires/`, frontmatter `status` is still
  `sent` and `needed_by` is in the past. The founder stated that deadline in interview exchange 2, so the
  probe measures the founder's own declared expectation rather than an invented proxy.
- **Exit contract:** never `0` or `1`. `2` = NOT YET (nothing overdue), `3` = CANNOT ESTABLISH (no
  questionnaire has been emitted yet), `5` = ACTION REQUIRED (an answer the founder is waiting on is
  overdue). Whether to chase it is a judgement, not a probe's verb. Precedent:
  `scripts/followthroughs/ccla-representative-icla-7922.sh`.
- **Why it needs no positive control:** unlike a count over a store, the subject's having run is
  *intrinsic* to the signal — a file exists only because the skill emitted one. Absence of files is
  reported as `3`, never as a pass.
- **Reporter is not the subject** (#6737 / ADR-126): the probe runs in the sweeper, never inside
  `questionnaire-generate`.
- **Directive + label:** the tracker carries
  `<!-- soleur:followthrough script=scripts/followthroughs/questionnaire-unanswered-8289.sh earliest=<deploy+7d> -->`
  and the `follow-through` label. No new `secrets=` are needed, so
  `.github/workflows/scheduled-followthrough-sweeper.yml` is unchanged.

This is also what closes Flow D's return leg as a mechanism rather than a hope: the emitted document
carries `recipient_role`, `needed_by`, `blocked_decision` and `status` in its frontmatter, an `## Answers`
section the reply is pasted into, and a `## Blocked on` back-pointer into the artifact that caused the
ask — so the next session finds the open question without anyone remembering it.

### The glossary has no honest usage signal — stated rather than invented

The register's precedent (`technical-debt/`: 11 entries, 0 closures) does **not** transfer to the
glossary, because a glossary has no drain — it is never "closed". Worse for the store and better for the
glossary: a stale debt entry is inert, whereas a stale rejection actively says "no" to something that
should now be "yes".

Three candidate glossary signals were examined and all three are unusable, so none is claimed:

- `.claude/.skill-invocations.jsonl` → `knowledge-base/engineering/operations/skill-freshness.json` is
  **structurally dead**: the JSONL is gitignored and the producing cron reads it from a fresh clone.
  Measured committed content: **67 skills, 67 `never_invoked`.** Two new skills would land there as
  `never_invoked` forever, so **this plan claims no invocation measurability for either new skill.**
  (The underlying defect is engineering-owned and explicitly out of scope; ADR-091 already solved the
  class for `rule-metrics.json`.)
- Glossary mutation count via `git log` is confounded twice: `cron-artifact-age.sh`'s own header warns
  *"Human edits MASK cron darkness"*, and #8030's finding that *"an obeyed rule emits nothing"* applies
  directly — a correct glossary needs no edits, so silence is ambiguous.
- Term-lookup counts do not exist and cannot be produced without new telemetry.

The glossary's accountability is therefore **structural, not metered**: because `operator-rephrase`
cites it as a stop-list, a term missing from it produces a visibly untranslated word in founder-facing
output — a failure the founder notices without a dashboard. This repo already carries two dead metrics;
inventing a third would be the defect this PR claims to cure.

One zero-machinery addition is taken: the glossary carries `review_cadence: biannual` and
`last_reviewed` frontmatter, which self-enrolls it in `review-reminder.yml`. ADR-094's objection (two
writers silently bumping `last_reviewed`) does not apply — those writers are `brainstorm`'s roadmap
reconcile and `cron-campaign-calendar.ts`, neither of which touches this path.

## Encryption Posture

Skipped. No persistent data store and no cross-component connection is introduced; the Phase 2.11
detection globs (`*.tf`, `supabase/migrations/*.sql`, `cloud-init*.yaml`, `docker-compose*.yaml`) match
nothing in the file lists below.

## Infrastructure (IaC)

Phase 2.8 reviewed and **not applicable**: this plan introduces no host, service, scheduled job, vendor
account, DNS record, certificate, secret or firewall rule, and every deliverable is a tracked Markdown
or shell file inside the existing repository. Nothing routes to `terraform-architect`, and there is no
`## Terraform changes` / `## Apply path` to write because no resource exists to apply.

No `iac-routing-ack` opt-out is used, and that is deliberate. An earlier draft of this section tripped
`.claude/hooks/iac-plan-write-guard.sh` twice — once on a phrase naming a secret-write command while
asserting its absence, and once on an idiom for "outside the system" that the guard classifies under its
human-actor framing rule. Both were **reworded**, not acknowledged away: the ack asserts that a reviewed
infrastructure step is genuinely required, which would have been false here. This is the #7003 class —
a line documenting a violation by reproducing its trigger tokens — and the correct resolution is to stop
reproducing the tokens, never to claim a step that does not exist. Verified clean against the guard's
own patterns (a), (b), (d).

## GDPR / Compliance Gate

The canonical regulated-data regex matches nothing here — no schema, no migration, no auth flow, no API
route, no `.sql`. Two expansion triggers fire:

- **(b) brand-survival threshold `single-user incident` is declared.**
- **(d) a new artifact distribution surface**: `questionnaire-generate` emits a document the founder
  sends to an external third party. Soleur is not the sender — the founder is the controller — but the
  *content* the skill assembles into `## Context` is the exposure vector named above.

Plus one surface the legal lens raised that neither bundle 1 nor 2 faced: the rejected register is a
**durable record of "we said no to X" in a public git history**. If an entry ever names a requester —
a customer, a named individual — that is personal data committed permanently. The format doc therefore
requires **role or source, never identity** ("a paying customer asked", never a name), and the lint
asserts it as a closed-vocabulary field rather than trusting the prose.

`/soleur:gdpr-gate` runs in Phase 0 against this plan document; output is advisory with the mandatory
disclaimer. The concrete question put to it: **what must the emitted questionnaire's `## Context` be
forbidden from carrying**, given the founder is the controller and the recipient is a third party with
no data-processing agreement in place. Any Critical finding (Art. 9 special-category, missing lawful
basis, Art. 30 trigger) follows the standard path — acknowledged write to `compliance-posture.md`
Active Items plus an issue labelled `compliance/critical`.

### Published-legal-corpus gate on the questionnaire component

A blocking pre-condition, not a review item. The constitution requires that before speccing a feature
that emits legal-shaped text, the published legal corpus is grepped for affirmative claims the feature
would falsify, and warns that a published disclaimer's own wording can veto the feature shape outright,
with the amendment cost (TC_VERSION bump, canonical↔mirror sync, CLO attestation) a blocking
dependency. A skill that generates a questionnaire the founder sends **to a lawyer** is at minimum
adjacent to that. Both corpora exist and must be grepped in Phase 0: `docs/legal/` and
`plugins/soleur/docs/pages/legal/` (9 documents each, canonical plus mirror, including
`disclaimer.md`). The skill must not frame its output as legal analysis and must not imply Soleur
assessed the founder's legal position — it **elicits** information, it does not evaluate it. If the
grep surfaces a conflicting affirmative claim, the questionnaire component is re-scoped or split before
implementation rather than after.

## Guard Contract

One guard ships. A second was considered and cut — see the note after the contract.

### Guard 1 — `scripts/lint-rejected-register.sh`

**Property.** No file in the rejected-concepts record claims a concept is unimplemented while carrying
evidence that it is; every entry carries the fields concept-matching mechanically depends on
(`aliases`, `scope`, the `why`/`public_note` split, `instead`); the filename's concept slug never
claims more than the entry's own `scope`; and no entry identifies a requester.

**Assembly.** The chokepoint is the **glob**, not a name list: every tracked file matching
`knowledge-base/project/rejected/*.md` except `README.md`, discovered by walking the directory rather
than by reading a manifest.

**There is NOT "exactly one write chokepoint" — an earlier revision claimed that and it is false.**
`git commit --no-verify` and a merge-resolution commit both reach the repository without the pre-commit
hook, and this repo already knows it: the comment at `lefthook.yml` immediately below
`distribution-content-liquid-guard` reads *"pre-push mirror of the client-pii-grep signal-quality gate
(#3703) so a bypass is surfaced at push time even if the pre-commit hook was skipped (e.g. amended
commit, `--no-verify` on an earlier commit)"*. So the dispatch set is **three**, and all three are
deliverables: `pre-commit` on the glob with `{staged_files}` (the `distribution-content-liquid-guard`
shape — `priority:`, `glob:`, `run: bash scripts/<lint>.sh {staged_files}`), a `pre-push` mirror in the
`client-pii-grep` shape, and a CI step running the lint over the **full glob** rather than the staged
set. The `{staged_files}` form also means the lint must behave correctly when handed zero paths — a
mutation row below, because "no paths, exit 0, nothing checked" is the vacuous arm.

**Advisory-only clause — the single highest-value line in this plan.** It goes in
`knowledge-base/project/rejected/README.md`, in ADR-232, and is asserted by the lint:

> A rejected-concepts entry may never be the sole basis for closing, labelling or auto-closing an issue.
> A prior-rejection hit is **reported to a human and escalates; it never acts.** In particular
> `deferred-scope-out` must never be applied on the basis of a store hit.

This exists because the architecture lens traced a complete, already-built amplification path that the
guard cannot see: a false entry commits (internally consistent, so the lint passes) → an agent with
`gh issue edit` applies `deferred-scope-out` → `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`
auto-closes it after 90 days with `state_reason: "not_planned"`, no human in the loop →
`scripts/sweep-followthroughs.sh` thereafter refuses to reopen it (*"NOT_PLANNED is a deliberate wontfix.
Reopening it would override a human decision"*). A false entry becomes a permanently-closed issue
attributed to a human decision that never happened, through two automated hops. Non-Goal 1 gates the
first hop **today only**, and that Non-Goal's own tracking issue asks for the very change that opens it —
so the advisory-only clause is also a named **precondition on that tracking issue**, and the checkout
must not land without it. Three lines retire the whole chain regardless of what the scheduled pass later
gains.

**Mutation matrix.** Derived from the property, before the lint exists. Rows 1–11 and 13–16 MUST drive
it **RED**; row 12 is the must-**PASS** row and is marked as such. The header is worded this way because
an earlier revision said "each row MUST drive it RED" while including the must-PASS row in the same
table and the same floor — a contradiction the floor would have inherited.

| # | Axis | Mutation | Must red because |
|---|---|---|---|
| 1 | fixture shape | an entry with `redundancy_check: implemented` | the poisoning class, stated directly |
| 2 | fixture shape | an entry with no `redundancy_check` key at all | absence must not read as compliant |
| 3 | fixture shape | an entry carrying `implemented_at: apps/web-platform/...` | a key that can only be true of a built feature |
| 4 | fixture shape | an entry with `searched:` present but empty | a `not-implemented` claim with no evidence |
| 5 | fixture shape | an entry carrying **any** `requester:` / `requested_by:` key at all | the public-git personal-data class. The field is **removed from the schema entirely** rather than enum-guarded — with zero external filers there is nobody to put in it, so a forbidden-key check is strictly safer than a closed-vocabulary check and costs the same |
| 6 | fixture shape | an entry with no `aliases:`, or an empty one | **the support lens's primary failure mode, which an earlier revision of this matrix could not see.** Without `aliases`, concept matching is aspirational rather than mechanical — "night theme" never reaches `dark-mode` |
| 7 | fixture shape | an entry with no `scope:` | the narrower-request-matches-broader-rejection failure. Unasserted in the earlier revision despite being declared a required field |
| 8 | fixture shape | an entry with `why:` but no `public_note:` | the split exists so an agent never quotes the blunt internal reason outward; a missing `public_note` means the only quotable text is the one that must not be quoted |
| 9 | fixture shape | an entry with no `instead:` | every *mechanism* refusal has an "instead"; an entry without one is either a genuine category-level never (rare, deliberate) or a **mis-keyed mechanism rejection** — which is the AC-4c/AC-4d class the marketing lens caught |
| 10 | fixture shape | an entry whose filename concept slug does not appear in its own `scope:` | a broad filename outrunning a narrow scope. To an external reader the **filename is the claim**, and `rejected/2026-09-20-browser-automation.md` reads as "Soleur does not do browser automation" no matter what the body says |
| 11 | fixture shape | an entry naming itself as sufficient grounds to close or label an issue | the advisory-only clause, asserted rather than requested |
| 12 | fixture direction | a **valid** entry (correct enum, non-empty `searched`/`aliases`/`scope`/`instead`, `why`+`public_note`, no `implemented_at`, no requester key, slug inside `scope`) MUST **pass** | a lint that rejects everything is as useless as one that accepts everything; this is the must-PASS row, and it is not the canonical `README.md` |
| 13 | cardinality | two entries, the **first** valid and the **second** invalid | a check that stops at the first member is the defect class |
| 14 | dispatch | invoke with zero path arguments | must not exit 0 claiming success; a `{staged_files}` lint handed nothing must report `0 files` and not certify the record |
| 15 | SUT | delete the `implemented_at` rejection branch from the lint | proves row 3 is carried by the lint, not by fixture luck |
| 16 | SUT | replace the enum comparison with a substring match | `not-implemented` **contains** `implemented`; proves the comparison is whole-value, per `cq-assert-anchor-not-bare-token` |

Rows 6–11 were added after review. The architecture lens established that the three fields the support
lens declared **required** — `aliases`, `scope`, and the `why`/`public_note` split — were precisely the
three the earlier matrix could not see, so *"the failure mode the support lens named as primary is the one
the guard cannot see."* Rows 9–10 close the mis-keying and filename-overreach classes the marketing lens
found in the seed itself. The axis count is unchanged at **five** (SUT, fixture shape, fixture direction,
dispatch, cardinality) — these rows lift `MIN_CASES`, not `MIN_AXES`, which is the distinction ADR-193
Decision 2 exists to preserve.

**Harness rows.** At least one edit to the **suite** must drive it RED, plus a must-PASS input that is
not the canonical:

| # | Harness mutation | Must red because |
|---|---|---|
| H1 | reroute the suite's `bad()` helper to increment the PASS counter | bundle 2's lesson — a misrouted `bad()` keeps conservation and both floors green. This is the instrument self-test, and it proves **direction**, not presence |
| H2 | drop one case from the battery | the direct anti-vacuity floor must catch a shrinking battery |
| H3 | make the suite's success condition `fail == 0` only | `0 passed, 0 failed` must not exit 0 |
| P1 | row 6's valid entry — a real concept file with all required fields, differing from `README.md` | a suite whose only must-PASS input is the canonical proves nothing about inputs the contract permits |

**Anchor.** The lint compares an entry's *claim* (`redundancy_check: not-implemented`) against the
*evidence it carries* (`searched:`), both inside the same file — so within one commit it proves
**internal consistency, not truth**. That gap closes outside the commit: each `searched` line is a
command plus its result count, re-runnable by a reviewer or a later session. A second assertion needing
network is therefore deliberately **not** in the pre-commit tier — *no number in `prior_requests`
resolves to an issue closed as `completed`*, which catches the drift case where the concept is built
later and nobody updates the register. That one runs in the full battery.

**Floors.** Direct, in the ADR-193 shape, never routed through the verdict helper:

```sh
[[ "$cases" -lt "$MIN_CASES" ]] && { printf 'FATAL: battery shrank: %s < %s\n' "$cases" "$MIN_CASES" >&2; exit 1; }
[[ "$axes"  -lt "$MIN_AXES"  ]] && { printf 'FATAL: axes covered: %s < %s\n'  "$axes"  "$MIN_AXES"  >&2; exit 1; }
```

`MIN_AXES` counts **axes**, not rows (ADR-193 Decision 2, and the lesson of
`2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in.md`): the five axes above are
SUT, fixture shape, fixture direction, dispatch and cardinality. The companion suite is
`plugins/soleur/test/lint-rejected-register.test.sh`, which lands under the glob-registered
`plugins/soleur/test/*.test.sh` so `scripts/lint-orphan-test-suites.sh` does not report it. **It sources
`plugins/soleur/test/lib/git-fixture-env.sh` by choice, not by obligation:** the fixture-env adoption
gate's `SHELL_ROOTS` are `tests/*`, `.github/scripts/test/*` and `apps/web-platform/infra/*`, and
`plugins/soleur/test/*` is explicitly in `OUT_OF_SCOPE_SHELL_ROOTS`. An earlier revision asserted the
requirement "binds"; it does not. Sourcing it anyway is right — the suite builds git fixtures — but the
plan must not claim a gate is forcing it.

### Cut: a committed peer-prose shingle suite; kept: a calibrated ship-time comparison

A suite pinning sha256 of the peer's 8-word shingles was considered and **cut** on two measured
grounds. There is no pinned peer corpus in this repository, and
`plugins/soleur/skills/competitive-analysis/references/peer-plugin-audit.md` deliberately re-derives
from a fresh clone (*"Do not assume prior catalog counts — they drift"*): the suite would need either a
CI network clone, making its verdict depend on a third party's HEAD, or a committed hash manifest that
rots silently the day the peer edits a file, leaving a permanently green assertion pinning nothing. And
a committed hash manifest of another project's prose is still a derived artifact of that prose.

What replaces it is stronger than bundle 2's bare check and costs no new machinery: the comparison
**reuses the scorer from `plugins/soleur/test/agent-originality.test.ts` — which requires extracting it first (P1-3).** Those three functions are module-local in a `.test.ts` with **zero** `export` statements, so "re-implementation is not permitted" was unsatisfiable as written, and the plan contradicted itself by calling that file "the shape to copy, not the comparison to reuse" in one section and mandating reuse in another. Resolution: extract `neutralize()`/`shingles()`/`jaccard()` into `plugins/soleur/test/lib/shingles.ts`, import it from both `agent-originality.test.ts` and the new check, and add **both** paths to `## Files to Edit` / `## Files to Create` (8-word windows, lowercase, non-alphanumerics
collapsed to whitespace, `WARN` calibrated at 0.30 against this repo's own corpus) rather than
re-implementing them, and it carries a **non-vacuity floor** and a **positive control** — the two
things bundle 2's AC lacked, and the documented failure mode in
`knowledge-base/project/learnings/best-practices/2026-06-12-porting-external-ci-gate-needs-calibration-positive-control-fail-closed.md`.
The reason the floor matters here concretely: a register README and a questionnaire template are mostly
headings, field names and answer stubs, so normalized they may yield almost no 8-word windows — and an
artifact with zero shingles shares zero shingles with everything and passes a 0 bar trivially. See
AC-L1/L2/L3.

## Design Decisions

### D1 — The store is called the rejected-concepts store, never "the register"

`register` is a **term of art in this repository**, and measurement makes the case stronger than the
product lens put it: eight live instances, seven of them compliance artifacts with counsel review and
an inclusion predicate — `knowledge-base/legal/{article-30-register,article-30-2-register,breach-register,ccla-register,side-letter-register,tenant-dpa-register,terms-and-conditions-contradiction-register}.md`
— plus `knowledge-base/engineering/architecture/nfr-register.md`. A pull request whose whole purpose is
one shared vocabulary cannot ship by overloading a compliance noun; it would commit the defect it
claims to cure.

So: the directory stays `knowledge-base/project/rejected/`, and every piece of prose in this bundle —
the skill, the convention, the pre-checks, the ADR, the PR body — calls it the **rejected-concepts
store**. The issue body's word "register" is retained only where it quotes the issue.

And the near-miss becomes the proof the artifact is needed: **`register` is the glossary's first
entry**, defined as the compliance sense, with an `_Avoid_` list naming the rejected synonyms and an
explicit note that the rejected-concepts store is deliberately not one.

### D2 — The glossary is an agent artifact, and the inclusion test is four-part

The issue calls the glossary "a document the founder reads and edits". Three independent measurements
say that framing is wrong, and the issue's own chosen path already contradicts it: the path
`knowledge-base/project/` is the machinery directory (`brainstorms/`, `plans/`, `specs/`, `reviews/`,
`rule-metrics.json`, `kb-health.md`, `weakness-digest.md`) while the founder-facing surfaces are the
eight department directories; `knowledge-base/marketing/brand-guide.md` instructs the founder-facing
layer to *use "your AI team" instead of "60+ agents"* and to avoid jargon; and `operator-rephrase`
rule 5 already **removes** jargon, file paths, issue numbers and command names. An artifact the founder
reads cannot be built from the vocabulary the founder-facing skill strips.

A term earns an entry only if **all four** hold:

1. It appears in **≥3** skill or agent definition files that an agent loads at decision time. Below
   that, the local file defines it well enough.
2. **No file already defines it.** If an "an X is…" sentence exists anywhere, the entry is a pointer to
   that file — a second definition drifts, which is the rule `operator-rephrase` §Register already
   applies to itself.
3. An agent could act **differently** under two readings, and the divergence lands in a committed
   artifact. This is the falsifiable half: "ambiguous" is not enough — name the wrong commit it
   produces.
4. It is **not** founder-facing vocabulary. If the founder should ever see the word, it belongs in the
   brand guide's lexicon, not here.

Candidate terms measured by file count: `register` 77, `shard` 36, `ratchet` 26, `WORM` 23, `lane` 21,
`rung` 13, `soak` 10 — all pass tests 1 and 2. `rung` is the instructive near-miss: the metaphor is
consistent (an ordered fallback step) but the **ladder differs per site** — `reproduce-bug` has ten
reproduction rungs, `operator-bootstrap` a credential ladder, `compound` a rule-lifecycle stage. So its
entry is not "what is a rung" but *"a rung is always of a named ladder — name the ladder."*

### D3 — `operator-rephrase` cites the glossary as a STOP-LIST, not as a source of approved terms

The shipped §Vocabulary paragraph is *right* to reject a glossary as an approved-terms source: its
rule 3 is satisfied by choosing plain everyday words, not by looking a term up. What the skill actually
needs is the inverse — the list of words that **must be translated**, each with a plain-English gloss to
translate *into*. That serves **rule 5, not rule 3**.

This is the wiring that makes the glossary reach the founder without the founder ever opening it, and it
is why the §Vocabulary rewrite is a capability change rather than a grudging correction. The same
stop-list is what keeps an internal noun out of an emitted questionnaire (G6 below).

### D4 — `questionnaire-generate` guardrails: allowlist the Context, never draft-then-redact

The founder is non-technical, will not audit the prose, and per
`hr-no-dashboard-eyeball-pull-data-yourself` should not be asked to. Design for the founder who signs
without reading.

| # | Guardrail |
|---|---|
| G1 | **Interview the send, never the subject.** Three questions only: who receives it, what is needed back, by when. If a subject question can be put to the founder, the questionnaire had no reason to exist |
| G2 | **Allowlist the `## Context` paragraph — never draft-then-redact.** Context is assembled from *only* the fields the founder stated in this session, with **no knowledge-base read on the drafting path.** This is the whole ballgame: #7331 was a draft-then-redact failure with every gate green |
| G3 | **Compute-then-preview plus typed confirmation** before the file is sendable (`invoice/SKILL.md` §S4.8 shape). The preview shows the Context paragraph verbatim, and nothing is appended after it |
| G4 | **`redact-sentinel.sh` as a floor, never a ceiling** (`plugins/soleur/skills/incident/scripts/redact-sentinel.sh`, the boundary `legal-generate` already applies before inline-emit). Fail closed on exit 2 |
| G5 | **Self-describe.** The document states it is a list of questions from a founder — not a position, not advice, not a completed brief |
| G6 | **The glossary as stop-list on the outbound path.** No internal noun leaves the repository inside a founder-attributed document |

**Must refuse:** to state any fact about the founder's business the founder did not say out loud in
this session (no KB-derived enrichment, no inferred figures, no "based on your roadmap"); to write in
the founder's voice claiming knowledge they lack (no "as we discussed", no invented prior
correspondence) — the founder must be able to answer any follow-up the recipient asks about their own
document; to forge attribution (no signature block, title or letterhead the founder did not supply);
and to ask a question whose answer the founder is obliged to already hold (registration number, fiscal
year end) — those route to a founder-fix step, exactly as `invoice` refuses to fabricate an invoice
fact.

**The rule in one line:** the Context paragraph carries nothing the founder did not say out loud in
this session. It carries three things — the decision being made, the recipient's role, and the
deadline.

Why an allowlist and not a scan: every one of the following passes `redact-sentinel.sh` clean, because
it matches secrets, and per `hr-third-party-content-grep-on-undertaking` *"a PII-scoped gate PASSES on
filenames, directory listings and repo internals — publication is a different predicate"*. All of it is
reachable today by a skill that summarizes the KB: the all-in monthly burn and break-even user count
from `knowledge-base/finance/cost-model.md`; the `PIVOT` validation verdict; the alpha-user count and
that user's name; competitor names from `competitive-intelligence.md`; unshipped roadmap phases; issue
and PR numbers; file paths; agent and skill names; anything under `knowledge-base/legal/`. A scan
cannot hold this line. A construction rule can.

### D5 — Do not touch `glossary.njk` or its drift guard

`plugins/soleur/test/seo-aeo-drift-guard.test.ts` asserts `found >= 8` by counting `>${t}</h2>`
matches on the rendered page. The current value is **9 against a floor of 8** — the seventh heading
renders as `>Knowledge Base (Compound Knowledge)</h2>` and already misses the literal
`>Knowledge Base</h2>`. **The arithmetic matters and an earlier revision got it wrong:** the assertion is
`toBeGreaterThanOrEqual(8)`, so ONE rename takes 9 → 8 and still **passes**; two reddens it. The headroom
is exactly one rename. D5's conclusion is unchanged — do not touch the file — but the reason is "there is
one rename of headroom and no product gain", not "one rename reddens the suite".

## Files to Create

Attribution rule, settled by the legal lens and stated once: **only the two `SKILL.md` files and the
three `references/*.md` files carry the `Inspired by` comment. Nothing under any `knowledge-base/` path
does.** Placing it on `knowledge-base/project/glossary.md` would assert peer provenance over Soleur's
own vocabulary — a false attribution. The comment is a Soleur provenance convention; the MIT notice is
discharged solely by `plugins/soleur/NOTICE` shipping in the payload.

| Path | What | `Inspired by` comment |
|---|---|---|
| `plugins/soleur/skills/kb-glossary/SKILL.md` | The write discipline, **plus a `## When to self-invoke` section (R3)** in the shape of the repo's only precedent, `operator-rephrase/SKILL.md` — without it nothing reaches this skill and PR-2 has no producer. The discipline: challenge a term that conflicts with the glossary, sharpen a fuzzy or overloaded one, update inline the moment it resolves rather than batching, and the hard scope line that the artifact is a glossary and nothing else — no specs, no implementation detail, no scratch space | **Yes**, after the closing frontmatter fence — `.../engineering/domain-modeling/SKILL.md` |
| `plugins/soleur/skills/kb-glossary/references/glossary-format.md` | **Must be named from `SKILL.md` or a sibling** — `components.test.ts` asserts every `.md` under a skill's `references/` is reachable, and the only permitted orphan today is `skill-security-scan/references/disclaimer.md`. Entry format and inclusion test. Two rules Soleur adds to the peer shape: an entry whose term already has a canonical definer is a **pointer** to that definer, never a restatement; and a term belongs only if two or more skills or agents pass it to each other | **Yes**, after the fence — `.../domain-modeling/CONTEXT-FORMAT.md` |
| `knowledge-base/project/glossary.md` | The artifact. Sits beside `constitution.md` as a project-wide governing document. Seeded only with terms whose definers already exist and can be pointed at | **No** — Soleur-authored, not derived |
| `knowledge-base/project/rejected/README.md` | The register convention, co-located with the store (the `learnings/technical-debt/README.md` shape): the field set, the concept-and-aliases key, the role-not-identity requirement, the write procedure with its machine gate and typed confirmation, and the built-is-not-rejected prohibition as the store's first rule | **No** — the *derived* prose lives in the skill-side reference; this file is the founder-facing convention |
| `plugins/soleur/skills/kb-glossary/references/rejected-request-register.md` | Also must be named from `SKILL.md` (same reachability assertion). The derived half of the convention: the one-file-per-concept discipline, concept-not-keyword matching, the durable-reason test, and the built-is-not-rejected prohibition | **Yes**, after the fence — `.../engineering/triage/OUT-OF-SCOPE.md` |
| `plugins/soleur/skills/questionnaire-generate/SKILL.md` | Grill the send, not the subject: two interview exchanges (who it goes to; what is needed back), then questions aimed at the gap. Plus the founder-protection guardrails — what `## Context` must never carry, and the refusal to frame output as analysis | **Yes**, after the fence — `.../productivity/to-questionnaire/SKILL.md` |
| `plugins/soleur/skills/questionnaire-generate/references/questionnaire.template` | The document template. Carries the comment on **line 1**, because the emitter strips the first line. **Extension is `.template`, not `.md` — three measured reasons, all from bundle 2's direct precedent:** all six files in `constraint-scaffold/references/` use `.template`; `scripts/markdown-lint.sh` scopes to `git ls-files '*.md'`, so a `.template` escapes markdown-lint (a template full of `<placeholder>` tokens and `>` answer stubs would otherwise fight it); and `components.test.ts`'s references/-reachability assertion walks **only `.md`** files, which is why `boundary-readme.template` is legitimately un-named from its own `SKILL.md` (`grep -c` → 0) without being an orphan | **Yes on line 1**; **stripped** from the emitted document |
| `knowledge-base/project/questionnaires/` (directory + `README.md`) | **R5 — the emitted questionnaire had no address.** No output path, filename convention or directory appeared anywhere in the earlier plan: the artifact existed and could not be located. Emission path is `YYYY-MM-DD-<recipient-role>-<topic>.md`, reusing the dated-slug convention AC-4b mandates for the store. The README states the frontmatter contract (`recipient_role`, `needed_by`, `blocked_decision`, `status: sent\|answered`), the `## Answers` section a reply is pasted into, and the `## Blocked on` back-pointer | **No** — founder-facing, Soleur-authored |
| `scripts/followthroughs/questionnaire-unanswered-8289.sh` | The return-leg probe (Phase 2.9.1) | No |
| `scripts/lint-rejected-register.sh` | Guard 1 | No |
| `plugins/soleur/test/lint-rejected-register.test.sh` | Guard 1's battery. **Located here, not under `scripts/` (P1-2).** `scripts/test-all.sh --print-suite-globs` does not include `scripts/*.test.sh` — the runner says so itself (*"Registered explicitly — `scripts/*.test.sh` is not auto-globbed"*), and 94 of the 95 tracked `scripts/*.test.sh` carry a hand-written `run_suite` line. Placing it there would have required editing `scripts/test-all.sh`, which AC-33 forbade, making AC-7 unsatisfiable. `plugins/soleur/test/*.test.sh` **is** glob-registered, so the suite is reachable with no runner edit | No |
| `knowledge-base/engineering/architecture/decisions/ADR-232-<slug>.md` | ADR-232 | No |
| `knowledge-base/project/specs/feat-one-shot-8289-kb-glossary-rejected-register/decision-challenges.md` | DC-1 and any further User-Challenge, rendered by `ship` Phase 6 into the PR body and an `action-required` issue | No |

## Files to Edit

| Path | Edit | Measured constraint |
|---|---|---|
| `plugins/soleur/commands/go.md` | Two routing rows inside `<!-- eval-gate:block:go-routing:start/end -->`, inserted **before** the `default` catch-all. Trigger signals must be tight enough not to cannibalise `default` — "questions" already routes there, so the questionnaire row keys on *a document to send to a named third party*, not on the presence of a question | Eval-gated → `go-routing` eval run, ~144 API calls, disclosed in Phase 5 |
| `plugins/soleur/commands/help.md` | `kb-*` is **already** in the prefix-family enumeration, so `kb-glossary` groups with no edit. `questionnaire-*` is a new single-member family and must be added to the enumeration in **all three** harness blocks (Claude Code, Devin CLI, Grok Build). Note the blocks are **not** byte-identical: the Claude Code and Devin CLI forms open `[List all skills found with brief descriptions, grouped by the token before the first hyphen: …]` while the Grok Build form opens `(list all skills — invoke as /<skill-name> — grouped by the token before the first hyphen: …)`. An edit keyed on the bracket form reaches only two of three | `skills/help/SKILL.md` defers to this file and must not be edited instead. The family token goes on the existing `flag-*, cron-*, …` line so the count in AC16 stays one line per block |
| `plugins/soleur/agents/support/ticket-triage.md` | Two read-only pre-check bullets under `## Scope`, **outside** the `eval-gate:block:ticket-triage` markers (which wrap only the severity bullet), plus the per-issue pre-check detail block appended to `## Output Format`. The 6-column table stays byte-identical | Agent is read-only by declaration; the block is emitted only for close/dedup recommendations, so a 1,507-issue report stays readable |
| `.openhands/skills/ticket-triage/SKILL.md` | The same two bullets and the same block. This file mirrors the agent **body**, and there is no generator and no parity test — the mirror drifts by hand | Verified 42 L with the output table mirrored verbatim. `.grok/agents/soleur-support-ticket-triage.md` and `agents.manifest.json` mirror only the *description*, which this plan does not change, so they are **not** edited |
| `plugins/soleur/skills/triage/SKILL.md` | Both pre-checks in **Step 1**, scoped to what a `todos/` finding is: an internally-generated review finding that can legitimately restate an already-built or already-refused concept. **Plus Step 2 (R4)** — it has exactly three branches today (yes → promote, **next → deletes the todo file**, custom → loops), so the reject path destroys the finding with no record, the opposite of the store's purpose. A fourth branch, *"reject: record why"*, becomes the only branch that removes a finding, and it is the store's named write path | Not eval-gated; not a lifecycle skill, so no byte ceiling. Two leaders recommended cutting this edit — DC-1 |
| `plugins/soleur/skills/operator-rephrase/SKILL.md` | Rewrite `## Vocabulary`. It currently states no repository glossary exists and *"that is the durable state"*, naming #8289 as the work that would change it | Not a lifecycle skill; no ceiling |
| `plugins/soleur/skills/brainstorm/SKILL.md` | One glossary read-pointer | Lifecycle ceiling 134628/141000 → 6372 B headroom |
| `plugins/soleur/skills/plan/SKILL.md` | One glossary read-pointer | Lifecycle ceiling 115271/120000 → 4729 B headroom |
| `plugins/soleur/skills/spec-templates/SKILL.md` | One glossary read-pointer | Not governed by the ceiling |
| `plugins/soleur/skills/architecture/SKILL.md` | One glossary read-pointer plus the ADR-232 cross-reference | Not governed by the ceiling |
| `.claude/hooks/pre-ask-technical-fork-gate.sh` | Rung **5** in the `REASON` ladder naming `soleur:questionnaire-generate`, **and — load-bearing (R1) — a dedicated `EXTERNAL_EXPERT_RE` arm evaluated as its own decision BEFORE the `AUTHORITY_RE` short-circuit at line 84.** Rung 5 alone is unreachable: `AUTHORITY_RE` wins outright and matches `cost`/`budget`/`price`/`priorit`/`scope`/`schedule`/`spend`, which an accountant or lawyer question almost always carries, and the surviving path still requires `INVESTIGATIVE_RE`, which this class never matches. The arm covers `accountant`/`bookkeeper`/`lawyer`/`solicitor`/`notary`/`auditor`/`tax`/`insurer`/`bank`/`regulator`/`landlord` and must precede the short-circuit because this class legitimately co-occurs with `cost` | **Byte cost to `B_ALWAYS`: zero.** Hooks are not in the always-loaded payload. See the rule-pointer note |
| `.claude/hooks/pre-ask-technical-fork-gate.test.sh` | Assert rung 5 is present, anchored on surrounding syntax not a bare token (`cq-assert-anchor-not-bare-token`); bump the strict inventory count | Currently `[[ "$TOTAL" -eq 12 ]]` exactly → 13 |
| `plugins/soleur/test/components.test.ts` | Bump `SKILL_DESCRIPTION_WORD_BUDGET` by exactly the two new descriptions' word count, appending to the comment log in the established shape: `bumped +N for #8289 (<skill> skill description, N words measured through discoverSkills()/parseComponent(), against a 2499/2499 zero-headroom baseline)` | **Measured 2499/2499, zero headroom.** Both descriptions must open `This skill should be used when` and stay ≤1024 chars |
| `lefthook.yml` | Register Guard 1 on `glob: "knowledge-base/project/rejected/*.md"`, copying the `distribution-content-liquid-guard` shape | `run: bash scripts/lint-rejected-register.sh {staged_files}` |
| `plugins/soleur/NOTICE` | Append the `(#8289)` group to `Used in:` (paths relative to `plugins/soleur/`, naming the actual host files); append the bundle-3 `Portions adopted:` paragraph with what was imported, all four deliberately-not-imported items, and the narrowed emission sentence | Pinned SHA `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` is already on the stanza and does not change |
| `knowledge-base/INDEX.md` | Regenerate: `bash scripts/generate-kb-index.sh` | Tracked and generated; `scripts/merge-kb-index.sh` resolves landing conflicts, `--check` gated via `plugins/soleur/test/kb-index-merge-driver.test.sh` |
| `plugins/soleur/skills/compound/SKILL.md` | **R3 — Flow A's producer.** Add the glossary sharpening trigger at the existing pass *"Could a rule, hook, or skill instruction have prevented this?"* — the exact moment a session has settled what a word means. Without it the write discipline has no producer anywhere and PR-2 ships as prose nothing reaches | **Lifecycle skill, and the tightest of the three this plan edits: measured 54256 / 57000 → 2744 bytes of headroom** (vs `brainstorm` 6372 and `plan` 4729). The ceiling ratchets down-only, so the trigger prose must be a sentence, not a section |
| `plugins/soleur/skills/compound-capture/SKILL.md` | The same trigger on the capture path | Not a lifecycle skill; no ceiling |
| `plugins/soleur/skills/operator-digest/SKILL.md` | **R17.** It owns `## Register (how to write)` — the canonical definer `operator-rephrase` already points at — so the glossary's `register` entry must point here too. An earlier revision wired the pointer and skipped the referent | Not a lifecycle skill; no ceiling |
| `knowledge-base/project/constitution.md` | **R18.** One line pointing at the glossary. `work`, `compound`, `compound-capture` and `spec-templates` already read the constitution, so future skills inherit the pointer with no per-file edit and no lifecycle byte cost. The five named consumers keep explicit pointers as a declared phase-1 set | Not byte-ratcheted |
| `plugins/soleur/docs/_data/skills.js` | Add a `SKILL_CATEGORIES` row per new skill. **This was missing from an earlier revision of this list and is non-optional:** `knowledge-base/project/constitution.md` line 88 — *"When adding a new skill, manually register it in `docs/_data/skills.js` SKILL_CATEGORIES — skill discovery does not recurse and the docs site will silently omit unregistered skills"*, repeated by `release-docs/SKILL.md`. Both sibling `kb-*` skills are registered there (`"archive-kb": "Workflow"`, `"kb-search": "Workflow"`) | Omitting it ships the skill as `Uncategorized` on the docs site. Found by the simplicity lens; AC-33 would have *forbidden* adding it, which is why AC-33 is corrected too |
| `README.md`, `plugins/soleur/README.md`, `plugins/soleur/.claude-plugin/plugin.json` | `soleur:release-docs`: `bash scripts/sync-readme-counts.sh`, then the `plugin.json` description counts | **100 → 102** (`find … -name SKILL.md`, the producer `sync-readme-counts.sh` uses — not `ls -d`, which over-counts `flag-bootstrap/`). AC-27 asserts a clean `--check` re-run, not a literal count, because a hand-set number the sync script disagrees with reds its own gate |
| `knowledge-base/kb-tags.txt`, `knowledge-base/kb-categories.txt` | Regenerated alongside `INDEX.md`. `lefthook.yml` line 402 runs `bash scripts/generate-kb-index.sh && git add knowledge-base/INDEX.md knowledge-base/kb-tags.txt knowledge-base/kb-categories.txt` — **three** files, not one | An earlier revision of AC-33 permitted only `INDEX.md`, which the repo's own pre-commit hook falsifies. The comment above that hook records that staging only `INDEX.md` is the exact bug it was written to fix |

### `Used in:` additions (exact host files, resolved — not placeholders)

```
    skills/kb-glossary/ (SKILL.md, references/glossary-format.md,
    references/rejected-request-register.md),
    skills/questionnaire-generate/ (SKILL.md,
    references/questionnaire.template),
    skills/triage/SKILL.md (intake pre-checks),
    agents/support/ticket-triage.md (intake pre-checks) (#8289)
```

Deliberately **absent** from that list, and each for a stated reason:
`knowledge-base/project/glossary.md` and `knowledge-base/project/rejected/README.md` are outside the
payload and are Soleur-authored rather than adopted portions — listing them would attribute Soleur's
own vocabulary to a third party, and a NOTICE cannot warrant the provenance of concept files that do
not yet exist. The generated questionnaire is runtime output, not a file in this repository; listing
runtime output in a distribution NOTICE would imply the emission carries adopted content, which it does
not.

### Deliberately NOT adopted (all four recorded in NOTICE, ranked by what the omission protects)

1. **The three-way Confirm / Reconsider / Disagree maintainer prompt.** A prompt that invites reopening
   a recorded rejection defeats the register's purpose — a register that can be argued with is a
   suggestion. It also hands a non-technical founder a re-litigation with no new information, which
   becomes click-through within weeks and then launders auto-closes as consent. Soleur's register is
   read, not negotiated; the founder is interrupted only when their own recorded `revisit_if` trigger
   fires, and then the choice is binary. Both the support and engineering lenses reached this
   independently.
2. **`ADR-FORMAT.md`.** Soleur has an established ADR corpus and format
   (`plugins/soleur/skills/architecture/references/adr-template.md`, 230 ADRs). Adopting a peer ADR
   format would fork a live internal convention.
3. **The `.out-of-scope/` dotted-directory location.** Soleur uses a visible
   `knowledge-base/project/rejected/`. A dotfile directory hides founder-readable records from the
   founder, against the data-portability principle that a founder can `git clone` and see all of it.
4. **The `CONTEXT-MAP.md` multi-context mechanism.** Soleur's glossary is single-context: one company,
   one vocabulary. A bounded-context map is a modeling tool for multi-team codebases and would ship as
   dead structure; that need already routes to `ddd-architect`.

### Explicitly NOT edited

- **`plugins/soleur/lib/workflow-fidelity.ts`** — neither skill is registered. `kb-glossary` is a
  maintenance skill in the shape of `archive-kb` / `kb-search`, wired by the read-pointers above;
  `questionnaire-generate` is terminal and is reached from a hook deny, not a phase edge. Registering
  either buys only cost: `plugins/soleur/test/workflow-fidelity.test.ts` asserts
  `Object.keys(budget.ceilings).sort()` equals **exactly** FSM keys ∪ destinations ∪
  `ONE_SHOT_CHILD_SKILLS`, so a ceiling row without registration **fails that suite**, while
  registration buys a permanent down-only-ratcheting byte ceiling plus a mirrored edge in
  `.claude/workflow-transitions.json`. Neither skill owns a multi-phase pipeline, so
  `mandatorySuccessors()` protection buys nothing.
- **`plugins/soleur/test/skill-body-budget.json`** — follows from the above.
- **`AGENTS.md` / `AGENTS.rules.md`** — see the rule-pointer note.
- **`plugins/soleur/skills/skill-creator/references/skill-structure.md`** — its verb-first convention
  is a documented defect owned by bundle 4 (#8290).
- **`apps/web-platform/server/inngest/functions/cron-daily-triage.ts`** — see Non-Goals 1.
- **`plugins/soleur/docs/pages/glossary.njk`** — the public SEO glossary, whose term list is pinned by
  `plugins/soleur/test/seo-aeo-drift-guard.test.ts` (≥8 canonical terms plus a `DefinedTermSet`
  JSON-LD). Adding internal machinery nouns would publish them and make every internal rename an SEO
  change.
- **`plugins/soleur/knowledge-base/`** — the payload seed tree gets no glossary copy in v1.

### Rule-pointer note (byte cost stated, as the contract requires)

The contract asks that the rule body point at the skill now delivering the capability.
`hr-technical-fork-is-not-an-operator-question` is marked
`[hook-enforced: .claude/hooks/pre-ask-technical-fork-gate.sh]`, and that hook's `REASON` string
*already is* the resolution ladder — four numbered rungs, then *"Ask the operator ONLY for:
authorization… money, scope, priority, or schedule."* Per `cq-agents-md-tier-gate`, an already-enforced
rule's body migrates **into** its enforcer. So the pointer lands as rung 5 of that ladder, which:

- costs **0 bytes** of `B_ALWAYS` (measured 42920; WARN 44000) because hooks are not in the
  always-loaded set;
- needs **no** WORM ack — `scripts/lint-rule-bodies.py --check` blocks `hr-*`/`wg-*` **body** edits
  absent a hash-bound ack in `.claude/rule-weakening-acks.txt`, and this diff makes no body edit;
- fires at the exact moment of dead-end, since the hook denies the very `AskUserQuestion` that would
  otherwise have gone to the founder — which an always-loaded line never does.

Both alternatives were costed and declined: editing the body in place would cost ~105 bytes (315 B
against the 600 B per-rule cap; `B_ALWAYS` → ~43025, still under WARN) **plus** a `--write` manifest
regeneration and a WORM ack; a new rule id would cost ~655 bytes of permanent always-loaded budget
against 1080 B of headroom to WARN, and `cq-agents-md-tier-gate` forbids a domain-scoped rule in
AGENTS.md regardless. `cq-rule-ids-are-immutable` is satisfied trivially — no id is created, renamed or
retired.

## Non-Goals

Each is deferred with a named blocker, not dropped silently. Tracking issues are filed by the pipeline
at ship via `gh issue create`.

1. **The unattended daily-triage pass does not get the pre-checks.** The real unattended intake is
   `apps/web-platform/server/inngest/functions/cron-daily-triage.ts`, whose self-contained
   `DAILY_TRIAGE_PROMPT` references no skill or agent file. Its `--allowedTools` (line 171) **does**
   grant `Read,Glob,Grep` — so the named blocker is **not** the tool list. It is that the function
   **never clones** (line 216), so there is no working tree for `Read` to point at. The tracking issue
   must say *"give the scheduled pass a checkout, or serve the store over an API"*; a follow-up written
   against a missing-tools cause would be closed by a one-line change that fixes nothing.
2. **The requester-facing half of the register.** No auto-posted closing comment, no public rejection
   record, no three-way prompt. Measured reason: **zero external filers**; `wontfix` applied to 0
   issues in history. Re-evaluation criterion: the first rejection request from an author outside the
   org.
3. **A dedicated `reject-request` write skill.** Recommended by the support lens; deferred because the
   issue scopes two new skills and the description budget is at cap. v1's write procedure is owned by
   `knowledge-base/project/rejected/README.md` and enforced by Guard 1.
4. **The stale `scheduled-daily-triage.yml` references.** That workflow is deleted, yet
   `plugins/soleur/agents/support/ticket-triage.md`, `.openhands/skills/ticket-triage/SKILL.md`,
   `.grok/agents/soleur-support-ticket-triage.md`, `plugins/soleur/.claude-plugin/agents.manifest.json`,
   `plugins/soleur/skills/fix-issue/references/{agent-authored-exclusion,exclude-label-jq-snippet}.md`
   and two runbooks still name it. Fixing it means touching the agent **description**, which is
   mirrored across four surfaces and consumes description budget. Out of this issue's scope.
5. **Notifying earlier requesters when a concept is revisited or ships.** `prior_requests` is a list of
   people who get counted but never told; the support lens flagged the absence as expensive. Deferred
   with Non-Goal 2, since it has no audience until external filers exist.
6. **`#8290` and `#8292`** (bundles 4 and 5) are not closed, not modified, and get no `Closes`.

## Implementation Phases

Phase order is dependency-directed, not file-grouped: a contract lands before its consumer.

### Phase 0 — Preconditions (no writes to shipped files)

1. Re-run both budget authorities and record the numbers in the spec:
   `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`, and the description-word
   measurement through `discoverSkills()`/`parseComponent()`.
2. Re-derive the free ADR ordinal across **every** `origin/*` ref after a fresh `git fetch origin` —
   not `origin/main` alone. Expect ADR-232; treat it as provisional.
3. Re-fetch the five peer blobs at the pinned SHA into the scratchpad. They are read-only inputs and
   are never committed.
4. Run `/soleur:gdpr-gate` against this plan document.
5. **Run the published-legal-corpus grep** over `docs/legal/` and `plugins/soleur/docs/pages/legal/`
   for affirmative claims the questionnaire component would falsify. This gates Phase 4.
6. Confirm both new skill directory names are free and kebab-case, and that no `questionnaire-*` family
   exists yet (it does not).

### Phase 1 — ADR-232 first (the go/no-go gate for Phases 2 and 3)

Author ADR-232 via `/soleur:architecture` with the four-row `## Alternatives Considered` table and the
measurement behind each row. If drafting the alternatives establishes that a `--state all --search`
sweep over `not-planned` closes already answers "was this concept refused?", **stop and re-scope**
rather than shipping a third store, recording that as a decision challenge. The expected outcome is
that it does not, because that sweep is keyed on wording and carries no concept key, alias set or
durable reason.

### Phase 2 — The glossary (PR-1, PR-2)

0. **The description-budget bump lands FIRST (P1-4).** Consumption is exactly `2499/2499`, and
   `plugins/soleur/test/components.test.ts` throws the moment `totalWords > BUDGET` — so a plan that
   wrote the first new `description:` in Phase 2 and bumped the constant in Phase 5 would leave that
   suite **red from Phase 2 through Phase 5**, against this plan's own header rule that a contract lands
   before its consumer. Bump for `kb-glossary` here, top up for `questionnaire-generate` in Phase 4 step
   2, and re-measure at merge per AC-14.
1. `references/glossary-format.md` — format and inclusion test **before** the artifact, so the artifact
   is written to a contract rather than the contract inferred from the artifact.
2. `knowledge-base/project/glossary.md` — seeded only with terms that already have a canonical definer
   to point at (`lane` → `brainstorm/references/brainstorm-domain-config.md` `## Lane Inference` is the
   worked example), plus the declared audience split and the one-line cross-pointer to the public
   glossary.
3. `plugins/soleur/skills/kb-glossary/SKILL.md` — the write discipline.
4. Consumer read-pointers, one line each: `brainstorm`, `plan`, `spec-templates`, `architecture`.
5. Rewrite `operator-rephrase` `## Vocabulary` so the shipped prose is true again.

### Phase 3 — The register and its reader, in one increment (PR-3, PR-4, PR-5)

Ordered so the battery exists before the guard, per Phase 2.12.

1. Write the mutation matrix and `scripts/lint-rejected-register.test.sh` from the **design** — RED.
2. `scripts/lint-rejected-register.sh` — GREEN.
3. Wire it in `lefthook.yml` on the glob.
4. `references/rejected-request-register.md` (the derived convention) and
   `knowledge-base/project/rejected/README.md` (the founder-facing store convention, the field set with
   the `why` / `public_note` split, role-not-identity, the machine gate before the human gate, and the
   typed confirmation naming the concept rather than `y`).
5. The reader: pre-check bullets and the per-issue detail block in
   `plugins/soleur/agents/support/ticket-triage.md` **and** `.openhands/skills/ticket-triage/SKILL.md`,
   then the Step-1 pre-checks in `plugins/soleur/skills/triage/SKILL.md`.
6. The redundancy pre-check is specified **by reference** to
   `plugins/soleur/skills/brainstorm/SKILL.md` `#### 1.1 Research (Context Gathering)` — which already
   mandates the functional-noun re-sweep and the report-where-you-looked discipline — never restated.

### Phase 4 — `questionnaire-generate` (PR-6, PR-7), gated on Phase 0 step 5

1. `references/questionnaire.template`, attribution comment on line 1.
2. `SKILL.md`, including the strip-the-first-line emitter rule, the `## Context` guardrails, and the
   refusal to frame output as analysis or to warrant how the recipient will handle the data.
3. Rung 5 in `.claude/hooks/pre-ask-technical-fork-gate.sh`, plus the assertion and the 12 → 13
   inventory bump in its companion test.

### Phase 5 — Wiring, then the repo-global ratchets, then the panel

1. `go.md` routing rows; `help.md` family token in all three harness blocks.
2. `plugins/soleur/test/components.test.ts` budget bump with the exact word counts.
3. `plugins/soleur/NOTICE`; `bash scripts/generate-kb-index.sh`; `soleur:release-docs`.
4. **`soleur:eval-harness`** — `--dry-run --target go-routing` first (zero API calls, prints the
   estimate), then the real gated run with `--candidate-file`, attaching the verdict to the PR body.
   **API budget disclosure:** `promptfooconfig-go-routing.yaml --repeat 3` ≈ **144 Anthropic API
   calls** against the configured key. The `ticket-triage` target (≈108 calls) is **not** run as a gate
   because this diff does not touch the severity block its markers wrap; it runs once as a no-drift
   regression check only if the panel asks for it.
5. **The repo-global ratchets, each by its own invocation** — bundles 1 and 2 each lost a CI cycle
   here, and a file-selected suite set cannot see them:

   ```
   bash scripts/guard-vacuity-floor.test.sh
   python3 scripts/lint-trap-tempfile-ownership.py --changed
   python3 scripts/lint-rule-bodies.py --check --base <merge-base>
   bash plugins/soleur/test/fixture-relative-assert.test.sh
   bash plugins/soleur/test/fixture-dir-operand-assert.test.sh
   bash plugins/soleur/test/fixture-env-adoption.test.sh
   python3 scripts/lint-skill-body-budget.py --base <merge-base>
   bash scripts/lint-orphan-test-suites.sh
   bash scripts/check-adr-ordinals.sh
   ```

   `--base` is **required** on `lint-skill-body-budget.py`; the bare form exits non-zero on a missing
   argument. Also run `python3 scripts/lint-guard-contract.py` against this plan file and
   `bash plugins/soleur/test/c4-count-parity.test.sh` for the no-C4-impact claim.
6. The vendor-mark grep and the shingle comparison (AC-L1/L2/L3 below), pre-merge only — the repo is
   public and git permanence leaves no post-merge remediation.
7. Only then `soleur:plan-review` / the review panel.

### Phase 6 — Ordinal re-derivation immediately before merge

Re-run the all-refs ADR probe after the final `origin` sync. If ADR-232 has been claimed, renumber and
**sweep the whole feature artifact set in the same edit**:
`grep -rn 'ADR-232' knowledge-base/project/{plans,specs}/` plus the ADR body and every AC naming the
ordinal — the #5990 failure was a renumber that reached the ADR but left an AC asserting a nonexistent
file.

## Acceptance Criteria

All of these are pre-merge and in-pipeline. There are no post-merge steps for the founder: every
verification below is automatable, and the three tracking issues are filed by the pipeline.

1. `plugins/soleur/skills/kb-glossary/SKILL.md` and
   `plugins/soleur/skills/questionnaire-generate/SKILL.md` both exist; each frontmatter `description`
   opens with `This skill should be used when` and is ≤1024 chars; neither directory name matches
   `^(create|setup|manage|generate)-`.
2. `knowledge-base/project/glossary.md` exists, is non-empty, and every entry whose term has a
   canonical definer elsewhere resolves to a repo-relative path rather than restating the definition.
3. `plugins/soleur/skills/operator-rephrase/SKILL.md` no longer contains
   `ships with no vocabulary source` **and** its `## Vocabulary` section cites
   `knowledge-base/project/glossary.md`. Both halves asserted — the absence grep alone would pass on a
   deletion.
4. `knowledge-base/project/rejected/README.md` exists and contains the built-is-not-rejected
   exclusion **stated as a pointer** (an already-implemented `wontfix` is a redundancy finding whose
   record is the closing comment naming where the implementation lives — pre-check 1's output), the
   role-not-identity requirement, and the entry-naming convention.
4b. Entries are named `YYYY-MM-DD-<concept-slug>.md`, and anything not matching that pattern is not an
   entry. This is mechanical, not advisory: a concept-similarity lookup over the directory would
   otherwise match `README.md` itself and manufacture the exact false rejection the store exists to
   prevent. The convention is already shipped in `knowledge-base/project/learnings/` and
   `learnings/technical-debt/`.
4c. **Exactly one seed entry exists, it is a real dated rejection, and its scope is narrowed so it is not
   a false one (P1-6).** Browser automation **is** implemented today —
   `plugins/soleur/skills/agent-browser/` ships (Vercel's `agent-browser` CLI: navigation, form filling,
   screenshots, scraping) and `.mcp.json` registers a `playwright` MCP server — so an entry keyed on
   *"just let the agent browse the web for me"* would assert `redundancy_check: not-implemented` over a
   shipped capability. That is precisely the false rejection PR-4 exists to forbid, and Guard 1 could not
   catch it because the lint proves internal consistency, not truth. The entry is therefore scoped
   explicitly to **server-side, Soleur-hosted Playwright for tenant service automation**, with `aliases`
   restricted to that framing, `instead:` naming the shipped 3-tier answer (API+MCP ~80%, local browser
   ~15%, guided fallback ~5%), and `scope:` stating in its own words that `soleur:agent-browser`, the
   `playwright` MCP server and `soleur:ux-audit` are the implemented paths and are **not** refused.
   An earlier revision omitted all of that — not a
   synthesized example. The seed is the server-side-Playwright refusal recorded at
   `knowledge-base/product/roadmap.md` §*Architecture Decision: 3-Tier Service Automation (Brainstorm
   2026-03-23)*: *"Server-side Playwright was rejected (HIGH risk from CTO, CLO, CFO)."* Seeding it
   writes no rejection that never happened, it is a concept that will certainly re-arrive as a request
   ("just let the agent browse the web for me"), and it retires the empty-store-nobody-starts-using
   failure without touching PR-4. Asserted:
   `ls knowledge-base/project/rejected/ | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-.*\.md$'` is `1`, and
   that entry's `why` traces to the cited roadmap anchor.
4d. Two things that look like seeds are **not** seeded, and the README says why: the Telegram bridge
   (roadmap records *"Removed in April 2026 — will redesign as channel connector"* — a deferral awaiting
   redesign, and filing it as rejected would kill the redesign) and ADR rejected-alternatives tables
   (real rejections, but scoped to *mechanisms* rather than concepts — importing them poisons the store
   from the other direction). The README cites the ADR tables as a sibling store the lookup also checks,
   and imports nothing from them.
5. `bash scripts/lint-rejected-register.test.sh` exits 0, reports ≥10 mutation rows across ≥5 axes and
   ≥4 harness rows, and both floors are direct (`[[ … -lt … ]]` + `printf >&2` + `exit 1`), not routed
   through the verdict helper — asserted by grep on the suite source.
6. The instrument self-test proves **direction**: with `bad()` rerouted to the pass counter the suite
   exits **non-zero**.
7. `scripts/lint-rejected-register.test.sh` sources `plugins/soleur/test/lib/git-fixture-env.sh`
   (grep), and `bash scripts/lint-orphan-test-suites.sh` reports it registered, not orphaned.
8. `lefthook.yml` carries the `knowledge-base/project/rejected/*.md` glob wired to the lint with
   `{staged_files}`.
9. Both pre-checks appear in `plugins/soleur/agents/support/ticket-triage.md` **and**
   `.openhands/skills/ticket-triage/SKILL.md`, and the 6-column output table in both files is
   byte-identical to its pre-change form (`git diff <merge-base>..HEAD` shows no change on that row).
10. The redundancy pre-check in all three surfaces **cites**
    `plugins/soleur/skills/brainstorm/SKILL.md` `#### 1.1 Research (Context Gathering)` rather than
    restating its sweep — asserted by grep for the **citation string only**. The absence half is dropped:
    an earlier revision asserted "the absence of a duplicated `[-_ ]` sweep recipe", but as a grep pattern
    `[-_ ]` is a POSIX bracket expression matching any hyphen, underscore or space, so it hits nearly
    every line of every target and the absence assertion could never pass (`cq-regex-unicode-separators-escape-only`
    is the in-repo form of this trap). A `grep -F` form would work but tests prose shape, not the property.
11. **Behavioural, not a string grep (R1).** A representative external-expert question — e.g. *"Should
    we treat the plugin revenue as capex or opex this year?"* — fed to
    `.claude/hooks/pre-ask-technical-fork-gate.sh` as `AskUserQuestion` JSON returns
    `permissionDecision: "deny"` with a `permissionDecisionReason` naming `questionnaire-generate`. The
    case lives in `.claude/hooks/pre-ask-technical-fork-gate.test.sh` and the suite exits 0. Asserting
    only that rung 5's *string* exists would have passed against the broken design this AC replaced: the
    string was present and the deny was unreachable, because `AUTHORITY_RE` short-circuits on `cost` and
    `budget` before any rung is emitted. The criterion is the suite's exit code plus the new case, never
    the literal inventory count — a sibling branch adding a rung moves that number with no line of this
    diff changing.
12. `git diff --stat <merge-base>..HEAD -- AGENTS.md AGENTS.rules.md` is empty, and
    `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` exits 0. The criterion is
    "this diff adds zero always-loaded bytes", asserted by the empty diff — **not** the literal
    `B_ALWAYS=42920`, which any sibling rule edit moves.
13. `python3 scripts/lint-rule-bodies.py --check --base <merge-base>` exits 0 with **no** new line in
    `.claude/rule-weakening-acks.txt` (`git diff --stat <merge-base>..HEAD -- .claude/rule-weakening-acks.txt` empty).
14. `SKILL_DESCRIPTION_WORD_BUDGET` is bumped by exactly the sum of the two new descriptions' word
    counts, measured through `discoverSkills()`/`parseComponent()` **at merge time**, with the comment
    appended in the established shape naming #8289 and quoting the baseline *as re-measured then*;
    `bun test plugins/soleur/test/components.test.ts` exits 0. The criterion is the **delta and the
    green suite** — not the literal `2499`. This plan measured `2499/2499` today, and bundle 1 moved
    this same constant twice, so a sibling bump between now and merge is the norm rather than the
    exception.
15. `plugins/soleur/commands/go.md` carries one routing row per new skill, both **before** the `default`
    row and inside the `eval-gate:block:go-routing` markers; the `soleur:eval-harness` `go-routing`
    verdict is attached to the PR body with its API-call count.
16. `grep -c 'questionnaire-\*' plugins/soleur/commands/help.md` is `3` — one enumeration line per
    harness block — and `plugins/soleur/skills/help/SKILL.md` is unchanged (`git diff --stat <merge-base>..HEAD -- <path>` empty). The
    assertion is anchored on the `questionnaire-*` **family-token form**, not on the bare substring
    `questionnaire-`, per `cq-assert-anchor-not-bare-token`. The reason is measured, not theoretical:
    `grep -c 'operator-\*'` over this same file returns **6**, not 3, because the token appears both in
    the three enumeration lines and in the three *"The operator-\* family is not routed from
    /soleur:go"* sentences. A bare-token count over `help.md` is therefore ambiguous between "listed"
    and "declared not-routable", and both new skills here are routable, so only the enumeration form is
    the right anchor.
17. `git diff --stat <merge-base>..HEAD -- plugins/soleur/lib/workflow-fidelity.ts plugins/soleur/test/skill-body-budget.json`
    is **empty**, and `bun test plugins/soleur/test/workflow-fidelity.test.ts` exits 0.
18. `python3 scripts/lint-skill-body-budget.py --base <merge-base>` exits 0 — the `brainstorm` and
    `plan` read-pointers stayed inside their pinned ceilings.
19. Exactly the five derived files carry the comment verbatim **including the trailing period inside
    the comment**: for each of `kb-glossary/SKILL.md`, `kb-glossary/references/glossary-format.md`,
    `kb-glossary/references/rejected-request-register.md`, `questionnaire-generate/SKILL.md`,
    `questionnaire-generate/references/questionnaire.template`,
    `grep -cF 'MIT, Copyright (c) 2026 Matt Pocock). -->'` returns exactly `1`. Placement asserted:
    line 1 for the template, after the closing frontmatter fence for the other four.
20. **No** `Inspired by` line and no vendor mark appears in `knowledge-base/project/glossary.md`,
    anywhere under `knowledge-base/project/rejected/`, or in a questionnaire fixture **produced by
    running the skill** (a hand-written sample proves nothing about the emitter).
21. **AC-L1 (originality hygiene, Soleur-authored artifacts).** Scoring reuses
    `neutralize()`/`shingles()`/`jaccard()` from `plugins/soleur/test/agent-originality.test.ts`;
    re-implementation is not permitted. For `knowledge-base/project/glossary.md`,
    `knowledge-base/project/rejected/README.md`, and the emitted questionnaire fixture, each compared
    against every peer blob pinned at `c55ee46073ed923f86ce59a5eb3b6d895095d1b7`:
    **(a) non-vacuity** — the Soleur artifact yields ≥20 distinct 8-word shingles, because an artifact
    with none shares none with everything and passes trivially; **(b)** shared 8-word shingles with
    every peer blob is `0`; **(c)** Jaccard < 0.30, the line already calibrated against this repo's
    corpus rather than a number invented here; **(d) positive control** — injecting one 12-word run
    copied from a peer blob into a scratch copy makes (b) report ≥1, reverted before commit and the run
    recorded in the PR body. A shared single token that is a literal format marker cannot form an
    8-word window and is out of scope by construction.
22. **AC-L2 (verbatim cap, derived artifacts).** The five files in AC19 intentionally adopt peer prose,
    so AC-L1(b) does **not** apply to them. Instead: no shared **25-word** shingle with any pinned peer
    blob. This is the line between "informed by" and "copied", and it is the only AC that actually
    constrains `references/questionnaire.template` — the one file rendered from a peer template
    block.
23. **AC-L3 (discharge).** AC-L1 and AC-L2 are originality hygiene, **not** the licence discharge. The
    MIT notice is discharged solely by `plugins/soleur/NOTICE` shipping in the plugin payload, and the
    PR body says so, so that no later reader concludes the in-file comment is the discharge and
    "fixes" a false positive by deleting attribution.
24. The vendor-mark grep ran pre-merge, cited to the constitution's vendored-content clause (the
    operative requirement here) rather than to `hr-third-party-content-grep-on-undertaking`, whose
    trigger is an undertaking about a third party's content and is a near-miss for MIT. Every peer mark
    on an added line sits inside the sanctioned comment — the `grep -v` filter for the sanctioned form
    is load-bearing, and its absence would make the ten existing attribution comments trip the grep,
    whose instinctive "fix" is the one change that moves toward a licence problem.
25. `plugins/soleur/NOTICE` `Used in:` carries the `(#8289)` group naming the real host files;
    `Portions adopted:` carries the bundle-3 paragraph with the four deliberately-not-adopted items and
    the narrowed emission sentence. The pinned SHA line is unchanged.
26. `bash scripts/generate-kb-index.sh --check` exits 0 **after** the regeneration this diff performs.
    The criterion is that the diff leaves the generated set consistent with the tree, not that the
    checker was already green — every KB commit anywhere regenerates `INDEX.md`, which is why the repo
    ships `scripts/merge-kb-index.sh`.
27. `soleur:release-docs` ran and `bash scripts/sync-readme-counts.sh --check` reports **in sync** on a
    second invocation, with the diff in the PR body. The criterion is the clean re-run, never a literal
    count: an earlier revision asserted `103`, which was wrong twice over — the real transition is
    100 → 102, and a hand-set number the sync script disagrees with reds its own gate. The `plugin.json`
    half of this AC is **dropped**: `jq -r .description` on that file carries no counts at all, so there
    was nothing to verify. `release-docs/SKILL.md`'s instruction to "update plugin.json description with
    correct counts" is stale, and folding it in verbatim was the error.
28. The plan's ADR exists with its `## Alternatives Considered` carrying all four rows and their
    measurements, and `bash scripts/check-adr-ordinals.sh` exits 0. The criterion does **not** hardcode
    `232`: this plan measured ADR-231 already claimed on a sibling branch and ADR-230 claimed three
    different ways, so Phase 6 re-derives the ordinal immediately before merge and the AC tracks whatever
    it resolves to.
29. `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0. **This is a regression check, not
    evidence for the no-C4-impact claim** — `model.c4` embeds workflow and monitor counts that a sibling
    PR can move, so a green run says nothing about *this* diff in either direction. The no-C4-impact
    claim rests on the enumeration in `## Architecture Decision (ADR/C4)` → `### C4 views`, which names
    the actors, systems, stores and access relationships checked. An earlier revision cited this suite as
    backing the claim; that citation was wrong and is corrected here.
30. All nine Phase 5 repo-global ratchets ran by their own invocations and exited 0, plus
    `python3 scripts/lint-guard-contract.py` against this plan file.
31. `decision-challenges.md` exists and carries DC-1 — the two-leader recommendation to cut the
    `triage/SKILL.md` pre-checks — with the operator's direction recorded as the default.
32. PR body uses `Closes #8289` only; no `Closes` for #8290 or #8292, and neither is modified.
33. **Both directions (R7, R15).** (a) The diff is a subset of `## Files to Create` + `## Files to
    Edit`, **plus** the paths the pipeline itself writes — `knowledge-base/INDEX.md`,
    `knowledge-base/kb-tags.txt` and `knowledge-base/kb-categories.txt` (all three are staged together by
    `lefthook.yml` line 402; an earlier revision listed only `INDEX.md`, which the repo's own hook
    falsifies), `knowledge-base/project/specs/<branch>/{spec.md,tasks.md,session-state.md,decision-challenges.md}`,
    the emitted questionnaire fixture under `knowledge-base/project/questionnaires/`, and this plan file.
    (b) **And the converse:** every `Files to Create` path exists and every `Files to Edit` path has a
    non-empty diff. A subset check alone is satisfied by a half-shipped plan — which is precisely what
    would have let Flow B's four read-pointers be absent with every other criterion green.

## Domain Review

**Domains relevant:** engineering, support, legal, product

Marketing was assessed and found **not relevant**, on evidence rather than judgement: the only
marketing-owned adjacency is `plugins/soleur/docs/pages/glossary.njk`, and that question is already
closed by two measurements — `plugins/soleur/skills/operator-rephrase/SKILL.md` §Vocabulary already
adjudicates it (*"do not point at `plugins/soleur/docs/pages/glossary.njk` — that is marketing
surface"*), and `plugins/soleur/test/seo-aeo-drift-guard.test.ts` pins its term list at `found >= 8`
(currently 9). The page is not edited (D5). Spawning a marketing lens to re-derive a closed question
would be ceremony. Operations, sales and finance have no surface here; the only cost exposure is the
eval API budget, disclosed in Phase 5.

### Engineering

**Status:** reviewed

**Assessment:** ADR required on the substrate question only — the two-glossary split is disjoint by
construction and needs no ADR, but standing up a third rejection store alongside two with live
consumers (`not-planned` closes, which `scripts/sweep-followthroughs.sh` already treats as
authoritative; and `deferred-scope-out`, which has a scheduled consumer in
`cron-stale-deferred-scope-outs.ts`) does. Adopted as ADR-232, with the alternatives table as the
go/no-go gate. Lifecycle registration declined for both skills, with the measured reason that
`workflow-fidelity.test.ts` pins the ceiling key set to exactly the lifecycle set, so a ceiling row
without registration fails the suite while registration buys a permanent down-only ratchet and a
mirrored transition edge for protection neither skill needs. The rule pointer was redirected from
`AGENTS.rules.md` into `.claude/hooks/pre-ask-technical-fork-gate.sh` as rung 5 of the ladder already
in its `REASON` string — zero always-loaded bytes, no WORM ack, and it fires at the moment of
dead-end. The committed shingle suite was cut on the grounds recorded in the Guard Contract. Recommended
cutting the `triage/SKILL.md` pre-checks entirely (DC-1) and, separately, argued the whole store could
collapse into a `--state all --search` sweep — that argument is answered, not ignored: it is exactly
what ADR-232's alternatives table must decide on the record.

### Support

**Status:** reviewed

**Assessment:** the single most consequential measurement in this plan. **There are no external
filers** — a 300-issue sample of the 1,507 open issues returns three distinct authors, all internal
(`deruelle` 215, `app/soleur-ai` 68, `app/github-actions` 17) — and `wontfix` has been applied to **zero
issues in the repository's history** across 3,182 closed; rejection is expressed as a `not-planned`
closure (187). The hard invariant therefore guards a label nobody has ever used, and the
requester-facing half of the design serves an audience that does not exist. v1 is re-scoped to an
internal concept-dedup index, with the public voice deferred (Non-Goal 2). Adopted from this lens: the
`why` / `public_note` field split, because an internal reason is usually correct and unpublishable and
an agent that quotes `why` into a comment is the primary damage vector; `aliases` as a required field,
without which concept matching is aspirational rather than mechanical; `scope` as required, because the
real failure is a *narrower* request matching a *broader* rejection and being closed with a reason that
does not address it; uncertain matches **fail open**; the escalation is **binary** and fires only when
the founder's own recorded `revisit_if` trigger fires, never a three-way re-litigation that becomes
click-through; the per-issue pre-check block rather than a seventh table column, with the rule that a
`Verdict:` line is illegal in a block containing zero executed commands — which is what makes it
auditable rather than performative; and `scripts/lint-rejected-register.sh` as the mechanically
assertable form of the poisoning invariant. Also flagged and carried forward: the two pre-checks in
`ticket-triage.md` produce **no durable artifact** (the agent is read-only and reports inline), so
pre-check compliance is unmeasurable on that surface until the scheduled-pass work lands — stated here
rather than implied as coverage.

### Legal

**Status:** reviewed

**Assessment:** proceed, with three corrections, all adopted. (1) The premise that root
`knowledge-base/` ships to installers is **false** — `.claude-plugin/marketplace.json` sets
`"source": "./plugins/soleur"`, so the payload is `plugins/soleur/` and customers receive only the
four-item seed tree `plugins/soleur/knowledge-base/`. The glossary and the store are Soleur's own
corpus, publicly readable because the repo is public, which is a confidentiality consideration and not a
licensing one. (2) The grep obligation is cited to the **constitution's vendored-content clause**, not
to `hr-third-party-content-grep-on-undertaking`, whose trigger is an undertaking about a third party's
content and is a near-miss for MIT — citing the wrong authority would survive into the record as a false
precedent. (3) The bare "0 shared shingles" AC is replaced by AC-L1/L2/L3, adding the non-vacuity floor
and the positive control it lacked. Also adopted: the attribution comment is **not** the MIT discharge
(that is `plugins/soleur/NOTICE` in the payload), so stripping it from emitted output breaches nothing —
stated in the PR body so no later reader "fixes" a false positive by deleting attribution; nothing under
any `knowledge-base/` path carries the comment, because putting it on Soleur's own vocabulary would be a
false attribution; the template carries it on line 1 above frontmatter while the SKILL.md files carry it
after the closing fence, and the two placements must not be interchanged; the strip is **verified on the
emitted artifact** produced by running the skill, not inferred from the emitter; the store is a
potential personal-data surface in public git, so `requester` is role-only and lint-asserted; and the
published-legal-corpus grep is a **gate** on the questionnaire component, not a review item, because a
published disclaimer's wording is a genuine veto candidate. The advisory carries the standard
not-legal-advice disclaimer and creates no attorney-client relationship.

### Product/UX Gate

**Tier:** none

**Decision:** reviewed

**Agents invoked:** cpo

**Skipped specialists:** none — `ux-design-lead` is correctly absent because there is no UI surface:
the mechanical UI-surface override does not fire (no `components/**/*.tsx`, no `app/**/page.tsx`, no
`app/**/layout.tsx`, no path matching the UI-surface term list), so `wg-ui-feature-requires-pen-wireframe`
does not apply. `spec-flow-analyzer` and `architecture-strategist` are not skipped either — the
`single-user incident` threshold puts both on the `plan-review` panel.

**Pencil available:** N/A (no UI surface)

#### Findings

**Signed off** for `/work` at `single-user incident`, with `requires_cpo_signoff: true` set and
`user-impact-reviewer` armed for review. Five conditions, all adopted into the plan: D1 (stop calling it
a register, and make `register` the glossary's first entry); D3 (§Vocabulary as a stop-list serving
rule 5, not an approved-terms source); D5 (do not touch `glossary.njk` or its drift guard); AC-4b/4c/4d
(the entry-naming convention, the exclusion pointer, and the one real seed); and Phase 2.9.1 (the
follow-through probe lands in this PR, notify-only with a positive control, and the deferred scheduled-pass
issue names the missing checkout rather than missing tools). This lens also corrected my own P9
measurement — `--allowedTools` does grant `Read,Glob,Grep`; the blocker is the absent working tree — and
supplied the D2 inclusion test, the D4 guardrails, and the finding that `skill-freshness.json` reports
67 of 67 skills `never_invoked`, so this plan claims no invocation measurability for either new skill.

One adjacent defect was identified and is explicitly **not** fixed here: `cron-skill-freshness.ts` reads
a gitignored JSONL from an ephemeral clone and has published an all-zeros snapshot since 2026-05-04.
Engineering-owned; ADR-091 already solved the class for `rule-metrics.json`. Worth an issue, worth not
fixing in this PR.

### Standing panel check — `cq-ac-must-not-depend-on-concurrent-sessions`

Every entry under `## Acceptance Criteria` was read against the litmus: *could a process this plan never
mentions — a sibling worktree, another agent session, ambient machine state — flip this from true to
false with no line of the diff changing?*

**Result: clean.** No criterion asserts the absence of an ambient signal. The tell shapes the check
looks for (a run firing no contention banner, no sibling process detected, free disk, a wall-clock
bound) appear nowhere. Every criterion resolves against one of: a file's existence or contents, a
a merge-base-anchored `git diff` over named paths, a grep count over a committed file, or a suite's exit code — all
properties of the diff.

Two entries were examined closely and both hold. AC26 (`generate-kb-index.sh --check`) reads the
working tree, not shared state, so a concurrent session in another worktree cannot flip it. AC15 depends
on an eval verdict, which is model-nondeterministic rather than ambient — that is a property of the
gated tool this repo already relies on, not machine state, and the `--dry-run` step plus the recorded
call count make the run reproducible enough to re-adjudicate.

### Decision Challenges (persisted to `decision-challenges.md`, headless arm)

Both are challenges to the operator's **stated direction**, so per `decision-principles.md` (ADR-084)
the operator's direction is the default and neither is applied. `ship` Phase 6 renders them into the PR
body and files them as `action-required`.

- **DC-1 — cut the `triage/SKILL.md` pre-checks.** *Default if unchallenged:* the pre-checks land in
  `triage/SKILL.md` as the issue body specifies, scoped to what a `todos/` finding is.
  *Challenge if:* the engineering and support lenses independently concluded the file is the wrong
  surface — its own body says it *"handles only legacy local `todos/*.md` files that predate the GitHub
  issue integration"*, and a `todos/` finding is a per-file code defect with no domain concept to search
  and no concept that could have been previously refused. Cutting it would remove one of the three
  surfaces the issue names. **One supporting claim in that challenge was falsified on verification and
  is recorded as falsified:** the engineering lens described the corpus as "effectively frozen (59
  committed files, roughly 3 still pending)". The 59 and the 2026-09-09 last-commit hold, but
  `grep -rl '^status: pending' todos/ | wc -l` returns **33**, so a third of the corpus is unprocessed
  and the surface has a live backlog. That weakens the challenge and strengthens the default; the
  no-domain-concept argument is the part that stands and the part worth ruling on.
- **DC-2 — cut the `kb-glossary` skill, keep the glossary file.** *Default if unchallenged:* the skill
  ships, because the issue names G3 as a skill and its rename table mandates the name `kb-glossary`.
  *Challenge if:* the product lens argues the glossary needs a file and a read wiring, not a 100th
  skill — the consumers read the artifact, not the skill; the skill costs a routing row behind an eval
  gate, a `help.md` entry, a manifest and README count bump, and a permanent freshness row that will
  read `never_invoked` forever; and by the issue's own contract *"a skill nothing invokes is an
  orphan"*, since it would be invoked only when someone deliberately remembers to sharpen a term — the
  write-mostly failure mode wearing a skill's clothes. The proposed alternative is the inclusion test in
  the glossary's own header plus the sharpening trigger in `compound`, which already writes to the KB
  after fixes ship, so a term is sharpened when a real session proves it was ambiguous.

## Plan Review Revisions (R1–R18)

Six reviewers ran against the finished plan: the five-agent engineering panel mandated at
`single-user incident` (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer) plus
the one named lens not consulted at Phase 2.5 (CMO). Every revision below is **Mechanical** — a factual
error, an unreachable mechanism, or a missing producer, each with one right answer — and every one is
applied above. Findings that argue the operator's stated scope should change are **not** here; they are
in `decision-challenges.md`.

The three that matter most: my rule pointer was **unreachable**, my liveness probe exercised the lint on
the **one file the glob excludes**, and two of my four flows had **no producer at all**.

| # | Finding | Applied change |
|---|---|---|
| **R1** | **The rule pointer is unreachable.** `.claude/hooks/pre-ask-technical-fork-gate.sh` evaluates `AUTHORITY_RE` **first and wins outright** (line 84: `if grep -qE "$AUTHORITY_RE" <<<"$CORPUS"; then exit 0; fi`), and that pattern includes `cost\|budget\|price\|priorit\|scope\|schedule\|spend`. An accountant or lawyer question almost always carries one, so the hook **allows** and rung 5 is never emitted. If it survives that, the deny still requires `INVESTIGATIVE_RE` (line 88, `if ! grep -qE … then exit 0`), which matches investigation phrasings only — "which VAT scheme applies to plugin revenue" matches nothing, and `ask the accountant` does not match `ask (the )?(owner\|author\|whoever)`. The third-bucket question is *definitionally* the one carrying neither signal, so rung 5 sat in a string emitted only for a disjoint class | Rung 5 alone is **not sufficient**. The hook gains a dedicated `EXTERNAL_EXPERT_RE` arm — `accountant\|bookkeeper\|lawyer\|solicitor\|notary\|auditor\|tax\|insurer\|bank\|regulator\|landlord` — evaluated as **its own decision before** the `AUTHORITY_RE` short-circuit, because this class legitimately co-occurs with `cost` and `budget`. It denies with a reason pointing straight at `questionnaire-generate`. AC11 is rewritten from a string grep to a **behavioural case**: feed a representative external-expert question as JSON to the hook and assert `permissionDecision == "deny"` with a reason naming the skill |
| **R2** | **The `discoverability_test` exercised the lint on the one path the glob excludes.** It ran `lint-rejected-register.sh knowledge-base/project/rejected/README.md`, and the Assembly deliberately excludes `README.md` — so the probe stayed green with every entry check deleted, and it also contradicted AC-4c, which ships one seed | The probe points at the **seed entry**, and expects `1 file checked, 1 entry, OK` |
| **R3** | **Flow A had no producer.** PR-2 (sharpen at the moment a decision settles) had no trigger anywhere: the four consumer edits are read-pointers with no write obligation, `workflow-fidelity.ts` registration is declined so there is no phase edge, no hook points at `kb-glossary`, and the `go.md` row is the founder's surface — the one actor D2 test 4 says the artifact excludes | `plugins/soleur/skills/compound/SKILL.md` and `compound-capture/SKILL.md` join `## Files to Edit`. `compound`'s existing pass (*"Could a rule, hook, or skill instruction have prevented this?"*) is the exact moment a session has settled what a word means. `kb-glossary/SKILL.md` gains a `## When to self-invoke` section in the shape of the repo's only precedent, `operator-rephrase/SKILL.md`. The `kb-glossary` routing row's trigger signals are specified so they enter the eval candidate, and an AC greps `compound/SKILL.md` for the invocation |
| **R4** | **Flow C had no producer.** `triage/SKILL.md` Step 2 has exactly three branches — yes (promote), **next (deletes the todo file)**, custom (loops) — so on the only attended surface the reject path *destroys the finding with no record*, the opposite of the store's purpose. The plan edited Step 1 only | Step 2 joins `## Files to Edit` and Phase 3, gaining a **fourth branch — "reject: record why"** — which becomes the only branch that removes a finding. The write procedure is named and reachable rather than living only in a convention document |
| **R5** | **The emitted questionnaire had no address.** No output path, filename convention or directory appeared anywhere in the plan | Emission path specified as `knowledge-base/project/questionnaires/YYYY-MM-DD-<recipient-role>-<topic>.md`, reusing the dated-slug convention AC-4b already mandates, with an AC that the fixture lands there |
| **R6** | **Flow D's answer never came back.** The flow terminated at "file written": no ingest, no status field, no reader of a completed questionnaire, and no Non-Goal deferring the return leg. G1 collects "what is needed back, by when" and then discards the deadline; the asking session is gone days before the answer exists; and the repo's own time-gated follow-through primitive was applied to the store but not to the one flow with a real external dependency | The emitted document carries frontmatter (`recipient_role`, `needed_by`, `blocked_decision`, `status: sent\|answered`) and an `## Answers` section the reply is pasted into, plus a `## Blocked on` back-pointer into the artifact that caused the ask, so the next session finds the open question without remembering it. A notify-only follow-through probe keyed on `status` still `sent` past `needed_by` replaces the cut store probe (R13) |
| **R7** | **Flow B's read-pointers were unasserted.** Only `operator-rephrase` had an AC (AC3). `brainstorm`/`plan` were covered only by AC18, which passes identically whether the pointer exists; `spec-templates` and `architecture` appeared in no AC; and AC33's **subset** check permits their absence entirely — so Flow B's entry point could be wholly missing from the diff with every AC green | A new AC greps each consumer for `knowledge-base/project/glossary.md`. AC33 gains the **other direction**: every `Files to Create` path exists and every `Files to Edit` path has a non-empty diff |
| **R8** | **AC1 and AC11 asserted existence where the invariant is reachability** — the repo's "function exists vs reachable" class, which DC-2 names in the plan's own words | AC1 additionally asserts each skill is reachable from a **named invoker**: the `go.md` row for both, `compound/SKILL.md` for `kb-glossary`, and the hook's behavioural deny for `questionnaire-generate` |
| **R9** | **The ADR's alternatives table was falsified in two of four rows, and its load-bearing row was missing.** Row 2 was wrong: `cron-stale-deferred-scope-outs.ts` closes stale `deferred-scope-out` issues with `state_reason: "not_planned"` after 90 days, so deferred and refused **converge on the same terminal state** — it is a *delayed* refusal, not an opposite. Row 1's "no durable reason surviving closure" was wrong: a closed issue's body and comments persist. And the real property went unstated | Rows 1 and 2 are restated accurately, and **the load-bearing row is added**: *the store can record a refusal that was never filed as an issue.* Verified on the plan's own seed — the roadmap records the refusal, and `gh issue list --state all --search "playwright server-side"` returns nothing. Corroborated across the last 400 closed issues: `NOT_PLANNED` is 14, and all 14 are machinery (`decision-challenge:`, `[gdpr-gate]`, a test name), so the `not-planned` corpus is essentially devoid of concept refusals. Row 1's surviving clause is narrower and still true: GitHub search is a keyword index with no synonym expansion, so "night theme" never reaches `dark-mode` |
| **R10** | **No precedence rule between the store, a tracker state and an ADR** | Added to ADR-232 and the README: **an entry is evidence that a refusal was recorded, never the refusal itself.** The store is an index into trackers and ADRs, never authoritative over them. If `prior_requests` resolves to an issue closed `completed`, or an ADR accepts the mechanism, the entry is **stale** and the pre-check reports STALE rather than REFUSED |
| **R11** | **The seed was a mechanism rejection imported as a concept — AC-4c contradicted AC-4d**, and it published a "we rejected Playwright" record while `plugins/soleur/docs/pages/goal-primitive.md` (live at `goal-primitive/`) tells readers *"Use Playwright MCP, `xdg-open`, CLI tools, or APIs to drive completion."* The roadmap refused **one execution location** and shipped a 3-tier architecture in its place | The seed is re-keyed to the concept as actually refused — *running the automation browser on Soleur's own servers* — with `scope:` naming the shipped answer (the API+MCP tier at ~80% and local-browser at ~15%) and a pointer to the 3-tier table. A new required **`instead:`** field makes this structural: every mechanism refusal has an instead, so an entry without one is either a deliberate category-level never or a mis-keyed mechanism rejection. Mutation rows 9 and 10 assert `instead:` and slug-inside-`scope` |
| **R12** | **The guard could not see the three fields declared required.** `aliases`, `scope` and the `why`/`public_note` split were required by the support lens and asserted by nothing — *"the failure mode the support lens named as primary is the one the guard cannot see"* | Mutation rows 6, 7, 8 added. Row 5 changes from an enum check on `requester` to a **forbidden-key** check: the field is removed from the schema entirely, because with zero external filers there is nobody to put in it and a forbidden-key check is strictly safer at the same cost. Axis count stays five — these lift `MIN_CASES`, not `MIN_AXES` |
| **R13** | **The follow-through probe counted its own seed.** AC-4c ships one entry in this PR, whose add-commit lands at the start of the 180-day window, so the probe reports the store alive on zero real usage — the exact confound `--diff-filter=A` was chosen to avoid. Separately, `wg-pm-class-followthrough-for-operator-dogfood` does **not** fire here (no operator-only route, no cross-origin POST, no custom CSP, no new `process.env.*` read), so enrollment was discretionary; and the plan had already argued at length that it refuses to invent a usage signal, then exempted the store from its own test | **The store probe is cut.** The probe budget moves to Flow D's return leg (R6), which has a genuine time-gated external dependency and a signal that cannot be confounded — a questionnaire still `status: sent` past its own `needed_by` |
| **R14** | **"Exactly one write chokepoint" was false.** `--no-verify` and merge-resolution commits bypass pre-commit, and the repo already ships the remedy pattern (`lefthook.yml`: *"pre-push mirror of the client-pii-grep signal-quality gate (#3703) so a bypass is surfaced at push time"*) | Dispatch set is **three** and all three are deliverables: pre-commit on the glob, a pre-push mirror, and a CI step over the **full** glob rather than `{staged_files}` |
| **R15** | **`docs/_data/skills.js` was missing, and AC33 forbade adding it.** `knowledge-base/project/constitution.md` line 88 mandates manual `SKILL_CATEGORIES` registration; both sibling `kb-*` skills are registered. Separately AC33 permitted only `INDEX.md` while `lefthook.yml` line 402 stages **three** generated KB files | Both added to `## Files to Edit`; AC33 lists all four paths |
| **R16** | **Nine ACs asserted absolute literals a sibling branch flips** (`B_ALWAYS=42920`, `2499/2499`, `103 skills`, hook inventory `13`, ADR ordinal `232`). My own standing-check verdict said "clean" because I tested for ambient machine state and never for *a sibling branch moving a shared constant* — the same class, missed | Each rewritten to assert the **delta, the empty diff, or the green suite** rather than the baseline literal. The standing-check verdict is corrected below rather than left as a false pass |
| **R17** | **`register` has four live senses, not one**, so D1 undercounted: the eight compliance artifacts, plus the domain-model sense (`preflight/SKILL.md` `--register knowledge-base/engineering/architecture/domain-model.md`, "Check 11: Domain-Model Register Drift"), the prose/voice sense (`operator-digest/SKILL.md` `## Register (how to write)`), and the verb ("register an MCP server"). Worse, D1 made `register` a **restatement** in a glossary whose own rule 2 forbids restatement where a definer exists, and `operator-rephrase` points at `operator-digest`'s definer — so the plan wired the pointer and skipped the referent | D1's entry becomes a **pointer with four disambiguated senses**, each naming its definer, which is what rule 2 requires and what makes the entry the proof D1 claims it is. `operator-digest/SKILL.md` joins the consumer set |
| **R18** | **The consumer set was bounded by the byte ceiling and presented as a principle.** Applying D2 test 3 to consumers selects `work` (82 hits), `ship` (57 — and `soak`'s only canonical definer *is* `ship`, so the glossary would point at a file that never learns it exists), `review` (26), `preflight` (19), `operator-digest`, `incident`, `compound`. None were wired, and the five that were are the five the issue happened to name | The one-line glossary pointer also goes in `knowledge-base/project/constitution.md`, which `work`, `compound`, `compound-capture` and `spec-templates` already read — future skills inherit it with no per-file edit and no lifecycle byte cost. The five named consumers keep their explicit pointers and are declared a **phase-1 set**, with the byte-ceiling constraint stated out loud rather than dressed as a principle |

### R19–R27 — the correctness panel's remaining findings, all applied

The correctness lens re-ran **all fourteen** measured claims in `## Research Insights` by command and
every one **held**, including the ADR-ordinal enumeration across 97 refs and the two rival ADR-230
titles. Its findings were therefore about *my* derived claims, not my measurements — which is the more
expensive kind.

| # | Finding | Applied change |
|---|---|---|
| **R19** | **The skill count was wrong, and self-defeatingly so.** `ls -d plugins/soleur/skills/*/` returns 101 because `flag-bootstrap/` holds only a `SETUP.md`. Every consumer counts `SKILL.md` files: `find … -name SKILL.md` → **100**, `sync-readme-counts.sh --check` → *"68 agents, 3 commands, 100 skills"*, `discoverSkills()` → 100. So "101 → 103" was wrong twice, and AC-27's hand-set `103` would have **reddened the sync script's own `--check`** | Stated as **100 → 102**, citing `find … -name SKILL.md` as the producer. AC-27 asserts an in-sync `--check`, never a literal |
| **R20** | **AC-7 was unsatisfiable and collided with AC-33.** The battery was placed at `scripts/lint-rejected-register.test.sh`, but `scripts/*.test.sh` is **not** in `SUITE_GLOBS` — the runner says so itself, and 94 of 95 tracked `scripts/*.test.sh` carry a hand-written `run_suite` line. Registering it needed an edit to `scripts/test-all.sh` that AC-33 forbade | The battery moves to `plugins/soleur/test/lint-rejected-register.test.sh`, which **is** glob-registered. No runner edit, AC-7 satisfiable, AC-33 intact |
| **R21** | **The `git-fixture-env.sh` requirement does not bind here.** The adoption gate's `SHELL_ROOTS` are `tests/*`, `.github/scripts/test/*`, `apps/web-platform/infra/*`, and `plugins/soleur/test/*` is explicitly `OUT_OF_SCOPE_SHELL_ROOTS`. I asserted a gate was forcing it | The suite still sources it — it builds git fixtures, so it is right — but the plan no longer claims a gate compels it |
| **R22** | **AC-21 was unsatisfiable: the scorer is not exported.** `neutralize()`/`shingles()`/`jaccard()` are module-local in a `.test.ts` with zero `export` statements, so "re-implementation is not permitted" required editing a file that was not in `## Files to Edit`. The plan also contradicted itself — "the shape to copy, not the comparison to reuse" in one section, mandated reuse in another | Extract to `plugins/soleur/test/lib/shingles.ts`, imported by both `agent-originality.test.ts` and the new check; both paths added to the file lists |
| **R23** | **Phase ordering inversion, against the plan's own header rule.** Consumption is `2499/2499` and `components.test.ts` throws on `totalWords > BUDGET`, so writing the first new `description:` in Phase 2 while bumping the constant in Phase 5 leaves that suite **red for three phases** | The bump becomes **Phase 2 step 0**, topped up in Phase 4 |
| **R24** | **The seed was a false rejection.** `plugins/soleur/skills/agent-browser/` ships (navigation, form filling, screenshots, scraping) and `.mcp.json` registers a `playwright` MCP server. An entry keyed on *"just let the agent browse the web for me"* asserts `not-implemented` over a shipped capability — exactly the class PR-4 forbids, and Guard 1 cannot catch it because the lint proves consistency, not truth | AC-4c narrows the entry to **server-side, Soleur-hosted Playwright for tenant service automation**, with `aliases` restricted to that framing and `scope:` naming `agent-browser`, the `playwright` MCP server and `ux-audit` as the implemented paths that are *not* refused |
| **R25** | **Five "unchanged" ACs were vacuously satisfiable.** Bare `git diff` / `git diff --stat` compares worktree↔index and is blind to anything already committed — and `one-shot`/`work` commit per phase, so AC-9/12/13/16/17 all read green while the defect was live. This is the same class the plan cites at its own Research Insights line | All six `git diff` sites are anchored: `git diff --stat <merge-base>..HEAD -- <path>` |
| **R26** | **AC-24's grep false-fails on this plan file itself.** Four added lines carry the vendor mark outside the sanctioned comment (the peer-source table, the stale-PR row, the NOTICE description, the `gh api repos/mattpocock/skills/…` fetch line), and AC-33 makes the plan an added path. Same for the spec artifacts | The grep is **path-scoped to the payload tree** (`plugins/soleur/**`) plus the founder-facing artifacts, with `knowledge-base/project/{plans,specs}/**` excluded as point-in-time records — the same carve-out shape this repo already uses for rename sweeps. The `grep -v` for the sanctioned form stays, and so does the Sharp Edge warning that deleting attribution is the wrong "fix" |
| **R27** | **AC-24's authority citation was circular.** Constitution line 192's own operative citation *is* `hr-third-party-content-grep-on-undertaking` — the rule I said not to cite — and its rationale is scoped to licences where credit is *optional* (it names CC0 and argues that shipping credit is "choosing to run a third party's ad"). Under **MIT**, retaining the notice **is** satisfying a licence term, so the clause's reasoning inverts here | Both authorities are cited with their actual scopes: the hard rule supplies the *grep-the-diff* obligation (and is not a near-miss once the clause's own pointer is read), while the strip-from-emitted-output half rests on the constitution clause **with an explicit MIT carve-out** stating that the in-repo `NOTICE` satisfies the licence and the in-file comment is a Soleur provenance convention, not the discharge |

Two further paper resolutions the same lens caught, both now closed: the **seed entry** had no
`## Files to Create` row and no phase step despite AC-4c mandating it (added to Phase 3 step 4 and the
file list), and the **`prior_requests` network assertion** named "the full battery" without a suite, a
mutation row or an AC (it is now a named case in the relocated battery). One Observability failure mode
was **dropped** rather than fixed: the branch claiming the lint rejects a `Verdict:` line inside a
pre-check block cannot work, because pre-check blocks are emitted inline by a read-only agent and no file
under the lint's glob ever contains one — the plan's own Support finding says exactly that. Keeping it
would have shipped an unasserted, unmutated lint arm.

### Also applied, from the same panel

- **The `requester` closed vocabulary was never enumerated anywhere**, so a writer could be blocked by a
  check whose legal values no artifact published. Resolved by R12 — the field is gone. The `searched:`
  line format is published in the README and the seed entry is the copyable shape.
- **`revisit_if` had no evaluator.** It appeared only inside prose about what was *not* adopted, was
  absent from the README field set and from every AC, and nothing fired it — while the plan promised the
  founder is interrupted *"only when their own recorded `revisit_if` trigger fires."* It is now a
  required, syntactically-checkable field, and the **reopen path is defined**: an entry gains
  `superseded_by` and is never deleted, with the lint asserting a superseded entry no longer
  participates in matching. That also supplies the retraction path the plan lacked for the case it
  itself calls more dangerous than stale debt.
- **A third intake surface went unnamed.** `triage/SKILL.md`'s own body says *"The `soleur:review` skill
  now creates GitHub issues directly for all new findings"* — the repo's highest-volume issue producer,
  which never passes through `ticket-triage`. Added to Non-Goals with a named blocker rather than left
  silently uncovered.
- **The `.openhands` mirror edit instruction was unexecutable.** The plan said to place the pre-checks
  *"outside the `eval-gate:block:ticket-triage` markers"* in both files — but those markers **do not
  exist in the mirror** (source 2, mirror 0; added by #5701 and never mirrored), and the mirror is also
  missing the `meta/machinery` no-route rule from #8038, so the OpenHands triage still has the
  skew-producing behaviour. Fleet-wide, 40 of 63 mirrored agents have drifted. The instruction is
  corrected, and **#8306** — which owns mirror completeness and is blocked on whether OpenHands is a
  supported harness — is cited in both the Files-to-Edit row and the Risks table, replacing the claim
  that AC9 was the mitigation.
- **`wg-when-deferring-a-capability-create-a` was under-applied.** The plan said "three tracking issues"
  against **six** Non-Goals without naming which three or running the triple test for any. Non-Goals 1,
  3 and the `soleur:review` surface are filed (each passes the triple test: a real capability gap, a
  named blocker needing its own cycle, not documentable-in-place because it is a different surface); 2,
  5 and 6 stay **documented in place**, which is the rule's default and avoids phantom backlog.
- **`prior_requests` and `public_note` are writer-only in v1** — their readers are Non-Goals 2 and 5.
  Both stay in the schema because the store's value is the record, but the plan now says so plainly
  instead of implying a reader exists.
- **The outcome claim is 1-for-3 and is restated for the PR body.** The issue's sentence is kept as the
  aspiration; what ships is: *agents resolve internal nouns the same way across sessions; a refusal is
  recorded once and found by the next triage pass; and when the answer is in someone else's head, the
  founder gets a document to send instead of a stalled session.* Only the third clause is delivered as
  the issue words it — clause 2's audience is measured at zero by this plan's own reconciliation table,
  and shipping the unmeasured version into a release digest would make a roadmap promise read as a
  shipped outcome.
- **G7 added to D4:** the emitted document's register is the brand guide's General register, first-person
  singular, sender is the founder as a person (Jikigai where an entity is required), and the word
  "Soleur" does not appear. D4's six guardrails were all *provenance* and none was *register*, and there
  was no voice AC anywhere. One AC now runs over the fixture AC-20 already produces: zero emoji, zero
  sender-referring `\bwe\b`/`\bour\b`, zero hedges from a fixed list, zero occurrences of `Soleur`.
- **Naming, refined.** "Rejected-concepts store" decays in speech back to "the register" — the word D1
  banned — and "store" is datastore jargon on the wrong side of the brand guide's business-analogy rule.
  Two fixed names replace it: **"the no-list"** in founder-facing and skill prose (the founder's own
  words — the issue says *"'no' only has to be said once"*), and **"rejected-concepts record"** where a
  formal noun is required. `register`'s `_Avoid_` list names both the banned synonym and "store".
- **The Domain Review's marketing row was wrong.** "Not relevant" was concluded from the absence of a
  marketing *file edit*, but the marketing surfaces here are a publicly readable record of what the
  company refused to build, a document that leaves the company under the founder's name, and the outcome
  claim — none of which touch `glossary.njk`. The row is amended to *reviewed; no edit to `glossary.njk`
  (D5); residual brand risk is the public refusal record, the emitted document's register, and the
  outcome claim*, with the findings above. Leaving "not relevant" would have set a precedent that a
  public artifact needs no brand lens so long as no marketing file is edited.
- **The public-glossary leak path is closed in the artifact, not only in the skill.** By D2 test 4 the
  internal glossary is *by construction* the list of words the customer must never see, and a future
  content session greps `knowledge-base/` and finds it. Its header now carries an explicit negative
  clause naming both siblings by path — `plugins/soleur/docs/pages/glossary.njk` (public/SEO) and
  `knowledge-base/marketing/brand-guide.md` § Audience Voice Profiles → Key term glossary
  (customer-facing equivalents) — and stating it is neither. One AC asserts both paths are named.
- **AC5 asserted counts, not identity.** "≥N rows across ≥5 axes" is satisfied by N copies of one row,
  and the axis label was self-reported. It now asserts **identity**: a stable case id per matrix row, and
  the emitted id set equals the matrix id set — the `Object.keys(...).sort()` equality shape
  `workflow-fidelity.test.ts` already uses.
- **AC9 asserted presence, not parity.** For a mirror the plan itself says has no generator and no
  parity test, the real invariant is that the two files **agree with each other**: the shared block is
  extracted from both and asserted byte-equal.
- **AC2 asserted path shape, not resolution.** It now asserts the target file exists **and** the cited
  heading string is present, per `cq-cite-content-anchor-not-line-number`.
- **AC16 counted a substring across the whole file.** It now extracts each harness block and asserts the
  token once per block, since three mentions inside one block would pass while two blocks went unedited.

### Standing panel check — corrected verdict

The earlier verdict on `cq-ac-must-not-depend-on-concurrent-sessions` read **clean**, and that was
wrong. I applied the litmus only to *ambient machine state* — a sibling worktree, free disk, a wall-clock
bound — and never to the other member of the same class: **a sibling branch moving a shared constant**.
Nine criteria asserted absolute literals (`B_ALWAYS=42920`, the `2499/2499` baseline, `103` skills, the
hook inventory `13`, the ADR ordinal, and the several suites whose greens depend on headroom measured
today). Each could flip from true to false with no line of this diff changing, which is exactly what the
rule prohibits. All nine are rewritten per R16 to assert a delta, an empty diff, or a green suite. The
plan's own record of this failure is more useful than a corrected pass would have been: the check was run
honestly and its scope was too narrow, which is the `hr-verify-repo-capability-claim-before-assert`
shape applied to a gate rather than to a capability.

### Added after review (R3, R6, R7, R8, G7)

34. **Flow A has a producer (R3).** `grep -c 'kb-glossary' plugins/soleur/skills/compound/SKILL.md` is
    ≥1, and `plugins/soleur/skills/kb-glossary/SKILL.md` contains a `## When to self-invoke` heading.
    Without both, the write discipline is prose nothing reaches.
35. **Flow B's pointers are asserted (R7).** Each of `brainstorm`, `plan`, `spec-templates`,
    `architecture`, `operator-rephrase`, `operator-digest` and `knowledge-base/project/constitution.md`
    greps positive for `knowledge-base/project/glossary.md`. An earlier revision asserted only
    `operator-rephrase`, and AC18 passes identically whether the other pointers exist.
36. **Reachability, not existence (R8).** Each new skill is named by a live invoker: both appear in a
    `go.md` routing row; `kb-glossary` appears in `compound/SKILL.md`; `questionnaire-generate` is
    reached by the hook's behavioural deny (AC11).
37. **Flow C has a write path (R4).** `plugins/soleur/skills/triage/SKILL.md` Step 2 carries a fourth
    branch that records a rejection, and it is the only branch that removes a finding.
38. **Flow D's return leg exists (R6).** The emitted fixture carries `recipient_role`, `needed_by`,
    `blocked_decision` and `status` in frontmatter, an `## Answers` section and a `## Blocked on`
    back-pointer; `bash scripts/followthroughs/questionnaire-unanswered-8289.sh` exits `2` or `3` on a
    clean tree and never `0` or `1`.
39. **The emitted questionnaire has an address (R5).** The fixture lands under
    `knowledge-base/project/questionnaires/` matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}-.*\.md$`.
40. **Voice (G7).** Over the fixture AC-20 produces by running the skill: zero emoji, zero
    sender-referring `\bwe\b`/`\bour\b`, zero hedges from a fixed list (`might`, `could`,
    `potentially`, `perhaps`), and zero occurrences of `Soleur`. D4's six guardrails were all
    provenance; this is the only register gate in the bundle.
41. **The glossary names both siblings.** `knowledge-base/project/glossary.md` names
    `plugins/soleur/docs/pages/glossary.njk` and
    `knowledge-base/marketing/brand-guide.md` by path and states it is neither — the leak path closed in
    the artifact a grepping session lands on, not only in the skill.
42. **Matrix identity, not counts (AC5's replacement).** The suite emits a stable case id per matrix row
    and the emitted id set **equals** the matrix id set, in the `Object.keys(...).sort()` equality shape
    `plugins/soleur/test/workflow-fidelity.test.ts` already uses. A count is satisfied by N copies of one
    row.
43. **Mirror parity, not presence (AC9's extension).** The shared pre-check block is extracted from
    `plugins/soleur/agents/support/ticket-triage.md` and
    `.openhands/skills/ticket-triage/SKILL.md` and asserted byte-equal. Note the mirror does **not**
    currently carry the `eval-gate:block:ticket-triage` markers (source 2, mirror 0) or the
    `meta/machinery` rule, so the placement instruction anchors on `## Scope` rather than on those
    markers; broader mirror completeness is **#8306**, not this PR.
44. **The store is advisory-only.** `knowledge-base/project/rejected/README.md` and the ADR both carry the
    clause, and the lint rejects an entry naming itself as sufficient grounds to close or label an issue.
    This clause is also a named precondition on Non-Goal 1's tracking issue.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The register becomes a write-mostly artifact — the `technical-debt/` outcome (11 entries, 0 closures, #2723) | Its reader ships in the same increment (Phase 3 is one phase by construction), and the plan declines the requester-facing half that would have inflated it without readers |
| A false rejection poisons concept-dedup, and the mechanism that would catch the error is the one the error disabled | Guard 1 asserts the mutual exclusion at commit time: `redundancy_check` exactly `not-implemented`, `searched` non-empty, `implemented_at` absent |
| An entry's blunt internal reason is quoted back to a requester | `why` and `public_note` are separate required fields, and only `public_note` may be reused outward |
| A narrower incoming request matches a broader rejection and is closed with a reason that does not address it | `scope` is required, and an uncertain match **fails open** — escalate, never auto-close |
| A register entry names a person, creating permanent personal data in a public repository | `requester` is a closed-vocabulary role token, asserted by the lint (mutation row 5), not requested in prose |
| The `ticket-triage` body mirror in `.openhands/` silently drifts (no generator, no parity test) | Both files are in `## Files to Edit`; AC9 asserts the pre-checks in both |
| The two new `go.md` rows cannibalise `default → brainstorm`, which currently absorbs "questions" | Trigger signals key on *a document to send to a named third party*, and the `go-routing` eval is the empirical check rather than a judgement call |
| ADR-232's ordinal is claimed mid-pipeline (it has happened twice on one branch before) | Phase 6 re-derives across every `origin/*` ref immediately before merge and sweeps the whole artifact set on renumber |
| The glossary drifts from the definers it points at | Entries are pointers, not restatements — the drift surface is removed rather than monitored |
| The emitted questionnaire carries internal context to a third party with no data-processing agreement | The `## Context` guardrails are a Phase 4 deliverable, the GDPR gate is asked that exact question in Phase 0, and the threshold puts `user-impact-reviewer` on the diff |
| The questionnaire component is vetoed by the published legal corpus after the other three land | Phase 0 step 5 runs that grep **before** Phase 4, so the veto surfaces while a split is still cheap |

## Test Scenarios

Written as `mutation → guard reddens`, not `command → terminal output`.

1. An entry with `redundancy_check: implemented` → `scripts/lint-rejected-register.sh` exits non-zero
   naming the file and the field.
2. An entry with no `redundancy_check` key → RED.
3. An entry carrying `implemented_at:` → RED.
4. An entry with `searched:` present but empty → RED.
5. An entry whose `requester:` is a personal name → RED.
6. A **valid** entry that is not `README.md` → the lint **passes** (must-PASS, non-canonical).
7. Two entries, first valid and second invalid → RED (the check does not stop at the first member).
8. The lint invoked with zero path arguments → reports `0 files` and does **not** certify the store.
9. Delete the `implemented_at` branch from the lint → the battery reddens.
10. Replace the enum comparison with a substring match → the battery reddens, because
    `not-implemented` contains `implemented`.
11. Reroute the suite's `bad()` to the pass counter → the suite exits non-zero (direction, not
    presence).
12. Remove one battery case → the `MIN_CASES` floor reddens.
13. Remove one whole axis → the `MIN_AXES` floor reddens.
14. Remove rung 5 from the hook's `REASON` → `pre-ask-technical-fork-gate.test.sh` reddens.
15. Add a skill without bumping `SKILL_DESCRIPTION_WORD_BUDGET` →
    `plugins/soleur/test/components.test.ts` reddens, proving AC14 is load-bearing.
16. Render the questionnaire template through the emitter → the output contains no `Inspired by` line.
17. Inject a 12-word run from a peer blob into a scratch copy of the glossary → AC-L1(b) reports ≥1
    (the positive control; without it a vacuous scorer reads as clean).
18. Truncate the glossary to two headings → AC-L1(a) reddens on the non-vacuity floor rather than
    passing with zero shared shingles.
19. Restore `ships with no vocabulary source` to `operator-rephrase` → AC3 reddens.
20. Rename **two** headings in `plugins/soleur/docs/pages/glossary.njk` → `seo-aeo-drift-guard.test.ts`
    reddens at `found >= 8` (currently 9, so one rename still passes). This scenario is written as two
    deliberately: an earlier revision said one, which would have shipped a mutation row that does not
    redden — a vacuous case in a battery whose whole purpose is to exclude those.
21. Name `README.md` as a concept entry (drop the `YYYY-MM-DD-` prefix requirement) → the
    concept-similarity lookup matches the convention document itself and manufactures a false
    rejection; AC4b reddens.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with a concrete
  artifact and a concrete vector; do not reduce either to a category name.
- **A write to this plan file can be denied by `.claude/hooks/iac-plan-write-guard.sh` for prose that
  merely *names* the patterns it matches** — this file's `## Infrastructure (IaC)` section tripped it
  twice while asserting that no such step exists (the #7003 class). The resolution is to **reword**, and
  both instances were reworded. Do **not** reach for the `iac-routing-ack` opt-out here: it asserts that
  a reviewed infrastructure step is genuinely required, which is false for this plan, and using it to
  force a write would put a false claim in the record.
- **The `grep -v` filter for the sanctioned attribution form is load-bearing in the vendor-mark grep.**
  Without it the existing attribution comments trip the grep themselves, and the instinctive "fix" —
  deleting the attribution — is the one change that moves toward an actual licence problem. The MIT
  notice is discharged by `plugins/soleur/NOTICE` in the payload, never by the in-file comment.
- **`not-implemented` contains `implemented`.** Any comparison against the `redundancy_check` enum must
  be whole-value; a substring match inverts the guard silently. Mutation row 10 exists to catch exactly
  this, and `cq-assert-anchor-not-bare-token` is the general form.
- **An artifact with zero 8-word shingles shares zero shingles with everything.** A bare "0 shared
  shingles" assertion over a file that is mostly headings, field names and answer stubs passes
  trivially. AC-L1(a)'s non-vacuity floor and AC-L1(d)'s positive control are what make the comparison
  evidence rather than ceremony.
- **Do not claim invocation measurability for either new skill.** `skill-freshness.json` reports 67 of
  67 existing skills as `never_invoked`, because its producing cron reads a gitignored JSONL from an
  ephemeral clone. Two new skills land there as `never_invoked` forever. The glossary's accountability is
  structural (a missing term shows up as an untranslated word in founder-facing output), not metered.
- **The deferred scheduled-pass issue must name the absent checkout, not absent tools.**
  `cron-daily-triage.ts` line 171 grants `Read,Glob,Grep`; line 216 says it never clones. A follow-up
  filed against a missing-tools cause gets closed by a one-line change that fixes nothing.
