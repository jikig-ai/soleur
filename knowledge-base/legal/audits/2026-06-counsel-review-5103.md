---
title: "Counsel review audit — #5103 (operator inbox delegation: PA-27 AI-assisted email triage legal bundle)"
type: counsel-review
date: 2026-06-11
issue: 5103
pr: 5125
tracking_issue: 5150
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1; external counsel re-review on the frontmatter triggers)"
signed_off_at: 2026-06-11
signed_off_by: "clo agent (Soleur legal domain leader) — reviewing authority for v1 per the agent-native company model; external counsel re-review reserved for the triggers below"
re_evaluation_triggers: "First arms-length user (any expansion beyond the single operator — cohort onboarding, customer inboxes, any non-operator data subject as triage-item owner) OR any address expansion beyond ops@soleur.ai OR any send/reply/act authority attached to the pipeline (#4671/#4672 boundary) OR first materialised Art. 9 leak into a persisted summary OR any data subject whose habitual residence raises an EEA-out transfer question not covered by the disclosed DPF/SCCs mechanisms OR any sender or processing context belonging to a regulated industry (healthcare, finance, legal-services)"
---

# Counsel review audit — #5103 (PA-27 operator inbox triage legal bundle)

> **STATUS: SIGNED-OFF — reviewed and attested by the `clo` agent on 2026-06-11.**
> The `clo` agent (Soleur legal domain leader) is the reviewing authority for the
> v1 Soleur-as-tenant-zero posture — this is an agent-native company; legal review
> is a CLO-agent function, not a task for the non-lawyer operator. The agent
> cross-checked every implementation-detail claim against migration 102 (table,
> WORM trigger, `set_email_triage_status`, `purge_email_triage_items`,
> `anonymise_email_triage_items`, `processed_resend_events`, `probe_tokens`),
> `server/email-triage/summarize.ts`, `server/inngest/functions/email-on-received.ts`,
> `server/inngest/functions/cron-email-ingress-probe.ts`,
> `app/api/webhooks/resend-inbound/route.ts`, `server/account-delete.ts` step 3.97,
> `server/dsar-export-allowlist.ts`, `server/sensitive-keys.ts`, and
> `lib/email-triage/statutory-rules.ts`, resolved the five substantive judgment
> calls, and **discharged the gate with one in-PR condition (applied this
> session — see below)**. External counsel re-review is reserved for the
> frontmatter triggers. The full agent verdict is recorded per-artifact below.

This audit is the load-bearing evidence for the counsel-review gate on PR #5125
(issue #5103, `feat-operator-inbox-delegation`). The PR ships the third
multi-source ingress: inbound email to `ops@soleur.ai` is Sieve-forwarded
(forward-AND-keep — the Proton mailbox stays the durable original) to Resend
Inbound, delivered as a svix-verified metadata-only webhook, and triaged by an
Inngest pipeline — a deterministic, metadata-first statutory fast-path runs
BEFORE any LLM; everything else gets a read-only Anthropic summary under a
structural parse-and-discard contract (`email_triage_items` has no body
column). The legal grain change: **the first register activity whose primary
data subjects are involuntary** (inbound senders, and persons mentioned in
their mail, who have no account or contract with the processing).

Pre-attestation pipeline already passed: (a) generation-time grep-validation
(63 checks); (b) legal-compliance-auditor cross-consistency pass (1 Critical
fixed — Inngest event-store retention posture corrected repo-wide, including
the prior uncorroborated "~24h"/"30-day rolling" figures; SHA re-pins green);
(c) 12-agent review incl. security-sentinel legal-framing cross-check and a
code-quality drift check; (d) review-driven LIA correction (erasure prose no
longer claims a per-request targeted-delete RPC — verified below against the
parameterless `purge_email_triage_items`).

**Brand-survival threshold:** `single-user incident`.

---

## Artifact 1 — Article 30 register: Processing Activity 27 + Resend/Anthropic vendor rows

**File:** `knowledge-base/legal/article-30-register.md` (canonical; no Eleventy mirror; not SHA-tracked)

**Scope of review:**

- New PA-27 with all Art. 30(1) limbs: purpose (deterministic statutory
  escalation + read-only summarization + synthetic probe), data subjects
  (involuntary senders / persons mentioned / operator, with the Art. 14(5)(b)
  posture stated at the limb), data categories (exhaustive at-rest column list
  + in-transit surfaces), special categories (named residual, not denied),
  lawful basis (Art. 6(1)(f) + LIA pointer), recipients (Resend, Anthropic,
  Supabase, plus the self-hosted Inngest event store framed correctly as a
  PII *surface*, not a recipient), transfers (DPF + SCCs per vendor),
  retention (7d/365d/accountability-period with the predicate-level carve-out
  named), and 11 enumerated TOMs.
- Resend vendor row split into two roles (outbound transactional + inbound
  custody with the 30-day/no-deletion-API Chapter V finding); Anthropic row
  scope-amended for the Jikigai-keyed PA-27 summarizer.

**Verification against implementation (all claims checked, all hold):**

- **Column list is exhaustive and exact** vs migration 102 (`user_id`,
  `claim_key`, `message_id`, `resend_email_id`, `sender`, `subject`,
  `summary`, `mail_class`, `statutory_class`, `rule_id`, `status`,
  `status_changed_at`, `acknowledged_at`, `received_at`,
  `received_at_source`, `created_at`); **no body column exists** (102:59-94).
- **WORM mutation matrix prose matches the trigger body** (102:139-227):
  hard-frozen set, one-time-set set, status-GUC gate (`set_email_triage_status`
  one-way `new → acknowledged|archived`, `auth.uid()`-pinned, search_path
  pinned per cq-pg-security-definer-search-path-pin-pg-temp), DELETE only
  under the purge GUC, `user_id`/`sender` NOT NULL→NULL only under the
  anonymise GUC (re-identification rejected even under the GUC).
- **Retention predicates match** `purge_email_triage_items` (102:331-389):
  probe 7d, non-statutory 365d, and the `statutory_class IS NULL` WHERE
  carve-out IS the statutory retention guarantee, exactly as disclosed;
  `probe_tokens` 7d; `processed_resend_events` 90d pg_cron sweep.
  Purge-first step order confirmed in `cron-email-ingress-probe.ts` (step 1).
- **Art. 9 prompt instruction quoted verbatim** matches `SYSTEM_PROMPT` in
  `server/email-triage/summarize.ts:49-59` character-for-character.
- **`MAIL_CLASS_ALLOWLIST`** = `vendor|billing|security|newsletter|legal-review|other`
  (excludes all statutory classes and `probe`); out-of-allowlist coerces to
  `other` + Sentry mirror — as disclosed (summarize.ts:32-85).
- **64 KiB truncation** (`MAX_SUMMARIZE_BODY_BYTES`), `sanitizePromptString`,
  throttle `{ limit: 60, period: "1h" }`, `EMAIL_TRIAGE_DAILY_LLM_CEILING = 200`,
  and the `"deferred — volume cap"` sentinel all verified in code.
- **Parse-and-discard:** the fused `fetch-sanitize-summarize` step returns only
  `{summary, mailClass, ...}` discriminants — the body is never a `step.run`
  return value or event field (email-on-received.ts:424-498).
- **Webhook TOM:** 413 (256 KiB) before verify, fail-closed 500 on unset
  secret BEFORE svix is touched, 401 on missing headers/verify-throw,
  raw-body HMAC, `processed_resend_events` dedup — all verified in
  `app/api/webhooks/resend-inbound/route.ts`.
- **DSAR:** `email_triage_items: { ownerField: "user_id", article: "15+20" }`
  verified in `server/dsar-export-allowlist.ts:288`.
- **Observability scrub:** `subject`/`sender`/`from`/`to` verified in
  `server/sensitive-keys.ts:79-82`.

**Required amendment (APPLIED this session):** PA-27 §(a) cited the statutory
rule registry at `server/email-triage/statutory-rules.ts`; the module lives at
`lib/email-triage/statutory-rules.ts` (relocated at implementation time
because client surfaces import it). Path corrected. This is the known
prose-vs-code drift class (PR #4353/#4558 precedent) — path-only; every
substantive claim about the registry (rule ids, classes, due rules, excerpts,
first-match priority order) verified accurate.

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-06-11 | PR #5125 / Task spawn | ☑ | See **CLO Attestation Record** below. |

---

## Artifact 2 — Legitimate Interest Assessment (Art. 6(1)(f) three-part test)

**File:** `knowledge-base/legal/legitimate-interest-assessments/2026-06-11-operator-inbox-triage-lia.md`

**Scope of review:**

- Purpose / Necessity / Balancing in dedicated H2 sections; ICO + CNIL + WP29
  06/2014 guidance cited; involuntary-data-subject balancing (the decisive
  feature) addressed head-on; Art. 14(5)(b) posture; Art. 17 path with the
  Art. 17(3)(b) override; four outstanding counsel-review items; pinned
  re-evaluation triggers.

**Particular attention resolved:**

1. **Three-limb adequacy.** Purpose is specific/explicit/legitimate (one
   address; persisted output limited to summary + envelope metadata; stated in
   advance across LIA/PA-27/DPIA/Privacy §4.13). Necessity credibly rejects
   four less-intrusive alternatives — including the honest rejection of the
   status quo (the materialized unread-quota-warning incident) and of the
   strictly-larger mailbox-credential surface. Balancing follows the WP29
   §III.3 factor structure, does not claim away the open-address Art. 9
   residual, and correctly finds no Art. 22 trigger (summary + category for
   one human; no legal/similarly-significant automated effect). **ADEQUATE.**
2. **Erasure prose vs code (review-driven correction).** The LIA now states
   no per-request targeted-delete RPC exists in v1 and that the purge function
   is parameterless and age-based — verified exact against migration 102
   (`purge_email_triage_items()` takes no arguments; deletion outside the
   sweep is an operator-run SQL action under the purge GUC, documented
   per-request). **ACCURATE.**

**Required amendment (APPLIED this session):** registry path corrected
(`server/` → `lib/email-triage/statutory-rules.ts`), same drift as Artifact 1.

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-06-11 | PR #5125 / Task spawn | ☑ | See **CLO Attestation Record** below (B1, B2, B4). |

---

## Artifact 3 — DPIA screening memo

**File:** `knowledge-base/legal/audits/2026-06-11-dpia-screening-operator-inbox-triage.md`

**Scope of review:**

- Art. 35(3)(a)–(c) + WP248 nine-criteria screening; conclusion that a full
  DPIA is not required at single-operator scale; three named accepted
  residuals ((a) Art. 9-in-summary, (b) prompt-injection-distorted summaries,
  (c) Resend 30-day no-delete window); re-screening triggers incl. the
  hard rule that any write/act authority forces a full DPIA-grade
  re-assessment.

**Verdict reasoning:** the screening is methodologically correct — it engages
the two WP248 criteria that genuinely apply (involuntary subjects; innovative
technology), cites the WP248 "in most cases two criteria" heuristic rather
than asserting zero engagement, and the "classifies emails, not people / no
Art. 22 effect" distinction is accurate against the implementation (the LLM
structurally cannot write `statutory_class` or `probe`; no agent write tool
exists — FR9 boundary verified: no acknowledge/write tool in
`server/email-triage-tools.ts` scope reviewed by the 12-agent pass). The §3
Inngest event-store correction ("no automatic deletion", with the ~24h figure
correctly re-attributed to the event-id dedup window) is corroborated by the
retention-flag-free `inngest start` ExecStart and is consistently propagated.
**The screening conclusion is APPROVED at the stated scale**; trigger (1)
(any non-operator item owner) is the binding boundary of this approval.

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-06-11 | PR #5125 / Task spawn | ☑ | See **CLO Attestation Record** below (B5). |

---

## Artifact 4 — Statutory Response Catalog (new)

**File:** `knowledge-base/legal/statutory-response-catalog.md`

**Scope of review:**

- Four sections in registry priority order (breach > service-of-process >
  dsar > regulator), each with anchor, obligation, period, and first-response
  checklist; maintenance contract binding the catalog to the code registry.

**Verification:** every `catalogExcerpt` quote matches the registry string
**verbatim**; every `<a id>` anchor matches the registry `catalogAnchor`
values; every `dueRule` label quoted exactly (`72 hours` / `calendar-month` /
`verify the instrument's own deadline`); the calendar-month clamp description
(Jan 31 → Feb 28/29) matches `computeDueDate`; the T-7d / daily-from-T-2d
re-pin claim matches `cron-email-ingress-probe.ts`; the
"`purge_email_triage_items` only deletes rows where `statutory_class IS NULL`"
claim matches the migration predicate. Legal content of the excerpts is
correct: Art. 33 72-hours-from-awareness with the received_at-as-conservative-
proxy caveat stated (not hidden); Art. 12(3) calendar-month with the 2-month
extension discipline; instrument-stated deadlines for service-of-process and
regulator mail with the one-month default explicitly demoted to a safety net.
The checklists correctly push service-of-process and non-routine regulator
correspondence to **external counsel** — outside the operator-attestation
envelope.

**Required amendment (APPLIED this session):** three registry-path references
corrected (`server/` → `lib/email-triage/statutory-rules.ts`) — frontmatter
`related`, intro, and the Maintenance consistency contract. The consistency
contract pointing at a non-existent path would have silently defeated its own
purpose.

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-06-11 | PR #5125 / Task spawn | ☑ | See **CLO Attestation Record** below. |

---

## Artifact 5 — Anthropic DPA snapshot scope amendment

**File:** `knowledge-base/legal/data-processing-agreements/anthropic.md`

**Scope of review:**

- Frontmatter role/refs extended to PA-27; PA-27 surface description
  (Jikigai-keyed, NOT operator BYOK — correctly distinguished from PA-22's
  lease model); PA-27 TOM list; three residual risks named per the §(g)
  honest-admission precedent (#4954).

**Verdict reasoning:** all payload claims verified (subject + sender +
truncated/sanitized body; one `messages.create` per non-statutory email;
statutory/probe mail structurally pre-LLM). The "statutory-class mail NEVER
reaches Anthropic" claim is **provenance-true**: `statutory_class` non-NULL ⟺
deterministic-path origin, so anything bearing the class never transited the
LLM. A recall-miss statutory email (keywords matching neither metadata nor
body patterns) could reach the summarizer — but it is then not
statutory-classed, the registry deliberately errs broad ("recall over
precision"), and the DPIA/LIA do not overclaim detection completeness.
Non-blocking observation only. The 30-day-default-retention residual (3) is
correctly framed as now ALSO load-bearing for involuntary third-party data
subjects, which properly raises the priority of the Zero-Retention amendment
operator step (PA-22 (f) / posture Active Items (ii)).

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-06-11 | PR #5125 / Task spawn | ☑ | See **CLO Attestation Record** below (B3). |

---

## Artifact 6 — compliance-posture.md (bundle entry + vendor rows + PA-27 Active Items)

**File:** `knowledge-base/legal/compliance-posture.md`

**Scope of review:**

- 2026-06-11 bundle changelog comment; document-table updates (Privacy/GDPR/
  DPD dates; new LIA + catalog rows); Resend + Anthropic vendor-DPA-row scope
  amendments; new PA-27 Active Items row with four tracked items
  ((i) Resend window, (ii) Zero-Retention amendment, (iii) DPIA residuals
  scale-bound, (iv) Inngest event-store purge bound → **#5150, verified OPEN**).

**Verdict reasoning:** the posture row is the correct living-status home for
the accepted vendor-window posture; the Inngest correction provenance
("corrected 2026-06-11 from ~24h … DPD §2.3(o) corrected in lockstep") is
accurate against the shipped DPD diff. New KB artifacts retain
`Draft (counsel review pending)` status in the document table — consistent
with the register's own row and the LinkedIn-LIA precedent: this audit is the
v1 *internal* attestation; the external-counsel pendency the table records is
discharged only by the frontmatter re-evaluation triggers.

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-06-11 | PR #5125 / Task spawn | ☑ | See **CLO Attestation Record** below. |

---

## Artifact 7 — Privacy Policy §4.13 + §5.9 (the Art. 14(5)(b) public notice of record)

**Files:** `docs/legal/privacy-policy.md` (canonical) + `plugins/soleur/docs/pages/legal/privacy-policy.md` (Eleventy mirror)

**Scope of review:**

- §4.13 is the **public notice of record** on which the entire Art. 14(5)(b)
  posture rests. Checked against the WP260/Art. 14(1)-(2) information
  catalogue: controller identity reachable (policy header + rights contact
  <legal@jikigai.com>), purposes + lawful basis (Art. 6(1)(f), LIA referenced),
  categories of data (summary + enumerated envelope metadata; explicit
  body-never-stored statement), recipients (Resend with the 30-day/no-delete
  window in plain language — "that copy expires rather than being deletable
  on request"; Anthropic non-statutory-only; Supabase; the self-hosted event
  store with its no-auto-deletion honesty), transfers (DPF + SCCs), retention
  (7d/365d/accountability period), rights (Arts. 15–21 + the Art. 17(3)(b)
  exception WITH the commitment to tell the data subject when it is applied —
  Art. 12(1) conformant), and the Art. 22 negative statement.
- §5.9 Resend second-role bullet consistent with §4.13 and the DPD row.
- Lay-readability: the "(or are mentioned in an email sent to it)" opener
  puts the involuntary subject on notice in the first paragraph — Art. 12
  clear-and-plain standard met.

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-06-11 | PR #5125 / Task spawn | ☑ | See **CLO Attestation Record** below (B2). |

---

## Artifact 8 — GDPR Policy §3.10

**Files:** `docs/legal/gdpr-policy.md` (canonical) + `plugins/soleur/docs/pages/legal/gdpr-policy.md` (Eleventy mirror)

**Scope of review:**

- §3.10 condenses the three-limb test accurately (no drift from the LIA's
  conclusions); states the Art. 14(5)(b) posture; rights-exercise paragraph
  routes Arts. 15–21 to <legal@jikigai.com> with the per-request, documented
  Art. 17(3)(b) application. No new data-subject right or exercise path is
  introduced that lacks an entry; the involuntary-sender erasure path is the
  gated-RPC family disclosed consistently across all surfaces.

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-06-11 | PR #5125 / Task spawn | ☑ | See **CLO Attestation Record** below. |

---

## Artifact 9 — Data Protection Disclosure §2.3(aa) + §4.2 rows + §2.3(o) lockstep correction

**Files:** `docs/legal/data-protection-disclosure.md` (canonical) + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Eleventy mirror)

**Scope of review:**

- §2.3(aa): the most complete public surface — every implementation claim
  verified (column enumeration, WORM/RPC erasure framing "the same gate that
  makes the ledger trustworthy makes erasure auditable", TOM list, Art. 22
  negative, sub-processor set); consistency sentence extended to include (aa).
- §4.2: Resend row dual-role amendment + new Anthropic §2.3(aa) row with the
  correct lawful-basis column (Art. 6(1)(f) + LIA pointer) — the DPD now has
  two Anthropic-relationship framings (independent-controller BYOK vs
  processor for PA-27) and keeps them distinct.
- §2.3(o) **lockstep correction**: the prior "30-day rolling SQLite window"
  claim for the self-hosted Inngest store was uncorroborated; corrected to
  no-automatic-deletion in the same PR that relies on the corrected fact for
  PA-27 — the right repo-wide-consistency behavior (this was the bundle
  audit's 1 Critical, verified fixed).

| Counsel/CPO | Date | Channel | Sign-off | Substantive comments |
|---|---|---|---|---|
| clo agent (Soleur legal domain leader) | 2026-06-11 | PR #5125 / Task spawn | ☑ | See **CLO Attestation Record** below (B3). |

---

## CLO Attestation Record (2026-06-11, clo agent)

| Artifact | Verdict | Note |
|---|---|---|
| 1 — Art-30 PA-27 + vendor rows | APPROVE-WITH-AMENDMENT | Every limb verified against migration 102 + pipeline code; column list exhaustive-exact; retention predicates match; Art. 9 prompt verbatim. Amendment **applied**: registry path `server/` → `lib/email-triage/statutory-rules.ts`. |
| 2 — LIA | APPROVE-WITH-AMENDMENT | Three limbs adequate (B1); erasure prose matches the parameterless purge RPC post-correction; Art. 14(5)(b) + 17(3)(b) analyses sound (B2, B4). Amendment **applied**: same path fix. |
| 3 — DPIA screening memo | APPROVE | Screening methodology correct; no-full-DPIA conclusion approved at single-operator scale; residuals honestly named; trigger (1) is the binding boundary. |
| 4 — Statutory catalog | APPROVE-WITH-AMENDMENT | All excerpts/anchors/labels verbatim vs registry; legal content of the four obligations correct; external-counsel hand-offs correctly placed. Amendment **applied**: 3 path fixes (incl. the consistency contract itself). |
| 5 — Anthropic DPA snapshot | APPROVE | PA-22/PA-27 key-model distinction correct; residuals per #4954 precedent; "never reaches Anthropic" is provenance-true (non-blocking recall-miss observation noted). |
| 6 — compliance-posture | APPROVE | PA-27 Active Items row correct; #5150 verified OPEN; draft-status retention for KB artifacts consistent with house precedent. |
| 7 — Privacy §4.13 + §5.9 | APPROVE | The Art. 14(5)(b) notice of record satisfies the WP260 information catalogue; Art. 12 clear-and-plain met; Art. 17(3)(b) notice-on-application commitment present. |
| 8 — GDPR Policy §3.10 | APPROVE | Faithful condensation of the LIA; no missing rights path. |
| 9 — DPD §2.3(aa) + §4.2 + §2.3(o) | APPROVE | Most complete surface; all claims verify; §2.3(o) lockstep correction is the right repo-wide-consistency behavior. |
| SHA pins (`legal-doc-shas.ts`) | VERIFIED | `legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts`: 19/19 green this session. Non-T&C edits → no `TC_VERSION` bump (correct). |

**Substantive judgment calls:**

- **B1 — Art. 6(1)(f) adequacy: ADEQUATE.** The interest is real and dual
  (operational mailbox function + statutory response clocks, the latter
  directly protective of requesting data subjects); necessity rejects four
  alternatives on credible grounds; balancing engages the involuntary-subject
  problem honestly. Art. 6(1)(c) is not the better basis — no law mandates
  AI triage; the statutory purpose is correctly placed as a balancing weight,
  not the basis. Art. 22 correctly ruled out (advisory summary for one human;
  the LLM structurally cannot create statutory effect).
- **B2 — Art. 14(5)(b) posture: DEFENSIBLE at v1 scale; the bundle's weakest
  point, correctly flagged as counsel item 1.** For persons merely *mentioned*
  in mail, provision is impossible (no contact details held) — clean 14(5)(b).
  For *senders*, Jikigai holds the address, so notice is possible in
  principle; the posture therefore rests on disproportionate effort plus the
  intrusiveness of a contact whose only purpose is the notice. Given WP260's
  narrow-construction caution, this holds at single-operator volume with
  minimal persisted data and a §4.13 notice that satisfies the
  "appropriate measures … including making the information publicly
  available" limb — and the LIA already pins the proportionality threshold
  (auto-acknowledgment footer) at which per-sender notice becomes owed.
  External-counsel confirmation remains attached to the first-arms-length
  trigger.
- **B3 — Retention disclosures: TRUE TO IMPLEMENTATION, vendor windows
  disclosed not hidden.** 7d/365d/accountability-period verified at the
  predicate level. Resend 30-day/no-deletion-API disclosed at all six
  surfaces (register vendor row, PA-27 (d)/(f), posture row, Privacy
  §4.13/§5.9, DPD §2.3(aa)/§4.2, DPIA residual (c)) with the Art. 28(3)(g)
  tension named (LIA counsel item 3) rather than papered over. Inngest
  event-store no-auto-deletion corrected repo-wide (incl. the pre-existing
  DPD §2.3(o) claim) and bounded by OPEN tracking issue #5150 — the
  disclose-then-remediate sequence is correct; #5150 must not silently close
  without the purge bound landing.
- **B4 — Art. 17 path: SOUND.** `anonymise_email_triage_items` verified
  (NULLs `user_id` + `sender` under the anonymise GUC; service_role-only;
  wired fail-closed at account-delete step 3.97 — aborts deletion rather than
  FK-blocking with PII left behind). The Art. 17(3)(b) override is properly
  scoped: statutory rows only, enforced at the purge predicate (not by
  policy), with sender-anonymisation named as the less-intrusive partial
  measure and per-request documentation required. The post-review LIA
  correction (no per-request delete RPC claimed) closes the last prose/code
  gap.
- **B5 — Art. 9 residual: HONESTLY NAMED.** The prompt instruction is quoted
  verbatim and consistently framed as "a claim, not a mechanism" across
  register / DPIA / DPA snapshot / LIA; the WORM-immutability consequence of
  a leak is stated rather than hidden; the correction path (GUC-gated purge)
  is real. First materialised leak is a pinned re-screening trigger.

**Overall disposition: DISCHARGED.** One in-PR condition (statutory-rules
registry path correction across catalog ×3, LIA ×1, register ×1) **applied
this session** by the attesting agent. Non-blocking observation (recall-miss
framing, Artifact 5) requires no text change. No prose misstates the
implementation after the path fix; no lawful basis is weak enough to block at
the v1 Soleur-as-tenant-zero scale. KB artifacts retain
`draft-requires-counsel-review` status pending the external-counsel triggers,
per house precedent — that status is NOT a discharge blocker.

---

## Post-sign-off actions

1. Commit the five path-fix edits + this audit file in PR #5125 (the
   attesting agent does not commit; the orchestrator lands them).
2. `gh pr ready 5125`, then merge per the project's gated merge flow. #5103
   is Ref (not auto-close).
3. Keep #5150 OPEN until the Inngest event-store purge bound is implemented
   or a periodic-maintenance bound is confirmed and recorded in PA-27
   §(d)/(f) + DPD §2.3(o)/(aa) + posture Active Items (iv).
4. On the Anthropic Zero-Retention amendment signing (operator step, PA-22
   (f)): update PA-27 §(d)/(f), the Anthropic DPA snapshot residual 3, LIA
   Necessity §6, Privacy §4.13, and DPD §4.2 in lockstep.

---

## Re-evaluation triggers

External counsel re-review of all artifacts above is triggered by ANY of:

1. **First arms-length user / any expansion beyond the single operator** —
   cohort onboarding, customer inboxes, or any non-operator data subject as
   triage-item owner. Re-weights the WP248 "large scale" and "imbalance"
   factors immediately (DPIA trigger (1)) and re-opens the Art. 14(5)(b)
   proportionality analysis (B2).
2. **Any address expansion beyond `ops@soleur.ai`** — the LIA's purpose limb
   is scoped to one operational address.
3. **Any send/reply/act authority attached to the pipeline** (#4671/#4672
   boundary) — converts DPIA residual (b) from "misleading text" to "induced
   action"; full DPIA-grade re-assessment required.
4. **First materialised Art. 9 leak into a persisted summary** — re-assess
   the instruction-only mitigation (DPIA residual (a)).
5. **EEA-out transfer question** not covered by the disclosed DPF/SCCs
   mechanisms for Resend/Anthropic.
6. **Any regulated-industry context** (healthcare, finance, legal-services)
   among senders or processing purposes — sector obligations exceed the v1
   attestation framework.

These extend the canonical set from `2026-05-counsel-review-{4289,4353,4558}.md`
with the involuntary-data-subject-specific triggers (1)–(4).
