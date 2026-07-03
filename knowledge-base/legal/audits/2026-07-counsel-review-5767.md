---
title: "Counsel review audit — #5767 / PR #5881 (L5 runaway guard: T&C §3a.5 BYOK best-effort ceiling + overage allocation; Art. 30 PA-22 (g)(12) working-pause + honest halt notification; ADR-041 rolling-1h cap reconciliation)"
type: counsel-review
date: 2026-07-02
issue: 5767
pr: 5881
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-07-02
signed_off_by: "CLO agent (v1 internal counsel-review attestation authority, Soleur-as-tenant-zero posture); operator (Jean Deruelle, Jikigai SARL gérant) retains optional veto"
re_evaluation_triggers: "First arms-length (non-Jikigai-affiliate) operator funding a BYOK-metered autonomous run under these Terms OR any operator whose habitual residence is outside the EEA OR any operator in a regulated industry (healthcare, finance) OR any change that (a) makes the pause account-wide for the per-run ceiling / max-turns halts, (b) adds a checkpoint/re-bill resume apparatus (ADR-041 Rejected alternative #6), (c) causes the cost-breaker notification payload to carry any field beyond the recipient's own account id + server-generated cost aggregates + the reason/window enums, or (d) implements the deferred rolling-24h founder budget (#5903) or the daily/monthly tiers, which would re-open the §3a.5 disclosure and the ADR-041 reconciliation note"
---

# Counsel review audit — #5767 / PR #5881 (L5 runaway guard)

This audit file is the load-bearing discharge evidence for the counsel-review CLO-attestation gate (ship Phase 5.5) on PR #5881 (`feat-l5-runaway-guard`), issue #5767. Per the Soleur-as-tenant-zero v1 posture, the CLO agent is the attesting authority; the operator (`ops@jikigai.com`, a non-lawyer founder) is NOT the sign-off — this discharges the recurring bug recorded at `knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`. This attestation is the v1 *internal* sign-off; external counsel re-review is reserved for the frontmatter `re_evaluation_triggers`.

**Brand-survival threshold: single-user incident.** The feature exists to make a formerly-cosmetic spending pause real and to make a formerly-silent (Sentry-only) cost/loop halt honestly visible to the operator, so a runaway leader loop can no longer burn the operator's BYOK Anthropic credits without pausing and telling them.

The three artifacts below carry the legal-attestation content: (1) the amended **T&C §3a.5** (canonical + Eleventy mirror, with the `TC_VERSION` 2.3.0→2.4.0 bump and the recomputed `TC_DOCUMENT_SHA`); (2) the **Article 30 register PA-22 (g)(12)** TOM entry; (3) the **ADR-041** Layer-0 + notification sections with the rolling-1-hour cap reconciliation. Each implementation claim in the prose was cross-checked against the actual implementing files (below); security-sentinel independently found the prose↔code cross-check clean in code review, and this audit owns the lawful-basis + disclosure-accuracy attestation.

**Implementing files cross-checked (source of truth for every prose claim):**

- `apps/web-platform/supabase/migrations/121_byok_cap_kill_tripped_while_paused.sql` — the `record_byok_use_and_check_cap` body: 1-hour `SUM(token_count * unit_cost_cents)` over `now() - interval '1 hour'` grouped by `founder_id`, compared to `users.runtime_cost_cap_cents`; `kill_tripped = true` whenever `runtime_paused_at IS NOT NULL` (paused-state, not just NULL→set transition); `runtime_paused_at` set on first breach only (`WHERE ... AND runtime_paused_at IS NULL`), NEVER cleared (set-never-clear, AC2); `FOR UPDATE` row lock; `SECURITY DEFINER` with `search_path = public, pg_temp`; service-role-only GRANT.
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` — spawn-entry pause gate (`step.run("check-runtime-pause")`, fail-OPEN on read error); the `notify` subset wired at the four cost/turn-cap sites; the single `step.run("notify-cost-breaker")` memoized notify at the one `persistFailure` deadletter site, gated by `isCostBreakerReason(reason)`; the `run_paused` site passes NO `notify` object.
- `apps/web-platform/server/notifications.ts` — `COST_BREAKER_NOTIFY_REASONS` single source of truth; `CostBreakerNotificationPayload` = `{type, reason, which_window, context:{cumulativeCents, ceilingCents}}` (no prompt/response content, no third-party PII, recipient = founder's own userId); honest per-reason copy; `mirrorNotifyFailure` → Sentry `op=notify-cost-breaker`.
- `apps/web-platform/app/api/dashboard/runtime/resume/route.ts` — the SOLE `runtime_paused_at = NULL` writer; origin/CSRF gate + `auth.getUser()` + service-role UPDATE scoped to `id = user.id` (server-derived); `.select("id")` rowcount guard fails loud on 0/≠1 match.

**Verification performed at audit-write time:**

- `sha256sum docs/legal/terms-and-conditions.md` = `f3640a38ea9805667456336ea2be8cf9606ee61a097664ad2770e3888893a5cf`, byte-identical to `TC_DOCUMENT_SHA` in `apps/web-platform/lib/legal/tc-version.ts`. The SHA is load-bearing: it drives the Art. 13(3) re-consent banner, so a stale SHA would fail to re-prompt on a material change. Match confirmed.
- `TC_BUMP_METADATA.substantiveChange = "BYOK best-effort cost ceiling and operator overage allocation"` — period-free (banner-shape gate), `lastUpdated = "July 2, 2026"`.
- Migration 121 body: 1-hour `SUM` vs `runtime_cost_cap_cents` and set-never-clear confirmed against the RPC body (no daily/monthly tier exists in the shipped RPC — confirming the ADR-041 reconciliation note is honest, not aspirational).

---

## Re-evaluation triggers (external counsel re-review of all three artifacts)

ANY of the following triggers an external-counsel re-read (see frontmatter `re_evaluation_triggers` for the canonical set):

1. **First arms-length operator.** The v1 posture is bounded by Soleur-as-tenant-zero (the operator is Jikigai itself, and is simultaneously the data subject and the BYOK keyholder). The first non-Jikigai-affiliate operator who funds a BYOK-metered autonomous run under these Terms triggers re-read of (a) the §3a.5 overage-allocation fairness against consumer-fairness law (UK CRA 2015 Part 2 / EU UCTD 93/13) when the operator is not also the drafter, and (b) the Art. 6(1)(f) balancing test when the data subject is not the controller-affiliate.
2. **EEA-out operator.** Habitual residence outside the EEA raises Art. 44–49 transfer questions for the cost-telemetry + notification path (already routed via Anthropic DPF+SCCs and Resend/Supabase existing mechanisms, but re-confirm for the new surface).
3. **Regulated-industry operator.** Healthcare / finance / legal-services sector-specific rules not captured in v1.
4. **Scope changes** that re-open the disclosure: making the account-wide pause fire for the per-run ceiling / max-turns halts (currently only the rolling-1h cap pauses the account); adding a checkpoint/re-bill resume apparatus (ADR-041 rejected alternative #6); widening the `cost_breaker_tripped` payload beyond recipient-own-id + server-generated cost aggregates + enums; or shipping the deferred rolling-24h founder budget (#5903) / daily-monthly tiers.

---

## Artifact 1 — Terms & Conditions §3a.5 "BYOK cost ceiling" (rewrite) + `TC_VERSION` 2.4.0

**Files:** `docs/legal/terms-and-conditions.md` (canonical) + `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (Eleventy mirror) + `apps/web-platform/lib/legal/tc-version.ts` (`TC_VERSION` 2.3.0→2.4.0, `TC_DOCUMENT_SHA` recomputed, `TC_BUMP_METADATA` refreshed).

**Scope of review:**

- §3a.5 rewritten from a single paragraph into three: (i) the unchanged BYOK/audit-ledger framing; (ii) a NEW paragraph describing the Web Platform's best-effort safeguards — a per-run cost ceiling ($2.00 / `PER_SPAWN_COST_CEILING_CENTS = 200`), a bounded per-run step limit (`LEADER_MAX_TURNS = 8`), and a rolling short-window (~1-hour) cumulative-spend cap per account (`runtime_cost_cap_cents`), with pause-and-notify on trip and operator-cleared resume; (iii) a NEW overage-allocation paragraph assigning all BYOK API charges and overage — **including spend incurred before a best-effort safeguard halts a run** — to the operator, subject to §11 (Limitation of Liability).
- **Removal of the prior false statement** "The Web Platform does not include a Jikigai-provided cost ceiling beyond the cap you set on your own key." This statement was falsified by the shipped Layer-0/Layer-1/Layer-2/Layer-3 enforcement; removing it is the core corrective act of this artifact.
- Version bump 2.3.0→2.4.0 (material change class per `knowledge-base/legal/tc-version-bump-policy.md`), SHA recomputed to match the amended canonical doc (verified above), `TC_BUMP_METADATA` refreshed with a period-free `substantiveChange`.
- Canonical/mirror parity: the §3a.5 body and the Last-Updated changelog byline are byte-consistent across both files (prepend-without-date-bump convention, `#5767` segment ahead of the prior `#4949/#4952` segment).

**Particular attention — resolved:**

1. **Lawful basis (Art. 6(1)(b) + 6(1)(f)).** The safeguards, the account pause, and the operator-cleared resume are all performance-of-contract processing under Art. 6(1)(b) — they are the metered-runtime service the operator's subscription buys (PA-22 register limb (b) already grounds the runtime in 6(1)(b)). The cost-telemetry writes that make the rolling-1h SUM possible are grounded in Art. 6(1)(f) per PA-22 (Lawful basis). No new lawful basis is introduced by §3a.5; the disclosure describes existing-basis processing. **Verdict: sound.**
2. **Overage allocation fairly disclosed?** Yes. The allocation is (a) conspicuous — it sits in the operative §3a.5 and is summarized in the Last-Updated changelog; (b) honest about limits — the safeguards are expressly "provided on a best-effort basis and are not a guarantee," "may not prevent all overspending," and "network, timing, or system conditions can allow spend to exceed a ceiling before a run halts," which faithfully mirrors the RPC reality (the audit row is appended before the cap SUM/decision, and the cap blocks the *next* call rather than clawing back the crossing call); (c) balanced — the operator is the Anthropic keyholder who sets the direct cap, so allocating BYOK spend to the keyholder is the natural allocation, and the clause is a net *improvement* over the prior "no ceiling" posture rather than a new exclusion of a protection the user had; (d) tied to the existing §11 liability framework rather than an unbounded standalone carve-out. Under consumer-fairness analysis this does not create a significant imbalance to the detriment of the (v1: affiliate) operator. **Verdict: fairly disclosed.**
3. **Accuracy of "pause… you resume by clearing the pause" for ALL safeguards (nuance).** In the shipped code, only the rolling-1h cap (`byok_cap_exceeded`) sets `runtime_paused_at` and therefore requires the operator-resume clear; the per-run ceiling (`cost_ceiling_exceeded`), the max-turns halt (`leader_max_turns_exceeded`), and the transient `cap_check_unavailable` halt the *run* without setting the account pause. §3a.5's collective phrasing ("When a safeguard trips, the Web Platform pauses further automated spending on your account… you resume by clearing the pause") slightly over-describes the account-level pause for the non-cap halts. This is (a) operator-favorable (it describes MORE protection than exists, never disclaims a protection the user has), (b) subordinate to the precise in-product per-reason copy in `notifications.ts` (`costBreakerCopy` distinguishes the reasons; the email CTA renders "Clear pause & resume" only for `byok_cap_exceeded`), and (c) immaterial at the single-user tenant-zero threshold. **Verdict: non-blocking accuracy nuance; recorded as an optional in-PR tightening (see In-PR conditions), not a fairness or honesty defect.**

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| CLO agent (v1 internal counsel-review attestation authority, Soleur-as-tenant-zero posture; operator retains optional veto; external re-review triggers per frontmatter) | 2026-07-02 | CLO-attestation gate on PR #5881 | ☑ | Approved. The removal of the false "no Jikigai cost ceiling" statement is the correct corrective act. Safeguard description is honest-by-construction (best-effort, not-a-guarantee, admits pre-halt overspend). Overage allocation is conspicuous, balanced, and §11-anchored — fairly disclosed. SHA verified byte-identical; version bump is correctly classed material. Non-blocking: the collective "pause/resume" phrasing over-describes the account pause for the non-cap halts (operator-favorable; precise in-product copy governs). |

---

## Artifact 2 — Article 30 register PA-22 (g)(12) "Working-pause + honest halt notification"

**File:** `knowledge-base/legal/article-30-register.md` — PA-22 limb **(g) TOMs (Art. 32)**, new sub-entry **(12)**.

**Scope of review:**

- New TOM (12) records: the spawn-entry pause gate (reads `users.runtime_paused_at`, refuses the loop when set — no Anthropic call, no `audit_byok_use` row); the cap RPC (mig 121) returning `kill_tripped` while paused (set-never-clear; sole clearer = `POST /api/dashboard/runtime/resume`, scoped to the caller's own id); the two new `failure_reason` enum values `run_paused` / `cap_check_unavailable` as bare taxonomy strings carrying no PII; and the `cost_breaker_tripped` notification.
- The notification-minimization claim (**TR5**): payload minimized to cost aggregates (`cumulativeCents`/`ceilingCents`) + a `which_window` enum + the reason — **no prompt/response content, no third-party PII, no PII beyond the founder's own account id** (the recipient). Fired **exactly once** (memoized `step.run("notify-cost-breaker")`, replay-safe) at the single `persistFailure` site, for `{cost_ceiling_exceeded, byok_cap_exceeded, leader_max_turns_exceeded, cap_check_unavailable}` only — NEVER for `cancelled_by_operator` or `run_paused`; send failures mirror to Sentry `op=notify-cost-breaker`.

**Particular attention — resolved:**

1. **TR5 minimization is accurate against the code.** `CostBreakerNotificationPayload` in `notifications.ts` carries exactly `{type, reason, which_window, context:{cumulativeCents, ceilingCents}}`; all fields are server-generated (enum + numbers), and the recipient is the founder's own `userId`. No prompt text, no diff content, no third-party contributor PII, no email/subject reaches the payload. The register's "minimised to cost aggregates + the founder's own account id" is a faithful description. **Verdict: accurate.**
2. **Art. 6(1)(f) LIA three-part test for the cost-telemetry + notification.**
   - **(i) Purpose test — legitimate.** Enforce the spending safeguards (the 1-hour SUM requires the `audit_byok_use` telemetry) and make the halt non-silent by telling the operator their own run stopped and why. Both are legitimate interests: accountability (Art. 5(2)) for the cap enforcement, and the brand-survival interest that a runaway spend must not halt silently.
   - **(ii) Necessity test — necessary, least-intrusive.** The rolling-1h cap cannot be computed without the per-call cost rows; the halt notification is the *whole point* of the feature (a halt with no notice is the exact failure this PR removes). The payload is already minimized to server-generated aggregates + the recipient's own id — there is no less-intrusive way to tell the operator their own spend halted.
   - **(iii) Balancing test — favours the interest.** The data subject is the operator (single-user tenant-zero) receiving processing of the operator's *own* cost data at the operator's *own* account; no third-party data subject is implicated by the pause flag or the notification payload (verified: no PR-diff / contributor content in the payload). The operator reasonably expects to be told when their own BYOK spend halts. Minimal impact; no override of the data subject's interests. **Verdict: LIA passes.**
3. **Consent + retention.** No consent is required: the halt notification is a transactional service message (not marketing), delivered over already-consented `push_subscriptions` with an email fallback (PA-covered) — no ePrivacy/marketing consent trigger. Retention (Art. 5(1)(e)): the notification payload is ephemeral (delivered, not stored); the cost aggregates derive from `audit_byok_use` under PA-13's existing 90-day retention (PA-22 limb (f), unchanged); `runtime_paused_at` is a single nullable timestamp on `users`, cleared on resume — no new retention surface. **Verdict: no new consent or retention obligation.**

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| CLO agent (v1 internal counsel-review attestation authority, Soleur-as-tenant-zero posture) | 2026-07-02 | CLO-attestation gate on PR #5881 | ☑ | Approved. TR5 minimization matches the `CostBreakerNotificationPayload` shape exactly (server-generated aggregates + reason/window enums, recipient-own-id, zero third-party PII). Art. 6(1)(f) LIA passes all three prongs for cost-telemetry + notification; the data subject is the operator receiving their own data. No consent trigger (transactional message); no new retention surface (ephemeral payload; `audit_byok_use` unchanged under PA-13). `run_paused` correctly excluded from notify (double-safe: no `notify` object at the site AND `isCostBreakerReason` false). |

---

## Artifact 3 — ADR-041 Layer-0 + Notification sections + rolling-1h cap reconciliation

**File:** `knowledge-base/engineering/architecture/decisions/ADR-041-byok-cap-enforcement-model.md`.

**Scope of review (legal-accuracy lens only; architecture is the CTO's domain):**

- **Reconciliation note (P2-9):** the ADR's Layer-1 prose is corrected from the aspirational, never-implemented "daily soft $20 / hard $50 / monthly hard $500" tiered model to the *shipped* single **rolling 1-hour cumulative-spend cap per founder** (`SUM` over `now() - interval '1 hour'` vs `users.runtime_cost_cap_cents`); daily/monthly tiers deferred to #5903. This matters legally because ADR-041 is the register's authority for the cap mechanism (PA-22 (g)5 references Layer 1 per ADR-041), and the T&C §3a.5 "~1-hour" description must trace to a truthful ADR. Verified against mig 121 body: the SUM window and cap column are exactly as reconciled; no daily/monthly tier exists in the RPC. **The correction removes a live prose-vs-code drift (the known drift class from PR #4353/#4558), it does not introduce one.**
- **Layer 0 section:** spawn-entry pause gate (fail-OPEN on read error, with the Layer-1 `FOR UPDATE` re-read as the backstop rationale); RPC backstop returning `kill_tripped` while paused; set-never-clear contract (sole clearer = resume route); `cap_check_unavailable` as a distinct reason so a transient DB error is not misreported as a budget breach. All four points verified against the handler + migration + resume route.
- **Notification layer section:** single memoized `step.run("notify-cost-breaker")` before the `action_sends` UPDATE, enumerated subset, `run_paused` deliberately excluded to avoid a notification storm, payload minimization (TR5), Sentry-mirrored send failure. Verified against `notifications.ts` + the handler.

**Particular attention — resolved:**

1. **Does the reconciliation create any disclosure inconsistency?** No. After the correction, three surfaces agree: T&C §3a.5 ("rolling short-window (approximately one hour) cumulative-spend cap per account"), ADR-041 Layer-1 (rolling 1-hour `runtime_cost_cap_cents`), and mig 121 (1-hour `SUM` vs `runtime_cost_cap_cents`). The prior ADR prose, had it survived, would have contradicted the T&C's "~1-hour" language and the shipped RPC. **Verdict: reconciliation is corrective and consistency-restoring.**
2. **Honesty of the "aspirational / never implemented" framing.** The note explicitly labels the old tiers as never implemented in the RPC and defers them (#5903) rather than silently deleting the history — this is the correct Art. 5(2)-accountability posture for an ADR that other legal artifacts cite. **Verdict: honest.**

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| CLO agent (v1 internal counsel-review attestation authority, Soleur-as-tenant-zero posture) | 2026-07-02 | CLO-attestation gate on PR #5881 | ☑ | Approved on the legal-accuracy lens (architecture deferred to CTO). The rolling-1h reconciliation removes a prose-vs-code drift rather than adding one, and restores three-surface consistency (T&C ↔ ADR ↔ mig 121). Layer-0 + notification prose match the implementing files. `runtime_cost_cap_cents` is the authoritative Layer-1 mechanism; daily/monthly tiers honestly deferred to #5903. |

---

## Decision record

**Decision:** DISCHARGED. All three legal-attestation artifacts on PR #5881 are signed off under the Soleur-as-tenant-zero v1 CLO-agent attestation. `status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)`.

**Rationale:** (a) the core act — removing the false "no Jikigai-provided cost ceiling" statement and replacing it with an honest best-effort description + a fair, §11-anchored overage allocation — is legally sound and consumer-fair at the v1 threshold; (b) the Art. 6(1)(f) LIA for the cost-telemetry + notification passes all three prongs with the data subject being the operator receiving their own minimized data; (c) no new consent obligation (transactional message) and no new retention surface (ephemeral payload; `audit_byok_use` unchanged); (d) every implementation claim in the three artifacts was cross-checked against the RPC / handler / notifications / resume-route source and found faithful, and the load-bearing `TC_DOCUMENT_SHA` was verified byte-identical to the amended canonical doc.

**Attestation authority:** The CLO agent performs this v1 *internal* sign-off (not the non-lawyer operator), per the ship Phase 5.5 Counsel-Review CLO-Attestation Gate and the learning at `2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`. The operator retains an optional veto; **external** counsel re-review is reserved for the frontmatter `re_evaluation_triggers` (first arms-length operator, EEA-out, regulated industry, or a scope change listed there). This does not contradict the standing "draft material requiring professional legal review" posture — it is the defined v1 internal gate.

**Side effects:**

- The Art. 13(3) re-consent banner will fire on next login for the material `TC_VERSION` 2.3.0→2.4.0 bump (SHA-gated; SHA verified current).
- No edit to `knowledge-base/legal/compliance-posture.md` is required by this PR (no new vendor DPA / sub-processor; Anthropic + Resend + Supabase surfaces are pre-existing PA-covered). No new privacy-policy / GDPR-policy / DPD triplet edit is triggered: this PR adds no new processing *activity* — it adds a TOM (Art. 32 safeguard) and a transactional notification within the existing PA-22, disclosed in the register's (g) limb. (Recorded explicitly so a future reader does not mistake the absence of a triplet edit for a missed disclosure.)

---

## In-PR conditions

1. **Non-blocking (optional tightening).** Consider narrowing §3a.5's collective "the Web Platform pauses further automated spending on your account… you resume by clearing the pause" so it does not imply an account-wide pause for the per-run ceiling / max-turns / `cap_check_unavailable` halts (only the rolling-1h `byok_cap_exceeded` cap pauses the account and renders Resume). Suggested framing: "When the rolling spending cap trips, the Web Platform pauses further automated spending on your account and you resume by clearing the pause; other safeguards stop the individual run." This is an accuracy refinement in the operator's favor, NOT a discharge condition — the precise in-product per-reason copy in `notifications.ts` already governs the actual UX, and the discrepancy over-describes protection rather than disclaiming it.

No blocking conditions.

---

## Overall disposition

**DISCHARGED.** All three artifacts signed off; PR #5881 clears the counsel-review CLO-attestation gate. One non-blocking, operator-favorable §3a.5 wording refinement is offered for optional adoption in-PR.

---

## Post-attestation reconciliation (2026-07-03, CTO fork #5767-vs-#5919)

After this attestation, sibling PR #5919 merged an exactly-once (`v_tripped := FOUND`) rewrite of `record_byok_use_and_check_cap` to main. Per the CTO fork ruling, PR #5881's RPC-backstop migration (`121_byok_cap_kill_tripped_while_paused.sql`) was **deleted**, and the spawn-entry pause gate was made **fail-closed** (a `users`-read error now halts via `run_paused` instead of proceeding).

**Legal impact: none.** The verdicts above are UNCHANGED. The working-pause guarantee the ToS §3a.5 / Article 30 PA-22(g)(12) disclosures rest on is *preserved and strengthened* (fail-closed is more protective, not less); the `cost_breaker_tripped` payload minimization (TR5) is untouched; no lawful-basis, consent, retention, or transfer analysis depended on the RPC backstop. Cross-references in this audit to "migration 121 (kill_tripped-while-paused)" now read as the entry-gate guard; the SHA/`TC_VERSION`/disclosure findings are unaffected.
