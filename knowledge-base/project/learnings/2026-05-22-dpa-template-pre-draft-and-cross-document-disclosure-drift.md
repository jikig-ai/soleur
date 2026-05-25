---
title: "DPA template pre-draft pattern + cross-document disclosure-drift defects multi-agent review reliably catches"
date: 2026-05-22
category: best-practices
tags: [legal, dpa, gdpr, multi-agent-review, cross-document-drift, deferred-artifact]
pr: 4348
issue: 4330
related_prs: [4225, 4287, 4289, 4294, 4328]
brand_survival_threshold: single-user incident
---

# DPA template pre-draft pattern + cross-document disclosure-drift defects multi-agent review reliably catches

## Problem

Pre-drafting a customer-facing Data Processing Agreement (DPA) so it is ready before the first B2B procurement ask requires authoring a ~500-line legal instrument that asserts an exact correspondence with a moving target: the public Data Protection Disclosure's processor table (DPD §4.2), the operator-attested counsel-review precedent, the controllership framing under CJEU C-210/16 *Wirtschaftsakademie*, the SCC Module 2/3 attribution per EDPB, and the actual on-disk schema of the running platform (table names, RLS predicates, RPC names, audit triggers, search_path pins).

Plan-time review and verbatim plan execution catch the high-level architectural questions (Direction A vs Direction B controllership framing; whether Anthropic is a Jikigai sub-processor under BYOK). They do NOT catch the integrity defects that ship inside the template body when AI-assisted authoring fills in plausible-looking specifics that don't match ground truth: an invented DPD §2.3 sub-bullet letter that doesn't exist, a storage table that doesn't exist, an Eleventy mirror Last Updated chain that silently drops an earlier PR's disclosure entry, a register-conflation between the non-Soleur deploy-substrate `tenant-dpa-register.md` and the customer-DPA execution log.

These integrity defects look right to a single agent reading the document in isolation. They surface only when multiple agents independently cross-read the template against the live DPD body, the Article 30 register, the migration sources, and the in-tree storage-table names.

## Solution

**Pre-draft pattern (Soleur-as-tenant-zero):** Pre-draft customer-facing contractual artifacts (DPA, side letter, SCC schedules) in `knowledge-base/legal/` with `status: draft-pending-trigger` + `not_yet_executed: true` frontmatter, accompanied by an explicit `compliance-posture.md` Active Items row listing the trigger conditions and the at-publish actions (regenerate Schedules from then-current ground truth, invoke external counsel review, write execution-register row, evaluate SOC 2 engagement). This separates "the contractual instrument exists and procurement counsel can see it" from "the instrument has been executed and counsel-reviewed" — the deferral is explicit, the trigger conditions are verbatim, and the at-publish flow is operationally clear.

**Cross-document drift defects (P1 class) multi-agent review reliably catches in a docs-only PR:**

- **Invented sub-bullet letters.** The DPA template's §3.2 cross-reference table cited DPD §2.3 sub-bullets by letter; one row invented `(q)` for GitHub-sourced priority signals because the author pattern-matched on Article 30 register PA-17 framing rather than the actual DPD §2.3 letter sequence (a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, r, s, t, u — there is no q). Pattern-recognition-specialist caught it by reading both files exhaustively. Fix: replace with actual anchors `(o) + (r)` and an Article 30 PA-17 cross-reference.
- **Non-existent storage tables.** The DPA template invented a `byok_credentials` table for AES-256-GCM encrypted API key storage; the canonical table is `api_keys` (mig 001 + `dsar-export-allowlist.ts`). Pattern-recognition caught it by reading the migrations. Same class as the `subscriptions` table mention (subscription columns are on `public.users`, no standalone table).
- **Eleventy mirror Last Updated chain silently drops entries.** Canonical DPD chain head was `#4287 — cross-referenced Article 30 register Processing Activity 20...`; the mirror chain head was the older `added Section 2.3(u)... PR #4289` because the mirror had not been updated by PR #4287. Prepending the new #4330 entry to BOTH chains in lockstep — without first reconciling the mirror against canonical — silently drops the #4287 PA-20 disclosure from the public Eleventy mirror.
- **Register conflation across two domains.** `knowledge-base/legal/tenant-dpa-register.md` is for the non-Soleur deploy-substrate flow (#3723), with row schema keyed by `Tenant slug | Founder UUID`. The DPA template's at-publish flow proposed funneling customer-DPA execution rows through that same register. Pattern-recognition caught the schema mismatch by reading the register's frontmatter `type: tenant-dpa-register` + `issue: 3723`.
- **Contractually-binding SOC 2 commitment with no engagement plan.** §10.3 promised "obtain SOC 2 Type II within 24 months of first executed Customer DPA" without a `compliance-posture.md` line item, budget envelope, auditor shortlist, or 90-day kickoff task. Security-sentinel caught the contract-formation risk under §12.2(b) gross-negligence carve-out. Recast to reasonable-best-efforts evaluation with a 12-month status-update commitment.
- **Super-cap conflict with Art. 82(4).** §12.3 bounded Jikigai's liability for sub-processor breach to the sub-processor's cap-of-record, which (a) could undercut §12.1's EUR 100 / 12-months-fees floor when a vendor's cap is lower than that floor, and (b) implicitly suggested capping a customer's data-subject-derivative claim against Jikigai. Recast as "recovery-from-sub-processor with excess remit to Customer" with explicit "nothing limits Article 82 joint-and-several liability" clause.
- **Internal repo paths in customer-facing legal prose.** DPD §2.1b(a) embedded `knowledge-base/legal/data-processing-agreement-template.md` — a non-public GitHub source path — in the public-facing controllership clause where procurement counsel reads. User-impact-reviewer flagged it as a single-user-incident-class trust signal: a path that resolves to "not on this domain" at the exact clause that names the relevant contractual instrument. Fix: replace with user-observable trigger language ("where an organization has invited additional Co-Members").
- **Doppler variable names in customer-facing prose.** Same §2.1b(a) edit cited `FLAG_TEAM_WORKSPACE_INVITE` as the gate. A current paying individual Workspace Owner cannot inspect Doppler to determine whether the exception applies to them. Fix: describe the user-observable trigger (Co-Member invite), not the runtime variable name.
- **Engineering paths in customer-facing Last Updated changelog.** The DPD's Last Updated chain prepended a new #4330 entry that included `apps/web-platform/scripts/check-tc-document-sha.sh` in the explanation. Procurement counsel reading the live DPD sees release-engineering plumbing leaked into a legal disclosure — a low-credibility signal. Fix: rewrite to customer-facing prose; track release-engineering rationale in compliance-posture instead.

## Key insight

**For docs-only PRs that publish customer-facing legal artifacts, multi-agent review is NOT optional even when plan-time review was thorough.** Plan-time review at this PR was multi-agent (CLO + CPO + CTO panels per the brand-survival single-user-incident threshold) and identified the load-bearing directional question (Direction A vs B controllership framing) plus the BYOK Anthropic carve-out plus the EDPB-aligned 30/30-day sub-processor notice window. None of those plan-time agents read the DPD §2.3 sub-bullet letters exhaustively or grepped the migrations for storage-table names, because plan-time agents focus on legal-architectural validity, not template-body integrity against the codebase. Post-implementation 6-agent review reliably catches the integrity defects:

- `pattern-recognition-specialist` reads the DPA template against DPD + Article 30 register + migrations and finds invented letters, non-existent tables, register conflation, chain-drop.
- `security-sentinel` reads the contractual mechanics (liability cap, governing law, SOC 2 commitment, audit rights) against the live ToS and compliance-posture state and finds contract-formation risks.
- `user-impact-reviewer` reads the customer-facing surface (DPD §2.1b(a), DPD Last Updated body, public legal prose) against the brand-survival threshold and finds public-facing internal-path leaks and Doppler-variable-name confusion.
- `identity-rbac-reviewer` reads the template's claims about RLS predicates, SECURITY DEFINER helpers, search_path pins, and WORM triggers against the migrations.
- `code-quality-analyst` finds locale-mix, GDPR-Article-vs-Section confusion, migration-number-collision ambiguity.
- `git-history-analyzer` confirms cited PR antecedents, the operator-attested counsel-review precedent, and the absence of prior DPA templates or controllership re-litigation.

**Triggering signal for this defect class:** any PR that ships a customer-facing legal artifact whose body asserts an exact correspondence with the live codebase, the live public legal docs, and the Article 30 register. Specifically: any new file under `knowledge-base/legal/` matching `*dpa*`, `*processing-agreement*`, `*controller*`, `*side-letter*`, `*scc*` — or any edit to `docs/legal/data-protection-disclosure.md` §2.1b/§2.3/§4.2 — must run multi-agent review before merge regardless of plan-time review depth.

## Session Errors

1. **Bash CWD drift on first AC13 invocation.** `cd plugins/soleur/docs && bun run build` failed ("Script not found 'build'") because the script name is `docs:build`; the sibling `cd apps/web-platform && ./node_modules/.bin/vitest ...` then resolved against the stale CWD inside `plugins/soleur/docs` (Bash tool does not persist CWD across calls). **Recovery:** re-ran both commands with absolute paths. **Prevention:** when chaining post-cd commands across Bash invocations, always use absolute paths or include the `cd` in the same `&&`-joined invocation.

2. **Edit failed on first F-2 attempt for Schedule 4 TOM #4.** A `replace_all` for F-1 had changed `search_path = pg_temp` → `public, pg_temp` BEFORE F-2's `Edit` ran, so F-2's `old_string` no longer matched. **Recovery:** re-read the file, found the updated baseline, applied F-2 with the new text. **Prevention:** when `replace_all` mutates text inside a paragraph that a planned later Edit targets, re-read the affected lines BEFORE issuing the next Edit. Add a Sharp Edge to the work skill: "Sequential Edits after `replace_all` must re-anchor."

3. **DPA template invented DPD §2.3 letter `(q)` + non-existent `byok_credentials` table.** Plan Phase 0 step 5 prescribed reading DPD §4.2 verbatim but did NOT extend to enumerating DPD §2.3 sub-bullet letters or grepping migrations for storage-table names. The AI-assisted authoring filled in plausible-looking specifics by pattern-matching against the Article 30 register's PA-17 framing rather than the actual DPD letter sequence. **Recovery:** pattern-recognition-specialist caught both at review time; corrected inline. **Prevention:** plan's Phase 0 precondition checks should include "enumerate every DPD §2.3 sub-bullet letter cited by the new artifact AND grep migrations for every storage-table name cited." Encoded as a Sharp Edge in the plan skill's legal-artifact authoring section.

4. **Eleventy mirror Last Updated chain silently dropped #4287 entry.** When prepending the new #4330 entry to both canonical + mirror Last Updated chains, the mirror was behind canonical by one entry (mirror chain head = #4289; canonical chain head = #4287). The prepend created a new mirror chain reading `#4330 → #4289` and silently lost #4287 PA-20. Pattern-recognition-specialist caught it as P1-C. **Recovery:** restored the missing #4287 segment. **Prevention:** Eleventy mirror Last Updated chain edits must first diff the mirror's chain vs the canonical's chain and reconcile any drift BEFORE prepending the new entry. Encoded as a Sharp Edge in the plan + work skills' legal-doc-consistency section.

5. **Vercel-as-vendor confusion in customer-facing legal prose.** Operator surfaced via mid-flight question. Vercel is NOT used as infrastructure (substrate is Hetzner per ADR-030); only referenced as published-DPA precedent (Vercel publishes its DPA at `vercel.com/legal/dpa` which the template uses as a structural anchor). The mentions are legitimate but the volume (~6 occurrences in a ~500-line template) reads as cargo-cult sourcing to a procurement-counsel reader. **Recovery:** confirmed via repo grep that Vercel is precedent-only / comments-only; flagged to operator for publish-time decision on whether to soften brand attribution. **Prevention:** before referencing a third-party brand in customer-facing legal prose, verify whether they are an active vendor in the codebase (`grep -rn -i "<brand>" apps/ infra/` excluding comments). If precedent-only, frame as "industry best practice (Vercel and Linear publish similar)" rather than direct vendor-name attribution. Add a Sharp Edge to the plan skill: "Customer-facing legal docs naming a third-party brand must include the precedent-vs-vendor classification in the citation."

## Tags

category: best-practices
module: legal-docs
related: multi-agent-review, cross-document-drift, deferred-artifact-pattern
