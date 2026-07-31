---
title: "Counsel review audit — PR #7086 (Anthropic scope-enumeration non-exhaustiveness correction: claude-eval Inngest cron fleet omitted from the Jikigai-keyed surface list)"
type: counsel-review
date: 2026-07-30
pr: 7086
changed_artifact:
  - knowledge-base/legal/data-processing-agreements/anthropic.md
  - knowledge-base/legal/compliance-posture.md
status: "DISCHARGED WITH ONE BLOCKING IN-PR CONDITION (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-07-30
signed_off_by: "clo agent (Soleur legal domain leader) — reviewing authority for v1 per the agent-native company model; external counsel re-review reserved for the re-evaluation triggers below"
brand_survival_threshold: single-user incident
re_evaluation_triggers: "Author the deferred Art. 30 PA for the claude-eval cron fleet BEFORE any of the following: the first arms-length (non-founder) user of the Soleur Web Platform; any fleet member being pointed at a repository, Discord guild, or social account other than jikig-ai/soleur and Jikigai's own properties; the PA-17 '#4558 first third-party-personal-data repository' trigger firing (cron-community-monitor's Discord/HN/GitHub-commenter population is already on the far side of it — see Finding 3); the Anthropic Zero-Retention amendment remaining unsigned 90 days from this date while the fleet continues to egress third-party content; any EEA-out transfer not covered by the disclosed DPF/SCCs; a fleet member gaining a write path to a public surface carrying third-party personal data beyond cron-daily-triage's existing gh issue comment."
---

# Counsel review audit — PR #7086 (Anthropic scope-enumeration correction)

> **STATUS: DISCHARGED — with one BLOCKING in-PR condition (C1) that must land
> before merge, plus three non-blocking conditions.**
> Reviewed and attested by the `clo` agent on 2026-07-30. The `clo` agent is the
> reviewing authority for the v1 Soleur-as-tenant-zero posture — this is an
> agent-native company; legal review is a CLO-agent function, not a task for the
> non-lawyer operator. The operator retains an optional veto; **external** counsel
> re-review is reserved for the frontmatter re-evaluation triggers.
> Every implementation-detail claim in the two amended records was cross-checked
> against the actual implementing TypeScript and workflow YAML. One claim was
> found **false** (Finding 4) — that is C1.

## Scope of the gate

The gate fired because the diff touches `knowledge-base/legal/` and the plan
declares `brand_survival_threshold: single-user incident`. The legal diff is
exactly two edits, both adding a disclaimer of non-exhaustiveness to an existing
enumeration rather than asserting a new legal position:

1. `knowledge-base/legal/data-processing-agreements/anthropic.md` — a dated bullet
   appended under "Activities in scope" recording that the "Pre-PR-B Jikigai-keyed
   surfaces" list was not exhaustive.
2. `knowledge-base/legal/compliance-posture.md` — a parenthetical on the Anthropic
   PBC vendor row's "Scope: Jikigai-keyed Anthropic API surface only" clause
   recording the same.

No DRAFT markers were added, so none are cleared. No T&C document is touched, so
no `TC_VERSION` bump is in scope. The expense/cost records in the same PR are
outside this review's remit.

## Finding 1 — the "coverage unaffected / framing unassessed" split is correct on Art. 28, and materially understated on Art. 30

**Art. 28 — no deficiency.** The claim that DPA coverage does not depend on either
enumeration is legally correct. The Art. 28(3) processor contract is the Anthropic
DPA auto-incorporated through Commercial Terms § C ("Data Privacy"), effective
2025-06-17, which binds at the account/Services level rather than per-workload; its
processing description is generic to Customer Data submitted to the Services. A
controller's internal inventory of which of its own workloads reach a processor is
not a condition of that contract's validity or scope. An incomplete internal list
therefore creates no Art. 28 gap. Art. 28(3)(a) documented instructions are
satisfied through the Terms; Art. 28(2) sub-processor authorisation runs off
Anthropic's published sub-processor list and is likewise unaffected.

**Art. 30 — a real gap, described too softly.** The record calls this a matter of
"framing … not yet assessed to the PA-27 standard". That understates it. Verified
against `knowledge-base/legal/article-30-register.md`: the register carries PA-1
through PA-30 and **no entry covers the claude-eval cron fleet at all**. PA-22 is
the BYOK leader-prompt runtime; PA-27 is the email-triage summarizer; neither
reaches the fleet. The register's own § 0 declares "Soleur GitHub repository
(`jikig-ai/soleur`)" an in-scope surface, so the fleet's processing is in-scope of
the register by its own terms and simply absent from it. That is a live Art. 30(1)
incompleteness, not a stylistic one.

**Why it nonetheless does not block.** The incompleteness exists on `main` today
and is not created by this PR — this PR introduces no processing and moves the
fleet from *unrecorded* to *recorded-as-unassessed*, which strictly improves the
register's accuracy. Art. 30(1) is a standing obligation without a merge-triggered
deadline; the supervisory remedy for an incomplete RoPA is a corrective order under
Art. 58(2)(d), not a per-commit gate. Blocking a PR that narrows the gap would
leave the record strictly worse. Tracked remediation is the proportionate response.

## Finding 2 — recording non-exhaustiveness is the right disposition; the PA must NOT be authored in this PR

Authoring a fleet PA to the PA-27 standard requires an Art. 30 activity entry,
data-subject and data-category enumeration, an Art. 6(1)(f) LIA, a retention
analysis that interacts with the unsigned Zero-Retention amendment, TOMs, and a
DPIA screening — across roughly seven heterogeneous data flows with materially
different data-subject populations (GitHub commenters, Discord members, Hacker News
posters, competitor-page subjects, marketing-content subjects). PA-27 consumed a
dedicated PR (#5103) for a **single** `messages.create` call. Fifteen crons is
strictly larger work.

Bolting that onto a cost-records-correction PR would produce a rushed LIA, and a
rushed balancing test is a **worse** compliance artifact than an honest
"not yet assessed" marker: Art. 5(2) accountability is served by an accurate record
of a known gap, not by a fabricated assessment that a supervisory authority would
later find unsupported. Scope discipline points the same way — this PR's subject is
cost records; the legal edits are incidental corrections discovered en route.

**Disposition: record + track. Do not author the PA here.**

## Finding 3 — YES, the named fleet members process third-party personal data, and the lawful-basis question is NOT covered by the Anthropic DPA row (this is the strongest finding, and the PR's prose understates it)

Verified in code, not taken on the PR author's summary:

- **`cron-community-monitor.ts`** (prompt constant `COMMUNITY_MONITOR_PROMPT`,
  collection steps 2 and 4): fetches Discord `guild-info` / `members` / `channels`
  and then **per-channel messages**; GitHub `contributors` and
  `fetch-interactions`; Hacker News `mentions` and `trending`; and new
  **stargazers (username plus starred date)**. The prompt then directs a
  `| User | Issue/PR | Comment |` table carrying "a snippet of their comment".
  All of that raw third-party content enters the model input under the Jikigai key.
  **Legally load-bearing distinction the record misses:** the prompt's
  minimization directives — "Summarize and aggregate — do not store raw message
  transcripts" and "Aggregate-only — never list individual followers, commenters,
  or likers" — constrain the **digest output**. They do not constrain the
  **Anthropic input**. The raw Discord messages and GitHub comment bodies are in
  the model's context regardless. Nothing in either amended record captures this.
- **`cron-daily-triage.ts`** (prompt constant `DAILY_TRIAGE_PROMPT`, steps 1 and
  3a): lists up to 200 open issues and runs `gh issue view <number>` on each,
  putting full third-party issue bodies and author handles into the model, then
  writes a public `gh issue comment` with the model's reasoning.
- Both spawn under `ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY`, with the
  ADR-033 **I2** invariant stated in each file header — "Operator
  `ANTHROPIC_API_KEY` only; never founder BYOK", build-time-enforced by
  `test/server/cron-no-byok-lease-sweep.test.ts`. Jikigai is therefore
  **controller** and Anthropic **processor**. This is *not* the BYOK
  independent-controller carve-out at register § 0 "Out-of-scope".

**The lawful-basis gap.** The Anthropic DPA row is a vendor/Art. 28 record; it
never supplies a lawful basis. A lawful basis is a controller-side Art. 6
determination that lives in the Art. 30 PA — and there is no PA for the fleet.
There is consequently **no Art. 6 basis of record** for transmitting a Discord
member's message or a Hacker News poster's content to a US processor.

Worse, the nearest analogue expressly fences this exact case. **PA-17**'s balancing
test carries a **"first third-party-personal-data repository" re-evaluation
trigger**, recorded in the #4558 counsel-review audit, which re-opens the balancing
where the data belongs to natural persons who are neither the Workspace Owner nor a
Co-Member. `cron-community-monitor`'s Discord / HN / GitHub-commenter population is
precisely that population. The fleet therefore does not merely lack a basis — it
sits on the far side of a re-evaluation trigger Jikigai has already committed to
honour. **Art. 14** (indirect collection) engages for those same subjects and is
likewise unaddressed.

This is answered YES, and more strongly than the PR's prose conveys. It is captured
as re-evaluation triggers in this audit's frontmatter and as condition C2.

## Finding 4 — BLOCKING: the record states a live Anthropic surface is dead

The amended `anthropic.md` bullet asserts:

> while `claude-code-action` — named first — is `disabled_manually` and emits nothing.

**This is false.** Verified against workflow state and source:

- Only `.github/workflows/claude-code-review.yml` ("Claude Code Review") is
  `disabled_manually`.
- `.github/workflows/fix-constraints-stage-a.yml` is workflow-state **`active`**,
  triggers on `pull_request` (`opened`/`synchronize`/`reopened`), and at its
  "Dispatch agent to fix the gate (fix-only)" step uses
  `anthropics/claude-code-action@5aa6f47e977fec3321f32c06d8076b1f503f832c` (v1.0.161)
  with `anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}` — the Jikigai key —
  gated only on `steps.gate.outputs.rc != '0' && steps.preflight.outputs.ok == 'true'`.
- `gh run list` shows successful runs as recently as **2026-07-29**, one day before
  the record was written.
- `fix-constraints-stage-b` and `test-pretooluse-hooks` are also `active`.

The processing is non-trivial: the action checks out the **PR head SHA** and the
agent reads and edits that tree, so contributor-authored source and PR metadata
reach Anthropic. Fork PRs receive no secrets, so the preflight fails and the agent
step is skipped — that bounds the exposure to same-repo branches, but does not
eliminate third-party content.

**Why this blocks where the Art. 30 gap does not.** The Art. 30 gap pre-exists this
PR; this false statement is **introduced by** it, into the very records a
supervisory authority would read to establish scope. A record that marks a live
processing surface as emitting nothing is worse than the original omission, because
it affirmatively invites a reader to exclude that surface. The remedy is one
sentence. Correcting it is C1.

## Finding 5 — "Tracked for that assessment" is unsupported

The `anthropic.md` bullet closes "Tracked for that assessment". Verified via
`gh issue list` across open and closed states: **no issue exists** referencing
#7086 or a fleet Art. 30 assessment. As written the sentence is an unfalsifiable
commitment, and it is the load-bearing half of the "record + track" disposition
this audit approves under Finding 2. Without a tracker, "record + track" degrades
to "record and forget". This is C2.

## Finding 6 — two secondary defects (non-blocking)

- **Zero-retention interaction is unstated for the fleet.** The same file's
  frontmatter carries `zero_retention_amendment: unsigned`, and its
  "Zero-Retention amendment" section explains that Anthropic's default **30-day**
  API request/response retention applies until signed. That window applies to
  **every** Jikigai-keyed call, so Discord message content and GitHub comment
  bodies now rest at a US processor for 30 days. The record notes the 30-day
  window for PA-27 only. A reader of the corrected bullet should see it applies to
  the fleet too. This is C3.
- **Frontmatter contradicts the new body text.** `role:` still reads "independent
  controller/processor under operator BYOK; processor for the Jikigai-keyed
  email-triage summarizer (PA-27)" and `register_activity_refs: [PA-22, PA-27]`.
  Both now understate the file's own contents. The frontmatter is the
  machine-readable index used by `kb-search` facet queries, so the drift is not
  cosmetic. This is C4.

## Claims verified as ACCURATE

Recorded so a later reader knows these were checked, not assumed:

- **"15 crons on `_cron-claude-eval-substrate`"** — exact. Precisely 15 `cron-*.ts`
  files call `spawnClaudeEval`: `agent-native-audit`, `architecture-diagram-sync`,
  `bug-fixer`, `campaign-calendar`, `community-monitor`, `competitive-analysis`,
  `content-generator`, `daily-triage`, `follow-through-monitor`, `growth-audit`,
  `growth-execution`, `legal-audit`, `roadmap-review`, `seo-aeo-audit`, `ux-audit`.
  Seventeen `cron-*.ts` files import the module; two do so for types/constants only.
- **"plus `cron-compound-promote` and `cron-weekly-release-digest` over HTTP"** —
  correct. Both call `postAnthropicMessage` (direct Messages API), not the CLI
  substrate; `cron-compound-promote.ts` states invariant "I4 — N/A (no claude
  binary; pure TS + Anthropic fetch)".
- **All seven named fleet members exist** and are members of the 15:
  `cron-legal-audit`, `cron-community-monitor`, `cron-daily-triage`,
  `cron-content-generator`, `cron-campaign-calendar`, `cron-competitive-analysis`,
  and `cron-growth-*` (`growth-audit` + `growth-execution`).
- **"the *dominant* Jikigai-keyed Anthropic surface"** — supported: 15 CLI crons
  plus 2 HTTP crons against 1 CI action and 1 summarizer.
- **"can route third-party or personal data to Anthropic"** — correct, and
  understated per Finding 3.

## Conditions

| # | Condition | Blocking? |
|---|---|---|
| **C1** | Correct the false `claude-code-action` claim in `anthropic.md` (and re-check the mirrored parenthetical in `compliance-posture.md`). `claude-code-action` is **live** via `fix-constraints-stage-a.yml` under the Jikigai `ANTHROPIC_API_KEY`, last successful run 2026-07-29; only `claude-code-review.yml` is `disabled_manually`. State that the action processes the PR head-SHA tree, and that fork PRs are excluded because they receive no secrets. | **YES — must land before merge** |
| **C2** | Replace "Tracked for that assessment" with a real GitHub issue reference. Open an issue for the fleet Art. 30 PA (activity entry + Art. 6(1)(f) LIA + Art. 14 analysis + DPIA screening, to the PA-27 standard), label it `domain/legal` + `priority/p2`, cite the PA-17 / #4558 "first third-party-personal-data repository" trigger as the reason the balancing is already re-opened, and cite its number in both amended records. | No — but C1 and C2 should land together; the disposition in Finding 2 depends on C2 existing |
| **C3** | Add one clause noting that Anthropic's default 30-day request/response retention (`zero_retention_amendment: unsigned`) applies to the fleet's egress, not only to PA-27. | No |
| **C4** | Update `anthropic.md` frontmatter `role:` and `register_activity_refs:` so the machine-readable index does not contradict the new body text. | No |

## Attestation

The `clo` agent has reviewed both amended artifacts against the implementing
TypeScript (`_cron-claude-eval-substrate.ts`, `cron-daily-triage.ts`,
`cron-community-monitor.ts`, `cron-compound-promote.ts`,
`cron-weekly-release-digest.ts`), the workflow YAML
(`fix-constraints-stage-a.yml`, `claude-code-review.yml`), live workflow state via
`gh workflow list` and `gh run list`, and the Art. 30 register, and

**DISCHARGES** the Counsel-Review CLO-Attestation gate for PR #7086, conditioned on
**C1 landing in this PR before merge**. C2–C4 are recorded as non-blocking.

Per-artifact verdict:

| Artifact | Verdict |
|---|---|
| `knowledge-base/legal/data-processing-agreements/anthropic.md` | **APPROVED subject to C1** (C2/C3/C4 non-blocking) |
| `knowledge-base/legal/compliance-posture.md` | **APPROVED subject to C1** (re-check the mirrored parenthetical) |

This attestation is the v1 **internal** sign-off. All output remains draft material;
**external** counsel re-review is reserved for the frontmatter re-evaluation
triggers — most immediately the first arms-length user and the PA-17 / #4558
third-party-personal-data trigger, which Finding 3 assesses as already engaged.
