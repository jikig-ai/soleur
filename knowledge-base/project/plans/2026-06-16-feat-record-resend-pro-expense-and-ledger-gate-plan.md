<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 IaC Routing Gate reviewed. The only "operator-driven" step in this plan is a
Resend *billing-plan upgrade* (free → Pro) performed in Resend's authenticated billing
portal, plus reading the resulting invoice. This is a vendor-portal/billing action behind
operator-only dashboard auth — NOT server/service/cron/DNS/secret provisioning, and the
restricted Resend send-key cannot self-upgrade the plan via API. It is therefore a genuine
human-gated step, not Terraform-routable. The sending-domain DNS (outbound.soleur.ai
DKIM/SPF/MX/DMARC) was already provisioned via Terraform in the merged go-live (#5365).
This plan introduces NO new infrastructure — it edits ops/finance docs, one AGENTS rule,
and the /ship SKILL.md. See ## Infrastructure (IaC) section below.
-->
---
title: "Record missed Resend Pro expense + close the recurring-vendor-cost ledger gap"
date: 2026-06-16
type: feat
status: planned
branch: feat-one-shot-record-resend-pro-expense-and-ledger-gate
lane: cross-domain
brand_survival_threshold: none
---

# feat: Record missed Resend Pro expense + add a recurring-vendor-cost ledger gate

## Overview

Two-part change, both motivated by the same root cause: the **2026-06-15 outbound-email cold-sending go-live (#5325 / PR #5365)** moved agent cold-outreach onto a **dedicated `outbound.soleur.ai` sending subdomain**, kept separate from the `notifications@soleur.ai` transactional stream. Running a second Resend sending domain exceeds the Resend free tier (1 domain), so the account is being upgraded to **Resend Pro (~$20/mo, 50K emails/mo)** — but the upgrade was never recorded in the expense ledger.

- **PART 1 (ops, the symptom):** Flip the existing **Resend** row in `knowledge-base/operations/expenses.md` from `$0.00 / free-tier` to `active` at the Pro price ($20.00/mo), rewrite its Notes (trigger + tier + estimate-with-verify caveat mirroring the Sentry PAYG row), bump `last_updated`, and refresh `cost-model.md` because the shift exceeds the ledger's >10% Downstream-Consumers threshold.
- **PART 2 (workflow, the cause):** Add a `wg-*` Workflow Gate requiring any PR that subscribes to / upgrades / otherwise incurs a new or changed recurring vendor expense to record it in `expenses.md` in the same change before `gh pr ready` (or file a tracked follow-up if the billing action is operator-driven), and **wire the actual check into `/ship` Phase 5.5** so it is enforced, not just documented.

Scope is deliberately tight: a ledger edit + a cost-model refresh + one new gate rule (one-line pointer, body in the correct sidecar) + one ship-skill enforcement step. **No new heavyweight system, no new CI workflow, no new hook.**

## Research Reconciliation — Spec vs. Codebase

The feature description was paraphrased from the operator's recollection of the go-live; three claims drifted from the merged code. All were verified against `origin/main` / the merged PR before writing this plan.

| Claim in feature description | Reality (verified) | Plan response |
|---|---|---|
| Sending domain is `mail.soleur.ai` | The merged go-live (PR #5365) **pivoted to `outbound.soleur.ai`** in a fix commit: `mail.soleur.ai` is delegated to Buttondown (`NS → onbuttondown.com`) and cannot carry Resend DNS. Runtime `OUTBOUND_FROM = "Soleur <hello@outbound.soleur.ai>"` (`apps/web-platform/server/email-triage/outbound.ts:37`); ADR-060 + compliance-posture PA-28 both say `outbound.soleur.ai`. The PR *title* still reads `mail.soleur.ai`. | **Use `outbound.soleur.ai`** in the expenses.md Notes (the runtime fact), not `mail.soleur.ai`. One-line parenthetical may note the title drift. |
| Resend Pro upgrade is a done deal to be recorded | PR #5365 body: **"Operator/infra (gated, not in this PR): Resend Pro + register mail.soleur.ai (restricted send-key can't)."** The Pro upgrade + domain registration are **operator-driven and not yet applied at merge.** | Record the row as the *intended* recurring cost with an explicit **"verify exact amount + billing/renewal date on the next Resend invoice"** caveat (estimate-with-verify, mirroring Sentry PAYG). This is the operator-driven branch of PART 2's own gate — also satisfied by a tracked follow-up if preferred (see §Open Questions). |
| Recording is a fresh row | A **Resend row already exists** in the Recurring table (`email` category, `0.00 / free-tier`). cost-model.md "Tier Triggers" (line 137) already anticipates the exact `+$20.00/mo (paid tier, 50K emails)` flip. | **Edit the existing row in place** — do NOT add a duplicate. Update the cost-model Tier-Triggers + Product-COGS in lockstep. |

## Research Insights

- **Target ledger file:** `knowledge-base/operations/expenses.md` (`last_updated: 2026-06-11`). Resend row at line 27; Sentry PAYG estimate-with-verify pattern at line 21 (`$29 base + ~$11 expected PAYG (estimate: …; verify actual draw on the 2026-06-17 invoice)`) — the caveat shape to mirror.
- **Downstream consumer:** `knowledge-base/finance/cost-model.md` (`review_cadence: monthly`) — line 44 of expenses.md mandates a refresh on every category-subtotal shift >10%. Resend is `email` category; cost-model groups it under **Product COGS**.
- **Subtotal-shift math (both >10%, refresh REQUIRED):**
  - `email` category in expenses.md: Proton $14 + Resend $0 = **$14 → $34** (+143%).
  - Product COGS subtotal in cost-model.md: **121.08 → 141.08** (+16.4%); Totals line and R&D/COGS split must re-derive.
  - cost-model Tier-Triggers table (line 137) already lists the `+$20.00/mo` Resend flip — flip its left column from `$0` to the active Pro value and update the `[expenses.md@DATE]` provenance tag.
- **AGENTS budget — AT CAP (load-bearing constraint):** `B_ALWAYS = wc -c AGENTS.md (5792) + AGENTS.core.md (17202) = 22994 / 23000` → **6 bytes free.** `scripts/lint-agents-rule-budget.py` REJECTS at `>23000`. A new `wg-*` rule requires a 1:1 AGENTS.md index pointer (enforced by `lint_union` in `scripts/lint-rule-ids.py`); a measured `- [id: wg-…] → rest` pointer is **64 bytes** → would push B_ALWAYS to ~23058 → **hard lint FAIL.** This is exactly the #5349-class at-cap scenario. **The plan MUST free ≥64 bytes from `AGENTS.md` or `AGENTS.core.md` in the same commit** (a rest/docs body in a sidecar is NOT counted toward B_ALWAYS, but its pointer IS). See §Phase 3 for the trim.
- **Loader-class fit (where the body lives):** `.claude/hooks/session-rules-loader.sh:88-126`. The new gate fires on PRs that add a vendor SDK/dep (`package.json` → `.ts`/code), a vendor env var (code), or `.tf` infra — i.e. `code`/`infra` change classes → loader loads `core + rest`. **The body belongs in `AGENTS.rest.md`** (Workflow Gates section), pointer `→ rest`. A `docs-only` placement would silently no-op for the gate's own trigger surface (the #3681 silent-drop failure mode). Note: pointer byte cost is identical for `→ core`/`→ rest`/`→ docs-only`, so tier choice does not change the budget math — the trim in Phase 3 is required regardless.
- **Ship enforcement home:** `/ship` Phase 5.5 (`plugins/soleur/skills/ship/SKILL.md` ~line 853, "Undeferred Operator-Step Gate"). That gate is the canonical model: telemetry `emit_incident`, PR-body capture + fenced-code-strip, list-anchored detection, 3-option interactive halt + headless-abort, "Why" provenance. The new "Recurring Vendor Expense Gate" mirrors this structure exactly (a sibling subsection under Phase 5.5).
- **ADR provenance:** ADR-060 (`knowledge-base/engineering/architecture/decisions/ADR-060-outbound-email-sending-domain-and-compliance-chokepoint.md`) records the sending-domain decision; `compliance-posture.md` Resend row (line 74) records the PA-28 outbound scope amendment dated `2026-06-15, #5325`.
- **Ledger owner agent:** `plugins/soleur/agents/operations/ops-advisor.md` (reads/updates `expenses.md`) — not edited here, but the gate's "record in expenses.md" instruction aligns with its template.
- **Detection signal for the gate (kept advisory, not a CI scanner):** new vendor SDK/dependency in `package.json`, new vendor env var, or plan-tier strings (`Pro`, `subscription`, `upgrade`, `paid tier`) in the diff or PR body — phrased as reviewer/ship guidance, not a regex scanner, to honor the tight-scope constraint.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this edits an internal cost ledger, an internal workflow gate, and a ship-skill checklist. A wrong figure misstates internal burn; a broken gate fails to remind a future PR author to record a vendor cost. Neither reaches a Soleur end-user surface.

**If this leaks, the user's data is exposed via:** no user data touched. The expense ledger contains only Soleur's own vendor costs (no PII, no secrets — DKIM keys etc. live in `dns.tf`/Doppler, not here).

**Brand-survival threshold:** none.

> `threshold: none, reason:` this change touches only internal ops docs (`expenses.md`, `cost-model.md`), an AGENTS workflow-gate rule, and the `/ship` SKILL.md checklist — no schema, auth, API route, `.sql`, user-data surface, or sensitive path per the preflight Check 6 canonical regex. (Required scope-out bullet because threshold is `none`; the diff touches no sensitive path, so this is informational, not a sign-off trigger.)

## Implementation Phases

### Phase 1 — Record the Resend Pro expense (PART 1, the symptom)

**Files to edit:** `knowledge-base/operations/expenses.md`

1. **Flip the Resend Recurring row** (line 27). New cell values:
   - `Amount`: `20.00`
   - `Status`: `active`
   - `Renewal Date`: leave `-` (unknown until first Pro invoice; the Notes caveat carries the verify instruction — do NOT fabricate a date).
   - `Notes` (rewrite, mirroring the Sentry PAYG estimate-with-verify shape at line 21):
     > Transactional + cold-outbound email API. Upgraded free-tier → **Pro ($20/mo, 50K emails/mo)**. Trigger: the 2026-06-15 outbound-email cold-sending go-live (#5325, PR #5365) added a **dedicated `outbound.soleur.ai` sending subdomain** for agent cold outreach, isolated from the `notifications@soleur.ai` transactional stream; running a second Resend sending domain exceeds the free tier's 1-domain limit. (PR title says `mail.soleur.ai`; the merged runtime domain is `outbound.soleur.ai` — `mail.soleur.ai` is delegated to Buttondown and can't carry Resend DNS.) Pro upgrade is operator-driven/gated (restricted send-key can't self-upgrade). **Estimate — verify exact amount + billing/renewal date on the next Resend invoice.** See ADR-060, compliance-posture PA-28.
2. **Bump frontmatter** `last_updated: 2026-06-11` → `last_updated: 2026-06-16`.
3. **Self-consistency check:** confirm the Amount column is plain `20.00` (matches sibling-row formatting — no `$`, two decimals) and Status is one of the existing enum tokens (`active`).

**Acceptance Criteria (Phase 1):**
- `grep '| Resend |' knowledge-base/operations/expenses.md` shows `20.00`, `active`, and Notes containing `outbound.soleur.ai`, `Pro`, `50K`, and `verify`.
- `head -3 knowledge-base/operations/expenses.md` shows `last_updated: 2026-06-16`.
- No duplicate Resend row (`grep -c '| Resend | Resend |' …` returns `1`).

### Phase 2 — Refresh the cost-model (PART 1 downstream, >10% rule)

**Files to edit:** `knowledge-base/finance/cost-model.md`

1. **Tier Triggers table (line 137):** flip the Resend left-hand cell from `$0 [expenses.md@2026-04-19] (free tier)` to the active Pro value with a fresh provenance tag `[expenses.md@2026-06-16]`; the "+$20.00/mo (paid tier, 50K emails)" projection becomes the realized cost.
2. **Add a Resend line to the Product COGS table** (after line 53, before the Subtotal row), e.g.:
   `| Resend Pro (outbound + transactional email, $20/mo) | 20.00 [expenses.md@2026-06-16] | expenses.md |`
3. **Re-derive subtotals:** Product COGS `121.08 → 141.08`; update the Subtotal row's provenance tag to `[expenses.md@2026-06-16]`; update the `**Totals:**` block (line 56+) and any R&D/COGS split that references the COGS subtotal.
4. **Bump cost-model frontmatter** `last_updated` (if present) to `2026-06-16` and confirm `review_cadence: monthly` is unchanged.

**Acceptance Criteria (Phase 2):**
- Product COGS subtotal reads `141.08` and every dependent total re-derives correctly (arithmetic check in the PR body).
- No stale `121.08` remains (`grep -c '121.08' knowledge-base/finance/cost-model.md` returns `0`).
- Resend Tier-Triggers row no longer shows `$0` in the current-cost column.

### Phase 3 — Add the Workflow Gate rule (PART 2, the cause)

**Files to edit:** `AGENTS.md` (pointer), `AGENTS.rest.md` (body), plus a **budget-freeing trim** in `AGENTS.md` or `AGENTS.core.md`.

1. **Free ≥64 bytes (REQUIRED — B_ALWAYS is at 22994/23000).** Preferred lever: trim ≥64 bytes of non-load-bearing prose from one verbose **core** rule body in `AGENTS.core.md` (core bodies count toward B_ALWAYS; rest/docs bodies do not). Candidate selection deferred to deepen-plan / work Phase 0 — pick a rule whose trim removes redundant restatement without weakening the directive, and show before/after byte counts. **Do NOT** trim by demoting a `core` rule to `rest` solely for budget — the pointer cost is identical (64 bytes either tier), so a demotion frees nothing and risks loader-class silent-drop. If no clean 64-byte core trim exists, fall back to Phase 3-alt (drop the AGENTS pointer; see §Sharp Edges).
2. **Add the rule body** to `AGENTS.rest.md` under `## Workflow Gates`, one line, ≤600 bytes (per-rule cap), `[id: …]` suffix + `[skill-enforced: ship Phase 5.5 …]` tag. Draft:
   > Any PR that subscribes to, upgrades, or otherwise incurs a new or changed **recurring third-party vendor expense** (new vendor SDK/dependency, new vendor env var, or plan-tier strings like `Pro`/`subscription`/`upgrade`/`paid tier` in the diff or PR body) MUST record it in `knowledge-base/operations/expenses.md` in the same change before `gh pr ready` — or, if the billing action is operator-driven, file a tracked `type/chore` follow-up carrying the `deferred-automation` sentinel [id: wg-record-recurring-vendor-expense-before-ready] [skill-enforced: ship Phase 5.5 Recurring-Vendor-Expense Gate]. **Why:** #5325 added a second Resend sending domain (→ Resend Pro $20/mo) with no ledger entry before merge.
3. **Add the matching pointer** to `AGENTS.md` under `## Workflow Gates`:
   `- [id: wg-record-recurring-vendor-expense-before-ready] → rest`
4. **Verify lints pass:**
   - `python3 scripts/lint-rule-ids.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` (pointer↔body 1:1, id unique, not retired).
   - `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` (B_ALWAYS ≤ 23000, body ≤ 600 bytes).
   - `python3 scripts/lint-agents-enforcement-tags.py …` if present (the `[skill-enforced: …]` tag must resolve).
5. **Loader-class-fit assertion (cite in PR body):** the gate's trigger surface is code/infra (vendor dep/env/`.tf`), which loads `core + rest`; the rule is in `AGENTS.rest.md` → loads on its own trigger. Confirmed against `session-rules-loader.sh:88-126`.

**Acceptance Criteria (Phase 3):**
- `lint-agents-rule-budget.py` exits 0; report the post-edit `B_ALWAYS` value in the PR body (must be ≤ 23000).
- `lint-rule-ids.py` exits 0 (exactly one pointer + one body for the new id).
- New rule body ≤ 600 bytes (`awk` length check on the rule line).
- Trim diff shows the freed bytes ≥ the added pointer bytes (net B_ALWAYS non-increasing or within cap).

### Phase 4 — Wire enforcement into `/ship` Phase 5.5 (PART 2, the teeth)

**Files to edit:** `plugins/soleur/skills/ship/SKILL.md`

Add a new subsection **"Recurring-Vendor-Expense Gate (mandatory)"** under Phase 5.5, immediately after the "Undeferred Operator-Step Gate", mirroring that gate's structure:

1. **Telemetry:** `emit_incident wg-record-recurring-vendor-expense-before-ready applied "<short desc>"` (same `incidents.sh` source line).
2. **Detection (advisory signal, scoped tight — NOT a new scanner):** compute the PR diff + read the PR body; flag when the change introduces a vendor-cost signal:
   - new dependency added to a `package.json` whose name matches a known-vendor list OR any new dep at all (advisory — agent judges whether it is a *paid* vendor);
   - a new vendor env var (`grep` added `*_API_KEY`/`*_TOKEN`/`*_SECRET` lines in `.env.example` / Doppler-write steps);
   - plan-tier strings in the diff or PR body (`grep -iE 'pro\b|subscription|upgrade|paid tier|/mo'`), list/prose-anchored to avoid noise.
3. **Rule:** if a signal fires, require EITHER (a) a same-PR edit to `knowledge-base/operations/expenses.md` (`git diff --name-only origin/main...HEAD | grep -q 'operations/expenses.md'`), OR (b) a `Tracks/Refs #NNNN` companion pointing at an OPEN `type/chore` issue carrying `deferred-automation` (operator-driven billing branch — reuse the exact issue-verification loop already written for the Undeferred Operator-Step Gate).
4. **Interactive halt (3 options):** (i) record the expense in expenses.md now, (ii) file/cite a tracked operator-driven follow-up, (iii) operator-attestation override (`<!-- gate-override: wg-record-recurring-vendor-expense-before-ready -->`) for false positives (e.g., a free-tier SDK with no cost).
5. **Headless mode:** abort with the structured error (no auto-file/auto-override), same as the sibling gate.
6. **"Why" provenance:** cite #5325 / this PR.
7. **Phase 5 checklist line:** add `- [ ] Recurring-vendor-expense gate passed (Phase 5.5 gate)` to the Phase 5 Final Checklist (~line 273, next to the other gate checkboxes).

**Acceptance Criteria (Phase 4):**
- The new subsection exists under Phase 5.5 with all 6 structural elements (telemetry, detection, rule, 3-option halt, headless-abort, Why).
- The detection bash uses the same fenced-code-strip + list-anchored conventions as the sibling gate (no self-trip when a PR edits this skill).
- The skill description word-budget is unaffected (this edits the body, not `description:`); run `bun test plugins/soleur/test/components.test.ts` to confirm green.
- Phase 5 Final Checklist includes the new gate checkbox.

## Acceptance Criteria (rollup)

### Pre-merge (PR)
- [ ] expenses.md Resend row = `20.00 / active`, Notes cite `outbound.soleur.ai` + `Pro` + `50K` + invoice-verify caveat; `last_updated: 2026-06-16`.
- [ ] cost-model.md Product COGS = `141.08`, no stale `121.08`, Tier-Triggers Resend current-cost flipped, totals re-derived, provenance tags `@2026-06-16`.
- [ ] New `wg-record-recurring-vendor-expense-before-ready` rule: pointer in AGENTS.md `→ rest`, body in AGENTS.rest.md ≤ 600 bytes, `[skill-enforced: …]` tag present.
- [ ] `lint-rule-ids.py` AND `lint-agents-rule-budget.py` exit 0; post-edit `B_ALWAYS ≤ 23000` reported in PR body.
- [ ] Budget-freeing trim landed in AGENTS.md/AGENTS.core.md (before/after bytes shown).
- [ ] `/ship` Phase 5.5 has the new Recurring-Vendor-Expense Gate subsection + Phase 5 checklist line.
- [ ] `bun test plugins/soleur/test/components.test.ts` green (skill description budget + structure).
- [ ] PR body uses `Ref #5325` (not `Closes`) — #5325 is the umbrella go-live, not closed by this ledger fix.

### Post-merge (operator)
- [ ] **Verify the actual Resend Pro charge + billing/renewal date on the next Resend invoice**, then update the expenses.md Amount/Renewal-Date/caveat to the recorded-actual. **Automation: not feasible because** the Resend invoice/billing portal is behind operator-only authenticated dashboard access (no read API exposed by the restricted send-key); this is a genuine human-judgment/portal step. Track via a `type/chore` `deferred-automation` issue if the Pro upgrade has not yet been applied at merge time (see §Open Questions).

## Domain Review

**Domains relevant:** Operations, Finance

### Operations
**Status:** reviewed (inline — ops-advisor owns `expenses.md`; this is the canonical ledger-edit path)
**Assessment:** Edit-in-place of the existing Resend row matches the ops-advisor template; estimate-with-verify caveat is the established pattern (Sentry PAYG, Proton TBD). No new vendor account, no provisioning. The gate addition formalizes a recurring-cost-capture discipline the ledger already implies.

### Finance
**Status:** reviewed (inline — cost-model.md is the declared downstream consumer)
**Assessment:** The >10% subtotal-shift rule fires (email +143%, Product COGS +16.4%); refresh is mandatory, not optional. cost-model already pre-staged the `+$20/mo` trigger, so the refresh is a flip + re-sum, low risk. CFO/budget-analyst review not separately spawned — change is a mechanical realized-cost flip the cost-model itself prescribes.

### Product/UX Gate
Not applicable — no `## Files to Create`/`## Files to Edit` path matches any UI-surface term/glob (`components/**`, `app/**/page.tsx`, etc.). No user-facing surface. Tier: NONE.

## Observability

Skip — pure-docs + skill + AGENTS-rule change. No Files-to-Edit under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`; no new infra surface. The `/ship` gate's own observability is the `emit_incident` telemetry line (mirrors the sibling gate), recorded by the weekly rule-application aggregator.

## Infrastructure (IaC)

Skip — no new server, service, cron, vendor account, DNS record, TLS cert, secret, or firewall rule introduced by this change. The Resend Pro upgrade itself is an operator-driven billing-plan action in Resend's authenticated billing portal on an existing vendor account (the sending-domain DNS was already provisioned via Terraform in the merged #5365); recording the cost in the ledger is a docs edit, not provisioning. The restricted Resend send-key cannot self-upgrade the plan via API, so no IaC path exists for the billing action. (Phase 2.8 reviewed — see top-of-file ack comment.)

## Open Code-Review Overlap

None — no open `code-review`-labeled issue touches `expenses.md`, `cost-model.md`, `AGENTS*.md`, or `ship/SKILL.md` Phase 5.5 (verified at plan time; re-confirm at work Phase 0 with the `gh issue list --label code-review` two-stage jq query if any doubt).

## Open Questions

1. **Has the Resend Pro upgrade already been applied?** If yes (operator confirms), record the recorded-actual amount/date directly and drop the post-merge operator AC. If no (the #5365 body implies not — "gated, not in this PR"), keep the estimate + file the `type/chore` `deferred-automation` follow-up so the new gate's own operator-driven branch is satisfied. **This PR is itself the first test of the new gate** — it incurs a recurring vendor cost (Resend Pro) whose billing is operator-driven, so it must either record the expense (PART 1 does) AND/OR carry the tracked follow-up.

## Sharp Edges

- **AGENTS budget is at cap (22994/23000).** A new `wg-*` pointer is 64 bytes → would FAIL `lint-agents-rule-budget.py`. The Phase 3 trim is **load-bearing, not optional** — do not add the rule without freeing ≥64 bytes from AGENTS.md/AGENTS.core.md in the same commit. **Phase 3-alt fallback:** if no clean core-body trim exists, drop the AGENTS pointer entirely and place the gate's normative force in `/ship` Phase 5.5 + a one-line note in the constitution (the #5349 fallback). This deviates from the literal "add a `wg-` rule" ask — surface to the operator before choosing it; prefer the trim.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with the required sensitive-path scope-out bullet.
- **Use `outbound.soleur.ai`, never `mail.soleur.ai`** in the ledger Notes — the latter is the stale PR-title value and is delegated to Buttondown. Grep the final expenses.md edit for `mail.soleur.ai` to confirm it does not leak in as the sending domain (the only acceptable mention is the parenthetical noting the title drift).
- **`Ref #5325`, not `Closes #5325`** — #5325 is the umbrella outbound-email feature; this ledger/gate fix closes one bookkeeping gap, not the feature. Auto-close keywords fire anywhere in the body (`wg-use-closes-n-in-pr-body-not-title-to`).
- **Edit the existing Resend row in place** — do not append a second Resend row; cost-model and the ledger both key on the single `email`-category Resend entry.
- **The detection step in Phase 4 must strip fenced code blocks before grepping** the PR body for plan-tier strings, or a PR that edits this skill (quoting `Pro`/`upgrade` in the gate body) will self-trip. Reuse the sibling gate's `awk` fence-stripper verbatim.
