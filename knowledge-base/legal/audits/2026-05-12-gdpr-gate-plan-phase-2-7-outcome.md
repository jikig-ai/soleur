---
title: "GDPR-gate plan Phase 2.7 outcome — PR-C of #3603"
type: gdpr-gate-outcome
phase: plan-2.7
plan: knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md
issue: 3603
pr: 3662
invoked_at: 2026-05-12
brand_survival_threshold: single-user incident
trigger: clause-b (USER_BRAND_CRITICAL)
critical_findings: 0
important_findings: 0
suggestion_findings: 4
operator_ack_required: false
---

**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

# `/soleur:gdpr-gate` plan Phase 2.7 outcome — PR-C of #3603

## Scope and trigger

- **Audited:** `knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md`
- **Diff at plan time:** empty (plan is prose); the gate audits the plan's prescribed FR/TR sections against the regulated-data canonical regex.
- **Canonical regex match:** **NO**. The regex `^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)` matches no PR-C file. PR-C touches only:
    - `docs/legal/*.md` (4 files)
    - `plugins/soleur/docs/pages/legal/*.md` (4 files)
    - `knowledge-base/legal/compliance-posture.md`
    - `knowledge-base/legal/audits/*.md` (3-5 new evidence files)
- **Extended trigger:** clause **(b)** of `hr-gdpr-gate-on-regulated-data-surfaces` — plan declares `brand-survival threshold: single-user incident`. Mandatory invocation per the rule's extension to cover cross-controller data-movement surfaces.

## v1 5-check results

| `check_id` | Article | Triggered | Rationale |
|---|---|---|---|
| `GDPR-Art-6` | Art. 6 lawful basis | NO | No new schema columns introduced by PR-C. PR-A2 (#3648, already merged) introduced the `usage` jsonb column; PR-C documents it. Lawful basis (Art. 6(1)(b) contract performance) inherited from the existing `messages` table activity. |
| `GDPR-Art-5e` | Art. 5(1)(e) retention | NO | No new PII tables. PR-C documents the retention rule (cascade-delete equality with parent conversation) for existing `messages` rows. AC10 + AC18 are the documentation-side closure of the retention-disclosure gap. |
| `GDPR-Art-17` | Art. 17 erasure | NO | No new FKs to `users`. The `messages.conversation_id → conversations.user_id` cascade was established in migration 001; PR-C makes the cascade explicit in disclosure prose. |
| `GDPR-Chapter-V` | Arts. 44-49 cross-border | NO | No new non-EEA vendor env vars. Supabase already in Vendor DPA register (signed 2026-03-19, eu-west-1, SCCs M2+M3); the `usage` jsonb column is covered by the existing processing-activity-bound DPA. Compliance-posture.md row gets an evidentiary Notes-column appendage only (AC18). |
| `GDPR-Art-9` | Art. 9 special-category | NO | `usage` jsonb stores token counts + cost metadata (USD float, model name, token type counters). NONE of: health, biometric, genetic, religious, political-opinion, sexual-orientation, ethnic-origin, philosophical-belief, trade-union membership. Not a special-category data class. |

**0 Critical, 0 Important. No operator-acknowledgment escalation required. No `compliance/critical` issue creation from this invocation. No `compliance-posture.md` Active Items row written by the gate.**

## Suggestions (heuristic, advisory only)

### `PLAN-Art-13-3` — Art. 13(3) timing argument is correctly framed

- **Severity:** Suggestion
- **Article:** Art. 13(3) GDPR
- **Location:** Plan §Overview, §Risks R1 (P0), §Acceptance Criteria OP1-OP4
- **Pattern matched:** "disclosure precedes flag-flip activation" — the plan correctly identifies the latent-exposure window between PR-A2 merge (2026-05-12 09:41 UTC) and PR-C live-on-prod.
- **Why this matters:** Plan R1 P0 mitigation (operator runbook requires PR-C merge SHA + live-on-prod verification timestamp before flag flip) is the correct Art. 13(3) posture. AC20 latent-exposure documentation + Completed Compliance Work near-miss row provide the compound-learning audit trail. CLO Q1 advisory was load-bearing here.
- **What to do:** Proceed as planned. The work-phase 2 exit gate (Phase 9) will re-verify that `CC_PERSIST_USAGE=false` still holds at PR-ready-for-review time.

### `PLAN-Art-30` — Article 30 register additions correctly enumerated

- **Severity:** Suggestion
- **Article:** Art. 30 GDPR
- **Location:** Plan AC12 (GDPR Policy §10 register, activity #10 = conversation management)
- **Pattern matched:** Article 30 register canonical-vs-plugin gap.
- **Why this matters:** Forward-port adds the 10th processing activity to canonical, with documented data categories, legal basis (Art. 6(1)(b) contract performance), and retention rule (cascade-delete). Activity count line ("The register documents nine processing activities" → "ten") updated atomically per AC12. Result is Art. 30(1)(c)(d)(f) compliant. `usage` jsonb appendage on activity #10 enriches Art. 30(1)(c) data-category enumeration.
- **What to do:** Proceed as planned. Verify count line update post-edit per AC12 verification step.

### `PLAN-Art-9` — `usage` jsonb classification is sound

- **Severity:** Suggestion
- **Article:** Art. 9 GDPR
- **Location:** Plan §Implementation Phase 2 step 1
- **Pattern matched:** new personal-data category disclosure (`usage` jsonb).
- **Why this matters:** `usage` jsonb stores `{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens, cost_usd}` (verified against PR-A2 migration). Not Art. 9. Legal basis correctly inherited (contract performance, Art. 6(1)(b)) — same activity (`messages` row), same processor (Supabase), same retention (cascade-delete).
- **What to do:** No action. Recorded for the audit trail.

### `PLAN-Art-35` — DPIA re-evaluation note in GDPR §9 is sufficient

- **Severity:** Suggestion
- **Article:** Art. 35 GDPR
- **Location:** Plan AC11 (GDPR Policy §9 DPIA re-evaluation)
- **Pattern matched:** new column on existing PII-bearing table (`messages.usage`).
- **Why this matters:** Article 35(3) high-risk threshold remains unmet for this addition — same processing-activity scale (`messages` table at single-tenant scale), same legal basis, no special categories, no profiling, no large-scale systematic monitoring of data subjects, no automated decision-making with legal effects. Plan AC11 correctly documents this conclusion.
- **What to do:** Proceed as planned. If `usage` jsonb is later consumed by an automated decision-making feature (e.g., usage-based throttling or pricing tier auto-assignment), DPIA re-evaluation will be required at that future feature's plan time. Out of PR-C scope.

## Disposition

- **No Critical findings.** No operator-acknowledgment escalation triggered.
- **No `compliance/critical` GitHub issue creation** from this invocation. (Other plan ACs may file `domain/legal` issues per AC24; those are unrelated to this gate's escalation flow.)
- **No `compliance-posture.md` Active Items row written by the gate.** The plan's AC18 + AC20 prescribe operator-driven Completed Compliance Work rows for the W7 DSAR audit and the latent-exposure near-miss — those are documentation-side compounds, not gate-emitted findings.

Plan proceeds to plan-review (DHH + Kieran + code-simplicity reviewers). Phase 9 work-phase 2 exit re-invocation will run when `/work` reaches the regulated-data exit gate. Phase 5.5 ship-time invocation reserved for `/ship` skill.

## Sub-processor disclosure (Anthropic, per gate prompt template)

Column NAMES (not values) were transmitted to Anthropic via this gate's reasoning step. No row-value payload transmitted. This is itself a Chapter V transfer; it falls under Anthropic's existing DPA recorded in `compliance-posture.md` Vendor DPAs (verified 2026-03-19). No further disclosure obligation arises.

## v2 amendment (2026-05-12, post-Doppler verification)

The v1 outcome above stated "the window remains LATENT (no `usage` rows written without disclosure)" based on the plan-time assumption that `CC_PERSIST_USAGE=false` in Doppler. **At plan-finalization, direct verification via `doppler secrets get CC_PERSIST_USAGE -p soleur -c {prd,prd_scheduled} --plain` returned `true` for both configs.** The operator confirmed this is a deliberate decision: PR-C disclosure is in flight, the operator chose to flip the flag with the understanding that the disclosure refresh would land shortly after. The flag flip is not a near-miss and not an Art. 33-notifiable incident under the operator's framing.

This amendment converts the Phase 2.7 outcome's R1-class narrative (latent-window mitigation) to a documented operator-decision (`compliance-posture.md` Completed Compliance Work row per plan AC8 row (b)). The `PLAN-Art-13-3` Suggestion above remains in effect — Art. 13(3) timing is correctly framed by the plan; the difference is that the disclosure side is the closing action, not the gating action of a separate flag flip.

The remaining v1 Suggestions (PLAN-Art-30, PLAN-Art-9, PLAN-Art-35) are unaffected.

**Disposition unchanged:** plan proceeds to plan-review (completed — DHH/Kieran/code-simplicity feedback applied to plan v2) and Phase 5 work-phase 2 exit re-invocation.

## Cross-references

- Plan v2: `knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md`
- AGENTS.md rule: `hr-gdpr-gate-on-regulated-data-surfaces`
- CLO advisory: integrated inline in plan §Domain Review (Q2-Q4 + R1-R7 from v1; Q1 reframed in v2 per Research Reconciliation row 3).
- Worktree: `.worktrees/feat-cc-transcript-hardening-prc-3603`
- Draft PR: #3662
- Umbrella issue: #3603
