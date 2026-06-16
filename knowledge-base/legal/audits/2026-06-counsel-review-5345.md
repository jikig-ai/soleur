---
title: "Counsel review audit — #5345 (routine_runs operational run-log legal-doc lockstep: Privacy §4.12 + GDPR §3.7 + DPD §2.3(ac) + Article-30 PA-29)"
type: counsel-review
date: 2026-06-16
issue: 5345
pr: 5342
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-06-16
signed_off_by: "CLO agent (v1 counsel-review attestation authority, Soleur-as-tenant-zero posture — operator authorized shipping; external counsel re-review reserved for the re_evaluation_triggers below)"
re_evaluation_triggers: "First arms-length (non-Soleur) tenant onboarded onto the routines substrate (at which point routine_runs.actor_id ceases to be the operator's own id and a genuine third-party data subject appears — promote routine_runs to DSAR_TABLE_ALLOWLIST under actor_id/Art.15 and re-disclose) OR any data subject whose habitual residence is outside the EEA OR any data subject belonging to a regulated industry (healthcare, finance, legal-services) OR a material growth in routine_runs row volume that makes the indefinite-retention floor disproportionate (the migration-107 header's own 'revisit if volume grows' trigger, cf. 103_github_events_retention_7day)"
---

# Counsel review audit — #5345 (routine_runs operational run-log legal-doc lockstep)

This audit file is the load-bearing discharge evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #5342 (`feat-routines-management`), which carries `brand_survival_threshold: single-user incident`. The PR introduces the new `public.routine_runs` operational WORM run-log (migration 107, #5345) and the four-surface GDPR legal-doc lockstep that discloses it.

I am the **v1 counsel-review attestation authority** (Soleur-as-tenant-zero posture, per the recurring-bug learning at `knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md` — the attestation is NOT deferred to the non-lawyer operator). The operator has authorized shipping; the operator retains an optional veto. External counsel re-review is reserved for the frontmatter `re_evaluation_triggers`. This attestation is the v1 *internal* sign-off and does not contradict the house-style "draft-requiring-professional-review" inline marking carried in each doc's Last-Updated ref-note (that wording is the standard marking, not a blocking gate marker, and is left as-is).

The disclosure data-model posture (FKs, WORM bypass, anonymise approach) was settled in Jean's commit `be3f7061` (the #5372 Art-17-deletability fix) and is NOT redesigned here; this audit attests the legal prose against that settled implementation. An earlier engineering review (security-sentinel + code-quality) already confirmed, column-by-column, that the prose matched migration 107 with ZERO drift, with the single gap — `error_summary` was "truncated" but the prose said "scrubbed" — FIXED in commit `67c105be` (the summary now runs through the shared `redactCommandForDisplay` allowlist BEFORE truncation). This audit re-verifies that fix holds.

The four artifacts below disclose the new substrate to the four regulator-facing surfaces: Privacy Policy §4.12, GDPR Policy §3.7, Data Protection Disclosure §2.3(ac), and Article 30 register PA-29. Each is CLO-agent-attested per the Soleur-as-tenant-zero posture, following the precedent set by the prior audit files at `knowledge-base/legal/audits/2026-05-counsel-review-{4051,4066,4289,4353,4558}.md`.

---

## Cross-check basis (prose ⊥ implementation)

Verification commands run against the worktree at HEAD (commit `ea113e32`):

- Schema source of truth: `apps/web-platform/supabase/migrations/107_routine_runs.sql`.
- Erasure call site: `apps/web-platform/server/account-delete.ts` step 3.995 (`anonymise_routine_runs`, lines 1000–1031).
- DSAR exclusion: `apps/web-platform/server/dsar-export-allowlist.ts` (`routine_runs` entry in `DSAR_TABLE_EXCLUSIONS`).
- Scrub boundary: `apps/web-platform/server/inngest/middleware/run-log.ts` (`errorSummary()` = `redactCommandForDisplay(firstLine).slice(0, ERROR_SUMMARY_MAX)`, `ERROR_SUMMARY_MAX = 500`).
- SHA repins: `apps/web-platform/lib/legal/legal-doc-shas.ts` re-verified against `sha256sum docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` — all three match.
- Canonical ⊥ Eleventy-mirror parity: the only diffs are the expected frontmatter/`base.njk` layout wrapper; the substantive `routine_runs` disclosure body landed in all three mirrors (`plugins/soleur/docs/pages/legal/*.md`).

---

## Artifact 1 — Privacy Policy §4.12 "Routine Run-Log (`routine_runs`)"

**File:** `docs/legal/privacy-policy.md` (canonical) + `plugins/soleur/docs/pages/legal/privacy-policy.md` (Eleventy mirror)

**Scope of review:** new `**Routine Run-Log (`routine_runs`)**` paragraph appended to §4.12 (after the `workspace_activity` and `kb_files` blocks), plus the lawful-basis paragraph that carves the run-log out of the §4.12 default Art. 6(1)(b) basis onto Art. 6(1)(f). Plain-language enumeration of the recorded fields; the off-schedule-only account-identifier nuance; the indefinite-retention statement; the Art. 17 NULL-on-deletion + row-preservation statement; the self-serve-export exclusion with a forward pointer to DPD §2.3(ac); Article 30 PA-29.

**Particular attention + CLO findings:**

1. **Lawful-basis carve-out accuracy.** §4.12's umbrella lawful-basis paragraph reads "Article 6(1)(b) GDPR — performance of the contract … The Routine Run-Log above rests instead on **legitimate interest** (Article 6(1)(f) GDPR) — operational audit of routine executions." This correctly distinguishes the run-log from the contract-basis workspace-collaboration features and matches the migration-107 `LAWFUL_BASIS` header (`legitimate_interest`). **Verdict: accurate.**
2. **"Scrubbed, truncated error summary" claim.** Now true post-`67c105be`: `errorSummary()` applies `redactCommandForDisplay` (tokens/JWT/conn-string passwords/emails/UUIDs/IPs) BEFORE the 500-char `.slice()`. **Verdict: accurate.**
3. **Indefinite retention disclosed plainly.** "retained indefinitely as a low-volume audit log (approximately one entry per run)" — matches the migration `RETENTION: indefinite` header. **Verdict: acceptable** (see Decision record §retention).

**CLO sign-off:** ☑ Approved. Field enumeration matches migration 107; the 6(1)(f) carve-out is correctly scoped; the DPD §2.3(ac) forward-pointer resolves.

---

## Artifact 2 — GDPR Policy §3.7 "Routine run-log (routine_runs)" bullet (+ inline Art-6(1)(f) LIA)

**File:** `docs/legal/gdpr-policy.md` (canonical) + Eleventy mirror

**Scope of review:** new bullet inserted into §3.7 "Web Platform Service Delivery" (line 106, between the "Operational telemetry" entry and §3.8). Declares Art. 6(1)(f) legitimate interest; enumerates the data processed; carries the **inline three-part balancing test** that DPD §2.3(ac) and Article-30 PA-29 both cross-reference; Art. 21 objection route; indefinite retention; Art. 17 cascade summary; Art. 15/20 exclusion.

**Particular attention + CLO findings:**

1. **Art-6(1)(f) Legitimate Interest Assessment (LIA) sufficiency.** The inline balancing test has all three required limbs plus the Art. 21 right: (a) **purpose/necessity** — a tamper-evident WORM run-log is necessary for failure diagnosis, operational accountability, and Art. 32 integrity-of-processing, and cannot be achieved without recording who triggered each off-schedule run; (b) **necessity/minimisation** — minimal structural execution record, no message content, no third-party data, only the operator's own account id on off-schedule runs (NULL otherwise); (c) **balancing against data-subject interests** — on the single-operator tenant the controller and the sole data subject are the **same legal entity** (Soleur's operator), so the processing falls squarely within the data subject's own reasonable expectations of an audit log over their own automation; no profiling, no Art. 22 decision-making, no cross-purpose use. Art. 21 objection route to `legal@jikigai.com` is stated. **Verdict: the LIA is sufficient for the v1 single-operator posture.** The controller==data-subject identity is the load-bearing fact that makes the balancing test trivially favour processing at v1; it is also precisely the fact that the first-arms-length-tenant re_evaluation_trigger retires, at which point the LIA must be re-run against a genuine third-party data subject.
2. **Cross-reference integrity.** §3.7 exists (line 92) and the bullet sits inside it before §3.8 (line 112). DPD §2.3(ac) points to "GDPR Policy Section 3.7" for the balancing test — resolves. **Verdict: accurate.**
3. **Erasure-path prose.** "`anonymise_routine_runs` … NULLs `actor_id`/`delegating_principal` under the WORM bypass (preserving the audit row), called in `server/account-delete.ts` BEFORE auth-delete (mirrors `anonymise_workspace_activity`)" — matches account-delete.ts step 3.995 (runs at line 1000, BEFORE `auth.admin.deleteUser` at line 1040) and the migration's `SET LOCAL app.worm_bypass='on'` body. **Verdict: accurate.**

**CLO sign-off:** ☑ Approved. The inline LIA is the canonical balancing test for PA-29 and is sufficient at v1; the Art. 17 cascade prose mirrors the implementation.

---

## Artifact 3 — Data Protection Disclosure §2.3(ac) "Routine run-log (`routine_runs`, #5345)"

**File:** `docs/legal/data-protection-disclosure.md` (canonical) + Eleventy mirror

**Scope of review:** new `- **(ac)**` sub-section under §2.3 (next free letter after the (x)/(y) accretion). This is the most-scrutinised (regulator-facing) of the four surfaces and carries the full column-by-column enumeration.

**Particular attention + CLO findings:**

1. **Column-by-column enumeration completeness (the core drift surface).** §2.3(ac) enumerates: `id` (UUID PK), `routine_id` (text), `run_id` (text), `status` (text completed/failed), `trigger_source` (text scheduled/manual/agent), `actor_class` (text system/human/agent), `actor_id` (UUID NULLable, FK `public.users(id)` `ON DELETE RESTRICT`), `delegating_principal` (UUID NULLable, FK `public.users(id)` `ON DELETE RESTRICT`), `started_at`/`ended_at` (timestamptz), `duration_ms` (integer), `error_summary` (text NULLable, failed-only, scrubbed+truncated), `created_at` (timestamptz). **Cross-checked against the `CREATE TABLE public.routine_runs` in migration 107: every column, type, NULLability, and FK ON DELETE behaviour matches with ZERO drift.** The prose correctly omits no column and invents none. **Verdict: complete and accurate.**
2. **RPC signature + WORM-bypass mechanism.** Prose: `anonymise_routine_runs(p_user_id)` SECURITY DEFINER NULLs both actor columns under `app.worm_bypass = 'on'` (post-087 privilege-free GUC carve-out), preserving the row; `write_routine_run` is the service-role-only SECURITY DEFINER writer; `routine_runs_no_mutate()` are statement-level BEFORE-UPDATE/DELETE triggers; `routine_runs_latest` is `security_invoker`. **All match migration 107 verbatim** (incl. the statement-level-trigger + ON-DELETE-RESTRICT rationale, the named-role REVOKE matrix, and the security_invoker view). **Verdict: accurate.**
3. **DSAR-exclusion soundness.** Prose: excluded from the self-serve export at present; canonical rationale in `dsar-export-allowlist.ts`. The exclusion entry there reads "operational run-log … the only data subject is Soleur itself; rows record routine executions, not user-profile data … Promote to DSAR_TABLE_ALLOWLIST (actor_id, Art. 15) when a non-Soleur tenant exists or the dsar-export.ts chain is wired." The exclusion is reason-bearing (satisfies the `dsar-allowlist-completeness.test.ts` non-empty-reason lint) and mirrors the established `workspace_activity` operational-log exclusion precedent. **Verdict: sound.** The Art. 15 exclusion is defensible at v1 because on the single-operator tenant `actor_id`/`delegating_principal` is the operator's *own* id (no third-party data subject is denied access), and the operator separately has RLS operator-SELECT visibility over every row via `routine_runs_authenticated_select`. The promotion trigger is correctly captured in the frontmatter re_evaluation_triggers.
4. **Art. 22.** Negative determination stated — an operational audit record, no automated decision producing legal or similarly significant effects. **Verdict: correct** (the run-log records *that* a routine ran and its outcome; it makes no decision *about* a data subject).

**CLO sign-off:** ☑ Approved. The §2.3(ac) enumeration is the regulator-facing source of truth and matches migration 107 column-for-column; DSAR exclusion is sound; Art. 22 negative determination is correct.

---

## Artifact 4 — Article 30 register Processing Activity 29 (PA-29)

**File:** `knowledge-base/legal/article-30-register.md`

**Scope of review:** new PA-29 register block (purpose, data subjects, personal-data categories, lawful basis with three-part test, recipients, retention + Art. 17 cascade, TOMs, DSAR posture). Carries the `brand_survival_threshold: single-user incident` marker.

**Particular attention + CLO findings:**

1. **Register ⊥ disclosure consistency.** PA-29's lawful-basis, retention, recipients, TOMs, and DSAR rows are consistent with Artifacts 1–3 and with migration 107. The (g) TOMs row correctly enumerates the seven safeguards (WORM trigger, RESTRICT FKs, RLS operator-select, search_path-pinned SECURITY DEFINER writer with named-role REVOKE, bypass-re-arming anonymise RPC, security_invoker view, error_summary scrub). **Verdict: consistent.**
2. **Recipients accuracy.** (d) names the authenticated operator (RLS), the agent MCP tools via the service-role client (explicit GRANT on `routine_runs_latest`), and Supabase Inc (existing sub-processor) — "No new recipient, no new third-party egress, no new sub-processor." Matches the migration's GRANT matrix. **Verdict: accurate.**

**CLO sign-off:** ☑ Approved. PA-29 is internally consistent with the three regulator-facing surfaces and with the implementation.

---

## Decision record

**Lawful basis (resolved).** Art. 6(1)(f) legitimate interest, per the migration-107 `LAWFUL_BASIS` header. Sound at v1: the inline §3.7 LIA's balancing limb is dominated by the controller==sole-data-subject identity (the operator audits their own automation). Retired by the first-arms-length-tenant trigger.

**Retention (resolved — acceptable, not flagged).** Indefinite is acceptable for this substrate at v1 for three reasons: (a) it is a low-volume operational audit log (~one row per terminal cron run); (b) Art. 17 erasure of the *subject's PII* is independently guaranteed via `anonymise_routine_runs` (the indefinite floor applies to the run-lineage row, not to identifiable PII, which is NULLed on account deletion); (c) the migration header itself carries a "revisit if volume grows" self-trigger (cf. the 7-day `103_github_events_retention` precedent), which is mirrored into the frontmatter re_evaluation_triggers. No separate flag required.

**Art-6(1)(f) LIA (resolved — sufficient).** The three-part test is inline in GDPR Policy §3.7 with the Art. 21 objection route; sufficient for the single-operator v1 posture (Artifact 2 finding 1).

**Art-22 (resolved — negative determination).** No automated decision producing legal or similarly significant effects (Artifact 3 finding 4).

**DSAR-exclusion (resolved — sound).** Reason-bearing exclusion mirroring the `workspace_activity` precedent; defensible because no third-party data subject exists at v1; promotion trigger captured (Artifact 3 finding 3).

**error_summary scrub (re-verified).** "Scrubbed + truncated" is true post-`67c105be` (`redactCommandForDisplay` before `.slice(0,500)`), with test coverage in `run-log-middleware.test.ts`.

**Lockstep completeness.** All four surfaces + both Eleventy mirrors + the three SHA repins are present and mutually consistent; the SHA repins match the current canonical files. No `[DRAFT — pending CLO/counsel review]` literal gate markers exist (only the house-style inline "draft-requiring-professional-review" wording, left as-is). The compliance-posture entry's "CLO attestation: pending operator-verify" line is updated to reflect this attestation.

**Disposition:** **DISCHARGED.** Prose accurate (zero drift against migration 107, account-delete.ts, dsar-export-allowlist.ts, run-log.ts); lawful basis sound; LIA sufficient; Art. 22 negative; DSAR exclusion sound; retention acceptable. Ship Phase 5.5 may proceed.

---

## External counsel re-review triggers

External counsel re-review of all four artifacts is triggered by ANY of:

1. **First arms-length (non-Soleur) tenant** onboarded onto the routines substrate — `routine_runs.actor_id` ceases to be the operator's own id and a genuine third-party data subject appears; re-run the LIA, re-disclose, and promote `routine_runs` to `DSAR_TABLE_ALLOWLIST` (`actor_id`, Art. 15).
2. **Any data subject whose habitual residence is outside the EEA** — Art. 44–49 cross-border-transfer analysis for any DSAR fulfilment path.
3. **Any data subject belonging to a regulated industry** (healthcare, finance, legal-services).
4. **Material growth in `routine_runs` row volume** that makes the indefinite-retention floor disproportionate — the migration-107 "revisit if volume grows" self-trigger.

Any single trigger re-triggers a full re-read of all four artifacts plus a re-evaluation of (i) whether indefinite retention remains proportionate, and (ii) whether the DSAR self-serve exclusion still holds once a third-party data subject is in scope.
