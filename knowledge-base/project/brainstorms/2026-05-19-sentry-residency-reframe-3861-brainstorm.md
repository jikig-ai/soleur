---
title: "Sentry residency reframe — falsified-premise correction after support replies"
date: 2026-05-19
parent_issue: 3861
bundled_issues: [3861, 3962, 3849]
draft_pr: 4044
brand_survival_threshold: single-user incident
lane: cross-domain
triad: [CPO, CLO, CTO]
status: brainstorm-complete
---

## What We're Building

A two-PR corrective sweep that retracts the falsified "phantom-ingest to unowned third-party org" narrative committed to main on 2026-05-17 (PR-α #3904, PR-β #3945, PR-γ #3946), and replaces it with the truth Sentry support confirmed on 2026-05-19: both `jikigai` (org ID `4511123328466944`) and `jikigai-eu` orgs are owned by `jean.deruelle@jikigai.com`, both run on Sentry's EU databases, and no third-party recipient ever existed. The 49-day "phantom-ingest window" was ingest into the operator's own EU-database org via the `jikigai.sentry.io` URL front door.

The probable root cause of the original 401 / discovery failure is **token-scope mismatch** (runtime `SENTRY_AUTH_TOKEN` minted with scope only for the `jikigai-eu` slug, not for `jikigai`), compounded by misreading Sentry's URL routing topology (`jikigai.sentry.io` ≠ `eu.sentry.io/jikigai`). This must be empirically verified before any doc correction lands.

**Out of scope:** revert the operational outcome. The runtime cutover to `jikigai-eu` is the cleaner state regardless of original framing and stays.

## Why This Approach

The committed disclosure in `knowledge-base/legal/article-30-register.md` PA8 §(d) currently reads as an **affirmative public-facing admission** of a sub-processor recipient-drift event — named org ID, SQL-count of affected users, Art-33 deadline calculation. Triad converged independently: this is **more harmful** than the prior absence. A DPA reading PA8 §(d) today concludes Soleur self-reported a sub-processor incident; the inevitable follow-up question ("why didn't you Art-33 notify?") cannot be answered truthfully because the event did not occur.

The right corrective shape is:

1. **Empirical first.** Don't pre-commit the reframe narrative until the token-scope probe runs and lands as committed evidence. Unanimous triad pushback ("don't pre-commit until probe runs"). The probe is first-party reproducible evidence; Sentry's two replies are hearsay from our evidentiary stance — useful confirmation, not sole authority.
2. **Retract-in-place with dated pointer**, not silent rewrite and not append-correcting-block. CLO's argument carried: a live disclosure register must not read as an affirmative incident claim that no longer holds. Git history preserves the original entry; the live document is dated `[2026-05-19 UPDATE: ...]` with a forward-pointer to the corrected PIR.
3. **PIR Gate-3b precisely as specified.** The PIR Phase 8 Gate 3b prescription (line 100 in current main) already names this exact recovery path: "HALT closure; reopen this PIR (`status: open`); investigate why region-router + token-membership probes returned 401 against a self-owned org. This branch is a workflow-defect signal, not a residual." Follow that prescription, do not invent new structure.
4. **Two PRs**, not one. Splits one load-bearing evidentiary commit (probe report + PIR reopen) from a wider doc sweep (Article 30 + ADR + learnings). PR-1's review can move fast; PR-2's review can take its time without blocking the urgent reopen.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Token-scope probe runs FIRST**, before any doc-touch. Agent-driven via Playwright MCP, operator-ack at the org:read token mint step. | Unanimous triad pushback. The reframe narrative rests on the inference "401 = token scope, not unowned org" — committing doc corrections before verifying repeats the same error class that produced the original framing. |
| D2 | **PR shape: two PRs.** PR-1: probe + PIR reopen + Gate-3b correction (3–4 files). PR-2: Article 30 PA8 §(d) + Vendor DPAs row + auth.users audit + ADR-031 + host glossary + learnings (5–6 files). | Decouples urgent evidentiary work from corpus sweep. PR-1 has narrow risk; PR-2 can be reviewed more deliberately. |
| D3 | **PA8 §(d) correction style: retract-in-place + dated pointer.** Strike the affirmative recipient-drift paragraphs; replace with `[2026-05-19 UPDATE: ...]` block linking forward to the corrected PIR. | CLO recommendation. Append-correcting-block (CPO alternate) keeps a false claim live alongside a correction, which an inattentive reader could conflate; retract-in-place removes the false claim from the live document while git history preserves provenance. |
| D4 | **Audit-trail preservation:** dated `[2026-05-19 UPDATE: ...]` annotations on the live disclosure surfaces (PA8, PIR Phase 8). Git history is the audit trail for supporting docs (ADR-031, host glossary, learnings). | Regulators read the live disclosure register, not git log. Annotation on disclosure surfaces preserves evolution without leaving false claims live. |
| D5 | **Operational outcome stands.** Runtime stays on `jikigai-eu`. 4-gate audit script stays (reframe header comment from "detects phantom-ingest" → "detects destination-controllability drift"). 7 secret-surface atomic swaps NOT reverted. | CTO: jikigai-eu is the cleaner state regardless — fresh org, no historical baggage. Reverting costs another 7-surface swap with the same risk profile for zero gain. 4-gate audit is defense-in-depth even when its motivating story was wrong. |
| D6 | **Billing reply: transfer credit to `jikigai-eu`.** Operator transmits card-last-4 + expiry directly to Sentry support reply (NOT through agent conversation, per `hr-never-paste-secrets-via-bang-prefix`). | Avoids refund round-trip + bank settle. Credit flows into the continuing EU customer relationship. |
| D7 | **PIR treatment: reopen + dated Gate-3b correction**, not full rewrite. Strike `art_33_deadline` (anchored on a notional breach that didn't occur). Strike `classification_override.chosen: none` (replace with Gate-3b note). Add explicit "Phase A2 misdiagnosis" section referencing the support replies verbatim. | Gate 3b prescription is precise — follow it. Full rewrite (CTO alternate) destroys the evolution evidence; the misdiagnosis IS part of the institutional record. |
| D8 | **ADR-031 + host glossary: revise-in-place.** DSN cluster substring **remains residency-authoritative** (unchanged routing fact). The second-layer learning ("cluster substring ≠ admin-controllability") is **still true** but needs reframing as **three** independent dimensions: URL slug, database cluster, and token-membership scope. | CTO: the original learning was correct but learned in service of a wrong story. Reframe restores the three orthogonal axes. |
| D9 | **Brand-survival threshold for correcting work: `single-user incident`.** Audience is regulators-of-record. Every retracted claim needs a forward-pointer to the corrected statement. | Triad converged. CLO gloss: "corpus-correction" frames the audience correctly even though the threshold tier name stays the same. |

## Probe sequence (D1, CTO-authored)

```bash
# Step 1: prd token (jikigai-eu scope) against ORIGINAL org
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN_PRD" \
  https://sentry.io/api/0/organizations/jikigai/
# Expected: 401 (token not scoped to jikigai slug)

# Step 2: same token against NEW org (control)
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN_PRD" \
  https://sentry.io/api/0/organizations/jikigai-eu/
# Expected: 200 (token scoped to jikigai-eu)

# Step 3: mint short-lived org:read token via Sentry UI scoped ONLY to jikigai,
# label "probe-2026-05-19-revoke", run Step 1 again, revoke in same session
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $PROBE_TOKEN" \
  https://sentry.io/api/0/organizations/jikigai/
# Expected: 200 (scope-matched token reveals operator-controllable org)
```

Probe report committed at `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md` (PR-1 artifact). Token lifetime < 10 min, one read call, revoked before probe report is written. Blast radius: one ephemeral read-scoped token in Sentry audit log, traceable to operator.

**Conditional flow:** if Step 1 returns anything other than 401 (e.g., 403, 200), OR Step 3 also returns 401, the token-scope theory dies and the brainstorm reframe halts. Surface the divergence and re-spawn triad before doc-touch.

## User-Brand Impact

**Artifact:** `knowledge-base/legal/article-30-register.md` PA8 §(d) "Recipient-drift after-the-fact disclosure" block (lines ~160, ~10 lines of affirmative public-facing legal text). Also: PIR `status: resolved` frontmatter + `art_33_triggered: true` + `art_33_deadline: 2026-05-19T12:50:00Z` (a deadline anchored on a non-event).

**Vector:** DPA / regulator reading the live Article 30 register today concludes Soleur had a sub-processor recipient-drift event with a third party (named org ID, SQL count, dates). The inevitable follow-up ("Art 33 notification?") cannot be answered truthfully because the event did not occur. False affirmative disclosure of a sub-processor incident is regulator-bait of higher class than absence of disclosure.

**Threshold:** `single-user incident`. The current corpus is more alarmist than truth — correction is risk-reducing, not risk-introducing. But the correcting work itself touches public-facing legal disclosure surfaces and must be evidentially grounded (the probe report); a sloppy correction inherits the same evidentiary weakness as the original.

**Channel of harm:** regulators and counsel reading the register. End-user impact is indirect (brand-credibility), but the audience whose perception we are correcting is institutional, not end-user.

## PR Sequencing

### PR-1 (urgent, ships first) — probe + PIR Gate-3b

**Files (~3–4):**
- `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md` (NEW; probe output + screenshots)
- `knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md` (`status: open`; strike `art_33_deadline`; strike `art_33_triggered: true`; append `## Phase 9 — Gate 3b Correction (2026-05-19)` section with Sentry replies verbatim + token-scope probe results)
- `apps/web-platform/scripts/sentry-monitors-audit.sh` (header comment reframe: "destination-controllability drift" not "phantom-ingest")
- Close #3962 (Gate-3b resolved 12 days early)

**Brand-survival threshold:** `single-user incident`. User-impact-reviewer required at PR review.

### PR-2 (corpus sweep, ships after PR-1) — Article 30 + ADR-031 + learnings

**Files (~5–6):**
- `knowledge-base/legal/article-30-register.md` (PA8 §(d): retract-in-place + dated pointer per D3; Vendor DPAs row at line 258: keep DE residency claim, drop drift cross-reference)
- `knowledge-base/legal/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md` (rename + prepend correcting note; preserve SQL count)
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` (DE-region support survives; drop recipient-drift causal narrative; reframe "cluster substring ≠ admin-controllability" → three-dimensional)
- `knowledge-base/project/learnings/2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md` (keep, append three-dimensional reframe)
- `knowledge-base/project/learnings/2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md` (NEW)
- `knowledge-base/project/learnings/2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md` (append "premise cascade extended by Sentry replies 2026-05-19" pointer)

**Brand-survival threshold:** `single-user incident`. User-impact-reviewer required at PR review. PR-2 explicitly blocked-by PR-1.

### Operator action (parallel, no PR)

Reply to Sentry billing thread choosing "transfer credit to jikigai-eu", paste card-last-4 + expiry directly into the Sentry support reply (NOT into agent conversation). Capture screenshot of Sentry's acknowledgment as PR-1 evidence.

## Open Questions

1. **Step 3 token revocation timing** — should the probe report capture the revocation timestamp from Sentry's audit log to prove "ephemeral lifetime ≤ 10 min" as committed §5(2) evidence? (Probably yes; cheap to capture.)
2. **PA8 §(d) Vendor DPAs row (line 258)** — currently reads `Sentry (Functional Software GmbH) | DE | SCCs (standard EU-region terms) | DE region, intra-EU | 8`. The "8" is monitor-count; verify post-cutover count on `jikigai-eu` still matches 8 (PR-2 verifies inline).
3. **`classification_override.chosen: none`** in PIR frontmatter — does Gate-3b correction replace this with a new override value, or strike entirely (the override is moot once the population question is dissolved by "no recipient drift occurred")?
4. **#3849 (Sentry IaC AC13-AC16 blocked)** — does the token-scope probe also unblock this, or does it remain blocked on the separate `SENTRY_AUTH_TOKEN` operator-action thread? (Likely partial unblock; verify after probe runs.)
5. **Learning file naming** — the `2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md` is a high-leverage premise-validation learning. Should it also be cross-linked from `plugins/soleur/skills/brainstorm/SKILL.md` Phase 1.1 inline as a verification pattern? (PR-2 candidate.)

## Capability Gaps

None identified. The probe sequence uses existing Doppler tokens + standard Sentry UI org:read mint. The corpus correction uses existing surfaces. The 4-gate audit script already exists; only its header comment changes.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

(Mandatory CPO+CLO+CTO triad spawned per `USER_BRAND_CRITICAL=true`. Other 5 domains assessed as non-relevant — this is a legal-corpus correction with engineering verification; no marketing, ops, sales, finance, or support implications.)

### CPO

**Summary:** Current PA8 §(d) over-disclosure is higher brand risk than prior under-disclosure. Sequencing-blocker is the token-scope probe (#6 blocks #2, #3, #5). Append-do-not-rewrite-in-place pattern is the strongest provenance trail; threshold `single-user incident` stands. Pushback: don't pre-commit the reframe narrative until the probe lands.

### CLO

**Summary:** PA8 §(d) is actively harmful — a DPA reading it sees an affirmative sub-processor incident report with named org ID and Art-33 deadline. Retract in place (not annotate); a live disclosure register must not read as a claim that no longer holds. Per-surface: PA8 retract, Vendor DPAs revise, auth.users audit reframe-not-delete, PIR reopen, ADR revise-in-place. Token-scope probe is §5(2) accountability gold — run and commit. Threshold: `corpus-correction` audience (regulators, not end users) with `single-user incident` tier. Pushback: Sentry replies are hearsay from our stance — verify the 401 root cause before retracting.

### CTO

**Summary:** Token-scope probe via existing prd token + ephemeral org:read mint, no broad-scope token created. Operational outcome (jikigai-eu cutover) stands; 4-gate audit stays as defense-in-depth with reframed header. Three-dimensional URL/cluster/token-scope model replaces the two-dimensional "substring ≠ controllability" learning. Blast radius: ~8–10 files, single half-day PR (operator chose two-PR split). Pushback: don't pre-commit reframe until Step 3 probe lands; if Step 1 returns 403 (not 401) or Step 3 also returns 401, token-scope theory dies.

## References

- Parent issue: #3861 (do NOT close; needs scope rewrite reflected by PR-2 merge)
- Gated follow-through: #3962 (Gate 3b T+14d 2026-05-31; resolves with PR-1 ~12 days early)
- Adjacent blocked issue: #3849 (Sentry IaC AC13-AC16; may partial-unblock with PR-1 probe)
- Source replies: Sentry billing support 2026-05-19 + Rodolfo (Sentry support) 2026-05-19 (reproduced verbatim above)
- Committed corpus to correct:
  - `knowledge-base/legal/article-30-register.md` PA8 §(d) + Vendor DPAs row
  - `knowledge-base/legal/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md`
  - `knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md`
  - `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`
  - `knowledge-base/project/learnings/2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`
  - `knowledge-base/project/learnings/2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md`
  - `apps/web-platform/scripts/sentry-monitors-audit.sh` header
- Prior brainstorms (provenance):
  - `knowledge-base/project/brainstorms/2026-05-15-sentry-residency-cleanup-brainstorm.md`
  - `knowledge-base/project/brainstorms/2026-05-16-sentry-residency-a2-branch-c-brainstorm.md`
- Draft PR: #4044 (this brainstorm's worktree)
