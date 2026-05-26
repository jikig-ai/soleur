---
date: 2026-05-15
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related-issues: ["#3785", "#3786"]
related-brainstorm: knowledge-base/project/brainstorms/2026-05-15-claude-for-legal-evaluation-brainstorm.md
related-spec: knowledge-base/project/specs/feat-cc-legal-skill-bridge/spec.md
type: feature
classification: docs+agent-extension
---

# CLO founder-threshold detection + vendor-neutral recommended-tools docs

> **Branch-name note:** worktree `feat-cc-legal-skill-bridge` was named when the brainstorm framed this as "bridge to claude-for-legal." The triad (CPO + CMO + CLO + CTO) under USER_BRAND_CRITICAL=true converged on **no integration**. This plan implements the smaller adjacent yes — extend `clo` agent + `legal-audit` skill + add `knowledge-base/legal/recommended-tools.md` + add `/soleur:go` keyword routing — and references claude-for-legal alongside vendor-neutral alternatives on the docs page only.

## Overview

When a Soleur founder hits a legal need that exceeds founder-grade compliance helping (vendor MSA review, DSAR, AI vendor terms, OSS license, breach notice), Soleur's existing legal stack does not recognize the threshold or recommend a downstream specialist. This plan adds threshold detection at three entry surfaces (`clo` Assess phase, `legal-audit` skill, `/soleur:go` keyword classifier) + a vendor-neutral `recommended-tools.md` docs page that lists `anthropics/claude-for-legal` alongside founder-accessible counsel marketplaces and (where applicable) classification SaaS.

Captures ~90% of the value of a direct `claude-for-legal` integration at ~5% of the maintenance cost. Honors the PIVOT verdict ("validate demand first"). Avoids vendor lock-in. Zero upstream coupling. Zero ToS amendment. Zero new sub-processor disclosure.

## User-Brand Impact

Carried forward from brainstorm Phase 0.1:

**If this lands broken, the user experiences:** A founder who needs immediate DSAR-response or breach-notice guidance gets the existing Soleur-native triage output but no escalation pointer; they don't know they've crossed the founder→lawyer threshold; they self-assemble a response that misses statutory deadlines or fails the substantive bar.

**If this leaks, the user's data is exposed via:** Not applicable under the chosen path — no founder data flows through claude-for-legal or any downstream tool. The bridge mechanic that would have created data-flow exposure was rejected at brainstorm time.

**Brand-survival threshold:** `single-user incident`. One founder fined or sued because Soleur output was treated as legal advice — or because Soleur's escalation pointer failed to fire when the threshold was crossed — is brand-fatal.

`requires_cpo_signoff: true` set in frontmatter. `user-impact-reviewer` agent fires at PR review per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Domain Review

**Domains relevant:** Product, Marketing, Legal, Engineering (carry-forward from brainstorm `## Domain Assessments`).

- **CPO** (carry-forward): Honors PIVOT verdict. Cannibalization risk drops to zero — `clo` becomes the gateway to *any* legal-tooling recommendation, not just one privileged upstream. The recommended-tools.md page is the demand-validation surface.
- **CMO** (carry-forward): On-brand. Single-sentence framing — "Soleur recognizes when your need crosses the founder-to-lawyer threshold and hands off — output is for attorney review, not client delivery" — is literally true under the chosen path. Marketing surface: docs only.
- **CLO** (carry-forward): No new UPL/malpractice surface. Existing disclaimer pattern (`legal-document-generator.md:22`) sufficient. Apache-2.0 license irrelevant (no upstream code imported). ToS amendment NOT required. Anthropic sub-processor row NOT required.
- **CTO** (carry-forward): Lowest-risk implementation. Capability gaps NOT triggered. AGENTS.md `hr-new-skills-agents-or-user-facing` does NOT fire (extending existing components + adding kb doc + classifier-row patch, no new skill or agent file). `hr-gdpr-gate-on-regulated-data-surfaces` fires via brand-survival trigger (b) — see Phase 5 below.

**Product/UX Gate:** NONE. No user-facing UI surface created.

**Brainstorm-recommended specialists:** None recommended by name.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned zero matches against any of the planned files.

## Research Insights

(Consolidated from brainstorm research; no re-spawn.)

**Existing legal stack:**
- `plugins/soleur/agents/legal/clo.md` — domain leader; 3-phase contract (Assess / Recommend & Delegate / Sharp Edges); body 549 words.
- `plugins/soleur/skills/legal-audit/SKILL.md` — **4 phases: 0 Discovery, 1 Context, 2 Audit, 3 Report**. The `<critical_sequence>` block at `SKILL.md:65-69` hard-requires inline-conversation findings; **NEVER persists to files**. Empty-discovery short-circuit lives at `SKILL.md:27` (inside Phase 0).
- `plugins/soleur/agents/legal/legal-document-generator.md:22` — canonical DRAFT disclaimer (mandatory at top AND bottom).
- `plugins/soleur/skills/gdpr-gate/SKILL.md:10` — canonical advisory disclaimer asserted by `gdpr-gate.test.ts`.
- `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` — lefthook pre-commit hook, signature `{staged_files}` (NOT `--target`); always exits 0 (advisory). Blocking enforcement is in `/soleur:ship Phase 5.5`.
- `plugins/soleur/skills/gdpr-gate/NOTICE` — gosprinto/compliance-skills lift; **scope is PII-detector code-scanning** (`pii-detector/patterns/`, `pii-detector/rules/`, `pii-detector/layers/`), NOT legal-tooling. **Does NOT have DSAR/breach/vendor-AI/commercial-contract sections.** Tool B claims for these thresholds must use other vendors (verified pre-/work).
- `plugins/soleur/commands/go.md` — `/soleur:go` skill with "Step 2: Classify and Route" intent table (current intents: fix, drain, review, incident, default). New legal-threshold intent slot in.

**Plugin-wide rules (`plugins/soleur/AGENTS.md`):**
- Versioning: `## Changelog` + `semver:patch` (this PR adds no new component).
- No edits to `plugin.json` (`0.0.0-dev` frozen) or `marketplace.json`.
- Pre-commit checklist: README.md component counts verified (line 23) — applies if recommended-tools.md changes the legal-doc count.

**Prior decisions to cite:**
- `2026-03-10-claude-marketplace-evaluation-brainstorm.md` — no-go on Anthropic distribution surface (PIVOT validation takes priority).
- `2026-05-15-claude-for-legal-evaluation-brainstorm.md` — this plan's parent.
- `2026-05-15-evaluating-anthropic-first-party-plugin-marketplaces.md` (learning).

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/legal/recommended-tools.md` | Vendor-neutral specialist-tools docs page. 5 H2 sections (one per threshold). Each section: trigger description + statutory deadline if applicable + tool table (≥2 rows). |

## Files to Edit

| Path | Change |
|---|---|
| `plugins/soleur/agents/legal/clo.md` | Assess phase: append "Common founder thresholds" subsection (5-row table). Sharp Edges: append brainstorm-verdict pointer + atomic-rename grep reminder. |
| `plugins/soleur/skills/legal-audit/SKILL.md` | **Phase 0** Discovery short-circuit message (`SKILL.md:27`): extend with threshold-catalog pointer. **Phase 3** Report: append "When to escalate (inline-conversation only)" block with statutory-deadline interpolation + zero-findings + threshold-in-flight catch. |
| `plugins/soleur/commands/go.md` | "Step 2: Classify and Route" intent table: add `legal-threshold` intent row with trigger signals (MSA, DSAR, breach, AI vendor terms, OSS license keywords) routing to `clo` agent. |
| `knowledge-base/project/specs/feat-cc-legal-skill-bridge/spec.md` | TR4 already corrected from "No GDPR-gate trigger" to "GDPR-gate fires via brand-survival trigger." |

## Implementation Phases

### Phase 0: Preconditions

```bash
# AGENTS.md hr-always-read-a-file-before-editing-it
ls plugins/soleur/agents/legal/clo.md \
   plugins/soleur/skills/legal-audit/SKILL.md \
   plugins/soleur/commands/go.md

# Verify gdpr-gate.sh signature (NOT --target; expects {staged_files} from lefthook)
head -20 plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh

# Verify no new file path collisions
ls knowledge-base/legal/recommended-tools.md 2>/dev/null && echo "FAIL: file exists" || echo "OK"

# Confirm legal-audit phase numbering (phases 0/1/2/3)
grep -nE "^## Phase [0-9]+" plugins/soleur/skills/legal-audit/SKILL.md

# Snapshot critical_sequence block for byte-equality AC check
sed -n '65,69p' plugins/soleur/skills/legal-audit/SKILL.md > /tmp/critical-sequence-baseline.txt
```

### Phase 1: Frozen threshold catalog (one table; no /work-time AskUserQuestion)

The 5 leader-endorsed thresholds, their triggers, statutory deadlines, recommended-tools.md anchor, and per-threshold tool list. PR-review captures CPO sign-off on the as-shipped catalog (single yes/no, no mid-/work interruption).

| Threshold | Trigger | Statutory deadline | Anchor | Tool A | Tool B | Tool C |
|---|---|---|---|---|---|---|
| `vendor-msa-review` | Founder receives MSA from vendor; needs red-flag scan before signing | None | `#vendor-msa-review` | `claude-for-legal:commercial-legal:review` | Founder-accessible counsel marketplace (LawTrades, Priori, Lawpath) | ContractGen / LegalSifter / ContractWorks (commercial-contract review SaaS) |
| `dsar-request` | Founder receives Data Subject Access Request from EU/CA user | GDPR Art. 12: 30 days; CCPA: 45 days | `#dsar-request` | `claude-for-legal:privacy-legal:dsar-response` | Privacy counsel marketplace (LawTrades privacy lane, Priori privacy filter, IAPP member directory) | OneTrust / Securiti / Osano DSAR module |
| `ai-vendor-terms` | Founder evaluating vendor AI ToS (training-on-data, IP, liability, model-change) | None | `#ai-vendor-terms` | `claude-for-legal:ai-governance-legal:vendor-ai-review` | Soleur's existing `legal-audit benchmark` mode + counsel marketplace | — (third option not warranted; ≥2 satisfied) |
| `oss-license-classification` | Founder including OSS dep with non-permissive license (GPL/AGPL/SSPL/custom) | None | `#oss-license-classification` | `claude-for-legal:ip-legal:oss-review` | FOSSA / Snyk / GitHub Dependency Review (license-detection engines — these ARE legal-classification tools when used for SPDX categorization) | IP counsel marketplace (LawTrades IP lane, Priori IP filter) |
| `breach-notice-triage` | Founder discovers PII exposure / unauthorized access | GDPR Art. 33: 72 hours from awareness; state laws vary | `#breach-notice-triage` | `claude-for-legal:privacy-legal:reg-gap-analysis` (Art. 33/34) | Privacy/security counsel marketplace | OneTrust / Securiti incident-response module |

**Vendor-neutrality enforcement:** every row has Tool B ≠ claude-for-legal AND Tool B ≠ "retained counsel" prose alone (each names actual marketplaces or actual SaaS). gosprinto/compliance-skills was considered and rejected as Tool B for any threshold — it is a PII-detector code-scanner (`pii-detector/patterns|rules|layers`), NOT a legal-domain tool.

**Catalog drift discipline:** if the operator adds/removes thresholds at PR-review, `clo.md` (table rows) + `recommended-tools.md` (H2 sections) + `commands/go.md` (classifier triggers) update atomically in one commit. Per-file Sharp Edge in clo.md serves as the literacy reminder.

### Phase 2: Write `knowledge-base/legal/recommended-tools.md`

**Path-choice rationale:** Brainstorm CMO suggested `integrations/`; this plan uses `knowledge-base/legal/` because (a) it's the canonical home for legal-domain prose (`compliance-posture.md`, `data-protection-disclosure.md` live there), (b) `clo` Assess already inventories that directory, (c) `integrations/` would imply a Soleur product surface (MCP / plugin install), which the brainstorm explicitly rejected.

Structure:

- **Top-of-file disclaimer** (adapt canonical DRAFT pattern): "Recommendations on this page are starting points for evaluating downstream specialists. They are not endorsements, partnerships, or legal advice. Verify suitability with retained counsel before relying on any tool's output. Soleur is a developer tool, not a law firm."
- **5 H2 sections** (anchors from Phase 1 table). For each:
  - 1-paragraph trigger description.
  - Statutory deadline callout for DSAR + breach.
  - Tool table from Phase 1 (`Tool | License | How to get it | Best for | Canonical URL`).
  - "If you have no retained counsel" sub-paragraph for DSAR / breach / MSA — names the founder-accessible marketplace explicitly.
- **Footer:** links to brainstorm and to deferred issue #3786.

### Phase 3: Edit `plugins/soleur/agents/legal/clo.md`

One insertion + one Sharp Edges entry (down from two subsections — code-simp #6 cut). The Recommend & Delegate routing rule is implicit once Assess emits the catalog.

1. **Assess phase:** Append subsection at end of "### 1. Assess" titled "**Common founder thresholds**". Body: one paragraph + the 5-row table from Phase 1 (columns: `Threshold | Trigger | Statutory deadline | See`; "See" = `recommended-tools.md#<anchor>`). Surfaces on every `clo` invocation (passive routing, brainstorm Phase 0.5, plan Phase 2.5, direct Task call).
2. **Sharp Edges:** Append entry at end of "### 3. Sharp Edges" titled "**Re-investigating downstream legal-tool integration**": "Before proposing a `claude-for-legal` lift/delegate/bridge, read `knowledge-base/project/brainstorms/2026-05-15-claude-for-legal-evaluation-brainstorm.md` — the triad (CPO+CMO+CLO+CTO) under USER_BRAND_CRITICAL=true converged on no-integration. Re-evaluation criteria are in #3786 (ALL must hold). If you rename `recommended-tools.md` or any H2 anchor, grep `clo.md` and `legal-audit/SKILL.md` for inbound references and update them in the same commit."

Verify post-edit: `wc -w plugins/soleur/agents/legal/clo.md` ≤ 850.

### Phase 4: Edit `plugins/soleur/skills/legal-audit/SKILL.md`

**Phase 0 Discovery short-circuit** (line `SKILL.md:27` — confirmed phase number is 0, not 1; correctness panel P0). Replace:

```
If no legal documents are found, report: "No legal documents found in this project. Use `/legal-generate` to create them."
```

with:

```
If no legal documents are found, report: "No legal documents found in this project. Use `/legal-generate` to create them.

> **Or:** If you're handling an inbound MSA, DSAR, AI-vendor terms review, OSS-license question, or breach notice, see `knowledge-base/legal/recommended-tools.md` for downstream specialist tools."
```

**Phase 3 Report** — append at the END (after the existing `<critical_sequence>` block at `SKILL.md:65-69`, before `## Important Guidelines`):

```
**When to escalate (inline-conversation only)**

After displaying findings, scan each finding's category against the threshold catalog at `knowledge-base/legal/recommended-tools.md`.

For each finding that matches a threshold, append a one-line escalation pointer:

> **When to escalate:** <threshold name>. See `knowledge-base/legal/recommended-tools.md#<anchor>`.

For statutory-deadline thresholds (DSAR, breach), interpolate the deadline into the heading and use a dedicated `### Escalation required` H3 above the findings list (NOT a trailing blockquote — deadline-sensitive). Format:

---

### Escalation required — 72h deadline (GDPR Art. 33 — breach-notice-triage)

See `knowledge-base/legal/recommended-tools.md#breach-notice-triage`.

---

**Zero-findings + threshold-in-flight catch:** if the audit produces zero findings AND the project contains regulated-data surfaces (privacy policy, ToS mentioning data processing, breach-response doc, anything matching `**/{privacy,terms,gdpr,dpa,disclaimer}*`), ALWAYS append the full threshold catalog pointer at the bottom of the report. A clean audit does not mean no threshold is in flight — a founder mid-DSAR may have a clean privacy policy.

**Inline only.** NEVER write the escalation pointer or catalog to a file — Phase 3 `<critical_sequence>` applies.
```

### Phase 5: Edit `plugins/soleur/commands/go.md`

Add a `legal-threshold` intent row to the "Step 2: Classify and Route" table:

| Intent | Trigger Signals | Routes To |
|---|---|---|
| legal-threshold | The user input mentions an inbound vendor MSA, DSAR (data subject access request), AI vendor terms / vendor AI review, OSS license question (GPL/AGPL/SSPL/copyleft), breach / data exposure / unauthorized access | `clo` agent (Task spawn; Assess phase emits the threshold catalog) |

Place above the `default` row so legal-threshold matches before the catch-all. The `clo` invocation reuses the existing Task pattern (no new infrastructure).

### Phase 6: GDPR / Compliance Gate

Per `hr-gdpr-gate-on-regulated-data-surfaces` trigger (b) — brand-survival threshold = single-user incident — invoke gate at plan-time. **Correction from earlier draft:** `gdpr-gate.sh` is a lefthook pre-commit script with signature `{staged_files}`, NOT `--target`, and always exits 0 (advisory). The plan-time invocation goes through the **skill**, not the script:

```
Skill: soleur:gdpr-gate
args: target=knowledge-base/project/plans/2026-05-15-feat-clo-founder-threshold-detection-plan.md
```

Expected: PASS / no Critical findings (no schema, no migration, no auth flow, no API route — none of the 5 mandatory checks (Art. 6 / 5(1)(e) / 17 / Chapter V / 9) apply to a docs+agent-extension PR). Critical findings (if any) follow the gate procedure: operator-acknowledged write to `compliance-posture.md` Active Items + `compliance/critical`-labeled issue. Blocking enforcement at ship-time is `/soleur:ship Phase 5.5`.

### Phase 7: Test surface

- **Existing:** `plugins/soleur/test/components.test.ts` and `plugins/soleur/test/gdpr-gate.test.ts` MUST still pass (no skill-description changes; no gdpr-gate disclaimer regression).
- **New:** Add a 10-line vendor-neutrality grep test to `plugins/soleur/test/components.test.ts` (or sibling `legal-recommended-tools.test.ts` if components feels wrong). Asserts:
  - `recommended-tools.md` exists.
  - Has exactly 5 H2 sections.
  - Each H2 is followed by a markdown table with ≥ 2 data rows.
  - No row has `claude-for-legal` as the only non-empty Tool column.
  - Anchors in `clo.md` and `legal-audit/SKILL.md` referencing `recommended-tools.md#<anchor>` resolve to actual H2 anchors.
- This single test replaces the cut Phase 7 anchor-resolution lefthook + the per-threshold vendor-neutrality manual review (one mechanism, not multiple — code-simp #4 + Kieran P1-2).

### Phase 8: Documentation + close-out

- **Update `knowledge-base/legal/compliance-posture.md`** Active Items only IF `clo` Assess already inventories that file (read first; don't dupe).
- **Verify README.md legal-doc count** — per `plugins/soleur/AGENTS.md` line 23. Run docs build locally (`bun run build:docs` if available) to confirm.
- **Comment on #3786 (NO criteria mutation)** — one-line: "The brainstorm criteria as recorded ('docs page click-through > N founders/month') are unobservable because `recommended-tools.md` has no instrumentation. Future re-openers should propose new observable criteria at the time real founder demand emerges; do not pre-litigate." This DOES NOT mutate the issue body — it's a comment for context. (Earlier draft tried to rewrite the criteria inline; that was an out-of-scope spec mutation per arch-strategist + DHH + Kieran.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `Closes #3785` in PR body. `Refs #3786` (comment posted per Phase 8).
- [ ] `## Changelog` section in PR body with `semver:patch` rationale.
- [ ] `knowledge-base/legal/recommended-tools.md` exists with: top-of-file DRAFT-style disclaimer; exactly 5 H2 sections (frozen catalog from Phase 1); each table ≥ 2 rows; no row has claude-for-legal as the sole non-empty Tool; statutory-deadline callouts for DSAR + breach; footer links to brainstorm + #3786.
- [ ] `plugins/soleur/agents/legal/clo.md`: Assess phase has "Common founder thresholds" subsection with 5-row table; Sharp Edges has brainstorm-verdict + atomic-rename pointer; `wc -w` ≤ 850.
- [ ] `plugins/soleur/skills/legal-audit/SKILL.md`: Phase 0 short-circuit message extended with catalog pointer; Phase 3 has "When to escalate" block with statutory-deadline H3 + zero-findings catch; `<critical_sequence>` byte-equal to baseline (`diff <(sed -n '65,69p' plugins/soleur/skills/legal-audit/SKILL.md) /tmp/critical-sequence-baseline.txt` returns empty).
- [ ] `plugins/soleur/commands/go.md`: `legal-threshold` intent row added to Classify table above `default`.
- [ ] Phase 7 vendor-neutrality test passes (`bun test plugins/soleur/test/components.test.ts`).
- [ ] Phase 7 test asserts anchor resolution (`recommended-tools.md#<anchor>` references in `clo.md` and `legal-audit/SKILL.md` resolve).
- [ ] `bun test plugins/soleur/test/gdpr-gate.test.ts` passes (disclaimer invariant intact).
- [ ] `Skill: soleur:gdpr-gate` invoked at plan-time (Phase 6); no Critical findings recorded — OR recorded with `compliance/critical`-labeled issue + `compliance-posture.md` row.
- [ ] Spec.md TR4 already updated (in same PR, separate commit acceptable).
- [ ] Comment on #3786 posted (NOT inline criteria mutation).
- [ ] `user-impact-reviewer` agent ran at PR review.
- [ ] CPO sign-off captured (single yes/no on the as-shipped 5-threshold catalog).
- [ ] `git diff main -- 'AGENTS*.md' | wc -l` = 0.
- [ ] README.md component counts verified (per `plugins/soleur/AGENTS.md` line 23).

### Post-merge (operator)

None. This is a docs+agent-extension+classifier-row PR. No migrations, no infra applies, no Doppler updates.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Threshold catalog designed for an imagined founder.** Single PR-review gate could rubber-stamp wrong-shape thresholds. | Medium | High | CPO sign-off explicitly evaluates the 5-row catalog; #3786 captures "thresholds-don't-match-reality" demand signal; thresholds match leader analysis converged at brainstorm time. |
| **Vendor-neutrality wash.** Page-level ≥ 2 tools count passes vacuously if claude-for-legal is sole listing for any section. | Medium | High | Phase 7 test asserts per-row "no claude-for-legal as sole non-empty Tool" — automated, not manual. Phase 1 table names real Tool B options (counsel marketplaces; OneTrust/Securiti/Osano; FOSSA/Snyk for OSS). gosprinto explicitly rejected for legal sections (verified: PII-detector scope, not legal-tooling). |
| **`legal-audit` "When to escalate" block leaks escalation prose to file.** Subtle agent-prompt slip violates `<critical_sequence>`. | Low | Critical | Phase 4 prompt template explicitly reiterates inline-only; AC includes byte-equality git-diff for `SKILL.md:65-69`. |
| **Empty-discovery dropped-founder cohort** (founder runs `/soleur:legal-audit` with no docs at all) AND **zero-findings-with-clean-docs cohort** (founder mid-DSAR with adequate privacy policy). | Was high; mitigated | Critical | Phase 4: Phase 0 short-circuit emits catalog pointer; Phase 3 "zero-findings + regulated-data-surfaces present → emit catalog anyway" rule. |
| **`/soleur:go` keyword-routing classifier mis-fires** — false positives (founder mentions "MSA" in unrelated context) or false negatives (founder uses synonym not in trigger list). | Medium | Medium | Phase 5 trigger list is broad enough for modal cases (MSA, DSAR, breach, AI vendor, OSS license + variants). False positives route to `clo` Assess which gracefully degrades (catalog appears but other Assess output is contextually relevant). False negatives covered by direct `legal-audit` invocation + passive routing on `legal` keyword (existing). |

## Sharp Edges

- **Vendor-neutrality is automation-enforced (Phase 7 test), not manual.** A future PR that drops a tool row, makes claude-for-legal the sole Tool, or removes a section will fail CI. Don't rely on PR-review for vendor-neutrality drift.
- **`legal-audit` Phase 3 `<critical_sequence>` is load-bearing.** "Never persist to files" is hard-required for open-source repos. Future edits that soften this are brand-survival regressions. AC byte-equality check enforces.
- **`legal-audit` Phase 0 short-circuit is the highest-need-cohort surface.** Founders with no docs at all are the modal real-world cohort hitting the catalog (inbound MSA/DSAR/breach are events, not audit triggers). Future edits that revert the short-circuit pointer drop that cohort silently.
- **gosprinto/compliance-skills is NOT a legal-tooling alternative.** It's a PII-detector code-scanner. Future plan-time grep for "Tool B alternatives" must verify scope before naming it. (Trap caught at this plan's revision pass.)
- **If you rename `recommended-tools.md` or any H2 anchor**, grep `clo.md`, `legal-audit/SKILL.md`, and `commands/go.md` for inbound references and update atomically. The Phase 7 test will fail commit if anchors don't resolve, but the failure message is clearer if the rename is intentional and atomic.
- **Founder voice MUST NOT replace the conservative legal voice on recommended-tools.md.** Use the canonical DRAFT-disclaimer pattern (`legal-document-generator.md:22`). Don't invent founder-toned alternatives that imply Soleur endorses any tool.
- **Statutory-deadline interpolation precision.** "GDPR Art. 33 — 72 hours" is shorthand; full text is "without undue delay and where feasible, not later than 72 hours" and applies to controllers. Inline H3 uses shorthand (actionable); `recommended-tools.md` body carries the nuance. CLO PR-review validates wording.

## Open Questions

1. **Does `/soleur:go` keyword classifier need a Phase 6.5 disambiguation gate** for ambiguous mentions (e.g., "MSA" could be Master Services Agreement or Master of Science in Accountancy)? Defer to /work-time judgment; if false positives surface in dogfooding, file a follow-up.
2. **`bun run build:docs` availability** — verify at /work Phase 8.

## Out of Scope / Non-Goals

(Carry-forward from spec; no additions.)

- **Not** importing/delegating/lifting any code from `anthropics/claude-for-legal`.
- **Not** producing `/soleur:legal-*` commands that wrap upstream plugins.
- **Not** amending Soleur ToS for legal-tooling-bridge UPL coverage.
- **Not** adding Anthropic as a sub-processor row in `data-protection-disclosure.md` for this scope.
- **Not** building an Apache-2.0 NOTICE generator skill or an upstream-drift cron.
- **Not** privileging Anthropic over other downstream specialists.
- **Not** instrumenting click-through analytics on `recommended-tools.md`.
- **Not** generating GitHub issues for each threshold (the `clo` agent emits inline triage; persisting per-threshold matter files would adopt claude-for-legal's matter-workspace pattern, which the brainstorm rejected).
- **Not** mutating #3786's recorded re-evaluation criteria (Phase 8 posts a context comment only).

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-15-feat-clo-founder-threshold-detection-plan.md. Branch: feat-cc-legal-skill-bridge. Worktree: .worktrees/feat-cc-legal-skill-bridge/. Issue: #3785. PR: #3780. Plan reviewed (5-agent panel; revisions applied: P0 phase numbering fixed, Phase 7 anchor machinery cut, Phase 9 spec mutation cut, Risks 11→5, /soleur:go keyword route un-deferred, zero-findings catalog gap fixed, gosprinto removed as legal Tool B per verification, escalation H3 with deadline-in-heading, gdpr-gate signature corrected). Implementation next.
```
