---
date: 2026-07-26
category: workflow-patterns
module: brainstorm
tags: [prior-art, premise-validation, subagent-scope, external-product-evaluation, adr-corpus]
issues: [6962, 6959, 6960, 6961]
pr: 6958
---

# Learning: a prior-art negative is only as broad as what you actually swept

## Problem

The Openship adoption brainstorm (#6962) opened on a **false greenfield premise**. Two independent checks both
returned "no prior art," and both were wrong in the same direction.

**Check 1 — the Phase 1.1 sweep.** It globbed on product and competitor names:

```bash
find knowledge-base/project/{brainstorms,specs,learnings} -maxdepth 3 -type f \
  \( -iname "*openship*" -o -iname "*paas*" -o -iname "*deploy-platform*" \
     -o -iname "*coolify*" -o -iname "*dokku*" -o -iname "*self-host*" \)
```

One unrelated hit. A companion `git grep` across the ADR corpus for
`coolify|dokku|caprover|render\.com|fly\.io|railway` also returned nothing.

**Check 2 — the `learnings-researcher` subagent.** It reported, in its own words, *"Repository-wide search found
zero prior evaluations of specific PaaS/deploy platforms."*

Both were false. `ADR-030 — Multi-tenant deploy substrate` (accepted 2026-05-14) had already decided this exact
architectural question, carrying a **hard constraint** that governs it. Alongside it sat an archived brainstorm,
plan, spec, and a legitimate-interest assessment.

It surfaced only when the CTO leader cited ADR-030 — after five domain leaders had already been spawned on the
wrong premise.

## Root cause

Two distinct failures that happen to produce the same symptom.

**1. The sweep was keyed on identity, not function.** The prior art was named for what it *does* — "deploy
substrate," "multi-tenant deploy" — not for any vendor. No amount of competitor-name enumeration finds it,
because the vendor did not exist when it was written. The winning term was one nobody would list while thinking
about a specific product.

Compounding this, the sweep's **roots** were `knowledge-base/project/{brainstorms,specs,learnings}` — which
structurally cannot reach three of the six relevant artifacts:

```
knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md   ← the governing ADR
knowledge-base/legal/legitimate-interest-assessments/2026-05-14-tenant-deploy-substrate-lia.md
knowledge-base/project/plans/archive/…-deploy-substrate-v1-scaffolding-plan.md               ← plans/ not a root
```

**Depth was never the failure**, and an earlier draft of this learning wrongly said it was. With the *right*
term, the *same* `-maxdepth 3` and the *same* roots return the archived brainstorm — it sits at depth 2:

```
find knowledge-base/project/{brainstorms,specs,learnings} -maxdepth 3 -type f -iname "*deploy-substrate*"
  → knowledge-base/project/brainstorms/archive/20260515-…-deploy-substrate-multi-tenant-brainstorm.md
```

Two further properties of `find` that `git ls-files` does not share: `-type f -iname` matches **basenames only**,
so a spec whose keyword lives in the *directory* name is invisible to it (verified — the archived
`specs/archive/…-deploy-substrate-3723/{spec,tasks}.md` return zero hits from `find`, six from `git ls-files`);
and the root list has to be maintained by hand.

Separately: **archived planning artifacts remain canonical for the decisions they record.** ADR-030's frontmatter
cites its brainstorm at the *unarchived* path, so following the citation literally produces `sed: No such file` —
a false "missing" for a file that is present one directory deeper.

**2. A scoped agent's negative was read as a global negative — but not for the reason the first draft gave.**
`learnings-researcher` reported "repository-wide search found zero prior evaluations," and that phrasing was
accepted at face value.

The first draft explained this as a *charter* gap ("the ADR corpus is a directory the agent is not chartered to
read"). **That is false**, and review caught it. The agent's Step 0
(`plugins/soleur/agents/engineering/research/learnings-researcher.md`) instructs it to grep
`knowledge-base/INDEX.md` first, which "reveals relevant files across ALL domains" — and INDEX.md line 39 *is*
`ADR-030 — Multi-tenant deploy substrate`. The agent was fully chartered to reach it.

What is actually true is narrower, and more useful:

- A scoped agent's negative is bounded by **its index**, and `INDEX.md` excludes two classes — **0** `/archive/` rows AND per-feature working state under `project/specs/` (ADR-173) — so
  archived artifacts are genuinely outside its reach.
- Everything else it missed, it missed for the *same reason as (1)*: the query vocabulary was the vendor's name,
  and INDEX.md files the prior art under the function's name.

So both checks failed for one root cause, not two. That matters for the fix: widening an agent's charter would
not have helped, and "check what the agent is chartered to read" — the first draft's prescription — would have
concluded the agent *could* see ADR-030 and stopped there.

## Solution

Applied inline to `plugins/soleur/skills/brainstorm/SKILL.md` Phase 1.1 as one bullet, since both facets are the
same insight — *a negative result carries only the scope that produced it.*

When an external-product evaluation's prior-art sweep returns nothing:

1. **Re-sweep on the product's function, not its name.** Ask "what would someone have called this decision
   before this vendor existed?" — two or three functional nouns (`deploy substrate`, `secret distribution`,
   `identity provider`).
2. **Match both separators, and search paths not basenames.** Filenames hyphenate what prose spaces, so the
   naive composition of step 1 into a filename grep **silently returns zero** — the exact false-greenfield this
   rule exists to prevent:

   ```bash
   git ls-files | grep -i  "deploy substrate"          # → 0 hits   (prose form; filenames are hyphenated)
   git ls-files | grep -iE 'deploy[-_ ]substrate'      # → 6 hits   (all correct, incl. archive/ + ADR + LIA)
   ```

   Use the `[-_ ]` form. `git ls-files` is unrooted and matches **full paths**, so unlike a rooted
   `find -type f -iname` it reaches the ADR corpus, `knowledge-base/legal/`, `plans/`, `**/archive/`, and specs
   whose keyword lives in the *directory* name. Grep file *contents* with the spaced form separately.
3. **Follow an ADR's frontmatter citations, and if the path 404s, search for the basename** before concluding
   the artifact is gone. Archiving rewrites paths; frontmatter is not updated.
4. **Never restate a scoped agent's negative as a global one — and check its INDEX, not its charter.** The
   binding limit on `learnings-researcher` is that `knowledge-base/INDEX.md` excludes `**/archive/` **and per-feature working state under `project/specs/`** (ADR-173), not that
   it may only read `learnings/`. So: re-run the INDEX grep yourself with function vocabulary, and treat
   archived artifacts as unproven by any INDEX-following agent.

## Key Insight

**A negative search result is a statement about the query, not about the repository.** Both the glob and the
subagent were correct about what they examined; the error was in how broadly their silence was interpreted.

For external-product evaluations this bites hardest, because the natural query vocabulary is the vendor's — and
the institution's own prior art is filed under the *problem's* vocabulary. The vendor's name is the one term
guaranteed absent from every record written before it launched.

**The same session then produced the mirror image of this defect, which is the more valuable half.** The
resulting decision record asserted three facts about the vendor — no legal entity, no RBAC, no disclosure
process — under an explicit banner reading *"Verified via `gh api` and the repo's own README — **not** from the
marketing surface."* All three live on the product site. The method could not see them, and the exclusion was
presented as rigor. So:

> A sweep that cannot reach a class of fact will report that class absent, and it will do so in the same
> confident register it uses for facts it actually measured. **Scope-completeness is a property of the source
> set, and it has to be argued, not asserted** — "I deliberately did not look there" is a reason to hedge, never
> a reason to conclude.

Inward (repo prior art) and outward (vendor facts), it is one rule.

## Prevention

- **State each finding as what was observed, not what was inferred.** `community/profile returns null` is a
  measurement; "no disclosure process" is a claim about the world, and a root `SECURITY.md` refutes it. The
  hedge in this session survived in the evidence table ("None *identified*") and was dropped by the time it
  reached the verdict — the hedge is present where it is least read and absent where the decision is made.
- **For a vendor evaluation, the source set must include the product site** (`/terms`, `/privacy`, `/trust`,
  `/security`, the footer) and a `contents/` probe for `SECURITY.md` / `LICENSE` / governance files. An
  API-only sweep is structurally incapable of answering legal, commercial, or policy questions.
- **Re-derive any ratio whose denominator you did not measure.** "225 of ~290 (~78%)" was really 226/386 (~59%);
  the true total was available two ways (`Link: rel="last"`, anonymous-contributor sum) and both say 386.
- **A deferral gate must be calibrated against verified state.** Two of the five original re-open triggers were
  already satisfied on the day they were written, which corrupts the instrument: a future reader either
  believes conditions newly cleared, or dismisses the issue as unreachable.
- The prior-art sweep is cheap; the wrong-premise leader fan-out is not. Five leaders ran before the premise
  was corrected.
- The correction arrived from a leader (CTO), not from the sweep — and the vendor-fact corrections arrived from
  review, not from the author. Neither is process; both are luck that happened to hold.

## Session Errors

1. **Stale cost figure propagated into all five domain-leader prompts — then the correction was wrong twice
   more.** `~$81/mo product COGS, break-even 2 users` came from `roadmap.md` (lines 63/74/454, anchored
   2026-04-23). The COO corrected it to `$234.34`; I repeated that; a review agent then "verified" it by citing
   `$231.33`. All three are superseded intermediates in the review-note chain
   `$200.11 → $231.33 → $234.34 → $223.39`. The authoritative value is the **subtotal**:
   `cost-model.md:204` = **`223.39`**, with all three break-even tables (`:284`, `:297`, `:328`) at **5 users**.
   True understatement ≈ **2.75×**.
   Three independent readers landed on a wrong number because `cost-model.md` **contradicts itself** — line 204's
   subtotal reads `223.39` while line 232's summary reads `~$234/month`, both under the same
   `[expenses.md@2026-07-17]` anchor.
   **Recovery:** measured the subtotal and all three break-even tables directly.
   **Prevention:** read the subtotal row or a break-even table — never a narrative review note, and never a
   downstream summary. Filed as #6959 (now covering both the stale roadmap rows and the self-inconsistency);
   the 2-line `roadmap.md` correction was folded inline rather than deferred.

2. **Prior-art sweep keyed on competitor names missed the governing ADR.** See root cause above.
   **Recovery:** CTO cited ADR-030; verified directly and re-framed. **Prevention:** applied inline to
   brainstorm SKILL.md Phase 1.1.

3. **Scoped subagent negative reported as repo-wide — and my first explanation of *why* was also wrong.**
   `learnings-researcher` said "repository-wide"; I attributed that to a charter limited to `learnings/`.
   Review refuted it: the agent's Step 0 greps `INDEX.md` across all domains, and INDEX.md line 39 carries
   ADR-030. The real limit is that INDEX.md holds **0** `/archive/` rows and no per-feature working state under `project/specs/` (ADR-173), plus the same vendor-vocabulary
   problem as #2. **Recovery:** read the agent definition and INDEX.md directly.
   **Prevention:** corrected in the Root cause and Solution sections; the prescription is now "re-run the INDEX
   grep with function vocabulary", not "check the agent's charter".

3b. **The rule this learning prescribes was itself vacuous as first written.** Step 1 supplied *spaced*
   functional nouns (`deploy substrate`) and step 2 said to `grep -i <function>` over filenames — which are
   hyphenated. Composed literally: **0 hits**, silently. The fix (`grep -iE 'deploy[-_ ]substrate'`) returns
   6 and is now verified in-document. A rule whose worked example reproduces the failure it prevents is worse
   than no rule. **Prevention:** every prescribed command in a learning must be executed and its hit count
   recorded before the learning is committed.

4. **Duplicate ADR numbers caused a wrong-file read.** `ADR-030` names both `inngest-as-durable-trigger-layer`
   and `multi-tenant-deploy-substrate`; `ADR-027`, `ADR-031`, `ADR-033`, `ADR-038` also collide. Reading "ADR-030"
   opened the wrong record first. **Recovery:** `ls | grep ADR-030` disambiguated. **Prevention:** filed #6960
   proposing a CI guard against duplicate `ADR-NNN` prefixes. This directly undermines the existing brainstorm
   rule to *"verify any cited ADR number → mechanism mapping"* — that rule assumes numbers are unique.

5. **`roadmap-reconcile.sh validate` reported phase-4 drift** (`roadmap=56o/179c` vs `milestone=67o/183c`).
   **Recovery:** not corrected in-worktree; the sanctioned fix is the roadmap-review cron, which opens a reviewed
   PR. Surfaced to the operator. No assessment was affected — the CPO pulled live milestone numbers itself.
   **Prevention:** none needed; the mechanism exists and fired correctly.

6. **`sed` exit 2 following ADR-030's frontmatter brainstorm citation.** The file was archived, not missing.
   **Recovery:** `find` located it under `brainstorms/archive/`. **Prevention:** folded into #2 — treat a 404 on
   a frontmatter-cited artifact as "search for the basename," not "it does not exist."

7. **Three vendor "facts" in the decision record were false — the outward mirror of this learning's own thesis,
   committed in the same PR.** The evidence table declared *"Verified via `gh api` and the repo's own README —
   **not** from the marketing surface"*, then asserted no legal entity, no RBAC/multi-tenancy, and no disclosure
   process. All three are published on the product site the method deliberately excluded:
   Oblien LLC (site JSON-LD `legalName` + every footer; `/terms` §12 Irish governing law);
   `apps/api/src/modules/permissions/*` plus `/trust`'s "role + resource grants" and "Credential custody";
   and a root `SECURITY.md` (4,458 B) plus `/trust` responsible disclosure. The README's *"the first admin"* is
   **ordinal**, and the `(singular)` gloss inverted it. `community/profile → security_policy: null` was read as
   a fact about the world rather than an API-detection artifact.
   Downstream damage: the managed-cloud `PROHIBITED` verdict rested entirely on the false no-entity claim, and
   two of the five re-open triggers in #6961 were already satisfied the day they were written.
   **Recovery:** two review agents converged; each claim re-verified in one command; the evidence table,
   verdicts, domain summaries and triggers were rewritten, and the true stronger ground was substituted
   (`/terms` §02: *"Openship Cloud is not yet generally available"*).
   **Prevention:** see Key Insight — scope-completeness is a property of the source set and must be argued, not
   asserted; and state findings as observations, not inferences.

## Related

- Decision record: `knowledge-base/project/brainstorms/2026-07-26-openship-adoption-eval-brainstorm.md`
- `knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md`
- `knowledge-base/project/learnings/2026-03-25-verify-platform-limits-during-brainstorm.md`
- `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md`
