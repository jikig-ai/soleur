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

Compounding this: the artifacts lived under `knowledge-base/project/*/archive/`, which the `-maxdepth 3` glob
reached only by accident and which reads as "superseded." **Archived planning artifacts remain canonical for
the decisions they record.** ADR-030's frontmatter cites its brainstorm at the *unarchived* path, so following
the citation literally produces `sed: No such file` — a false "missing" for a file that is present one directory
deeper.

**2. A scope-limited agent's negative was read as a global negative.** `learnings-researcher` is *defined* to
search `knowledge-base/project/learnings/`. Its finding was correct and correctly scoped. But it phrased the
result as "repository-wide," and that phrasing was accepted at face value. The decisive prior art was in the ADR
corpus — a directory the agent is not chartered to read.

This is the mirror image of the failure mode the brainstorm skill already warns about (a subagent falsely
reporting a file *absent*). Here the subagent reported a *class* absent, from a vantage point that could not see
the class.

## Solution

Applied inline to `plugins/soleur/skills/brainstorm/SKILL.md` Phase 1.1 as one bullet, since both facets are the
same insight — *a negative result carries only the scope that produced it.*

When an external-product evaluation's prior-art sweep returns nothing:

1. **Re-sweep on the product's function, not its name.** Ask "what would someone have called this decision
   before this vendor existed?" and grep the ADR corpus for that: `deploy substrate`, `secret distribution`,
   `queue`, `identity provider`. Two or three functional nouns.
2. **Include `**/archive/`.** Use `git ls-files | grep -i <function>` rather than a depth-bounded `find` — it
   is scope-complete by construction and catches archived artifacts.
3. **Follow an ADR's frontmatter citations, and if the path 404s, search for the basename** before concluding
   the artifact is gone. Archiving rewrites paths; frontmatter is not updated.
4. **Never restate a scoped agent's negative as a global one.** Before acting on "no prior art exists," check
   what directories the reporting agent is chartered to read. If the ADR corpus, `knowledge-base/legal/`, or
   `**/archive/` are outside its charter, the claim is unproven there.

## Key Insight

**A negative search result is a statement about the query, not about the repository.** Both the glob and the
subagent were correct about what they examined; the error was in how broadly their silence was interpreted.

For external-product evaluations this bites hardest, because the natural query vocabulary is the vendor's — and
the institution's own prior art is filed under the *problem's* vocabulary. The vendor's name is the one term
guaranteed absent from every record written before it launched.

## Prevention

- The prior-art sweep is cheap; the wrong-premise leader fan-out is not. Five leaders ran before the premise
  was corrected — roughly 300k subagent tokens spent partly on the wrong floor.
- The correction arrived from a leader (CTO), not from the sweep. That is luck, not process: the CTO happened to
  be the agent whose charter includes the ADR corpus. Had the question been purely legal or commercial, the
  premise would have survived into the decision record.

## Session Errors

1. **Stale cost figure propagated into all five domain-leader prompts.** `~$81/mo product COGS, break-even 2
   users` was read from `roadmap.md` (lines 63/74/454, anchored 2026-04-23); the authoritative
   `cost-model.md@2026-07-17` says `~$234/mo, break-even 5` — a ~2.9x understatement. The COO caught it
   mid-assessment. **Recovery:** verified both files directly and corrected the record.
   **Prevention:** for any financial figure entering a subagent prompt, read `cost-model.md` (the owner), never
   a downstream summary. `roadmap-reconcile.sh validate` syncs milestone counts but has no financial check —
   filed as #6959 with a proposed `STALE_FINANCIALS` verdict.

2. **Prior-art sweep keyed on competitor names missed the governing ADR.** See root cause above.
   **Recovery:** CTO cited ADR-030; verified directly and re-framed. **Prevention:** applied inline to
   brainstorm SKILL.md Phase 1.1.

3. **Scope-limited subagent negative reported as repo-wide.** See root cause above. **Recovery:** the ADR corpus
   contradicted it. **Prevention:** same bullet.

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

## Related

- Decision record: `knowledge-base/project/brainstorms/2026-07-26-openship-adoption-eval-brainstorm.md`
- `knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md`
- `knowledge-base/project/learnings/2026-03-25-verify-platform-limits-during-brainstorm.md`
- `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md`
