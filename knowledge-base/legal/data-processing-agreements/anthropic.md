---
vendor: Anthropic PBC
role: independent controller/processor under operator BYOK; processor for the Jikigai-keyed email-triage summarizer (PA-27)
status_snapshot_date: 2026-06-11
register_activity_refs: [PA-22, PA-27]
zero_retention_amendment: unsigned
---

# Anthropic PBC — DPA snapshot

Cross-reference to the Article 30 Vendor Mapping row in
`knowledge-base/legal/article-30-register.md` (line ~412) and to
Processing Activity 22 (autonomous AI leader-prompt runtime under
operator BYOK).

## DPA + transfer mechanisms

| Field | Value |
|---|---|
| **DPA mechanism** | AUTO via Anthropic Commercial Terms § C |
| **DPA effective date** | 2025-02-24 |
| **Transfer mechanisms** | EU-US DPF + SCCs M2+3 + UK IDTA + Swiss Addendum |
| **Region (data processed)** | US |
| **Anthropic Commercial Terms URL** | https://www.anthropic.com/legal/commercial-terms |
| **Anthropic DPA URL** | https://www.anthropic.com/legal/dpa |
| **Anthropic Sub-Processors list** | https://www.anthropic.com/legal/subprocessors |

## Zero-Retention amendment

**Status at PR-B (#4379) merge: UNSIGNED.**

Anthropic's default Commercial Terms include a 30-day API request /
response retention window for safety review. The Zero-Retention
amendment, signed via the Anthropic Console, opts the operator's
Workspace out of that retention.

PR-B's PA-22 (f) records "unsigned at PR-B merge" and tracks the
amendment via:

1. Operator step (pre or post-merge): visit Anthropic Console →
   Workspace Settings → Privacy → Zero-Retention amendment, sign.
2. Operator updates PA-22 (f) replacing "unsigned at PR-B merge" with
   the signed date.
3. Operator updates this file's `zero_retention_amendment` frontmatter
   field to `signed` + adds a `zero_retention_amendment_date` field.

Until signed: the dashboard surfaces a one-time banner to that effect
(scope of Non-Goal #2, filed as a follow-up issue).

## Activities in scope

- **PA-22** — Autonomous AI leader-prompt runtime (`agent.spawn.requested`
  Inngest function). Per-turn `anthropic.messages.create` calls under
  the operator's BYOK lease. 5 action classes: `engineering.pr_review_pending`,
  `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`,
  `knowledge.kb_drift`.
- **PA-27** — Email-triage summarization (#5103,
  `feat-operator-inbox-delegation`). One `messages.create` call per
  **non-statutory** inbound email to `ops@soleur.ai`, under the
  **Jikigai-keyed** `ANTHROPIC_API_KEY` (NOT operator BYOK — distinct from
  PA-22's lease model). Payload: subject + sender + body of third-party
  mail, hard-truncated to 64 KiB (`MAX_SUMMARIZE_BODY_BYTES`) and
  sanitized (`sanitizePromptString`) before the call
  (`server/email-triage/summarize.ts`). Statutory-class mail and probe
  mail NEVER reach Anthropic (deterministic pre-LLM fast-path). Anthropic's
  default 30-day API request/response retention applies until the
  Zero-Retention amendment is signed (see above) — disclosed in Article 30
  PA-27 §(d)/(f) and Privacy Policy §4.13. Volume bounds: Inngest throttle
  60/h + daily LLM-call ceiling 200.
- Pre-PR-B Jikigai-keyed surfaces (out of scope of this register file's
  PA-22 framing; see Vendor Mapping Notes column): `claude-code-action`
  CI + compound-promotion-loop #2720.

## TOMs relied on (Art. 32)

Soleur's TOMs that bound Anthropic-side risk under PA-22:

- Per-turn BYOK lease (ALS-scoped; cannot escape).
- $2.00 per-spawn cost ceiling + 8-turn backstop (ADR-041).
- PII-scrub at prompt assembly (email redaction; control-char strip).
- Prompt caching ON (`cache_control: ephemeral`) reduces cost AND
  reduces the per-call payload sent to Anthropic post-warm-cache.
- LEADER_CLASSES_DISABLED Doppler-config kill switch for any class
  surfacing quality / safety issues.

TOMs that bound Anthropic-side risk under **PA-27** (email triage):

- Deterministic statutory fast-path BEFORE any LLM — deadline-bearing
  third-party mail (DSAR / breach / service-of-process / regulator) never
  transits Anthropic.
- 64 KiB body truncation + `sanitizePromptString` before the call.
- Closed `MAIL_CLASS_ALLOWLIST` on output — the model structurally cannot
  write statutory provenance or the probe class.
- Read-only, no tools, untrusted-data framing; summary rendered as plain
  text only.
- Inngest throttle (60/h) + daily LLM ceiling (200) bound
  attacker-controlled spend and egress volume.

## Residual risks — named per the §(g) honest-admission precedent (#4954)

Admitted to the CLO bar as residual risks, not mitigated claims:

1. **Prompt injection via inbound email content (PA-27).** Anyone on the
   internet can mail `ops@soleur.ai` adversarial instructions; the model
   processes that content. The binding is read-only/no-tools and the output
   class is allowlist-coerced, so the blast radius is bounded to a
   **misleading summary** — but a distorted summary CAN cause the operator
   to mis-prioritise or misread an email. Mitigations (untrusted-data
   framing, plain-text rendering, server-uuid-only deep links, Proton
   keep-copy as the recovery original) are named as mitigations, not as a
   safety guarantee. Becomes unacceptable (full re-assessment required) if
   any write/act authority is ever attached to the pipeline (#4671/#4672).
2. **Art. 9 content surviving into the persisted summary (PA-27).** The
   system prompt instructs omission of special-category details; **the model
   can ignore the instruction**, and the WORM one-time-set rule makes the
   persisted summary immutable through ordinary writes. Correction path is
   Art. 17 row deletion via the GUC-gated RPCs. Recorded as accepted
   residual (a) in the DPIA screening memo
   (`knowledge-base/legal/audits/2026-06-11-dpia-screening-operator-inbox-triage.md`).
3. **30-day default retention until Zero-Retention is signed (PA-22 + PA-27).**
   Third-party mail content sent under PA-27 sits in Anthropic's default
   safety-review retention window; the amendment-signing operator step is
   tracked above and in PA-22 (f).

## Re-evaluate when

- Anthropic publishes a revised DPA or revises sub-processor list.
- Operator signs the Zero-Retention amendment (update this file).
- Soleur takes on data subjects beyond the operator (cohort onboarding).

## Refs

- `knowledge-base/legal/article-30-register.md` — PA-22 entry + Vendor
  Mapping row.
- ADR-042 — Anthropic-SDK inside Inngest leader loop topology.
- ADR-041 — BYOK cap enforcement model.
- PR #4379 — PR-B Anthropic leader loop (PA-22 substrate).
