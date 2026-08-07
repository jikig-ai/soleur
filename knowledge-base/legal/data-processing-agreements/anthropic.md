---
vendor: Anthropic PBC
role: independent controller/processor under operator BYOK; processor for the Jikigai-keyed email-triage summarizer (PA-27), for the Anthropic-egressing Inngest function fleet (PA-31), for the community observation and republication activity's collection limb (PA-32), for the Jikigai-keyed Anthropic API surface in GitHub Actions CI (PA-33), and — NEW 2026-08-06 (#7331) — as JIKIGAI'S SUB-PROCESSOR for operator-assisted alpha-tester runs (PA-34 controller limb; Art. 30(2) record P-1 processor limb), which is the first engagement where Anthropic sits downstream of Jikigai in a chain whose ultimate controller is a THIRD PARTY rather than the operator
status_snapshot_date: 2026-08-06
register_activity_refs: [PA-22, PA-27, PA-31, PA-32, PA-33, PA-34]  # Art. 30(1) gap for the in-repo fleet + CI surface closed 2026-07-31 (#7100); the 2026-07-30 INCOMPLETE marker is retired. 2026-08-01 at review: PA-33's predicate widened repo-wide after a Jikigai-keyed egress in the sibling repo jikig-ai/operator-digest was found outside it; now PA-33 member (7), registered from committed source with asset-vs-deployed drift named as a residual. 2026-08-06 (#7331): PA-34 added, plus record P-1 in the separate knowledge-base/legal/article-30-2-register.md
zero_retention_amendment: unsigned  # FIRED CONSEQUENCE 2026-08-06: an alpha tester's repository content egressed under the Jikigai key, so the 30-day retention window now attaches to a THIRD PARTY's data, not only the operator's. Session of 2026-08-06 expires ~2026-09-05.
---

# Anthropic PBC — DPA snapshot

Cross-reference to the Article 30 Vendor Mapping row in
`knowledge-base/legal/article-30-register.md` (§ "Vendor / Sub-Processor Mapping") and to
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
- **Enumeration corrected 2026-07-30 (#7086), then re-measured and superseded
  2026-07-31 (#7100).** The list above was non-exhaustive: the
  **Anthropic-egressing Inngest function fleet** is the *dominant* Jikigai-keyed
  Anthropic surface and was never named. It is now **PA-31**, whose membership is
  a dated 21-module snapshot.

  The 2026-07-30 figures were themselves inaccurate and are corrected here rather
  than restated. Measured on branch `feat-one-shot-7100-art30-eval-fleet-register` 2026-07-31, with the commands
  recorded in the PA-31 LIA's provenance section *(tree corrected 2026-07-31 at review: this read
  "on `main`", while the provenance section it cites states the measurements were run on the branch —
  the vendor record named a tree its own cited evidence disclaims)*:

  | 2026-07-30 claim | Measured | Note |
  |---|---|---|
  | 15 crons call `spawnClaudeEval` | **13** of the 18 **crons** call `spawnClaudeEval`; **2** more (`cron-daily-triage`, `cron-follow-through-monitor`) call `resolveClaudeBin()` and spawn the CLI directly. Fleet-wide over all 21 members the figures are **16** and **2** — the 13/15 pair is cron-scoped, and the register's §(a) was corrected at review after it presented these cron-scoped counts against a 21-module antecedent (15 + 3 = 18 ≠ 21) | "15 crons egress via the CLI" is correct; the *mechanism* was not. PA-31 is therefore scoped by an egress predicate, never by helper name. |
  | 17 modules import the substrate, 2 for types only | **20** modules carry a real import | 1 is type-only (`_cron-shared.ts`); 1 imports only workspace helpers and invokes no Claude (`cron-skill-freshness.ts`); `cron-workspace-gc.ts` names the substrate in a comment and is not an importer. |
  | 2 HTTP crons on `postAnthropicMessage` | **3** — `cron-compound-promote`, `cron-weekly-release-digest`, and `cron-anthropic-credit-probe` | The credit probe sends a `maxTokens: 1` literal `"ping"` and carries **nil personal data**. It is named anyway: the defect being corrected is non-exhaustive enumeration, so a nil-PII member is still enumerated. |

  **The `claude-code-action` entry is also
  mis-stated in the opposite direction:** only `claude-code-review.yml` is
  `disabled_manually`. `fix-constraints-stage-a.yml` uses the SAME
  `anthropics/claude-code-action` with `secrets.ANTHROPIC_API_KEY`, is workflow-state
  **active**, triggers on `pull_request`, and last ran 2026-07-29. It checks out the PR
  head SHA, so **contributor-authored source reaches Anthropic** on same-repo PRs (forks
  are excluded — no secrets, so the preflight skips). That is a live egress surface, not
  a dormant one. Several fleet members
  (`cron-legal-audit`, `cron-community-monitor`, `cron-daily-triage`,
  `cron-content-generator`, `cron-campaign-calendar`,
  `cron-competitive-analysis`, `cron-growth-*`) can route third-party or
  personal data to Anthropic. **Coverage is unaffected** — the DPA
  auto-incorporates via Commercial Terms § C and does not depend on this
  enumeration. ~~The Art. 30 framing for the fleet is not yet assessed to
  the PA-27 standard (which required an activity entry, a DPA scope
  amendment, an LIA and a DPIA screening for a *single* summarizer call).~~
  **[2026-07-31 RESOLVED (#7100).** All four artifacts the struck sentence
  called outstanding landed in this change: the activity entries (PA-31 /
  PA-32 / PA-33), the `register_activity_refs` frontmatter amendment above,
  the Art. 6(1)(f) LIA
  (`knowledge-base/legal/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md`)
  and the DPIA screening memo
  (`knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md`).
  Struck rather than deleted because the frontmatter now asserts the gap is
  closed, and a body still asserting the opposite is exactly the
  frontmatter-contradicts-body drift counsel review #7086 raised against this
  file. **]**
  **Retention:** the zero-retention amendment is `unsigned` (frontmatter), so the
  standard Anthropic 30-day retention window applies to ALL fleet egress described
  above — not only to the PA-27 surface it was previously reasoned about.
  Delivered by **#7100** (Art. 30 entries PA-31/32/33 + Art. 6(1)(f) LIA + Art. 14 assessment + DPIA
  screening, per the PA-27 precedent). Do not read this list as exhaustive.

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
- ~~Soleur takes on data subjects beyond the operator (cohort onboarding).~~ — **FIRED 2026-08-06.
  Actioned below.**
- Jikigai is engaged as processor by a further third-party controller (each new alpha tester).

## ⚠ Fired trigger — cohort onboarding, 2026-08-06 (#7331)

**The trigger fired and this section is the action, not a note to action it later.**

Alpha onboarding began 2026-08-06. On that date the operator ran Soleur agents on his own machine,
**under this Jikigai Anthropic key**, against an alpha tester's repository content, at the tester's
request. See
`knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md`.

### What changed about Anthropic's role

Until now every Jikigai-keyed activity in `register_activity_refs` had **Jikigai** (or the operator)
as the ultimate controller. PA-34 is the first where the ultimate controller is a **third party** —
the alpha tester. Anthropic is therefore Jikigai's **sub-processor** in a chain Jikigai does not
terminate, and Art. 28(2) applies: **the tester has neither authorised this sub-processor nor been
given notice of it.** Obtaining that authorisation, with notice of Anthropic's identity, US
location, and transfer mechanism, is condition C3 of the determination.

Note what this is **not**: an Art. 28(4) breach. Anthropic's own DPA auto-incorporates via
Commercial Terms §C and carries Art. 28(3) terms, DPF, SCCs Modules 2+3 and the IDTA. Art. 28(4)
requires the processor to bind its sub-processor to terms mirroring its own contract with the
controller — and there is **no controller contract yet to mirror**. The obligation is **inchoate,
not breached**. An earlier draft of this analysis claimed otherwise by conflating this snapshot memo
with Anthropic's actual DPA; that claim was overruled and is corrected here.

### The retention consequence — the operative fact

`zero_retention_amendment` is **`unsigned`**, so Anthropic's default **30-day retention window**
applies to everything egressing under this key. As of 2026-08-06 that window holds a **third
party's** content, not merely the operator's.

For the 2026-08-06 session the window expires approximately **2026-09-05**. That is a date to
record, not a deadline to chase — nothing needs doing when it passes; the Anthropic-side copy simply
lapses. Jikigai **cannot** accelerate deletion inside that window while the amendment is unsigned,
which is what makes an Art. 17 request from a downstream data subject only partly answerable today.

### Actions

| # | Action | Status |
|---|---|---|
| 1 | Record the fired trigger and its consequences here | **Done** (this section) |
| 2 | Behavioural control: no further Jikigai-keyed runs against tester content until an Art. 28(3) instrument exists — use the tester's machine and key, or do not run | **In force** — wired as a hard gate in `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md` |
| 3 | **Sign the Zero-Retention amendment, or use the tester's key.** Either removes the window entirely and is the cheapest of the remediations | **Open — operator action** |
| 4 | Confirm this account is on **Commercial** Terms, not Consumer Terms. The entire §C auto-incorporation analysis rests on it, and it has not been verified | **Open — operator action, and it is a premise not a formality** |
| 5 | Obtain tester sub-processor authorisation + notice (Art. 28(2)) | **Open** — carried in the tester-facing terms |

## Refs

- `knowledge-base/legal/article-30-register.md` — PA-22 entry + Vendor
  Mapping row.
- ADR-042 — Anthropic-SDK inside Inngest leader loop topology.
- ADR-041 — BYOK cap enforcement model.
- PR #4379 — PR-B Anthropic leader loop (PA-22 substrate).
