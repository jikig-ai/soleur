---
title: Plan skill — grep hard-rule body verbatim before prescribing rule details; cross-reviewer convergence catches paraphrase-from-memory inversions
date: 2026-05-14
category: workflow-issues
tags:
  - plan-skill
  - hard-rule-paraphrase
  - search-path-injection
  - cross-reviewer-convergence
  - n1-validation-gate
  - planner-prescriptions
issue: 3723
plan: knowledge-base/project/plans/2026-05-14-feat-soleur-managed-deploy-substrate-v1-scaffolding-plan.md
status: published
---

# Learning: Plan skill — grep hard-rule body verbatim before prescribing rule details

## Problem

Plan revision-1 for #3723 (multi-tenant deploy substrate) prescribed `SET search_path = pg_temp, public` (pg_temp FIRST) inside the proposed Supabase migration 043, justified by a Sharp Edge bullet claiming "pg_temp first to defeat search-path injection." The plan then built **three** load-bearing artifacts on top of this inversion:

1. A Risks section bullet (R5) explaining the divergence from the 041 dsar precedent (claimed: "the 041 precedent uses `public, pg_temp` (public first); this plan deliberately overrides to put `pg_temp` first per the hard rule").
2. A Sharp Edges bullet warning future readers not to "copy ordering from the non-compliant precedent."
3. An ADR-030 sub-section noting the divergence as a deliberate design choice.

All three were wrong. The actual hard rule (`cq-pg-security-definer-search-path-pin-pg-temp` in `AGENTS.core.md:16`) reads verbatim: **"MUST pin `SET search_path = public, pg_temp` (in that order)"**, with the explicit rationale that listing `public` first + qualifying in the body is the belt-and-suspenders against `pg_temp` schema-planting. The 041 dsar precedent at `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql:184,239,280,320` is COMPLIANT, not non-compliant. The plan had inverted the rule from memory and built explanatory structure on top of the inversion.

Two other related defects in the same plan were paraphrase-from-memory artifacts:

- `oidc_jti uuid` (RFC 7519 §4.1.7 defines `jti` as a case-sensitive string; GitHub's OIDC currently uses UUID-shape jti but the spec does not guarantee it). Correct: `text NOT NULL CHECK (length BETWEEN 1 AND 255)`.
- `ON DELETE SET NULL` on `founder_id` FK with a co-located `anonymise_*` RPC. The `SET NULL` fires before the RPC can run, breaking the Art. 17 cascade. Correct: `ON DELETE RESTRICT`.

Kieran caught the search_path inversion; spec-flow-analyzer caught the FK action mismatch. Both are paraphrase-from-memory mode failures — the planner read the rule once at brainstorm time, then prescribed details from working memory at plan time without re-reading.

## Solution

**At plan-draft time, every prescription that cites a hard-rule ID, an RFC clause, or a precedent file MUST be backed by a `grep`/Read of the cited source in the same plan-drafting session.** Three concrete check shapes:

1. **Hard-rule citations:** when the plan body says "per `<rule-id>`" or includes a specific format/ordering/syntax from a rule, run `grep -A8 "<rule-id>" AGENTS.core.md` and copy the relevant ordering/format from the result. Do NOT paraphrase the rule body — quote it.
2. **External-spec citations (RFC/OAuth/JWT/HTTP):** when prescribing a column type / claim format / header shape for a spec-defined field, cite the RFC + section number in the plan AND name the spec's defined type. `jti` is "a case-sensitive string" per RFC 7519 §4.1.7 — `text` not `uuid`.
3. **Precedent-file citations:** when the plan says "clone migration X / file Y verbatim," `Read` the precedent file's relevant lines in the same drafting session and copy the actual primitives, not the planner's recollection.

The forward-looking principle: **the planner is the load-bearing prescriber; the work skill executes verbatim.** Any drift between the planner's mental model and the actual rule body becomes a defect at /work time, which is the most expensive point to catch it.

## Key Insight (cross-reviewer convergence)

The 5-reviewer parallel pass (DHH + Kieran + code-simplicity + spec-flow + legal-compliance) caught all three defects above plus a fourth class — premature factoring at N=1 (scaffold template + orchestration TS module + cross-tenant test that DHH and code-simplicity independently flagged from different angles).

**Cross-reviewer convergence is a stronger signal than any single reviewer's finding.** DHH argued from "build less, ship later" first principles. Code-simplicity argued from "templates earn their keep on the third copy." Spec-flow-analyzer argued from "enum-without-writer is a defect class." Three reviewers reaching the same conclusion from different reasoning paths is dispositive — the planner should accept the cut without spending tokens to argue the case.

This is the inverse-pattern to the false-consensus risk: when one reviewer's finding looks compelling but no other reviewer surfaces it, the finding may be true but is low-confidence. When multiple reviewers converge from different reasoning paths, the finding is high-confidence and should be applied promptly. The 5-reviewer parallel pass is calibrated to surface convergence within ~5-10 min of spawn.

The corollary: **plan-review is most valuable when reviewers reason from different premises.** A homogeneous review pass (all reviewers applying the same lens) is less informative than a deliberately heterogeneous one (DHH's brutality + Kieran's strictness + simplicity's YAGNI + spec-flow's gap-hunting + legal's compliance lens).

## Session Errors

This is what the plan-skill captured (full list at top of this file's "Problem" section):

1. **search_path order inverted** (`pg_temp, public` instead of `public, pg_temp`). Recovery: revision-2 rewrite. Prevention: grep hard-rule body verbatim before prescribing rule details (see Solution §1).
2. **oidc_jti uuid instead of text** (RFC 7519 §4.1.7). Recovery: revision-2 changed type. Prevention: cite RFC + section for any spec-defined field type (see Solution §2).
3. **ON DELETE SET NULL would fire before anonymise RPC**, breaking Art. 17 cascade. Recovery: revision-2 changed to RESTRICT. Prevention: trace operational order when FK actions interact with anonymise RPCs.
4. **provisioning_step_* enum values without writer code**. Recovery: revision-2 removed values. Prevention: enum members require at least one writer site in the same PR.
5. **Premature factoring at N=1** (scaffold template + orchestration module + cross-tenant test). Recovery: revision-2 cut all three. Prevention: apply "templates earn keep at 3rd copy" + "modules earn keep at 2 callsites" at N=1 validation gates.

## Related

- `knowledge-base/project/learnings/2026-05-14-brainstorm-cross-check-leader-substrate-and-issue-body-rule-citations.md` — Sibling pattern at brainstorm time: cross-check leader recommendations + issue-body hard-rule citations.
- `knowledge-base/project/learnings/best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` — Paraphrase-without-verification class (issue-body paths).
- `knowledge-base/project/learnings/2026-05-12-plan-time-parsing-pattern-needs-codebase-precedent-grep.md` — Plan-time parsing-pattern grep precedent (gsub awk).
- `knowledge-base/project/learnings/2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md` — AC paraphrase drift class.

## Tags

category: workflow-issues
module: plan
