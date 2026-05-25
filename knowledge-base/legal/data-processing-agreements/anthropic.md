---
vendor: Anthropic PBC
role: independent controller/processor under operator BYOK
status_snapshot_date: 2026-05-25
register_activity_refs: [PA-22]
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

## Re-evaluate when

- Anthropic publishes a revised DPA or revises sub-processor list.
- Operator signs the Zero-Retention amendment (update this file).
- Soleur takes on data subjects beyond the operator (cohort onboarding).

## Refs

- `knowledge-base/legal/article-30-register.md` — PA-22 entry + Vendor
  Mapping row.
- ADR-040 — Anthropic-SDK inside Inngest leader loop topology.
- ADR-041 — BYOK cap enforcement model.
- PR #4379 — PR-B Anthropic leader loop (PA-22 substrate).
